"""鯢吞亭（LANDMARK_GEIDONTEI）Hero — 人間之里 V2 P5 R2 新資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_geidontei.py

外觀 authority：docs/reference/重點地標/鲵吞亭_正面.png／_側面.png／鯢吞燈籠正面.png。
使用者裁示（2026-09-24）：「大山椒魚頭可以改成門框浮雕／突出招牌，不要為它改地塊。」
  → 頭做成入口上方的突出半圓頂（寬 3.2 m、前出 1.0 m、頂 3.60 m），上顎＋粉紫唇＋牙框住入口，兩側門柱貼唇帶；
    全部在 P4 屋脊與地塊內，不改地塊、不加高。
其餘依參考圖：平入切妻＋中央金色千鳥破風（懸魚）、破風下「鯢吞亭」大提燈；一樓四翼（外側暖紙格子窗、內側開放酒櫃）；
紫暖簾 2 片（白色圓紋）；紅提燈 1F 六盞（酒肴菜／鮮味膳）＋2F 兩盞（壽樂）；二樓格子窗＋手摺；前庭石燈籠一對；寬踏石。
尺寸 authority：P4 greybox.json B_P_LM_GEIDONTEI（10.92 × 9.10、簷 3.9、脊 5.95、台基 0.32、庇 2.7／深 0.91、
出簷 0.45、妻側 0.25、pitch 0.45）。地塊前緣 z＝HD＋1.50（右端斜邊 HD＋1.38）；道路 z ≥ HD＋2.00。
座標：Godot；原點＝footprint 中心、y 0＝footprint 內最高地面（base_h）、+z＝正面（主街）。
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402
from v2_kit import X, Y, Z, add, mul, norm, sub  # noqa: E402
from v2_zushi import Zushi, DARK, BOARD  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/geidontei'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(OUT + '/atlas.json')
AMAT = 'V2_Geidontei'
MATS = ['V2_Wood', 'V2_Plaster', 'V2_Kawara', 'V2_Stone', AMAT]

W, D = 10.92, 9.10
Q = Zushi(W, D, eave=3.90, pitch=0.45, plinth=0.32, bot=-0.38, ov_e=0.45, ov_g=0.25, his_y=2.76, his_d=0.91,
          mats=MATS, amat=AMAT, atlas=AT, matlib=ML)
HW, HD, PLINTH, BOT, RIDGE = Q.HW, Q.HD, Q.PLINTH, Q.BOT, Q.RIDGE
RG = Q.RG
LINTEL, PLATE = Q.LINTEL, Q.PLATE
POSTS = [-HW + 0.075, -3.55, -1.45, 1.45, 3.55, HW - 0.075]
# 山椒魚頭：寬扁的上半「超橢球」頂（平面指數 3 → 鈍圓吻、立面 1.6 → 扁平）；中心在牆內 0.10，前出到 HD+1.15
HC = (0.0, 2.55, HD - 0.10)
HR = (1.85, 0.82, 1.25)
PLAN_E, ELEV_E = 3.0, 1.6
HIS_GAP = HR[0] + 0.06
# 千鳥破風退到主屋前坡上（破風面 zg＝HD−0.90）：P4 主街→南大鳥居視線 gate（永久）有 3 站的視線以 y 4.0–4.6、z ≈ HD−0.1～HD+0.6
# 掠過正面；破風面放在牆線上（R2 首版 zg＝HD）會擋 2–3 站。退進去後破風＋大提燈最前緣 z ≤ HD−0.15。
GC = dict(cx=0.0, zg=HD - 0.90, yp=5.55, p2=0.80, ov=0.40)
LAN_R, LAN_H = 0.36, 0.80
LAN_Z = GC['zg'] + LAN_R + 0.03                       # 燈身背面離破風面 0.03
LAN_Y = Q.roof_y(GC['zg']) + 0.08 + LAN_H / 2         # 燈底比破風腳的主屋面高 0.08
TORO_X, TORO_Z = 4.75, HD + 1.00
RED_1F = [(-4.4, 0), (-3.3, 1), (-2.2, 2), (2.2, 3), (3.3, 4), (4.4, 5)]   # 酒肴菜｜鮮味膳
RED_2F = [(-2.05, 6), (2.05, 7)]                                          # 壽｜樂


def ell(a, b):
    """α∈[0,π]（+x→前→−x）、β∈[0,π/2]（底→頂）的頭部表面點與外法線。"""
    def sp(t, e):
        return math.copysign(abs(t) ** (2.0 / e), t)
    ca, sa, cb, sb = sp(math.cos(a), PLAN_E), sp(math.sin(a), PLAN_E), sp(math.cos(b), ELEV_E), sp(math.sin(b), ELEV_E)
    p = (HC[0] + HR[0] * cb * ca, HC[1] + HR[1] * sb, HC[2] + HR[2] * cb * sa)
    n = norm((cb * ca / HR[0], sb / HR[1], cb * sa / HR[2]))
    return p, n


def head(m, lod):
    na, nb = (28, 9) if lod == 0 else ((14, 5) if lod == 1 else (8, 3))
    u0, v0, u1, v1 = RG['skin']
    # 頂列收斂成一點會產生退化四邊形 → 格網只到 nb−1，頂端另以三角扇收口
    m.grid(lambda i, j: ell(math.pi * i / na, 0.5 * math.pi * j / nb)[0],
           lambda i, j: (u0 + (u1 - u0) * i / na, v1 - (v1 - v0) * j / nb), na, nb - 1, AMAT, 1.0,
           (0.0, 0.2, 1.0))
    top = ell(0.0, 0.5 * math.pi)[0]
    vt = v1 - (v1 - v0) * (nb - 1) / nb
    for i in range(na):
        pa, pb = ell(math.pi * i / na, 0.5 * math.pi * (nb - 1) / nb)[0], ell(math.pi * (i + 1) / na, 0.5 * math.pi * (nb - 1) / nb)[0]
        Q.oface(m, [pa, pb, top], (0.0, 1.0, 0.0), AMAT,
                [(u0 + (u1 - u0) * i / na, vt), (u0 + (u1 - u0) * (i + 1) / na, vt), ((u0 + u1) / 2, v0)], 1.0)
    # 上顎（口腔頂，朝下）：半橢圓扇形
    ring = [ell(math.pi * i / na, 0.0)[0] for i in range(na + 1)]
    cz = (HC[0], HC[1], HD - 0.10)
    mu0, mv0, mu1, mv1 = RG['mouth']
    for i in range(na):
        ps = [cz, ring[i + 1], ring[i]]
        uvs = [((mu0 + mu1) / 2, mv0), (mu0 + (mu1 - mu0) * (i + 1) / na, mv1), (mu0 + (mu1 - mu0) * i / na, mv1)]
        Q.oface(m, ps, (0.0, -1.0, 0.0), AMAT, uvs, 0.9)
    if lod >= 2:
        return
    # 唇：沿口緣的粉紫管
    lip = Q.sw('#E7AEB5')
    seg = 6 if lod == 0 else 4
    for i in range(na):
        a, b = ring[i], ring[i + 1]
        e = mul(norm(sub(b, a)), 0.035)          # 相鄰段互相重疊，避免管口在接縫露出內面
        a, b = sub(a, e), add(b, e)
        m.cyl(add(a, (0, -0.01, 0)), add(b, (0, -0.01, 0)), 0.09, 0.09, seg, AMAT, 1.0, caps=(False, False),
              uv_atlas=lip)
    # 眼：頂部兩側（金色虹膜圓片＋皮色眼瞼環）
    for s in (-1, 1):
        a = math.pi / 2 - s * 0.72
        p, n = ell(a, 0.62)
        n = norm(add(n, (0.0, 0.6, 0.0)))
        c = add(p, mul(n, 0.045))
        # 眼眶用淺米色環（不是皮色）：實機 1600×900、9 m 外，皮色眼瞼會跟斑點混在一起（R2 首版 vision 評 2/5）
        m.cyl(add(p, mul(n, -0.06)), add(p, mul(n, 0.05)), 0.27, 0.215, 16 if lod == 0 else 8, AMAT, 1.0,
              caps=(False, False), uv_atlas=Q.sw('#E6D9BC'))
        Q.disc(m, add(c, mul(n, 0.016)), n, 0.205, 16 if lod == 0 else 8, RG['eye'])
    if lod == 0:
        # 鼻孔
        for s in (-1, 1):
            p, n = ell(math.pi / 2 - s * 0.26, 0.28)
            Q.disc(m, add(p, mul(n, 0.012)), n, 0.055, 8, Q.sw('#2A1A14'))
        # 牙：口緣內側 0.10 的小三角錐（下緣 ≥ 2.40）
        ivory = Q.sw('#E8DDC4')
        for k in range(19):
            a = math.pi * (k + 0.5) / 19
            if abs(a - math.pi / 2) > 1.30:
                continue
            p, _ = ell(a, 0.0)
            d = norm(sub((HC[0], 0.0, HC[2]), (p[0], 0.0, p[2])))
            base = add(p, mul(d, 0.10))
            t = mul((d[2], 0.0, -d[0]), 0.055)
            tip = add(base, (0.0, -0.12, 0.0))
            b0, b1, b2 = add(base, t), add(base, mul(t, -1.0)), add(base, mul(d, 0.08))
            y0 = base[1] - 0.001
            b0, b1, b2 = (b0[0], y0, b0[2]), (b1[0], y0, b1[2]), (b2[0], y0, b2[2])
            cen = mul(add(add(b0, b1), b2), 1.0 / 3.0)   # 朝向參考用三角錐底心（b0–b1 中點＝base，拿 base 當參考會得零向量）
            for (pa, pb) in ((b0, b1), (b1, b2), (b2, b0)):
                Q.oface(m, [pa, pb, tip], sub(mul(add(pa, pb), 0.5), cen), AMAT, [(ivory[0], ivory[1])] * 3, 1.0)


def door_lips(m):
    """門框浮雕：兩側門柱前貼粉紫唇帶（接上顎），入口成為「口」。"""
    zf = HD
    lip = Q.sw('#C98F97')
    for s in (-1, 1):
        x = s * 1.45
        m.abox((x, (0.35 + 2.55) / 2, zf + 0.06), (0.14, (2.55 - 0.35) / 2, 0.06), AMAT, {'*': lip}, 1.0,
               skip=('-z', '-y'))
        # 口角：唇帶頂端到上顎口緣的過渡塊（皮色）
        m.abox((s * 1.62, 2.40, zf + 0.10), (0.24, 0.16, 0.10), AMAT, {'*': Q.rsub(RG['skin'], 0.3, 0.3, 0.4, 0.4)},
               1.0, skip=('-z',))


def facade_1f(m, lod):
    zf = HD
    for i, xa in enumerate(POSTS):
        full = i in (0, len(POSTS) - 1)
        m.box((xa - 0.075, PLINTH, zf - 0.15), (xa + 0.075, PLATE[1] if full else LINTEL[0], zf),
              'V2_Wood', DARK, grain=Y, skip=('-y',))
    m.box((-HW, LINTEL[0], zf - 0.14), (HW, LINTEL[1], zf + 0.01), 'V2_Wood', DARK, grain=X)
    # 外翼：腰板＋暖紙＋細格子
    for (a, b) in ((POSTS[0] + 0.075, POSTS[1] - 0.075), (POSTS[4] + 0.075, POSTS[5] - 0.075)):
        Q.fz(m, a, b, PLINTH, 0.80, zf - 0.03, 'V2_Wood', BOARD * 0.8, grain=Y)
        m.box((a, 0.80, zf - 0.08), (b, 0.86, zf), 'V2_Wood', DARK, grain=X)
        Q.fz(m, a, b, 0.86, LINTEL[0], zf - 0.07, AMAT, 1.0, RG['lattice_paper'])
        if lod <= 1:
            Q.bars(m, a + 0.02, b - 0.02, 0.86, LINTEL[0], zf - 0.06, zf - 0.01, 0.075 if lod == 0 else 0.15, 0.035)
            for y in (1.35, 1.90):
                m.box((a, y, zf - 0.065), (b, y + 0.03, zf - 0.005), 'V2_Wood', DARK, grain=X, skip=('-z',))
    # 內翼：腰壁＋開放酒櫃
    for (a, b) in ((POSTS[1] + 0.075, POSTS[2] - 0.075), (POSTS[3] + 0.075, POSTS[4] - 0.075)):
        Q.recess(m, a, b, 0.95, LINTEL[0], zf - 0.02, 1.10, Q.rsub(RG['interior'], 0.0, 0.05, 1.0, 0.72),
                 floor_col=0.40)
        Q.fz(m, a, b, PLINTH, 0.95, zf - 0.02, 'V2_Wood', BOARD * 0.75, grain=Y)
        m.box((a, 0.92, zf - 0.30), (b, 0.97, zf + 0.06), 'V2_Wood', BOARD * 0.6, grain=X)
    # 中央入口
    a, b = POSTS[2] + 0.075, POSTS[3] - 0.075
    Q.recess(m, a, b, PLINTH, LINTEL[0], zf - 0.06, 2.60, RG['interior'], side_region=RG['lattice_dark'],
             floor_col=0.36)
    m.box((a, 0.30, zf - 0.10), (b, 0.35, zf + 0.02), 'V2_Wood', DARK, grain=X)
    door_lips(m)
    zn = zf + 0.14
    m.cyl((-1.02, 2.37, zn), (1.02, 2.37, zn), 0.018, 0.018, 8 if lod == 0 else 6, 'V2_Wood', DARK)
    for k in range(2):
        x0 = -0.99 + k * 1.00
        Q.fz(m, x0, x0 + 0.98, 1.50, 2.36, zn + 0.006 * k, AMAT, 1.0, Q.rsub(RG['noren'], k / 2, 0, (k + 1) / 2, 1))
        Q.fz(m, x0, x0 + 0.98, 1.50, 2.36, zn + 0.006 * k - 0.004, AMAT, 1.0, RG['noren_back'], back=True)
    # 寬踏石
    m.box((-1.40, -0.14, zf), (1.40, 0.14, zf + 0.50), 'V2_Stone', 0.92, skip=('-y', '-z'))
    if lod <= 1:
        for (x, i) in RED_1F:
            Q.chochin(m, (x, 1.98, zf + 0.42), 0.16, 0.36, RG['red_%d' % i], lod)
            m.box((x - 0.01, 2.19, zf + 0.41), (x + 0.01, 2.46, zf + 0.43), 'V2_Wood', 0.2)


def facade_2f(m, lod):
    zf = HD
    zw = zf - 0.02
    Q.fz(m, -HW + 0.15, HW - 0.15, LINTEL[1], 2.85, zw, 'V2_Plaster', 0.97)
    Q.fz(m, -HW + 0.15, HW - 0.15, 3.45, PLATE[0], zw, 'V2_Plaster', 0.97)
    for (a, b) in ((-HW + 0.15, -5.10), (-2.35, 2.35), (5.10, HW - 0.15)):
        Q.fz(m, a, b, 2.85, 3.45, zw, 'V2_Plaster', 0.97)
    m.box((-HW - Q.OV_G, PLATE[0], zf - 0.16), (HW + Q.OV_G, PLATE[1], zf + 0.01), 'V2_Wood', DARK, grain=X)
    for (a, b) in ((-5.10, -2.35), (2.35, 5.10)):
        Q.fz(m, a, b, 2.85, 3.45, zf - 0.10, AMAT, 0.9, RG['lattice_paper'])
        Q.fx(m, zf - 0.10, zw, 2.85, 3.45, a, 'V2_Wood', DARK * 0.8)
        Q.fx(m, zf - 0.10, zw, 2.85, 3.45, b, 'V2_Wood', DARK * 0.8, neg=True)
        m.box((a - 0.06, 3.45, zf - 0.06), (b + 0.06, 3.51, zf + 0.03), 'V2_Wood', DARK, grain=X)
        if lod <= 1:
            Q.bars(m, a, b, 2.85, 3.45, zf - 0.05, zf, 0.09 if lod == 0 else 0.18, 0.035)
        # 手摺：前出 0.14
        m.box((a - 0.06, 2.92, zf), (b + 0.06, 2.97, zf + 0.14), 'V2_Wood', DARK, grain=X)
        if lod == 0:
            k = int((b - a) / 0.30)
            for i in range(k + 1):
                x = a + (b - a) * i / k
                m.box((x - 0.02, 2.62, zf + 0.08), (x + 0.02, 2.92, zf + 0.12), 'V2_Wood', DARK, grain=Y,
                      skip=('+y', '-y'))
        m.box((a - 0.06, 2.60, zf), (b + 0.06, 2.64, zf + 0.12), 'V2_Wood', DARK, grain=X)
    if lod <= 1:
        for (x, i) in RED_2F:
            yb = Q.roof_y(zf + 0.25) - 0.19 - 0.10
            Q.chochin(m, (x, yb - 0.20, zf + 0.25), 0.15, 0.36, RG['red_%d' % i], lod)


def name_lantern(m, lod):
    z = LAN_Z
    Q.chochin(m, (0.0, LAN_Y, z), LAN_R, LAN_H, RG['name_lantern'], lod)
    if lod <= 1:
        m.box((-0.012, LAN_Y + LAN_H / 2 + 0.02, z - 0.012), (0.012, GC['yp'] - 0.10, z + 0.012), 'V2_Wood', 0.2)


def toro(m, lod, sx):
    x, z = TORO_X * sx, TORO_Z
    m.box((x - 0.23, -0.12, z - 0.23), (x + 0.23, 0.18, z + 0.23), 'V2_Stone', 0.80, skip=('-y',))
    m.box((x - 0.09, 0.18, z - 0.09), (x + 0.09, 0.95, z + 0.09), 'V2_Stone', 0.85, skip=('-y', '+y'))
    m.box((x - 0.20, 0.95, z - 0.20), (x + 0.20, 1.01, z + 0.20), 'V2_Stone', 0.78)
    rw = RG['toro_window']
    m.abox((x, 1.16, z), (0.15, 0.15, 0.15), AMAT, {'*': rw}, 1.0, skip=('+y', '-y'))
    m.cyl((x, 1.31, z), (x, 1.52, z), 0.30, 0.04, 4, 'V2_Stone', 0.75, caps=(True, False), phase=math.pi / 4)
    if lod == 0:
        m.cyl((x, 1.50, z), (x, 1.60, z), 0.05, 0.02, 8, 'V2_Stone', 0.75, caps=(False, True))


def gable(m, lod):
    gold = Q.sw('#D9A441')
    # 懸魚不放：破風退進主屋坡後，大提燈正好吊在懸魚的位置（兩者會互相穿插）
    Q.cross_gable(m, lod, GC['cx'], GC['zg'], GC['yp'], GC['p2'], GC['ov'], 'V2_Wood', BOARD * 0.9, trim=gold)


def build(lod):
    m = K.Mesh('Geidontei_LOD%d' % lod, MATS, Q.TILE)
    arms = [p for p in POSTS if abs(p) > HIS_GAP]
    if lod <= 1:
        m.box((-HW, BOT, -HD), (HW, PLINTH, HD), 'V2_Stone', 0.85, skip=('-y',))
        facade_1f(m, lod)
        facade_2f(m, lod)
        Q.sides_back(m, lod, back_door=(1.55, 2.45), side_windows=True, back_window=-1.5, win_region='lattice_paper')
        Q.hisashi(m, lod, segs=[(-HW - 0.07, -HIS_GAP), (HIS_GAP, HW + 0.07)], arms=arms)
        Q.main_roof(m, lod)
        gable(m, lod)
        head(m, lod)
        name_lantern(m, lod)
        for sx in (-1, 1):
            toro(m, lod, sx)
    else:
        Q.lod2_shell(m, front_1f_region=RG['interior'])
        Q.hisashi(m, 2, segs=[(-HW - 0.07, -HIS_GAP), (HIS_GAP, HW + 0.07)])
        Q.main_roof_lod2(m)
        Q.cross_gable(m, 2, GC['cx'], GC['zg'], GC['yp'], GC['p2'], GC['ov'], 'V2_Plaster', 0.9)
        head(m, 2)
        Q.fz(m, -LAN_R, LAN_R, LAN_Y - LAN_H / 2, LAN_Y + LAN_H / 2, LAN_Z + LAN_R, AMAT, 1.0,
             Q.rsub(RG['name_lantern'], 0.1, 0.0, 0.4, 1.0))
        for sx in (-1, 1):
            x = TORO_X * sx
            m.box((x - 0.20, -0.12, TORO_Z - 0.20), (x + 0.20, 1.40, TORO_Z + 0.20), 'V2_Stone', 0.8, skip=('-y',))
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
        if lod == 0:
            xs = [p[0] for p in m.v]
            ys = [p[1] for p in m.v]
            zs = [p[2] for p in m.v]
            stats['aabb'] = [[round(min(xs), 3), round(min(ys), 3), round(min(zs), 3)],
                             [round(max(xs), 3), round(max(ys), 3), round(max(zs), 3)]]
    K.export_glb(bpy, OUT + '/src/geidontei.glb', objs)
    zf = HD
    spec = {
        '_note': '鯢吞亭 Hero 資產規格（build_geidontei.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、'
                 'verify_village_v2_hero_gate.gd 讀取）。尺寸 authority＝P4 greybox B_P_LM_GEIDONTEI。'
                 '山椒魚頭＝入口上方突出的門框浮雕（使用者 2026-09-24 裁示），不改地塊。'
                 'size.z_max 含前庭石燈籠（在地塊內，parcel_fit 另驗）。',
        'id': 'geidontei', 'landmark': 'LANDMARK_GEIDONTEI', 'kind': 'hero', 'budget_class': '鯢吞亭',
        'glb': 'res://assets/village_v2/geidontei/src/geidontei.glb',
        'scene': 'res://assets/village_v2/geidontei/geidontei.scn',
        'lod_objects': ['Geidontei_LOD0', 'Geidontei_LOD1', 'Geidontei_LOD2'],
        'lod_ranges_m': [0, 40, 110, 600],
        'budget': {'lod0': 100000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': {k: (ML[k]['tres'] if k in ML else 'res://assets/village_v2/geidontei/V2_Geidontei.tres')
                      for k in MATS},
        'spec': {'width_m': W, 'depth_m': D, 'eave_m': Q.EAVE, 'ridge_m': round(RIDGE, 3), 'plinth_m': PLINTH,
                 'foundation_bottom_m': BOT, 'hisashi_m': 2.7, 'hisashi_depth_m': Q.HIS_D, 'ov_eave_m': Q.OV_E,
                 'ov_gable_m': Q.OV_G, 'door_m': [2.75, 2.07], 'floor_m': PLINTH,
                 'door_clear_m': [2.75, round(LINTEL[0] - 0.35, 3)],
                 'design': {'salamander_head': {'type': '門框浮雕／突出上顎', 'width_m': 2 * HR[0],
                                                'front_m': round(HC[2] + HR[2] - HD, 2), 'top_m': HC[1] + HR[1],
                                                'jaw_m': HC[1]},
                            'cross_gables': ['中央（金破風、「鯢吞亭」大提燈；破風面退到 HD−0.90 保南大鳥居視線）'],
                            'lanterns': {'red_1f': 6, 'red_2f': 2, 'name': 1, 'stone': 2}}},
        'gate_spec': {
            'placement': 'greybox', 'anchor': 'Landmarks/LANDMARK_GEIDONTEI', 'replaces': 'Greybox',
            'p4_id': 'B_P_LM_GEIDONTEI', 'parcel': 'P_LM_GEIDONTEI', 'road': 'MainStreet',
            'size': {'x_half_max': HW + Q.OV_G + 0.12, 'z_min': -(HD + Q.OV_E + 0.12), 'z_max': TORO_Z + 0.23 + 0.05,
                     'top': [round(RIDGE, 3), round(RIDGE + 0.30, 3)], 'bottom': BOT},
            'body': {'w': W, 'd': D, 'eave': Q.EAVE, 'ridge': round(RIDGE, 3), 'plinth': PLINTH},
            'door_clear': {'h': round(LINTEL[0] - 0.35, 3), 'w': 2.75, 'min_h': 1.9, 'min_w': 1.2},
            'ground': [
                {'name': '台基', 'rect': [-HW, -HD, HW, HD], 'bottom': BOT, 'top': PLINTH, 'embed_max': 0.50},
                {'name': '踏石', 'rect': [-1.40, zf, 1.40, zf + 0.50], 'bottom': -0.14, 'top': 0.14, 'embed_max': 0.25},
                {'name': '石燈籠左', 'rect': [-TORO_X - 0.23, TORO_Z - 0.23, -TORO_X + 0.23, TORO_Z + 0.23],
                 'bottom': -0.12, 'top': 0.18, 'embed_max': 0.25},
                {'name': '石燈籠右', 'rect': [TORO_X - 0.23, TORO_Z - 0.23, TORO_X + 0.23, TORO_Z + 0.23],
                 'bottom': -0.12, 'top': 0.18, 'embed_max': 0.25},
                {'name': '勝手口踏石', 'rect': [1.55, -HD - 0.41, 2.45, -HD - 0.01], 'bottom': -0.12, 'top': 0.14,
                 'embed_max': 0.25}],
            'walkway': {'rect': [-3.95, zf + 0.65, 3.95, zf + Q.HIS_D + 0.30], 'head': 1.95, 'min_clear': 2.0,
                        'step': 0.25},
            'entry': [0.0, zf + 0.95], 'inside': [0.0, 0.0]},
        'collision': [
            # 本體碰撞前緣推到 HD+0.20：蓋住門面突出物（玻璃櫃 0.12–0.15、唇帶 0.12、手摺），步行帶從 HD+0.65 起不受影響
            {'type': 'box', 'name': 'Body', 'center': [0, (BOT + Q.EAVE) / 2, 0.10], 'size': [W, Q.EAVE - BOT, D + 0.20]},
            {'type': 'convex', 'name': 'Step', 'center': [0, 0, 0], 'points': [
                [sx * 1.40, y, z] for sx in (-1, 1) for (y, z) in (
                    (-0.14, zf), (0.14, zf), (0.14, zf + 0.42), (-0.14, zf + 0.68))]},
            {'type': 'box', 'name': 'ToroL', 'center': [-TORO_X, 0.74, TORO_Z], 'size': [0.50, 1.72, 0.50]},
            {'type': 'box', 'name': 'ToroR', 'center': [TORO_X, 0.74, TORO_Z], 'size': [0.50, 1.72, 0.50]},
            {'type': 'box', 'name': 'BackStep', 'center': [2.0, 0.0, -HD - 0.21], 'size': [0.90, 0.26, 0.40]}],
        'measured_blender': stats,
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[GEIDONTEI]', stats)


main()
