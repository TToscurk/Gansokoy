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


make_dragon()
make_duck()
make_heron()
make_koi()
for i, nm in enumerate(["rock_a", "rock_b", "rock_c", "rock_d"]):
    make_rock(nm, 17 + i * 31, subdiv=1 if i < 2 else 2, rough=0.30 + i * 0.06)
print("done")
