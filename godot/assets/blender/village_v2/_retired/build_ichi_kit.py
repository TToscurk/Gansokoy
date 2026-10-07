"""人間之里 V2 P10 R1b：市集西通り Kit（ichi_kit）— 新資產（docs/reference/市集資產 の参考図に基づく自作 procedural）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_ichi_kit.py

參考と讀感（TPS 3–20 m）：市集攤.png の「屋根の形で店が分かる」小屋形の店 3 種（瓦屋根の八百屋・茅葺きの瀬戸物・板屋根の反物）、
  04 の段々の野菜棚・吊るし物の竿・棚・腰掛け、01／05 の花紋の暖簾・縞の卓布・巾着・反物の積み、02／03 の染付・流し釉・藁巻き甕・縄掛けの瓶、
  06 の野菜の箱と籠、旗桿.png の花紋の長旗、木箱木桶稻草.png の樽と藁束。市集 R1（market_kit）の語彙と色を崩さず、
  「屋根のある店」「段々の陳列」「吊るし物」で輪郭と密度を足す。
材質：V2_Wood（柱・板）＋V2_Kawara（瓦屋根、_matlib の桟瓦：u＝x／4.24、v＝坂／2.4）＋IC_Ichi（ichi_kit atlas：暖簾・旗・布・器・茅・板屋根・作物の色票）。
座標：Godot（x 右、y 上、+z 前＝客側）；原點＝接地點；單位 m。*_l1＝LOD1。
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/ichi_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(OUT + '/atlas.json')
REG = AT['regions']
SWC = AT['swatches']
WD = 'V2_Wood'
KW = 'V2_Kawara'
IC = 'IC_Ichi'
MATS = [WD, KW, IC]
TILE = {WD: ML['V2_Wood']['tile_m'], KW: ML['V2_Kawara']['tile_m'], IC: 1.0}

# 市集 R1 の木より一段明るく（vision 講評：小屋の中・棚・樽が黒い塊に沈む）
WOODC = (1.0, 0.95, 0.85)
AGED = (0.88, 0.83, 0.75)
OLD = (0.74, 0.69, 0.62)
DARK = (0.5, 0.44, 0.37)

MODS = {}
INFO = {}


def new(name, lod, note=''):
    n = name + ('_l1' if lod else '')
    m = K.Mesh(n, MATS, TILE)
    MODS[n] = m
    INFO[n] = note
    return m


def swr(key):
    u, v = SWC[key]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


def pc(m, ps, key):
    u, v = SWC[key]
    m.poly(ps, IC, 1.0, uvs=[(u, v)] * len(ps))


def bx(m, lo, hi, key):
    c = K.mul(K.add(lo, hi), 0.5)
    h = K.mul(K.sub(hi, lo), 0.5)
    m.abox(c, h, IC, {'*': swr(key)})


def obx(m, c, h, key, ax=K.X, ay=K.Y, az=K.Z):
    m.abox(c, h, IC, {'*': swr(key)}, 1.0, ax=ax, ay=ay, az=az)


def rbx(m, c, h, region, ax=K.X, ay=K.Y, az=K.Z, col=1.0):
    m.abox(c, h, IC, {'*': REG[region]}, col, ax=ax, ay=ay, az=az)


def cy(m, p0, p1, r0, r1, seg, key, caps=(True, True)):
    m.cyl(p0, p1, r0, r1, seg, IC, 1.0, caps=caps, uv_atlas=swr(key))


def rcy(m, p0, p1, r0, r1, seg, region, caps=(True, True), col=1.0):
    m.cyl(p0, p1, r0, r1, seg, IC, col, caps=caps, uv_atlas=REG[region])


def ball(m, c, r, key, seg, squash=1.0):
    x, y, z = c
    ry = r * squash
    cy(m, (x, y - ry, z), (x, y - ry * 0.55, z), r * 0.25, r * 0.85, seg, key, caps=(True, False))
    cy(m, (x, y - ry * 0.55, z), (x, y + ry * 0.55, z), r * 0.85, r * 0.85, seg, key, caps=(False, False))
    cy(m, (x, y + ry * 0.55, z), (x, y + ry, z), r * 0.85, r * 0.25, seg, key, caps=(False, True))


def pole(m, p0, p1, r, key='take', seg=6):
    cy(m, p0, p1, r, r * 0.9, seg, key, caps=(False, True))


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


def daikon(m, x, y, z, ang, L, lod, key='daikon', leaf='daikon_leaf', r=0.035):
    d = (math.cos(ang), 0.0, math.sin(ang))
    tip = (x + d[0] * L, y, z + d[2] * L)
    cy(m, (x, y, z), tip, r, r * 0.22, 5 if lod else 7, key, caps=(True, False))
    if not lod:
        lf = (x - d[0] * 0.22, y + 0.07, z - d[2] * 0.22)
        cy(m, (x, y, z), lf, r * 0.8, r * 1.4, 5, leaf, caps=(False, True))


def jar(m, x, y, z, r, h, key, lod, region=None):
    seg = 8 if lod else 12
    if region:
        rcy(m, (x, y, z), (x, y + h * 0.5, z), r * 0.7, r, seg, region, caps=(True, False))
        rcy(m, (x, y + h * 0.5, z), (x, y + h * 0.88, z), r, r * 0.6, seg, region, caps=(False, False))
    else:
        cy(m, (x, y, z), (x, y + h * 0.5, z), r * 0.7, r, seg, key, caps=(True, False))
        cy(m, (x, y + h * 0.5, z), (x, y + h * 0.88, z), r, r * 0.6, seg, key, caps=(False, False))
    cy(m, (x, y + h * 0.88, z), (x, y + h, z), r * 0.62, r * 0.62, seg, key, caps=(False, True))


def bowl(m, x, y, z, r, h, lod, region='sometsuke', inner='hakuji'):
    seg = 8 if lod else 12
    rcy(m, (x, y, z), (x, y + h, z), r * 0.45, r, seg, region, caps=(True, False))
    if not lod:
        cy(m, (x, y + h, z), (x, y + h * 0.35, z), r * 0.96, r * 0.4, seg, inner, caps=(False, True))


def bowls(m, x, y, z, r, n, lod, region='sometsuke'):
    for i in range(n if not lod else min(n, 2)):
        bowl(m, x, y + i * 0.035, z, r - i * 0.004, 0.06, lod, region)


def zaru(m, x, y, z, r, lod, h=0.05):
    seg = 8 if lod else 12
    u0, v0, u1, v1 = REG['zaru']
    m.cyl((x, y, z), (x, y + h, z), r * 0.8, r, seg, IC, 1.0, caps=(True, False), uv_atlas=[u0, v0, u1, v0 + (v1 - v0) * 0.3])
    return y + h * 0.4


def kago(m, x, y, z, r, h, lod):
    seg = 8 if lod else 12
    m.cyl((x, y, z), (x, y + h, z), r * 0.82, r, seg, IC, 1.0, caps=(True, False), uv_atlas=REG['zaru'])
    cy(m, (x, y + h - 0.012, z), (x, y + h + 0.012, z), r + 0.012, r + 0.012, seg, 'take', caps=(False, False))
    return y + h


def crate(m, x, y, z, w, h, d, col=AGED, lid=False, yaw=0.0):
    ax = (math.cos(yaw), 0.0, -math.sin(yaw))
    az = (math.sin(yaw), 0.0, math.cos(yaw))
    m.obox((x, y + h / 2, z), (w / 2, h / 2, d / 2), WD, col, ax=ax, ay=K.Y, az=az)
    if not lid:
        m.obox((x, y + h - 0.012, z), (w / 2 - 0.025, 0.01, d / 2 - 0.025), WD, DARK, ax=ax, ay=K.Y, az=az)
    return y + h


PRODUCE = {
    'daikon': lambda m, x, y, z, w, d, rng, lod: [daikon(m, x - w * 0.35 + rng.uniform(-0.02, 0.02), y + 0.03 + (i % 2) * 0.04, z - d * 0.3 + i * d * 0.12, 0.05, w * 0.8, lod)
                                                  for i in range(6 if not lod else 3)],
    'ninjin': lambda m, x, y, z, w, d, rng, lod: [daikon(m, x - w * 0.3, y + 0.025 + (i % 2) * 0.03, z - d * 0.3 + i * d * 0.1, 0.1, w * 0.55, lod, 'ninjin', 'negi_ao', 0.025)
                                                  for i in range(7 if not lod else 3)],
    'kyabetsu': lambda m, x, y, z, w, d, rng, lod: heap(m, x, y, z, w * 0.3, d * 0.3, 4, 0.1, 'kyabetsu', rng, lod, 0.8, 1),
    'hakusai': lambda m, x, y, z, w, d, rng, lod: [ball(m, (x + s * w * 0.2, y + 0.09, z), 0.1, 'hakusai', 7, 1.9) for s in (-1, 1)],
    'tomato': lambda m, x, y, z, w, d, rng, lod: heap(m, x, y, z, w * 0.35, d * 0.35, 9, 0.04, 'tomato', rng, lod, 0.85),
    'nasu': lambda m, x, y, z, w, d, rng, lod: heap(m, x, y, z, w * 0.35, d * 0.35, 8, 0.04, 'nasu', rng, lod, 1.4),
    'jagaimo': lambda m, x, y, z, w, d, rng, lod: heap(m, x, y, z, w * 0.36, d * 0.36, 10, 0.04, 'jagaimo', rng, lod, 0.8),
    'tamanegi': lambda m, x, y, z, w, d, rng, lod: heap(m, x, y, z, w * 0.35, d * 0.35, 8, 0.045, 'tamanegi', rng, lod, 0.95),
    'kaki': lambda m, x, y, z, w, d, rng, lod: heap(m, x, y, z, w * 0.35, d * 0.35, 8, 0.042, 'kaki', rng, lod, 0.7),
    'yuzu': lambda m, x, y, z, w, d, rng, lod: heap(m, x, y, z, w * 0.35, d * 0.35, 9, 0.038, 'yuzu', rng, lod, 0.95),
    'ringo': lambda m, x, y, z, w, d, rng, lod: heap(m, x, y, z, w * 0.35, d * 0.35, 9, 0.042, 'ringo', rng, lod, 0.9),
    'kabocha': lambda m, x, y, z, w, d, rng, lod: [ball(m, (x + s * w * 0.18, y + 0.1, z + s * d * 0.1), 0.12, 'kabocha', 8 if lod else 10, 0.72) for s in (-1, 1)],
    'kabu': lambda m, x, y, z, w, d, rng, lod: heap(m, x, y, z, w * 0.33, d * 0.33, 7, 0.05, 'kabu', rng, lod, 0.9),
    'piman': lambda m, x, y, z, w, d, rng, lod: heap(m, x, y, z, w * 0.35, d * 0.35, 9, 0.04, 'piman', rng, lod, 1.1),
    'negi': lambda m, x, y, z, w, d, rng, lod: [cy(m, (x - w * 0.4 + 0.0, y + 0.03 + (i % 3) * 0.025, z - d * 0.3 + i * d * 0.07), (x + w * 0.45, y + 0.04 + (i % 3) * 0.025, z - d * 0.3 + i * d * 0.07), 0.015, 0.015, 5, 'negi' if i % 2 else 'negi_ao', caps=(True, True))
                                                for i in range(9 if not lod else 4)],
    'satoimo': lambda m, x, y, z, w, d, rng, lod: heap(m, x, y, z, w * 0.36, d * 0.36, 10, 0.035, 'satoimo', rng, lod, 1.0),
}


def produce(m, kind, x, y, z, w, d, rng, lod):
    PRODUCE[kind](m, x, y, z, w, d, rng, lod)


def crate_of(m, kind, x, z, w, h, d, rng, lod, y=0.0, yaw=0.0):
    top = crate(m, x, y, z, w, h, d, AGED if rng.random() < 0.5 else OLD, yaw=yaw)
    produce(m, kind, x, top - 0.04, z, w, d, rng, lod)


def basket_of(m, kind, x, z, r, h, rng, lod, y=0.0):
    top = kago(m, x, y, z, r, h, lod)
    produce(m, kind, x, top - 0.05, z, r * 1.6, r * 1.6, rng, lod)


def cloth(m, a, b, c, d, region, back=True, col=1.0):
    m.rect_uv(a, b, c, d, IC, REG[region], col)
    if back:
        m.rect_uv(b, a, d, c, IC, REG[region], col * 0.85)


def noren(m, x0, x1, y_top, h, z, region, panels, lod):
    """暖簾：竿＋ panels 枚（隙間 0.02、裾をわずかに前へ）。"""
    pole(m, (x0 - 0.08, y_top + 0.03, z), (x1 + 0.08, y_top + 0.03, z), 0.018, 'take')
    u0, v0, u1, v1 = REG[region]
    pw = (x1 - x0) / panels
    nv = 1 if lod else 3
    for i in range(panels):
        xa = x0 + i * pw + 0.012
        xb = x0 + (i + 1) * pw - 0.012
        ua = u0 + (u1 - u0) * i / panels
        ub = u0 + (u1 - u0) * (i + 1) / panels
        # 布の垂れ：上は竿に沿って平ら、下へ向かって前へ膨らみ、裾の両端が少し内へ寄る（参考図 01 の暖簾）
        for j in range(nv):
            ta, tb = j / nv, (j + 1) / nv
            dza = 0.0 if lod else 0.07 * math.sin(math.pi * ta * 0.85)
            dzb = 0.0 if lod else 0.07 * math.sin(math.pi * tb * 0.85)
            ia = 0.0 if lod else 0.012 * ta
            ib = 0.0 if lod else 0.012 * tb
            ya, yb = y_top - h * ta, y_top - h * tb
            va = v0 + (v1 - v0) * ta
            vb = v0 + (v1 - v0) * tb
            a, b, c, d = (xa + ib, yb, z + dzb), (xb - ib, yb, z + dzb), (xb - ia, ya, z + dza), (xa + ia, ya, z + dza)
            m.quad(a, b, c, d, IC, 1.0, uvs=[(ua, vb), (ub, vb), (ub, va), (ua, va)])
            m.quad(b, a, d, c, IC, 0.82, uvs=[(ub, vb), (ua, vb), (ua, va), (ub, va)])


def lantern(m, c, r, h, lod, region='chochin_hana'):
    x, y, z = c
    seg = 8 if lod else 12
    rcy(m, (x, y - h * 0.5, z), (x, y - h * 0.3, z), r * 0.7, r, seg, region, caps=(False, False))
    rcy(m, (x, y - h * 0.3, z), (x, y + h * 0.3, z), r, r, seg, region, caps=(False, False))
    rcy(m, (x, y + h * 0.3, z), (x, y + h * 0.5, z), r, r * 0.7, seg, region, caps=(False, False))
    cy(m, (x, y - h * 0.56, z), (x, y - h * 0.5, z), r * 0.72, r * 0.72, seg, 'sumi')
    cy(m, (x, y + h * 0.5, z), (x, y + h * 0.56, z), r * 0.72, r * 0.72, seg, 'sumi')


def hang_bundle(m, x, y, z, L, key, lod, r=0.05):
    cy(m, (x, y, z), (x, y - 0.12, z), 0.006, 0.006, 3, 'nawa', caps=(False, False))
    if key == 'togarashi':
        for i in range(9 if not lod else 4):
            ball(m, (x + 0.02 * ((i % 2) * 2 - 1), y - 0.16 - i * L / 10, z), 0.02, 'togarashi', 5, 1.8)
    elif key == 'ninniku':
        for i in range(6 if not lod else 3):
            ball(m, (x + 0.025 * ((i % 2) * 2 - 1), y - 0.18 - i * L / 7, z), 0.035, 'ninniku', 6, 0.9)
    else:
        rcy(m, (x, y - 0.12, z), (x, y - 0.12 - L, z), r * 0.6, r * 1.2, 6, 'straw', caps=(True, True))
        if not lod:
            cy(m, (x, y - 0.18, z), (x, y - 0.12 - L * 0.9, z), r * 0.9, r * 1.4, 6, 'wakakusa', caps=(False, True))


# ─────────────────────────── 小屋形の店（市集攤.png） ───────────────────────────

W2, D2 = 1.25, 0.95          # 柱の半間口・半奥行
EAVE_F, EAVE_B, RIDGE = 2.3, 2.3, 3.15


def koya_frame(m, lod):
    """4 本柱＋桁・梁＋背の板壁＋腰の側板＋縄の結び。"""
    for x in (-W2, W2):
        for z in (-D2, D2):
            m.box((x - 0.065, 0.0, z - 0.065), (x + 0.065, EAVE_F, z + 0.065), WD, AGED)
            if not lod:
                cy(m, (x, EAVE_F - 0.35, z), (x, EAVE_F - 0.28, z), 0.08, 0.08, 6, 'nawa', caps=(False, False))
    for z in (-D2, D2):
        m.box((-W2 - 0.25, EAVE_F - 0.12, z - 0.07), (W2 + 0.25, EAVE_F, z + 0.07), WD, OLD)
    for x in (-W2, W2):
        m.box((x - 0.07, EAVE_F - 0.12, -D2 - 0.07), (x + 0.07, EAVE_F + 0.05, D2 + 0.07), WD, OLD)
    m.box((-W2, 0.0, -D2 - 0.04), (W2, EAVE_F - 0.12, -D2 + 0.02), WD, OLD)          # 背の板壁
    for x in (-W2, W2):
        m.box((x - 0.02, 0.0, -D2), (x + 0.02, 0.95, D2), WD, AGED)                   # 腰の側板
    # 棟束
    m.box((-0.05, EAVE_F, -0.05), (0.05, RIDGE - 0.08, 0.05), WD, OLD)


def roof_planes(lod):
    """切妻の 2 面（前・後）の頂点：[(ridge_l, ridge_r, eave_r, eave_l)]、外法線、坂長。"""
    ox = W2 + 0.45
    oz = D2 + 0.5
    ef = EAVE_F - 0.18
    out = []
    for s in (1, -1):
        rl, rr = (-ox, RIDGE, 0.0), (ox, RIDGE, 0.0)
        el, er = (-ox, ef, s * oz), (ox, ef, s * oz)
        out.append((s, rl, rr, er, el))
    return out


def koya_counter(m, lod, front_region):
    """前の売り台（0.85）：天板＋前垂れの布。"""
    m.box((-W2 + 0.05, 0.8, D2 - 0.42), (W2 - 0.05, 0.86, D2 + 0.12), WD, WOODC)
    m.box((-W2 + 0.05, 0.0, D2 - 0.05), (W2 - 0.05, 0.8, D2 + 0.05), WD, OLD)
    cloth(m, (-W2 + 0.1, 0.42, D2 + 0.13), (W2 - 0.1, 0.42, D2 + 0.13), (W2 - 0.1, 0.86, D2 + 0.13), (-W2 + 0.1, 0.86, D2 + 0.13), front_region, back=False)


def koya_shelves(m, lod):
    for y in (1.05, 1.5):
        m.box((-W2 + 0.08, y, -D2 + 0.04), (W2 - 0.08, y + 0.04, -D2 + 0.38), WD, WOODC)


def koya_yasai(lod):
    m = new('ic_koya_yasai', lod, '瓦屋根の八百屋の小屋（市集攤.png 左）：柱 4（間口 2.5・奥 1.9）、切妻の桟瓦屋根（棟 3.15・軒 2.12、出 0.45／0.5）＋棟瓦、'
            '藍の花紋の暖簾 3 枚、弁柄の提灯、売り台に野菜の箱 5（大根・人参・キャベツ・トマト・茄子）＋格子の前垂れ、背の棚に甕と瓶、右に脇台と籠、吊るし薬草')
    rng = random.Random(30101)
    koya_frame(m, lod)
    tu, tv = 4.24, 2.4
    for s, rl, rr, er, el in roof_planes(lod):
        S = math.dist(rl, el)
        if s > 0:
            m.quad(el, er, rr, rl, KW, 1.0, uvs=[(el[0] / tu, S / tv), (er[0] / tu, S / tv), (rr[0] / tu, 0.0), (rl[0] / tu, 0.0)])
            m.quad(rl, rr, er, el, WD, 0.5)
        else:
            m.quad(er, el, rl, rr, KW, 1.0, uvs=[(-er[0] / tu, S / tv), (-el[0] / tu, S / tv), (-rl[0] / tu, 0.0), (-rr[0] / tu, 0.0)])
            m.quad(rr, rl, el, er, WD, 0.5)
        # 軒先の厚み（瓦の小口）
        m.beam(el, er, 0.06, 0.06, WD, DARK)
    cy(m, (-W2 - 0.5, RIDGE + 0.04, 0.0), (W2 + 0.5, RIDGE + 0.04, 0.0), 0.09, 0.09, 8 if lod else 12, 'kokuyu')
    if not lod:
        for x in (-W2 - 0.5, W2 + 0.5):
            cy(m, (x - 0.03 * (1 if x > 0 else -1), RIDGE + 0.04, 0.0), (x + 0.05 * (1 if x > 0 else -1), RIDGE + 0.04, 0.0), 0.13, 0.13, 10, 'kokuyu')
    koya_counter(m, lod, 'nuno_koshi')
    koya_shelves(m, lod)
    for i, (x, kind) in enumerate(((-0.95, 'daikon'), (-0.48, 'ninjin'), (0.0, 'kyabetsu'), (0.48, 'tomato'), (0.95, 'nasu'))):
        crate_of(m, kind, x, D2 - 0.15, 0.42, 0.1, 0.42, rng, lod, y=0.86)
    for x in (-0.9, -0.45, 0.0, 0.5, 0.95):
        jar(m, x, 1.09, -D2 + 0.2, 0.09 + 0.02 * (int(x * 10) % 2), 0.28, 'ameyu' if x < 0 else 'midori_bin', lod)
    for x in (-0.8, -0.2, 0.4):
        crate(m, x, 1.54, -D2 + 0.2, 0.42, 0.2, 0.3, OLD, lid=True)
    noren(m, -W2, W2, EAVE_F - 0.14, 0.42, D2 + 0.2, 'noren_ai', 3, lod)
    cy(m, (-W2 - 0.2, EAVE_F - 0.14, D2 + 0.45), (-W2 - 0.2, EAVE_F - 0.4, D2 + 0.45), 0.005, 0.005, 3, 'nawa', caps=(False, False))
    lantern(m, (-W2 - 0.2, EAVE_F - 0.66, D2 + 0.45), 0.15, 0.48, lod)
    for i in range(3 if not lod else 1):
        hang_bundle(m, W2 + 0.12, EAVE_F - 0.15, D2 - 0.2 - i * 0.25, 0.42, 'yakuso', lod)
    # 右の脇台＋籠
    m.box((W2 + 0.3, 0.55, 0.1), (W2 + 0.95, 0.6, 0.65), WD, WOODC)
    for x in (W2 + 0.33, W2 + 0.88):
        for z in (0.13, 0.6):
            m.box((x - 0.025, 0.0, z - 0.025), (x + 0.025, 0.55, z + 0.025), WD, OLD)
    basket_of(m, 'yuzu', W2 + 0.62, 0.38, 0.16, 0.16, rng, lod, y=0.6)
    basket_of(m, 'kabocha', -W2 - 0.55, 0.55, 0.26, 0.3, rng, lod)
    return m


def koya_seto(lod):
    m = new('ic_koya_seto', lod, '茅葺きの瀬戸物の小屋（市集攤.png 中）：柱 4、厚い茅の切妻（厚 0.26、棟に押さえ竹）、生成りの草花の暖簾、'
            '売り台と背の棚に染付・飴釉・灰釉の碗・甕・急須、前に低い台（大鉢）、吊り看板（甕の絵）')
    rng = random.Random(30102)
    koya_frame(m, lod)
    for s, rl, rr, er, el in roof_planes(lod):
        nrm = K.norm(K.cross(K.sub(er, el), K.sub(rl, el))) if s > 0 else K.norm(K.cross(K.sub(rl, el), K.sub(er, el)))
        c = K.mul(K.add(K.add(rl, rr), K.add(er, el)), 0.25)
        S = math.dist(rl, el)
        dsl = K.norm(K.sub(el, rl))
        thick = 0.26
        rbx(m, K.add(c, K.mul(nrm, thick * 0.5)), (W2 + 0.55, S * 0.5 + 0.06, thick * 0.5), 'kaya', ax=K.X, ay=dsl, az=nrm)
    cy(m, (-W2 - 0.6, RIDGE + 0.2, 0.0), (W2 + 0.6, RIDGE + 0.2, 0.0), 0.14, 0.14, 8 if lod else 10, 'wara')
    if not lod:
        for x in (-0.9, -0.3, 0.3, 0.9):
            cy(m, (x, RIDGE + 0.05, -0.35), (x, RIDGE + 0.05, 0.35), 0.025, 0.025, 5, 'take', caps=(True, True))
    koya_counter(m, lod, 'nuno_hana_kinari')
    koya_shelves(m, lod)
    for i, x in enumerate((-1.0, -0.6, -0.2, 0.2, 0.6, 1.0)):
        bowls(m, x, 0.86, D2 - 0.15, 0.12, 3, lod, 'sometsuke' if i % 2 == 0 else 'haiyu')
    for i, x in enumerate((-0.95, -0.5, 0.0, 0.5, 0.95)):
        if i % 2:
            jar(m, x, 1.09, -D2 + 0.2, 0.11, 0.3, 'ameyu', lod, region='ameyu_drip')
        else:
            bowls(m, x, 1.09, -D2 + 0.2, 0.1, 2, lod, 'sometsuke')
    for i, x in enumerate((-0.8, -0.3, 0.2, 0.7)):
        jar(m, x, 1.54, -D2 + 0.2, 0.09, 0.26, 'haiyu_c' if i % 2 else 'seiji', lod)
    noren(m, -W2, W2, EAVE_F - 0.14, 0.4, D2 + 0.22, 'noren_kinari', 3, lod)
    # 吊り看板（右の柱から）
    m.box((W2 + 0.05, EAVE_F - 0.3, D2 + 0.04), (W2 + 0.45, EAVE_F - 0.25, D2 + 0.1), WD, OLD)
    cloth(m, (W2 + 0.13, EAVE_F - 0.95, D2 + 0.07), (W2 + 0.37, EAVE_F - 0.95, D2 + 0.07), (W2 + 0.37, EAVE_F - 0.32, D2 + 0.07), (W2 + 0.13, EAVE_F - 0.32, D2 + 0.07), 'kanban_kame')
    # 前の低い台（大鉢）
    m.box((-0.55, 0.42, D2 + 0.55), (0.55, 0.47, D2 + 1.05), WD, WOODC)
    for x in (-0.5, 0.45):
        for z in (D2 + 0.6, D2 + 1.0):
            m.box((x - 0.03, 0.0, z - 0.03), (x + 0.03, 0.42, z + 0.03), WD, OLD)
    bowl(m, -0.25, 0.47, D2 + 0.8, 0.2, 0.11, lod, 'haiyu')
    bowl(m, 0.25, 0.47, D2 + 0.8, 0.18, 0.1, lod, 'sometsuke')
    jar(m, -W2 - 0.4, 0.0, 0.5, 0.22, 0.55, 'kokuyu', lod)
    jar(m, -W2 - 0.45, 0.0, -0.05, 0.18, 0.42, 'ameyu', lod, region='ameyu_drip')
    _ = rng
    return m


def koya_nuno(lod):
    m = new('ic_koya_nuno', lod, '板屋根の反物の小屋（市集攤.png 右）：柱 4、板葺きの切妻（押縁）、弁柄の花紋の暖簾 4 枚、背に下げた反物 5 本、'
            '売り台に巻いた反物と畳んだ布の山、前垂れ、右に提灯、前に布を積んだ箱')
    rng = random.Random(30103)
    koya_frame(m, lod)
    for s, rl, rr, er, el in roof_planes(lod):
        nrm = K.norm(K.cross(K.sub(er, el), K.sub(rl, el))) if s > 0 else K.norm(K.cross(K.sub(rl, el), K.sub(er, el)))
        c = K.mul(K.add(K.add(rl, rr), K.add(er, el)), 0.25)
        S = math.dist(rl, el)
        dsl = K.norm(K.sub(el, rl))
        rbx(m, K.add(c, K.mul(nrm, 0.04)), (W2 + 0.48, S * 0.5 + 0.03, 0.04), 'ita', ax=K.X, ay=dsl, az=nrm)
    m.box((-W2 - 0.55, RIDGE - 0.02, -0.08), (W2 + 0.55, RIDGE + 0.12, 0.08), WD, DARK)
    koya_counter(m, lod, 'nuno_hana_aka')
    regs = ['nuno_ai', 'nuno_hana_kinari', 'nuno_kasuri', 'nuno_hana_aka', 'nuno_shima']
    for i in range(5):
        x = -1.0 + i * 0.5
        cloth(m, (x - 0.2, 0.75, -D2 + 0.06), (x + 0.2, 0.75, -D2 + 0.06), (x + 0.2, EAVE_F - 0.2, -D2 + 0.06), (x - 0.2, EAVE_F - 0.2, -D2 + 0.06), regs[i], back=False)
    pole(m, (-W2, EAVE_F - 0.18, -D2 + 0.08), (W2, EAVE_F - 0.18, -D2 + 0.08), 0.018)
    for i in range(6 if not lod else 3):
        x = -1.0 + i * 0.4
        rcy(m, (x - 0.15, 0.95, D2 - 0.25), (x + 0.15, 0.95, D2 - 0.25), 0.08, 0.08, 8, regs[i % 5])
    for i in range(3):
        x = -0.8 + i * 0.8
        for j in range(4 if not lod else 2):
            rbx(m, (x, 0.88 + j * 0.05, D2 - 0.02), (0.2, 0.024, 0.14), regs[(i + j) % 5])
    noren(m, -W2, W2, EAVE_F - 0.14, 0.4, D2 + 0.22, 'noren_aka', 4, lod)
    cy(m, (W2 + 0.2, EAVE_F - 0.14, D2 + 0.45), (W2 + 0.2, EAVE_F - 0.4, D2 + 0.45), 0.005, 0.005, 3, 'nawa', caps=(False, False))
    lantern(m, (W2 + 0.2, EAVE_F - 0.66, D2 + 0.45), 0.15, 0.48, lod)
    top = crate(m, W2 + 0.55, 0.0, D2 + 0.25, 0.55, 0.4, 0.45, OLD, lid=True)
    for j in range(3):
        rbx(m, (W2 + 0.55, top + 0.025 + j * 0.05, D2 + 0.25), (0.22, 0.024, 0.18), regs[j + 1])
    _ = rng
    return m


# ─────────────────────────── 旗・吊るし物 ───────────────────────────

def hata(key, lod):
    m = new('ic_hata_' + key, lod, '花紋の長旗（旗桿.png）：竿 4.4（埋 0.3・石の根止め）、横竿 0.75、布 0.60 × 2.40（%s、上に小紋・中に大紋・裾に波）、竿側を 3 か所で結ぶ' %
            {'ai': '藍・輪の花紋', 'aka': '弁柄・花紋と枝'}[key])
    H = 4.4
    pole(m, (0.0, -0.3, 0.0), (0.0, H, 0.0), 0.03, 'kuri', 8)
    m.cyl((0.0, 0.0, 0.0), (0.0, 0.14, 0.0), 0.13, 0.1, 6, WD, OLD)
    pole(m, (0.0, H - 0.12, 0.0), (0.72, H - 0.12, 0.0), 0.018, 'kuri')
    u0, v0, u1, v1 = REG['hata_' + key]
    top, bot = H - 0.18, H - 2.58
    n = 1 if lod else 3
    for i in range(n):
        ta, tb = i / n, (i + 1) / n
        ya = top - (top - bot) * ta
        yb = top - (top - bot) * tb
        za = 0.05 * math.sin(math.pi * ta * 1.5) if not lod else 0.0
        zb = 0.05 * math.sin(math.pi * tb * 1.5) if not lod else 0.0
        a, b, c, d = (0.05, yb, zb), (0.65, yb, zb + 0.04), (0.65, ya, za + 0.04), (0.05, ya, za)
        va = v0 + (v1 - v0) * ta
        vb = v0 + (v1 - v0) * tb
        m.quad(a, b, c, d, IC, 1.0, uvs=[(u0, vb), (u1, vb), (u1, va), (u0, va)])
        m.quad(b, a, d, c, IC, 1.0, uvs=[(u1, vb), (u0, vb), (u0, va), (u1, va)])
    if not lod:
        for y in (top - 0.3, top - 1.2, top - 2.1):
            cy(m, (0.0, y, 0.0), (0.0, y + 0.04, 0.0), 0.045, 0.045, 6, 'nawa', caps=(False, False))
    return m


def kakezao(lod):
    m = new('ic_kakezao', lod, '吊るし物の竿（04 の商品掛け）：柱 2.45（石の台）＋横木 1.7、絵看板（花紋）・唐辛子の連・大蒜の連・薬草の束・瓢箪 2')
    m.box((-0.05, 0.0, -0.05), (0.05, 2.45, 0.05), WD, AGED)
    m.box((-0.22, 0.0, -0.22), (0.22, 0.1, 0.22), WD, OLD)
    m.beam((0.0, 1.5, 0.0), (0.35, 2.1, 0.0), 0.04, 0.04, WD, OLD)
    m.beam((0.0, 1.5, 0.0), (-0.35, 2.1, 0.0), 0.04, 0.04, WD, OLD)
    m.box((-0.85, 2.15, -0.04), (0.85, 2.23, 0.04), WD, AGED)
    cloth(m, (-0.78, 1.45, 0.0), (-0.48, 1.45, 0.0), (-0.48, 2.05, 0.0), (-0.78, 2.05, 0.0), 'kanban_hana')
    for x in (-0.7, -0.56):
        cy(m, (x, 2.15, 0.0), (x, 2.05, 0.0), 0.005, 0.005, 3, 'nawa', caps=(False, False))
    hang_bundle(m, -0.3, 2.15, 0.0, 0.6, 'togarashi', lod)
    hang_bundle(m, 0.15, 2.15, 0.0, 0.55, 'ninniku', lod)
    hang_bundle(m, 0.42, 2.15, 0.0, 0.5, 'yakuso', lod)
    for x, r, y in ((0.7, 0.07, 1.72), (0.7, 0.05, 1.56)):
        ball(m, (x, y, 0.0), r, 'hyoutan', 6 if lod else 8, 1.1)
    cy(m, (0.7, 2.15, 0.0), (0.7, 1.8, 0.0), 0.005, 0.005, 3, 'nawa', caps=(False, False))
    return m


# ─────────────────────────── 陳列台・卓・箱 ───────────────────────────

def hinadan_yasai(lod):
    m = new('ic_hinadan_yasai', lod, '段々の野菜棚（04 の二段の傾斜棚）：1.80 × 0.95、下段（0.45、傾き）に箱 2・上段（0.85）に箱 3——キャベツ・白菜・南瓜・人参・蕪')
    rng = random.Random(30201)
    for x in (-0.88, 0.84):
        m.box((x, 0.0, -0.45), (x + 0.05, 1.0, -0.4), WD, OLD)
        m.box((x, 0.0, 0.4), (x + 0.05, 0.5, 0.45), WD, OLD)
        m.beam((x + 0.025, 0.5, 0.42), (x + 0.025, 1.0, -0.42), 0.05, 0.05, WD, AGED)
    m.box((-0.9, 0.42, -0.05), (0.9, 0.46, 0.45), WD, WOODC)
    m.box((-0.9, 0.82, -0.45), (0.9, 0.86, -0.05), WD, WOODC)
    for i, (x, kind) in enumerate(((-0.45, 'hakusai'), (0.45, 'kabocha'))):
        crate_of(m, kind, x, 0.2, 0.8, 0.12, 0.42, rng, lod, y=0.46)
    for i, (x, kind) in enumerate(((-0.6, 'kyabetsu'), (0.0, 'ninjin'), (0.6, 'kabu'))):
        crate_of(m, kind, x, -0.25, 0.56, 0.12, 0.36, rng, lod, y=0.86)
    return m


def dai(key, lod):
    if key == 'shima':
        m = new('ic_dai_shima', lod, '縞の卓布の台（05 の覆い卓）：1.40 × 0.70 × 0.70、藍と生成りの縞の布（裾の房）、染付の碗の重ね・急須・湯呑・箸立て')
    else:
        m = new('ic_dai_hana', lod, '花柄の卓布の台（05）：1.40 × 0.70 × 0.70、弁柄の花柄の布、畳んだ反物の山 2・巾着 2・風呂敷包み・毛糸の籠')
    rng = random.Random(30202 if key == 'shima' else 30203)
    reg = 'nuno_shima' if key == 'shima' else 'nuno_hana_aka'
    H = 0.7
    m.box((-0.7, H - 0.04, -0.35), (0.7, H, 0.35), WD, WOODC)
    for x in (-0.66, 0.62):
        for z in (-0.31, 0.27):
            m.box((x, 0.0, z), (x + 0.04, H - 0.04, z + 0.04), WD, OLD)
    u0, v0, u1, v1 = REG[reg]
    m.quad((-0.72, H + 0.005, 0.37), (0.72, H + 0.005, 0.37), (0.72, H + 0.005, -0.37), (-0.72, H + 0.005, -0.37), IC, 1.0, uvs=[(u0, v1), (u1, v1), (u1, v0), (u0, v0)])
    for a, b in (((-0.72, 0.37), (0.72, 0.37)), ((0.72, -0.37), (-0.72, -0.37)), ((0.72, 0.37), (0.72, -0.37)), ((-0.72, -0.37), (-0.72, 0.37))):
        m.quad((a[0], H - 0.32, a[1]), (b[0], H - 0.32, b[1]), (b[0], H + 0.005, b[1]), (a[0], H + 0.005, a[1]), IC, 0.9, uvs=[(u0, v1), (u1, v1), (u1, v0), (u0, v0)])
    if key == 'shima':
        for i, x in enumerate((-0.5, -0.2, 0.15)):
            bowls(m, x, H, 0.1, 0.12, 3, lod, 'sometsuke' if i != 1 else 'haiyu')
        ball(m, (0.45, H + 0.1, 0.1), 0.09, 'hakuji', 8, 0.85)
        if not lod:
            cy(m, (0.53, H + 0.11, 0.1), (0.6, H + 0.14, 0.1), 0.012, 0.008, 4, 'hakuji')
        for x in (-0.45, -0.25, -0.05):
            rcy(m, (x, H, -0.18), (x, H + 0.1, -0.18), 0.04, 0.045, 8, 'sometsuke')
        m.cyl((0.45, H, -0.18), (0.45, H + 0.18, -0.18), 0.06, 0.06, 8, WD, AGED)
        for i in range(6 if not lod else 2):
            a = i * 1.05
            cy(m, (0.45 + math.cos(a) * 0.03, H + 0.1, -0.18 + math.sin(a) * 0.03), (0.45 + math.cos(a) * 0.04, H + 0.36, -0.18 + math.sin(a) * 0.04), 0.004, 0.004, 3, 'kuri', caps=(False, False))
    else:
        regs = ['nuno_ai', 'nuno_hana_kinari', 'nuno_kasuri', 'nuno_koshi', 'nuno_nami']
        for i, x in enumerate((-0.45, 0.0)):
            for j in range(4 if not lod else 2):
                rbx(m, (x, H + 0.03 + j * 0.055, 0.08), (0.2, 0.027, 0.15), regs[(i * 2 + j) % 5])
        for x, reg2 in ((0.42, 'nuno_hana_ai'), (0.58, 'nuno_hana_kinari')):
            rcy(m, (x, H, -0.12), (x, H + 0.2, -0.12), 0.09, 0.07, 8, reg2, caps=(True, False))
            cy(m, (x, H + 0.2, -0.12), (x, H + 0.26, -0.12), 0.04, 0.06, 6, reg2 == 'nuno_hana_ai' and 'ai' or 'kinari')
        rbx(m, (-0.3, H + 0.08, -0.2), (0.15, 0.08, 0.1), 'nuno_hana_kinari')
        top = kago(m, 0.4, H, 0.18, 0.12, 0.1, lod)
        for i, k2 in enumerate(('kinari', 'beni', 'ai')):
            ball(m, (0.35 + i * 0.05, top + 0.03, 0.18), 0.045, k2, 6, 1.0)
    _ = rng
    return m


def hako(key, lod):
    kinds = {'a': ['daikon', 'kyabetsu', 'kabu'], 'b': ['tomato', 'kabocha', 'tamanegi', 'kaki'], 'c': ['negi', 'hakusai', 'jagaimo', 'ringo']}[key]
    m = new('ic_hako_' + key, lod, '野菜・果物の箱と籠の組（06）：%s——木箱（0.48 × 0.36 × 0.22）と浅い籠を 2 段にずらして並べる' % '・'.join(kinds))
    rng = random.Random(30300 + ord(key))
    n = len(kinds)
    for i, kind in enumerate(kinds):
        x = -0.55 * (n - 1) / 2 + i * 0.55
        if kind in ('kabocha', 'kaki', 'kabu', 'hakusai'):
            basket_of(m, kind, x, 0.05 if i % 2 else -0.05, 0.22, 0.14, rng, lod)
        else:
            crate_of(m, kind, x, 0.05 if i % 2 else -0.05, 0.48, 0.22, 0.36, rng, lod, yaw=rng.uniform(-0.08, 0.08))
    crate(m, -0.55 * (n - 1) / 2 + 0.25, 0.0, -0.42, 0.5, 0.32, 0.34, OLD, lid=True)
    return m


def tsubo(lod):
    m = new('ic_tsubo', lod, '甕と瓶の置き場（03）：藁巻きの大甕・板蓋を縄で留めた壺・流し釉の両耳壺・染付の蓋物・縄掛けの緑の瓶 2・小樽')
    seg = 8 if lod else 12
    jar(m, -0.55, 0.0, 0.0, 0.3, 0.8, 'kokuyu', lod)
    rcy(m, (-0.55, 0.15, 0.0), (-0.55, 0.62, 0.0), 0.31, 0.3, seg, 'komo', caps=(False, False))
    if not lod:
        for a in range(6):
            t = a * math.pi / 3
            cy(m, (-0.55 + math.cos(t) * 0.31, 0.1, math.sin(t) * 0.31), (-0.55 + math.cos(t) * 0.2, 0.82, math.sin(t) * 0.2), 0.01, 0.01, 4, 'nawa', caps=(False, False))
    jar(m, 0.1, 0.0, 0.15, 0.24, 0.55, 'tsuchi', lod)
    m.cyl((0.1, 0.55, 0.15), (0.1, 0.59, 0.15), 0.2, 0.2, seg, WD, AGED)
    cy(m, (-0.12, 0.6, 0.15), (0.32, 0.6, 0.15), 0.008, 0.008, 4, 'nawa', caps=(False, False))
    jar(m, 0.55, 0.0, -0.2, 0.18, 0.42, 'ameyu', lod, region='ameyu_drip')
    jar(m, 0.2, 0.0, -0.32, 0.12, 0.3, 'hakuji', lod, region='sometsuke')
    for x, z in ((0.62, 0.25), (0.82, 0.05)):
        cy(m, (x, 0.0, z), (x, 0.32, z), 0.1, 0.11, seg, 'midori_bin', caps=(True, False))
        cy(m, (x, 0.32, z), (x, 0.48, z), 0.11, 0.035, seg, 'midori_bin', caps=(False, False))
        cy(m, (x, 0.48, z), (x, 0.56, z), 0.03, 0.03, 6, 'kuri')
        if not lod:
            for y in (0.12, 0.24):
                cy(m, (x, y, z), (x, y + 0.02, z), 0.115, 0.115, seg, 'nawa', caps=(False, False))
    m.cyl((-0.15, 0.0, -0.4), (-0.15, 0.36, -0.4), 0.17, 0.18, seg, WD, WOODC)
    if not lod:
        for y in (0.08, 0.28):
            cy(m, (-0.15, y, -0.4), (-0.15, y + 0.03, -0.4), 0.185, 0.185, seg, 'nawa', caps=(False, False))
    return m


def zakka(lod):
    m = new('ic_zakka', lod, '雑貨の置き場（05）：生成りの巾着（花紋）・藍の巾着・縄の束 3・菅笠（立て掛け）・棒を挿した桶・風呂敷包み 2')
    seg = 8 if lod else 12
    for x, reg, h in ((-0.55, 'nuno_hana_kinari', 0.5), (-0.15, 'nuno_hana_ai', 0.44)):
        rcy(m, (x, 0.0, 0.0), (x, h * 0.8, 0.0), 0.2, 0.18, seg, reg, caps=(True, False))
        rcy(m, (x, h * 0.8, 0.0), (x, h, 0.0), 0.18, 0.06, seg, reg, caps=(False, False))
        cy(m, (x, h, 0.0), (x, h + 0.08, 0.0), 0.07, 0.09, 6, reg == 'nuno_hana_ai' and 'ai' or 'kinari')
    for i, (x, z) in enumerate(((0.3, 0.15), (0.55, 0.0), (0.4, -0.2))):
        cy(m, (x, 0.0, z), (x, 0.1, z), 0.16, 0.16, seg, 'nawa')
        if not lod:
            cy(m, (x, 0.1, z), (x, 0.1, z), 0.06, 0.06, 6, 'kuri')
    # 菅笠（立て掛け）
    c = (0.85, 0.32, -0.25)
    rcy(m, K.add(c, (0.0, 0.0, -0.02)), K.add(c, (0.0, 0.0, 0.14)), 0.32, 0.02, seg, 'straw', caps=(True, False))
    m.cyl((-0.6, 0.0, -0.4), (-0.6, 0.32, -0.4), 0.12, 0.13, seg, WD, AGED)
    for i in range(6 if not lod else 2):
        a = i * 1.05
        cy(m, (-0.6 + math.cos(a) * 0.05, 0.2, -0.4 + math.sin(a) * 0.05), (-0.6 + math.cos(a) * 0.09, 0.85, -0.4 + math.sin(a) * 0.09), 0.01, 0.01, 4, 'kuri', caps=(False, False))
    rbx(m, (0.05, 0.12, -0.35), (0.18, 0.12, 0.14), 'nuno_hana_aka')
    rbx(m, (0.05, 0.3, -0.35), (0.13, 0.06, 0.1), 'nuno_kasuri')
    return m


def tana(lod):
    m = new('ic_tana', lod, '器の棚（04 の開き棚）：1.10 × 0.40 × 1.40、三段（背板あり）に染付・灰釉・飴釉の碗・皿・壺')
    m.box((-0.55, 0.0, -0.2), (-0.5, 1.4, 0.2), WD, AGED)
    m.box((0.5, 0.0, -0.2), (0.55, 1.4, 0.2), WD, AGED)
    m.box((-0.5, 0.0, -0.2), (0.5, 1.4, -0.16), WD, OLD)
    for y in (0.08, 0.52, 0.96, 1.36):
        m.box((-0.5, y, -0.16), (0.5, y + 0.04, 0.2), WD, WOODC)
    for j, y in enumerate((0.12, 0.56, 1.0)):
        for i, x in enumerate((-0.32, 0.0, 0.32)):
            if (i + j) % 3 == 0:
                jar(m, x, y, 0.02, 0.09, 0.28, 'ameyu', lod, region='ameyu_drip')
            elif (i + j) % 3 == 1:
                bowls(m, x, y, 0.02, 0.11, 3, lod, 'sometsuke')
            else:
                bowls(m, x, y, 0.02, 0.1, 2, lod, 'haiyu')
    return m


def taru(lod):
    m = new('ic_taru', lod, '樽と藁束の置き場（木箱木桶稻草.png）：樽 3（2＋1 横積み）・藁束 4（縄 2 本）・蓋付きの木箱')
    seg = 8 if lod else 12
    for x in (-0.5, 0.0):
        m.cyl((x, 0.0, 0.0), (x, 0.62, 0.0), 0.22, 0.24, seg, WD, AGED if x < 0 else WOODC)
        if not lod:
            for y in (0.12, 0.5):
                cy(m, (x, y, 0.0), (x, y + 0.03, 0.0), 0.245, 0.245, seg, 'take', caps=(False, False))
    m.cyl((-0.25, 0.85, -0.28), (-0.25, 0.85, 0.28), 0.2, 0.2, seg, WD, OLD)
    for i, (x, z) in enumerate(((0.55, 0.15), (0.85, 0.15), (0.55, -0.2), (0.7, 0.0))):
        y = 0.0 if i < 3 else 0.32
        rcy(m, (x - 0.14, y + 0.16, z), (x + 0.14, y + 0.16, z), 0.16, 0.16, 8, 'straw')
        if not lod:
            for t in (-0.06, 0.06):
                cy(m, (x + t, y + 0.16, z), (x + t + 0.015, y + 0.16, z), 0.165, 0.165, 8, 'nawa', caps=(False, False))
    crate(m, -0.3, 0.0, -0.45, 0.6, 0.36, 0.38, OLD, lid=True)
    return m


def hiyoke(lod):
    m = new('ic_hiyoke', lod, '縞の日除けと縁台（01 の縞の日除け）：竹竿 4（2.25／1.95）に藍と生成りの縞の布 2.4 × 1.7（前垂れ 0.25）、下に縁台 1.8 × 0.5')
    for x in (-1.15, 1.15):
        pole(m, (x, 0.0, 0.8), (x, 2.0, 0.8), 0.025, 'take')
        pole(m, (x, 0.0, -0.8), (x, 2.3, -0.8), 0.025, 'take')
    u0, v0, u1, v1 = REG['nuno_shima']
    nseg = 1 if lod else 3
    for i in range(nseg):
        ta, tb = i / nseg, (i + 1) / nseg
        za, zb = -0.85 + 1.75 * ta, -0.85 + 1.75 * tb
        ya = 2.3 - 0.33 * ta - (0.0 if lod else 0.05 * math.sin(math.pi * ta))
        yb = 2.3 - 0.33 * tb - (0.0 if lod else 0.05 * math.sin(math.pi * tb))
        for k in range(3):                      # 縞が伸びないよう 3 幅に分けて同じ柄を繰り返す
            xa, xb = -1.2 + 0.8 * k, -1.2 + 0.8 * (k + 1)
            m.quad((xa, yb, zb), (xb, yb, zb), (xb, ya, za), (xa, ya, za), IC, 1.0, uvs=[(u0, v1), (u1, v1), (u1, v0), (u0, v0)])
            m.quad((xb, yb, zb), (xa, yb, zb), (xa, ya, za), (xb, ya, za), IC, 0.8, uvs=[(u1, v1), (u0, v1), (u0, v0), (u1, v0)])
    for k in range(3):
        xa, xb = -1.2 + 0.8 * k, -1.2 + 0.8 * (k + 1)
        cloth(m, (xa, 1.72, 0.9), (xb, 1.72, 0.9), (xb, 1.97, 0.9), (xa, 1.97, 0.9), 'nuno_shima')
    m.box((-0.9, 0.42, -0.25), (0.9, 0.46, 0.25), WD, WOODC)
    for x in (-0.85, 0.81):
        for z in (-0.22, 0.18):
            m.box((x, 0.0, z), (x + 0.04, 0.42, z + 0.04), WD, OLD)
    return m


def build_all():
    for lod in (0, 1):
        koya_yasai(lod)
        koya_seto(lod)
        koya_nuno(lod)
        hata('ai', lod)
        hata('aka', lod)
        kakezao(lod)
        hinadan_yasai(lod)
        dai('shima', lod)
        dai('hana', lod)
        for k in ('a', 'b', 'c'):
            hako(k, lod)
        tsubo(lod)
        zakka(lod)
        tana(lod)
        taru(lod)
        hiyoke(lod)


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
    K.export_glb(bpy, OUT + '/src/ichi_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_ichi_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=ichi_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[ICKIT] %d 構件、合計 %d 三角面' % (len(manifest), total))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[ICKIT]   %-18s %5d 面  LOD1 %4d  dims %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims']))


main()
