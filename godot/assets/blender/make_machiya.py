# 町家 Production Kit —— PHASE 2 Architecture Kit
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
#    每個構件指定語意材質（WOOD / WOOD_LT / PLASTER / STONE / KAWARA /
#    SHOJI），glTF 匯出時一種材質一個 primitive，Godot 端逐 surface 掛
#    專案的 PBR 材質庫。
#
# 3. **屋頂是一組構件，不是一片斜面。**
# 4. **庇是完整的建築構件**（腕木→桁→垂木→野地→軒裏→鼻隠し→瓦）。
#
# ══════════════════════════════════════════════════════════════════════
# PHASE 2：variation 的規矩 ——「同一文化、不同家庭」
# ══════════════════════════════════════════════════════════════════════
#
# 這一輪要解的是**重複感**，但重複感的相反不是「每棟都不一樣」。一條真實的
# 町並み看起來是同一個聚落，是因為所有人家共用同一套做法；看起來不是複製
# 貼上，是因為每一家的**間口、財力、行業**不同。所以變化分兩類：
#
#   ── 不變的（人的尺度 / 同一文化）──────────────────────────────
#     内法高 LINTEL_Z 1.85（門與格子的上緣）—— 人的身高沒有因為家而不同
#     柱斷面 150／貫 105／長押 130／腰板 0.62（工房 0.85 是**功能**不是品味）
#     材質六種、真壁造的填法、桟瓦の葺き方、犬走り、玉石基礎
#   ── 變的（家的尺度 / 不同家庭）────────────────────────────────
#     間口 W 5.2 ~ 9.8｜總高 4.85 ~ 6.40｜厨子二階 無／虫籠窓／真二階
#     開間數與配置（出格子・連子格子・大戶口・板戶）
#     平入り／妻入り｜庇の長さと位置｜卯建・煙出し｜坡度 19 ~ 23°
#
# ⚠ 明令：**不做「同一 mesh 換 scale／rotation」的假 variation**。
#    每個 variant 的面數、開間數、剪影都不同，是各自生成的幾何。
#    （Phase 1.6 的 slice 曾經用 f_a 轉 90° 冒充妻入り —— 這輪它被
#      真正的妻入り模組 `machiya_t_a` 取代。）
#
# ── 模組座標約定（跟 make_town.py 一致，不能改，佈局端吃這個）──
#   正面朝 -y、原點在正面地面中心、x = 面寬方向。
#   Blender(x, y, z) → Godot(x, z, -y)。
import bpy
import bmesh
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_compat as BC   # shader nodes by TYPE, not by (localized) name

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
    而那種錯只有在引擎裡才看得見）。

    ⚠ PHASE 2 新增 `xf`：一個作用在頂點上的座標變換。妻入り的屋頂就是
    「把平入りの屋根轉 90°」—— 但**不是**把整棟 mesh 轉 90°（那就是規格
    禁止的假 variation），而是只把屋根這一組構件在生成時轉過去，牆體、
    立面、庇全部照原方向長。變換必須是**行列式為正的旋轉**，否則繞序
    會整批反掉、引擎剔面（Blender 雙面看不出來，代價見 docs §3）。"""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.mats = []
        self.xf = None

    def _p(self, p):
        return self.xf(p) if self.xf else p

    def tri(self, a, b, c, mat, flip=False):
        a, b, c = self._p(a), self._p(b), self._p(c)
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
        bsdf = BC.principled(m)
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
# 不變量 —— 「同一文化」就寫在這幾個常數裡
# ══════════════════════════════════════════════════════════════════════
#
# 軸組的斷面（真實町家的尺寸，不是隨手給的）：
#   土台 150×150｜通し柱 150×150｜管柱 120×150｜貫 105×30（穿出柱面）
#   内法長押 130×30｜桁 180×180
POST = 0.150            # 柱斷面（正方）
SILL = 0.150            # 土台
PLATE = 0.180           # 桁
NUKI_T = 0.105          # 貫厚
PROUD = 0.030           # 貫／長押凸出柱面
INFILL = 0.100          # 漆喰嵌板厚
RECESS = 0.025          # 嵌板比柱面內縮 —— 真壁造在遠景唯一讀得出來的東西
# 内法高（門・格子的上緣）。**全 kit 共用** —— 一條街上所有人家的門一樣高，
# 這是「同一文化」最強的一個訊號，比材質還強。變的是門的寬與樣式。
LINTEL_Z = 1.85
# 棟：桟瓦葺きの棟（熨斗少一層）
RIDGE_STACK = 0.24


# ══════════════════════════════════════════════════════════════════════
# Variant 明表 —— 六戶人家
# ══════════════════════════════════════════════════════════════════════
#
# 欄位裡沒有一項是「隨機微調」。每一筆都對應一個**社會事實**：
# 間口寬 = 地價與家業規模｜厨子二階的有無與高度 = 建造年代與財力｜
# 卯建 = 有錢（「うだつが上がらない」的那個うだつ）｜煙出し = 用火的行業｜
# 妻入り = 地界的方向（角地或路的另一側）。
#
# W/D/total_h/pitch 由 make_town.py 的 MACHIYA 表覆寫（一份 manifest 一個
# 寫入者）；這裡的值是單獨跑本檔時的預設，兩邊必須一致。
DEFAULT = {
    "W": 7.6, "D": 7.8, "total_h": 5.40, "pitch": 21.0, "plinth": 0.30,
    "bays": ["degoushi", "koushi", "door", "koushi"],
    "tsushi": ("mushiko", 2.36, 0.78),   # (mode, z0, h)
    "hisashi": ("full", 0.88, 0.50),     # (mode, proj, span_over)
    "orient": "hira",                    # hira 平入り / tsuma 妻入り
    "overhang": 0.85,
    "koshi": 0.62,                       # 腰板（下見板張り）高
    "udatsu": False,                     # 卯建（防火袖壁）
    "smoke": False,                      # 煙出し（屋根の櫓）
    "gyogyo": True,                      # 懸魚
}

SPECS = {
    # ── 標準商家。PHASE 1.1/1.7 審過的那一棟，幾何一個字不動 ──
    "machiya_f_a": {},

    # ── 仕舞屋（しもたや）：小間口の住宅。店をやめた家、あるいは職人の家 ──
    # 間口 5.2 は町家の最小級（京間三間）。厨子二階なし＝古い形／慎ましい家。
    # 庇は入口の上だけ —— 通し庇は店の設備で、商売をしない家には要らない。
    "machiya_f_s": {
        "W": 5.2, "D": 6.8, "total_h": 4.85, "pitch": 22.0,
        "bays": ["koushi", "door_s", "koushi"],
        "tsushi": ("none", 0, 0),
        "hisashi": ("entry", 0.72, 1.15),
        "koshi": 0.74,
    },

    # ── 大店（おおだな）：裕福な商家。間口が広い＝地価を払える ──
    # 出格子が二間ぶん、大戶口も広い。厨子二階は高く（虫籠窓 0.95）、
    # 卯建まで上げている。天際線で一番高い民家はこれ。
    "machiya_f_o": {
        "W": 9.8, "D": 8.6, "total_h": 6.15, "pitch": 20.0,
        "bays": ["degoushi", "degoushi", "door_w", "koushi", "koushi"],
        "tsushi": ("mushiko", 2.52, 0.95),
        "hisashi": ("full", 1.02, 0.62),
        "udatsu": True,
    },

    # ── 妻入りの町家：山牆が街を向く ──
    # ⚠ これは f_a を 90° 回したものでは**ない**。屋根だけが 90° で、
    #    立面・庇・軸組は街向きのまま生成される。だから間口 6.4 の正面に
    #    破風と懸魚が乗り、平入りには存在しない剪影になる。
    "machiya_t_a": {
        "W": 6.4, "D": 8.8, "total_h": 5.70, "pitch": 23.0,
        "bays": ["koushi", "door", "koushi"],
        "tsushi": ("mushiko", 2.36, 0.70),
        "hisashi": ("entry", 0.95, 1.45),
        "orient": "tsuma", "overhang": 0.78,
    },

    # ── 工房（紺屋・鍛冶・木地師）：住居ではなく仕事場 ──
    # 大戶口が広い（荷と道具が通る）、格子は少ない（採光より作業面）、
    # 腰板が高い（水と火を使う）、屋根に煙出し。庇は深い（作業が外にはみ出す）。
    "machiya_w_a": {
        "W": 7.2, "D": 7.4, "total_h": 5.15, "pitch": 19.0,
        "bays": ["itado", "door_w", "itado"],
        "tsushi": ("none", 0, 0),
        "hisashi": ("full", 1.06, 0.44),
        "koshi": 0.95, "smoke": True, "gyogyo": False,
    },

    # ── 二階建て（明治以降の新しい家）：厨子ではなく本物の二階 ──
    # 二階に連子格子の窓と手摺。庇は一階の上だけ。町並みの中で一番「新しい」。
    "machiya_f_n": {
        "W": 8.0, "D": 8.2, "total_h": 6.40, "pitch": 21.0,
        "bays": ["koushi", "door", "koushi", "degoushi"],
        "tsushi": ("nikai", 2.36, 1.42),
        "hisashi": ("full", 0.82, 0.50),
    },

    # ══ PHASE 3 Architecture Consolidation：legacy を消すための三戸 ══
    #
    # ⚠ この三戸は「舊 blockout を production 風に化粧したもの」ではない。
    #   軸組・嵌板・組物屋根は他の六戸とまったく同じ経路で生成される。
    #   既存モジュールを scale して名前を変えたものは一つもない。

    # ── 村緣の平屋：`machiya_e_a`（49 棟）の置き換え ──────────────
    # 里の外縁、田と町のあいだの家。店ではないので通し庇はなく、入口だけ。
    # 一間ぶんが板戸 —— 農具と薪を仕舞う土間がそのまま道に面している。
    # 腰板が高いのは風雨が直接当たる場所だから。懸魚は付けない（格が違う）。
    #
    # ⚠ 高さについて：`machiya_e_a` は総高 3.50 だったが、内法 1.85 の真壁を
    #   建てて瓦を葺くと 3.50 には**物理的に入らない**（反推した屋身が
    #   1.8m の下限を割る）。内法高は kit 全戸共通の契約なので下げられない。
    #   したがって総高は 4.15 —— 前列の 5.40 より明確に低く、段差は残る。
    #   fw/fd は e_a と同じ 7.90 に合わせてあるので**配置は 1cm も動かない**。
    "machiya_e_p": {
        "W": 6.0, "D": 6.2, "total_h": 4.15, "pitch": 19.0,
        "bays": ["itado", "door_s", "koushi"],
        "tsushi": ("none", 0, 0),
        "hisashi": ("entry", 0.68, 1.20),
        "koshi": 0.80, "overhang": 0.84, "plinth": 0.26,
        "gyogyo": False,
    },

    # ── 総二階（そうにかい）：`machiya_b_a`（20 棟）の置き換え ────────
    # 後列の二層目のスカイラインを担う家。厨子ではなく**本物の二階**で、
    # 一階の階高が 3.30 と高い（後列は蔵と作業場を兼ねる）。
    # 二階は連子格子＋手摺、通し庇が一階の上を横に切る。
    #
    # ⚠ 総高について：b_a は 9.40 だったが、その高さの 4.0m は**45° の屋根**
    #   が稼いでいたもので、屋身は 5.06 しかない。21〜23° の kit 語彙で
    #   同じ 9.40 に届かせようとすると三階建てになる（＝嘘）。
    #   実測（前列の軒 3.66m を 6.1m 先から見る角を 14m 先で超える高さ）は
    #   **6.14m** —— 7.65 なら二層目は 1.5m ぶん残る。潰れてはいない。
    # ⚠ bays は `machiya_f_n` と**必ず違えること**。最初の版は f_n と
    #   一字一句同じ並び（koushi/door/koushi/degoushi）で、間口と総高だけ
    #   違う「同じ家の大きい版」になっていた —— それは規格が禁じている
    #   fake variation そのもの。後列の家は荷が入るので大戸口と板戸を持つ。
    "machiya_n_a": {
        "W": 9.2, "D": 7.6, "total_h": 7.65, "pitch": 23.0,
        "bays": ["koushi", "koushi", "door_w", "itado"],
        "tsushi": ("nikai", 3.30, 1.55),
        "hisashi": ("full", 0.85, 0.46),
        "koshi": 0.66, "overhang": 0.84,
    },

    # ── 米屋・仕出し：`machiya_f_b`（32 棟）の置き換え ────────────────
    # 前列でいちばん数の多い「間口が広くて背の低い店」。荷が土間に入るので
    # 大戸口が広く、その隣は板戸（俵と炭を積む）。厨子二階は**無い** ——
    # 使用者が承認した階梯天際線（前列 4.5 / 後列 9〜10）の低い側を担うのが
    # この家の都市的な役割なので、二階を足して f_a に近づけてはいけない。
    # 通し庇は深い（荷を濡らさない）。
    #
    # ⚠ 総高 4.50 → 4.60。内法 1.85 の真壁に瓦を葺くと 4.50 では小壁が
    #   0.05m を切って嵌板が生成されない。0.10m だけ上げて成立させた。
    "machiya_f_m": {
        "W": 8.8, "D": 7.6, "total_h": 4.60, "pitch": 21.0,
        "bays": ["degoushi", "door_w", "itado", "koushi"],
        "tsushi": ("none", 0, 0),
        "hisashi": ("full", 0.85, 0.42),
        "koshi": 0.72, "overhang": 0.84, "gyogyo": False,
    },

    # ── 総二階の大店：`machiya_b_b`（16 棟）の置き換え ──────────────
    # n_a を広げただけにはしない。間口が五間、卯建が上がり、屋根に煙出し
    # ——「後列でいちばん羽振りのいい家」。勾配も 24° で n_a と分ける。
    "machiya_n_o": {
        "W": 10.4, "D": 8.0, "total_h": 7.95, "pitch": 24.0,
        "bays": ["koushi", "door_w", "degoushi", "koushi", "itado"],
        "tsushi": ("nikai", 3.45, 1.55),
        "hisashi": ("full", 0.85, 0.44),
        "koshi": 0.66, "overhang": 0.84, "udatsu": True, "smoke": True,
    },
}


def spec_of(name, W=None, D=None, total_h=None, pitch=None):
    s = dict(DEFAULT)
    s.update(SPECS[name])
    if W is not None:
        s["W"] = W
    if D is not None:
        s["D"] = D
    if total_h is not None:
        s["total_h"] = total_h
    if pitch is not None:
        s["pitch"] = pitch
    return s


# ══════════════════════════════════════════════════════════════════════
# 町家本體
# ══════════════════════════════════════════════════════════════════════

def machiya(bld, s):
    """高度預算（總高由規格給，屋身**反推**）：

        body = 總高 − 基礎 − (跨距/2)·tanθ − 棟高

    ⚠ 「跨距」平入り是進深 D、妻入り是**面寬 W** —— 屋脊轉了 90°，
      屋根の rise 就改由另一個方向決定。這一行是妻入り真正的技術差別，
      不是把 mesh 轉過去而已。

    回傳 (ridge_z, door_x)。"""
    W, D = s["W"], s["D"]
    pitch = math.radians(s["pitch"])
    plinth = s["plinth"]
    tsuma = s["orient"] == "tsuma"
    span = W if tsuma else D          # 屋根が落ちる方向の全長
    body = s["total_h"] - plinth - (span / 2) * math.tan(pitch) - RIDGE_STACK
    assert body > 1.8, "反推出的屋身太矮：%.2f（%s）" % (body, s)
    z0 = plinth                     # 土台底
    z_top = z0 + body               # 桁底（＝屋身頂）
    wall_y = POST / 2               # 牆心：柱外面剛好落在 y=0
    nbay = len(s["bays"])
    hw = W / 2
    bay = W / nbay
    posts_x = [-hw + i * bay for i in range(nbay + 1)]
    tmode, tz0, th = s["tsushi"]

    _foundation(bld, W, D, plinth)
    _frame(bld, W, D, z0, z_top, wall_y, posts_x)
    _walls(bld, W, D, z0, z_top, wall_y, posts_x, bay, tmode, tz0, th, s["koshi"])
    door_x, door_w = _facade(bld, W, z0, z_top, wall_y, posts_x, bay, s["bays"])
    if tmode == "mushiko":
        _tsushi(bld, W, z0, wall_y, posts_x, tz0, th)
    elif tmode == "nikai":
        _nikai(bld, W, z0, wall_y, posts_x, tz0, th)
    # 通し庇：**橫貫整個面寬**，不是只罩住入口。
    # ⚠ 這是把「屋頂壓倒立面」真正解掉的那一件：高立面需要一條水平線把它
    # 切成「一階店面／厨子二階」兩段。但**不是每一家都有** —— 通し庇是
    # 店の設備。住宅（f_s）と妻入り（t_a）は入口の上だけ。
    hmode, hproj, hover = s["hisashi"]
    if hmode == "full":
        _hisashi(bld, 0.0, W, z0 + LINTEL_Z + 0.20, wall_y,
                 span_over=hover, proj=hproj)
    elif hmode == "entry":
        _hisashi(bld, door_x, door_w, z0 + LINTEL_Z + 0.20, wall_y,
                 span_over=hover, proj=hproj)
    ridge = _roof_dispatch(bld, s, W, D, z_top, pitch)
    if s["udatsu"]:
        _udatsu(bld, W, z0, z_top, wall_y)
    if s["smoke"]:
        _smoke(bld, W, D, z_top, pitch, s["overhang"], tsuma)
    return ridge, door_x, z_top


def _roof_dispatch(bld, s, W, D, z_top, pitch):
    """平入り＝そのまま。妻入り＝**屋根だけ**を 90° 回した座標系で生成。

    変換は行列式 +1 の回転（[[0,-1,0],[1,0,0],[0,0,1]]）—— 鏡像にすると
    繞序が全部裏返って Godot が剔面する。Blender は両面で描くので
    見た目では気づけない（docs §3 の「参道が丸ごと消えた」件と同じ罠）。"""
    if s["orient"] != "tsuma":
        return _roof(bld, W, D, z_top, pitch, s["overhang"], gyogyo=s["gyogyo"])
    W_r, D_r = D, W        # 屋根から見た「棟方向の長さ」「勾配方向の長さ」
    bld.xf = lambda p: (D_r * 0.5 - p[1], p[0] + W_r * 0.5, p[2])
    try:
        ridge = _roof(bld, W_r, D_r, z_top, pitch, s["overhang"], gyogyo=s["gyogyo"])
    finally:
        bld.xf = None
    return ridge


def _foundation(bld, W, D, plinth):
    """石場建て：玉石基礎 + 一圈犬走り石。

    舊版是一塊比屋身大 0.22 的石頭方塊。真實町家是**礎石**（柱腳下的單顆石）
    加上外緣的**布基礎**。這裡折衷：連續的低石基（讀得出是石不是水泥）+
    四角與柱位的沓石凸出，剪影上就有「柱是坐在石頭上」的資訊。"""
    bld.box(0, D / 2, plinth / 2, W + 0.16, D + 0.16, plinth, "STONE")
    # 犬走り：基礎外一圈更矮的石緣，把建築接進地面
    bld.box(0, D / 2, 0.045, W + 0.62, D + 0.62, 0.09, "STONE")


def _frame(bld, W, D, z0, z_top, wall_y, posts_x):
    """軸組：土台 → 柱 → 貫 → 内法長押 → 桁。

    ⚠ 這一段是整個 kit 的重點。舊版沒有這層 —— 它只有「牆」跟「貼在
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
    # z_wall，梁擺在那個高度一定穿出屋面。


def _walls(bld, W, D, z0, z_top, wall_y, posts_x, bay, tmode, tz0, th, koshi):
    """漆喰嵌板：**填在柱與柱之間**，比柱面內縮 25mm。

    ⚠ 這就是「不要 white box + wood strips attached outside」那條規格的實作。
    嵌板逐格生成、每格的四邊都是柱／貫／土台／桁 —— 牆不是一個連續量體，
    所以柱可以真的比牆凸出來，陰影線是**幾何**不是貼圖。"""
    hw = W / 2
    z_lo = z0 + SILL
    z_hi = z_top - PLATE
    # 正面：一階是建具（格子／板戶）。内法長押以上是漆喰。
    # 厨子二階／二階がある家は**三段に割る**（小壁 → 窓帯 → 上小壁）；
    # ない家（仕舞屋・工房）は内法から桁まで一枚の小壁 —— それが「低い家」
    # の立面。一枚で 0.8m 前後なら倉庫には読めない。
    for i in range(len(posts_x) - 1):
        x0 = posts_x[i] + POST / 2
        x1 = posts_x[i + 1] - POST / 2
        if tmode == "none":
            lo, hi = z0 + LINTEL_Z + 0.13, z_hi
            if hi - lo > 0.05:
                bld.box((x0 + x1) / 2, wall_y, (lo + hi) / 2,
                        x1 - x0, INFILL, hi - lo, "PLASTER")
            continue
        for lo, hi in ((z0 + LINTEL_Z + 0.13, z0 + tz0),
                       (z0 + tz0 + th, z_hi)):
            if hi - lo > 0.05:
                bld.box((x0 + x1) / 2, wall_y, (lo + hi) / 2,
                        x1 - x0, INFILL, hi - lo, "PLASTER")
        # 窗帶那一段仍要有牆（虫籠窓只開在開間中央 62%，兩側是漆喰）
        bld.box((x0 + x1) / 2, wall_y, z0 + tz0 + th / 2,
                x1 - x0, INFILL, th, "PLASTER")
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
    for sx in (1, -1):
        bld.box(sx * (hw - wall_y), D / 2, z_lo + koshi / 2,
                POST + 0.04, D, koshi, "WOOD_LT")
    bld.box(0, D - wall_y, z_lo + koshi / 2, W, POST + 0.04, koshi, "WOOD_LT")


def _facade(bld, W, z0, z_top, wall_y, posts_x, bay, bays):
    """正面建具。回傳 (門的中心 x, 門開間的寬)。

    開間の並びは spec の `bays` がそのまま順番 —— 町家の正面は本来
    非対称（店・住・通り庭がそれぞれ開間を取る）。ここで variant ごとに
    違う顔ができる。"""
    z_lo = z0 + SILL
    z_hi = z0 + LINTEL_Z
    door_x, door_w = 0.0, bay
    for i, kind in enumerate(bays):
        x0 = posts_x[i] + POST / 2
        x1 = posts_x[i + 1] - POST / 2
        cx = (x0 + x1) / 2
        w = x1 - x0
        if kind == "door":
            door_x, door_w = cx, w
            _door(bld, cx, w, z_lo, z_hi, wall_y)
        elif kind == "door_w":
            door_x, door_w = cx, w
            _door(bld, cx, w, z_lo, z_hi, wall_y, rails=4)
        elif kind == "door_s":
            door_x, door_w = cx, w
            _door(bld, cx, w, z_lo, z_hi, wall_y, leaves=1, maxw=1.02)
        elif kind == "degoushi":
            _degoushi(bld, cx, w, z_lo, z_hi, wall_y)
        elif kind == "itado":
            _itado(bld, cx, w, z_lo, z_hi, wall_y)
        else:
            _koushi(bld, cx, w, z_lo, z_hi, wall_y, koshi_h=0.42)
    return door_x, door_w


def _tsushi(bld, W, z0, wall_y, posts_x, tz0, th):
    """厨子二階（つし二階）：一階內法之上的矮夾層，開**虫籠窓**。

    虫籠窓不是格子：它是**塗り込め**的 —— 木骨外面裹一層漆喰，所以櫺條
    又厚又圓、顏色跟牆一樣，剪影上是一排粗胖的白色豎條。跟一階那排細而
    深色的連子格子形成對比，這個對比就是町家立面的招牌。"""
    zb = z0 + tz0
    zt = zb + th
    for i in range(len(posts_x) - 1):
        x0 = posts_x[i] + POST / 2
        x1 = posts_x[i + 1] - POST / 2
        cx = (x0 + x1) / 2
        w = x1 - x0
        # 窗洞：比開間窄一截（虫籠窓不會做滿整間）
        ww = w * 0.62
        # 洞內的暗底（開口的深度）
        bld.box(cx, wall_y + 0.02, (zb + zt) / 2, ww, INFILL, th, "WOOD")
        # 塗り込め櫺：粗、圓、白 —— 用漆喰材質，不是木材質
        n = max(3, int(ww / 0.26))
        for k in range(n):
            x = cx - ww / 2 + (k + 0.5) * (ww / n)
            bld.box(x, wall_y - POST / 2 + 0.020, (zb + zt) / 2,
                    0.105, 0.075, th, "PLASTER")
        # 窗的上下框（漆喰的厚邊，塗り込め的特徵）
        for zz, hh in ((zb - 0.055, 0.11), (zt + 0.055, 0.11)):
            bld.box(cx, wall_y - POST / 2 + 0.015, zz, ww + 0.22, 0.085, hh, "PLASTER")


def _nikai(bld, W, z0, wall_y, posts_x, tz0, th):
    """真二階：厨子ではなく**人が立てる**二階。明治以降の町家。

    虫籠窓（塗り込め・白・太い）との差は決定的で、ここは一階と同じ
    **連子格子**（細い・木色・深い）を使い、外に手摺を回す。つまり
    「上にもう一軒ある」立面 —— 厨子二階の「屋根裏に窓が開いている」
    立面とは剪影が違う。"""
    zb = z0 + tz0
    zt = zb + th
    for i in range(len(posts_x) - 1):
        x0 = posts_x[i] + POST / 2
        x1 = posts_x[i + 1] - POST / 2
        cx = (x0 + x1) / 2
        w = x1 - x0
        ww = w * 0.86
        # 障子背板 + 連子格子（一階と同じ語彙・寸法）
        bld.box(cx, wall_y + 0.01, (zb + zt) / 2, ww, INFILL, th, "SHOJI")
        n = max(4, int(ww / 0.155))
        for k in range(n):
            x = cx - ww / 2 + (k + 0.5) * (ww / n)
            bld.box(x, wall_y - POST / 2 - 0.010, (zb + zt) / 2,
                    0.032, 0.045, th, "WOOD")
        for zz in (zb, zt):
            bld.box(cx, wall_y - POST / 2 - 0.008, zz, ww + 0.06, 0.052, 0.075, "WOOD")
    # 手摺（縁の外に回る）—— 二階の存在を剪影で言い切る一件
    yb = wall_y - POST / 2 - 0.16
    bld.box(0, yb, zb + 0.055, W - 0.10, 0.10, 0.11, "WOOD")          # 地覆
    bld.box(0, yb, zb + 0.62, W - 0.10, 0.09, 0.10, "WOOD")           # 笠木
    nb = max(6, int((W - 0.3) / 0.30))
    for k in range(nb):
        x = -(W - 0.30) / 2 + (k + 0.5) * ((W - 0.30) / nb)
        bld.box(x, yb, zb + 0.34, 0.045, 0.055, 0.46, "WOOD")         # 束
    for sx in (1, -1):                                                # 持ち送り
        bld.box(sx * (W / 2 - 0.35), wall_y - POST / 2 - 0.08, zb - 0.10,
                0.06, 0.17, 0.22, "WOOD")


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


def _itado(bld, cx, w, z_lo, z_hi, wall_y):
    """板戸張り（板壁）：格子ではなく**板**で塞いだ開間。工房の顔。

    採光より作業面・道具掛け。縦の板と横桟だけ —— 障子紙がないので
    夜も光が漏れない。街から見ると「ここは店ではない」と一目でわかる。"""
    bld.box(cx, wall_y - 0.014, (z_lo + z_hi) / 2, w, INFILL + 0.03,
            z_hi - z_lo, "WOOD_LT")
    n = max(4, int(w / 0.32))
    for k in range(1, n):                                   # 板の継ぎ目（竪桟）
        x = cx - w / 2 + k * (w / n)
        bld.box(x, wall_y - POST / 2 - 0.014, (z_lo + z_hi) / 2,
                0.045, 0.038, z_hi - z_lo, "WOOD")
    for t in (0.30, 0.72):                                  # 横桟
        bld.box(cx, wall_y - POST / 2 - 0.020, z_lo + (z_hi - z_lo) * t,
                w, 0.048, 0.080, "WOOD")
    bld.box(cx, wall_y - POST / 2 - 0.010, z_lo + 0.035, w + 0.04, 0.055, 0.070, "WOOD")


def _door(bld, cx, w, z_lo, z_hi, wall_y, leaves=2, maxw=None, rails=3):
    """大戶口：板戶 + 框 + 敷居。

    leaves=2 は引き分けの大戸（商家）、leaves=1 は片開きの小さな戸（仕舞屋）。
    maxw を与えると開間より狭い戸になり、余りは袖壁（漆喰）で埋まる ——
    間口が広くても戸まで広いとは限らない、というのが「家ごとの差」。"""
    ow = min(w, maxw) if maxw else w
    if ow < w - 0.02:                                        # 袖壁（両脇の漆喰）
        for sx in (-1, 1):
            sw = (w - ow) / 2
            bld.box(cx + sx * (ow + sw) / 2, wall_y, (z_lo + z_hi) / 2,
                    sw, INFILL, z_hi - z_lo, "PLASTER")
    if leaves == 1:
        dws = [(0.0, ow)]
    else:
        dw = (ow - 0.09) / 2
        dws = [(-(dw + 0.045) / 2, dw), ((dw + 0.045) / 2, dw)]
    ts = [0.22, 0.52, 0.82] if rails == 3 else [0.17, 0.40, 0.63, 0.86]
    for dx, dw in dws:
        bld.box(cx + dx, wall_y - 0.012, (z_lo + z_hi) / 2,
                dw, INFILL, z_hi - z_lo, "WOOD_LT")
        for t in ts:                                         # 板戸の横桟
            bld.box(cx + dx, wall_y - POST / 2 - 0.012,
                    z_lo + (z_hi - z_lo) * t, dw, 0.040, 0.075, "WOOD")
    bld.box(cx, wall_y - POST / 2 - 0.008, z_lo + 0.035, ow + 0.06, 0.060, 0.070, "WOOD")


def _hisashi(bld, cx, w, z, wall_y, span_over=0.9, proj=0.95):
    """庇（入口上方）：腕木 → 桁 → 垂木 → 野地 → 軒裏 → 鼻隠し → 瓦。

    ⚠ 規格明令禁止「horizontal cube sticking from wall」。所以這裡每一件都
    在：撐它的腕木、它自己的桁、看得到的垂木、有厚度的野地、仰視看得到的
    軒裏、簷口的鼻隠し、以及瓦。"""
    slope = math.radians(17.0)
    y0 = wall_y - POST / 2
    y1 = y0 - proj
    z1 = z - proj * math.tan(slope)
    span = w + span_over
    # 腕木（穿出牆面的懸臂）—— 通し庇要多幾根，不然中段會像懸空的板
    n_arm = max(2, int(span / 2.1) + 1)
    for k in range(n_arm):
        ax = cx - span / 2 + 0.35 + k * ((span - 0.70) / max(1, n_arm - 1))
        bld.box(ax, y0 - 0.30, z - 0.16, 0.09, 0.62, 0.13, "WOOD")
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
    # 瓦：桟瓦（淺桟）—— 跟主屋頂同一套語彙
    nk = max(8, int(span / 0.30))
    for k in range(nk):
        x = cx - span / 2 + (k + 0.5) * (span / nk)
        bld.prism_y(x - 0.028, x + 0.028, y0, z,
                    0.0, 0.024, -proj, -proj * math.tan(slope) + 0.024, "KAWARA")


def _udatsu(bld, W, z0, z_wall, wall_y):
    """卯建（うだつ）：隣家との境に立ち上げる**防火袖壁**。

    実用は延焼止め、実際は財力の表示 —— 「うだつが上がらない」の語源。
    町並みの中で一軒だけこれがあると、天際線に縦の切れ目が入る。
    構成：漆喰の袖壁 + 上に小さな切妻の瓦屋根 + 軒裏。"""
    # ⚠ 最初 dep=1.05 / top=+0.62 で作ったら lineup で**白い柱**に読めた。
    # 卯建は「庇の上に立ち上がる壁」であって独立した塔ではない ——
    # 出を庇より少し深いだけに、立ち上がりを軒より少し高いだけに抑える。
    t = 0.26                                   # 壁厚
    dep = 0.72                                 # 街側への出
    top = z_wall + 0.42
    base = z0 + LINTEL_Z + 0.34                # 通し庇の上から立ち上がる
    yc = wall_y - POST / 2 - dep / 2
    for sx in (1, -1):
        gx = sx * (W / 2 - t / 2)
        bld.box(gx, yc, (base + top) / 2, t, dep, top - base, "PLASTER")
        # 小屋根（両流れの小さな切妻）
        cap = 0.13
        for sy in (1, -1):
            bld.prism_y(gx - t / 2 - 0.09, gx + t / 2 + 0.09,
                        yc, top + cap + 0.05,
                        sy * (dep / 2 + 0.09), -cap,
                        sy * (dep / 2 + 0.09), -cap - 0.06, "KAWARA")
        bld.box(gx, yc, top + cap + 0.10, t + 0.26, 0.16, 0.09, "KAWARA")   # 棟


def _smoke(bld, W, D, z_wall, pitch, overhang, tsuma):
    """煙出し（けむだし）：棟に乗る小さな櫓。火と煙を使う家の印。

    紺屋の藍甕、鍛冶の炉、竈 —— 屋根に穴を開けて越屋根を乗せる。
    剪影に「屋根の上にもう一つ屋根」が出るので、遠景でも一軒だけ違う。"""
    span = W if tsuma else D
    ridge_z = z_wall + (span / 2) * math.tan(pitch)
    length = (D if tsuma else W) * 0.34
    wdt = 0.86
    h = 0.52
    cy = D / 2
    zb = ridge_z - 0.06
    # 櫓の胴（板張り）+ ルーバー
    if tsuma:
        bld.box(0, cy, zb + h / 2, wdt, length, h, "WOOD_LT")
        for k in range(3):
            bld.box(0, cy, zb + 0.12 + k * 0.15, wdt + 0.05, length + 0.05, 0.055, "WOOD")
        for sy in (1, -1):
            bld.prism_y(-wdt / 2 - 0.16, wdt / 2 + 0.16, cy, zb + h + 0.30,
                        sy * (length / 2 + 0.16), -0.24,
                        sy * (length / 2 + 0.16), -0.30, "KAWARA")
        bld.box(0, cy, zb + h + 0.33, wdt + 0.40, 0.17, 0.10, "KAWARA")
    else:
        bld.box(0, cy, zb + h / 2, length, wdt, h, "WOOD_LT")
        for k in range(3):
            bld.box(0, cy, zb + 0.12 + k * 0.15, length + 0.05, wdt + 0.05, 0.055, "WOOD")
        for sy in (1, -1):
            bld.prism_y(-length / 2 - 0.16, length / 2 + 0.16, cy, zb + h + 0.30,
                        sy * (wdt / 2 + 0.16), -0.24,
                        sy * (wdt / 2 + 0.16), -0.30, "KAWARA")
        bld.box(0, cy, zb + h + 0.33, length + 0.40, 0.17, 0.10, "KAWARA")


def _roof(bld, W, D, z_wall, pitch, overhang=0.85, thick=0.16, gyogyo=True):
    """切妻屋根：野地 → 軒裏 → 垂木 → 鼻隠し → 破風板 → 懸魚 →
    棟（熨斗＋冠）→ 桟瓦。

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
        # ── 桟瓦葺き ──
        # 本瓦 = 深半圓的丸瓦壓在平瓦接縫上（凸 52mm，剪影是一排粗肋）
        # 桟瓦 = 一體成型的波形瓦，只有淺桟（凸 22mm），而且**橫向的
        #        葺き足（每列的重疊段差）才是主節奏**
        # ⚠ PHASE 1.7：桟從「平面上的細肋」改成「**連續的波形面**」。
        # 肋與肋之間留平坦帶的話，屋面在遠景是「亮線／暗帶」高頻交替，
        # 30m 外整片屋頂摩爾成一張細網。半寬拉到 0.118 讓相鄰的桟幾乎
        # 接起來，屋面變成連續起伏 —— 而且這才是桟瓦對的形。
        nk = max(12, int(2 * hw / 0.302))          # 桟瓦定尺 305mm
        for k in range(nk):
            x = -hw + (k + 0.5) * (2 * hw / nk)
            bld.prism_y(x - 0.118, x + 0.118, cy, ridge_z,
                        0.0, 0.020,
                        sy * hd, (eave_z - ridge_z) + 0.020, "KAWARA")
        # 葺き足：每列瓦的下緣段差（桟瓦的主節奏）。做成貼在坡面上的細條，
        # 不切開坡面本身。列距 0.46 是**可讀性優先於考證**的取捨（實際約
        # 0.265）—— 近景仍看得出是一列一列的瓦，遠景不再是一張網。
        ncourse = max(5, int(slope_len / 0.46))
        for k in range(1, ncourse):
            t = float(k) / ncourse
            yy = cy + sy * hd * t
            zz = ridge_z + (eave_z - ridge_z) * t
            bld.prism_y(-hw, hw, yy, zz + 0.023,
                        sy * 0.055, -0.055 * math.tan(pitch) + 0.012,
                        sy * 0.055, -0.055 * math.tan(pitch) - 0.010, "KAWARA")
        # 軒瓦（簷端一列瓦當）—— 桟瓦的軒先瓦是**連續的唇**，不是一排圓盤
        bld.box(0, ye - sy * 0.050, eave_z + 0.052, 2 * hw + 0.02, 0.10, 0.075,
                "KAWARA")

    # 破風板（妻側的封簷板）+ 懸魚
    for sx in (1, -1):
        gx = sx * hw
        # 妻壁是**漆喰**不是瓦 —— 破風板壓在它外面，兩者材質不同才讀得出
        # 「板釘在牆上」。
        bld.tri((gx - sx * 0.02, cy - hd, eave_z), (gx - sx * 0.02, cy + hd, eave_z),
                (gx - sx * 0.02, cy, ridge_z), "PLASTER", flip=(sx < 0))
        # ⚠ PHASE 2 で「けらば軒裏」を一度足して**外した**。妻側の出は
        # 下から見たら裏面が見えるはずだと思い込んで、破風面と同一平面に
        # WOOD_LT の三角形をもう一枚入れた —— 結果は同一平面の z-fighting
        # で妻面が真っ黒。lineup の一枚目で即バレた。
        # 実際には破風の三角形が端をきちんと塞いでいて穴などなかった。
        # **無かった穴を塞ごうとして本物の穴を開けた** —— 塞ぐべき面が
        # あるかどうかは、まず絵で確かめてから。
        for sy in (1, -1):
            bld.prism_y(gx - sx * 0.075, gx,
                        cy, ridge_z + 0.05,
                        sy * hd, (eave_z - ridge_z),
                        sy * hd * 0.995, (eave_z - ridge_z) - 0.27, "WOOD_LT")
        if gyogyo:
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


def build_variant(name, W=None, D=None, total_h=None, pitch=None):
    """給 make_town.py 呼叫：依 spec 生一棟，回傳 (ob, report, meta)。"""
    s = spec_of(name, W, D, total_h, pitch)
    b = MB()
    ridge, door_x, z_top = machiya(b, s)
    ob = b.build(name)
    nbay = len(s["bays"])
    hmode, hproj, _hover = s["hisashi"]
    # ⚠ PHASE 2.6b：庇と軒の**面の位置**を manifest に出す。
    # Phase 2.6 で吊り物（暖簾・簾・染め布・提灯）の高さを手で決めたら、
    # 庇の桁が暖簾の上帯を貫き、染め布が庇を突き抜けた。原因は単純で、
    # 配置側が屋根面の高さを**知らなかった**こと。数字を持たせれば
    # 「庇の下端より下に吊る」が計算になる。
    meta = {
        "door_x": round(door_x, 3),
        "door_w": round(s["W"] / nbay - POST, 3),
        "beam_z": round(LINTEL_Z + 0.30 - 0.07, 3),
        "bay_w": round(s["W"] / nbay, 3), "nbay": nbay,
        "bays": list(s["bays"]), "orient": s["orient"],
        "tsushi": s["tsushi"][0], "ridge": round(ridge, 3),
        # 庇（storefront の天井）。z は壁面での上端、slope は下り勾配。
        # 前桁は先端から 0.06 内側・断面 0.11 なので、吊り物は
        # proj − 0.15 より内側に置けば桁と当たらない。
        "hisashi": {"mode": hmode, "z": round(s["plinth"] + LINTEL_Z + 0.20, 3),
                    "proj": round(hproj, 3), "slope": 17.0,
                    "thick": 0.055, "beam_back": 0.15},
        # 主屋根（上段の天井）。妻入りは軒の向きが 90° 違うので使わないこと。
        "eave": {"z_wall": round(z_top, 3), "overhang": round(s["overhang"], 3),
                 "pitch": round(s["pitch"], 3), "thick": 0.16},
    }
    return ob, validate(ob), meta


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


def _neutral_stage(ground_at=(0, 3.9), ground_size=140):
    """中性舞台：純灰背景 + 一主一補的日光 + 灰地面。**不做電影感**。"""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 220
    # ⚠ 這台的 Blender 是 build without OpenImageDenoiser —— 開 denoising 會
    # 直接 RuntimeError。改成拉高 samples 硬解噪點。
    sc.cycles.use_denoising = False
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 1100
    sc.render.film_transparent = False
    world = bpy.data.worlds.new("neutral")
    sc.world = world
    world.use_nodes = True
    bg = BC.background(world)
    bg.inputs[0].default_value = (0.55, 0.56, 0.58, 1.0)
    bg.inputs[1].default_value = 1.0
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sc.collection.objects.link(sun)
    sun.data.energy = 3.0
    sun.data.angle = math.radians(2.0)
    sun.rotation_euler = (math.radians(52), 0, math.radians(-38))
    fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
    sc.collection.objects.link(fill)
    fill.data.energy = 0.9
    fill.rotation_euler = (math.radians(62), 0, math.radians(140))
    bpy.ops.mesh.primitive_plane_add(size=ground_size,
                                     location=(ground_at[0], ground_at[1], 0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("GROUND")
    gm.use_nodes = True
    gbsdf = BC.principled(gm)
    gbsdf.inputs["Base Color"].default_value = (0.20, 0.20, 0.20, 1.0)
    gbsdf.inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(gm)
    return sc


def _camera(sc, lens=52.0):
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def render_views(ob, out_dir):
    import mathutils
    os.makedirs(out_dir, exist_ok=True)
    sc = _neutral_stage()
    cam = _camera(sc)
    for name, pos, tgt in VIEWS:
        cam.location = mathutils.Vector(pos)
        _look_at(cam, tgt)
        sc.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("rendered %s" % sc.render.filepath)


def render_lineup(objs, out_dir, gap=2.6):
    """**Kit lineup**：六棟並排的正面與 3/4。

    這張圖是 Phase 2 的核心審圖 —— 要同時回答兩個相反的問題：
      「它們像不像同一個聚落？」（軒高帶、内法線、材質、瓦の語彙）
      「它們是不是同一棟？」（間口、總高、開間數、屋根の向き、剪影）
    分開審單棟看不出這兩件事，只有並排才看得出來。"""
    import mathutils
    os.makedirs(out_dir, exist_ok=True)
    xs, total = [], 0.0
    for ob in objs:
        w = bbox(ob)[0]
        xs.append(total + w / 2)
        total += w + gap
    off = total / 2 - gap / 2
    for ob, x in zip(objs, xs):
        ob.location = (x - off, 0, 0)
    sc = _neutral_stage(ground_at=(0, 4.0), ground_size=420)
    lens = 70.0
    cam = _camera(sc, lens=lens)
    # ⚠ 距離は**並びの実測幅から逆算**する。ハードコードすると kit が増えた
    #   ときに黙って両端が切れる（6 棟のときは 145m 固定で足りていた）。
    #   70mm・センサ 36mm → 写る幅 = 2·d·tan(atan(18/70)) = 0.5143·d。
    #   余白 12% を見て d = 全長 / 0.5143 × 1.12。
    dist = total / (2 * math.tan(math.atan(18.0 / lens))) * 1.04
    top = max(bbox(ob)[2] for ob in objs)
    shots = [
        ("00_lineup_front", (0.0, -dist, top * 0.95), (0.0, 4.0, top * 0.46)),
        ("00_lineup_45", (-dist * 0.42, -dist * 0.70, dist * 0.17),
         (0.0, 4.0, top * 0.34)),
    ]
    print("  lineup：全長 %.1fm → 距離 %.0fm（最高 %.2fm）" % (total, dist, top))
    sc.render.resolution_x = 2400
    sc.render.resolution_y = 900
    for name, pos, tgt in shots:
        cam.location = mathutils.Vector(pos)
        _look_at(cam, tgt)
        sc.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("rendered %s" % sc.render.filepath)


# ══════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    clear()
    make_materials()
    objs = []
    seen_mats = set()
    print("\n── 町家 Architecture Kit（PHASE 2）──")
    for name in SPECS:
        ob, rep, meta = build_variant(name)
        bb = bbox(ob)
        assert rep["degenerate"] == 0, "%s 有退化面：%s" % (name, rep)
        # ⚠ 這個 assert 擋的是「材質身分在管線中間死掉」（全部塌成一個
        # surface）。**不是**每棟都必須用滿六種 —— 工房 machiya_w_a 是板戶
        # 張り、障子紙一張也沒有，那是立面語彙的差別不是 bug。
        # 所以逐棟只要 ≥4 種，全 kit 的聯集必須是 6 種。
        assert len(rep["material_faces"]) >= 4, "%s 語意材質塌了：%s" % (name, rep)
        seen_mats |= set(rep["material_faces"].keys())
        print("  %-14s 面 %4d  bbox %5.2f×%5.2f×%5.2f  %s %d間 厨子=%s%s%s"
              % (name, rep["faces"], bb[0], bb[1], bb[2],
                 "妻入" if meta["orient"] == "tsuma" else "平入",
                 meta["nbay"], meta["tsushi"],
                 " 卯建" if spec_of(name)["udatsu"] else "",
                 " 煙出" if spec_of(name)["smoke"] else ""))
        export(ob, name)
        objs.append(ob)
    assert seen_mats == set(ORDER), "全 kit 沒用滿六種語意材質：%s" % sorted(seen_mats)
    if RENDER_DIR:
        render_lineup(objs, RENDER_DIR)
