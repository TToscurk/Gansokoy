"""人間之里 V2 P6 R1：模組化町家 Kit（共用構件）— 新資產，不重用任何舊房屋資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_machiya_kit.py

設計：
  - 187 棟 P4 町家量體幾乎各異（面寬 39 種、縱深 3 種、簷高 3 種、平入／妻入），逐棟烘焙 ≈ 600 MB 不可行
    → Kit＝一組共用構件網格（只存一次），Godot 端 tools/village_v2_machiya_kit_lib.gd 依 P4 灰盒紀錄逐棟組裝
    （節點＋transform，場景裡只多文字）。bench（p6_r1）：7480 節點 1.14 ms／合併 1.36 ms，差異可忽略。
  - 構件只允許「設計好的伸縮方向」：開間沿 x（±12 % 內，京間 1.82／0.91 兩種寬度選配）；屋面／破風／妻壁
    y、z 同比（保持 pitch 0.45，跨距分級 0.25 m → 伸縮 ≤ 6 %）；台基、LOD 外殼用 triplanar 材質（伸縮不拉貼圖）。
  - 參考圖 docs/reference/民宅/（普町1–4、商家、長屋）：平入切妻灰瓦、1F 出格子／格子戶／店先＋暖簾、
    厨子二階＝低 2F 灰泥＋蟲籠窓、總二階＝2F 格子窓；真壁（柱露明）＋腰板。
座標：Godot（x 右、y 上、+z 外側）；各構件原點見各函式；單位公尺。y 0＝P4 base（footprint 最高地面），
地板＝台基頂 0.32。
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402
from v2_kit import X, Y, Z, add, mul, norm  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/machiya_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(OUT + '/atlas.json')
# atlas 區域內縮 12 texel（2048 圖）：遠景 mipmap 會把相鄰圖塊（淺色障子／灰泥）滲進邊緣，看起來像牆與窗之間的亮縫
_IN = 12.0 / 2048.0
RG = {k: [v[0] + _IN, v[1] + _IN, v[2] - _IN, v[3] - _IN] for k, v in AT['regions'].items()}
SW = {k: tuple(v['uv']) for k, v in AT['swatches'].items()}
AM = 'V2_MachiyaKit'
MATS = ['V2_Wood', 'V2_Plaster', 'V2_Kawara', 'V2_KitStoneTri', AM]
TILE = {m: ML[m]['tile_m'] for m in ('V2_Wood', 'V2_Plaster', 'V2_Kawara')}
TILE['V2_KitStoneTri'] = 1.5
KW = ML['V2_Kawara']

P = 0.45                     # P4 pitch
FL = 0.32                    # 台基頂＝地板
HU = KW['tile_u_m'] / KW['columns'] * 2     # 屋面半單元＝2 欄桟瓦（0.53 m）；長度 1／2／4 個半單元組合
RU = HU * 4                                 # 棟／LOD 用的長度單元（2.12 m）
ROOF_N = (1, 2, 4)
BAYS = (1.82, 0.91)          # 京間一間／半間
DARK, BOARD, PL = 0.60, 0.88, 0.97
Y1 = {'h27': 2.7, 'h29': 2.9}          # 1F 上緣（厨子二階 2.7／平屋・總二階 2.9）
EAVES = {'e29': 2.9, 'e39': 3.9, 'e54': 5.4}
DEPTHS = {'d910': 9.10, 'd1001': 10.01, 'd1092': 10.92}
SPANS = [2.0 + 0.5 * i for i in range(9)]     # 屋面／破風／妻壁水平跨距分級 2.0–6.0（y、z 同比伸縮 ≤ 12 %，pitch 不變）
HIS_S = 0.45                                  # P4 庇出（hisashi_depth，63 棟全是 0.45）
POST_W = 0.12
KOSHI_OUT = 0.12             # 出格子外凸（≤ gate 碰撞容許 0.15）

MODS = {}                    # 名稱 → Mesh
INFO = {}                    # 名稱 → 附註（manifest）


def new(name, note=''):
    m = K.Mesh(name, MATS, TILE)
    MODS[name] = m
    INFO[name] = note
    return m


def sw(hexc):
    return [SW[hexc]] * 4


# ─────────────────────────── 牆面構件 ───────────────────────────

def post(m, x0, y0, y1, z0=-0.09, z1=0.03, w=POST_W):
    m.box((x0, y0, z0), (x0 + w, y1, z1), 'V2_Wood', DARK, grain=Y)


def beam_x(m, x0, x1, y0, y1, z0=-0.06, z1=0.05, col=DARK):
    m.box((x0, y0, z0), (x1, y1, z1), 'V2_Wood', col, grain=X)


def wall(m, x0, x1, y0, y1, mat='V2_Plaster', col=PL, z=0.0):
    if x1 - x0 < 1e-3 or y1 - y0 < 1e-3:
        return
    m.quad((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z), mat, col, grain=X if mat == 'V2_Wood' else Y)


def reveal(m, xa, xb, ya, yb, zin, col=None):
    """內退開口的四邊收口（抱き）：從牆面 z 0 退到 zin；朝開口內側。"""
    c = PL * 0.85 if col is None else col
    # 繞序：法線＝(v1−v0)×(v2−v0)（與 wall() 相同慣例）
    m.quad((xa, yb, zin), (xa, yb, 0.0), (xa, ya, 0.0), (xa, ya, zin), 'V2_Plaster', c)      # 左邊（朝 +x）
    m.quad((xb, yb, 0.0), (xb, yb, zin), (xb, ya, zin), (xb, ya, 0.0), 'V2_Plaster', c)      # 右邊（朝 −x）
    m.quad((xa, yb, zin), (xb, yb, zin), (xb, yb, 0.0), (xa, yb, 0.0), 'V2_Plaster', c)      # 上（朝下）
    m.quad((xa, ya, 0.0), (xb, ya, 0.0), (xb, ya, zin), (xa, ya, zin), 'V2_Plaster', c)      # 下（朝上）


def koshiita(m, x0, x1, top=1.0):
    """腰板：地板到 top 的下見板（木）＋上緣押縁。"""
    wall(m, x0, x1, FL, top, 'V2_Wood', BOARD, z=0.012)
    beam_x(m, x0, x1, top - 0.04, top + 0.02, 0.0, 0.035)


def front1(kind, wn, hk):
    """1F 正面一開間：x 0..wn（左柱在 x 0..0.12）、牆面 z 0、+z 外；y 地板 0.32 到 1F 上緣 Y1。"""
    y1 = Y1[hk]
    m = new('f1_%s_%d_%s' % (kind, round(wn * 100), hk), '1F 正面開間 %s 寬 %.2f 上緣 %.1f' % (kind, wn, y1))
    post(m, 0.0, FL, y1)
    beam_x(m, 0.0, wn, y1 - 0.2, y1)                          # 差鴨居／桁
    a, b = POST_W, wn
    if kind == 'plain':
        koshiita(m, a, b)
        wall(m, a, b, 1.02, y1 - 0.2)
    elif kind == 'koshi':
        # 出格子：腰（木）0.32–0.62、格子 0.62–2.15（atlas koshi，外凸 KOSHI_OUT），上方灰泥
        xa, xb, zo = a + 0.05, b - 0.05, KOSHI_OUT
        m.box((xa, FL, 0.0), (xb, 0.62, zo), 'V2_Wood', DARK, grain=X, skip=('-z',))
        m.rect_uv((xa, 0.62, zo), (xb, 0.62, zo), (xb, 2.15, zo), (xa, 2.15, zo), AM, RG['koshi'])
        for x0 in (xa, xb - 0.06):                                        # 格子框（縱）
            m.box((x0, 0.62, 0.0), (x0 + 0.06, 2.15, zo + 0.01), 'V2_Wood', DARK, grain=Y, skip=('-z',))
        m.box((xa, 2.15, 0.0), (xb, 2.22, zo + 0.02), 'V2_Wood', DARK, grain=X, skip=('-z',))   # 笠木
        wall(m, a, b, FL, 2.22, 'V2_Wood', DARK * 0.8, z=-0.002)          # 格子後的暗部（不透光）
        wall(m, a, b, 2.22, y1 - 0.2)
    elif kind == 'mado':
        koshiita(m, a, b)
        xa, xb = a + 0.12, b - 0.08
        m.rect_uv((xa, 1.05, -0.03), (xb, 1.05, -0.03), (xb, 2.0, -0.03), (xa, 2.0, -0.03), AM, RG['koshi_b'])
        wall(m, a, xa, 1.02, 2.0)
        wall(m, xb, b, 1.02, 2.0)
        for (u0, u1) in ((xa - 0.05, xa), (xb, xb + 0.05)):
            m.box((u0, 1.02, -0.03), (u1, 2.05, 0.02), 'V2_Wood', DARK, grain=Y)
        beam_x(m, xa - 0.05, xb + 0.05, 2.0, 2.06, -0.03, 0.03)
        beam_x(m, xa - 0.05, xb + 0.05, 1.0, 1.05, -0.03, 0.04)
        wall(m, a, b, 2.06, y1 - 0.2)
    elif kind == 'door':
        # 格子戶（內退 0.06）＋鴨居＋上方灰泥（欄間位）
        xa, xb, top = a + 0.08, b - 0.02, FL + 1.95
        m.rect_uv((xa, FL, -0.06), (xb, FL, -0.06), (xb, top, -0.06), (xa, top, -0.06), AM, RG['door'])
        m.box((xa - 0.06, FL, -0.08), (xa, top, 0.02), 'V2_Wood', DARK, grain=Y)
        m.box((xb, FL, -0.08), (xb + 0.02, top, 0.02), 'V2_Wood', DARK, grain=Y)
        beam_x(m, xa - 0.06, xb + 0.02, top, top + 0.1, -0.08, 0.03)
        m.box((xa - 0.06, FL - 0.04, -0.12), (xb + 0.02, FL, 0.06), 'V2_Wood', DARK, grain=X, skip=('-y',))  # 敷居
        wall(m, a, b, top + 0.1, y1 - 0.2)
    elif kind.startswith('shop'):
        # 店先：整間開放，內退 0.7 的店內（atlas shop_in／goods）、天井、土間；暖簾（atlas，無字）或簾
        var = kind[-1]
        top, zi = 2.25, -0.7          # 店先開口淨高 2.25−0.32＝1.93 m（≥ 1.90）
        back = RG['goods'] if var == 'c' else RG['shop_in']
        m.rect_uv((a, FL, zi), (b, FL, zi), (b, top, zi), (a, top, zi), AM, back)
        m.quad((a, FL, 0.0), (b, FL, 0.0), (b, FL, zi), (a, FL, zi), AM, uvs=sw('#2E2119'))         # 土間（朝上）
        m.quad((a, top, zi), (b, top, zi), (b, top, 0.0), (a, top, 0.0), 'V2_Wood', BOARD * 0.8, grain=Z)   # 天井（朝下）
        m.quad((a, FL, 0.0), (a, FL, zi), (a, top, zi), (a, top, 0.0), 'V2_Wood', BOARD * 0.8, grain=Y)    # 左側壁（朝 +x）
        m.quad((b, FL, zi), (b, FL, 0.0), (b, top, 0.0), (b, top, zi), 'V2_Wood', BOARD * 0.8, grain=Y)    # 右側壁（朝 −x）
        beam_x(m, 0.0, wn, top, top + 0.12, -0.06, 0.05)
        wall(m, a, b, top + 0.12, y1 - 0.2, 'V2_Wood', BOARD, z=0.0)                               # 幕板
        if var in 'cd':                                                                             # 店台（入口開間 a/b 不放，可通行）
            m.box((a + 0.1, FL, zi + 0.05), (b - 0.1, 0.72, zi + 0.45), 'V2_Wood', BOARD, grain=X)
        if var in 'ab':
            reg = RG['noren_a'] if var == 'a' else RG['noren_b']
            m.rect_uv((a + 0.04, 1.55, 0.03), (b - 0.02, 1.55, 0.03), (b - 0.02, top, 0.03), (a + 0.04, top, 0.03), AM, reg)
            m.rect_uv((b - 0.02, 1.55, 0.029), (a + 0.04, 1.55, 0.029), (a + 0.04, top, 0.029), (b - 0.02, top, 0.029), AM, reg)
        elif var == 'd':
            m.rect_uv((a + 0.04, 1.35, 0.03), (b - 0.02, 1.35, 0.03), (b - 0.02, top, 0.03), (a + 0.04, top, 0.03), AM, RG['sudare'])
            m.rect_uv((b - 0.02, 1.35, 0.029), (a + 0.04, 1.35, 0.029), (a + 0.04, top, 0.029), (b - 0.02, top, 0.029), AM, RG['sudare'])
    return m


def upper(kind, wn, y0, y1):
    """上層正面一開間（厨子二階 2.7–3.9／總二階 2.9–5.4）：左柱＋灰泥＋窗。"""
    m = new('u_%s_%d_%d' % (kind, round(wn * 100), round(y0 * 10)), '上層正面 %s 寬 %.2f %.1f–%.1f' % (kind, wn, y0, y1))
    post(m, 0.0, y0, y1)
    beam_x(m, 0.0, wn, y1 - 0.22, y1)                         # 軒桁
    a, b = POST_W, wn
    if kind == 'mushi':                                       # 蟲籠窓（atlas），灰泥塗込め
        xa, xb = a + (b - a) * 0.12, b - (b - a) * 0.12
        ya, yb = y0 + 0.25, y1 - 0.42
        wall(m, a, b, y0, ya)
        wall(m, a, b, yb, y1 - 0.22)
        wall(m, a, xa, ya, yb)
        wall(m, xb, b, ya, yb)
        m.rect_uv((xa, ya, -0.05), (xb, ya, -0.05), (xb, yb, -0.05), (xa, yb, -0.05), AM, RG['mushiko'])
        m.box((xa, ya - 0.03, -0.05), (xb, ya, 0.02), 'V2_Plaster', PL * 0.92, grain=X, skip=('-z',))
        m.box((xa, yb, -0.05), (xb, yb + 0.03, 0.02), 'V2_Plaster', PL * 0.92, grain=X, skip=('-z',))
        m.box((xa - 0.03, ya, -0.05), (xa, yb, 0.02), 'V2_Plaster', PL * 0.92, grain=Y, skip=('-z',))
        m.box((xb, ya, -0.05), (xb + 0.03, yb, 0.02), 'V2_Plaster', PL * 0.92, grain=Y, skip=('-z',))
    elif kind == 'win':                                       # 2F 格子窓＋手摺
        xa, xb = a + 0.1, b - 0.08
        ya, yb = y0 + 0.55, y1 - 0.55
        wall(m, a, b, y0, ya)
        wall(m, a, b, yb, y1 - 0.22)
        wall(m, a, xa, ya, yb)
        wall(m, xb, b, ya, yb)
        m.rect_uv((xa, ya, -0.06), (xb, ya, -0.06), (xb, yb, -0.06), (xa, yb, -0.06), AM, RG['window_2f'])
        reveal(m, xa, xb, ya, yb, -0.06)
        beam_x(m, xa, xb, ya - 0.05, ya, -0.06, 0.06)
        beam_x(m, xa, xb, yb, yb + 0.06, -0.06, 0.04)
        beam_x(m, xa, xb, ya + 0.5, ya + 0.55, 0.05, 0.1)     # 手摺
        n = max(2, int(round((xb - xa) / 0.45)))
        for i in range(n + 1):
            x = xa + (xb - xa - 0.04) * i / n
            m.box((x, ya, 0.05), (x + 0.04, ya + 0.5, 0.09), 'V2_Wood', DARK, grain=Y)
    else:
        wall(m, a, b, y0, y1 - 0.22)
        if y1 - y0 > 2.0:
            beam_x(m, a, b, y0 + 1.15, y0 + 1.25, -0.03, 0.03)   # 長押
    return m


def closing_post(ek):
    e = EAVES[ek]
    m = new('post_%s' % ek, '面右端收邊柱（x −0.12..0）到簷 %.1f' % e)
    post(m, -POST_W, FL, e)
    return m


def back(kind, wn, ek):
    e = EAVES[ek]
    m = new('bk_%s_%d_%s' % (kind, round(wn * 100), ek), '背面開間 %s 寬 %.2f 到簷 %.1f' % (kind, wn, e))
    post(m, 0.0, FL, e)
    beam_x(m, 0.0, wn, e - 0.22, e)
    a, b = POST_W, wn
    koshiita(m, a, b)
    if kind == 'win':
        xa, xb = a + 0.3, b - 0.3
        m.rect_uv((xa, 1.3, -0.03), (xb, 1.3, -0.03), (xb, 2.0, -0.03), (xa, 2.0, -0.03), AM, RG['mado'])
        reveal(m, xa, xb, 1.3, 2.0, -0.03)
        wall(m, a, xa, 1.02, 2.0)
        wall(m, xb, b, 1.02, 2.0)
        wall(m, xa, xb, 1.02, 1.3)
        beam_x(m, xa - 0.04, xb + 0.04, 2.0, 2.05, -0.03, 0.03)
        wall(m, a, b, 2.05, e - 0.22)
    else:
        wall(m, a, b, 1.02, e - 0.22)
    if e > 3.5:
        beam_x(m, a, b, 2.75, 2.85, -0.03, 0.03)
    return m


def side(dk, ek):
    """側牆（平入＝妻側、妻入＝平側）：x −d/2..d/2、z 0 外；腰板＋灰泥＋真壁柱（每 1.82）＋梁。"""
    d, e = DEPTHS[dk], EAVES[ek]
    m = new('sd_%s_%s' % (dk, ek), '側牆 長 %.2f 到簷 %.1f' % (d, e))
    x0, x1 = -d / 2, d / 2
    koshiita(m, x0, x1)
    wall(m, x0, x1, 1.02, e - 0.22)
    beam_x(m, x0, x1, e - 0.22, e)
    if e > 3.5:
        beam_x(m, x0, x1, 2.75, 2.87, -0.03, 0.03)
    n = max(1, int(round(d / 1.82)))
    for i in range(n + 1):
        x = x0 + (d - POST_W) * i / n
        post(m, x, FL, e, -0.05, 0.025)
    return m


def gable(s):
    """妻壁三角（牆面上方）：底 x −s..s 在 y 0（簷高）、頂 (0, s·p)；灰泥＋梁＋束。y、x 同比伸縮保持 pitch。"""
    m = new('gb_%d' % round(s * 100), '妻壁 半跨 %.2f' % s)
    h = s * P
    m.poly([(-s, 0.0, 0.0), (s, 0.0, 0.0), (0.0, h, 0.0)], 'V2_Plaster', PL)
    beam_x(m, -s, s, 0.0, 0.16, -0.05, 0.03)
    m.box((-0.06, 0.16, -0.04), (0.06, h - 0.12, 0.025), 'V2_Wood', DARK, grain=Y)
    yb = h * 0.45
    beam_x(m, -s * 0.52, s * 0.52, yb, yb + 0.1, -0.04, 0.02)
    return m


# ─────────────────────────── 屋根構件 ───────────────────────────

def eave_caps(m, x0, x1, s):
    """簷口瓦當：每欄波峰一個（tile_roof 內建版左右各留 0.12 → 模組接縫處會缺；這裡只留 0.01）。"""
    tu, cols, crest = KW['tile_u_m'], KW['columns'], KW['crest_u']
    dsl = norm((0.0, -P, 1.0))
    n = norm((0.0, 1.0, P))
    S = s * math.sqrt(1 + P * P)
    amp, step = 0.022, 0.028
    k = math.ceil((x0 / tu - crest) * cols)
    while True:
        x = (crest + k / cols) * tu
        if x > x1 - 0.01:
            break
        if x >= x0 + 0.01:
            c = add((x, 0.0, 0.0), add(mul(dsl, S), mul(n, amp + step * 0.55)))
            m.cyl(add(c, mul(dsl, -0.03)), add(c, mul(dsl, 0.02)), 0.068, 0.068, 8, 'V2_Kawara', 0.9, caps=(False, True))
        k += 1


def roof_unit(s, nh, name=None):
    """屋面：x 0..nh·HU、原點＝屋面板面的棟線（P4 屋根面），往 +z 下坡到水平 s；含瓦、瓦當、軒裏、茅負。"""
    L = nh * HU
    m = new(name or 'rf_%d_%d' % (round(s * 100), nh), '屋面 %.2f m × 水平 %.2f' % (L, s))
    dsl = norm((0.0, -P, 1.0))
    n = norm((0.0, 1.0, P))
    S = s * math.sqrt(1 + P * P)
    K.tile_roof(m, (0.0, 0.0, 0.0), dsl, n, 0.0, L, S, KW, 0, seg_per_col=2, ends=False)
    eave_caps(m, 0.0, L, s)
    th = 0.12
    e = (0.0, -s * P, s)
    down = mul(n, -th)
    m.quad(add((0, 0, 0), down), add((L, 0, 0), down), add((L, e[1], e[2]), down), add(e, down),
           'V2_Wood', BOARD * 0.9, grain=Z)
    m.quad(add(e, down), add((L, e[1], e[2]), down), (L, e[1] + 0.03, e[2]), (0.0, e[1] + 0.03, e[2]),
           'V2_Wood', DARK, grain=X)
    return m


def hisashi_unit(nh):
    """庇：x 0..nh·HU、原點＝牆面上的屋面線（y 0＝P4 hisashi 高），往 +z 出 0.45；含腕木、出桁、壁際雨押。"""
    L = nh * HU
    m = roof_unit(HIS_S, nh, 'his_%d' % nh)
    INFO[m.name] = '1F 庇 %.2f m（出 0.45、含腕木）' % L
    y = -0.16
    for xb in [HU * (i + 0.5) for i in range(nh)][::2]:
        m.beam((xb, y, -0.02), (xb, y - HIS_S * P * 0.2, HIS_S - 0.04), 0.07, 0.09, 'V2_Wood', DARK)
    m.box((0.0, -HIS_S * P - 0.2, HIS_S - 0.12), (L, -HIS_S * P - 0.1, HIS_S - 0.02), 'V2_Wood', DARK, grain=X)
    m.box((0.0, -0.05, -0.04), (L, 0.06, 0.02), 'V2_Kawara', 0.75, grain=X)
    return m


def ridge_unit():
    """棟：x 0..RU（節點 x 縮放到棟長）；熨斗瓦＋冠瓦，頂在屋面線上 0.29。"""
    m = new('rg_u', '棟單元 x 0..%.2f：熨斗瓦＋冠瓦' % RU)
    m.box((0.0, 0.0, -0.14), (RU, 0.15, 0.14), 'V2_Kawara', 0.72, grain=X)
    m.box((0.0, 0.15, -0.1), (RU, 0.21, 0.1), 'V2_Kawara', 0.66, grain=X)
    m.cyl((0.0, 0.23, 0.0), (RU, 0.23, 0.0), 0.06, 0.06, 8, 'V2_Kawara', 0.62, caps=(False, False))
    return m


def oni():
    m = new('oni', '鬼瓦（棟端，x 對稱；頂在屋面線上 0.30）')
    m.box((-0.06, -0.02, -0.17), (0.06, 0.18, 0.17), 'V2_Kawara', 0.58, grain=Y)
    m.cyl((-0.07, 0.18, 0.0), (0.07, 0.18, 0.0), 0.12, 0.12, 10, 'V2_Kawara', 0.58)
    return m


def verge(s):
    """螻羽（妻側屋緣）：x 0 對稱；破風板（木）＋袖瓦捲，從棟 (0,0,0) 到簷 (0,−s·p,s)。"""
    m = new('vg_%d' % round(s * 100), '螻羽 水平 %.2f' % s)
    top = (0.0, 0.0, 0.0)
    e = (0.0, -s * P, s)
    m.beam(add(top, (0, -0.14, 0)), add(e, (0, -0.14, 0)), 0.05, 0.26, 'V2_Wood', DARK)
    m.cyl(add(top, (0, 0.06, 0)), add(e, (0, 0.06, 0)), 0.075, 0.075, 8, 'V2_Kawara', 0.66, caps=(False, True))
    return m


# ─────────────────────────── 台基與 LOD 外殼 ───────────────────────────

def unit_box(name, mat, col, note, swatch=None):
    m = new(name, note)
    if swatch:
        m.abox((0.0, 0.5, 0.0), (0.5, 0.5, 0.5), AM, {'*': [SW[swatch][0], SW[swatch][1], SW[swatch][0], SW[swatch][1]]})
    else:
        m.box((-0.5, 0.0, -0.5), (0.5, 1.0, 0.5), mat, col)
    return m


def l_roof():
    """LOD 外殼屋根：單位三角柱（棟沿 x，x/z −0.5..0.5、y 0..1）；坡面 triplanar 瓦、妻面灰泥。"""
    m = new('l_roof', 'LOD1/2 屋根三角柱（單位）')
    a, b, c, d = (-0.5, 0, 0.5), (0.5, 0, 0.5), (0.5, 1, 0), (-0.5, 1, 0)
    m.quad(a, b, c, d, AM, uvs=sw('#6B6F70'))
    m.quad((0.5, 0, -0.5), (-0.5, 0, -0.5), (-0.5, 1, 0), (0.5, 1, 0), AM, uvs=sw('#6B6F70'))
    m.poly([(0.5, 0, 0.5), (0.5, 0, -0.5), (0.5, 1, 0)], AM, uvs=[SW['#E8E0CF']] * 3)
    m.poly([(-0.5, 0, -0.5), (-0.5, 0, 0.5), (-0.5, 1, 0)], AM, uvs=[SW['#E8E0CF']] * 3)
    m.quad((-0.5, 0, -0.5), (0.5, 0, -0.5), (0.5, 0, 0.5), (-0.5, 0, 0.5), AM, uvs=sw('#4A3526'))   # 軒裏（朝下）
    return m


def l_slab():
    m = new('l_slab', 'LOD1 庇板（單位：x 0..1、往 +z 下坡 1，y＝−z·p）')
    m.quad((0, 0, 0), (0, -P, 1), (1, -P, 1), (1, 0, 0), AM, uvs=sw('#4A3526'))
    m.quad((0, 0, 0), (1, 0, 0), (1, -P, 1), (0, -P, 1), AM, uvs=sw('#6B6F70'))
    return m


def l_face(name, reg, y0, y1, note):
    m = new(name, note)
    m.rect_uv((0.0, y0, 0.01), (1.82, y0, 0.01), (1.82, y1, 0.01), (0.0, y1, 0.01), AM, reg)
    return m


def build_all():
    for hk in Y1:
        for wn in BAYS:
            kinds = ['plain', 'koshi', 'mado', 'shop_a', 'shop_b', 'shop_c', 'shop_d'] + (['door'] if wn > 1.0 else [])
            for k in kinds:
                front1(k, wn, hk)
    for wn in BAYS:
        for k in ('mushi', 'plain'):
            upper(k, wn, 2.7, 3.9)
        for k in ('win', 'plain'):
            upper(k, wn, 2.9, 5.4)
        for ek in EAVES:
            back('plain', wn, ek)
            if wn > 1.0:
                back('win', wn, ek)
    for ek in EAVES:
        closing_post(ek)
        for dk in DEPTHS:
            side(dk, ek)
    for s in SPANS:
        for nh in ROOF_N:
            roof_unit(s, nh)
        verge(s)
        gable(s)
    for nh in ROOF_N:
        hisashi_unit(nh)
    ridge_unit()
    oni()
    unit_box('base', 'V2_KitStoneTri', 1.0, '台基（單位方塊 y 0..1；triplanar 石）')
    unit_box('l_box', AM, 1.0, 'LOD1/2 牆體（單位方塊，atlas 灰泥色票）', '#E8E0CF')
    l_roof()
    l_slab()
    l_face('l_f1_res_h27', RG['koshi'], FL, 2.5, 'LOD1 1F 住宅立面（koshi）')
    l_face('l_f1_res_h29', RG['koshi'], FL, 2.7, 'LOD1 1F 住宅立面（koshi）')
    l_face('l_f1_shop_h27', RG['shop_in'], FL, 2.5, 'LOD1 1F 店先立面')
    l_face('l_f1_shop_h29', RG['shop_in'], FL, 2.7, 'LOD1 1F 店先立面')
    l_face('l_u_mushi', RG['mushiko'], 2.95, 3.55, 'LOD1 蟲籠窓')
    l_face('l_u_win', RG['window_2f'], 3.45, 4.85, 'LOD1 2F 窗')


def main():
    K.clear_scene(bpy)
    build_all()
    bm = K.blender_mats(bpy, MATS)
    objs = []
    manifest = {}
    for name, m in MODS.items():
        ob = m.to_blender(bpy, bmats=bm)
        objs.append(ob)
        tri = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        manifest[name] = {'tris': tri, 'note': INFO[name]}
    K.export_glb(bpy, OUT + '/src/machiya_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_machiya_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd）讀此表逐一轉成 mesh/<名>.res。',
        'constants': {'pitch': P, 'floor': FL, 'ru': RU, 'hu': HU, 'roof_n': list(ROOF_N), 'bays': list(BAYS), 'y1': Y1, 'eaves': EAVES,
                      'depths': DEPTHS, 'spans': SPANS, 'his_s': HIS_S, 'post_w': POST_W, 'koshi_out': KOSHI_OUT},
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[KIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/machiya_kit.glb'))


main()
