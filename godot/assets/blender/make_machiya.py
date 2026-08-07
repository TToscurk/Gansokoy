# 町家 Production Kit —— PHASE 1 prototype（machiya_f_a）
#
#   blender -b -P assets/blender/make_machiya.py -- <outdir> [--render <dir>]
#
# ══════════════════════════════════════════════════════════════════════
# 這支跟 make_town.py 的差別（也就是「production」跟「blockout」的差別）
# ══════════════════════════════════════════════════════════════════════
#
# 1. **真壁造是真的軸組，不是白盒子外面貼木條。**
#    舊版：`bld.box(...)` 一個完整的白牆量體，再往牆外貼幾根 0.17 厚的柱。
#    柱與牆沒有結構關係，牆是連續的、柱是裝飾。
#    這版：先立**軸組**（土台→柱→貫→内法長押→桁→梁），漆喰是**填在柱與柱
#    之間**的獨立嵌板，而且比柱面**內縮 25mm** —— 那 25mm 的落差就是真壁造
#    在遠景唯一讀得出來的東西（陰影線）。牆不再是一個連續量體。
#
# 2. **語意材質，不是頂點色。**
#    舊版整棟一份 mesh、一個 COLOR_0、Godot 端 `prop_mesh()` 再把所有 surface
#    覆蓋成同一個 vertex-color 材質 —— 材質身分在 pipeline 中間就死了。
#    這版每個構件指定語意材質（WOOD / WOOD_LT / PLASTER / STONE / KAWARA /
#    SHOJI），glTF 匯出時一種材質一個 primitive，Godot 端逐 surface 掛
#    專案的 PBR 材質庫。
#
# 3. **屋頂是一組構件，不是一片斜面。**
#    野地（含厚度）／軒裏／垂木／鼻隠し／破風板／懸魚／棟（熨斗＋冠）／
#    丸瓦（本瓦葺き的縱向半圓）。近看有瓦、遠看剪影正確。
#
# 4. **庇是完整的建築構件。**
#    腕木→桁→垂木→野地→軒裏→鼻隠し→瓦。不是「從牆上戳出來的水平方塊」。
#
# ── 模組座標約定（跟 make_town.py 一致，不能改，佈局端吃這個）──
#   正面朝 -y、原點在正面地面中心、x = 面寬方向。
#   Blender(x, y, z) → Godot(x, z, -y)。
import bpy
import bmesh
import math
import os
import sys

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = ARGV[0] if ARGV else "godot/assets/models"
RENDER_DIR = None
if "--render" in ARGV:
    RENDER_DIR = ARGV[ARGV.index("--render") + 1]

# ── 語意材質（base color 為 linear；roughness 走 Principled）──
# 名字是**契約**：Godot 端 `gen_lib.semantic_mat()` 靠它掛專案的貼圖組。
MATS = {
    "WOOD":     ((0.105, 0.076, 0.054), 0.82),   # 柱・梁・貫・桁（曬過的深木）
    "WOOD_LT":  ((0.230, 0.170, 0.115), 0.80),   # 板戶・腰板・軒裏（淺木）
    "PLASTER":  ((0.700, 0.676, 0.622), 0.92),   # 漆喰嵌板
    "STONE":    ((0.360, 0.358, 0.345), 0.88),   # 玉石基礎・沓石
    "KAWARA":   ((0.150, 0.166, 0.200), 0.62),   # 瓦（藍灰）
    "SHOJI":    ((0.845, 0.826, 0.762), 0.94),   # 障子紙
}
ORDER = list(MATS.keys())


class MB:
    """三角形累加器，**逐面帶語意材質**（舊版是逐面帶頂點色）。

    winding 沿用 make_town.py 那組已經被 169 棟町家驗證過的慣例：
    `box()` 的六面順序與 `quad(flip=)` 的語意一個字都沒改 —— 這裡換的是
    材質不是繞序，繞序沒理由重新發明一次（重新發明的代價是整批面被剔掉，
    而那種錯只有在引擎裡才看得見）。"""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.mats = []

    def tri(self, a, b, c, mat, flip=False):
        i = len(self.verts)
        self.verts += [a, c, b] if flip else [a, b, c]
        self.faces.append((i, i + 1, i + 2))
        self.mats.append(ORDER.index(mat))

    def quad(self, a, b, c, d, mat, flip=False):
        self.tri(a, b, c, mat, flip)
        self.tri(a, c, d, mat, flip)

    def box(self, cx, cy, cz, w, d, h, mat, top=None, skip_bottom=True):
        x0, x1 = cx - w / 2, cx + w / 2
        y0, y1 = cy - d / 2, cy + d / 2
        z0, z1 = cz - h / 2, cz + h / 2
        top = top or mat
        self.quad((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), top)
        if not skip_bottom:
            self.quad((x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0), mat)
        self.quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), mat)
        self.quad((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1), mat)
        self.quad((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1), mat)
        self.quad((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1), mat)

    def prism_y(self, x0, x1, y, z, ay, az, by, bz, mat):
        """沿 x 走的三角柱（丸瓦、破風板的斷面都用它）。
        斷面三點：(y,z)、(y+ay, z+az)、(y+by, z+bz)。"""
        p = [(x0, y, z), (x0, y + ay, z + az), (x0, y + by, z + bz)]
        q = [(x1, y, z), (x1, y + ay, z + az), (x1, y + by, z + bz)]
        for k in range(3):
            k2 = (k + 1) % 3
            self.quad(p[k], p[k2], q[k2], q[k], mat)
        self.tri(p[0], p[1], p[2], mat)
        self.tri(q[0], q[2], q[1], mat)

    def build(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        me.update()
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        for m in ORDER:
            ob.data.materials.append(bpy.data.materials[m])
        for pi, poly in enumerate(me.polygons):
            poly.use_smooth = False
            poly.material_index = self.mats[pi]
        return ob


def make_materials():
    for name, (col, rough) in MATS.items():
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.25
        elif "Specular" in bsdf.inputs:
            bsdf.inputs["Specular"].default_value = 0.25


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


# ══════════════════════════════════════════════════════════════════════
# 町家本體
# ══════════════════════════════════════════════════════════════════════
#
# 高度預算（總高由規格給，屋身**反推** —— 跟舊版同一條規矩，
# 因為天際線的階梯是使用者定案過的，prototype 不許順手改掉）：
#   body = 總高 − 基礎 − (D/2)·tanθ − 棟高
#
# 軸組的斷面（真實町家的尺寸，不是隨手給的）：
#   土台 150×150｜通し柱 150×150｜管柱 120×150｜貫 105×30（穿出柱面）
#   内法長押 130×30｜桁 180×180｜梁 150×240
POST = 0.150            # 柱斷面（正方）
SILL = 0.150            # 土台
PLATE = 0.180           # 桁
NUKI_T = 0.105          # 貫厚
PROUD = 0.030           # 貫／長押凸出柱面
INFILL = 0.100          # 漆喰嵌板厚
RECESS = 0.025          # 嵌板比柱面內縮 —— 真壁造在遠景唯一讀得出來的東西


def machiya_f_a(bld, W=7.6, D=7.8, total_h=4.50, pitch=math.radians(23.0),
                plinth=0.30, nbay=4):
    # ⚠ 扣的是**棟的實際堆疊高**（熨斗 0.13 + 冠瓦 0.13 = 0.26），不是舊版
    # 那個 0.14 —— 舊版的棟只有一根方條，這版是熨斗＋冠瓦兩層。第一次跑出來
    # 總高 4.78（規格 4.50），差的就是這 0.28。天際線的階梯是使用者定案過的，
    # prototype 不許順手改掉，所以是**屋身讓棟**。
    body = total_h - plinth - (D / 2) * math.tan(pitch) - RIDGE_STACK
    assert body > 1.8, "反推出的屋身太矮：%.2f" % body
    z0 = plinth                     # 土台底
    z_top = z0 + body               # 桁底（＝屋身頂）
    wall_y = POST / 2               # 牆心：柱外面剛好落在 y=0
    hw = W / 2
    bay = W / nbay
    posts_x = [-hw + i * bay for i in range(nbay + 1)]

    _foundation(bld, W, D, plinth)
    _frame(bld, W, D, z0, z_top, wall_y, posts_x)
    _walls(bld, W, D, z0, z_top, wall_y, posts_x, bay)
    door_x = _facade(bld, W, z0, z_top, wall_y, posts_x, bay)
    z_lintel = z0 + SILL + _NUKI_Z0 + 0.0    # 由 _facade 內部決定，見下
    _hisashi(bld, door_x, bay, z0 + LINTEL_Z, wall_y)
    ridge = _roof(bld, W, D, z_top, pitch)
    return ridge, door_x


# 内法高（門・格子的上緣）：一般町家 1.75~1.85。這裡取下限 1.72 ——
# 4.50 的總高扣掉 23° 屋頂（1.655）之後屋身只剩 2.29，內法再高一點，
# 長押以上的「小壁」就薄到讀不出來（真壁造的立面節奏就是靠那條小壁）。
LINTEL_Z = 1.72
RIDGE_STACK = 0.26          # 棟：熨斗瓦 0.13 + 冠瓦 0.13
_NUKI_Z0 = 0.0


def _foundation(bld, W, D, plinth):
    """石場建て：玉石基礎 + 一圈犬走り石。

    舊版是一塊比屋身大 0.22 的石頭方塊。真實町家是**礎石**（柱腳下的單顆石）
    加上外緣的**布基礎**。這裡折衷：連續的低石基（讀得出是石不是水泥）+
    四角與柱位的沓石凸出，剪影上就有「柱是坐在石頭上」的資訊。"""
    bld.box(0, D / 2, plinth / 2, W + 0.16, D + 0.16, plinth, "STONE")
    # 犬走り：基礎外一圈更矮的石緣，把建築接進地面
    bld.box(0, D / 2, 0.045, W + 0.62, D + 0.62, 0.09, "STONE")


def _frame(bld, W, D, z0, z_top, wall_y, posts_x):
    """軸組：土台 → 柱 → 貫 → 内法長押 → 桁 → 梁。

    ⚠ 這一段是整個 prototype 的重點。舊版沒有這層 —— 它只有「牆」跟「貼在
    牆上的木條」。有了軸組之後，漆喰才有東西可以填，真壁造才成立。"""
    hw = W / 2
    hpost = z_top - PLATE - (z0 + SILL)
    zc = (z0 + SILL + z_top - PLATE) / 2

    # 土台（四周一圈，坐在基礎上）
    bld.box(0, wall_y, z0 + SILL / 2, W, SILL, SILL, "WOOD")
    bld.box(0, D - wall_y, z0 + SILL / 2, W, SILL, SILL, "WOOD")
    for sx in (1, -1):
        bld.box(sx * (hw - wall_y), D / 2, z0 + SILL / 2, SILL, D, SILL, "WOOD")

    # 通し柱（四角）+ 管柱（正面／背面的間柱）
    for sx in (1, -1):
        for yy in (wall_y, D - wall_y):
            bld.box(sx * (hw - POST / 2), yy, zc, POST, POST, hpost, "WOOD")
    for px in posts_x[1:-1]:
        bld.box(px, wall_y, zc, POST, POST, hpost, "WOOD")
        bld.box(px, D - wall_y, zc, POST, POST, hpost, "WOOD")
    # 側面的管柱（進深方向，每 ~2.6m 一根）
    nside = max(2, int(D / 2.6))
    for i in range(1, nside):
        yy = i * (D / nside)
        for sx in (1, -1):
            bld.box(sx * (hw - POST / 2), yy, zc, POST, POST, hpost, "WOOD")

    # 貫：橫向穿過柱身、兩面各凸 30mm —— 真壁造的水平節奏
    for zz in (z0 + SILL + hpost * 0.34, z0 + SILL + hpost * 0.68):
        bld.box(0, wall_y, zz, W, POST + PROUD * 2, NUKI_T, "WOOD")
        bld.box(0, D - wall_y, zz, W, POST + PROUD * 2, NUKI_T, "WOOD")
        for sx in (1, -1):
            bld.box(sx * (hw - wall_y), D / 2, zz, POST + PROUD * 2, D, NUKI_T, "WOOD")

    # 内法長押（門・格子的上緣，正面才有 —— 它是**室內側**的裝飾材，
    # 町家的正面因為是店面所以看得到）
    bld.box(0, wall_y - PROUD, z0 + LINTEL_Z + 0.065, W, POST, 0.130, "WOOD")

    # 桁（柱頭，沿 x 走；屋頂坐在它上面）
    # ⚠ 桁**頂面齊 z_wall**，不是坐在 z_wall 上往上長。屋面在牆線的高度就是
    # z_wall，桁往上凸 0.18 的話會直接戳穿屋面 —— 規格明列的禁項
    # 「roof intersecting wall」。
    bld.box(0, wall_y, z_top - PLATE / 2, W + 0.10, PLATE, PLATE, "WOOD")
    bld.box(0, D - wall_y, z_top - PLATE / 2, W + 0.10, PLATE, PLATE, "WOOD")
    # ⚠ 小屋梁**不做**。它架在兩道桁之間、在屋根空間裡；而屋面在牆線上就是
    # z_wall，梁擺在那個高度一定穿出屋面。平入切妻的妻側看到的是妻壁與
    # 破風板，梁端本來就被破風板遮住 —— 做了也看不到，只會製造穿模。


def _walls(bld, W, D, z0, z_top, wall_y, posts_x, bay):
    """漆喰嵌板：**填在柱與柱之間**，比柱面內縮 25mm。

    ⚠ 這就是「不要 white box + wood strips attached outside」那條規格的實作。
    嵌板逐格生成、每格的四邊都是柱／貫／土台／桁 —— 牆不是一個連續量體，
    所以柱可以真的比牆凸出來，陰影線是**幾何**不是貼圖。"""
    hw = W / 2
    z_lo = z0 + SILL
    z_hi = z_top - PLATE
    # 正面：一階是建具（格子／板戶），漆喰只在内法長押以上那條「小壁」
    for i in range(len(posts_x) - 1):
        x0 = posts_x[i] + POST / 2
        x1 = posts_x[i + 1] - POST / 2
        zc = (z0 + LINTEL_Z + 0.13 + z_hi) / 2
        h = z_hi - (z0 + LINTEL_Z + 0.13)
        if h > 0.05:
            bld.box((x0 + x1) / 2, wall_y, zc, x1 - x0, INFILL, h, "PLASTER")
    # 背面：整面漆喰（逐格）
    for i in range(len(posts_x) - 1):
        x0 = posts_x[i] + POST / 2
        x1 = posts_x[i + 1] - POST / 2
        bld.box((x0 + x1) / 2, D - wall_y, (z_lo + z_hi) / 2,
                x1 - x0, INFILL, z_hi - z_lo, "PLASTER")
    # 側面：逐格（柱位由 _frame 的 nside 決定，這裡重算一次同樣的分割）
    nside = max(2, int(D / 2.6))
    ys = [0.0] + [i * (D / nside) for i in range(1, nside)] + [D]
    for sx in (1, -1):
        for i in range(len(ys) - 1):
            y0 = ys[i] + POST / 2
            y1 = ys[i + 1] - POST / 2
            bld.box(sx * (hw - wall_y), (y0 + y1) / 2, (z_lo + z_hi) / 2,
                    INFILL, y1 - y0, z_hi - z_lo, "PLASTER")
    # 腰板（下見板張り）：牆腳一圈木板，保護漆喰不被雨濺
    #   ⚠ 要**比柱面凸出**（板是釘在柱外的），不然看不出是兩種材料
    koshi = 0.62
    for sx in (1, -1):
        bld.box(sx * (hw - wall_y), D / 2, z_lo + koshi / 2,
                POST + 0.04, D, koshi, "WOOD_LT")
    bld.box(0, D - wall_y, z_lo + koshi / 2, W, POST + 0.04, koshi, "WOOD_LT")


def _facade(bld, W, z0, z_top, wall_y, posts_x, bay):
    """正面建具：出格子 / 連子格子 / 大戶口。回傳門的中心 x。

    四開間的節奏刻意**不對稱**（町家的正面本來就不對稱 —— 店・住・通り庭
    各佔各的開間）：
        bay0 出格子（凸窗，店面）｜bay1 連子格子｜bay2 大戶口｜bay3 連子格子
    """
    z_lo = z0 + SILL
    z_hi = z0 + LINTEL_Z
    door_i = 2
    door_x = 0.0
    for i in range(len(posts_x) - 1):
        x0 = posts_x[i] + POST / 2
        x1 = posts_x[i + 1] - POST / 2
        cx = (x0 + x1) / 2
        w = x1 - x0
        if i == door_i:
            door_x = cx
            _door(bld, cx, w, z_lo, z_hi, wall_y)
        elif i == 0:
            _degoushi(bld, cx, w, z_lo, z_hi, wall_y)
        else:
            _koushi(bld, cx, w, z_lo, z_hi, wall_y, koshi_h=0.42)
    return door_x


def _koushi(bld, cx, w, z_lo, z_hi, wall_y, koshi_h=0.42):
    """連子格子：腰板 + 障子背板 + 細直櫺。櫺條**凸出柱面** 20mm。"""
    bld.box(cx, wall_y, z_lo + koshi_h / 2, w, INFILL + 0.02, koshi_h, "WOOD_LT")
    zb = z_lo + koshi_h
    h = z_hi - zb
    bld.box(cx, wall_y + 0.01, zb + h / 2, w, INFILL, h, "SHOJI")
    n = max(4, int(w / 0.155))
    for k in range(n):
        x = cx - w / 2 + (k + 0.5) * (w / n)
        bld.box(x, wall_y - POST / 2 - 0.010, zb + h / 2, 0.032, 0.045, h, "WOOD")
    # 上下框
    for zz in (zb, z_hi):
        bld.box(cx, wall_y - POST / 2 - 0.008, zz, w, 0.052, 0.075, "WOOD")


def _degoushi(bld, cx, w, z_lo, z_hi, wall_y):
    """出格子：整組往街上凸 0.34m 的格子窗（町家店面的招牌構件）。

    ⚠ 它是**有厚度的盒子**不是一片格柵：底板（持ち送り撐著）、兩側板、
    上面一片小庇。少了任何一件都會讀成「牆上貼了一片柵欄」。"""
    proj = 0.34
    yc = wall_y - POST / 2 - proj / 2
    zb = z_lo + 0.42
    h = z_hi - zb
    bld.box(cx, wall_y, z_lo + 0.21, w, INFILL + 0.02, 0.42, "WOOD_LT")   # 腰板
    bld.box(cx, yc, zb - 0.055, w + 0.06, proj, 0.11, "WOOD")             # 底板
    for sx in (1, -1):                                                    # 側板
        bld.box(cx + sx * (w / 2 - 0.03), yc, zb + h / 2, 0.06, proj, h, "WOOD")
    bld.box(cx, wall_y + 0.01, zb + h / 2, w, INFILL, h, "SHOJI")         # 障子背板
    n = max(5, int(w / 0.135))
    for k in range(n):                                                    # 直櫺
        x = cx - w / 2 + (k + 0.5) * (w / n)
        bld.box(x, yc - proj / 2 + 0.028, zb + h / 2, 0.034, 0.055, h, "WOOD")
    bld.box(cx, yc, zb + h + 0.055, w + 0.10, proj + 0.06, 0.11, "WOOD")  # 上枠
    # 持ち送り（底板下的斜撐）
    for sx in (1, -1):
        bld.box(cx + sx * (w / 2 - 0.10), wall_y - POST / 2 - 0.10,
                zb - 0.22, 0.05, 0.20, 0.26, "WOOD")


def _door(bld, cx, w, z_lo, z_hi, wall_y):
    """大戶口：兩片板戶（中間留縫）+ 框 + 敷居。"""
    dw = (w - 0.09) / 2
    for sx in (-1, 1):
        bld.box(cx + sx * (dw + 0.045) / 2, wall_y - 0.012, (z_lo + z_hi) / 2,
                dw, INFILL, z_hi - z_lo, "WOOD_LT")
        # 板戶的橫桟（三道）
        for t in (0.22, 0.52, 0.82):
            bld.box(cx + sx * (dw + 0.045) / 2, wall_y - POST / 2 - 0.012,
                    z_lo + (z_hi - z_lo) * t, dw, 0.040, 0.075, "WOOD")
    bld.box(cx, wall_y - POST / 2 - 0.008, z_lo + 0.035, w + 0.06, 0.060, 0.070, "WOOD")


def _hisashi(bld, cx, w, z, wall_y):
    """庇（入口上方）：腕木 → 桁 → 垂木 → 野地 → 軒裏 → 鼻隠し → 瓦。

    ⚠ 規格明令禁止「horizontal cube sticking from wall」。所以這裡每一件都
    在：撐它的腕木、它自己的桁、看得到的垂木、有厚度的野地、仰視看得到的
    軒裏、簷口的鼻隠し、以及瓦。"""
    proj = 0.95
    slope = math.radians(17.0)
    y0 = wall_y - POST / 2
    y1 = y0 - proj
    z1 = z - proj * math.tan(slope)
    span = w + 0.9
    # 腕木（穿出牆面的懸臂）
    for sx in (-1, 1):
        bld.box(cx + sx * (w / 2 - 0.05), y0 - 0.30, z - 0.16,
                0.09, 0.62, 0.13, "WOOD")
    # 前桁
    bld.box(cx, y1 + 0.06, z1 + 0.02, span, 0.11, 0.13, "WOOD")
    # 垂木（看得到的椽）
    nr = max(5, int(span / 0.42))
    for k in range(nr):
        x = cx - span / 2 + (k + 0.5) * (span / nr)
        bld.prism_y(x - 0.026, x + 0.026, y0, z - 0.055,
                    -proj, -proj * math.tan(slope), -proj, -proj * math.tan(slope) - 0.055,
                    "WOOD")
    # 野地（含厚度）
    th = 0.055
    for x0, x1 in [(cx - span / 2, cx + span / 2)]:
        bld.quad((x0, y0, z), (x1, y0, z), (x1, y1, z1), (x0, y1, z1), "KAWARA")
        bld.quad((x0, y1, z1), (x1, y1, z1), (x1, y1, z1 - th), (x0, y1, z1 - th),
                 "KAWARA")                                    # 鼻隠し（簷口斷面）
        bld.quad((x0, y1, z1 - th), (x1, y1, z1 - th), (x1, y0, z - th), (x0, y0, z - th),
                 "WOOD_LT", flip=True)                        # 軒裏（仰視面）
        for sxx in (0, 1):                                    # 兩端封口
            xx = x0 if sxx == 0 else x1
            bld.quad((xx, y0, z), (xx, y1, z1), (xx, y1, z1 - th), (xx, y0, z - th),
                     "KAWARA", flip=(sxx == 0))
    # 瓦：縱向丸瓦
    nk = max(6, int(span / 0.33))
    for k in range(nk):
        x = cx - span / 2 + (k + 0.5) * (span / nk)
        bld.prism_y(x - 0.055, x + 0.055, y0, z,
                    0.0, 0.048, -proj, -proj * math.tan(slope) + 0.048, "KAWARA")


def _roof(bld, W, D, z_wall, pitch, overhang=0.85, thick=0.16):
    """切妻屋根（平入）：野地 → 軒裏 → 垂木 → 鼻隠し → 破風板 → 懸魚 →
    棟（熨斗＋冠）→ 丸瓦。

    ⚠ 屋脊錨在**牆面**（ridge = z_wall + (D/2)·tanθ），出簷沿同一斜度往外
    往下包 —— 跟 make_town.py 同一條規矩。改掉的話總高會多出 overhang·tanθ，
    使用者定案過的階梯天際線就破了。"""
    hw = W / 2 + overhang
    hd = D / 2 + overhang
    cy = D / 2
    ridge_z = z_wall + (D / 2) * math.tan(pitch)
    eave_z = z_wall - overhang * math.tan(pitch)
    slope_len = math.hypot(hd, hd * math.tan(pitch))

    for sy in (1, -1):
        ye = cy + sy * hd
        # 野地（瓦底層）
        bld.quad((-hw, cy, ridge_z), (hw, cy, ridge_z),
                 (hw, ye, eave_z), (-hw, ye, eave_z), "KAWARA", flip=(sy > 0))
        # 鼻隠し（簷口斷面）
        bld.quad((-hw, ye, eave_z), (hw, ye, eave_z),
                 (hw, ye, eave_z - thick), (-hw, ye, eave_z - thick),
                 "KAWARA", flip=(sy > 0))
        # 軒裏（仰視面）—— 木色，不是瓦色
        bld.quad((-hw, ye, eave_z - thick), (hw, ye, eave_z - thick),
                 (hw, cy + sy * (D / 2 - 0.05), z_wall - thick),
                 (-hw, cy + sy * (D / 2 - 0.05), z_wall - thick),
                 "WOOD_LT", flip=(sy < 0))
        # 垂木（簷下看得到的椽，只做出簷段 —— 牆內看不到）
        nr = max(8, int(W / 0.45))
        for k in range(nr + 1):
            x = -hw + k * (2 * hw / nr)
            y_in = cy + sy * (D / 2 - 0.02)
            bld.prism_y(x - 0.030, x + 0.030,
                        y_in, z_wall - thick - 0.005,
                        (ye - y_in), (eave_z - thick - 0.005) - (z_wall - thick - 0.005),
                        (ye - y_in), (eave_z - thick - 0.062) - (z_wall - thick - 0.005),
                        "WOOD")
        # 丸瓦（本瓦葺きの縱向半圓）—— 近看有瓦的關鍵
        nk = max(10, int(2 * hw / 0.36))
        for k in range(nk):
            x = -hw + (k + 0.5) * (2 * hw / nk)
            bld.prism_y(x - 0.062, x + 0.062, cy, ridge_z,
                        0.0, 0.052,
                        sy * hd, (eave_z - ridge_z) + 0.052, "KAWARA")
        # 軒瓦（簷端的巴瓦：每條丸瓦末端一個小圓盤，剪影上是一排點）
        for k in range(nk):
            x = -hw + (k + 0.5) * (2 * hw / nk)
            bld.box(x, ye - sy * 0.045, eave_z + 0.055, 0.115, 0.09, 0.085, "KAWARA")

    # 破風板（妻側的封簷板）+ 懸魚
    for sx in (1, -1):
        gx = sx * hw
        # 妻壁是**漆喰**不是瓦 —— 破風板壓在它外面，兩者材質不同才讀得出
        # 「板釘在牆上」。第一版整片給瓦色，妻側遠看是一塊純灰的三角形。
        bld.tri((gx - sx * 0.02, cy - hd, eave_z), (gx - sx * 0.02, cy + hd, eave_z),
                (gx - sx * 0.02, cy, ridge_z), "PLASTER", flip=(sx < 0))
        for sy in (1, -1):
            bld.prism_y(gx - sx * 0.075, gx,
                        cy, ridge_z + 0.05,
                        sy * hd, (eave_z - ridge_z),
                        sy * hd * 0.995, (eave_z - ridge_z) - 0.27, "WOOD_LT")
        bld.box(gx - sx * 0.05, cy, ridge_z - 0.30, 0.10, 0.34, 0.40, "WOOD")

    # 棟：熨斗瓦（層疊的平瓦）+ 冠瓦（半圓）
    bld.box(0, cy, ridge_z + 0.065, 2 * hw + 0.20, 0.44, 0.13, "KAWARA")
    bld.prism_y(-hw - 0.13, hw + 0.13, cy - 0.19, ridge_z + 0.13,
                0.19, 0.13, 0.38, 0.0, "KAWARA")
    return ridge_z


# ══════════════════════════════════════════════════════════════════════
# 匯出 + 幾何驗證
# ══════════════════════════════════════════════════════════════════════

def validate(ob):
    """匯出前的幾何自檢：退化面、法線一致性、鬆散頂點、材質覆蓋。
    在 Blender 這一端擋，比在引擎裡看著一片黑再回頭查便宜太多。"""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    degen = [f for f in bm.faces if f.calc_area() < 1e-9]
    loose = [v for v in bm.verts if not v.link_faces]
    nonmanifold = [e for e in bm.edges if not e.is_manifold]
    slots = {}
    for f in bm.faces:
        slots[f.material_index] = slots.get(f.material_index, 0) + 1
    bm.free()
    report = {
        "faces": len(me.polygons),
        "verts": len(me.vertices),
        "degenerate": len(degen),
        "loose_verts": len(loose),
        "non_manifold_edges": len(nonmanifold),
        "material_faces": {ORDER[k]: v for k, v in sorted(slots.items())},
    }
    return report


def bbox(ob):
    vs = [v.co for v in ob.data.vertices]
    return (max(v.x for v in vs) - min(v.x for v in vs),
            max(v.y for v in vs) - min(v.y for v in vs),
            max(v.z for v in vs))


def gbox(ob):
    vs = [v.co for v in ob.data.vertices]
    return [round(min(v.x for v in vs), 3), round(max(v.x for v in vs), 3),
            round(-max(v.y for v in vs), 3), round(-min(v.y for v in vs), 3)]


def export(ob, name):
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    # ⚠ export_materials 必須留在 EXPORT（預設）——這支的重點就是材質身分
    # 要活著走完 Blender → GLB → Godot。
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True,
                              export_format="GLB", export_yup=True,
                              export_apply=True, export_materials="EXPORT")
    return path


# ══════════════════════════════════════════════════════════════════════
# Art review 渲染（中性光、中性背景、無霧無景深）
# ══════════════════════════════════════════════════════════════════════

VIEWS = [
    ("01_front",       (0.0, -22.0, 3.4),  (0.0, 3.9, 2.3)),
    ("02_front45",     (-15.5, -15.5, 6.0), (0.0, 3.9, 2.2)),
    ("03_side",        (24.0, 3.9, 3.4),   (0.0, 3.9, 2.3)),
    ("04_rear45",      (14.0, 19.0, 6.0),  (0.0, 3.9, 2.2)),
    ("05_elevated34",  (-13.0, -13.0, 13.0), (0.0, 3.9, 1.8)),
]


def _look_at(ob, target):
    import mathutils
    d = mathutils.Vector(target) - ob.location
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def render_views(ob, out_dir):
    import mathutils
    os.makedirs(out_dir, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 220
    # ⚠ 這台的 Blender 是 build without OpenImageDenoiser —— 開 denoising 會
    # 直接 RuntimeError。改成拉高 samples 硬解噪點（審圖要看幾何，不能有雜訊）。
    sc.cycles.use_denoising = False
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 1100
    sc.render.film_transparent = False
    # 中性背景：純灰，不用 HDRI（HDRI 會把顏色染掉，看不出材質本色）
    world = bpy.data.worlds.new("neutral")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.55, 0.56, 0.58, 1.0)
    bg.inputs[1].default_value = 1.0
    # 中性日光：一盞主光 + 一盞補光，**不做電影感**
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sc.collection.objects.link(sun)
    sun.data.energy = 3.0
    sun.data.angle = math.radians(2.0)
    sun.rotation_euler = (math.radians(52), 0, math.radians(-38))
    fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
    sc.collection.objects.link(fill)
    fill.data.energy = 0.9
    fill.rotation_euler = (math.radians(62), 0, math.radians(140))
    # 地面：中性灰，讓建築有影子可落（沒有地面的話量體會飄）
    bpy.ops.mesh.primitive_plane_add(size=140, location=(0, 3.9, 0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("GROUND")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
        0.20, 0.20, 0.20, 1.0)
    gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(gm)

    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 52.0
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    paths = []
    for name, pos, tgt in VIEWS:
        cam.location = mathutils.Vector(pos)
        _look_at(cam, tgt)
        sc.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)
        paths.append(sc.render.filepath)
        print("rendered %s" % sc.render.filepath)
    return paths


# ══════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    clear()
    make_materials()
    b = MB()
    ridge, door_x = machiya_f_a(b)
    ob = b.build("machiya_f_a")
    rep = validate(ob)
    bb = bbox(ob)
    print("\n── machiya_f_a（production prototype）──")
    print("  面 %d / 頂點 %d" % (rep["faces"], rep["verts"]))
    print("  退化面 %d / 鬆散頂點 %d / 非流形邊 %d"
          % (rep["degenerate"], rep["loose_verts"], rep["non_manifold_edges"]))
    print("  材質分佈：%s" % rep["material_faces"])
    print("  bbox %.2f × %.2f × %.2f（總高規格 4.50）" % bb)
    print("  gbox %s　門位 x=%.2f" % (gbox(ob), door_x))
    p = export(ob, "machiya_f_a")
    print("  匯出 %s" % p)
    # manifest 片段（gen_town 讀 town_modules.json；這裡印出來讓
    # make_town.py 那份可以對照，不在這支裡覆寫整份 manifest）
    print("  MANIFEST fw=%.2f fd=%.2f h=%.2f gbox=%s"
          % (round(bb[0], 2), round(bb[1], 2), round(bb[2], 2), gbox(ob)))
    if RENDER_DIR:
        render_views(ob, RENDER_DIR)
