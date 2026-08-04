# 角色產生器（Blender headless）：
#   blender -b -P godot/assets/blender/make_chars.py -- godot/assets/models
#
# 為什麼是 Q 版：用程式雕寫實人體會翻車 —— 臉的比例差 3% 就恐怖谷，
# 手指、衣褶、頭髮用 Python 寫座標又沒有即時回饋。Q 版（約 3.8 頭身）
# 容錯高得多，而且走路動畫好做。這是「先做 Q 版中階給我看」那一輪的產物。
#
# ── 兩個約定 ──
# 1. **朝向軸 +X**：跟 duck/heron/koi 一致（詞彙表 FacingAxis）。
# 2. **不綁骨架**：各部位是**獨立物件**，樞紐（origin）擺在關節上，
#    走路動畫在 GDScript 裡轉節點就好。Q 版四肢是硬管，蒙皮沒有意義，
#    而且省掉「產生器要輸出動畫資料」這條管線。
#
# 產出：villager_a（女・和服・髷）／villager_b（男・作務衣）／villager_c（童）
import bpy
import bmesh
import math
import sys
import os

OUT_DIR = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "godot/assets/models"
os.makedirs(OUT_DIR, exist_ok=True)
TAU = math.pi * 2


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


# ── 幾何小工具（局部座標，Blender Z-up）────────────────────────────────

def sphere(cx, cy, cz, r, sx=1.0, sy=1.0, sz=1.0, seg=16, rings=10, z_from=-1.0):
    """經緯球。z_from 可以把球切一半（頭髮的帽狀用）。"""
    verts, faces = [], []
    r0 = max(0, int((z_from + 1.0) * 0.5 * rings))
    rows = list(range(r0, rings + 1))
    for ri in rows:
        phi = math.pi * ri / rings
        zz = math.cos(phi)
        rr = math.sin(phi)
        for si in range(seg):
            a = TAU * si / seg
            verts.append((cx + math.cos(a) * rr * r * sx,
                          cy + math.sin(a) * rr * r * sy,
                          cz + zz * r * sz))
    nrow = len(rows)
    for i in range(nrow - 1):
        for s in range(seg):
            s2 = (s + 1) % seg
            a = i * seg + s
            b = i * seg + s2
            c = (i + 1) * seg + s2
            d = (i + 1) * seg + s
            faces.append((a, b, c, d))
    return verts, faces


def hair_shell(cx, cy, cz, r, sx, sy, sz, front, back, seg=18, rings=14):
    """頭髮：整顆球算出來，再依**髮際線**裁面。

    front / back 是髮際線高度（相對 r 的倍數）：正面高（露出額頭與眼睛）、
    背面低（後髮蓋到後頸）。用堆球體去拼瀏海拼不出來 —— v1 拼出一張被
    白邊框住的面具，v2 拼出橫在臉上的黑色布條。改成一顆球裁一次乾淨得多。
    """
    verts, faces = [], []
    for ri in range(rings + 1):
        phi = math.pi * ri / rings
        zz = math.cos(phi)
        rr = math.sin(phi)
        for si in range(seg):
            a = TAU * si / seg
            verts.append((cx + math.cos(a) * rr * r * sx,
                          cy + math.sin(a) * rr * r * sy,
                          cz + zz * r * sz))
    for i in range(rings):
        for si in range(seg):
            s2 = (si + 1) % seg
            quad = (i * seg + si, i * seg + s2, (i + 1) * seg + s2, (i + 1) * seg + si)
            fx = sum(verts[k][0] for k in quad) / 4.0 - cx
            fz = sum(verts[k][2] for k in quad) / 4.0 - cz
            # 臉朝 +X：t=1 是正面、t=0 是背面
            t = (fx / (r * sx) + 1.0) * 0.5
            if fz > (back + (front - back) * t) * r:
                faces.append(quad)
    return verts, faces


def tube(path_pts, radii, squash=None, sides=10, cap=True):
    """沿 Z 主軸的錐管（軀幹、四肢）。squash 是每節點的 (x,y) 比例。"""
    verts, faces = [], []
    n = len(path_pts)
    for i, p in enumerate(path_pts):
        sx, sy = squash[i] if squash else (1.0, 1.0)
        for s in range(sides):
            a = TAU * s / sides
            verts.append((p[0] + math.cos(a) * radii[i] * sx,
                          p[1] + math.sin(a) * radii[i] * sy,
                          p[2]))
    for i in range(n - 1):
        for s in range(sides):
            s2 = (s + 1) % sides
            faces.append((i * sides + s, i * sides + s2,
                          (i + 1) * sides + s2, (i + 1) * sides + s))
    if cap:
        faces.append(tuple(range(sides - 1, -1, -1)))
        base = (n - 1) * sides
        faces.append(tuple(range(base, base + sides)))
    return verts, faces


def box(cx, cy, cz, sx, sy, sz):
    v = [(cx + dx * sx / 2, cy + dy * sy / 2, cz + dz * sz / 2)
         for dx, dy, dz in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
                            (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def merge(*parts):
    """把 (verts, faces, color) 三元組疊起來，回傳 verts / faces / 每面顏色"""
    verts, faces, cols = [], [], []
    for pv, pf, col in parts:
        off = len(verts)
        verts.extend(pv)
        for f in pf:
            faces.append(tuple(i + off for i in f))
            cols.append(col)
    return verts, faces, cols


def make_object(name, verts, faces, face_cols, smooth=True, loc=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    attr = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    for pi, poly in enumerate(me.polygons):
        r, g, b = face_cols[pi]
        for li in poly.loop_indices:
            attr.data[li].color = (r, g, b, 1.0)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    # 法線重算朝外：手寫球面／管面的繞序不保證正確，錯了會看到內壁
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob.location = loc
    return ob


def export_parts(objs, name):
    """不 join —— 各部位要保持獨立物件，GDScript 才轉得動關節。"""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_yup=True, export_apply=False)
    print("exported", path, "parts=", len(objs))


# ── 配色 ────────────────────────────────────────────────────────────────
SKIN = (0.82, 0.63, 0.50)   # 壓深過 —— 太亮會在陽光下糊成一顆白球
EYE = (0.13, 0.11, 0.13)
BROW = (0.24, 0.17, 0.13)
MOUTH = (0.72, 0.42, 0.40)
SOLE = (0.30, 0.24, 0.20)
TABI = (0.88, 0.87, 0.82)

PALETTES = {
    # 女・和服：藍染上衣、赤茶的帶
    "villager_a": dict(hair=(0.14, 0.10, 0.09), top=(0.26, 0.33, 0.46),
                       skirt=(0.20, 0.26, 0.38), obi=(0.62, 0.34, 0.24),
                       trim=(0.86, 0.84, 0.78), bun=True, tall=1.0),
    # 男・作務衣：藍鼠上衣、深褲
    "villager_b": dict(hair=(0.11, 0.09, 0.08), top=(0.34, 0.36, 0.36),
                       skirt=(0.24, 0.23, 0.24), obi=(0.30, 0.25, 0.20),
                       trim=(0.72, 0.70, 0.64), bun=False, tall=1.06),
    # 童：柿色の着物
    "villager_c": dict(hair=(0.17, 0.12, 0.09), top=(0.70, 0.44, 0.24),
                       skirt=(0.58, 0.36, 0.20), obi=(0.30, 0.40, 0.34),
                       trim=(0.90, 0.86, 0.76), bun=False, tall=0.72),
}


# ══════════════════════════════════════════════ 村民 ═══════════════════
def make_villager(name):
    """約 3.8 頭身。各部位獨立，origin 放在關節上：
         Body   骨盤（0,0,hip）      —— 全身的根，走路時上下起伏
         Head   頸（0,0,neck）
         ArmL/R 肩
         LegL/R 股関節
    """
    clear()
    p = PALETTES[name]
    T = p["tall"]
    HEAD_R = 0.175 * (1.0 if T >= 1.0 else 0.92)   # 小孩頭沒有等比例縮小
    hip = 0.46 * T                                  # 骨盤高度（地面到股関節）
    torso = 0.40 * T                                # 骨盤到肩
    neck = hip + torso
    shoulder_w = 0.145 * T

    parts = []

    # ── 軀幹（含和服的裾張り與帶）──
    # 局部座標以骨盤為原點：z 從 0（腰）往上到 torso（肩）、往下到裙擺
    prof_z = [-hip * 0.86, -hip * 0.45, -0.02, 0.10, 0.22, torso * 0.72, torso, torso + 0.035]
    prof_r = [0.150, 0.140, 0.121, 0.118, 0.124, 0.140, 0.146, 0.120]
    prof_sq = [(1.0, 0.72), (1.0, 0.70), (1.0, 0.66), (1.0, 0.66),
               (1.0, 0.68), (1.0, 0.70), (1.0, 0.72), (1.0, 0.72)]
    body_v, body_f = tube([(0, 0, z) for z in prof_z], prof_r, prof_sq, sides=14)
    # 上下分色：腰帶以上是上衣、以下是裙／褲
    body_cols = []
    for f in body_f:
        zc = sum(body_v[i][2] for i in f) / len(f)
        body_cols.append(p["top"] if zc > 0.06 else p["skirt"])
    body_parts = [(body_v, body_f, None)]

    # 帶（腰帶）
    obi_v, obi_f = tube([(0, 0, 0.02), (0, 0, 0.115)], [0.128, 0.128],
                        [(1.0, 0.70), (1.0, 0.70)], sides=14, cap=False)
    # 襟（前面的 V 字合わせ）
    lap_v, lap_f = box(0.085, 0.0, 0.30 * T + 0.02, 0.03, 0.075, 0.30 * T)

    verts, faces, cols = [], [], []
    for pv, pf, col in [(body_v, body_f, None), (obi_v, obi_f, p["obi"]), (lap_v, lap_f, p["trim"])]:
        off = len(verts)
        verts.extend(pv)
        for fi, f in enumerate(pf):
            faces.append(tuple(i + off for i in f))
            if col is None:
                cols.append(body_cols[fi])
            else:
                cols.append(col)
    parts.append(make_object("Body", verts, faces, cols, loc=(0, 0, hip)))

    # ── 頭（含髮、眼、眉、口）──
    # 局部原點在頸；頭心在 z = HEAD_R*0.95
    hz = HEAD_R * 0.95
    head_v, head_f = sphere(0, 0, hz, HEAD_R, 1.0, 0.94, 1.02, seg=18, rings=12)
    # 頭髮：一顆球裁一次。正面髮際線在眼睛上方，背面蓋到後頸。
    hair_v, hair_f = hair_shell(0, 0, hz, HEAD_R * 1.055, 1.0, 0.98, 1.05,
                                front=0.32, back=-0.92, seg=20, rings=16)
    head_parts = [(head_v, head_f, SKIN), (hair_v, hair_f, p["hair"])]
    if p["bun"]:      # 髷（後ろで結った團子）
        bun_v, bun_f = sphere(-HEAD_R * 0.72, 0, hz + HEAD_R * 0.52, HEAD_R * 0.40,
                              seg=12, rings=8)
        head_parts.append((bun_v, bun_f, p["hair"]))
        pin_v, pin_f = box(-HEAD_R * 0.72, 0, hz + HEAD_R * 0.52, 0.012, 0.13, 0.012)
        head_parts.append((pin_v, pin_f, p["trim"]))
    # 眼：臉朝 +X，兩眼在 y = ±
    # 五官要**貼在臉的表面上**，不能照直覺擺在「臉前面一點」。
    # 頭是 x 半徑 = HEAD_R 的橢球，眼睛的高度與左右偏移一代進去，
    # 臉皮其實只在 x ≈ 0.92·HEAD_R —— v2/v3 把眼睛放在 0.70~0.72，
    # 整組五官埋在頭裡面，遠看是一張沒有臉的臉。
    def face_x(y_off, z_off, bulge):
        q = 1.0 - (y_off / 0.94) ** 2 - (z_off / 1.02) ** 2
        return HEAD_R * (math.sqrt(max(q, 0.04)) + bulge)

    for sy in (-1, 1):
        eyo = 0.34
        eze = -0.04
        ev, ef = sphere(face_x(eyo, eze, -0.02), sy * HEAD_R * eyo, hz + HEAD_R * eze,
                        HEAD_R * 0.26, 0.24, 0.62, 1.10, seg=12, rings=8)
        head_parts.append((ev, ef, EYE))
        hv, hf = sphere(face_x(eyo * 0.92, 0.05, 0.015), sy * HEAD_R * eyo * 0.92,
                        hz + HEAD_R * 0.05, HEAD_R * 0.070, 0.22, 0.9, 1.0, seg=8, rings=6)
        head_parts.append((hv, hf, (0.99, 0.99, 0.99)))
        # 眉離眼睛遠一點，貼太近會連成一條黑線
        bz = 0.21
        bv, bf = box(face_x(eyo, bz, 0.0), sy * HEAD_R * eyo, hz + HEAD_R * bz,
                     0.010, HEAD_R * 0.28, 0.013)
        head_parts.append((bv, bf, BROW))
    mv, mf = sphere(face_x(0.0, -0.40, -0.01), 0, hz - HEAD_R * 0.40, HEAD_R * 0.14,
                    0.22, 1.10, 0.34, seg=10, rings=6)
    head_parts.append((mv, mf, MOUTH))
    v, f, c = merge(*head_parts)
    parts.append(make_object("Head", v, f, c, loc=(0, 0, neck)))

    # ── 腕（袖 + 手）──origin 在肩
    for side, sname in ((1, "ArmL"), (-1, "ArmR")):
        arm_len = 0.30 * T
        sleeve_v, sleeve_f = tube(
            [(0, 0, 0.01), (0, 0, -arm_len * 0.30), (0, 0, -arm_len * 0.58)],
            [0.052, 0.062, 0.050], [(1.0, 0.95)] * 3, sides=8)
        fore_v, fore_f = tube(
            [(0, 0, -arm_len * 0.56), (0, 0, -arm_len * 0.95)],
            [0.036, 0.031], sides=8)
        hand_v, hand_f = sphere(0, 0, -arm_len - 0.012, 0.040, 0.9, 0.75, 1.05,
                                seg=10, rings=7)
        v, f, c = merge((sleeve_v, sleeve_f, p["top"]),
                        (fore_v, fore_f, SKIN), (hand_v, hand_f, SKIN))
        parts.append(make_object(sname, v, f, c,
                                 loc=(0, side * shoulder_w, neck - 0.045)))

    # ── 脚（腳 + 足袋 + 草履）──origin 在股関節
    for side, lname in ((1, "LegL"), (-1, "LegR")):
        leg_len = hip - 0.045
        leg_v, leg_f = tube([(0, 0, 0), (0, 0, -leg_len * 0.55), (0, 0, -leg_len)],
                            [0.055, 0.046, 0.038], sides=8)
        foot_v, foot_f = box(0.024, 0, -leg_len - 0.028, 0.115, 0.070, 0.052)
        sole_v, sole_f = box(0.024, 0, -leg_len - 0.056, 0.130, 0.080, 0.018)
        v, f, c = merge((leg_v, leg_f, p["skirt"] if name == "villager_b" else SKIN),
                        (foot_v, foot_f, TABI), (sole_v, sole_f, SOLE))
        parts.append(make_object(lname, v, f, c, loc=(0, side * 0.058, hip)))

    export_parts(parts, name)


for key in PALETTES:
    make_villager(key)
print("done")
