# 稗田邸・豪邸主屋 + 庭院 Blockout（Blender headless）：
#   blender -b -P godot/assets/blender/make_hieda.py -- godot/assets/models
#   blender -b -P godot/assets/blender/preview.py -- hieda_main hieda_blockout
#
# Feature List 見 docs/hieda-estate-features.md。已完成：
#   1. 屋頂陡峭化 + 誇張軒反り（四角沿 Z 抬升 1.0m，神殿級飛翹）
#   2. 京間木柱加粗到 35~40cm
#   3. 6m 拱形鋪石大道（中央微拱、邊緣與草地交錯侵蝕）
#   4. 11m 巨樹框景 ×2（枝幹 3.5m 高處向路中央橫伸 5m，楓紅拱門）
#   5. 腰簷（錣葺き）—— 主屋頂／裳階／腰簷三層剪影
#   6. 唐破風玄関 + 五段階梯（本輪，見下方 build_karahafu 的長註解）
#
# ⚠ 軒反り的技術含義：角要獨立抬升，屋面就不能是整片大 quad ——
# 入母屋改成「沿簷線細分」的掃掠網格：每圈截面是繞矩形一周的折線
# （每邊 M 段），圈與圈之間鋪 quad。角部抬升量沿邊緣按 |2t-1|³ 集中。
#
# 面數守則（Feature List §4）：瓦壟**不做實體幾何**，之後在 Godot 用
# 法線/位移貼圖做。主屋單體（hieda_main）原本守在 ~2,000 面，這輪加唐破風
# 玄関之後是 **2,532 面**。多出來的 500 面幾乎全在那條 S 曲線的橫向細分
# （nt=18）跟破風板上 —— 那是這個玄関唯一的賣點，砍下去就只剩一塊雨遮。
# 已經先把能省的省掉了：屋面深度方向是直紋曲面所以 nd 只給 2、階梯改成
# 開放殼（30→20 quad）、被妻壁擋住的蟇股整組拿掉。仍然是一份 mesh、
# 一次 draw call。
#
# ⚠ 楓樹的樹冠**不是**橢球體。使用者看完第一版 blockout：「球體樹我覺得
# 不太有我想要的」——那兩棵巨樹是全場唯一的有機造型，卻是平滑橢球，
# 跟 make_hedge.py 已經解決過的「西瓜」是同一個病：光滑封閉曲面不管
# 怎麼上色都是球。這裡搬同一招（凹凸殼 + 上千片小葉打碎輪廓），
# 只是換成球面參數化。全場只有 2 棵，面數可以放心加密
# （單棵樹冠一叢 ~80~110 片葉，5 叢/棵）。仍然是 flat shading 的扁平
# 三角片、頂點色、無貼圖 —— 不是走寫實，是打碎輪廓（規格 §1.1）。
import bpy
import json
import math
import random
import sys
import os

OUT_DIR = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "godot/assets/models"
os.makedirs(OUT_DIR, exist_ok=True)

KEN = 1.82
# 後院小徑終點（Blender Z-up）。木戶、樹叢、以及匯出給 Godot 的觸發區座標
# 都從這裡取 —— 分開寫死兩份的話，之後挪動木戶觸發區就會留在原地。
PATH_END = (37.0, 68.0)
PATH_END_ANG = math.radians(28.0)
# 玄関開口半寬。腰簷、正面高欄、格子窗全部照這個讓路 —— 唐破風、階梯、
# 大扉、簷的缺口是同一件事，散在四處各寫一個數字遲早會對不齊。
GATE_HW = 2.9

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
# 犬走り（牆腳碎石帶）兩階：貼牆一條窄的**暗帶**（假的接觸陰影／AO），
# 外側一條寬的土色帶往草地過渡。第一版兩條都調得太亮（0.35/0.47），
# 跟石垣的 0.52 差不多，整片牆腳糊成一坨白 —— 過渡帶要看得出來才有用，
# 關鍵是那條暗帶：物件「坐」在地上而不是「放」在地上，讀的就是接觸陰影。
# 暗帶必須比**草地**還暗才讀得成接觸陰影。量過渲染值：草地 albedo 0.22
# 出來是 130，第一版暗帶給 0.285 出來是 144 —— 比草還亮，於是整條讀成
# 「一道混凝土路緣」，反而多加了一條硬邊，跟要解的問題正好相反。
C_GRAVEL_DK = (0.150, 0.150, 0.135)
C_GRAVEL = (0.425, 0.420, 0.370)
# ── 後院（back garden）──
# 水：由岸到心的深度漸層 + 一個「鏡面」色。鏡面偏天空的冷灰藍，是拿來
# 讀成「這片在映屋頂」的，不是真的反射（blockout 只有頂點色）。
C_WATER_SHAL = (0.255, 0.400, 0.300)
C_WATER_DEEP = (0.045, 0.105, 0.140)
C_WATER_MIRROR = (0.430, 0.505, 0.575)
C_WATER_MIRROR_DK = (0.175, 0.220, 0.280)
C_WATER_SHEEN = (0.760, 0.820, 0.880)      # 天光柔斑（假的 specular）
C_WATER_EDGE = (0.395, 0.440, 0.395)       # 岸際：水與石之間的過渡色
C_MUD = (0.300, 0.255, 0.185)
C_EARTH = (0.200, 0.160, 0.115)
# 枯山水的白砂：兩階明度交替就是耙紋
C_SAND = (0.700, 0.685, 0.620)
C_SAND_DK = (0.545, 0.532, 0.478)
C_ROCK_DK = (0.330, 0.325, 0.310)
C_MOSS = (0.185, 0.310, 0.130)
C_MOSS_LT = (0.290, 0.415, 0.175)
# 靈氣裂縫：全場最亮的顏色，Godot 端要拿這個色域驅動 emissive
# 兩階都把紅通道推到 0.92 以上 —— 全場其他顏色最高只到 C_SHOJI 的 0.87，
# 所以「R > 0.92」是一條乾淨的判別線，Godot 端可以直接用它挑出要發光的面。
C_GLOW = (1.000, 0.895, 0.660)
C_GLOW_DIM = (0.945, 0.700, 0.360)
# 菜園
C_SOIL = (0.195, 0.140, 0.092)
C_STRAW = (0.620, 0.550, 0.360)
C_LEAF = (0.235, 0.410, 0.150)
C_LEAF_LT = (0.390, 0.545, 0.205)
# ── 兩套植栽，刻意分開 ──
# 灌木叢（路邊裝飾）：亮而新鮮的綠。
# 生垣（界線）：深、帶藍灰。一眼就分得出「界線」與「點綴」。
#
# ⚠ 兩者的**殼**都必須很暗。make_hedge.py 的 HULL_DARK 是 0.020；
# 我第一版灌木叢的殼用 0.115，亮了五倍 —— 殼因此變成主視覺，葉子只像
# 插在上面的刺，於是不管怎麼捏形狀都是一顆西瓜。殼的工作只是擋視線，
# 看得到殼就是葉子撒得不夠。
C_BUSH_HULL = (0.030, 0.052, 0.024)
C_BUSH_DEEP = (0.150, 0.265, 0.115)
C_BUSH_MID = (0.265, 0.400, 0.165)
C_BUSH_LIT = (0.405, 0.540, 0.225)
C_BUSH_STEM = (0.215, 0.170, 0.120)
C_HG_HULL = (0.022, 0.040, 0.032)
C_HG_DEEP = (0.070, 0.125, 0.100)
C_HG_MID = (0.128, 0.208, 0.168)
C_HG_LIT = (0.205, 0.295, 0.238)
C_BARK = (0.200, 0.150, 0.110)
# 樹皮：主幹深、末梢略淺。C_BARK 原本渲染出來偏灰白，像水泥柱
C_TRUNK = (0.115, 0.086, 0.062)
C_TWIG = (0.175, 0.132, 0.094)
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

    def tri_v(self, a, b, c, ca, cb, cc, flip=False):
        """每個角各自一個顏色（build() 會偵測 cols[fi] 是不是巢狀）。

        為什麼需要它：原本一張面只能給一個色，畫漸層就只能靠「一圈一個色」
        堆出來 —— 六圈就是六條等高線，水面看起來是地形圖不是水。
        角色可以在面內線性內插，色階才是連續的。"""
        i = len(self.verts)
        if flip:
            self.verts += [a, c, b]
            self.cols.append((ca, cc, cb))
        else:
            self.verts += [a, b, c]
            self.cols.append((ca, cb, cc))
        self.faces.append((i, i + 1, i + 2))

    def quad_v(self, a, b, c, d, ca, cb, cc, cd, flip=False):
        self.tri_v(a, b, c, ca, cb, cc, flip)
        self.tri_v(a, c, d, ca, cc, cd, flip)

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
            c = self.cols[fi]
            if isinstance(c[0], (tuple, list)):          # 每角一色（tri_v）
                for k, li in enumerate(poly.loop_indices):
                    r, g, b2 = c[k]
                    attr.data[li].color = (r, g, b2, 1.0)
            else:                                        # 整面一色
                r, g, b2 = c
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
               col=C_KAWARA, col_edge=C_KAWARA_DK, gap_hw=0.0):
    """裳階／腰簷：內外兩圈細分折線，四角斜接 + 角部微翹。

    gap_hw > 0 時在**正面（-y 邊）**|x| < gap_hw 的區段整段不畫 ——
    唐破風玄関要從這裡穿出去。簷不讓路的話，一條 25m 的水平簷會直接
    從玄関屋頂中間橫切過去，唐破風就變成貼在牆上的雨遮而不是玄関。
    切口露出來的斷面不補（正上方就是唐破風屋面，看不到）。
    要切得準，m 要開大：預設 m=5 一段就 5.5m 寬，根本切不出 6m 的口。"""
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
        # j < m 才是正面那條邊（ring() 的第一段），玄関開口只在正面讓路
        if gap_hw > 0.0 and j < m and abs(ro[j][0] + ro[j2][0]) * 0.5 < gap_hw:
            continue
        bld.quad(ro[j], ro[j2], ri[j2], ri[j], col)
        bld.quad((ro[j][0], ro[j][1], ro[j][2] - 0.16),
                 (ro[j2][0], ro[j2][1], ro[j2][2] - 0.16),
                 ro[j2], ro[j], col_edge)


# ─────────────────────── 唐破風玄関（向唐破風）───────────────────────
#
# Feature List §1 建築件的最後一塊，也是整張清單技術上最麻煩的一件。
#
# 破風的輪廓是一條 **S 曲線**：中央上凸（起り）→ 兩翼下凹（反り）→
# 末端再往上勾一下（簷角）。三段曲率、兩個反曲點。硬湊控制點會湊到天亮，
# 但找對函數就只是一行：
#
#   **sin²(sπ/2) 天生就是這條 S。** 它在 s=0 附近二階導為正、s=1 附近為負，
#   反曲點正正好落在 s=0.5。拿它當「從棟往下掉多少」，中央自然是凸的、
#   外側自然是凹的，而且只用 drop 一個參數就控制整條曲線的深度。
#
#   末端那一勾另外加 s⁶。六次方在 s<0.75 幾乎是 0，只有最外側十幾 % 才
#   抬得動 —— 剛好是簷角的位置，不會把中段辛苦做出來的凸給壓平。
#
# 屋面**不是**把這條曲線沿 y 平移拉出去（那是圓筒，看起來像水管）：
# 從牆面掃到簷口的過程中半寬 3.35→3.85 外張、棟高 4.45→3.75 下傾，
# **每一圈都是一條不同的 S 曲線**，圈與圈之間鋪 quad。這就是「曲面斷面
# ＋寬度方向切妻疊合」—— 整片屋面沒有任何一塊 quad 是平的。
#
# 高度是被上下夾死的，不能亂調：上面 y=-8.98 處有裳階的簷口壓著
# （底 4.54），下面有腰簷（頂 3.36）。棟頂 4.45→3.75 這組數字是量出來
# 剛好穿過中間的，動 z_back/z_tip 之前先重算這兩個夾擠點。

def _bar_y(bld, x, hx, hz, y0, z0, y1, z1, col):
    """沿 y 掃的矩形斷面棒，**可以斜** —— box() 只能軸對齊，做不出跟著
    屋面一起下傾的棟。繞序交給 _auto_quad 用幾何判（手推六個面的繞序
    是純粹在給自己找錯）。"""
    ctr = (x, (y0 + y1) / 2, (z0 + z1) / 2)

    def sec(y, z):
        return [(x - hx, y, z - hz), (x + hx, y, z - hz),
                (x + hx, y, z + hz), (x - hx, y, z + hz)]

    a, b = sec(y0, z0), sec(y1, z1)
    for k in range(4):
        k2 = (k + 1) % 4
        _auto_quad(bld, ctr, a[k], a[k2], b[k2], b[k], col)
    _auto_quad(bld, ctr, a[0], a[1], a[2], a[3], col)
    _auto_quad(bld, ctr, b[0], b[1], b[2], b[3], col)


def _kara_z(t, peak, drop, flare):
    """唐破風斷面。t ∈ [-1,1]（0=棟、±1=簷角），回傳絕對高度。"""
    s = min(1.0, abs(t))
    return peak - drop * math.sin(s * math.pi / 2) ** 2 + flare * s ** 6


def build_karahafu(bld, y_wall, y_deck, deck_z, gate_hw):
    """向唐破風玄関：屋面 + 破風板 + 兎毛通 + 向拝柱 + 虹樑 + 五段階梯。

    y_wall  正面外牆平面（-y 側）
    y_deck  縁側外緣（階梯從這裡往外落）
    deck_z  縁側面高（階梯要爬到這個高度）
    gate_hw 玄関開口半寬（腰簷、高欄、格子窗都照這個讓路）
    """
    y_back, y_tip, y_post = y_wall + 0.13, -12.35, -11.90
    z_back, z_tip = 4.45, 3.75
    hw_back, hw_tip = 3.35, 3.85
    drop, flare = 1.25, 0.55
    # nd 只要 2：hw_at/pk_at 都是 u 的一次式，_kara_z 的 v 項又跟 u 無關 ——
    # 這片屋面在深度方向是**直紋曲面**，切再多刀也是同一個形狀，純浪費面。
    # 曲率全部集中在 nt（橫向），那才是 S 曲線所在、也才是輪廓所在。
    nd, nt = 2, 18
    bd_h, bd_t, sof = 0.46, 0.20, 0.22          # 破風板垂高／厚度、屋面下皮

    def hw_at(u):
        return hw_back + (hw_tip - hw_back) * u

    def pk_at(u):
        return z_back + (z_tip - z_back) * u

    def pt(i, j):
        u = i / nd                              # 0=牆 1=簷口
        v = j / nt * 2.0 - 1.0                  # -1=左簷角 0=棟 +1=右簷角
        return (v * hw_at(u), y_back + (y_tip - y_back) * u,
                _kara_z(v, pk_at(u), drop, flare))

    # ── 屋面（上皮）+ 下皮（軒裏）──
    # 下皮不是可有可無：玩家站在階梯上抬頭第一眼就是這一面，零厚度的
    # 單面屋頂會被背面剔除直接看穿到天空去。
    for i in range(nd):
        for j in range(nt):
            a, b2, c, dd = pt(i, j), pt(i, j + 1), pt(i + 1, j + 1), pt(i + 1, j)
            bld.quad(a, b2, c, dd, C_KAWARA if j % 2 == 0 else C_KAWARA_DK, flip=True)
            bld.quad((a[0], a[1], a[2] - sof), (b2[0], b2[1], b2[2] - sof),
                     (c[0], c[1], c[2] - sof), (dd[0], dd[1], dd[2] - sof), C_WOOD_LT)
    for i in range(nd):                         # 左右簷口的厚度側面
        for j in (0, nt):
            a, b2 = pt(i, j), pt(i + 1, j)
            _auto_quad(bld, (0.0, (y_back + y_tip) / 2, (z_back + z_tip) / 2 - 1.0),
                       a, b2, (b2[0], b2[1], b2[2] - sof), (a[0], a[1], a[2] - sof),
                       C_KAWARA_DK)
    # 棟收在破風板後面 0.6m：頂到簷口的話，正面看就是破風尖上頂著一顆
    # 方盒子（棟的端面），唐破風最好看的那個頂點會被自己的棟砸爛。
    y_rg = y_tip + 0.60
    _bar_y(bld, 0.0, 0.26, 0.11, y_back, z_back + 0.06,
           y_rg, pk_at((y_rg - y_back) / (y_tip - y_back)) + 0.06, C_RIDGE)

    # ── 破風板：沿簷口那條 S 曲線垂下的厚板，唐破風的招牌 ──
    def tip_z(v):
        return _kara_z(v, z_tip, drop, flare)

    y_bd = y_tip - bd_t
    for j in range(nt):
        v0, v1 = j / nt * 2.0 - 1.0, (j + 1) / nt * 2.0 - 1.0
        x0, x1 = v0 * hw_tip, v1 * hw_tip
        z0t, z1t = tip_z(v0), tip_z(v1)
        bld.quad((x0, y_tip, z0t), (x1, y_tip, z1t),
                 (x1, y_bd, z1t), (x0, y_bd, z0t), C_KAWARA_DK, flip=True)
        bld.quad((x0, y_bd, z0t), (x1, y_bd, z1t),
                 (x1, y_bd, z1t - bd_h), (x0, y_bd, z0t - bd_h), C_WOOD_LT, flip=True)
        bld.quad((x0, y_bd, z0t - bd_h), (x1, y_bd, z1t - bd_h),
                 (x1, y_tip, z1t - bd_h), (x0, y_tip, z0t - bd_h), C_WOOD, flip=True)

    # ── 向拝柱 ×2 + 礎石 + 虹樑 ──
    # 柱頂／樑頂都用 _kara_z 現算屋面高度，不寫死數字：改上面任何一個
    # 參數，柱子會自己跟著長到屋面底下，不會又戳出去或懸空。
    u_post = (y_post - y_back) / (y_tip - y_back)
    z_col = _kara_z(2.55 / hw_at(u_post), pk_at(u_post), drop, flare) - 0.06
    z_lint = _kara_z(2.78 / hw_at(u_post), pk_at(u_post), drop, flare) - 0.35
    for sx in (1, -1):
        bld.box(sx * 2.55, y_post, 0.13, 0.72, 0.72, 0.26, C_STONE)          # 礎石
        bld.box(sx * 2.55, y_post, (0.26 + z_col) / 2, 0.40, 0.40, z_col - 0.26, C_WOOD)
    bld.box(0.0, y_post, z_lint - 0.21, 5.9, 0.34, 0.42, C_WOOD)             # 虹樑
    # 樑上不放蟇股：妻壁在 y_tip、樑在 y_post，中間差 0.45m，蟇股會**整個**
    # 被妻壁擋在後面 —— 六個 quad 誰也看不到。

    # ── 妻壁：破風板背後那片漆喰，被 S 曲線切成一彎月牙 ──
    for j in range(nt):
        v0, v1 = j / nt * 2.0 - 1.0, (j + 1) / nt * 2.0 - 1.0
        z0t, z1t = tip_z(v0) - bd_h, tip_z(v1) - bd_h
        if z0t <= z_lint and z1t <= z_lint:
            continue                                    # 曲線已經掉到樑下，月牙到此為止
        bld.quad((v0 * hw_tip, y_tip, max(z0t, z_lint)),
                 (v1 * hw_tip, y_tip, max(z1t, z_lint)),
                 (v1 * hw_tip, y_tip, z_lint), (v0 * hw_tip, y_tip, z_lint),
                 C_PLASTER, flip=True)

    # 兎毛通（破風正中央垂下的懸魚）：兩段收窄，不然就是一顆掛在破風上的箱子
    zc = tip_z(0.0) - bd_h
    bld.box(0.0, y_bd - 0.06, zc - 0.14, 0.52, 0.14, 0.30, C_WOOD)
    bld.box(0.0, y_bd - 0.06, zc - 0.38, 0.30, 0.14, 0.26, C_WOOD)

    # ── 五段階梯（Feature List §1「5 階木階梯」）──
    # 舊版的階梯埋在縁側**底下**（頂階 y≈-8.6，縁側從 -9.33 才開始），
    # 爬到第三階就撞到地板，前面還橫著一整排不斷開的高欄 —— 等於做了
    # 一座走不上去的階梯。這次落在縁側外緣往外，高欄在這一段開口。
    # ⚠ 階梯**不能**用 5 個實心 box 疊。box 是巢狀的（每個都從地面長到自己
    # 的高度），側面全部落在 x=±hw_st 同一個平面上互相重疊 —— 共面的兩張面
    # 會讓 Cycles 的陰影線一離開表面就打到對方，整片階梯側面算成 **純黑
    # (0,0,0)**，連關掉太陽只留環境光都還是黑的。（這個黑塊 debug 花的時間
    # 比唐破風本身還久：看起來像破洞，ray_cast 打下去卻是好好的面、法線
    # 對、顏色對 —— 錯的是「有兩張」。）
    #
    # 改成分段鋪面的**開放殼**：蹴込 + 踏面 + 兩側，每一段各佔各的 y/z 區間，
    # 沒有任何一對共面。底面與背面直接不畫 —— 它們永遠貼著地面和基壇正面，
    # 看不到，而畫出來就又是兩對共面。順便還從 30 個 quad 降到 20 個。
    n_st, tread = 5, 0.42
    hw_st = gate_hw - 0.05
    ys = [y_deck - (n_st - i) * tread for i in range(n_st)] + [y_deck]
    zs = [0.0] + [deck_z * (i + 1) / n_st for i in range(n_st)]
    for i in range(n_st):
        y0, y1, za, zb = ys[i], ys[i + 1], zs[i], zs[i + 1]
        bld.quad((-hw_st, y0, za), (hw_st, y0, za),
                 (hw_st, y0, zb), (-hw_st, y0, zb), C_WOOD)              # 蹴込板
        bld.quad((-hw_st, y0, zb), (hw_st, y0, zb),
                 (hw_st, y1, zb), (-hw_st, y1, zb),
                 C_WOOD_LT if i % 2 else C_ENGAWA)                       # 踏面
        for sx in (1, -1):
            bld.quad((sx * hw_st, y0, 0.0), (sx * hw_st, y1, 0.0),
                     (sx * hw_st, y1, zb), (sx * hw_st, y0, zb),
                     C_ENGAWA, flip=(sx < 0))


# ─────────────────────── 主屋 ───────────────────────

def build_house(bld):
    w = 14 * KEN
    d = 8 * KEN
    f1 = 3.9
    f2 = 3.1
    pod = 0.85
    # 基壇（階梯歸唐破風玄関那段做 —— 階梯得跟玄関對齊才有意義）
    # 前後進深吃到 d+4.1：縁側外緣就在 ±(d/2+2.05)，基壇原本只到 ±(d/2+1.1)，
    # 縁側等於有 0.95m 懸空。以前正面被一整排高欄擋著看不出來，這輪把高欄
    # 在玄関處切開之後，階梯旁邊就露出一個全黑的洞。基壇接到縁側外緣為止。
    bld.box(0, 0, pod / 2, w + 2.2, d + 4.1, pod, C_STONE)
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
        if abs(px) < GATE_HW:
            continue                                     # 這一段是玄関大扉
        bld.box(px, -(d / 2 + 0.02), z0 + 1.75, KEN * 0.74, 0.06, 1.15, C_SHOJI)
    # 玄関大扉（雙開）—— 唐破風正下方
    bld.box(0, -(d / 2 + 0.10), z0 + 1.125, 2 * GATE_HW - 0.5, 0.20, 2.25, C_WOOD)
    for sx in (1, -1):
        bld.box(sx * 1.25, -(d / 2 + 0.17), z0 + 1.10, 2.30, 0.10, 2.00, C_WOOD_LT)
    # ── 腰簷（Feature List §1：多層次屋頂／錣葺き）──
    # 牆中段切一圈外突腰簷，給下方格子窗一條長條柔和陰影。
    # z0+2.35 ≈ 地面上 3.2m（使用者指定高度），剛好卡在窗楣（頂在
    # z0+2.325）正上方 —— 窗跟簷幾乎是同一條線，陰影才會貼著窗蓋下來。
    # 正面中央讓給唐破風（gap_hw）；m 從 5 開到 13 才切得出準確的開口。
    koshi_z = z0 + 2.35
    skirt_ring(bld, w / 2 - 0.05, d / 2 - 0.05, koshi_z + 0.16,
               w / 2 + 1.0, d / 2 + 1.0, koshi_z - 0.06, lift_corner=0.10,
               m=13, gap_hw=GATE_HW + 0.3)
    # 縁側 + 高欄（正面在玄関處斷開，階梯才進得來）
    for sy in (1, -1):
        bld.box(0, sy * (d / 2 + 1.05), z0 + 0.12, w + 1.4, 2.0, 0.22, C_ENGAWA)
        if sy > 0:
            bld.box(0, sy * (d / 2 + 1.95), z0 + 0.95, w + 1.4, 0.11, 0.11, C_WOOD)
        else:
            seg = (w + 1.4) / 2 - GATE_HW
            for sx in (1, -1):
                bld.box(sx * (GATE_HW + seg / 2), sy * (d / 2 + 1.95),
                        z0 + 0.95, seg, 0.11, 0.11, C_WOOD)
        for i in range(13):
            px = -w / 2 + i * (w / 12)
            if sy < 0 and abs(px) < GATE_HW:
                continue
            bld.box(px, sy * (d / 2 + 1.95), z0 + 0.5, 0.09, 0.09, 0.9, C_WOOD)
    # ── 唐破風玄関（Feature List §1）──
    build_karahafu(bld, -d / 2, -(d / 2 + 2.05), z0 + 0.23, GATE_HW)
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
    """參道：一條乾淨連續的石板道，中央微拱。y0（靠石階）→ y1（遠端）。

    ⚠ 這裡本來是「邊緣與草地不規則交錯侵蝕」（Feature List §2 原始規格）：
    每一排的左右邊界各自亂數抖動 ±0.45m，邊緣車道還有 30% 機率整格換成草色。
    使用者看過參考圖（求聞編年史的稗田邸參道）後改規格 —— 那條參道是**整齊
    的切石鋪面**，不是荒廢的碎石徑。侵蝕感讓整條路看起來像沒人維護的野徑，
    跟「貴族宅邸的正式參道」是反的。

    改成規則的石板網格：邊界筆直、板與板之間留固定目地。石板尺寸仍有
    ±3% 的色差（真石材本來就不同色），但**幾何**完全對齊。"""
    rng = rng or random.Random(7)
    hw = width / 2
    cols = 4                                   # 橫向四塊板
    rows = max(1, int(abs(y1 - y0) / 1.55))
    joint = 0.055                              # 目地寬（板與板之間的縫）

    def crown(x):
        """中央微拱：拋物線，中心 +0.16、兩緣歸零。"""
        u = x / hw
        return 0.16 * max(0.0, 1.0 - u * u)

    # 底層鋪面（目地的陰影色）—— 石板浮在它上面，縫看起來就是暗的
    bld.quad((-hw, y0, 0.035), (hw, y0, 0.035), (hw, y1, 0.035), (-hw, y1, 0.035),
             C_STONE_DK, flip=(y1 > y0))
    for r in range(rows):
        ya = y0 + (y1 - y0) * r / rows
        yb = y0 + (y1 - y0) * (r + 1) / rows
        # 目地往內縮，四邊都留縫
        sa, sb = (ya + joint, yb - joint) if yb > ya else (ya - joint, yb + joint)
        for c in range(cols):
            xa = -hw + width * c / cols + joint
            xb = -hw + width * (c + 1) / cols - joint
            sh = rng.uniform(-0.022, 0.022)          # 石材色差，不是幾何雜訊
            col = (C_STONE[0] + sh, C_STONE[1] + sh, C_STONE[2] + sh)
            za, zb2 = crown(xa) + 0.075, crown(xb) + 0.075
            bld.quad((xa, sa, za), (xb, sa, zb2), (xb, sb, zb2), (xa, sb, za),
                     col, flip=(y1 > y0))
            # 板厚的側緣：只畫最外側兩排的外邊，中間的縫看不到側面
            if c in (0, cols - 1):
                ex = xa if c == 0 else xb
                bld.quad((ex, sa, za), (ex, sb, za),
                         (ex, sb, 0.035), (ex, sa, 0.035),
                         C_STONE_DK, flip=(c == 0) != (y1 > y0))


# ─────────────────────── 格子塀 + 表門（前庭圍牆）───────────────────────
#
# Feature List §3「郭外防線」。原規格寫的是**平的白壁土塀**，使用者看過
# 參考圖後改成 **格子塀**：石垣基 → 白漆喰腰壁 → 上段一條深色木格子帶 →
# 兩坡瓦頂。差別在「上段那條格子帶」：一面 3.5m 高、38m 長的純白牆在
# 遠景就是一條白帶子，沒有任何尺度感；橫向的格子把它切成有節奏的段落，
# 遠看是深淺相間的帶，近看才看得出是木格柵。
#
# 本輪只做**正面那一道 + 兩側短回折**（參道視角看得到的範圍）。整圈
# 的東西南北四面留給 §3 正式那輪 —— 這輪的指定範圍是「前庭裝飾」。

def _batter(bld, p, q, fix, axis, ht, hb, z_lo, z_hi, col):
    """石垣腳：上窄下寬的梯形斷面 —— 真石垣的「勾配」。

    牆腳原本是一個等寬的 box，跟地面交出一條完全垂直的硬邊，讀起來就是
    「一塊牆放在一塊地上」的兩個物件。往外攤開的斜面會讓光沿著它連續
    變化，視覺上牆是從地裡長出來的。繞序交給 _auto_quad 判（梯形柱是
    凸的，離心方向永遠等於外法線）。"""
    ctr = ((p + q) / 2, fix, (z_lo + z_hi) / 2) if axis == "x" \
        else (fix, (p + q) / 2, (z_lo + z_hi) / 2)

    def P(t, off, z):
        return (t, fix + off, z) if axis == "x" else (fix + off, t, z)

    for sd in (1, -1):
        _auto_quad(bld, ctr, P(p, sd * ht, z_hi), P(q, sd * ht, z_hi),
                   P(q, sd * hb, z_lo), P(p, sd * hb, z_lo), col)
    for t in (p, q):                                     # 兩端的梯形端面
        _auto_quad(bld, ctr, P(t, -ht, z_hi), P(t, ht, z_hi),
                   P(t, hb, z_lo), P(t, -hb, z_lo), col)


def _apron(bld, p, q, fix, axis, hb, z=0.045):
    """犬走り：牆腳往外的兩階碎石帶（暗→淡），把牆腳接進地面。"""
    bands = ((hb, hb + 0.34, C_GRAVEL_DK), (hb + 0.34, hb + 1.34, C_GRAVEL))
    for sd in (1, -1):
        for o0, o1, col in bands:
            if axis == "x":
                bld.quad((p, fix + sd * o0, z), (q, fix + sd * o0, z),
                         (q, fix + sd * o1, z), (p, fix + sd * o1, z),
                         col, flip=(sd < 0))
            else:
                bld.quad((fix + sd * o0, p, z), (fix + sd * o0, q, z),
                         (fix + sd * o1, q, z), (fix + sd * o1, p, z),
                         col, flip=(sd > 0))


def build_wall_run(bld, a0, a1, fix, axis="x", gate_hw=0.0, apron_trim=(0.0, 0.0)):
    """一段格子塀。axis="x" 時沿 x 走、fix 是 y 座標；axis="y" 則相反。
    gate_hw > 0 時中央讓出門洞（只有正面那道用得到）。

    兩軸共用同一支函式而不是各寫一份：牆有石垣／漆喰／格子帶／冠木／
    兩坡瓦頂／棟瓦六層，各寫一份等於把六層的尺寸抄兩遍，改一邊忘另一邊
    是遲早的事（第一版側面回折就是手抄的，格柵間距跟正面對不上）。"""
    z_stone, z_wall, z_lat, z_top = 0.72, 2.30, 3.10, 3.50
    segs = [(a0, -gate_hw), (gate_hw, a1)] if gate_hw > 0.0 else [(a0, a1)]

    def slab(c, ln, thick, cz, h, col):
        if axis == "x":
            bld.box(c, fix, cz, ln, thick, h, col)
        else:
            bld.box(fix, c, cz, thick, ln, h, col)

    for p, q in segs:
        if q - p < 0.05:
            continue
        cc, ln = (p + q) / 2, q - p
        # 腰石垣：外八字的梯形（上半寬 0.525 → 地面 0.79），不是等寬 box
        _batter(bld, p, q, fix, axis, 0.525, 0.79, 0.0, z_stone, C_STONE)
        _apron(bld, p + apron_trim[0], q - apron_trim[1], fix, axis, 0.79)
        slab(cc, ln, 0.86, (z_stone + z_wall) / 2, z_wall - z_stone, C_PLASTER)
        # 格子帶：深色底板 + 直立木格柵（格柵厚過底板，才有立體的格子影）
        slab(cc, ln, 0.80, (z_wall + z_lat) / 2, z_lat - z_wall, C_WOOD)
        n_sl = max(2, int(ln / 0.42))
        for i in range(n_sl):
            pc = p + (i + 0.5) * (ln / n_sl)
            if axis == "x":
                bld.box(pc, fix, (z_wall + z_lat) / 2, 0.14, 0.94,
                        z_lat - z_wall - 0.12, C_WOOD_LT)
            else:
                bld.box(fix, pc, (z_wall + z_lat) / 2, 0.94, 0.14,
                        z_lat - z_wall - 0.12, C_WOOD_LT)
        slab(cc, ln, 1.00, z_lat + 0.07, 0.14, C_WOOD)                       # 冠木
        for sd in (1, -1):                                                   # 兩坡瓦頂
            if axis == "x":
                bld.quad((p, fix + sd * 0.06, z_top), (q, fix + sd * 0.06, z_top),
                         (q, fix + sd * 0.74, z_lat + 0.14),
                         (p, fix + sd * 0.74, z_lat + 0.14), C_KAWARA, flip=(sd < 0))
            else:
                bld.quad((fix + sd * 0.06, p, z_top), (fix + sd * 0.06, q, z_top),
                         (fix + sd * 0.74, q, z_lat + 0.14),
                         (fix + sd * 0.74, p, z_lat + 0.14), C_KAWARA, flip=(sd > 0))
        slab(cc, ln, 0.28, z_top + 0.06, 0.18, C_RIDGE)                      # 棟瓦


def build_gate(bld, y, gate_hw, post_hw=0.35):
    """表門：兩根粗門柱 + 冠木 + 瓦屋根（棟門形）。參道從中間穿過。

    柱高從 3.60 收到 3.30：狛犬放大之後，門柱／簷口與狛犬要在同一個
    視覺量級上，門太高會把石獅子吃掉（使用者：狛犬「get visually
    swallowed by the gate structure」）。兩邊各讓一步 —— 狛犬 +18%、
    門 -8%，比只動一邊自然。"""
    z_post, z_beam = 3.30, 3.32
    for sx in (1, -1):
        px = sx * (gate_hw + post_hw)
        # 礎石也走外八字，跟牆腳同一套語言，柱子才不是「插在地上」。
        # 半寬與犬走り的 hb 都跟牆腳取同一組（0.525/0.79），兩邊的碎石帶
        # 才會**接齊而不是疊在一起** —— 疊在一起就是兩張同法線的共面，
        # 互相擋掉對方的環境光，整塊算成全黑。
        _batter(bld, px - post_hw, px + post_hw, y, "x", 0.525, 0.79, 0.0, 0.52, C_STONE)
        _apron(bld, px - post_hw, px + post_hw, y, "x", 0.79)
        # 門柱比牆厚（1.10 vs 牆身 0.86）才露得出來。上一版柱寬 0.62 完全
        # 埋在牆裡，整座門只剩一片浮在開口上的屋頂，柱子一根都看不到。
        bld.box(px, y, (0.48 + z_post) / 2, 2 * post_hw, 1.10,
                z_post - 0.48, C_WOOD)                                        # 門柱
    span = 2 * (gate_hw + 2 * post_hw)
    bld.box(0, y, z_beam + 0.24, span, 0.52, 0.48, C_WOOD)                   # 冠木
    bld.box(0, y, z_beam - 0.40, span * 0.86, 0.34, 0.34, C_WOOD)            # 貫
    # 屋根：兩坡，出簷比牆頂大一截 —— 門要比牆搶眼
    zr = z_beam + 0.48
    for sy in (1, -1):
        bld.quad((-span / 2 - 0.6, y + sy * 0.08, zr + 0.84),
                 (span / 2 + 0.6, y + sy * 0.08, zr + 0.84),
                 (span / 2 + 0.6, y + sy * 1.55, zr),
                 (-span / 2 - 0.6, y + sy * 1.55, zr), C_KAWARA, flip=(sy < 0))
        bld.quad((-span / 2 - 0.6, y + sy * 1.55, zr),
                 (span / 2 + 0.6, y + sy * 1.55, zr),
                 (span / 2 + 0.6, y + sy * 1.55, zr - 0.16),
                 (-span / 2 - 0.6, y + sy * 1.55, zr - 0.16), C_KAWARA_DK, flip=(sy < 0))
    bld.box(0, y, zr + 0.92, span + 1.2, 0.42, 0.26, C_RIDGE)                # 大棟
    for sx in (1, -1):                                                       # 鬼瓦
        bld.box(sx * (span / 2 + 0.58), y, zr + 1.02, 0.34, 0.52, 0.46, C_RIDGE)


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
    # ⚠ 樹冠改用 _canopy_from_tips（跟後院的樹同一套）。原本是 5 顆
    # add_canopy 球疊在枝上 —— 拱門的**骨架**是對的（枝真的橫伸 5m），
    # 但冠仍然是「球黏在枝上」。骨架保留不動，只把冠換成沿枝端撒葉。
    tips = [
        ((x_side + lean, y, 9.2), (x_side + lean, y, 6.8), 2.6),
        ((x_side + lean * 0.6, y + rng.uniform(-1, 1), 7.4),
         (x_side + lean, y, 5.8), 2.1),
        ((x_side - sgn * 3.4, y, 6.1), (bx0, y, bz0), 2.0),
        ((x_side - sgn * 5.2, y + rng.uniform(-0.6, 0.6), 5.6),
         (x_side - sgn * 3.2, y, 6.0), 1.6),
        ((x_side + sgn * 1.2, y - 1.6, 8.2), (x_side + lean, y, 6.6), 1.7),
    ]
    _canopy_from_tips(bld, rng, tips, 1.95, 660, 0.70,
                      TREE_MAPLE["hull"], TREE_MAPLE["lo"], TREE_MAPLE["hi"])


# ─────────────────────── 後院（back garden）───────────────────────
#
# 設計語言**刻意跟前庭相反**：門前是儀式性的左右對稱（狛犬成對、燈籠成對、
# 參道筆直），後院是私密的、有機的、看起來像幾代人陸續加出來的。所以這一
# 段裡沒有任何一對鏡射物件、沒有等距排列。
#
# 但「不對稱」不等於「亂撒」—— 每一件都有構圖上的理由：
#   ・水池的南岸留白 = 映主屋屋頂與楓樹的鏡面
#   ・涸れ滝擺在池的北緣 = 從主屋往北看，視線越過鏡面落在瀑布上
#   ・枯山水的波紋圓心 = 懸浮石的正下方（沙面在「回應」靈氣）
#   ・主石／添石的主賓關係 = 石組的古典規矩，不是三顆一樣大的石頭
#
# 三區的份量也不對等：水池與菜園是日常的、安靜的，枯山水＋靈氣裂縫才是
# 這座後院的主角（規格：pond/veg 是玩家「路過」的，裂縫是要停下來看的）。


def _rough_box(bld, cx, cy, cz, sx, sy, sz, seed, col, col_top=None, yaw=0.0, jit=0.10):
    """粗胚石塊：八個角各自隨機位移的六面體，可繞 z 轉。
    庭石不是工整方塊、也不是圓球 —— 要有稜有角、每個面朝向都不同，
    方向光才切得出面與面的明暗差。"""
    rng = random.Random(seed)
    hx, hy, hz = sx / 2.0, sy / 2.0, sz / 2.0
    ca, sa = math.cos(yaw), math.sin(yaw)
    v = []
    for dx, dy, dz in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
                       (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]:
        px = dx * hx * (1.0 + rng.uniform(-jit, jit))
        py = dy * hy * (1.0 + rng.uniform(-jit, jit))
        pz = dz * hz * (1.0 + rng.uniform(-jit, jit))
        v.append((cx + px * ca - py * sa, cy + px * sa + py * ca, cz + pz))
    ct = col_top or col
    bld.quad(v[0], v[1], v[5], v[4], col)
    bld.quad(v[2], v[3], v[7], v[6], col)
    bld.quad(v[1], v[2], v[6], v[5], col)
    bld.quad(v[3], v[0], v[4], v[7], col)
    bld.quad(v[7], v[4], v[5], v[6], ct)
    bld.quad(v[0], v[3], v[2], v[1], col)


def _organic(cx, cy, r, seed, n, amp=0.24):
    """有機輪廓：極座標半徑疊三個隨機頻率的正弦。回傳 [(x, y, 角度, 半徑)]。
    池岸與砂紋都用這個 —— 完美的圓在庭園裡一眼就假。"""
    rng = random.Random(seed)
    ws = [rng.uniform(0.45, 1.0) for _ in range(3)]
    ws = [w / sum(ws) for w in ws]                    # 正規化：k ∈ [1-amp, 1+amp]
    terms = [(rng.randint(2, 4), rng.uniform(0.0, math.tau), amp * w) for w in ws]
    out = []
    for i in range(n):
        a = i / n * math.tau
        k = 1.0
        for f, ph, am in terms:
            k += am * math.sin(a * f + ph)
        out.append((cx + math.cos(a) * r * k, cy + math.sin(a) * r * k, a, r * k))
    return out


# ── 1. 石造水池 ──

def build_pond(bld, cx, cy, r, seed):
    """石造水池。回傳 (rim, r_at)，讓涸れ滝／楓／庭石都能照**實際池緣**擺。

    ⚠ 水面用 `quad_v`（每角一色）而不是整面一色。整面一色時漸層只能靠
    「一圈一個色」堆，六圈就是六條清清楚楚的等高線 —— 使用者看到的
    「像地形圖不像水」就是這個。改成把顏色寫成一個**連續的位置函式**
    `wcol(x, y)`，每個角各自取值、面內線性內插，色帶邊界就消失了。

    wcol 疊四件事：
      1. 深度漸層（岸亮綠 → 心暗藍），由實際池底深度算
      2. 鏡面：朝主屋那側往天空色偏，且**鏡面色本身隨深度變暗**
      3. 天光柔斑：一塊高斯狀的亮區，假的 specular
         （真正的粗糙度/反射是 Godot 材質的事，這裡只烤一個柔和的亮部）
      4. 岸際柔化：最外 14% 半徑往岸石色收，水與石之間不是一刀切
    """
    n = 44
    rim = _organic(cx, cy, r, seed, n, amp=0.18)
    z_w, d_max = 0.30, 1.25

    def r_at(a):
        aa = (a % math.tau) / math.tau * n
        i0 = int(math.floor(aa)) % n
        f = aa - math.floor(aa)
        return rim[i0][3] * (1.0 - f) + rim[(i0 + 1) % n][3] * f

    # 天光柔斑：擺在鏡面那一側、偏離中心（正中央會讀成一顆太陽）
    hx, hy = cx - r * 0.30, cy - r * 0.40
    hsig = r * 0.34

    def wcol(px, py):
        dx, dy = px - cx, py - cy
        d = math.hypot(dx, dy)
        a = math.atan2(dy, dx)
        t = min(1.0, d / max(r_at(a), 0.001))
        dep = 1.0 - t * t
        col = _mix(C_WATER_SHAL, C_WATER_DEEP, dep ** 0.75)
        mir = max(0.0, -math.sin(a)) ** 1.2
        col = _mix(col, _mix(C_WATER_MIRROR, C_WATER_MIRROR_DK, dep), mir * 0.80)
        sheen = math.exp(-((math.hypot(px - hx, py - hy) / hsig) ** 2))
        # 0.42 太強、半徑又寬，整池被洗成一片淡灰藍，深度漸層讀不出來。
        # 柔斑是「一塊天光」，不該蓋過水本身的深淺。
        col = _mix(col, C_WATER_SHEEN, sheen * 0.26)
        if t > 0.86:
            k = (t - 0.86) / 0.14
            col = _mix(col, C_WATER_EDGE, k * k * 0.62)
        return col

    def lerp_pt(t, idx):
        return (cx + (rim[idx][0] - cx) * t, cy + (rim[idx][1] - cy) * t)

    rings = 12
    for ri in range(rings):
        t0, t1 = ri / rings, (ri + 1) / rings
        for i in range(n):
            i2 = (i + 1) % n
            a0, b0 = lerp_pt(t0, i), lerp_pt(t0, i2)
            a1, b1 = lerp_pt(t1, i), lerp_pt(t1, i2)
            bld.quad_v((a0[0], a0[1], z_w), (a1[0], a1[1], z_w),
                       (b1[0], b1[1], z_w), (b0[0], b0[1], z_w),
                       wcol(*a0), wcol(*a1), wcol(*b1), wcol(*b0))
    # 池底：真的做出深淺（Godot 端接水體 shader 時這層才有意義）
    for ri in range(3):
        t0, t1 = ri / 3.0, (ri + 1) / 3.0
        for i in range(n):
            i2 = (i + 1) % n
            def flr(t, idx):
                q = lerp_pt(t, idx)
                return (q[0], q[1], z_w - d_max * (1.0 - t * t))
            bld.quad(flr(t0, i), flr(t1, i), flr(t1, i2), flr(t0, i2),
                     _mix(C_MUD, C_EARTH, 1.0 - t0))
    # 池壁 + 天端石
    for i in range(n):
        i2 = (i + 1) % n
        pa, pb = rim[i], rim[i2]
        na = (math.cos(pa[2]), math.sin(pa[2]))
        nb = (math.cos(pb[2]), math.sin(pb[2]))
        oa = (pa[0] + na[0] * 0.72, pa[1] + na[1] * 0.72)
        ob = (pb[0] + nb[0] * 0.72, pb[1] + nb[1] * 0.72)
        bld.quad((pa[0], pa[1], 0.46), (oa[0], oa[1], 0.46),
                 (ob[0], ob[1], 0.46), (pb[0], pb[1], 0.46), C_STONE)
        bld.quad((oa[0], oa[1], 0.46), (oa[0], oa[1], 0.0),
                 (ob[0], ob[1], 0.0), (ob[0], ob[1], 0.46), C_STONE_DK)
        bld.quad((pa[0], pa[1], 0.46), (pb[0], pb[1], 0.46),
                 (pb[0], pb[1], z_w - 0.02), (pa[0], pa[1], z_w - 0.02), C_STONE_DK)
    return rim, r_at


# ── 涸れ滝（乾瀑布）──

def build_karetaki(bld, x_top, y_top, x_bot, y_bot, z_top, seed):
    """涸れ滝：沒有水，但堆出「水曾經從這裡落下」的石階。

    這是水池的戲劇性錨點。做法是古典的三段式 —— 兩側**立起來**的挟石
    （水落石）夾出一道垂直的溝，中間錯落的階石一路跌到水面。石頭要
    一階比一階往前吐，跌水的動線才看得出來（全部切齊就只是一道樓梯）。
    """
    rng = random.Random(seed)
    steps = 6
    sc = z_top / 2.55                       # 石階尺寸跟著落差走，不然大池配小瀑布
    for k in range(steps):
        t = k / (steps - 1.0)
        px = x_top + (x_bot - x_top) * t
        py = y_top + (y_bot - y_top) * t
        pz = z_top * (1.0 - t) ** 1.35 + 0.30
        w = (1.35 + t * 1.15) * sc
        _rough_box(bld, px, py, pz, w, (0.95 + t * 0.5) * sc,
                   (0.42 + (1 - t) * 0.22) * sc,
                   seed * 13 + k, C_STONE, col_top=_mix(C_STONE, C_MOSS, 0.18 * t),
                   yaw=rng.uniform(-0.35, 0.35), jit=0.16)
    # 挟石：兩側立石，高度不等（等高就變成門框）
    ang = math.atan2(y_bot - y_top, x_bot - x_top)
    sx_, sy_ = -math.sin(ang), math.cos(ang)
    # ⚠ hh 是**總高**，不是「在 z_top 之上再加多少」。第一版寫成 z_top + hh，
    # 兩塊挟石變成 4.7m / 4.1m 的巨柱，加上低 jit 的方正比例，整組讀起來
    # 是兩根清水模柱子夾一道樓梯，不是石組。
    # 挟石要**矮胖、粗糙、左右不等高**：它們是夾住水路的岩壁，不是門框。
    for sd, hh, ww in ((1, 2.35 * sc, 1.15 * sc), (-1, 1.65 * sc, 0.95 * sc)):
        _rough_box(bld, x_top + sx_ * sd * 1.45 * sc, y_top + sy_ * sd * 1.45 * sc,
                   hh * 0.46, ww, ww * 1.25, hh,
                   seed * 29 + sd, C_STONE_DK,
                   col_top=_mix(C_STONE_DK, C_MOSS, 0.32),
                   yaw=rng.uniform(-0.5, 0.5), jit=0.26)


# ── 楓（池畔）──

# ─────────────────── 樹：遞迴分枝（不是棍子上插球）───────────────────
#
# ⚠ 舊版 build_maple 是「八角柱樹幹 + 2~3 顆 add_canopy 球」，樹冠中心是
# 寫死在樹幹頂端上方的偏移量 —— 跟枝條完全無關。那就是字面意義上的
# 「棍子上插一顆球」，再怎麼調球的凹凸都救不回來，因為**問題不在表面**。
#
# 真正的樹：樹冠的形狀是「所有枝條末端在哪裡」的結果，不是一個獨立的
# 幾何體貼上去。所以這裡改成遞迴分枝：
#   1. 樹幹長一段 → 分岔 → 每個子枝再長再分，深度 3
#   2. 半徑逐段收細，每次分岔再乘一個 < 1 的比例（枝越分越細）
#   3. **葉團只長在枝端**，一個枝端一團。樹冠 = 所有葉團的聯集 ——
#      枝條伸到哪，冠就到哪；枝條不對稱，冠就自然不對稱
#   4. 子枝的方位角平均分佈後再抖動，長度／半徑比例也各自隨機 ——
#      完全對稱的分岔會長出聖誕樹
#
# 松用同一支產生器，只換 profile：多一個「主幹延續（leader）」的子枝
# 幾乎直上，其餘側枝接近水平 —— 那是針葉樹的骨架，闊葉樹則是主幹在
# 分岔處就消失（分叉成對等的枝）。


def _norm3(v):
    l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) or 1.0
    return (v[0] / l, v[1] / l, v[2] / l)


def _basis(d):
    """給方向 d 一組正交基底 (d, u, v)。"""
    ref = (0.0, 0.0, 1.0) if abs(d[2]) < 0.9 else (1.0, 0.0, 0.0)
    u = _norm3((d[1] * ref[2] - d[2] * ref[1], d[2] * ref[0] - d[0] * ref[2],
                d[0] * ref[1] - d[1] * ref[0]))
    v = (d[1] * u[2] - d[2] * u[1], d[2] * u[0] - d[0] * u[2], d[0] * u[1] - d[1] * u[0])
    return u, v


def _bend(d, az, ang):
    """把方向 d 依方位角 az 偏開 ang 弧度。"""
    u, v = _basis(d)
    ca, sa = math.cos(ang), math.sin(ang)
    cz, sz = math.cos(az), math.sin(az)
    return _norm3((d[0] * ca + (u[0] * cz + v[0] * sz) * sa,
                   d[1] * ca + (u[1] * cz + v[1] * sz) * sa,
                   d[2] * ca + (u[2] * cz + v[2] * sz) * sa))


def _tube(bld, pts, radii, col, sides=5):
    """沿折線掃的錐形管（枝幹）。每節點各自取正交基底 —— 會有一點扭轉，
    但枝這種細長物件看不出來，省掉 parallel transport。"""
    n = len(pts)
    rings = []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        t = _norm3((b[0] - a[0], b[1] - a[1], b[2] - a[2]))
        u, v = _basis(t)
        ring = []
        for k in range(sides):
            ang = k / sides * math.tau
            cu, cv = math.cos(ang) * radii[i], math.sin(ang) * radii[i]
            ring.append((p[0] + u[0] * cu + v[0] * cv,
                         p[1] + u[1] * cu + v[1] * cv,
                         p[2] + u[2] * cu + v[2] * cv))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            bld.quad(rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k], col)


def _canopy_from_tips(bld, rng, tips, spread, n_tuft, leaf, c_hull, c_lo, c_hi,
                      n_shade=5):
    """樹冠 = 所有枝端**周圍體積**裡的葉子聯集，不是「每個枝端一顆殼」。

    ⚠ 這是第五版才走對的路。v4 是每個枝端做一顆凹凸殼再撒葉，結果每團
    都是「深色核心 + 一圈放射狀的葉」—— 像海膽不像樹。原因是密度算不過來：
    一顆半徑 0.56 的殼表面約 3m²，要蓋滿得撒數百片葉（make_hedge.py 實測
    要 276 片/m²），24 顆殼乘起來根本撒不起，於是殼永遠露著。

    改成把葉子直接撒進枝端周圍的**體積**：密度集中在冠的外緣（真正形成
    剪影的地方），而不是平均攤在每顆殼的表面上。同樣的面數，覆蓋率完全
    不同。暗色團塊只留 5 顆放在最粗的枝端，純粹擋光。

    葉子朝向取「離冠心的方向」—— 整個冠的受光才會連貫（每片各自朝外的話
    明暗會亂成雜訊）。"""
    if not tips:
        return
    cx = sum(t[0][0] for t in tips) / len(tips)
    cy = sum(t[0][1] for t in tips) / len(tips)
    cz = sum(t[0][2] for t in tips) / len(tips)
    # ⚠ 不放暗色團塊。v5 在粗枝端擺了 5 顆暗殼擋光，結果它們在葉子之間
    # 露成一顆顆深色多面體 —— 像樹上掛了幾個鳥巢。擋光改用**顏色**做：
    # 靠近枝端（冠內部）的葉子往暗色混，外緣的保持鮮亮。同樣讀得出
    # 「裡面是暗的」，但沒有任何一塊硬幾何露出來，而且不花面數。
    # 葉子：挑一枝，沿它的**外段**（t=0.32~1.0）取點再偏移。
    # 只堆在末端一點的話，枝條會長長一段光禿禿地露在外面 —— 真的樹
    # 葉子是長在枝的外三分之一整段上的。
    ws = [t[2] for t in tips]
    tot = sum(ws) or 1.0
    for _ in range(n_tuft):
        r = rng.random() * tot
        acc = 0.0
        pick = tips[0]
        for t, wq in zip(tips, ws):
            acc += wq
            if acc >= r:
                pick = t
                break
        ft = rng.uniform(0.32, 1.0)
        tp = (pick[1][0] + (pick[0][0] - pick[1][0]) * ft,
              pick[1][1] + (pick[0][1] - pick[1][1]) * ft,
              pick[1][2] + (pick[0][2] - pick[1][2]) * ft)
        # ⚠ 半徑取 u^0.45 而不是球內均勻取樣。均勻取樣有一半的葉子落在
        # 內部被自己擋住 —— 對剪影完全沒貢獻，等於白花面數。偏外側取樣
        # 讓同樣的葉數集中在真正形成輪廓的地方（但仍不是純球面，
        # 純球面會排成一層殼、內部空掉）。
        _d = _norm3((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        _rad = rng.random() ** 0.45
        ox, oy, oz = _d[0] * _rad, _d[1] * _rad, _d[2] * _rad
        sc = spread * 1.16
        rad = _rad
        p_ = (tp[0] + ox * sc, tp[1] + oy * sc, tp[2] + oz * sc * 0.82)
        nrm = _norm3((p_[0] - cx, p_[1] - cy, (p_[2] - cz) * 0.7 + 0.25))
        # 內深外亮：rad 小 = 貼著枝端 = 冠內部
        lo = _mix(c_hull, c_lo, min(1.0, 0.30 + rad * 0.95))
        hi = _mix(c_lo, c_hi, min(1.0, rad * 1.15))
        _leaf_tuft(bld, rng, p_, nrm, leaf, lo, hi, n_leaf=2)


def _canopy_pads(bld, rng, tips, n_tuft, leaf, c_hull, c_lo, c_hi,
                 flat=0.34, bulk=1.30, rmin=0.30):
    """松專用的樹冠：**幾團扁平的葉盤**，不是一整片平均的葉雲。

    ⚠ 一開始松跟楓共用 _canopy_from_tips（葉子平均撒在每個枝端周圍）。
    楓對，松錯 —— 針葉小，同樣的 ntuft 攤到 48 個枝端上每處都只剩十幾片，
    整棵讀成「闊葉樹幼苗」，主幹還會有一段光禿禿的鞭子露在葉子上方。

    庭木的松（仕立て松）本來就不是平均的：葉子被剪成幾團**扁平的段**，
    段與段之間露出彎曲的枝，最頂上那團是天芯。所以這裡先把枝端依
    pad_depth 的祖先分組，每組塌成一個扁球（z 只有 flat 倍），葉量按組
    的枝長權重分。同樣的面數集中成團 → 密；團之間留空 → 骨架看得見。"""
    groups = {}
    for t in tips:
        groups.setdefault(t[3], []).append(t)
    if not groups:
        return
    tot_w = sum(sum(t[2] for t in ts) for ts in groups.values()) or 1.0
    for ts in groups.values():
        gx = sum(t[0][0] for t in ts) / len(ts)
        gy = sum(t[0][1] for t in ts) / len(ts)
        gz = sum(t[0][2] for t in ts) / len(ts)
        # 盤的半徑取「枝端離組心的散佈」——枝張得開的那組盤就大
        sp = sum(math.dist(t[0], (gx, gy, gz)) for t in ts) / len(ts)
        rad = max(rmin, sp * bulk) * rng.uniform(0.86, 1.15)
        # 每盤各自傾斜一點、扁度也不同。全部水平等厚的話會讀成「一疊盤子」
        fl = flat * rng.uniform(0.82, 1.30)
        til, taz = rng.uniform(0.06, 0.26), rng.uniform(0.0, math.tau)
        tx, ty = math.cos(taz) * til, math.sin(taz) * til
        w = sum(t[2] for t in ts)
        n = max(14, int(n_tuft * w / tot_w))
        for _ in range(n):
            _d = _norm3((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
            u = rng.random() ** 0.40
            ox, oy = _d[0] * rad * u, _d[1] * rad * u
            # 盤面上拱下平：頂面往上鼓一點，底面幾乎不掉下去
            oz = _d[2] * rad * u * fl * (1.35 if _d[2] > 0 else 0.62)
            p_ = (gx + ox, gy + oy, gz + oz + ox * tx + oy * ty)
            nrm = _norm3((ox * 0.55, oy * 0.55, oz * 0.4 + rad * 0.62))
            # 內暗外亮 × 上亮下暗：松的段是「上面一層受光、下面全是陰影」
            t_up = 0.5 + oz / (rad * fl * 2.0 + 1e-6) * 0.5
            k = min(1.0, 0.16 + u * 0.72 + max(0.0, t_up - 0.5) * 0.66)
            lo = _mix(c_hull, c_lo, k)
            hi = _mix(c_lo, c_hi, min(1.0, (u * 0.70 + t_up * 0.75)))
            _leaf_tuft(bld, rng, p_, nrm, leaf, lo, hi, n_leaf=2)


def _grow(bld, tips, p, d, r, ln, depth, cfg, rng, gid=None, ctr=None):
    """一段枝：邊長邊收細，末端分岔；到底層就記下枝端位置給葉團用。"""
    segs = 3
    pts, rr = [p], [r]
    if depth == 0:
        # 樹頭外張：真的樹幹在地面附近會擴根盤，等徑圓柱插進土裡像電線桿
        pts = [p, (p[0] + d[0] * ln * 0.10, p[1] + d[1] * ln * 0.10,
                   p[2] + d[2] * ln * 0.10)]
        rr = [r * 1.42, r]
    cur_p, cur_d = pts[-1], d
    ups = cfg["up"]
    up_k = ups[min(depth, len(ups) - 1)]
    for i in range(segs):
        cur_d = _norm3((cur_d[0] + rng.uniform(-cfg["wig"], cfg["wig"]),
                        cur_d[1] + rng.uniform(-cfg["wig"], cfg["wig"]),
                        cur_d[2] + up_k))
        step = ln / segs
        cur_p = (cur_p[0] + cur_d[0] * step, cur_p[1] + cur_d[1] * step,
                 cur_p[2] + cur_d[2] * step)
        pts.append(cur_p)
        rr.append(r * (1.0 - (i + 1) / segs * cfg["taper"]))
    _tube(bld, pts, rr, _mix(C_TRUNK, C_TWIG, min(1.0, depth / 3.0)),
          sides=5 if depth == 0 else (4 if depth == 1 else 3))
    r_end = rr[-1]
    if depth >= cfg["depth"]:
        tips.append((cur_p, pts[0], ln, gid))
        return
    n = cfg["split"][min(depth, len(cfg["split"]) - 1)]
    az0 = rng.uniform(0.0, math.tau)
    pad_d = cfg.get("pad_depth")
    for c in range(n):
        leader = cfg.get("leader") and c == 0
        az = az0 + (c / float(n)) * math.tau + rng.uniform(-0.55, 0.55)
        ang = rng.uniform(*(cfg["lead_ang"] if leader else cfg["ang"]))
        lr = rng.uniform(*(cfg["lead_lratio"] if leader else cfg["lratio"]))
        g = gid
        if pad_d is not None and g is None and depth + 1 >= pad_d:
            ctr[0] += 1
            g = ctr[0]
        _grow(bld, tips, cur_p, _bend(cur_d, az, ang),
              r_end * rng.uniform(*cfg["rratio"]), ln * lr, depth + 1, cfg, rng,
              g, ctr)


# ⚠ 闊葉樹也要 leader。沒有 leader 的話樹幹在第一次分岔就消失，所有枝
# 從同一高度散開 —— 冠因此是一頂**平底的蘑菇帽**（v2 就是這樣）。
# 有 leader 主幹才會一路往上、每一層沿途甩出側枝，枝端散佈在不同高度，
# 冠的下緣才會參差。
# up 改成 per-depth：主幹向上(0.34) → 側枝漸平(0.14/0.02) → 末梢下垂(-0.12)。
# 楓的枝是外展微垂的，全部向上就是白楊。
TREE_MAPLE = dict(
    trunk_r=0.044, trunk_len=0.30, depth=4, split=(4, 2, 2, 2),
    ang=(0.62, 1.15), lratio=(0.50, 0.88), rratio=(0.54, 0.74),
    up=(0.34, 0.14, 0.02, -0.12), wig=0.30, taper=0.28,
    leader=True, lead_ang=(0.10, 0.32), lead_lratio=(0.66, 0.86),
    fol=0.072, ntuft=500, leaf=0.50, flat=0.78,
    hull=(0.048, 0.016, 0.012),
    lo=(0.520, 0.095, 0.045), hi=(0.830, 0.290, 0.095))

# 松走另一條路：pad_depth 開啟「葉盤」模式（見 _canopy_pads）。枝角開得比
# 楓大(1.10~1.52)、wig 很小 —— 松枝是折線不是曲線，一節一節硬轉。
TREE_PINE = dict(
    trunk_r=0.040, trunk_len=0.30, depth=4, split=(3, 3, 2, 2),
    ang=(1.10, 1.52), lratio=(0.44, 0.64), rratio=(0.56, 0.70),
    up=(0.50, 0.02, -0.10, -0.16), wig=0.09, taper=0.22,
    leader=True, lead_ang=(0.08, 0.24), lead_lratio=(0.60, 0.74),
    # 葉盤模式：9 團（pad_depth=2 → 3×3），每團扁到 0.36，葉量集中。
    pad_depth=2, ntuft=1500, leaf=0.32, pad_flat=0.34, pad_bulk=1.55,
    pad_rmin=0.080,
    fol=0.046, flat=0.40,
    hull=(0.016, 0.030, 0.018),
    lo=(0.130, 0.245, 0.115), hi=(0.265, 0.395, 0.180))


# 三個品種：差在**骨架比例**（枝角、下垂、葉量），不是只換 seed ——
# 只換 seed 的話每棵的統計輪廓一樣，遠看仍是同一棵複製貼上。
MAPLE_OLD = dict(TREE_MAPLE, ang=(0.72, 1.28), up=(0.30, 0.08, -0.04, -0.20),
                 fol=0.080, ntuft=470, trunk_r=0.050)
MAPLE_MID = dict(TREE_MAPLE)
MAPLE_YNG = dict(TREE_MAPLE, ang=(0.50, 0.95), up=(0.40, 0.22, 0.10, -0.04),
                 fol=0.064, ntuft=500, trunk_r=0.038)


def build_tree(bld, x, y, h, seed, cfg):
    """遞迴分枝樹。h = 目標樹高（公尺）。"""
    rng = random.Random(seed)
    tips = []
    d0 = _norm3((rng.uniform(-0.10, 0.10), rng.uniform(-0.10, 0.10), 1.0))
    _grow(bld, tips, (x, y, 0.0), d0, h * cfg["trunk_r"], h * cfg["trunk_len"],
          0, cfg, rng, None, [0])
    if cfg.get("pad_depth") is not None:
        _canopy_pads(bld, rng, tips, cfg["ntuft"], cfg["leaf"] * h / 8.0,
                     cfg["hull"], cfg["lo"], cfg["hi"],
                     flat=cfg["pad_flat"], bulk=cfg["pad_bulk"],
                     rmin=h * cfg["pad_rmin"])
    else:
        _canopy_from_tips(bld, rng, tips, h * cfg["fol"], cfg["ntuft"],
                          cfg["leaf"], cfg["hull"], cfg["lo"], cfg["hi"])


# ── 2. 菜園 ──

def build_veg_garden(bld, cx, cy, seed):
    """菜園：手作感的關鍵不是「亂」，是**畦是直的、但畦與畦不對齊**。
    大小、角度、行距各自不同，畦間留的走道也寬窄不一 —— 那是有人每天
    踩出來的，不是機器犁出來的格線。"""
    rng = random.Random(seed)
    beds = [(-3.4, -2.1, 4.6, 1.9, 0.13), (2.3, -1.3, 3.0, 2.4, -0.21),
            (-2.4, 2.2, 5.4, 1.6, 0.04), (3.9, 2.6, 2.3, 2.0, 0.31),
            (-5.2, 4.6, 2.8, 1.5, -0.16)]
    for bi, (ox, oy, bw, bd, rot) in enumerate(beds):
        bx, by = cx + ox, cy + oy
        _rough_box(bld, bx, by, 0.11, bw, bd, 0.22, seed * 17 + bi,
                   C_SOIL, col_top=_mix(C_SOIL, C_STRAW, 0.14), yaw=rot, jit=0.07)
        rows = max(2, int(bd / 0.62))
        ca, sa = math.cos(rot), math.sin(rot)
        for r in range(rows):
            ry = (-bd / 2 + (r + 0.5) * (bd / rows)) * rng.uniform(0.92, 1.08)
            nper = max(3, int(bw / rng.uniform(0.52, 0.78)))
            for c in range(nper):
                rx = -bw / 2 + (c + 0.5) * (bw / nper) + rng.uniform(-0.07, 0.07)
                px = bx + rx * ca - ry * sa
                py = by + rx * sa + ry * ca
                s = rng.uniform(0.16, 0.30)
                for k in range(3):
                    a = rng.uniform(0.0, math.tau) + k * math.tau / 3.0
                    bld.tri2((px - math.cos(a) * s * 0.4, py - math.sin(a) * s * 0.4, 0.22),
                             (px + math.cos(a) * s * 0.4, py + math.sin(a) * s * 0.4, 0.22),
                             (px + math.cos(a) * s * 0.9, py + math.sin(a) * s * 0.9,
                              0.22 + s * rng.uniform(1.5, 2.4)),
                             _mix(C_LEAF, C_LEAF_LT, rng.random()))


# ── 3. 枯山水 + 靈氣裂縫（後院主角）──

def build_float_rock(bld, cx, cy, cz, sx, sy, sz, seed, gap=0.15, n_dash=7):
    """懸浮景觀石：上下兩塊之間裂開一道縫，縫裡是暖白的光。

    ⚠ 真正的自發光是 **Godot 端的 emissive 材質**；這份 .glb 只帶頂點色，
    這條高亮色帶是之後驅動 emission 用的來源（Feature List §3 本來就寫
    「內填⋯Emission」）。所以這裡的重點是把**裂縫的幾何**做出來、把顏色
    拉到明顯高於全場任何東西，而不是假裝 blockout 能發光。

    裂縫內壁切成長短不一的「筆畫」（亮/次亮交替、高度不一）—— 遠看是
    一條連續光帶，近看有字跡感。呼應阿求記錄幻想鄉緣起的設定：裂縫漏出
    來的是被記下來的歷史（規格裡 optional 的 rune 那條）。
    """
    rng = random.Random(seed)
    hd = sz * 0.46
    _rough_box(bld, cx, cy, cz - gap / 2 - hd / 2, sx, sy, hd, seed * 3 + 1,
               C_ROCK_DK, col_top=C_ROCK_DK, yaw=rng.uniform(0, math.tau), jit=0.17)
    _rough_box(bld, cx, cy, cz + gap / 2 + hd * 0.58, sx * 0.94, sy * 0.94, hd * 1.16,
               seed * 3 + 2, C_ROCK_DK, col_top=_mix(C_ROCK_DK, C_MOSS, 0.22),
               yaw=rng.uniform(0, math.tau), jit=0.17)
    # 裂縫：內縮一點，讓上下兩塊的邊緣稍微罩住光源（光才像是從「裡面」漏出來）
    for k in range(n_dash):
        u0 = -0.46 + k * (0.92 / n_dash)
        u1 = u0 + (0.92 / n_dash) * rng.uniform(0.55, 0.92)
        hz = gap * rng.uniform(0.55, 1.0)
        col = C_GLOW if k % 2 == 0 else C_GLOW_DIM
        _rough_box(bld, cx + (u0 + u1) * 0.5 * sx, cy, cz,
                   (u1 - u0) * sx, sy * rng.uniform(0.78, 0.94), hz,
                   seed * 5 + k, col, col_top=col, jit=0.05)


def build_karesansui(bld, cx, cy, r, seed, host, guests, floats):
    """枯山水：砂紋、石組（主賓）、苔、懸浮石。

    **砂紋是同心圓，圓心正好在懸浮石的正下方** —— 規格的核心：耙紋不是
    裝飾，是在敘事。像石頭落水那樣一圈圈盪開，把「靈氣正在擾動沙面」
    畫出來。所以這裡不用平行直紋（那是海波紋，講的是別的事）。

    砂床的外緣就是最外那圈波紋 —— 不另外畫一塊床再把圓紋裁進去，
    波紋本身定義了這片砂的形狀。
    """
    rng = random.Random(seed)
    n = 34
    n_ring = 28
    # ⚠ 所有圈**共用同一組噪聲相位**，半徑只差在倍率。
    # 每圈各自抽噪聲的話，內圈在某些角度會胖過外圈 —— 兩圈交叉重疊，
    # 共面的兩張同法線面互相擋掉環境光，整片砂紋變成一圈圈死黑的環。
    # （階梯側面 → 犬走り → 這裡，同一個病第四次踩到：**任何時候在同一個
    # 高度鋪兩片面，都要先證明它們不會重疊**。）
    # 共用相位 k(θ) 之後 r_i(θ) = r_i · k(θ) 對 i 嚴格遞增，數學上保證不交叉。
    rng_k = random.Random(seed * 31)
    terms = [(rng_k.randint(2, 4), rng_k.uniform(0.0, math.tau),
              rng_k.uniform(0.05, 0.11)) for _ in range(3)]

    def kdev(a):
        k = 1.0
        for f, ph, am in terms:
            k += am * math.sin(a * f + ph)
        return k

    ringpts = []
    for ri in range(n_ring + 1):
        rr = r * (ri / float(n_ring)) ** 0.92
        ringpts.append([(cx + math.cos(i / n * math.tau) * rr * kdev(i / n * math.tau),
                         cy + math.sin(i / n * math.tau) * rr * kdev(i / n * math.tau))
                        for i in range(n)])
    for ri in range(n_ring):
        a_ring, b_ring = ringpts[ri], ringpts[ri + 1]
        col = C_SAND if ri % 2 == 0 else C_SAND_DK
        for i in range(n):
            i2 = (i + 1) % n
            bld.quad((a_ring[i][0], a_ring[i][1], 0.05),
                     (b_ring[i][0], b_ring[i][1], 0.05),
                     (b_ring[i2][0], b_ring[i2][1], 0.05),
                     (a_ring[i2][0], a_ring[i2][1], 0.05), col)

    # 砂床外緣倒角：直接切一刀的話是一道 5cm 垂直斷崖，又變成「一盤砂
    # 放在草地上」（跟上一輪牆腳同一個病）。最外圈往外斜下去接到地面。
    outer = ringpts[n_ring]
    for i in range(n):
        i2 = (i + 1) % n
        ex0 = (cx + (outer[i][0] - cx) * 1.075, cy + (outer[i][1] - cy) * 1.075)
        ex1 = (cx + (outer[i2][0] - cx) * 1.075, cy + (outer[i2][1] - cy) * 1.075)
        bld.quad((outer[i][0], outer[i][1], 0.05), (ex0[0], ex0[1], 0.0),
                 (ex1[0], ex1[1], 0.0), (outer[i2][0], outer[i2][1], 0.05),
                 _mix(C_SAND_DK, C_EARTH, 0.45))

    # ── 石組：主賓關係 ──
    # 主石**立起來**、最大、稍微偏離中心；添石矮、退後、朝主石傾。
    # 三顆一樣大平均擺開就只是「三顆石頭」，沒有主從就沒有石組。
    hx, hy, hw, hh = host
    _rough_box(bld, hx, hy, hh * 0.42, hw, hw * 0.82, hh, seed * 41,
               C_STONE_DK, col_top=_mix(C_STONE_DK, C_MOSS, 0.30),
               yaw=rng.uniform(-0.5, 0.5), jit=0.19)
    # 主石腳下一圈苔：只在**基部**，不爬上石身。這圈苔是在講年份 ——
    # 石頭立在這裡夠久了，久到腳邊長出東西。稗田家一千年的家業，
    # 要有一個地方看得出時間。
    for i in range(n):
        i2 = (i + 1) % n
        a0, a1 = i / n * math.tau, i2 / n * math.tau
        r0 = hw * 0.62
        r1 = hw * (1.02 + 0.30 * math.sin(a0 * 3.0 + seed))
        r1b = hw * (1.02 + 0.30 * math.sin(a1 * 3.0 + seed))
        bld.quad((hx + math.cos(a0) * r0, hy + math.sin(a0) * r0, 0.062),
                 (hx + math.cos(a0) * r1, hy + math.sin(a0) * r1, 0.062),
                 (hx + math.cos(a1) * r1b, hy + math.sin(a1) * r1b, 0.062),
                 (hx + math.cos(a1) * r0, hy + math.sin(a1) * r0, 0.062),
                 _mix(C_MOSS, C_MOSS_LT, 0.5 + 0.5 * math.sin(a0 * 5.0)))
    for gi, (gx, gy, gw, gh) in enumerate(guests):
        # 添石朝主石傾：yaw 指向主石，高度只有主石的三~四成
        yaw = math.atan2(hy - gy, hx - gx)
        _rough_box(bld, gx, gy, gh * 0.36, gw, gw * 0.9, gh, seed * 53 + gi,
                   C_STONE_DK, col_top=_mix(C_STONE_DK, C_MOSS, 0.16),
                   yaw=yaw + rng.uniform(-0.2, 0.2), jit=0.20)

    # ── 懸浮石 ──
    for fi, (fx, fy, fz, fs) in enumerate(floats):
        build_float_rock(bld, fx, fy, fz, fs, fs * 0.78, fs * 0.62, seed * 67 + fi)
        # 地面的受光池：砂面上一圈被照亮的暈。這圈同時把「波紋圓心在這裡」
        # 再講一次 —— 光源、圓心、懸浮石三者對齊。
        for i in range(n):
            i2 = (i + 1) % n
            a0, a1 = i / n * math.tau, i2 / n * math.tau
            # 每顆石頭的受光池各給各的高度：兩池的半徑和大於兩石間距，
            # 擺同一個 z 就會共面重疊 → 又是一塊黑斑
            pz = 0.058 + fi * 0.007
            # ⚠ 半徑收到 0.95 倍、混色減半。第一版鋪到 1.7 倍又混得很重，
            # 兩片大白盤正好蓋掉砂紋的圓心 —— 而圓心就是「靈氣在擾動沙面」
            # 的敘事重點，等於為了加光暈把主題擦掉了。
            for k, (rr0, rr1, mixk) in enumerate([(0.0, fs * 0.55, 0.30),
                                                  (fs * 0.55, fs * 0.95, 0.13)]):
                col = _mix(C_SAND, C_GLOW, mixk / max(fz, 0.6))
                bld.quad((fx + math.cos(a0) * rr0, fy + math.sin(a0) * rr0, pz),
                         (fx + math.cos(a0) * rr1, fy + math.sin(a0) * rr1, pz),
                         (fx + math.cos(a1) * rr1, fy + math.sin(a1) * rr1, pz),
                         (fx + math.cos(a1) * rr0, fy + math.sin(a1) * rr0, pz), col)


# ── 4. 迂迴小徑（為後續劇情預留）──
#
# 需求有兩面：氣氛上要「有地方可以走過去」，結構上要留一個之後能接場景的
# 出口。所以路線**往外走、不繞回庭園**，終點做成「刻意的封閉」而不是斷頭 ——
# 一道打不開的木戶、兩側密植擋住視線，讀起來是「這邊還有路，只是現在過不去」。
#
# 視線設計：控制點刻意讓路在兩處折向，並在折點的內側放遮蔽物（樹叢／立石）。
# 站在起點看不到終點；走過第二個彎，木戶才整個露出來。一眼望穿的直路
# 沒有「還有東西沒看到」的感覺，也就留不住劇情空間。


def _spline(ctrl, samples):
    """Catmull-Rom 取樣。控制點只給大方向，實際曲線由樣條插出來 ——
    手打折線的路一定看得出折角。"""
    out = []
    m = len(ctrl)
    for s in range(samples + 1):
        u = s / float(samples) * (m - 1)
        i = min(int(u), m - 2)
        f = u - i
        p0, p1 = ctrl[max(i - 1, 0)], ctrl[i]
        p2, p3 = ctrl[i + 1], ctrl[min(i + 2, m - 1)]
        f2, f3 = f * f, f * f * f
        pt = []
        for k in range(2):
            pt.append(0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * f
                             + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * f2
                             + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * f3))
        out.append((pt[0], pt[1]))
    return out


def build_bush(bld, x, y, rx, rz, seed, n_sprig=80, leaf=0.62):
    """路邊灌木叢（裝飾性植栽）：野生的、有機的 —— 跟界線用的刈込み生垣
    刻意相反。但「有機」不等於「圓」。

    ⚠ 使用者第三次退件：「太圓了很像西瓜」。這個字眼在這個專案裡有前科 ——
    `make_hedge.py` 的 v15 就是因為「很像西瓜黏上去」被打回，那支的結論
    寫得很清楚，我前三版都沒有真的照做：

      1. **殼要很暗。** 那支的 HULL_DARK = 0.020；我一路用 0.115（亮五倍）。
         殼一亮就變成主視覺，葉子只是插在上面的刺 —— 這才是西瓜感的來源，
         不是團塊形狀不夠歪。前三版一直在調形狀，方向根本是錯的。
      2. **葉片要短而寬。** 我用 `wd = ln * 0.36`（細長三角形），正是那支
         註解裡點名會「變成仙人掌」的做法 —— 這種葉子撒再多也打不碎輪廓。
      3. **數量要夠。** 那支一個 2.4m 模組撒 430 叢；我一叢灌木才 44 叢。

    所以 v4 改的是這三件，形狀反而維持多團塊：殼壓到 0.030、葉子改短寬
    （0.72~0.95 倍寬長比）、叢數 44 → 125，另外補幾根露出來的枝幹
    （那支也有做「底下露枝幹」）。
    """
    rng = random.Random(seed)
    n_lobe = 2
    ctr_all = (x, y, rz * 0.78)
    lobes = []
    for li in range(n_lobe):
        ang = rng.uniform(0.0, math.tau)
        off = rx * rng.uniform(0.26, 0.50) if li else 0.0
        lobes.append(dict(
            lx=x + math.cos(ang) * off, ly=y + math.sin(ang) * off,
            lrx=rx * (1.0 if li == 0 else rng.uniform(0.55, 0.82)),
            lrz=rz * (1.0 if li == 0 else rng.uniform(0.50, 0.85)),
            ph=[rng.uniform(0.0, math.tau) for _ in range(3)],
            fr=[rng.uniform(2.6, 5.4) for _ in range(3)],
            sq=rng.uniform(0.78, 1.22)))

    def mk_surf(L):
        def surf(u, v):
            th, phi = u * math.tau, v * math.pi
            nx = math.sin(phi) * math.cos(th)
            ny = math.sin(phi) * math.sin(th)
            nz = math.cos(phi)
            k = 1.0 + 0.28 * (math.sin(th * L["fr"][0] + L["ph"][0])
                              + math.sin(phi * L["fr"][1] + L["ph"][1])
                              + math.sin((th * 0.7 + phi * 1.3) * L["fr"][2] + L["ph"][2])) / 1.8
            k = max(0.55, k)
            return ((L["lx"] + nx * L["lrx"] * k,
                     L["ly"] + ny * L["lrx"] * L["sq"] * k,
                     L["lrz"] * 0.82 + nz * L["lrz"] * k), (nx, ny, nz))
        return surf

    for L in lobes:
        surf = mk_surf(L)
        rows, cols = 6, 13
        for ri in range(rows):
            for ci in range(cols):
                v0, v1 = ri / rows, (ri + 1) / rows
                u0, u1 = ci / cols, (ci + 1) / cols
                _auto_quad(bld, ctr_all, surf(u0, v0)[0], surf(u1, v0)[0],
                           surf(u1, v1)[0], surf(u0, v1)[0],
                           _mix(C_BUSH_HULL, C_BUSH_DEEP, 0.06 + 0.22 * (1.0 - v0)))
        for _ in range(n_sprig // n_lobe):
            p_, nn = surf(rng.uniform(0.0, 1.0), rng.uniform(0.03, 0.97))
            _leaf_tuft(bld, rng, p_, nn, leaf, C_BUSH_MID, C_BUSH_LIT)
    # 底下露幾根枝幹：灌木不是浮在草上的一團，要看得到它從哪裡長出來
    for k in range(4):
        a = rng.uniform(0.0, math.tau)
        r0 = rx * rng.uniform(0.10, 0.34)
        bld.box(x + math.cos(a) * r0, y + math.sin(a) * r0, rz * 0.28,
                0.075, 0.075, rz * 0.56, C_BUSH_STEM)


def build_shrub_clump(bld, x, y, seed, n=2, spread=1.6, scale=1.0):
    """一處擺 2~3 株**小**灌木，不是一顆巨球。

    ⚠ 這是「西瓜」的最後一塊拼圖，也是前四版都沒看出來的：**尺寸本身**。
    原本一叢 rx=2.3（將近 5m 寬）—— 那不是灌木，是樹的體積。球面積隨
    半徑平方漲，5m 的球表面積約 55m²，要蓋滿它得撒上萬片葉（`make_hedge.py`
    的密度是 276 片/m²，而它之所以撒得起是因為一個模組只有 7.8m²）。
    面數上根本不可能，於是殼永遠露著 → 永遠是西瓜。
    收到 rx≈1.25（2.5m 寬、約 23m²），同樣的葉片數才蓋得住；
    要體積就用**叢生**補回來 —— 順帶比單顆巨球自然。
    """
    rng = random.Random(seed)
    for i in range(n):
        a = rng.uniform(0.0, math.tau)
        d = 0.0 if i == 0 else spread * rng.uniform(0.55, 1.0)
        rr = scale * (1.25 if i == 0 else rng.uniform(0.70, 0.96))
        hh = scale * (1.80 if i == 0 else rng.uniform(1.15, 1.55))
        build_bush(bld, x + math.cos(a) * d, y + math.sin(a) * d, rr, hh, seed * 7 + i)


def build_tobiishi(bld, ctrl, seed=77, specials=None):
    """飛石小徑：一塊塊埋進草皮的踏石，不是連續鋪面。

    路線／視線設計／終點沿用；「grown-in」用頂點色畫（頂面 tri_v 扇形，
    中心石色、外圈往苔綠混隨機量），側裙只露 6.5cm。

    **節奏**（本輪）：不是整條等距單石到底 —— 在幾個「該停一步」的點換
    語彙，其餘路段維持單石：
      ・兩個折點與終點木戶前：**大判の踏み分け石**（1.5~1.8×、更圓更整）
        或 **二枚打ち**（兩塊小石並置、微錯位）
      ・過了第一折的遮蔽樹叢、池面第一次整個露出來的位置：大石 ——
        腳下的石頭變大，人自然停下來，抬頭剛好是水面
    變化**集中在這些點**，不平均撒 —— 平均撒就只是隨機混尺寸，讀不出
    「這裡要你停」。specials: [(弧長, "landing"|"pair"), ...]。"""
    rng = random.Random(seed)
    pts = _spline(ctrl, len(ctrl) * 9)
    dists = [0.0]
    for i in range(1, len(pts)):
        dists.append(dists[-1] + math.hypot(pts[i][0] - pts[i - 1][0],
                                            pts[i][1] - pts[i - 1][1]))
    total = dists[-1]

    def at_dist(d):
        i = next(k for k in range(1, len(dists)) if dists[k] >= d)
        f = (d - dists[i - 1]) / (dists[i] - dists[i - 1] or 1.0)
        px = pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * f
        py = pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * f
        tx, ty = pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]
        tl = math.hypot(tx, ty) or 1.0
        return px, py, tx / tl, ty / tl

    def stone(px, py, scale=1.0, round_k=0.0):
        """一塊踏石。round_k→1 半徑趨於一致（大石要圓整，單石保持不規則）。"""
        rot = rng.uniform(0.0, math.tau)
        rr = [rng.uniform(0.40, 0.60) * (1.0 - round_k) + 0.52 * round_k
              for _ in range(8)]
        sh = rng.uniform(-0.03, 0.03)
        c_top = (C_STONE[0] + sh, C_STONE[1] + sh, C_STONE[2] + sh)
        zt = 0.065
        ring = []
        for k in range(8):
            a = rot + k / 8.0 * math.tau
            ring.append((px + math.cos(a) * rr[k] * scale,
                         py + math.sin(a) * rr[k] * scale * 0.88))
        for k in range(8):
            k2 = (k + 1) % 8
            c_e1 = _mix(c_top, C_MOSS, rng.uniform(0.22, 0.60))
            c_e2 = _mix(c_top, C_MOSS, rng.uniform(0.22, 0.60))
            bld.tri_v((px, py, zt), (ring[k][0], ring[k][1], zt),
                      (ring[k2][0], ring[k2][1], zt), c_top, c_e1, c_e2)
            bld.quad((ring[k][0], ring[k][1], zt), (ring[k][0], ring[k][1], 0.0),
                     (ring[k2][0], ring[k2][1], 0.0), (ring[k2][0], ring[k2][1], zt),
                     _mix(C_STONE_DK, C_MOSS, 0.35), flip=True)

    specials = sorted(specials or [], key=lambda q: q[0])
    d = 0.9
    while d < total - 1.2:
        # 特殊點落在這一步之內 → 放大石／二枚打ち，然後跳過它
        if specials and specials[0][0] <= d + 1.55:
            sd, kind = specials.pop(0)
            px, py, ux, uy = at_dist(sd)
            if kind == "pair":
                # 二枚打ち：兩塊小石並置、沿行進方向微錯位
                off = rng.uniform(0.42, 0.52)
                slip = rng.uniform(0.14, 0.26)
                stone(px - uy * off - ux * slip, py + ux * off - uy * slip, 0.82)
                stone(px + uy * off + ux * slip, py - ux * off + uy * slip, 0.82)
            else:
                stone(px, py, rng.uniform(1.5, 1.8), round_k=0.65)
            d = sd + rng.uniform(1.35, 1.65)
            continue
        px, py, ux, uy = at_dist(d)
        off = rng.uniform(-0.34, 0.34)
        stone(px - uy * off, py + ux * off)
        d += rng.uniform(1.15, 1.55)
    return pts, dists


def build_garden_lantern(bld, x, y, seed, h=1.30):
    """庭園裡的小型石燈籠（置き燈籠風）。

    **刻意比前庭那對簡單**：前庭的 stone_lantern.glb 是春日形（六角、
    火袋鏤空、蕨手），是儀式性的；這裡是私人庭園的道具，方形、矮、
    構件少 —— 兩者擺在同一張圖裡要一眼分得出「門面」與「日用」。
    幾何簡單到不值得開一個 .glb 資產，直接內建。"""
    rng = random.Random(seed)
    rot = rng.uniform(0.0, math.tau)
    sc = h / 1.30
    base_w = 0.42 * sc
    _rough_box(bld, x, y, 0.09 * sc, base_w, base_w, 0.18 * sc, seed * 3 + 1,
               C_STONE, col_top=_mix(C_STONE, C_MOSS, 0.30), yaw=rot, jit=0.08)
    bld.box(x, y, 0.42 * sc, 0.16 * sc, 0.16 * sc, 0.50 * sc, C_STONE_DK)     # 短竿
    bld.box(x, y, 0.72 * sc, 0.30 * sc, 0.30 * sc, 0.10 * sc, C_STONE)        # 中台
    # 火袋：四角柱夾出開口（方形，不是前庭的六角）
    for sx in (1, -1):
        for sy in (1, -1):
            bld.box(x + sx * 0.115 * sc, y + sy * 0.115 * sc, 0.95 * sc,
                    0.055 * sc, 0.055 * sc, 0.36 * sc, C_STONE_DK)
    bld.box(x, y, 1.16 * sc, 0.34 * sc, 0.34 * sc, 0.07 * sc, C_STONE)
    # 笠：方形四坡（一顆壓扁的 rough box 就夠 —— 這是日用道具）
    _rough_box(bld, x, y, 1.25 * sc, 0.52 * sc, 0.52 * sc, 0.12 * sc,
               seed * 3 + 2, C_STONE, col_top=_mix(C_STONE, C_MOSS, 0.42),
               yaw=rot, jit=0.10)
    bld.box(x, y, 1.36 * sc, 0.10 * sc, 0.10 * sc, 0.10 * sc, C_STONE_DK)     # 宝珠


def build_closed_gate(bld, px, py, ang, seed):
    """終點的「刻意封閉」：一道關著的木戶。

    不是斷頭路 —— 有柱、有門扇、有屋根、有門閂，只是打不開。兩側再密植
    擋住繞過去的可能。玩家讀到的是「這裡通往別處，只是現在不開」，
    而不是「地圖到此為止」。之後要開通的話，這裡就是接場景的地方。"""
    ca, sa = math.cos(ang), math.sin(ang)

    def P(u, v, z):
        return (px + u * ca - v * sa, py + u * sa + v * ca, z)

    for sd in (1, -1):                                       # 門柱
        for dz, w in ((1.35, 0.30),):
            v = sd * 1.45
            bld.box(px + (-v) * sa, py + v * ca, dz, w, w, 2.70, C_WOOD)
    # 門扇（關著）：直立板 ×5
    for k in range(5):
        v = -1.25 + (k + 0.5) * (2.50 / 5)
        c0 = P(0.0, v, 0.0)
        bld.box(c0[0], c0[1], 1.15, 0.46, 0.10, 2.10,
                C_WOOD_LT if k % 2 else _mix(C_WOOD_LT, C_WOOD, 0.35))
    for zz, th in ((0.55, 0.13), (1.72, 0.13)):              # 橫閂
        c0 = P(0.0, 0.0, 0.0)
        bld.box(c0[0], c0[1], zz, 2.60, 0.16, th, C_WOOD)
    c0 = P(0.0, 0.0, 0.0)
    bld.box(c0[0], c0[1], 2.42, 3.30, 0.34, 0.22, C_WOOD)    # 冠木
    for sd in (1, -1):                                       # 兩坡小屋根
        bld.quad(P(sd * 0.06, -1.75, 2.92), P(sd * 0.06, 1.75, 2.92),
                 P(sd * 0.90, 1.75, 2.56), P(sd * 0.90, -1.75, 2.56),
                 C_KAWARA, flip=(sd < 0))
    bld.box(c0[0], c0[1], 2.99, 3.60, 0.24, 0.16, C_RIDGE)


def _leaf_tuft(bld, rng, org, nrm, size, c_lo, c_hi, n_leaf=3):
    """一叢 3 片**短而寬**的葉。

    ⚠ 寬度要接近長度（0.72~0.95×）。`make_hedge.py` 踩過並寫在註解裡：
    細長三角形的葉子撒稀一點，整叢會變成仙人掌。我的灌木叢第一版正是
    `wd = ln * 0.36`（細長刺），所以葉子完全沒有把輪廓打碎的效果。"""
    nx, ny, nz = nrm
    ref = (0.0, 0.0, 1.0) if abs(nz) < 0.9 else (1.0, 0.0, 0.0)
    tx, ty, tz = ny * ref[2] - nz * ref[1], nz * ref[0] - nx * ref[2], nx * ref[1] - ny * ref[0]
    tl = math.sqrt(tx * tx + ty * ty + tz * tz) or 1.0
    tx, ty, tz = tx / tl, ty / tl, tz / tl
    bx, by, bz = ny * tz - nz * ty, nz * tx - nx * tz, nx * ty - ny * tx
    for k in range(n_leaf):
        a = rng.uniform(0.0, math.tau) + k * math.tau / n_leaf
        ln = size * rng.uniform(0.85, 1.30)
        wd = ln * rng.uniform(0.72, 0.95)
        dx = nx + (tx * math.cos(a) + bx * math.sin(a)) * 0.85
        dy = ny + (ty * math.cos(a) + by * math.sin(a)) * 0.85
        dz = nz + (tz * math.cos(a) + bz * math.sin(a)) * 0.85
        dl = math.sqrt(dx * dx + dy * dy + dz * dz) or 1.0
        tip = (org[0] + dx / dl * ln, org[1] + dy / dl * ln, org[2] + dz / dl * ln)
        p1 = (org[0] + tx * wd * 0.5, org[1] + ty * wd * 0.5, org[2] + tz * wd * 0.5)
        p2 = (org[0] - tx * wd * 0.5, org[1] - ty * wd * 0.5, org[2] - tz * wd * 0.5)
        bld.tri2(p1, p2, tip, _mix(c_lo, c_hi, rng.random() ** 0.7))


# 刈込み生垣的斷面：一側 → 過頂 → 另一側。(橫向偏移倍率, 高度倍率)
# 側面近垂直（0~0.62 幾乎不收）、頂緣才收進去 —— 這就是「修剪過」的讀法。
_HEDGE_PROF = [(-1.00, 0.00), (-1.00, 0.62), (-0.94, 0.88), (-0.52, 1.00),
               (0.00, 1.035), (0.52, 1.00), (0.94, 0.88), (1.00, 0.62), (1.00, 0.00)]


def build_clipped_hedge(bld, pts, seed, hw=0.46, skip_at=None, skip_r=5.5):
    """生垣（刈込み）：修剪過的條狀塊體，**刻意跟路邊灌木叢的有機輪廓相反**。

    邊界要一眼讀得出來，靠的是「語彙對比」：灌木叢是野的（多團塊、亂輪廓、
    亮綠），生垣是人工的（平頂、近垂直側面、深藍綠）。兩者用同一套幾何
    就會變成「同一種東西擺在不同地方」，界線還是讀不出來。

    技法沿用 `make_hedge.py`（村內生垣）驗證過的三件事：
      1. 殼要**很暗**（0.022 而不是 0.115）—— 殼是樹籬內部，本來照不到光。
         看得到殼就是葉子撒得不夠。
      2. 殼與葉**共用同一組剖面**，不然葉撒不到側面，露出光滑的殼。
      3. 葉片**短而寬**，不是細長刺（見 `_leaf_tuft`）。

    ⚠ 但**不能直接 instance hedge_a/b/c.glb**：一個 2.4m 模組 5,786 面，
    這圈約 240m 要 ~100 個模組 ≈ 58 萬面，而整個 blockout 現在才 4.2 萬。
    村內能用是因為 `gen_village.gd` 走 MultiMesh（每種變體一次 draw call）；
    blockout 只有一份 mesh，沒有這個選項。所以照技法重寫、密度按 blockout 調。
    Godot 端接手時應該換回 MultiMesh + hedge_*.glb。

    高度沿線起伏 1.0~1.4m，並在幾處**壓低或斷開**留視線缺口 —— 一圈等高
    密不透風的綠牆會把後院關成一個盒子。
    """
    rng = random.Random(seed)
    n = len(pts)
    # 視線缺口：t 是沿線的比例位置。dip = 壓低到看得過去，gap = 整段不畫。
    dips = [(0.14, 0.055), (0.47, 0.05), (0.78, 0.06)]
    gaps = [(0.315, 0.016), (0.635, 0.014)]

    def h_at(i):
        t = i / float(n - 1)
        for gt, gw in gaps:
            if abs(t - gt) < gw:
                return 0.0
        h = 1.20 + 0.20 * math.sin(t * 17.0 + seed) * 0.5 + 0.10 * math.sin(t * 41.0)
        for dt, dw in dips:
            k = max(0.0, 1.0 - abs(t - dt) / dw)
            h -= 0.62 * (k * k * (3 - 2 * k))          # smoothstep 壓低
        return max(0.0, min(1.42, h))

    def frame(i):
        a = pts[min(i + 1, n - 1)]
        b = pts[max(i - 1, 0)]
        tx, ty = a[0] - b[0], a[1] - b[1]
        tl = math.hypot(tx, ty) or 1.0
        return -ty / tl, tx / tl                        # 水平外法線

    def prof_pt(i, j):
        nx, ny = frame(i)
        o, zf = _HEDGE_PROF[j]
        h = h_at(i)
        return (pts[i][0] + nx * o * hw, pts[i][1] + ny * o * hw, zf * h)

    for i in range(n - 1):
        mx, my = (pts[i][0] + pts[i + 1][0]) * 0.5, (pts[i][1] + pts[i + 1][1]) * 0.5
        if skip_at and math.hypot(mx - skip_at[0], my - skip_at[1]) < skip_r:
            continue
        if h_at(i) < 0.05 or h_at(i + 1) < 0.05:
            continue
        ctr = (mx, my, (h_at(i) + h_at(i + 1)) * 0.25)
        for j in range(len(_HEDGE_PROF) - 1):
            _auto_quad(bld, ctr, prof_pt(i, j), prof_pt(i, j + 1),
                       prof_pt(i + 1, j + 1), prof_pt(i + 1, j),
                       _mix(C_HG_HULL, C_HG_DEEP, 0.10 + 0.35 * _HEDGE_PROF[j][1]))
        # 缺口與端點的封口
        for i_end, sd in ((i, -1), (i + 1, 1)):
            nb = i_end + sd
            if 0 <= nb < n and h_at(nb) >= 0.05:
                continue
            for j in range(len(_HEDGE_PROF) - 1):
                _auto_quad(bld, ctr, prof_pt(i_end, j), prof_pt(i_end, j + 1),
                           (pts[i_end][0], pts[i_end][1], _HEDGE_PROF[j + 1][1] * h_at(i_end)),
                           (pts[i_end][0], pts[i_end][1], _HEDGE_PROF[j][1] * h_at(i_end)),
                           C_HG_HULL)

    # 葉：沿頂緣與上側面撒，把修剪過的稜線「毛」掉一點點 —— 完全銳利的
    # 邊會變成塑膠模型，但也不能撒到把平頂打散（那就不是刈込み了）。
    for i in range(n - 1):
        mx, my = (pts[i][0] + pts[i + 1][0]) * 0.5, (pts[i][1] + pts[i + 1][1]) * 0.5
        if skip_at and math.hypot(mx - skip_at[0], my - skip_at[1]) < skip_r:
            continue
        if h_at(i) < 0.05:
            continue
        seg = math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
        for _ in range(max(1, int(seg * 3.4))):
            f = rng.random()
            jj = rng.uniform(1.0, len(_HEDGE_PROF) - 2.0)
            j0 = int(jj)
            fr = jj - j0
            p0 = prof_pt(i, j0)
            p1 = prof_pt(i, j0 + 1)
            base = (p0[0] + (p1[0] - p0[0]) * fr + (pts[i + 1][0] - pts[i][0]) * f,
                    p0[1] + (p1[1] - p0[1]) * fr + (pts[i + 1][1] - pts[i][1]) * f,
                    p0[2] + (p1[2] - p0[2]) * fr)
            nx, ny = frame(i)
            o = _HEDGE_PROF[j0][0]
            nz = 0.30 + 1.5 * _HEDGE_PROF[j0][1] ** 3
            nl = math.hypot(o, nz) or 1.0
            _leaf_tuft(bld, rng, base, (nx * o / nl, ny * o / nl, nz / nl),
                       0.135, C_HG_MID, C_HG_LIT)


def build_back_garden(bld):
    """把三區擺進後院，回傳要用 place_asset 擺的自然石清單。

    ── 尺度（第二輪修正）──
    第一版水池 r=6.4（直徑 13m）、枯山水 r=7.0，對上 25.5m 寬的主屋只有
    一半不到，讀起來是「屋子旁邊的兩個小擺設」而不是庭園本身。
    水池放大到 r=16（2.5×，直徑 32m ≈ 主屋寬），枯山水放大到 r=14（2×，
    砂紋因此有足夠半徑鋪出漸層）。兩者與主屋、以及兩者彼此之間都拉開：
      主屋背面 y=9.33 → 水池南緣 ≈17、枯山水南緣 ≈18（原本只有 1~4m）
      水池東緣 ≈-1 ↔ 枯山水西緣 ≈7（原本兩區幾乎相連）
    目的是讓每一區各自是一個「目的地」，不是擠成一團的裝飾。

    ── 位置的理由（跟第一輪相同，只是放大）──
    水池貼主屋北面 —— 南岸那片鏡面才照得到屋頂；
    涸れ滝在池的北緣 —— 從主屋往北看，視線越過鏡面正好落在瀑布上；
    枯山水在東側單獨一區 —— 主角要有自己的空間；
    菜園退到西北角 —— 最私密的擺最裡面。
    """
    PX, PY, PR = -17.0, 33.0, 16.0
    rim, r_at = build_pond(bld, PX, PY, PR, 5)

    def at_edge(deg, out):
        """池緣外 out 公尺處的座標。所有靠池的東西都照**實際池緣**擺 ——
        池岸是隨機起伏的，寫死座標換個 seed 就會站進水裡。"""
        a = math.radians(deg)
        rr = r_at(a) + out
        return (PX + math.cos(a) * rr, PY + math.sin(a) * rr)

    # 涸れ滝：池北緣，落差 4.6m。放大是為了配得上 32m 的池 —— 但仍然遠低於
    # 池本身的尺度，它是池裡的重音，不是蓋過池的主角。
    kb = at_edge(72.0, -0.6)
    kt = at_edge(72.0, 6.4)
    build_karetaki(bld, kt[0], kt[1], kb[0], kb[1], 4.6, 9)

    # 池畔楓 ×2：都在南岸（鏡面那側），大小與前後都不同
    m1 = at_edge(248.0, 2.2)
    m2 = at_edge(288.0, 1.6)
    # ── 楓的分佈 ──
    # 三個品種（老木／中木／若木），差在**比例與疏密**而不只是 seed ——
    # 只換 seed 的話每棵的輪廓統計上一樣，遠看還是同一棵複製貼上。
    #   老木 crown 1.25 / dens 0.72 / 3 叢：高、冠寬、葉疏
    #   中木 crown 1.00 / dens 1.00 / 2 叢
    #   若木 crown 0.72 / dens 1.30 / 2 叢：矮、冠緊、葉最密
    for mx, my, mh, ms, var in [
            (m1[0], m1[1], 11.0, 23, MAPLE_OLD), (m2[0], m2[1], 7.8, 41, MAPLE_MID),
            (35.6, 19.8, 8.6, 53, MAPLE_MID), (31.9, 47.6, 6.2, 59, MAPLE_YNG),
            (5.4, 21.1, 10.2, 67, MAPLE_OLD),          # 枯山水外緣
            (-8.0, 50.0, 9.4, 73, MAPLE_OLD), (12.5, 50.0, 6.6, 79, MAPLE_YNG),
            (24.5, 55.5, 8.0, 83, MAPLE_MID)]:         # 小徑沿線
        build_tree(bld, mx, my, mh, ms, var)

    # 菜園（西北角，退到最裡面）
    build_veg_garden(bld, -30.0, 52.0, 11)

    # 枯山水（東側）：波紋圓心 = 懸浮石正下方。石與懸浮石一併放大 ~1.6×，
    # 砂床變兩倍大而石頭不變的話，主賓關係在遠景就消失了。
    build_karesansui(
        bld, 21.0, 32.0, 14.0, 3,
        host=(25.0, 27.0, 2.10, 3.80),
        guests=[(28.4, 32.6, 1.25, 1.42), (21.0, 24.2, 1.00, 1.00)],
        floats=[(19.6, 32.8, 1.16, 2.20), (22.6, 35.6, 0.88, 1.55)])

    # 自然石：池畔散置。全部照池緣擺，並避開南岸鏡面（角度 230°~310°）。
    g1 = at_edge(196.0, 0.4)
    g2 = at_edge(126.0, 1.1)
    g3 = at_edge(38.0, 0.6)
    g4 = at_edge(158.0, 2.4)

    # ── 迂迴小徑：從池與枯山水之間出發，一路往東北的未開發地走 ──
    # 路線刻意兩次折向，折點內側擺遮蔽物：起點看不到終點，走過第二個彎
    # 木戶才整個露出來。往外走、不繞回庭園 —— 之後要延伸有地方接。
    PATH_CTRL = [(2.0, 20.0), (4.0, 31.0), (0.0, 42.0), (5.0, 52.0),
                 (15.0, 59.0), (27.0, 64.0), (PATH_END[0], PATH_END[1])]
    # 特殊點的弧長：兩個折點（樣條控制點 (0,42)、(15,59)）＋池面揭示點
    # （過了第一折的遮蔽樹叢 ~4m）＋終點木戶前。位置從樣條上找最近取樣點
    # 算弧長，不寫死數字 —— 之後動路線會自己跟著。
    _probe = _spline(PATH_CTRL, len(PATH_CTRL) * 9)
    _pd = [0.0]
    for _i in range(1, len(_probe)):
        _pd.append(_pd[-1] + math.hypot(_probe[_i][0] - _probe[_i - 1][0],
                                        _probe[_i][1] - _probe[_i - 1][1]))

    def _arc_near(tx, ty):
        return _pd[min(range(len(_probe)),
                       key=lambda k: math.hypot(_probe[k][0] - tx, _probe[k][1] - ty))]

    _bend1 = _arc_near(0.0, 42.0)
    _bend2 = _arc_near(15.0, 59.0)
    path_pts, _ = build_tobiishi(bld, PATH_CTRL, specials=[
        (_bend1, "landing"),                  # 第一折：大石
        (_bend1 + 4.0, "landing"),            # 過遮蔽樹叢、池面整個露出來
        (_bend2, "pair"),                     # 第二折：二枚打ち
        (_pd[-1] - 2.6, "landing"),           # 木戶前：停一步再面對關著的門
    ])
    # ── 小型石燈籠 ×4：單獨擺、間距不等、左右交錯但偏移量各自不同 ——
    # 成對鏡射是前庭的語言。位置沿樣條取比例點，路線改了會自己跟著。
    for t, side, off, ls, lh in [(0.16, 1, 1.7, 201, 1.30), (0.40, -1, 2.1, 202, 1.14),
                                 (0.63, 1, 1.5, 203, 1.38), (0.87, -1, 1.9, 204, 1.22)]:
        i = int(t * (len(path_pts) - 2))
        tx = path_pts[i + 1][0] - path_pts[i][0]
        ty = path_pts[i + 1][1] - path_pts[i][1]
        tl = math.hypot(tx, ty) or 1.0
        build_garden_lantern(bld, path_pts[i][0] - ty / tl * side * off,
                             path_pts[i][1] + tx / tl * side * off, ls, h=lh)
    # ── 灌木叢重新分佈 ──
    # 原本六叢全擠在小徑前段，其中兩叢（7.6,35 / 6.2,39.6）還直接壓在
    # 枯山水的砂床上 —— 耙好的砂上不能長東西，那片必須淨空。
    # 改成四個帶：折點內側（視線遮蔽，留兩叢）／池畔／縁側前／生垣內側。
    # 枯山水足跡（中心 21,32、有機外緣 ~16.1m）已逐叢驗過淨空。
    for bx, by, bs, bn in [
            (-1.0, 45.8, 63, 3), (10.6, 53.4, 64, 2),      # 折點內側（視線遮蔽）
            (20.0, 61.6, 65, 2),                            # 第二折之後
            (-33.6, 45.4, 61, 2), (-4.2, 15.8, 62, 2),     # 池畔（東北岸／東南岸）
            (7.2, 13.1, 67, 2), (-6.0, 13.3, 68, 2),       # 縁側前（離基壇 1.2~1.4m）
            (-40.5, 27.0, 69, 3), (31.5, 52.5, 70, 2),     # 生垣內側
            (-8.5, 69.5, 71, 2)]:                           # 生垣內側（北段）
        build_shrub_clump(bld, bx, by, bs, n=bn)
    # 終點：關著的木戶 + 兩側密植（不是斷頭路，是「現在過不去」）
    build_closed_gate(bld, PATH_END[0], PATH_END[1], PATH_END_ANG, 71)
    # ── 生垣（刈込み）：後院外周，高 1.0~1.4m 起伏 + 視線缺口 ──
    # 木戶那一段留 5.5m 開口，垣與門接在一起 —— 分開的話會變成「一道垣
    # 旁邊另外立著一扇門」，門就不是這道界線的出入口了。
    # 兩端**埋進主屋基壇 0.3m**（基壇角落在 ±13.84, 9.33；端點 ±13.5, 8.8
    # 在基壇footprint內），整圈的封閉由「生垣＋建築本體」共同完成。
    # 原本端點在 (±16, 10)，離基壇角落懸空 ~2.3m —— 界線在建築兩側各開
    # 一個大洞，跟規格裡刻意留的窄視線缺口完全是兩回事。
    # 端點只埋 0.3m 不多埋：埋深了會從基壇另一側戳出來。
    FENCE = [(13.5, 8.8), (16.0, 10.0), (36.0, 16.0), (45.0, 34.0), (42.0, 54.0),
             (36.0, 66.0), (26.0, 72.0), (8.0, 76.0), (-12.0, 74.0), (-30.0, 68.0),
             (-46.0, 54.0), (-50.0, 34.0), (-42.0, 16.0), (-16.0, 10.0), (-13.5, 8.8)]
    build_clipped_hedge(bld, _spline(FENCE, len(FENCE) * 13), 91,
                        skip_at=PATH_END, skip_r=5.5)
    # 兩側密植往外挪、收小一號：擋得住繞路，但不會把木戶壓成配角 ——
    # 終點要讀成「一道關著的門」，不是「兩叢樹中間有東西」
    for sd in (1, -1):
        build_shrub_clump(bld, PATH_END[0] - math.sin(PATH_END_ANG) * sd * 5.4,
                          PATH_END[1] + math.cos(PATH_END_ANG) * sd * 5.4,
                          80 + sd, n=3, spread=1.9)
    return [
        ("rock_c", g1[0], g1[1], 0.30, 0.6, (1.15, 1.15, 1.30)),
        ("rock_a", g2[0], g2[1], 0.22, 2.1, (1.30, 1.30, 1.05)),
        ("rock_b", g3[0], g3[1], 0.20, 1.2, (1.25, 1.25, 1.00)),
        ("rock_d", g4[0], g4[1], 0.26, 0.4, (0.95, 0.95, 0.80)),
        ("rock_b", 33.5, 40.0, 0.24, 2.6, (1.35, 1.35, 1.10)),
    ]


def place_asset(model, xforms):
    """把**已經定案的** .glb（狛犬、石燈籠、松）載進場景擺位，回傳物件清單。

    為什麼不把幾何抄進這支檔案：狛犬在 make_props.py 已經改過三輪才過關，
    抄一份過來就等於開了第二個真相來源，下次改狛犬會有一隻沒跟到。
    這裡只負責「擺哪裡」，造型永遠是 make_props.py 說了算。

    ⚠ 匯入的網格顏色屬性名字不一定叫 "Col"（glTF 匯入器有時給 "Color"），
    而 export_sel() 的 join 是**照名字合併**屬性的 —— 名字對不上，
    合併後那半邊的顏色會整片變成預設值（白）。所以這裡強制正規化成
    跟 B.build() 一樣的 BYTE_COLOR / CORNER / "Col"。"""
    path = os.path.join(OUT_DIR, model + ".glb")
    out = []
    for i, (px, py, pz, rot, sc) in enumerate(xforms):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        fresh = [o for o in bpy.data.objects if o not in before]
        meshes = [o for o in fresh if o.type == "MESH"]
        for o in meshes:
            o.parent = None
            o.location = (px, py, pz)
            o.rotation_euler = (0.0, 0.0, rot)
            # sc 可以是純量或 (x, y, z) —— 庭石要壓扁或拉高才有「立石／臥石」
            o.scale = tuple(sc) if isinstance(sc, (tuple, list)) else (sc, sc, sc)
            me = o.data
            ca = me.color_attributes
            if len(ca):
                if ca[0].name != "Col" or ca[0].domain != "CORNER" or ca[0].data_type != "BYTE_COLOR":
                    src = [tuple(d.color) for d in ca[0].data]
                    dom, typ = ca[0].domain, ca[0].data_type
                    ca.remove(ca[0])
                    new = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
                    for poly in me.polygons:
                        for li in poly.loop_indices:
                            vi = me.loops[li].vertex_index
                            new.data[li].color = src[vi] if dom == "POINT" else src[li]
            out.append(o)
        # glTF 匯入會多帶一個空的場景根節點，不清掉 join 時會抓到它當 active
        for o in fresh:
            if o.type != "MESH":
                bpy.data.objects.remove(o, do_unlink=True)
    return out


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

# ── 產出 2：Blockout（主屋 + 參道 + 巨樹框景 + 前庭門牆與添景）──
# ⚠ 巨樹直接寫進同一個 bld —— 房子＋參道＋兩棵樹是**一份網格**。
# 狛犬／石燈籠／松是 make_props.py 定案的獨立資產，用 place_asset() 載進來
# 擺位，最後在 export_sel() 裡一起 join 成同一份 mesh（仍是 1 個 draw call）。
clear()
bld = B()
w, d, pod = build_house(bld)

# 參道：從石階腳下（y=-11.43）一路連到門外，中間不斷開。
Y_STEP = -11.43                          # 唐破風石階最外緣
Y_GATE = -34.0                           # 表門：主殿正面前推 ~27m（§3：25~30m）
Y_OUT = -40.5                            # 外側參道端點
build_avenue(bld, Y_STEP, Y_OUT, width=6.0)

# 前庭圍牆：正面一道 + 兩側短回折（本輪只做參道視角看得到的範圍）
WALL_HX = 19.0
# ⚠ 不要叫 GATE_HW —— 模組層已經有一個 GATE_HW=2.9（唐破風玄関的開口半寬，
# build_house 在用）。在這裡同名再指派一次會把模組層那個整個蓋掉，之後
# 任何人再呼叫 build_house() 就會拿到 3.6，玄関的窗、高欄、腰簷缺口全部跑掉。
MON_HW = 3.6                             # 表門門洞半寬，6m 參道穿得過
MON_POST_HW = 0.35                       # 門柱半寬
# 牆的缺口要把**門柱也讓出來**（MON_HW + 兩根柱寬），柱子才站得出來；
# 缺口只讓門洞的話柱子會整根埋在牆身裡。
build_wall_run(bld, -WALL_HX, WALL_HX, Y_GATE, axis="x",
               gate_hw=MON_HW + 2 * MON_POST_HW)
build_gate(bld, Y_GATE, MON_HW, MON_POST_HW)
# 兩側回折：一路拉到主屋側面（y=-6）才收。第一版只往北 12m 就停在半空中，
# 空中斷頭的牆比沒有牆還糟。北面與東西後段留給 §3 郭外防線那輪補完整圈。
# apron_trim 把回折的犬走り往內縮 1.9m —— 不縮的話轉角處會跟正面那道的
# 犬走り**完全共面重疊**，兩張同法線的面互相擋住對方的環境光，整塊算成
# 全黑（跟唐破風那輪階梯側面同一個病，見 docs）。
for sx in (1, -1):
    build_wall_run(bld, Y_GATE, -6.0, sx * WALL_HX, axis="y", apron_trim=(1.9, 0.0))

build_giant_tree(bld, +4.9, -20.4, 11)
build_giant_tree(bld, -4.9, -21.5, 47)

# ── 對稱添景：狛犬 / 石燈籠 / 松，三對沿參道由內而外、由窄而寬排開 ──
# 前庭深 22.6m（門 -34 → 石階 -11.4）。狛犬擺在「從外側參道往內約 1/3」
# 處 = -34 + 22.6/3 ≈ -26.5。燈籠與松依序往外側讓開，形成一個漸開的
# 八字 —— 站在門口往內看，三對物件把視線收束到唐破風玄関上。
# 門前的松：改用遞迴樹產生器。tree_pine_a.glb 是「圓錐插在棍子上」，
# 跟舊版楓同一個病；這裡不動那個共用資產（村裡還在用），改成在
# 稗田邸自己長兩棵。
build_tree(bld, 9.90, -30.60, 7.6, 151, TREE_PINE)
build_tree(bld, -9.50, -30.90, 8.8, 157, TREE_PINE)
garden_rocks = build_back_garden(bld)
objs = [bld.build("hieda_scene")]
# 狛犬**維持左右嚴格對稱**：牠是儀式性的門衛，一對石獅子擺歪就只是沒對齊。
# 原型面朝 -y，繞 z 轉 θ 後朝向是 (sinθ, -cosθ)，θ=-sx*1.0 讓兩隻都斜對
# 參道中線、同時偏向來人（約 57°）。
# 放大到 1.18：門柱同時降到 3.30，兩邊各讓一步之後狛犬（3.25m）跟門柱
# （3.30m）幾乎同高，才「carry equal visual weight」而不是被門吃掉。
for sx in (1, -1):
    objs += place_asset("komainu_a", [(sx * 4.7, -26.5, 0.0, -sx * 1.0, 1.18)])

# ── 松與燈籠：刻意**不對稱** ──
# 上一版兩側是完全鏡射、而且燈籠與松等距排開，讀起來像貼上去的裝飾而不是
# 長出來的庭園。這裡把兩側的間距、前後、大小全部拆開寫成明表（不用 for
# 迴圈鏡射）—— 迴圈天生只會生出對稱，要不對稱就得放棄迴圈。
#   右側：燈籠緊挨狛犬（1.9m），松再往外拉開（4.8m）—— 疏密對比大
#   左側：燈籠退遠（3.6m），松貼著燈籠（2.9m）—— 節奏跟右側相反
for mdl, px, py, rot, sc in [
        ("stone_lantern", 6.50, -27.20, 0.26, 1.06),
        ("stone_lantern", -7.40, -28.90, -0.62, 0.98)]:
    objs += place_asset(mdl, [(px, py, 0.0, rot, sc)])

# ── 後院（主屋北面）── 設計語言刻意跟前庭相反：沒有任何鏡射與等距。
for mdl, px, py, pz, rot, sc in garden_rocks:
    objs += place_asset(mdl, [(px, py, pz, rot, sc)])
export_sel(objs, "hieda_blockout")

# ── 後院小徑終點的觸發區座標，寫成資料檔給 Godot 端用 ──
# 手抄一份到 meta.json 的話，之後挪動木戶就會忘了改觸發區。這裡直接從
# 建幾何用的同一個 PATH_END 算出來，永遠對得上。
# 座標轉換：glTF 是 export_yup=True，Blender(Z-up) → Godot(Y-up) 是
#   godot_x = blender_x、godot_y = blender_z、godot_z = -blender_y
# target 留 null = 保留中。main.gd 看到 null 仍會建 Area3D 並接上偵測，
# 只是不執行切換；哪天填上目的地就自動變成正常傳送點，不用再改程式。
_marker = {
    "note": "稗田邸後院小徑終點（木戶）。target 待指定；填上之後即生效。",
    "portals": [{"x": round(PATH_END[0], 3), "y": 0.9,
                 "z": round(-PATH_END[1], 3), "target": None}],
}
_mpath = os.path.join(os.path.dirname(OUT_DIR.rstrip("/")), "..", "data",
                      "hieda_garden.markers.json")
_mpath = os.path.normpath(_mpath)
try:
    os.makedirs(os.path.dirname(_mpath), exist_ok=True)
    with open(_mpath, "w", encoding="utf-8") as fh:
        json.dump(_marker, fh, ensure_ascii=False, indent=2)
    print("wrote %s" % _mpath)
except OSError as e:
    print("!! marker 寫入失敗：%s" % e)
print("done")
