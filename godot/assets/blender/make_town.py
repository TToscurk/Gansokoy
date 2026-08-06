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
#   machiya_f_a / f_b   前排町家  總高 4.8 / 5.4（規格 4.5~5.5）
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
        for sx in (1, -1):
            bld.box(sx * (W / 2 + 0.10), cy * 0.7, z0 + body_h - 0.5,
                    0.16, D * 0.5, 1.0, C_PLASTER_DK, top=C_KAWARA_DK)
    # 一階陰影帶（貼地一圈微暗 —— 頂點色的接觸陰影，稗田邸驗過的手法）
    bld.box(0, cy, z0 + 0.10, W + 0.04, D + 0.04, 0.20, C_PLASTER_DK)
    ridge = gable_roof(bld, 0, cy, z0 + body_h, W, D, pitch)
    return ridge + 0.055 + 0.17 / 2


# ── 12m 半拱木橋 ──


def bridge_main(bld, span=22.0, width=12.0, rise=1.5, rail_h=1.15):
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
    nseg = 14

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
    # 縱樑 ×3 + 橋腳（兩組，河裡）
    for fy in (-hw * 0.62, 0.0, hw * 0.62):
        for i in range(nseg):
            x0 = -hs + i * (span / nseg)
            x1 = x0 + span / nseg
            z0, z1 = arc(x0), arc(x1)
            bld.quad((x0, fy - 0.17, z0 - deck_t), (x1, fy - 0.17, z1 - deck_t),
                     (x1, fy - 0.17, z1 - deck_t - 0.3), (x0, fy - 0.17, z0 - deck_t - 0.3),
                     C_BEAM)
            bld.quad((x0, fy + 0.17, z0 - deck_t - 0.3), (x1, fy + 0.17, z1 - deck_t - 0.3),
                     (x1, fy + 0.17, z1 - deck_t), (x0, fy + 0.17, z0 - deck_t), C_BEAM)
    for px in (-hs * 0.42, hs * 0.42):
        for fy in (-hw * 0.62, 0.0, hw * 0.62):
            bld.box(px, fy, arc(px) / 2 - 1.4, 0.42, 0.42, arc(px) + 2.8, C_BEAM)
        bld.box(px, 0, arc(px) - deck_t - 0.62, 0.5, width * 0.72, 0.34, C_BEAM)
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
        npost = 12
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
            bld.box(px, ry, pz + (rail_h + 0.35) / 2 - 0.10, 0.50, 0.50,
                    rail_h + 0.55, C_WOOD)
            gz = pz + rail_h + 0.25
            bld.box(px, ry, gz + 0.11, 0.38, 0.38, 0.22, C_GIBO)
            bld.box(px, ry, gz + 0.31, 0.19, 0.19, 0.18, C_GIBO)
    # 橋台（兩端石座 —— 跟河岸接的地方；產生器把它埋進岸裡）
    for sx in (1, -1):
        bld.box(sx * (hs + 0.9), 0, -0.55, 2.0, width + 0.6, 1.7,
                (0.520, 0.520, 0.500), top=(0.420, 0.425, 0.415))
    return rise + deck_t + rail_h + 0.35 + 0.35


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
MACHIYA = [
    ("machiya_f_a", 7.6, 7.8, 4.80, 1, 26.0, 11),   # 前排（規格 4.5~5.5）
    ("machiya_f_b", 8.8, 8.2, 5.40, 1, 29.0, 23),   # 前排
    ("machiya_b_a", 9.2, 7.6, 9.40, 2, 45.0, 37),   # 後排（規格 9~10、45°）
    ("machiya_b_b", 10.4, 8.0, 9.90, 2, 45.0, 41),  # 後排
    ("machiya_e_a", 6.0, 6.2, 3.50, 1, 21.0, 53),   # 村緣（規格 3.5）
]

manifest = {"note": "人間之里模組庫。由 make_town.py 產出，gen_town.gd 讀。"
                    "模組正面朝 -y（machiya）；bridge 沿 x。單位公尺。",
            "modules": {}}
for name, W, D, bh, st, pit, sd in MACHIYA:
    clear()
    b = B()
    total = machiya(b, W, D, bh, st, math.radians(pit), sd)
    ob = b.build(name)
    n = export(ob, name)
    manifest["modules"][name] = {
        "kind": "machiya", "w": W, "d": D, "fw": round(W + 1.7, 2),
        "fd": round(D + 1.7, 2), "h": round(total, 2),
        "faces": n, "glb": "res://assets/models/%s.glb" % name}
    print("  %s 總高 %.2f m" % (name, total))

clear()
b = B()
bh = bridge_main(b)
ob = b.build("bridge_main")
n = export(ob, "bridge_main")
manifest["modules"]["bridge_main"] = {
    "kind": "bridge", "span": 22.0, "w": 12.0, "rise": 1.5, "rail_h": 1.15,
    "h": round(bh, 2), "faces": n, "glb": "res://assets/models/bridge_main.glb"}

mp = os.path.normpath(os.path.join(os.path.dirname(OUT_DIR.rstrip("/")), "..",
                                   "data", "town_modules.json"))
os.makedirs(os.path.dirname(mp), exist_ok=True)
with open(mp, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, ensure_ascii=False, indent=1)
print("wrote %s（%d 模組）" % (mp, len(manifest["modules"])))
print("done")
