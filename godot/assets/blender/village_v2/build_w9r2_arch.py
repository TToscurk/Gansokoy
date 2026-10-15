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
POSTS = {}      # 建築 id → 庇柱・玄関柱 [{x, z, top, w}]（Godot 側が碰撞を作る・gate が読む）
EAVES = {}      # 建築 id → 庇の構造メタ（gate が読む）
ROOFS = {}      # 建築 id → 屋根の収め（棟・鬼瓦・軒先・懸魚）メタ
_CUR = [None]


def _rec(group, **kw):
    if _CUR[0]:
        {'eave': EAVES, 'post': POSTS}.get(group, ROOFS).setdefault(_CUR[0], []).append(kw)


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
    if lod == 0:
        # 軒先の垂木尻（前後の軒）
        ye_ = eave - p * ove
        nx = max(3, int(round(wall_len / 0.52)))
        for i in range(nx + 1):
            xx = -wall_len * 0.5 + wall_len * i / nx
            for sg in (1, -1):
                dst.box((xx - 0.035, ye_ - 0.33, sg * (half + ove - EAVE_TRIM + 0.02) - 0.07), (xx + 0.035, ye_ - 0.2, sg * (half + ove - EAVE_TRIM + 0.02) + 0.07),
                        'V2_Wood', DARK * 0.85, grain=Y)
        # 懸魚（妻面の合掌下の飾り板）：妻入の正面（と背面）
        if tsuma and gyo:
            for e in (-1.0, 1.0):
                put(dst, cached(('gyo',), lambda: NS['gegyo']()), off=(e * (L * 0.5 - VERGE_IN + 0.0), H - 0.02, 0.0), rot=e * math.pi * 0.5)
        _rec('roof', kind='gable', ridge_stack=True, oni=bool(oni), hip_caps=0, eave_tails=True, gegyo=bool(tsuma and gyo), ove=ove)
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
        if lod == 0:
            # 大棟：Kit の熨斗瓦＋冠瓦の段積み（rg_u）を棟長に伸ばし、棟端に鬼瓦
            Lr = 2.0 * xt + 0.5
            t = tmp()
            put(t, cached(('rg',), lambda: NS['ridge_unit']()), sx=(Lr - 2.0 * ONI_IN) / RU)
            put(dst, t, off=(-Lr * 0.5 + ONI_IN, y_r - 0.03, 0.0))
            for e in (-1.0, 1.0):
                put(dst, cached(('oni',), lambda: NS['oni']()), off=(e * (Lr * 0.5 - ONI_IN), y_r - 0.03, 0.0))
        else:
            I.hip_ridge(dst, (-xt, y_r, 0.0), (xt, y_r, 0.0), lod, w=0.30, h=0.22)
    elif ridge_box:
        dst.box((-0.2, y_r, -0.2), (0.2, y_r + 0.3, 0.2), 'V2_Kawara', 0.62)
    if lod == 0:
        # 隅棟の先端に巴瓦（丸い留め）
        for sx in (1, -1):
            for sz in (1, -1):
                end = (sx * ha, y_e, sz * hb)
                dn = norm(sub((sx * xt, y_r, 0.0), end))
                c0 = add(end, (0.0, 0.11, 0.0))
                dst.cyl(c0, add(c0, mul(dn, -0.07)), 0.12, 0.12, 12, 'V2_Kawara', 0.52, caps=(True, True))
        # 軒先の垂木尻（鼻隠しの下に並ぶ）：厚みと影を出す
        nx = max(3, int(round(2.0 * ha / 0.52)))
        for i in range(nx + 1):
            xx = -ha + 2.0 * ha * i / nx
            for sg in (1, -1):
                dst.box((xx - 0.035, y_e - 0.33, sg * (hb + 0.03) - 0.07), (xx + 0.035, y_e - 0.2, sg * (hb + 0.03) + 0.07), 'V2_Wood', DARK * 0.85, grain=Y)
        nz = max(3, int(round(2.0 * hb / 0.52)))
        for i in range(nz + 1):
            zz = -hb + 2.0 * hb * i / nz
            for sx in (1, -1):
                dst.box((sx * (ha + 0.03) - 0.07, y_e - 0.33, zz - 0.035), (sx * (ha + 0.03) + 0.07, y_e - 0.2, zz + 0.035), 'V2_Wood', DARK * 0.85, grain=Y)
        _rec('roof', kind='hip', ridge_stack=xt > 0.05, oni=xt > 0.05, hip_caps=4, eave_tails=True, gegyo=False, ove=ove)
    return y_r


# ───────────────────────── 庇・下屋・布・小構件 ─────────────────────────

def eave_roof(dst, lod, x0, x1, y, zf, depth, p=0.36, style='tile', brackets=True, strut=False, fascia_col=DARK, posts=(), tone=0.8, flash=False):
    """壁（z＝zf）に付く片流れの庇：壁際の屋面線 y から depth だけ前へ、勾配 p で下る。style='tile'（瓦）／'board'（杉皮板葺）。
    R2.1：板庇に『厚み』を持たせる（野地裏・垂木・鼻隠し・袖板）。壁際に胴差と雨押さえ、腕木は 1.15 m 以内の間隔、
    flash=True（収尾で 011／020／026 だけ）：雨押さえを鉛色（V2_Kawara）にして壁から屋面へ 12 cm 立ち上げ、接合線を見える形にする。他の棟は R2.1 のまま。
    深い庇（≥1.6 m）は庇柱（礎石付き）＋繋ぎ梁で受ける。排水＝壁側が高く通り側へ下がる（p>0）。"""
    L = x1 - x0
    s = depth - 0.04
    ye = y - s * p
    nb = max(2, int(math.ceil(L / 1.15)))
    if lod == 0:
        _rec('eave', x0=x0, x1=x1, y=y, zf=zf, depth=depth, p=p, style=style, brackets=(nb + 1) if brackets else 0,
             bracket_gap=(L / nb) if brackets else None, strut=bool(strut), posts=[float(q) for q in posts])
    if style == 'tile':
        roof_row(dst, lod, x0, L, s, p, (0.0, y, zf))
    else:
        th = 0.05
        a_, b_ = (x0, y, zf), (x1, y, zf)
        c_, d_ = (x1, ye, zf + s), (x0, ye, zf + s)
        dst.quad(d_, c_, b_, a_, 'V2_Wood', tone, grain=Z)                                   # 上面（杉皮板葺）
        if lod == 0:
            dn = lambda q: (q[0], q[1] - th, q[2])
            dst.quad(dn(a_), dn(b_), dn(c_), dn(d_), 'V2_Wood', DARK * 0.8, grain=Z)           # 野地裏（下向き）
            nbat = max(2, int(L / 0.42))
            for i in range(nbat + 1):                                                          # 押縁（棟から軒へ）
                xx = x0 + 0.04 + (L - 0.08) * i / nbat
                dst.beam((xx, y + 0.02, zf), (xx, ye + 0.02, zf + s), 0.03, 0.03, 'V2_Wood', DARK)
            nr = max(3, int(L / 0.5))
            for i in range(nr + 1):                                                            # 垂木
                xx = x0 + 0.06 + (L - 0.12) * i / nr
                dst.beam((xx, y - th - 0.05, zf + 0.02), (xx, ye - th - 0.05, zf + s - 0.04), 0.045, 0.075, 'V2_Wood', DARK)
            dst.box((x0, ye - 0.17, zf + s - 0.03), (x1, ye + 0.03, zf + s + 0.03), 'V2_Wood', DARK, grain=X)   # 鼻隠し
            for xe, o in ((x0, -1.0), (x1, 1.0)):                                              # 袖板（庇の側面を塞ぐ）
                pts = [(xe, y + 0.01, zf), (xe, ye + 0.01, zf + s), (xe, ye - th - 0.15, zf + s), (xe, y - th - 0.15, zf)]
                polyo(dst, pts, 'V2_Wood', DARK, out=(o, 0.0, 0.0), grain=Z)
                polyo(dst, [(xe - o * 0.02, q[1], q[2]) for q in pts], 'V2_Wood', DARK * 0.8, out=(-o, 0.0, 0.0), grain=Z)
    if lod:
        return
    # 出桁（先端の桁）
    dst.box((x0, ye - 0.30, zf + s - 0.1), (x1, ye - 0.14, zf + s + 0.02), 'V2_Wood', fascia_col, grain=X)
    # 壁際：雨押さえ（上）と胴差（下・壁の骨組みに庇を結ぶ）
    if flash:
        dst.box((x0, y - 0.05, zf - 0.04), (x1, y + 0.12, zf + 0.03), 'V2_Kawara', 0.66, grain=X)     # 雨押さえ（鉛色の水切り：壁から屋面へ 12 cm 立ち上げ・庇の全長）
    else:
        dst.box((x0, y - 0.05, zf - 0.04), (x1, y + 0.06, zf + 0.02), 'V2_Kawara' if style == 'tile' else 'V2_Wood', 0.75, grain=X)
    dst.box((x0, y - 0.36, zf - 0.02), (x1, y - 0.18, zf + 0.07), 'V2_Wood', DARK * 0.9, grain=X)
    if brackets:
        for i in range(nb + 1):
            xb = x0 + 0.15 + (L - 0.3) * i / nb
            dst.beam((xb, y - 0.20, zf - 0.02), (xb, ye - 0.22, zf + s - 0.08), 0.07, 0.10, 'V2_Wood', DARK)         # 腕木
            if strut:
                dst.beam((xb, y - 1.05, zf - 0.02), (xb, ye - 0.30, zf + s - 0.12), 0.06, 0.08, 'V2_Wood', DARK)   # 斜材
    for xp in posts:                                                                               # 庇柱（礎石＋繋ぎ梁）
        zp = zf + s - 0.04
        dst.box((xp - 0.07, 0.12, zp - 0.07), (xp + 0.07, ye - 0.30, zp + 0.07), 'V2_Wood', DARK, grain=Y)
        dst.box((xp - 0.12, 0.0, zp - 0.12), (xp + 0.12, 0.14, zp + 0.12), 'V2_KitStoneTri', 0.8)
        dst.beam((xp, ye - 0.33, zp), (xp, y - 0.30, zf + 0.02), 0.08, 0.12, 'V2_Wood', DARK)
        _rec('post', x=float(xp), z=float(zp), top=float(ye - 0.30), w=0.14)


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


def shitomi(dst, x0, x1, y_hinge, zf, rise=0.85, out=0.9, struts=True):
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
    for xx in (x0 + 0.12, x1 - 0.12):
        if struts:                                                          # 突っ支い棒（足元に物が立つ棟では使わない）
            dst.beam((xx, y_hinge - 1.15, zf + out * 0.95), (xx, y1 - 0.05, z1 - 0.02), 0.035, 0.035, 'V2_Wood', DARK)
        else:                                                               # 吊り金具：軒裏の釣り環から垂らす（足元は空ける）
            dst.beam((xx, y1, z1 - 0.03), (xx, y1 + 0.2, z1 - 0.1), 0.02, 0.02, 'V2_Wood', DARK * 0.55)


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

def hung_fish(dst, x0, x1, y, z, n=8):
    """干物の竿：竹棹に紐で吊る魚（尾を上に・頭が下・胴が膨らむ輪郭。二段、下端は y−0.51）。"""
    dst.beam((x0, y, z), (x1, y, z), 0.035, 0.035, 'V2_Wood', DARK)
    for i in range(n):
        xx = x0 + 0.15 + (x1 - x0 - 0.3) * i / max(1, n - 1)
        for k in range(2):
            yy = y - 0.04 - k * 0.25
            pts = [(xx - 0.03, yy, z), (xx + 0.03, yy, z), (xx + 0.05, yy - 0.08, z), (xx + 0.03, yy - 0.17, z), (xx, yy - 0.22, z),
                   (xx - 0.03, yy - 0.17, z), (xx - 0.05, yy - 0.08, z)]                       # 尾を上に吊った魚の輪郭（頭が下・胴が膨らむ。下端は y−0.51＝竿 2.36 で 1.85 m）
            polyo(dst, pts, 'V2_Plaster', 0.92 if (i + k) % 2 else 0.78, out=(0.0, 0.0, 1.0))
            polyo(dst, pts[::-1], 'V2_Plaster', 0.62, out=(0.0, 0.0, -1.0))
        dst.beam((xx, y, z), (xx, y - 0.04, z), 0.012, 0.012, 'V2_Wood', DARK)


def bamboo_rack(dst, x0, x1, y, z0, z1, n=6):
    """庇下に吊った竹材の干し架：吊り束 3 組と受け梁 2 本（z 方向）の上に、長い竹竿が横一列に載る。"""
    for xx in (x0 + 0.1, x1 - 0.1):
        dst.beam((xx, y - 0.05, z0), (xx, y - 0.05, z1), 0.05, 0.05, 'V2_Wood', DARK)
        for zz in (z0 + 0.02, z1 - 0.02):
            dst.beam((xx, y - 0.05, zz), (xx, y + 0.34, zz), 0.035, 0.035, 'V2_Wood', DARK)
    for i in range(n):
        zz = z0 + 0.08 + (z1 - z0 - 0.16) * i / max(1, n - 1)
        yy = y + 0.04 + (0.045 if i % 2 else 0.0)
        dst.cyl((x0, yy, zz), (x1, yy, zz), 0.042, 0.04, 8, 'V2_Wood', 0.98, caps=(True, True))


def shelf_wall(dst, x0, x1, zf, tiers=(0.62, 1.1, 1.58), depth=0.34):
    """壁に取り付く陳列棚（柱 2＋棚板 3 段）＋草履の並び（履物屋）。"""
    for xx in (x0, x1 - 0.06):
        dst.box((xx, 0.0, zf + 0.02), (xx + 0.06, tiers[-1] + 0.3, zf + depth), 'V2_Wood', DARK, grain=Y)
    for yy in tiers:
        dst.box((x0, yy - 0.04, zf + 0.02), (x1, yy, zf + depth), 'V2_Wood', BOARD, grain=X)
        dst.box((x0, yy, zf + depth - 0.03), (x1, yy + 0.06, zf + depth), 'V2_Wood', DARK, grain=X)
        n = max(3, int((x1 - x0) / 0.2))
        for i in range(n):
            xs = x0 + 0.1 + i * (x1 - x0 - 0.2) / max(1, n - 1)
            dst.box((xs - 0.07, yy, zf + 0.06), (xs + 0.07, yy + 0.04, zf + depth - 0.06), 'V2_Wood', 0.95 if i % 3 else 1.12, grain=Z)


def tsuchido(dst, x0, x1, zf, y1=2.25):
    """土戸（防火の厚い漆喰引戸）：閉じた一枚＋鉄の帯金＋抱き。"""
    dst.box((x0, FL, zf - 0.02), (x1, y1, zf + 0.12), 'V2_Plaster', 0.66, grain=Y)
    for yy in (0.75, 1.35, 1.9):
        dst.box((x0, yy, zf + 0.12), (x1, yy + 0.07, zf + 0.14), 'V2_Wood', DARK * 0.45, grain=X)
    dst.box((x0 - 0.05, FL, zf - 0.04), (x0 + 0.04, y1 + 0.05, zf + 0.15), 'V2_Plaster', PL * 0.9, grain=Y)
    dst.box((x1 - 0.04, FL, zf - 0.04), (x1 + 0.05, y1 + 0.05, zf + 0.15), 'V2_Plaster', PL * 0.9, grain=Y)


def koshi_turret(B, lod, H, scale=1.5, rot=math.pi * 0.5, x=0.0, z=0.0):
    """越屋根（煙出し・湯気抜き）：Kit の kemuri を拡大して棟上に載せる。"""
    if lod:
        return
    tm = tmp()
    put(tm, cached(('kemu',), lambda: NS['kemuri']()), sx=scale, sy=scale, sz=scale)
    put(B.R[lod], tm, off=(x, H - 0.1, z), rot=rot)
    _rec('roof', kind='turret', scale=scale)


def post(dst, x, z, top, w=0.15, col=None):
    """独立柱（礎石付き）：碰撞用の寸法を POSTS へ記録（Godot の bake が StaticBody3D を作る）。"""
    dst.box((x - w / 2, 0.12, z - w / 2), (x + w / 2, top, z + w / 2), 'V2_Wood', DARK if col is None else col, grain=Y)
    dst.box((x - 0.12, 0.0, z - 0.12), (x + 0.12, 0.14, z + 0.12), 'V2_KitStoneTri', 0.8)
    _rec('post', x=float(x), z=float(z), top=float(top), w=float(w))


def louver_window(dst, x0, x1, y0, y1, z, n=5):
    """無双窓（横板の換気窓）：枠＋暗い奥＋水平の板。壁（z）より 0.06 まで出る。"""
    dst.box((x0 - 0.05, y0 - 0.05, z - 0.04), (x1 + 0.05, y1 + 0.05, z + 0.03), 'V2_Wood', DARK, grain=X)
    dst.box((x0, y0, z - 0.06), (x1, y1, z - 0.01), 'V2_Wood', DARK * 0.3, grain=X)
    for i in range(n):
        yy = y0 + (y1 - y0) * (i + 0.5) / n
        dst.box((x0 + 0.02, yy - 0.022, z - 0.005), (x1 - 0.02, yy + 0.018, z + 0.06), 'V2_Wood', 0.95, grain=X)


def ridge_vent(B, lod, H, x0, x1, hh=0.55, hw_=0.36):
    """棟換気（越屋根の細長い版）：棟に載る横板の籠＋小さな切妻屋根。棟は x 方向。lod0 のみ。"""
    if lod:
        return
    R = B.R[0]
    y0 = H + 0.02
    R.box((x0, y0, -hw_), (x1, y0 + 0.10, hw_), 'V2_Wood', DARK, grain=X)
    n = max(2, int(round((x1 - x0) / 0.9)))
    for i in range(n + 1):
        xx = x0 + 0.06 + (x1 - x0 - 0.12) * i / n
        for sg in (-1.0, 1.0):
            R.box((xx - 0.04, y0 + 0.10, sg * (hw_ - 0.05) - 0.04), (xx + 0.04, y0 + hh, sg * (hw_ - 0.05) + 0.04), 'V2_Wood', DARK, grain=Y)
    for sg in (-1.0, 1.0):
        for k in range(4):
            yy = y0 + 0.17 + k * ((hh - 0.24) / 4.0)
            za, zb = (hw_ - 0.03, hw_ + 0.012) if sg > 0 else (-hw_ - 0.012, -hw_ + 0.03)
            R.box((x0 + 0.04, yy, za), (x1 - 0.04, yy + 0.05, zb), 'V2_Wood', 0.95, grain=X)
    yc = y0 + hh
    hwo = hw_ + 0.2
    xa, xb = x0 - 0.16, x1 + 0.16
    for sg in (-1.0, 1.0):
        polyo(R, [(xa, yc, sg * hwo), (xb, yc, sg * hwo), (xb, yc + 0.34, 0.0), (xa, yc + 0.34, 0.0)], 'V2_Kawara', 0.58, out=(0.0, 0.7, sg), grain=X)
        polyo(R, [(xa, yc - 0.05, sg * hwo), (xb, yc - 0.05, sg * hwo), (xb, yc, sg * hwo), (xa, yc, sg * hwo)], 'V2_Wood', DARK, out=(0.0, 0.0, sg), grain=X)
    for xe, o in ((xa, -1.0), (xb, 1.0)):
        polyo(R, [(xe, yc, -hwo), (xe, yc, hwo), (xe, yc + 0.34, 0.0)], 'V2_Plaster', PL, out=(o, 0.0, 0.0))
    R.box((xa - 0.02, yc + 0.31, -0.06), (xb + 0.02, yc + 0.39, 0.06), 'V2_Kawara', 0.5, grain=X)


def hung_sandals(dst, x0, x1, y, z, n=10):
    """草履・下駄の吊り列（竿に二つ一組）。下端は y−0.40 以上。"""
    dst.beam((x0, y, z), (x1, y, z), 0.04, 0.04, 'V2_Wood', DARK)
    for i in range(n):
        xx = x0 + 0.14 + (x1 - x0 - 0.28) * i / max(1, n - 1)
        for k, dx in enumerate((-0.06, 0.06)):
            h = 0.26 + 0.02 * ((i + k) % 3)
            dst.box((xx + dx - 0.04, y - 0.06 - h, z - 0.012), (xx + dx + 0.04, y - 0.06, z + 0.012), 'V2_Wood', 1.12 if i % 2 else 0.95, grain=Y)
            dst.beam((xx + dx, y, z), (xx + dx, y - 0.06, z), 0.012, 0.012, 'V2_Wood', DARK)


def chimney(R, x, z, y0, y1, s=0.5):
    """土の煙突（豆腐屋・鍛冶など火を使う作業場の目印）：漆喰の角筒＋煤けた口＋小さな瓦の笠。"""
    h = s / 2
    R.box((x - h, y0, z - h), (x + h, y1, z + h), 'V2_Plaster', PL * 0.82, grain=Y)
    R.box((x - h - 0.04, y1 - 0.34, z - h - 0.04), (x + h + 0.04, y1 - 0.20, z + h + 0.04), 'V2_Plaster', PL * 0.7, grain=X)
    R.box((x - h - 0.02, y1 - 0.20, z - h - 0.02), (x + h + 0.02, y1, z + h + 0.02), 'V2_Wood', DARK * 0.5, grain=Y)
    top = y1 + 0.24
    cx0, cx1, cz0, cz1 = x - h - 0.12, x + h + 0.12, z - h - 0.12, z + h + 0.12
    for pts, out in (([(cx0, y1, cz1), (cx1, y1, cz1), (x + 0.05, top, z + 0.05), (x - 0.05, top, z + 0.05)], (0.0, 0.6, 1.0)),
                     ([(cx1, y1, cz0), (cx0, y1, cz0), (x - 0.05, top, z - 0.05), (x + 0.05, top, z - 0.05)], (0.0, 0.6, -1.0)),
                     ([(cx1, y1, cz1), (cx1, y1, cz0), (x + 0.05, top, z - 0.05), (x + 0.05, top, z + 0.05)], (1.0, 0.6, 0.0)),
                     ([(cx0, y1, cz0), (cx0, y1, cz1), (x - 0.05, top, z + 0.05), (x - 0.05, top, z - 0.05)], (-1.0, 0.6, 0.0))):
        polyo(R, pts, 'V2_Kawara', 0.55, out=out, grain=X)



class Bld:
    def __init__(self, bid, w, d, eave, hk='h29', fin=0, tone=0):
        self.id = bid
        _CUR[0] = bid
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
        H = gable_roof(tm, lod, B.d, B.w / 2, y_wall, p, ove, ovg, tsuma=True, oni=oni, ridge_scale=ridge_scale)
        put(B.R[lod], tm, rot=-math.pi * 0.5)
    else:
        H = gable_roof(tm, lod, B.w, B.d / 2, y_wall, p, ove, ovg, tsuma=False, oni=oni, ridge_scale=ridge_scale)
        put(B.R[lod], tm)
    return H


def build_mkt012():
    """B_P_MKT_012 酒屋（大店）：寄棟＋棟上の越屋根（気抜き＝酒蔵の目印）＋海鼠壁の腰＋玄関の瓦庇（戸口〜右手）＋藍の日除け幕。
    左手は海鼠壁の袖（P10 の幟・提灯の竿が立つので庇を掛けない）。入口＝x 0（幅 1.733）。"""
    B = Bld('B_P_MKT_012', 5.197, 10.92, 5.4, fin=2, tone=0)
    w, zf = B.w, B.zf
    wl = w / 2 - 0.8665
    cx0, cx1 = -1.05, w / 2 - 0.02          # 玄関庇の範囲
    d_e = 1.35
    ye = 2.95 - (d_e - 0.04) * 0.30
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        if lod == 0:
            namako(W, -w / 2, -0.8665, FL, 1.25, zf, 0.24)
            W.quad((-w / 2, 1.25, zf), (-0.8665, 1.25, zf), (-0.8665, 2.62, zf), (-w / 2, 2.62, zf), 'V2_Plaster', PL, grain=Y)
            W.box((-w / 2 - 0.02, 2.58, zf - 0.02), (-0.8665, 2.72, zf + 0.1), 'V2_Plaster', PL * 0.92, grain=X)
            shoji_bay(W, -w / 2 + 0.5, -w / 2 + 1.5, 1.45, 2.3, zf + 0.06, frame=DARK)
            put(W, FR('shop_o', 1.733, B.hk), off=(-0.8665, 0.0, zf))
            put(W, FR('shop_k', w - wl - 1.733, B.hk), off=(0.8665, 0.0, zf))
            row2(B, W, [('winb', wl), ('winb', 1.733), ('winb', w - wl - 1.733)], 2.9, 5.4)
        H = hip_on_body(B, lod, 5.4, 0.55, 0.10)
        koshi_turret(B, lod, H, 1.5, math.pi * 0.5)
        eave_roof(R, lod, cx0, cx1, 2.95, zf, d_e, p=0.30, style='tile', strut=True)
        if lod == 0:
            cloth(W, cx0 + 0.2, cx1 - 0.2, ye - 0.14, 1.92, zf + d_e - 0.07, 'noren_a', seg_w=0.86, tilt=0.04)
            shitomi(W, 0.95, 2.2, 2.0, zf + 0.02, 0.4, 0.5, struts=False)
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
    """B_P_MKT_011 荒物屋：切妻平入（Kit の段違い屋根・小山牆は外す）＋両袖の袖卯建（隣の庇と切り離す）＋板庇 1.45 m（腕木＋斜材）＋吊るし売りの竿。
    入口＝x 0..1.75。"""
    B = Bld('B_P_MKT_011', 7.004, 10.01, 5.4, fin=3, tone=1)
    w, zf = B.w, B.zf
    bays1 = [('shop_c', 1.75), ('shop_c', 1.75), ('shop_o', 1.75), ('koshib', w - 5.25)]
    bays2 = [('amado', 1.75), ('amado', 1.75), ('wins', 1.75), ('amado', w - 5.25)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        gable_on_body(B, lod, 5.4, 0.42, 0.30, 0.12, False)
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.95, zf, 1.45, p=0.26, style='board', strut=True, posts=(-w / 2 + 0.25, 2.05), flash=True)   # 庇柱：戸口（x 0..1.75）の前は空け、左端と戸口の右で受ける（P10 の平台・桶山・桶を避ける位置）
        if lod == 0:
            row1(B, W, bays1)
            row2(B, W, bays2, 2.9, 5.4)
            for e in (-1.0, 1.0):
                put(W, cached(('ud110',), lambda: NS['udatsu'](1.1)), off=(e * (w / 2 - 0.13), 2.95, zf))
            hung_goods(W, -w / 2 + 0.3, -0.1, 2.46, zf + 0.85, n=5, seed=3)
            hung_goods(W, 0.3, w / 2 - 0.3, 2.40, zf + 1.15, n=7, seed=5)
            cloth(W, 0.1, 1.65, 2.25, 1.55, zf + 0.03, 'sudare_b', seg_w=0.78, billow=0.03, rod=True)
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
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.72, zf, 0.75, p=0.33, style='tile', brackets=False)
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
                W.rect_uv((xa, 1.55, zf + 0.015), (xb, 1.55, zf + 0.015), (xb, 2.15, zf + 0.015), (xa, 2.15, zf + 0.015), AM, RG['koshi_b'], 0.55)
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
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.95, zf, 1.1, p=0.30, style='tile', strut=False)
        if lod == 0:
            row1(B, W, bays1)
            row2(B, W, bays2, 2.9, 5.4, dz=-0.45)
            balcony(W, -0.2, w / 2 - 0.02, 2.95 + 0.0, zf - 0.45, depth=0.5, rail=0.85) if False else None
            sloped_cloth(W, -w / 2 + 0.1, w / 2 - 0.1, 2.55, zf + 1.05, 1.98, zf + 1.45, 'noren_e', seg_w=0.8, drop=0.12)
            bx(W, (1.15, FL, zf + 0.45), (2.3, 0.5, zf + 0.9), 0.9)
            bx(W, (-2.3, FL, zf + 0.45), (-1.85, 0.42, zf + 0.85), 0.9)
    B.finish()
    return B


def build_mkt008():
    """B_P_MKT_008 大工の家（平屋）：低い寄棟＋右半分は材木置き場の下屋（開放作業場・庇柱 2＋繋ぎ梁・礎石）＋積み丸太。入口＝x −1.75..0。"""
    B = Bld('B_P_MKT_008', 7.0, 10.92, 2.9, fin=3, tone=2)
    w, zf = B.w, B.zf
    bays1 = [('koshib', 1.75), ('door', 1.75), ('shop_o', 1.75), ('shop_o', 1.75)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        H = hip_on_body(B, lod, 2.9, 0.5, 0.15)
        eave_roof(R, lod, 0.35, w / 2 - 0.02, 2.82, zf, 1.7, p=0.2, style='board', strut=True, posts=(2.62, w / 2 - 0.14))
        if lod == 0:
            row1(B, W, bays1)
            logs(W, 2.35, w / 2 - 0.2, zf + 0.02, rows=3, r=0.1)
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
            engawa(W, 0.62, w / 2 - 0.25, zf, 0.42, 0.5)
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
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.75, zf, 1.0, p=0.30, style='tile')
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
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 3.85, zf + 0.45, 0.45, p=0.30, style='tile', brackets=False)
    B.finish()
    return B


def build_mkt025():
    """B_P_MKT_025 魚屋（R2.1 改）：隣（2 階建て・軒 5.4 m）より一段低い『平屋＋中二階』の吹き放ち店。
    店先は柱 4 本と太い差鴨居だけの全面開放（入口＝x −3.05..−1.31 は左端の間）、奥は石敷きの土間・石の生け簀・板台、
    差鴨居の前に干物の竿。中二階の壁帯に無双窓（換気）、棟には細長い棟換気。Kit の壁・屋根は全て隠し、側壁・背壁・屋根を自前で閉じる。
    店の輪郭が通りの屋並みの『谷』になる（棟 Kit −2.3 m）ことが主眼。"""
    B = Bld('B_P_MKT_025', 6.096, 10.92, 3.45, fin=0, tone=2)
    w, zf = B.w, B.zf
    YE = 3.45
    xs = [-w / 2 + 0.10, -1.305, 0.8715, w / 2 - 0.10]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        H = gable_on_body(B, lod, YE, 0.40, 0.85, 0.10, False)
        W.box((-w / 2, FL, -zf), (-w / 2 + 0.10, YE, zf), 'V2_Plaster', PL * 0.9, grain=Z)
        W.box((w / 2 - 0.10, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL * 0.9, grain=Z)
        W.box((-w / 2, FL, -zf), (w / 2, YE, -zf + 0.10), 'V2_Plaster', PL * 0.9, grain=X)
        if lod == 1:
            W.box((-w / 2, FL, zf - 0.05), (w / 2, 2.55, zf), 'V2_Wood', DARK * 0.45, grain=X)
            W.box((-w / 2, 2.55, zf - 0.05), (w / 2, YE, zf), 'V2_Plaster', PL, grain=X)
            continue
        zi = zf - 3.0
        W.box((-w / 2 + 0.10, FL, zi), (w / 2 - 0.10, FL + 0.04, zf), 'V2_KitStoneTri', 0.85)                  # 石敷きの土間
        W.box((-w / 2 + 0.10, FL, zi - 0.10), (w / 2 - 0.10, YE, zi), 'V2_Plaster', PL * 0.78, grain=X)        # 奥の壁（漆喰：暗い口にならず『開いた店』と読める）
        W.box((-w / 2 + 0.10, 2.50, zi), (w / 2 - 0.10, 2.56, zf), 'V2_Wood', BOARD * 0.8, grain=X)            # 天井
        W.box((-2.55, FL + 0.04, zi + 0.02), (1.55, FL + 0.66, zi + 0.78), 'V2_KitStoneTri', 0.8)               # 石の生け簀
        W.box((-2.43, FL + 0.60, zi + 0.12), (1.43, FL + 0.67, zi + 0.68), 'V2_Wood', DARK * 0.3, grain=X)     # 水面（暗）
        W.box((-0.4, FL + 0.74, zi + 1.3), (2.5, FL + 0.80, zi + 2.1), 'V2_Wood', BOARD, grain=X)              # 板台
        for xl in (-0.3, 2.4):
            for zl in (zi + 1.35, zi + 2.05):
                W.box((xl - 0.04, FL + 0.04, zl - 0.04), (xl + 0.04, FL + 0.74, zl + 0.04), 'V2_Wood', DARK, grain=Y)
        for xp in xs:                                                                                           # 吹き放ちの柱
            W.box((xp - 0.09, FL, zf - 0.09), (xp + 0.09, 2.52, zf + 0.09), 'V2_Wood', DARK, grain=Y)
        W.box((-w / 2, 2.50, zf - 0.12), (w / 2, 3.02, zf + 0.10), 'V2_Wood', DARK * 0.95, grain=X)            # 差鴨居
        W.box((-w / 2, 3.02, zf - 0.04), (w / 2, YE, zf + 0.03), 'V2_Plaster', PL, grain=X)                     # 中二階の壁帯
        for xc in (-2.1, -0.7, 0.7, 2.1):
            louver_window(W, xc - 0.38, xc + 0.38, 3.12, 3.36, zf + 0.03)
        for xa, xb in zip(xs[1:-1], xs[2:]):                                                                    # 貫（入口の間には渡さない）
            W.box((xa + 0.09, 0.95, zf - 0.04), (xb - 0.09, 1.02, zf + 0.03), 'V2_Wood', DARK * 0.9, grain=X)
        for xh in (-2.75, 2.75):
            W.beam((xh, 2.42, zf + 0.10), (xh, 2.42, zf + 0.52), 0.06, 0.08, 'V2_Wood', DARK)
        hung_fish(W, -2.85, 2.85, 2.36, zf + 0.52, n=11)
        ridge_vent(B, lod, H, -1.9, 1.9)
    B.finish()
    return B

def build_mkt027():
    """B_P_MKT_027 飯屋：2F の張り出し縁（客席＝手摺付き）＋棟上の大きな越屋根（竈の煙出し）＋戸口の両脇に据え付けの長床几＋半暖簾。
    入口＝x 0（幅 1.737）。Kit style mixed/c0/t2。"""
    B = Bld('B_P_MKT_027', 5.207, 10.01, 5.4, fin=0, tone=2)
    w, zf = B.w, B.zf
    wn = (w - 1.737) / 2
    bays1 = [('koshi', wn), ('shop_o', 1.737), ('shop_c', wn)]
    bays2 = [('win', wn), ('win', 1.737), ('win', wn)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        H = gable_on_body(B, lod, 5.4, 0.34, 0.35, 0.10, False)
        koshi_turret(B, lod, H, 2.1, 0.0)
        if lod == 0:
            row1(B, W, bays1)
            row2(B, W, bays2, 2.9, 5.4)
            balcony(W, -w / 2 + 0.05, w / 2 - 0.05, 2.95, zf, depth=0.8, rail=0.85)
            agari_en(W, -2.05, -0.98, zf, y=0.45, out=0.45)
            agari_en(W, 0.98, 2.05, zf, y=0.45, out=0.45)
            cloth(W, -0.8, 0.8, 2.3, 1.55, zf + 0.03, 'noren_c', seg_w=0.8, billow=0.03, rod=True)
    B.finish()
    return B


def build_mkt026():
    """B_P_MKT_026 履物屋（R2.1 改）：長い一様な瓦庇をやめ、玄関（x 0.88..2.64）の上に『出し破風の小屋根』（妻面を通りへ向ける切妻・
    懸魚付き・前の 2 本の庇柱と繋ぎ梁）を出して店の顔にする。その左右は短くした瓦庇、左 2 間は壁から 0.32 m 張り出す出格子の陳列窓。
    玄関の庇の下に草履・下駄の吊り列。2F の玄関上は塗り壁（庇の屋根が窓を隠すため）。Kit style bengara/c1/t0。"""
    B = Bld('B_P_MKT_026', 8.797, 10.92, 3.9, hk='h27', fin=1, tone=0)
    w, zf = B.w, B.zf
    cx, hw_ = 1.7615, 1.45
    bays1 = [('koshir', 1.76), ('koshir', 1.76), ('koshir', 1.76), ('shop_o', 1.76), ('koshir', w - 7.04)]
    bays2 = [('mushi', 1.76), ('mushib', 1.76), ('mushi', 1.76), ('plain', 1.76), ('mushi', w - 7.04)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        gable_on_body(B, lod, 3.9, 0.46, 0.45, 0.10, False)
        eave_roof(R, lod, -w / 2 + 0.02, cx - hw_ - 0.14, 2.75, zf, 1.1, p=0.30, style='tile', strut=False, flash=True)
        eave_roof(R, lod, cx + hw_ + 0.14, w / 2 - 0.02, 2.75, zf, 1.1, p=0.30, style='tile', strut=False, flash=True)
        tm = tmp()
        gable_roof(tm, lod, 1.30, hw_, 2.70, 0.50, 0.12, 0.10, tsuma=True)
        put(R, tm, off=(cx, 0.0, zf + 0.50), rot=-math.pi * 0.5)
        if lod == 0:
            row1(B, W, bays1)
            row2(B, W, bays2, 2.7, 3.9)
            deguchi(W, -2.45, -1.07, 0.62, 2.15, zf, out=0.32)
            deguchi(W, -0.69, 0.69, 0.62, 2.15, zf, out=0.32)
            for xq in (cx - 1.30, cx + 1.30):
                post(W, xq, zf + 1.05, 2.40, w=0.16)
            W.box((cx - 1.46, 2.40, zf + 0.98), (cx + 1.46, 2.60, zf + 1.12), 'V2_Wood', DARK, grain=X)       # 繋ぎ梁（庇柱の頭）
            hung_sandals(W, cx - 1.10, cx + 1.10, 2.30, zf + 0.72, n=9)
    B.finish()
    return B

def nurigome(dst, w, zf, y0, y1, openings, t=0.17, col=None):
    """塗籠（2F 全面を厚い漆喰で塗り込めた壁）：木の骨組みを覆う連続した壁面。窓は厚み t の深い抱き（開口の側面・上下が見える）。
    openings＝[(中心 x, 幅, 下端 y, 上端 y)]。壁面は帯状の箱で組み、開口の縁を壁の厚みとして見せる。"""
    col = PL * 0.98 if col is None else col
    x = -w / 2
    for (cx, ow, oy0, oy1) in sorted(openings):
        dst.box((x, y0, zf), (cx - ow / 2, y1, zf + t), 'V2_Plaster', col, grain=Y)
        dst.box((cx - ow / 2, y0, zf), (cx + ow / 2, oy0, zf + t), 'V2_Plaster', col, grain=X)
        dst.box((cx - ow / 2, oy1, zf), (cx + ow / 2, y1, zf + t), 'V2_Plaster', col, grain=X)
        x = cx + ow / 2
    dst.box((x, y0, zf), (w / 2, y1, zf + t), 'V2_Plaster', col, grain=Y)


def build_mkt024():
    """B_P_MKT_024 油屋（塗籠・低い屋根）：火を恐れる商いなので 2F 全面が白漆喰の塗籠、軒裏まで塗り込めた厚い鼻、1F は土戸（閉じた 2 枚と、開いた戸口）。
    緩勾配の屋根＋浅い瓦庇。入口＝x 0.44..2.20。Kit style open/c1/t1。"""
    B = Bld('B_P_MKT_024', 7.902, 10.92, 5.4, fin=1, tone=1)
    w, zf = B.w, B.zf
    bays1 = [('', 2.195), ('', 2.195), ('shop_o', 1.756), ('koshi', 1.756)]
    bays2 = [('mushib', 2.195), ('plain', 2.195), ('mushib', 1.756), ('plain', 1.756)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        gable_on_body(B, lod, 5.4, 0.30, 0.25, 0.10, False)
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.95, zf, 0.95, p=0.30, style='tile', strut=False)
        if lod == 0:
            x = -w / 2
            tsuchido(W, x + 0.1, x + 2.195 - 0.05, zf)
            tsuchido(W, x + 2.195 + 0.05, x + 4.39 - 0.1, zf)
            put(W, FR('shop_o', 1.756, B.hk), off=(0.439 + 0.0, 0.0, zf))
            put(W, FR('koshi', 1.756, B.hk), off=(2.195, 0.0, zf))
            row2(B, W, bays2, 2.9, 5.4)
            nurigome(W, w, zf, 2.98, 4.97, [(-2.853, 1.15, 3.45, 4.55), (1.317, 1.15, 3.45, 4.55)])   # 2F は全面塗籠（木の骨組みを塗り込める・窓は深い抱き）
            W.box((-w / 2 - 0.05, 4.95, zf - 0.02), (w / 2 + 0.05, 5.38, zf + 0.28), 'V2_Plaster', PL * 0.94, grain=X)       # 塗り込めた軒の鼻
            W.box((-w / 2 - 0.05, 2.86, zf - 0.02), (w / 2 + 0.05, 2.98, zf + 0.12), 'V2_Plaster', PL * 0.9, grain=X)       # 2F の腰の見切り
    B.finish()
    return B


def build_mkt006():
    """B_P_MKT_006 竹籠工房：三間とも戸を開け放した作業土間＋深めの板庇の下に竹材の干し架（長い竹竿の束）＋棟上の煙出し。入口＝x 0（幅 1.733）。
    Kit style open/c3/t0。"""
    B = Bld('B_P_MKT_006', 5.198, 10.01, 3.9, hk='h27', fin=3, tone=0)
    w, zf = B.w, B.zf
    wn = (w - 1.733) / 2
    bays1 = [('shop_o', wn), ('shop_o', 1.733), ('shop_o', wn)]
    bays2 = [('mushis', wn), ('mushis', 1.733), ('mushis', wn)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        H = gable_on_body(B, lod, 3.9, 0.38, 0.30, 0.10, False)
        koshi_turret(B, lod, H, 1.0, 0.0)
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.75, zf, 1.3, p=0.28, style='board', strut=True)
        if lod == 0:
            row1(B, W, bays1)
            row2(B, W, bays2, 2.7, 3.9)
            bamboo_rack(W, -w / 2 + 0.15, w / 2 - 0.15, 2.1, zf + 0.55, zf + 1.05)
    B.finish()
    return B


def build_mkt020():
    """B_P_MKT_020 豆腐屋（R2.1 改）：妻入の急勾配＋懸魚。板庇は 1.0→0.55 m に縮め、製作空間をはっきりさせる：
    右の作業側に『湯気窓』＋持ち出しの作業台＋窓下の石の水舟、屋根には土の煙突（竈）と大きな湯気抜きの越屋根。入口＝x −1.44..0.48。Kit style open/c4/t0。"""
    B = Bld('B_P_MKT_020', 4.806, 9.1, 3.9, hk='h27', fin=4, tone=0)
    w, zf = B.w, B.zf
    bays1 = [('koshib', 0.96), ('shop_o', 1.924), ('shop_k', w - 2.884)]
    bays2 = [('mushis', 0.96), ('mushis', 1.924), ('mushis', w - 2.884)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        H = gable_on_body(B, lod, 3.9, 0.62, 0.20, 0.30, True)
        koshi_turret(B, lod, H, 1.9, -math.pi * 0.5, z=0.3)
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.75, zf, 0.55, p=0.30, style='board', flash=True)
        if lod == 0:
            row1(B, W, bays1)
            row2(B, W, bays2, 2.7, 3.9)
            xk0, xk1 = 0.55, w / 2 - 0.12
            W.rect_uv((xk0, 1.65, zf + 0.015), (xk1, 1.65, zf + 0.015), (xk1, 2.45, zf + 0.015), (xk0, 2.45, zf + 0.015), AM, RG['koshi_b'], 0.9)
            W.box((xk0 - 0.04, 2.45, zf - 0.02), (xk1 + 0.04, 2.55, zf + 0.06), 'V2_Wood', DARK, grain=X)
            W.box((xk0 - 0.06, 1.04, zf - 0.02), (xk1 + 0.06, 1.12, zf + 0.24), 'V2_Wood', BOARD, grain=X)    # 作業台の持ち出し板
            for xb in (xk0 + 0.1, (xk0 + xk1) / 2, xk1 - 0.1):
                W.beam((xb, 1.04, zf + 0.22), (xb, 0.80, zf + 0.0), 0.05, 0.07, 'V2_Wood', DARK)
            W.box((xk0, FL, zf), (xk1 - 0.1, FL + 0.50, zf + 0.26), 'V2_KitStoneTri', 0.8)                 # 石の水舟（P10 の桶山が z+0.29 から立つので 0.26 まで）
            W.box((xk0 + 0.08, FL + 0.44, zf + 0.06), (xk1 - 0.18, FL + 0.51, zf + 0.21), 'V2_Wood', DARK * 0.3, grain=X)
            xc_, zc_ = 1.15, zf - 1.6
            yr = H - 0.62 * abs(xc_)
            R.box((xc_ - 0.38, yr - 0.12, zc_ - 0.38), (xc_ + 0.38, yr + 0.20, zc_ + 0.38), 'V2_Kawara', 0.6)  # 屋根との取り合い（鉛色の水切り）
            chimney(R, xc_, zc_, yr - 0.3, H + 1.40, s=0.62)                                                # 竈の煙突（棟より 1.4 m 上・遠くからも見える太さ）
    B.finish()
    return B

BUILDERS = [build_mkt012, build_mkt013, build_mkt011, build_mkt010, build_mkt009, build_mkt008,
            build_rsw047, build_rsw048, build_rsw061, build_rsw062,
            build_mkt025, build_mkt027, build_mkt026, build_mkt024, build_mkt006, build_mkt020]


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
        'materials': MATS, 'modules': manifest, 'total_tris': total, 'eaves': EAVES, 'roofs': ROOFS, 'posts': POSTS})
    print('[W9R2] %d メッシュ、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/w9r2_arch.glb'))
    for k, v in manifest.items():
        print('[W9R2]  %s %d tri' % (k, v['tris']))


main()
