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
# 法線/位移貼圖做。主屋單體（hieda_main）守在 ~2,000 面。
#
# ⚠ 楓樹的樹冠**不是**橢球體。使用者看完第一版 blockout：「球體樹我覺得
# 不太有我想要的」——那兩棵巨樹是全場唯一的有機造型，卻是平滑橢球，
# 跟 make_hedge.py 已經解決過的「西瓜」是同一個病：光滑封閉曲面不管
# 怎麼上色都是球。這裡搬同一招（凹凸殼 + 上千片小葉打碎輪廓），
# 只是換成球面參數化。全場只有 2 棵，面數可以放心加密
# （單棵樹冠一叢 ~80~110 片葉，5 叢/棵）。仍然是 flat shading 的扁平
# 三角片、頂點色、無貼圖 —— 不是走寫實，是打碎輪廓（規格 §1.1）。
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
# 楓紅四階（線性）—— 火紅拱門。HI 是新葉／逆光邊緣的亮橙，
# 打碎輪廓時要靠這階跟 LT 拉開層次，不然疊起來還是一坨均勻的紅。
C_MAPLE_DK = (0.290, 0.045, 0.030)
C_MAPLE = (0.470, 0.085, 0.042)
C_MAPLE_LT = (0.640, 0.150, 0.055)
C_MAPLE_HI = (0.820, 0.320, 0.090)
MAPLE_TONES = (C_MAPLE_DK, C_MAPLE, C_MAPLE_LT, C_MAPLE_HI)


def _mix(a, b, t):
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))


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

    def tri2(self, a, b, c, col):
        """雙面三角形（葉片專用）：CULL_DISABLED 只讓背面畫得出來，
        照明用的還是原法線，背面會全黑（make_hedge.py 踩過的坑）——
        正反各給一張自己的面才是真的雙面。"""
        self.tri(a, b, c, col)
        self.tri(a, b, c, col, flip=True)

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


# ── 楓葉樹冠：不做球體 ──
#
# 使用者看完 blockout：「球體樹我覺得不太有我想要的」。他是對的，而且
# 是同一個病根，這次還是同一帖藥：**光滑的封閉曲面不管怎麼上色都是球**。
# make_hedge.py 已經驗證過「凹凸殼 + 上千片小葉打碎輪廓」能解決這件事，
# 這裡把同一招搬到球面參數（生垣是半圓柱剖面，樹冠要整顆球）。
#
# 不是往寫實走——規格 §1.1 定案是「偏卡通」，這裡的葉子仍然是
# flat shading 的扁平三角片、頂點色、無貼圖。差別只在**輪廓形狀**：
# 平滑橢球 → 凹凸的雲朵狀，邊緣是碎的不是圓的。
#
# 全場只有 2 棵巨樹（不像生垣要撒滿全村），面數可以放心加密。

def _canopy_surf(center, rx, ry, rz, seed):
    """凹凸球面：標準球面參數（u=方位角/TAU、v=極角/π）疊 4 個隨機頻率的
    正弦擾動，讓半徑忽大忽小 —— 從「撞球」變成「雲朵」。
    回傳 surf(u,v) -> (絕對座標點, 擾動前的球面法線)。用擾動前的法線
    當作葉片朝向已經夠準（凹凸只有 ±30% 半徑，方向不會偏太多），
    比對曲面做有限差分省一半功夫。"""
    rng = random.Random(seed)
    terms = [(rng.uniform(2.0, 4.0), rng.uniform(1.5, 3.5),
              rng.uniform(0.0, math.tau), rng.uniform(0.14, 0.30)) for _ in range(4)]

    def surf(u, v):
        theta = u * math.tau
        phi = v * math.pi
        nx = math.sin(phi) * math.cos(theta)
        ny = math.sin(phi) * math.sin(theta)
        nz = math.cos(phi)
        lump = 1.0
        for fu, fv, ph, amp in terms:
            lump += amp * math.sin(theta * fu + phi * fv + ph)
        lump = max(0.55, lump)
        pt = (center[0] + nx * rx * lump, center[1] + ny * ry * lump,
              center[2] + nz * rz * lump)
        return pt, (nx, ny, nz)
    return surf


def _auto_quad(bld, ctr, p0, p1, p2, p3, col):
    """繞序自動判斷：算面法線，跟「面心 - 球心」的方向比對，
    反了就翻面。凹凸球面手動推繞序很容易推錯（make_hedge.py 的鏡射
    翻面就是手推出過錯），這裡直接用幾何判斷，不用每次盯著算。"""
    e1 = (p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2])
    e2 = (p3[0] - p0[0], p3[1] - p0[1], p3[2] - p0[2])
    n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2],
         e1[0] * e2[1] - e1[1] * e2[0])
    mid = ((p0[0] + p2[0]) / 2 - ctr[0], (p0[1] + p2[1]) / 2 - ctr[1],
           (p0[2] + p2[2]) / 2 - ctr[2])
    dot = n[0] * mid[0] + n[1] * mid[1] + n[2] * mid[2]
    bld.quad(p0, p1, p2, p3, col, flip=(dot < 0))


def _canopy_hull(bld, center, surf, rows=6, cols=10):
    """粗胚殼：只負責擋視線，壓暗色，看得到它就是葉子撒得不夠
    （跟生垣的 hull 同一個角色）。"""
    for ri in range(rows):
        v0, v1 = ri / rows, (ri + 1) / rows
        for ci in range(cols):
            u0, u1 = ci / cols, (ci + 1) / cols
            p00, _ = surf(u0, v0)
            p10, _ = surf(u1, v0)
            p11, _ = surf(u1, v1)
            p01, _ = surf(u0, v1)
            col = _mix(C_MAPLE_DK, C_MAPLE, 0.15 + 0.25 * v0)
            _auto_quad(bld, center, p00, p10, p11, p01, col)


def _leaf_sprig(bld, rng, org, nrm, size, tone_t):
    """一叢 4 片短寬雙面葉，沿法線方向岔開（make_hedge.py sprig() 的
    球面版）。org 要往內縮一點讓葉根埋進殼裡，殼的接縫才不會露出來。"""
    nx, ny, nz = nrm
    ref = (0.0, 1.0, 0.0) if abs(nz) < 0.9 else (1.0, 0.0, 0.0)
    tx, ty, tz = ny * ref[2] - nz * ref[1], nz * ref[0] - nx * ref[2], nx * ref[1] - ny * ref[0]
    tl = math.sqrt(tx * tx + ty * ty + tz * tz) or 1.0
    tx, ty, tz = tx / tl, ty / tl, tz / tl
    bx, by, bz = ny * tz - nz * ty, nz * tx - nx * tz, nx * ty - ny * tx
    org = (org[0] - nx * 0.09, org[1] - ny * 0.09, org[2] - nz * 0.09)
    for k in range(4):
        a = rng.uniform(0.0, math.tau) + k * math.tau / 4.0
        spread = rng.uniform(0.65, 1.35)
        ln = size * rng.uniform(0.95, 1.65)
        wd = size * rng.uniform(0.36, 0.58)
        dx = nx + (tx * math.cos(a) + bx * math.sin(a)) * spread
        dy = ny + (ty * math.cos(a) + by * math.sin(a)) * spread
        dz = nz + (tz * math.cos(a) + bz * math.sin(a)) * spread
        dl = math.sqrt(dx * dx + dy * dy + dz * dz) or 1.0
        dx, dy, dz = dx / dl, dy / dl, dz / dl
        tip = (org[0] + dx * ln, org[1] + dy * ln, org[2] + dz * ln)
        p1 = (org[0] + tx * wd, org[1] + ty * wd, org[2] + tz * wd)
        p2 = (org[0] - tx * wd, org[1] - ty * wd, org[2] - tz * wd)
        col = _mix(C_MAPLE, C_MAPLE_LT, tone_t * rng.uniform(0.3, 1.0))
        r = rng.random()
        if r < 0.16:
            col = _mix(col, C_MAPLE_HI, rng.uniform(0.4, 0.9))       # 逆光/新葉的亮橙
        elif r < 0.30:
            col = _mix(col, C_MAPLE_DK, rng.uniform(0.3, 0.6))       # 陰影葉
        bld.tri2(p1, p2, tip, col)


def add_canopy(bld, center, rx, ry, rz, seed, n_sprigs=80, leaf_size=0.62):
    """一叢楓葉團：凹凸殼 + 撒葉，取代舊版的平滑橢球。"""
    rng = random.Random(seed)
    surf = _canopy_surf(center, rx, ry, rz, seed)
    _canopy_hull(bld, center, surf)
    for _ in range(n_sprigs):
        u, v = rng.uniform(0.0, 1.0), rng.uniform(0.04, 0.96)
        p, n = surf(u, v)
        tone_t = rng.uniform(0.15, 1.0)
        _leaf_sprig(bld, rng, p, n, leaf_size, tone_t)
    # 頂部補幾叢，避免極點附近（v 接近 0）撒得稀
    for _ in range(n_sprigs // 5):
        u = rng.uniform(0.0, 1.0)
        p, n = surf(u, rng.uniform(0.0, 0.08))
        _leaf_sprig(bld, rng, p, n, leaf_size, rng.uniform(0.6, 1.0))


def build_giant_tree(bld, x_side, y, seed):
    """框景巨樹（Feature List §2）：高 11m、幹徑 0.8m，
    枝幹 3.5m 高處向路中央橫伸 5m —— 兩棵在頭頂交織成楓紅拱門。
    ⚠ 寫進**呼叫者傳進來的 bld**，不再自己開一個新物件 —— 主幹、
    枝、樹冠現在是同一份網格的一部分，不需要再 join。"""
    rng = random.Random(seed)
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
    # 樹冠：主冠（幹頂）+ 拱門冠（枝端，覆在路上方）—— 凹凸殼+撒葉，不是球
    add_canopy(bld, (x_side + lean, y, 9.2), 2.6, 2.6, 2.6 * 0.62, seed * 3 + 1, n_sprigs=110)
    add_canopy(bld, (x_side + lean * 0.6, y + rng.uniform(-1, 1), 7.4),
               2.1, 2.1, 2.1 * 0.66, seed * 3 + 2, n_sprigs=90)
    add_canopy(bld, (x_side - sgn * 3.4, y, 6.1), 2.0, 2.0, 2.0 * 0.62, seed * 3 + 3, n_sprigs=85)
    add_canopy(bld, (x_side - sgn * 5.2, y + rng.uniform(-0.6, 0.6), 5.6),
               1.55, 1.55, 1.55 * 0.6, seed * 3 + 4, n_sprigs=65)
    add_canopy(bld, (x_side + sgn * 1.2, y - 1.6, 8.2), 1.7, 1.7, 1.7 * 0.6, seed * 3 + 5, n_sprigs=70)


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
# ⚠ 巨樹現在直接寫進同一個 bld —— 房子＋大道＋兩棵樹是**一份網格**，
# 不再需要 export_sel 裡的 bpy.ops.object.join()（少一次操作、少一個
# 出錯點），整個 blockout 場景在 Godot 端也只佔 1 個 draw call。
clear()
bld = B()
w, d, pod = build_house(bld)
sy0 = -(d / 2 + 3.2)                     # 石階前
build_avenue(bld, sy0, sy0 - 26.0, width=6.0)
build_giant_tree(bld, +4.9, sy0 - 7.5, 11)
build_giant_tree(bld, -4.9, sy0 - 8.6, 47)
export_sel([bld.build("hieda_scene")], "hieda_blockout")
print("done")
