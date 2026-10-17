"""獸道 S01 R6：入口的建築與農村道具（Blender 5.2.1，bpy＋bmesh 外的純頂點組裝，固定 seed、可重現）。

用法：
    背景（正式輸出）：blender -b --python build_s01_shrine.py -- [--no-export] [--preview=<base>] [--only=a,b]
    即時 Blender（MCP）：g={'__name__':'s01shrine','__file__':<本檔>}; exec(open(<本檔>).read(), g); g['build_all'](export=False)
      只在自己的 collection「S01_SHRINE」裡建，不重設場景、不動其他物件。
共用 build_s01_kit.py 的網格累加器（MB）、管、葉等工具（以 exec 載入、不改它；它的 27＋ 件資產不受影響）。

輸出（assets/beast_path/s01_kit/）：
    glb/s01_torii_a.glb        明神鳥居（朱漆木部：柱、根卷、貫、楔、額束、額、島木、笠木）——Godot 材質 mat/s01k_paint.gdshader
    glb/s01_torii_a_base.glb   鳥居石台座 ×2——Godot 材質 s01k_rock（同 S01 岩，苔／腳邊泥土在 Godot 依地形算）
    glb/s01_lantern_a.glb      春日型六角石燈籠（基礎＋反花、竿＋節、中台、火袋〔兩面火口＝真的開口〕、六角笠＋蕨手、請花＋寶珠）——s01k_rock
    glb/s01_crop_daikon.glb    大根（羽狀深裂葉的蓮座＋露出土面的白根頭）——meadow_grass（同 S01 植物）
    glb/s01_crop_negi.glb      蔥（一株 2 本、管狀葉、白的葉鞘）
    glb/s01_crop_greens.glb    小松菜型葉菜（湯匙形葉＋葉柄）
    src/s01_shrine.blend、src/shrine_manifest.json

座標：Blender Z 向上；glTF 匯出 Y 向上（Blender −Y → Godot +Z）。原點＝地面（鳥居＝兩柱中點；燈籠＝竿心）。
鳥居：柱心距 5.0 m（地面）＝原 layout span，通行淨寬不變；鳥居本體 Godot 本地 ±Z 對稱、額面向 +Z（村子那側）。
頂點資料（鳥居木部，對 s01k_paint.gdshader）：COLOR.rgb＝塗色（sRGB）；UV0＝木紋座標（公尺：u 繞周／橫向、v 沿構件）；
    UV1.x＝材質（0 朱漆、0.25 黑漆、0.5 素木）、UV1.y＝木紋方向（0 直立構件、1 水平構件）。
"""
import bpy, math, random, os, sys, json
from mathutils import Vector

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", r"D:/神社/shrine/godot/assets/beast_path/s01_kit/src/build_s01_shrine.py")))
K = {"__name__": "s01kit_lib"}
exec(open(os.path.join(_HERE, "build_s01_kit.py"), encoding="utf-8").read(), K)
K["COLL"] = "S01_SHRINE"
MB, tube, leaf, fbm, lerp3, sstep = K["MB"], K["tube"], K["leaf"], K["fbm"], K["lerp3"], K["sstep"]
placeholder_mat, coll, clear_coll = K["placeholder_mat"], K["coll"], K["clear_coll"]
OUT = K["OUT"]
GLB_DIR = OUT + "/glb"
SRC_DIR = OUT + "/src"


# ============================================================ 硬表面工具
def poly(mb, pts, colfn, mat, grain, inside, uvfn=None):
    """平面多邊形（扇形三角化）；inside＝實體內一點，法線朝外（不對就自動翻轉）。"""
    pts = [Vector(p) for p in pts]
    n = Vector((0.0, 0.0, 0.0))
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    if n.length < 1e-9:
        return
    n.normalize()
    c = sum(pts, Vector()) / len(pts)
    if n.dot(c - Vector(inside)) < 0:
        pts.reverse()
        n = -n
    ids = []
    for p in pts:
        u = uvfn(p, n) if uvfn else _uv_auto(p, n, grain)
        ids.append(mb.v(p, n, colfn(p, n), u, (mat + 0.01, float(grain))))
    for i in range(1, len(ids) - 1):
        mb.tri(ids[0], ids[i], ids[i + 1])


def _uv_auto(p, n, grain):
    if grain == 1:                       # 水平構件：v 沿 X
        return (p.y + p.z if abs(n.z) < 0.7 else p.y, p.x)
    return (p.x + p.y, p.z)


def box(mb, mn, mx, colfn, mat, grain=0):
    x0, y0, z0 = mn
    x1, y1, z1 = mx
    ctr = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    V = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    for f in ((0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        poly(mb, [V[i] for i in f], colfn, mat, grain, ctr)


def loft_x(mb, xs, prof, zfn, colfn, mat, end_slant=0.0, caps=True):
    """沿 X 放樣：prof＝[(y, z)]（凸多邊形，順序任意方向）；zfn(x)＝這個 x 的底高（反り）；end_slant＝兩端木口上緣外伸量。"""
    zmax = max(q[1] for q in prof)
    rings = []
    for i, x in enumerate(xs):
        ring = []
        for (y, z) in prof:
            xx = x
            if i == 0:
                xx = x - end_slant * (z / zmax)
            elif i == len(xs) - 1:
                xx = x + end_slant * (z / zmax)
            ring.append(Vector((xx, y, zfn(x) + z)))
        rings.append(ring)
    cy = sum(q[0] for q in prof) / len(prof)
    cz = sum(q[1] for q in prof) / len(prof)
    n = len(prof)
    for i in range(len(xs) - 1):
        xm = (xs[i] + xs[i + 1]) / 2
        inside = (xm, cy, zfn(xm) + cz)
        for k in range(n):
            k2 = (k + 1) % n
            poly(mb, [rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]], colfn, mat, 1, inside)
    if caps:
        poly(mb, rings[0], colfn, mat, 1, (xs[0] + 0.5, cy, zfn(xs[0]) + cz))
        poly(mb, rings[-1], colfn, mat, 1, (xs[-1] - 0.5, cy, zfn(xs[-1]) + cz))


def lathe(mb, prof, sides, colfn, mat, center=(0.0, 0.0), phase=0.0, jitter=None, cap_bot=False, cap_top=False, smooth=True, hexr=False):
    """迴轉體：prof＝[(r, z)] 由下往上。smooth＝圓的（徑向法線）；hexr＝True 時 r 是六角形的外接半徑、側面平的。"""
    cx, cy = center
    rings = []
    for (r, z) in prof:
        ring = []
        for j in range(sides):
            a = phase + math.tau * j / sides
            p = Vector((cx + r * math.cos(a), cy + r * math.sin(a), z))
            if jitter:
                p = p + jitter(p)
            ring.append(p)
        rings.append(ring)
    m = len(prof)
    if smooth:
        ids = []
        for i in range(m):
            r0, z0 = prof[max(i - 1, 0)]
            r1, z1 = prof[min(i + 1, m - 1)]
            dr, dz = r1 - r0, z1 - z0
            row = []
            for j in range(sides):
                a = phase + math.tau * j / sides
                rad = Vector((math.cos(a), math.sin(a), 0.0))
                nn = (rad * dz - Vector((0, 0, 1)) * dr)
                nn = nn.normalized() if nn.length > 1e-6 else rad
                p = rings[i][j]
                row.append(mb.v(p, nn, colfn(p, nn), (j / sides * math.tau * max(prof[i][0], 0.05), p.z), (mat + 0.01, 0.0)))
            ids.append(row)
        for i in range(m - 1):
            for j in range(sides):
                j2 = (j + 1) % sides
                a, b, c, d = ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j]
                if abs(prof[i][0]) < 1e-6:
                    mb.tri(a, c, d)
                elif abs(prof[i + 1][0]) < 1e-6:
                    mb.tri(a, b, c)
                else:
                    mb.quad(a, b, c, d)
    else:
        for i in range(m - 1):
            zc = (prof[i][1] + prof[i + 1][1]) / 2
            for j in range(sides):
                j2 = (j + 1) % sides
                q = [rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]]
                if (q[0] - q[1]).length < 1e-6 or (q[2] - q[3]).length < 1e-6:
                    q = [q[0], q[2], q[3]] if (q[0] - q[1]).length < 1e-6 else [q[0], q[1], q[2]]
                poly(mb, q, colfn, mat, 0, (cx, cy, zc))
    if cap_bot:
        poly(mb, rings[0], colfn, mat, 0, (cx, cy, prof[0][1] + 1.0))
    if cap_top:
        poly(mb, rings[-1], colfn, mat, 0, (cx, cy, prof[-1][1] - 1.0))
    return rings


# ============================================================ 鳥居（明神鳥居）
SPAN = 5.0           # 柱心距（地面）
LEAN = 0.10          # 転び：柱頂往內（每側）
Z_FOOT = 0.30        # 石台座頂＝柱腳
PR0, PR1 = 0.23, 0.20
Y_NUKI = (3.22, 3.52)
NUKI_HALF = 3.02
Z_SHIMA = 4.24       # 島木底（中央）
SHIMA_H = 0.24
SHIMA_HALF = 3.10
KASA_HALF = 3.52
SORI = 0.22
SORI_X0 = 0.9

VERM = (0.60, 0.25, 0.17)        # 朱（sRGB）：收斂、不是飽和紅
VERM_FADE = (0.66, 0.38, 0.29)   # 日曬褪色（朝上的面、上半）
VERM_DARK = (0.50, 0.22, 0.16)
BLACK = (0.105, 0.098, 0.092)
BLACK_FADE = (0.20, 0.18, 0.16)
WOOD = (0.33, 0.27, 0.20)


def lift(x):
    a = abs(x)
    if a <= SORI_X0:
        return 0.0
    t = (a - SORI_X0) / (KASA_HALF - SORI_X0)
    return SORI * t ** 2


def post_x(z, side):
    return side * (SPAN / 2 - LEAN * z / Z_SHIMA)


def paint_col(seed):
    def f(p, n):
        v = fbm(Vector((p.x * 0.9, p.y * 0.9, p.z * 0.35)), seed, 3)
        w = fbm(Vector((p.x * 3.1, p.y * 3.1, p.z * 0.6)), seed + 7, 2)
        c = lerp3(VERM, VERM_DARK, sstep(-0.2, 0.6, v) * 0.6)
        up = max(0.0, n.z)
        fade = min(1.0, 0.25 * sstep(0.5, 4.6, p.z) + 0.55 * up + 0.25 * sstep(0.1, 0.7, w))
        return lerp3(c, VERM_FADE, fade)
    return f


def black_col(seed):
    def f(p, n):
        v = fbm(Vector((p.x * 1.4, p.y * 1.4, p.z)), seed, 3)
        return lerp3(BLACK, BLACK_FADE, min(1.0, 0.35 * max(0.0, n.z) + 0.4 * sstep(0.0, 0.7, v)))
    return f


def wood_col(seed):
    def f(p, n):
        v = fbm(Vector((p.x * 6.0, p.y * 6.0, p.z * 1.2)), seed, 2)
        return lerp3(WOOD, (0.42, 0.37, 0.30), sstep(-0.3, 0.6, v))
    return f


def torii(name):
    mb = MB()
    pc, bc, wc = paint_col(11), black_col(12), wood_col(13)
    sides = 18
    zt = Z_SHIMA + 0.10
    for side in (-1, 1):
        # 柱：收分＋転び，12 段（色斑有地方落）
        prof = []
        for i in range(13):
            z = Z_FOOT + (zt + lift(post_x(zt, side)) - Z_FOOT) * i / 12
            prof.append((PR0 + (PR1 - PR0) * (z - Z_FOOT) / (zt - Z_FOOT), z))
        cx = post_x(0.0, side)
        # 轉び：每一圈的中心依高度往內
        rings_pts = []
        ids = []
        for i, (r, z) in enumerate(prof):
            row = []
            ccx = post_x(z, side)
            for j in range(sides):
                a = math.tau * j / sides
                rad = Vector((math.cos(a), math.sin(a), 0.0))
                p = Vector((ccx + r * math.cos(a), r * math.sin(a), z))
                row.append(mb.v(p, rad, pc(p, rad), (j / sides * math.tau * r, z), (0.01, 0.0)))
            ids.append(row)
        for i in range(len(prof) - 1):
            for j in range(sides):
                j2 = (j + 1) % sides
                mb.quad(ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j])
        # 根卷（黑漆）：柱腳 0.48 m，上緣小斜面
        rr = PR0 + 0.028
        nprof = [(rr, Z_FOOT - 0.02), (rr, Z_FOOT + 0.46), (rr - 0.012, Z_FOOT + 0.49), (PR0 - 0.002, Z_FOOT + 0.50)]
        lathe(mb, nprof, sides, bc, 0.25, center=(post_x(Z_FOOT + 0.25, side), 0.0))
        # 楔（貫が柱を貫く外側）
        # 楔：從貫的上面打進去、上寬下窄，頭露出 9 cm、尾露出 5 cm；貼著柱外側
        xw = post_x(sum(Y_NUKI) / 2, side) + side * (PR1 + 0.055)
        zb_, zt_ = Y_NUKI[0] - 0.05, Y_NUKI[1] + 0.09
        wb, wt = 0.022, 0.05
        q = [(xw - side * wb, -0.10, zb_), (xw + side * wb, -0.10, zb_), (xw + side * wt, -0.10, zt_), (xw - side * wt * 0.4, -0.10, zt_)]
        qb = [(x, 0.10, z) for x, _, z in q]
        cen = (xw, 0.0, (zb_ + zt_) / 2)
        poly(mb, q, pc, 0.0, 0, cen)
        poly(mb, qb, pc, 0.0, 0, cen)
        for i in range(4):
            i2 = (i + 1) % 4
            poly(mb, [q[i], q[i2], qb[i2], qb[i]], pc, 0.0, 0, cen)
    # 貫
    xs = [-NUKI_HALF + 2 * NUKI_HALF * i / 16 for i in range(17)]
    loft_x(mb, xs, [(-0.085, 0.0), (0.085, 0.0), (0.085, Y_NUKI[1] - Y_NUKI[0]), (-0.085, Y_NUKI[1] - Y_NUKI[0])], lambda x: Y_NUKI[0], pc, 0.0)
    # 額束＋額
    box(mb, (-0.11, -0.075, Y_NUKI[1] - 0.01), (0.11, 0.075, Z_SHIMA + 0.02), pc, 0.0, 0)
    zg = (Y_NUKI[1] + Z_SHIMA) / 2 + 0.02
    hw, hh = 0.27, 0.36
    box(mb, (-hw, -0.105, zg - hh), (hw, -0.075, zg + hh), bc, 0.25, 0)            # 額縁（前，黑）
    box(mb, (-hw + 0.055, -0.118, zg - hh + 0.055), (hw - 0.055, -0.100, zg + hh - 0.055), wc, 0.5, 0)   # 額板（素木，風化）
    box(mb, (-hw, 0.075, zg - hh), (hw, 0.105, zg + hh), bc, 0.25, 0)              # 背面
    # 島木（朱）
    xs = [-SHIMA_HALF + 2 * SHIMA_HALF * i / 24 for i in range(25)]
    loft_x(mb, xs, [(-0.16, 0.0), (0.16, 0.0), (0.16, SHIMA_H), (-0.16, SHIMA_H)], lambda x: Z_SHIMA + lift(x), pc, 0.0, end_slant=0.05)
    # 笠木（黑）：下窄上寬、頂部微圓
    zk = Z_SHIMA + SHIMA_H
    xs = [-KASA_HALF + 2 * KASA_HALF * i / 28 for i in range(29)]
    loft_x(mb, xs, [(-0.17, 0.0), (0.17, 0.0), (0.215, 0.19), (0.215, 0.22), (0.19, 0.30), (0.0, 0.335), (-0.19, 0.30), (-0.215, 0.22), (-0.215, 0.19)],
           lambda x: zk + lift(x), bc, 0.25, end_slant=0.14)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_paint", (0.6, 0.2, 0.12)))
    return ob


def stone_jitter(seed, amp=0.008):
    def j(p):
        return Vector((fbm(p * 7.0, seed, 2), fbm(p * 7.0, seed + 3, 2), fbm(p * 7.0, seed + 5, 2) * 0.5)) * amp
    return j


def grey(p, n):
    return (0.6, 0.6, 0.58)


def torii_base(name):
    """台座：方形石（下 0.92 見方，埋 0.32），上緣大面取，頂 0.66 見方＝柱腳 0.30。手鑿的微起伏。"""
    mb = MB()
    for side in (-1, 1):
        cx = post_x(0.0, side)
        prof = [(0.65, -0.32), (0.655, 0.10), (0.64, 0.16), (0.50, 0.27), (0.47, Z_FOOT)]
        lathe(mb, [(r, z) for r, z in prof], 4, grey, 0.75, center=(cx, 0.0), phase=math.pi / 4, jitter=stone_jitter(31 + side),
              cap_top=True, smooth=False)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_stone", (0.55, 0.55, 0.52)))
    return ob


# ============================================================ 石燈籠（春日型六角）
def hex_ring(R, z, sub, phase=math.pi / 6, lift_fn=None):
    """六角形外接半徑 R 的周邊，每邊細分 sub 段；lift_fn(t_corner)＝角附近抬高（蕨手）。"""
    pts = []
    for k in range(6):
        a0 = phase + math.tau * k / 6
        a1 = phase + math.tau * (k + 1) / 6
        p0 = Vector((R * math.cos(a0), R * math.sin(a0), z))
        p1 = Vector((R * math.cos(a1), R * math.sin(a1), z))
        for s in range(sub):
            t = s / sub
            p = p0.lerp(p1, t)
            if lift_fn:
                p.z += lift_fn(min(t, 1 - t))
            pts.append(p)
    return pts


def loft_rings(mb, rings, colfn, mat, ctr_z, cap_bot=False, cap_top=False):
    n = len(rings[0])
    for i in range(len(rings) - 1):
        zc = (rings[i][0].z + rings[i + 1][0].z) / 2
        for j in range(n):
            j2 = (j + 1) % n
            poly(mb, [rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]], colfn, mat, 0, (0.0, 0.0, zc - 0.0001))
    if cap_bot:
        poly(mb, rings[0], colfn, mat, 0, (0, 0, rings[0][0].z + 1.0))
    if cap_top:
        poly(mb, rings[-1], colfn, mat, 0, (0, 0, rings[-1][0].z - 1.0))


def lantern(name):
    S = 1.0
    mb = MB()
    jit = stone_jitter(41, 0.006)
    HX = math.pi / 6
    # 基礎（六角，埋 0.15）＋反花（往竿收）
    lathe(mb, [(0.40 * S, -0.15), (0.405 * S, 0.06 * S), (0.395 * S, 0.10 * S)], 6, grey, 0.75, phase=HX, jitter=jit, cap_top=True, smooth=False)
    lathe(mb, [(0.37 * S, 0.10 * S), (0.375 * S, 0.125 * S), (0.36 * S, 0.155 * S), (0.32 * S, 0.185 * S), (0.26 * S, 0.21 * S),
               (0.20 * S, 0.228 * S), (0.155 * S, 0.24 * S), (0.13 * S, 0.25 * S)], 20, grey, 0.75, jitter=jit, cap_bot=True, smooth=True)
    # 竿（圓、收分）＋節
    lathe(mb, [(0.125 * S, 0.24 * S), (0.12 * S, 0.60 * S), (0.138 * S, 0.615 * S), (0.138 * S, 0.665 * S), (0.118 * S, 0.68 * S),
               (0.108 * S, 1.00 * S)], 16, grey, 0.75, jitter=jit, smooth=True)
    # 中台（六角、下窄上寬）
    lathe(mb, [(0.13 * S, 0.99 * S), (0.18 * S, 1.02 * S), (0.30 * S, 1.13 * S), (0.31 * S, 1.15 * S), (0.31 * S, 1.20 * S)], 6, grey, 0.75,
          phase=HX, jitter=jit, cap_top=True, smooth=False)
    # 火袋：底板＋六根角柱＋上框；四面實板（帶淺框）、左右兩面（本地 ±X，面向主路）開火口
    zb, zt = 1.20 * S, 1.64 * S
    A = 0.215 * S                      # 外側邊心距
    Rc = A / math.cos(math.pi / 6)
    lathe(mb, [(Rc * 1.02, zb), (Rc * 1.02, zb + 0.045 * S)], 6, grey, 0.75, phase=HX, cap_top=True, smooth=False)
    lathe(mb, [(Rc * 1.06, zt - 0.05 * S), (Rc * 1.06, zt)], 6, grey, 0.75, phase=HX, cap_bot=True, cap_top=True, smooth=False)
    for k in range(6):
        a = HX + math.tau * k / 6
        c = Vector((Rc * 0.94 * math.cos(a), Rc * 0.94 * math.sin(a), 0.0))
        w = 0.032 * S
        box(mb, (c.x - w, c.y - w, zb + 0.04 * S), (c.x + w, c.y + w, zt - 0.045 * S), grey, 0.75, 0)
    for k in range(6):
        ac = math.tau * k / 6                      # 面的法線方向（0＝+X）
        nrm = Vector((math.cos(ac), math.sin(ac), 0.0))
        tan = Vector((-nrm.y, nrm.x, 0.0))
        half = A * math.tan(math.pi / 6) * (0.92 if k in (0, 3) else 0.86)
        z0, z1 = zb + 0.045 * S, zt - 0.05 * S
        if k in (0, 3):                            # 火口：只有薄的上下橫框（開口是空的）
            for (za, zz) in ((z0, z0 + 0.02 * S), (z1 - 0.02 * S, z1)):
                q = [nrm * A - tan * half, nrm * A + tan * half, nrm * (A - 0.04 * S) + tan * half, nrm * (A - 0.04 * S) - tan * half]
                pts_lo = [Vector((p.x, p.y, za)) for p in q]
                pts_hi = [Vector((p.x, p.y, zz)) for p in q]
                cen = (nrm * (A - 0.02 * S)).to_tuple()
                cen = (cen[0], cen[1], (za + zz) / 2)
                poly(mb, pts_lo, grey, 0.75, 0, cen)
                poly(mb, pts_hi, grey, 0.75, 0, cen)
                for i in range(4):
                    i2 = (i + 1) % 4
                    poly(mb, [pts_lo[i], pts_lo[i2], pts_hi[i2], pts_hi[i]], grey, 0.75, 0, cen)
            continue
        # 實板：外面退 0.012 的淺框（框＝外緣一圈、板面凹進）
        o = nrm * A
        i_ = nrm * (A - 0.035 * S)
        cen = ((nrm * (A - 0.018 * S)).x, (nrm * (A - 0.018 * S)).y, (z0 + z1) / 2)
        quad_out = [o - tan * half + Vector((0, 0, z0)), o + tan * half + Vector((0, 0, z0)), o + tan * half + Vector((0, 0, z1)), o - tan * half + Vector((0, 0, z1))]
        quad_in = [i_ - tan * half + Vector((0, 0, z0)), i_ + tan * half + Vector((0, 0, z0)), i_ + tan * half + Vector((0, 0, z1)), i_ - tan * half + Vector((0, 0, z1))]
        # 外面：框四條＋凹板
        m = 0.03 * S
        inn = [o - tan * (half - m) + Vector((0, 0, z0 + m)), o + tan * (half - m) + Vector((0, 0, z0 + m)),
               o + tan * (half - m) + Vector((0, 0, z1 - m)), o - tan * (half - m) + Vector((0, 0, z1 - m))]
        rec = [p - nrm * 0.012 for p in inn]
        for i in range(4):
            i2 = (i + 1) % 4
            poly(mb, [quad_out[i], quad_out[i2], inn[i2], inn[i]], grey, 0.75, 0, cen)
            poly(mb, [inn[i], inn[i2], rec[i2], rec[i]], grey, 0.75, 0, cen)
        poly(mb, rec, grey, 0.75, 0, cen)
        poly(mb, quad_in, grey, 0.75, 0, (cen[0] + nrm.x * 0.5, cen[1] + nrm.y * 0.5, cen[2]))     # 內面（朝內）
        for i in range(4):
            i2 = (i + 1) % 4
            if i in (1, 3):
                poly(mb, [quad_out[i], quad_out[i2], quad_in[i2], quad_in[i]], grey, 0.75, 0, cen)
    # 笠（六角、反りのある軒、蕨手、照り屋根）
    sub = 4
    wl = lambda tc: 0.05 * S * (1.0 - sstep(0.0, 0.18, tc))            # 角の反り上がり
    r_soffit = hex_ring(Rc * 1.06, zt, sub)
    r_eave_b = hex_ring(0.50 * S, zt + 0.035 * S, sub, lift_fn=wl)
    r_eave_t = hex_ring(0.50 * S, zt + 0.085 * S, sub, lift_fn=wl)
    r_1 = hex_ring(0.40 * S, zt + 0.115 * S, sub, lift_fn=lambda tc: 0.6 * wl(tc))
    r_2 = hex_ring(0.27 * S, zt + 0.19 * S, sub)
    r_3 = hex_ring(0.15 * S, zt + 0.27 * S, sub)
    r_4 = hex_ring(0.10 * S, zt + 0.30 * S, sub)
    rings = [r_soffit, r_eave_b, r_eave_t, r_1, r_2, r_3, r_4]
    rings = [[p + jit(p) for p in r] for r in rings]
    loft_rings(mb, rings, grey, 0.75, zt + 0.1, cap_bot=True, cap_top=True)
    # 蕨手（角の巻き）：各角に小さな丸い塊
    for k in range(6):
        a = math.pi / 6 + math.tau * k / 6
        p = Vector((0.505 * S * math.cos(a), 0.505 * S * math.sin(a), zt + 0.125 * S))
        lathe(mb, [(0.0, p.z - 0.035 * S), (0.032 * S, p.z - 0.02 * S), (0.034 * S, p.z + 0.01 * S), (0.0, p.z + 0.03 * S)], 8, grey, 0.75,
              center=(p.x, p.y), smooth=True)
    # 請花＋寶珠
    z0 = zt + 0.30 * S
    lathe(mb, [(0.0, z0 - 0.001), (0.07 * S, z0), (0.105 * S, z0 + 0.04 * S), (0.085 * S, z0 + 0.065 * S), (0.05 * S, z0 + 0.07 * S)], 12, grey,
          0.75, smooth=True)
    jp = [(0.05, 0.07), (0.075, 0.09), (0.088, 0.12), (0.082, 0.15), (0.06, 0.18), (0.03, 0.205), (0.012, 0.225), (0.0, 0.235)]
    lathe(mb, [(r * S, z0 + z * S) for r, z in jp], 14, grey, 0.75, smooth=True)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_stone", (0.55, 0.55, 0.52)))
    return ob


# ============================================================ 作物（meadow_grass 頂點慣例：UV0.y 根 0→尖 1、UV1＝(相位, 剛性)）
def daikon(name, seed=601):
    rng = random.Random(seed)
    mb = MB()
    # 根頭（白〜淡綠、露出土面 6–9 cm）
    h = rng.uniform(0.035, 0.05)
    tube(mb, [Vector((0, 0, -0.05)), Vector((0, 0, h * 0.6)), Vector((0, 0, h))], [0.046, 0.044, 0.033], 8,
         (0.60, 0.62, 0.52), (0.44, 0.54, 0.33), 0.0, 0.0, 0.0, 1.0)
    n = rng.randint(9, 12)
    for k in range(n):
        az = k * 2.4 + rng.gauss(0, 0.25)
        L = rng.uniform(0.36, 0.56)
        el = math.radians(rng.uniform(55, 80))
        dr = math.radians(rng.uniform(25, 55))
        out = Vector((math.cos(az), math.sin(az), 0.0))
        side = Vector((-out.y, out.x, 0.0))
        ph = rng.random()
        p = Vector((out.x * 0.03, out.y * 0.03, h * 0.8))
        pts = [p.copy()]
        seg = 6
        for i in range(seg):
            t = (i + 0.5) / seg
            e = el - dr * t ** 1.5
            d = Vector((math.cos(e) * out.x, math.cos(e) * out.y, math.sin(e)))
            p = p + d * L / seg
            pts.append(p.copy())
        tube(mb, pts, [0.0045 * (1 - i / (seg + 1)) + 0.0015 for i in range(seg + 1)], 3, (0.42, 0.52, 0.30), (0.30, 0.44, 0.18), 0.0, 1.0, ph, 0.6)
        cb = lerp3((0.13, 0.25, 0.07), (0.17, 0.29, 0.08), rng.random())
        ct = lerp3((0.25, 0.40, 0.12), (0.31, 0.45, 0.16), rng.random())
        # 羽狀深裂：葉軸の上半に対生の裂片、先端に大きい頂裂片
        for i in range(2, seg):
            t = i / seg
            q = pts[i]
            fwd = (pts[i + 1] - pts[i - 1]).normalized()
            up = side.cross(fwd).normalized()
            if up.z < 0:
                up = -up
            Ls = L * (0.10 + 0.13 * t)
            for s in (-1, 1):
                f2 = (fwd * 0.35 + side * s).normalized()
                leaf(mb, q, f2, up, Ls, Ls * 0.62, cb, ct, ph, 0.5, t, droop=0.25)
        tip = pts[-1]
        fwd = (pts[-1] - pts[-2]).normalized()
        up = side.cross(fwd).normalized()
        if up.z < 0:
            up = -up
        leaf(mb, tip - fwd * 0.02, fwd, up, L * 0.30, L * 0.20, cb, ct, ph, 0.5, 1.0, droop=0.3)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_crop", (0.2, 0.35, 0.12)))
    return ob


def negi(name, seed=611):
    rng = random.Random(seed)
    mb = MB()
    for pl in range(2):
        b = Vector((rng.uniform(-0.03, 0.03), (pl - 0.5) * 0.06, -0.03))
        n = rng.randint(5, 7)
        for k in range(n):
            az = rng.uniform(0, math.tau)
            H = rng.uniform(0.55, 0.78)
            lean = rng.uniform(0.03, 0.16)
            bend = rng.uniform(0.10, 0.45)
            ph = rng.random()
            pts, rad = [], []
            seg = 6
            for i in range(seg + 1):
                t = i / seg
                ang = lean + bend * t ** 2
                pts.append(b + Vector((math.sin(ang) * math.cos(az) * H * t, math.sin(ang) * math.sin(az) * H * t, H * t * math.cos(ang * 0.6))))
                rad.append(0.0075 * (1 - 0.55 * t) + 0.0015)
            # 葉鞘（白）→ 葉（青みの緑）
            tube(mb, pts[:3], rad[:3], 5, (0.50, 0.55, 0.42), (0.40, 0.50, 0.33), 0.0, 0.33, ph, 0.9)   # 培土：白い軟白部は土の中、見えるのは緑がかった部分
            tube(mb, pts[2:], rad[2:], 4, (0.32, 0.44, 0.32), (0.24, 0.38, 0.26), 0.33, 1.0, ph, 0.6)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_crop", (0.2, 0.35, 0.12)))
    return ob


def greens(name, seed=621):
    rng = random.Random(seed)
    mb = MB()
    n = rng.randint(8, 11)
    for k in range(n):
        az = k * 2.4 + rng.gauss(0, 0.3)
        out = Vector((math.cos(az), math.sin(az), 0.0))
        el = math.radians(rng.uniform(48, 72) if k > 3 else rng.uniform(65, 82))
        Lp = rng.uniform(0.06, 0.11)
        d = Vector((math.cos(el) * out.x, math.cos(el) * out.y, math.sin(el)))
        p0 = Vector((0, 0, -0.01))
        p1 = p0 + d * Lp
        ph = rng.random()
        tube(mb, [p0, p1], [0.006, 0.005], 4, (0.50, 0.60, 0.36), (0.40, 0.54, 0.26), 0.0, 0.4, ph, 0.7)
        L = rng.uniform(0.16, 0.23)
        side = Vector((-out.y, out.x, 0.0))
        fwd = (d * 0.6 + out * 0.4 - Vector((0, 0, 0.15))).normalized()
        up = side.cross(fwd).normalized()
        if up.z < 0:
            up = -up
        cb = lerp3((0.10, 0.20, 0.06), (0.13, 0.24, 0.07), rng.random())
        ct = lerp3((0.18, 0.32, 0.09), (0.24, 0.38, 0.12), rng.random())
        leaf(mb, p1, fwd, up, L, L * 0.62, cb, ct, ph, 0.55, 0.4 + 0.6 * k / n, droop=0.3)
        leaf(mb, p1 + fwd * L * 0.15, (fwd + side * 0.25).normalized(), up, L * 0.85, L * 0.45, cb, ct, ph, 0.55, 0.5, droop=0.35)
        leaf(mb, p1 + fwd * L * 0.15, (fwd - side * 0.25).normalized(), up, L * 0.85, L * 0.45, cb, ct, ph, 0.55, 0.5, droop=0.35)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_crop", (0.2, 0.35, 0.12)))
    return ob


# ============================================================ 清單
ITEMS = [
    ("s01_torii_a", "arch", torii),
    ("s01_torii_a_base", "arch_stone", torii_base),
    ("s01_lantern_a", "arch_stone", lantern),
    ("s01_crop_daikon", "crop", daikon),
    ("s01_crop_negi", "crop", negi),
    ("s01_crop_greens", "crop", greens),
]


def build_all(export=True, only=None):
    c = coll()
    for ob in list(c.objects):
        if any(ob.name == n for n, _, _ in ITEMS) or ob.name.startswith("S01K_ref") or ob.name.startswith("S01K_cam"):
            me = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if me is not None and getattr(me, "users", 1) == 0:
                bpy.data.meshes.remove(me)
    built = []
    for name, cat, fn in ITEMS:
        if only and name not in only:
            continue
        built.append((fn(name), cat))
    man = {}
    for ob, cat in built:
        me = ob.data
        xs = [v.co.x for v in me.vertices]
        ys = [v.co.y for v in me.vertices]
        zs = [v.co.z for v in me.vertices]
        man[ob.name] = {"category": cat, "tris": sum(len(p.vertices) - 2 for p in me.polygons), "verts": len(me.vertices),
                        "size_m": [round(max(xs) - min(xs), 3), round(max(ys) - min(ys), 3), round(max(zs) - min(zs), 3)],
                        "z_min": round(min(zs), 3), "z_max": round(max(zs), 3)}
        if export:
            os.makedirs(GLB_DIR, exist_ok=True)
            for o in bpy.data.objects:
                if o is not None and o.name in bpy.context.view_layer.objects:
                    o.select_set(False)
            ob.select_set(True)
            bpy.context.view_layer.objects.active = ob
            bpy.ops.export_scene.gltf(filepath=GLB_DIR + "/" + ob.name + ".glb", export_format='GLB', use_selection=True, export_apply=True,
                                      export_yup=True, export_vertex_color='ACTIVE', export_all_vertex_colors=False, export_normals=True,
                                      export_texcoords=True, export_materials='PLACEHOLDER', export_extras=False)
    if export and not only:
        with open(SRC_DIR + "/shrine_manifest.json", "w", encoding="utf-8") as f:
            json.dump({"generator": "assets/beast_path/s01_kit/src/build_s01_shrine.py", "blender": bpy.app.version_string, "assets": man,
                       "torii": {"span_post_centres_m": SPAN, "post_r_m": [PR0, PR1], "nemaki_r_m": PR0 + 0.028, "lean_m": LEAN, "foot_z_m": Z_FOOT,
                                 "nuki_z_m": list(Y_NUKI), "shimaki_z_m": Z_SHIMA, "kasagi_half_m": KASA_HALF, "sori_m": SORI,
                                 "clear_width_ground_m": round(SPAN - 2 * (PR0 + 0.028), 3), "clear_height_m": Y_NUKI[0]}},
                      f, ensure_ascii=False, indent=1)
        bpy.ops.wm.save_as_mainfile(filepath=SRC_DIR + "/s01_shrine.blend", copy=True)
    return man


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and (o.users_collection and o.users_collection[0].name != K["COLL"]):
            bpy.data.objects.remove(o, do_unlink=True)
    only = None
    for a in argv:
        if a.startswith("--only="):
            only = a[7:].split(",")
    man = build_all(export=("--no-export" not in argv), only=only)
    for k, v in man.items():
        print("[shrine] %-20s %-10s tris=%6d size=%s z=[%.2f, %.2f]" % (k, v["category"], v["tris"], v["size_m"], v["z_min"], v["z_max"]))
    for a in argv:
        if a.startswith("--preview="):
            K["preview"](a[10:] + "_arch.png", ["s01_torii_a", "s01_torii_a_base", "s01_lantern_a"], cols=3, cam_back=13, cam_h=3.0, lens=40)
            K["preview"](a[10:] + "_crop.png", ["s01_crop_daikon", "s01_crop_negi", "s01_crop_greens"], cols=3, cam_back=2.6, cam_h=1.1, lens=40)
