"""P8 散點農舍 第二棟（noka_b）：茅葺入母屋の平屋農家 — 三階段建築驗證的首個實際案例。

  B="D:/Blender/blender-5.2.1-windows-x64/blender.exe"
  "$B" -b --factory-startup --python godot/assets/blender/village_v2/build_noka_b.py -- --stage=skeleton
  "$B" -b --factory-startup --python godot/assets/blender/village_v2/build_noka_b.py -- --stage=full

外觀 authority：D:/參考圖概念圖/參考圖文理/民宅/農家.PNG（茅葺入母屋、焦茶の軸組＋生成りの土壁、腰板、正面の障子／板戸、
  緣側＋板葺の下屋庇、礎石建ち、棟の押さえ竹と烏おどし、左に薪積み）。屋根裏の換気窓・左の下屋・菜園は本輪なし。
尺寸：本體 8.19 × 5.46 m（9 × 6 間、柱間 2.73 m）、桁上端 3.04、軒先（茅外面）3.10、棟 7.43、茅厚 0.45、勾配 50°、
  軒の出 0.90（茅外面）、緣側 0.91、下屋庇の出 1.53、床高 0.60。FarmsteadP13 A1（6.4 × 9.1、茅葺 45°）より一回り小さい民家。
流程：既存 v2_kit（K.Mesh／box／poly、K.blender_mats、K.export_glb）。既存 build_aux 等は LOD ごとに 1 網格へ合併するが、
  本件は**構件ごとに 1 物件**（柱・梁・壁・屋根を個別に驗證するため）。頂點は Blender 側で焊接（封閉網格→穿透深度が量れる）。
座標：Godot（y 上、+z＝正面）で組み、to_blender が (x, −z, y) に変換。原點＝本體中心・地面 y 0。
--stage=skeleton：礎石・柱・足固め・大引・桁・梁・叉首（軸組＋小屋組）。--stage=full：＋床・壁・建具・緣側・下屋・茅・棟・薪。
連接表 docs/arch_spatial/examples/noka_b.arch.json は同じ定数から毎回生成（兩階段とも同じ表）。
"""
import math
import os
import sys

import bpy
import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402
from v2_kit import X, Y, Z, add, sub, mul, cross, dot, norm  # noqa: E402

G = K.repo_paths(__file__)
REPO = os.path.dirname(G)
OUT = G + '/assets/village_v2/noka_b/src'
MAP = REPO + '/docs/arch_spatial/examples/noka_b.arch.json'
MATS = ['NK_Wood', 'NK_Plaster', 'NK_Thatch', 'NK_Stone', 'NK_Paper']
TILE = {m: 1.0 for m in MATS}

# ── 色（頂點色；參考圖の焦茶・生成り・茅・灰石）
C_POST = (0.20, 0.14, 0.09)
C_BEAM = (0.17, 0.12, 0.08)
C_SASU = (0.30, 0.24, 0.16)
C_BOARD = (0.27, 0.21, 0.15)
C_FLOOR = (0.40, 0.34, 0.27)
C_PLASTER = (0.80, 0.73, 0.60)
C_PAPER = (0.86, 0.84, 0.78)
C_THATCH = (0.55, 0.45, 0.28)
C_MOSS = (0.38, 0.40, 0.22)
C_STONE = (0.46, 0.45, 0.42)
C_BAMBOO = (0.47, 0.42, 0.28)
C_LOG = (0.52, 0.40, 0.26)
C_DARK = (0.06, 0.05, 0.04)

# ── 寸法（m）
HW, HD = 4.095, 2.73            # 本體半幅（柱心）
XS = [-HW, -1.365, 1.365, HW]   # 桁行の柱心
P = 0.15                        # 柱角
ST_TOP, ST_BOT, ST_W = 0.30, -0.10, 0.36
POST_TOP = 2.80                 # 桁下
KETA = (2.80, 3.04)
HARI = (3.04, 3.28)
HARI_Z = HD + 0.15              # 梁の出（茅の内面と 14 mm 空く）
KETA_X = HW + 0.15
ASHI = (0.42, 0.56)
OBIKI_Z = 1.365
FLOOR = (0.56, 0.60)
KOSHI = 1.06                    # 腰板上端
WALL_T = 0.08
T50 = math.tan(math.radians(50.0))
C50, S50 = math.cos(math.radians(50.0)), math.sin(math.radians(50.0))
OV = 0.90                       # 軒の出（茅外面、柱心から）
EX, EZ = HW + OV, HD + OV
Y_E = 3.10                      # 軒先 茅外面
TH = 0.45                       # 茅厚
Y_R = Y_E + EZ * T50            # 棟（茅外面の頂）
Y_M = 5.75                      # 入母屋：寄棟部の上端
RUN_M = (Y_M - Y_E) / T50
XG, ZM = EX - RUN_M, EZ - RUN_M
YI0 = Y_E - TH / C50            # 茅内面：y = YI0 + (EZ − |z|)·tan
SASU_H = 0.12
SASU_W = 0.12
SASU_X = [-1.365, 1.365]
ENG_Z1 = HD + P / 2 + 0.91      # 緣側先端
HIS_Z0, HIS_Z1 = HD + P / 2, HD + 1.60
HIS_TOP0 = 2.79
HIS_TAN = 0.223
HIS_T = 0.05
HIS_POST_Z = HD + 1.40
HIS_POST_X = [-HW, -1.365, HW]


def y_in(z):
    return YI0 + (EZ - abs(z)) * T50


def his_top(z):
    return HIS_TOP0 - (z - HIS_Z0) * HIS_TAN


def his_under(z):
    return his_top(z) - HIS_T / math.cos(math.atan(HIS_TAN))


# ─────────────────────────── 幾何ヘルパ（v2_kit Mesh の上）

def newell(ps):
    n = [0.0, 0.0, 0.0]
    for i in range(len(ps)):
        a, b = ps[i], ps[(i + 1) % len(ps)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return tuple(n)


def slab(m, outer, n, t, mat, col):
    """平面多角形 outer（外面）を −n 方向へ厚み t 押し出した封閉体。"""
    n = norm(n)
    if dot(newell(outer), n) < 0:
        outer = outer[::-1]
    inner = [sub(p, mul(n, t)) for p in outer]
    m.poly(list(outer), mat, col)
    m.poly(inner[::-1], mat, col)
    k = len(outer)
    for i in range(k):
        a, b = outer[i], outer[(i + 1) % k]
        ai, bi = inner[i], inner[(i + 1) % k]
        m.quad(b, a, ai, bi, mat, col)


def prism_zy(m, prof, x0, x1, mat, col):
    """(z, y) 断面を x0..x1 に押し出し。"""
    slab(m, [(x1, y, z) for (z, y) in prof], X, x1 - x0, mat, col)


def mirror_z(prof):
    return [(-z, y) for (z, y) in prof]


# ─────────────────────────── 構件

PARTS = []        # (name, stage, type, role, builder)


def part(name, stage, typ, role):
    def deco(fn):
        PARTS.append((name, stage, typ, role, fn))
        return fn
    return deco


def post_sites():
    s = []
    for i, x in enumerate(XS):
        s.append(('F%d' % i, x, HD, POST_TOP))
        s.append(('B%d' % i, x, -HD, POST_TOP))
    s.append(('S0', -HW, 0.0, HARI[0]))     # 妻側中柱：梁まで
    s.append(('S1', HW, 0.0, HARI[0]))
    return s


for _id, _x, _z, _top in post_sites():
    def _mk_stone(m, x=_x, z=_z):
        m.box((x - ST_W / 2, ST_BOT, z - ST_W / 2), (x + ST_W / 2, ST_TOP, z + ST_W / 2), 'NK_Stone', C_STONE)

    def _mk_post(m, x=_x, z=_z, top=_top):
        m.box((x - P / 2, ST_TOP, z - P / 2), (x + P / 2, top, z + P / 2), 'NK_Wood', C_POST)
    part('Stone_' + _id, 'skeleton', 'foundation', 'structure')(_mk_stone)
    part('Post_' + _id, 'skeleton', 'post', 'structure')(_mk_post)


def ashi_segments(line):
    if line in ('F', 'B'):
        z = HD if line == 'F' else -HD
        return [((XS[i] + P / 2, ASHI[0], z - P / 2), (XS[i + 1] - P / 2, ASHI[1], z + P / 2)) for i in range(3)]
    x = -HW if line == 'S0' else HW
    zs = [-HD, 0.0, HD]
    return [((x - P / 2, ASHI[0], zs[i] + P / 2), (x + P / 2, ASHI[1], zs[i + 1] - P / 2)) for i in range(2)]


for _l in ('F', 'B', 'S0', 'S1'):
    def _mk_ashi(m, l=_l):
        for lo, hi in ashi_segments(l):
            m.box(lo, hi, 'NK_Wood', C_BEAM)
    part('Ashi_' + _l, 'skeleton', 'beam', 'structure')(_mk_ashi)

for _i, _sz in enumerate((-1, 1)):
    def _mk_obiki(m, sz=_sz):
        m.box((-HW + P / 2, ASHI[0], sz * OBIKI_Z - 0.06), (HW - P / 2, ASHI[1], sz * OBIKI_Z + 0.06), 'NK_Wood', C_BEAM)
    part('Obiki_%d' % _i, 'skeleton', 'beam', 'structure')(_mk_obiki)

for _l, _sz in (('F', 1), ('B', -1)):
    def _mk_keta(m, sz=_sz):
        m.box((-KETA_X, KETA[0], sz * HD - P / 2), (KETA_X, KETA[1], sz * HD + P / 2), 'NK_Wood', C_BEAM)
    part('Keta_' + _l, 'skeleton', 'beam', 'structure')(_mk_keta)

for _i, _x in enumerate(XS):
    def _mk_hari(m, x=_x):
        m.box((x - P / 2, HARI[0], -HARI_Z), (x + P / 2, HARI[1], HARI_Z), 'NK_Wood', C_BEAM)
    part('Hari_%d' % _i, 'skeleton', 'beam', 'structure')(_mk_hari)


def sasu_profile():
    """前側の叉首：上面＝茅内面、脚は梁上端で水平切り、頂部は z=0 で鉛直切り（前後が面で突き合う）。"""
    off = SASU_H / C50
    yt = lambda z: y_in(z)                 # noqa: E731
    yb = lambda z: y_in(z) - off           # noqa: E731
    z_bf = EZ - (HARI[1] - (YI0 - off)) / T50
    z_tf = EZ - (HARI[1] - YI0) / T50
    return [(z_bf, HARI[1]), (z_tf, HARI[1]), (0.0, yt(0.0)), (0.0, yb(0.0))]


for _xi, _x in enumerate(SASU_X):
    for _side in ('F', 'B'):
        def _mk_sasu(m, x=_x, side=_side):
            pr = sasu_profile()
            prism_zy(m, pr if side == 'F' else mirror_z(pr), x - SASU_W / 2, x + SASU_W / 2, 'NK_Wood', C_SASU)
        part('Sasu_%s%d' % (_side, _xi), 'skeleton', 'rafter', 'structure')(_mk_sasu)


# ── 第二階段：床・壁・建具

@part('Yuka', 'full', 'floor', 'structure')
def _mk_yuka(m):
    m.box((-HW + P / 2, FLOOR[0], -HD + P / 2), (HW - P / 2, FLOOR[1], HD - P / 2), 'NK_Wood', C_FLOOR)


def wall_box(m, axis, line, u0, u1, y0, y1, plaster=True):
    """axis 'z'＝正背面（u＝x、面は z=line）、'x'＝妻面（u＝z、面は x=line）。腰板は 5 mm 厚く出す（共面を避ける）。"""
    def bx(a0, a1, b0, b1, t, mat, col):
        if axis == 'z':
            m.box((a0, b0, line - t / 2), (a1, b1, line + t / 2), mat, col)
        else:
            m.box((line - t / 2, b0, a0), (line + t / 2, b1, a1), mat, col)
    bx(u0, u1, y0, KOSHI, WALL_T + 0.01, 'NK_Wood', C_BOARD)
    if plaster:
        bx(u0, u1, KOSHI, y1, WALL_T, 'NK_Plaster', C_PLASTER)


def bay(i):
    return XS[i] + P / 2, XS[i + 1] - P / 2


@part('Wall_F0', 'full', 'wall', 'enclosure')
def _mk_wf0(m):
    u0, u1 = bay(0)
    wall_box(m, 'z', HD, u0, u1, ASHI[1], POST_TOP)


for _i in range(3):
    def _mk_wb(m, i=_i):
        u0, u1 = bay(i)
        wall_box(m, 'z', -HD, u0, u1, ASHI[1], POST_TOP)
    part('Wall_B%d' % _i, 'full', 'wall', 'enclosure')(_mk_wb)

for _sx, _l in ((-1, 'S0'), (1, 'S1')):
    for _k, (_a, _b) in enumerate(((-HD + P / 2, -P / 2), (P / 2, HD - P / 2))):
        def _mk_ws(m, sx=_sx, a=_a, b=_b):
            wall_box(m, 'x', sx * HW, a, b, ASHI[1], HARI[0])
        part('Wall_%s%s' % (_l, 'ab'[_k]), 'full', 'wall', 'enclosure')(_mk_ws)


def opening(m, i, kind):
    """正面の建具の間：敷居・鴨居・小壁＋建具（障子 4 枚／板戸 2 枚、2 本の溝に交互）。"""
    u0, u1 = bay(i)
    kam = (1.90, 2.00)
    m.box((u0, ASHI[1], HD - 0.05), (u1, ASHI[1] + 0.05, HD + 0.05), 'NK_Wood', C_BEAM)          # 敷居
    m.box((u0, kam[0], HD - 0.05), (u1, kam[1], HD + 0.05), 'NK_Wood', C_BEAM)                   # 鴨居
    m.box((u0, kam[1], HD - WALL_T / 2), (u1, POST_TOP, HD + WALL_T / 2), 'NK_Plaster', C_PLASTER)  # 小壁
    n = 4 if kind == 'shoji' else 2
    w = (u1 - u0) / n
    y0, y1 = ASHI[1] + 0.05, kam[0]
    for k in range(n):
        zc = HD + (0.022 if k % 2 == 0 else -0.022)
        a, b = u0 + k * w - (0.015 if k else 0.0), u0 + (k + 1) * w + (0.015 if k < n - 1 else 0.0)
        if kind == 'shoji':
            m.box((a, y0, zc - 0.012), (b, y1, zc + 0.012), 'NK_Paper', C_PAPER)
            m.box((a, y0, zc - 0.016), (b, y0 + 0.30, zc + 0.016), 'NK_Wood', C_BOARD)          # 腰
            for yy in (0.95, 1.25, 1.55):
                m.box((a, yy - 0.012, zc + 0.012), (b, yy + 0.012, zc + 0.020), 'NK_Wood', C_BEAM)
        else:
            m.box((a, y0, zc - 0.014), (b, y1, zc + 0.014), 'NK_Wood', C_BOARD)
            for yy in (0.95, 1.45):
                m.box((a, yy - 0.03, zc + 0.014), (b, yy + 0.03, zc + 0.026), 'NK_Wood', C_BEAM)


@part('Door_F1', 'full', 'door', 'enclosure')
def _mk_d1(m):
    opening(m, 1, 'shoji')


@part('Door_F2', 'full', 'door', 'enclosure')
def _mk_d2(m):
    opening(m, 2, 'itado')


# ── 緣側

@part('Eng_Ledger', 'full', 'beam', 'structure')
def _mk_eled(m):
    m.box((-HW - P / 2, 0.32, HD + P / 2), (HW + P / 2, 0.44, HD + P / 2 + 0.09), 'NK_Wood', C_BEAM)


@part('Eng_Beam', 'full', 'beam', 'structure')
def _mk_ebeam(m):
    m.box((-HW - P / 2, 0.32, ENG_Z1 - 0.13), (HW + P / 2, 0.44, ENG_Z1 - 0.01), 'NK_Wood', C_BEAM)


@part('Eng_Deck', 'full', 'floor', 'structure')
def _mk_edeck(m):
    m.box((-HW - P / 2, 0.44, HD + P / 2), (HW + P / 2, 0.50, ENG_Z1), 'NK_Wood', C_FLOOR)


for _i, _x in enumerate(XS):
    def _mk_etsuka(m, x=_x):
        m.box((x - 0.05, 0.10, ENG_Z1 - 0.12), (x + 0.05, 0.32, ENG_Z1 - 0.02), 'NK_Wood', C_POST)

    def _mk_estone(m, x=_x):
        m.box((x - 0.13, -0.12, ENG_Z1 - 0.20), (x + 0.13, 0.10, ENG_Z1 + 0.06), 'NK_Stone', C_STONE)
    part('Eng_Tsuka%d' % _i, 'full', 'post', 'structure')(_mk_etsuka)
    part('Eng_Stone%d' % _i, 'full', 'foundation', 'structure')(_mk_estone)


@part('Kutsunugi', 'full', 'step', 'access')
def _mk_step(m):
    # 沓脱石：緣側束石 Eng_Stone2（x 1.235–1.495）と 20 mm 重なっていた → 石を動かさず（束→緣桁→床を支える）こちらを x 0.25–1.10 へ
    m.box((0.25, -0.10, ENG_Z1 + 0.04), (1.10, 0.25, ENG_Z1 + 0.54), 'NK_Stone', C_STONE)


# ── 下屋庇（板葺）

@part('His_Ledger', 'full', 'beam', 'structure')
def _mk_hled(m):
    z0, z1 = HIS_Z0, HIS_Z0 + 0.09
    prism_zy(m, [(z0, 2.62), (z1, 2.62), (z1, his_under(z1)), (z0, his_under(z0))], -HW - P / 2, HW + P / 2,
             'NK_Wood', C_BEAM)


@part('His_Keta', 'full', 'beam', 'structure')
def _mk_hketa(m):
    z0, z1 = HIS_POST_Z - 0.06, HIS_POST_Z + 0.06
    yb = his_under(z1) - 0.12
    prism_zy(m, [(z0, yb), (z1, yb), (z1, his_under(z1)), (z0, his_under(z0))], -HW - 0.30, HW + 0.30, 'NK_Wood', C_BEAM)


for _i, _x in enumerate(HIS_POST_X):
    def _mk_hpost(m, x=_x):
        yb = his_under(HIS_POST_Z + 0.06) - 0.12
        m.box((x - 0.06, 0.12, HIS_POST_Z - 0.06), (x + 0.06, yb, HIS_POST_Z + 0.06), 'NK_Wood', C_POST)

    def _mk_hstone(m, x=_x):
        m.box((x - 0.14, -0.13, HIS_POST_Z - 0.14), (x + 0.14, 0.12, HIS_POST_Z + 0.14), 'NK_Stone', C_STONE)
    part('His_Post%d' % _i, 'full', 'post', 'structure')(_mk_hpost)
    part('His_Stone%d' % _i, 'full', 'foundation', 'structure')(_mk_hstone)


@part('His_Roof', 'full', 'roof', 'roof')
def _mk_hroof(m):
    xa = HW + 0.30
    a = math.atan(HIS_TAN)
    # 板厚を法線方向に押し出すと裏面の内端が t·sin(a)＝10.9 mm 柱の中へ戻る → 上面の起点をその分前へ（勾配面は不変＝棚・下屋桁に載ったまま）
    z0 = HIS_Z0 + HIS_T * math.sin(a)
    top = [(-xa, his_top(z0), z0), (xa, his_top(z0), z0), (xa, his_top(HIS_Z1), HIS_Z1), (-xa, his_top(HIS_Z1), HIS_Z1)]
    slab(m, top, (0.0, math.cos(a), math.sin(a)), HIS_T, 'NK_Wood', C_BOARD)


# ── 茅葺 入母屋

def thatch_col(i):
    return C_MOSS if i % 3 == 1 else C_THATCH


@part('Thatch_F', 'full', 'roof', 'roof')
def _mk_tf(m):
    o = [(-EX, Y_E, EZ), (EX, Y_E, EZ), (XG, Y_M, ZM), (XG, Y_R, 0.0), (-XG, Y_R, 0.0), (-XG, Y_M, ZM)]
    slab(m, o, (0.0, C50, S50), TH, 'NK_Thatch', C_THATCH)


@part('Thatch_B', 'full', 'roof', 'roof')
def _mk_tb(m):
    o = [(EX, Y_E, -EZ), (-EX, Y_E, -EZ), (-XG, Y_M, -ZM), (-XG, Y_R, 0.0), (XG, Y_R, 0.0), (XG, Y_M, -ZM)]
    slab(m, o, (0.0, C50, -S50), TH, 'NK_Thatch', C_THATCH)


for _sx, _l in ((-1, 'L'), (1, 'R')):
    def _mk_ts(m, sx=_sx):
        o = [(sx * EX, Y_E, EZ), (sx * EX, Y_E, -EZ), (sx * XG, Y_M, -ZM), (sx * XG, Y_M, ZM)]
        slab(m, o, (sx * S50, C50, 0.0), TH, 'NK_Thatch', C_MOSS)
    part('Thatch_' + _l, 'full', 'roof', 'roof')(_mk_ts)

    def _mk_gable(m, sx=_sx):
        yb = Y_M - 0.08 * (C50 / S50)
        zb = EZ - (yb - YI0) / T50
        x0, x1 = sorted((sx * (XG - 0.08), sx * (XG - 0.11)))
        prism_zy(m, [(-zb, yb), (zb, yb), (0.0, y_in(0.0))], x0, x1, 'NK_Wood', C_DARK)
    part('Gable_' + _l, 'full', 'gable', 'enclosure')(_mk_gable)


@part('Ridge', 'full', 'ridge', 'roof')
def _mk_ridge(m):
    m.box((-XG - 0.25, Y_R - 0.22, -0.30), (XG + 0.25, Y_R + 0.15, 0.30), 'NK_Thatch', C_BAMBOO)


@part('Ridge_Cross', 'full', 'ornament', 'decor')
def _mk_rcross(m):
    for x in (-XG + 0.3, 0.0, XG - 0.3):
        for s in (-1, 1):
            m.beam((x, Y_R + 0.15, s * 0.22), (x, Y_R + 0.70, -s * 0.30), 0.07, 0.07, 'NK_Wood', C_BAMBOO)


@part('Makiba', 'full', 'prop', 'decor')
def _mk_makiba(m):
    x0, x1 = -HW - 0.80, -HW - 0.21   # 礎石 Stone_S0（x −4.275）と 30 mm 重なっていた → 薪側を 60 mm 外へ（石は Post_S0 を支える）
    z0, z1 = -1.8, 1.2
    m.box((x0, -0.04, z0), (x0 + 0.08, 0.06, z1), 'NK_Wood', C_BEAM)
    m.box((x1 - 0.08, -0.04, z0), (x1, 0.06, z1), 'NK_Wood', C_BEAM)
    r = 0.075
    for row in range(7):
        y = 0.06 + r + row * (2 * r + 0.005)
        for k in range(int((z1 - z0) / (2 * r + 0.01))):
            zc = z0 + r + k * (2 * r + 0.01) + (r if row % 2 else 0.0)
            if zc + r > z1:
                continue
            m.cyl((x0, y, zc), (x1, y, zc), r, r * 0.95, 7, 'NK_Wood', C_LOG)


# ─────────────────────────── 連接表（同じ定数から生成）

def constraints():
    C = []

    def c(t, a, b=None, **kw):
        d = {'id': kw.pop('id', '%s:%s%s' % (t, a, ('>' + b) if b else '')), 'type': t, 'a': a}
        if b:
            d['b'] = b
        d.update(kw)
        C.append(d)
    sites = post_sites()
    for sid, x, z, top in sites:
        c('SUPPORT', 'Post_' + sid, 'Stone_' + sid, embed_max=0.005)
    for i in range(4):
        for l in ('F', 'B'):
            c('SUPPORT', 'Keta_' + l, 'Post_%s%d' % (l, i), require='b')
    for i in range(4):
        for l in ('F', 'B'):
            c('CONTACT', 'Hari_%d' % i, 'Keta_' + l)
    c('SUPPORT', 'Hari_0', 'Post_S0', require='b')
    c('SUPPORT', 'Hari_3', 'Post_S1', require='b')
    adj = {'F': ['Post_F%d' % i for i in range(4)], 'B': ['Post_B%d' % i for i in range(4)],
           'S0': ['Post_B0', 'Post_S0', 'Post_F0'], 'S1': ['Post_B3', 'Post_S1', 'Post_F3']}
    for l, ps in adj.items():
        for p_ in ps:
            c('CONTACT', 'Ashi_' + l, p_)
    for i in range(2):
        c('CONTACT', 'Obiki_%d' % i, 'Ashi_S0')
        c('CONTACT', 'Obiki_%d' % i, 'Ashi_S1')
    for xi in range(2):
        for s in ('F', 'B'):
            c('SUPPORT', 'Sasu_%s%d' % (s, xi), 'Hari_%d' % (xi + 1), method='lowest', contact_band=0.02, min_contact=0.8)
        c('CONTACT', 'Sasu_F%d' % xi, 'Sasu_B%d' % xi, id='GASSHO:%d' % xi)
    c('EVEN_SPACING', None, components=['Post_F%d' % i for i in range(4)], axis='right', id='EVEN:front_posts')
    c('SYMMETRIC', 'Hari_0', 'Hari_3', id='SYM:hari_ends')
    c('PARALLEL', 'Keta_F', 'Keta_B', id='PAR:keta')
    # ── 第二階段
    c('CONTACT', 'Yuka', 'Obiki_0')
    c('CONTACT', 'Yuka', 'Obiki_1')
    walls = {'Wall_F0': ('Ashi_F', ['Post_F0', 'Post_F1'], 'Keta_F'),
             'Wall_B0': ('Ashi_B', ['Post_B0', 'Post_B1'], 'Keta_B'),
             'Wall_B1': ('Ashi_B', ['Post_B1', 'Post_B2'], 'Keta_B'),
             'Wall_B2': ('Ashi_B', ['Post_B2', 'Post_B3'], 'Keta_B'),
             'Wall_S0a': ('Ashi_S0', ['Post_B0', 'Post_S0'], 'Hari_0'),
             'Wall_S0b': ('Ashi_S0', ['Post_S0', 'Post_F0'], 'Hari_0'),
             'Wall_S1a': ('Ashi_S1', ['Post_B3', 'Post_S1'], 'Hari_3'),
             'Wall_S1b': ('Ashi_S1', ['Post_S1', 'Post_F3'], 'Hari_3'),
             'Door_F1': ('Ashi_F', ['Post_F1', 'Post_F2'], 'Keta_F'),
             'Door_F2': ('Ashi_F', ['Post_F2', 'Post_F3'], 'Keta_F')}
    for w, (base, posts, top) in walls.items():
        # 複合物件（腰板＋漆喰、敷居＋建具）は内部にも下向き面がある → 最低帶だけで測る（門檻 0.6 は同じ）
        c('SUPPORT', w, base, method='lowest', contact_band=0.02, min_contact=0.6)
        for p_ in posts:
            c('CONTACT', w, p_)
        c('CONTACT', w, top)
    c('CONTACT', 'Eng_Ledger', 'Post_F1')
    c('CONTACT', 'Eng_Ledger', 'Post_F2')
    c('SUPPORT', 'Eng_Deck', 'Eng_Ledger', require='b')
    c('SUPPORT', 'Eng_Deck', 'Eng_Beam', require='b')
    for i in range(4):
        c('SUPPORT', 'Eng_Beam', 'Eng_Tsuka%d' % i, require='b')
        c('SUPPORT', 'Eng_Tsuka%d' % i, 'Eng_Stone%d' % i, embed_max=0.005)
    c('CONTACT', 'His_Ledger', 'Post_F1')
    c('CONTACT', 'His_Ledger', 'Post_F2')
    c('SUPPORT', 'His_Roof', 'His_Ledger', require='b')
    c('SUPPORT', 'His_Roof', 'His_Keta', require='b')
    for i in range(3):
        c('SUPPORT', 'His_Keta', 'His_Post%d' % i, require='b')
        c('SUPPORT', 'His_Post%d' % i, 'His_Stone%d' % i, embed_max=0.005)
    c('CLEARANCE_REQUIRED', 'His_Roof', 'Thatch_F', min=0.05, id='CLEAR:canopy_under_thatch')
    for s in ('F', 'B'):
        for xi in range(2):
            c('CONTACT', 'Thatch_' + s, 'Sasu_%s%d' % (s, xi), tol=0.003)
        for side in ('L', 'R'):
            c('OVERLAP_ALLOWED', 'Thatch_' + s, 'Thatch_' + side, max_depth=0.50, id='HIP:%s%s' % (s, side))
    c('OVERLAP_ALLOWED', 'Thatch_F', 'Thatch_B', max_depth=0.50, id='RIDGE_LAP')
    for side, h in (('L', 'Hari_0'), ('R', 'Hari_3')):
        c('CONTACT', 'Gable_' + side, 'Thatch_' + side, tol=0.003)
        c('CONTACT', 'Gable_' + side, 'Thatch_F', tol=0.003)
        c('CLEARANCE_REQUIRED', 'Thatch_' + side, h, min=0.05, id='CLEAR:skirt_over_%s' % h)
    c('CLEARANCE_REQUIRED', 'Thatch_F', 'Hari_1', min=0.005, id='CLEAR:thatch_over_hari_end')
    for s in ('F', 'B'):
        c('OVERLAP_ALLOWED', 'Ridge', 'Thatch_' + s, max_depth=0.25, id='RIDGE_ON_%s' % s)
    c('OVERLAP_ALLOWED', 'Ridge_Cross', 'Ridge', max_depth=0.06, id='CROSS_ON_RIDGE')
    c('SYMMETRIC', 'Thatch_L', 'Thatch_R', id='SYM:skirts')
    c('SYMMETRIC', 'Thatch_F', 'Thatch_F', id='SYM:front_roof')
    c('CLEARANCE_REQUIRED', 'Makiba', 'Wall_S0b', min=0.05, id='CLEAR:woodpile')
    c('NO_INTERSECTION', 'Kutsunugi', 'Eng_Deck')
    for d in C:
        if d.get('a') is None:
            d.pop('a')
    return C


def write_map():
    spec = {
        'building_id': 'noka_b', 'style': 'japanese_house',
        '_note': 'P8 散點農舍 第二棟。build_noka_b.py が同じ定数から生成（skeleton／full 共通の表）。',
        'frame': {'origin': [0, 0, 0], 'front': '-Y'},
        'components': {n: {'object': n, 'type': t, 'role': r} for (n, _s, t, r, _f) in PARTS},
        'constraints': constraints(),
        'ground_z': 0.0, 'check_detached': True, 'ground_embed_max': 0.14,
    }
    K.write_json(MAP, spec)


# ─────────────────────────── main

PALETTE = {'post': C_POST, 'beam': C_BEAM, 'sasu': C_SASU, 'board': C_BOARD, 'floor': C_FLOOR, 'plaster': C_PLASTER,
           'paper': C_PAPER, 'thatch': C_THATCH, 'moss': C_MOSS, 'stone': C_STONE, 'bamboo': C_BAMBOO, 'log': C_LOG,
           'dark': C_DARK}


def palette_mats():
    """快速通道不做 prefab 換材質（v2_kit 的佔位材質在 Godot 只剩白色）：每個色票一個實色材質，GLB 直接帶顏色。"""
    out = {}
    for k, c in PALETTE.items():
        m = bpy.data.materials.new('NK_' + k)
        m.use_nodes = True
        b = m.node_tree.nodes.get('Principled BSDF')
        b.inputs['Base Color'].default_value = (c[0], c[1], c[2], 1.0)
        b.inputs['Roughness'].default_value = 0.88
        out[k] = m
    return out


def recolor(ob, pm):
    """面的頂點色 → 最近色票的材質（幾何不變＝arch 快取鍵不變）。"""
    me = ob.data
    col = me.color_attributes['Col']
    keys = list(pm)
    me.materials.clear()
    for k in keys:
        me.materials.append(pm[k])
    for poly in me.polygons:
        c = col.data[poly.loop_start].color
        poly.material_index = min(range(len(keys)), key=lambda i: sum((c[j] - PALETTE[keys[i]][j]) ** 2 for j in range(3)))


def weld(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    stage = 'full'
    for a in argv:
        if a.startswith('--stage='):
            stage = a.split('=', 1)[1]
    assert stage in ('skeleton', 'full'), stage
    K.clear_scene(bpy)
    bm = K.blender_mats(bpy, MATS)
    pm = palette_mats()
    objs = []
    tris = 0
    for (name, st, typ, role, fn) in PARTS:
        if stage == 'skeleton' and st != 'skeleton':
            continue
        m = K.Mesh(name, MATS, TILE)
        fn(m)
        tris += m.tris()
        ob = m.to_blender(bpy, bmats=bm)
        weld(ob)
        recolor(ob, pm)
        ob['arch_type'] = typ
        ob['arch_role'] = role
        objs.append(ob)
    os.makedirs(OUT, exist_ok=True)
    gi = OUT + '/.gdignore'
    if not os.path.exists(gi):
        open(gi, 'w').close()
    write_map()
    blend = OUT + ('/noka_b_skeleton.blend' if stage == 'skeleton' else '/noka_b.blend')
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    if stage == 'full':
        K.export_glb(bpy, OUT + '/noka_b.glb', objs)
    print('[NOKA] stage=%s objects=%d tris=%d blend=%s' % (stage, len(objs), tris, blend))
    print('[NOKA] dims: body %.2f x %.2f, eave %.2f, ridge %.2f, XG %.2f, ZM %.2f' % (2 * HW, 2 * HD, Y_E, Y_R, XG, ZM))


main()
