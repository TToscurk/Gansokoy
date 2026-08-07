# 人間之里 街區重設計：町家與主橋的**模組庫**。
#
#   blender -b -P make_town.py -- <outdir>
#
# ⚠ 這支只做模組，**不在 Blender 組街**。佈局（河道、街區、階梯天際線、
# 交錯排列）全部在 Godot 端的 tools/gen_town.gd —— 那邊讀 data/town_modules.json
# 拿到每個模組的尺寸，用 MultiMesh 批次實例。這是開工前就定案的分工：
# 「Blender builds modules only; layout logic lives in a Godot-side generator」。
# 在 Blender 組整條街再匯入 = 毀掉 MultiMesh（稗田邸走過一次回頭路，
# 92,854 面 → 拆完 22,600，這次第一步就走對的路）。
#
# 模組清單（尺寸寫進 town_modules.json，產生器照表擺位）：
#   machiya_f_a / f_b   前排町家  總高 **4.5 / 4.5**（使用者定案：壓到下限）
#                       同高之後的變化改由面寬 7.6/8.8 與屋頂 23°/26° 帶
#   machiya_b_a / b_b   後排町家  總高 9.4 / 9.9（規格 9~10），屋頂 45°
#   machiya_e_a         村緣小屋  總高 3.5（規格）
#   bridge_main         12m 寬半拱木橋（拱高 +1.5、欄杆 1.15、親柱加大）
#
# 高度**做進模組**，不用 y 縮放做 —— y 縮放會改屋頂斜度，而 45° 是規格。
# 顏色沿用村內／稗田邸的頂點色慣例（linear、BYTE_COLOR/CORNER/"Col"）。
import bpy, sys, os, math, random, json

OUT_DIR = "godot/assets/models"
argv = sys.argv
if "--" in argv:
    OUT_DIR = argv[argv.index("--") + 1]

# ── 頂點色（linear。glTF COLOR_0 不做色彩空間轉換，Godot 端直接當 albedo）──
C_PLASTER = (0.760, 0.740, 0.690)      # 白漆喰
C_PLASTER_DK = (0.660, 0.635, 0.575)   # 一層陰影帶
C_WOOD = (0.165, 0.135, 0.110)         # 深色木（柱、格子）
C_WOOD_LT = (0.240, 0.200, 0.160)      # 淺木（板、門）
C_WOOD_MID = (0.205, 0.168, 0.132)
C_KAWARA = (0.235, 0.255, 0.300)       # 瓦（藍灰）
C_KAWARA_DK = (0.185, 0.200, 0.240)
C_RIDGE = (0.290, 0.310, 0.355)        # 棟
C_STONE = (0.520, 0.520, 0.500)        # 基石
C_STONE_DK = (0.420, 0.425, 0.415)
C_SHOJI = (0.870, 0.850, 0.780)        # 障子紙
C_DECK = (0.300, 0.228, 0.152)         # 橋面板（日曬過的木 —— 要暖，
C_DECK_DK = (0.246, 0.184, 0.120)      # 第一版 0.36 灰階太高，整座讀成水泥橋）
C_BEAM = (0.225, 0.172, 0.124)         # 橋樑構材
C_GIBO = (0.300, 0.285, 0.240)         # 擬宝珠（銅綠前的木/金屬色）
C_NOREN = (0.145, 0.170, 0.235)        # 暖簾（藍染）—— 食堂的招牌色
C_CHOCHIN = (0.780, 0.560, 0.230)      # 提灯（點著的暖橘）
C_BAMBOO = (0.400, 0.365, 0.200)       # 犬矢来的竹


def clampf_(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)


def _mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


class B:
    """三角形累加器（同 make_hieda.py 的慣例：一模組一 mesh、頂點色、flat）。"""

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

    def box(self, cx, cy, cz, w, d, h, col, top=None, skip_bottom=True):
        x0, x1 = cx - w / 2, cx + w / 2
        y0, y1 = cy - d / 2, cy + d / 2
        z0, z1 = cz - h / 2, cz + h / 2
        top = top or col
        self.quad((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), top)
        if not skip_bottom:
            self.quad((x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0), col)
        self.quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), col)
        self.quad((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1), col)
        self.quad((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1), col)
        self.quad((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1), col)

    def build(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        me.update()
        ca = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        li = 0
        for pi, poly in enumerate(me.polygons):
            poly.use_smooth = False
            c = self.cols[pi]
            for _ in range(poly.loop_total):
                ca.data[li].color = (c[0], c[1], c[2], 1.0)
                li += 1
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        return ob


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


# ── 町家 ──
# 模組座標約定：**面向 -y**（正面朝 -y，跟稗田邸資產同一慣例），
# 原點在正面地面中心 —— 產生器把「臨街線」對到模組原點就好，
# 不用知道進深。x = 面寬方向。


def gable_roof(bld, cx, cy, z_wall, w, d, pitch, overhang=0.85, thick=0.16,
               kaw=C_KAWARA):
    """切妻屋根：稜線沿 x（平入 —— 町家臨街的標準形）。
    pitch 是**弧度**。45° 規格靠這個參數保證，所以不准用 z 縮放調高度。

    ⚠ 屋脊錨在**牆面**：ridge = z_wall + (d/2)·tanθ；出簷從牆頂沿同一斜度
    **往外往下**包（eave z = z_wall - ov·tanθ）。第一版把 rise 用含出簷的
    半深算、屋頂又整個坐在牆頂上 —— 45° 配 0.85 出簷平白多出 0.85m 高，
    後排總高衝到 12m（規格 9~10）。總高規格由 machiya() 反推屋身高保證。"""
    hw = w / 2 + overhang
    hd = d / 2 + overhang
    ridge_z = z_wall + (d / 2) * math.tan(pitch)
    eave_z = z_wall - overhang * math.tan(pitch)
    for sy in (1, -1):
        a = (cx - hw, cy, ridge_z)
        b = (cx + hw, cy, ridge_z)
        c = (cx + hw, cy + sy * hd, eave_z)
        dd = (cx - hw, cy + sy * hd, eave_z)
        bld.quad(a, b, c, dd, kaw, flip=(sy > 0))
        # 屋面厚度（簷口斷面）——沒有這條，屋頂是一張紙
        e = (cx + hw, cy + sy * hd, eave_z - thick)
        f = (cx - hw, cy + sy * hd, eave_z - thick)
        bld.quad(dd, c, e, f, C_KAWARA_DK, flip=(sy > 0))
        # 簷底（仰視面）：從簷口回收到牆面
        bld.quad((cx - hw, cy + sy * hd, eave_z - thick),
                 (cx + hw, cy + sy * hd, eave_z - thick),
                 (cx + hw, cy + sy * (d / 2 - 0.05), z_wall - thick),
                 (cx - hw, cy + sy * (d / 2 - 0.05), z_wall - thick),
                 C_KAWARA_DK, flip=(sy < 0))
    # 山牆（兩端三角形）＋棟
    for sx in (1, -1):
        gx = cx + sx * hw
        bld.tri((gx, cy - hd, eave_z), (gx, cy + hd, eave_z),
                (gx, cy, ridge_z), C_KAWARA_DK, flip=(sx < 0))
    bld.box(cx, cy, ridge_z + 0.055, hw * 2 + 0.24, 0.42, 0.17, C_RIDGE)
    return ridge_z


def machiya(bld, W, D, target_h, storeys, pitch, seed, plinth=0.30):
    """一棟町家。**屋身高由目標總高反推** —— 規格（前排 4.5~5.5、後排 9~10
    含 45° 屋頂、村緣 3.5）由建構保證，不是蓋完再量。回傳實際總高。

    造型語彙抄現有村子的 _longhouse（基石→屋身→真壁柱樑→格子帶→切妻瓦）。
    """
    rng = random.Random(seed)
    body_h = target_h - plinth - (D / 2) * math.tan(pitch) - 0.14   # 0.14=棟
    assert body_h > 1.8, "反推出的屋身太矮：D=%.1f pitch=%.0f°" % (
        D, math.degrees(pitch))
    cy = D / 2                                    # 正面在 y=0，屋身往 +y
    # 基石
    bld.box(0, cy, plinth / 2, W + 0.22, D + 0.22, plinth, C_STONE, top=C_STONE_DK)
    z0 = plinth
    # 屋身
    bld.box(0, cy, z0 + body_h / 2, W, D, body_h, C_PLASTER)
    # 真壁：柱（正面 + 四角）
    # ⚠ 模組面朝 -y、屋身佔 y∈[0,D] —— 立面元素要**往 -y 凸出牆外**。
    # 第一版全寫成小的 +y 偏移 = 全部埋進牆裡；二階窗背面剛好貼在 y=0
    # 牆面上（共面 → 渲染成黑洞，這個病第五次）。所有立面偏移一律負值，
    # 而且**不許有任何面正好落在 y=0**。
    nbay = max(2, int(W / 2.9))
    for i in range(nbay + 1):
        px = -W / 2 + i * (W / nbay)
        bld.box(px, -0.035, z0 + body_h / 2, 0.17, 0.13, body_h, C_WOOD)
    for sx in (1, -1):
        bld.box(sx * (W / 2 + 0.02), cy, z0 + body_h / 2, 0.13, 0.13, body_h, C_WOOD)
    # 樑（正面：足元、中段、桁）
    mid_z = min(2.15, body_h - 0.45)
    for zz in (0.10, mid_z, body_h - 0.12):
        bld.box(0, -0.045, z0 + zz, W + 0.1, 0.11, 0.15, C_WOOD)
    # 一階正面：格子窗帶 + 入口（高度夾進「足元樑～中段樑」之間 ——
    # 村緣小屋 body 只有 1.9，寫死 1.55 的格子會戳進屋頂）
    lat_z0 = z0 + 0.24
    lat_h = mid_z - 0.32
    door_bay = rng.randrange(nbay)
    for i in range(nbay):
        bx = -W / 2 + (i + 0.5) * (W / nbay)
        bw = W / nbay - 0.42
        if i == door_bay:
            # 入口：板戶（微凸 —— blockout 不做真的內凹）
            bld.box(bx, -0.045, lat_z0 + lat_h / 2, bw * 0.82, 0.07, lat_h, C_WOOD_LT)
            bld.box(bx, -0.075, lat_z0 + lat_h / 2, 0.07, 0.05, lat_h, C_WOOD)
        else:
            # 格子（連子格子：一片暗底 + 細直櫺）
            bld.box(bx, -0.050, lat_z0 + lat_h / 2, bw, 0.05,
                    lat_h, _mix(C_WOOD, (0, 0, 0), 0.25))
            nsl = max(3, int(bw / 0.17))
            for k in range(nsl):
                sxp = bx - bw / 2 + (k + 0.5) * (bw / nsl)
                bld.box(sxp, -0.090, lat_z0 + lat_h / 2, 0.055, 0.045,
                        lat_h, C_WOOD_MID)
    if storeys >= 2:
        # 二階窓（虫籠窓風：矮橫窗）
        n2 = max(1, nbay - 1)
        for i in range(n2):
            bx = -W / 2 + (i + 1) * (W / nbay) - W / nbay * 0.5 + rng.uniform(-0.1, 0.1)
            bld.box(bx, -0.050, z0 + body_h - 1.15, W / nbay * 0.52, 0.08, 0.78, C_SHOJI)
            for k in range(4):
                bld.box(bx - W / nbay * 0.26 + (k + 0.5) * W / nbay * 0.13, -0.095,
                        z0 + body_h - 1.15, 0.05, 0.05, 0.78, C_WOOD_MID)
        # 一二階之間：腰簷（下屋般的細簷 —— 沒有它，兩層樓是一面平牆）
        ko_z = z0 + body_h * rng.uniform(0.44, 0.50)
        bld.box(0, -0.28, ko_z, W + 0.7, 0.95, 0.10, C_KAWARA_DK, top=C_KAWARA)
        # 卯建（兩側防火牆立上）——後排高町家的剪影特徵
        # ⚠ 卯建要**穿出屋面**才看得到。第一版頂在 z0+body_h（牆頂）、
        # 外緣只到 W/2+0.10，整片埋在 0.85m 的出簷底下 —— 實測街道正面／
        # 3/4 視角各 0 像素，等於白做（而註解還寫著「後排高町家的剪影特徵」）。
        for sx in (1, -1):
            ud_top = z0 + body_h + (D / 2) * math.tan(pitch) * 0.72
            bld.box(sx * (W / 2 + 0.62), cy * 0.72, (z0 + 0.9 + ud_top) / 2,
                    0.20, D * 0.46, ud_top - z0 - 0.9,
                    C_PLASTER_DK, top=C_KAWARA_DK)
    # 一階陰影帶（貼地一圈微暗 —— 頂點色的接觸陰影，稗田邸驗過的手法）
    bld.box(0, cy, z0 + 0.10, W + 0.04, D + 0.04, 0.20, C_PLASTER_DK)
    ridge = gable_roof(bld, 0, cy, z0 + body_h, W, D, pitch)
    # 立面錨點：密度層的吊掛（暖簾／提灯／招牌）要對齊**真的門與樑**。
    # 每種模組是一個固定 glb（seed 固定 → door_bay 固定），所以這些
    # 座標對該 kind 是常數，寫進 manifest 給 gen_town 讀。
    # door_x 是 Blender x = Godot x；beam_z 取中段樑**底緣**（吊掛頂點）。
    facade = {
        "door_x": round(-W / 2 + (door_bay + 0.5) * (W / nbay), 3),
        "door_w": round((W / nbay - 0.42) * 0.82, 3),
        "beam_z": round(z0 + mid_z - 0.075, 3),
        "bay_w": round(W / nbay, 3), "nbay": nbay}
    return ridge + 0.055 + 0.17 / 2, facade


# ── 12m 半拱木橋 ──


def bridge_main(bld, span=22.0, width=12.0, rise=1.5, rail_h=1.15,
                nseg=14, npost=12, oya=0.50, abut=True):
    """日式半拱木橋（太鼓橋的緩拱版）。

    模組座標：橋面沿 **x**（過橋方向 = x），寬沿 y，原點在橋中心地面。
    拱：z = rise·cos(π/2 · x/(span/2))^0.9 —— 端點落地、中央 +rise，
    比純圓弧的端部斜率緩，走起來不像溜滑梯。

    親柱隨橋寬放大是規格點：12m 的橋配 0.24m 的親柱會讀成牙籤 ——
    這裡 0.46m 見方、高出欄杆 0.35，柱頭擬宝珠。

    欄杆**鏤空**是規格點：上橫木＋下橫木之間留空、束柱 1.1m 一支 ——
    陽光斜射時欄影一條條掃在橋面上（配 daynight 的太陽：影子永遠往 -z 半空
    擺 ±40°，所以**橋面沿 x 走向**的橋，南側欄杆整天都在橋面上投影）。
    """
    hs = span / 2
    hw = width / 2

    def arc(x):
        t = max(-1.0, min(1.0, x / hs))
        return rise * (math.cos(math.pi / 2 * t) ** 0.9)

    deck_t = 0.24
    # 橋面：一段段的板（頂點色交替 —— 木板的節奏遠看才讀得出）
    for i in range(nseg):
        x0 = -hs + i * (span / nseg)
        x1 = x0 + span / nseg
        z0, z1 = arc(x0), arc(x1)
        c = C_DECK if i % 2 else C_DECK_DK
        bld.quad((x0, -hw, z0 + deck_t), (x1, -hw, z1 + deck_t),
                 (x1, hw, z1 + deck_t), (x0, hw, z0 + deck_t), c)
        # 側緣（桁隠し）
        for sy in (1, -1):
            bld.quad((x0, sy * hw, z0 + deck_t), (x1, sy * hw, z1 + deck_t),
                     (x1, sy * hw, z1 - deck_t), (x0, sy * hw, z0 - deck_t),
                     C_BEAM, flip=(sy < 0))
        # 底面（從河面往上看得到）
        bld.quad((x0, -hw, z0 - deck_t), (x0, hw, z0 - deck_t),
                 (x1, hw, z1 - deck_t), (x1, -hw, z1 - deck_t), C_BEAM)
    # 縱樑 + 橋腳（兩組，河裡）。窄橋只要兩根縱樑。
    for fy in ((-hw * 0.62, 0.0, hw * 0.62) if width >= 6.0 else (-hw * 0.55, hw * 0.55)):
        for i in range(nseg):
            x0 = -hs + i * (span / nseg)
            x1 = x0 + span / nseg
            z0, z1 = arc(x0), arc(x1)
            bld.quad((x0, fy - 0.17, z0 - deck_t), (x1, fy - 0.17, z1 - deck_t),
                     (x1, fy - 0.17, z1 - deck_t - 0.3), (x0, fy - 0.17, z0 - deck_t - 0.3),
                     C_BEAM)
            bld.quad((x0, fy + 0.17, z0 - deck_t - 0.3), (x1, fy + 0.17, z1 - deck_t - 0.3),
                     (x1, fy + 0.17, z1 - deck_t), (x0, fy + 0.17, z0 - deck_t), C_BEAM)
    # 下部結構跟著橋寬縮 —— 第一版硬寫 0.42 見方、深 2.8，小橋的三根橋墩
    # 佔掉 4.2m 橋面寬的 30%，從水面看跟主橋一樣重。
    pier = clampf_(0.42 * width / 12.0, 0.18, 0.42)
    pier_d = 1.2 + rise * 2.0
    fys = (-hw * 0.62, 0.0, hw * 0.62) if width >= 6.0 else (-hw * 0.55, hw * 0.55)
    for px in (-hs * 0.42, hs * 0.42):
        for fy in fys:
            bld.box(px, fy, arc(px) / 2 - pier_d / 2, pier, pier,
                    arc(px) + pier_d, C_BEAM)
        # width*0.72 在 width=4.2 時剛好等於橋墩外緣 (hw*0.62 + 0.21) ——
        # bridge_small 的兩片側面完全共面。加 0.12 讓它一定錯開。
        bld.box(px, 0, arc(px) - deck_t - 0.62, 0.5, width * 0.72 + 0.12, 0.34, C_BEAM)
    def rail_beam(ry, frac, th, wy, col):
        """沿拱的連續橫木：每段一個**斜切稜柱**（頂/底面跟著弧線斜），
        相鄰段共用端點 —— 連續、無縫。
        ⚠ 第一版用一段段水平箱近似，渲出來是鋸齒階梯（拱高 1.5m 攤在
        14 段上，每段落差 10~20cm，遠看就是樓梯不是欄杆）。"""
        for i in range(nseg):
            x0 = -hs + i * (span / nseg)
            x1 = x0 + span / nseg
            zt0 = arc(x0) + deck_t + rail_h * frac
            zt1 = arc(x1) + deck_t + rail_h * frac
            y0, y1 = ry - wy / 2, ry + wy / 2
            # 頂、底、外、內四面（端面被鄰段接住，最外兩端貼親柱）
            bld.quad((x0, y0, zt0), (x1, y0, zt1), (x1, y1, zt1), (x0, y1, zt0), col)
            bld.quad((x0, y1, zt0 - th), (x1, y1, zt1 - th),
                     (x1, y0, zt1 - th), (x0, y0, zt0 - th), col)
            bld.quad((x0, y0, zt0 - th), (x1, y0, zt1 - th),
                     (x1, y0, zt1), (x0, y0, zt0), col)
            bld.quad((x0, y1, zt0), (x1, y1, zt1),
                     (x1, y1, zt1 - th), (x0, y1, zt0 - th), col)

    # 欄杆（鏤空：上橫木 + 中橫木、束柱）＋ 親柱
    for sy in (1, -1):
        ry = sy * (hw - 0.28)
        for i in range(npost + 1):
            px = -hs + i * (span / npost)
            if i in (0, npost):
                continue                          # 端點讓給親柱
            pz = arc(px) + deck_t
            bld.box(px, ry, pz + rail_h / 2, 0.15, 0.15, rail_h, C_WOOD_MID)
        # 橫木沿拱：上（頂緣）、中（0.52h）—— 之間全空，影子才有條紋
        rail_beam(ry, 1.0, 0.16, 0.14, C_WOOD)
        rail_beam(ry, 0.52, 0.11, 0.12, C_WOOD)
        # 親柱：四角，0.50 見方、比欄杆高 0.35、擬宝珠柱頭
        # （規格點：親柱要隨 12m 橋寬等比放大 —— 0.24 的親柱配這座橋是牙籤）
        for sx in (1, -1):
            px = sx * hs
            pz = arc(px) + deck_t
            bld.box(px, ry, pz + (rail_h + 0.35) / 2 - 0.10, oya, oya,
                    rail_h + 0.55, C_WOOD)
            gz = pz + rail_h + 0.25
            bld.box(px, ry, gz + 0.11, oya * 0.76, oya * 0.76, 0.22, C_GIBO)
            bld.box(px, ry, gz + 0.31, oya * 0.38, oya * 0.38, 0.18, C_GIBO)
    # 橋台（兩端石座 —— 跟河岸接的地方；產生器把它埋進岸裡）
    if abut:
        for sx in (1, -1):
            # 頂緣切齊橋面端點（deck_t=0.24），第一版高出 0.06m，
            # 正好在踏上橋的地方留一道石唇。
            bld.box(sx * (hs + 0.9), 0, deck_t - 0.85, 2.0, width + 0.6, 1.7,
                    (0.520, 0.520, 0.500), top=(0.420, 0.425, 0.415))
    return rise + deck_t + rail_h + 0.35 + 0.35



# ── 鵜呑亭（臨河食堂）──
# 使用者決策：河道經過舊街區時**不搬遷，改造成臨河食堂當賣點**。
# 形制參考京都鴨川納涼床：主屋在陸上、川床（木造平台）用束柱架到水面上。
# 本河只有 14m 寬、中心水深 1.6m，所以床面取 1.33m（介於鴨川的 2~4m
# 與貴船的 0.3m 之間）—— 小河配小床。
# 座標約定跟町家完全一樣（原點=正面地面中心、正面朝 -y、屋身往 +y）：
#   **-y = 街側**（正面），+y 一路是 主屋 → 縁側 → 川床 → 水面。
# 產生器只要把 face_dir 設成「河的法線、朝離水那側」就自動擺對，
# _house()/OBB 檢查一行都不用改。
def unomitei(bld):
    W, D = 13.2, 9.2                 # 主屋
    plinth, pitch = 0.45, math.radians(24.0)
    body_h = 6.95 - plinth - (D / 2) * math.tan(pitch) - 0.14
    cy = D / 2
    rng = random.Random(97)
    bld.box(0, cy, plinth / 2, W + 0.22, D + 0.22, plinth, C_STONE, top=C_STONE_DK)
    z0 = plinth
    bld.box(0, cy, z0 + body_h / 2, W, D, body_h, C_PLASTER)
    bld.box(0, cy, z0 + 0.10, W + 0.04, D + 0.04, 0.20, C_PLASTER_DK)
    # 真壁柱（街側 + 河側 + 角）
    for py, n in ((-0.035, 5), (D + 0.035, 5)):
        for i in range(n):
            bld.box(-W / 2 + (i + 0.5) * (W / n), py, z0 + body_h / 2,
                    0.17, 0.13, body_h, C_WOOD)
    for sx in (1, -1):
        bld.box(sx * (W / 2 + 0.02), cy, z0 + body_h / 2, 0.13, 0.13, body_h, C_WOOD)
    for zz in (0.10, 2.30, body_h - 0.12):
        for py in (-0.045, D + 0.045):
            bld.box(0, py, z0 + zz, W + 0.1, 0.11, 0.15, C_WOOD)
    # 街側門面：中央入口（暖簾）＋兩側出格子
    bld.box(0, -0.30, z0 + 1.05, 3.30, 0.55, 2.10, C_WOOD_LT)          # 玄関凹處雨遮下
    for k in range(5):                                                  # 暖簾五巾
        bld.box(-1.28 + k * 0.64, -0.58, z0 + 2.34, 0.58, 0.03, 1.05, C_NOREN)
    for sx in (1, -1):
        bx = sx * 4.35
        bld.box(bx, -0.22, z0 + 1.45, 3.90, 0.34, 1.70,
                _mix(C_WOOD, (0, 0, 0), 0.30))                          # 出格子箱
        for k in range(11):
            bld.box(bx - 1.85 + k * 0.37, -0.40, z0 + 1.45, 0.07, 0.05, 1.70, C_WOOD_MID)
        bld.box(bx, -0.22, z0 + 2.36, 4.06, 0.40, 0.14, C_WOOD)         # 格子上框
    # 犬矢来（0.9m 高的弧形竹欄，貼牆腳）
    for k in range(14):
        bld.box(-6.2 + k * 0.95, -0.52, z0 + 0.45, 0.10, 0.10, 0.90, C_BAMBOO)
    bld.box(0, -0.52, z0 + 0.88, 13.4, 0.12, 0.10, C_BAMBOO)
    # 提灯 ×2（門口）
    for sx in (1, -1):
        bld.box(sx * 1.95, -0.62, z0 + 2.52, 0.34, 0.34, 0.52, C_CHOCHIN)
        bld.box(sx * 1.95, -0.62, z0 + 2.82, 0.10, 0.10, 0.10, C_WOOD)
    # 一階庇（街側下屋）
    bld.box(0, -0.72, z0 + 2.62, W + 0.9, 1.55, 0.11, C_KAWARA_DK, top=C_KAWARA)
    # 二階虫籠窓
    # ⚠ 深度 0.10 配 cy=-0.05 → y∈[-0.10, 0.00]，背面**正好落在 y=0**，
    # 跟主屋正面共面。這正是本檔 169 行明令禁止、docs 記了五次「黑洞」的那個
    # 病，第六次。町家那邊用的是 cy=-0.050 / d=0.08（y∈[-0.09,-0.01]）。
    for k in range(4):
        bld.box(-4.5 + k * 3.0, -0.055, z0 + body_h - 1.05, 1.55, 0.08, 0.72, C_SHOJI)
        for j in range(5):
            bld.box(-4.5 + k * 3.0 - 0.62 + j * 0.31, -0.10,
                    z0 + body_h - 1.05, 0.06, 0.06, 0.72, C_WOOD_MID)
    gable_roof(bld, 0, cy, z0 + body_h, W, D, pitch)
    # ── 縁側（主屋 → 川床的過渡）──
    # 各段互相**重疊 1cm** 而不是零間隙貼合 —— 貼合面會餵給 LOD/陰影網格的
    # 頂點焊接，是共面問題的溫床。
    bld.box(0, D + 0.69, 0.50, W, 1.42, 0.14, C_DECK, top=C_DECK)
    bld.box(0, D + 0.75, 0.16, W - 0.4, 1.30, 0.34, C_BEAM)
    # 護岸石垣（縁側底下，模組自帶 —— 產生器的護岸在這段會讓開）
    bld.box(0, D + 0.75, -0.55, W + 0.6, 1.90, 1.60, C_STONE, top=C_STONE_DK)
    # ── 川床（懸在水面上）──
    dW, dD = 12.4, 5.4
    dy = D + 1.39 + dD / 2
    bld.box(0, dy, 0.42, dW, dD, 0.12, C_DECK, top=C_DECK)              # 床板
    for k in range(6):                                                   # 大引
        bld.box(0, D + 1.55 + k * 1.02, 0.28, dW - 0.06, 0.16, 0.22, C_BEAM)
    # 束柱：4 列 × 4 排，長度過長埋進河床（同 bridge_main 的手法）
    for ix in range(4):
        px = -dW / 2 + 0.55 + ix * ((dW - 1.1) / 3)
        for iy in range(4):
            py = D + 1.75 + iy * 1.30
            bld.box(px, py, -1.05, 0.15, 0.15, 2.90, C_BEAM)
        # 筋交（斜撐）—— 只做外側兩列，剪影才有結構感
        if ix in (0, 3):
            bld.box(px, D + 2.40, -0.42, 0.10, 3.20, 0.10, C_BEAM)
    # 高欄（三面：左右 + 外側，靠主屋那面不做）
    for sx in (1, -1):
        for k in range(5):
            bld.box(sx * (dW / 2 - 0.12), D + 1.75 + k * 1.25, 0.95, 0.11, 0.11, 0.96, C_WOOD_MID)
        for frac in (0.94, 0.50):
            bld.box(sx * (dW / 2 - 0.12), dy, 0.48 + 0.96 * frac, 0.13, dD - 0.2, 0.10, C_WOOD)
    for k in range(11):
        bld.box(-dW / 2 + 0.35 + k * 1.17, D + 1.40 + dD - 0.12, 0.95, 0.11, 0.11, 0.96, C_WOOD_MID)
    for frac in (0.94, 0.50):
        bld.box(0, D + 1.40 + dD - 0.12, 0.48 + 0.96 * frac, dW - 0.2, 0.13, 0.10, C_WOOD)
    # 川床上半段的庇（靠主屋那 2.1m 有遮，外側開天 —— 納涼床的規矩）
    bld.box(0, D + 2.45, 3.05, dW + 0.5, 2.30, 0.11, C_KAWARA_DK, top=C_KAWARA)
    for sx in (1, -1):
        bld.box(sx * (dW / 2 - 0.25), D + 2.45, 1.75, 0.14, 0.14, 2.60, C_WOOD)
    return 6.95



# ══ 超現實地標塔 ══
# 使用者本輪指令：**只挑 2~3 座**地標推到 15~20m，而且「基座要維持樸實
# 的尺寸」—— 讀成超現實的是**太高配太窄**的錯配，不是單純的高。
# 一般町家的階梯天際線（前排 4.5 / 後排 9~10）**維持不動**：對比才是重點，
# 這個手法不准擴散出去。
#
# 三座都放在街道視線的終點（見 gen_town.gd 的 TOWERS）：
#   火見櫓  本通北端終點      19.5m / 基座 4.6m 見方  → 高寬比 4.2
#   鐘楼    本通南端終點      17.5m / 基座 4.2m 見方  → 高寬比 4.2
#   水車櫓  z=85 街的河岸終點  16.5m / 基座 5.4×4.4    → 高寬比 3.1
# 對照：後排町家 9.9m / 面寬 10.4 → 高寬比 0.95。差了四倍。


def _quad_frustum(bld, z0, z1, r0, r1, a0, a1, col, cap=None, skip_bottom=True):
    """四角錐台，上下可各自旋轉（扭轉）。r = 半寬、a = 弧度。"""
    def ring(z, r, a):
        return [(r * math.sqrt(2) * math.cos(a + math.pi / 4 + k * math.pi / 2),
                 r * math.sqrt(2) * math.sin(a + math.pi / 4 + k * math.pi / 2), z)
                for k in range(4)]
    lo, hi = ring(z0, r0, a0), ring(z1, r1, a1)
    for k in range(4):
        k2 = (k + 1) % 4
        bld.quad(lo[k], lo[k2], hi[k2], hi[k], col)
    if cap:
        bld.quad(hi[0], hi[1], hi[2], hi[3], cap)
    if not skip_bottom:
        bld.quad(lo[3], lo[2], lo[1], lo[0], col)
    return hi


def _hip_roof(bld, z, r, a, rise, over, col, col_dk):
    """四角攢尖屋根（寶形造）—— 塔頂的標準收法。"""
    ro = r + over
    base = [(ro * math.sqrt(2) * math.cos(a + math.pi / 4 + k * math.pi / 2),
             ro * math.sqrt(2) * math.sin(a + math.pi / 4 + k * math.pi / 2), z)
            for k in range(4)]
    apex = (0.0, 0.0, z + rise)
    for k in range(4):
        k2 = (k + 1) % 4
        bld.tri(base[k], base[k2], apex, col if k % 2 else col_dk)
        # 簷口斷面
        bld.quad(base[k], base[k2],
                 (base[k2][0], base[k2][1], z - 0.14), (base[k][0], base[k][1], z - 0.14),
                 col_dk)
    return z + rise


def fire_tower(bld):
    """火見櫓：四腳木造望楼。19.5m 配 4.6m 見方的基座。

    ⚠ 「不合理」在**中段收到 38% 再往上張開**：真的櫓是一路收窄的，
    這座收到腰身比腳還細，上面卻托著更大的望台 —— 結構上撐不住，
    但它就站在那裡。每一節再各扭 6~9°，接縫也對不齊。"""
    a = 0.0
    # 石製礎盤（樸實 —— 基座不誇張，誇張的是它上面的東西）
    bld.box(0, 0, 0.28, 4.8, 4.8, 0.56, C_STONE, top=C_STONE_DK)
    # 四支通し柱（腳）：從 2.3 半寬收到 0.88（38%）
    STAGES = [(0.56, 5.2, 2.30, 1.72, 0.00, 0.11),
              (5.2, 9.6, 1.72, 1.18, 0.11, 0.26),
              (9.6, 13.4, 1.18, 0.88, 0.26, 0.42),     # 最細的腰
              (13.4, 15.6, 0.88, 1.62, 0.42, 0.30),    # ← 反過來張開
              (15.6, 16.9, 1.62, 2.05, 0.30, 0.22)]    # 望台托座
    for (z0, z1, r0, r1, a0, a1) in STAGES:
        for k in range(4):
            ang0 = a0 + math.pi / 4 + k * math.pi / 2
            ang1 = a1 + math.pi / 4 + k * math.pi / 2
            p0 = (r0 * math.sqrt(2) * math.cos(ang0), r0 * math.sqrt(2) * math.sin(ang0), z0)
            p1 = (r1 * math.sqrt(2) * math.cos(ang1), r1 * math.sqrt(2) * math.sin(ang1), z1)
            _leg(bld, p0, p1, 0.16, C_WOOD)
        # 貫（水平箍）
        for k in range(4):
            k2 = (k + 1) % 4
            ang0 = a1 + math.pi / 4 + k * math.pi / 2
            ang2 = a1 + math.pi / 4 + k2 * math.pi / 2
            q0 = (r1 * math.sqrt(2) * math.cos(ang0), r1 * math.sqrt(2) * math.sin(ang0), z1 - 0.12)
            q1 = (r1 * math.sqrt(2) * math.cos(ang2), r1 * math.sqrt(2) * math.sin(ang2), z1 - 0.12)
            _leg(bld, q0, q1, 0.10, C_WOOD_MID)
        # 筋交（斜撐，只做兩面 —— 剪影才有疏密）
        for k in (0, 2):
            k2 = (k + 1) % 4
            ang0 = a0 + math.pi / 4 + k * math.pi / 2
            ang2 = a1 + math.pi / 4 + k2 * math.pi / 2
            _leg(bld, (r0 * math.sqrt(2) * math.cos(ang0),
                       r0 * math.sqrt(2) * math.sin(ang0), z0),
                 (r1 * math.sqrt(2) * math.cos(ang2),
                  r1 * math.sqrt(2) * math.sin(ang2), z1), 0.09, C_WOOD_MID)
    # 望台（板張 + 高欄）
    _quad_frustum(bld, 16.9, 17.12, 2.05, 2.05, 0.22, 0.22, C_DECK_DK, cap=C_DECK)
    for k in range(4):
        k2 = (k + 1) % 4
        ang0 = 0.22 + math.pi / 4 + k * math.pi / 2
        ang2 = 0.22 + math.pi / 4 + k2 * math.pi / 2
        c0 = (2.05 * math.sqrt(2) * math.cos(ang0), 2.05 * math.sqrt(2) * math.sin(ang0))
        c2 = (2.05 * math.sqrt(2) * math.cos(ang2), 2.05 * math.sqrt(2) * math.sin(ang2))
        for f in (0.42, 1.0):
            _leg(bld, (c0[0], c0[1], 17.12 + 1.05 * f), (c2[0], c2[1], 17.12 + 1.05 * f),
                 0.09, C_WOOD)
        for t in (0.0, 0.5):
            px = c0[0] + (c2[0] - c0[0]) * t
            py = c0[1] + (c2[1] - c0[1]) * t
            _leg(bld, (px, py, 17.12), (px, py, 17.12 + 1.05), 0.10, C_WOOD_MID)
    top = _hip_roof(bld, 18.35, 2.05, 0.22, 1.15, 0.42, C_KAWARA, C_KAWARA_DK)
    # 半鐘（吊在望台下）
    bld.box(0, 0, 17.55, 0.52, 0.52, 0.62, C_GIBO)
    return top


def _leg(bld, a, b, r, col):
    """兩點之間的方柱（塔的腳、貫、筋交都用它）。"""
    d = [b[i] - a[i] for i in range(3)]
    L = math.sqrt(sum(c * c for c in d)) or 1.0
    d = [c / L for c in d]
    up = (0.0, 0.0, 1.0) if abs(d[2]) < 0.9 else (1.0, 0.0, 0.0)
    sx = [d[1] * up[2] - d[2] * up[1], d[2] * up[0] - d[0] * up[2], d[0] * up[1] - d[1] * up[0]]
    sl = math.sqrt(sum(c * c for c in sx)) or 1.0
    sx = [c / sl for c in sx]
    sy = [d[1] * sx[2] - d[2] * sx[1], d[2] * sx[0] - d[0] * sx[2], d[0] * sx[1] - d[1] * sx[0]]
    def corner(p, i, j):
        return tuple(p[k] + sx[k] * i * r + sy[k] * j * r for k in range(3))
    for (i0, j0, i1, j1) in ((-1, -1, 1, -1), (1, -1, 1, 1), (1, 1, -1, 1), (-1, 1, -1, -1)):
        bld.quad(corner(a, i0, j0), corner(a, i1, j1),
                 corner(b, i1, j1), corner(b, i0, j0), col)


def bell_tower(bld):
    """鐘楼：17.5m 配 4.2m 見方的石壇。

    ⚠ 「不合理」在**倒錐**：軸身一路收到 0.62 半寬，鐘室卻張到 1.95 ——
    上面比下面寬三倍，像一根竹竿頂著一頂轎子。"""
    bld.box(0, 0, 0.65, 5.0, 5.0, 1.30, C_STONE, top=C_STONE_DK)
    bld.box(0, 0, 1.45, 4.2, 4.2, 0.30, C_STONE_DK)
    # 軸身：白漆喰 + 真壁，一路收窄且扭轉
    z, r, a = 1.60, 1.55, 0.0
    for (dz, r1, da) in ((4.2, 1.22, 0.14), (4.0, 0.95, 0.30), (3.6, 0.62, 0.50)):
        _quad_frustum(bld, z, z + dz, r, r1, a, a + da, C_PLASTER)
        for k in range(4):
            ang0 = a + math.pi / 4 + k * math.pi / 2
            ang1 = a + da + math.pi / 4 + k * math.pi / 2
            _leg(bld, (r * 1.414 * math.cos(ang0), r * 1.414 * math.sin(ang0), z),
                 (r1 * 1.414 * math.cos(ang1), r1 * 1.414 * math.sin(ang1), z + dz),
                 0.13, C_WOOD)
        z += dz
        r = r1
        a += da
    # 鐘室：反過來張到 1.95（比腰身寬三倍）
    _quad_frustum(bld, z, z + 0.35, r, 1.95, a, a - 0.18, C_WOOD)
    z += 0.35
    a -= 0.18
    _quad_frustum(bld, z, z + 2.10, 1.95, 1.82, a, a - 0.06, C_WOOD_LT)
    # 鐘室的柱與梵鐘
    for k in range(4):
        ang = a + math.pi / 4 + k * math.pi / 2
        _leg(bld, (1.95 * 1.414 * math.cos(ang), 1.95 * 1.414 * math.sin(ang), z),
             (1.82 * 1.414 * math.cos(ang), 1.82 * 1.414 * math.sin(ang), z + 2.10),
             0.17, C_WOOD)
    bld.box(0, 0, z + 0.95, 1.10, 1.10, 1.30, C_GIBO)
    bld.box(0, 0, z + 1.72, 0.34, 0.34, 0.26, C_GIBO)
    return _hip_roof(bld, z + 2.10, 1.82, a - 0.06, 1.55, 0.60, C_KAWARA, C_KAWARA_DK)


def water_mill_tower(bld):
    """水車櫓：16.5m 配 5.4×4.4 的基座。水輪在 -y 側（朝河）。

    ⚠ 「不合理」在**頭重腳輕**：上面三層一層比一層往河面挑出去，
    最上層懸到基座外 2.6m，底下什麼支撐都沒有。"""
    W, D = 5.4, 4.4
    bld.box(0, 0, 0.35, W + 0.5, D + 0.5, 0.70, C_STONE, top=C_STONE_DK)
    z = 0.70
    # 一層：正常的水車小屋
    bld.box(0, 0, z + 2.35, W, D, 4.70, C_PLASTER)
    for sx in (1, -1):
        bld.box(sx * (W / 2 + 0.02), 0, z + 2.35, 0.15, D + 0.06, 4.70, C_WOOD)
    for zz in (0.12, 2.20, 4.58):
        bld.box(0, -(D / 2 + 0.05), z + zz, W + 0.1, 0.11, 0.16, C_WOOD)
    bld.box(0, -(D / 2 + 0.07), z + 1.35, W * 0.5, 0.09, 1.90, C_WOOD_LT)   # 板戶
    z += 4.70
    # 二～四層：一層比一層往 -y（河）挑出去，而且愈上愈窄
    OVER = [(3.9, 0.90, 4.9, 3.9), (3.5, 1.85, 4.2, 3.3), (3.1, 2.60, 3.4, 2.7)]
    for (dz, off, w2, d2) in OVER:
        # 挑樑（露出來的支撐 —— 明知撐不住還是畫幾根，反差更強）
        for sx in (-1, 1):
            _leg(bld, (sx * w2 * 0.34, -off + d2 * 0.30, z + 0.10),
                 (sx * w2 * 0.34, -off * 0.15, z - 0.75), 0.13, C_WOOD)
        bld.box(0, -off, z + dz / 2, w2, d2, dz, C_PLASTER)
        for sx in (1, -1):
            bld.box(sx * (w2 / 2 + 0.02), -off, z + dz / 2, 0.13, d2 + 0.05, dz, C_WOOD)
        bld.box(0, -off - d2 / 2 - 0.05, z + dz - 0.85, w2 * 0.62, 0.09, 0.80, C_SHOJI)
        bld.box(0, -off, z + dz * 0.5, w2 + 0.06, d2 + 0.06, 0.22, C_WOOD)   # 胴差
        # 腰簷
        bld.box(0, -off, z + 0.16, w2 + 1.2, d2 + 1.2, 0.11, C_KAWARA_DK, top=C_KAWARA)
        z += dz
    top = _hip_roof(bld, z, 1.60, 0.0, 1.35, 0.80, C_KAWARA, C_KAWARA_DK)
    # 水車（立輪，朝 -y 的河面）
    wy = -(D / 2 + 0.75)
    R = 2.85
    for k in range(16):
        t0 = k / 16.0 * math.tau
        t1 = (k + 1) / 16.0 * math.tau
        p0 = (R * math.cos(t0), wy, 1.05 + R * math.sin(t0))
        p1 = (R * math.cos(t1), wy, 1.05 + R * math.sin(t1))
        for dy in (-0.42, 0.42):
            _leg(bld, (p0[0], wy + dy, p0[2]), (p1[0], wy + dy, p1[2]), 0.10, C_WOOD_MID)
            _leg(bld, (p0[0], wy + dy, p0[2]), (p0[0] * 0.22, wy + dy, 1.05 + (p0[2] - 1.05) * 0.22),
                 0.07, C_WOOD_MID)
        # 水掻き（葉板）
        bld.quad((p0[0], wy - 0.46, p0[2]), (p1[0], wy - 0.46, p1[2]),
                 (p1[0] * 0.66, wy + 0.46, 1.05 + (p1[2] - 1.05) * 0.66),
                 (p0[0] * 0.66, wy + 0.46, 1.05 + (p0[2] - 1.05) * 0.66), C_DECK_DK)
    _leg(bld, (0, wy - 0.55, 1.05), (0, -(D / 2 - 0.3), 1.05), 0.22, C_WOOD)   # 心棒
    return top


def _bbox(ob):
    """(寬 x, 深 y, 高 z) —— 從實際頂點量，不是從建構參數推。"""
    vs = [v.co for v in ob.data.vertices]
    return (max(v.x for v in vs) - min(v.x for v in vs),
            max(v.y for v in vs) - min(v.y for v in vs),
            max(v.z for v in vs))


def _gbox(ob):
    """模組在 **Godot 局部座標**的 XZ 包絡 [x0, x1, z0, z1]。
    Blender(x, y) → Godot(x, -y)，所以 z0 = -ymax、z1 = -ymin。
    佈局端要靠它對**任何**模組建 OBB —— 光有 fw/fd 建不出「原點不在
    幾何中心」的模組（町家的原點在正面、橋的原點在中心），而那正是
    鵜呑亭壓到橋上卻沒被自檢抓到的原因。"""
    vs = [v.co for v in ob.data.vertices]
    return [round(min(v.x for v in vs), 3), round(max(v.x for v in vs), 3),
            round(-max(v.y for v in vs), 3), round(-min(v.y for v in vs), 3)]


def export(ob, name):
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True,
                              export_format="GLB", export_yup=True,
                              export_apply=True)
    n = len(ob.data.polygons)
    print("exported %s（%d 面）" % (path, n))
    return n


# ── 產出 ──
# (name, W 面寬, D 進深, 目標總高, storeys, pitch°, seed)
# 後排進深收到 7.6/8.0：45° 屋頂的 rise = D/2，進深 9m 的話光屋頂就 4.5m，
# 屋身只剩不到 5m 裝兩層樓。7.6~8.0 的進深讓屋頂 3.8~4.0、屋身 5.2~5.6。
# 前排兩種都壓到 **4.50**（使用者定案：階梯天際線選 (c)，只動前排、
# 後排與排間距不動）。同高之後變化改由**面寬／進深／屋頂斜度**帶：
# f_a 7.6 寬 23°（緩坡、扁）、f_b 8.8 寬 26°（稍陡、寬）—— 剪影仍分得出來，
# 但兩者的脊都在 4.5，後排 9.4/9.9 的露出量最大化。
# ⚠ 屋身高是反推的：body = 目標 - 基石 0.30 - (D/2)·tanθ - 棟 0.14。
# f_b 原本 D=8.2/29° 在 4.5 的目標下反推出 1.79m 屋身（低於 1.8 的下限，
# assert 會擋），所以 D 收到 7.6、θ 收到 26。
# ⚠ machiya_f_a 已經換成 **production prototype**（PHASE 1）：幾何由
# `make_machiya.py` 產（真壁造軸組 + 語意材質 + 構件化屋頂／庇），不再走
# 下面這個 blockout 的 `machiya()`。尺寸列在這裡是因為 manifest 仍由本檔
# 統一寫出 —— 一份 manifest 一個寫入者，兩邊各寫一份遲早對不上。
# 其餘四種維持 legacy blockout，Phase 1 明令不批量替換。
PROTO = {"machiya_f_a"}
MACHIYA = [
    # ⚠ PHASE 1.1：總高 4.50 → **5.40**、坡度 23° → 21°（使用者定案：放寬到
    # 5.2~5.6 讓屋頂不再壓倒立面）。這張表是**唯一**的真相來源 —— prototype
    # builder 自己的預設值只在單獨跑 make_machiya.py 時生效，正式產出走這裡。
    ("machiya_f_a", 7.6, 7.8, 5.40, 1, 21.0, 11),   # 前排（PHASE 1.1 prototype）
    ("machiya_f_b", 8.8, 7.6, 4.50, 1, 26.0, 23),   # 前排
    ("machiya_b_a", 9.2, 7.6, 9.40, 2, 45.0, 37),   # 後排（規格 9~10、45°）不動
    ("machiya_b_b", 10.4, 8.0, 9.90, 2, 45.0, 41),  # 後排 不動
    ("machiya_e_a", 6.0, 6.2, 3.50, 1, 21.0, 53),   # 村緣（規格 3.5）
]

manifest = {"note": "人間之里模組庫。由 make_town.py 產出，gen_town.gd 讀。"
                    "模組正面朝 -y（machiya）；bridge 沿 x。單位公尺。",
            "modules": {}}
for name, W, D, bh, st, pit, sd in MACHIYA:
    clear()
    if name in PROTO:
        import importlib.util as _ilu
        _spec = _ilu.spec_from_file_location(
            "make_machiya", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                         "make_machiya.py"))
        _mm = _ilu.module_from_spec(_spec)
        _spec.loader.exec_module(_mm)
        _mm.make_materials()
        _b = _mm.MB()
        _ridge, _door_x = _mm.machiya_f_a(_b, W, D, bh, math.radians(pit))
        ob = _b.build(name)
        rep = _mm.validate(ob)
        assert rep["degenerate"] == 0, "prototype 有退化面：%s" % rep
        assert len(rep["material_faces"]) == 6, "語意材質不齊：%s" % rep
        n = _mm.export(ob, name)
        n = len(ob.data.polygons)
        total = max(v.co.z for v in ob.data.vertices)
        facade = {"door_x": round(_door_x, 3), "door_w": 1.63,
                  "beam_z": round(_mm.LINTEL_Z + 0.30 - 0.07, 3),
                  "bay_w": round(W / 4.0, 3), "nbay": 4}
        print("  [PROTO] %s 面 %d 材質 %s" % (name, n, rep["material_faces"]))
    else:
        b = B()
        total, facade = machiya(b, W, D, bh, st, math.radians(pit), sd)
        ob = b.build(name)
        n = export(ob, name)
    # ⚠ fw 要含**屋脊蓋**的 0.24（gable_roof 的棟是 hw*2+0.24）。
    # 少算的話 gen_town 的 OBB 自檢會樂觀 0.24m —— 實測最壞穿透從 0.000
    # 變成 0.038m，還在 0.05 門檻內，但報出來的餘裕是假的。
    # fw/fd/h 一律**從實際 bbox 量**，不是從參數推。
    bb = _bbox(ob)
    manifest["modules"][name] = {
        "kind": "machiya", "w": W, "d": D,
        "fw": round(bb[0], 2), "fd": round(bb[1], 2), "h": round(bb[2], 2),
        "gbox": _gbox(ob), "facade": facade,
        "faces": n, "glb": "res://assets/models/%s.glb" % name}
    print("  %s 總高 %.2f m  門位 x=%.2f" % (name, total, facade["door_x"]))

for _nm, _sp, _wd, _ri, _rh, _ns, _np, _oy in (
        ("bridge_main", 22.0, 12.0, 1.50, 1.15, 14, 12, 0.50),
        # 小橋：明確從屬於主橋 —— 窄一半、拱矮一半、親柱小一號，
        # 但語彙同源（同樣的半拱、鏤空欄杆、擬宝珠）。
        ("bridge_small", 19.0, 4.2, 0.75, 1.05, 10, 8, 0.30)):
    clear()
    b = B()
    bh = bridge_main(b, span=_sp, width=_wd, rise=_ri, rail_h=_rh,
                     nseg=_ns, npost=_np, oya=_oy)
    ob = b.build(_nm)
    n = export(ob, _nm)
    bb = _bbox(ob)
    manifest["modules"][_nm] = {
        "kind": "bridge", "span": _sp, "w": _wd, "rise": _ri, "rail_h": _rh,
        "fw": round(bb[0], 2), "fd": round(bb[1], 2), "h": round(bb[2], 2),
        "gbox": _gbox(ob),
        "faces": n, "glb": "res://assets/models/%s.glb" % _nm}

for _nm, _fn in (("tower_fire", "fire_tower"), ("tower_bell", "bell_tower"),
                 ("tower_mill", "water_mill_tower")):
    clear()
    b = B()
    th = globals()[_fn](b)
    ob = b.build(_nm)
    n = export(ob, _nm)
    bb = _bbox(ob)
    manifest["modules"][_nm] = {
        "kind": "tower", "fw": round(bb[0], 2), "fd": round(bb[1], 2),
        "h": round(bb[2], 2), "gbox": _gbox(ob), "faces": n,
        "glb": "res://assets/models/%s.glb" % _nm}
    print("  %s 高 %.2f m / 基座 %.1f×%.1f → 高寬比 %.1f"
          % (_nm, bb[2], bb[0], bb[1], bb[2] / max(bb[0], bb[1])))

clear()
b = B()
uh = unomitei(b)
ob = b.build("unomitei")
n = export(ob, "unomitei")
# ⚠ fd 一定要是**含川床**的真進深（17.5），不是主屋的 10.9 —— 少 6.6m
# 就是鵜呑亭壓到橋上而 OBB 自檢沒抓到的原因。
_bb = _bbox(ob)
manifest["modules"]["unomitei"] = {
    "kind": "landmark", "w": 13.2, "d": 9.2,
    "fw": round(_bb[0], 2), "fd": round(_bb[1], 2), "h": round(_bb[2], 2),
    "gbox": _gbox(ob), "deck_d": 16.0, "faces": n, "glb": "res://assets/models/unomitei.glb"}

mp = os.path.normpath(os.path.join(os.path.dirname(OUT_DIR.rstrip("/")), "..",
                                   "data", "town_modules.json"))
os.makedirs(os.path.dirname(mp), exist_ok=True)
with open(mp, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, ensure_ascii=False, indent=1)
print("wrote %s（%d 模組）" % (mp, len(manifest["modules"])))
print("done")
