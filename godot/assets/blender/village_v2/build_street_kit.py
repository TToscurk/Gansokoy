"""人間之里 V2 P10 R2：主街 Street Life Kit（street_kit）— 新資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_street_kit.py

讀感（TPS 3–25 m、主街を歩く玩家の目線）：「店の前に商品があふれ、職人が道端で働き、路地の口に行き先が分かる」——
  店頭の平台・雛壇・米俵・菓子台、置行灯・衝立看板・幟・提灯竿、道端の小さな作業場（桶屋・大工・藁細工）、
  巷口の道標、市の入口の大看板と荷、農田→住宅の境の農具・稲架・藁塚・柴垣。
材質：V2_Wood（_matlib、柱・板・脚）＋ST_Street（street_kit atlas：幟・看板・行灯・道標の字、提灯、稲藁・和紙・竹笊・柴・稲束・菰、色票）。
既存 Hero／P9／market_kit は只讀（擺放側で重用）。座標：Godot（x 右、y 上、+z 前＝通り側）；原點＝接地點（y 0）；單位 m。
  店頭：st_hiradai_yasai 八百屋の平台／st_hiradai_zakka 荒物の平台／st_hinadan_seto 瀬戸物の雛壇／st_hiradai_kashi 菓子の台／st_kome_tsumi 米俵積み
  看板：st_andon_{meshi,yasumi,kusuri} 置行灯／st_kanban_{sake,kome,kusuri,abura} 衝立看板／st_nobori_{sake,kome,meshi} 幟／st_chochin_{aka,shiro} 提灯竿
  作業：st_okeya 桶屋の作業場／st_daiku 大工の馬と板／st_wara 藁細工（草鞋掛け）
  巷口：st_fuda_{ichi,ta,kawa,yashiro} 道標／市の入口：st_ichi_kanban 大看板（提灯 2）／st_kago_tsumi 届いた荷（箱・籠）
  農田交界：st_kuwa 農具掛け／st_warazuka 藁塚／st_hasa 稲架／st_shibagaki 柴垣
  *_l1  LOD1
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/street_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(OUT + '/atlas.json')
REG = AT['regions']
SWC = AT['swatches']
WD = 'V2_Wood'
ST = 'ST_Street'
MATS = [WD, ST]
TILE = {WD: ML['V2_Wood']['tile_m'], ST: 1.0}

WOODC = (0.84, 0.78, 0.68)
AGED = (0.66, 0.62, 0.56)
OLD = (0.52, 0.48, 0.43)
DARK = (0.34, 0.29, 0.24)

MODS = {}
INFO = {}


def new(name, lod, note=''):
    n = name + ('_l1' if lod else '')
    m = K.Mesh(n, MATS, TILE)
    MODS[n] = m
    INFO[n] = note
    return m


# ─────────────────────────── 基本（build_market_kit.py と同じ作法） ───────────────────────────

def swr(key):
    u, v = SWC[key]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


def pc(m, ps, key):
    u, v = SWC[key]
    m.poly(ps, ST, 1.0, uvs=[(u, v)] * len(ps))


def bx(m, lo, hi, key):
    c = K.mul(K.add(lo, hi), 0.5)
    h = K.mul(K.sub(hi, lo), 0.5)
    m.abox(c, h, ST, {'*': swr(key)})


def obx(m, c, h, key, ax=K.X, ay=K.Y, az=K.Z):
    m.abox(c, h, ST, {'*': swr(key)}, 1.0, ax=ax, ay=ay, az=az)


def rbx(m, c, h, region, ax=K.X, ay=K.Y, az=K.Z):
    m.abox(c, h, ST, {'*': REG[region]}, 1.0, ax=ax, ay=ay, az=az)


def cy(m, p0, p1, r0, r1, seg, key, caps=(True, True)):
    m.cyl(p0, p1, r0, r1, seg, ST, 1.0, caps=caps, uv_atlas=swr(key))


def rcy(m, p0, p1, r0, r1, seg, region, caps=(True, True)):
    m.cyl(p0, p1, r0, r1, seg, ST, 1.0, caps=caps, uv_atlas=REG[region])


def ball(m, c, r, key, seg, squash=1.0):
    x, y, z = c
    ry = r * squash
    cy(m, (x, y - ry, z), (x, y - ry * 0.55, z), r * 0.25, r * 0.85, seg, key, caps=(True, False))
    cy(m, (x, y - ry * 0.55, z), (x, y + ry * 0.55, z), r * 0.85, r * 0.85, seg, key, caps=(False, False))
    cy(m, (x, y + ry * 0.55, z), (x, y + ry, z), r * 0.85, r * 0.25, seg, key, caps=(False, True))


def pole(m, p0, p1, r, key='take', seg=6):
    cy(m, p0, p1, r, r * 0.9, seg, key, caps=(False, True))


def wpost(m, x, z, y0, y1, r=0.05, col=AGED):
    m.box((x - r, y0, z - r), (x + r, y1, z + r), WD, col)


def board2(m, cx, y0, y1, z, hw, region, back='wood_light'):
    """両面の板（表＝region、裏＝back region か同じ region を裏から正しく読める向き）。"""
    m.rect_uv((cx - hw, y0, z + 0.012), (cx + hw, y0, z + 0.012), (cx + hw, y1, z + 0.012), (cx - hw, y1, z + 0.012), ST, REG[region])
    rb = REG[back] if back else REG[region]
    m.rect_uv((cx + hw, y0, z - 0.012), (cx - hw, y0, z - 0.012), (cx - hw, y1, z - 0.012), (cx + hw, y1, z - 0.012), ST, rb)


def zaru(m, x, y, z, r, lod, h=0.05):
    seg = 8 if lod else 12
    u0, v0, u1, v1 = REG['zaru']
    m.cyl((x, y, z), (x, y + h, z), r * 0.8, r, seg, ST, 1.0, caps=(True, False), uv_atlas=[u0, v0, u1, v0 + (v1 - v0) * 0.3])
    return y + h * 0.4


def kago(m, x, y, z, r, h, lod):
    seg = 8 if lod else 12
    m.cyl((x, y, z), (x, y + h, z), r * 0.82, r, seg, ST, 1.0, caps=(True, False), uv_atlas=REG['zaru'])
    cy(m, (x, y + h - 0.012, z), (x, y + h + 0.012, z), r + 0.012, r + 0.012, seg, 'take', caps=(False, False))
    return y + h


def daikon(m, x, y, z, ang, L, lod):
    d = (math.cos(ang), 0.0, math.sin(ang))
    tip = (x + d[0] * L, y, z + d[2] * L)
    cy(m, (x, y, z), tip, 0.035, 0.008, 5 if lod else 7, 'daikon', caps=(True, False))
    if not lod:
        lf = (x - d[0] * 0.22, y + 0.06, z - d[2] * 0.22)
        cy(m, (x, y, z), lf, 0.03, 0.05, 5, 'daikon_leaf', caps=(False, True))


def heap(m, cx, cy0, cz, rx, rz, n, r, key, rng, lod, squash=1.0, layer=2):
    k = 0
    for L in range(layer):
        cnt = n if L == 0 else max(1, n // 3)
        for i in range(cnt):
            if lod and k % 2 == 1:
                k += 1
                continue
            a = 2 * math.pi * i / cnt + rng.uniform(-0.3, 0.3) + L * 0.5
            rr = rng.uniform(0.25, 0.85) * (1.0 - 0.5 * L)
            ball(m, (cx + math.cos(a) * rx * rr, cy0 + r * squash * (1 + 1.5 * L), cz + math.sin(a) * rz * rr), r * rng.uniform(0.85, 1.1),
                 key, 5 if lod else 7, squash)
            k += 1


def jar(m, x, y, z, r, h, key, lod, lid=None):
    seg = 8 if lod else 12
    cy(m, (x, y, z), (x, y + h * 0.5, z), r * 0.7, r, seg, key, caps=(True, False))
    cy(m, (x, y + h * 0.5, z), (x, y + h * 0.88, z), r, r * 0.6, seg, key, caps=(False, False))
    cy(m, (x, y + h * 0.88, z), (x, y + h, z), r * 0.62, r * 0.62, seg, key, caps=(False, True))
    if lid:
        m.cyl((x, y + h, z), (x, y + h + 0.025, z), r * 0.7, r * 0.7, seg, WD, lid, caps=(False, True))


def bowl(m, x, y, z, r, h, key, lod):
    seg = 8 if lod else 12
    cy(m, (x, y, z), (x, y + h, z), r * 0.45, r, seg, key, caps=(True, False))
    if not lod:
        cy(m, (x, y + h, z), (x, y + h * 0.35, z), r * 0.96, r * 0.4, seg, 'hakuji', caps=(False, True))


def plates(m, x, y, z, r, n, key, lod):
    seg = 8 if lod else 12
    for i in range(n):
        cy(m, (x, y + i * 0.018, z), (x, y + i * 0.018 + 0.016, z), r * 0.7, r, seg, key, caps=(True, True))
    return y + n * 0.018


def tawara(m, x, y, z, yaw, lod, L=0.72, r=0.22):
    d = (math.cos(yaw), 0.0, -math.sin(yaw))
    a = (x - d[0] * L / 2, y + r, z - d[2] * L / 2)
    b = (x + d[0] * L / 2, y + r, z + d[2] * L / 2)
    seg = 8 if lod else 10
    u0, v0, u1, v1 = REG['straw']
    m.cyl(a, K.lerp(a, b, 0.12), r * 0.8, r, seg, ST, 1.0, caps=(True, False), uv_atlas=[u0, v0, u1, v1])
    m.cyl(K.lerp(a, b, 0.12), K.lerp(a, b, 0.88), r, r, seg, ST, 1.0, caps=(False, False), uv_atlas=[u0, v0, u1, v1])
    m.cyl(K.lerp(a, b, 0.88), b, r, r * 0.8, seg, ST, 1.0, caps=(False, True), uv_atlas=[u0, v0, u1, v1])
    if not lod:
        for t in (0.25, 0.5, 0.75):
            p = K.lerp(a, b, t)
            cy(m, K.add(p, K.mul(d, -0.012)), K.add(p, K.mul(d, 0.012)), r + 0.01, r + 0.01, seg, 'nawa', caps=(False, False))


def crate(m, x, y, z, w, h, d, yaw, col=AGED, lid=True):
    ax = (math.cos(yaw), 0.0, -math.sin(yaw))
    az = (math.sin(yaw), 0.0, math.cos(yaw))
    m.obox((x, y + h / 2, z), (w / 2, h / 2, d / 2), WD, col, ax=ax, ay=K.Y, az=az)
    if not lid:
        m.obox((x, y + h - 0.01, z), (w / 2 - 0.02, 0.012, d / 2 - 0.02), WD, DARK, ax=ax, ay=K.Y, az=az)


def hiradai(m, W, D, H, col=AGED):
    """平台：天板（板 4 枚の継ぎ目）＋脚 4＋貫。上面＝H。"""
    for i in range(4):
        z0 = -D / 2 + i * D / 4
        m.box((-W / 2, H - 0.035, z0 + 0.004), (W / 2, H, z0 + D / 4 - 0.004), WD, col if i % 2 else WOODC)
    for x in (-W / 2 + 0.05, W / 2 - 0.09):
        for z in (-D / 2 + 0.04, D / 2 - 0.08):
            m.box((x, 0.0, z), (x + 0.045, H - 0.035, z + 0.045), WD, OLD)
    m.box((-W / 2 + 0.05, 0.12, -D / 2 + 0.05), (W / 2 - 0.05, 0.16, -D / 2 + 0.08), WD, OLD)
    m.box((-W / 2 + 0.05, 0.12, D / 2 - 0.08), (W / 2 - 0.05, 0.16, D / 2 - 0.05), WD, OLD)


def straw_bundle(m, x, z, y0, h, r, lod, tilt=(0.0, 0.0), region='straw'):
    top = (x + tilt[0], y0 + h, z + tilt[1])
    rcy(m, (x, y0, z), top, r, r * 0.75, 6 if lod else 8, region, caps=(True, True))
    if not lod:
        cy(m, K.lerp((x, y0, z), top, 0.62), K.lerp((x, y0, z), top, 0.66), r * 0.86, r * 0.84, 8, 'nawa', caps=(False, False))


# ─────────────────────────── 店頭 ───────────────────────────

def hiradai_yasai(lod):
    m = new('st_hiradai_yasai', lod, '八百屋の平台 1.60 × 0.70（天板 0.45）：笊 5（茄子・人参・蜜柑・里芋・胡瓜）＋大根の束＋キャベツの山、脇に籠（葱）')
    rng = random.Random(20101)
    H = 0.45
    hiradai(m, 1.6, 0.7, H)
    for x, z, key, r in ((-0.55, 0.12, 'nasu', 0.04), (-0.05, 0.16, 'ninjin', 0.035), (0.48, 0.14, 'mikan', 0.045),
                         (0.2, -0.18, 'satoimo', 0.04), (-0.35, -0.2, 'kyuri', 0.03)):
        yy = zaru(m, x, H, z, 0.2, lod)
        heap(m, x, yy, z, 0.13, 0.13, 8, r, key, rng, lod, 1.2 if key in ('nasu', 'kyuri') else 0.95)
    for i in range(6 if not lod else 3):
        daikon(m, 0.6 + rng.uniform(-0.03, 0.03), H + 0.04 + (i % 2) * 0.05, -0.28 + i * 0.03, math.pi * 0.85, 0.42, lod)
    heap(m, -0.75, H, -0.05, 0.05, 0.12, 3, 0.09, 'kyabetsu', rng, lod, 0.8, layer=1)
    kago(m, 0.95, 0.0, 0.05, 0.18, 0.42, lod)
    for i in range(7 if not lod else 3):
        a = i * 0.9
        cy(m, (0.95 + math.cos(a) * 0.06, 0.3, 0.05 + math.sin(a) * 0.06), (0.95 + math.cos(a) * 0.12, 0.78, 0.05 + math.sin(a) * 0.12), 0.012, 0.01, 4, 'negi', caps=(False, True))
    return m


def hiradai_zakka(lod):
    m = new('st_hiradai_zakka', lod, '荒物の平台 1.60 × 0.70（天板 0.42）：笊の重ね 3 山・籠 2・柄杓立て、後ろに箒 3 本を立て掛け、脚元に桶')
    H = 0.42
    hiradai(m, 1.6, 0.7, H, OLD)
    for x, z, n in ((-0.55, 0.1, 6), (-0.05, 0.15, 4), (0.45, 0.1, 5)):
        y = H
        for i in range(n if not lod else 2):
            zaru(m, x, y, z, 0.22 - i * 0.008, lod, 0.06)
            y += 0.03
    kago(m, -0.45, H, -0.2, 0.16, 0.26, lod)
    kago(m, 0.25, H, -0.2, 0.2, 0.32, lod)
    m.cyl((0.62, H, -0.18), (0.62, H + 0.3, -0.18), 0.08, 0.09, 10 if not lod else 6, WD, AGED)
    for i in range(4 if not lod else 2):
        a = i * 1.57 + 0.4
        cy(m, (0.62 + math.cos(a) * 0.04, H + 0.25, -0.18 + math.sin(a) * 0.04), (0.62 + math.cos(a) * 0.1, H + 0.68, -0.18 + math.sin(a) * 0.1), 0.008, 0.008, 4, 'take')
    for i, x in enumerate((-0.7, -0.45, 0.85)):
        top = (x + 0.05, 1.45, -0.5)
        pole(m, (x, 0.42, -0.36), top, 0.014, 'take', 5)
        rcy(m, (x - 0.01, 0.0, -0.33), (x, 0.44, -0.36), 0.14, 0.035, 6 if lod else 8, 'straw', caps=(True, False))
    m.cyl((-0.85, 0.0, 0.25), (-0.85, 0.3, 0.25), 0.15, 0.17, 10 if not lod else 6, WD, AGED, caps=(True, False))
    return m


def hinadan_seto(lod):
    m = new('st_hinadan_seto', lod, '瀬戸物の雛壇 1.30 × 0.70（3 段 0.32／0.58／0.84）：染付の鉢・白磁の皿の重ね・飴釉の壺・急須、前に甕 2')
    rng = random.Random(20103)
    W = 1.3
    steps = ((0.32, 0.12, 0.35), (0.58, -0.1, 0.13), (0.84, -0.3, -0.08))
    for y, z0, z1 in steps:
        m.box((-W / 2, y - 0.03, z0 - 0.0), (W / 2, y, z1), WD, AGED)
        m.box((-W / 2, 0.0, z1 - 0.03), (W / 2, y - 0.03, z1), WD, OLD)
    for x in (-W / 2, W / 2 - 0.04):
        m.box((x, 0.0, -0.35), (x + 0.04, 0.86, 0.36), WD, OLD)
    keys = ['sometsuke', 'hakuji', 'ameyu', 'kokuyu', 'haiyu']
    for si, (y, z0, z1) in enumerate(steps):
        zc = (z0 + z1) / 2
        for i in range(5 if not lod else 3):
            x = -0.5 + i * 0.25
            k = keys[(i + si) % len(keys)]
            if si == 0:
                plates(m, x, y, zc, 0.1, 3 if not lod else 2, k, lod)
            elif si == 1:
                bowl(m, x, y, zc, 0.09, 0.07, k, lod)
            else:
                if i % 2 == 0:
                    jar(m, x, y, zc, 0.07, 0.18, k, lod)
                else:
                    ball(m, (x, y + 0.06, zc), 0.06, k, 7 if lod else 10, 0.8)
    jar(m, -0.42, 0.0, 0.55, 0.2, 0.46, 'ameyu', lod, lid=OLD)
    jar(m, 0.0, 0.0, 0.6, 0.16, 0.36, 'kokuyu', lod)
    _ = rng
    return m


def hiradai_kashi(lod):
    m = new('st_hiradai_kashi', lod, '菓子の台 1.40 × 0.60（天板 0.45、緋毛氈）：煎餅の箱 2・飴の壺 3（黄・赤・白）・金平糖の盆、小さな品札')
    rng = random.Random(20104)
    H = 0.45
    hiradai(m, 1.4, 0.6, H, WOODC)
    pc(m, [(-0.68, H + 0.004, 0.28), (0.68, H + 0.004, 0.28), (0.68, H + 0.004, -0.28), (-0.68, H + 0.004, -0.28)], 'mousen')
    pc(m, [(-0.68, H + 0.004, 0.28), (-0.68, H - 0.16, 0.3), (0.68, H - 0.16, 0.3), (0.68, H + 0.004, 0.28)], 'mousen')
    for x in (-0.45, -0.05):
        m.box((x - 0.17, H, 0.0), (x + 0.17, H + 0.08, 0.24), WD, WOODC)
        for i in range(6 if not lod else 2):
            cy(m, (x - 0.12 + i * 0.05, H + 0.08, 0.12), (x - 0.12 + i * 0.05, H + 0.095, 0.12), 0.04, 0.04, 8, 'senbei')
    for i, (x, key) in enumerate(((0.25, 'ame_y'), (0.45, 'ame_r'), (0.62, 'ame_w'))):
        jar(m, x, H, -0.12, 0.08, 0.2, 'hakuji', lod)
        heap(m, x, H + 0.2, -0.12, 0.04, 0.04, 4, 0.018, key, rng, lod, 1.0, layer=1)
    m.box((0.2, H, 0.08), (0.5, H + 0.02, 0.24), WD, DARK)
    heap(m, 0.35, H + 0.02, 0.16, 0.1, 0.05, 9, 0.012, 'konpeito', rng, lod, 1.0, layer=1)
    m.box((-0.66, H, -0.25), (-0.62, H + 0.3, -0.21), WD, OLD)
    m.rect_uv((-0.7, H + 0.12, -0.2), (-0.58, H + 0.12, -0.2), (-0.58, H + 0.3, -0.2), (-0.7, H + 0.3, -0.2), ST, REG['paper'])
    return m


def kome_tsumi(lod):
    m = new('st_kome_tsumi', lod, '米屋の俵積み：台 1.50 × 0.90 × 0.12、米俵 3＋2＋1（全高 1.40）、前に枡 2 と箕（立て掛け）')
    m.box((-0.75, 0.0, -0.45), (0.75, 0.12, 0.45), WD, OLD)
    y = 0.12
    for row, n in enumerate((3, 2, 1)):
        for i in range(n):
            x = (i - (n - 1) / 2) * 0.46
            tawara(m, x, y + row * 0.38, 0.0, math.pi / 2, lod, 0.78, 0.21)
    for x in (-0.45, 0.0):
        m.box((x - 0.12, 0.0, 0.52), (x + 0.12, 0.17, 0.76), WD, WOODC)
        if not lod:
            bx(m, (x - 0.1, 0.12, 0.54), (x + 0.1, 0.16, 0.74), 'kome')
    u0, v0, u1, v1 = REG['zaru']
    m.abox((0.55, 0.32, 0.58), (0.28, 0.3, 0.02), ST, {'*': [u0, v0, u1, v1]}, 1.0,
           ax=K.X, ay=K.norm((0.0, 1.0, -0.35)), az=K.norm((0.0, 0.35, 1.0)))
    return m


# ─────────────────────────── 看板・行灯・幟・提灯 ───────────────────────────

def andon(key, lod):
    m = new('st_andon_' + key, lod, '置行灯「%s」：脚台 0.40 角（高 0.30）＋和紙の箱 0.30 × 0.30 × 0.62（表裏に字、両側は無地）＋笠、全高 1.05' %
            {'meshi': 'めし', 'yasumi': '御休処', 'kusuri': '薬'}[key])
    for x in (-0.18, 0.15):
        for z in (-0.18, 0.15):
            m.box((x, 0.0, z), (x + 0.03, 0.32, z + 0.03), WD, DARK)
    m.box((-0.2, 0.28, -0.2), (0.2, 0.32, 0.2), WD, DARK)
    y0, y1, hw = 0.32, 0.94, 0.15
    region = 'andon_' + key
    board2(m, 0.0, y0, y1, hw - 0.012, hw, region, back=None)
    for sx in (-1, 1):
        x = sx * hw
        m.rect_uv((x, y0, hw * sx), (x, y0, -hw * sx), (x, y1, -hw * sx), (x, y1, hw * sx), ST, REG['paper'])
    for x in (-hw - 0.012, hw - 0.012):
        for z in (-hw - 0.012, hw - 0.012):
            m.box((x, y0, z), (x + 0.024, y1, z + 0.024), WD, DARK)
    m.box((-0.2, y1, -0.2), (0.2, y1 + 0.04, 0.2), WD, DARK)
    if not lod:
        m.box((-0.06, y1 + 0.04, -0.06), (0.06, y1 + 0.1, 0.06), WD, DARK)
    return m


def kanban_tate(key, lod):
    m = new('st_kanban_' + key, lod, '衝立看板「%s」：足 2（0.60）＋柱 2（1.70）＋板 0.44 × 1.20（表裏同じ字）＋笠木、全高 1.78' %
            {'sake': '酒', 'kome': '御米', 'kusuri': 'くすり', 'abura': '油'}[key])
    for x in (-0.25, 0.25):
        m.box((x - 0.035, 0.0, -0.3), (x + 0.035, 0.07, 0.3), WD, OLD)
        m.box((x - 0.03, 0.0, -0.03), (x + 0.03, 1.72, 0.03), WD, AGED)
    m.rect_uv((-0.22, 0.42, 0.035), (0.22, 0.42, 0.035), (0.22, 1.62, 0.035), (-0.22, 1.62, 0.035), ST, REG['kanban_' + key])
    m.rect_uv((0.22, 0.42, -0.035), (-0.22, 0.42, -0.035), (-0.22, 1.62, -0.035), (0.22, 1.62, -0.035), ST, REG['kanban_' + key])
    m.box((-0.22, 0.42, -0.03), (0.22, 1.62, 0.03), WD, OLD, skip=('+z', '-z'))
    m.box((-0.33, 1.7, -0.08), (0.33, 1.78, 0.08), WD, DARK)
    return m


def nobori(key, lod):
    m = new('st_nobori_' + key, lod, '幟「%s」：竹竿 4.0（地に 0.3 埋め・石の根止め）、布 0.45 × 1.8、風で 3 段に緩く折れる' %
            {'sake': '酒', 'kome': '米', 'meshi': '御食事'}[key])
    H = 3.7
    pole(m, (0.0, -0.3, 0.0), (0.0, H, 0.0), 0.022, 'take')
    m.cyl((0.0, 0.0, 0.0), (0.0, 0.1, 0.0), 0.09, 0.07, 6, WD, OLD)
    pole(m, (0.0, H - 0.08, 0.0), (0.5, H - 0.08, 0.0), 0.012, 'take')
    u0, v0, u1, v1 = REG['nobori_' + key]
    top, bot = H - 0.1, H - 1.9
    n = 1 if lod else 3
    for i in range(n):
        ta, tb = i / n, (i + 1) / n
        ya = top - (top - bot) * ta
        yb = top - (top - bot) * tb
        za = 0.05 * math.sin(math.pi * ta * 1.5) if not lod else 0.0
        zb = 0.05 * math.sin(math.pi * tb * 1.5) if not lod else 0.0
        xa = 0.03 + 0.02 * ta
        xb = 0.03 + 0.02 * tb
        a, b, c, d = (xb, yb, zb), (xb + 0.45, yb, zb + 0.04), (xa + 0.45, ya, za + 0.04), (xa, ya, za)
        va = v0 + (v1 - v0) * ta
        vb = v0 + (v1 - v0) * tb
        m.quad(a, b, c, d, ST, 1.0, uvs=[(u0, vb), (u1, vb), (u1, va), (u0, va)])   # 表：a（竿側）＝u0（2026-10-07 修正：表が鏡像だった）
        m.quad(b, a, d, c, ST, 1.0, uvs=[(u0, vb), (u1, vb), (u1, va), (u0, va)])   # 裏：b＝u0（表と位置ごとに左右反転＝裏からも正しく読める、2026-10-07）
    return m


def chochin_lantern(m, c, r, h, region, lod):
    x, y, z = c
    seg = 8 if lod else 12
    rcy(m, (x, y - h * 0.5, z), (x, y - h * 0.3, z), r * 0.7, r, seg, region, caps=(False, False))
    rcy(m, (x, y - h * 0.3, z), (x, y + h * 0.3, z), r, r, seg, region, caps=(False, False))
    rcy(m, (x, y + h * 0.3, z), (x, y + h * 0.5, z), r, r * 0.7, seg, region, caps=(False, False))
    cy(m, (x, y - h * 0.56, z), (x, y - h * 0.5, z), r * 0.72, r * 0.72, seg, 'sumi')
    cy(m, (x, y + h * 0.5, z), (x, y + h * 0.56, z), r * 0.72, r * 0.72, seg, 'sumi')


def chochin_sao(key, lod):
    m = new('st_chochin_' + key, lod, '提灯竿（%s）：柱 2.40（埋 0.30）＋腕木 0.55 ＋提灯 Ø0.36 × 0.56、石の根止め' %
            {'aka': '赤・「御」', 'shiro': '白・丸に一の紋'}[key])
    m.box((-0.045, -0.3, -0.045), (0.045, 2.4, 0.045), WD, AGED)
    m.cyl((0.0, 0.0, 0.0), (0.0, 0.12, 0.0), 0.14, 0.11, 6, WD, OLD)
    m.box((-0.03, 2.22, -0.03), (0.03, 2.28, 0.58), WD, AGED)
    m.beam((0.0, 1.95, 0.0), (0.0, 2.24, 0.3), 0.035, 0.035, WD, AGED)
    cy(m, (0.0, 2.22, 0.5), (0.0, 2.06, 0.5), 0.004, 0.004, 3, 'sumi', caps=(False, False))
    chochin_lantern(m, (0.0, 1.76, 0.5), 0.18, 0.56, 'chochin_' + key, lod)
    return m


# ─────────────────────────── 作業場 ───────────────────────────

def shavings(m, cx, cz, rx, rz, n, rng, key='kanna'):
    for i in range(n):
        a = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(0.0, 1.0)
        x = cx + math.cos(a) * rx * rr
        z = cz + math.sin(a) * rz * rr
        s = rng.uniform(0.04, 0.09)
        b = rng.uniform(0, math.pi)
        pc(m, [(x - math.cos(b) * s, 0.006, z - math.sin(b) * s), (x + math.sin(b) * s * 0.5, 0.012, z - math.cos(b) * s * 0.5),
               (x + math.cos(b) * s, 0.006, z + math.sin(b) * s), (x - math.sin(b) * s * 0.5, 0.01, z + math.cos(b) * s * 0.5)], key)


def okeya(lod):
    m = new('st_okeya', lod, '桶屋の作業場（約 2.0 × 1.2）：作業の丸太台 Ø0.42、箍を締めかけの桶（側板が開いた状態）、出来た桶 2・盥、側板の束、竹の箍 3 を立て掛け、腰掛け、鉋屑')
    rng = random.Random(20201)
    m.cyl((-0.55, 0.0, 0.1), (-0.55, 0.45, 0.1), 0.21, 0.2, 12 if not lod else 7, WD, OLD)
    # 締めかけの桶：側板 14 枚を少し開いて立て、箍 1
    n = 14 if not lod else 8
    for i in range(n):
        a = 2 * math.pi * i / n
        r0, r1 = 0.22, 0.26
        p0 = (0.15 + math.cos(a) * r0, 0.0, 0.25 + math.sin(a) * r0)
        p1 = (0.15 + math.cos(a) * r1, 0.58, 0.25 + math.sin(a) * r1)
        m.beam(p0, p1, 0.09, 0.022, WD, WOODC if i % 3 else AGED, up=(math.cos(a), 0.0, math.sin(a)))
    cy(m, (0.15, 0.12, 0.25), (0.15, 0.16, 0.25), 0.235, 0.235, 12 if not lod else 7, 'takebe', caps=(False, False))
    for x, z, r, h in ((0.75, -0.25, 0.2, 0.36), (0.75, 0.3, 0.17, 0.3)):
        m.cyl((x, 0.0, z), (x, h, z), r * 0.92, r, 12 if not lod else 7, WD, WOODC, caps=(True, False))
        for t in (0.25, 0.75):
            cy(m, (x, h * t - 0.015, z), (x, h * t + 0.015, z), r * (0.95 + 0.05 * t) + 0.008, r * (0.95 + 0.05 * t) + 0.008, 12 if not lod else 7, 'takebe', caps=(False, False))
    m.cyl((-0.2, 0.0, -0.4), (-0.2, 0.16, -0.4), 0.3, 0.32, 12 if not lod else 7, WD, AGED, caps=(True, False))
    for i in range(7 if not lod else 3):
        x = -0.85 + i * 0.05
        m.beam((x, 0.0, -0.45), (x + 0.12, 0.62, -0.55), 0.08, 0.018, WD, WOODC if i % 2 else AGED)
    for i in range(3):
        c = (-0.95 + i * 0.07, 0.28 + i * 0.02, 0.45)
        m.cyl(K.add(c, (0.0, 0.0, -0.01)), K.add(c, (0.0, 0.0, 0.01)), 0.27 - i * 0.03, 0.27 - i * 0.03, 12 if not lod else 7, ST, 1.0, caps=(False, False), uv_atlas=swr('takebe'))
    m.box((-0.15, 0.0, 0.55), (0.15, 0.28, 0.75), WD, OLD)
    if not lod:
        shavings(m, -0.1, 0.1, 0.7, 0.45, 26, rng)
        cy(m, (-0.5, 0.46, 0.05), (-0.25, 0.47, 0.0), 0.015, 0.015, 5, 'tetsu')
    return m


def daiku(lod):
    m = new('st_daiku', lod, '大工の作業場（約 2.2 × 1.1）：馬（作業台）2 に板 2.0 を渡し鋸を載せる、丸太 1、道具箱（鋸の柄・墨壺）、立て掛けた板 3、鉋屑')
    rng = random.Random(20202)
    for x in (-0.7, 0.7):
        for sz_ in (-1, 1):
            m.beam((x - 0.25, 0.0, sz_ * 0.18), (x - 0.05, 0.6, 0.0), 0.05, 0.05, WD, OLD)
            m.beam((x + 0.25, 0.0, sz_ * 0.18), (x + 0.05, 0.6, 0.0), 0.05, 0.05, WD, OLD)
        m.box((x - 0.35, 0.58, -0.05), (x + 0.35, 0.66, 0.05), WD, AGED)
    m.box((-1.0, 0.66, -0.13), (1.0, 0.7, 0.13), WD, WOODC)
    bx(m, (0.1, 0.7, -0.07), (0.55, 0.706, 0.03), 'hagane')
    m.box((0.55, 0.7, -0.04), (0.72, 0.74, 0.0), WD, DARK)
    m.cyl((-0.9, 0.17, 0.42), (0.6, 0.17, 0.42), 0.17, 0.15, 10 if not lod else 6, WD, OLD)
    m.box((0.75, 0.0, 0.25), (1.15, 0.24, 0.5), WD, AGED)
    if not lod:
        m.box((0.78, 0.24, 0.3), (1.12, 0.26, 0.45), WD, DARK)
        cy(m, (0.85, 0.27, 0.38), (1.05, 0.27, 0.38), 0.02, 0.02, 5, 'kuri')
        bx(m, (0.9, 0.24, 0.27), (0.98, 0.3, 0.33), 'sumi')
    for i in range(3):
        x = -1.05 + i * 0.06
        m.beam((x, 0.0, -0.32), (x + 0.1, 1.55, -0.55), 0.24, 0.025, WD, WOODC if i == 1 else AGED)
    if not lod:
        shavings(m, 0.0, 0.0, 0.9, 0.45, 30, rng)
    return m


def wara(lod):
    m = new('st_wara', lod, '藁細工の作業場（約 1.6 × 1.0）：筵 1.4 × 0.9 に藁束 3（立てる）・編みかけの草鞋、後ろに草鞋掛け（枠 1.0 × 1.4、草鞋 8 足）、腰掛け')
    rng = random.Random(20203)
    u0, v0, u1, v1 = REG['straw']
    m.quad((-0.7, 0.012, 0.45), (0.7, 0.012, 0.45), (0.7, 0.012, -0.45), (-0.7, 0.012, -0.45), ST, 0.92, uvs=[(u0, v1), (u1, v1), (u1, v0), (u0, v0)])
    for x, z in ((-0.45, 0.1), (-0.25, 0.25), (0.45, 0.05)):
        straw_bundle(m, x, z, 0.012, 0.75 + rng.uniform(-0.05, 0.05), 0.11, lod, (rng.uniform(-0.04, 0.04), rng.uniform(-0.04, 0.04)))
    for i in range(3 if not lod else 1):
        m.abox((0.0 + i * 0.12, 0.03, 0.15), (0.05, 0.012, 0.12), ST, {'*': [u0, v0, u1, v1]})
    m.box((0.15, 0.0, -0.1), (0.42, 0.26, 0.1), WD, OLD)
    # 草鞋掛け：枠＋横木 3、草鞋（吊るし）
    for x in (-0.5, 0.5):
        m.box((x - 0.03, 0.0, -0.45), (x + 0.03, 1.4, -0.39), WD, AGED)
    for y in (0.6, 0.95, 1.3):
        cy(m, (-0.52, y, -0.42), (0.52, y, -0.42), 0.012, 0.012, 5, 'take', caps=(False, False))
        for i in range(4 if not lod else 2):
            x = -0.36 + i * 0.24
            m.abox((x, y - 0.13, -0.4), (0.05, 0.12, 0.012), ST, {'*': [u0, v0, u1, v1]})
            if not lod:
                cy(m, (x, y, -0.41), (x, y - 0.02, -0.4), 0.006, 0.006, 3, 'nawa', caps=(False, False))
    return m


# ─────────────────────────── 巷口・市の入口 ───────────────────────────

def fuda(key, lod):
    m = new('st_fuda_' + key, lod, '道標「%s」：柱 1.70（埋 0.30）＋札 0.22 × 0.80（表裏に字＋指し矢）＋小屋根、根元に石' %
            {'ichi': '市此方', 'ta': '田畑', 'kawa': '水車', 'yashiro': '御社'}[key])
    m.box((-0.05, -0.3, -0.05), (0.05, 1.7, 0.05), WD, AGED)
    m.rect_uv((-0.11, 0.85, 0.052), (0.11, 0.85, 0.052), (0.11, 1.65, 0.052), (-0.11, 1.65, 0.052), ST, REG['fuda_' + key])
    m.rect_uv((0.11, 0.85, 0.028), (-0.11, 0.85, 0.028), (-0.11, 1.65, 0.028), (0.11, 1.65, 0.028), ST, REG['fuda_' + key])
    m.box((-0.11, 0.85, 0.03), (0.11, 1.65, 0.05), WD, OLD, skip=('+z', '-z'))
    m.box((-0.16, 1.7, -0.08), (0.16, 1.74, 0.14), WD, DARK)
    if not lod:
        cy(m, (0.05, 0.0, 0.12), (0.06, 0.16, 0.13), 0.12, 0.07, 6, 'haiyu')
    return m


def ichi_kanban(lod):
    m = new('st_ichi_kanban', lod, '市の入口の大看板：柱 2（2.30、埋 0.30）＋大板 0.80 × 1.20（朱縁「市 この奥」＋指し矢、表裏）＋屋根＋赤提灯 2、足元に石')
    for x in (-0.5, 0.5):
        m.box((x - 0.05, -0.3, -0.05), (x + 0.05, 2.3, 0.05), WD, AGED)
        if not lod:
            cy(m, (x, 0.0, 0.0), (x, 0.14, 0.0), 0.15, 0.1, 6, 'haiyu')
    m.rect_uv((-0.4, 0.75, 0.05), (0.4, 0.75, 0.05), (0.4, 1.95, 0.05), (-0.4, 1.95, 0.05), ST, REG['ichi_big'])
    m.rect_uv((0.4, 0.75, -0.05), (-0.4, 0.75, -0.05), (-0.4, 1.95, -0.05), (0.4, 1.95, -0.05), ST, REG['ichi_big'])
    m.box((-0.45, 0.72, -0.045), (0.45, 0.75, 0.045), WD, DARK)
    m.box((-0.45, 1.95, -0.045), (0.45, 1.99, 0.045), WD, DARK)
    # 屋根（切妻の板 2 枚）
    for s in (-1, 1):
        m.obox((0.0, 2.36, s * 0.13), (0.72, 0.02, 0.17), WD, DARK, ax=K.X, ay=K.norm((0.0, 1.0, s * 0.5)), az=K.norm((0.0, -s * 0.5, 1.0)))
    m.box((-0.7, 2.18, -0.04), (0.7, 2.24, 0.04), WD, AGED)
    for x in (-0.62, 0.62):
        cy(m, (x, 2.18, 0.0), (x, 2.02, 0.0), 0.004, 0.004, 3, 'sumi', caps=(False, False))
        chochin_lantern(m, (x, 1.82, 0.0), 0.13, 0.4, 'chochin_aka', lod)
    return m


def kago_tsumi(lod):
    m = new('st_kago_tsumi', lod, '届いた荷（市の入口）：開けた木箱 2（大根・南瓜）、籠 3（蜜柑・林檎・茄子）、麻袋 1、縄掛けの箱 1；1.30 × 0.80')
    rng = random.Random(20301)
    crate(m, -0.35, 0.0, 0.1, 0.6, 0.34, 0.44, 0.08, AGED, lid=False)
    for i in range(6 if not lod else 3):
        daikon(m, -0.6 + rng.uniform(-0.02, 0.02), 0.32 + (i % 2) * 0.04, -0.02 + i * 0.045, 0.1, 0.5, lod)
    crate(m, 0.3, 0.0, 0.15, 0.56, 0.32, 0.42, -0.1, OLD, lid=False)
    for i, (x, z) in enumerate(((0.2, 0.1), (0.42, 0.2), (0.3, 0.02))):
        ball(m, (x, 0.32 + 0.09, z), 0.12, 'kabocha', 7 if lod else 10, 0.72)
    for x, z, key in ((-0.45, -0.32, 'mikan'), (0.05, -0.3, 'ringo'), (0.5, -0.28, 'nasu')):
        y = kago(m, x, 0.0, z, 0.17, 0.26, lod)
        heap(m, x, y - 0.02, z, 0.1, 0.1, 6, 0.04, key, rng, lod, 1.0 if key != 'nasu' else 1.25, layer=1)
    crate(m, -0.35, 0.34, 0.12, 0.5, 0.26, 0.38, 0.3, AGED)
    if not lod:
        for t in (-0.1, 0.12):
            cy(m, (-0.6, 0.61, 0.12 + t), (-0.1, 0.61, 0.12 + t), 0.01, 0.01, 4, 'nawa', caps=(False, False))
    rbx(m, (0.68, 0.22, -0.05), (0.16, 0.22, 0.15), 'komo')
    return m


# ─────────────────────────── 農田交界 ───────────────────────────

def kuwa(lod):
    m = new('st_kuwa', lod, '農具掛け（1.30 × 0.60）：柱 2（1.50）＋横木 2、鍬 2・鋤 1・熊手 1 を立て掛け、蓑 1 を吊るし、足元に鎌を入れた籠')
    for x in (-0.6, 0.6):
        m.box((x - 0.04, 0.0, -0.3), (x + 0.04, 1.5, -0.22), WD, OLD)
    for y in (0.75, 1.42):
        m.box((-0.66, y, -0.29), (0.66, y + 0.06, -0.23), WD, AGED)
    for i, x in enumerate((-0.4, -0.15, 0.15, 0.4)):
        top = (x + 0.02, 1.48, -0.18)
        bot = (x - 0.04, 0.05, 0.22)
        m.beam(bot, top, 0.035, 0.035, WD, AGED)
        if i in (0, 1):            # 鍬：刃（鉄）
            obx(m, K.add(bot, (0.0, 0.06, 0.06)), (0.08, 0.1, 0.012), 'hagane', ay=K.norm((0.0, 0.3, 1.0)), az=K.norm((0.0, 1.0, -0.3)))
        elif i == 2:               # 鋤
            obx(m, K.add(bot, (0.0, 0.1, 0.0)), (0.1, 0.16, 0.012), 'hagane', ay=K.norm((0.0, 1.0, -0.27)), az=K.norm((0.0, 0.27, 1.0)))
        else:                      # 熊手（竹）
            for k in range(7 if not lod else 3):
                cy(m, K.add(bot, (-0.15 + k * 0.05, 0.02, 0.0)), K.add(bot, (-0.03 + k * 0.01, 0.32, -0.06)), 0.006, 0.006, 3, 'take', caps=(False, False))
    # 蓑（藁の外套）：上が狭い台形の厚板を横木から吊るす
    u0, v0, u1, v1 = REG['straw']
    for s in (1, -1):
        zz = -0.17 if s > 0 else -0.21
        m.quad((-0.35 * s, 0.75, zz), (0.35 * s, 0.75, zz), (0.18 * s, 1.4, zz), (-0.18 * s, 1.4, zz), ST, 0.85 if s > 0 else 0.7,
               uvs=[(u0, v1), (u1, v1), (u1, v0), (u0, v0)])
    kago(m, 0.85, 0.0, 0.1, 0.16, 0.28, lod)
    for k in range(3 if not lod else 1):
        cy(m, (0.82 + k * 0.03, 0.2, 0.1), (0.8 + k * 0.05, 0.5, 0.15), 0.012, 0.012, 4, 'kuri')
    return m


def warazuka(lod):
    m = new('st_warazuka', lod, '藁塚 Ø1.40 × 1.75：芯柱＋稲藁を円錐に積み、頂に藁の笠、縄 1 巻き；田の縁の脱穀後の藁')
    seg = 10 if lod else 14
    rcy(m, (0.0, 0.0, 0.0), (0.0, 0.25, 0.0), 0.62, 0.7, seg, 'straw', caps=(True, False))
    rcy(m, (0.0, 0.25, 0.0), (0.0, 1.05, 0.0), 0.7, 0.55, seg, 'straw', caps=(False, False))
    rcy(m, (0.0, 1.05, 0.0), (0.0, 1.45, 0.0), 0.55, 0.3, seg, 'ine', caps=(False, False))
    rcy(m, (0.0, 1.4, 0.0), (0.0, 1.62, 0.0), 0.42, 0.08, seg, 'straw', caps=(False, True))
    m.box((-0.03, 1.55, -0.03), (0.03, 1.78, 0.03), WD, OLD)
    if not lod:
        cy(m, (0.0, 0.62, 0.0), (0.0, 0.66, 0.0), 0.67, 0.665, seg, 'nawa', caps=(False, False))
    return m


def hasa(lod):
    m = new('st_hasa', lod, '稲架 3.0 × 0.8（高 1.90）：X 脚 3 組＋横竿 2 段（1.10／1.60）、稲束を竿に振り分けて掛ける（上段 12・下段 10、穂が下）')
    rng = random.Random(20401)
    for x in (-1.45, 0.0, 1.45):
        m.beam((x - 0.35, 0.0, 0.3), (x + 0.1, 1.9, -0.05), 0.05, 0.05, WD, OLD)
        m.beam((x + 0.35, 0.0, -0.3), (x - 0.1, 1.9, 0.05), 0.05, 0.05, WD, OLD)
    for y in (1.1, 1.6):
        pole(m, (-1.55, y, 0.0), (1.55, y, 0.0), 0.025, 'take', 6)
    for row, (y, n) in enumerate(((1.6, 12), (1.1, 10))):
        for i in range(n if not lod else n // 2):
            x = -1.35 + 2.7 * i / max(1, (n if not lod else n // 2) - 1)
            for s in (-1, 1):
                top = (x, y + 0.02, s * 0.03)
                bot = (x + rng.uniform(-0.03, 0.03), y - 0.48, s * 0.14)
                rcy(m, top, bot, 0.06, 0.085, 5 if lod else 6, 'ine', caps=(True, True))
    return m


def shibagaki(lod):
    m = new('st_shibagaki', lod, '柴垣 3.0 × 1.10：杭 3（埋 0.30）＋胴縁 2、柴（小枝の束）を縦に詰めた面（厚 0.10、上端は不揃い）')
    rng = random.Random(20402)
    for x in (-1.45, 0.0, 1.45):
        m.box((x - 0.04, -0.3, -0.04), (x + 0.04, 1.15, 0.04), WD, OLD)
    for y in (0.35, 0.85):
        m.box((-1.5, y, 0.05), (1.5, y + 0.05, 0.09), WD, AGED)
        m.box((-1.5, y, -0.09), (1.5, y + 0.05, -0.05), WD, AGED)
    n = 10 if not lod else 4
    u0, v0, u1, v1 = REG['shiba']
    for i in range(n):
        xa = -1.45 + 2.9 * i / n
        xb = -1.45 + 2.9 * (i + 1) / n
        ta = 1.0 + rng.uniform(-0.08, 0.1)
        tb = 1.0 + rng.uniform(-0.08, 0.1)
        ua = u0 + (u1 - u0) * (i % 4) / 4
        ub = u0 + (u1 - u0) * ((i % 4) + 1) / 4
        for z, f in ((0.045, 1.0), (-0.045, 0.82)):
            if z > 0:
                m.quad((xa, 0.0, z), (xb, 0.0, z), (xb, tb, z), (xa, ta, z), ST, f, uvs=[(ua, v1), (ub, v1), (ub, v0), (ua, v0)])
            else:
                m.quad((xb, 0.0, z), (xa, 0.0, z), (xa, ta, z), (xb, tb, z), ST, f, uvs=[(ub, v1), (ua, v1), (ua, v0), (ub, v0)])
        m.quad((xa, ta, 0.045), (xb, tb, 0.045), (xb, tb, -0.045), (xa, ta, -0.045), ST, 0.7, uvs=[(ua, v0), (ub, v0), (ub, v0 + 0.01), (ua, v0 + 0.01)])
    return m


def ido(lod):
    m = new('st_ido', lod, '井戸（井戸端）：石の井筒 Ø1.10 × 0.72（内は暗い水面）＋半分の板蓋、柱 2（2.10）＋切妻の小屋根＋滑車・釣瓶（縄で吊る）、脇に盥と手桶、足元に踏み石 2')
    seg = 10 if lod else 16
    m.cyl((0.0, 0.0, 0.0), (0.0, 0.72, 0.0), 0.56, 0.55, seg, ST, 1.0, caps=(False, False), uv_atlas=swr('haiyu'))
    m.cyl((0.0, 0.72, 0.0), (0.0, 0.3, 0.0), 0.42, 0.42, seg, ST, 0.55, caps=(False, False), uv_atlas=swr('haiyu'))
    m.cyl((0.0, 0.3, 0.0), (0.0, 0.72, 0.0), 0.42, 0.42, seg, ST, 0.55, caps=(False, False), uv_atlas=swr('haiyu'))
    cy(m, (0.0, 0.7, 0.0), (0.0, 0.76, 0.0), 0.58, 0.56, seg, 'haiyu', caps=(False, False))
    ring = [(math.cos(a) * 0.42, 0.45, math.sin(a) * 0.42) for a in [2 * math.pi * i / seg for i in range(seg)]]
    pc(m, ring, 'kon')
    pc(m, ring[::-1], 'kon')
    if not lod:
        for i in range(seg):
            a = 2 * math.pi * (i + 0.5) / seg
            cy(m, (math.cos(a) * 0.555, 0.24, math.sin(a) * 0.555), (math.cos(a) * 0.555, 0.26, math.sin(a) * 0.555), 0.02, 0.02, 4, 'kokuyu', caps=(False, False))
    for i in range(4):
        z = -0.48 + i * 0.12
        m.box((-0.55, 0.76, z), (0.55, 0.79, z + 0.11), WD, AGED if i % 2 else WOODC)
    for x in (-0.7, 0.7):
        m.box((x - 0.05, 0.0, -0.05), (x + 0.05, 2.1, 0.05), WD, AGED)
    m.box((-0.8, 1.95, -0.05), (0.8, 2.03, 0.05), WD, AGED)
    for s in (-1, 1):
        m.obox((0.0, 2.2, s * 0.2), (0.95, 0.02, 0.24), WD, DARK, ax=K.X, ay=K.norm((0.0, 1.0, s * 0.75)), az=K.norm((0.0, -s * 0.75, 1.0)))
    m.cyl((-0.06, 1.85, 0.0), (0.06, 1.85, 0.0), 0.09, 0.09, 8, WD, OLD)
    cy(m, (0.0, 1.93, 0.0), (0.0, 1.95, 0.0), 0.01, 0.01, 3, 'nawa', caps=(False, False))
    cy(m, (0.0, 1.85, 0.09), (0.0, 1.05, 0.09), 0.008, 0.008, 4, 'nawa', caps=(False, False))
    m.cyl((0.0, 0.8, 0.09), (0.0, 1.05, 0.09), 0.12, 0.13, 8 if lod else 12, WD, WOODC)
    m.cyl((0.95, 0.0, 0.45), (0.95, 0.16, 0.45), 0.3, 0.33, 8 if lod else 12, WD, AGED, caps=(True, False))
    m.cyl((0.8, 0.0, -0.45), (0.8, 0.24, -0.45), 0.13, 0.14, 8 if lod else 12, WD, WOODC, caps=(True, False))
    if not lod:
        cy(m, (0.68, 0.24, -0.45), (0.92, 0.24, -0.45), 0.012, 0.012, 4, 'take', caps=(False, False))
        for x, z in ((-0.3, 0.85), (0.35, 0.95)):
            cy(m, (x, -0.1, z), (x, 0.04, z), 0.2, 0.18, 7, 'haiyu')
    return m


def onobori(lod):
    m = new('st_onobori_ichi', lod, '大幟「市 此方」：杉の柱 7.6（埋 0.4・石の根止め）、横竿 0.9、布 0.80 × 4.20（下端 3.0 m＝軒より上に出る遠目の目印、両面）')
    H = 7.6
    m.cyl((0.0, -0.4, 0.0), (0.0, H, 0.0), 0.06, 0.045, 8, WD, AGED)
    m.cyl((0.0, 0.0, 0.0), (0.0, 0.2, 0.0), 0.2, 0.16, 8, WD, OLD)
    pole(m, (0.0, H - 0.12, 0.0), (0.92, H - 0.12, 0.0), 0.016, 'take')
    u0, v0, u1, v1 = REG['onobori_ichi']
    top, bot = H - 0.15, H - 4.35
    n = 1 if lod else 4
    for i in range(n):
        ta, tb = i / n, (i + 1) / n
        ya = top - (top - bot) * ta
        yb = top - (top - bot) * tb
        za = 0.08 * math.sin(math.pi * ta * 1.3) if not lod else 0.0
        zb = 0.08 * math.sin(math.pi * tb * 1.3) if not lod else 0.0
        a, b, c, d = (0.07, yb, zb), (0.87, yb, zb + 0.05), (0.87, ya, za + 0.05), (0.07, ya, za)
        va = v0 + (v1 - v0) * ta
        vb = v0 + (v1 - v0) * tb
        m.quad(a, b, c, d, ST, 1.0, uvs=[(u0, vb), (u1, vb), (u1, va), (u0, va)])   # 表：a（竿側）＝u0（2026-10-07 修正：表が鏡像だった）
        m.quad(b, a, d, c, ST, 1.0, uvs=[(u0, vb), (u1, vb), (u1, va), (u0, va)])   # 裏：b＝u0（表と位置ごとに左右反転＝裏からも正しく読める、2026-10-07）
    return m


# ─────────────────────────── 出力 ───────────────────────────

def build_all():
    for lod in (0, 1):
        hiradai_yasai(lod)
        hiradai_zakka(lod)
        hinadan_seto(lod)
        hiradai_kashi(lod)
        kome_tsumi(lod)
        for k in ('meshi', 'yasumi', 'kusuri'):
            andon(k, lod)
        for k in ('sake', 'kome', 'kusuri', 'abura'):
            kanban_tate(k, lod)
        for k in ('sake', 'kome', 'meshi'):
            nobori(k, lod)
        for k in ('aka', 'shiro'):
            chochin_sao(k, lod)
        okeya(lod)
        daiku(lod)
        wara(lod)
        for k in ('ichi', 'ta', 'kawa', 'yashiro'):
            fuda(k, lod)
        ichi_kanban(lod)
        kago_tsumi(lod)
        kuwa(lod)
        warazuka(lod)
        hasa(lod)
        shibagaki(lod)
        ido(lod)
        onobori(lod)


def dims(m):
    xs = [p[0] for p in m.v]
    ys = [p[1] for p in m.v]
    zs = [p[2] for p in m.v]
    return [round(min(xs), 4), round(min(ys), 4), round(min(zs), 4), round(max(xs), 4), round(max(ys), 4), round(max(zs), 4)]


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
        manifest[name] = {'tris': tri, 'dims': dims(m), 'mats': sorted({m.mats[f[1]] for f in m.f}), 'note': INFO[name]}
    os.makedirs(OUT + '/src', exist_ok=True)
    K.export_glb(bpy, OUT + '/src/street_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_street_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=street_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[STKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/street_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[STKIT]   %-20s %5d 面  LOD1 %4d  dims %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims']))


main()
