"""霧雨店（LANDMARK_KIRISAME）Hero — 人間之里 V2 P5 R2 新資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_kirisame.py

外觀 authority：docs/reference/重點地標/霧雨店.png（＋霧雨燈籠.png、霧雨特價.png）。依參考圖重新設計（使用者 2026-09-24：
「不要單純為了塞滿 P4 高度硬加一層」）：
  - 平入切妻、灰瓦；**一樓店面＋低矮屋根裏**（參考圖沒有二樓窗、沒有可住二樓）→ 2F 帶只有灰泥＋額，不開窗。
  - 主屋前坡兩個千鳥破風：中央大破風（下掛扇形邊木額「霧雨店」）、左側小破風——參考圖的輪廓就是這樣，
    兩個破風都壓在 P4 屋脊以下（不加高）。
  - 五開間：左玻璃櫃（淺凸 0.12）、左陳列窗、中央入口＋深綠星月暖簾、右陳列窗＋紅布展示台、右玻璃櫃。
  - 魔女帽（黑、淡紫蝴蝶結）在額右上方的主屋前坡；右庇下「魔」大提燈；左端柱吊橢圓木牌；
    左前 A 字黑板（魔法道具 特別セール！）＋木箱；右前木桶花台；後左小煙囪。
尺寸 authority：P4 greybox.json B_P_LM_KIRISAME（8.19 × 7.28、簷 3.9、脊 5.54、台基 0.32、庇 2.7／深 0.91、
出簷 0.45、妻側 0.25、pitch 0.45）。前方地塊線 z＝HD＋0.91（地面接觸件不得超過）；道路 z ≥ HD＋1.41。
座標：Godot；原點＝footprint 中心、y 0＝footprint 內最高地面（base_h）、+z＝正面（主街）。
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402
from v2_kit import X, Y, Z, add, mul, norm  # noqa: E402
from v2_zushi import Zushi, DARK, BOARD  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/kirisame'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(OUT + '/atlas.json')
AMAT = 'V2_Kirisame'
MATS = ['V2_Wood', 'V2_Plaster', 'V2_Kawara', 'V2_Stone', AMAT]

# ── P4 authority
W, D = 8.19, 7.28
Q = Zushi(W, D, eave=3.90, pitch=0.45, plinth=0.32, bot=-0.38, ov_e=0.45, ov_g=0.25, his_y=2.76, his_d=0.91,
          mats=MATS, amat=AMAT, atlas=AT, matlib=ML)
HW, HD, PLINTH, BOT, RIDGE = Q.HW, Q.HD, Q.PLINTH, Q.BOT, Q.RIDGE
RG = Q.RG
LINTEL, PLATE = Q.LINTEL, Q.PLATE
FRONT_LIM = HD + 0.61            # 地面接觸件前緣上限（地塊線 HD+0.91；步行帶膠囊從 HD+0.63 起）
# ── 立面：五開間（柱心）
POSTS = [-HW + 0.075, -2.75, -0.95, 0.95, 2.75, HW - 0.075]
DOOR = (-0.875, 0.875)
SIGN = (0.0, 3.30, 2.80, 0.79)   # 額：中心 x、y、寬、高（atlas 1024×288）
GC = dict(cx=0.0, yp=5.20, p2=0.80, ov=0.40)     # 中央破風
GL = dict(cx=-3.20, yp=4.50, p2=0.80, ov=0.30)   # 左小破風


def facade_1f(m, lod):
    zf = HD
    for i, xa in enumerate(POSTS):
        full = i in (0, len(POSTS) - 1)
        m.box((xa - 0.075, PLINTH, zf - 0.15), (xa + 0.075, PLATE[1] if full else LINTEL[0], zf),
              'V2_Wood', DARK, grain=Y, skip=('-y',))
    m.box((-HW, LINTEL[0], zf - 0.14), (HW, LINTEL[1], zf + 0.01), 'V2_Wood', DARK, grain=X)    # 差鴨居
    # 兩個陳列窗：腰板＋貨架 recess（4 層）＋細框
    for (a, b) in ((POSTS[1] + 0.075, POSTS[2] - 0.075), (POSTS[3] + 0.075, POSTS[4] - 0.075)):
        Q.recess(m, a, b, 0.78, LINTEL[0], zf - 0.03, 0.50, RG['goods'], floor_col=0.40)
        for y in (1.18, 1.60, 2.02):
            Q.shelf(m, a, b, y, zf - 0.03, 0.50)
        Q.fz(m, a, b, PLINTH, 0.74, zf - 0.04, 'V2_Wood', BOARD * 0.78, grain=Y)
        m.box((a, 0.74, zf - 0.10), (b, 0.80, zf + 0.01), 'V2_Wood', DARK, grain=X)
        if lod <= 1:
            n = 3
            for k in range(1, n):
                x = a + (b - a) * k / n
                m.box((x - 0.02, 0.80, zf - 0.07), (x + 0.02, LINTEL[0], zf - 0.02), 'V2_Wood', DARK, grain=Y,
                      skip=('+y', '-y', '-z'))
            m.box((a, 1.62, zf - 0.07), (b, 1.65, zf - 0.02), 'V2_Wood', DARK, grain=X, skip=('-z',))
    # 兩端玻璃櫃：從牆面凸出 0.12（< 碰撞容許 0.15，不另設碰撞）
    for (a, b) in ((POSTS[0] + 0.075, POSTS[1] - 0.075), (POSTS[4] + 0.075, POSTS[5] - 0.075)):
        zc = zf + 0.12
        Q.fz(m, a, b, PLINTH, 0.70, zc, 'V2_Wood', BOARD * 0.66, grain=Y)
        Q.fz(m, a, b, 0.70, 2.20, zc - 0.02, AMAT, 0.80, Q.rsub(RG['goods'], 0.0, 0.25, 0.30, 1.0))
        m.box((a - 0.02, 2.20, zf - 0.02), (b + 0.02, 2.30, zc + 0.03), 'V2_Wood', DARK, grain=X)   # 頂板
        m.box((a - 0.02, 0.66, zf - 0.02), (b + 0.02, 0.72, zc + 0.02), 'V2_Wood', DARK, grain=X)
        for xx in (a, b):
            Q.fx(m, zf, zc, PLINTH, 2.20, xx, 'V2_Wood', BOARD * 0.55, neg=(xx == a))
        m.box((a, 2.20, zf), (b, 2.42, zf + 0.01), 'V2_Wood', BOARD * 0.5, grain=X)
        if lod <= 1:
            for x in (a + (b - a) / 3, a + 2 * (b - a) / 3):
                m.box((x - 0.018, 0.72, zc - 0.03), (x + 0.018, 2.20, zc + 0.01), 'V2_Wood', DARK, grain=Y,
                      skip=('+y', '-y', '-z'))
            for y in (1.20, 1.70):
                m.box((a, y, zc - 0.03), (b, y + 0.03, zc + 0.01), 'V2_Wood', DARK, grain=X, skip=('-z',))
    # 中央入口：深室（貨架背板＋書背側板）、敷居、兩側細柱
    a, b = POSTS[2] + 0.075, POSTS[3] - 0.075
    Q.recess(m, a, b, PLINTH, LINTEL[0], zf - 0.06, 2.20, RG['goods'], side_region=RG['spines'], floor_col=0.36)
    m.box((a, 0.30, zf - 0.10), (b, 0.35, zf + 0.02), 'V2_Wood', DARK, grain=X)
    # 暖簾：深綠 6 片（竿 2.37、下緣 1.58）
    zn = zf + 0.12
    m.cyl((-0.93, 2.37, zn), (0.93, 2.37, zn), 0.016, 0.016, 8 if lod == 0 else 6, 'V2_Wood', DARK)
    pw = (1.80 - 5 * 0.02) / 6
    for k in range(6):
        x0 = -0.90 + k * (pw + 0.02)
        dz = 0.010 * math.sin(k * 1.9)
        Q.fz(m, x0, x0 + pw, 1.58, 2.36, zn + dz, AMAT, 1.0, Q.rsub(RG['noren'], k / 6, 0, (k + 1) / 6, 1))
        Q.fz(m, x0, x0 + pw, 1.58, 2.36, zn + dz - 0.004, AMAT, 1.0, RG['noren_back'], back=True)
    # 踏石
    m.box((-0.85, -0.14, zf), (0.85, 0.14, zf + 0.45), 'V2_Stone', 0.92, skip=('-y', '-z'))
    if lod <= 1:
        props(m, lod)


def props(m, lod):
    zf = HD
    # 右：紅布展示台（x 1.05–2.65；台面 0.72；布垂到 0.42）＋書堆、瓶
    x0, x1, z0, z1 = 1.05, 2.65, zf + 0.08, zf + 0.54
    for (lx, lz) in ((x0 + 0.05, z0 + 0.05), (x1 - 0.05, z0 + 0.05), (x0 + 0.05, z1 - 0.05), (x1 - 0.05, z1 - 0.05)):
        m.box((lx - 0.035, -0.10, lz - 0.035), (lx + 0.035, 0.70, lz + 0.035), 'V2_Wood', DARK, grain=Y, skip=('-y',))
    m.box((x0, 0.68, z0), (x1, 0.72, z1), 'V2_Wood', BOARD * 0.6, grain=X)
    m.abox(((x0 + x1) / 2, 0.725, (z0 + z1) / 2), ((x1 - x0) / 2 + 0.01, 0.006, (z1 - z0) / 2 + 0.01), AMAT,
           {'*': RG['cloth_red']}, 1.0, skip=('-y',))
    Q.fz(m, x0 - 0.01, x1 + 0.01, 0.42, 0.72, z1 + 0.012, AMAT, 0.95, RG['cloth_red'])
    for i, (x, w_, h) in enumerate(((1.30, 0.30, 0.16), (1.72, 0.26, 0.10), (2.35, 0.34, 0.22))):
        m.abox((x, 0.73 + h / 2, (z0 + z1) / 2), (w_ / 2, h / 2, 0.11), AMAT,
               {'+z': Q.rsub(RG['spines'], i / 4, 0.5, (i + 1) / 4, 1.0), '*': Q.sw('#D8CFB8')}, 1.0, skip=('-y',))
    for (x, c) in ((2.00, '#4B6B45'), (2.10, '#3A5F6E')):
        m.cyl((x, 0.73, z1 - 0.12), (x, 0.93, z1 - 0.12), 0.045, 0.035, 8, AMAT, 1.0, caps=(False, True),
              uv_atlas=Q.sw(c))
    # 右端：木桶花台（r 0.27、高 0.62）
    bx, bz = 3.45, zf + 0.33
    m.cyl((bx, -0.12, bz), (bx, 0.62, bz), 0.27, 0.25, 14 if lod == 0 else 8, AMAT, 1.0, caps=(False, False),
          uv_atlas=Q.sw('#7A5A36'))
    for y in (0.08, 0.50):
        m.cyl((bx, y, bz), (bx, y + 0.04, bz), 0.28, 0.28, 14 if lod == 0 else 8, AMAT, 1.0, caps=(False, False),
              uv_atlas=Q.sw('#1E1B18'))
    m.abox((bx, 0.72, bz), (0.24, 0.12, 0.24), AMAT, {'*': RG['flowers']}, 1.0, skip=('-y',))
    # 左：A 字黑板（x −3.30、寬 0.62、高 1.05）＋木箱
    cx, zc = -3.30, zf + 0.34
    tilt = 0.20
    for s in (1, -1):
        n = norm((0.0, tilt, float(s)))
        ay = norm((0.0, 1.0, -tilt * s))
        c = (cx, 0.47, zc + s * 0.095)
        # 右手系：ax × ay ＝ n（背板 ax 取 −X）
        if s > 0:
            m.abox(c, (0.31, 0.53, 0.012), AMAT, {'+z': RG['chalk'], '*': RG['sign_wood']}, 1.0, X, ay, n)
        else:
            m.abox(c, (0.31, 0.53, 0.012), AMAT, {'*': RG['sign_wood']}, 1.0, mul(X, -1.0), ay, n)
    for sx in (-1, 1):
        m.box((cx + sx * 0.31 - 0.02, -0.10, zc - 0.22), (cx + sx * 0.31 + 0.02, 0.02, zc + 0.22), 'V2_Wood', DARK,
              grain=Z, skip=('-y',))
    m.box((-2.55, -0.10, zf + 0.10), (-2.05, 0.46, zf + 0.55), 'V2_Wood', BOARD * 0.55, skip=('-y',))
    m.box((-2.58, 0.46, zf + 0.07), (-2.02, 0.50, zf + 0.58), 'V2_Wood', BOARD * 0.45)
    m.abox((-2.30, 0.56, zf + 0.32), (0.18, 0.06, 0.13), AMAT,
           {'*': Q.rsub(RG['spines'], 0.5, 0.0, 0.75, 0.5)}, 1.0, skip=('-y',))
    # 「魔」大提燈（右庇下，x 3.55、z HD+0.36：前緣 HD+0.58 在步行帶 HD+0.65 外；燈身 1.76–2.20，整顆露在庇出桁下）
    Q.chochin(m, (3.55, 1.98, zf + 0.36), 0.22, 0.44, RG['lantern_ma'], lod)
    m.box((3.55 - 0.012, 2.23, zf + 0.36 - 0.012), (3.55 + 0.012, 2.52, zf + 0.36 + 0.012), 'V2_Wood', 0.2)
    # 左端柱吊橢圓木牌（魔女剪影）
    ox, oy = POSTS[0], 1.98
    m.box((ox - 0.004, oy + 0.14, zf + 0.012), (ox + 0.004, 2.30, zf + 0.02), 'V2_Wood', 0.2)
    pts = [(ox + 0.19 * math.cos(2 * math.pi * i / 16), oy + 0.14 * math.sin(2 * math.pi * i / 16)) for i in range(16)]
    u0, v0, u1, v1 = RG['oval_ma']
    uvs = [(u0 + (u1 - u0) * (0.5 + 0.5 * math.cos(2 * math.pi * i / 16)),
            v0 + (v1 - v0) * (0.5 - 0.5 * math.sin(2 * math.pi * i / 16))) for i in range(16)]
    m.face(m.verts([(x, y, zf + 0.05) for (x, y) in pts]), AMAT, uvs, 1.0)


def facade_2f(m, lod):
    """屋根裏帶（2.58–3.78）：無窗灰泥＋額＋魔女帽。"""
    zf = HD
    zw = zf - 0.02
    Q.fz(m, -HW + 0.15, HW - 0.15, LINTEL[1], PLATE[0], zw, 'V2_Plaster', 0.97)
    m.box((-HW - Q.OV_G, PLATE[0], zf - 0.16), (HW + Q.OV_G, PLATE[1], zf + 0.01), 'V2_Wood', DARK, grain=X)
    for xa in (-2.75, 2.75):                                  # 2F 間柱
        m.box((xa - 0.06, LINTEL[1], zf - 0.10), (xa + 0.06, PLATE[0], zf + 0.005), 'V2_Wood', DARK, grain=Y,
              skip=('+y', '-y'))
    # 額：扇形邊（上緣波浪），正面 atlas、側／背素木；兩托木
    cx, cy, sw_, sh = SIGN
    zb, zfr = zf + 0.04, zf + 0.10
    nseg = 32 if lod == 0 else 16
    pts = []
    for i in range(nseg):
        t = 2 * math.pi * i / nseg
        c, s = math.cos(t), math.sin(t)
        r = 1.0 / (abs(c) ** 5 + abs(s) ** 5) ** 0.2
        if s > 0:
            r *= 1 + 0.05 * abs(math.sin(3 * t))
        pts.append((c * r * sw_ / 2, s * r * sh / 2))
    u0, v0, u1, v1 = RG['sign']

    def suv(p):
        return (u0 + (p[0] / sw_ + 0.5) * (u1 - u0), v0 + (0.5 - p[1] / sh) * (v1 - v0))
    m.face(m.verts([(cx + p[0], cy + p[1], zfr) for p in pts]), AMAT, [suv(p) for p in pts], 1.0)
    m.face(m.verts(list(reversed([(cx + p[0], cy + p[1], zb) for p in pts]))), AMAT,
           [suv(p) for p in reversed(pts)], 0.8)
    wu0, wv0, wu1, wv1 = RG['sign_wood']
    for i in range(nseg):
        p, q = pts[i], pts[(i + 1) % nseg]
        m.face(m.verts([(cx + p[0], cy + p[1], zb), (cx + q[0], cy + q[1], zb),
                        (cx + q[0], cy + q[1], zfr), (cx + p[0], cy + p[1], zfr)]), AMAT,
               [(wu0, wv1), (wu1, wv1), (wu1, wv0), (wu0, wv0)], 0.8)
    for bx in (-0.95, 0.95):
        m.box((cx + bx - 0.04, cy - sh / 2 - 0.10, zf), (cx + bx + 0.04, cy - sh / 2 + 0.04, zb + 0.02),
              'V2_Wood', DARK, skip=('-z',))
    if lod <= 1:
        hat(m, lod)


def hat(m, lod):
    """魔女帽：坐在主屋前坡（x 2.55、z HD+0.25），軸沿屋面法線微前傾；黑布帽＋淡紫蝴蝶結。"""
    zc = HD + 0.25
    base = (2.55, Q.roof_y(zc) + 0.07, zc)
    ax = norm((0.12, 1.0, 0.30))
    seg = 16 if lod == 0 else 10
    black = Q.sw('#1E1B18')
    m.cyl(add(base, mul(ax, -0.015)), add(base, mul(ax, 0.015)), 0.40, 0.40, seg, AMAT, 1.0, uv_atlas=black)
    m.cyl(add(base, mul(ax, 0.015)), add(base, mul(ax, 0.30)), 0.21, 0.13, seg, AMAT, 1.0, caps=(False, False),
          uv_atlas=RG['hat'])
    bend = add(add(base, mul(ax, 0.30)), (0.0, 0.0, 0.0))
    tip = add(add(base, mul(ax, 0.52)), (0.14, -0.04, 0.10))
    m.cyl(bend, tip, 0.13, 0.012, seg, AMAT, 1.0, caps=(False, True), uv_atlas=RG['hat'])
    m.cyl(add(base, mul(ax, 0.03)), add(base, mul(ax, 0.10)), 0.215, 0.205, seg, AMAT, 1.0, caps=(False, False),
          uv_atlas=Q.sw('#B7A6C9'))
    bow = add(add(base, mul(ax, 0.07)), (0.0, 0.0, 0.21))
    m.abox(bow, (0.10, 0.045, 0.02), AMAT, {'*': Q.sw('#B7A6C9')}, 1.0)


def chimney(m, lod):
    x, z = -2.60, -1.80
    y0 = Q.roof_y(z) - 0.20
    y1 = RIDGE + 0.05
    m.box((x - 0.24, y0, z - 0.24), (x + 0.24, y1, z + 0.24), 'V2_Plaster', 0.80, skip=('-y',))
    m.box((x - 0.28, y1, z - 0.28), (x + 0.28, y1 + 0.08, z + 0.28), 'V2_Stone', 0.70)


def gables(m, lod):
    reg = RG['gable_boards']
    for g in (GC, GL):
        Q.cross_gable(m, lod, g['cx'], HD, g['yp'], g['p2'], g['ov'], 'V2_Wood', 0.95, face_region=reg,
                      gegyo='#C9A24A' if g is GC else None)


def build(lod):
    m = K.Mesh('Kirisame_LOD%d' % lod, MATS, Q.TILE)
    if lod <= 1:
        m.box((-HW, BOT, -HD), (HW, PLINTH, HD), 'V2_Stone', 0.85, skip=('-y',))
        facade_1f(m, lod)
        facade_2f(m, lod)
        Q.sides_back(m, lod, back_door=(1.55, 2.45), side_windows=False, back_window=-1.2,
                     win_region=Q.sw('#D8CFB8'))
        Q.hisashi(m, lod, arms=POSTS)
        Q.main_roof(m, lod)
        gables(m, lod)
        chimney(m, lod)
    else:
        Q.lod2_shell(m, front_1f_region=RG['goods'])
        cx, cy, sw_, sh = SIGN
        Q.fz(m, cx - sw_ / 2, cx + sw_ / 2, cy - sh / 2, cy + sh / 2, HD + 0.08, AMAT, 1.0, RG['sign'])
        Q.fz(m, -0.90, 0.90, 1.58, 2.36, HD + 0.12, AMAT, 1.0, RG['noren'])
        Q.hisashi(m, 2)
        Q.main_roof_lod2(m)
        for g in (GC, GL):
            Q.cross_gable(m, 2, g['cx'], HD, g['yp'], g['p2'], g['ov'], 'V2_Wood', 0.95,
                          face_region=RG['gable_boards'])
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
    K.export_glb(bpy, OUT + '/src/kirisame.glb', objs)
    zf = HD
    spec = {
        '_note': '霧雨店 Hero 資產規格（build_kirisame.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、'
                 'verify_village_v2_hero_gate.gd 讀取）。尺寸 authority＝P4 greybox B_P_LM_KIRISAME。'
                 '設計依參考圖：一樓店面＋屋根裏（不加樓層）、中央＋左側千鳥破風。',
        'id': 'kirisame', 'landmark': 'LANDMARK_KIRISAME', 'kind': 'hero', 'budget_class': '霧雨店',
        'glb': 'res://assets/village_v2/kirisame/src/kirisame.glb',
        'scene': 'res://assets/village_v2/kirisame/kirisame.scn',
        'lod_objects': ['Kirisame_LOD0', 'Kirisame_LOD1', 'Kirisame_LOD2'],
        'lod_ranges_m': [0, 40, 110, 600],
        'budget': {'lod0': 60000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': {k: (ML[k]['tres'] if k in ML else 'res://assets/village_v2/kirisame/V2_Kirisame.tres')
                      for k in MATS},
        'spec': {'width_m': W, 'depth_m': D, 'eave_m': Q.EAVE, 'ridge_m': round(RIDGE, 3), 'plinth_m': PLINTH,
                 'foundation_bottom_m': BOT, 'hisashi_m': 2.7, 'hisashi_depth_m': Q.HIS_D, 'ov_eave_m': Q.OV_E,
                 'ov_gable_m': Q.OV_G, 'door_m': [DOOR[1] - DOOR[0], 2.10], 'floor_m': PLINTH,
                 'door_clear_m': [DOOR[1] - DOOR[0], round(LINTEL[0] - 0.35, 3)],
                 'design': {'storeys': '一樓店面＋屋根裏（無二樓窗）', 'cross_gables': ['中央（額）', '左小'],
                            'bays': 5}},
        'gate_spec': {
            'placement': 'greybox', 'anchor': 'Landmarks/LANDMARK_KIRISAME', 'replaces': 'Greybox',
            'p4_id': 'B_P_LM_KIRISAME', 'parcel': 'P_LM_KIRISAME', 'road': 'MainStreet',
            'size': {'x_half_max': HW + Q.OV_G + 0.12, 'z_min': -(HD + Q.OV_E + 0.12), 'z_max': HD + Q.HIS_D + 0.12,
                     'top': [round(RIDGE, 3), round(RIDGE + 0.30, 3)], 'bottom': BOT},
            'body': {'w': W, 'd': D, 'eave': Q.EAVE, 'ridge': round(RIDGE, 3), 'plinth': PLINTH},
            'door_clear': {'h': round(LINTEL[0] - 0.35, 3), 'w': round(DOOR[1] - DOOR[0], 3), 'min_h': 1.9,
                           'min_w': 1.2},
            'ground': [
                {'name': '台基', 'rect': [-HW, -HD, HW, HD], 'bottom': BOT, 'top': PLINTH, 'embed_max': 0.50},
                {'name': '踏石', 'rect': [-0.85, zf, 0.85, zf + 0.45], 'bottom': -0.14, 'top': 0.14, 'embed_max': 0.25},
                {'name': '展示台腳', 'rect': [1.065, zf + 0.095, 2.635, zf + 0.525], 'bottom': -0.10, 'top': 0.70,
                 'embed_max': 0.25},
                {'name': '花桶', 'rect': [3.45 - 0.27, zf + 0.06, 3.45 + 0.27, zf + 0.60], 'bottom': -0.12,
                 'top': 0.62, 'embed_max': 0.25},
                {'name': '黑板腳', 'rect': [-3.63, zf + 0.12, -2.97, zf + 0.56], 'bottom': -0.10, 'top': 0.02,
                 'embed_max': 0.25},
                {'name': '木箱', 'rect': [-2.55, zf + 0.10, -2.05, zf + 0.55], 'bottom': -0.10, 'top': 0.46,
                 'embed_max': 0.25},
                {'name': '勝手口踏石', 'rect': [1.60, -HD - 0.41, 2.40, -HD - 0.01], 'bottom': -0.12, 'top': 0.14,
                 'embed_max': 0.25}],
            'walkway': {'rect': [-HW, zf + 0.65, HW, zf + Q.HIS_D + 0.30], 'head': 1.95, 'min_clear': 2.0,
                        'step': 0.25},
            'entry': [0.0, zf + 0.95], 'inside': [0.0, 0.0]},
        'collision': [
            # 本體碰撞前緣推到 HD+0.20：蓋住門面突出物（玻璃櫃 0.12–0.15、唇帶 0.12、手摺），步行帶從 HD+0.65 起不受影響
            {'type': 'box', 'name': 'Body', 'center': [0, (BOT + Q.EAVE) / 2, 0.10], 'size': [W, Q.EAVE - BOT, D + 0.20]},
            {'type': 'convex', 'name': 'Step', 'center': [0, 0, 0], 'points': [
                [sx * 0.85, y, z] for sx in (-1, 1) for (y, z) in (
                    (-0.14, zf), (0.14, zf), (0.14, zf + 0.38), (-0.14, zf + 0.62))]},
            {'type': 'box', 'name': 'Table', 'center': [1.85, 0.31, zf + 0.31], 'size': [1.62, 0.82, 0.48]},
            {'type': 'box', 'name': 'Barrel', 'center': [3.45, 0.39, zf + 0.33], 'size': [0.56, 0.98, 0.54]},
            {'type': 'box', 'name': 'ChalkCrate', 'center': [-2.84, 0.48, zf + 0.335], 'size': [1.60, 1.16, 0.51]},
            {'type': 'box', 'name': 'BackStep', 'center': [2.0, 0.0, -HD - 0.21], 'size': [0.80, 0.26, 0.40]}],
        'measured_blender': stats,
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[KIRISAME]', stats)


main()
