# 稗田邸・豪邸主屋 + 庭院 Blockout（Blender headless）：
#   blender -b -P godot/assets/blender/make_hieda.py -- godot/assets/models
#   blender -b -P godot/assets/blender/preview.py -- hieda_main hieda_blockout
#
# Feature List 見 docs/hieda-estate-features.md。本輪動工的四件（使用者點名）：
#   1. 屋頂陡峭化 + 誇張軒反り（四角沿 Z 抬升 1.0m，神殿級飛翹）
#   2. 京間木柱加粗到 35~40cm
#   3. 6m 拱形鋪石大道（中央微拱、邊緣與草地交錯侵蝕）
#   4. 11m 巨樹框景 ×2（枝幹 3.5m 高處向路中央橫伸 5m，楓紅拱門）
#
# ⚠ 軒反り的技術含義：角要獨立抬升，屋面就不能是整片大 quad ——
# 入母屋改成「沿簷線細分」的掃掠網格：每圈截面是繞矩形一周的折線
# （每邊 M 段），圈與圈之間鋪 quad。角部抬升量沿邊緣按 |2t-1|³ 集中。
#
# 面數守則（Feature List §4）：瓦壟**不做實體幾何**，之後在 Godot 用
# 法線/位移貼圖做 —— 這裡守住 ~2,500 面以內。
import bpy
import math
import random
import sys
import os

OUT_DIR = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "godot/assets/models"
os.makedirs(OUT_DIR, exist_ok=True)

KEN = 1.82

C_PLASTER = (0.760, 0.740, 0.690)
C_WOOD = (0.165, 0.135, 0.110)
C_WOOD_LT = (0.240, 0.200, 0.160)
C_KAWARA = (0.310, 0.360, 0.450)
C_KAWARA_DK = (0.272, 0.318, 0.405)
C_RIDGE = (0.160, 0.190, 0.250)
C_STONE = (0.520, 0.520, 0.500)
C_STONE_DK = (0.400, 0.405, 0.395)
C_SHOJI = (0.870, 0.850, 0.780)
C_ENGAWA = (0.420, 0.330, 0.240)
C_GRASS = (0.240, 0.360, 0.150)
C_BARK = (0.200, 0.150, 0.110)
# 楓紅三階（線性）—— 火紅拱門
C_MAPLE_DK = (0.290, 0.045, 0.030)
C_MAPLE = (0.470, 0.085, 0.042)
C_MAPLE_LT = (0.640, 0.150, 0.055)


class B:
    """quad/tri 累積器（Z-up，face 色 → COLOR_0）。"""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.cols = []

    def tri(self, a, b, c, col, flip=False):
        i = len(self.verts)
        self.verts += [a, c, b] if flip else [a, b, c]
        self.faces.append((i, i + 1, i + 2))
        self.cols.append(col)

    def quad(self, a, b, c, d, col, flip=False):
        self.tri(a, b, c, col, flip)
        self.tri(a, c, d, col, flip)

    def box(self, cx, cy, cz, sx, sy, sz, col, col_top=None):
        hx, hy, hz = sx / 2, sy / 2, sz / 2
        v = [(cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
             (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
             (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
             (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz)]
        ct = col_top or col
        self.quad(v[0], v[1], v[5], v[4], col)
        self.quad(v[2], v[3], v[7], v[6], col)
        self.quad(v[1], v[2], v[6], v[5], col)
        self.quad(v[3], v[0], v[4], v[7], col)
        self.quad(v[7], v[4], v[5], v[6], ct)
        self.quad(v[0], v[3], v[2], v[1], col)

    def build(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        me.update()
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        attr = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        for fi, poly in enumerate(me.polygons):
            r, g, b2 = self.cols[fi]
            for li in poly.loop_indices:
                attr.data[li].color = (r, g, b2, 1.0)
            poly.use_smooth = False
        return ob


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


# ─────────────────────── 入母屋（細分掃掠 + 角部軒反り）───────────────────────

def _ring(s, gx, hw, hd, base_z, rise, overhang, s_hip, lift_mid, lift_corner, m):
    """一圈截面：繞矩形一周的折線（每邊 m 段，共 4m 點，CCW 起點 (-x,-y)）。
    回傳 [(x, y, z, edge_kind)]，edge_kind: 0=前後坡 1=左右（妻側）。"""
    ym = (hd + overhang) * s
    if s <= s_hip:
        xm = gx
    else:
        k = (s - s_hip) / (1.0 - s_hip)
        xm = gx + (hw + overhang - gx) * k
    zb = base_z + rise * (1.0 - s)
    # 軒反り：越靠簷（s→1）越抬，沿邊緣向角集中（|2t-1|³）
    amt = s ** 2.5

    def lift(t):
        cf = abs(2.0 * t - 1.0) ** 3
        return amt * (lift_mid + (lift_corner - lift_mid) * cf)

    pts = []
    for j in range(m):                                   # 前（-y）：-x → +x
        t = j / m
        pts.append((-xm + 2 * xm * t, -ym, zb + lift(t), 0))
    for j in range(m):                                   # 右（+x）：-y → +y
        t = j / m
        pts.append((xm, -ym + 2 * ym * t, zb + lift(t), 1))
    for j in range(m):                                   # 後（+y）：+x → -x
        t = j / m
        pts.append((xm - 2 * xm * t, ym, zb + lift(t), 0))
    for j in range(m):                                   # 左（-x）：+y → -y
        t = j / m
        pts.append((-xm, ym - 2 * ym * t, zb + lift(t), 1))
    return pts


def irimoya(bld, w, d, base_z, rise, gable_frac=0.42, overhang=2.0,
            lift_mid=0.22, lift_corner=1.0, steps=10, m=6):
    """入母屋一體網格。妻壁（上段左右面）直接長在掃掠裡（漆喰色），
    軒反り由 _ring 的 lift() 給 —— 角部在簷口抬滿 lift_corner。"""
    hw, hd = w / 2, d / 2
    gx = w * gable_frac / 2
    s_hip = 0.42
    thick = 0.24
    rings = []
    for i in range(steps + 1):
        s = i / steps
        rings.append(_ring(s, gx, hw, hd, base_z, rise, overhang,
                           s_hip, lift_mid, lift_corner, m))
    n = 4 * m
    for i in range(steps):
        r0 = rings[i]                                    # 靠脊（高）
        r1 = rings[i + 1]                                # 靠簷（低）
        shade = C_KAWARA if i % 2 == 0 else C_KAWARA_DK
        s_mid = (i + 0.5) / steps
        for j in range(n):
            j2 = (j + 1) % n
            kind = r1[j][3]
            col = shade
            if kind == 1 and s_mid < s_hip:
                col = C_PLASTER                          # 上段妻壁：漆喰
            a = (r1[j][0], r1[j][1], r1[j][2])
            b2 = (r1[j2][0], r1[j2][1], r1[j2][2])
            c = (r0[j2][0], r0[j2][1], r0[j2][2])
            dd = (r0[j][0], r0[j][1], r0[j][2])
            # 退化段（脊上、妻側零寬）跳過
            if abs(a[0] - b2[0]) < 1e-5 and abs(a[1] - b2[1]) < 1e-5:
                continue
            bld.quad(a, b2, c, dd, col)
    # 簷口厚度（一圈側緣）
    re = rings[steps]
    for j in range(n):
        j2 = (j + 1) % n
        a = (re[j][0], re[j][1], re[j][2])
        b2 = (re[j2][0], re[j2][1], re[j2][2])
        bld.quad((a[0], a[1], a[2] - thick), (b2[0], b2[1], b2[2] - thick),
                 b2, a, C_KAWARA_DK)
    # 大棟 + 鬼瓦
    zt = base_z + rise
    bld.box(0, 0, zt + 0.10, gx * 2 + 0.6, 0.55, 0.36, C_RIDGE)
    for sx in (1, -1):
        bld.box(sx * (gx + 0.3), 0, zt + 0.16, 0.5, 0.68, 0.55, C_RIDGE)
    # 破風板（妻壁邊框，沿上段斜邊）
    r_hipi = int(s_hip * steps)
    y_h = rings[r_hipi][m][1] if r_hipi < len(rings) else hd * s_hip
    z_h = base_z + rise * (1.0 - s_hip)
    for sx in (1, -1):
        for sy in (1, -1):
            bld.quad((sx * (gx + 0.02), sy * abs(y_h), z_h),
                     (sx * (gx + 0.02), 0, zt),
                     (sx * (gx + 0.02), 0, zt - 0.20),
                     (sx * (gx + 0.02), sy * abs(y_h), z_h - 0.20),
                     C_WOOD, flip=(sx > 0) != (sy > 0))


def skirt_ring(bld, xi, yi, zi, xo, yo, zo, lift_corner=0.45, m=5,
               col=C_KAWARA, col_edge=C_KAWARA_DK):
    """裳階／腰簷：內外兩圈細分折線，四角斜接 + 角部微翹。"""
    def ring(xm, ym, z, do_lift):
        pts = []
        for j in range(m):
            t = j / m
            lf = (abs(2 * t - 1.0) ** 3) * lift_corner if do_lift else 0.0
            pts.append((-xm + 2 * xm * t, -ym, z + lf))
        for j in range(m):
            t = j / m
            lf = (abs(2 * t - 1.0) ** 3) * lift_corner if do_lift else 0.0
            pts.append((xm, -ym + 2 * ym * t, z + lf))
        for j in range(m):
            t = j / m
            lf = (abs(2 * t - 1.0) ** 3) * lift_corner if do_lift else 0.0
            pts.append((xm - 2 * xm * t, ym, z + lf))
        for j in range(m):
            t = j / m
            lf = (abs(2 * t - 1.0) ** 3) * lift_corner if do_lift else 0.0
            pts.append((-xm, ym - 2 * ym * t, z + lf))
        return pts

    ri = ring(xi, yi, zi, False)
    ro = ring(xo, yo, zo, True)
    n = 4 * m
    for j in range(n):
        j2 = (j + 1) % n
        bld.quad(ro[j], ro[j2], ri[j2], ri[j], col)
        bld.quad((ro[j][0], ro[j][1], ro[j][2] - 0.16),
                 (ro[j2][0], ro[j2][1], ro[j2][2] - 0.16),
                 ro[j2], ro[j], col_edge)


# ─────────────────────── 主屋 ───────────────────────

def build_house(bld):
    w = 14 * KEN
    d = 8 * KEN
    f1 = 3.9
    f2 = 3.1
    pod = 0.85
    # 基壇 + 石階
    bld.box(0, 0, pod / 2, w + 2.2, d + 2.2, pod, C_STONE)
    for i in range(5):
        t = (i + 0.5) / 5
        bld.box(0, -(d / 2 + 1.1) - (1 - t) * 1.8, pod * t - 0.10,
                4.4, 0.55, 0.22, C_ENGAWA if i % 2 == 0 else C_WOOD_LT)
    z0 = pod
    bld.box(0, 0, z0 + f1 / 2, w, d, f1, C_PLASTER)
    bld.box(0, 0, z0 + 0.55, w + 0.08, d + 0.08, 1.1, C_WOOD_LT)
    # 柱（Feature List：加粗到 35~40cm；角柱 40）
    n_post = 15
    for i in range(n_post):
        px = -w / 2 + i * (w / (n_post - 1))
        fat = 0.40 if i in (0, n_post - 1) else 0.36
        for sy in (1, -1):
            bld.box(px, sy * (d / 2 + 0.10), z0 + f1 / 2, fat, 0.26, f1, C_WOOD)
    for sy in (1, -1):
        bld.box(0, sy * (d / 2 + 0.06), z0 + 0.10, w + 0.3, 0.20, 0.20, C_WOOD)
        bld.box(0, sy * (d / 2 + 0.06), z0 + f1 - 0.12, w + 0.3, 0.20, 0.24, C_WOOD)
        bld.box(0, sy * (d / 2 + 0.06), z0 + 2.30, w + 0.3, 0.16, 0.16, C_WOOD)
    for i in range(n_post - 1):
        px = -w / 2 + (i + 0.5) * (w / (n_post - 1))
        bld.box(px, -(d / 2 + 0.02), z0 + 1.75, KEN * 0.74, 0.06, 1.15, C_SHOJI)
    # 縁側 + 高欄
    for sy in (1, -1):
        bld.box(0, sy * (d / 2 + 1.05), z0 + 0.12, w + 1.4, 2.0, 0.22, C_ENGAWA)
        bld.box(0, sy * (d / 2 + 1.95), z0 + 0.95, w + 1.4, 0.11, 0.11, C_WOOD)
        for i in range(13):
            px = -w / 2 + i * (w / 12)
            bld.box(px, sy * (d / 2 + 1.95), z0 + 0.5, 0.09, 0.09, 0.9, C_WOOD)
    # 裳階（角部微翹跟主屋頂呼應）
    z1 = z0 + f1
    w2, d2 = w - 3.6, d - 2.6
    skirt_ring(bld, w2 / 2 - 0.4, d2 / 2 - 0.4, z1 + 0.62,
               w / 2 + 1.7, d / 2 + 1.7, z1 - 0.05, lift_corner=0.45)
    # 二層
    bld.box(0, 0, z1 + f2 / 2, w2, d2, f2, C_PLASTER)
    for sy in (1, -1):
        bld.box(0, sy * (d2 / 2 + 0.03), z1 + f2 - 1.35, w2 * 0.86, 0.08, 1.05, C_WOOD)
        bld.box(0, sy * (d2 / 2 + 0.06), z1 + 0.10, w2 + 0.2, 0.18, 0.18, C_WOOD)
        bld.box(0, sy * (d2 / 2 + 0.06), z1 + f2 - 0.10, w2 + 0.2, 0.18, 0.18, C_WOOD)
    for i in range(9):
        px = -w2 / 2 + i * (w2 / 8)
        for sy in (1, -1):
            bld.box(px, sy * (d2 / 2 + 0.05), z1 + f2 / 2, 0.30, 0.18, f2, C_WOOD)
    # 入母屋：更陡（rise 3.6 → 4.9）+ 角部軒反り 1.0m（Feature List §1）
    irimoya(bld, w2, d2, z1 + f2, rise=4.9, gable_frac=0.40, overhang=2.2,
            lift_mid=0.22, lift_corner=1.0)
    return w, d, pod


# ─────────────────────── 庭院 Blockout ───────────────────────

def build_avenue(bld, y0, y1, width=6.0, rng=None):
    """拱形鋪石大道（Feature List §2）：中央微拱 + 邊緣與草地交錯侵蝕。
    y0（靠石階）→ y1（遠端），寬 width。"""
    rng = rng or random.Random(7)
    rows = int(abs(y1 - y0) / 2.2)
    lanes = 6
    hw = width / 2
    for r in range(rows):
        ya = y0 + (y1 - y0) * r / rows
        yb = y0 + (y1 - y0) * (r + 1) / rows
        # 邊緣侵蝕：這一排的左右邊界各自抖動
        el = -hw + rng.uniform(-0.45, 0.35)
        er = hw + rng.uniform(-0.35, 0.45)
        for c in range(lanes):
            xa = el + (er - el) * c / lanes
            xb = el + (er - el) * (c + 1) / lanes
            # 拱形：中央 +0.18、邊緣歸零（拋物線）
            def crown(x):
                u = (x - (el + er) / 2) / ((er - el) / 2)
                return 0.18 * max(0.0, 1.0 - u * u)
            sh = rng.uniform(-0.06, 0.06)
            col = (C_STONE[0] + sh, C_STONE[1] + sh, C_STONE[2] + sh)
            # 邊緣車道偶爾換成草色 —— 「與草地不規則交錯」
            if c in (0, lanes - 1) and rng.random() < 0.30:
                col = C_GRASS
            ga = 0.05
            bld.quad((xa, ya, crown(xa) + ga), (xb, ya, crown(xb) + ga),
                     (xb, yb, crown(xb) + ga), (xa, yb, crown(xa) + ga), col)
        # 排與排之間的目地（細縫陰影）
        bld.box((el + er) / 2, yb, 0.045, er - el, 0.10, 0.05, C_STONE_DK)


def _cluster(bld_obj_list, center, radius, squash, tier, seed):
    """楓葉團：低細分 icosphere（借 make_trees 的做法）。"""
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=center)
    ob = bpy.context.active_object
    ob.scale = (1 + rng.uniform(-0.1, 0.1), 1 + rng.uniform(-0.1, 0.1), squash)
    bpy.ops.object.transform_apply(scale=True)
    me = ob.data
    attr = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    cz, rad = center[2], radius * squash
    for poly in me.polygons:
        vz = sum(me.vertices[me.loops[li].vertex_index].co.z for li in poly.loop_indices) / len(poly.loop_indices)
        t = max(0.0, min(1.0, (vz - (cz - rad)) / (2 * rad)))
        base = C_MAPLE_DK if t < 0.35 else (C_MAPLE if t < 0.75 else C_MAPLE_LT)
        k = 0.8 + 0.4 * t
        for li in poly.loop_indices:
            attr.data[li].color = (min(1, base[0] * k), min(1, base[1] * k),
                                   min(1, base[2] * k), 1.0)
        poly.use_smooth = False
    bld_obj_list.append(ob)


def build_giant_tree(objs, x_side, y, seed):
    """框景巨樹（Feature List §2）：高 11m、幹徑 0.8m，
    枝幹 3.5m 高處向路中央橫伸 5m —— 兩棵在頭頂交織成楓紅拱門。"""
    import mathutils
    rng = random.Random(seed)
    bld = B()
    sgn = 1 if x_side > 0 else -1
    # 主幹（八角柱疊兩段，微傾向路心）
    lean = -sgn * 0.35
    for seg, (r0, r1, z0, z1) in enumerate([(0.42, 0.34, 0.0, 4.0), (0.34, 0.22, 4.0, 8.0)]):
        n = 8
        for k in range(n):
            a0 = k / n * math.tau
            a1 = (k + 1) / n * math.tau
            lx0 = lean * (z0 / 8.0)
            lx1 = lean * (z1 / 8.0)
            bld.quad((x_side + lx0 + math.cos(a0) * r0, y + math.sin(a0) * r0, z0),
                     (x_side + lx0 + math.cos(a1) * r0, y + math.sin(a1) * r0, z0),
                     (x_side + lx1 + math.cos(a1) * r1, y + math.sin(a1) * r1, z1),
                     (x_side + lx1 + math.cos(a0) * r1, y + math.sin(a0) * r1, z1),
                     C_BARK)
    # 拱門主枝：3.5m 高向路中央橫伸 5m（微上揚），八角錐掃掠
    bx0, bz0 = x_side + lean * (3.5 / 8.0), 3.5
    bx1, bz1 = x_side - sgn * 5.0, 5.1
    n = 7
    for k in range(n):
        a0 = k / n * math.tau
        a1 = (k + 1) / n * math.tau
        r0, r1 = 0.26, 0.12
        # 枝的截面在 y-z 平面
        def p(ax, r, ang):
            return (ax[0], y + math.sin(ang) * r, ax[1] + math.cos(ang) * r)
        for t0, t1 in [(0.0, 0.5), (0.5, 1.0)]:
            ax0 = (bx0 + (bx1 - bx0) * t0, bz0 + (bz1 - bz0) * t0 + 0.5 * t0 * (1 - t0))
            ax1 = (bx0 + (bx1 - bx0) * t1, bz0 + (bz1 - bz0) * t1 + 0.5 * t1 * (1 - t1))
            rr0 = r0 + (r1 - r0) * t0
            rr1 = r0 + (r1 - r0) * t1
            bld.quad(p(ax0, rr0, a0), p(ax0, rr0, a1), p(ax1, rr1, a1), p(ax1, rr1, a0),
                     C_BARK, flip=(sgn < 0))
    # 側枝兩根（往外、往後）
    ob = bld.build("tree_trunk_%d" % seed)
    objs.append(ob)
    # 樹冠：主冠（幹頂）+ 拱門冠（枝端，覆在路上方）
    _cluster(objs, (x_side + lean, y, 9.2), 2.6, 0.62, 0, seed * 3 + 1)
    _cluster(objs, (x_side + lean * 0.6, y + rng.uniform(-1, 1), 7.4), 2.1, 0.66, 1, seed * 3 + 2)
    _cluster(objs, (x_side - sgn * 3.4, y, 6.1), 2.0, 0.62, 1, seed * 3 + 3)
    _cluster(objs, (x_side - sgn * 5.2, y + rng.uniform(-0.6, 0.6), 5.6), 1.55, 0.6, 2, seed * 3 + 4)
    _cluster(objs, (x_side + sgn * 1.2, y - 1.6, 8.2), 1.7, 0.6, 1, seed * 3 + 5)


def export_sel(objs, name):
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
    n = len(ob.data.polygons)
    print("exported %s（%d 面）" % (path, n))


# ── 產出 1：主屋單體 ──
clear()
bld = B()
build_house(bld)
export_sel([bld.build("hieda_main")], "hieda_main")

# ── 產出 2：Blockout（主屋 + 大道 + 巨樹框景）──
clear()
bld = B()
w, d, pod = build_house(bld)
sy0 = -(d / 2 + 3.2)                     # 石階前
build_avenue(bld, sy0, sy0 - 26.0, width=6.0)
scene_objs = [bld.build("hieda_scene")]
build_giant_tree(scene_objs, +4.9, sy0 - 7.5, 11)
build_giant_tree(scene_objs, -4.9, sy0 - 8.6, 47)
export_sel(scene_objs, "hieda_blockout")
print("done")
