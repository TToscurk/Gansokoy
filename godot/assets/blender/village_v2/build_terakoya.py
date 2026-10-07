"""寺子屋（LANDMARK_TERAKOYA）Hero — 人間之里 V2 P5 R3 新資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_terakoya.py

外觀 authority：docs/reference/重點地標/寺子屋2.PNG（入母屋、主屋前坡千鳥破風、唐破風向拝、兩層立面＋裳階、
五開間一樓：中央暖簾入口、兩側格子／窗；前庭：左幟＋左告示、右告示＋右石燈籠、花壇）、
寺子屋告示牌.PNG、上白澤旗桿.PNG。文字全在 terakoya_atlas（tools/build_village_v2_r3_atlas.py）。
尺寸 authority：P0 LANDMARK_TERAKOYA（size 22 × 11 × 16，yaw 90；沒有 P4 灰盒）＋地塊 P_LM_TERAKOYA（24 × 30，
yard 4）。牆 17 × 10、含向拝總深 ≤ 12、最高點 10.15 m，全在 P0 量體內；前庭道具在地塊 yard 內。
座標：Godot；原點＝P0 地標原點（地塊中心）、y 0＝地標節點高度、+z＝正面（WestAlley；yaw 90 由 gate_spec 給）。
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402
from v2_kit import X, Y, Z, add, mul, norm, sub  # noqa: E402
from v2_zushi import Zushi, DARK, BOARD  # noqa: E402
import v2_irimoya as I  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/terakoya'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(OUT + '/atlas.json')
AMAT = 'V2_Terakoya'
MATS = ['V2_Wood', 'V2_Plaster', 'V2_Kawara', 'V2_Stone', AMAT]

# ── 主屋
W, D = 17.0, 10.0
HW, HD = W / 2, D / 2
PLINTH, BOT = 0.40, -0.40
KETA = 6.00                       # 二樓軒桁
# 入母屋：主坡 P、出簷 OV；上半切妻（破風面 x＝±XG）、下半寄棟
P = 0.62
SEC = math.sqrt(1 + P * P)
OV = 1.30
XE, ZE = HW + OV, HD + OV
YR = 9.45                         # 棟（屋面頂線）
YE = YR - P * ZE                  # 簷口（屋面）
Z_G = ZE * 0.45
XG = XE - (ZE - Z_G)
Y_G = YE + P * (XE - XG)
OVG = 0.55
XT = XG + OVG                     # 上半屋面左右緣（破風板）
S_F, S_G, S_H = ZE * SEC, Z_G * SEC, (XE - XG) * SEC
ONI_TOP = YR + 0.70
RIDGE_TOP = YR + 0.33
# 裳階（一、二樓之間的腰屋根）
YM, PM, PMK = 3.30, 1.05, 0.45
SECM = math.sqrt(1 + PMK * PMK)
YME = YM - PMK * PM
# 向拝（唐破風）
ZF = HD + 1.80                    # 向拝柱心
PX = 2.30
KB, KYE, KH = 2.95, 3.45, 1.05
KZ1 = ZF + 0.30
BEAM = (2.62, 2.95)
PAVE = 0.12
GAP = KB + 0.20
# 千鳥破風
CG = dict(zg=HD - 0.40, yp=8.55, p2=0.85, ov=0.35)
# 前庭道具
BAN = (-3.70, 7.90)
BRD_L = (-5.70, 7.70)
BRD_R = (4.60, 7.70)
TORO = (7.40, 7.40)
BED = [(-8.30, -5.30), (5.30, 8.30)]

Q = Zushi(W, D, eave=YR - HD * P, pitch=P, plinth=PLINTH, bot=BOT, ov_e=OV, ov_g=OVG, his_y=YM, his_d=PM,
          mats=MATS, amat=AMAT, atlas=AT, matlib=ML)
assert abs(Q.RIDGE - YR) < 1e-9
RG = Q.RG
GOLD = '#D9A441'


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
# 各面：柱（不含轉角）、一樓區段、二樓窗
LAYOUT = {
    'front': (FRONT, [-5.1, -1.7, 1.7, 5.1],
              [(-8.38, -5.22, 'win'), (-4.98, -1.82, 'koshi'), (-1.58, 1.58, 'door'), (1.82, 4.98, 'koshi'),
               (5.22, 8.38, 'win')],
              [(-7.9, -5.5), (-5.0, -2.6), (2.6, 5.0), (5.5, 7.9)]),
    'back': (BACK, [-2.9, 2.9],
             [(-8.38, -3.02, 'plain_win'), (-2.78, 2.78, 'plain'), (3.02, 8.38, 'plain_win')],
             [(-6.2, -3.8), (3.8, 6.2)]),
    'right': (RIGHT, [0.0], [(-4.88, -0.12, 'plain_win'), (0.12, 4.88, 'plain_win')], [(-3.8, -1.4), (1.4, 3.8)]),
    'left': (LEFT, [0.0], [(-4.88, -0.12, 'plain_win'), (0.12, 4.88, 'plain_win')], [(-3.8, -1.4), (1.4, 3.8)]),
}


def split_region(m, S, t0, t1, y0, y1, d, region, col=1.0):
    """方形 atlas 區塊貼到長條面：依長寬比切成 n 片，避免拉長。"""
    n = max(1, round((t1 - t0) / (y1 - y0)))
    for k in range(n):
        a = t0 + (t1 - t0) * k / n
        b = t0 + (t1 - t0) * (k + 1) / n
        S.rect(m, a, b, y0, y1, d, AMAT, col, region)


def bars(m, S, t0, t1, y0, y1, pitch, d0=-0.06, d1=-0.01):
    n = int((t1 - t0) / pitch)
    off = (t1 - t0 - (n - 1) * pitch) / 2
    for k in range(n):
        t = t0 + off + k * pitch
        S.box(m, t - 0.017, t + 0.017, y0, y1, d0, d1, 'V2_Wood', DARK, grain=Y, skip=('+y', '-y'))


def wall(m, lod, key):
    S, posts, zones, wins = LAYOUT[key]
    L = S.half
    ga = S.gax
    for t in posts:
        S.box(m, t - 0.12, t + 0.12, PLINTH, KETA - 0.15, -0.12, 0.04, 'V2_Wood', DARK, grain=Y, skip=('-y',))
    # 橫材：土台、長押、裳階桁、軒桁、軒下小壁
    S.box(m, -L, L, PLINTH, PLINTH + 0.12, -0.10, 0.03, 'V2_Wood', DARK, grain=ga)
    S.box(m, -L, L, 2.45, 2.62, -0.12, 0.05, 'V2_Wood', DARK, grain=ga)
    S.box(m, -L, L, YM - 0.05, YM + 0.12, -0.10, 0.06, 'V2_Wood', DARK, grain=ga)
    S.box(m, -L - 0.10, L + 0.10, KETA - 0.18, KETA + 0.05, -0.10, 0.08, 'V2_Wood', DARK, grain=ga)
    S.box(m, -L - 0.10, L + 0.10, KETA + 0.05, 6.22, -0.10, -0.02, 'V2_Wood', DARK * 0.75, grain=ga,
          skip=('+y', '-y'))
    # 一樓
    for (a, b, kind) in zones:
        y0 = PLINTH + 0.12
        if kind == 'door':
            Q.recess(m, a, b, PLINTH, 2.45, HD - 0.04, 1.80, RG['interior'], floor_col=0.36)
            # 半開的障子
            for (p0, p1) in ((a, a + 0.98), (b - 0.98, b)):
                S.rect(m, p0, p1, PLINTH + 0.02, 2.44, -0.09, AMAT, 0.95, RG['lattice_paper'])
                S.box(m, p0, p1, 2.36, 2.44, -0.10, -0.06, 'V2_Wood', DARK, grain=ga, skip=('-z',))
            continue
        if kind == 'koshi':
            S.rect(m, a, b, y0, 2.45, -0.05, AMAT, 1.0, RG['koshi'])
            if lod == 0:
                bars(m, S, a + 0.03, b - 0.03, 0.95, 2.45, 0.10, -0.045, -0.005)
            S.box(m, a, b, 0.90, 0.96, -0.06, 0.02, 'V2_Wood', DARK, grain=ga)
            continue
        S.rect(m, a, b, y0, 0.95, -0.03, 'V2_Wood', BOARD * 0.8, grain=Y)
        S.box(m, a, b, 0.95, 1.00, -0.06, 0.02, 'V2_Wood', DARK, grain=ga)
        if kind == 'win':
            split_region(m, S, a, b, 1.00, 2.20, -0.07, RG['lattice_paper'], 0.95)
            if lod == 0:
                bars(m, S, a + 0.02, b - 0.02, 1.00, 2.20, 0.09)
            S.box(m, a, b, 2.20, 2.25, -0.08, 0.01, 'V2_Wood', DARK, grain=ga)
            S.rect(m, a, b, 2.25, 2.45, -0.03, 'V2_Plaster', 0.95)
        elif kind == 'plain_win':
            c = (a + b) / 2
            w = min(1.6, b - a - 0.6)
            wa, wb = c - w / 2, c + w / 2
            S.rect(m, a, wa, 1.00, 2.45, -0.03, 'V2_Plaster', 0.95)
            S.rect(m, wb, b, 1.00, 2.45, -0.03, 'V2_Plaster', 0.95)
            S.rect(m, wa, wb, 2.10, 2.45, -0.03, 'V2_Plaster', 0.95)
            S.rect(m, wa, wb, 1.00, 1.10, -0.03, 'V2_Plaster', 0.95)
            split_region(m, S, wa, wb, 1.10, 2.10, -0.07, RG['lattice_paper'], 0.9)
            S.box(m, wa - 0.06, wb + 0.06, 2.10, 2.16, -0.08, 0.02, 'V2_Wood', DARK, grain=ga)
            S.box(m, wa - 0.06, wb + 0.06, 1.04, 1.10, -0.08, 0.03, 'V2_Wood', DARK, grain=ga)
            for (p0, p1) in ((wa - 0.06, wa), (wb, wb + 0.06)):
                S.box(m, p0, p1, 1.10, 2.10, -0.08, 0.02, 'V2_Wood', DARK, grain=Y, skip=('+y', '-y'))
            if lod == 0:
                bars(m, S, wa + 0.02, wb - 0.02, 1.10, 2.10, 0.09)
        else:
            S.rect(m, a, b, 1.00, 2.45, -0.03, 'V2_Plaster', 0.95)
    # 一、二樓之間的小壁（裳階下）
    S.rect(m, -L, L, 2.62, YM - 0.05, -0.03, 'V2_Plaster', 0.93)
    # 二樓：灰泥＋窗
    y0, y1 = YM + 0.12, KETA - 0.18
    wa, wb = 3.75, 4.65
    S.rect(m, -L, L, y0, wa, -0.03, 'V2_Plaster', 0.96)
    S.rect(m, -L, L, wb, y1, -0.03, 'V2_Plaster', 0.96)
    edges = [-L] + [v for w_ in wins for v in w_] + [L]
    for i in range(0, len(edges), 2):
        if edges[i + 1] - edges[i] > 1e-3:
            S.rect(m, edges[i], edges[i + 1], wa, wb, -0.03, 'V2_Plaster', 0.96)
    for (a, b) in wins:
        S.rect(m, a, b, wa, wb, -0.09, AMAT, 0.95, RG['window_2f'])
        S.box(m, a - 0.07, b + 0.07, wb, wb + 0.07, -0.10, 0.03, 'V2_Wood', DARK, grain=ga)
        S.box(m, a - 0.07, b + 0.07, wa - 0.07, wa, -0.10, 0.05, 'V2_Wood', DARK, grain=ga)
        for (p0, p1) in ((a - 0.07, a), (b, b + 0.07)):
            S.box(m, p0, p1, wa, wb, -0.10, 0.03, 'V2_Wood', DARK, grain=Y, skip=('+y', '-y'))


def corners(m):
    for sx in (-1, 1):
        for sz in (-1, 1):
            x0, x1 = sorted((sx * (HW - 0.20), sx * (HW + 0.04)))
            z0, z1 = sorted((sz * (HD - 0.20), sz * (HD + 0.04)))
            m.box((x0, PLINTH, z0), (x1, KETA - 0.15, z1), 'V2_Wood', DARK, grain=Y, skip=('-y',))


# ── 屋根
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
        # 茅負（簷口前緣）
        a, b = (-XE, YE, sg * ZE), (XE, YE, sg * ZE)
        m.beam(add(a, mul(n, -0.06)), add(b, mul(n, -0.06)), 0.07, 0.24, 'V2_Wood', DARK * 0.9, up=n)
    for sx in (1, -1):
        o = (sx * XG, Y_G, 0.0)
        dsl = norm((float(sx), -P, 0.0))
        n = norm((P * sx, 1.0, 0.0))
        ax = (0.0, 0.0, -float(sx))
        I.tile_band(m, o, ax, dsl, n, lambda s: -(Z_G + s / SEC), lambda s: Z_G + s / SEC, S_H, kw, lod,
                    ends=(lod == 0))
        I.under(m, o, ax, dsl, n, lambda s: -(Z_G + s / SEC), lambda s: Z_G + s / SEC, S_H)
        a, b = (sx * XE, YE, -ZE), (sx * XE, YE, ZE)
        m.beam(add(a, mul(n, -0.06)), add(b, mul(n, -0.06)), 0.07, 0.24, 'V2_Wood', DARK * 0.9, up=n)
        # 妻（破風面三角，atlas 狐格子）＋水切り
        u0, v0, u1, v1 = RG['tsuma']
        Q.oface(m, [(sx * XG, Y_G, -Z_G), (sx * XG, Y_G, Z_G), (sx * XG, YR - 0.05, 0.0)], (float(sx), 0.0, 0.0),
                AMAT, [(u0, v1), (u1, v1), ((u0 + u1) / 2, v0)], 0.95)
        x0, x1 = sorted((sx * (XG - 0.02), sx * (XG + 0.14)))
        m.box((x0, Y_G - 0.04, -Z_G), (x1, Y_G + 0.10, Z_G), 'V2_Wood', DARK, grain=Z)
        # 破風板＋降棟（沿上半屋面左右緣）
        for sz in (1, -1):
            a, b = (sx * XT, YR, 0.0), (sx * XT, Y_G, sz * Z_G)
            I.hip_ridge(m, a, b, lod, w=0.26, h=0.18)
            m.beam((sx * (XT + 0.04), YR - 0.10, 0.0), (sx * (XT + 0.04), Y_G - 0.10, sz * (Z_G + 0.08)), 0.08, 0.36,
                   'V2_Wood', DARK * 0.85, up=Y)
            # 隅棟（寄棟下半四角）
            I.hip_ridge(m, (sx * XG, Y_G, sz * Z_G), (sx * XE, YE, sz * ZE), lod, w=0.28, h=0.18)
        if lod <= 1:
            # 懸魚（金）
            xg = sx * (XT + 0.09)
            u, v = Q.SWATCH[GOLD]
            Q.oface(m, [(xg, YR - 0.25, -0.20), (xg, YR - 0.85, 0.0), (xg, YR - 0.25, 0.20), (xg, YR - 0.02, 0.0)],
                    (float(sx), 0.0, 0.0), AMAT, [(u - 0.003, v), (u, v + 0.003), (u + 0.003, v), (u, v - 0.003)], 1.0)
    # 大棟＋鬼瓦
    m.box((-XT - 0.05, YR - 0.12, -0.22), (XT + 0.05, YR + 0.18, 0.22), 'V2_Kawara', 0.6, grain=X)
    if lod <= 1:
        m.cyl((-XT - 0.05, YR + 0.20, 0.0), (XT + 0.05, YR + 0.20, 0.0), 0.13, 0.13, 12 if lod == 0 else 8,
              'V2_Kawara', 0.55, caps=(True, True))
    for sx in (1, -1):
        x0, x1 = sorted((sx * (XT - 0.05), sx * (XT + 0.28)))
        m.box((x0, YR - 0.15, -0.34), (x1, ONI_TOP, 0.34), 'V2_Kawara', 0.45, grain=Y)
    if lod == 0:
        # 垂木（前後、兩側）
        for sg in (1, -1):
            k = int((2 * HW - 0.4) / 0.45)
            for i in range(k + 1):
                x = -HW + 0.2 + i * (2 * HW - 0.4) / k
                za, zb = HD, ZE - 0.10
                m.beam((x, YR - P * za - 0.25, sg * za), (x, YR - P * zb - 0.25, sg * zb), 0.08, 0.09,
                       'V2_Wood', DARK * 0.8, up=Y)
        for sx in (1, -1):
            k = int((2 * HD - 0.4) / 0.45)
            for i in range(k + 1):
                z = -HD + 0.2 + i * (2 * HD - 0.4) / k
                xa, xb = HW, XE - 0.10
                m.beam((sx * xa, YE + P * (XE - xa) - 0.25, z), (sx * xb, YE + P * (XE - xb) - 0.25, z), 0.08, 0.09,
                       'V2_Wood', DARK * 0.8, up=Y)


def mokoshi(m, lod):
    kw = Q.KW
    for key in ('front', 'back', 'right', 'left'):
        S = LAYOUT[key][0]
        L = S.half
        o = S.P(0.0, YM, 0.0)
        dsl = norm(add(S.n, (0.0, -PMK, 0.0)))
        n = norm(add(mul(S.n, PMK), (0.0, 1.0, 0.0)))
        Sm = PM * SECM
        bands = [(lambda s: -(L + s / SECM), lambda s: L + s / SECM)]
        if key == 'front':
            bands = [(lambda s: -(L + s / SECM), lambda s: -GAP), (lambda s: GAP, lambda s: L + s / SECM)]
        for (xl, xr) in bands:
            I.tile_band(m, o, S.t, dsl, n, xl, xr, Sm, kw, lod, ends=(lod == 0))
            I.under(m, o, S.t, dsl, n, xl, xr, Sm, depth=0.10)
            e0 = add(add(o, mul(S.t, xl(Sm))), mul(dsl, Sm))
            e1 = add(add(o, mul(S.t, xr(Sm))), mul(dsl, Sm))
            m.beam(add(e0, mul(n, -0.05)), add(e1, mul(n, -0.05)), 0.05, 0.18, 'V2_Wood', DARK * 0.9, up=n)
        if key == 'front':
            for t in (-GAP, GAP):
                a = add(add(o, mul(S.t, t)), mul(n, -0.04))
                b = add(add(add(o, mul(S.t, t)), mul(dsl, Sm)), mul(n, -0.04))
                m.beam(a, b, 0.06, 0.20, 'V2_Wood', DARK * 0.85, up=n)
                # 裳階斷口封板（瓦面與野地裏之間；朝唐破風那側）
                p0 = add(o, mul(S.t, t))
                p1 = add(p0, mul(dsl, Sm))
                ps = [add(p0, mul(n, -0.12)), add(p1, mul(n, -0.12)), add(p1, mul(n, 0.07)), add(p0, mul(n, 0.07))]
                Q.oface(m, ps, mul(S.t, -1.0 if t > 0 else 1.0), 'V2_Wood', [(0, 0), (1, 0), (1, 0.2), (0, 0.2)],
                        DARK * 0.7)
    for sx in (1, -1):
        for sz in (1, -1):
            I.hip_ridge(m, (sx * HW, YM, sz * HD), (sx * (HW + PM), YME, sz * (HD + PM)), lod, w=0.20, h=0.14)


def cross_gable(m, lod):
    Q.cross_gable(m, lod, 0.0, CG['zg'], CG['yp'], CG['p2'], CG['ov'], AMAT, 0.95, face_region=RG['tsuma'],
                  gegyo=GOLD)
    # 額「寺子屋」：千鳥破風面前（金框）
    zp = CG['zg'] + 0.06
    m.abox((0.0, 7.155, zp - 0.02), (1.08, 0.455, 0.03), AMAT, {'*': Q.sw(GOLD)}, 1.0, skip=('-z',))
    Q.fz(m, -1.0, 1.0, 6.78, 7.53, zp + 0.012, AMAT, 1.0, RG['plaque'])


# ── 向拝
def porch(m, lod):
    m.box((-2.75, -0.20, HD), (2.75, PAVE, ZF + 0.35), 'V2_Stone', 0.9, skip=('-y', '-z'))
    yr = I.karahafu(m, lod, 0.0, KB, KYE, KH, HD, KZ1, RG['karahafu_board'], AMAT, carve=RG['carve'],
                    beam_y=BEAM[1], post_x=PX)
    seg = 12 if lod == 0 else 8
    for sx in (-1, 1):
        x = sx * PX
        m.box((x - 0.20, -0.05, ZF - 0.20), (x + 0.20, PAVE + 0.10, ZF + 0.20), 'V2_Stone', 0.8, skip=('-y',))
        m.cyl((x, PAVE + 0.10, ZF), (x, yr(x) - 0.14, ZF), 0.13, 0.13, seg, 'V2_Wood', DARK * 1.1, caps=(False, False))
        if lod <= 1:
            m.beam((x, 2.80, ZF - 0.10), (x, 3.10, HD), 0.14, 0.20, 'V2_Wood', DARK)
    m.box((-PX - 0.10, BEAM[0], ZF - 0.12), (PX + 0.10, BEAM[1], ZF + 0.20), 'V2_Wood', DARK, grain=X)
    # 暖簾（三片）＋竿
    zn = HD + 0.14
    if lod <= 1:
        m.cyl((-1.55, 2.41, zn), (1.55, 2.41, zn), 0.018, 0.018, 6, 'V2_Wood', DARK)
    for k in range(3):
        x0 = -1.50 + k * 1.00
        Q.fz(m, x0, x0 + 0.98, 1.55, 2.40, zn + 0.004 * k, AMAT, 1.0, Q.rsub(RG['noren'], k / 3, 0, (k + 1) / 3, 1))
        Q.fz(m, x0, x0 + 0.98, 1.55, 2.40, zn + 0.004 * k - 0.004, AMAT, 1.0, RG['noren_back'], back=True)
    # 立看板「上白沢慧音」：右柱正面
    x = PX
    m.box((x - 0.21, 1.16, ZF + 0.12), (x + 0.21, 2.32, ZF + 0.155), 'V2_Wood', BOARD * 0.9, grain=Y)
    Q.fz(m, x - 0.18, x + 0.18, 1.20, 2.28, ZF + 0.158, AMAT, 1.0, RG['board_keine'])


# ── 前庭
def banner(m, lod):
    x, z = BAN
    m.box((x - 0.24, -0.15, z - 0.24), (x + 0.24, 0.20, z + 0.24), 'V2_Stone', 0.8, skip=('-y',))
    bam = Q.sw('#A9774A')
    seg = 8 if lod <= 1 else 4
    m.cyl((x, 0.20, z), (x, 5.40, z), 0.055, 0.045, seg, AMAT, 1.0, caps=(False, True), uv_atlas=bam)
    if lod <= 1:
        for y in (1.2, 2.4, 3.6, 4.8):
            m.cyl((x, y, z), (x, y + 0.04, z), 0.062, 0.062, seg, AMAT, 1.0, caps=(True, True), uv_atlas=Q.sw('#6B4A2E'))
    # 橫竿＋幟（兩面）
    m.cyl((x, 5.05, z), (x + 0.86, 5.05, z), 0.025, 0.025, 6, AMAT, 1.0, caps=(False, True), uv_atlas=bam)
    Q.fz(m, x + 0.07, x + 0.82, 2.05, 5.03, z + 0.006, AMAT, 1.0, RG['banner'])
    Q.fz(m, x + 0.07, x + 0.82, 2.05, 5.03, z - 0.006, AMAT, 0.85, RG['banner'], back=True)   # 裏：fz(back=True) が既に左右を合わせる；rsub の二重反轉で鏡像だった（2026-10-07 修正）
    # 布邊（外緣與下緣封口，免得側看露出背面）
    nv = Q.sw('#2F3F66')
    Q.fx(m, z - 0.006, z + 0.006, 2.05, 5.03, x + 0.82, AMAT, 1.0, nv)
    Q.fx(m, z - 0.006, z + 0.006, 2.05, 5.03, x + 0.07, AMAT, 1.0, nv, neg=True)
    Q.oface(m, [(x + 0.07, 2.05, z - 0.006), (x + 0.82, 2.05, z - 0.006), (x + 0.82, 2.05, z + 0.006),
                (x + 0.07, 2.05, z + 0.006)], (0.0, -1.0, 0.0), AMAT, [(nv[0], nv[1])] * 4, 1.0)


def notice(m, lod, c, region):
    x, z = c
    for sx in (-1, 1):
        px = x + sx * 0.88
        m.box((px - 0.06, -0.30, z - 0.06), (px + 0.06, 2.40, z + 0.06), 'V2_Wood', BOARD * 0.7, grain=Y)
    m.box((x - 0.90, 1.00, z - 0.02), (x + 0.90, 2.20, z + 0.03), 'V2_Wood', BOARD * 0.85, grain=X)
    Q.fz(m, x - 0.80, x + 0.80, 1.07, 2.13, z + 0.033, AMAT, 1.0, region)
    # 小切妻屋根（板葺，厚 0.04：上面、下面、簷口、兩端都封）
    dn = (0.0, -0.04, 0.0)
    uv4 = [(0, 0), (2, 0), (2, 0.4), (0, 0.4)]
    for sg in (1, -1):
        a = (x - 1.02, 2.62, z)
        b = (x + 1.02, 2.62, z)
        c0 = (x - 1.02, 2.40, z + sg * 0.30)
        c1 = (x + 1.02, 2.40, z + sg * 0.30)
        Q.oface(m, [a, b, c1, c0], (0.0, 1.0, 0.25 * sg), 'V2_Wood', uv4, DARK)
        Q.oface(m, [add(a, dn), add(b, dn), add(c1, dn), add(c0, dn)], (0.0, -1.0, 0.0), 'V2_Wood', uv4, DARK * 0.6)
        Q.oface(m, [c0, c1, add(c1, dn), add(c0, dn)], (0.0, 0.0, float(sg)), 'V2_Wood', uv4, DARK * 0.8)
        for (e0, e1, sx) in ((a, c0, -1.0), (b, c1, 1.0)):
            Q.oface(m, [e0, e1, add(e1, dn), add(e0, dn)], (sx, 0.0, 0.0), 'V2_Wood', uv4, DARK * 0.8)
    m.box((x - 1.02, 2.58, z - 0.04), (x + 1.02, 2.68, z + 0.04), 'V2_Wood', DARK * 0.8, grain=X)
    m.box((x - 0.95, 2.20, z - 0.05), (x + 0.95, 2.40, z + 0.05), 'V2_Wood', DARK, grain=X)


def toro(m, lod):
    x, z = TORO
    m.box((x - 0.23, -0.12, z - 0.23), (x + 0.23, 0.18, z + 0.23), 'V2_Stone', 0.80, skip=('-y',))
    m.box((x - 0.09, 0.18, z - 0.09), (x + 0.09, 0.95, z + 0.09), 'V2_Stone', 0.85, skip=('-y', '+y'))
    m.box((x - 0.20, 0.95, z - 0.20), (x + 0.20, 1.01, z + 0.20), 'V2_Stone', 0.78)
    m.abox((x, 1.16, z), (0.15, 0.15, 0.15), AMAT, {'*': RG['toro_window']}, 1.0, skip=('+y', '-y'))
    m.cyl((x, 1.31, z), (x, 1.52, z), 0.30, 0.04, 4, 'V2_Stone', 0.75, caps=(True, False), phase=math.pi / 4)
    if lod == 0:
        m.cyl((x, 1.50, z), (x, 1.60, z), 0.05, 0.02, 8, 'V2_Stone', 0.75, caps=(False, True))


def beds(m, lod):
    for (a, b) in BED:
        z0, z1 = HD + 0.05, HD + 0.50
        m.box((a, -0.15, z0), (b, 0.28, z1), 'V2_Wood', BOARD * 0.6, grain=X, skip=('-y', '-z'))
        y = 0.28
        Q.oface(m, [(a + 0.05, y + 0.01, z1 - 0.05), (b - 0.05, y + 0.01, z1 - 0.05), (b - 0.05, y + 0.01, z0),
                    (a + 0.05, y + 0.01, z0)], (0.0, 1.0, 0.0), AMAT,
                [(RG['flowers'][0], RG['flowers'][3]), (RG['flowers'][2], RG['flowers'][3]),
                 (RG['flowers'][2], RG['flowers'][1]), (RG['flowers'][0], RG['flowers'][1])], 1.0)
        if lod <= 1:
            # 低矮花叢（前、上兩面）
            n = max(1, round((b - a - 0.1) / 1.0))
            for k in range(n):
                c0 = a + 0.05 + (b - a - 0.1) * k / n
                c1 = a + 0.05 + (b - a - 0.1) * (k + 1) / n
                Q.fz(m, c0, c1, 0.28, 0.55, z1 - 0.10, AMAT, 1.0, RG['flowers'])
                Q.oface(m, [(c0, 0.55, z1 - 0.10), (c1, 0.55, z1 - 0.10), (c1, 0.55, z0 + 0.05), (c0, 0.55, z0 + 0.05)],
                        (0.0, 1.0, 0.0), AMAT, [(RG['flowers'][0], RG['flowers'][3]), (RG['flowers'][2], RG['flowers'][3]),
                                                (RG['flowers'][2], RG['flowers'][1]), (RG['flowers'][0], RG['flowers'][1])],
                        0.9)


def build(lod):
    m = K.Mesh('Terakoya_LOD%d' % lod, MATS, Q.TILE)
    m.box((-HW, BOT, -HD), (HW, PLINTH, HD), 'V2_Stone', 0.85, skip=('-y',))
    if lod <= 1:
        for key in ('front', 'back', 'right', 'left'):
            wall(m, lod, key)
        corners(m)
    else:
        m.box((-HW + 0.02, PLINTH, -HD + 0.02), (HW - 0.02, 6.22, HD - 0.02), 'V2_Plaster', 0.9,
              skip=('-y', '+y', '+z'))
        FRONT.rect(m, -HW, HW, PLINTH, 2.45, -0.02, AMAT, 0.9, RG['koshi'])
        FRONT.rect(m, -HW, HW, 2.45, 3.75, -0.02, 'V2_Plaster', 0.95)
        FRONT.rect(m, -HW, HW, 3.75, 4.65, -0.02, AMAT, 0.9, RG['window_2f'])
        FRONT.rect(m, -HW, HW, 4.65, 6.22, -0.02, 'V2_Plaster', 0.95)
    main_roof(m, lod)
    mokoshi(m, lod)
    cross_gable(m, lod)
    porch(m, lod)
    banner(m, lod)
    notice(m, lod, BRD_L, RG['board_recruit'])
    notice(m, lod, BRD_R, RG['board_today'])
    toro(m, lod)
    beds(m, lod)
    return m


def main():
    K.clear_scene(bpy)
    bm = K.blender_mats(bpy, MATS)
    objs = []
    stats = {}
    for lod in (0, 1, 2):
        m = build(lod)
        objs.append(m.to_blender(bpy, bmats=bm))
        stats['LOD%d' % lod] = m.tris()
        xs = [p[0] for p in m.v]
        ys = [p[1] for p in m.v]
        zs = [p[2] for p in m.v]
        stats['aabb%d' % lod] = [[round(min(xs), 3), round(min(ys), 3), round(min(zs), 3)],
                                 [round(max(xs), 3), round(max(ys), 3), round(max(zs), 3)]]
    K.export_glb(bpy, OUT + '/src/terakoya.glb', objs)
    eave_back = round(YR - P * (ZE - 0.05) + 0.03, 3)
    spec = {
        '_note': '寺子屋 Hero 資產規格（build_terakoya.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、'
                 'verify_village_v2_hero_gate.gd 讀取）。沒有 P4 灰盒：放在 P0 地標原點（anchor），'
                 '取代 P0 線框（Wire＋Footprint）；尺寸以 P0 量體 22×11×16 為上限、地塊 P_LM_TERAKOYA 為界。',
        'id': 'terakoya', 'landmark': 'LANDMARK_TERAKOYA', 'kind': 'hero', 'budget_class': '寺子屋',
        'glb': 'res://assets/village_v2/terakoya/src/terakoya.glb',
        'scene': 'res://assets/village_v2/terakoya/terakoya.scn',
        'lod_objects': ['Terakoya_LOD0', 'Terakoya_LOD1', 'Terakoya_LOD2'],
        'lod_ranges_m': [0, 45, 120, 600],
        'budget': {'lod0': 100000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': {k: (ML[k]['tres'] if k in ML else 'res://assets/village_v2/terakoya/V2_Terakoya.tres')
                      for k in MATS},
        'spec': {'width_m': W, 'depth_m': D, 'porch_post_z_m': ZF, 'keta_m': KETA, 'eave_m': round(YE, 3),
                 'ridge_m': YR, 'ridge_top_m': RIDGE_TOP, 'top_m': ONI_TOP, 'plinth_m': PLINTH,
                 'foundation_bottom_m': BOT, 'pitch': P, 'ov_eave_m': OV,
                 'design': {'roof': '入母屋（下半寄棟 XE %.2f × ZE %.2f、上半切妻 破風面 x ±%.2f、y %.2f）' % (XE, ZE, XG, Y_G),
                            'mokoshi': '裳階 四周（壁頂 %.2f、出 %.2f、簷 %.2f；正面中央讓給唐破風）' % (YM, PM, YME),
                            'karahafu': '唐破風向拝（半寬 %.2f、簷 %.2f、中央 %.2f、柱心 z %.2f、虹梁下 %.2f）' % (
                                KB, KYE, KYE + KH, ZF, BEAM[0]),
                            'chidori': '千鳥破風（面 z %.2f、棟 %.2f）＋額「寺子屋」' % (CG['zg'], CG['yp']),
                            'props': '幟「上白沢寺子屋」、告示「生徒募集」「今日の学問」、立看板「上白沢慧音」、石燈籠、花壇×2'}},
        'gate_spec': {
            'placement': 'anchor', 'anchor': 'Landmarks/LANDMARK_TERAKOYA', 'replaces': 'Wire',
            'also_retire': ['Footprint'], 'yaw_deg': 90.0,
            'parcel': 'P_LM_TERAKOYA', 'road': 'WestAlley',
            'size': {'x_half_max': XE + 0.25, 'z_min': -(ZE + 0.25), 'z_max': 8.40,
                     'top': [round(ONI_TOP - 0.02, 3), round(ONI_TOP + 0.30, 3)], 'bottom': BOT},
            'building': {'w': W, 'd': D, 'zf': ZF, 'plinth': PLINTH, 'ridge': RIDGE_TOP, 'eave_edge': eave_back,
                         'ov_eave': OV, 'probe': {'x': -7.6, 'y': 1.5, 'z': 0.6, 'gx': -PX}},
            'door_clear': {'h': round(BEAM[0] - PAVE, 3), 'w': round(2 * (PX - 0.13), 2), 'min_h': 1.9, 'min_w': 1.2},
            'ground': [
                {'name': '台基', 'rect': [-HW, -HD, HW, HD], 'bottom': BOT, 'top': PLINTH, 'embed_max': 0.50},
                {'name': '踏石', 'rect': [-2.75, HD, 2.75, ZF + 0.35], 'bottom': -0.20, 'top': PAVE, 'embed_max': 0.25},
                {'name': '幟台', 'rect': [BAN[0] - 0.24, BAN[1] - 0.24, BAN[0] + 0.24, BAN[1] + 0.24],
                 'bottom': -0.15, 'top': 0.20, 'embed_max': 0.25},
                {'name': '告示左', 'rect': [BRD_L[0] - 0.94, BRD_L[1] - 0.06, BRD_L[0] + 0.94, BRD_L[1] + 0.06],
                 'bottom': -0.30, 'top': 0.30, 'embed_max': 0.40},
                {'name': '告示右', 'rect': [BRD_R[0] - 0.94, BRD_R[1] - 0.06, BRD_R[0] + 0.94, BRD_R[1] + 0.06],
                 'bottom': -0.30, 'top': 0.30, 'embed_max': 0.40},
                {'name': '石燈籠', 'rect': [TORO[0] - 0.23, TORO[1] - 0.23, TORO[0] + 0.23, TORO[1] + 0.23],
                 'bottom': -0.12, 'top': 0.18, 'embed_max': 0.25}] + [
                {'name': '花壇%d' % i, 'rect': [a, HD + 0.05, b, HD + 0.50], 'bottom': -0.15, 'top': 0.28,
                 'embed_max': 0.25} for i, (a, b) in enumerate(BED)],
            'walkway': {'rect': [-2.2, ZF + 0.80, 2.2, ZF + 1.60], 'head': 1.95, 'min_clear': 2.0, 'step': 0.25},
            'entry': [0.0, ZF + 1.00], 'inside': [0.0, 0.0]},
        'collision': [
            # 主屋：前緣推到 HD+0.60 蓋住花壇與門面突出物；向拝下的玩家停在門前 0.9 m
            # 寬多 0.10：轉角柱外皮在 HW＋0.04
            {'type': 'box', 'name': 'Body', 'center': [0, (BOT + KETA) / 2, 0.28], 'size': [W + 0.10, KETA - BOT, D + 0.66]},
            {'type': 'convex', 'name': 'Porch', 'center': [0, 0, 0], 'points': [
                [sx * 2.75, y, z] for sx in (-1, 1) for (y, z) in (
                    (-0.20, HD), (PAVE, HD), (PAVE, ZF + 0.35), (-0.20, ZF + 0.75))]},
            {'type': 'cylinder', 'name': 'PostL', 'center': [-PX, 1.75, ZF], 'radius': 0.15, 'height': 3.3},
            # 右柱掛立看板（前出 0.16、寬 0.42）→ 用 box 一起包住
            {'type': 'box', 'name': 'PostR', 'center': [PX, 1.75, ZF + 0.02], 'size': [0.46, 3.3, 0.36]},
            {'type': 'box', 'name': 'Banner', 'center': [BAN[0], 2.6, BAN[1]], 'size': [0.50, 5.6, 0.50]},
            {'type': 'box', 'name': 'NoticeL', 'center': [BRD_L[0], 1.2, BRD_L[1]], 'size': [2.06, 2.9, 0.64]},
            {'type': 'box', 'name': 'NoticeR', 'center': [BRD_R[0], 1.2, BRD_R[1]], 'size': [2.06, 2.9, 0.64]},
            {'type': 'box', 'name': 'Toro', 'center': [TORO[0], 0.74, TORO[1]], 'size': [0.62, 1.72, 0.62]}],
        'measured_blender': {'LOD0': stats['LOD0'], 'LOD1': stats['LOD1'], 'LOD2': stats['LOD2'],
                             'aabb': stats['aabb0'], 'aabb_lod1': stats['aabb1'], 'aabb_lod2': stats['aabb2']},
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[TERAKOYA]', stats)


main()
