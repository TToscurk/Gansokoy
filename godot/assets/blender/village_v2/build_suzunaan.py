"""鈴奈庵（LANDMARK_SUZUNAAN）Hero — 人間之里 V2 P5 R1 新資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_suzunaan.py

外觀 authority：docs/reference/重點地標/鈴耐庵.png（厨子二階、平入切妻、灰瓦；三開間：左格子＋腰板＋書架、
中障子戸＋靛暖簾「鈴奈庵」5 片、右開放書架＋縁台；通長瓦庇＋腕木／出桁；二樓灰泥＋左大右小木格子窗、中央自然邊
看板；左柱「貸本」牌；右庇下行燈；左花盆＋木箱；低石基＋入口踏石）。
尺寸 authority：P4 greybox.json B_P_LM_SUZUNAAN（9.10 × 8.19、簷 3.9、脊 5.74、台基 0.32、庇 2.7／深 0.91、
出簷 0.45、妻側 0.25、pitch 0.45、門 1.82 × 2.1 置中、基礎底 −0.38）。P4 不動；舊 鈴奈庵.glb 只作參考。
座標：Godot；原點＝footprint 中心、y 0＝footprint 內最高地面（base_h）、+z＝正面（主街）。
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402
from v2_kit import X, Y, Z, add, mul, norm  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/suzunaan'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(OUT + '/atlas.json')
RG = AT['regions']
SWATCH = {k: v['uv'] for k, v in AT['swatches'].items()}
TILE = {k: v['tile_m'] for k, v in ML.items()}
KW = ML['V2_Kawara']
MATS = ['V2_Wood', 'V2_Plaster', 'V2_Kawara', 'V2_Stone', 'V2_Suzunaan']
AMAT = 'V2_Suzunaan'

# ── P4 authority
W, D = 9.10, 8.19
HW, HD = W / 2, D / 2
PLINTH, BOT = 0.32, -0.38
EAVE, PITCH, OV_E, OV_G = 3.90, 0.45, 0.45, 0.25
RIDGE = EAVE + HD * PITCH                 # 5.7428（屋面在壁心線 y＝EAVE）
SEC = math.sqrt(1 + PITCH ** 2)
HIS_Y, HIS_D = 2.76, 0.91                  # 庇瓦面在壁際的高度、出
DOOR_W, DOOR_H = 1.82, 2.10
# ── 立面（概念圖三開間 30:37:33 → 2.73／3.64／2.73）
XP = 1.82                                 # 中間兩柱
LINTEL = (2.42, 2.58)
PLATE = (3.62, 3.78)
WIN_Y = (3.00, 3.58)
WIN_L = (-3.50, -1.25)
WIN_R = (1.35, 3.15)
SIGN = (0.05, 3.28, 2.00, 0.625)          # 中心 x, y, 寬, 高
# ── 頂點色（線性乘數；V2_Wood 平均 #7A6445 → 結構深木 #493B27 ≈ 0.32、板 #6B583D ≈ 0.75）
DARK, BOARD, MID = 0.34, 0.74, 0.50


def rsub(r, fx0, fy0, fx1, fy1):
    u0, v0, u1, v1 = r
    return [u0 + (u1 - u0) * fx0, v0 + (v1 - v0) * fy0, u0 + (u1 - u0) * fx1, v0 + (v1 - v0) * fy1]


def sw(hexcol):
    u, v = SWATCH[hexcol]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


def fz(m, x0, x1, y0, y1, z, mat, col=1.0, region=None, grain=Y, back=False):
    """z 平面矩形；預設朝 +z（back=True 朝 −z，從背面看左右對調）。"""
    if back:
        a, b, c, d = (x1, y0, z), (x0, y0, z), (x0, y1, z), (x1, y1, z)
    else:
        a, b, c, d = (x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)
    if region:
        m.rect_uv(a, b, c, d, mat, region, col)
    else:
        m.quad(a, b, c, d, mat, col, grain=grain)


def fx(m, z0, z1, y0, y1, x, mat, col=1.0, region=None, grain=Y, neg=False):
    """x 平面矩形；預設朝 +x（neg=True 朝 −x）。"""
    if neg:
        a, b, c, d = (x, y0, z0), (x, y0, z1), (x, y1, z1), (x, y1, z0)
    else:
        a, b, c, d = (x, y0, z1), (x, y0, z0), (x, y1, z0), (x, y1, z1)
    if region:
        m.rect_uv(a, b, c, d, mat, region, col)
    else:
        m.quad(a, b, c, d, mat, col, grain=grain)


def recess(m, x0, x1, y0, y1, zf, depth, tiers, side_region=None, floor_col=0.42, col=1.0):
    """開口後的淺室（面朝內）：背板＝書背 atlas 分層；側板、地板、天花。tiers＝[(y0, y1, row), …]。"""
    zb = zf - depth
    for (ya, yb, row) in tiers:
        fz(m, x0, x1, ya, yb, zb, AMAT, col, rsub(RG['spines'], 0, row / 4, min(1.0, (x1 - x0) / 2.5), (row + 1) / 4))
    if side_region:
        fx(m, zb, zf, y0, y1, x0, AMAT, col * 0.7, side_region)
        fx(m, zb, zf, y0, y1, x1, AMAT, col * 0.7, side_region, neg=True)
    else:
        fx(m, zb, zf, y0, y1, x0, 'V2_Wood', DARK * 0.7)
        fx(m, zb, zf, y0, y1, x1, 'V2_Wood', DARK * 0.7, neg=True)
    m.quad((x0, y0, zf), (x1, y0, zf), (x1, y0, zb), (x0, y0, zb), 'V2_Wood', floor_col, grain=X)
    m.quad((x0, y1, zb), (x1, y1, zb), (x1, y1, zf), (x0, y1, zf), 'V2_Wood', DARK * 0.45, grain=X)


def shelf(m, x0, x1, y, zf, depth, col=BOARD * 0.7):
    m.box((x0, y - 0.03, zf - depth), (x1, y, zf), 'V2_Wood', col, grain=X, skip=('-z',))


def bars(m, x0, x1, y0, y1, z0, z1, pitch, bw, col=DARK):
    n = int((x1 - x0) / pitch)
    off = (x1 - x0 - (n - 1) * pitch) / 2
    for k in range(n):
        x = x0 + off + k * pitch
        m.box((x - bw / 2, y0, z0), (x + bw / 2, y1, z1), 'V2_Wood', col, grain=Y, skip=('+y', '-y', '-z'))


def roof_y(z):
    return RIDGE - PITCH * abs(z)


def main_roof(m, lod):
    x0, x1 = -HW - OV_G, HW + OV_G
    S = (HD + OV_E) * SEC
    for sgn in (1, -1):
        dsl = norm((0.0, -PITCH, float(sgn)))
        n = norm((0.0, 1.0, PITCH * sgn))
        o = (0.0, RIDGE, 0.0)
        K.tile_roof(m, o, dsl, n, x0, x1, S, KW, lod, u_sign=float(sgn), ends=(lod == 0))
        # 野地裏（仰視面，全面）
        uo = add(o, mul(n, -0.15))
        m.grid(lambda i, j: add(add(uo, mul(X, x0 + (x1 - x0) * i)), mul(dsl, S * j)),
               lambda i, j: ((x0 + (x1 - x0) * i) / TILE['V2_Wood'], S * j / TILE['V2_Wood']), 1, 1,
               'V2_Wood', DARK * 0.55, mul(n, -1.0), smooth=False)
        # 鼻隱（簷口板）
        e0 = add(add(o, mul(X, x0)), mul(dsl, S))
        e1 = add(add(o, mul(X, x1)), mul(dsl, S))
        # 鼻隱：蓋住瓦面與野地裏之間的縫（瓦面最高 amp＋step ≈ +0.05、野地裏 −0.15）
        m.beam(add(e0, mul(n, -0.05)), add(e1, mul(n, -0.05)), 0.05, 0.22, 'V2_Wood', DARK * 0.9, up=n)
        # 破風板（兩山）
        for xs in (x0, x1):
            a = add(add(o, mul(X, xs)), mul(n, -0.06))
            b = add(add(add(o, mul(X, xs)), mul(dsl, S)), mul(n, -0.06))
            m.beam(add(a, mul(dsl, -0.02)), b, 0.06, 0.26, 'V2_Wood', DARK * 0.85, up=n)
        if lod == 0:
            # 垂木鼻：壁線到簷口之間，每 0.45 m
            zw, ze = HD * sgn, (HD + OV_E - 0.06) * sgn
            k = int((x1 - x0) / 0.45)
            for i in range(k + 1):
                xx = x0 + 0.12 + i * (x1 - x0 - 0.24) / k
                a = (xx, roof_y(zw) - 0.19, zw)
                b = (xx, roof_y(ze) - 0.19, ze)
                m.beam(a, b, 0.07, 0.08, 'V2_Wood', DARK * 0.8, up=Y)
    # 棟：熨斗積＋冠瓦＋兩端巴
    m.box((x0 - 0.02, RIDGE - 0.08, -0.16), (x1 + 0.02, RIDGE + 0.08, 0.16), 'V2_Kawara', 0.62, grain=X)
    seg = 12 if lod == 0 else 8
    m.cyl((x0 - 0.02, RIDGE + 0.08, 0), (x1 + 0.02, RIDGE + 0.08, 0), 0.11, 0.11, seg, 'V2_Kawara', 0.55,
          caps=(lod == 0, lod == 0))
    if lod == 0:
        for sx in (-1, 1):
            xe = (x1 + 0.03) * sx
            m.cyl((xe - 0.03 * sx, RIDGE + 0.02, 0), (xe + 0.02 * sx, RIDGE + 0.02, 0), 0.17, 0.17, 14,
                  'V2_Kawara', 0.5)


def hisashi(m, lod):
    x0, x1 = -HW - 0.07, HW + 0.07
    dsl = norm((0.0, -PITCH, 1.0))
    n = norm((0.0, 1.0, PITCH))
    o = (0.0, HIS_Y, HD)
    S = HIS_D * SEC
    K.tile_roof(m, o, dsl, n, x0, x1, S, KW, lod, u_sign=1.0, ends=(lod == 0))
    uo = add(o, mul(n, -0.10))
    m.grid(lambda i, j: add(add(uo, mul(X, x0 + (x1 - x0) * i)), mul(dsl, S * j)),
           lambda i, j: ((x0 + (x1 - x0) * i) / TILE['V2_Wood'], S * j / TILE['V2_Wood']), 1, 1,
           'V2_Wood', DARK * 0.55, mul(n, -1.0), smooth=False)
    e0 = add(add(o, mul(X, x0)), mul(dsl, S))
    e1 = add(add(o, mul(X, x1)), mul(dsl, S))
    m.beam(add(e0, mul(n, -0.045)), add(e1, mul(n, -0.045)), 0.045, 0.16, 'V2_Wood', DARK * 0.9, up=n)
    for xs in (x0, x1):   # 兩端蓋板
        a = add(add(o, mul(X, xs)), mul(n, -0.03))
        b = add(add(add(o, mul(X, xs)), mul(dsl, S)), mul(n, -0.03))
        m.beam(a, b, 0.04, 0.14, 'V2_Wood', DARK * 0.85, up=n)
    ze = HD + HIS_D - 0.10
    # 出桁＋腕木
    m.box((x0, 2.10, ze - 0.06), (x1, 2.24, ze + 0.06), 'V2_Wood', DARK, grain=X)
    for xa in (-HW + 0.075, -XP, XP, HW - 0.075):
        m.box((xa - 0.045, 2.12, HD), (xa + 0.045, 2.24, ze + 0.10), 'V2_Wood', DARK, grain=Z, skip=('-z',))


def facade_1f(m, lod):
    zf = HD
    # 柱（前面四支）
    for xa, full in ((-HW + 0.075, True), (-XP, False), (XP, False), (HW - 0.075, True)):
        m.box((xa - 0.075, PLINTH, zf - 0.15), (xa + 0.075, PLATE[1] if full else LINTEL[0], zf),
              'V2_Wood', DARK, grain=Y, skip=('-y',))
    # 差鴨居
    m.box((-HW, LINTEL[0], zf - 0.14), (HW, LINTEL[1], zf + 0.01), 'V2_Wood', DARK, grain=X)
    # 左開間：腰板＋格子＋書架
    xl0, xl1 = -HW + 0.15, -XP - 0.075
    recess(m, xl0, xl1, 0.86, LINTEL[0], zf - 0.02, 0.62,
           [(0.86, 1.24, 0), (1.27, 1.66, 1), (1.69, 2.04, 2), (2.07, LINTEL[0], 3)])
    for y in (1.27, 1.69, 2.07):
        shelf(m, xl0, xl1, y, zf - 0.02, 0.62)
    fz(m, xl0, xl1, PLINTH, 0.80, zf - 0.03, 'V2_Wood', BOARD * 0.8, grain=Y)
    m.box((xl0, 0.80, zf - 0.08), (xl1, 0.86, zf), 'V2_Wood', DARK, grain=X)
    bars(m, xl0 + 0.02, xl1 - 0.02, 0.86, LINTEL[0], zf - 0.06, zf - 0.01, 0.10, 0.045)
    for y in (1.40, 2.00):
        m.box((xl0, y, zf - 0.065), (xl1, y + 0.03, zf - 0.005), 'V2_Wood', DARK, grain=X, skip=('-z',))
    # 中開間：店內＋障子戸＋暖簾
    xc0, xc1 = -XP + 0.075, XP - 0.075
    recess(m, xc0, xc1, PLINTH, LINTEL[0], zf - 0.06, 2.40,
           [(PLINTH, 0.84, 0), (0.84, 1.36, 1), (1.36, 1.88, 2), (1.88, LINTEL[0], 3)],
           side_region=RG['spines'], floor_col=0.36)
    m.box((xc0, 0.30, zf - 0.10), (xc1, 0.35, zf + 0.02), 'V2_Wood', DARK, grain=X)    # 敷居
    for (a, b) in ((xc0, -DOOR_W / 2), (DOOR_W / 2, xc1)):
        fz(m, a, b, 0.35, 0.72, zf - 0.05, 'V2_Wood', BOARD * 0.75, grain=Y)
        fz(m, a, b, 0.72, LINTEL[0] - 0.02, zf - 0.05, AMAT, 0.95, RG['shoji'])
        for (p, q) in ((a, a + 0.04), (b - 0.04, b)):
            m.box((p, 0.35, zf - 0.06), (q, LINTEL[0], zf - 0.02), 'V2_Wood', DARK, grain=Y, skip=('-z',))
        for y in (0.70, LINTEL[0] - 0.05):
            m.box((a, y, zf - 0.06), (b, y + 0.04, zf - 0.02), 'V2_Wood', DARK, grain=X, skip=('-z',))
    # 暖簾：5 片，竿 2.36，下緣 1.58
    zn = zf + 0.12
    m.cyl((-1.72, 2.37, zn), (1.72, 2.37, zn), 0.016, 0.016, 8 if lod == 0 else 6, 'V2_Wood', DARK)
    pw = (3.30 - 4 * 0.025) / 5
    for k in range(5):
        a = -1.65 + k * (pw + 0.025)
        dz = 0.012 * math.sin(k * 1.7)
        fz(m, a, a + pw, 1.58, 2.36, zn + dz, AMAT, 1.0, rsub(RG['noren'], k / 5, 0, (k + 1) / 5, 1))
        fz(m, a, a + pw, 1.58, 2.36, zn + dz - 0.004, AMAT, 1.0, RG['noren_back'], back=True)
    # 右開間：縁台＋開放書架
    xr0, xr1 = XP + 0.075, HW - 0.15
    recess(m, xr0, xr1, 0.62, LINTEL[0], zf - 0.02, 0.55, [(0.62, 1.20, 0), (1.23, 1.80, 1), (1.83, LINTEL[0], 2)])
    for y in (1.23, 1.83):
        shelf(m, xr0, xr1, y, zf - 0.02, 0.55)
    m.box((xr0, 0.56, zf - 0.57), (xr1, 0.62, zf + 0.25), 'V2_Wood', BOARD * 0.7, grain=X)
    fz(m, xr0, xr1, -0.08, 0.56, zf + 0.23, 'V2_Wood', BOARD * 0.62, grain=Y)
    fx(m, zf, zf + 0.23, -0.08, 0.56, xr0, 'V2_Wood', BOARD * 0.55, neg=True)
    fx(m, zf, zf + 0.23, -0.08, 0.56, xr1, 'V2_Wood', BOARD * 0.55)
    m.quad((xr0, 0.30, zf + 0.23), (xr1, 0.30, zf + 0.23), (xr1, 0.30, zf), (xr0, 0.30, zf), 'V2_Wood', 0.2)
    if lod <= 1:
        # 平積みの本（上面＝書封）
        for i, (x, wdt, h) in enumerate(((2.35, 0.34, 0.12), (2.95, 0.30, 0.18), (3.55, 0.36, 0.09))):
            c = (x, 0.62 + h / 2, zf + 0.08)
            m.abox(c, (wdt / 2, h / 2, 0.12), AMAT,
                   {'+y': rsub(RG['covers'], i / 4, 0, (i + 1) / 4, 1), '*': sw('#B8AE96')}, 1.0, skip=('-y',))
        # 花瓶＋花
        m.cyl((4.10, 0.62, zf + 0.10), (4.10, 0.84, zf + 0.10), 0.075, 0.055, 10, AMAT, 1.0,
              caps=(False, True), uv_atlas=sw('#4A4E55'))
        m.abox((4.10, 0.93, zf + 0.10), (0.11, 0.09, 0.10), AMAT, {'*': RG['foliage']}, 1.0, skip=('-y',))
    # 踏石
    m.box((-0.85, -0.14, zf), (0.85, 0.14, zf + 0.45), 'V2_Stone', 0.92, skip=('-y', '-z'))
    # 貸本牌（左柱）
    m.abox((-XP, 1.72, zf + 0.02), (0.09, 0.27, 0.015), AMAT, {'+z': RG['kashihon'], '*': RG['sign_wood']}, 1.0)
    m.box((-XP - 0.004, 1.99, zf + 0.012), (-XP + 0.004, 2.20, zf + 0.02), 'V2_Wood', 0.2)
    if lod <= 1:
        # 行燈（右庇下）
        c = (4.05, 2.22, zf + 0.46)           # 下緣 2.04：人走庇下不碰頭
        m.abox(c, (0.13, 0.18, 0.13), AMAT, {'*': RG['lantern']}, 1.0, skip=('+y', '-y'))
        for dy in (0.19, -0.19):
            m.box((c[0] - 0.15, c[1] + dy - 0.02, c[2] - 0.15), (c[0] + 0.15, c[1] + dy + 0.02, c[2] + 0.15),
                  'V2_Wood', 0.25)
        m.box((c[0] - 0.012, c[1] + 0.21, c[2] - 0.012), (c[0] + 0.012, 2.50, c[2] + 0.012), 'V2_Wood', 0.2)
        m.box((c[0] - 0.02, 2.50, zf), (c[0] + 0.02, 2.55, c[2] + 0.03), 'V2_Wood', DARK)
        # 花盆＋木箱（左）
        m.box((-4.45, -0.14, zf + 0.10), (-3.35, 0.34, zf + 0.52), 'V2_Wood', BOARD * 0.62, skip=('-y',))
        m.abox((-3.90, 0.46, zf + 0.31), (0.52, 0.13, 0.19), AMAT, {'*': RG['foliage']}, 1.0, skip=('-y',))
        m.box((-3.20, -0.14, zf + 0.10), (-2.15, 0.52, zf + 0.62), 'V2_Wood', BOARD * 0.5, skip=('-y', '+y'))
        m.box((-3.23, 0.52, zf + 0.07), (-2.12, 0.58, zf + 0.65), 'V2_Wood', BOARD * 0.42)
        for y in (0.10, 0.30):
            m.box((-3.20, y, zf + 0.62), (-2.15, y + 0.04, zf + 0.64), 'V2_Wood', DARK, grain=X, skip=('-z',))


def facade_2f(m, lod):
    zf = HD
    zw = zf - 0.02
    y0, y1 = LINTEL[1], PLATE[0]
    # 灰泥牆（挖兩個窗洞）
    xa, xb = -HW + 0.15, HW - 0.15
    fz(m, xa, xb, y0, WIN_Y[0], zw, 'V2_Plaster', 0.97)
    fz(m, xa, xb, WIN_Y[1], y1, zw, 'V2_Plaster', 0.97)
    for (a, b) in ((xa, WIN_L[0]), (WIN_L[1], WIN_R[0]), (WIN_R[1], xb)):
        fz(m, a, b, WIN_Y[0], WIN_Y[1], zw, 'V2_Plaster', 0.97)
    m.box((-HW - OV_G, PLATE[0], zf - 0.16), (HW + OV_G, PLATE[1], zf + 0.01), 'V2_Wood', DARK, grain=X)
    for (a, b) in (WIN_L, WIN_R):
        fz(m, a, b, WIN_Y[0], WIN_Y[1], zf - 0.12, AMAT, 0.55, RG['paper'])
        fx(m, zf - 0.12, zw, WIN_Y[0], WIN_Y[1], a, 'V2_Wood', DARK * 0.8)
        fx(m, zf - 0.12, zw, WIN_Y[0], WIN_Y[1], b, 'V2_Wood', DARK * 0.8, neg=True)
        m.box((a - 0.06, WIN_Y[1], zf - 0.06), (b + 0.06, WIN_Y[1] + 0.06, zf + 0.03), 'V2_Wood', DARK, grain=X)
        m.box((a - 0.06, WIN_Y[0] - 0.06, zf - 0.06), (b + 0.06, WIN_Y[0], zf + 0.04), 'V2_Wood', DARK, grain=X)
        for (p, q) in ((a - 0.06, a), (b, b + 0.06)):
            m.box((p, WIN_Y[0], zf - 0.06), (q, WIN_Y[1], zf + 0.03), 'V2_Wood', DARK, grain=Y, skip=('+y', '-y'))
        if lod <= 1:
            bars(m, a, b, WIN_Y[0], WIN_Y[1], zf - 0.05, zf, 0.075, 0.035)
            m.box((a, 3.27, zf - 0.055), (b, 3.30, zf + 0.005), 'V2_Wood', DARK, grain=X, skip=('-z',))
    # 看板：自然邊（超橢圓＋小起伏），正面 atlas、側／背素木；兩個托木
    cx, cy, sw_, sh = SIGN
    zb, zfr = zf + 0.04, zf + 0.10
    nseg = 28 if lod == 0 else 14
    pts = []
    for i in range(nseg):
        t = 2 * math.pi * i / nseg
        c, s = math.cos(t), math.sin(t)
        r = 1.0 / (abs(c) ** 4 + abs(s) ** 4) ** 0.25
        r *= 1 + 0.035 * math.sin(3 * t + 0.4) + 0.02 * math.sin(7 * t + 1.3)
        pts.append((c * r * sw_ / 2, s * r * sh / 2))
    u0, v0, u1, v1 = RG['sign']

    def suv(p):
        return (u0 + (p[0] / sw_ + 0.5) * (u1 - u0), v0 + (0.5 - p[1] / sh) * (v1 - v0))
    front = [(cx + p[0], cy + p[1], zfr) for p in pts]
    m.face(m.verts(front), AMAT, [suv(p) for p in pts], 1.0)
    back = list(reversed([(cx + p[0], cy + p[1], zb) for p in pts]))
    m.face(m.verts(back), AMAT, [suv(p) for p in reversed(pts)], 0.8)
    wu0, wv0, wu1, wv1 = RG['sign_wood']
    for i in range(nseg):
        p, q = pts[i], pts[(i + 1) % nseg]
        m.face(m.verts([(cx + p[0], cy + p[1], zb), (cx + q[0], cy + q[1], zb),
                        (cx + q[0], cy + q[1], zfr), (cx + p[0], cy + p[1], zfr)]), AMAT,
               [(wu0, wv1), (wu1, wv1), (wu1, wv0), (wu0, wv0)], 0.8)
    for bx in (-0.62, 0.62):
        m.box((cx + bx - 0.04, cy - sh / 2 - 0.10, zf), (cx + bx + 0.04, cy - sh / 2 + 0.02, zb + 0.02),
              'V2_Wood', DARK, skip=('-z',))


def sides_back(m, lod):
    for sx in (1, -1):
        xw = (HW - 0.02) * sx
        neg = sx < 0
        fx(m, -HD + 0.15, HD - 0.15, PLINTH, 2.62, xw, 'V2_Wood', BOARD * 0.8, grain=Z, neg=neg)
        fx(m, -HD + 0.15, HD - 0.15, 2.72, PLATE[0], xw, 'V2_Plaster', 0.95, neg=neg)
        # 妻壁（三角；+x 側照此順序即朝 +x，−x 側反序）
        tri = [(xw, 3.70, HD - 0.15), (xw, 3.70, -HD + 0.15), (xw, RIDGE - 0.16, 0.0)]
        if sx < 0:
            tri = tri[::-1]
        m.poly(tri, 'V2_Plaster', 0.93)
        xo = HW * sx
        xi = (HW - 0.15) * sx
        lo, hi = min(xo, xi), max(xo, xi)
        m.box((lo, 2.62, -HD), (hi + 0.01 if sx > 0 else hi, 2.72, HD), 'V2_Wood', DARK, grain=Z)
        m.box((lo, PLATE[0], -HD - OV_E + 0.1), (hi, PLATE[1], HD + 0.0), 'V2_Wood', DARK, grain=Z)
        m.box((lo, PLINTH, -0.075), (hi, PLATE[0], 0.075), 'V2_Wood', DARK, grain=Y, skip=('-y',))
        # 後角柱
        m.box(((HW - 0.15) * sx if sx > 0 else -HW, PLINTH, -HD), (HW if sx > 0 else -HW + 0.15, PLATE[1], -HD + 0.15),
              'V2_Wood', DARK, grain=Y, skip=('-y',))
    zb = -HD + 0.02
    fz(m, -HW + 0.15, HW - 0.15, PLINTH, 2.62, zb, 'V2_Wood', BOARD * 0.8, grain=X, back=True)
    fz(m, -HW + 0.15, HW - 0.15, 2.72, PLATE[0], zb, 'V2_Plaster', 0.95, back=True)
    m.box((-HW, 2.62, -HD), (HW, 2.72, -HD + 0.15), 'V2_Wood', DARK, grain=X)
    m.box((-HW - OV_G, PLATE[0], -HD - 0.01), (HW + OV_G, PLATE[1], -HD + 0.16), 'V2_Wood', DARK, grain=X)
    m.box((-0.075, PLINTH, -HD - 0.01), (0.075, PLATE[0], -HD + 0.15), 'V2_Wood', DARK, grain=Y, skip=('-y',))
    # 勝手口（後面右側，外看在左）：板戸＋框＋踏石
    zo = -HD - 0.01
    fz(m, 1.55, 2.45, PLINTH, 2.12, zo - 0.005, 'V2_Wood', BOARD * 0.62, grain=Y, back=True)
    for (p0, p1) in ((1.49, 1.55), (2.45, 2.51)):
        m.box((p0, PLINTH, zo - 0.05), (p1, 2.18, zo), 'V2_Wood', DARK, grain=Y, skip=('+z', '-y'))
    m.box((1.49, 2.12, zo - 0.05), (2.51, 2.18, zo), 'V2_Wood', DARK, grain=X, skip=('+z',))
    for y in (0.75, 1.25, 1.75):
        m.box((1.58, y, zo - 0.03), (2.42, y + 0.03, zo - 0.005), 'V2_Wood', DARK, grain=X, skip=('+z',))
    m.box((1.60, -0.12, zo - 0.40), (2.40, 0.14, zo), 'V2_Stone', 0.9, skip=('-y', '+z'))
    # 二樓小窗：後面一扇、兩山各一扇（貼在灰泥面外 1 cm；紙窗＋木框＋豎格子）
    small_window(m, lod, 'z', -HD - 0.01, -1.0, 0.8, -1.0)
    for sx in (1, -1):
        small_window(m, lod, 'x', (HW + 0.01) * sx, 0.0, 1.0, float(sx))


def small_window(m, lod, axis, plane, c, w, sgn):
    """plane＝牆外表面座標；c／w＝沿牆中心與寬；sgn＝外法線方向（+1／−1）。y 2.98–3.42。"""
    y0, y1 = 2.98, 3.42

    def P(t, y, d):          # t＝沿牆、d＝離牆外推
        return (plane + d * sgn, y, t) if axis == 'x' else (t, y, plane + d * sgn)
    a, b = c - w / 2, c + w / 2
    # 紙窗（外看：左下→右下→右上→左上）
    if (axis == 'z') == (sgn > 0):
        q = [P(a, y0, 0.005), P(b, y0, 0.005), P(b, y1, 0.005), P(a, y1, 0.005)]
    else:
        q = [P(b, y0, 0.005), P(a, y0, 0.005), P(a, y1, 0.005), P(b, y1, 0.005)]
    m.rect_uv(q[0], q[1], q[2], q[3], AMAT, RG['paper'], 0.5)
    ax_t = Z if axis == 'x' else X
    ax_n = X if axis == 'x' else Z

    def bx(t0, t1, ya, yb, d0, d1):
        lo = [0, 0, 0]
        hi = [0, 0, 0]
        ti = 2 if axis == 'x' else 0
        ni = 0 if axis == 'x' else 2
        lo[ti], hi[ti] = t0, t1
        lo[1], hi[1] = ya, yb
        n0, n1 = plane + d0 * sgn, plane + d1 * sgn
        lo[ni], hi[ni] = min(n0, n1), max(n0, n1)
        m.box(tuple(lo), tuple(hi), 'V2_Wood', DARK, grain=ax_t if t1 - t0 > yb - ya else Y)
    bx(a - 0.06, b + 0.06, y1, y1 + 0.06, 0.0, 0.06)
    bx(a - 0.06, b + 0.06, y0 - 0.06, y0, 0.0, 0.07)
    bx(a - 0.06, a, y0, y1, 0.0, 0.06)
    bx(b, b + 0.06, y0, y1, 0.0, 0.06)
    if lod == 0:
        n = int(w / 0.09)
        for k in range(1, n):
            t = a + k * w / n
            bx(t - 0.015, t + 0.015, y0, y1, 0.01, 0.045)


def gutters(m, lod):
    """概念圖兩側落水管：主屋前簷軒樋（半圓）＋兩端竪樋落地（在庇端外側）。
    材質上限 5（§14.8）→ 金屬不另開 V2_Metal，用 atlas 灰色票 #4A4E55。"""
    ze = HD + OV_E + 0.03
    ye = roof_y(HD + OV_E) - 0.16
    seg = 8 if lod == 0 else 6
    gm = sw('#4A4E55')
    m.cyl((-HW - OV_G, ye, ze), (HW + OV_G, ye, ze), 0.06, 0.06, seg, AMAT, 0.8, caps=(False, False),
          arc=(-math.pi * 0.5, math.pi * 0.5), uv_atlas=gm)          # 下半圓（開口朝上）
    m.rect_uv((-HW - OV_G, ye, ze + 0.06), (HW + OV_G, ye, ze + 0.06), (HW + OV_G, ye, ze - 0.06),
              (-HW - OV_G, ye, ze - 0.06), AMAT, gm, 0.35)                  # 開口蓋（俯視不穿透）
    for sx in (-1, 1):
        x = (HW + 0.17) * sx
        m.cyl((x, ye, ze), (x, -0.16, ze), 0.04, 0.04, seg, AMAT, 0.75, caps=(False, False), uv_atlas=gm)
        m.cyl((x, 0.02, ze), (x + 0.10 * sx, -0.14, ze + 0.10), 0.045, 0.045, seg, AMAT, 0.75, caps=(False, True),
              uv_atlas=gm)


def build(lod):
    m = K.Mesh('Suzunaan_LOD%d' % lod, MATS, TILE)
    m.box((-HW, BOT, -HD), (HW, PLINTH, HD), 'V2_Stone', 0.85, skip=('-y',))
    if lod <= 1:
        facade_1f(m, lod)
        facade_2f(m, lod)
        sides_back(m, lod)
        hisashi(m, lod)
        main_roof(m, lod)
        gutters(m, lod)
    else:
        # 遠景：牆體一盒、1F 深色店面、2F 灰泥、看板與暖簾兩片、瓦庇與屋頂平面
        m.box((-HW + 0.02, PLINTH, -HD + 0.02), (HW - 0.02, PLATE[1], HD - 0.02), 'V2_Plaster', 0.9,
              skip=('-y', '+y', '+z'))
        fz(m, -HW + 0.02, HW - 0.02, PLINTH, LINTEL[1], HD - 0.02, 'V2_Wood', DARK * 0.8, grain=X)
        fz(m, -HW + 0.02, HW - 0.02, LINTEL[1], PLATE[1], HD - 0.02, 'V2_Plaster', 0.95)
        cx, cy, sw_, sh = SIGN
        fz(m, cx - sw_ / 2, cx + sw_ / 2, cy - sh / 2, cy + sh / 2, HD + 0.08, AMAT, 1.0, RG['sign'])
        fz(m, -1.65, 1.65, 1.58, 2.36, HD + 0.12, AMAT, 1.0, RG['noren'])
        for sx in (1, -1):
            xw = (HW - 0.02) * sx
            tri = [(xw, PLATE[1] - 0.02, HD - 0.02), (xw, PLATE[1] - 0.02, -HD + 0.02), (xw, RIDGE - 0.16, 0.0)]
            m.poly(tri[::-1] if sx < 0 else tri, 'V2_Plaster', 0.9)
        hisashi_lod2(m)
        main_roof_lod2(m)
    return m


def hisashi_lod2(m):
    dsl = norm((0.0, -PITCH, 1.0))
    n = norm((0.0, 1.0, PITCH))
    K.tile_roof(m, (0.0, HIS_Y, HD), dsl, n, -HW - 0.07, HW + 0.07, HIS_D * SEC, KW, 2)
    uo = (0.0, HIS_Y - 0.10, HD)
    e = add(uo, mul(dsl, HIS_D * SEC))
    m.quad((-HW, uo[1], uo[2]), (HW, uo[1], uo[2]), (HW, e[1], e[2]), (-HW, e[1], e[2]), 'V2_Wood', DARK * 0.5)


def main_roof_lod2(m):
    S = (HD + OV_E) * SEC
    for sgn in (1, -1):
        dsl = norm((0.0, -PITCH, float(sgn)))
        n = norm((0.0, 1.0, PITCH * sgn))
        K.tile_roof(m, (0.0, RIDGE, 0.0), dsl, n, -HW - OV_G, HW + OV_G, S, KW, 2, u_sign=float(sgn))
        uo = add((0.0, RIDGE, 0.0), mul(n, -0.15))
        m.grid(lambda i, j: add(add(uo, mul(X, (-HW - OV_G) + 2 * (HW + OV_G) * i)), mul(dsl, S * j)),
               lambda i, j: (i, j), 1, 1, 'V2_Wood', DARK * 0.5, mul(n, -1.0), smooth=False)
    m.box((-HW - OV_G, RIDGE - 0.08, -0.16), (HW + OV_G, RIDGE + 0.18, 0.16), 'V2_Kawara', 0.58, grain=X)


def main():
    K.clear_scene(bpy)
    bm = K.blender_mats(bpy, MATS)
    objs = []
    stats = {}
    for lod in (0, 1, 2):
        m = build(lod)
        objs.append(m.to_blender(bpy, bmats=bm))
        stats['LOD%d' % lod] = m.tris()
        if lod == 0:
            xs = [p[0] for p in m.v]
            ys = [p[1] for p in m.v]
            zs = [p[2] for p in m.v]
            stats['aabb'] = [[round(min(xs), 3), round(min(ys), 3), round(min(zs), 3)],
                             [round(max(xs), 3), round(max(ys), 3), round(max(zs), 3)]]
    K.export_glb(bpy, OUT + '/src/suzunaan.glb', objs)
    zf = HD
    spec = {
        '_note': '鈴奈庵 Hero 資產規格（build_suzunaan.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、'
                 'verify_village_v2_hero_gate.gd 讀取）。尺寸 authority＝P4 greybox B_P_LM_SUZUNAAN。',
        'id': 'suzunaan', 'landmark': 'LANDMARK_SUZUNAAN', 'kind': 'hero', 'budget_class': '鈴奈庵',
        'glb': 'res://assets/village_v2/suzunaan/src/suzunaan.glb',
        'scene': 'res://assets/village_v2/suzunaan/suzunaan.scn',
        'lod_objects': ['Suzunaan_LOD0', 'Suzunaan_LOD1', 'Suzunaan_LOD2'],
        'lod_ranges_m': [0, 40, 110, 600],
        'budget': {'lod0': 60000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': {k: (ML[k]['tres'] if k in ML else 'res://assets/village_v2/suzunaan/V2_Suzunaan.tres')
                      for k in MATS},
        'spec': {'width_m': W, 'depth_m': D, 'eave_m': EAVE, 'ridge_m': round(RIDGE, 3), 'plinth_m': PLINTH,
                 'foundation_bottom_m': BOT, 'hisashi_m': 2.7, 'hisashi_depth_m': HIS_D, 'ov_eave_m': OV_E,
                 'ov_gable_m': OV_G, 'door_m': [DOOR_W, DOOR_H], 'floor_m': PLINTH,
                 'door_clear_m': [DOOR_W, round(LINTEL[0] - PLINTH, 3)]},
        'gate_spec': {
            # 放置：與 P4 灰盒同一 transform（原點＝footprint 中心、y＝footprint 內最高地面、+z＝正面）
            'placement': 'greybox', 'anchor': 'Landmarks/LANDMARK_SUZUNAAN', 'replaces': 'Greybox',
            'p4_id': 'B_P_LM_SUZUNAAN', 'parcel': 'P_LM_SUZUNAAN', 'road': 'MainStreet',
            'size': {'x_half_max': HW + OV_G + 0.12, 'z_min': -(HD + OV_E + 0.12), 'z_max': HD + HIS_D + 0.12,
                     'top': [round(RIDGE, 3), round(RIDGE + 0.30, 3)], 'bottom': BOT},
            'body': {'w': W, 'd': D, 'eave': EAVE, 'ridge': round(RIDGE, 3), 'plinth': PLINTH},
            'door_clear': {'h': round(LINTEL[0] - PLINTH, 3), 'w': round(2 * (XP - 0.075), 3), 'min_h': 1.9, 'min_w': 1.2},
            # 地面接觸件：局部 xz 矩形、底、頂、容許埋深（另加地塊高低差）
            'ground': [
                {'name': '台基', 'rect': [-HW, -HD, HW, HD], 'bottom': BOT, 'top': PLINTH, 'embed_max': 0.50},
                {'name': '踏石', 'rect': [-0.85, zf, 0.85, zf + 0.45], 'bottom': -0.14, 'top': 0.14, 'embed_max': 0.25},
                {'name': '縁台前板', 'rect': [XP + 0.075, zf + 0.20, HW - 0.15, zf + 0.25], 'bottom': -0.08, 'top': 0.62,
                 'embed_max': 0.25},
                {'name': '花盆', 'rect': [-4.45, zf + 0.10, -3.35, zf + 0.52], 'bottom': -0.14, 'top': 0.34,
                 'embed_max': 0.25},
                {'name': '木箱', 'rect': [-3.20, zf + 0.10, -2.15, zf + 0.62], 'bottom': -0.14, 'top': 0.52,
                 'embed_max': 0.25},
                {'name': '勝手口踏石', 'rect': [1.60, -HD - 0.41, 2.40, -HD - 0.01], 'bottom': -0.12, 'top': 0.14,
                 'embed_max': 0.25},
                {'name': '竪樋左', 'rect': [-(HW + 0.27), HD + OV_E, -(HW + 0.13), HD + OV_E + 0.18], 'bottom': -0.18,
                 'top': 0.30, 'embed_max': 0.30},
                {'name': '竪樋右', 'rect': [HW + 0.13, HD + OV_E, HW + 0.27, HD + OV_E + 0.18], 'bottom': -0.18,
                 'top': 0.30, 'embed_max': 0.30}],
            # 庇下步行帶：地面→地面＋1.95 m 不得碰到任何 LOD0 面（頭上淨空）；另報最低淨空
            'walkway': {'rect': [-HW, zf + 0.65, HW, zf + HIS_D + 0.30], 'head': 1.95, 'min_clear': 2.0, 'step': 0.25},
            # 入口前站點：玩家膠囊放這裡不得與資產碰撞；膠囊移到台基內必須被擋
            'entry': [0.0, zf + 0.95], 'inside': [0.0, 0.0]},
        'collision': [
            {'type': 'box', 'name': 'Body', 'center': [0, (BOT + EAVE) / 2, 0], 'size': [W, EAVE - BOT, D]},
            # 踏石：前緣斜面（凸殼），膠囊可直接走上去
            {'type': 'convex', 'name': 'Step', 'center': [0, 0, 0], 'points': [
                [sx * 0.85, y, z] for sx in (-1, 1) for (y, z) in (
                    (-0.14, zf), (0.14, zf), (0.14, zf + 0.38), (-0.14, zf + 0.62))]},
            {'type': 'box', 'name': 'Counter', 'center': [(XP + 0.075 + HW - 0.15) / 2, 0.27, zf + 0.125],
             'size': [HW - 0.15 - XP - 0.075, 0.70, 0.25]},
            {'type': 'box', 'name': 'Planter', 'center': [-3.90, 0.18, zf + 0.31], 'size': [1.10, 0.64, 0.42]},
            {'type': 'box', 'name': 'Chest', 'center': [-2.675, 0.20, zf + 0.36], 'size': [1.05, 0.68, 0.52]},
            {'type': 'box', 'name': 'BackStep', 'center': [2.0, 0.0, -HD - 0.21], 'size': [0.80, 0.26, 0.40]}],
        'measured_blender': stats,
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[SUZUNAAN]', stats)


main()
