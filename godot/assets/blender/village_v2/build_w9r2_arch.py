"""人間之里 V2 P13 W9 Round 2：建築外形の代表サンプル 10 棟（主街 6＋住宅巷 4）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_w9r2_arch.py

使用者 2026-10-15 裁定「W9 Round 2 改成『建築外形與街區特色強化』：主街 6 棟・住宅巷 4 棟、屋簷・附屬建物・正立面・店鋪用途を明確に変える」。
方針（重用優先）：
  - 封存済み build_machiya_kit.py は一字も触らず、main() 呼び出しの手前までを exec して前面開間（front1）・上層（upper）・屋面単位（roof_unit）・
    棟・鬼瓦・妻壁などの既存構件関数をそのまま再利用する（任意幅で呼べる）。
  - 新規は：深い庇／下屋・日除け幕・蔀・縁・出格子・寄棟屋根・妻入屋根・海鼠壁・1F 前面の組替えなど、建築の「輪郭」を変えるものだけ。
  - 座標＝町家 Kit と同じ body 局部座標（原點＝footprint 中心、y 0＝base、+z＝正面（通り側））。1 棟＝LOD0／LOD1 の 2 メッシュ。
  - 既存 Kit 側は overlay が該当構件（前面・屋根・庇）だけ非表示にする。footprint・入口位置・碰撞は変えない。
"""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v2_kit as K  # noqa: E402
import v2_irimoya as I  # noqa: E402
from v2_kit import X, Y, Z, add, mul, norm, sub  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/w9r2_arch'

# ── 封存済み町家 Kit の構件関数を（main() を呼ばずに）取り込む ──
_MK = HERE + '/build_machiya_kit.py'
_src = open(_MK, encoding='utf-8').read()
_src = _src[:_src.rindex('\nmain()')]
NS = {'__name__': 'machiya_defs', '__file__': _MK}
exec(compile(_src, _MK, 'exec'), NS)
MATS, TILE, RG, AM, KW = NS['MATS'], NS['TILE'], NS['RG'], NS['AM'], NS['KW']
FL, P, PL, DARK, BOARD, BENGARA = NS['FL'], NS['P'], NS['PL'], NS['DARK'], NS['BOARD'], NS['BENGARA']
HU, RU, POST_W = NS['HU'], NS['RU'], NS['POST_W']
SW = NS['SW']
EAVE_TRIM, END_TRIM, VERGE_IN, ONI_IN = 0.065, 0.03, 0.08, 0.075
SEC = math.sqrt(1 + P * P)

MODS = {}
INFO = {}


def new(name, note=''):
    m = K.Mesh(name, MATS, TILE)
    MODS[name] = m
    INFO[name] = note
    return m


def tmp(name='tmp'):
    return K.Mesh(name, MATS, TILE)


def put(dst, src, off=(0.0, 0.0, 0.0), sx=1.0, sy=1.0, sz=1.0, rot=0.0):
    """src の頂点を (スケール → y 軸回転 rot（Godot Basis(UP, rot) と同じ向き）→ 平行移動) して dst に追加。"""
    c, s = math.cos(rot), math.sin(rot)
    base = len(dst.v)
    for (x, y, z) in src.v:
        x, y, z = x * sx, y * sy, z * sz
        dst.v.append((c * x + s * z + off[0], y + off[1], -s * x + c * z + off[2]))
    for idx, mi, uvs, cols, sm in src.f:
        dst.f.append((tuple(i + base for i in idx), mi, uvs, cols, sm))


_cache = {}


def cached(key, fn):
    if key not in _cache:
        _cache[key] = fn()
    return _cache[key]


def FR(kind, wn, hk='h29'):
    return cached(('f1', kind, round(wn, 3), hk), lambda: NS['front1'](kind, wn, hk))


def UP(kind, wn, y0, y1):
    return cached(('up', kind, round(wn, 3), y0, y1), lambda: NS['upper'](kind, wn, y0, y1))


def HG(key, wn):
    return cached(('hang', key, round(wn, 3)), lambda: NS['hang'](key, wn))


def _newell(ps):
    nx = ny = nz = 0.0
    for i in range(len(ps)):
        a, b = ps[i], ps[(i + 1) % len(ps)]
        nx += (a[1] - b[1]) * (a[2] + b[2])
        ny += (a[2] - b[2]) * (a[0] + b[0])
        nz += (a[0] - b[0]) * (a[1] + b[1])
    return norm((nx, ny, nz))


def polyo(m, ps, mat, col=1.0, out=(0.0, 0.0, 1.0), grain=Y):
    """法線が out 側を向くように頂点順を整えて貼る。"""
    n = _newell(ps)
    ps = list(ps) if sum(a * b for a, b in zip(n, out)) >= 0 else list(reversed(ps))
    m.poly(ps, mat, col, grain=grain)


def bx(m, lo, hi, col=1.0, mat='V2_Wood', grain=None, skip=()):
    m.box(lo, hi, mat, col, grain=grain, skip=skip)


def rq2(m, a, b, c, d, key, col=1.0):
    """atlas 領域の両面板（a 左下・b 右下・c 右上・d 左上＝表から見て）。裏面も文字が逆にならない向き。"""
    m.rect_uv(a, b, c, d, AM, RG[key], col)
    m.rect_uv(b, a, d, c, AM, RG[key], col * 0.85)


def sq(m, a, b, c, d, key, col=1.0):
    """atlas 色票（無地）の片面板。a→b→c→d は外から見て反時計回り。"""
    u, v = SW[key]
    m.quad(a, b, c, d, AM, col, uvs=[(u, v)] * 4)


# ───────────────────────── 屋根 ─────────────────────────

def roof_unit_c(s, nh, p):
    return cached(('ru', round(s, 3), nh, round(p, 3)), lambda: NS['roof_unit'](s, nh, 'tmp_ru', p, ''))


def roof_row(dst, lod, x0, L, s, p, off, rot=0.0):
    """屋面の行：棟線（off）から s だけ下る片流れを x 方向 L にわたって（Kit と同じ 4／2／1 単位を並べ、x を伸縮）。
    rot=π で背面坡（x が反転するので呼び出し側で x0 を右端にする）。lod>=1 は平らな 1 枚。"""
    if lod >= 1:
        t = tmp()
        dsl = norm((0.0, -p, 1.0))
        n = norm((0.0, 1.0, p))
        K.tile_roof(t, (0.0, 0.0, 0.0), dsl, n, 0.0, L, s * math.sqrt(1 + p * p), KW, 2, seg_per_col=2, ends=False)
        put(dst, t, off=(off[0] + (x0 if rot == 0.0 else -x0), off[1], off[2]), rot=rot)
        return
    n_ = max(1, int(round(L / HU)))
    kx = L / (n_ * HU)
    left = n_
    x = 0.0
    for u in (4, 2, 1):
        while left >= u:
            put(dst, roof_unit_c(s, u, p), off=(off[0] + (x0 + x if rot == 0.0 else -(x0 + x)), off[1], off[2]), sx=kx, rot=rot)
            x += u * HU * kx
            left -= u


def gable_roof(dst, lod, wall_len, half, eave, p, ove, ovg, ridge_dz=0.0, tsuma=False, oni=True, gyo=True, ridge_scale=1.0):
    """切妻屋根（Kit _roof と同じ組立：屋面行・螻羽・妻壁半片・棟・鬼瓦）。
    wall_len＝棟方向の壁長、half＝棟直交方向の半幅（平入＝d/2）。F 回転で妻入に。棟は y＝eave＋p·half。"""
    H = eave + p * half
    L = wall_len + ovg * 2.0
    Lp = L - END_TRIM * 2.0
    S = half + ove - EAVE_TRIM
    for side in (0, 1):
        sgn = 1.0 if side == 0 else -1.0
        rot = math.pi * side
        roof_row(dst, lod, -Lp * 0.5, Lp, S, p, (0.0, H, 0.0), rot=rot)
        if lod == 0:
            for e in (-1.0, 1.0):
                t = NS['verge'](S, p, '')
                put(dst, t, off=(e * (L * 0.5 - VERGE_IN), H, 0.0), sz=1.0, rot=rot)
            t = NS['gable_half'](half, p, '')
            for e in (-1.0, 1.0):
                put(dst, t, off=(e * wall_len * 0.5, eave, 0.0), rot=-math.pi * 0.5 * sgn)
        else:
            # LOD1：妻壁三角（片側ずつ）
            for e in (-1.0, 1.0):
                polyo(dst, [(e * wall_len * 0.5, eave, 0.0), (e * wall_len * 0.5, eave, sgn * half), (e * wall_len * 0.5, H, 0.0)],
                      'V2_Plaster', PL, out=(e, 0.0, 0.0))
    if lod == 0:
        t = tmp()
        put(t, cached(('rg',), lambda: NS['ridge_unit']()), sx=(L - 2.0 * ONI_IN) * ridge_scale / RU)
        put(dst, t, off=(-L * 0.5 + ONI_IN, H, 0.0))
        if oni:
            for e in (-1.0, 1.0):
                put(dst, cached(('oni',), lambda: NS['oni']()), off=(e * (L * 0.5 - ONI_IN), H, 0.0))
    else:
        dst.box((-L * 0.5, H - 0.02, -0.12), (L * 0.5, H + 0.18, 0.12), 'V2_Kawara', 0.66, grain=X)
    return H


def hip_roof(dst, lod, HA, HB, y_wall, p, ove, ridge_box=True):
    """寄棟屋根。ローカル枠：棟は +x 方向。HA＝棟方向の壁半長、HB＝直交方向の壁半幅（HA ≥ HB）。
    屋面は壁頂（y_wall）を通り、勾配 p は四面同じ。簷先は壁から ove 出る（四辺同じ）。返り値＝棟高。"""
    ha, hb = HA + ove, HB + ove
    xt = ha - hb
    y_e = y_wall - p * ove
    y_r = y_e + p * hb
    S = hb * math.sqrt(1 + p * p)
    sec = math.sqrt(1 + p * p)
    tkw = KW
    for sg in (1, -1):
        o = (0.0, y_r, 0.0)
        dsl = norm((0.0, -p, float(sg)))
        n = norm((0.0, 1.0, p * sg))
        ax = (float(sg), 0.0, 0.0)
        I.tile_band(dst, o, ax, dsl, n, lambda s: -(xt + s / sec), lambda s: xt + s / sec, S, tkw, 2 if lod else 0, ends=(lod == 0))
        I.under(dst, o, ax, dsl, n, lambda s: -(xt + s / sec), lambda s: xt + s / sec, S)
        a, b = (-ha, y_e, sg * hb), (ha, y_e, sg * hb)
        dst.beam(add(a, mul(n, -0.06)), add(b, mul(n, -0.06)), 0.07, 0.24, 'V2_Wood', DARK * 0.9, up=n)
    for sx in (1, -1):
        o = (sx * xt, y_r, 0.0)
        dsl = norm((float(sx), -p, 0.0))
        n = norm((p * sx, 1.0, 0.0))
        ax = (0.0, 0.0, -float(sx))
        I.tile_band(dst, o, ax, dsl, n, lambda s: -(s / sec), lambda s: s / sec, S, tkw, 2 if lod else 0, ends=(lod == 0))
        I.under(dst, o, ax, dsl, n, lambda s: -(s / sec), lambda s: s / sec, S)
        a, b = (sx * ha, y_e, -hb), (sx * ha, y_e, hb)
        dst.beam(add(a, mul(n, -0.06)), add(b, mul(n, -0.06)), 0.07, 0.24, 'V2_Wood', DARK * 0.9, up=n)
        for sz in (1, -1):
            I.hip_ridge(dst, (sx * xt, y_r, 0.0), (sx * ha, y_e, sz * hb), lod, w=0.26, h=0.18)
    if xt > 0.05:
        I.hip_ridge(dst, (-xt, y_r, 0.0), (xt, y_r, 0.0), lod, w=0.30, h=0.22)
    elif ridge_box:
        dst.box((-0.2, y_r, -0.2), (0.2, y_r + 0.3, 0.2), 'V2_Kawara', 0.62)
    return y_r


# ───────────────────────── 庇・下屋・布・小構件 ─────────────────────────

def eave_roof(dst, lod, x0, x1, y, zf, depth, p=0.36, style='tile', brackets=True, strut=False, fascia_col=DARK):
    """壁（z＝zf）に付く片流れの庇：壁際の屋面線 y から depth だけ前へ、勾配 p で下る。style='tile'（瓦）／'board'（杉板葺）。
    腕木（brackets）を壁から出し、深い庇（strut）は斜材で受ける。x0..x1 の範囲。"""
    L = x1 - x0
    s = depth - 0.04
    if style == 'tile':
        roof_row(dst, lod, x0, L, s, p, (0.0, y, zf))
    else:
        n = norm((0.0, 1.0, p))
        dsl = norm((0.0, -p, 1.0))
        a = (x0, y, zf)
        b = (x1, y, zf)
        c = (x1, y - s * p, zf + s)
        d = (x0, y - s * p, zf + s)
        dst.quad(d, c, b, a, 'V2_Wood', 0.95, grain=Z)
        for i in range(max(2, int(L / 0.38))):                      # 押縁
            xx = x0 + L * (i + 0.5) / max(2, int(L / 0.38))
            dst.box((xx - 0.012, y - 0.0, zf), (xx + 0.012, y + 0.03, zf + 0.02), 'V2_Wood', DARK)
        dst.quad(a, b, (x1, y - 0.06, zf), (x0, y - 0.06, zf), 'V2_Wood', DARK, grain=X)
    if lod:
        return
    # 出桁（先端の桁）と化粧板
    ye = y - s * p
    dst.box((x0, ye - 0.22, zf + s - 0.1), (x1, ye - 0.08, zf + s + 0.02), 'V2_Wood', fascia_col, grain=X)
    dst.box((x0, y - 0.05, zf - 0.04), (x1, y + 0.06, zf + 0.02), 'V2_Kawara' if style == 'tile' else 'V2_Wood', 0.75, grain=X)
    if brackets:
        nb = max(2, int(round(L / 0.95)))
        for i in range(nb + 1):
            xb = x0 + 0.15 + (L - 0.3) * i / nb
            if strut:
                dst.beam((xb, y - 0.16, zf - 0.02), (xb, ye - 0.15, zf + s - 0.08), 0.07, 0.10, 'V2_Wood', DARK)       # 腕木
                dst.beam((xb, y - 1.05, zf - 0.02), (xb, ye - 0.14, zf + s - 0.12), 0.06, 0.08, 'V2_Wood', DARK)       # 斜材
            else:
                dst.beam((xb, y - 0.16, zf - 0.02), (xb, ye - 0.15, zf + s - 0.08), 0.07, 0.10, 'V2_Wood', DARK)


def cloth(dst, x0, x1, ytop, ybot, z, key, seg_w=0.9, billow=0.05, tilt=0.0, col=1.0, rod=True):
    """布（暖簾・日除け幕）：atlas 暖簾領域を幅 seg_w ごとの短冊に貼る（両面）。上辺 z、下辺 z＋tilt、短冊ごとに少しはらむ。"""
    n = max(1, int(round((x1 - x0) / seg_w)))
    w = (x1 - x0) / n
    for i in range(n):
        a = x0 + w * i
        b = a + w - 0.012
        bz = billow * (1 if i % 2 == 0 else -0.6)
        rq2(dst, (a, ybot, z + tilt + bz), (b, ybot, z + tilt + bz), (b, ytop, z), (a, ytop, z), key, col)
    if rod:
        dst.box((x0 - 0.04, ytop - 0.02, z - 0.03), (x1 + 0.04, ytop + 0.04, z + 0.03), 'V2_Wood', DARK, grain=X)


def sloped_cloth(dst, x0, x1, y_hi, z_hi, y_lo, z_lo, key, seg_w=0.95, col=1.0, drop=0.0):
    """斜めに張る日除け幕（上端は庇、下端は竹竿）。drop＝裾の垂れ。"""
    n = max(1, int(round((x1 - x0) / seg_w)))
    w = (x1 - x0) / n
    for i in range(n):
        a = x0 + w * i
        b = a + w - 0.012
        rq2(dst, (a, y_lo - drop, z_lo), (b, y_lo - drop, z_lo), (b, y_hi, z_hi), (a, y_hi, z_hi), key, col)
    dst.beam((x0, y_lo, z_lo), (x1, y_lo, z_lo), 0.045, 0.045, 'V2_Wood', DARK)


def shitomi(dst, x0, x1, y_hinge, zf, rise=0.85, out=0.9):
    """蔀戸（上げて吊る格子戸）：y_hinge の鴨居で蝶番、leaf は前上方へ out 出して突っ支い棒で支える。"""
    z1, y1 = zf + out, y_hinge + rise
    # leaf を下面（店内側）が見えるように 2 枚の面で：外側＝格子、内側＝暗い裏
    a = (x0, y_hinge, zf)
    b = (x1, y_hinge, zf)
    c = (x1, y1, z1)
    d = (x0, y1, z1)
    dst.rect_uv(d, c, b, a, AM, RG['koshi_b'], 0.95)                      # 上面（前から見て）
    dst.quad(a, b, c, d, 'V2_Wood', DARK * 0.7, grain=X)                    # 下面（店先から見上げ）
    for xx in (x0, x1 - 0.06):
        dst.beam((xx + 0.03, y_hinge, zf), (xx + 0.03, y1, z1), 0.06, 0.06, 'V2_Wood', DARK)
    dst.beam((x0, y1, z1), (x1, y1, z1), 0.07, 0.07, 'V2_Wood', DARK)
    for xx in (x0 + 0.12, x1 - 0.12):                                       # 突っ支い棒
        dst.beam((xx, y_hinge - 1.15, zf + out * 0.95), (xx, y1 - 0.05, z1 - 0.02), 0.035, 0.035, 'V2_Wood', DARK)


def agari_en(dst, x0, x1, zf, y=0.62, out=0.55):
    """揚げ縁（折り畳み縁台）：下ろして腰掛け台に。"""
    dst.box((x0, y - 0.05, zf), (x1, y, zf + out), 'V2_Wood', BOARD, grain=X)
    for xx in (x0 + 0.1, x1 - 0.14):
        dst.box((xx, FL, zf + out - 0.1), (xx + 0.06, y - 0.05, zf + out - 0.04), 'V2_Wood', DARK, grain=Y)


def barrel_stack(dst, x0, zc, rows=(4, 3, 2), r=0.28, h=0.62, col=0.62):
    """酒樽（もろ蓋樽）の三角積み。x0＝左端、zc＝中心 z。"""
    y = FL
    for ri, n in enumerate(rows):
        for i in range(n):
            xc = x0 + r + i * 2 * r * 1.02 + ri * r
            p0 = (xc, y, zc)
            p1 = (xc, y + h, zc)
            dst.cyl(p0, p1, r, r, 12, 'V2_Wood', col, caps=(True, True))
            for yy in (y + 0.12, y + h - 0.12):
                dst.cyl((xc, yy, zc), (xc, yy + 0.03, zc), r + 0.008, r + 0.008, 12, 'V2_Wood', DARK * 0.6, caps=(False, False))
        y += h * 0.9


# ───────────────────────── 追加の小構件 ─────────────────────────

def tint(m, tints):
    """面の頂点色に tint を掛ける（上限 1.0）。Kit の色変体（FIN／TONE）と同じ規則。"""
    nf = []
    for (idx, mi, uvs, cols, sm) in m.f:
        t = tints.get(m.mats[mi])
        if t:
            cols = tuple(tuple(min(1.0, c[k] * t[k]) for k in range(3)) for c in cols)
        nf.append((idx, mi, uvs, cols, sm))
    m.f = nf


def namako(dst, x0, x1, y0, y1, z, cell=0.24, tcol=0.42):
    """海鼠壁：白漆喰の格子目地（盛り上がり）に暗い平瓦。z＝壁面。"""
    dst.quad((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z), 'V2_Plaster', PL, grain=Y)
    nx = max(2, int(round((x1 - x0) / cell)))
    ny = max(2, int(round((y1 - y0) / cell)))
    cw, ch = (x1 - x0) / nx, (y1 - y0) / ny
    j = 0.03
    for iy in range(ny):
        for ix in range(nx):
            a, b = x0 + ix * cw + j, x0 + (ix + 1) * cw - j
            c, d = y0 + iy * ch + j, y0 + (iy + 1) * ch - j
            dst.quad((a, c, z + 0.012), (b, c, z + 0.012), (b, d, z + 0.012), (a, d, z + 0.012), 'V2_Kawara', tcol, grain=Y)
    for iy in range(ny + 1):
        yy = y0 + iy * ch
        dst.box((x0, yy - j * 0.8, z), (x1, yy + j * 0.8, z + 0.02), 'V2_Plaster', PL, grain=X)
    for ix in range(nx + 1):
        xx = x0 + ix * cw
        dst.box((xx - j * 0.8, y0, z), (xx + j * 0.8, y1, z + 0.02), 'V2_Plaster', PL, grain=Y)


def shoji_bay(dst, x0, x1, y0, y1, z, frame=DARK):
    """障子戸（atlas shoji）：枠＋敷居＋鴨居。壁より 0.05 退く。"""
    dst.rect_uv((x0 + 0.05, y0, z - 0.05), (x1 - 0.05, y0, z - 0.05), (x1 - 0.05, y1, z - 0.05), (x0 + 0.05, y1, z - 0.05), AM, RG['shoji'], 0.95)
    for xx in (x0, x1 - 0.06):
        dst.box((xx, y0, z - 0.07), (xx + 0.06, y1 + 0.06, z + 0.03), 'V2_Wood', frame, grain=Y)
    dst.box((x0, y1, z - 0.07), (x1, y1 + 0.1, z + 0.03), 'V2_Wood', frame, grain=X)
    dst.box((x0, y0 - 0.05, z - 0.07), (x1, y0, z + 0.05), 'V2_Wood', frame, grain=X)


def logs(dst, x0, x1, z, rows=3, r=0.1, y0=FL, col=0.85):
    """壁際に積んだ丸太（軸は x）：下段から n, n-1, …"""
    n0 = max(2, int((x1 - x0) / (2 * r)))
    for ri in range(rows):
        n = n0 - ri
        for i in range(n):
            xc = x0 + r + i * 2 * r * 1.01 + ri * r
            zc = z + r + (0.02 if (i + ri) % 2 else 0.0)
            yc = y0 + r + ri * r * 1.75
            dst.cyl((xc, yc, zc - r * 1.0), (xc, yc, zc + r * 1.0), r, r, 8, 'V2_Wood', col, caps=(True, True))


def engawa(dst, x0, x1, zf, h=0.42, depth=0.55):
    """縁側（高床のデッキ）：床板＋縁框＋束石。"""
    dst.box((x0, h - 0.06, zf), (x1, h, zf + depth), 'V2_Wood', BOARD, grain=X)
    dst.box((x0, h - 0.18, zf + depth - 0.06), (x1, h - 0.06, zf + depth), 'V2_Wood', DARK, grain=X)
    n = max(2, int((x1 - x0) / 1.2))
    for i in range(n + 1):
        xx = x0 + 0.1 + (x1 - x0 - 0.3) * i / n
        dst.box((xx, FL - 0.1, zf + depth - 0.22), (xx + 0.14, h - 0.18, zf + depth - 0.08), 'V2_KitStoneTri', 0.8)


def balcony(dst, x0, x1, y, zf, depth=0.75, rail=0.95):
    """2F の縁：床＋出桁＋手摺（縦桟＋笠木）。"""
    dst.box((x0, y - 0.08, zf), (x1, y, zf + depth), 'V2_Wood', BOARD, grain=X)
    dst.box((x0, y - 0.22, zf + depth - 0.08), (x1, y - 0.08, zf + depth), 'V2_Wood', DARK, grain=X)
    for xb in [x0 + 0.2 + (x1 - x0 - 0.4) * i / max(1, int((x1 - x0) / 0.95)) for i in range(max(1, int((x1 - x0) / 0.95)) + 1)]:
        dst.beam((xb, y - 0.14, zf + 0.05), (xb, y - 0.32, zf + depth - 0.02), 0.07, 0.08, 'V2_Wood', DARK)
    zr = zf + depth - 0.05
    dst.box((x0, y + rail - 0.05, zr), (x1, y + rail + 0.03, zr + 0.07), 'V2_Wood', DARK, grain=X)
    dst.box((x0, y + 0.25, zr + 0.01), (x1, y + 0.3, zr + 0.05), 'V2_Wood', DARK, grain=X)
    n = max(3, int((x1 - x0) / 0.3))
    for i in range(n + 1):
        xx = x0 + (x1 - x0 - 0.04) * i / n
        dst.box((xx, y, zr + 0.01), (xx + 0.04, y + rail - 0.05, zr + 0.05), 'V2_Wood', DARK, grain=Y)
    for xx in (x0, x1 - 0.07):
        dst.box((xx, y, zr - 0.01), (xx + 0.07, y + rail + 0.03, zr + 0.08), 'V2_Wood', DARK, grain=Y)


def deguchi(dst, x0, x1, y0, y1, zf, out=0.35):
    """出格子（2F）：外へ out 出る格子の箱＋小屋根板。"""
    zo = zf + out
    dst.rect_uv((x0, y0, zo), (x1, y0, zo), (x1, y1, zo), (x0, y1, zo), AM, RG['koshi_b'], 0.95)
    for (xa, xb, na) in ((x0, x0, -1.0), (x1, x1, 1.0)):
        dst.quad((xa, y0, zf), (xa, y0, zo), (xa, y1, zo), (xa, y1, zf), 'V2_Wood', DARK * 0.9, grain=Z) if na < 0 else \
            dst.quad((xb, y0, zo), (xb, y0, zf), (xb, y1, zf), (xb, y1, zo), 'V2_Wood', DARK * 0.9, grain=Z)
    dst.box((x0 - 0.03, y1, zf - 0.02), (x1 + 0.03, y1 + 0.06, zo + 0.05), 'V2_Wood', DARK, grain=X)
    dst.box((x0 - 0.03, y0 - 0.1, zf - 0.02), (x1 + 0.03, y0, zo + 0.05), 'V2_Wood', DARK, grain=X)
    for xx in (x0, x1 - 0.05):
        dst.box((xx, y0, zo - 0.02), (xx + 0.05, y1, zo + 0.03), 'V2_Wood', DARK, grain=Y)


def hung_goods(dst, x0, x1, y, z, n=6, seed=1):
    """竹棹に吊るした箒・籠・笊（円柱と円錐台で簡略）。下端は常に y−0.55 以上＝通行人の頭より上（棹 y≥2.4 前提）。"""
    dst.beam((x0, y, z), (x1, y, z), 0.035, 0.035, 'V2_Wood', DARK)
    for i in range(n):
        xx = x0 + 0.15 + (x1 - x0 - 0.3) * i / max(1, n - 1)
        k = (i * 7 + seed) % 3
        if k == 0:       # 箒
            dst.cyl((xx, y - 0.03, z), (xx, y - 0.55, z), 0.03, 0.15, 8, 'V2_Wood', 0.95, caps=(False, True))
        elif k == 1:     # 籠
            dst.cyl((xx, y - 0.12, z), (xx, y - 0.5, z), 0.17, 0.11, 10, 'V2_Wood', 0.78, caps=(True, True))
            dst.beam((xx, y, z), (xx, y - 0.12, z), 0.015, 0.015, 'V2_Wood', DARK)
        else:            # 笊
            dst.cyl((xx, y - 0.1, z), (xx, y - 0.2, z), 0.22, 0.18, 10, 'V2_Wood', 0.9, caps=(True, True))
            dst.beam((xx, y, z), (xx, y - 0.1, z), 0.015, 0.015, 'V2_Wood', DARK)


# ───────────────────────── 建物ごとの組立 ─────────────────────────

class Bld:
    def __init__(self, bid, w, d, eave, hk='h29', fin=0, tone=0):
        self.id = bid
        self.w, self.d, self.eave, self.hk = w, d, eave, hk
        self.zf = d / 2.0
        self.fin, self.tone = fin, tone
        self.m0 = new(bid + '_L0', bid + ' LOD0')
        self.m1 = new(bid + '_L1', bid + ' LOD1')
        self.W = [tmp('w0'), tmp('w1')]      # 壁・前面（FIN 色変体）
        self.R = [tmp('r0'), tmp('r1')]      # 屋根・庇（TONE 瓦色変体）

    def finish(self):
        FIN, TONE = NS['FIN'], NS['TONE']
        for lod, dst in ((0, self.m0), (1, self.m1)):
            if self.fin:
                tint(self.W[lod], {'V2_Plaster': FIN[self.fin][0], 'V2_Wood': FIN[self.fin][1]})
            if self.tone:
                tint(self.R[lod], {'V2_Kawara': TONE[self.tone]})
            put(dst, self.W[lod])
            put(dst, self.R[lod])


def row1(B, m, bays, dz=0.0):
    x = -B.w / 2
    for kind, wn in bays:
        if kind:
            put(m, FR(kind, wn, B.hk), off=(x, 0.0, B.zf + dz))
        x += wn
    assert abs(x - B.w / 2) < 0.02, (B.id, 'row1 sum', x, B.w / 2)


def row2(B, m, bays, y0, y1, dz=0.0):
    x = -B.w / 2
    for kind, wn in bays:
        if kind:
            put(m, UP(kind, wn, y0, y1), off=(x, 0.0, B.zf + dz))
        x += wn
    assert abs(x - B.w / 2) < 0.02, (B.id, 'row2 sum', x, B.w / 2)


def hip_on_body(B, lod, y_wall, p, ove, HA=None, HB=None):
    """寄棟（棟は長い方の軸）。d>w なら棟は z 方向（ローカル枠で組んで回す）。"""
    t = B.R[lod]
    a, b = B.w / 2, B.d / 2
    tm = tmp()
    if a >= b:
        H = hip_roof(tm, lod, a, b, y_wall, p, ove)
        put(t, tm)
    else:
        H = hip_roof(tm, lod, b, a, y_wall, p, ove)
        put(t, tm, rot=math.pi * 0.5)
    return H


def gable_on_body(B, lod, y_wall, p, ove, ovg, tsuma, ridge_scale=1.0, oni=True):
    tm = tmp()
    if tsuma:
        H = gable_roof(tm, lod, B.d, B.w / 2, y_wall, p, ove, ovg, oni=oni, ridge_scale=ridge_scale)
        put(B.R[lod], tm, rot=-math.pi * 0.5)
    else:
        H = gable_roof(tm, lod, B.w, B.d / 2, y_wall, p, ove, ovg, oni=oni, ridge_scale=ridge_scale)
        put(B.R[lod], tm)
    return H


def build_mkt012():
    """B_P_MKT_012 酒屋（大店）：寄棟＋深い瓦庇＋藍の日除け幕＋蔀＋樽。入口＝x 0（幅 1.733）。"""
    B = Bld('B_P_MKT_012', 5.197, 10.92, 5.4, fin=2, tone=0)
    w, zf = B.w, B.zf
    wl = w / 2 - 0.8665
    bays1 = [('koshir', wl), ('shop_o', 1.733), ('shop_k', w - wl - 1.733)]
    bays2 = [('winb', wl), ('winb', 1.733), ('winb', w - wl - 1.733)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        if lod == 0:
            row1(B, W, bays1)
            row2(B, W, bays2, 2.9, 5.4)
        hip_on_body(B, lod, 5.4, 0.55, 0.10)
        eave_roof(R, lod, -w / 2 - 0.02, w / 2 + 0.02, 2.95, zf, 1.5, p=0.30, style='tile', strut=True)
        if lod == 0:
            cloth(W, -w / 2 + 0.2, w / 2 - 0.2, 2.62, 1.92, zf + 1.38, 'noren_a', seg_w=0.86, tilt=0.06)
            shitomi(W, -w / 2 + 0.1, -0.95, 2.0, zf + 0.02, 0.4, 0.55)
            barrel_stack(W, w / 2 - 1.65, zf + 0.4, rows=(3, 2))
    B.finish()
    return B


def build_mkt013():
    """B_P_MKT_013 薬屋（厨子二階）：板庇＋袖卯建＋袖看板＋蔀＋揚げ縁＋暖簾。入口＝x −1.317..0.439。"""
    B = Bld('B_P_MKT_013', 7.902, 10.92, 3.9, hk='h27', fin=4, tone=2)
    w, zf = B.w, B.zf
    bays1 = [('koshib', 1.3), ('shop_k', 1.334), ('shop_o', 1.756), ('koshir', 1.756), ('koshib', 1.756)]
    bays2 = [('mushib', 1.3), ('mushi', 1.334), ('mushi', 1.756), ('mushib', 1.756), ('mushi', 1.756)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        eave_roof(R, lod, -w / 2, w / 2, 2.75, zf, 1.05, p=0.30, style='board')
        if lod == 0:
            row1(B, W, bays1)
            row2(B, W, bays2, 2.7, 3.9)
            for e in (-1.0, 1.0):
                put(W, cached(('ud72',), lambda: NS['udatsu'](0.72)), off=(e * (w / 2 - 0.13), 2.7, zf))
            put(W, cached(('kbs_c',), lambda: NS['kanban_side']('kanban_c')), off=(w / 2 - 0.5, 2.7, zf))
            x_sk = -w / 2 + 1.3
            shitomi(W, x_sk + 0.04, x_sk + 1.3, 1.9, zf + 0.02, 0.35, 0.6)
            agari_en(W, x_sk + 0.05, x_sk + 1.18, zf, y=0.62, out=0.45)
            cloth(W, -1.317 + 0.1, 0.439 - 0.1, 2.25, 1.5, zf + 0.03, 'noren_d', seg_w=0.8, billow=0.04, rod=True)
    B.finish()
    return B


def build_mkt011():
    """B_P_MKT_011 荒物屋：深い板庇（腕木＋斜材）＋吊るし売りの竿＋簾＋店先の籠。入口＝x 0..1.75。"""
    B = Bld('B_P_MKT_011', 7.004, 10.01, 5.4, fin=3, tone=1)
    w, zf = B.w, B.zf
    bays1 = [('shop_c', 1.75), ('shop_c', 1.75), ('shop_o', 1.75), ('koshib', w - 5.25)]
    bays2 = [('amado', 1.75), ('amado', 1.75), ('wins', 1.75), ('amado', w - 5.25)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        eave_roof(R, lod, -w / 2, w / 2, 2.95, zf, 2.0, p=0.20, style='board', strut=True)
        if lod == 0:
            row1(B, W, bays1)
            row2(B, W, bays2, 2.9, 5.4)
            hung_goods(W, -w / 2 + 0.1, 0.0, 2.4, zf + 1.1, n=6, seed=3)
            hung_goods(W, 0.1, w / 2 - 0.1, 2.4, zf + 1.75, n=8, seed=5)
            cloth(W, 0.1, 1.65, 2.25, 1.5, zf + 0.03, 'sudare_b', seg_w=0.78, billow=0.03, rod=True)
            bx(W, (-w / 2 + 0.2, FL, zf + 0.05), (-w / 2 + 1.3, FL + 0.55, zf + 0.5), 0.85)
            bx(W, (-w / 2 + 0.3, FL + 0.55, zf + 0.1), (-w / 2 + 1.1, FL + 1.0, zf + 0.45), 0.9)
    B.finish()
    return B


def build_mkt010():
    """B_P_MKT_010 蔵造りの住居（妻入）：海鼠壁＋観音開きの土戸＋鉄格子窓＋急な妻入屋根・太い棟。入口＝x −2.195..−0.439。"""
    B = Bld('B_P_MKT_010', 7.905, 10.92, 3.9, hk='h27', fin=0, tone=2)
    w, zf = B.w, B.zf
    x_l = -w / 2
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        gable_on_body(B, lod, 3.9, 0.58, 0.10, 0.30, True, ridge_scale=1.0)
        eave_roof(R, lod, -w / 2 - 0.05, w / 2 + 0.05, 2.72, zf, 0.75, p=0.33, style='tile', brackets=False)
        if lod == 0:
            # 1F：海鼠壁（腰〜1.25）＋白漆喰（〜2.7）。入口と窓は別
            door0, door1 = -2.195, -0.439
            namako(W, x_l, door0, FL, 1.25, zf, 0.24)
            namako(W, door1, w / 2, FL, 1.25, zf, 0.24)
            W.quad((x_l, 1.25, zf), (door0, 1.25, zf), (door0, 2.62, zf), (x_l, 2.62, zf), 'V2_Plaster', PL, grain=Y)
            W.quad((door1, 1.25, zf), (w / 2, 1.25, zf), (w / 2, 2.62, zf), (door1, 2.62, zf), 'V2_Plaster', PL, grain=Y)
            W.quad((door0, 2.2, zf), (door1, 2.2, zf), (door1, 2.62, zf), (door0, 2.62, zf), 'V2_Plaster', PL, grain=Y)
            # 土戸（観音開き）：深い抱き、厚い扉、鉄の帯金
            zin = zf - 0.28
            W.quad((door0, FL, zin), (door1, FL, zin), (door1, 2.2, zin), (door0, 2.2, zin), 'V2_Wood', DARK * 0.6, grain=Y)
            xm = (door0 + door1) / 2
            for (a, b) in ((door0 + 0.04, xm - 0.02), (xm + 0.02, door1 - 0.04)):
                W.box((a, FL, zin), (b, 2.15, zin + 0.1), 'V2_Plaster', 0.62, grain=Y)
                for yy in (0.8, 1.4, 1.95):
                    W.box((a, yy, zin + 0.1), (b, yy + 0.07, zin + 0.125), 'V2_Wood', DARK * 0.45, grain=X)
            for xx in (door0, door1 - 0.1):
                W.box((xx, FL, zin), (xx + 0.1, 2.25, zf + 0.02), 'V2_Plaster', PL * 0.9, grain=Y)
            W.box((door0 - 0.06, 2.2, zin), (door1 + 0.06, 2.3, zf + 0.04), 'V2_Plaster', PL * 0.9, grain=X)
            # 鉄格子窓 2
            for (xa, xb) in ((x_l + 0.7, x_l + 1.9), (0.3, 1.5)):
                W.rect_uv((xa, 1.55, zf - 0.12), (xb, 1.55, zf - 0.12), (xb, 2.15, zf - 0.12), (xa, 2.15, zf - 0.12), AM, RG['koshi_b'], 0.55)
                NS['reveal'](tmp(), 0, 1, 0, 1, 0.0) if False else None
                W.box((xa - 0.1, 1.5, zf - 0.14), (xb + 0.1, 1.55, zf + 0.03), 'V2_Plaster', PL * 0.9, grain=X)
                W.box((xa - 0.1, 2.15, zf - 0.14), (xb + 0.1, 2.22, zf + 0.03), 'V2_Plaster', PL * 0.9, grain=X)
                W.box((xa - 0.1, 1.5, zf - 0.14), (xa, 2.22, zf + 0.03), 'V2_Plaster', PL * 0.9, grain=Y)
                W.box((xb, 1.5, zf - 0.14), (xb + 0.1, 2.22, zf + 0.03), 'V2_Plaster', PL * 0.9, grain=Y)
            # 2F（低い）：土蔵窓 2 と白壁
            row2(B, W, [('mushib', 1.756), ('plain', 1.756), ('mushib', 1.756), ('mushib', 1.756), ('plain', w - 7.024)], 2.7, 3.9)
            # 鉢巻（軒下の厚い漆喰帯）
            W.box((-w / 2 - 0.04, 3.55, zf - 0.02), (w / 2 + 0.04, 3.9, zf + 0.14), 'V2_Plaster', PL * 0.95, grain=X)
            W.box((-w / 2 - 0.04, 2.62, zf - 0.02), (w / 2 + 0.04, 2.72, zf + 0.12), 'V2_Plaster', PL * 0.92, grain=X)
    B.finish()
    return B


def build_mkt009():
    """B_P_MKT_009 茶屋（二階建て・妻入）：妻入屋根＋2F 縁（手摺）＋庇下の縁台＋赤い日除け幕。入口＝x −1.44..0.48。"""
    B = Bld('B_P_MKT_009', 4.796, 9.1, 5.4, fin=4, tone=0)
    w, zf = B.w, B.zf
    bays1 = [('plain', 0.96), ('shop_o', 1.92), ('shop_k', w - 2.88)]
    bays2 = [('amado', 0.96), ('win', 1.92), ('wins', w - 2.88)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        gable_on_body(B, lod, 5.4, 0.62, 0.10, 0.35, True)
        eave_roof(R, lod, -w / 2 - 0.03, w / 2 + 0.03, 2.95, zf, 1.1, p=0.30, style='tile', strut=False)
        if lod == 0:
            row1(B, W, bays1)
            row2(B, W, bays2, 2.9, 5.4, dz=-0.45)
            balcony(W, -0.2, w / 2 - 0.02, 2.95 + 0.0, zf - 0.45, depth=0.5, rail=0.85) if False else None
            sloped_cloth(W, -w / 2 + 0.1, w / 2 - 0.1, 2.55, zf + 1.05, 1.98, zf + 1.45, 'noren_e', seg_w=0.8, drop=0.12)
            bx(W, (0.95, FL, zf + 0.45), (2.3, 0.5, zf + 0.9), 0.9)
            bx(W, (-2.3, FL, zf + 0.45), (-1.85, 0.42, zf + 0.85), 0.9)
    B.finish()
    return B


def build_mkt008():
    """B_P_MKT_008 大工の家（平屋）：低い寄棟＋右半分は材木置き場の下屋（開放作業場）＋積み丸太。入口＝x −1.75..0。"""
    B = Bld('B_P_MKT_008', 7.0, 10.92, 2.9, fin=3, tone=2)
    w, zf = B.w, B.zf
    bays1 = [('koshib', 1.75), ('door', 1.75), ('shop_o', 1.75), ('shop_o', 1.75)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        H = hip_on_body(B, lod, 2.9, 0.5, 0.15)
        eave_roof(R, lod, 0.0, w / 2 + 0.02, 2.82, zf, 2.0, p=0.18, style='board', strut=True)
        if lod == 0:
            row1(B, W, bays1)
            logs(W, 0.2, w / 2 - 0.2, zf + 0.02, rows=3, r=0.1)
            tm = tmp()
            put(tm, cached(('kemu',), lambda: NS['kemuri']()), rot=0.0)
            put(R, tm, off=(0.0, H, 0.0), rot=-math.pi * 0.5)
    B.finish()
    return B


def build_rsw047():
    """B_P_RSW_047 小さな妻入の家：縁側（高床の濡れ縁）＋ Kit の戸口。庇なし。入口＝x −1.23..0.41。"""
    B = Bld('B_P_RSW_047', 4.097, 10.92, 2.9, fin=3, tone=0)
    w, zf = B.w, B.zf
    bays1 = [('amado', 0.82), ('door', 1.64), ('koshib', w - 2.46)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        # 庇は付けない：巷が狭く、TPS カメラが戸口の前（壁の面・床上 2.2 m）に来て庇の下に入り、庇裏が視界の上半分を覆うため（R1 と同じ r5 機位で実測）
        if lod == 0:
            row1(B, W, bays1)
            engawa(W, 0.62, w / 2, zf, 0.42, 0.5)
        else:
            W.box((0.62, 0.36, zf), (w / 2, 0.42, zf + 0.5), 'V2_Wood', BOARD, grain=X)      # LOD1：縁側の床板だけ
    B.finish()
    return B


def build_rsw048():
    """B_P_RSW_048 厨子二階：寄棟＋瓦庇＋虫籠窓 4。入口＝x −1.8..0。"""
    B = Bld('B_P_RSW_048', 7.198, 10.92, 3.9, hk='h27', fin=0, tone=1)
    w, zf = B.w, B.zf
    bays1 = [('koshib', 1.8), ('door', 1.8), ('koshi', 1.8), ('koshi', w - 5.4)]
    bays2 = [('mushi', 1.8), ('mushib', 1.8), ('mushi', 1.8), ('mushib', w - 5.4)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        hip_on_body(B, lod, 3.9, 0.58, 0.45)
        eave_roof(R, lod, -w / 2 - 0.02, w / 2 + 0.02, 2.75, zf, 1.0, p=0.30, style='tile')
        if lod == 0:
            row1(B, W, bays1)
            row2(B, W, bays2, 2.7, 3.9)
    B.finish()
    return B


def build_rsw061():
    """B_P_RSW_061 広い平屋：低くて大きな寄棟（出 0.9）＋縁側＋障子 3。入口＝x 0.45..2.25。"""
    B = Bld('B_P_RSW_061', 8.101, 10.92, 2.9, fin=4, tone=1)
    w, zf = B.w, B.zf
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        hip_on_body(B, lod, 2.9, 0.40, 0.90)
        if lod == 0:
            row1(B, W, [('', 4.5), ('door', 1.8), ('koshir', w - 6.3)]) if False else None
            x = -w / 2
            for (xa, xb) in ((x, x + 1.5), (x + 1.5, x + 3.0), (x + 3.0, x + 4.5)):
                W.box((xa, FL, zf - 0.02), (xb, 0.95, zf + 0.0), 'V2_Wood', BOARD, grain=X)
                shoji_bay(W, xa, xb, 0.95, 2.45, zf)
            W.box((x, 2.45, zf - 0.05), (x + 4.5, 2.9, zf), 'V2_Plaster', PL, grain=X)
            put(W, FR('door', 1.8, B.hk), off=(0.45, 0.0, zf))
            put(W, FR('koshir', w / 2 - 2.25, B.hk), off=(2.25, 0.0, zf))
            engawa(W, -2.4, x + 4.2, zf, 0.5, 0.55)
    B.finish()
    return B


def build_rsw062():
    """B_P_RSW_062 細い厨子二階：妻入の急な屋根＋2F 出し梁（せり出し）。入口＝x −1.353..0.451。"""
    B = Bld('B_P_RSW_062', 4.509, 10.92, 3.9, hk='h27', fin=4, tone=0)
    w, zf = B.w, B.zf
    bays1 = [('koshib', 0.9), ('door', 1.804), ('plain', 0.9), ('plain', w - 3.604)]
    bays2 = [('mushi', 1.2), ('mushi', 1.804), ('mushib', w - 3.004)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        gable_on_body(B, lod, 3.9, 0.68, 0.10, 0.30, True)
        if lod == 0:
            row1(B, W, bays1)
            row2(B, W, bays2, 2.7, 3.9, dz=0.45)
            W.box((-w / 2 - 0.02, 2.58, zf - 0.02), (w / 2 + 0.02, 2.72, zf + 0.5), 'V2_Wood', DARK, grain=X)
            for xb in (-w / 2 + 0.3, 0.0, w / 2 - 0.3):
                W.beam((xb, 2.25, zf - 0.02), (xb, 2.6, zf + 0.44), 0.08, 0.1, 'V2_Wood', DARK)
        eave_roof(R, lod, -w / 2 - 0.02, w / 2 + 0.02, 3.85, zf + 0.45, 0.45, p=0.30, style='tile', brackets=False)
    B.finish()
    return B


BUILDERS = [build_mkt012, build_mkt013, build_mkt011, build_mkt010, build_mkt009, build_mkt008,
            build_rsw047, build_rsw048, build_rsw061, build_rsw062]


def main():
    K.clear_scene(bpy)
    for fn in BUILDERS:
        fn()
    bm = K.blender_mats(bpy, MATS)
    objs = []
    manifest = {}
    keep = [n for n in MODS if n.startswith('B_P_')]
    for name in keep:
        m = MODS[name]
        ob = m.to_blender(bpy, bmats=bm)
        objs.append(ob)
        tri = sum(len(p_.vertices) - 2 for p_ in ob.data.polygons)
        manifest[name] = {'tris': tri, 'note': INFO[name]}
    os.makedirs(OUT + '/src', exist_ok=True)
    K.export_glb(bpy, OUT + '/src/w9r2_arch.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_w9r2_arch.py 產生；Godot prefab（tools/p13/w9/w9r2_prefab.gd）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[W9R2] %d メッシュ、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/w9r2_arch.glb'))
    for k, v in manifest.items():
        print('[W9R2]  %s %d tri' % (k, v['tris']))


main()
