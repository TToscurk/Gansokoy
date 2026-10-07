"""人間之里 V2 P10 R1：市集廣場 Kit（market_kit）— 新資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_market_kit.py

讀感（TPS 5–20 m）：「人が商い・食べ・運び・干している」——輪郭を変える中大型（屋台 2.4 m、布棚 2.5 m、幟 3.7 m、
番傘 2.3 m、荷車・天秤・干し竿）＋その上の商品（野菜・器・反物・団子）。同じ屋台を並べない：屋台／布棚／筵の 3 形式×商品 で変える。
材質：V2_Wood（_matlib、柱・板・梁）＋MK_Market（market_kit atlas：幟・暖簾・置き看板の文字、日除け布、反物の柄、
稲藁・和紙・竹笊・木地、色票＝農産物・器・漆・毛氈・番傘）。既存 Hero／P9 kit は只讀。
座標：Godot（x 右、y 上、+z 前＝客側）；原點＝接地點（y 0）；單位 m。
  屋台（板屋根 2.4 × 1.3）：mk_yatai_yasai 八百屋／mk_yatai_dango 団子屋（炭火・団子・急須）／mk_yatai_meshi 一膳飯（鍋・お櫃・椀）
  布棚（竹 4 本＋日除け布 3.0 × 2.2）：mk_tana_nuno 反物・古着（縁台に反物の山＋掛け竿）／mk_tana_seto 瀬戸物（雛壇 3 段＋甕）
  筵（地べた売り）：mk_mushiro_yasai 農家の野菜（大根束・南瓜・茄子の笊・葱・背負い籠）／mk_mushiro_kago 笊・籠・草鞋
  mk_bangasa 野点傘（朱、Ø2.4）／mk_nobori_{yasai,cha,seto,tanmono,ichi} 幟（竿 4.0、布 0.45 × 1.8）／
  mk_kanban_{yasai,dango,seto,furugi} 置き看板（A 字、0.42 × 0.90）
  運搬・作業：mk_kuruma_ni 荷を積んだ大八車／mk_tenbin 天秤棒と籠 2／mk_tsumini 木箱・俵・菰包みの荷積み／mk_kame 甕 3
  曬物：mk_hoshimono 干し竿（布 3・吊るし柿・干し大根）
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
OUT = G + '/assets/village_v2/market_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(OUT + '/atlas.json')
REG = AT['regions']
SWC = AT['swatches']
WD = 'V2_Wood'
MK = 'MK_Market'
MATS = [WD, MK]
TILE = {WD: ML['V2_Wood']['tile_m'], MK: 1.0}

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


# ─────────────────────────── 基本 ───────────────────────────

def swr(key):
    u, v = SWC[key]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


def pc(m, ps, key):
    u, v = SWC[key]
    m.poly(ps, MK, 1.0, uvs=[(u, v)] * len(ps))


def bx(m, lo, hi, key):
    c = K.mul(K.add(lo, hi), 0.5)
    h = K.mul(K.sub(hi, lo), 0.5)
    m.abox(c, h, MK, {'*': swr(key)})


def obx(m, c, h, key, ax=K.X, ay=K.Y, az=K.Z, skip=()):
    m.abox(c, h, MK, {'*': swr(key)}, 1.0, ax=ax, ay=ay, az=az, skip=skip)


def rbx(m, c, h, region, ax=K.X, ay=K.Y, az=K.Z, side=None):
    """atlas 區域の方塊（全面同じ區域、side＝側面の色票）。"""
    r = {'*': REG[region]}
    if side:
        for k in ('+x', '-x', '+y', '-y'):
            r[k] = swr(side)
    m.abox(c, h, MK, r, 1.0, ax=ax, ay=ay, az=az)


def cy(m, p0, p1, r0, r1, seg, key, caps=(True, True)):
    m.cyl(p0, p1, r0, r1, seg, MK, 1.0, caps=caps, uv_atlas=swr(key))


def ball(m, c, r, key, seg, squash=1.0):
    x, y, z = c
    ry = r * squash
    cy(m, (x, y - ry, z), (x, y - ry * 0.55, z), r * 0.25, r * 0.85, seg, key, caps=(True, False))
    cy(m, (x, y - ry * 0.55, z), (x, y + ry * 0.55, z), r * 0.85, r * 0.85, seg, key, caps=(False, False))
    cy(m, (x, y + ry * 0.55, z), (x, y + ry, z), r * 0.85, r * 0.25, seg, key, caps=(False, True))


def post(m, x, z, y0, y1, r=0.05, col=AGED):
    m.box((x - r, y0, z - r), (x + r, y1, z + r), WD, col)


def pole(m, p0, p1, r, key='take', seg=6):
    cy(m, p0, p1, r, r * 0.9, seg, key, caps=(False, True))


def cloth(m, a, b, c, d, region, back=True):
    """両面の布（表裏とも文字は正しく読める）。a 左下・b 右下・c 右上・d 左上（表から見て）。"""
    m.rect_uv(a, b, c, d, MK, REG[region])
    if back:
        m.rect_uv(b, a, d, c, MK, REG[region])


def cloth_sw(m, a, b, c, d, key):
    pc(m, [a, b, c, d], key)
    pc(m, [b, a, d, c], key)


def sag_cloth(m, x0, x1, zf, zb, yf, yb, region, n, sag, ext_f=0.0):
    """斜めの日除け布：x0..x1 × 前 zf（高 yf）〜後 zb（高 yb）を n 帯に分け、帯の中ほどを sag だけ垂らす。"""
    u0, v0, u1, v1 = REG[region]
    for i in range(n):
        xa = x0 + (x1 - x0) * i / n
        xb = x0 + (x1 - x0) * (i + 1) / n
        for j in range(2):
            ta, tb = j / 2.0, (j + 1) / 2.0

            def P(x, t):
                z = zb + (zf + ext_f - zb) * t
                y = yb + (yf - yb) * t - sag * math.sin(math.pi * t) * (0.6 + 0.4 * math.sin(math.pi * (x - x0) / (x1 - x0)))
                return (x, y, z)
            a, b, c, d = P(xa, tb), P(xb, tb), P(xb, ta), P(xa, ta)
            ua = u0 + (u1 - u0) * i / n
            ub = u0 + (u1 - u0) * (i + 1) / n
            va = v0 + (v1 - v0) * ta
            vb = v0 + (v1 - v0) * tb
            m.quad(a, b, c, d, MK, 1.0, uvs=[(ua, vb), (ub, vb), (ub, va), (ua, va)])
            m.quad(b, a, d, c, MK, 0.82, uvs=[(ub, vb), (ua, vb), (ua, va), (ub, va)])


# ─────────────────────────── 商品 ───────────────────────────

def zaru(m, x, y, z, r, lod, h=0.05):
    """竹笊（浅い）：底＋立ち上がり。"""
    seg = 8 if lod else 12
    u0, v0, u1, v1 = REG['zaru']
    m.cyl((x, y, z), (x, y + h, z), r * 0.8, r, seg, MK, 1.0, caps=(True, False), uv_atlas=[u0, v0, u1, v0 + (v1 - v0) * 0.3])
    return y + h * 0.4


def kago(m, x, y, z, r, h, lod):
    """深い籠（竹）：胴＋口の縁。"""
    seg = 8 if lod else 12
    u0, v0, u1, v1 = REG['zaru']
    m.cyl((x, y, z), (x, y + h, z), r * 0.82, r, seg, MK, 1.0, caps=(True, False), uv_atlas=[u0, v0, u1, v1])
    cy(m, (x, y + h - 0.012, z), (x, y + h + 0.012, z), r + 0.012, r + 0.012, seg, 'take', caps=(False, False))
    return y + h


def daikon(m, x, y, z, ang, L, lod, lean=0.0):
    d = (math.cos(ang), lean, math.sin(ang))
    tip = (x + d[0] * L, y + d[1] * L, z + d[2] * L)
    cy(m, (x, y, z), tip, 0.035, 0.008, 5 if lod else 7, 'daikon', caps=(True, False))
    if not lod:
        lf = (x - d[0] * 0.22, y + 0.06, z - d[2] * 0.22)
        cy(m, (x, y, z), lf, 0.03, 0.05, 5, 'daikon_leaf', caps=(False, True))


def heap(m, cx, cy0, cz, rx, rz, n, r, key, rng, lod, squash=1.0, layer=2):
    """丸い作物の山（茄子・南瓜・蕪・柿・林檎）：下段に n、上段に n/3。"""
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


def nasu_zaru(m, x, y, z, lod, rng, key='nasu', r=0.042):
    yy = zaru(m, x, y, z, 0.25, lod)
    heap(m, x, yy, z, 0.17, 0.17, 9, r, key, rng, lod, squash=1.3)


def bolt(m, x, y, z, w, h, d, region, yaw=0.0):
    """反物（巻いた布の束を平たく）：上と前に柄、側面は色票。"""
    ax = (math.cos(yaw), 0.0, -math.sin(yaw))
    az = (math.sin(yaw), 0.0, math.cos(yaw))
    rbx(m, (x, y + h / 2, z), (w / 2, h / 2, d / 2), region, ax=ax, az=az)


def bowl(m, x, y, z, r, h, key, lod, inner='hakuji'):
    seg = 8 if lod else 12
    cy(m, (x, y, z), (x, y + h, z), r * 0.45, r, seg, key, caps=(True, False))
    if not lod:
        cy(m, (x, y + h, z), (x, y + h * 0.35, z), r * 0.96, r * 0.4, seg, inner, caps=(False, True))


def plates(m, x, y, z, r, n, key, lod):
    seg = 8 if lod else 12
    for i in range(n):
        cy(m, (x, y + i * 0.018, z), (x, y + i * 0.018 + 0.016, z), r * 0.7, r, seg, key, caps=(True, True))
    return y + n * 0.018


def jar(m, x, y, z, r, h, key, lod, lid=None):
    seg = 8 if lod else 12
    cy(m, (x, y, z), (x, y + h * 0.5, z), r * 0.7, r, seg, key, caps=(True, False))
    cy(m, (x, y + h * 0.5, z), (x, y + h * 0.88, z), r, r * 0.6, seg, key, caps=(False, False))
    cy(m, (x, y + h * 0.88, z), (x, y + h, z), r * 0.62, r * 0.62, seg, key, caps=(False, True))
    if lid:
        m.cyl((x, y + h, z), (x, y + h + 0.025, z), r * 0.7, r * 0.7, seg, WD, lid, caps=(False, True))


def teapot(m, x, y, z, r, key, lod):
    ball(m, (x, y + r * 0.8, z), r, key, 7 if lod else 10, 0.8)
    if not lod:
        cy(m, (x + r * 0.8, y + r * 0.7, z), (x + r * 1.5, y + r * 1.1, z), 0.012, 0.008, 5, key)
        cy(m, (x, y + r * 1.45, z), (x, y + r * 1.6, z), 0.02, 0.012, 6, key)


def tawara(m, x, y, z, yaw, lod, L=0.72, r=0.22):
    d = (math.cos(yaw), 0.0, -math.sin(yaw))
    a = (x - d[0] * L / 2, y + r, z - d[2] * L / 2)
    b = (x + d[0] * L / 2, y + r, z + d[2] * L / 2)
    seg = 8 if lod else 10
    u0, v0, u1, v1 = REG['straw']
    m.cyl(a, K.lerp(a, b, 0.12), r * 0.8, r, seg, MK, 1.0, caps=(True, False), uv_atlas=[u0, v0, u1, v1])
    m.cyl(K.lerp(a, b, 0.12), K.lerp(a, b, 0.88), r, r, seg, MK, 1.0, caps=(False, False), uv_atlas=[u0, v0, u1, v1])
    m.cyl(K.lerp(a, b, 0.88), b, r, r * 0.8, seg, MK, 1.0, caps=(False, True), uv_atlas=[u0, v0, u1, v1])
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


def dango(m, x, y, z, ang, lod):
    d = (math.cos(ang), 0.0, math.sin(ang))
    s0 = (x - d[0] * 0.07, y, z - d[2] * 0.07)
    s1 = (x + d[0] * 0.09, y, z + d[2] * 0.09)
    cy(m, s0, s1, 0.004, 0.004, 4, 'take', caps=(False, False))
    for i, k in enumerate(['dango_p', 'dango_w', 'dango_g']):
        c = K.lerp(s0, s1, 0.3 + 0.22 * i)
        ball(m, c, 0.016, k, 5 if lod else 6)


# ─────────────────────────── 屋台（板屋根） ───────────────────────────

W_Y, D_Y = 2.4, 1.3


def yatai_frame(m, noren, lod, hf=2.15, hb=2.45, cloth_roof=None):
    W, D = W_Y, D_Y
    for sx in (-1, 1):
        post(m, sx * (W / 2 - 0.05), D / 2 - 0.05, 0.0, hf, 0.045, AGED)
        post(m, sx * (W / 2 - 0.05), -D / 2 + 0.05, 0.0, hb, 0.045, AGED)
        # 側の貫と梁
        m.beam((sx * (W / 2 - 0.05), hf - 0.04, D / 2 - 0.05), (sx * (W / 2 - 0.05), hb - 0.04, -D / 2 + 0.05), 0.07, 0.08, WD, OLD)
        m.beam((sx * (W / 2 - 0.05), 0.35, D / 2 - 0.05), (sx * (W / 2 - 0.05), 0.35, -D / 2 + 0.05), 0.05, 0.05, WD, OLD)
    m.beam((-W / 2, hf - 0.04, D / 2 - 0.05), (W / 2, hf - 0.04, D / 2 - 0.05), 0.07, 0.08, WD, OLD)
    m.beam((-W / 2, hb - 0.04, -D / 2 + 0.05), (W / 2, hb - 0.04, -D / 2 + 0.05), 0.07, 0.08, WD, OLD)
    # 板屋根：後ろ 0.15、前 0.45 張り出し、板の段差（LOD0）
    zb, zf = -D / 2 - 0.15, D / 2 + 0.45
    yb, yf = hb + 0.05, hf - 0.1
    sl = K.norm((0.0, yf - yb, zf - zb))
    nrm = K.norm(K.cross((1.0, 0.0, 0.0), sl))
    L = math.sqrt((yf - yb) ** 2 + (zf - zb) ** 2)
    nb = 0 if cloth_roof else (1 if lod else 7)
    if cloth_roof:
        sag_cloth(m, -W / 2 - 0.12, W / 2 + 0.12, zf, zb, yf, yb, cloth_roof, 3 if not lod else 1, 0.05)
    for i in range(nb):
        t0 = i / nb
        c = (0.0, yb + (yf - yb) * (t0 + 0.5 / nb), zb + (zf - zb) * (t0 + 0.5 / nb))
        c = K.add(c, K.mul(nrm, 0.014 * (i % 2)))
        m.obox(c, (W / 2 + 0.18, 0.022, L / nb / 2 + 0.07), WD, [(0.62, 0.58, 0.52), (0.72, 0.68, 0.61)][i % 2], az=sl, ay=nrm, ax=K.X)
    if not lod and not cloth_roof:
        for sx in (-0.7, 0.0, 0.7):
            m.beam((sx, yb + 0.03, zb + 0.05), (sx, yf + 0.02, zf - 0.05), 0.04, 0.03, WD, DARK, up=nrm)
    # 暖簾：前の軒下 0.45 垂れる
    yn = hf - 0.1
    cloth(m, (-W / 2 + 0.08, yn - 0.45, D / 2 + 0.06), (W / 2 - 0.08, yn - 0.45, D / 2 + 0.06),
          (W / 2 - 0.08, yn, D / 2 + 0.06), (-W / 2 + 0.08, yn, D / 2 + 0.06), noren)
    # 台：天板 0.82、前板、下の棚
    m.box((-W / 2 + 0.02, 0.8, -0.05), (W / 2 - 0.02, 0.84, D / 2 + 0.05), WD, WOODC)
    m.box((-W / 2 + 0.06, 0.12, D / 2 - 0.02), (W / 2 - 0.06, 0.8, D / 2 + 0.02), WD, (0.8, 0.74, 0.64))
    m.box((-W / 2 + 0.06, 0.16, -0.4), (W / 2 - 0.06, 0.19, D / 2 - 0.05), WD, OLD)
    # 後ろの棚（高 1.35）
    m.box((-W / 2 + 0.05, 1.35, -D / 2 + 0.05), (W / 2 - 0.05, 1.38, -D / 2 + 0.38), WD, WOODC)
    return 0.84


def eave_hang(m, lod, kind, hf=2.15, n=5):
    """前の軒下（暖簾の内側）に吊るし物：kaki＝吊るし柿の連、daikon＝干し大根、waraji＝草鞋、himono＝干物。"""
    W, D = W_Y, D_Y
    z = D / 2 - 0.12
    y0 = hf - 0.14
    pole(m, (-W / 2 + 0.08, y0, z), (W / 2 - 0.08, y0, z), 0.014)
    for i in range(n if not lod else max(2, n // 2)):
        x = -W / 2 + 0.3 + (W - 0.6) * i / max(1, n - 1)
        if kind == 'kaki':
            cy(m, (x, y0, z), (x, y0 - 0.55, z), 0.004, 0.004, 3, 'nawa', caps=(False, False))
            for j in range(6 if not lod else 3):
                ball(m, (x, y0 - 0.06 - j * 0.085, z), 0.034, 'kaki', 5 if lod else 6, 0.9)
        elif kind == 'daikon':
            for j in range(3 if not lod else 1):
                cy(m, (x + (j - 1) * 0.04, y0, z), (x + (j - 1) * 0.05, y0 - 0.48, z + 0.02), 0.024, 0.01, 5, 'daikon', caps=(False, True))
        elif kind == 'waraji':
            cy(m, (x, y0, z), (x, y0 - 0.5, z), 0.004, 0.004, 3, 'nawa', caps=(False, False))
            u0, v0, u1, v1 = REG['straw']
            for j in range(3 if not lod else 1):
                m.abox((x, y0 - 0.12 - j * 0.15, z), (0.05, 0.11, 0.012), MK, {'*': [u0, v0, u1, v1]})
        elif kind == 'himono':
            for j in range(3 if not lod else 1):
                obx(m, (x + (j - 1) * 0.07, y0 - 0.16, z), (0.03, 0.14, 0.008), 'himono')
    return m


def yatai_yasai(lod):
    m = new('mk_yatai_yasai', lod, '八百屋の屋台：板屋根 2.4 × 1.3（前 2.15・後 2.45）、藍の丸紋暖簾、天板に笊 4（茄子・人参・蕪・柿）＋大根の束、後棚に南瓜・籠、台下に木箱')
    rng = random.Random(10101)
    y = yatai_frame(m, 'noren_mon', lod)
    eave_hang(m, lod, 'kaki', n=5)
    # 天板の後ろ半分に段（+0.22）：奥の商品が前から見える
    m.box((-1.15, y, -0.6), (1.15, y + 0.22, -0.12), WD, WOODC)
    for x, key in ((-0.8, 'kyabetsu'), (-0.2, 'kabocha_in'), (0.45, 'negi'), (0.95, 'satoimo')):
        yy = zaru(m, x, y + 0.22, -0.36, 0.25, lod)
        if key == 'negi':
            for i in range(9 if not lod else 3):
                xx = x - 0.16 + i * 0.04
                cy(m, (xx, yy + 0.03, -0.52), (xx, yy + 0.05, -0.12), 0.016, 0.014, 5, 'negi', caps=(True, False))
                if not lod:
                    cy(m, (xx, yy + 0.05, -0.12), (xx + 0.02, yy + 0.12, 0.05), 0.014, 0.022, 4, 'daikon_leaf', caps=(False, True))
        else:
            heap(m, x, yy, -0.36, 0.17, 0.15, 7, 0.06 if key == 'kyabetsu' else 0.05, key, rng, lod, 0.85)
    nasu_zaru(m, -0.8, y, 0.35, lod, rng)
    yy = zaru(m, -0.25, y, 0.4, 0.2, lod)
    for i in range(6 if not lod else 3):
        daikon(m, -0.38 + i * 0.05, yy + 0.02, 0.32, 0.4 + rng.uniform(-0.15, 0.15), 0.26, lod, 0.08)
    yy = zaru(m, 0.32, y, 0.38, 0.2, lod)
    heap(m, 0.32, yy, 0.38, 0.13, 0.13, 7, 0.04, 'kaki', rng, lod, 0.85)
    yy = zaru(m, 0.85, y, 0.35, 0.2, lod)
    heap(m, 0.85, yy, 0.35, 0.13, 0.13, 6, 0.045, 'daikon', rng, lod, 0.9)
    # 大根の束を台の端に寝かせる
    for i in range(5 if not lod else 2):
        daikon(m, -1.05, y + 0.04 + i * 0.03, -0.0 + i * 0.07, 0.15, 0.42, lod)
    # 後棚：南瓜 3＋籠
    for i, x in enumerate((-0.8, -0.45, -0.1)):
        ball(m, (x, 1.38 + 0.09, -0.4), 0.11, 'kabocha', 6 if lod else 9, 0.75)
    kago(m, 0.5, 1.38, -0.42, 0.14, 0.18, lod)
    heap(m, 0.5, 1.5, -0.42, 0.08, 0.08, 5, 0.035, 'ringo', rng, lod, 0.9, layer=1)
    # 台下：木箱 2
    crate(m, -0.6, 0.19, 0.05, 0.6, 0.32, 0.42, 0.0, OLD)
    crate(m, 0.5, 0.19, 0.0, 0.6, 0.3, 0.42, 0.1, AGED)
    return m


def yatai_dango(lod):
    m = new('mk_yatai_dango', lod, '団子屋の屋台：生成りに藍「だんご」の暖簾、炭火の焼き台（黒・赤い炭）、串団子の盆 3、急須・湯呑、後棚に重箱・茶壺')
    rng = random.Random(10102)
    y = yatai_frame(m, 'noren_dango', lod)
    eave_hang(m, lod, 'waraji', n=4)
    # 焼き台（黒い箱＋網＋炭）
    bx(m, (-1.0, y, 0.0), (-0.3, y + 0.16, 0.42), 'kokuyu')
    bx(m, (-0.96, y + 0.16, 0.04), (-0.34, y + 0.17, 0.38), 'togarashi')
    for i in range(6 if not lod else 3):
        dango(m, -0.88 + i * 0.1, y + 0.19, 0.22, math.pi / 2 + rng.uniform(-0.1, 0.1), lod)
    # 盆に団子
    for k, x in enumerate((0.0, 0.42, 0.84)):
        bx(m, (x - 0.16, y, 0.18), (x + 0.16, y + 0.025, 0.42), 'shuurushi')
        for i in range(4 if not lod else 2):
            dango(m, x - 0.08 + i * 0.055, y + 0.045, 0.3, math.pi / 2, lod)
    teapot(m, 0.5, y, -0.05, 0.07, 'tetsu', lod)
    for i in range(3):
        bowl(m, 0.75 + i * 0.09, y, -0.02, 0.035, 0.055, 'hakuji', lod)
    # 後棚：重箱・茶壺
    bx(m, (-0.9, 1.38, -0.55), (-0.6, 1.62, -0.3), 'urushi')
    bx(m, (-0.88, 1.62, -0.53), (-0.62, 1.64, -0.32), 'shuurushi')
    jar(m, -0.2, 1.38, -0.42, 0.1, 0.24, 'ameyu', lod)
    jar(m, 0.25, 1.38, -0.42, 0.09, 0.2, 'sometsuke', lod)
    # 台下：水桶・炭俵
    m.cyl((0.6, 0.19, 0.05), (0.6, 0.52, 0.05), 0.17, 0.19, 10 if not lod else 8, WD, AGED)
    tawara(m, -0.5, 0.19, 0.0, 0.0, lod, 0.6, 0.15)
    return m


def yatai_meshi(lod):
    m = new('mk_yatai_meshi', lod, '一膳飯の屋台：柿渋に白「めし」の暖簾、大鍋 2（鉄）・お櫃・椀の重ね・醤油樽、前に縁台用の空き樽')
    rng = random.Random(10103)
    y = yatai_frame(m, 'noren_meshi', lod)
    eave_hang(m, lod, 'daikon', n=5)
    for x in (-0.75, -0.2):
        cy(m, (x, y, 0.15), (x, y + 0.2, 0.15), 0.18, 0.21, 8 if lod else 12, 'tetsu', caps=(True, False))
        cy(m, (x, y + 0.2, 0.15), (x, y + 0.13, 0.15), 0.2, 0.16, 8 if lod else 12, 'shoyu', caps=(False, True))
        if not lod:
            m.cyl((x, y + 0.22, 0.15), (x, y + 0.24, 0.15), 0.19, 0.19, 12, WD, OLD)
    m.cyl((0.35, y, 0.2), (0.35, y + 0.22, 0.2), 0.17, 0.17, 12 if not lod else 8, WD, WOODC)
    cy(m, (0.35, y + 0.22, 0.2), (0.35, y + 0.25, 0.2), 0.175, 0.175, 12 if not lod else 8, 'kakishibu')
    for i in range(4):
        for j in range(3 if not lod else 1):
            bowl(m, 0.75 + (i % 2) * 0.11, y + j * 0.045, 0.1 + (i // 2) * 0.12, 0.05, 0.05, ['shuurushi', 'urushi'][i % 2], lod)
    # 後棚：徳利・小鉢・醤油樽
    for i in range(4):
        jar(m, -0.9 + i * 0.22, 1.38, -0.45, 0.05, 0.17, ['hakuji', 'ameyu', 'hakuji', 'sometsuke'][i], lod)
    m.cyl((0.6, 1.38, -0.45), (0.6, 1.62, -0.45), 0.13, 0.13, 10, WD, AGED)
    # 台下：薪束
    for i in range(5 if not lod else 2):
        m.cyl((-0.9, 0.24 + (i % 2) * 0.06, -0.2 + i * 0.07), (0.0, 0.24 + (i % 2) * 0.06, -0.2 + i * 0.07), 0.035, 0.035, 5, WD, OLD)
    return m


def yatai_sakana(lod):
    m = new('mk_yatai_sakana', lod, '魚屋の屋台：柿渋の布屋根（板でない輪郭）、藍の丸紋暖簾は無し、軒下に干物の連、天板に盤台 3（鮮魚・貝・干物）＋まな板・包丁、足元に水桶')
    rng = random.Random(10104)
    y = yatai_frame(m, 'noren_mon', lod, cloth_roof='awn_kaki')
    eave_hang(m, lod, 'himono', n=6)
    for k, (x, key) in enumerate(((-0.75, 'sakana'), (0.0, 'sakana'), (0.75, 'himono'))):
        m.cyl((x, y, 0.2), (x, y + 0.1, 0.2), 0.3, 0.32, 12 if not lod else 8, WD, WOODC, caps=(True, False))
        m.cyl((x, y + 0.095, 0.2), (x, y + 0.1, 0.2), 0.3, 0.3, 12 if not lod else 8, WD, (0.5, 0.46, 0.4), caps=(False, True))
        for i in range(7 if not lod else 3):
            a = i * 0.9 + k
            c = (x + math.cos(a) * 0.15, y + 0.12 + 0.012 * (i % 2), 0.2 + math.sin(a) * 0.13)
            ax = (math.cos(a + 1.3), 0.0, math.sin(a + 1.3))
            obx(m, c, (0.13 if key == 'sakana' else 0.1, 0.022, 0.035), key, ax=ax, az=(-ax[2], 0.0, ax[0]))
    m.box((0.5, y, -0.45), (1.05, y + 0.04, -0.15), WD, WOODC)
    obx(m, (0.75, y + 0.05, -0.3), (0.14, 0.004, 0.02), 'tetsu')
    m.cyl((-0.7, 0.0, 0.9), (-0.7, 0.36, 0.9), 0.2, 0.22, 12 if not lod else 8, WD, AGED)
    cy(m, (-0.7, 0.33, 0.9), (-0.7, 0.34, 0.9), 0.2, 0.2, 10, 'sometsuke')
    return m


def yatai_cha(lod):
    m = new('mk_yatai_cha', lod, '茶店の屋台：藍白縞の布屋根、生成り「だんご」でなく丸紋暖簾、天板に茶箱 3・茶壺・急須 2・湯呑の盆、鉄瓶の炉、軒下に赤提灯 2')
    rng = random.Random(10105)
    y = yatai_frame(m, 'noren_mon', lod, cloth_roof='awn_shima')
    for x in (-0.9, 0.9):
        lantern(m, x, 1.98, 0.5, 0.13, 0.32, lod)
    for i, x in enumerate((-0.95, -0.55, -0.15)):
        rbx(m, (x, y + 0.14, -0.35), (0.17, 0.14, 0.17), 'paper', side='urushi')
        rbx(m, (x, y + 0.29, -0.35), (0.12, 0.012, 0.12), 'wood_dark')
    jar(m, 0.35, y, -0.35, 0.13, 0.3, 'sometsuke', lod, lid=OLD)
    teapot(m, 0.75, y, -0.3, 0.075, 'kokuyu', lod)
    teapot(m, 0.1, y, 0.25, 0.07, 'ameyu', lod)
    bx(m, (0.45, y, 0.1), (0.95, y + 0.02, 0.45), 'urushi')
    for i in range(6 if not lod else 3):
        bowl(m, 0.52 + (i % 3) * 0.15, y + 0.02, 0.18 + (i // 3) * 0.14, 0.035, 0.06, 'hakuji', lod)
    bx(m, (-1.0, 0.19, 0.05), (-0.45, 0.62, 0.5), 'tsuchi')
    cy(m, (-0.72, 0.62, 0.28), (-0.72, 0.8, 0.28), 0.12, 0.1, 10, 'tetsu')
    return m


def yatai_ame(lod):
    m = new('mk_yatai_ame', lod, '飴屋の屋台：紅白の布屋根、暖簾なし、天板に飴の壺 6（色とりどり）・飴細工を挿した藁束 2・鈴の吊り、前に風車の藁束')
    rng = random.Random(10106)
    y = yatai_frame(m, 'noren_dango', lod, cloth_roof='awn_beni')
    for i in range(6):
        x = -1.0 + i * 0.36
        jar(m, x, y, -0.3 + 0.18 * (i % 2), 0.09, 0.24, 'hakuji', lod)
        heap(m, x, y + 0.24, -0.3 + 0.18 * (i % 2), 0.05, 0.05, 5, 0.02, ['dango_p', 'yamabuki', 'dango_g', 'bangasa', 'dango_w', 'ai'][i], rng, lod, 1.0, layer=1)
    u0, v0, u1, v1 = REG['straw']
    for x in (-0.6, 0.6):
        m.cyl((x, y, 0.35), (x, y + 0.42, 0.35), 0.07, 0.06, 8, MK, 1.0, caps=(True, True), uv_atlas=[u0, v0, u1, v1])
        for i in range(7 if not lod else 3):
            a = i * 0.9
            tip = (x + math.cos(a) * 0.12, y + 0.62 + 0.08 * (i % 2), 0.35 + math.sin(a) * 0.12)
            cy(m, (x, y + 0.3, 0.35), tip, 0.004, 0.004, 3, 'take', caps=(False, False))
            ball(m, tip, 0.03, ['bangasa', 'yamabuki', 'wakakusa', 'ai', 'dango_p', 'bangasa', 'yamabuki'][i], 5 if lod else 6)
    return m


def lantern(m, x, y, z, r, h, lod):
    """提灯（赤い紙＋黒い枠）：上端 y から下へ h。"""
    seg = 8 if lod else 12
    u0, v0, u1, v1 = REG['chochin']
    cy(m, (x, y, z), (x, y - 0.03, z), r * 0.55, r * 0.6, seg, 'urushi', caps=(True, False))
    # 紙の胴は下→上へ作る（cyl は p0 に v1・p1 に v0；上→下だと半分ずつ上下逆＋左右逆になり字が割れていた、2026-10-07 修正）
    m.cyl((x, y - 0.03 - h, z), (x, y - 0.03 - h * 0.5, z), r * 0.6, r, seg, MK, 1.0, caps=(False, False), uv_atlas=[u0, (v0 + v1) / 2, u1, v1])
    m.cyl((x, y - 0.03 - h * 0.5, z), (x, y - 0.03, z), r, r * 0.6, seg, MK, 1.0, caps=(False, False), uv_atlas=[u0, v0, u1, (v0 + v1) / 2])
    cy(m, (x, y - 0.03 - h, z), (x, y - 0.06 - h, z), r * 0.6, r * 0.55, seg, 'urushi', caps=(False, True))


def chochin_line(lod):
    m = new('mk_chochin_line', lod, '提灯の吊り綱：竹竿 2（高 3.3、間 5.0、石の根止め）＋綱（中ほど 0.25 垂れる）に赤提灯 5（Ø0.26 × 0.38、「市」）')
    span = 5.0
    for x in (-span / 2, span / 2):
        pole(m, (x, -0.3, 0.0), (x, 3.3, 0.0), 0.028, 'take')
        m.cyl((x, 0.0, 0.0), (x, 0.1, 0.0), 0.1, 0.08, 6, WD, OLD)
    n = 10 if not lod else 4
    pts = []
    for i in range(n + 1):
        t = i / n
        x = -span / 2 + span * t
        y = 3.2 - 0.25 * math.sin(math.pi * t)
        pts.append((x, y, 0.0))
    for i in range(n):
        cy(m, pts[i], pts[i + 1], 0.006, 0.006, 4, 'nawa', caps=(False, False))
    for k in range(5):
        t = (k + 1) / 6
        x = -span / 2 + span * t
        y = 3.2 - 0.25 * math.sin(math.pi * t)
        cy(m, (x, y, 0.0), (x, y - 0.12, 0.0), 0.004, 0.004, 3, 'nawa', caps=(False, False))
        lantern(m, x, y - 0.12, 0.0, 0.13, 0.38, lod)
    return m


def tana_kasa(lod):
    m = new('mk_tana_kasa', lod, '笠・傘屋の布棚：藍の日除け、横竿に菅笠 6 を吊る、台に畳んだ番傘の束 2（朱・藍）・開いた番傘 1（台の脇）、蓑 1')
    rng = random.Random(10204)
    tana_frame(m, 'awn_ai', lod)
    pole(m, (-1.5, 1.8, 0.9), (1.5, 1.8, 0.9), 0.02)
    u0, v0, u1, v1 = REG['straw']
    for i in range(6 if not lod else 3):
        x = -1.25 + i * 0.5
        cy(m, (x, 1.8, 0.9), (x, 1.55, 0.9), 0.004, 0.004, 3, 'nawa', caps=(False, False))
        m.cyl((x, 1.55, 0.9), (x, 1.4, 0.96), 0.02, 0.24, 10 if not lod else 6, MK, 1.0, caps=(False, False), uv_atlas=[u0, v0, u1, v1])
        m.cyl((x, 1.4, 0.96), (x, 1.55, 0.9), 0.24, 0.02, 10 if not lod else 6, MK, 0.8, caps=(False, False), uv_atlas=[u0, v0, u1, v1])
    endai(m, -1.2, 1.2, -0.6, 0.5, 0.45, lod, 'straw')
    for k, (x, key) in enumerate(((-0.7, 'bangasa'), (0.1, 'ai'))):
        for i in range(5 if not lod else 2):
            a = i * 0.25 - 0.5
            p0 = (x + i * 0.08, 0.47, -0.2)
            cy(m, p0, (p0[0] + 0.05, 0.47 + 0.05, 0.4), 0.05, 0.03, 6, key)
            cy(m, (p0[0] + 0.05, 0.52, 0.4), (p0[0] + 0.05, 0.53, 0.52), 0.012, 0.012, 4, 'take')
    # 開いた番傘（台の脇、少し傾ける）
    cy(m, (1.35, 0.0, 0.2), (1.25, 1.55, 0.25), 0.012, 0.012, 4, 'take')
    cy(m, (1.25, 1.45, 0.25), (1.24, 1.72, 0.25), 0.62, 0.05, 16 if not lod else 8, 'ai', caps=(False, False))
    cy(m, (1.24, 1.7, 0.25), (1.25, 1.44, 0.25), 0.05, 0.6, 16 if not lod else 8, 'bangasa_in', caps=(False, False))
    # 蓑（台の後ろに掛ける）
    m.cyl((-1.2, 1.65, -0.85), (-1.2, 0.85, -0.85), 0.12, 0.32, 10 if not lod else 6, MK, 1.0, caps=(False, False), uv_atlas=[u0, v0, u1, v1])
    return m


def tana_omocha(lod):
    m = new('mk_tana_omocha', lod, '玩具屋の布棚：紅白の日除け、横竿に風車・でんでん太鼓・お面を吊る、台に手毬・独楽・犬張子、前に風車の藁束 2')
    rng = random.Random(10205)
    tana_frame(m, 'awn_beni', lod)
    pole(m, (-1.5, 1.75, 0.95), (1.5, 1.75, 0.95), 0.02)
    cols = ['bangasa', 'yamabuki', 'ai', 'wakakusa', 'dango_p', 'kon']
    for i in range(8 if not lod else 4):
        x = -1.3 + i * 0.37
        cy(m, (x, 1.75, 0.95), (x, 1.5, 0.95), 0.004, 0.004, 3, 'nawa', caps=(False, False))
        if i % 2 == 0:
            ball(m, (x, 1.42, 0.95), 0.08, 'hakuji', 6 if lod else 8, 1.1)
            bx(m, (x - 0.04, 1.43, 1.02), (x + 0.04, 1.46, 1.03), cols[i % 6])
        else:
            cy(m, (x, 1.5, 0.95), (x, 1.15, 0.95), 0.006, 0.006, 3, 'take')
            cy(m, (x, 1.4, 0.92), (x, 1.4, 0.98), 0.07, 0.07, 10 if not lod else 6, cols[i % 6])
    endai(m, -1.2, 1.2, -0.6, 0.5, 0.45, lod, 'wood_light')
    for i in range(10 if not lod else 4):
        x = -1.0 + (i % 5) * 0.45
        z = -0.35 + (i // 5) * 0.45
        if i % 3 == 0:
            ball(m, (x, 0.53, z), 0.075, cols[i % 6], 6 if lod else 8)
        elif i % 3 == 1:
            cy(m, (x, 0.45, z), (x, 0.55, z), 0.02, 0.07, 8, cols[(i + 2) % 6])
            cy(m, (x, 0.55, z), (x, 0.58, z), 0.07, 0.01, 8, cols[(i + 3) % 6])
        else:
            ball(m, (x, 0.55, z), 0.07, 'hakuji', 6, 0.9)
            ball(m, (x + 0.06, 0.62, z), 0.05, 'hakuji', 6)
    u0, v0, u1, v1 = REG['straw']
    for x in (-0.9, 0.9):
        m.cyl((x, 0.0, 1.25), (x, 0.9, 1.25), 0.08, 0.06, 8, MK, 1.0, caps=(True, True), uv_atlas=[u0, v0, u1, v1])
        for i in range(8 if not lod else 3):
            a = i * 0.8
            tip = (x + math.cos(a) * 0.12, 1.05 + 0.1 * (i % 3), 1.25 + math.sin(a) * 0.12)
            cy(m, (x, 0.7, 1.25), tip, 0.004, 0.004, 3, 'take', caps=(False, False))
            for k in range(4):
                b = k * math.pi / 2 + a
                d1 = (math.cos(b) * 0.07, math.sin(b) * 0.07, 0.0)
                d2 = (math.cos(b + 0.9) * 0.05, math.sin(b + 0.9) * 0.05, 0.0)
                pc(m, [tip, K.add(tip, d1), K.add(tip, d2)], cols[(i + k) % 6])
                pc(m, [tip, K.add(tip, d2), K.add(tip, d1)], cols[(i + k) % 6])
    return m


# ─────────────────────────── 布棚（竹＋日除け布） ───────────────────────────

def tana_frame(m, awn, lod, W=3.0, D=2.2, hf=2.0, hb=2.45):
    for sx in (-1, 1):
        pole(m, (sx * W / 2, 0.0, D / 2), (sx * W / 2, hf + 0.08, D / 2), 0.035)
        pole(m, (sx * W / 2, 0.0, -D / 2), (sx * W / 2, hb + 0.08, -D / 2), 0.035)
    pole(m, (-W / 2 - 0.1, hf, D / 2), (W / 2 + 0.1, hf, D / 2), 0.028)
    pole(m, (-W / 2 - 0.1, hb, -D / 2), (W / 2 + 0.1, hb, -D / 2), 0.028)
    sag_cloth(m, -W / 2 - 0.08, W / 2 + 0.08, D / 2 + 0.25, -D / 2, hf - 0.05, hb + 0.03, awn, 3 if not lod else 1, 0.06, 0.0)
    if not lod:
        # 前の張り綱 2
        for sx in (-1, 1):
            cy(m, (sx * W / 2, hf, D / 2), (sx * (W / 2 + 0.25), 0.02, D / 2 + 0.9), 0.006, 0.006, 4, 'nawa', caps=(False, False))
            m.box((sx * (W / 2 + 0.25) - 0.02, 0.0, D / 2 + 0.88), (sx * (W / 2 + 0.25) + 0.02, 0.12, D / 2 + 0.92), WD, OLD)


def endai(m, x0, x1, z0, z1, h, lod, top='straw'):
    m.box((x0, h - 0.04, z0), (x1, h, z1), WD, WOODC)
    for x in (x0 + 0.06, x1 - 0.1):
        for z in (z0 + 0.05, z1 - 0.09):
            m.box((x, 0.0, z), (x + 0.04, h - 0.04, z + 0.04), WD, OLD)
    u0, v0, u1, v1 = REG[top]
    m.quad((x0 + 0.03, h + 0.004, z1 - 0.03), (x1 - 0.03, h + 0.004, z1 - 0.03), (x1 - 0.03, h + 0.004, z0 + 0.03), (x0 + 0.03, h + 0.004, z0 + 0.03),
           MK, 1.0, uvs=[(u0, v1), (u1, v1), (u1, v0), (u0, v0)])


def tana_nuno(lod):
    m = new('mk_tana_nuno', lod, '反物・古着の布棚：竹 4 本＋藍白縞の日除け 3.0 × 2.2（前 2.0・後 2.45）、縁台 2.4 × 0.9 に反物の山 3、後ろの掛け竿に古着・布 4 枚、足元に行李')
    rng = random.Random(10201)
    tana_frame(m, 'awn_shima', lod)
    regs0 = ['nuno_akane', 'nuno_ai', 'nuno_yamabuki', 'nuno_koshi', 'nuno_wakakusa', 'nuno_kasuri']
    for i, r in enumerate(regs0):
        x = -1.25 + i * 0.5
        cloth(m, (x - 0.22, 1.35, 1.12), (x + 0.22, 1.35, 1.12), (x + 0.22, 1.96, 1.12), (x - 0.22, 1.96, 1.12), r)
    endai(m, -1.2, 1.2, -0.05, 0.85, 0.45, lod, 'straw')
    regs = ['nuno_ai', 'nuno_koshi', 'nuno_akane', 'nuno_wakakusa', 'nuno_nezumi', 'nuno_yamabuki', 'nuno_kasuri', 'nuno_shima']
    k = 0
    for gx in (-0.75, 0.0, 0.75):
        y = 0.455
        for j in range(6 if not lod else 3):
            bolt(m, gx + rng.uniform(-0.03, 0.03), y, 0.42 + rng.uniform(-0.04, 0.04), 0.56, 0.08, 0.38, regs[k % len(regs)], rng.uniform(-0.08, 0.08))
            y += 0.08
            k += 3
    # 掛け竿（後ろ、高 1.75）＋垂れた布 4
    pole(m, (-1.4, 1.75, -0.8), (1.4, 1.75, -0.8), 0.022)
    for i, x in enumerate((-1.05, -0.35, 0.35, 1.05)):
        r = regs[(i * 3 + 1) % len(regs)]
        cloth(m, (x - 0.28, 0.75 + 0.08 * (i % 2), -0.79), (x + 0.28, 0.75 + 0.08 * (i % 2), -0.79), (x + 0.28, 1.74, -0.79), (x - 0.28, 1.74, -0.79), r)
    # 行李（柳行李）
    rbx(m, (1.45, 0.16, 0.6), (0.3, 0.16, 0.2), 'zaru', side='take')
    return m


def tana_seto(lod):
    m = new('mk_tana_seto', lod, '瀬戸物の布棚：生成りの日除け、雛壇 3 段（2.2 m）に皿の重ね・丼・急須・徳利（白磁・染付・飴釉・黒釉）、前に大甕 2・すり鉢')
    rng = random.Random(10202)
    tana_frame(m, 'awn_kinari', lod)
    for k, (y, z0, z1) in enumerate(((0.35, 0.25, 0.75), (0.65, -0.15, 0.25), (0.95, -0.55, -0.15))):
        m.box((-1.15, y - 0.04, z0), (1.15, y, z1), WD, WOODC)
        for x in (-1.12, 1.08):
            m.box((x, 0.0, z0 + 0.05), (x + 0.04, y - 0.04, z0 + 0.09), WD, OLD)
            m.box((x, 0.0, z1 - 0.09), (x + 0.04, y - 0.04, z1 - 0.05), WD, OLD)
        zc = (z0 + z1) / 2
        n = 7 if not lod else 4
        for i in range(n):
            x = -0.95 + 1.9 * i / (n - 1)
            kind = (i + k) % 4
            key = ['hakuji', 'sometsuke', 'ameyu', 'kokuyu', 'haiyu'][(i * 2 + k) % 5]
            if kind == 0:
                plates(m, x, y, zc, 0.11, 5 if not lod else 2, key, lod)
            elif kind == 1:
                for j in range(3 if not lod else 1):
                    bowl(m, x, y + j * 0.04, zc, 0.075, 0.07, key, lod)
            elif kind == 2:
                teapot(m, x, y, zc, 0.07, key, lod)
            else:
                jar(m, x, y, zc, 0.06, 0.2, key, lod)
    for x, key in ((-0.8, 'ameyu'), (-0.25, 'kokuyu')):
        jar(m, x, 0.0, 0.95, 0.26, 0.62, key, lod)
    bowl(m, 0.45, 0.0, 0.95, 0.22, 0.14, 'tsuchi', lod, inner='ameyu')
    return m


def tana_zakka(lod):
    m = new('mk_tana_zakka', lod, '荒物屋の布棚：柿渋の日除け、横竿に箒・柄杓・笊・草鞋を吊る、台に桶の重ね・手桶・籠、足元に竹箒の束と樽')
    rng = random.Random(10203)
    tana_frame(m, 'awn_kaki', lod)
    pole(m, (-1.5, 1.75, 0.95), (1.5, 1.75, 0.95), 0.02)
    for i in range(7 if not lod else 3):
        x = -1.25 + i * 0.42
        kind = i % 4
        if kind == 0:
            cy(m, (x, 1.75, 0.95), (x, 0.95, 0.95), 0.012, 0.012, 4, 'take', caps=(False, False))
            u0, v0, u1, v1 = REG['straw']
            m.cyl((x, 0.95, 0.95), (x, 0.6, 0.95), 0.03, 0.12, 8, MK, 1.0, caps=(False, True), uv_atlas=[u0, v0, u1, v1])
        elif kind == 1:
            cy(m, (x, 1.75, 0.95), (x, 1.2, 0.95), 0.008, 0.008, 4, 'take', caps=(False, False))
            bowl(m, x, 1.08, 0.95, 0.07, 0.1, 'take', lod)
        elif kind == 2:
            cy(m, (x, 1.75, 0.95), (x, 1.45, 0.95), 0.004, 0.004, 3, 'nawa', caps=(False, False))
            u0, v0, u1, v1 = REG['zaru']
            m.cyl((x, 1.45, 0.95), (x, 1.15, 0.97), 0.18, 0.18, 10, MK, 1.0, caps=(True, False), uv_atlas=[u0, v0, u1, v1])
        else:
            cy(m, (x, 1.75, 0.95), (x, 1.3, 0.95), 0.004, 0.004, 3, 'nawa', caps=(False, False))
            u0, v0, u1, v1 = REG['straw']
            for j in range(3 if not lod else 1):
                m.abox((x, 1.62 - j * 0.15, 0.95), (0.05, 0.11, 0.012), MK, {'*': [u0, v0, u1, v1]})
    endai(m, -1.2, 1.2, -0.6, 0.5, 0.45, lod, 'wood_light')
    for i, x in enumerate((-0.85, -0.25, 0.35, 0.9)):
        yy = 0.45
        for j in range(3 if i % 2 == 0 else 2):
            m.cyl((x, yy, 0.0), (x, yy + 0.16, 0.0), 0.17 - j * 0.02, 0.19 - j * 0.02, 12 if not lod else 8, WD, [WOODC, AGED][j % 2], caps=(True, False))
            yy += 0.12
    for x in (-1.0, 1.0):
        for i in range(5 if not lod else 2):
            a = i * 0.5 - 1.0
            cy(m, (x + 0.03 * i, 0.0, 0.9), (x + 0.03 * i + 0.25 * math.sin(a), 1.1, 0.95), 0.012, 0.012, 4, 'take', caps=(False, False))
            u0, v0, u1, v1 = REG['straw']
            if not lod:
                m.cyl((x + 0.03 * i, 0.0, 0.9), (x + 0.03 * i + 0.06 * math.sin(a), 0.32, 0.91), 0.08, 0.03, 6, MK, 1.0, caps=(True, False), uv_atlas=[u0, v0, u1, v1])
    m.cyl((1.35, 0.0, -0.75), (1.35, 0.6, -0.75), 0.22, 0.24, 12 if not lod else 8, WD, AGED)
    return m


def mushiro_tsuke(lod):
    m = new('mk_mushiro_tsuke', lod, '漬物の地べた売り：筵 1.9 × 1.3 に漬物樽 3（沢庵・菜・梅）＋壺 2・木の杓子、背負い籠')
    rng = random.Random(10303)
    mushiro(m, 1.9, 1.3)
    for x, z, key in ((-0.55, 0.15, 'takuan'), (0.05, 0.25, 'daikon_leaf'), (0.6, 0.1, 'ume')):
        m.cyl((x, 0.012, z), (x, 0.42, z), 0.22, 0.24, 12 if not lod else 8, WD, AGED, caps=(True, False))
        for t in (0.12, 0.34):
            cy(m, (x, 0.012 + t, z), (x, 0.03 + t, z), 0.235, 0.24, 12 if not lod else 8, 'take', caps=(False, False))
        if key == 'takuan':
            for i in range(6 if not lod else 3):
                a = i * 1.05
                obx(m, (x + math.cos(a) * 0.1, 0.43, z + math.sin(a) * 0.1), (0.1, 0.025, 0.025), key, ax=(math.cos(a), 0.0, math.sin(a)), az=(-math.sin(a), 0.0, math.cos(a)))
        else:
            cy(m, (x, 0.38, z), (x, 0.43, z), 0.215, 0.18, 12 if not lod else 8, key)
            if key == 'ume':
                heap(m, x, 0.43, z, 0.12, 0.12, 8, 0.025, 'ume', rng, lod, 1.0, layer=1)
    jar(m, -0.5, 0.012, -0.4, 0.13, 0.3, 'ameyu', lod, lid=OLD)
    jar(m, -0.15, 0.012, -0.45, 0.1, 0.24, 'kokuyu', lod)
    cy(m, (0.35, 0.44, 0.0), (0.55, 0.7, -0.1), 0.01, 0.01, 4, 'take')
    kago(m, 0.75, 0.0, -0.95, 0.2, 0.5, lod)
    return m


def endai_uri(lod):
    m = new('mk_endai_uri', lod, '駄菓子と風車の縁台：縁台 1.8 × 0.6（緋毛氈）に飴の壺 3・盆 2、藁束に挿した風車 9（赤・黄・藍・緑）、日除けの番傘は無し')
    rng = random.Random(10304)
    m.box((-0.9, 0.42, -0.3), (0.9, 0.46, 0.3), WD, WOODC)
    for x in (-0.82, 0.78):
        for z in (-0.25, 0.21):
            m.box((x, 0.0, z), (x + 0.04, 0.42, z + 0.04), WD, OLD)
    pc(m, [(-0.86, 0.464, 0.28), (0.86, 0.464, 0.28), (0.86, 0.464, -0.28), (-0.86, 0.464, -0.28)], 'mousen')
    for i, (x, key) in enumerate(((-0.6, 'dango_p'), (-0.25, 'yamabuki'), (0.1, 'dango_g'))):
        jar(m, x, 0.464, -0.1, 0.09, 0.22, 'hakuji', lod)
        heap(m, x, 0.684, -0.1, 0.05, 0.05, 5, 0.018, key, rng, lod, 1.0, layer=1)
    for x in (-0.45, 0.1):
        bx(m, (x - 0.14, 0.464, 0.08), (x + 0.14, 0.48, 0.26), 'shuurushi')
        for i in range(4 if not lod else 2):
            ball(m, (x - 0.08 + i * 0.05, 0.5, 0.17), 0.02, ['dango_w', 'dango_p', 'yamabuki', 'dango_g'][i], 5 if lod else 6)
    # 藁束（風車を挿す）
    u0, v0, u1, v1 = REG['straw']
    m.cyl((0.6, 0.464, 0.0), (0.6, 0.85, 0.0), 0.09, 0.07, 8, MK, 1.0, caps=(True, True), uv_atlas=[u0, v0, u1, v1])
    cols = ['bangasa', 'yamabuki', 'ai', 'wakakusa', 'mousen', 'dango_p', 'kon', 'yamabuki', 'bangasa']
    for i in range(9 if not lod else 4):
        a = i * 0.7
        h = 0.95 + 0.12 * (i % 3)
        tip = (0.6 + math.cos(a) * 0.12, 0.464 + h, math.sin(a) * 0.12)
        cy(m, (0.6 + math.cos(a) * 0.04, 0.7, math.sin(a) * 0.04), tip, 0.005, 0.005, 3, 'take', caps=(False, False))
        for k in range(4):
            b = k * math.pi / 2 + a
            d1 = (math.cos(b) * 0.07, math.sin(b) * 0.07, 0.0)
            d2 = (math.cos(b + 0.9) * 0.05, math.sin(b + 0.9) * 0.05, 0.0)
            p0 = tip
            pc(m, [p0, K.add(p0, d1), K.add(p0, d2)], cols[(i + k) % len(cols)])
            pc(m, [p0, K.add(p0, d2), K.add(p0, d1)], cols[(i + k) % len(cols)])
    return m


# ─────────────────────────── 筵（地べた売り） ───────────────────────────

def mushiro(m, W, D):
    u0, v0, u1, v1 = REG['straw']
    m.quad((-W / 2, 0.012, D / 2), (W / 2, 0.012, D / 2), (W / 2, 0.012, -D / 2), (-W / 2, 0.012, -D / 2), MK, 0.92,
           uvs=[(u0, v1), (u1, v1), (u1, v0), (u0, v0)])
    m.quad((-W / 2, 0.0, -D / 2), (W / 2, 0.0, -D / 2), (W / 2, 0.012, -D / 2), (-W / 2, 0.012, -D / 2), MK, 0.8,
           uvs=[(u0, v1), (u1, v1), (u1, v0), (u0, v0)])
    m.quad((W / 2, 0.0, D / 2), (-W / 2, 0.0, D / 2), (-W / 2, 0.012, D / 2), (W / 2, 0.012, D / 2), MK, 0.8,
           uvs=[(u0, v1), (u1, v1), (u1, v0), (u0, v0)])


def mushiro_yasai(lod):
    m = new('mk_mushiro_yasai', lod, '農家の地べた売り：筵 2.0 × 1.4 に大根の束 2・南瓜 3・茄子の笊・葱の束・里芋の笊、後ろに背負い籠（野菜入り）・腰掛け')
    rng = random.Random(10301)
    mushiro(m, 2.0, 1.4)
    y = 0.012
    for bxk, bz in ((-0.6, 0.2), (-0.3, -0.25)):
        for i in range(6 if not lod else 3):
            daikon(m, bxk + rng.uniform(-0.05, 0.05), y + 0.035 + (i % 2) * 0.05, bz + i * 0.045, 0.2, 0.42, lod)
    for i, (x, z) in enumerate(((0.25, 0.35), (0.5, 0.15), (0.32, 0.0))):
        ball(m, (x, y + 0.11, z), 0.13, 'kabocha', 7 if lod else 10, 0.72)
    nasu_zaru(m, 0.72, y, -0.35, lod, rng)
    yy = zaru(m, 0.05, y, -0.4, 0.2, lod)
    heap(m, 0.05, yy, -0.4, 0.13, 0.13, 8, 0.04, 'satoimo', rng, lod, 0.9)
    for i in range(8 if not lod else 3):
        x = -0.85 + i * 0.03
        cy(m, (x, y + 0.03, 0.55), (x + 0.42, y + 0.03 + 0.02 * (i % 2), 0.55), 0.016, 0.014, 5, 'negi', caps=(True, False))
        if not lod:
            cy(m, (x + 0.42, y + 0.03, 0.55), (x + 0.62, y + 0.06, 0.58), 0.014, 0.02, 4, 'daikon_leaf', caps=(False, True))
    # 背負い籠＋腰掛け
    kago(m, 0.85, 0.0, -0.95, 0.2, 0.5, lod)
    heap(m, 0.85, 0.5, -0.95, 0.1, 0.1, 4, 0.06, 'kyabetsu', rng, lod, 0.8, layer=1)
    m.box((0.1, 0.0, -1.0), (0.45, 0.32, -0.8), WD, OLD)
    return m


def mushiro_kago(lod):
    m = new('mk_mushiro_kago', lod, '笊・籠・草鞋の地べた売り：筵 1.8 × 1.3 に笊の重ね 3 山・籠 3（大小）・草鞋の束 2・竹の柄杓立て')
    rng = random.Random(10302)
    mushiro(m, 1.8, 1.3)
    for x, z, n in ((-0.55, 0.25, 6), (-0.1, 0.35, 4), (0.35, 0.25, 5)):
        y = 0.012
        for i in range(n if not lod else 2):
            zaru(m, x, y, z, 0.24 - i * 0.008, lod, 0.06)
            y += 0.03
    for x, z, r, h in ((-0.6, -0.3, 0.2, 0.32), (-0.15, -0.35, 0.16, 0.26), (0.3, -0.3, 0.24, 0.4)):
        kago(m, x, 0.012, z, r, h, lod)
    for i, (x, z) in enumerate(((0.7, 0.3), (0.7, -0.05))):
        for j in range(4 if not lod else 1):
            u0, v0, u1, v1 = REG['straw']
            m.abox((x, 0.03 + j * 0.03, z), (0.12, 0.012, 0.05), MK, {'*': [u0, v0, u1, v1]})
    m.cyl((0.75, 0.0, -0.4), (0.75, 0.36, -0.4), 0.09, 0.1, 10, WD, AGED)
    for i in range(4 if not lod else 2):
        a = i * 1.57 + 0.4
        cy(m, (0.75 + math.cos(a) * 0.04, 0.3, -0.4 + math.sin(a) * 0.04), (0.75 + math.cos(a) * 0.1, 0.72, -0.4 + math.sin(a) * 0.1), 0.008, 0.008, 4, 'take')
    return m


# ─────────────────────────── 番傘・幟・置き看板 ───────────────────────────

def bangasa(lod):
    m = new('mk_bangasa', lod, '野点傘（朱）：Ø2.4、柄 2.3（地に挿す石の台）、骨は内側の生成りに放射の線（LOD0）')
    seg = 12 if lod else 20
    R = 1.2
    pole(m, (0.0, 0.0, 0.0), (0.0, 2.3, 0.0), 0.03, 'take')
    m.cyl((0.0, 0.0, 0.0), (0.0, 0.12, 0.0), 0.16, 0.13, 8, WD, OLD)
    # 傘：外（朱）と内（生成り）、中心が高い浅い円錐を 2 段
    cy(m, (0.0, 2.05, 0.0), (0.0, 2.32, 0.0), R, R * 0.45, seg, 'bangasa', caps=(False, False))
    cy(m, (0.0, 2.32, 0.0), (0.0, 2.4, 0.0), R * 0.45, 0.04, seg, 'bangasa', caps=(False, False))
    cy(m, (0.0, 2.3, 0.0), (0.0, 2.04, 0.0), R * 0.45, R * 0.99, seg, 'bangasa_in', caps=(False, False))
    cy(m, (0.0, 2.38, 0.0), (0.0, 2.3, 0.0), 0.04, R * 0.45, seg, 'bangasa_in', caps=(False, False))
    if not lod:
        for i in range(16):
            a = 2 * math.pi * i / 16
            cy(m, (0.0, 2.2, 0.0), (math.cos(a) * R * 0.95, 2.06, math.sin(a) * R * 0.95), 0.006, 0.006, 3, 'take', caps=(False, False))
    return m


def nobori(key, lod):
    m = new('mk_nobori_' + key, lod, '幟「%s」：竹竿 4.0（地に 0.3 埋め・石の根止め）、布 0.45 × 1.8（上の横竿＋竿側の乳）、風で 3 段に緩く折れる' %
            {'yasai': '野菜', 'cha': '御茶', 'seto': '瀬戸物', 'tanmono': '反物', 'ichi': '市'}[key])
    H = 3.7
    pole(m, (0.0, -0.3, 0.0), (0.0, H, 0.0), 0.022, 'take')
    m.cyl((0.0, 0.0, 0.0), (0.0, 0.1, 0.0), 0.09, 0.07, 6, WD, OLD)
    pole(m, (0.0, H - 0.08, 0.0), (0.5, H - 0.08, 0.0), 0.012, 'take')
    region = 'nobori_' + key
    u0, v0, u1, v1 = REG[region]
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
        m.quad(a, b, c, d, MK, 1.0, uvs=[(u0, vb), (u1, vb), (u1, va), (u0, va)])   # 表：a（竿側）＝u0（2026-10-07 修正：表が鏡像だった）
        m.quad(b, a, d, c, MK, 1.0, uvs=[(u0, vb), (u1, vb), (u1, va), (u0, va)])   # 裏：b＝u0（表と位置ごとに左右反転＝裏からも正しく読める、2026-10-07）
    return m


def kanban(key, lod):
    m = new('mk_kanban_' + key, lod, '置き看板「%s」：A 字の脚 2、板 0.42 × 0.90（両面）、笠木、全高 1.15' %
            {'yasai': 'やさい', 'dango': '団子', 'seto': '瀬戸物', 'furugi': '古着'}[key])
    region = 'kanban_' + key
    for sz_ in (-1, 1):
        a = (0.0, 0.0, sz_ * 0.3)
        b = (0.0, 1.1, sz_ * 0.04)
        for sx in (-0.23, 0.23):
            m.beam((sx, a[1], a[2]), (sx, b[1], b[2]), 0.04, 0.03, WD, OLD)
    tilt = math.atan2(0.26, 1.1)
    for sz_ in (-1, 1):
        n = (0.0, math.sin(tilt), sz_ * math.cos(tilt))
        up = K.norm((0.0, 1.1, -sz_ * 0.26))
        c = (0.0, 0.62, sz_ * 0.165)
        c = K.add(c, K.mul(n, 0.02))
        hw, hh = 0.21, 0.45
        p = [K.add(c, K.add(K.mul((1.0, 0.0, 0.0), -hw * sz_), K.mul(up, -hh))),
             K.add(c, K.add(K.mul((1.0, 0.0, 0.0), hw * sz_), K.mul(up, -hh))),
             K.add(c, K.add(K.mul((1.0, 0.0, 0.0), hw * sz_), K.mul(up, hh))),
             K.add(c, K.add(K.mul((1.0, 0.0, 0.0), -hw * sz_), K.mul(up, hh)))]
        m.rect_uv(p[0], p[1], p[2], p[3], MK, REG[region])
        m.rect_uv(p[1], p[0], p[3], p[2], MK, REG['wood_light'])
    m.box((-0.27, 1.08, -0.07), (0.27, 1.15, 0.07), WD, AGED)
    return m


# ─────────────────────────── 運搬・作業・曬物 ───────────────────────────

def kuruma_ni(lod):
    m = new('mk_kuruma_ni', lod, '荷を積んだ大八車：車輪 Ø0.92 × 2、荷台 0.84 × 1.75、梶棒を地に下ろす（前傾）；米俵 3・南瓜 2・籠 2・菰包み 1、縄掛け')
    rng = random.Random(10401)
    tilt = math.radians(10.0)
    R = 0.46
    seg = 10 if lod else 16
    for sx in (-1, 1):
        x = sx * 0.5
        m.cyl((x - 0.03 * sx, R, 0.0), (x + 0.03 * sx, R, 0.0), R, R, seg, WD, OLD, caps=(True, True))
        if not lod:
            m.cyl((x - 0.05 * sx, R, 0.0), (x + 0.05 * sx, R, 0.0), 0.08, 0.08, 8, WD, DARK)
    def T(p):
        x, y, z = p
        zz = z * math.cos(tilt) - (y - R) * math.sin(tilt)
        yy = R + z * math.sin(tilt) + (y - R) * math.cos(tilt)
        return (x, yy, zz)
    # 荷台（局部座標を傾ける：前＝+z が下がる）
    deck = [(-0.42, R + 0.06, -0.85), (0.42, R + 0.06, -0.85), (0.42, R + 0.06, 0.9), (-0.42, R + 0.06, 0.9)]
    up = T((0.0, R + 1.0, 0.0))
    upv = K.norm(K.sub(up, T((0.0, R, 0.0))))
    fwd = K.norm(K.sub(T((0.0, R, 1.0)), T((0.0, R, 0.0))))
    c = T((0.0, R + 0.04, 0.02))
    m.obox(c, (0.42, 0.025, 0.88), WD, AGED, ax=K.X, ay=upv, az=fwd)
    for sx in (-1, 1):
        a = T((sx * 0.36, R + 0.02, -0.9))
        b = T((sx * 0.36, R + 0.02, 2.05))
        m.beam(a, b, 0.06, 0.06, WD, OLD, up=upv)
    m.beam(T((-0.36, R + 0.02, 1.95)), T((0.36, R + 0.02, 1.95)), 0.05, 0.05, WD, OLD, up=upv)
    # 荷：米俵 3（2＋1）・南瓜・籠・菰包み
    def on(x, y, z):
        return T((x, R + 0.065 + y, z))
    for i, (x, z) in enumerate(((-0.2, -0.45), (0.2, -0.45))):
        p = on(x, 0.0, z)
        tawara(m, p[0], p[1], p[2], math.pi / 2, lod, 0.7, 0.2)
    p = on(0.0, 0.36, -0.45)
    tawara(m, p[0], p[1], p[2], math.pi / 2, lod, 0.7, 0.2)
    for x, z in ((-0.2, 0.25), (0.15, 0.15)):
        p = on(x, 0.0, z)
        ball(m, (p[0], p[1] + 0.11, p[2]), 0.13, 'kabocha', 7 if lod else 10, 0.72)
    p = on(0.15, 0.0, 0.6)
    kago(m, p[0], p[1], p[2], 0.17, 0.3, lod)
    heap(m, p[0], p[1] + 0.3, p[2], 0.09, 0.09, 4, 0.05, 'kyabetsu', rng, lod, 0.8, layer=1)
    p = on(-0.2, 0.0, 0.62)
    u0, v0, u1, v1 = REG['straw']
    m.abox((p[0], p[1] + 0.17, p[2]), (0.16, 0.17, 0.22), MK, {'*': [u0, v0, u1, v1]}, 1.0, ax=K.X, ay=upv, az=fwd)
    if not lod:
        for z in (-0.45, 0.25):
            a = on(-0.45, 0.42, z)
            b = on(0.45, 0.42, z)
            cy(m, a, b, 0.008, 0.008, 4, 'nawa', caps=(False, False))
    return m


def tenbin(lod):
    m = new('mk_tenbin', lod, '天秤棒と籠 2：棒 1.7 を籠の縁に渡して置く、籠に青菜と魚（干物）、縄の吊り')
    rng = random.Random(10402)
    for i, (x, key) in enumerate(((-0.62, 'kyabetsu'), (0.62, 'himono'))):
        kago(m, x, 0.0, 0.0, 0.2, 0.3, lod)
        if key == 'kyabetsu':
            heap(m, x, 0.3, 0.0, 0.11, 0.11, 5, 0.06, 'kyabetsu', rng, lod, 0.75, layer=1)
        else:
            for j in range(5 if not lod else 2):
                a = j * 0.6
                c = (x + math.cos(a) * 0.08, 0.31 + 0.01 * j, math.sin(a) * 0.08)
                obx(m, c, (0.11, 0.012, 0.035), 'himono', ax=(math.cos(a + 1.2), 0.0, math.sin(a + 1.2)), az=(-math.sin(a + 1.2), 0.0, math.cos(a + 1.2)))
        if not lod:
            for k in range(4):
                a = k * math.pi / 2 + 0.4
                cy(m, (x + math.cos(a) * 0.2, 0.3, math.sin(a) * 0.2), (x, 0.62, 0.0), 0.005, 0.005, 3, 'nawa', caps=(False, False))
    pole(m, (-0.85, 0.36, 0.08), (0.85, 0.36, 0.08), 0.025, 'take')
    return m


def tsumini(lod):
    m = new('mk_tsumini', lod, '荷積み：木箱 4（2 段、ずらし）・米俵 3（2＋1）・菰包み 2・縄の束；市の裏手の置き場')
    rng = random.Random(10403)
    crate(m, -0.7, 0.0, 0.0, 0.62, 0.42, 0.44, 0.05, OLD)
    crate(m, -0.05, 0.0, 0.05, 0.62, 0.42, 0.44, -0.08, AGED)
    crate(m, -0.4, 0.42, 0.02, 0.6, 0.4, 0.42, 0.18, AGED)
    crate(m, -0.75, 0.0, -0.55, 0.58, 0.36, 0.42, 0.0, WOODC)
    for x, z in ((0.75, 0.15), (0.75, -0.35)):
        tawara(m, x, 0.0, z, 0.0, lod)
    tawara(m, 0.75, 0.38, -0.1, 0.0, lod)
    u0, v0, u1, v1 = REG['straw']
    for x, z, y in ((0.1, -0.55, 0.0), (0.3, -0.6, 0.0)):
        m.abox((x, y + 0.2, z), (0.17, 0.2, 0.15), MK, {'*': [u0, v0, u1, v1]}, 1.0, ax=(math.cos(0.3), 0.0, -math.sin(0.3)), az=(math.sin(0.3), 0.0, math.cos(0.3)))
    if not lod:
        for i in range(3):
            cy(m, (-0.05, 0.43 + i * 0.03, -0.62), (0.32, 0.43 + i * 0.03, -0.62), 0.03, 0.03, 6, 'nawa', caps=(True, True))
    return m


def kame(lod):
    m = new('mk_kame', lod, '甕 3：大（Ø0.66 × 0.78、木の蓋＋柄杓）・中 2（飴釉・黒釉）')
    jar(m, 0.0, 0.0, 0.0, 0.33, 0.78, 'ameyu', lod, lid=AGED)
    if not lod:
        cy(m, (0.05, 0.83, 0.05), (0.45, 1.05, 0.1), 0.012, 0.012, 4, 'take')
        cy(m, (0.0, 0.81, 0.0), (0.0, 0.86, 0.0), 0.06, 0.06, 8, 'take')
    jar(m, 0.62, 0.0, 0.18, 0.22, 0.52, 'kokuyu', lod)
    jar(m, 0.55, 0.0, -0.38, 0.2, 0.46, 'ameyu', lod, lid=OLD)
    return m


def hoshimono(lod):
    m = new('mk_hoshimono', lod, '干し竿：竹の X 脚 2（高 1.85）＋竿 2.8、布 3 枚（藍・縞・生成り）、吊るし柿の連 2、干し大根 6')
    rng = random.Random(10404)
    for x in (-1.35, 1.35):
        pole(m, (x - 0.35, 0.0, 0.0), (x + 0.12, 1.95, 0.0), 0.022)
        pole(m, (x + 0.35, 0.0, 0.0), (x - 0.12, 1.95, 0.0), 0.022)
    pole(m, (-1.55, 1.83, 0.0), (1.55, 1.83, 0.0), 0.02)
    for x, r in ((-0.85, 'nuno_ai'), (-0.25, 'nuno_shima'), (0.95, 'nuno_kasuri')):
        cloth(m, (x - 0.26, 0.92, 0.01), (x + 0.26, 0.92, 0.01), (x + 0.26, 1.82, 0.01), (x - 0.26, 1.82, 0.01), r)
    for x in (0.25, 0.48):
        cy(m, (x, 1.82, 0.0), (x, 1.05, 0.0), 0.004, 0.004, 3, 'nawa', caps=(False, False))
        for j in range(8 if not lod else 3):
            ball(m, (x + 0.02 * ((j % 2) * 2 - 1), 1.75 - j * 0.09, 0.0), 0.032, 'kaki', 5 if lod else 6, 0.9)
    for i in range(6 if not lod else 2):
        x = 1.3 - i * 0.05
        cy(m, (x, 1.82, 0.04), (x + 0.02, 1.32 + rng.uniform(-0.05, 0.05), 0.04), 0.022, 0.012, 5, 'daikon', caps=(False, True))
    return m


# ─────────────────────────── 出力 ───────────────────────────

def build_all():
    for lod in (0, 1):
        yatai_yasai(lod)
        yatai_dango(lod)
        yatai_meshi(lod)
        tana_nuno(lod)
        tana_seto(lod)
        yatai_sakana(lod)
        yatai_cha(lod)
        yatai_ame(lod)
        tana_kasa(lod)
        tana_omocha(lod)
        chochin_line(lod)
        tana_zakka(lod)
        mushiro_tsuke(lod)
        endai_uri(lod)
        mushiro_yasai(lod)
        mushiro_kago(lod)
        bangasa(lod)
        for k in ('yasai', 'cha', 'seto', 'tanmono', 'ichi'):
            nobori(k, lod)
        for k in ('yasai', 'dango', 'seto', 'furugi'):
            kanban(k, lod)
        kuruma_ni(lod)
        tenbin(lod)
        tsumini(lod)
        kame(lod)
        hoshimono(lod)


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
    K.export_glb(bpy, OUT + '/src/market_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_market_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=market_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[MKKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/market_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[MKKIT]   %-18s %5d 面  LOD1 %4d  dims %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims']))


main()
