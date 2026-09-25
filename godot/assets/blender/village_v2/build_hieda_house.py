"""稗田邸 本屋（LANDMARK_HIEDA）Hero — 人間之里 V2 P5 R6 新資產（全新程序化建模）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_hieda_house.py

外觀 authority：docs/reference/重點地標/裨田邸正面.PNG（正面：中央高兩層、正面大山牆，兩側較低兩層翼屋、二樓木欄＋格子窗）、
裨田後.PNG（背面：同構成；一樓緣側＋庇、障子、二樓格子窗；屋根入母屋、中央棟與正面垂直、翼屋棟與正面平行）。
使用者 2026-09-26 裁示（R6 選 A）：本輪只做本屋本體（兩層、正面中央山牆、側面與背面輪廓）；池庭／池塘延 P9／P10，
整圈圍牆延 P6／P10；位置照 layout provisional，P0–P4 不動。木色＋灰瓦＋灰泥，不做紅色；無招牌、無文字。
構法沿用 R3 寺子屋／R5 山頂社殿（v2_irimoya.tile_band／under／hip_ridge），腳本另存、既有資產不動。
尺寸 authority：P0 LANDMARK_HIEDA（box 28 × 9 × 18，寬×高×深；沒有 P4 灰盒）＋地塊 P_LM_HIEDA（34 × 24）。
  全部（含出簷、庇、石段）在 P0 量體內：x ±14、z ±9、最高點 ≤ 9.0。
座標：Godot；原點＝P0 地標原點（地塊中心）、y 0＝地標節點高度、+z＝正面（南，朝大宅門）。
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402
from v2_kit import X, Y, Z, add, mul, norm, cross, dot, sub  # noqa: E402
import v2_irimoya as I  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/hieda_house'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(OUT + '/atlas.json')
RG = AT['regions']
SWATCH = {k: v['uv'] for k, v in AT['swatches'].items()}
AMAT = 'V2_HiedaHouse'
MATS = ['V2_Wood', 'V2_Kawara', 'V2_Stone', 'V2_Plaster', AMAT]
TILE = {k: v['tile_m'] for k, v in ML.items()}
KW = ML['V2_Kawara']
DARK, BOARD = 0.34, 0.74

# ── 高度
BOT, KIDAN = -0.40, 0.50           # 石積基壇底、頂（一樓床）
LINTEL1 = 2.55                     # 一樓鴨居下
NAGE1 = (2.55, 2.70)               # 一樓長押
FLOOR2 = (3.15, 3.45)              # 二樓床梁
WIN2 = (3.85, 4.90)                # 二樓窗
KETA_W, KETA_P = 5.25, 5.75        # 桁頂：翼屋、中央棟
# ── 平面
PX = 4.5                           # 中央棟半寬（x ±4.5）
PZ0, PZ1 = -6.2, 7.0               # 中央棟 背、正面（玄關）
WX = 12.0                          # 翼屋外牆 x
WZ = 5.0                           # 翼屋前後牆 z ±5
KID_X = WX + 0.35
KID_Z0 = PZ0 - 0.05                # 背側基壇（緣側在其上）
KID_ZW = WZ + 0.40                 # 翼屋前基壇
KID_ZP = PZ1 + 0.30                # 玄關前基壇
EN_Z = PZ0                         # 背面緣側外緣（翼屋 z −5 → −6.2）
# ── 屋根
OV = 1.0
PP, YE_P = 0.52, 5.60              # 中央棟：坡度、簷口（屋面）
WP, YE_W = 0.36, 5.10              # 翼屋（棟比中央棟低 ≈1.4 m：參考圖翼屋峰約中央 3/4 高）
PCZ = (PZ0 + PZ1) / 2              # 中央棟 棟中心 z
PHL = (PZ1 - PZ0) / 2
YR_P = YE_P + PP * (PX + OV)
YR_W = YE_W + WP * (WZ + OV)
ONI_P = YR_P + 0.45
# 玄關
GEN = 1.20                         # 玄關開口半寬
GEN_D = 0.70                       # 玄關凹入深
STEP = [(PZ1 + 0.30, PZ1 + 0.95, 0.25)]      # 一段踏石：地面→0.25→台基 0.50（每階 0.25）
ST_HW = 1.50
# 庇（一樓）
HIS_P = 0.30


def gsw(hexcol):
    u, v = SWATCH[hexcol]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


# ─────────────────────────── 牆面 ───────────────────────────
class Face:
    """牆面座標：t＝從外面看向右、y、d＝往外（牆面 d＝0）。t、n 都是軸向。"""

    def __init__(self, o, t, n):
        self.o, self.t, self.n = o, t, n
        self.gax = X if abs(t[0]) > 0.5 else Z

    def P(self, t, y, d=0.0):
        return add(add(add(self.o, mul(self.t, t)), (0.0, y, 0.0)), mul(self.n, d))

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


def split_region(m, F, t0, t1, y0, y1, d, region, col=1.0):
    u0, v0, u1, v1 = region
    ra = (u1 - u0) / (v1 - v0)
    n = max(1, round((t1 - t0) / (y1 - y0) / ra))
    for k in range(n):
        a = t0 + (t1 - t0) * k / n
        b = t0 + (t1 - t0) * (k + 1) / n
        F.rect(m, a, b, y0, y1, d, AMAT, col, region)


def zone(m, F, t0, t1, y0, y1, kind, lod):
    if kind == 'plaster':
        F.rect(m, t0, t1, y0, y1, -0.04, 'V2_Plaster', 0.97, grain=F.gax)
    elif kind == 'board':
        F.rect(m, t0, t1, y0, y1, -0.04, 'V2_Wood', BOARD * 0.6, grain=Y)
        if lod == 0:
            n = max(1, int((t1 - t0) / 0.45))
            for k in range(1, n):
                t = t0 + (t1 - t0) * k / n
                F.box(m, t - 0.02, t + 0.02, y0, y1, -0.04, -0.01, 'V2_Wood', DARK * 0.9, grain=Y,
                      skip=('+y', '-y'))
    else:
        split_region(m, F, t0, t1, y0, y1, -0.05, RG[kind], 1.0)


def facade(m, lod, F, t0, t1, posts, keta, z1, z2, back_col='V2_Plaster', top_band=None):
    """兩層牆面：底襯（防透）、柱、橫材、一樓／二樓區塊。z1／z2＝[(t0, t1, kind)]（kind 或 [(y0, y1, kind)…]）。"""
    F.rect(m, t0, t1, KIDAN, keta, -0.07, 'V2_Wood', DARK * 0.5, grain=Y)
    for t in posts:
        F.box(m, t - 0.12, t + 0.12, KIDAN, keta, -0.12, 0.04, 'V2_Wood', DARK, grain=Y, skip=('-y',))
    ga = F.gax
    F.box(m, t0, t1, KIDAN, KIDAN + 0.10, -0.10, 0.03, 'V2_Wood', DARK * 0.9, grain=ga)            # 土台
    F.box(m, t0, t1, NAGE1[0], NAGE1[1], -0.10, 0.05, 'V2_Wood', DARK, grain=ga)                    # 長押
    F.box(m, t0, t1, FLOOR2[0], FLOOR2[1], -0.10, 0.06, 'V2_Wood', DARK, grain=ga)                  # 二樓床梁
    F.box(m, t0 - 0.06, t1 + 0.06, keta - 0.24, keta, -0.10, 0.08, 'V2_Wood', DARK, grain=ga)       # 桁
    if top_band:
        F.box(m, t0 - 0.10, t1 + 0.10, keta, top_band, -0.10, -0.02, 'V2_Wood', DARK * 0.7, grain=ga,
              skip=('+y', '-y'))
    for (a, b, kind) in z1:
        if isinstance(kind, list):
            for (y0, y1, k) in kind:
                zone(m, F, a, b, y0, y1, k, lod)
        else:
            zone(m, F, a, b, KIDAN + 0.10, NAGE1[0], kind, lod)
        zone(m, F, a, b, NAGE1[1], FLOOR2[0], 'plaster', lod)
    for (a, b, kind) in z2:
        if isinstance(kind, list):
            for (y0, y1, k) in kind:
                zone(m, F, a, b, y0, y1, k, lod)
        else:
            zone(m, F, a, b, FLOOR2[1], WIN2[0], 'plaster', lod)
            zone(m, F, a, b, WIN2[0], WIN2[1], kind, lod)
            zone(m, F, a, b, WIN2[1], keta - 0.24, 'plaster', lod)
            F.box(m, a, b, WIN2[0] - 0.06, WIN2[0], -0.08, 0.02, 'V2_Wood', DARK, grain=ga)      # 窗台
            F.box(m, a, b, WIN2[1], WIN2[1] + 0.06, -0.08, 0.02, 'V2_Wood', DARK, grain=ga)


def bays(t0, t1, posts, kind, pw=0.12):
    """柱間區段：[(a, b, kind)]（扣掉柱寬）。"""
    edges = [t0] + [v for t in posts for v in (t - pw, t + pw)] + [t1]
    return [(edges[i], edges[i + 1], kind) for i in range(0, len(edges), 2)]


def corner_post(m, x, z, keta):
    m.box((x - 0.14, KIDAN, z - 0.14), (x + 0.14, keta, z + 0.14), 'V2_Wood', DARK, grain=Y, skip=('-y',))


def hisashi(m, lod, F, t0, t1, y_wall, depth, brackets=True):
    """一樓庇（單坡瓦）：牆頂 y_wall → 外出 depth。"""
    S = depth * math.sqrt(1 + HIS_P * HIS_P)
    o = F.P(0.0, y_wall, 0.02)
    dsl = norm(add(F.n, (0.0, -HIS_P, 0.0)))
    n = norm(add(mul(F.n, HIS_P), Y))
    I.tile_band(m, o, F.t, dsl, n, lambda s: t0, lambda s: t1, S, KW, min(lod, 2), ends=(lod == 0))
    if lod <= 1:
        I.under(m, o, F.t, dsl, n, lambda s: t0, lambda s: t1, S, depth=0.10)
        e0 = add(add(o, mul(F.t, t0)), mul(dsl, S))
        e1 = add(add(o, mul(F.t, t1)), mul(dsl, S))
        m.beam(add(e0, mul(n, -0.05)), add(e1, mul(n, -0.05)), 0.04, 0.12, 'V2_Wood', DARK * 0.85, up=n)
        for t in (t0, t1):   # 端の板（三角＋帯）
            a = F.P(t, y_wall + 0.03, 0.02)
            b = F.P(t, y_wall - depth * HIS_P + 0.03, depth + 0.02)
            m.beam(a, b, 0.04, 0.16, 'V2_Wood', DARK * 0.8, up=Y)
    if lod == 0 and brackets:
        k = max(1, int((t1 - t0) / 1.9))
        for i in range(k + 1):
            t = t0 + 0.15 + i * (t1 - t0 - 0.30) / k
            F.box(m, t - 0.05, t + 0.05, y_wall - 0.42, y_wall - 0.30, 0.0, depth * 0.75, 'V2_Wood', DARK * 0.9,
                  grain=F.n if abs(F.n[0]) > 0.5 else Z)
            m.beam(F.P(t, y_wall - 0.80, 0.0), F.P(t, y_wall - 0.36, depth * 0.55), 0.08, 0.08, 'V2_Wood', DARK * 0.85)


# ─────────────────────────── 屋根（入母屋；棟方向任意軸） ───────────────────────────
def irimoya(m, lod, c, er, es, a_wall, HD, P, YE, frac, a_butt=None, rafter_a=None, oni_h=0.45):
    """入母屋：棟沿 er、坡朝 ±es。a_wall＝(a_lo 牆, a_hi 牆)（沿 er，相對 c）；a_butt＝(lo, hi) 不做山牆的一端改直通到該值
    （翼屋內端插進中央棟屋根，None＝該端做入母屋）。回傳棟高 YR。"""
    SEC = math.sqrt(1 + P * P)
    ZE = HD + OV
    YR = YE + P * ZE
    Z_G = ZE * frac
    S_F, S_G = ZE * SEC, Z_G * SEC
    ends = {}
    for side, aw in ((-1, a_wall[0]), (1, a_wall[1])):
        butt = a_butt[0 if side < 0 else 1] if a_butt else None
        if butt is not None:
            ends[side] = {'butt': butt}
        else:
            XE = abs(aw) + OV
            XG = XE - (ZE - Z_G)
            ends[side] = {'XE': XE, 'XG': XG, 'XT': XG + 0.55, 'Y_G': YE + P * (XE - XG)}

    def bound(side, s):
        e = ends[side]
        if 'butt' in e:
            return abs(e['butt'])
        return e['XT'] if s < S_G else e['XE'] - ZE + s / SEC

    def PT(a, b, y):
        return (c[0] + er[0] * a + es[0] * b, y, c[2] + er[2] * a + es[2] * b)
    TW = TILE['V2_Wood']
    for sg in (1, -1):
        o = PT(0.0, 0.0, YR)
        dsl = norm(add(mul(es, sg), (0.0, -P, 0.0)))
        n = norm(add(mul(es, P * sg), Y))
        ax = cross(mul(es, -sg), Y)
        k = dot(er, ax)
        if k > 0:
            xl, xr = (lambda s: -bound(-1, s)), (lambda s: bound(1, s))
        else:
            xl, xr = (lambda s: -bound(1, s)), (lambda s: bound(-1, s))
        I.tile_band(m, o, ax, dsl, n, xl, xr, S_F, KW, lod, s_range=(0.0, S_G), ends=False)
        I.tile_band(m, o, ax, dsl, n, xl, xr, S_F, KW, lod, s_range=(S_G, S_F), ends=(lod == 0))
        if lod <= 1:
            I.under(m, o, ax, dsl, n, xl, xr, S_G)
            o2 = add(o, mul(dsl, S_G))
            I.under(m, o2, ax, dsl, n, lambda s: xl(s + S_G), lambda s: xr(s + S_G), S_F - S_G)
            # 簷桁
            a0, a1 = -bound(-1, S_F), bound(1, S_F)
            e0, e1 = PT(a0, sg * ZE, YE), PT(a1, sg * ZE, YE)
            m.beam(add(e0, mul(n, -0.06)), add(e1, mul(n, -0.06)), 0.08, 0.24, 'V2_Wood', DARK * 0.9, up=n)
        if lod == 0 and rafter_a:
            ra0, ra1 = rafter_a
            kk = int((ra1 - ra0) / 0.42)
            for i in range(kk + 1):
                a = ra0 + 0.15 + i * (ra1 - ra0 - 0.30) / kk
                za, zb = HD, ZE - 0.12
                m.beam(PT(a, sg * za, YR - P * za - 0.24), PT(a, sg * zb, YR - P * zb - 0.24), 0.07, 0.08,
                       'V2_Wood', DARK * 0.8, up=Y)
    # 山牆端
    for side in (-1, 1):
        e = ends[side]
        if 'butt' in e:
            continue
        XE, XG, XT, Y_G = e['XE'], e['XG'], e['XT'], e['Y_G']
        erv = mul(er, float(side))
        o = PT(side * XG, 0.0, Y_G)
        dsl = norm(add(erv, (0.0, -P, 0.0)))
        n = norm(add(mul(erv, P), Y))
        ax = cross(mul(erv, -1.0), Y)
        S_H = (XE - XG) * SEC
        I.tile_band(m, o, ax, dsl, n, lambda s: -(Z_G + s / SEC), lambda s: Z_G + s / SEC, S_H, KW, lod,
                    ends=(lod == 0))
        if lod <= 1:
            I.under(m, o, ax, dsl, n, lambda s: -(Z_G + s / SEC), lambda s: Z_G + s / SEC, S_H)
            m.beam(add(PT(side * XE, -ZE, YE), mul(n, -0.06)), add(PT(side * XE, ZE, YE), mul(n, -0.06)), 0.08, 0.24,
                   'V2_Wood', DARK * 0.9, up=n)
        u0, v0, u1, v1 = RG['tsuma']
        I.oface(m, [PT(side * XG, -Z_G, Y_G), PT(side * XG, Z_G, Y_G), PT(side * XG, 0.0, YR - 0.05)], erv,
                AMAT, [(u0, v1), (u1, v1), ((u0 + u1) / 2, v0)], 0.95)
        p, q = PT(side * (XG - 0.02), -Z_G, Y_G - 0.04), PT(side * (XG + 0.14), Z_G, Y_G + 0.10)
        m.box(tuple(min(p[i], q[i]) for i in range(3)), tuple(max(p[i], q[i]) for i in range(3)), 'V2_Wood', DARK)
        for sb in (1, -1):
            I.hip_ridge(m, PT(side * XT, 0.0, YR), PT(side * XT, sb * Z_G, Y_G), lod, w=0.26, h=0.18)
            if lod <= 1:
                m.beam(PT(side * (XT + 0.04), 0.0, YR - 0.10), PT(side * (XT + 0.04), sb * (Z_G + 0.08), Y_G - 0.10),
                       0.08, 0.34, 'V2_Wood', DARK * 0.85, up=Y)
            I.hip_ridge(m, PT(side * XG, sb * Z_G, Y_G), PT(side * XE, sb * ZE, YE), lod, w=0.28, h=0.18)
        if lod == 0:   # 懸魚
            xg = side * (XT + 0.09)
            gy = YR - 0.30
            ps = [PT(xg, -0.18, gy + 0.02), PT(xg, 0.0, gy - 0.32), PT(xg, 0.18, gy + 0.02), PT(xg, 0.0, gy + 0.20)]
            I.oface(m, ps, erv, 'V2_Wood', [(0, 0), (0.1, 0), (0.1, 0.1), (0, 0.1)], DARK * 0.9)
        if lod == 0:   # 妻側垂木
            kk = int((2 * HD - 0.4) / 0.42)
            aw = abs(a_wall[0 if side < 0 else 1])
            for i in range(kk + 1):
                b = -HD + 0.2 + i * (2 * HD - 0.4) / kk
                xa, xb = aw, XE - 0.12
                m.beam(PT(side * xa, b, YE + P * (XE - xa) - 0.24), PT(side * xb, b, YE + P * (XE - xb) - 0.24),
                       0.07, 0.08, 'V2_Wood', DARK * 0.8, up=Y)
    # 棟
    a_lo = -(ends[-1]['butt'] if 'butt' in ends[-1] else ends[-1]['XT'] + 0.05)
    a_hi = ends[1]['butt'] if 'butt' in ends[1] else ends[1]['XT'] + 0.05
    a_lo, a_hi = -abs(a_lo), abs(a_hi)
    p, q = PT(a_lo, -0.22, YR - 0.12), PT(a_hi, 0.22, YR + 0.18)
    m.box(tuple(min(p[i], q[i]) for i in range(3)), tuple(max(p[i], q[i]) for i in range(3)), 'V2_Kawara', 0.55,
          grain=er)
    if lod <= 1:
        m.cyl(PT(a_lo, 0.0, YR + 0.20), PT(a_hi, 0.0, YR + 0.20), 0.13, 0.13, 12 if lod == 0 else 8, 'V2_Kawara',
              0.50, caps=(True, True))
    for side in (-1, 1):
        if 'butt' in ends[side]:
            continue
        XT = ends[side]['XT']
        p, q = PT(side * (XT - 0.05), -0.34, YR - 0.15), PT(side * (XT + 0.28), 0.34, YR + oni_h)
        m.box(tuple(min(p[i], q[i]) for i in range(3)), tuple(max(p[i], q[i]) for i in range(3)), 'V2_Kawara', 0.40,
              grain=Y)
    return YR


# ─────────────────────────── 構件 ───────────────────────────
def kidan(m, lod):
    parts = [((-KID_X, KID_Z0), (KID_X, KID_ZW)), ((-PX - 0.20, KID_ZW), (PX + 0.20, KID_ZP))]
    for (x0, z0), (x1, z1) in parts:
        m.box((x0, BOT, z0), (x1, KIDAN, z1), 'V2_Stone', 0.84, skip=('-y',))
    if lod != 0:
        return
    rnd = random.Random(606)
    runs = [(-KID_X, KID_X, KID_Z0, 'x', -1), (-KID_X, -PX - 0.20, KID_ZW, 'x', 1), (PX + 0.20, KID_X, KID_ZW, 'x', 1),
            (-PX - 0.20, PX + 0.20, KID_ZP, 'x', 1), (KID_Z0, KID_ZW, KID_X, 'z', 1), (KID_Z0, KID_ZW, -KID_X, 'z', -1),
            (KID_ZW, KID_ZP, PX + 0.20, 'z', 1), (KID_ZW, KID_ZP, -PX - 0.20, 'z', -1)]
    for (a, b, fixed, axis, sgn) in runs:
        for (y0, y1) in ((-0.08, 0.20), (0.20, KIDAN - 0.02)):
            t = a
            while t < b - 0.05:
                L = rnd.uniform(0.55, 1.20)
                e = min(b, t + L)
                if b - e < 0.30:
                    e = b
                col = rnd.uniform(0.72, 0.94)
                if axis == 'x':
                    if a <= -ST_HW <= b and fixed == KID_ZP and not (e <= -ST_HW or t >= ST_HW):
                        t = e
                        continue
                    lo = (t + 0.02, y0 + 0.01, fixed if sgn > 0 else fixed - 0.02)
                    hi = (e - 0.02, y1 - 0.01, fixed + 0.02 if sgn > 0 else fixed)
                    m.box(lo, hi, 'V2_Stone', col, skip=('-y', '-z' if sgn > 0 else '+z'))
                else:
                    lo = (fixed if sgn > 0 else fixed - 0.02, y0 + 0.01, t + 0.02)
                    hi = (fixed + 0.02 if sgn > 0 else fixed, y1 - 0.01, e - 0.02)
                    m.box(lo, hi, 'V2_Stone', col, skip=('-y', '-x' if sgn > 0 else '+x'))
                t = e


def steps(m):
    for (z0, z1, top) in STEP:
        m.box((-ST_HW, -0.20, z0 - 0.02), (ST_HW, top, z1), 'V2_Stone', 0.86 if top > 0.2 else 0.90, skip=('-y',))


def genkan(m, lod):
    """玄關：中央棟正面一樓、開口 ±GEN、凹入 GEN_D（地板石、兩側板、天井、奧に格子戶）。"""
    zf, zb = PZ1, PZ1 - GEN_D
    u0, v0, u1, v1 = RG['door']
    m.rect_uv((-GEN, KIDAN, zb), (GEN, KIDAN, zb), (GEN, LINTEL1, zb), (-GEN, LINTEL1, zb), AMAT, RG['door'], 1.0)
    m.quad((-GEN, KIDAN, zb), (-GEN, KIDAN, zf), (-GEN, LINTEL1, zf), (-GEN, LINTEL1, zb), 'V2_Wood', DARK * 0.8,
           grain=Y)
    m.quad((GEN, KIDAN, zf), (GEN, KIDAN, zb), (GEN, LINTEL1, zb), (GEN, LINTEL1, zf), 'V2_Wood', DARK * 0.8,
           grain=Y)
    m.quad((-GEN, KIDAN, zf), (GEN, KIDAN, zf), (GEN, KIDAN, zb), (-GEN, KIDAN, zb), 'V2_Stone', 0.70, grain=X)
    m.quad((-GEN, LINTEL1, zb), (GEN, LINTEL1, zb), (GEN, LINTEL1, zf), (-GEN, LINTEL1, zf), 'V2_Wood', DARK * 0.5,
           grain=X)
    # 敷居・鴨居の框
    m.box((-GEN, KIDAN, zf - 0.10), (GEN, KIDAN + 0.04, zf + 0.02), 'V2_Wood', DARK * 0.9, grain=X, skip=('-y',))
    if lod == 0:
        # 奧：遠處暗室（格子戶の格子越し）
        m.rect_uv((-GEN + 0.02, KIDAN + 0.1, zb - 0.02), (GEN - 0.02, KIDAN + 0.1, zb - 0.02),
                  (GEN - 0.02, LINTEL1 - 0.1, zb - 0.02), (-GEN + 0.02, LINTEL1 - 0.1, zb - 0.02), AMAT,
                  RG['interior'], 1.0)


def pavilion_walls(m, lod):
    FR = Face((0.0, 0.0, PZ1), X, Z)
    posts = [-GEN - 0.12, GEN + 0.12, -2.95, 2.95]
    z1 = [(-PX + 0.14, -3.07, 'koshi'), (-2.83, -GEN - 0.24, 'koshi'), (GEN + 0.24, 2.83, 'koshi'),
          (3.07, PX - 0.14, 'koshi')]
    z2 = bays(-PX + 0.14, PX - 0.14, [-GEN - 0.12, GEN + 0.12, -2.95, 2.95], 'window_2f')
    # 玄關の上（二樓）は窗、一樓は凹入：facade 的一樓區塊不含開口
    facade(m, lod, FR, -PX, PX, posts, KETA_P, z1, z2, top_band=KETA_P + 0.22)
    FR.rect(m, -GEN, GEN, NAGE1[1], FLOOR2[0], -0.04, 'V2_Plaster', 0.97, grain=X)
    genkan(m, lod)
    BK = Face((0.0, 0.0, PZ0), mul(X, -1.0), mul(Z, -1.0))
    bposts = [-1.5, 1.5]
    facade(m, lod, BK, -PX, PX, bposts, KETA_P, bays(-PX + 0.14, PX - 0.14, bposts, 'shoji'),
           bays(-PX + 0.14, PX - 0.14, bposts, 'window_2f'), top_band=KETA_P + 0.22)
    for sx in (-1, 1):
        # 正面突出部の側面（z WZ → PZ1）、背面突出部の側面（PZ0 → −WZ）
        if sx > 0:
            SF = Face((PX, 0.0, 0.0), mul(Z, -1.0), X)
            tf0, tf1 = -PZ1, -WZ
            tb0, tb1 = WZ, -PZ0
        else:
            SF = Face((-PX, 0.0, 0.0), Z, mul(X, -1.0))
            tf0, tf1 = WZ, PZ1
            tb0, tb1 = PZ0, -WZ
        facade(m, lod, SF, tf0, tf1, [], KETA_P,
               [(tf0 + 0.14, tf1 - 0.14, [(KIDAN + 0.10, 1.25, 'board'), (1.25, NAGE1[0], 'plaster')])],
               [(tf0 + 0.14, tf1 - 0.14, [(FLOOR2[1], KETA_P - 0.24, 'plaster')])], top_band=KETA_P + 0.22)
        facade(m, lod, SF, tb0, tb1, [], KETA_P,
               [(tb0 + 0.14, tb1 - 0.14, [(KIDAN + 0.10, 1.25, 'board'), (1.25, NAGE1[0], 'plaster')])],
               [(tb0 + 0.14, tb1 - 0.14, [(FLOOR2[1], KETA_P - 0.24, 'plaster')])], top_band=KETA_P + 0.22)
        # 側面 2F 上部（翼屋屋根より上に見える三角域）：中央棟桁〜翼屋屋面は屋根で覆うので不要
    for (x, z) in ((-PX, PZ1), (PX, PZ1), (-PX, PZ0), (PX, PZ0)):
        corner_post(m, x, z, KETA_P)


WPOSTS = [6.375, 8.25, 10.125]


def wing_walls(m, lod):
    for sx in (-1, 1):
        ts = sorted(sx * p for p in WPOSTS)
        a0, a1 = sorted((sx * PX, sx * WX))
        # 正面（z＝WZ，t＝x）
        FR = Face((0.0, 0.0, WZ), X, Z)
        facade(m, lod, FR, a0, a1, ts, KETA_W, bays(a0 + 0.02, a1 - 0.14 if sx > 0 else a1, ts, 'koshi')
               if sx > 0 else bays(a0 + 0.14, a1 - 0.02, ts, 'koshi'),
               bays(a0 + 0.02, a1 - 0.14, ts, 'window_2f') if sx > 0 else bays(a0 + 0.14, a1 - 0.02, ts, 'window_2f'),
               top_band=KETA_W + 0.20)
        # 背面（z＝−WZ，t＝−x）
        BK = Face((0.0, 0.0, -WZ), mul(X, -1.0), mul(Z, -1.0))
        b0, b1 = sorted((-a1, -a0))
        bts = sorted(-t for t in ts)
        inner_first = sx > 0   # 背面 t 軸反向：右翼的內端在 t 大的一側
        z1 = bays(b0 + 0.14, b1 - 0.02, bts, 'shoji') if inner_first else bays(b0 + 0.02, b1 - 0.14, bts, 'shoji')
        z2 = bays(b0 + 0.14, b1 - 0.02, bts, 'window_2f') if inner_first else bays(b0 + 0.02, b1 - 0.14, bts,
                                                                                  'window_2f')
        facade(m, lod, BK, b0, b1, bts, KETA_W, z1, z2, top_band=KETA_W + 0.20)
        # 外側面（x＝±WX）
        if sx > 0:
            SF = Face((WX, 0.0, 0.0), mul(Z, -1.0), X)
        else:
            SF = Face((-WX, 0.0, 0.0), Z, mul(X, -1.0))
        sp = [-2.5, 0.0, 2.5]
        z1 = [(-WZ + 0.14, -2.62, [(KIDAN + 0.10, 1.25, 'board'), (1.25, NAGE1[0], 'plaster')]),
              (-2.38, -0.12, [(KIDAN + 0.10, 1.10, 'board'), (1.10, 2.30, 'shoji'), (2.30, NAGE1[0], 'plaster')]),
              (0.12, 2.38, [(KIDAN + 0.10, 1.10, 'board'), (1.10, 2.30, 'shoji'), (2.30, NAGE1[0], 'plaster')]),
              (2.62, WZ - 0.14, [(KIDAN + 0.10, 1.25, 'board'), (1.25, NAGE1[0], 'plaster')])]
        z2 = [(-WZ + 0.14, -2.62, [(FLOOR2[1], KETA_W - 0.24, 'plaster')]), (-2.38, -0.12, 'window_2f'),
              (0.12, 2.38, 'window_2f'), (2.62, WZ - 0.14, [(FLOOR2[1], KETA_W - 0.24, 'plaster')])]
        facade(m, lod, SF, -WZ, WZ, sp, KETA_W, z1, z2, top_band=KETA_W + 0.20)
        for z in (-WZ, WZ):
            corner_post(m, sx * WX, z, KETA_W)
            corner_post(m, sx * PX, z, KETA_P if z < 0 else KETA_W)
        # 背側端收在緣側庇之下（z −WZ），前側 +0.10
        hisashi(m, lod, SF, *((-WZ - 0.10, WZ) if sx > 0 else (-WZ, WZ + 0.10)), 3.30, 0.90)


def balcony(m, lod):
    """翼屋二樓正面の縁（木欄）：床 FLOOR2、外出 1.0 m；一樓の軒を兼ねる。"""
    z0, z1 = WZ, WZ + 1.0
    y_f = FLOOR2[1]
    for sx in (-1, 1):
        a0, a1 = sorted((sx * (PX + 0.02), sx * (WX + 0.02)))
        m.box((a0, y_f - 0.12, z0), (a1, y_f, z1), 'V2_Wood', BOARD * 0.6, grain=X)
        m.box((a0, y_f - 0.30, z1 - 0.12), (a1, y_f - 0.12, z1), 'V2_Wood', DARK, grain=X)
        yt, yb = y_f + 0.85, y_f + 0.10
        zr = z1 - 0.06
        m.box((a0, yt - 0.07, zr - 0.05), (a1, yt, zr + 0.05), 'V2_Wood', DARK, grain=X)
        m.box((a0, yb, zr - 0.04), (a1, yb + 0.06, zr + 0.04), 'V2_Wood', DARK, grain=X)
        xe = sx * (WX - 0.04)
        m.box((xe - 0.04, yt - 0.07, z0), (xe + 0.04, yt, z1), 'V2_Wood', DARK, grain=Z)
        pts = [a0 + 0.06, a1 - 0.06] + [sx * p for p in WPOSTS]
        for x in pts:
            m.box((x - 0.05, y_f, zr - 0.05), (x + 0.05, yt, zr + 0.05), 'V2_Wood', DARK, grain=Y, skip=('-y',))
            if lod == 0:   # 持送り
                m.beam((x, y_f - 0.95, z0 + 0.02), (x, y_f - 0.30, z1 - 0.15), 0.10, 0.10, 'V2_Wood', DARK * 0.9)
        if lod == 0:
            k = int((a1 - a0) / 0.14)
            for i in range(1, k):
                x = a0 + i * (a1 - a0) / k
                m.box((x - 0.02, yb + 0.06, zr - 0.02), (x + 0.02, yt - 0.07, zr + 0.02), 'V2_Wood', DARK * 0.9,
                      grain=Y, skip=('+y', '-y'))


def engawa(m, lod):
    """背面：翼屋一樓緣側（z −WZ → EN_Z）＋庇（柱で受ける）；中央棟背面は短い庇のみ。"""
    for sx in (-1, 1):
        a0, a1 = sorted((sx * PX, sx * (WX + 0.10)))
        m.box((a0, KIDAN - 0.10, EN_Z + 0.02), (a1, KIDAN + 0.05, -WZ), 'V2_Wood', BOARD * 0.6, grain=X, skip=('-y',))
        if lod == 0:
            for k in range(1, 8):
                z = EN_Z + (-WZ - EN_Z) * k / 8
                m.box((a0, KIDAN + 0.05, z - 0.005), (a1, KIDAN + 0.055, z + 0.005), 'V2_Wood', DARK * 0.8, grain=X,
                      skip=('-y',))
        pz = EN_Z + 0.14
        for x in [sx * (PX + 0.30)] + [sx * p for p in WPOSTS] + [sx * (WX - 0.05)]:
            m.box((x - 0.07, KIDAN + 0.05, pz - 0.07), (x + 0.07, 3.02, pz + 0.07), 'V2_Wood', DARK, grain=Y,
                  skip=('-y',))
        m.box((a0, 2.86, pz - 0.08), (a1, 3.02, pz + 0.08), 'V2_Wood', DARK, grain=X)
        BK = Face((0.0, 0.0, -WZ), mul(X, -1.0), mul(Z, -1.0))
        h0, h1 = sorted((sx * PX, sx * (WX + 0.90)))     # 庇外端與側面庇出簷對齊（轉角不留缺口）
        b0, b1 = sorted((-h1, -h0))
        hisashi(m, lod, BK, b0, b1, 3.40, 1.55, brackets=False)
    BK = Face((0.0, 0.0, PZ0), mul(X, -1.0), mul(Z, -1.0))
    hisashi(m, lod, BK, -PX - 0.05, PX + 0.05, 3.30, 0.80)


def genkan_roof(m, lod):
    FR = Face((0.0, 0.0, PZ1), X, Z)
    hisashi(m, lod, FR, -PX - 0.05, PX + 0.05, 3.35, 1.30)


def lod2_body(m):
    """LOD2：量體＋主要面貼 atlas（一樓格子、二樓窗）。"""
    for (x0, x1, z0, z1, keta) in ((-WX, WX, -WZ, WZ, KETA_W), (-PX, PX, PZ0, PZ1, KETA_P)):
        m.box((x0, KIDAN, z0), (x1, keta + 0.2, z1), 'V2_Plaster', 0.8, skip=('-y', '+y'))
    for (x0, x1, z, sg) in ((-WX, -PX, WZ, 1), (PX, WX, WZ, 1), (-PX, PX, PZ1, 1)):
        F = Face((0.0, 0.0, z + 0.01), X, Z)
        F.rect(m, x0, x1, KIDAN, NAGE1[0], 0.0, AMAT, 1.0, RG['koshi'])
        F.rect(m, x0, x1, WIN2[0], WIN2[1], 0.0, AMAT, 1.0, RG['window_2f'])
    m.box((-KID_X, BOT, KID_Z0), (KID_X, KIDAN, KID_ZW), 'V2_Stone', 0.84, skip=('-y',))
    m.box((-PX - 0.2, BOT, KID_ZW), (PX + 0.2, KIDAN, KID_ZP), 'V2_Stone', 0.84, skip=('-y',))


def build(lod):
    m = K.Mesh('HiedaHouse_LOD%d' % lod, MATS, TILE)
    kidan(m, 0 if lod == 0 else 1)
    if lod <= 1:
        pavilion_walls(m, lod)
        wing_walls(m, lod)
        balcony(m, lod)
        engawa(m, lod)
        genkan_roof(m, lod)
        steps(m)
    else:
        lod2_body(m)
        m.box((-ST_HW, -0.2, STEP[0][0]), (ST_HW, STEP[0][2], STEP[-1][1]), 'V2_Stone', 0.86, skip=('-y',))
    # 中央棟：棟沿 z、正背面入母屋（正面山牆）
    # 破風比 0.85：正面山牆貼近正面牆（參考圖正面大三角山牆）
    irimoya(m, lod, (0.0, 0.0, PCZ), Z, X, (-PHL, PHL), PX, PP, YE_P, 0.85, rafter_a=(-PHL, PHL))
    # 翼屋：棟沿 x、外端入母屋、內端直通插進中央棟屋根
    for sx in (-1, 1):
        er = mul(X, float(sx))
        irimoya(m, lod, (0.0, 0.0, 0.0), er, Z, (-1.0, WX), WZ, WP, YE_W, 0.45, a_butt=(0.3, None),
                rafter_a=(PX + 0.1, WX), oni_h=0.38)
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
    glb = OUT + '/src/hieda_house.glb'
    K.export_glb(bpy, glb, objs)
    cnt = tri_count(glb)
    stats = {'LOD%d' % l: cnt['HiedaHouse_LOD%d' % l] for l in (0, 1, 2)}
    top = aabb[0][1][1]
    eave_back = round(YR_W - WP * (WZ + OV - 0.05) + 0.03, 3)
    st_z1 = STEP[-1][1]
    spec = {
        '_note': '稗田邸 本屋 Hero 資產規格（build_hieda_house.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、'
                 'verify_village_v2_hero_gate.gd 讀取）。沒有 P4 灰盒：放在 P0 地標原點（anchor），取代 P0 線框；'
                 '尺寸以 P0 量體 28 × 9 × 18 為上限、地塊 P_LM_HIEDA 為界。使用者 2026-09-26 裁示：只做本屋本體'
                 '（池庭 P9／P10、整圈圍牆 P6／P10）；位置照 layout provisional。',
        'id': 'hieda_house', 'landmark': 'LANDMARK_HIEDA', 'kind': 'hero', 'budget_class': '稗田邸',
        'glb': 'res://assets/village_v2/hieda_house/src/hieda_house.glb',
        'scene': 'res://assets/village_v2/hieda_house/hieda_house.scn',
        'lod_objects': ['HiedaHouse_LOD0', 'HiedaHouse_LOD1', 'HiedaHouse_LOD2'],
        'lod_ranges_m': [0, 55, 140, 700],
        'budget': {'lod0': 150000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': {k: (ML[k]['tres'] if k in ML else 'res://assets/village_v2/hieda_house/V2_HiedaHouse.tres')
                      for k in MATS},
        'spec': {'width_m': 2 * WX, 'depth_wing_m': 2 * WZ, 'depth_center_m': PZ1 - PZ0, 'center_w_m': 2 * PX,
                 'floor_m': KIDAN, 'floor2_m': FLOOR2[1], 'keta_m': [KETA_W, KETA_P],
                 'ridge_m': {'center': round(YR_P, 3), 'wing': round(YR_W, 3)}, 'top_m': top,
                 'eave_m': {'center': YE_P, 'wing': YE_W}, 'pitch': {'center': PP, 'wing': WP}, 'ov_eave_m': OV,
                 'foundation_bottom_m': BOT,
                 'design': {'roof': '中央棟 入母屋（棟沿 z，正面／背面山牆）＋兩翼 入母屋（棟沿 x，外端山牆、內端插入中央棟屋根）',
                            'front': '中央棟正面：一樓玄關（凹入 %.1f m、開口 %.1f m）＋千本格子、玄關庇；二樓格子窗；'
                                     '翼屋：一樓千本格子、二樓木欄の縁（出 1.0 m）＋格子窗' % (GEN_D, 2 * GEN),
                            'back': '翼屋一樓緣側（出 %.1f m）＋柱受け庇、障子；二樓格子窗；中央棟背面障子＋短庇' % (-WZ - EN_Z),
                            'side': '翼屋外側面：腰板＋灰泥、障子窗、二樓格子窗、一樓庇；入母屋妻（露明木構＋灰泥）',
                            'scope': '池庭、圍牆、燈籠不在本輪（P6／P9／P10）'}},
        'gate_spec': {
            'placement': 'anchor', 'anchor': 'Landmarks/LANDMARK_HIEDA', 'replaces': 'Wire',
            'also_retire': ['Footprint'], 'p4_id': '', 'parcel': 'P_LM_HIEDA', 'road': 'CrossStreetMid',
            'size': {'x_half_max': 14.0, 'z_min': -9.0, 'z_max': 9.0, 'top': [round(top - 0.05, 3), 9.0],
                     'bottom': BOT},
            'building': {'w': round(2 * (WX - 0.05), 3), 'd': round(2 * (WZ - 0.05), 3), 'zf': PZ1, 'plinth': KIDAN, 'ridge': round(YR_P + 0.18, 3),
                         'eave_edge': eave_back, 'ov_eave': OV, 'probe': {'x': 8.0, 'y': 4.5, 'z': 2.0, 'gx': -2.4}},
            'door_clear': {'h': round(LINTEL1 - KIDAN, 3), 'w': 2 * GEN, 'min_h': 1.9, 'min_w': 1.2},
            'ground': [
                {'name': '台基', 'rect': [-KID_X, KID_Z0, KID_X, KID_ZW], 'bottom': BOT, 'top': KIDAN, 'embed_max': 0.50},
                {'name': '台基（玄關）', 'rect': [-PX - 0.20, KID_ZW, PX + 0.20, KID_ZP], 'bottom': BOT, 'top': KIDAN,
                 'embed_max': 0.50},
                {'name': '踏石', 'rect': [-ST_HW, STEP[0][0] - 0.02, ST_HW, st_z1], 'bottom': -0.20, 'top': STEP[0][2],
                 'embed_max': 0.25}],
            'walkway': {'rect': [-1.0, st_z1 + 0.10, 1.0, st_z1 + 1.10], 'head': 1.95, 'min_clear': 2.5, 'step': 0.25},
            'entry': [0.0, 10.0], 'inside': [0.0, 0.0],
            # 鏡位（局部 xz）：地塊外圍平地（±20 m 高差 < 0.15 m）；西側 CrossStreetMid 終點、南側往大宅門
            'shots': [['front', 0.0, 21.0], ['front_r', 15.0, 19.0], ['street_w', -23.0, 5.0], ['back', -9.0, -20.0]]},
        'collision': [
            # 碰撞面比台基可見面外擴 0.08（避免射線掠過重合面）
            {'type': 'box', 'name': 'Wings', 'center': [0, (BOT + KETA_W) / 2, (KID_Z0 - 0.08 + KID_ZW + 0.08) / 2],
             'size': [2 * KID_X + 0.16, KETA_W - BOT, KID_ZW - KID_Z0 + 0.16]},
            {'type': 'box', 'name': 'Center', 'center': [0, (BOT + KETA_P) / 2, (KID_Z0 - 0.08 + KID_ZP + 0.08) / 2],
             'size': [2 * PX + 0.56, KETA_P - BOT, KID_ZP - KID_Z0 + 0.16]},
            {'type': 'convex', 'name': 'Steps', 'center': [0, 0, 0], 'points': [
                [sx * (ST_HW + 0.02), y, z] for sx in (-1, 1) for (y, z) in
                ((-0.20, KID_ZP - 0.05), (KIDAN, KID_ZP - 0.05), (-0.20, st_z1 + 0.05), (0.02, st_z1 + 0.05))]}],
        'measured_blender': dict(stats, aabb=aabb[0], aabb_lod1=aabb[1], aabb_lod2=aabb[2]),
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[HOUSE]', stats, aabb[0], 'YR_P %.2f YR_W %.2f TOP %.2f' % (YR_P, YR_W, top))


main()
