# 場景資產產生器（Blender headless）：
#   blender -b -P godot/assets/blender/make_props.py -- godot/assets/models
#
# 為什麼要有這支：產生器裡只有 box / cylinder，沒有任何曲面 ——
# 龍、鴨、鯉、岩石這種有機造型用方塊堆一定看起來像方塊堆
# （使用者：「怎麼材質只有這種岩石做成龍?」）。有機造型一律在這裡雕。
#
# 產出：dragon_statue / duck / heron / koi / rock_a~d
import bpy
import bmesh
import math
import random
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


def mesh_from(name, verts, faces, color_fn=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if color_fn:
        attr = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        for poly in me.polygons:
            for li in poly.loop_indices:
                v = me.vertices[me.loops[li].vertex_index]
                r, g, b = color_fn(v.co, poly.normal)
                attr.data[li].color = (r, g, b, 1.0)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    return ob


def export(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_yup=True, export_apply=True)
    print("exported", path)


# ── 掃掠管：沿路徑拉出有錐度的圓管（龍身、鯉魚身體都用這個） ──
def sweep(path_pts, radii, sides=8, close_start=True, close_end=True, squash=None):
    """path_pts: [(x,y,z)]；radii: 每個節點的半徑；squash: 每節點 (寬,高) 比例"""
    verts, faces = [], []
    n = len(path_pts)
    for i, p in enumerate(path_pts):
        # 切線
        a = path_pts[max(i - 1, 0)]
        b = path_pts[min(i + 1, n - 1)]
        t = [b[k] - a[k] for k in range(3)]
        tl = math.sqrt(sum(c * c for c in t)) or 1.0
        t = [c / tl for c in t]
        # 任取一個不平行的向量做正交基
        up = (0.0, 1.0, 0.0) if abs(t[1]) < 0.9 else (1.0, 0.0, 0.0)
        u = [t[1] * up[2] - t[2] * up[1], t[2] * up[0] - t[0] * up[2], t[0] * up[1] - t[1] * up[0]]
        ul = math.sqrt(sum(c * c for c in u)) or 1.0
        u = [c / ul for c in u]
        v = [t[1] * u[2] - t[2] * u[1], t[2] * u[0] - t[0] * u[2], t[0] * u[1] - t[1] * u[0]]
        sw, sh = squash[i] if squash else (1.0, 1.0)
        for s in range(sides):
            ang = s / sides * TAU
            cu = math.cos(ang) * radii[i] * sw
            cv = math.sin(ang) * radii[i] * sh
            verts.append((p[0] + u[0] * cu + v[0] * cv,
                          p[1] + u[1] * cu + v[1] * cv,
                          p[2] + u[2] * cu + v[2] * cv))
    for i in range(n - 1):
        for s in range(sides):
            s2 = (s + 1) % sides
            a = i * sides + s
            b = i * sides + s2
            c = (i + 1) * sides + s2
            d = (i + 1) * sides + s
            faces.append((a, b, c, d))
    if close_start:
        faces.append(tuple(range(sides - 1, -1, -1)))
    if close_end:
        base = (n - 1) * sides
        faces.append(tuple(range(base, base + sides)))
    return verts, faces


def box_verts(cx, cy, cz, sx, sy, sz):
    v = [(cx + dx * sx / 2, cy + dy * sy / 2, cz + dz * sz / 2)
         for dx, dy, dz in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
                            (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def merge(*parts):
    verts, faces = [], []
    for pv, pf in parts:
        off = len(verts)
        verts.extend(pv)
        faces.extend([tuple(i + off for i in f) for f in pf])
    return verts, faces


# ══════════════════════════════════════════════ 龍神像 ══════════════════
def make_dragon():
    clear()
    STONE = (0.62, 0.62, 0.60)
    # 龍身：盤繞石柱兩圈半的螺旋，由粗到細
    N = 90
    path, radii, squash = [], [], []
    for i in range(N):
        t = i / (N - 1)
        ang = -t * TAU * 2.35 + 1.2
        rad = 0.80 - t * 0.10
        y = 1.55 + t * 5.0
        # 尾端往外甩、頭端往上探
        if t > 0.9:
            rad += (t - 0.9) * 3.0
            y += (t - 0.9) * 1.6
        path.append((math.cos(ang) * rad, math.sin(ang) * rad, y))
        # 頸細、腹粗、尾尖
        prof = 0.30 * (0.55 + 0.95 * math.sin(min(t * 1.15, 1.0) * math.pi) ** 0.6)
        radii.append(max(prof, 0.055))
        squash.append((1.15, 0.86))          # 龍身略扁
    body = sweep(path, radii, sides=10, squash=squash)

    parts = [body]
    # 背鰭（沿背脊的三角鬃）
    for i in range(6, N - 8, 4):
        t = i / (N - 1)
        p = path[i]
        h = 0.30 * (1.0 - t * 0.5)
        fin = ([(p[0], p[1], p[2] + radii[i] * 0.7),
                (p[0] + 0.16, p[1], p[2] + radii[i] * 0.7),
                (p[0] + 0.05, p[1] + 0.04, p[2] + radii[i] + h),
                (p[0], p[1] + 0.14, p[2] + radii[i] * 0.7)],
               [(0, 1, 2), (1, 3, 2), (3, 0, 2), (0, 3, 1)])
        parts.append(fin)
    # 四肢：從身體伸出的短腿 + 三爪
    for li, i in enumerate([18, 34, 52, 68]):
        p = path[i]
        ang = math.atan2(p[1], p[0])
        out = (math.cos(ang), math.sin(ang))
        knee = (p[0] + out[0] * 0.42, p[1] + out[1] * 0.42, p[2] - 0.34)
        foot = (p[0] + out[0] * 0.62, p[1] + out[1] * 0.62, p[2] - 0.72)
        leg = sweep([p, knee, foot], [0.15, 0.12, 0.09], sides=6)
        parts.append(leg)
        for c in range(3):
            ca = ang + (c - 1) * 0.5
            tip = (foot[0] + math.cos(ca) * 0.24, foot[1] + math.sin(ca) * 0.24, foot[2] - 0.1)
            parts.append(sweep([foot, tip], [0.055, 0.012], sides=4))
    # 龍首：吻部 + 顎 + 角 + 鬚 + 眼
    hp = path[-1]
    hang = math.atan2(hp[1], hp[0]) + 1.2
    fwd = (math.cos(hang), math.sin(hang))
    skull = box_verts(hp[0], hp[1], hp[2] + 0.1, 0.52, 0.46, 0.40)
    parts.append(skull)
    snout_a = (hp[0], hp[1], hp[2] + 0.08)
    snout_b = (hp[0] + fwd[0] * 0.62, hp[1] + fwd[1] * 0.62, hp[2] + 0.18)
    parts.append(sweep([snout_a, snout_b], [0.22, 0.15], sides=6))
    jaw_b = (hp[0] + fwd[0] * 0.52, hp[1] + fwd[1] * 0.52, hp[2] - 0.16)
    parts.append(sweep([(hp[0], hp[1], hp[2] - 0.06), jaw_b], [0.17, 0.10], sides=6))
    for s in (-1, 1):
        side = (-fwd[1] * s, fwd[0] * s)
        hb = (hp[0] + side[0] * 0.18 - fwd[0] * 0.2, hp[1] + side[1] * 0.18 - fwd[1] * 0.2, hp[2] + 0.28)
        ht = (hb[0] + side[0] * 0.22 - fwd[0] * 0.4, hb[1] + side[1] * 0.22 - fwd[1] * 0.4, hb[2] + 0.62)
        parts.append(sweep([hb, ht], [0.075, 0.022], sides=5))        # 角
        wb = (hp[0] + fwd[0] * 0.5 + side[0] * 0.16, hp[1] + fwd[1] * 0.5 + side[1] * 0.16, hp[2] + 0.1)
        wt = (wb[0] + fwd[0] * 0.55 + side[0] * 0.4, wb[1] + fwd[1] * 0.55 + side[1] * 0.4, wb[2] + 0.35)
        parts.append(sweep([wb, wt], [0.035, 0.012], sides=4))        # 鬚
        eb = (hp[0] + fwd[0] * 0.18 + side[0] * 0.21, hp[1] + fwd[1] * 0.18 + side[1] * 0.21, hp[2] + 0.24)
        parts.append(sweep([eb, (eb[0] + side[0] * 0.06, eb[1] + side[1] * 0.06, eb[2])], [0.1, 0.07], sides=6))
    # 龍珠（爪中抱的寶珠）
    fp = path[52]
    ball_c = (fp[0] * 1.7, fp[1] * 1.7, fp[2] - 0.75)
    bs = []
    bf = []
    rings = 6
    for ri in range(rings + 1):
        pa = ri / rings * math.pi
        for si in range(10):
            sa = si / 10 * TAU
            bs.append((ball_c[0] + math.sin(pa) * math.cos(sa) * 0.28,
                       ball_c[1] + math.sin(pa) * math.sin(sa) * 0.28,
                       ball_c[2] + math.cos(pa) * 0.28))
    for ri in range(rings):
        for si in range(10):
            s2 = (si + 1) % 10
            bf.append((ri * 10 + si, ri * 10 + s2, (ri + 1) * 10 + s2, (ri + 1) * 10 + si))
    parts.append((bs, bf))
    # 石柱與基壇
    parts.append(sweep([(0, 0, 1.3), (0, 0, 6.4)], [0.46, 0.36], sides=12))
    for i, (w, h0, h1) in enumerate([(2.9, 0.0, 0.52), (2.35, 0.52, 0.98), (1.85, 0.98, 1.34)]):
        parts.append(box_verts(0, 0, (h0 + h1) / 2, w, w, h1 - h0))

    verts, faces = merge(*parts)
    ob = mesh_from("dragon_statue", verts, faces, lambda co, n: STONE)
    export([ob], "dragon_statue")


# ══════════════════════════════════════════════ 水鳥與魚 ════════════════
def make_duck():
    clear()
    BODY = (0.30, 0.28, 0.26)
    HEAD = (0.10, 0.34, 0.22)
    parts_body = [sweep([(-0.26, 0, 0.02), (-0.05, 0, 0.06), (0.16, 0, 0.05), (0.30, 0, 0.10)],
                        [0.055, 0.135, 0.12, 0.05], sides=8, squash=[(1.0, 0.85)] * 4)]
    v1, f1 = merge(*parts_body)
    body = mesh_from("duck_body", v1, f1, lambda co, n: BODY)
    parts_head = [
        sweep([(0.22, 0, 0.13), (0.26, 0, 0.24)], [0.05, 0.075], sides=6),   # 頸
        sweep([(0.26, 0, 0.25), (0.33, 0, 0.27)], [0.08, 0.06], sides=8),    # 頭
        sweep([(0.34, 0, 0.26), (0.44, 0, 0.245)], [0.045, 0.03], sides=5),  # 喙
    ]
    v2, f2 = merge(*parts_head)
    head = mesh_from("duck_head", v2, f2, lambda co, n: HEAD if co.x < 0.34 else (0.62, 0.52, 0.18))
    export([body, head], "duck")


def make_heron():
    clear()
    W = (0.86, 0.86, 0.84)
    parts = [
        sweep([(-0.22, 0, 0.52), (0.0, 0, 0.60), (0.16, 0, 0.55)], [0.06, 0.115, 0.07], sides=8),  # 身
        sweep([(0.12, 0, 0.60), (0.20, 0, 0.80), (0.16, 0, 0.96)], [0.045, 0.035, 0.04], sides=6), # S 頸
        sweep([(0.16, 0, 0.96), (0.24, 0, 1.00)], [0.05, 0.038], sides=6),                          # 頭
        sweep([(0.24, 0, 1.0), (0.46, 0, 0.965)], [0.028, 0.008], sides=4),                         # 長喙
        sweep([(-0.02, 0.05, 0.50), (-0.01, 0.05, 0.20), (0.03, 0.05, 0.0)], [0.028, 0.022, 0.02], sides=5),
        sweep([(-0.02, -0.05, 0.50), (-0.01, -0.05, 0.20), (0.03, -0.05, 0.0)], [0.028, 0.022, 0.02], sides=5),
        sweep([(-0.30, 0, 0.50), (-0.16, 0, 0.56)], [0.02, 0.07], sides=6),                         # 尾羽
    ]
    v, f = merge(*parts)
    ob = mesh_from("heron", v, f, lambda co, n: (0.55, 0.45, 0.16) if co.x > 0.26 and co.z > 0.9 else W)
    export([ob], "heron")


def make_koi():
    clear()
    N = 12
    path, radii, sq = [], [], []
    for i in range(N):
        t = i / (N - 1)
        path.append((-0.30 + t * 0.62, 0, 0.0))
        radii.append(0.115 * math.sin(min(t * 1.05 + 0.06, 1.0) * math.pi) ** 0.5 + 0.012)
        sq.append((0.62, 1.25))                     # 側扁
    parts = [sweep(path, radii, sides=8, squash=sq)]
    tail = ([(0.31, 0, 0), (0.50, 0.02, 0.13), (0.50, -0.02, 0.13), (0.50, 0.02, -0.13), (0.50, -0.02, -0.13)],
            [(0, 1, 2), (0, 3, 4), (0, 2, 4), (0, 3, 1)])
    parts.append(tail)
    for s in (-1, 1):                               # 胸鰭
        parts.append(([(0.02, 0.04 * s, -0.02), (0.14, 0.16 * s, -0.06), (0.02, 0.05 * s, -0.09)],
                      [(0, 1, 2)]))
    parts.append(([(0.0, 0.0, 0.12), (0.16, 0.0, 0.10), (0.06, 0.0, 0.22)], [(0, 1, 2)]))   # 背鰭
    v, f = merge(*parts)

    def col(co, n):
        # 錦鯉：白底紅斑
        return (0.86, 0.24, 0.14) if math.sin(co.x * 11.0) + math.sin(co.z * 7.0) > 0.55 else (0.94, 0.92, 0.88)
    ob = mesh_from("koi", v, f, col)
    export([ob], "koi")


# ══════════════════════════════════════════════ 狛犬 ════════════════════
#
# 稗田邸 Feature List §2「巨型基座狛犬 ×2」：總高 2.7m（1.2m 花崗岩基座 +
# 1.5m 雕像），階梯兩側。先出阿形（開口，mouth_open=True）；吽形只要把
# mouth_open 關掉、換個 seed 重跑，鬃毛與尾焰的隨機擾動就會自己長得不一樣。
#
# ⚠ v1 使用者退件：「不夠肌肉感」。病根不是半徑不夠粗，是**整隻獸只有
# 一根管子**——軀幹一條 sweep 從臀部平滑收到頸根，四肢是等徑細圓柱插上去。
# 平滑連續的單一曲面沒有任何地方會產生高光斷點，半徑開再大也只會像香腸。
# （跟 make_hedge.py 的「西瓜」、make_hieda.py 樹冠的「球」同一類病：
# 光滑封閉曲面本身不帶資訊。）
#
# 改法是**團塊堆疊**：胸廓、左右大腿、左右肩臂、胸板各自獨立 sweep 再相交。
# 相交處在 smooth shading 下留下硬摺線 —— 那條摺線就是肌肉群的分界。
# 搭配三件事一起做才成立：
#   ・比例壓扁：坐高 ~1.55m、寬度放到 ~1.05m（v1 只有 0.66m 寬）。
#     矮而寬才是猛獸，高而窄一定是狗。
#   ・四肢做強錐度：肩 0.26 → 肘 0.20 → 腕 0.135 → 掌 0.15（掌比腕寬）。
#   ・前腿之間補胸板，正面才不會是「兩根柱子中間一個洞」。
#
# v2 renders 又抓到三個：
#   ・頭縮在肩膀裡 —— 頭心跟肩峰同高就是駝背。頸子拉長、頭心抬到肩上
#     0.35m，胸才推得出去。
#   ・鬃毛變成莫西干 —— 環狀鬃刺在頂點那幾根直直往上戳到頭邊。
#   ・基座像結婚蛋糕 —— 兩階等高的方塊太笨重。改成薄底座 + 高主體。
#
# v3 renders 再抓到三個（現在的版本）：
#   ・鬃毛救過頭 —— 為了壓掉莫西干給了 +y 0.12~0.24 的後掃偏置，但長度
#     只有 0.15~0.23，後掃分量直接蓋過徑向分量，整圈鬃毛倒下去貼在背上
#     變成一排扁刀片，側面看像翅膀。改成短（0.10~0.15）、粗（末端 0.075
#     不收尖）、幾乎純徑向（後掃砍到 0.04~0.09）的石雕捲毛。
#   ・前腿還是等徑錐 —— 五節單調遞減沒有肌腹。改成七節的**鼓－束－鼓**
#     （肩 0.26 → 上臂腹 0.235 → 肘上束 0.175 → 前臂腹 0.195 → 束 0.145
#     → 腕 0.125 → 掌 0.15）。smooth shading 下每個鼓－束交界都會生一條
#     高光帶，那才是「看得出肌肉」的來源，不是把整根調粗。
#   ・眉稜是方塊 —— 全身都是掃掠曲面，只有眉稜兩塊 box，像貼上去的積木。


def _paw(parts, cx, cy, cz, dy, r0, r1, toe_n=3, toe_r=0.058, spread=0.10):
    """獸掌：壓扁的掌墊 + 幾根趾。掌比腕寬才有抓地感。
    掌沿 -y 掃，此時 squash=(z 縮放, x 縮放) —— 壓 z、放 x 就是扁掌。"""
    parts.append(sweep([(cx, cy, cz), (cx, cy + dy, cz - 0.01)],
                       [r0, r1], sides=8, squash=[(0.70, 1.18)] * 2))
    for c in range(toe_n):
        ox = (c - (toe_n - 1) / 2.0) * spread
        parts.append(sweep([(cx + ox, cy + dy * 0.75, cz - 0.005),
                            (cx + ox * 1.10, cy + dy * 1.30, cz - 0.02)],
                           [toe_r, toe_r * 0.72], sides=5))


def make_komainu(name="komainu_a", mouth_open=True, seed=5):
    clear()
    rng = random.Random(seed)
    STONE = (0.58, 0.57, 0.53)

    parts = []
    # ── 花崗岩基座：薄底座 + 高主體，總高 1.2m（Feature List 指定）。
    # 兩階等高的話整組看起來就是一塊笨重的方糖，壓過上面的獸。
    parts.append(box_verts(0, 0, 0.15, 1.66, 1.86, 0.30))
    parts.append(box_verts(0, 0, 0.75, 1.34, 1.54, 0.90))
    z0 = 1.20

    # ── 胸廓：臀 → 腰（收）→ 胸（放到最寬）→ 頸（收）。
    # squash 第一個值放大 x：胸口半寬 0.36×1.34 ≈ 0.48，全寬 ~0.97m，
    # 對上 1.55m 坐高才是「矮壯」。頸子從 z0+0.82 一路拉到 z0+1.12，
    # 頭才有地方擺在肩膀**上面**而不是中間。
    parts.append(sweep(
        [(0, 0.40, z0 + 0.30), (0, 0.24, z0 + 0.54), (0, 0.02, z0 + 0.70),
         (0, -0.20, z0 + 0.82), (0, -0.30, z0 + 0.96), (0, -0.34, z0 + 1.12)],
        [0.31, 0.32, 0.32, 0.36, 0.27, 0.21], sides=12,
        squash=[(1.28, 1.00), (1.24, 1.00), (1.22, 0.98),
                (1.34, 1.02), (1.10, 1.00), (1.00, 1.00)]))

    # ── 胸板：填前腿之間。少了這塊，正面就是「兩根柱子夾一個洞」。
    parts.append(sweep([(0, -0.30, z0 + 0.84), (0, -0.35, z0 + 0.60), (0, -0.34, z0 + 0.40)],
                       [0.26, 0.24, 0.20], sides=10, squash=[(1.16, 1.00)] * 3))

    for sx in (1, -1):
        # ── 後腿：大腿團塊沿 x 往外鼓（squash=(z 縮放, y 縮放)），
        # 跟胸廓相交出髖部摺線 —— 蹲坐獸最明顯的肌肉分界就是這條。
        parts.append(sweep([(sx * 0.04, 0.32, z0 + 0.44), (sx * 0.22, 0.34, z0 + 0.42),
                            (sx * 0.34, 0.30, z0 + 0.32)],
                           [0.28, 0.30, 0.19], sides=10, squash=[(1.06, 1.00)] * 3))
        parts.append(sweep([(sx * 0.32, 0.28, z0 + 0.32), (sx * 0.31, 0.16, z0 + 0.15),
                            (sx * 0.30, 0.09, z0 + 0.09)],
                           [0.17, 0.14, 0.13], sides=8))
        _paw(parts, sx * 0.30, 0.09, z0 + 0.08, -0.17, 0.15, 0.135, spread=0.093)

        # ── 前腿：肩 0.26 → 肘 0.20 → 前臂 0.16 → 腕 0.135 → 掌 0.15。
        # v2 的錐度太弱，五節幾乎等徑，看起來是象腿。最上一節半徑特意大到
        # 咬進胸廓，交線就是肩胛／三角肌。
        parts.append(sweep(
            [(sx * 0.30, -0.24, z0 + 0.90), (sx * 0.315, -0.28, z0 + 0.74),
             (sx * 0.32, -0.32, z0 + 0.60), (sx * 0.32, -0.35, z0 + 0.44),
             (sx * 0.32, -0.37, z0 + 0.28), (sx * 0.32, -0.385, z0 + 0.17),
             (sx * 0.32, -0.39, z0 + 0.11)],
            [0.26, 0.235, 0.175, 0.195, 0.145, 0.125, 0.15], sides=10,
            squash=[(1.00, 1.06)] * 7))
        _paw(parts, sx * 0.32, -0.35, z0 + 0.09, -0.19, 0.165, 0.145, spread=0.104)

    # ── 頭：sweep 的圓顱，不用 box（方塊擺在全掃掠的身體上就是積木）。
    # 沿 -y 掃，squash=(z 縮放, x 縮放) —— 壓 z 放 x 得到寬顱骨。
    # 頭心 z0+1.28，比肩峰（z0+0.90+0.26≈1.16）高出一截，不再縮在肩裡。
    parts.append(sweep([(0, -0.30, z0 + 1.22), (0, -0.48, z0 + 1.28), (0, -0.62, z0 + 1.22)],
                       [0.23, 0.28, 0.23], sides=10, squash=[(0.95, 1.18)] * 3))
    for sx in (1, -1):                                    # 頰／咬肌
        parts.append(sweep([(sx * 0.09, -0.58, z0 + 1.19), (sx * 0.22, -0.56, z0 + 1.17)],
                           [0.15, 0.11], sides=8))

    # 吻部：v2 太長太窄像熊嘴。縮短 0.30→0.26 並加粗末端（0.125→0.15）。
    jaw_gap = 0.20 if mouth_open else 0.04    # 吽形把嘴闔上只要改這個
    parts.append(sweep([(0, -0.58, z0 + 1.24), (0, -0.84, z0 + 1.25)],
                       [0.21, 0.15], sides=8, squash=[(0.90, 1.08)] * 2))     # 上顎
    parts.append(sweep([(0, -0.56, z0 + 1.24 - jaw_gap), (0, -0.80, z0 + 1.25 - jaw_gap * 1.15)],
                       [0.185, 0.13], sides=8, squash=[(0.90, 1.08)] * 2))    # 下顎
    for sx in (1, -1):
        parts.append(sweep([(sx * 0.09, -0.80, z0 + 1.18),
                            (sx * 0.09, -0.80, z0 + 1.18 - jaw_gap * 0.40)],
                           [0.038, 0.007], sides=4))                          # 上犬齒
        parts.append(sweep([(sx * 0.09, -0.76, z0 + 1.24 - jaw_gap),
                            (sx * 0.09, -0.76, z0 + 1.24 - jaw_gap * 0.52)],
                           [0.038, 0.007], sides=4))                          # 下犬齒
        parts.append(sweep([(sx * 0.17, -0.58, z0 + 1.32), (sx * 0.17, -0.67, z0 + 1.31)],
                           [0.082, 0.058], sides=6))                          # 眼球
        parts.append(sweep([(sx * 0.15, -0.52, z0 + 1.39), (sx * 0.19, -0.65, z0 + 1.37)],
                           [0.085, 0.055], sides=6))                          # 眉稜
        # 耳：短鈍兩段錐，形狀跟鬃毛的焰刺分開，不然頭頂糊成一團
        parts.append(sweep([(sx * 0.20, -0.36, z0 + 1.36), (sx * 0.27, -0.24, z0 + 1.50)],
                           [0.12, 0.05], sides=6))

    # ── 鬃毛：肩頸交界一圈焰狀捲毛。
    # v2 的環狀鬃刺在頂點那幾根直直往上戳，側面看是一排莫西干。這裡把
    # 垂直分量砍到 0.45 倍、+y 後掃偏置拉到 0.12~0.24，並且末端不收成針
    # （0.045 而不是 0.013）—— 貼著脖子往後的粗捲毛，不是頭上的刺。
    neck = (0.0, -0.26, z0 + 0.98)
    n_mane = 16
    for i in range(n_mane):
        ang = i / n_mane * TAU
        dx, dz = math.cos(ang), math.sin(ang)
        base = (neck[0] + dx * 0.25, neck[1] + rng.uniform(-0.05, 0.05), neck[2] + dz * 0.23)
        ln = rng.uniform(0.10, 0.15)
        tip = (base[0] + dx * ln, base[1] + rng.uniform(0.04, 0.09), base[2] + dz * ln * 0.8)
        parts.append(sweep([base, tip], [0.115, 0.075], sides=5))

    # ── 尾：從臀後翹起再往回勾，整條收在背後（v1 掃到肩膀正上方，
    # 側面看像一隻甩到頭頂的手臂）。
    parts.append(sweep([(0, 0.52, z0 + 0.36), (0, 0.61, z0 + 0.64), (0, 0.57, z0 + 0.92),
                        (0, 0.39, z0 + 1.08), (0, 0.47, z0 + 1.21)],
                       [0.21, 0.19, 0.16, 0.125, 0.055], sides=8))
    # 尾焰：x/y/z 三軸都要給散度 —— 只在 x 撒開的話，從正側面（只看得到
    # y-z 平面）整簇會完全躲在尾巴主管後面，等於白做
    for t in [(0, 0.56, z0 + 0.92), (0, 0.38, z0 + 1.08)]:
        for _ in range(3):
            tip = (t[0] + rng.uniform(-0.17, 0.17), t[1] + rng.uniform(-0.06, 0.16),
                   t[2] + rng.uniform(0.12, 0.20))
            parts.append(sweep([t, tip], [0.055, 0.007], sides=4))

    verts, faces = merge(*parts)

    def col(co, n):
        # 基座跟獸爪常年潮濕，往下摻苔綠；越高越乾淨的花崗岩灰
        moss = (0.30, 0.36, 0.23)
        k = max(0.0, (1.35 - co.z) / 1.35) * 0.35 if co.z < 1.35 else 0.0
        return tuple(STONE[i] * (1 - k) + moss[i] * k for i in range(3))

    ob = mesh_from(name, verts, faces, col)
    export([ob], name)


# ══════════════════════════════════════════════ 石燈籠 ══════════════════
#
# 稗田邸參道用（春日燈籠形）。六角形，由下而上：
# 基礎 → 竿（柱，帶兩道節）→ 中台 → 火袋 → 笠 → 宝珠。
#
# 火袋（燈室）**不做實體六角柱**：那樣就是一顆石頭疙瘩，看不出是燈。
# 改成上下兩片六角盤 + 六根角柱，中間鏤空 —— 剪影上就是「透光的燈室」，
# 而且完全不需要 boolean（這支檔案沒有 bmesh 布林的基礎建設）。
#
# sides=6 的 sweep 垂直掃時，六角形正好落在 x-y 平面（u=-x、v=-y），
# 不用另外轉向。

def make_stone_lantern(name="stone_lantern", seed=3):
    clear()
    rng = random.Random(seed)
    parts = []

    # 基礎（覆蓮式的矮座）
    parts.append(sweep([(0, 0, 0.0), (0, 0, 0.18), (0, 0, 0.30)],
                       [0.44, 0.42, 0.33], sides=6))
    # 竿（柱）+ 兩道節
    parts.append(sweep([(0, 0, 0.28), (0, 0, 1.18)], [0.135, 0.125], sides=8))
    for zz in (0.58, 0.92):
        parts.append(sweep([(0, 0, zz - 0.045), (0, 0, zz + 0.045)],
                           [0.175, 0.175], sides=8))
    # 中台（往外翻的托盤）
    parts.append(sweep([(0, 0, 1.14), (0, 0, 1.30), (0, 0, 1.42)],
                       [0.20, 0.32, 0.30], sides=6))
    # 火袋：上下盤 + 六根角柱，中間鏤空
    parts.append(sweep([(0, 0, 1.40), (0, 0, 1.50)], [0.34, 0.33], sides=6))
    parts.append(sweep([(0, 0, 1.88), (0, 0, 1.96)], [0.33, 0.35], sides=6))
    for k in range(6):
        a = (k / 6.0) * TAU + TAU / 12.0
        px, py = math.cos(a) * 0.285, math.sin(a) * 0.285
        parts.append(sweep([(px, py, 1.48), (px, py, 1.90)], [0.052, 0.052], sides=4))
    # 笠（六角屋頂，簷口微微外翻）
    parts.append(sweep([(0, 0, 1.94), (0, 0, 2.14), (0, 0, 2.19)],
                       [0.30, 0.58, 0.62], sides=6))
    for k in range(6):                                   # 蕨手（簷角的小翹起）
        a = (k / 6.0) * TAU
        px, py = math.cos(a) * 0.60, math.sin(a) * 0.60
        parts.append(sweep([(px, py, 2.16), (px * 1.10, py * 1.10, 2.30)],
                           [0.055, 0.022], sides=4))
    # 宝珠
    parts.append(sweep([(0, 0, 2.16), (0, 0, 2.30), (0, 0, 2.44)],
                       [0.10, 0.135, 0.03], sides=8))

    verts, faces = merge(*parts)

    def col(co, n):
        # 上朝面積苔、下方陰乾 —— 跟 make_rock 同一套邏輯，燈籠才不是一塊
        # 均勻的灰塑膠
        base = (0.545, 0.540, 0.510)
        moss = (0.32, 0.39, 0.25)
        k = max(n.z, 0.0) ** 2 * 0.42
        k += 0.10 if co.z < 0.35 else 0.0
        k = min(k, 0.62)
        return tuple(base[i] * (1 - k) + moss[i] * k for i in range(3))

    ob = mesh_from(name, verts, faces, col)
    export([ob], name)


# ══════════════════════════════════════════════ 岩石 ════════════════════
def make_rock(name, seed, subdiv=1, rough=0.34):
    clear()
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv + 1, radius=1.0)
    ob = bpy.context.active_object
    me = ob.data
    # 每個頂點沿法線隨機推拉 → 真的有凹凸，不是方板
    for v in me.vertices:
        k = 1.0 + rng.uniform(-rough, rough)
        # 低頻起伏疊高頻碎面
        k += 0.22 * math.sin(v.co.x * 2.7 + seed) * math.sin(v.co.z * 3.1)
        v.co = v.co * k
    ob.scale = (rng.uniform(0.85, 1.3), rng.uniform(0.8, 1.25), rng.uniform(0.55, 0.95))
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_flat()
    attr = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    for poly in me.polygons:
        # 朝上的面帶苔綠，側面是灰岩
        up = max(poly.normal.z, 0.0)
        base = (0.50, 0.49, 0.47)
        moss = (0.34, 0.42, 0.28)
        k = up ** 2 * 0.75
        c = tuple(base[i] * (1 - k) + moss[i] * k for i in range(3))
        for li in poly.loop_indices:
            attr.data[li].color = (c[0], c[1], c[2], 1.0)
    export([ob], name)

# ══════════════════════════════ 人間之里 密度層道具 ══════════════════════
# 2026-08-30 移除。這一段產出的 prop_*（樽／籃／木箱／縁台／暖簾／提灯／
# 招牌）在專案裡零引用，而且輸出的 GLB materials=0、images=0，在引擎裡是
# 純白塑膠塊；B3 廣場攤台就是栽在這上面。街道道具改由使用者的 Meshy 屋台
# 組供應。本檔其餘生成器（dragon_statue／duck／heron／koi／komainu_a／
# stone_lantern／rock_a-d）仍是活的，都還在場景裡被引用，不要一起刪。


make_dragon()
make_duck()
make_heron()
make_koi()
# 先只出阿形一隻給使用者看造型；吽形（mouth_open=False, seed 換一個）
# 等這隻過關再補，不用兩隻一起賭。
make_komainu("komainu_a", mouth_open=True, seed=5)
make_stone_lantern()
for i, nm in enumerate(["rock_a", "rock_b", "rock_c", "rock_d"]):
    make_rock(nm, 17 + i * 31, subdiv=1 if i < 2 else 2, rough=0.30 + i * 0.06)
print("done")
