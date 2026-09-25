"""山頂社殿（LANDMARK_NORTH_HILL）Hero — 人間之里 V2 P5 R5 新資產（全新建模；Protected 舊 assets/shrine/拜殿.glb 未讀取、未改動）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_hilltop_shrine.py

外觀 authority：docs/reference/神社/拜殿.png（vision brief）：入母屋灰瓦＋前坡千鳥破風＋唐破風向拝（兩柱、虹梁、彫刻）、
素木風化褐柱（非朱）、正面三間（中央寬、兩側窄；中 4 扉、側各 2 扉的深色方格子戶）、上段米白小壁＋紅花紋、組物帶、
前方高床縁＋褪朱高欄（擬寶珠暗銅）、中央五級石段＋袖石、低矮石積基壇、注連繩（房 3、紙垂 2）、賽錢箱（古金角金具＋巴紋）；
無鈴、無額、無燈籠。構法沿用 R3 寺子屋（build_terakoya.py：入母屋 main_roof、千鳥破風、唐破風向拝），腳本另存、寺子屋不動。
尺寸 authority：P0 LANDMARK_NORTH_HILL（box 14 × 9 × 10，寬×高×深；沒有 P4 灰盒）＋地塊 P_LM_NORTH_HILL（20 × 16）。
  全部（含出簷、石段、向拝）在 P0 量體內：x ±7.0、z ±5.0、最高點 ≤ 9.0。
座標：Godot；原點＝P0 地標原點（地塊中心）、y 0＝地標節點高度（山頂整平面）、+z＝正面（南，HillApproach 方向）。
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402
from v2_kit import X, Y, Z, add, mul, norm  # noqa: E402
from v2_zushi import Zushi, DARK, BOARD  # noqa: E402
import v2_irimoya as I  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/hilltop_shrine'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(OUT + '/atlas.json')
AMAT = 'V2_HilltopShrine'
MATS = ['V2_Wood', 'V2_Kawara', 'V2_Stone', 'V2_WoodRed', AMAT]

# ── 主屋（身舍）
W, D = 10.8, 6.2
HW, HD = W / 2, D / 2
KIDAN, BOT = 0.30, -0.40          # 石積基壇頂、底
FLOOR = 0.85                      # 高床（縁）面
DOOR_TOP = 2.95                   # 鴨居下
NAGESHI = (2.95, 3.10)
PANEL = (3.10, 3.95)              # 小壁（花紋）
BRACKET = (3.95, 4.45)            # 組物帶
KETA = 4.65                       # 軒桁頂
# 入母屋：主坡 P、出簷 OV；上半切妻（破風面 x＝±XG）、下半寄棟
P = 0.80
SEC = math.sqrt(1 + P * P)
OV = 1.30
XE, ZE = HW + OV, HD + OV
YE = 4.30                         # 簷口（屋面）
YR = YE + P * ZE                  # 棟（屋面頂線）
Z_G = ZE * 0.45
XG = XE - (ZE - Z_G)
Y_G = YE + P * (XE - XG)
OVG = 0.55
XT = XG + OVG
S_F, S_G, S_H = ZE * SEC, Z_G * SEC, (XE - XG) * SEC
ONI_TOP = YR + 0.70
RIDGE_TOP = YR + 0.33
# 縁（前）、石段、向拝
EN_Z = HD + 0.80                  # 縁前緣
STEP_H, STEP_T, N_STEP = 0.17, 0.26, 4          # 四級石段＋縁＝五踏
ST_HW = 1.45                      # 石段半寬
ST_Z1 = EN_Z + N_STEP * STEP_T    # 最下段前緣
KIDAN_Z = (-HD - 0.35, EN_Z + 0.15)
KIDAN_X = HW + 0.35
PX = 1.85                         # 向拝柱
ZF = EN_Z + 3 * STEP_T + 0.02     # 向拝柱心（最下段旁）
KB, KYE, KH = 2.35, 3.20, 0.70    # 唐破風：半寬、兩端、中央高
KZ1 = ZF + 0.25
BEAM = (2.60, 2.90)
# 千鳥破風
CG = dict(zg=HD - 0.40, yp=7.10, p2=0.85, ov=0.35)
GOLD, BRONZE, STRAW = '#AE8B48', '#5E5B40', '#C6A56B'

Q = Zushi(W, D, eave=YR - HD * P, pitch=P, plinth=KIDAN, bot=BOT, ov_e=OV, ov_g=OVG, his_y=3.0, his_d=1.0,
          mats=MATS, amat=AMAT, atlas=AT, matlib=ML)
assert abs(Q.RIDGE - YR) < 1e-9
RG = Q.RG


class Side:
    """牆面座標：t＝從外面看向右、y、d＝往外（牆面 d＝0）。"""

    def __init__(self, nrm, tan, off, half):
        self.n, self.t, self.off, self.half = nrm, tan, off, half
        self.gax = X if abs(tan[0]) > 0.5 else Z

    def P(self, t, y, d=0.0):
        return add(add(mul(self.t, t), (0.0, y, 0.0)), mul(self.n, self.off + d))

    def rect(self, m, t0, t1, y0, y1, d, mat, col=1.0, region=None, grain=None):
        a, b, c, e = self.P(t0, y0, d), self.P(t1, y0, d), self.P(t1, y1, d), self.P(t0, y1, d)
        if region:
            m.rect_uv(a, b, c, e, mat, region, col)
        else:
            m.quad(a, b, c, e, mat, col, grain=grain or Y)

    def box(self, m, t0, t1, y0, y1, d0, d1, mat, col=1.0, grain=None, skip=()):
        p, q = self.P(t0, y0, d0), self.P(t1, y1, d1)
        m.box(tuple(min(p[i], q[i]) for i in range(3)), tuple(max(p[i], q[i]) for i in range(3)), mat, col,
              grain=grain, skip=skip)


FRONT = Side((0.0, 0.0, 1.0), (1.0, 0.0, 0.0), HD, HW)
BACK = Side((0.0, 0.0, -1.0), (-1.0, 0.0, 0.0), HD, HW)
RIGHT = Side((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), HW, HD)
LEFT = Side((-1.0, 0.0, 0.0), (0.0, 0.0, 1.0), HW, HD)
# 各面：柱（不含轉角）、區段（門／板壁）
LAYOUT = {
    'front': (FRONT, [-1.9, 1.9], [(-5.20, -2.02, 'door_side'), (-1.78, 1.78, 'door_center'), (2.02, 5.20, 'door_side')]),
    'back': (BACK, [-1.9, 1.9], [(-5.28, -2.02, 'board'), (-1.78, 1.78, 'board'), (2.02, 5.28, 'board')]),
    'right': (RIGHT, [0.0], [(-2.98, -0.12, 'board'), (0.12, 2.98, 'board')]),
    'left': (LEFT, [0.0], [(-2.98, -0.12, 'board'), (0.12, 2.98, 'board')]),
}


def split_region(m, S, t0, t1, y0, y1, d, region, col=1.0):
    """atlas 區塊貼到長條面：依實物長寬比與區塊長寬比切成 n 片，避免拉長。"""
    u0, v0, u1, v1 = region
    ra = (u1 - u0) / (v1 - v0)
    n = max(1, round((t1 - t0) / (y1 - y0) / ra))
    for k in range(n):
        a = t0 + (t1 - t0) * k / n
        b = t0 + (t1 - t0) * (k + 1) / n
        S.rect(m, a, b, y0, y1, d, AMAT, col, region)


def wall(m, lod, key):
    S, posts, zones = LAYOUT[key]
    L = S.half
    ga = S.gax
    for t in posts:
        S.box(m, t - 0.12, t + 0.12, KIDAN, KETA - 0.20, -0.12, 0.04, 'V2_Wood', DARK, grain=Y, skip=('-y',))
    # 橫材：土台、敷居（縁高）、長押、組物下台輪、軒桁、軒下小壁
    S.box(m, -L, L, FLOOR - 0.02, FLOOR + 0.05, -0.10, 0.03, 'V2_Wood', DARK, grain=ga)
    S.box(m, -L, L, NAGESHI[0], NAGESHI[1], -0.10, 0.05, 'V2_Wood', DARK, grain=ga)
    S.box(m, -L - 0.06, L + 0.06, BRACKET[0] - 0.08, BRACKET[0], -0.10, 0.06, 'V2_Wood', DARK, grain=ga)
    S.box(m, -L - 0.12, L + 0.12, BRACKET[1], KETA, -0.10, 0.10, 'V2_Wood', DARK, grain=ga)
    S.box(m, -L - 0.12, L + 0.12, KETA, 5.22, -0.10, -0.02, 'V2_Wood', DARK * 0.7, grain=ga, skip=('+y', '-y'))
    # 床下：縁束の奧、暗板（內縮）
    S.rect(m, -L, L, KIDAN, FLOOR - 0.02, -0.25, 'V2_Wood', DARK * 0.45, grain=Y)
    for (a, b, kind) in zones:
        if kind == 'board':
            S.rect(m, a, b, FLOOR + 0.05, NAGESHI[0], -0.03, 'V2_Wood', BOARD * 0.62, grain=Y)
            if lod == 0:   # 板壁の目板
                n = max(1, int((b - a) / 0.45))
                for k in range(1, n):
                    t = a + (b - a) * k / n
                    S.box(m, t - 0.02, t + 0.02, FLOOR + 0.05, NAGESHI[0], -0.03, 0.0, 'V2_Wood', DARK * 0.9,
                          grain=Y, skip=('+y', '-y'))
        else:
            split_region(m, S, a, b, FLOOR + 0.05, DOOR_TOP, -0.07, RG[kind], 1.0)
            # 戶の框（左右）
            for (p0, p1) in ((a - 0.05, a + 0.03), (b - 0.03, b + 0.05)):
                S.box(m, p0, p1, FLOOR + 0.05, DOOR_TOP, -0.09, -0.01, 'V2_Wood', DARK, grain=Y, skip=('+y', '-y'))
    # 小壁（花紋）＋組物帶：全周
    edges = [-L] + [v for t in posts for v in (t - 0.12, t + 0.12)] + [L]
    for i in range(0, len(edges), 2):
        a, b = edges[i], edges[i + 1]
        split_region(m, S, a, b, PANEL[0], PANEL[1], -0.04, RG['panel'], 1.0)
        split_region(m, S, a, b, BRACKET[0], BRACKET[1] - 0.02, -0.02, RG['bracket'], 1.0)
    if lod == 0:
        # 出組（柱頭の斗栱：肘木二段、木口古金）
        for t in list(posts) + [-L + 0.08, L - 0.08]:
            S.box(m, t - 0.30, t + 0.30, BRACKET[0] + 0.10, BRACKET[0] + 0.24, 0.0, 0.34, 'V2_Wood', DARK * 1.1, grain=ga)
            S.box(m, t - 0.12, t + 0.12, BRACKET[0] + 0.24, BRACKET[1], 0.0, 0.46, 'V2_Wood', DARK * 1.1, grain=ga)
            S.rect(m, t - 0.10, t + 0.10, BRACKET[0] + 0.27, BRACKET[1] - 0.03, 0.465, AMAT, 1.0, Q.sw(GOLD))


def corners(m):
    for sx in (-1, 1):
        for sz in (-1, 1):
            x0, x1 = sorted((sx * (HW - 0.20), sx * (HW + 0.04)))
            z0, z1 = sorted((sz * (HD - 0.20), sz * (HD + 0.04)))
            m.box((x0, KIDAN, z0), (x1, KETA - 0.20, z1), 'V2_Wood', DARK, grain=Y, skip=('-y',))


# ── 屋根（R3 寺子屋 main_roof 同構法；尺寸改本資產）
def main_roof(m, lod):
    kw = Q.KW
    for sg in (1, -1):
        o = (0.0, YR, 0.0)
        dsl = norm((0.0, -P, float(sg)))
        n = norm((0.0, 1.0, P * sg))
        ax = (float(sg), 0.0, 0.0)
        I.tile_band(m, o, ax, dsl, n, lambda s: -XT, lambda s: XT, S_F, kw, lod, s_range=(0.0, S_G), ends=False)
        I.tile_band(m, o, ax, dsl, n, lambda s: -(XE - ZE + s / SEC), lambda s: XE - ZE + s / SEC, S_F, kw, lod,
                    s_range=(S_G, S_F), ends=(lod == 0))
        I.under(m, o, ax, dsl, n, lambda s: -XT, lambda s: XT, S_G)
        o2 = add(o, mul(dsl, S_G))
        I.under(m, o2, ax, dsl, n, lambda s: -(XG + s / SEC), lambda s: XG + s / SEC, S_F - S_G)
        a, b = (-XE, YE, sg * ZE), (XE, YE, sg * ZE)
        m.beam(add(a, mul(n, -0.06)), add(b, mul(n, -0.06)), 0.08, 0.26, 'V2_Wood', DARK * 0.9, up=n)
    for sx in (1, -1):
        o = (sx * XG, Y_G, 0.0)
        dsl = norm((float(sx), -P, 0.0))
        n = norm((P * sx, 1.0, 0.0))
        ax = (0.0, 0.0, -float(sx))
        I.tile_band(m, o, ax, dsl, n, lambda s: -(Z_G + s / SEC), lambda s: Z_G + s / SEC, S_H, kw, lod,
                    ends=(lod == 0))
        I.under(m, o, ax, dsl, n, lambda s: -(Z_G + s / SEC), lambda s: Z_G + s / SEC, S_H)
        a, b = (sx * XE, YE, -ZE), (sx * XE, YE, ZE)
        m.beam(add(a, mul(n, -0.06)), add(b, mul(n, -0.06)), 0.08, 0.26, 'V2_Wood', DARK * 0.9, up=n)
        u0, v0, u1, v1 = RG['tsuma']
        Q.oface(m, [(sx * XG, Y_G, -Z_G), (sx * XG, Y_G, Z_G), (sx * XG, YR - 0.05, 0.0)], (float(sx), 0.0, 0.0),
                AMAT, [(u0, v1), (u1, v1), ((u0 + u1) / 2, v0)], 0.95)
        x0, x1 = sorted((sx * (XG - 0.02), sx * (XG + 0.14)))
        m.box((x0, Y_G - 0.04, -Z_G), (x1, Y_G + 0.10, Z_G), 'V2_Wood', DARK, grain=Z)
        for sz in (1, -1):
            a, b = (sx * XT, YR, 0.0), (sx * XT, Y_G, sz * Z_G)
            I.hip_ridge(m, a, b, lod, w=0.26, h=0.18)
            m.beam((sx * (XT + 0.04), YR - 0.10, 0.0), (sx * (XT + 0.04), Y_G - 0.10, sz * (Z_G + 0.08)), 0.08, 0.36,
                   'V2_Wood', DARK * 0.85, up=Y)
            I.hip_ridge(m, (sx * XG, Y_G, sz * Z_G), (sx * XE, YE, sz * ZE), lod, w=0.28, h=0.18)
        if lod <= 1:
            xg = sx * (XT + 0.09)
            u, v = Q.SWATCH[GOLD]
            Q.oface(m, [(xg, YR - 0.25, -0.20), (xg, YR - 0.85, 0.0), (xg, YR - 0.25, 0.20), (xg, YR - 0.02, 0.0)],
                    (float(sx), 0.0, 0.0), AMAT, [(u - 0.003, v), (u, v + 0.003), (u + 0.003, v), (u, v - 0.003)], 1.0)
    m.box((-XT - 0.05, YR - 0.12, -0.22), (XT + 0.05, YR + 0.18, 0.22), 'V2_Kawara', 0.55, grain=X)
    if lod <= 1:
        m.cyl((-XT - 0.05, YR + 0.20, 0.0), (XT + 0.05, YR + 0.20, 0.0), 0.13, 0.13, 12 if lod == 0 else 8,
              'V2_Kawara', 0.50, caps=(True, True))
    for sx in (1, -1):
        x0, x1 = sorted((sx * (XT - 0.05), sx * (XT + 0.28)))
        m.box((x0, YR - 0.15, -0.34), (x1, ONI_TOP, 0.34), 'V2_Kawara', 0.40, grain=Y)
    if lod == 0:
        # 垂木（前後、兩側）＋前面垂木木口の古金
        gu = Q.sw(GOLD)
        for sg in (1, -1):
            k = int((2 * HW - 0.4) / 0.40)
            for i in range(k + 1):
                x = -HW + 0.2 + i * (2 * HW - 0.4) / k
                za, zb = HD, ZE - 0.12
                m.beam((x, YR - P * za - 0.25, sg * za), (x, YR - P * zb - 0.25, sg * zb), 0.08, 0.09,
                       'V2_Wood', DARK * 0.8, up=Y)
                if sg == 1:
                    y = YR - P * zb - 0.25
                    Q.fz(m, x - 0.04, x + 0.04, y - 0.045, y + 0.045, zb + 0.005, AMAT, 1.0, gu)
        for sx in (1, -1):
            k = int((2 * HD - 0.4) / 0.40)
            for i in range(k + 1):
                z = -HD + 0.2 + i * (2 * HD - 0.4) / k
                xa, xb = HW, XE - 0.12
                m.beam((sx * xa, YE + P * (XE - xa) - 0.25, z), (sx * xb, YE + P * (XE - xb) - 0.25, z), 0.08, 0.09,
                       'V2_Wood', DARK * 0.8, up=Y)


def cross_gable(m, lod):
    r = Q.cross_gable(m, lod, 0.0, CG['zg'], CG['yp'], CG['p2'], CG['ov'], AMAT, 0.95, face_region=RG['tsuma'],
                      gegyo=GOLD)
    # 破風頂の飾り（暗色彫刻＋古金圓）
    zq = r['zf2'] + 0.02
    ytop = CG['yp'] + 0.18
    m.box((-0.16, ytop, zq - 0.30), (0.16, ytop + 0.42, zq + 0.04), 'V2_Kawara', 0.35, grain=Y)
    if lod <= 1:
        Q.disc(m, (0.0, ytop + 0.22, zq + 0.045), (0.0, 0.0, 1.0), 0.10, 12 if lod == 0 else 6, Q.sw(GOLD), 1.0)
    return r


# ── 縁、高欄、石段
def veranda(m, lod):
    m.box((-HW, FLOOR - 0.08, HD), (HW, FLOOR, EN_Z), 'V2_Wood', BOARD * 0.62, grain=X, skip=('-z',))
    m.box((-HW, FLOOR - 0.20, EN_Z - 0.12), (HW, FLOOR - 0.08, EN_Z), 'V2_Wood', DARK, grain=X)
    if lod <= 1:
        for x in (-5.2, -3.6, -2.1, 2.1, 3.6, 5.2):     # 縁束（石段範圍外）
            m.box((x - 0.07, KIDAN, EN_Z - 0.20), (x + 0.07, FLOOR - 0.20, EN_Z - 0.06), 'V2_Wood', DARK * 0.8,
                  skip=('-y', '+y'))
    if lod == 0:
        for k in range(1, 12):
            x = -HW + W * k / 12
            m.box((x - 0.01, FLOOR, HD), (x + 0.01, FLOOR + 0.005, EN_Z - 0.02), 'V2_Wood', DARK * 0.8, grain=Z,
                  skip=('-y',))


def railing(m, lod):
    """褪朱高欄：前縁（石段口兩側）＋兩端短邊；親柱上擬寶珠（暗銅）。"""
    red = 'V2_WoodRed'
    zr = EN_Z - 0.08
    y_top, y_mid, y_bot = FLOOR + 0.75, FLOOR + 0.42, FLOOR + 0.06
    bz = Q.sw(BRONZE)
    runs = [((-HW, zr), (-ST_HW - 0.10, zr)), ((ST_HW + 0.10, zr), (HW, zr)),
            ((-HW, HD + 0.05), (-HW, zr)), ((HW, HD + 0.05), (HW, zr))]
    for (a, b) in runs:
        for (y, h, w_) in ((y_top, 0.07, 0.08), (y_mid, 0.05, 0.05), (y_bot, 0.06, 0.07)):
            if lod >= 1 and y == y_mid:
                continue
            m.beam((a[0], y, a[1]), (b[0], y, b[1]), w_, h, red, 0.95, up=Y)
    posts = [(-HW, zr), (-ST_HW - 0.10, zr), (ST_HW + 0.10, zr), (HW, zr), (-HW, HD + 0.05), (HW, HD + 0.05)]
    if lod == 0:
        posts += [(-3.6, zr), (3.6, zr)]
    for (x, z) in posts:
        m.box((x - 0.06, FLOOR, z - 0.06), (x + 0.06, y_top + 0.10, z + 0.06), red, 0.9, grain=Y, skip=('-y',))
        if lod <= 1 and (x, z) in ((-ST_HW - 0.10, zr), (ST_HW + 0.10, zr), (-HW, zr), (HW, zr)):
            m.cyl((x, y_top + 0.10, z), (x, y_top + 0.24, z), 0.075, 0.02, 8, AMAT, 1.0, caps=(True, False),
                  uv_atlas=bz)


def steps(m, lod):
    for k in range(1, N_STEP + 1):
        y0 = BOT + 0.20 if k == 1 else STEP_H * (k - 1)
        z1 = EN_Z + (N_STEP + 1 - k) * STEP_T
        m.box((-ST_HW, y0, KIDAN_Z[1] - 0.20), (ST_HW, STEP_H * k, z1), 'V2_Stone', 0.86 + 0.03 * (k % 2),
              skip=('-y', '-z'))
    # 袖石（斜）＋朱の手摺
    red = 'V2_WoodRed'
    for sx in (-1, 1):
        x = sx * (ST_HW + 0.10)
        m.beam((x, -0.02, ST_Z1 - 0.08), (x, FLOOR - 0.02, EN_Z - 0.05), 0.20, 0.30, 'V2_Stone', 0.78, up=Y)
        if lod <= 1:
            m.box((x - 0.06, 0.10, ST_Z1 - 0.12), (x + 0.06, 1.02, ST_Z1), red, 0.9, grain=Y, skip=('-y',))
            m.beam((x, 0.98, ST_Z1 - 0.06), (x, FLOOR + 0.75, EN_Z - 0.08), 0.06, 0.07, red, 0.95, up=Y)
            m.cyl((x, 1.02, ST_Z1 - 0.06), (x, 1.16, ST_Z1 - 0.06), 0.07, 0.02, 8, AMAT, 1.0, caps=(True, False),
                  uv_atlas=Q.sw(BRONZE))


def kidan(m, lod):
    x0, x1 = -KIDAN_X, KIDAN_X
    z0, z1 = KIDAN_Z
    m.box((x0, BOT, z0), (x1, KIDAN, z1), 'V2_Stone', 0.84, skip=('-y',))
    if lod == 0:
        # 野面の石積：二段、長さ不揃い（外へ 0.02 出す）
        rnd = random.Random(505)
        for (a, b, fixed, axis, sgn) in ((x0, x1, z1, 'x', 1), (x0, x1, z0, 'x', -1), (z0, z1, x1, 'z', 1),
                                         (z0, z1, x0, 'z', -1)):
            for (y0, y1) in ((-0.08, 0.10), (0.10, KIDAN - 0.02)):
                t = a
                while t < b - 0.05:
                    L = rnd.uniform(0.55, 1.10)
                    e = min(b, t + L)
                    if b - e < 0.30:
                        e = b
                    col = rnd.uniform(0.72, 0.94)
                    if axis == 'x':
                        lo = (t + 0.02, y0 + 0.01, fixed if sgn > 0 else fixed - 0.02)
                        hi = (e - 0.02, y1 - 0.01, fixed + 0.02 if sgn > 0 else fixed)
                        m.box(lo, hi, 'V2_Stone', col, skip=('-y', '-z' if sgn > 0 else '+z'))
                    else:
                        lo = (fixed if sgn > 0 else fixed - 0.02, y0 + 0.01, t + 0.02)
                        hi = (fixed + 0.02 if sgn > 0 else fixed, y1 - 0.01, e - 0.02)
                        m.box(lo, hi, 'V2_Stone', col, skip=('-y', '-x' if sgn > 0 else '+x'))
                    t = e


# ── 向拝（唐破風）
def porch(m, lod):
    yr = I.karahafu(m, lod, 0.0, KB, KYE, KH, HD, KZ1, RG['karahafu_board'], AMAT, carve=RG['carve'],
                    beam_y=BEAM[1], post_x=PX)
    seg = 12 if lod == 0 else (8 if lod == 1 else 6)
    for sx in (-1, 1):
        x = sx * PX
        m.box((x - 0.23, -0.15, ZF - 0.23), (x + 0.23, 0.20, ZF + 0.23), 'V2_Stone', 0.80, skip=('-y',))
        m.cyl((x, 0.20, ZF), (x, yr(x) - 0.14, ZF), 0.13, 0.13, seg, 'V2_Wood', DARK * 1.2, caps=(False, False))
        if lod <= 1:
            m.beam((x, 2.78, ZF - 0.10), (x, 3.08, HD), 0.14, 0.22, 'V2_Wood', DARK)      # 海老虹梁
            if lod == 0:
                for yy in (0.40, 2.52):   # 柱の金具
                    m.cyl((x, yy, ZF), (x, yy + 0.08, ZF), 0.145, 0.145, 12, AMAT, 1.0, caps=(False, False),
                          uv_atlas=Q.sw(GOLD))
    # 虹梁（木鼻つき）
    m.box((-PX - 0.30, BEAM[0], ZF - 0.12), (PX + 0.30, BEAM[1], ZF + 0.16), 'V2_Wood', DARK, grain=X)
    return yr


def shimenawa(m, lod):
    """注連繩：兩柱間下垂（中央粗）；房 3、紙垂 2。"""
    if lod >= 2:
        return
    ru = RG['rope']
    n_len = 18 if lod == 0 else 8
    n_rd = 10 if lod == 0 else 6
    z = ZF + 0.08
    xa = PX - 0.12

    def ctr(t):
        x = -xa + 2 * xa * t
        f = 1 - (x / xa) ** 2
        return (x, 2.52 - 0.30 * f, z), 0.08 + 0.07 * f
    rings = []
    for i in range(n_len + 1):
        c, r = ctr(i / n_len)
        rings.append(m.verts([(c[0], c[1] + r * math.cos(2 * math.pi * j / n_rd), c[2] + r * math.sin(2 * math.pi * j / n_rd))
                              for j in range(n_rd)]))
    u0, v0, u1, v1 = ru
    for i in range(n_len):
        for j in range(n_rd):
            j2 = (j + 1) % n_rd
            ua, ub = u0 + (u1 - u0) * i / n_len, u0 + (u1 - u0) * (i + 1) / n_len
            va, vb = v0 + (v1 - v0) * j / n_rd, v0 + (v1 - v0) * (j + 1) / n_rd
            # 外向繞序：沿 +x 前進、繞 x 軸逆時針（y→z）
            m.face([rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]], AMAT, [(ua, va), (ua, vb), (ub, vb), (ub, va)],
                   1.0, smooth=True)
    for s in (0, n_len):   # 端（柱に巻き付け）
        c, r = ctr(s / n_len)
        ps = [m.v[k] for k in rings[s]]
        Q.oface(m, ps, (-1.0 if s == 0 else 1.0, 0.0, 0.0), AMAT, [((u0 + u1) / 2, (v0 + v1) / 2)] * len(ps), 0.9)
    # 房（稻草，下垂）
    tu = RG['tassel']
    for (t, L) in ((0.25, 0.45), (0.5, 0.62), (0.75, 0.45)):
        c, r = ctr(t)
        top = (c[0], c[1] - r * 0.6, c[2])
        m.cyl(top, (c[0], top[1] - L, c[2]), 0.05, 0.09 if t == 0.5 else 0.07, 8 if lod == 0 else 5, AMAT, 1.0,
              caps=(False, True), uv_atlas=tu)
    # 紙垂（兩面；雷形 4 折）
    su = RG['shide']
    for t in (0.375, 0.625):
        c, r = ctr(t)
        y = c[1] - r * 0.7
        zz = c[2] + 0.01
        pts = [(c[0] - 0.05, y), (c[0] + 0.07, y - 0.12), (c[0] - 0.05, y - 0.24), (c[0] + 0.07, y - 0.36),
               (c[0] - 0.02, y - 0.50)]
        for k in range(len(pts) - 1):
            (xa0, ya0), (xb0, yb0) = pts[k], pts[k + 1]
            q = [(xa0 - 0.05, ya0, zz), (xa0 + 0.05, ya0, zz), (xb0 + 0.05, yb0, zz), (xb0 - 0.05, yb0, zz)]
            uv = [(su[0], su[1]), (su[2], su[1]), (su[2], su[3]), (su[0], su[3])]
            Q.oface(m, q, (0.0, 0.0, 1.0), AMAT, uv, 1.0)
            Q.oface(m, [(p[0], p[1], p[2] - 0.004) for p in q], (0.0, 0.0, -1.0), AMAT, uv, 0.9)


def saisen(m, lod):
    """賽錢箱：縁上、中央戶前。"""
    zc = HD + 0.42
    rg = {'+z': RG['saisen'], '*': Q.sw('#30251F')}
    m.abox((0.0, FLOOR + 0.29, zc), (0.62, 0.29, 0.26), AMAT, rg, 1.0, skip=('-y',))
    if lod == 0:
        for sx in (-1, 1):
            m.box((sx * 0.62 - 0.03, FLOOR, zc + 0.20), (sx * 0.62 + 0.03, FLOOR + 0.62, zc + 0.29), 'V2_Wood',
                  DARK, grain=Y, skip=('-y',))


def build(lod):
    m = K.Mesh('HilltopShrine_LOD%d' % lod, MATS, Q.TILE)
    kidan(m, lod)
    if lod <= 1:
        for key in ('front', 'back', 'right', 'left'):
            wall(m, lod, key)
        corners(m)
    else:
        m.box((-HW + 0.02, FLOOR - 0.30, -HD + 0.02), (HW - 0.02, 5.22, HD - 0.02), 'V2_Wood', BOARD * 0.55,
              skip=('-y', '+y', '+z'))
        FRONT.rect(m, -HW, HW, FLOOR, DOOR_TOP, -0.02, AMAT, 1.0, RG['door_side'])
        FRONT.rect(m, -HW, HW, DOOR_TOP, BRACKET[0], -0.02, AMAT, 1.0, RG['panel'])
        FRONT.rect(m, -HW, HW, BRACKET[0], 5.22, -0.02, 'V2_Wood', DARK)
    main_roof(m, lod)
    cross_gable(m, lod)
    veranda(m, lod)
    if lod <= 1:
        railing(m, lod)
    steps(m, lod)
    porch(m, lod)
    shimenawa(m, lod)
    if lod <= 1:
        saisen(m, lod)
    return m


def tri_count(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    out = {}
    for o in [o for o in bpy.data.objects if o not in before]:
        if o.type == 'MESH':
            out[o.name.split('.')[0]] = sum(len(p.vertices) - 2 for p in o.data.polygons)
        bpy.data.objects.remove(o, do_unlink=True)
    return out


def main():
    K.clear_scene(bpy)
    bm = K.blender_mats(bpy, MATS)
    objs, aabb = [], {}
    for lod in (0, 1, 2):
        m = build(lod)
        objs.append(m.to_blender(bpy, bmats=bm))
        xs, ys, zs = [p[0] for p in m.v], [p[1] for p in m.v], [p[2] for p in m.v]
        aabb[lod] = [[round(min(xs), 3), round(min(ys), 3), round(min(zs), 3)],
                     [round(max(xs), 3), round(max(ys), 3), round(max(zs), 3)]]
    glb = OUT + '/src/hilltop_shrine.glb'
    K.export_glb(bpy, glb, objs)
    cnt = tri_count(glb)        # 面數以匯出後 GLB 為準
    stats = {'LOD%d' % l: cnt['HilltopShrine_LOD%d' % l] for l in (0, 1, 2)}
    eave_back = round(YR - P * (ZE - 0.05) + 0.03, 3)
    spec = {
        '_note': '山頂社殿 Hero 資產規格（build_hilltop_shrine.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、'
                 'verify_village_v2_hero_gate.gd 讀取）。沒有 P4 灰盒：放在 P0 地標原點（anchor），取代 P0 佔位 Block；'
                 '尺寸以 P0 量體 14 × 9 × 10 為上限、地塊 P_LM_NORTH_HILL 為界。全新建模，Protected 舊拜殿未讀取、未改動。',
        'id': 'hilltop_shrine', 'landmark': 'LANDMARK_NORTH_HILL', 'kind': 'hero', 'budget_class': '社殿',
        'glb': 'res://assets/village_v2/hilltop_shrine/src/hilltop_shrine.glb',
        'scene': 'res://assets/village_v2/hilltop_shrine/hilltop_shrine.scn',
        'lod_objects': ['HilltopShrine_LOD0', 'HilltopShrine_LOD1', 'HilltopShrine_LOD2'],
        'lod_ranges_m': [0, 45, 130, 700],
        'budget': {'lod0': 60000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': {k: (ML[k]['tres'] if k in ML else 'res://assets/village_v2/hilltop_shrine/V2_HilltopShrine.tres')
                      for k in MATS},
        'spec': {'width_m': W, 'depth_m': D, 'floor_m': FLOOR, 'keta_m': KETA, 'eave_m': round(YE, 3),
                 'ridge_m': round(YR, 3), 'ridge_top_m': round(RIDGE_TOP, 3), 'top_m': round(ONI_TOP, 3),
                 'kidan_m': KIDAN, 'foundation_bottom_m': BOT, 'pitch': P, 'ov_eave_m': OV,
                 'design': {'roof': '入母屋（下半寄棟 XE %.2f × ZE %.2f、上半切妻 破風面 x ±%.2f、y %.2f）' % (XE, ZE, XG, Y_G),
                            'karahafu': '唐破風向拝（半寬 %.2f、簷 %.2f、中央 %.2f、柱心 z %.2f、虹梁下 %.2f）' % (
                                KB, KYE, KYE + KH, ZF, BEAM[0]),
                            'chidori': '千鳥破風（面 z %.2f、棟 %.2f）＋頂飾' % (CG['zg'], CG['yp']),
                            'front': '三間：中央 3.56 m（格子戶 4 扉）、兩側 3.26 m（各 2 扉）；縁 0.80 m＋褪朱高欄',
                            'props': '石段 5 踏（蹴上 0.17）＋袖石＋朱手摺、注連繩（房 3、紙垂 2）、賽錢箱「奉納」'}},
        'gate_spec': {
            'placement': 'anchor', 'anchor': 'Landmarks/LANDMARK_NORTH_HILL', 'replaces': 'Block',
            'p4_id': '', 'parcel': 'P_LM_NORTH_HILL', 'road': 'HillApproach',
            'size': {'x_half_max': 7.0, 'z_min': -5.0, 'z_max': 5.0,
                     'top': [round(ONI_TOP - 0.02, 3), 9.0], 'bottom': BOT},
            'building': {'w': W, 'd': D, 'zf': ZF, 'plinth': KIDAN, 'ridge': round(RIDGE_TOP, 3),
                         'eave_edge': eave_back, 'ov_eave': OV, 'probe': {'x': -3.6, 'y': 2.0, 'z': -1.0, 'gx': -PX}},
            'ground': [
                {'name': '台基', 'rect': [-KIDAN_X, KIDAN_Z[0], KIDAN_X, KIDAN_Z[1]], 'bottom': BOT, 'top': KIDAN,
                 'embed_max': 0.50},
                {'name': '踏石', 'rect': [-ST_HW, KIDAN_Z[1], ST_HW, ST_Z1], 'bottom': BOT + 0.20, 'top': STEP_H,
                 'embed_max': 0.25}] + [
                {'name': '向拝礎石%s' % s, 'rect': [sx * PX - 0.23, ZF - 0.23, sx * PX + 0.23, ZF + 0.23],
                 'bottom': -0.15, 'top': 0.20, 'embed_max': 0.25} for (sx, s) in ((-1, '左'), (1, '右'))],
            'walkway': {'rect': [-2.0, 5.5, 2.0, 6.5], 'head': 1.95, 'min_clear': 2.5, 'step': 0.25},
            'entry': [0.0, 6.2], 'inside': [0.0, 0.0],
            # 鏡位（局部 xz）：山頂整平面只有 x ±8、z −8～+6，外圍 3–4 m 就掉 1–3 m；站坡下時坡頂擋住下半棟、3P 鏡頭會
            # 鑽進坡面（front_r −28° 12 m 亮度標準差 0.026；street_far 21 m 整片坡面）→ 鏡位都放在整平面前緣與參道口
            'shots': [['front', 0.0, 8.0], ['front_l', 6.0, 7.5], ['front_r', -6.0, 7.5], ['approach', 8.0, 20.0]]},
        'collision': [
            # 主體：基壇＋身舍＋縁＋石段＋向拝柱一個 box（高床不開放，玩家停在石段前）
            {'type': 'box', 'name': 'Body', 'center': [0, (BOT + KETA) / 2, (KIDAN_Z[0] - 0.10 + ST_Z1 + 0.11) / 2],
             'size': [2 * KIDAN_X + 0.12, KETA - BOT, ST_Z1 + 0.11 - (KIDAN_Z[0] - 0.10)]}],
        'measured_blender': dict(stats, aabb=aabb[0], aabb_lod1=aabb[1], aabb_lod2=aabb[2]),
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[SHRINE]', stats, aabb[0], 'YR %.2f ONI %.2f ZF %.2f ST_Z1 %.2f' % (YR, ONI_TOP, ZF, ST_Z1))


main()
