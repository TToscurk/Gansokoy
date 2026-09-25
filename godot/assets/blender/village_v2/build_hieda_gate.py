"""稗田邸 大宅門（LANDMARK_HIEDA_GATE）Hero — 人間之里 V2 P5 R6 新資產（全新程序化建模）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_hieda_gate.py

外觀 authority：docs/reference/重點地標/裨田邸正面.PNG（使用者 2026-09-26 裁示選 B：用這張的造型，木色＋灰瓦，不做紅色）。
vision brief：兩根粗主柱（石礎）＋兩根細外柱夾窄側間；主屋根切妻、棟與牆平行、灰瓦、鬼瓦；兩側間各一片較低的小屋根；
側間閉合板戶；中央開口兩扉向內全開；兩側灰泥袖牆（石積腰、瓦頂）接在側間外柱、位於小屋根簷下。
屋根三層：主屋根 → 側間小屋根 → 袖牆瓦頂。燈籠、石段、整圈圍牆不在本輪（延 P6／P10）。
尺寸 authority：P0 LANDMARK_HIEDA_GATE（box 7 × 5 × 2，寬×高×深；沒有 P4 灰盒）＋地塊 P_LM_HIEDA_GATE（9 × 4）。
  全部（含出簷、袖牆）在 P0 量體內：x ±3.5、z ±1.0、最高點 ≤ 5.0；接地件在地塊內。
座標：Godot；原點＝P0 地標原點（地塊中心）、y 0＝地標節點高度、+z＝正面（南，FarmPath_4 方向；本屋在北 −z）。
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402
from v2_kit import X, Y, Z, add, mul, norm  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/hieda_gate'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
TILE = {k: v['tile_m'] for k, v in ML.items()}
KW = ML['V2_Kawara']
MATS = ['V2_Wood', 'V2_Kawara', 'V2_Stone', 'V2_Plaster', 'V2_Metal']
DARK, BOARD = 0.34, 0.74

# ── 主柱、冠木
PX, PW = 1.25, 0.26               # 主柱心、斷面
PIN = PX - PW / 2                 # 主柱內面（開口半寬）
POST_TOP = 3.05
KABUKI = (2.62, 2.90)             # 冠木（通行淨高＝下緣）
FOOT_TOP, FOOT_BOT = 0.08, -0.25  # 礎石
# ── 主屋根（切妻、棟沿 x、z＝0）
RP = 0.75                         # 坡度
RZ = 0.90                         # 簷（屋面）z
RY_E = 3.30                       # 簷口（屋面）高
RY = RY_E + RP * RZ               # 棟（屋面）
RX = 2.35                         # 破風（屋面）x
SEC = math.sqrt(1 + RP * RP)
# ── 側間、小屋根
OX, OW = 2.20, 0.18               # 外柱心、斷面
BAY_TOP = 2.18                    # 側間板戶上緣（其上灰泥小壁）
C_KETA = 2.62                     # 側間桁
CP, CZ, CY_E = 0.55, 0.72, 2.66   # 小屋根：坡度、簷 z、簷口高
CY = CY_E + CP * CZ
CX0, CX1 = 1.42, 2.62             # 小屋根 x 範圍（內端收在主屋根下）
# ── 袖牆
WX0, WX1 = OX + OW / 2, 3.42      # 袖牆 x
WT = 0.17                         # 灰泥牆半厚
WB = 0.24                         # 石積腰半厚
W_STONE = 0.45
W_TOP = 1.72
WP, WZ, WY_E = 0.60, 0.40, 1.84   # 瓦頂：坡度、簷 z、簷口高
WY = WY_E + WP * WZ
WCX1 = 3.44
# ── 門扉（向內全開，貼在側間背後）
LEAF_T = 0.05
LEAF_W = 0.94
LEAF_Y = (0.10, 2.56)
SILL_TOP = 0.035                  # 敷石頂（地形最高 +0.01）

ONI_H = 0.24
TOP = RY + 0.30 + ONI_H


def roof_x(m, lod, yr, p, ze, x0, x1, ridge=True, oni=True, rafters=True, col=1.0):
    """切妻（棟沿 x、z＝0）：前後兩坡 tile_roof＋野地裏＋簷桁＋破風板；回傳頂高。"""
    sec = math.sqrt(1 + p * p)
    S = ze * sec
    TW = TILE['V2_Wood']
    for sg in (1, -1):
        dsl = norm((0.0, -p, float(sg)))
        n = norm((0.0, 1.0, p * sg))
        o = (0.0, yr, 0.0)
        K.tile_roof(m, o, dsl, n, x0, x1, S, KW, lod, u_sign=float(sg), ends=(lod == 0), col=col)
        uo = add(o, mul(n, -0.12))
        m.grid(lambda i, j: add(add(uo, mul(X, x0 + (x1 - x0) * i)), mul(dsl, S * j)),
               lambda i, j: ((x0 + (x1 - x0) * i) / TW, S * j / TW), 1, 1, 'V2_Wood', DARK * 0.55, mul(n, -1.0),
               smooth=False)
        e0 = add(add(o, mul(X, x0)), mul(dsl, S))
        e1 = add(add(o, mul(X, x1)), mul(dsl, S))
        m.beam(add(e0, mul(n, -0.06)), add(e1, mul(n, -0.06)), 0.05, 0.16, 'V2_Wood', DARK * 0.9, up=n)
        for xs in (x0, x1):   # 破風板
            a = add(add(o, mul(X, xs)), mul(n, -0.05))
            b = add(add(add(o, mul(X, xs)), mul(dsl, S)), mul(n, -0.05))
            m.beam(add(a, mul(dsl, -0.02)), b, 0.05, 0.20, 'V2_Wood', DARK * 0.85, up=n)
        if lod == 0 and rafters:
            k = max(2, int((x1 - x0) / 0.30))
            for i in range(k + 1):
                xx = x0 + 0.10 + i * (x1 - x0 - 0.20) / k
                m.beam((xx, yr - p * 0.12 - 0.16, sg * 0.12), (xx, yr - p * (ze - 0.05) - 0.16, sg * (ze - 0.05)),
                       0.05, 0.06, 'V2_Wood', DARK * 0.8, up=Y)
    top = yr + 0.06
    if ridge:
        m.box((x0 - 0.02, yr - 0.06, -0.11), (x1 + 0.02, yr + 0.10, 0.11), 'V2_Kawara', 0.60, grain=X)
        top = yr + 0.10
        if lod <= 1:
            m.cyl((x0 - 0.02, yr + 0.10, 0), (x1 + 0.02, yr + 0.10, 0), 0.075, 0.075, 10 if lod == 0 else 6,
                  'V2_Kawara', 0.55, caps=(lod == 0, lod == 0))
            top = yr + 0.175
    return top


def gable_face(m, x, yr, p, ze, y_base, sgn, mat='V2_Plaster', col=0.95):
    """妻（x 平面，朝 sgn·x）：五角形——屋面下緣 −0.14 到 y_base。"""
    yb_edge = yr - p * ze - 0.14
    ps = [(x, y_base, -ze + 0.02), (x, y_base, ze - 0.02), (x, max(y_base, yb_edge), ze - 0.02), (x, yr - 0.16, 0.0),
          (x, max(y_base, yb_edge), -ze + 0.02)]
    if yb_edge <= y_base + 1e-3:   # 底邊已高過屋面下緣：三角形（避免重複頂點造成退化面）
        ps = [ps[0], ps[1], ps[3]]
    uvs = [(p_[2] / TILE[mat], p_[1] / TILE[mat]) for p_ in ps]
    n = (float(sgn), 0.0, 0.0)
    a, b, c = ps[0], ps[1], ps[2]
    cr = K.cross(K.sub(b, a), K.sub(c, a))
    if K.dot(cr, n) < 0:
        ps, uvs = ps[::-1], uvs[::-1]
    m.face(m.verts(ps), mat, uvs, col)


def plate_x(m, x0, x1, pts, mat='V2_Kawara', col=0.42):
    """x 向厚板（鬼瓦）：pts＝(z, y) 凸多邊形（逆時針，從 +x 看），厚度 x0..x1。"""
    tl = TILE[mat]
    for x, sgn in ((x1, 1.0), (x0, -1.0)):
        ps = [(x, y, z) for (z, y) in pts]
        uvs = [(z / tl, y / tl) for (z, y) in pts]
        cr = K.cross(K.sub(ps[1], ps[0]), K.sub(ps[2], ps[0]))
        if K.dot(cr, (sgn, 0.0, 0.0)) < 0:
            ps, uvs = ps[::-1], uvs[::-1]
        m.face(m.verts(ps), mat, uvs, col)
    n = len(pts)
    for i in range(n):
        (za, ya), (zb, yb) = pts[i], pts[(i + 1) % n]
        q = [(x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)]
        c = (0.0, sum(p[1] for p in pts) / n, sum(p[0] for p in pts) / n)
        mid = ((x0 + x1) / 2, (ya + yb) / 2, (za + zb) / 2)
        out = K.sub(mid, ((x0 + x1) / 2, c[1], c[2]))
        cr = K.cross(K.sub(q[1], q[0]), K.sub(q[2], q[0]))
        if K.dot(cr, out) < 0:
            q = q[::-1]
        m.face(m.verts(q), mat, [(0, 0), (0.1, 0), (0.1, 0.1), (0, 0.1)], col * 0.9)


def oni_pts(y0, y1, w0, w1, seg=6):
    """鬼瓦輪廓（z, y）：下寬 w0、肩寬 w1、上緣圓弧（逆時針，從 +x 看：z 往 −? 依 plate_x 自動繞序）。"""
    ys = y1 - w1 * 0.6
    pts = [(-w0, y0), (w0, y0), (w1, ys)]
    for k in range(1, seg):
        a = math.pi * k / seg
        pts.append((w1 * math.cos(a), ys + (y1 - ys) * math.sin(a)))
    pts.append((-w1, ys))
    return pts


def gable_over(m, x, sgn, col):
    """主屋根妻（x 平面，朝 sgn·x）：上緣＝主屋根野地裏、下緣＝小屋根瓦面（左右兩片凸四邊形，無縫）。"""
    zi = CZ - 0.02
    top_e = RY - RP * (RZ - 0.10) - 0.15
    ps_by = []
    for sz in (-1, 1):
        ps = [(x, CY + 0.03, 0.0), (x, CY_E + 0.03 + CP * 0.02, sz * zi), (x, top_e, sz * (RZ - 0.10)), (x, RY - 0.16, 0.0)]
        ps_by.append(ps)
    for ps in ps_by:
        n = (float(sgn), 0.0, 0.0)
        cr = K.cross(K.sub(ps[1], ps[0]), K.sub(ps[2], ps[0]))
        if K.dot(cr, n) < 0:
            ps = ps[::-1]
        m.face(m.verts(ps), 'V2_Wood', [(p_[2] / TILE['V2_Wood'], p_[1] / TILE['V2_Wood']) for p_ in ps], col)


def gegyo(m, x, y, sgn):
    """懸魚：破風頂下方的菱形板（暗木）＋金具點。"""
    xq = x + sgn * 0.035
    ps = [(xq, y, -0.14), (xq, y - 0.30, 0.0), (xq, y, 0.14), (xq, y + 0.14, 0.0)]
    n = (float(sgn), 0.0, 0.0)
    cr = K.cross(K.sub(ps[1], ps[0]), K.sub(ps[2], ps[0]))
    if K.dot(cr, n) < 0:
        ps = ps[::-1]
    m.poly(ps, 'V2_Wood', DARK * 0.9, grain=Y)


def posts(m, lod):
    seg = 12
    for sx in (-1, 1):
        x = sx * PX
        m.box((x - 0.23, FOOT_BOT, -0.23), (x + 0.23, FOOT_TOP, 0.23), 'V2_Stone', 0.82, skip=('-y',))
        m.box((x - PW / 2, FOOT_TOP, -PW / 2), (x + PW / 2, POST_TOP, PW / 2), 'V2_Wood', DARK * 1.05, grain=Y,
              skip=('-y',))
        # 控柱（後、細）：門扉背後斜撐不做，僅主柱背面貫
        if lod == 0:
            for yy in (0.30, 2.40):   # 根卷・柱頭金具
                m.box((x - PW / 2 - 0.012, yy, -PW / 2 - 0.012), (x + PW / 2 + 0.012, yy + 0.07, PW / 2 + 0.012),
                      'V2_Metal', 0.55, grain=X)
        # 腕木（柱頭、沿 z 伸出承簷桁）
        m.box((x - 0.08, POST_TOP - 0.16, -0.86), (x + 0.08, POST_TOP, 0.86), 'V2_Wood', DARK, grain=Z)
    # 冠木（木鼻出柱外 0.25）
    m.box((-PX - 0.40, KABUKI[0], -0.15), (PX + 0.40, KABUKI[1], 0.15), 'V2_Wood', DARK, grain=X)
    # 頭貫＋桁（主柱頂）、簷桁（腕木端）
    m.box((-PX - 0.30, POST_TOP - 0.02, -0.12), (PX + 0.30, POST_TOP + 0.16, 0.12), 'V2_Wood', DARK * 0.95, grain=X)
    for sz in (-1, 1):
        m.box((-RX + 0.18, POST_TOP, sz * 0.80 - 0.07), (RX - 0.18, POST_TOP + 0.14, sz * 0.80 + 0.07), 'V2_Wood',
              DARK * 0.9, grain=X)
    # 棟木＋束（妻內露明）
    ry_b = RY - 0.30
    m.box((-RX + 0.06, ry_b - 0.14, -0.08), (RX - 0.06, ry_b, 0.08), 'V2_Wood', DARK * 0.9, grain=X)
    for sx in (-1, 1):
        m.box((sx * PX - 0.06, POST_TOP + 0.16, -0.06), (sx * PX + 0.06, ry_b - 0.14, 0.06), 'V2_Wood', DARK * 0.9,
              grain=Y, skip=('-y', '+y'))
    if lod == 0:
        # 冠木正面的八双金具（兩端）
        for sx in (-1, 1):
            for sz in (-1, 1):
                x0, x1 = sorted((sx * (PX - 0.45), sx * (PX + 0.05)))
                zz = sz * 0.152
                z0, z1 = sorted((zz, zz + sz * 0.01))
                m.box((x0, KABUKI[0] + 0.05, z0), (x1, KABUKI[1] - 0.05, z1), 'V2_Metal', 0.50, grain=X)


def side_bays(m, lod):
    for sx in (-1, 1):
        xo = sx * OX
        # 外柱（立在腰石上）
        m.box((xo - OW / 2, 0.12, -OW / 2), (xo + OW / 2, C_KETA, OW / 2), 'V2_Wood', DARK * 1.05, grain=Y,
              skip=('-y',))
        # 側間：地覆石、板戶（兩面）、上方灰泥小壁、貫
        xa, xb = sorted((sx * (PX + PW / 2), sx * (OX - OW / 2)))
        m.box((xa, -0.20, -0.14), (xb, 0.12, 0.14), 'V2_Stone', 0.80, skip=('-y',))
        m.box((xa, 0.12, -0.035), (xb, BAY_TOP, 0.035), 'V2_Wood', BOARD * 0.62, grain=Y)
        m.box((xa, BAY_TOP, -0.05), (xb, BAY_TOP + 0.08, 0.05), 'V2_Wood', DARK, grain=X)
        m.box((xa, BAY_TOP + 0.08, -0.03), (xb, C_KETA - 0.02, 0.03), 'V2_Plaster', 0.97, grain=X)
        m.box((xa - 0.01, C_KETA - 0.10, -0.08), (xb + 0.01, C_KETA + 0.04, 0.08), 'V2_Wood', DARK, grain=X)
        if lod == 0:
            for sz in (-1, 1):   # 板戶の桟（表裏）＋縦目板
                zz = sz * 0.035
                z0, z1 = sorted((zz, zz + sz * 0.025))
                for yy in (0.45, 1.15, 1.85):
                    m.box((xa + 0.03, yy, z0), (xb - 0.03, yy + 0.07, z1), 'V2_Wood', DARK * 0.9, grain=X)
                for t in (0.33, 0.67):
                    xm = xa + (xb - xa) * t
                    m.box((xm - 0.015, 0.14, z0), (xm + 0.015, BAY_TOP - 0.02, z1), 'V2_Wood', DARK * 0.85, grain=Y,
                          skip=('+y', '-y'))
    # 小屋根（兩側各一）
    for sx in (-1, 1):
        x0, x1 = sorted((sx * CX0, sx * CX1))
        roof_x(m, lod, CY, CP, CZ, x0, x1, ridge=True, rafters=True, col=0.95)
        xe = sx * CX1
        gable_face(m, sx * (OX + OW / 2 - 0.01), CY, CP, CZ - 0.12, C_KETA + 0.04, sx, 'V2_Wood', DARK * 0.8)
        if lod <= 1:
            xa, xb = sorted((xe - sx * 0.02, xe + sx * 0.10))
            plate_x(m, xa, xb, oni_pts(CY - 0.04, CY + 0.26, 0.20, 0.16, 5 if lod == 0 else 3))   # 小鬼瓦
    # 腕木（外柱頂、承小屋根簷桁）
    for sx in (-1, 1):
        xo = sx * OX
        m.box((xo - 0.06, C_KETA - 0.02, -CZ + 0.10), (xo + 0.06, C_KETA + 0.10, CZ - 0.10), 'V2_Wood', DARK, grain=Z)


def sleeve_walls(m, lod):
    for sx in (-1, 1):
        x0, x1 = sorted((sx * WX0, sx * WX1))
        m.box((x0, -0.30, -WB), (x1, W_STONE, WB), 'V2_Stone', 0.80, skip=('-y',))
        m.box((x0, W_STONE, -WT), (x1, W_TOP, WT), 'V2_Plaster', 0.97, grain=X, skip=('-y',))
        m.box((x0 - 0.005, W_TOP - 0.10, -WT - 0.02), (x1 + 0.005, W_TOP, WT + 0.02), 'V2_Wood', DARK, grain=X)
        m.box((x0 - 0.005, W_STONE, -WT - 0.015), (x1 + 0.005, W_STONE + 0.07, WT + 0.015), 'V2_Wood', DARK * 0.9,
              grain=X)
        # 瓦頂の台（壁頂〜瓦下）
        m.box((x0, W_TOP, -WT - 0.04), (x1, WY_E + 0.02, WT + 0.04), 'V2_Wood', DARK * 0.7, grain=X, skip=('-y',))
        if lod == 0:
            # 石積の目地（腰石：二段、長さ不揃い・外へ 0.015）
            import random
            rnd = random.Random(611 + sx)
            for sz in (-1, 1):
                for (ya, yb) in ((-0.02, 0.20), (0.20, W_STONE - 0.02)):
                    t = x0
                    while t < x1 - 0.05:
                        L = rnd.uniform(0.35, 0.70)
                        e = min(x1, t + L)
                        if x1 - e < 0.20:
                            e = x1
                        zz = sz * WB
                        z0, z1 = sorted((zz, zz + sz * 0.015))
                        m.box((t + 0.015, ya + 0.01, z0), (e - 0.015, yb - 0.01, z1), 'V2_Stone',
                              rnd.uniform(0.70, 0.92), skip=('-y', '-z' if sz > 0 else '+z'))
                        t = e
        xa, xb = sorted((sx * (WX0 - 0.10), sx * WCX1))
        roof_x(m, lod, WY, WP, WZ, xa, xb, ridge=True, rafters=False, col=0.92)
        # 牆端の妻（灰泥三角）
        gable_face(m, sx * (WX1 + 0.002), WY, WP, WZ - 0.10, W_TOP, sx, 'V2_Plaster', 0.9)


def leaves(m, lod):
    """門扉：兩扉向內（−z）全開，貼在側間背後；板＋桟＋金具。"""
    for sx in (-1, 1):
        x0, x1 = sorted((sx * (PIN - 0.02), sx * (PIN - 0.02 - LEAF_T)))
        m.box((x0, LEAF_Y[0], -0.03 - LEAF_W), (x1, LEAF_Y[1], -0.03), 'V2_Wood', BOARD * 0.55, grain=Y)
        if lod == 0:
            for yy in (0.40, 1.30, 2.20):
                xa, xb = sorted((sx * (PIN - 0.02 - LEAF_T), sx * (PIN - 0.02 - LEAF_T - 0.025)))
                m.box((xa, yy, -0.03 - LEAF_W + 0.04), (xb, yy + 0.08, -0.07), 'V2_Wood', DARK * 0.9, grain=Z)
            for yy in (0.55, 2.05):   # 肘壺金具
                xa, xb = sorted((sx * (PIN - 0.015), sx * (PIN - 0.02 - LEAF_T - 0.01)))
                m.box((xa, yy, -0.20), (xb, yy + 0.06, -0.02), 'V2_Metal', 0.55, grain=Z)


def ground(m, lod):
    # 敷石（通路中央；薄板、頂 +0.035）
    m.box((-PIN + 0.02, -0.15, -0.95), (PIN - 0.02, SILL_TOP, 0.95), 'V2_Stone', 0.88, skip=('-y',))
    if lod == 0:
        for z in (-0.32, 0.32):
            m.box((-PIN + 0.03, SILL_TOP - 0.004, z - 0.008), (PIN - 0.03, SILL_TOP + 0.001, z + 0.008), 'V2_Stone',
                  0.55, skip=('-y',))


def lod2_roof(m, yr, p, ze, x0, x1, col=0.9):
    """LOD2 切妻：兩片平面瓦（同 UV 規則）＋簷下暗面。"""
    S = ze * math.sqrt(1 + p * p)
    for sg in (1, -1):
        dsl = norm((0.0, -p, float(sg)))
        n = norm((0.0, 1.0, p * sg))
        K.tile_roof(m, (0.0, yr, 0.0), dsl, n, x0, x1, S, KW, 2, u_sign=float(sg), ends=False, col=col)
    for xs, sx in ((x0, -1), (x1, 1)):
        gable_face(m, xs, yr, p, ze, yr - p * ze - 0.2, sx, 'V2_Wood', DARK * 0.6)


def build_lod2(m):
    for sx in (-1, 1):
        x = sx * PX
        m.box((x - PW / 2, FOOT_BOT, -PW / 2), (x + PW / 2, POST_TOP, PW / 2), 'V2_Wood', DARK, skip=('-y',))
        xa, xb = sorted((sx * (PX + PW / 2), sx * (OX + OW / 2)))
        m.box((xa, -0.20, -0.06), (xb, C_KETA, 0.06), 'V2_Wood', BOARD * 0.55, skip=('-y',))
        x0, x1 = sorted((sx * WX0, sx * WX1))
        m.box((x0, -0.30, -WT), (x1, W_TOP, WT), 'V2_Plaster', 0.9, skip=('-y',))
        lod2_roof(m, CY, CP, CZ, *sorted((sx * CX0, sx * CX1)))
        lod2_roof(m, WY, WP, WZ, *sorted((sx * (WX0 - 0.10), sx * WCX1)))
    m.box((-PX - 0.40, KABUKI[0], -0.15), (PX + 0.40, POST_TOP + 0.16, 0.15), 'V2_Wood', DARK)
    lod2_roof(m, RY, RP, RZ, -RX, RX, 1.0)
    m.box((-RX + 0.05, RY - 0.05, -0.13), (RX - 0.05, RY + 0.30, 0.13), 'V2_Kawara', 0.55, skip=('-y',))
    for sx in (-1, 1):
        xa, xb = sorted((sx * (RX - 0.10), sx * (RX + 0.06)))
        plate_x(m, xa, xb, oni_pts(RY - 0.10, RY + 0.30 + ONI_H, 0.30, 0.24, 2))
    m.box((-PIN + 0.02, -0.15, -0.95), (PIN - 0.02, SILL_TOP, 0.95), 'V2_Stone', 0.88, skip=('-y',))


def build(lod):
    m = K.Mesh('HiedaGate_LOD%d' % lod, MATS, TILE)
    if lod == 2:
        build_lod2(m)
        return m
    posts(m, lod)
    roof_x(m, lod, RY, RP, RZ, -RX, RX, ridge=True, rafters=True)
    # 主屋根 棟：熨斗積み二段＋鬼瓦
    m.box((-RX + 0.05, RY + 0.10, -0.13), (RX - 0.05, RY + 0.24, 0.13), 'V2_Kawara', 0.55, grain=X)
    m.box((-RX + 0.08, RY + 0.24, -0.10), (RX - 0.08, RY + 0.30, 0.10), 'V2_Kawara', 0.50, grain=X)
    for sx in (-1, 1):
        xa, xb = sorted((sx * (RX - 0.10), sx * (RX + 0.06)))
        plate_x(m, xa, xb, oni_pts(RY - 0.10, RY + 0.30 + ONI_H, 0.30, 0.24, 6 if lod == 0 else 3))
        # 妻：破風內側（x ±(RX−0.14)）封板；下緣沿小屋根瓦面、上緣沿主屋根野地裏（兩面）
        xg = sx * (RX - 0.14)
        gable_over(m, xg, sx, DARK * 0.62)
        gable_over(m, xg - sx * 0.02, -sx, DARK * 0.45)
        if lod == 0:
            gegyo(m, sx * RX, RY - 0.30, sx)
    side_bays(m, lod)
    sleeve_walls(m, lod)
    if lod <= 1:
        leaves(m, lod)
    ground(m, lod)
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
    glb = OUT + '/src/hieda_gate.glb'
    K.export_glb(bpy, glb, objs)
    cnt = tri_count(glb)
    stats = {'LOD%d' % l: cnt['HiedaGate_LOD%d' % l] for l in (0, 1, 2)}
    top = aabb[0][1][1]
    lx0, lx1 = sorted((PIN - 0.02 - LEAF_T - 0.03, PIN + 0.01))
    spec = {
        '_note': '稗田邸 大宅門 Hero 資產規格（build_hieda_gate.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、'
                 'verify_village_v2_hero_gate.gd 讀取）。沒有 P4 灰盒：放在 P0 地標原點（anchor），取代 P0 線框；'
                 '尺寸以 P0 量體 7 × 5 × 2 為上限、地塊 P_LM_HIEDA_GATE 為界。造型依使用者裁示 B（裨田邸正面.PNG）、'
                 '木色＋灰瓦、不做紅色；只做門＋門地塊內兩側短袖牆（整圈圍牆延 P6／P10）。',
        'id': 'hieda_gate', 'landmark': 'LANDMARK_HIEDA_GATE', 'kind': 'hero', 'budget_class': '稗田邸',
        'glb': 'res://assets/village_v2/hieda_gate/src/hieda_gate.glb',
        'scene': 'res://assets/village_v2/hieda_gate/hieda_gate.scn',
        'lod_objects': ['HiedaGate_LOD0', 'HiedaGate_LOD1', 'HiedaGate_LOD2'],
        'lod_ranges_m': [0, 45, 120, 600],
        'budget': {'lod0': 150000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': {k: ML[k]['tres'] for k in MATS},
        'spec': {'p0_box_m': [7, 5, 2], 'opening_clear_w_m': round(2 * PIN, 3), 'opening_clear_h_m': KABUKI[0],
                 'post_m': PW, 'eave_m': RY_E, 'ridge_m': round(RY, 3), 'top_m': top,
                 'side_bay_w_m': round(OX - OW / 2 - PX - PW / 2, 3), 'side_roof_eave_m': CY_E,
                 'sleeve_wall_m': {'x': [WX0, WX1], 'h': round(WY + 0.175, 3), 'coping_eave': WY_E},
                 'design': '棟門系：主柱 2（石礎）＋外柱 2、冠木、腕木承簷桁、切妻灰瓦＋熨斗棟＋鬼瓦＋懸魚；'
                           '兩側窄間板戶＋灰泥小壁＋較低小屋根；灰泥袖牆（石積腰、瓦頂）；兩扉向內全開；木色，不塗朱'},
        'gate_spec': {
            'placement': 'anchor', 'anchor': 'Landmarks/LANDMARK_HIEDA_GATE', 'replaces': 'Wire',
            'also_retire': ['Footprint'], 'p4_id': '', 'parcel': 'P_LM_HIEDA_GATE', 'road': 'FarmPath_4',
            'size': {'x_half_max': 3.5, 'z_min': -1.0, 'z_max': 1.0, 'top': [round(top - 0.05, 3), 5.0],
                     'bottom': -0.30},
            'ground': [
                {'name': '礎石左', 'rect': [-PX - 0.23, -0.23, -PX + 0.23, 0.23], 'bottom': FOOT_BOT, 'top': FOOT_TOP,
                 'embed_max': 0.35},
                {'name': '礎石右', 'rect': [PX - 0.23, -0.23, PX + 0.23, 0.23], 'bottom': FOOT_BOT, 'top': FOOT_TOP,
                 'embed_max': 0.35},
                {'name': '敷石', 'rect': [-PIN + 0.02, -0.95, PIN - 0.02, 0.95], 'bottom': -0.15, 'top': SILL_TOP,
                 'embed_max': 0.20},
                {'name': '側間地覆左', 'rect': [-(OX - OW / 2), -0.14, -(PX + PW / 2), 0.14], 'bottom': -0.20,
                 'top': 0.12, 'embed_max': 0.25},
                {'name': '側間地覆右', 'rect': [PX + PW / 2, -0.14, OX - OW / 2, 0.14], 'bottom': -0.20, 'top': 0.12,
                 'embed_max': 0.25},
                {'name': '袖牆腰石左', 'rect': [-WX1, -WB, -WX0, WB], 'bottom': -0.30, 'top': W_STONE,
                 'embed_max': 0.40},
                {'name': '袖牆腰石右', 'rect': [WX0, -WB, WX1, WB], 'bottom': -0.30, 'top': W_STONE, 'embed_max': 0.40}],
            # 通路：主柱間（淨寬 2×PIN）、冠木下；門扉全開貼在側間背後，不佔通路
            'walkway': {'rect': [-0.95, -0.9, 0.95, 0.9], 'head': 1.95, 'min_clear': 2.5, 'step': 0.25},
            'entry': [0.0, 3.0], 'inside': [2.8, 0.0],
            'shots': [['front', 0.0, 9.0], ['front_far', -3.0, 17.0], ['back', 1.5, -9.0]]},
        'collision': [
            {'type': 'box', 'name': 'Post%s' % s, 'center': [sx * PX, (FOOT_BOT + POST_TOP + 0.10) / 2, 0],
             'size': [PW + 0.10, POST_TOP + 0.10 - FOOT_BOT, PW + 0.10]} for (sx, s) in ((-1, 'L'), (1, 'R'))] + [
            {'type': 'box', 'name': 'Side%s' % s,
             'center': [sx * (PX + PW / 2 + WX1 + 0.06) / 2, (-0.30 + 2.30) / 2, 0],
             'size': [WX1 + 0.06 - PX - PW / 2, 2.60, 2 * WB + 0.10]} for (sx, s) in ((-1, 'L'), (1, 'R'))] + [
            {'type': 'box', 'name': 'Leaf%s' % s, 'center': [sx * (lx0 + lx1) / 2, 1.33, -0.03 - LEAF_W / 2],
             'size': [lx1 - lx0, 2.60, LEAF_W + 0.08]} for (sx, s) in ((-1, 'L'), (1, 'R'))],
        'measured_blender': dict(stats, aabb=aabb[0], aabb_lod1=aabb[1], aabb_lod2=aabb[2]),
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[GATE]', stats, aabb[0], 'RY %.2f TOP %.2f clear %.2f' % (RY, top, 2 * PIN))


main()
