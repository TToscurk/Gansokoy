"""獸道 荒野化 R2：危險森林的 Blender 實體資產（Blender 5.2.1，bpy＋bmesh，純程序、固定 seed、可重現）。

用法：
    D:/Blender/blender-5.2.1-windows-x64/blender.exe -b --python build_wild_kit.py -- [--no-export] [--preview=<base>] [--only=a,b]
共用 build_s01_kit.py（MB、tube、roots／log 的寫法、rock_finish）與 build_s01_shrine.py（鳥居的構件函式、漆色）——以 exec 載入、不改它們。
只在自己的 collection「WILD_KIT」裡建；輸出到 assets/beast_path/s01_kit/glb/wild_*.glb、src/wild_manifest.json、src/wild_kit.blend。

資產（Godot 端的材質依名稱分派：見 tools/beast_path/s01_dress.gd 與 s01_arch.gd）：
    wild_torii_ruin        破損鳥居（柱位／柱徑與 s01_torii_a 相同＝碰撞不變）：貫右半斷落在柱外、額掉在左柱外、
                           島木與笠木右端斷裂下垂、漆面剝落見木、柱腳苔——s01k_paint
    wild_rootgiant_a／b    折斷巨木的根座（板根＋3–5 m 拱起的根群）——s01k_wood（hackberry）
    wild_log_rootplate_a   連根倒下的巨木（10 m 樹幹＋垂直翻起的根盤）——s01k_wood（dead）
    wild_ruin_pillar_a     斷石柱（立，頂部斜斷）——加工石 s01k_stone
    wild_ruin_pillar_b     倒石柱（兩截＋碎塊）
    wild_ruin_wall_a       崩塌的野面積石垣（5 m，一半塌落）
    wild_ruin_steps_a      通往林中的廢棄石階（4 段，傾斜、缺損）
    wild_jizo_a            斷頭地藏（台座＋身＋落在旁邊的頭）
    wild_mud_a             路緣泥濘（扁平、深色濕土＋淺水窪）——meadow_grass（地被）
座標：Blender Z 向上、原點＝地面；埋入地下的部分在 z<0。
"""
import bpy, bmesh, math, random, os, sys, json
from mathutils import Vector, Matrix, Euler

_HERE = os.path.dirname(os.path.abspath(globals().get("__file__", r"D:/神社/shrine/godot/assets/beast_path/s01_kit/src/build_wild_kit.py")))
S = {"__name__": "s01shrine_lib", "__file__": os.path.join(_HERE, "build_s01_shrine.py")}
exec(open(os.path.join(_HERE, "build_s01_shrine.py"), encoding="utf-8").read(), S)
K = S["K"]
K["COLL"] = "WILD_KIT"
MB, tube, fbm, lerp, lerp3, sstep = K["MB"], K["tube"], K["fbm"], K["lerp"], K["lerp3"], K["sstep"]
placeholder_mat, coll, rock_finish = K["placeholder_mat"], K["coll"], K["rock_finish"]
poly, box, loft_x, lathe = S["poly"], S["box"], S["loft_x"], S["lathe"]
OUT = K["OUT"]
GLB_DIR = OUT + "/glb"
SRC_DIR = OUT + "/src"
COLL = "WILD_KIT"


def mb_append(dst, src, M):
    """把 src（MB）的頂點以矩陣 M 變換後併入 dst。"""
    R = M.to_3x3()
    base = len(dst.P)
    for i, p in enumerate(src.P):
        dst.P.append(tuple(M @ Vector(p)))
        dst.N.append(tuple((R @ Vector(src.N[i])).normalized()))
        dst.C.append(src.C[i])
        dst.U0.append(src.U0[i])
        dst.U1.append(src.U1[i])
    for (a, b, c) in src.F:
        dst.F.append((a + base, b + base, c + base))


# ============================================================ 破損鳥居
def ruin_paint(seed):
    """褪色、剝落見木（灰褐素木）、下段與朝上的面長苔。"""
    base = S["paint_col"](seed)

    def f(p, n):
        c = base(p, n)
        c = lerp3(c, (0.62, 0.42, 0.34), 0.35)                                  # 再褪一層（粉、灰）
        peel = sstep(0.18, 0.34, fbm(Vector((p.x * 2.4, p.y * 2.4, p.z * 1.1)), seed + 41, 3))
        c = lerp3(c, (0.40, 0.36, 0.30), peel)                                   # 剝落：素木灰褐
        moss = max(1.0 - sstep(0.5, 1.6, p.z), 0.7 * max(0.0, n.z) * sstep(-0.1, 0.4, fbm(Vector((p.x * 3, p.y * 3, p.z * 3)), seed + 77, 2)))
        moss *= sstep(-0.35, 0.15, fbm(Vector((p.x * 4.1, p.y * 4.1, p.z * 2.0)), seed + 91, 2))
        c = lerp3(c, (0.23, 0.27, 0.13), min(1.0, moss * 0.85))
        return c
    return f


def ruin_black(seed):
    base = S["black_col"](seed)

    def f(p, n):
        c = base(p, n)
        moss = 0.75 * max(0.0, n.z) * sstep(-0.2, 0.3, fbm(Vector((p.x * 2.5, p.y * 2.5, p.z)), seed + 5, 2))
        return lerp3(lerp3(c, (0.30, 0.27, 0.24), 0.3), (0.22, 0.26, 0.12), moss)
    return f


def jag_end(mb, rng, x_end, prof, zbase, colfn, mat, sgn, depth=0.12):
    """方材的斷口：木刺狀的鋸齒面（取代平整木口）。"""
    cy = sum(q[0] for q in prof) / len(prof)
    cz = sum(q[1] for q in prof) / len(prof)
    tip = Vector((x_end + sgn * depth * rng.uniform(0.6, 1.2), cy, zbase + cz))
    pts = [Vector((x_end + sgn * depth * rng.uniform(0.0, 0.7), y, zbase + z)) for (y, z) in prof]
    for k in range(len(pts)):
        poly(mb, [pts[k], pts[(k + 1) % len(pts)], tip], colfn, mat, 1, (x_end - sgn * 0.3, cy, zbase + cz))


def torii_ruin(name):
    rng = random.Random(1018)
    mb = MB()
    pc, bc, wc = ruin_paint(11), ruin_black(12), S["wood_col"](13)
    SPAN, LEAN, Z_FOOT, PR0, PR1 = S["SPAN"], S["LEAN"], S["Z_FOOT"], S["PR0"], S["PR1"]
    Y_NUKI, NUKI_HALF, Z_SHIMA, SHIMA_H, SHIMA_HALF, KASA_HALF = S["Y_NUKI"], S["NUKI_HALF"], S["Z_SHIMA"], S["SHIMA_H"], S["SHIMA_HALF"], S["KASA_HALF"]
    lift, post_x = S["lift"], S["post_x"]
    sides = 18
    zt = Z_SHIMA + 0.10
    for side in (-1, 1):
        prof = []
        for i in range(13):
            z = Z_FOOT + (zt + lift(post_x(zt, side)) - Z_FOOT) * i / 12
            prof.append((PR0 + (PR1 - PR0) * (z - Z_FOOT) / (zt - Z_FOOT), z))
        ids = []
        for i, (r, z) in enumerate(prof):
            row = []
            ccx = post_x(z, side)
            for j in range(sides):
                a = math.tau * j / sides
                rad = Vector((math.cos(a), math.sin(a), 0.0))
                dent = 1.0 - 0.06 * sstep(0.2, 0.6, fbm(Vector((math.cos(a) * 2, math.sin(a) * 2, z * 1.7)), 30 + side, 2))   # 風化凹蝕
                p = Vector((ccx + r * dent * math.cos(a), r * dent * math.sin(a), z))
                row.append(mb.v(p, rad, pc(p, rad), (j / sides * math.tau * r, z), (0.01, 0.0)))
            ids.append(row)
        for i in range(len(prof) - 1):
            for j in range(sides):
                j2 = (j + 1) % sides
                mb.quad(ids[i][j], ids[i][j2], ids[i + 1][j2], ids[i + 1][j])
        rr = PR0 + 0.028
        nprof = [(rr, Z_FOOT - 0.02), (rr, Z_FOOT + 0.46), (rr - 0.012, Z_FOOT + 0.49), (PR0 - 0.002, Z_FOOT + 0.50)]
        lathe(mb, nprof, sides, bc, 0.25, center=(post_x(Z_FOOT + 0.25, side), 0.0))
    # 貫：左段到 x＝+0.55 斷（鋸齒斷口）；右段已斷落
    np_ = [(-0.085, 0.0), (0.085, 0.0), (0.085, Y_NUKI[1] - Y_NUKI[0]), (-0.085, Y_NUKI[1] - Y_NUKI[0])]
    xb = 0.55
    xs = [-NUKI_HALF + (xb + NUKI_HALF) * i / 12 for i in range(13)]
    sag = lambda x: -0.06 * sstep(-1.0, xb, x) ** 2               # 斷端略垂
    loft_x(mb, xs, np_, lambda x: Y_NUKI[0] + sag(x), pc, 0.0, caps=False)
    poly(mb, [Vector((xs[0], y, Y_NUKI[0] + z)) for (y, z) in np_], pc, 0.0, 1, (xs[0] + 0.5, 0, Y_NUKI[0] + 0.15))
    jag_end(mb, rng, xb, np_, Y_NUKI[0] + sag(xb), pc, 0.0, 1, depth=0.16)
    # 楔：只剩左
    xw = post_x(sum(Y_NUKI) / 2, -1) - (PR1 + 0.055)
    box(mb, (xw - 0.05, -0.10, Y_NUKI[0] - 0.05), (xw + 0.02, 0.10, Y_NUKI[1] + 0.09), pc, 0.0, 0)
    # 額束：斷成殘樁；額：掉在左柱外的地上（斜靠、半埋）
    box(mb, (-0.11, -0.075, Y_NUKI[1] - 0.01), (0.11, 0.075, Y_NUKI[1] + 0.28), pc, 0.0, 0)
    jag_end(mb, rng, 0.0, [(-0.075, 0.0), (0.075, 0.0)], Y_NUKI[1] + 0.28, pc, 0.0, 1, depth=0.0)
    plaque = MB()
    hw, hh = 0.27, 0.36
    box(plaque, (-hw, -0.03, -hh), (hw, 0.0, hh), bc, 0.25, 0)
    box(plaque, (-hw + 0.055, -0.043, -hh + 0.055), (hw - 0.055, -0.025, hh - 0.055), wc, 0.5, 0)
    mb_append(mb, plaque, Matrix.Translation((-3.15, 0.55, 0.12)) @ Matrix.Rotation(math.radians(-68), 4, 'X') @ Matrix.Rotation(math.radians(24), 4, 'Z'))
    # 斷落的貫右段：躺在右柱外（|x|>2.9、離通行淨寬外），一端搭在根上
    seg = MB()
    L = NUKI_HALF - xb - 0.2
    xs2 = [-L / 2 + L * i / 10 for i in range(11)]
    loft_x(seg, xs2, np_, lambda x: 0.0, pc, 0.0, caps=False)
    poly(seg, [Vector((xs2[-1], y, z)) for (y, z) in np_], pc, 0.0, 1, (xs2[-1] - 0.5, 0, 0.15))
    jag_end(seg, rng, xs2[0], np_, 0.0, pc, 0.0, -1, depth=0.14)
    mb_append(mb, seg, Matrix.Translation((3.55, 0.75, 0.02)) @ Matrix.Rotation(math.radians(58), 4, 'Z') @ Matrix.Rotation(math.radians(-6), 4, 'Y'))
    # 島木（朱）＋笠木（黑）：右端在 x＝+2.62 斷，右半往下垂（斷裂處的木刺）
    xr = 1.0
    droop = lambda x: -0.55 * sstep(-2.6, xr, x) ** 2
    xs = [-SHIMA_HALF + (xr + SHIMA_HALF) * i / 24 for i in range(25)]
    sp = [(-0.16, 0.0), (0.16, 0.0), (0.16, SHIMA_H), (-0.16, SHIMA_H)]
    loft_x(mb, xs, sp, lambda x: Z_SHIMA + lift(x) + droop(x), pc, 0.0, end_slant=0.0, caps=False)
    poly(mb, [Vector((xs[0], y, Z_SHIMA + lift(xs[0]) + z)) for (y, z) in sp], pc, 0.0, 1, (xs[0] + 0.5, 0, Z_SHIMA + 0.3))
    jag_end(mb, rng, xr, sp, Z_SHIMA + lift(xr) + droop(xr), pc, 0.0, 1, depth=0.34)
    zk = Z_SHIMA + SHIMA_H
    kp = [(-0.17, 0.0), (0.17, 0.0), (0.215, 0.19), (0.215, 0.22), (0.19, 0.30), (0.0, 0.335), (-0.19, 0.30), (-0.215, 0.22), (-0.215, 0.19)]
    xk = 1.12
    xs = [-KASA_HALF + (xk + KASA_HALF) * i / 28 for i in range(29)]
    loft_x(mb, xs, kp, lambda x: zk + lift(x) + droop(x) * 1.15, bc, 0.25, end_slant=0.0, caps=False)
    poly(mb, [Vector((xs[0], y, zk + lift(xs[0]) + z)) for (y, z) in kp], bc, 0.25, 1, (xs[0] + 0.5, 0, zk + 0.2))
    jag_end(mb, rng, xk, kp, zk + lift(xk) + droop(xk) * 1.15, bc, 0.25, 1, depth=0.4)
    frag = MB()
    L2 = KASA_HALF - xk - 0.1
    xs3 = [-L2 / 2 + L2 * i / 14 for i in range(15)]
    loft_x(frag, xs3, kp, lambda x: lift(x + L2 / 2 + xk) - lift(xk), bc, 0.25, end_slant=0.14, caps=False)
    poly(frag, [Vector((xs3[-1] + 0.14 * z / 0.335, y, lift(KASA_HALF) - lift(xk) + z)) for (y, z) in kp], bc, 0.25, 1, (xs3[-1] - 0.5, 0, 0.2))
    jag_end(frag, rng, xs3[0], kp, 0.0, bc, 0.25, -1, depth=0.22)
    mb_append(mb, frag, Matrix.Translation((4.5, -1.05, 0.02)) @ Matrix.Rotation(math.radians(-24), 4, 'Z') @ Matrix.Rotation(math.radians(-8), 4, 'X'))
    sfrag = MB()
    L3 = SHIMA_HALF - xr - 0.3
    xs4 = [-L3 / 2 + L3 * i / 10 for i in range(11)]
    loft_x(sfrag, xs4, sp, lambda x: 0.0, pc, 0.0, caps=False)
    poly(sfrag, [Vector((xs4[-1], y, z)) for (y, z) in sp], pc, 0.0, 1, (xs4[-1] - 0.5, 0, 0.1))
    jag_end(sfrag, rng, xs4[0], sp, 0.0, pc, 0.0, -1, depth=0.18)
    mb_append(mb, sfrag, Matrix.Translation((3.7, 1.35, 0.03)) @ Matrix.Rotation(math.radians(36), 4, 'Z') @ Matrix.Rotation(math.radians(80), 4, 'X'))
    # 右柱頂：上の材が落ちて裸になった柱頭（斜めの割れ口）
    ztop = zt + lift(post_x(zt, 1))
    cxp = post_x(ztop, 1)
    ctr = mb.v((cxp + 0.04, 0.02, ztop + 0.10), (0, 0, 1), (0.46, 0.38, 0.30), (0, 0), (0.51, 0.0))
    rim = []
    for j in range(sides + 1):
        a = math.tau * j / sides
        p = Vector((cxp + PR1 * math.cos(a), PR1 * math.sin(a), ztop - 0.05 * math.cos(a) + rng.uniform(-0.03, 0.06)))
        rim.append(mb.v(p, (0, 0, 1), (0.42, 0.35, 0.28), (0, 0), (0.51, 0.0)))
    for j in range(sides):
        mb.tri(rim[j], rim[j + 1], ctr)
    ob = mb.to_object(name)
    ob.data.materials.append(placeholder_mat("S01K_paint", (0.6, 0.2, 0.12)))
    return ob


# ============================================================ 巨根／根座／連根倒木
def roots_into(mb, seed, n, R, r0, z_lift=0.16, arch=0.08, center_r=0.22, flat=False):
    rng = random.Random(seed)
    azs = sorted(rng.uniform(0, math.tau) for _ in range(n))
    for k in range(n):
        az = azs[k] + rng.uniform(-0.15, 0.15)
        main = k % 3 != 2
        ln = rng.uniform(*R) * (1.0 if main else rng.uniform(0.4, 0.65))
        nseg = 12
        pts, rad = [], []
        lat = rng.gauss(0, 0.22)
        hump = rng.uniform(0.6, 1.4) * arch
        for i in range(nseg + 1):
            t = i / nseg
            a = az + lat * math.sin(t * math.pi) + 0.18 * fbm(Vector((t * 3, k, 0)), seed, 1)
            rr = center_r + ln * t
            z = z_lift * (1 - t) ** 1.2 + hump * math.sin(min(1.0, t * 1.3) * math.pi) * (ln / 3.0) - 0.30 * sstep(0.72, 1.0, t)
            pts.append(Vector((math.cos(a) * rr, math.sin(a) * rr, 0.0 if flat else z)) if not flat else Vector((math.cos(a) * rr, math.sin(a) * rr, 0.0)))
            rad.append(r0 * (1.0 if main else 0.55) * (1 - t) ** 1.6 * rng.uniform(0.85, 1.1) + 0.035)
        tube(mb, pts, rad, 9, (1, 1, 1), (1, 1, 1), uv_scale=0.8)
        for _ in range(2 if main else 1):                       # 側根
            j = rng.randint(3, 8)
            a2 = az + rng.choice((-1, 1)) * rng.uniform(0.5, 1.0)
            p0 = pts[j]
            l2 = rng.uniform(0.6, 1.4)
            q = [p0, p0 + Vector((math.cos(a2), math.sin(a2), 0.05)) * l2 * 0.5, p0 + Vector((math.cos(a2), math.sin(a2), -0.25)) * l2]
            tube(mb, q, [rad[j] * 0.6, rad[j] * 0.4, 0.015], 6, (1, 1, 1), (1, 1, 1), uv_scale=0.8)


def snapped_trunk(mb, seed, H, r, flare=1.9, nrad=16):
    """折斷的巨木根元：根張りの板根（裾広がり）＋斜めに折れた上端（木刺）。"""
    rng = random.Random(seed)
    nz = 12
    tilt = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized()
    rings = []
    for i in range(nz + 1):
        t = i / nz
        z = -0.25 + (H + 0.25) * t
        ring = []
        for j in range(nrad + 1):
            a = math.tau * j / nrad
            but = 1.0 + (flare - 1.0) * (1 - sstep(0.0, 0.45, t)) * (0.55 + 0.45 * max(0.0, math.cos(5 * a + seed))) ** 2   # 板根
            rr = r * but * (1.0 + 0.06 * fbm(Vector((math.cos(a) * 2, math.sin(a) * 2, z)), seed, 2))
            top = (H + 0.25) * (1.0 - 0.0) if i < nz else H - 0.55 * (0.5 + 0.5 * Vector((math.cos(a), math.sin(a), 0)).dot(tilt)) - rng.uniform(0, 0.3)
            zz = z if i < nz else top
            p = Vector((math.cos(a) * rr, math.sin(a) * rr, zz))
            ring.append(mb.v(p, Vector((math.cos(a), math.sin(a), 0.0)), (1, 1, 1), (j / nrad * math.tau * r, zz), (0, 0)))
        rings.append(ring)
    for i in range(nz):
        for j in range(nrad):
            mb.quad(rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j])
    # 折れ口：中心へ落ち込む木刺
    ctr = mb.v((0, 0, H - 0.75), (0, 0, 1), (0.42, 0.32, 0.22), (0, 0), (0, 0))
    for j in range(nrad):
        mb.tri(rings[nz][j], rings[nz][j + 1], ctr)


def rootgiant(name, seed, H, r, n, R, r0):
    mb = MB()
    snapped_trunk(mb, seed, H, r)
    roots_into(mb, seed + 7, n, R, r0, z_lift=0.22, arch=0.07, center_r=r * 0.95)
    ob = mb.to_object(name, custom_normals=False)
    ob.data.shade_smooth()
    ob.data.materials.append(placeholder_mat("S01K_wood", (0.35, 0.28, 0.2)))
    return ob


def log_rootplate(name, seed=4401, L=10.0, r0=0.52, r1=0.30):
    """連根倒木：樹幹沿 +X 躺地，根盤在 −X 端垂直翻起（直徑約 3.6 m）＋根盤上的泥土塊。"""
    mb = MB()
    # 樹幹（不用 log()：要自己控制根端的位置）
    rng = random.Random(seed)
    nl, nr = 30, 16
    pts, radii = [], []
    for i in range(nl + 1):
        t = i / nl
        x = -L * 0.5 + L * t
        pts.append(Vector((x, 0.08 * math.sin(t * 2.4), r0 * 0.85 * (1 - t) + r1 * 0.85 * t + 0.10 * math.sin(t * math.pi))))
        radii.append(lerp(r0, r1, t ** 0.8) * (1 + 0.1 * fbm(Vector((x * 0.4, 0.3, 0.1)), seed, 2)))
    tube(mb, pts, radii, nr, (1, 1, 1), (1, 1, 1), uv_scale=1.0)
    # 樹梢端的斷口
    c = pts[-1]
    ctr = mb.v(c + Vector((0.12, 0, 0)), (1, 0, 0), (0.80, 0.72, 0.60), (0, 0), (0, 0))
    ring = []
    for j in range(nr + 1):
        a = math.tau * j / nr
        ring.append(mb.v(c + Vector((rng.uniform(0.0, 0.25), math.cos(a) * radii[-1], math.sin(a) * radii[-1])), (1, 0, 0), (0.62, 0.52, 0.40), (0, 0), (0, 0)))
    for j in range(nr):
        mb.tri(ring[j], ring[j + 1], ctr)
    # 根盤：根群在 YZ 平面放射（垂直），中心在樹幹根端
    plate = MB()
    roots_into(plate, seed + 3, 11, (1.3, 1.9), 0.26, z_lift=0.0, arch=0.03, center_r=0.55)
    root_end = pts[0] + Vector((-0.1, 0, 0))
    mb_append(mb, plate, Matrix.Translation((root_end.x, 0.0, 0.95)) @ Matrix.Rotation(math.radians(90), 4, 'Y'))
    # 根盤上的泥土塊（扁平的不規則圓盤，深色）
    soil = MB()
    nrr, nphi = 6, 22
    rows = []
    for i in range(nrr + 1):
        row = []
        rr = 1.45 * i / nrr
        for j in range(nphi):
            a = math.tau * j / nphi
            e = 1.0 + 0.22 * fbm(Vector((math.cos(a) * 1.5, math.sin(a) * 1.5, 0.3)), seed + 9, 2)
            th = 0.85 * (1 - (i / nrr) ** 2) + 0.10
            row.append((Vector((math.cos(a) * rr * e, math.sin(a) * rr * e, 0.0)), th))
        rows.append(row)
    ids_f, ids_b = [], []
    for i, row in enumerate(rows):
        rf, rb = [], []
        for j, (p, th) in enumerate(row):
            col = (0.40, 0.31, 0.22) if i < nrr - 1 else (0.46, 0.37, 0.26)
            rf.append(soil.v(p + Vector((0, 0, th * 0.5)), (0, 0, 1), col, (p.x, p.y), (0, 0)))
            rb.append(soil.v(p - Vector((0, 0, th * 0.5)), (0, 0, -1), col, (p.x, p.y), (0, 0)))
        ids_f.append(rf)
        ids_b.append(rb)
    for i in range(nrr):
        for j in range(nphi):
            j2 = (j + 1) % nphi
            soil.quad(ids_f[i][j], ids_f[i][j2], ids_f[i + 1][j2], ids_f[i + 1][j])
            soil.quad(ids_b[i][j], ids_b[i + 1][j], ids_b[i + 1][j2], ids_b[i][j2])
    for j in range(nphi):
        j2 = (j + 1) % nphi
        soil.quad(ids_f[nrr][j], ids_f[nrr][j2], ids_b[nrr][j2], ids_b[nrr][j])
    mb_append(mb, soil, Matrix.Translation((root_end.x - 0.35, 0.0, 0.95)) @ Matrix.Rotation(math.radians(90), 4, 'Y'))
    # 翻起後留下的坑緣土（根盤下方，埋進地面）
    ob = mb.to_object(name, custom_normals=False)
    ob.data.shade_smooth()
    ob.data.materials.append(placeholder_mat("S01K_wood", (0.35, 0.28, 0.2)))
    return ob


# ============================================================ 石造遺跡（形狀；顏色在 Godot 依地形算）
def _block_bm(size, M, seed, chip=0.025, cuts=2):
    """一塊加工石：細分的方塊＋邊角崩缺＋表面風化凹凸，回傳獨立 bmesh。"""
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    sx, sy, sz = size
    for v in bm.verts:
        p = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
        corner = (abs(v.co.x) > 0.49) + (abs(v.co.y) > 0.49) + (abs(v.co.z) > 0.49)
        n = Vector((v.co.x, v.co.y, v.co.z)).normalized()
        d = 0.35 * chip * fbm(p * 3.1, seed, 2) + (chip * 2.2 * rng.random() if corner >= 2 and rng.random() < 0.45 else 0.0)
        v.co = p - n * max(0.0, d)
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    return bm


def _break_top(bm, co, no, seed, rough=0.05):
    """斜斷：切平面上方丟掉，斷面補面後中心凹凸。"""
    res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=co, plane_no=no, clear_outer=True)
    edges = [e for e in bm.edges if e.is_boundary]
    if edges:
        f = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        for face in f["faces"]:
            r = bmesh.ops.poke(bm, faces=[face])
            for v in r["verts"]:
                v.co = v.co - Vector(no).normalized() * rough * (0.5 + fbm(v.co * 4.0, seed, 1))
        for v in bm.verts:
            if abs((v.co - Vector(co)).dot(Vector(no).normalized())) < 0.02:
                v.co += Vector((fbm(v.co * 9, seed + 1, 1), fbm(v.co * 9, seed + 2, 1), fbm(v.co * 9, seed + 3, 1))) * rough * 0.6


def _merge(dst, src):
    me = bpy.data.meshes.new("_tmp")
    src.to_mesh(me)
    src.free()
    dst.from_mesh(me)
    bpy.data.meshes.remove(me)


def ruin_pillar_a(name):
    bm = bmesh.new()
    b = _block_bm((0.46, 0.46, 2.3), Matrix.Translation((0, 0, 0.85)) @ Matrix.Rotation(math.radians(3.5), 4, 'X'), 501, chip=0.03, cuts=3)
    _break_top(b, (0, 0, 1.55), (0.45, 0.2, 1.0), 501, rough=0.07)
    _merge(bm, b)
    base = _block_bm((0.82, 0.82, 0.34), Matrix.Translation((0, 0, -0.08)), 502, chip=0.035)
    _merge(bm, base)
    chunk = _block_bm((0.28, 0.24, 0.30), Matrix.Translation((0.62, 0.38, 0.06)) @ Matrix.Rotation(math.radians(31), 4, 'Z') @ Matrix.Rotation(math.radians(18), 4, 'X'), 503, chip=0.04)
    _merge(bm, chunk)
    return rock_finish(name, bm, sharp_deg=40)


def ruin_pillar_b(name):
    bm = bmesh.new()
    a = _block_bm((1.5, 0.44, 0.44), Matrix.Translation((-0.5, 0, 0.12)) @ Matrix.Rotation(math.radians(6), 4, 'Z'), 511, chip=0.03, cuts=3)
    _break_top(a, (0.2, 0, 0), (1.0, 0.25, 0.1), 511, rough=0.06)
    _merge(bm, a)
    b = _block_bm((1.05, 0.44, 0.44), Matrix.Translation((0.95, 0.38, 0.10)) @ Matrix.Rotation(math.radians(-17), 4, 'Z') @ Matrix.Rotation(math.radians(8), 4, 'X'), 512, chip=0.03, cuts=3)
    _break_top(b, (0.5, 0.38, 0.1), (-1.0, 0.2, 0.0), 512, rough=0.06)
    _merge(bm, b)
    for k, (x, y, s) in enumerate([(0.35, -0.42, 0.22), (1.6, -0.1, 0.17), (-1.35, 0.45, 0.2)]):
        c = _block_bm((s, s * 0.9, s * 0.8), Matrix.Translation((x, y, s * 0.2)) @ Matrix.Rotation(k * 1.3, 4, 'Z'), 513 + k, chip=0.04, cuts=1)
        _merge(bm, c)
    return rock_finish(name, bm, sharp_deg=40)


def ruin_wall_a(name):
    """野面積石垣 5 m：下兩段大致整齊、上段左側殘存、右半崩落成坡。"""
    rng = random.Random(521)
    bm = bmesh.new()
    k = 0
    for row in range(4):
        x = -2.5 + rng.uniform(0, 0.2)
        z = -0.25 + row * 0.38
        while x < 2.4:
            w = rng.uniform(0.45, 0.85)
            collapse = sstep(-0.3, 1.2, x) * (row / 3.0)
            if row >= 2 and rng.random() < collapse * 1.4:
                x += w
                continue
            h = rng.uniform(0.30, 0.42)
            M = Matrix.Translation((x + w / 2, rng.uniform(-0.05, 0.05) + row * 0.04, z + h / 2)) @ Matrix.Rotation(rng.uniform(-0.06, 0.06), 4, 'Y') @ Matrix.Rotation(rng.uniform(-0.05, 0.05), 4, 'Z')
            _merge(bm, _block_bm((w * 0.96, rng.uniform(0.45, 0.6), h), M, 530 + k, chip=0.045, cuts=1))
            k += 1
            x += w
    for j in range(9):                                                     # 崩落した石：前（+Y）側の坡
        x = rng.uniform(0.0, 2.6)
        y = rng.uniform(0.45, 1.6)
        s = rng.uniform(0.28, 0.5)
        M = Matrix.Translation((x, y, s * 0.15 - 0.03 * y)) @ Matrix.Rotation(rng.uniform(0, math.tau), 4, 'Z') @ Matrix.Rotation(rng.uniform(-0.5, 0.5), 4, 'X')
        _merge(bm, _block_bm((s * 1.3, s, s * 0.75), M, 580 + j, chip=0.05, cuts=1))
    return rock_finish(name, bm, sharp_deg=38)


def ruin_steps_a(name):
    """林の奥へ上る廃石段：4 段、段ごとに傾き・ずれ・欠け；3 段目は割れて片側が落ちている。"""
    rng = random.Random(541)
    bm = bmesh.new()
    for i in range(4):
        y = i * 0.62
        z = -0.18 + i * 0.26
        for half in (-1, 1):
            if i == 2 and half > 0:
                M = Matrix.Translation((0.62, y + 0.35, z - 0.22)) @ Matrix.Rotation(0.42, 4, 'X') @ Matrix.Rotation(0.3, 4, 'Z')
            else:
                M = Matrix.Translation((half * 0.6 + rng.uniform(-0.05, 0.05), y + rng.uniform(-0.04, 0.04), z)) @ Matrix.Rotation(rng.uniform(-0.07, 0.07), 4, 'Y') @ Matrix.Rotation(rng.uniform(-0.05, 0.05), 4, 'X')
            if i == 3 and half > 0:
                continue                                                   # 最上段：右が欠落
            hgt = 0.30 + i * 0.26                                          # 各段は地面まで（浮かない）：上端 z+0.15、下端 −0.15−i·0.26
            M = M @ Matrix.Translation((0, 0, -(hgt - 0.30) * 0.5))
            _merge(bm, _block_bm((1.16, 0.58, hgt), M, 550 + i * 2 + (half > 0), chip=0.04, cuts=2))
    return rock_finish(name, bm, sharp_deg=38)


def jizo_a(name):
    """斷頭地藏：台座（二段）＋身（光背なしの丸彫り、合掌の膨らみ）＋首の折れ口；頭は台座の脇に転がる。"""
    bm = bmesh.new()
    _merge(bm, _block_bm((0.62, 0.52, 0.28), Matrix.Translation((0, 0, -0.04)), 561, chip=0.03))
    _merge(bm, _block_bm((0.46, 0.38, 0.18), Matrix.Translation((0, 0, 0.18)) @ Matrix.Rotation(0.05, 4, 'Z'), 562, chip=0.03))
    body = bmesh.new()
    prof = [(0.0, 0.27), (0.15, 0.27), (0.17, 0.42), (0.16, 0.62), (0.15, 0.80), (0.12, 0.90), (0.07, 0.95), (0.0, 0.96)]
    segs = 16
    rings = []
    for (r, z) in prof:
        rings.append([body.verts.new((r * math.cos(math.tau * j / segs), r * 0.82 * math.sin(math.tau * j / segs), z)) for j in range(segs)])
    for i in range(len(rings) - 1):
        for j in range(segs):
            j2 = (j + 1) % segs
            body.faces.new((rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]))
    for v in body.verts:
        if 0.5 < v.co.z < 0.7 and v.co.y < -0.05:
            v.co.y -= 0.035 * (1 - abs(v.co.x) / 0.15)                     # 合掌の膨らみ（前 −Y）
        v.co += Vector((fbm(v.co * 6, 563, 2), fbm(v.co * 6, 564, 2), fbm(v.co * 6, 565, 2))) * 0.012
    bmesh.ops.remove_doubles(body, verts=body.verts[:], dist=1e-5)
    bmesh.ops.holes_fill(body, edges=[e for e in body.edges if e.is_boundary], sides=0)
    bmesh.ops.transform(body, matrix=Matrix.Rotation(math.radians(5), 4, 'Y'), verts=body.verts)
    _break_top(body, (0, 0, 0.86), (0.25, -0.2, 1.0), 566, rough=0.03)
    _merge(bm, body)
    head = bmesh.new()
    bmesh.ops.create_uvsphere(head, u_segments=14, v_segments=10, radius=0.11)
    for v in head.verts:
        v.co.z *= 1.12
        v.co += Vector((fbm(v.co * 9, 567, 2), fbm(v.co * 9, 568, 2), fbm(v.co * 9, 569, 2))) * 0.01
    _break_top(head, (0, 0, -0.07), (0.1, 0.0, -1.0), 570, rough=0.02)
    bmesh.ops.transform(head, matrix=Matrix.Translation((0.48, -0.22, 0.07)) @ Matrix.Rotation(math.radians(100), 4, 'X') @ Matrix.Rotation(0.6, 4, 'Z'), verts=head.verts)
    _merge(bm, head)
    return rock_finish(name, bm, sharp_deg=50)


# ============================================================ 路緣泥濘（地被）
def mud(name, seed=591, size=(1.6, 1.1), res=(18, 13)):
    rng = random.Random(seed)
    mb = MB()
    nx, ny = res
    ids = {}
    for j in range(ny + 1):
        for i in range(nx + 1):
            x = (i / nx - 0.5) * size[0]
            y = (j / ny - 0.5) * size[1]
            rr = math.sqrt((x / (size[0] * 0.5)) ** 2 + (y / (size[1] * 0.5)) ** 2)
            e = 0.78 + 0.25 * fbm(Vector((x * 2.0, y * 2.0, 0.3)), seed, 2)
            m = 1.0 - sstep(e - 0.25, e, rr)
            wet = sstep(0.05, 0.35, fbm(Vector((x * 2.6, y * 2.6, 1.7)), seed + 5, 2)) * (1 - sstep(0.2, 0.75, rr))
            z = m * (0.006 + 0.012 * (0.5 + 0.5 * fbm(Vector((x * 8, y * 8, 0)), seed + 2, 2))) - (1 - m) * 0.02 - wet * 0.004
            col = lerp3((0.27, 0.21, 0.16), (0.33, 0.26, 0.19), 0.5 + 0.5 * fbm(Vector((x * 5, y * 5, 2)), seed + 3, 2))
            col = lerp3(col, (0.15, 0.13, 0.10), wet * 0.6)
            col = lerp3((0.34, 0.28, 0.21), col, sstep(0.0, 0.6, m))          # 邊緣淡回路土色（不是貼紙邊）                    # 水たまり：暗い
            ids[(i, j)] = (mb.v((x, y, z), (0, 0, 1), col, (0.5, 0.0), (0, 1)), m)
    for j in range(ny):
        for i in range(nx):
            q = [ids[(i, j)], ids[(i + 1, j)], ids[(i + 1, j + 1)], ids[(i, j + 1)]]
            if max(v[1] for v in q) <= 0.02:
                continue
            mb.quad(q[0][0], q[1][0], q[2][0], q[3][0])
    ob = mb.to_object(name, custom_normals=False)
    ob.data.shade_smooth()
    ob.data.materials.append(placeholder_mat("S01K_moss", (0.25, 0.2, 0.15)))
    return ob


ITEMS = [
    ("wild_torii_ruin", "arch", torii_ruin),
    ("wild_rootgiant_a", "wood", lambda n: rootgiant(n, 4201, H=3.4, r=0.9, n=8, R=(2.8, 4.2), r0=0.58)),
    ("wild_rootgiant_b", "wood", lambda n: rootgiant(n, 4211, H=2.8, r=0.72, n=7, R=(2.2, 3.5), r0=0.48)),
    ("wild_log_rootplate_a", "wood", log_rootplate),
    ("wild_ruin_pillar_a", "ruin", ruin_pillar_a),
    ("wild_ruin_pillar_b", "ruin", ruin_pillar_b),
    ("wild_ruin_wall_a", "ruin", ruin_wall_a),
    ("wild_ruin_steps_a", "ruin", ruin_steps_a),
    ("wild_jizo_a", "ruin", jizo_a),
    ("wild_mud_a", "moss", mud),
]


# ============================================================ 荒野化 R3
def root_run(name, seed, L=7.0, r0=0.30):
    """地表を這う根の列（道の縁に沿って置く）：根元（x=0）は土から太く出て、こぶ状に潜っては出る。離地 ≤ 0.6 m。"""
    rng = random.Random(seed)
    mb = MB()
    n = 26
    pts, rad = [], []
    for i in range(n + 1):
        t = i / n
        x = L * t
        y = 0.55 * math.sin(t * 5.1 + seed) * t + 0.25 * fbm(Vector((t * 3, 0.2, 0)), seed, 2)
        hump = max(0.0, math.sin(t * math.pi * 3.2 + 0.4)) * 0.32 * (1 - t) + 0.10
        z = hump - 0.16 - 0.28 * sstep(0.85, 1.0, t) - 0.12 * sstep(0.0, 0.06, 0.06 - t)
        pts.append(Vector((x, y, z)))
        rad.append(r0 * (1 - t) ** 0.9 + 0.035)
    tube(mb, pts, rad, 10, (1, 1, 1), (1, 1, 1), uv_scale=0.8)
    for k in range(4):
        j = rng.randint(4, n - 6)
        a2 = rng.choice((-1, 1)) * rng.uniform(0.5, 1.1)
        p0 = pts[j]
        l2 = rng.uniform(1.0, 2.2)
        d = Vector((math.cos(a2), math.sin(a2), 0.0))
        q = [p0, p0 + d * l2 * 0.45 + Vector((0, 0, 0.10)), p0 + d * l2 + Vector((0, 0, -0.22))]
        tube(mb, q, [rad[j] * 0.6, rad[j] * 0.42, 0.02], 7, (1, 1, 1), (1, 1, 1), uv_scale=0.8)
    ob = mb.to_object(name, custom_normals=False)
    ob.data.shade_smooth()
    ob.data.materials.append(placeholder_mat("S01K_wood", (0.35, 0.28, 0.2)))
    return ob


def gatepost(name, broken):
    """石の門柱（廃社の境界）：台石＋角柱＋笠石。broken＝1.4 m で斜めに折れ、上半と笠石が脇に落ちている。"""
    bm = bmesh.new()
    _merge(bm, _block_bm((0.86, 0.86, 0.40), Matrix.Translation((0, 0, -0.10)), 601, chip=0.04))
    H = 3.0
    col = _block_bm((0.44, 0.44, H), Matrix.Translation((0, 0, H / 2 + 0.08)) @ Matrix.Rotation(math.radians(1.5), 4, 'Y'), 602 + broken, chip=0.03, cuts=4)
    if broken:
        _break_top(col, (0, 0, 1.45), (0.5, 0.25, 1.0), 603, rough=0.07)
        _merge(bm, col)
        up = _block_bm((0.44, 0.44, 1.35), Matrix.Translation((1.05, 0.55, 0.20)) @ Matrix.Rotation(math.radians(86), 4, 'Y') @ Matrix.Rotation(0.5, 4, 'X'), 604, chip=0.04, cuts=2)
        _merge(bm, up)
        cap = _block_bm((0.95, 0.62, 0.30), Matrix.Translation((-0.85, 0.75, 0.05)) @ Matrix.Rotation(0.7, 4, 'Z') @ Matrix.Rotation(0.35, 4, 'X'), 605, chip=0.05)
        _merge(bm, cap)
    else:
        _merge(bm, col)
        cap = _block_bm((0.95, 0.62, 0.30), Matrix.Translation((0.03, 0.0, H + 0.2)) @ Matrix.Rotation(math.radians(4), 4, 'Y'), 606, chip=0.04)
        _merge(bm, cap)
    return rock_finish(name, bm, sharp_deg=40)


def rubble(name, seed=611):
    """崩れた加工石の散らばり（≤ 0.45 m、半分土に埋まる）：遺跡が森に呑まれた跡。"""
    rng = random.Random(seed)
    bm = bmesh.new()
    for k in range(9):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.0, 1.6)
        w = rng.uniform(0.35, 0.75)
        M = Matrix.Translation((math.cos(a) * r, math.sin(a) * r * 0.7, rng.uniform(-0.12, 0.02))) @ Matrix.Rotation(rng.uniform(0, math.tau), 4, 'Z') @ Matrix.Rotation(rng.uniform(-0.4, 0.4), 4, 'X')
        _merge(bm, _block_bm((w, w * rng.uniform(0.6, 0.9), w * rng.uniform(0.45, 0.65)), M, seed + k, chip=0.05, cuts=1))
    return rock_finish(name, bm, sharp_deg=40)


ITEMS += [
    ("wild_rootgiant_edge_a", "wood", lambda n: root_run(n, 701, L=7.0, r0=0.30)),
    ("wild_rootgiant_edge_b", "wood", lambda n: root_run(n, 713, L=5.2, r0=0.24)),
    ("wild_ruin_gatepost_a", "ruin", lambda n: gatepost(n, 0)),
    ("wild_ruin_gatepost_b", "ruin", lambda n: gatepost(n, 1)),
    ("wild_ruin_rubble_a", "ruin", rubble),
]


def build_all(export=True, only=None):
    c = coll()
    for ob in list(c.objects):
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
        with open(SRC_DIR + "/wild_manifest.json", "w", encoding="utf-8") as f:
            json.dump({"generator": "assets/beast_path/s01_kit/src/build_wild_kit.py", "blender": bpy.app.version_string, "assets": man}, f, ensure_ascii=False, indent=1)
        bpy.ops.wm.save_as_mainfile(filepath=SRC_DIR + "/wild_kit.blend", copy=True)
    return man


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and (o.users_collection and o.users_collection[0].name != COLL):
            bpy.data.objects.remove(o, do_unlink=True)
    only = None
    for a in argv:
        if a.startswith("--only="):
            only = a[7:].split(",")
    man = build_all(export=("--no-export" not in argv), only=only)
    for k, v in man.items():
        print("[wild] %-22s %-6s tris=%6d size=%s z=[%.2f, %.2f]" % (k, v["category"], v["tris"], v["size_m"], v["z_min"], v["z_max"]))
    for a in argv:
        if a.startswith("--preview="):
            base = a[10:]
            K["preview"](base + "_wild.png", [n for n, _, _ in ITEMS], cols=5, cam_back=44, cam_h=16, lens=35)
            print("[wild] preview ->", base)
