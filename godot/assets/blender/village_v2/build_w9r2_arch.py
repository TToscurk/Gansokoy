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
        self.P = [tmp('p0'), tmp('p1')]      # 小物（無着色：藁・炭・鉄の色が FIN／TONE に左右されない。Phase 2 r2）

    def finish(self):
        FIN, TONE = NS['FIN'], NS['TONE']
        for lod, dst in ((0, self.m0), (1, self.m1)):
            if self.fin:
                tint(self.W[lod], {'V2_Plaster': FIN[self.fin][0], 'V2_Wood': FIN[self.fin][1]})
            if self.tone:
                tint(self.R[lod], {'V2_Kawara': TONE[self.tone]})
            put(dst, self.W[lod])
            put(dst, self.R[lod])
            if self.P[lod].f:
                put(dst, self.P[lod])


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

# ═══════════════════════ Phase 2：新しい建築タイプ 3 棟（板葺き簡陋民宅／土蔵の商家／作業場付きの工匠宅）═══════════════════════
# 町家 Kit は『瓦屋根・木構架・土壁』の一語彙。ここでは屋根材・量体・壁の構造・開口・附属空間そのものを変えた 3 型を 1 棟ずつ見本にする。
# 材質は町で使用中の V2_Wood／V2_Plaster／V2_Kawara／V2_KitStoneTri／Kit の atlas だけ（新しい資源なし）。

def _lerp3(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def board_plane(dst, lod, ra, rb, ea, eb, col=0.78):
    """板葺（石置き）屋面の 1 枚：高い辺 ra→rb（x 方向）から低い辺 ea→eb へ下る。板の重なり（段）・押さえ竹（棟→軒）・石を載せる。
    戻り値＝(押さえ竹の本数, 石の数)。"""
    n = _newell([ra, rb, eb, ea])
    if n[1] < 0:
        n = mul(n, -1.0)
    polyo(dst, [ra, rb, eb, ea], 'V2_Wood', col, out=n, grain=X)
    if lod:
        return 0, 0
    dn = lambda q: add(q, mul(n, -0.05))
    polyo(dst, [dn(ra), dn(rb), dn(eb), dn(ea)], 'V2_Wood', DARK * 0.7, out=mul(n, -1.0), grain=X)
    S = math.sqrt(sum((ea[k] - ra[k]) ** 2 for k in range(3)))
    nc = max(2, int(S / 0.30))
    for i in range(1, nc):                                              # 板の重なり（段）
        f = i / nc
        dst.beam(add(_lerp3(ra, ea, f), mul(n, 0.012)), add(_lerp3(rb, eb, f), mul(n, 0.012)), 0.035, 0.022, 'V2_Wood', DARK * 0.78, up=n)
    Lx = math.sqrt(sum((rb[k] - ra[k]) ** 2 for k in range(3)))
    xd = norm(sub(rb, ra))
    npl = max(2, int(round(Lx / 0.85)))
    stones = 0
    for i in range(npl):                                                # 押さえ竹（棟→軒）＋石
        t = (i + 0.5) / npl
        top, bot = _lerp3(ra, rb, t), _lerp3(ea, eb, t)
        dst.beam(add(top, mul(n, 0.03)), add(bot, mul(n, 0.03)), 0.05, 0.05, 'V2_Wood', DARK * 0.82, up=n)
        for j, fr in enumerate((0.30, 0.58, 0.85)):
            c = add(_lerp3(top, bot, fr), mul(n, 0.085))
            cl = 0.76 + 0.18 * (((i * 7 + j * 3) % 5) / 4.0)
            dst.beam(add(c, mul(xd, -0.13)), add(c, mul(xd, 0.13)), 0.19 + 0.02 * ((i + j) % 3), 0.11, 'V2_KitStoneTri', cl, up=n)
            stones += 1
    return npl, stones


def board_roof(dst, lod, wall_len, half, eave, p, ove, ovg, patch=None):
    """板葺き（石置き）の切妻：棟は x 方向（gable_roof と同じ局部枠）。棟覆い・棟の石・破風板・鼻隠し付き。返り値＝棟高。"""
    H = eave + p * half
    L = wall_len + 2.0 * ovg
    ye = eave - p * ove
    Zs = half + ove
    nbat = nst = 0
    for sg in (1.0, -1.0):
        a, b = board_plane(dst, lod, (-L / 2, H, 0.0), (L / 2, H, 0.0), (-L / 2, ye, sg * Zs), (L / 2, ye, sg * Zs))
        nbat += a
        nst += b
        if lod == 0:
            n = norm((0.0, 1.0, sg * p))
            for e in (-1.0, 1.0):                                       # 破風板
                dst.beam((e * L / 2, H, 0.0), (e * L / 2, ye, sg * Zs), 0.05, 0.16, 'V2_Wood', DARK * 0.85, up=n)
            dst.beam((-L / 2, ye - 0.04, sg * Zs), (L / 2, ye - 0.04, sg * Zs), 0.05, 0.13, 'V2_Wood', DARK * 0.85)    # 鼻隠し
    if patch and lod == 0:                                              # 屋根の補修：新しい（明るい）板を一部だけ張り替えた跡
        sg_, xa_, xb_, ta_, tb_ = patch
        pt = lambda x_, t_: (x_, H + (ye - H) * t_, sg_ * Zs * t_)
        qa, qb, qc, qd = pt(xa_, ta_), pt(xb_, ta_), pt(xb_, tb_), pt(xa_, tb_)
        nn = _newell([qa, qb, qc, qd])
        nn = mul(nn, -1.0) if nn[1] < 0 else nn
        up_ = lambda q_: add(q_, mul(nn, 0.016))
        polyo(dst, [up_(qa), up_(qb), up_(qc), up_(qd)], 'V2_Wood', 1.0, out=nn, grain=X)
        nj = max(2, int((tb_ - ta_) * Zs / 0.30))
        for i in range(1, nj):                                          # 新しい板の段
            f_ = ta_ + (tb_ - ta_) * i / nj
            dst.beam(add(pt(xa_, f_), mul(nn, 0.02)), add(pt(xb_, f_), mul(nn, 0.02)), 0.03, 0.02, 'V2_Wood', 0.62, up=nn)
    if lod == 0:
        dst.box((-L / 2 - 0.04, H - 0.03, -0.16), (L / 2 + 0.04, H + 0.07, 0.16), 'V2_Wood', DARK * 0.9, grain=X)      # 棟覆い
        k = max(2, int(round(L / 1.1)))
        for i in range(k):
            xc = -L / 2 + L * (i + 0.5) / k
            dst.box((xc - 0.14, H + 0.07, -0.10), (xc + 0.14, H + 0.19, 0.10), 'V2_KitStoneTri', 0.8 + 0.1 * (i % 3) / 2.0)   # 棟の石
            nst += 1
        _rec('roof', kind='board', gable=True, ridge_cover=True, barge=True, battens=nbat, stones=nst, ove=ove)
    else:
        dst.box((-L / 2, H - 0.02, -0.14), (L / 2, H + 0.10, 0.14), 'V2_Wood', DARK * 0.9, grain=X)
    return H


def board_shed(dst, lod, x0, x1, z_hi, y_hi, z_lo, y_lo):
    """板葺きの片流れ（下屋）：z_hi の壁際（y_hi）から z_lo の軒（y_lo）へ下る。"""
    a, b = board_plane(dst, lod, (x0, y_hi, z_hi), (x1, y_hi, z_hi), (x0, y_lo, z_lo), (x1, y_lo, z_lo), col=0.72)
    if lod == 0:
        n = _newell([(x0, y_hi, z_hi), (x1, y_hi, z_hi), (x1, y_lo, z_lo), (x0, y_lo, z_lo)])
        n = mul(n, -1.0) if n[1] < 0 else n
        dst.beam((x0, y_lo - 0.04, z_lo), (x1, y_lo - 0.04, z_lo), 0.05, 0.13, 'V2_Wood', DARK * 0.85)               # 鼻隠し
        for xe in (x0, x1):                                                                                           # 破風板
            dst.beam((xe, y_hi, z_hi), (xe, y_lo, z_lo), 0.05, 0.15, 'V2_Wood', DARK * 0.85, up=n)
        _rec('roof', kind='board', gable=False, ridge_cover=False, barge=True, battens=a, stones=b, ove=0.3)


def namako_side(dst, z0, z1, y0, y1, x, sgn, cell=0.24, tcol=0.42):
    """海鼠壁（側面版）：x＝壁面、sgn＝外向き（+1／−1）。白漆喰の盛り上がった目地に暗い平瓦。"""
    j = 0.03
    out = (float(sgn), 0.0, 0.0)
    polyo(dst, [(x, y0, z0), (x, y0, z1), (x, y1, z1), (x, y1, z0)], 'V2_Plaster', PL, out=out, grain=Y)
    nz = max(2, int(round((z1 - z0) / cell)))
    ny = max(2, int(round((y1 - y0) / cell)))
    cw, ch = (z1 - z0) / nz, (y1 - y0) / ny
    xo = x + sgn * 0.012
    for iy in range(ny):
        for iz in range(nz):
            a, b = z0 + iz * cw + j, z0 + (iz + 1) * cw - j
            c, d = y0 + iy * ch + j, y0 + (iy + 1) * ch - j
            polyo(dst, [(xo, c, a), (xo, c, b), (xo, d, b), (xo, d, a)], 'V2_Kawara', tcol, out=out, grain=Y)
    xa, xb = (x, x + sgn * 0.02) if sgn > 0 else (x + sgn * 0.02, x)
    for iy in range(ny + 1):
        yy = y0 + iy * ch
        dst.box((xa, yy - j * 0.8, z0), (xb, yy + j * 0.8, z1), 'V2_Plaster', PL, grain=Z)
    for iz in range(nz + 1):
        zz = z0 + iz * cw
        dst.box((xa, y0, zz - j * 0.8), (xb, y1, zz + j * 0.8), 'V2_Plaster', PL, grain=Y)


def kura_window_side(dst, x, sgn, zc, y0, y1, ww=0.62):
    """土蔵の窓（側面）：壁より出る厚い漆喰の抱き（枠）＋暗い奥＋漆喰の観音扉（片方を開いた形）。"""
    xa, xb = (x, x + sgn * 0.11) if sgn > 0 else (x + sgn * 0.11, x)
    z0, z1 = zc - ww / 2, zc + ww / 2
    out = (float(sgn), 0.0, 0.0)
    xo = x + sgn * 0.004
    polyo(dst, [(xo, y0, z0), (xo, y0, z1), (xo, y1, z1), (xo, y1, z0)], 'V2_Wood', 0.12, out=out, grain=Y)           # 暗い奥
    t = 0.11
    dst.box((xa, y0 - t, z0 - t), (xb, y1 + t, z0), 'V2_Plaster', PL * 0.96, grain=Y)                                  # 抱き（左右・上下）
    dst.box((xa, y0 - t, z1), (xb, y1 + t, z1 + t), 'V2_Plaster', PL * 0.96, grain=Y)
    dst.box((xa, y1, z0), (xb, y1 + t, z1), 'V2_Plaster', PL * 0.96, grain=X)
    dst.box((xa, y0 - t, z0), (xb, y0, z1), 'V2_Plaster', PL * 0.96, grain=X)
    xs0, xs1 = (x + sgn * 0.11, x + sgn * 0.45)                                                                        # 開いた観音扉（壁に直角）
    dst.box((min(xs0, xs1), y0 - 0.03, z1 + t - 0.01), (max(xs0, xs1), y1 + 0.03, z1 + t + 0.05), 'V2_Plaster', PL * 0.9, grain=Y)


# ═══════════ Phase 2 r2：生活痕跡・倉儲／交易／搬運・作業区の小物（無着色の P メッシュへ）═══════════
# 規則：地面に置く物は壁から 0.45 m 以内（プレイヤーの碰撞カプセル r 0.45 が入れない帯＝碰撞を足さずに済む）。壁際の高さ 1.1–1.8 m の吊り物は壁から 0.7 m 以内（gate の HUG 帯）。
# 戸口の幅の前（z 0.25–1.6）は空ける。足元は y −0.04..−0.06 まで埋めて、地面が少し低くても浮かない。
STRAW = (0.80, 0.66, 0.36)


def solid(x, z, w, top):
    """見た目のある小物（薪・桶・荷受け台・切り株）の碰撞：庇柱（POSTS）と同じ記録＝Godot の bake が Posts の BoxShape3D を作る。
    プレイヤーの自動跨ぎ（step_height）で踏み上がれない高さ（top ≥ 0.9）にする。w は箱の一辺（碰撞は w＋0.06）。"""
    _rec('post', x=float(x), z=float(z), top=float(top), w=float(w))


def woodpile(dst, x0, x1, z, rows=6, r=0.075, ln=0.33, y0=-0.04):
    """壁際の薪積み：丸太の小口（円）を手前（+z）へ向け、段ごとに半個ずらして積む。長さ ln が壁から出る（出入りは決定的にばらつかせる）。"""
    n0 = max(3, int((x1 - x0) / (2 * r * 1.02)))
    for ri in range(rows):
        n = n0 - (ri % 2)
        xs = x0 + r + (ri % 2) * r
        for i in range(n):
            xc = xs + i * 2 * r * 1.02
            yc = y0 + r + ri * r * 1.82
            jit = 0.02 * (((i * 5 + ri * 3) % 4) - 1.5) / 1.5
            dst.cyl((xc, yc, z + 0.01), (xc, yc, z + ln + jit), r, r * 0.96, 8, 'V2_Wood', 0.82 + 0.16 * (((i * 3 + ri * 7) % 5) / 4.0), caps=(True, True))


def rice_bale(dst, xc, yc, zc, ln=0.62, r=0.17):
    """米俵：藁色の樽形（中央が膨らむ・軸 x）＋縄の帯 3 本。"""
    dst.cyl((xc - ln / 2, yc, zc), (xc, yc, zc), r * 0.80, r, 10, 'V2_Plaster', STRAW, caps=(True, False))
    dst.cyl((xc, yc, zc), (xc + ln / 2, yc, zc), r, r * 0.80, 10, 'V2_Plaster', STRAW, caps=(False, True))
    for dx in (-0.2, 0.0, 0.2):
        rr = r * (1.0 - 0.2 * abs(dx) / 0.31) + 0.006
        dst.cyl((xc + dx - 0.018, yc, zc), (xc + dx + 0.018, yc, zc), rr, rr, 10, 'V2_Wood', DARK * 0.8, caps=(False, False))


def crate(dst, x0, x1, z0, z1, y0, y1, col=0.80):
    """木箱：板の目地（暗い帯 3）と角の縦桟。"""
    dst.box((x0, y0, z0), (x1, y1, z1), 'V2_Wood', col, grain=X)
    for yy in (y0 + 0.05, (y0 + y1) / 2 - 0.012, y1 - 0.08):
        dst.box((x0 - 0.008, yy, z0 - 0.008), (x1 + 0.008, yy + 0.025, z1 + 0.008), 'V2_Wood', DARK * 0.8, grain=X)
    for xx in (x0, x1 - 0.04):
        dst.box((xx - 0.006, y0, z0 - 0.012), (xx + 0.046, y1, z1 + 0.012), 'V2_Wood', DARK * 0.9, grain=Y)


def barrels(dst, x0, zc, y0, rows=(1,), r=0.19, h=0.50, col=0.6):
    """樽（箍 2）の三角積み。x0＝左端、y0＝置く面の高さ。"""
    y = y0
    for ri, n in enumerate(rows):
        for i in range(n):
            xc = x0 + r + i * 2 * r * 1.02 + ri * r
            dst.cyl((xc, y, zc), (xc, y + h, zc), r * 0.94, r, 12, 'V2_Wood', col, caps=(True, True))
            for yy in (y + 0.1, y + h - 0.13):
                dst.cyl((xc, yy, zc), (xc, yy + 0.03, zc), r + 0.012, r + 0.012, 12, 'V2_Wood', DARK * 0.6, caps=(False, False))
        y += h * 0.92


def tub(dst, x, z, r, h, y0=-0.04, col=0.62, water=True):
    """桶・天水桶（口が広い・箍 2・水面）。"""
    dst.cyl((x, y0, z), (x, y0 + h, z), r * 0.86, r, 12, 'V2_Wood', col, caps=(True, True))
    for yy in (y0 + 0.08, y0 + h - 0.11):
        dst.cyl((x, yy, z), (x, yy + 0.028, z), r * 0.93 + 0.012, r * 0.93 + 0.012, 12, 'V2_Wood', DARK * 0.55, caps=(False, False))
    if water:
        dst.cyl((x, y0 + h - 0.07, z), (x, y0 + h - 0.065, z), r * 0.92, r * 0.92, 12, 'V2_Wood', 0.07, caps=(True, False))


def jar(dst, x, z, r, h, y0=-0.04):
    """甕（腹が膨らみ口が窄まる）。"""
    dst.cyl((x, y0, z), (x, y0 + h * 0.5, z), r * 0.62, r, 12, 'V2_KitStoneTri', 0.42, caps=(True, False))
    dst.cyl((x, y0 + h * 0.5, z), (x, y0 + h * 0.92, z), r, r * 0.56, 12, 'V2_KitStoneTri', 0.42, caps=(False, False))
    dst.cyl((x, y0 + h * 0.92, z), (x, y0 + h, z), r * 0.66, r * 0.66, 12, 'V2_KitStoneTri', 0.3, caps=(True, True))


def mino(dst, x, ytop, z, w=0.50, h=0.68):
    """蓑（藁の雨具）：上が細く裾が広がる台形に、藁の段を 6 枚重ねて壁に掛ける。z＝壁面。"""
    n = 6
    for i in range(n):
        f0, f1 = i / n, (i + 1) / n
        y1, y0 = ytop - h * f0, ytop - h * f1
        hw = 0.12 + (w / 2 - 0.12) * f1
        c = 0.9 + 0.1 * (i % 2)
        dst.box((x - hw, y0, z + 0.005), (x + hw, y1 + 0.02, z + 0.035 + 0.01 * (i % 2)), 'V2_Plaster', tuple(q * c for q in (0.74, 0.60, 0.33)), grain=Y)
    dst.box((x - 0.05, ytop, z), (x + 0.05, ytop + 0.05, z + 0.03), 'V2_Wood', DARK, grain=Y)       # 掛け釘の板


def kasa(dst, x, y, z, r=0.2):
    """笠（円錐）：壁に頂を手前へ向けて掛ける。"""
    dst.cyl((x, y, z + 0.015), (x, y, z + 0.11), r, 0.03, 10, 'V2_Plaster', (0.78, 0.64, 0.38), caps=(True, False))


def hung_dried(dst, x0, x1, y, z, n=6, seed=0):
    """干し物の竿：竹竿から干し大根（細長い白）・干し柿の連（橙）・藁束が垂れる。下端は y−0.52。壁から 0.15 m 以内に収める。"""
    dst.beam((x0, y, z), (x1, y, z), 0.03, 0.03, 'V2_Wood', DARK)
    for i in range(n):
        xx = x0 + 0.12 + (x1 - x0 - 0.24) * i / max(1, n - 1)
        k = (i + seed) % 3
        if k == 0:
            for dx in (-0.045, 0.0, 0.045):
                dst.cyl((xx + dx, y - 0.03, z), (xx + dx, y - 0.50, z), 0.026, 0.012, 6, 'V2_Plaster', (0.88, 0.82, 0.64), caps=(False, True))
        elif k == 1:
            dst.beam((xx, y, z), (xx, y - 0.46, z), 0.01, 0.01, 'V2_Wood', DARK)
            for q in range(4):
                yy = y - 0.10 - q * 0.10
                dst.cyl((xx, yy, z), (xx, yy - 0.085, z), 0.048, 0.04, 8, 'V2_Plaster', (0.80, 0.40, 0.14), caps=(True, True))
        else:
            dst.cyl((xx, y - 0.02, z), (xx, y - 0.48, z), 0.012, 0.075, 8, 'V2_Plaster', (0.70, 0.58, 0.32), caps=(False, True))


def ladder(dst, xw, sx, zc, ytop, lean=0.55, wd=0.42, rungs=7):
    """竹の梯子：外壁面 xw に sx 向きへ立て掛ける（足元は壁から lean、上端は壁）。"""
    for dz in (-wd / 2, wd / 2):
        dst.beam((xw + sx * lean, -0.03, zc + dz), (xw + sx * 0.02, ytop, zc + dz), 0.045, 0.045, 'V2_Wood', 0.9)
    for i in range(rungs):
        f = (i + 0.7) / (rungs + 0.4)
        xx = xw + sx * (lean * (1 - f) + 0.02 * f)
        yy = -0.03 + (ytop + 0.03) * f
        dst.beam((xx, yy, zc - wd / 2), (xx, yy, zc + wd / 2), 0.03, 0.03, 'V2_Wood', 0.8)


def board_vent(R, zc, H, ln=0.9, hw=0.30):
    """板葺き棟の煙出し（囲炉裏の煙の抜け）：細長い板囲い（前後は横板の隙間）＋小さな板葺き切妻。棟は z 方向。lod0 のみ。"""
    y0 = H - 0.14
    h = 0.50
    za, zb = zc - ln / 2, zc + ln / 2
    for sx in (-1.0, 1.0):
        xa, xb = (sx * (hw - 0.04), sx * hw) if sx > 0 else (sx * hw, sx * (hw - 0.04))
        R.box((xa, y0, za), (xb, y0 + h, zb), 'V2_Wood', DARK * 0.9, grain=Y)
    for sz in (-1.0, 1.0):
        z0_, z1_ = (zb - 0.04, zb) if sz > 0 else (za, za + 0.04)
        R.box((-hw, y0, z0_), (hw, y0 + h, z1_), 'V2_Wood', 0.08, grain=X)
        zs0, zs1 = (zb - 0.01, zb + 0.035) if sz > 0 else (za - 0.035, za + 0.01)
        for k in range(4):
            yy = y0 + 0.16 + k * 0.085
            R.box((-hw + 0.02, yy, zs0), (hw - 0.02, yy + 0.05, zs1), 'V2_Wood', 0.92, grain=X)
    yc = y0 + h
    hwo, zr0, zr1, top = hw + 0.12, za - 0.12, zb + 0.12, yc + 0.24
    for sx in (-1.0, 1.0):
        polyo(R, [(sx * hwo, yc - 0.03, zr0), (sx * hwo, yc - 0.03, zr1), (0.0, top, zr1), (0.0, top, zr0)], 'V2_Wood', 0.74, out=(sx * 0.6, 0.8, 0.0), grain=Z)
    for sz, zz in ((1.0, zr1), (-1.0, zr0)):
        polyo(R, [(-hwo, yc - 0.03, zz), (hwo, yc - 0.03, zz), (0.0, top, zz)], 'V2_Wood', DARK, out=(0.0, 0.0, sz))
    R.box((-0.05, top - 0.02, zr0), (0.05, top + 0.04, zr1), 'V2_Wood', DARK * 0.9, grain=Z)


def kamachi(dst, x0, x1, zf, h=0.46, depth=0.46):
    """店先の荷受け台（上がり框）：床板＋縁框＋前脚（背面は壁）。"""
    dst.box((x0, h - 0.06, zf + 0.01), (x1, h, zf + depth), 'V2_Wood', 0.82, grain=X)
    dst.box((x0, h - 0.17, zf + depth - 0.05), (x1, h - 0.06, zf + depth), 'V2_Wood', DARK, grain=X)
    n = max(2, int((x1 - x0) / 0.9))
    for i in range(n + 1):
        xx = x0 + 0.04 + (x1 - x0 - 0.12) * i / n
        dst.box((xx, -0.06, zf + depth - 0.12), (xx + 0.08, h - 0.17, zf + depth - 0.04), 'V2_Wood', DARK, grain=Y)


def stump_anvil(dst, x, z):
    """鍛冶の簷下作業区：鉄床の切り株＋鉄床（胴・面・角）＋載せた槌。"""
    dst.cyl((x, -0.05, z), (x, 0.44, z), 0.21, 0.18, 10, 'V2_Wood', 0.5, caps=(True, True))
    dst.box((x - 0.19, 0.44, z - 0.075), (x + 0.15, 0.60, z + 0.075), 'V2_KitStoneTri', 0.26)
    dst.box((x - 0.22, 0.60, z - 0.09), (x + 0.14, 0.67, z + 0.09), 'V2_KitStoneTri', 0.22)
    dst.cyl((x + 0.14, 0.635, z), (x + 0.36, 0.635, z), 0.045, 0.012, 8, 'V2_KitStoneTri', 0.22, caps=(False, True))
    dst.beam((x - 0.16, 0.69, z + 0.02), (x - 0.02, 0.69, z + 0.13), 0.03, 0.03, 'V2_Wood', DARK)
    dst.box((x - 0.05, 0.67, z + 0.11), (x + 0.03, 0.75, z + 0.19), 'V2_KitStoneTri', 0.24)


def charcoal(dst, x, y0, z, r=0.16, h=0.52):
    """炭俵（立てた藁の筒・煤けた色・縄 3）。"""
    dst.cyl((x, y0, z), (x, y0 + h, z), r, r, 10, 'V2_Plaster', (0.34, 0.30, 0.25), caps=(True, True))
    for yy in (y0 + 0.08, y0 + h / 2 - 0.012, y0 + h - 0.10):
        dst.cyl((x, yy, z), (x, yy + 0.025, z), r + 0.007, r + 0.007, 10, 'V2_Wood', DARK * 0.7, caps=(False, False))


def tool_wall(dst, x0, x1, z, y):
    """奥壁の道具掛け：掛け板に槌 3・鋏（やっとこ）3 を吊る（鍛冶の道具）。y＝掛け板の上端。"""
    dst.box((x0, y - 0.06, z), (x1, y, z + 0.05), 'V2_Wood', DARK, grain=X)
    n = 6
    for i in range(n):
        xx = x0 + 0.12 + (x1 - x0 - 0.24) * i / (n - 1)
        if i % 2 == 0:       # 槌
            dst.beam((xx, y - 0.06, z + 0.05), (xx, y - 0.46, z + 0.05), 0.03, 0.03, 'V2_Wood', DARK)
            dst.box((xx - 0.075, y - 0.20, z + 0.02), (xx + 0.075, y - 0.08, z + 0.10), 'V2_KitStoneTri', 0.24)
        else:                # やっとこ
            dst.beam((xx - 0.012, y - 0.06, z + 0.05), (xx - 0.045, y - 0.50, z + 0.05), 0.022, 0.022, 'V2_KitStoneTri', 0.24)
            dst.beam((xx + 0.012, y - 0.06, z + 0.05), (xx + 0.045, y - 0.50, z + 0.05), 0.022, 0.022, 'V2_KitStoneTri', 0.24)


def kura_loft(W, P, zg):
    """蔵の妻の上階：荷揚げ戸（厚い漆喰の観音扉を開けた口）＋棟下から突き出す荷揚げ梁・滑車・縄・吊り荷（米俵）。zg＝妻の面。
    店の棟（4.6 m）の上に出る高さ（口 6.05–6.95 m・梁 7.2 m）＝通りから『倉に荷を揚げる家』と読める。"""
    W.box((-0.46, 6.05, zg - 0.01), (0.46, 6.95, zg + 0.02), 'V2_Wood', 0.08, grain=Y)                       # 暗い奥
    for xa, xb in ((-0.58, -0.46), (0.46, 0.58)):
        W.box((xa, 5.95, zg), (xb, 7.05, zg + 0.13), 'V2_Plaster', PL * 0.96, grain=Y)                       # 抱き
    W.box((-0.58, 6.95, zg), (0.58, 7.05, zg + 0.13), 'V2_Plaster', PL * 0.96, grain=X)                      # 楣
    W.box((-0.58, 5.95, zg), (0.58, 6.05, zg + 0.17), 'V2_Plaster', PL * 0.90, grain=X)                      # 沓摺
    for sx in (-1.0, 1.0):                                                                                   # 開いた観音扉（壁に直角）
        xa, xb = (0.58, 0.66) if sx > 0 else (-0.66, -0.58)
        W.box((xa, 6.02, zg + 0.13), (xb, 6.98, zg + 0.62), 'V2_Plaster', PL * 0.9, grain=Z)
        W.box((xa - (0.012 if sx > 0 else -0.012), 6.30, zg + 0.20), (xb + (0.012 if sx > 0 else -0.012), 6.36, zg + 0.60), 'V2_Wood', DARK * 0.45, grain=Z)
        W.box((xa - (0.012 if sx > 0 else -0.012), 6.66, zg + 0.20), (xb + (0.012 if sx > 0 else -0.012), 6.72, zg + 0.60), 'V2_Wood', DARK * 0.45, grain=Z)
    zb_ = zg + 1.10
    P.beam((0.0, 7.17, zg - 0.12), (0.0, 7.17, zg + 1.30), 0.11, 0.13, 'V2_Wood', DARK)                      # 荷揚げ梁
    P.cyl((-0.04, 6.99, zb_), (0.04, 6.99, zb_), 0.09, 0.09, 12, 'V2_Wood', DARK * 0.45, caps=(True, True))  # 滑車
    P.beam((0.0, 7.10, zb_), (0.0, 7.00, zb_), 0.02, 0.02, 'V2_Wood', DARK * 0.45)
    # 吊り荷は『荷揚げ戸の高さまで上がってきた』位置（俵の中心 6.12 m＝戸の沓摺 6.05 m の少し上）に置く：
    # 店の棟（4.63 m）より 1.3 m 以上高く、街から見て店の屋根に隠れず、暗い戸口を背に俵が読める（5.18 m に垂らすと店の屋根に隠れた＝実測）。
    P.cyl((0.0, 6.92, zb_), (0.0, 6.52, zb_), 0.012, 0.012, 6, 'V2_Wood', 0.85, caps=(False, False))        # 縄
    for sx in (-1.0, 1.0):                                                                                   # 吊り荷の掛け縄
        P.beam((0.0, 6.52, zb_), (sx * 0.22, 6.31, zb_), 0.012, 0.012, 'V2_Wood', 0.85)
    rice_bale(P, 0.0, 6.12, zb_, ln=0.60, r=0.17)                                                            # 吊り上げ中の米俵



def build_rsw074():
    """B_P_RSW_074 板葺き簡陋民宅：低い平屋（壁 2.3 m）＋石置きの板葺き屋根（押さえ竹・石・棟覆い・破風板）、荒い土壁と腰板に露出した柱、
    小さな戸口（板戸）・連子窓・妻の小窓、背に板葺きの下屋。瓦・漆喰の町家とは屋根材・量体・壁の構造・開口が違う。入口＝x −1.35..0.45。"""
    B = Bld('B_P_RSW_074', 4.5013, 10.92, 2.3, fin=0, tone=0)
    w, zf = B.w, B.zf
    MUD, MUD2 = (0.74, 0.62, 0.47), (0.66, 0.55, 0.42)
    zm, zr, YE = -2.20, -B.zf, 2.30
    xdl, xdr = -1.35, 0.45
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        tm = tmp()
        H = board_roof(tm, lod, zf - zm, w / 2, YE, 0.36, 0.45, 0.40, patch=(1.0, 0.55, 1.95, 0.32, 0.80))     # 左の屋面の一部を新しい板に張り替えた補修跡
        put(R, tm, off=(0.0, 0.0, (zf + zm) / 2), rot=-math.pi * 0.5)
        board_shed(R, lod, -w / 2 - 0.35, w / 2 + 0.35, zm, 2.15, zr - 0.30, 1.45)
        eave_roof(R, lod, -1.25, 0.35, 2.56, zf, 0.85, p=0.28, style='board', tone=0.72)                              # 戸口の上の小さな板庇（雨宿り・土間の延長）
        if lod == 1:
            W.box((-w / 2, FL, zm), (w / 2, YE, zf), 'V2_Plaster', MUD, grain=Y)
            W.box((-w / 2, FL, zr), (w / 2, 1.75, zm), 'V2_Plaster', MUD2, grain=Y)
            polyo(W, [(-w / 2, YE, zf - 0.02), (w / 2, YE, zf - 0.02), (0.0, H, zf - 0.02)], 'V2_Wood', BOARD * 0.7, out=(0.0, 0.0, 1.0))
            polyo(W, [(-w / 2, YE, zm + 0.02), (w / 2, YE, zm + 0.02), (0.0, H, zm + 0.02)], 'V2_Wood', BOARD * 0.7, out=(0.0, 0.0, -1.0))
            continue
        # --- 前面：腰板（横板）＋荒壁、戸口（板戸を半分引いた形）、連子窓 ---
        for (xa, xb) in ((-w / 2, xdl), (xdr, w / 2)):
            W.box((xa, FL, zf - 0.12), (xb, 1.12, zf), 'V2_Wood', BOARD * 0.72, grain=X)
        W.box((-w / 2, 1.12, zf - 0.12), (xdl, YE, zf), 'V2_Plaster', MUD, grain=Y)
        wx0, wx1, wy0, wy1 = 0.95, 1.80, 1.30, 1.86
        W.box((xdr, 1.12, zf - 0.12), (wx0, YE, zf), 'V2_Plaster', MUD, grain=Y)
        W.box((wx1, 1.12, zf - 0.12), (w / 2, YE, zf), 'V2_Plaster', MUD, grain=Y)
        W.box((wx0, 1.12, zf - 0.12), (wx1, wy0, zf), 'V2_Plaster', MUD, grain=Y)
        W.box((wx0, wy1, zf - 0.12), (wx1, YE, zf), 'V2_Plaster', MUD, grain=Y)
        W.box((wx0, wy0, zf - 0.10), (wx1, wy1, zf - 0.07), 'V2_Wood', 0.14, grain=Y)                                 # 窓の奥（暗）
        nb_ = int((wx1 - wx0) / 0.075)
        for i in range(nb_ + 1):                                                                                       # 連子（竹の縦格子）
            xx = wx0 + 0.04 + (wx1 - wx0 - 0.08) * i / nb_
            W.box((xx - 0.012, wy0, zf - 0.065), (xx + 0.012, wy1, zf - 0.015), 'V2_Wood', 0.78, grain=Y)
        for yy in (wy0 - 0.03, wy1):
            W.box((wx0 - 0.03, yy, zf - 0.10), (wx1 + 0.03, yy + 0.04, zf + 0.0), 'V2_Wood', DARK, grain=X)
        W.box((xdl, 1.98, zf - 0.12), (xdr, YE, zf), 'V2_Plaster', MUD, grain=Y)                                      # 戸口の上の荒壁
        W.box((xdl - 0.06, 1.90, zf - 0.14), (xdr + 0.06, 1.98, zf + 0.03), 'V2_Wood', DARK, grain=X)                  # 鴨居
        W.box((-0.45, FL, zf - 0.10), (xdr, 1.90, zf - 0.05), 'V2_Wood', BOARD * 0.72, grain=Y)                        # 板戸（右半分を閉じ、左は開いて暗い）
        W.box((xdl, FL, zf - 0.62), (-0.45, 1.90, zf - 0.58), 'V2_Wood', 0.12, grain=Y)                                # 戸口の奥（暗い土間）
        for xp in (-w / 2 + 0.06, xdl, xdr, w / 2 - 0.06):                                                             # 柱（露出した骨組み）
            W.box((xp - 0.06, FL, zf - 0.14), (xp + 0.06, YE + 0.04, zf + 0.02), 'V2_Wood', DARK, grain=Y)
        W.box((-w / 2, YE - 0.06, zf - 0.14), (w / 2, YE + 0.06, zf + 0.04), 'V2_Wood', DARK, grain=X)                 # 頭貫
        for (xa, xb) in ((-w / 2, xdl), (xdr, w / 2)):
            W.box((xa, 1.08, zf - 0.13), (xb, 1.16, zf + 0.01), 'V2_Wood', DARK, grain=X)                              # 貫
        # 妻面（縦板）＋小窓
        polyo(W, [(-w / 2, YE, zf - 0.06), (w / 2, YE, zf - 0.06), (0.0, H - 0.02, zf - 0.06)], 'V2_Wood', BOARD * 0.68, out=(0.0, 0.0, 1.0), grain=Y)
        W.quad((-0.17, 2.50, zf - 0.055), (0.17, 2.50, zf - 0.055), (0.17, 2.80, zf - 0.055), (-0.17, 2.80, zf - 0.055), 'V2_Wood', 0.15, grain=Y)
        # --- 側面：腰板＋荒壁、柱、貫（主屋）---
        for sx in (-1.0, 1.0):
            xo, xi = sx * w / 2, sx * (w / 2 - 0.12)
            xlo, xhi = min(xo, xi), max(xo, xi)
            W.box((xlo, FL, zm), (xhi, 1.12, zf), 'V2_Wood', BOARD * 0.72, grain=Z)
            W.box((xlo, 1.12, zm), (xhi, YE, zf), 'V2_Plaster', MUD, grain=Z)
            for zz in (zm + 0.08, zm + (zf - zm) * 0.34, zm + (zf - zm) * 0.66, zf - 0.08):
                W.box((xlo - 0.02, FL, zz - 0.06), (xhi + 0.02, YE + 0.04, zz + 0.06), 'V2_Wood', DARK, grain=Y)
            W.box((xlo - 0.02, 1.08, zm), (xhi + 0.02, 1.16, zf), 'V2_Wood', DARK, grain=Z)
            W.box((xlo - 0.02, YE - 0.06, zm), (xhi + 0.02, YE + 0.06, zf), 'V2_Wood', DARK, grain=Z)
            # 下屋の側面（屋根の勾配に合わせた台形の荒壁）
            W.box((xlo, FL, zr), (xhi, 1.12, zm), 'V2_Wood', BOARD * 0.72, grain=Z)
            polyo(W, [(xo, 1.12, zm), (xo, 1.12, zr), (xo, 1.45, zr), (xo, 2.15, zm)], 'V2_Plaster', MUD2, out=(sx, 0.0, 0.0), grain=Z)
            for zz, ht in ((zm - 0.08, 2.15), (zr + 0.08, 1.45)):
                W.box((xlo - 0.02, FL, zz - 0.06), (xhi + 0.02, ht, zz + 0.06), 'V2_Wood', DARK, grain=Y)
        # --- 下屋の背面、主屋の背面（下屋の屋根より上）と背面の妻 ---
        W.box((-w / 2, FL, zr), (w / 2, 1.12, zr + 0.12), 'V2_Wood', BOARD * 0.72, grain=X)
        W.box((-w / 2, 1.12, zr), (w / 2, 1.45, zr + 0.12), 'V2_Plaster', MUD2, grain=X)
        W.box((-w / 2, 2.10, zm), (w / 2, YE, zm + 0.12), 'V2_Plaster', MUD, grain=X)
        polyo(W, [(-w / 2, YE, zm + 0.06), (w / 2, YE, zm + 0.06), (0.0, H - 0.02, zm + 0.06)], 'V2_Wood', BOARD * 0.68, out=(0.0, 0.0, -1.0), grain=Y)
        # --- 生活痕跡：薪（窓の下）・天水桶と桶・蓑と笠・干し物・梯子・棟の煙出し ---
        PR = B.P[0]
        woodpile(PR, 1.00, 2.18, zf, rows=6, r=0.075, ln=0.33)                    # 窓の下の薪積み（高さ 0.85 m・窓の下端 1.30 m より低い）
        for xs_ in (1.20, 1.60, 2.00):
            solid(xs_, zf + 0.17, 0.36, 0.95)                                     # 薪の碰撞
        solid(-1.80, zf + 0.22, 0.44, 0.90)                                       # 天水桶の碰撞
        solid(-2.17, zf + 0.15, 0.30, 0.90)                                       # 小桶の碰撞
        tub(PR, -1.80, zf + 0.24, 0.22, 0.46)                                      # 天水桶（左の壁・軒の雨だれ受け）
        tub(PR, -2.17, zf + 0.15, 0.13, 0.26, col=0.7, water=False)                # 小さな桶
        mino(PR, -1.80, 1.68, zf)                                                  # 蓑
        kasa(PR, -2.03, 1.86, zf)                                                  # 笠
        hung_dried(PR, 0.55, 2.12, 2.12, zf + 0.13, n=6, seed=1)                   # 干し大根・干し柿（壁から 0.13 m）
        ladder(PR, -w / 2, -1.0, 2.20, YE - 0.05)                                  # 左の壁に立て掛けた竹梯子（屋根の石を直す）
        board_vent(R, 2.8, H)                                                     # 棟の煙出し（囲炉裏）
    B.finish()
    return B


def build_mkt029():
    """B_P_MKT_029 土蔵の商家：通り側は低めの店（厨子二階・緩い瓦屋根・浅い庇）、その奥に一段高い土蔵（白漆喰の厚い壁・海鼠壁の腰・深い窓の観音扉・
    重い入母屋風の妻入瓦屋根）が背後から立ち上がり、店の棟の上に白い妻壁と鬼瓦が見える。量体＝店（手前 5.4 m）＋蔵（奥 5.2 m）。入口＝x 1.75..3.5。"""
    B = Bld('B_P_MKT_029', 6.9942, 10.92, 3.6, hk='h27', fin=2, tone=1)
    w, zf = B.w, B.zf
    zb, zk1, zk0 = 0.05, -0.30, -B.zf               # 店の背面／蔵の前面／蔵の背面
    kw_ = 3.10                                      # 蔵の半幅（側軒の先端が footprint 内に収まる）
    YK = 6.0                                        # 蔵の壁高（店の棟 4.6 m より 1.4 m 高い白壁が背後に立つ）
    YS = 3.6                                        # 店の壁高（厨子二階）
    half_s = (zf - zb) / 2.0
    bays1 = [('koshib', 1.75), ('shop_k', 1.75), ('koshir', 1.745), ('shop_o', w - 5.245)]
    bays2 = [('mushib', 1.75), ('mushi', 1.75), ('mushib', 1.745), ('mushi', w - 5.245)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        # 屋根：店（平入・緩い瓦）＋蔵（妻入・重い瓦・鬼瓦）
        tms = tmp()
        gable_roof(tms, lod, w, half_s, YS, 0.38, 0.35, 0.10, tsuma=False)
        put(R, tms, off=(0.0, 0.0, (zf + zb) / 2))
        tmk = tmp()
        gable_roof(tmk, lod, zk1 - zk0, kw_, YK, 0.45, 0.40, 0.12, tsuma=True, oni=True, gyo=True)
        put(R, tmk, off=(0.0, 0.0, (zk1 + zk0) / 2), rot=-math.pi * 0.5)
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.75, zf, 1.0, p=0.30, style='tile', strut=False)
        if lod == 1:
            W.box((-w / 2, FL, zb), (w / 2, YS, zf), 'V2_Plaster', PL, grain=Y)
            W.box((-kw_, FL, zk0), (kw_, YK, zk1), 'V2_Plaster', PL, grain=Y)
            continue
        # 店：前面は Kit の開間、側面・背面は漆喰の壁
        row1(B, W, bays1)
        row2(B, W, bays2, 2.7, YS)
        for sx in (-1.0, 1.0):
            W.box((min(sx * w / 2, sx * (w / 2 - 0.1)), FL, zb), (max(sx * w / 2, sx * (w / 2 - 0.1)), YS, zf), 'V2_Plaster', PL, grain=Z)
        W.box((-w / 2, FL, zb), (w / 2, YS, zb + 0.10), 'V2_Plaster', PL, grain=X)
        cloth(W, 1.80, 3.40, 2.30, 1.50, zf + 0.03, 'noren_a', seg_w=0.8, billow=0.04)
        # 蔵：厚い白漆喰の壁（前面は店の屋根の上に白く見える）、側面は海鼠壁の腰＋深い窓
        W.box((-kw_, FL, zk1 - 0.30), (kw_, YK, zk1), 'V2_Plaster', PL, grain=Y)
        W.box((-kw_, FL, zk0), (kw_, YK, zk0 + 0.30), 'V2_Plaster', PL, grain=Y)
        for sx in (-1.0, 1.0):
            x = sx * kw_
            xa, xb = (x - 0.30, x) if sx > 0 else (x, x + 0.30)
            W.box((xa, FL, zk0), (xb, YK, zk1), 'V2_Plaster', PL, grain=Z)
            namako_side(W, zk0 + 0.05, zk1 - 0.05, FL, 1.50, x + sx * 0.0, sx)
            W.box((min(x, x + sx * 0.05), 1.50, zk0), (max(x, x + sx * 0.05), 1.60, zk1), 'V2_Plaster', PL * 0.92, grain=Z)    # 海鼠壁の上端の見切り
            for zc in (-1.55, -3.60):
                kura_window_side(W, x, sx, zc, 4.30, 5.10)
        # 蔵の妻（前後）は木組みを塗り込めた平らな白漆喰（Kit の妻は軸組みが見える）＋前の妻に小窓（店の棟の上に見える）
        Hk = YK + 0.45 * kw_
        polyo(W, [(-kw_ + 0.06, YK - 0.02, zk1 + 0.035), (kw_ - 0.06, YK - 0.02, zk1 + 0.035), (0.0, Hk - 0.10, zk1 + 0.035)], 'V2_Plaster', PL, out=(0.0, 0.0, 1.0), grain=Y)
        polyo(W, [(-kw_ + 0.06, YK - 0.02, zk0 - 0.035), (kw_ - 0.06, YK - 0.02, zk0 - 0.035), (0.0, Hk - 0.10, zk0 - 0.035)], 'V2_Plaster', PL, out=(0.0, 0.0, -1.0), grain=Y)
        zg = zk1 + 0.035
        PR = B.P[0]
        kura_loft(W, PR, zg)                                                           # 荷揚げ戸＋荷揚げ梁・滑車・吊り荷（棟の上に出る）
        # 店先の荷受け台（上がり框）：米俵の積み・木箱・樽（壁から 0.46 m 以内・戸口は x 1.75..3.5 なので反対側）
        kamachi(PR, -3.40, -0.40, zf)
        for xb in (-3.05, -2.40, -1.75):
            rice_bale(PR, xb, 0.46 + 0.16, zf + 0.25)
        for xb in (-2.72, -2.07):
            rice_bale(PR, xb, 0.46 + 0.16 + 0.29, zf + 0.25)
        crate(PR, -1.40, -0.92, zf + 0.06, zf + 0.44, 0.46, 0.84)
        crate(PR, -1.32, -1.00, zf + 0.10, zf + 0.40, 0.84, 1.12, 0.72)
        barrels(PR, -0.88, zf + 0.25, 0.46, rows=(1,), r=0.19, h=0.50)
        for xs_ in (-3.20, -2.70, -2.20, -1.70, -1.20, -0.70):
            solid(xs_, zf + 0.25, 0.50, 1.20)                                     # 荷受け台＋荷（踏み上がれない高さ）
    B.finish()
    return B


def build_rsw014():
    """B_P_RSW_014 作業場付きの工匠宅（鍛冶）：左半分が大戸を開け放した作業場（棟の高い妻入・煙出し・土の煙突・突き上げ戸・竈／鉄床／水桶／作業台）、
    右半分が住まい（低い妻入）。2 つの妻入屋根が高さ違いで並び、谷が通りから見える。入口（住まい側）＝x 0..1.8。"""
    B = Bld('B_P_RSW_014', 7.1971, 10.92, 2.7, hk='h27', fin=2, tone=2)
    w, zf = B.w, B.zf
    hw = w / 4.0                    # 各棟の半幅 1.799
    YW, YH = 3.10, 2.70             # 作業棟／住まいの壁高
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        tmw = tmp()
        Hw = gable_roof(tmw, lod, B.d, hw, YW, 0.58, 0.18, 0.30, tsuma=True, oni=True, gyo=True)
        put(R, tmw, off=(-hw, 0.0, 0.0), rot=-math.pi * 0.5)
        tmh = tmp()
        gable_roof(tmh, lod, B.d, hw, YH, 0.50, 0.18, 0.30, tsuma=True, oni=True, gyo=True)
        put(R, tmh, off=(hw, 0.0, 0.0), rot=-math.pi * 0.5)
        koshi_turret(B, lod, Hw, 1.5, -math.pi * 0.5, x=-hw, z=0.8)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (0.0, YW, zf), 'V2_Plaster', PL * 0.8, grain=Y)
            W.box((0.0, FL, -zf), (w / 2, YH, zf), 'V2_Plaster', PL, grain=Y)
            W.quad((-w / 2 + 0.15, FL, zf + 0.02), (-0.15, FL, zf + 0.02), (-0.15, 2.45, zf + 0.02), (-w / 2 + 0.15, 2.45, zf + 0.02), 'V2_Wood', 0.15, grain=Y)
            continue
        # --- 作業棟（左）---
        W.box((-w / 2, FL, -zf), (-w / 2 + 0.10, YW, zf), 'V2_Wood', BOARD * 0.55, grain=Z)                          # 外壁（煤けた板）
        W.box((-w / 2, FL, -zf), (0.0, YW, -zf + 0.10), 'V2_Wood', BOARD * 0.55, grain=X)
        W.box((-0.06, FL, -zf), (0.06, YH, zf), 'V2_Plaster', PL * 0.9, grain=Z)                                      # 住まいとの界壁
        W.box((-0.07, YH, -zf), (0.07, YW, zf), 'V2_Wood', DARK * 0.6, grain=Z)                                       # 界壁の上（住まいの屋根より上の部分）は軒天の暗い板
        for xp in (-w / 2 + 0.09, -0.07):                                                                               # 大戸の脇の太い柱
            W.box((xp - 0.10, FL, zf - 0.14), (xp + 0.10, YW, zf + 0.05), 'V2_Wood', DARK, grain=Y)
        W.box((-w / 2, 2.45, zf - 0.14), (0.0, 2.80, zf + 0.06), 'V2_Wood', DARK * 0.95, grain=X)                       # 大戸の差鴨居
        W.box((-w / 2, 2.80, zf - 0.10), (0.0, YW, zf), 'V2_Wood', DARK * 0.8, grain=X)
        # 内部：土間・奥壁（漆喰）・天井、竈（石）・煙の覆い、鉄床、水桶、作業台
        xi0, xi1, zi = -w / 2 + 0.10, -0.06, zf - 4.4
        W.box((xi0, FL, zi), (xi1, FL + 0.02, zf), 'V2_Plaster', (0.62, 0.52, 0.40), grain=X)
        W.box((xi0, FL, zi - 0.10), (xi1, 2.45, zi), 'V2_Plaster', PL * 0.72, grain=X)
        W.box((xi0, 2.38, zi), (xi1, 2.45, zf), 'V2_Wood', DARK * 0.55, grain=X)
        W.box((-3.30, FL, zi + 0.2), (-2.10, FL + 0.62, zi + 1.3), 'V2_KitStoneTri', 0.72)                            # 竈
        W.box((-3.25, FL + 0.62, zi + 0.25), (-2.15, FL + 0.68, zi + 1.25), 'V2_Wood', 0.16, grain=X)                  # 火床（煤）
        W.box((-3.35, 1.70, zi + 0.12), (-2.05, 2.40, zi + 1.38), 'V2_Plaster', PL * 0.5, grain=Y)                    # 煙の覆い
        W.cyl((-1.20, FL, zf - 2.3), (-1.20, FL + 0.55, zf - 2.3), 0.22, 0.20, 10, 'V2_Wood', DARK, caps=(True, True))   # 鉄床の台（切り株）
        W.box((-1.47, FL + 0.55, zf - 2.43), (-0.93, FL + 0.80, zf - 2.17), 'V2_KitStoneTri', 0.28)                    # 鉄床
        W.box((-0.93, FL + 0.66, zf - 2.36), (-0.74, FL + 0.78, zf - 2.24), 'V2_KitStoneTri', 0.28)
        W.cyl((-2.45, FL, zf - 1.3), (-2.45, FL + 0.50, zf - 1.3), 0.36, 0.34, 12, 'V2_Wood', 0.55, caps=(True, True))  # 焼き入れの水桶
        W.box((-0.95, FL + 0.74, zi + 0.4), (-0.32, FL + 0.80, zi + 3.0), 'V2_Wood', BOARD * 0.8, grain=Z)              # 作業台
        for zz in (zi + 0.5, zi + 2.9):
            for xx in (-0.88, -0.38):
                W.box((xx - 0.035, FL, zz - 0.035), (xx + 0.035, FL + 0.74, zz + 0.035), 'V2_Wood', DARK, grain=Y)
        shitomi(W, -w / 2 + 0.1, -0.1, 2.45, zf, rise=0.75, out=0.85, struts=False)                                    # 突き上げ戸（庇になる）
        chimney(R, -2.75, zi + 0.75, 3.2, Hw + 1.15, s=0.70)                                                          # 竈の煙突（棟より 1.15 m 上）
        # --- 簷下の作業区（突き上げ戸の庇の下・壁から 0.45 m 以内）：鉄床の切り株、焼き入れ桶、炭俵 ---
        PR = B.P[0]
        stump_anvil(PR, -1.80, zf + 0.23)
        tub(PR, -2.85, zf + 0.22, 0.19, 0.42, col=0.5)
        charcoal(PR, -3.20, -0.04, zf + 0.20, h=0.54)
        charcoal(PR, -3.20, 0.50, zf + 0.20, h=0.54)
        solid(-1.80, zf + 0.22, 0.44, 0.90)                                       # 切り株（鉄床）の碰撞
        solid(-2.85, zf + 0.22, 0.40, 0.90)                                       # 焼き入れ桶の碰撞
        solid(-3.20, zf + 0.20, 0.34, 1.20)                                       # 炭俵（2 段）の碰撞
        # --- 室内：炭俵（左壁際）・奥壁の道具掛け（槌 3・やっとこ 3）---
        for cz in (zf - 0.75, zf - 1.20, zf - 1.65):
            charcoal(PR, -3.30, FL, cz)
        charcoal(PR, -3.30, FL + 0.52, zf - 0.97)
        tool_wall(PR, -1.95, -0.42, zi + 0.02, 1.62)
        # --- 住まい（右）---
        put(W, FR('door', 1.80, B.hk), off=(0.0, 0.0, zf))
        put(W, FR('koshi', w / 2 - 1.80, B.hk), off=(1.80, 0.0, zf))
        woodpile(PR, 2.00, 3.15, zf, rows=5, r=0.075, ln=0.30)                                                          # 住まいの薪（鍛冶の炭とは別＝暮らしの側）
        jar(PR, 3.38, zf + 0.17, 0.17, 0.44)                                                                           # 水甕
        for xs_ in (2.20, 2.60, 3.00):
            solid(xs_, zf + 0.15, 0.30, 0.95)                                                                         # 薪の碰撞
        solid(3.38, zf + 0.17, 0.34, 0.90)                                                                            # 水甕の碰撞
        W.box((w / 2 - 0.10, FL, -zf), (w / 2, YH, zf), 'V2_Plaster', PL, grain=Z)
        W.box((0.0, FL, -zf), (w / 2, YH, -zf + 0.10), 'V2_Plaster', PL, grain=X)
    B.finish()
    return B


# ═══════════════ Phase 3 A：主街 北ブロック（西側）の屋形の差異化 5 棟 ═══════════════
# 使用者 2026-10-15「連続した街区の 4–6 棟を、用途に応じて屋根・側屋・簷線・比例・臨街正面から作り変える。色・棚・看板・小さな窓枠だけで済ませない」。
# 選んだ街区＝MainStreet 西側の北ブロック（MKT_030｜路地｜MKT_031・MXC_005・006・007）。どれも『二階建て＋瓦＋格子＋水平の長い軒』で輪郭が同じだった。
#   MKT_030 瀬戸物屋 ＝ 棟の低い石置き板葺きの平屋（路地角の『谷』）
#   MKT_031 菓子屋大店 ＝ 高い棟＋二階の出桁造り（張り出し）＋千鳥破風
#   MXC_005 質屋 ＝ 店（低めの二階）＋脇の蔵（妻を通りへ向けた白い二階建て）
#   MXC_006 菓子屋 ＝ 寄棟の二階＋全幅の縁（手摺）
#   MXC_007 八百屋 ＝ 深い下屋（前 3.6 m の片流れ瓦）の吹き放ちの土間店＋奥の二階

def row1p(B, m, x0, bays, dz=0.0):
    """row1 の部分幅版（x0 から bays を並べる）。終端 x を返す。"""
    x = x0
    for kind, wn in bays:
        if kind:
            put(m, FR(kind, wn, B.hk), off=(x, 0.0, B.zf + dz))
        x += wn
    return x


def row2p(B, m, x0, bays, y0, y1, dz=0.0):
    x = x0
    for kind, wn in bays:
        if kind:
            put(m, UP(kind, wn, y0, y1), off=(x, 0.0, B.zf + dz))
        x += wn
    return x


def chidori(R, lod, xc, zg, ye, half=1.45, ln=2.0, p=0.56, ove=0.28):
    """千鳥破風：主屋根の前の屋面に載る小さな妻入の切妻（棟は屋面の勾配に突き刺さる）。ye＝妻面の底（その位置の屋面の高さ）、zg＝妻面の z。lod0 のみ。"""
    if lod:
        return ye + p * half
    tm = tmp()
    gable_roof(tm, lod, ln, half, ye, p, ove, 0.10, tsuma=True, oni=True, gyo=True)
    put(R, tm, off=(xc, 0.0, zg - ln / 2.0), rot=-math.pi * 0.5)
    return ye + p * half


def side_window(dst, x, sgn, zc, y0, y1, ww=0.9):
    """側壁の連子窓：壁面 x（sgn＝外向き）。暗い奥＋縦の連子＋枠＋小庇。"""
    xa, xb = (x, x + sgn * 0.06) if sgn > 0 else (x + sgn * 0.06, x)
    z0, z1 = zc - ww / 2, zc + ww / 2
    dst.box((min(x, x + sgn * 0.015), y0, z0), (max(x, x + sgn * 0.015), y1, z1), 'V2_Wood', 0.12, grain=Y)
    n_ = max(3, int(ww / 0.075))
    for i in range(n_ + 1):
        zz = z0 + 0.03 + (ww - 0.06) * i / n_
        dst.box((min(x, x + sgn * 0.04), y0, zz - 0.012), (max(x, x + sgn * 0.04), y1, zz + 0.012), 'V2_Wood', 0.78, grain=Y)
    for yy in (y0 - 0.05, y1):
        dst.box((min(xa, xb), yy, z0 - 0.05), (max(xa, xb), yy + 0.05, z1 + 0.05), 'V2_Wood', DARK, grain=Z)
    for zz in (z0 - 0.05, z1):
        dst.box((min(xa, xb), y0 - 0.05, zz), (max(xa, xb), y1 + 0.05, zz + 0.05), 'V2_Wood', DARK, grain=Y)


def kura_win_front(dst, xc, y0, y1, z, ww=0.62):
    """土蔵の窓（正面）：壁より出る厚い漆喰の抱き＋暗い奥＋片方を開いた観音扉。z＝壁面。"""
    x0, x1 = xc - ww / 2, xc + ww / 2
    t = 0.11
    dst.box((x0, y0, z - 0.01), (x1, y1, z + 0.004), 'V2_Wood', 0.12, grain=Y)
    dst.box((x0 - t, y0 - t, z), (x0, y1 + t, z + t), 'V2_Plaster', PL * 0.96, grain=Y)
    dst.box((x1, y0 - t, z), (x1 + t, y1 + t, z + t), 'V2_Plaster', PL * 0.96, grain=Y)
    dst.box((x0, y1, z), (x1, y1 + t, z + t), 'V2_Plaster', PL * 0.96, grain=X)
    dst.box((x0, y0 - t, z), (x1, y0, z + t), 'V2_Plaster', PL * 0.96, grain=X)
    dst.box((x1 + t, y0 - 0.03, z + t - 0.01), (x1 + t + 0.05, y1 + 0.03, z + t + 0.34), 'V2_Plaster', PL * 0.9, grain=Z)    # 開いた観音扉（壁に直角）



def kura_front(W, x0, x1, z, yk, door_w=1.1):
    """蔵の正面（z＝前面）：白漆喰＋海鼠壁の腰＋土戸（鉄の帯金）。R2b：軒 3.35 m の低い附属倉に合わせ、戸の上の窓を無くした
    （戸 2.2 m・庇 2.65 m・軒下の帯）。開口は『戸』と『妻の小窓』の二つだけ＝窓を縦に積まない（塔に読めた R1／R2 の原因）。"""
    xc = (x0 + x1) / 2
    namako(W, x0 + 0.05, x1 - 0.05, FL, 1.20, z + 0.004)
    W.box((x0 - 0.02, 1.20, z - 0.02), (x1 + 0.02, 1.30, z + 0.07), 'V2_Plaster', PL * 0.92, grain=X)
    tsuchido(W, xc - door_w / 2, xc + door_w / 2, z, 2.20)
    W.box((x0 - 0.02, 2.20, z - 0.02), (x1 + 0.02, 2.30, z + 0.06), 'V2_Plaster', PL * 0.92, grain=X)
    W.box((x0 - 0.02, yk - 0.16, z - 0.02), (x1 + 0.02, yk - 0.06, z + 0.06), 'V2_Plaster', PL * 0.92, grain=X)


def pottery(P, x0, x1, z, y0, tiers=3, dy=0.40, seed=0):
    """瀬戸物の棚：棚板＋碗の積み・徳利。P（無着色）に描く。z＝棚の奥行き中心。"""
    import random
    rng = random.Random(seed)
    for t in range(tiers):
        y = y0 + t * dy
        P.box((x0, y - 0.03, z - 0.16), (x1, y, z + 0.16), 'V2_Wood', 0.55, grain=X)
        x = x0 + 0.14
        while x < x1 - 0.12:
            r_ = rng.random()
            if r_ < 0.60:
                n = rng.randint(3, 6)
                for i in range(n):
                    P.cyl((x, y + i * 0.045, z), (x, y + (i + 1) * 0.045, z), 0.075, 0.095, 10, 'V2_KitStoneTri', 0.95 - 0.05 * (i % 2), caps=(True, False))
                x += 0.22
            else:
                jar(P, x, z, 0.075, 0.26, y0=y)
                x += 0.19


def build_mkt030():
    """B_P_MKT_030 瀬戸物屋（Phase 3 A）：妻入の瓦二階をやめ、棟の低い『石置き板葺きの平入平屋』へ（棟 4.4 m。隣の二階は 7.4–7.9 m＝路地角で輪郭が低く落ちる）。
    前面は柱 4 本の吹き放ち（戸口＝x −1.44..0.48）、左は連子窓の板壁、右は腰高の陳列台、奥の棚に瀬戸物。路地側の妻は縦板張り。入口＝x −1.44..0.48。"""
    B = Bld('B_P_MKT_030', 4.8018, 10.92, 2.75, fin=0, tone=0)
    w, zf = B.w, B.zf
    YE = 2.75
    xdl, xdr = -1.44, 0.48
    zi = zf - 1.7
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        tm = tmp()
        H = board_roof(tm, lod, w, zf, YE, 0.30, 0.50, 0.12)
        put(R, tm)
        for sx in (-1.0, 1.0):
            polyo(W, [(sx * w / 2, YE, -zf), (sx * w / 2, YE, zf), (sx * w / 2, H - 0.03, 0.0)], 'V2_Wood', BOARD * 0.68, out=(sx, 0.0, 0.0), grain=Y)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Wood', BOARD * 0.72, grain=Y)
            continue
        for sx in (-1.0, 1.0):                                                                  # 側面（下見板張り）＋柱・貫
            xo, xi = sx * w / 2, sx * (w / 2 - 0.12)
            xlo, xhi = min(xo, xi), max(xo, xi)
            W.box((xlo, FL, -zf), (xhi, YE, zf), 'V2_Wood', BOARD * 0.72, grain=Z)
            for zz in (-zf + 0.08, -1.8, 1.8, zf - 0.08):
                W.box((xlo - 0.02, FL, zz - 0.06), (xhi + 0.02, YE + 0.04, zz + 0.06), 'V2_Wood', DARK, grain=Y)
            W.box((xlo - 0.02, 1.08, -zf), (xhi + 0.02, 1.16, zf), 'V2_Wood', DARK, grain=Z)
            W.box((xlo - 0.02, YE - 0.06, -zf), (xhi + 0.02, YE + 0.06, zf), 'V2_Wood', DARK, grain=Z)
        W.box((-w / 2, FL, -zf), (w / 2, YE, -zf + 0.12), 'V2_Wood', BOARD * 0.72, grain=X)      # 背面
        # 奥の壁と土間（吹き放ちの内側）
        W.box((-w / 2 + 0.12, FL, zi - 0.12), (w / 2 - 0.12, YE, zi), 'V2_Wood', DARK * 0.55, grain=X)
        W.box((xdl, FL, zi), (w / 2 - 0.12, FL + 0.03, zf), 'V2_KitStoneTri', 0.55)
        # 前面：左＝腰板＋連子窓＋板壁、戸口＝吹き放ち、右＝腰高の陳列台
        W.box((-w / 2, FL, zf - 0.12), (xdl, 1.05, zf), 'V2_Wood', BOARD * 0.72, grain=X)
        wx0, wx1, wy0, wy1 = -w / 2 + 0.16, xdl - 0.10, 1.20, 2.00
        W.box((wx0, wy0, zf - 0.12), (wx1, wy1, zf - 0.08), 'V2_Wood', 0.14, grain=Y)
        nb_ = int((wx1 - wx0) / 0.075)
        for i in range(nb_ + 1):
            xx = wx0 + 0.02 + (wx1 - wx0 - 0.04) * i / nb_
            W.box((xx - 0.012, wy0, zf - 0.07), (xx + 0.012, wy1, zf - 0.02), 'V2_Wood', 0.78, grain=Y)
        for yy in (wy0 - 0.04, wy1):
            W.box((wx0 - 0.03, yy, zf - 0.12), (wx1 + 0.03, yy + 0.04, zf), 'V2_Wood', DARK, grain=X)
        W.box((-w / 2, 1.05, zf - 0.12), (wx0, 2.0, zf), 'V2_Wood', BOARD * 0.72, grain=X)
        W.box((wx1, 1.05, zf - 0.12), (xdl, 2.0, zf), 'V2_Wood', BOARD * 0.72, grain=X)
        W.box((-w / 2, 2.0, zf - 0.12), (w / 2, YE - 0.06, zf - 0.02), 'V2_Wood', BOARD * 0.72, grain=X)      # 鴨居より上の板壁
        W.box((xdl - 0.05, 2.0, zf - 0.14), (w / 2, 2.12, zf + 0.03), 'V2_Wood', DARK, grain=X)             # 鴨居
        louver_window(W, -0.35, 0.40, 2.22, 2.55, zf - 0.02, n=4)
        for xp in (-w / 2 + 0.06, xdl, xdr, w / 2 - 0.06):                                                  # 吹き放ちの柱
            W.box((xp - 0.06, FL, zf - 0.14), (xp + 0.06, YE + 0.04, zf + 0.02), 'V2_Wood', DARK, grain=Y)
        W.box((-w / 2, YE - 0.06, zf - 0.14), (w / 2, YE + 0.06, zf + 0.04), 'V2_Wood', DARK, grain=X)       # 頭貫
        W.box((xdr + 0.06, 0.78, zf - 0.60), (w / 2 - 0.14, 0.84, zf - 0.10), 'V2_Wood', BOARD * 0.9, grain=X)   # 陳列台
        for xl_ in (xdr + 0.12, w / 2 - 0.20):
            for zl_ in (zf - 0.56, zf - 0.14):
                W.box((xl_ - 0.03, FL, zl_ - 0.03), (xl_ + 0.03, 0.78, zl_ + 0.03), 'V2_Wood', DARK, grain=Y)
        pottery(B.P[0], xdl + 0.15, w / 2 - 0.16, zi + 0.17, 0.55, tiers=4, dy=0.36, seed=3)                # 奥の棚の瀬戸物
        for i, xc_ in enumerate((xdr + 0.30, xdr + 0.62, xdr + 0.94, xdr + 1.26)):                            # 陳列台の上
            for k in range(4 + (i % 2)):
                B.P[0].cyl((xc_, 0.84 + k * 0.045, zf - 0.35), (xc_, 0.84 + (k + 1) * 0.045, zf - 0.35), 0.09, 0.11, 10, 'V2_KitStoneTri', 0.95 - 0.05 * (k % 2), caps=(True, False))
    B.finish()
    return B


def build_mkt031():
    """B_P_MKT_031 菓子屋の大店（Phase 3 A）：高い棟（8.7 m＝隣より約 0.9 m 高い）＋二階が一階より 0.42 m 張り出す出桁造り（腕木が並ぶ）＋
    屋根の前面に千鳥破風。一階の庇は短く、張り出した二階の窓列が通りに被さる＝『高く、せり出す町家』。入口＝x 0.44..2.20。"""
    B = Bld('B_P_MKT_031', 7.9, 10.92, 5.9, fin=2, tone=1)
    w, zf = B.w, B.zf
    YE, Y2, out = 5.9, 3.05, 0.42
    bays1 = [('koshi', 0.878), ('koshib', 1.756), ('koshi', 1.756), ('shop_o', 1.756), ('koshir', 1.756)]
    bays2 = [('mushib', 0.878), ('win', 1.756), ('win', 1.756), ('win', 1.756), ('mushib', 1.756)]
    zc = zf + out
    p_, zg = 0.52, 3.2
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        H = gable_on_body(B, lod, YE, p_, 0.80, 0.10, False)
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, 2.85, zf, 0.75, p=0.32, style='tile')
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, 3.0, zf), 'V2_Plaster', PL, grain=Y)
            W.box((-w / 2, 3.0, -zf), (w / 2, YE, zc), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        W.box((-w / 2, 2.90, zf - 0.04), (w / 2, Y2, zc), 'V2_Wood', DARK * 0.9, grain=X)               # 二階の床裏・出桁
        nbk = 9
        for i in range(nbk):                                                                           # 腕木（出桁を支える）
            xb = -w / 2 + 0.25 + (w - 0.5) * i / (nbk - 1)
            W.beam((xb, 2.78, zf - 0.02), (xb, 2.98, zc - 0.06), 0.09, 0.15, 'V2_Wood', DARK)
        assert abs(row2p(B, W, -w / 2, bays2, Y2, 5.6, dz=out) - w / 2) < 0.02
        W.box((-w / 2, 5.60, zc - 0.06), (w / 2, YE, zc), 'V2_Plaster', PL, grain=X)                     # 軒下の帯
        W.box((-w / 2 - 0.02, 5.78, zc - 0.04), (w / 2 + 0.02, YE + 0.02, zc + 0.08), 'V2_Wood', DARK, grain=X)   # 軒桁
        for sx in (-1.0, 1.0):                                                                         # 側壁（張り出し部も）
            xo, xi = sx * w / 2, sx * (w / 2 - 0.10)
            W.box((min(xo, xi), FL, -zf), (max(xo, xi), YE, zf), 'V2_Plaster', PL, grain=Z)
            W.box((min(xo, xi), 2.90, zf), (max(xo, xi), YE, zc), 'V2_Plaster', PL, grain=Z)
        W.box((-w / 2, FL, -zf), (w / 2, YE, -zf + 0.10), 'V2_Plaster', PL, grain=X)
        # 路地側（−x）の側壁：海鼠壁の腰＋露出した木組み（柱・貫）＋二階の連子窓 2＋一階の通用口（路地から見える大面積）
        xw = -w / 2
        namako_side(W, -zf + 0.15, zf - 0.15, FL, 1.45, xw, -1.0)
        W.box((xw - 0.03, 1.45, -zf), (xw + 0.0, 1.55, zf), 'V2_Plaster', PL * 0.9, grain=Z)
        for zz in (-zf + 0.10, -2.7, 0.0, 2.7, zf - 0.10):
            W.box((xw - 0.05, FL, zz - 0.07), (xw + 0.0, YE, zz + 0.07), 'V2_Wood', DARK, grain=Y)                    # 柱
        for yy in (1.55, 3.0, 5.0):
            W.box((xw - 0.05, yy - 0.06, -zf), (xw + 0.0, yy + 0.06, zf), 'V2_Wood', DARK, grain=Z)                    # 貫
        for zc_ in (-1.35, 1.35):
            side_window(W, xw, -1.0, zc_, 3.55, 4.65, 1.0)
        W.box((xw - 0.04, FL, -0.55), (xw + 0.0, 2.05, 0.45), 'V2_Wood', 0.12, grain=Y)                                # 通用口（暗い戸口）
        W.box((xw - 0.07, 2.05, -0.65), (xw + 0.0, 2.17, 0.55), 'V2_Wood', DARK, grain=Z)
    # 千鳥破風（lod0 のみ）：屋面の高さ＝H − p·z
    chidori(B.R[0], 0, 0.0, zg, H - p_ * zg)
    B.finish()
    return B


def build_mxc005():
    """B_P_MXC_005 質屋（Phase 3 A・R2b）：店（左 3.5 m・低めの二階＝棟 7.0 m）＋脇の蔵（右 3.5 m・店より 2.4 m 低い白い附属倉＝軒 3.35 m・棟 約 4.6 m）。
    R2b（使用者 2026-10-15 の再確認）：R2 の蔵（軒 3.9・棟 5.2）も、通りから見る妻面で『戸・窓・妻の小窓』が縦に三段で、なお細長い塔に読めた。
    → 『較低矮的附屬倉房』へ：軒を 3.35 m に下げ（棟 4.6 m・棟高÷幅 1.3）、戸の上の窓を無くし、開口を戸と妻の小窓の二つにした（細部は足さない）。以下は R2 の説明：
    R2（使用者 2026-10-15）：R1 の蔵（幅 3.0 m・軒 6.2 m・棟 7.1 m・長さ 6.8 m）は細長い塔に読めた。→ 低く（棟を店より 1.8 m 下げる）・広く（3.5 m＝店と同じ幅）・
    長く（奥行をほぼ全長 10.3 m）し、街の面から 0.35 m 引いて『店に付く倉』にする。二つの屋根（横棟の店・縦棟の蔵）が並ぶ輪郭は残す。入口（店）＝x −1.75..0。"""
    B = Bld('B_P_MXC_005', 7.0068, 10.92, 4.5, fin=0, tone=0)
    w, zf = B.w, B.zf
    xs0, xk, xk1 = -w / 2, 0.0, w / 2
    YE, YK = 4.5, 3.35
    zk1, zk0 = zf - 0.35, -zf + 0.25
    ws = xk - xs0
    bays1 = [('koshir', 1.7525), ('shop_o', 1.7525)]
    bays2 = [('mushib', 1.7525), ('mushi', 1.7525)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        tm = tmp()
        gable_roof(tm, lod, ws, zf, YE, 0.40, 0.55, 0.05, tsuma=False)
        put(R, tm, off=((xs0 + xk) / 2, 0.0, 0.0))
        tk = tmp()
        Hk = gable_roof(tk, lod, zk1 - zk0, (xk1 - xk) / 2, YK, 0.55, 0.15, 0.12, tsuma=True, oni=True, gyo=True)
        put(R, tk, off=((xk + xk1) / 2, 0.0, (zk1 + zk0) / 2), rot=-math.pi * 0.5)
        eave_roof(R, lod, xs0 + 0.02, xk - 0.02, 2.85, zf, 0.85, p=0.32, style='tile')
        eave_roof(R, lod, xk + 0.02, xk1 - 0.02, 2.65, zk1, 0.50, p=0.30, style='tile')                    # 蔵の戸の庇：一階（戸）と上の窓を割る横の影
        W.box((xk, FL, zk0), (xk1, YK, zk1), 'V2_Plaster', PL, grain=Y)                                     # 蔵（中身は箱＝正面だけ作り込む）
        W.box((xk - 0.02, 0.0, zk0 - 0.02), (xk1 + 0.02, 0.42, zk1 + 0.05), 'V2_KitStoneTri', 0.8)         # 蔵の石の土台（どっしり据える）
        if lod == 1:
            W.box((xs0, FL, -zf), (xk, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, xs0, bays1) - xk) < 0.02
        assert abs(row2p(B, W, xs0, bays2, 2.85, YE) - xk) < 0.02
        W.box((xs0, FL, -zf), (xs0 + 0.10, YE, zf), 'V2_Plaster', PL, grain=Z)                           # 店の左壁・背壁・右壁（右壁は蔵が引いた前の 0.35 m の袖壁も兼ねる）
        W.box((xs0, FL, -zf), (xk, YE, -zf + 0.10), 'V2_Plaster', PL, grain=X)
        W.box((xk - 0.10, FL, -zf), (xk, YE, zf), 'V2_Plaster', PL, grain=Z)
        kura_front(W, xk, xk1, zk1, YK)
        # 蔵の妻（前後）：木組みを塗り込めた平らな白漆喰。前の妻には小窓
        for zz, sgn in ((zk1 + 0.035, 1.0), (zk0 - 0.035, -1.0)):
            polyo(W, [(xk + 0.06, YK - 0.02, zz), (xk1 - 0.06, YK - 0.02, zz), ((xk + xk1) / 2, Hk - 0.10, zz)], 'V2_Plaster', PL, out=(0.0, 0.0, sgn), grain=Y)
        kura_win_front(W, (xk + xk1) / 2, YK + 0.17, YK + 0.50, zk1 + 0.035, 0.36)
    B.finish()
    return B


def build_mxc006():
    """B_P_MXC_006 菓子屋（Phase 3 A）：寄棟の二階（棟 6.5 m・四方へ傾く屋根＝隣の切妻の壁の間に『帽子』の輪郭）＋二階の全幅の縁（手摺・簾）。
    一階は間口いっぱいの格子と開いた戸口（入口＝x 0）、縁が一階の庇の代わり＝茶店のような軽い構え。"""
    B = Bld('B_P_MXC_006', 5.1944, 9.1, 5.2, fin=1, tone=2)
    w, zf = B.w, B.zf
    YE = 5.2
    wn = w / 3.0
    bays1 = [('koshir', wn), ('shop_o', wn), ('koshir', w - 2 * wn)]
    bays2 = [('win', wn), ('wins', wn), ('win', w - 2 * wn)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        H = hip_on_body(B, lod, YE, 0.50, 0.15)      # 005 との隙間 0.196 m：軒先（垂木端の厚み込み）が 0.35 m 以内に収まる出
        koshi_turret(B, lod, H, 1.2, 0.0)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        row1(B, W, bays1)
        row2(B, W, bays2, 2.9, YE)
        balcony(W, -w / 2 + 0.05, w / 2 - 0.05, 2.95, zf, depth=0.8, rail=0.85)
        for sx in (-1.0, 1.0):
            xo, xi = sx * w / 2, sx * (w / 2 - 0.10)
            W.box((min(xo, xi), FL, -zf), (max(xo, xi), YE, zf), 'V2_Plaster', PL, grain=Z)
        W.box((-w / 2, FL, -zf), (w / 2, YE, -zf + 0.10), 'V2_Plaster', PL, grain=X)
    B.finish()
    return B


def build_mxc007():
    """B_P_MXC_007 八百屋（Phase 3 A）：前 3.60 m が柱 3 本で受けた『深い下屋』（片流れの瓦・前縁 2.6 m）の吹き放ちの土間店、その奥に一段高い二階の母屋（横棟 6.1 m）。
    街から見ると『低く長い下屋→二階の壁帯→母屋の屋根』の三段の輪郭。入口（店の土間）＝x −2.2..−0.44。"""
    B = Bld('B_P_MXC_007', 7.9, 10.92, 4.6, fin=4, tone=1)
    w, zf = B.w, B.zf
    YE, zh = 4.6, 1.86                      # 母屋の壁頂／下屋の取り付き面（母屋の前面）
    yh, ph, dh = 3.55, 0.24, 3.60           # 下屋：取り付き高さ・勾配・出（先端＝正面の壁面。通りへは出さない）
    zr_c = (zh - zf) / 2.0                  # 母屋の奥行き中心
    half_r = (zh + zf) / 2.0
    posts = [-3.45, 0.55, 3.45]
    bays2 = [('winb', 1.756), ('winb', 1.756), ('mushib', 1.756), ('winb', 1.756), ('mushib', w - 7.024)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        tm = tmp()
        gable_roof(tm, lod, w, half_r, YE, 0.42, 0.45, 0.10, tsuma=False)
        put(R, tm, off=(0.0, 0.0, zr_c))
        eave_roof(R, lod, -w / 2 + 0.02, w / 2 - 0.02, yh, zh, dh, p=ph, style='tile', posts=posts)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zh), 'V2_Plaster', PL, grain=Y)
            continue
        # 母屋：前面（下屋の上は窓の帯）・背面・側面
        W.box((-w / 2, FL, zh - 0.12), (w / 2, yh, zh), 'V2_Plaster', PL * 0.78, grain=X)                 # 土間店の奥の壁（陰）
        for xo_ in (-2.2, 0.0, 2.2):                                                                       # 奥の壁の戸口（暗）
            W.box((xo_ - 0.45, FL, zh - 0.14), (xo_ + 0.45, 2.15, zh - 0.10), 'V2_Wood', 0.12, grain=Y)
        assert abs(row2p(B, W, -w / 2, bays2, yh, YE, dz=zh - zf) - w / 2) < 0.02
        W.box((-w / 2, FL, -zf), (w / 2, YE, -zf + 0.10), 'V2_Plaster', PL, grain=X)
        for sx in (-1.0, 1.0):
            xo, xi = sx * w / 2, sx * (w / 2 - 0.10)
            xlo, xhi = min(xo, xi), max(xo, xi)
            W.box((xlo, FL, -zf), (xhi, YE, zh), 'V2_Plaster', PL, grain=Z)
            ze = zh + dh
            polyo(W, [(xo, FL, zh), (xo, FL, ze), (xo, yh - ph * (dh - 0.04) - 0.05, ze), (xo, yh - 0.05, zh)], 'V2_Plaster', PL * 0.9, out=(sx, 0.0, 0.0), grain=Z)   # 下屋の側面
        # 土間店の構え：差し鴨居・中間の柱・陳列台
        W.box((-w / 2, 2.55, zf - 0.20), (w / 2, 2.70, zf - 0.04), 'V2_Wood', DARK, grain=X)
        for xp in posts:
            W.box((xp - 0.08, FL, zf - 0.20), (xp + 0.08, 2.55, zf - 0.04), 'V2_Wood', DARK, grain=Y)
            W.box((xp - 0.07, FL, zh + 1.5), (xp + 0.07, yh - ph * 1.5 - 0.32, zh + 1.64), 'V2_Wood', DARK, grain=Y)      # 柱頭は屋面の下（垂木の厚み 0.3 を引く）
        W.box((-3.2, 0.62, zf - 1.7), (-0.25, 0.70, zf - 0.70), 'V2_Wood', BOARD * 0.9, grain=X)             # 左の陳列台
        W.box((0.95, 0.62, zf - 1.7), (3.2, 0.70, zf - 0.70), 'V2_Wood', BOARD * 0.9, grain=X)              # 右の陳列台
        for xl_ in (-3.2, -0.25, 0.95, 3.2):
            for zl_ in (zf - 1.7, zf - 0.70):
                W.box((xl_ - 0.03, FL, zl_ - 0.03), (xl_ + 0.03, 0.62, zl_ + 0.03), 'V2_Wood', DARK, grain=Y)
        for xa, xb in ((-3.1, -2.2), (-1.6, -0.7), (1.05, 1.95), (2.2, 3.1)):                              # 籠・木箱
            crate(B.P[0], xa, xb, zf - 1.62, zf - 0.88, 0.70, 0.98, 0.8)
    B.finish()
    return B


# ═══════════════ Phase 3 B：住宅巷（MidLane）の家 3 棟 ═══════════════
# 使用者 2026-10-15「簡陋な板葺きと完整な瓦屋を混ぜ、側屋・倉房・柴棚、屋脊の向き・簷線の高低・入口の位置に合理的な変化を」。
# MidLane には既に RSW_074（板葺き妻入の簡陋民宅・承認済み）がある。その東に 075（瓦の妻入・縁側）・076（母屋＋板蔵）、巷の反対側に 071（板葺き平入＋前の下屋の柴棚）。

def build_rsw075():
    """B_P_RSW_075 瓦葺きの小綺麗な家（Phase 3 B）：妻入の瓦屋根（懸魚・鬼瓦・前の妻の出 0.45 m）＋左の間に縁側。隣の 074（板葺き妻入）と同じ向きだが、
    瓦・白漆喰・新しい木で『ちゃんとした家』と読める。入口＝x −0.9..0.9。"""
    B = Bld('B_P_RSW_075', 5.3962, 10.92, 3.0, hk='h27', fin=4, tone=1)
    w, zf = B.w, B.zf
    YE = 3.0
    bays1 = [('koshib', 1.8), ('door', 1.8), ('amado', w - 3.6)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        gable_on_body(B, lod, YE, 0.52, 0.55, 0.45, True)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', PL, grain=Y)
            continue
        assert abs(row1p(B, W, -w / 2, bays1) - w / 2) < 0.02
        engawa(W, -w / 2 + 0.10, -0.95, zf, h=0.42, depth=0.55)
        for sx in (-1.0, 1.0):
            xo, xi = sx * w / 2, sx * (w / 2 - 0.10)
            xlo, xhi = min(xo, xi), max(xo, xi)
            W.box((xlo, FL, -zf), (xhi, YE, zf), 'V2_Plaster', PL, grain=Z)
            for zz in (-zf + 0.10, -1.8, 1.8):
                W.box((xlo - 0.03, FL, zz - 0.06), (xhi + 0.03, YE, zz + 0.06), 'V2_Wood', DARK, grain=Y)
            W.box((xlo - 0.03, 1.15, -zf), (xhi + 0.03, 1.23, zf), 'V2_Wood', DARK, grain=Z)
        W.box((-w / 2, FL, -zf), (w / 2, YE, -zf + 0.10), 'V2_Plaster', PL, grain=X)
    B.finish()
    return B


def build_rsw076():
    """B_P_RSW_076 母屋＋板蔵（Phase 3 B）：右 4.15 m が瓦の平入（棟 5.8 m・縁側・入口 x −0.45..1.35）、左 2.15 m が『倉房』＝黒ずんだ縦板張りの妻入の小屋
    （瓦の切妻・大きな板戸に鉄の帯金。母屋の前面より 0.35 m 引く）。母屋と倉の屋根が別の向き・別の高さで並ぶ。"""
    B = Bld('B_P_RSW_076', 6.3057, 10.92, 3.5, hk='h27', fin=0, tone=2)
    w, zf = B.w, B.zf
    xk0, xk1 = -w / 2, -1.0
    zk1, zk0 = zf - 0.35, zf - 6.0
    YH, YS = 3.5, 3.2
    bays1 = [('plain', 0.551), ('door', 1.8), ('amado', w / 2 - 1.351)]
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        tm = tmp()
        gable_roof(tm, lod, w / 2 - xk1, zf, YH, 0.42, 0.50, 0.08, tsuma=False)
        put(R, tm, off=((xk1 + w / 2) / 2, 0.0, 0.0))
        tk = tmp()
        Hs = gable_roof(tk, lod, zk1 - zk0, (xk1 - xk0) / 2, YS, 0.55, 0.20, 0.30, tsuma=True, oni=True, gyo=True)
        put(R, tk, off=((xk0 + xk1) / 2, 0.0, (zk1 + zk0) / 2), rot=-math.pi * 0.5)
        if lod == 1:
            W.box((xk1, FL, -zf), (w / 2, YH, zf), 'V2_Plaster', PL, grain=Y)
            W.box((xk0, FL, zk0), (xk1, YS, zk1), 'V2_Wood', BOARD * 0.5, grain=Y)
            continue
        assert abs(row1p(B, W, xk1, bays1) - w / 2) < 0.02
        engawa(W, 0.55 + 0.9, w / 2 - 0.10, zf, h=0.42, depth=0.55)
        for xo, xi in ((w / 2, w / 2 - 0.10),):
            W.box((xi, FL, -zf), (xo, YH, zf), 'V2_Plaster', PL, grain=Z)
        W.box((xk1, FL, -zf), (w / 2, YH, -zf + 0.10), 'V2_Plaster', PL, grain=X)
        W.box((xk1 - 0.10, FL, -zf), (xk1, YH, zk0), 'V2_Plaster', PL, grain=Z)
        # 倉房（黒ずんだ縦板張り）
        W.box((xk0, FL, zk0), (xk1, YS, zk1), 'V2_Wood', BOARD * 0.5, grain=Y)
        for xp in (xk0 + 0.05, (xk0 + xk1) / 2 - 0.55, (xk0 + xk1) / 2 + 0.55, xk1 - 0.05):                      # 正面の柱
            W.box((xp - 0.05, FL, zk1 - 0.04), (xp + 0.05, YS, zk1 + 0.05), 'V2_Wood', DARK, grain=Y)
        W.box((xk0, 1.3, zk1 - 0.02), (xk1, 1.4, zk1 + 0.04), 'V2_Wood', DARK, grain=X)
        xc_ = (xk0 + xk1) / 2
        W.box((xc_ - 0.55, FL, zk1 - 0.02), (xc_ + 0.55, 2.1, zk1 + 0.08), 'V2_Wood', BOARD * 0.55, grain=Y)    # 大きな板戸
        for yy in (0.8, 1.45, 1.95):
            W.box((xc_ - 0.55, yy, zk1 + 0.08), (xc_ + 0.55, yy + 0.07, zk1 + 0.10), 'V2_Wood', DARK * 0.45, grain=X)   # 鉄の帯金
        W.box((xc_ - 0.62, 2.1, zk1 - 0.04), (xc_ + 0.62, 2.22, zk1 + 0.10), 'V2_Wood', DARK, grain=X)             # 鴨居
        polyo(W, [(xk0 + 0.04, YS - 0.02, zk1 + 0.04), (xk1 - 0.04, YS - 0.02, zk1 + 0.04), (xc_, Hs - 0.06, zk1 + 0.04)], 'V2_Wood', BOARD * 0.5, out=(0.0, 0.0, 1.0), grain=Y)
        louver_window(W, xc_ - 0.3, xc_ + 0.3, YS + 0.22, YS + 0.58, zk1 + 0.04, n=3)                              # 妻の無双窓
        side_window(W, xk0, -1.0, zk1 - 2.2, 1.7, 2.6, 0.7)                                                          # 倉房の側の小窓
        PR = B.P[0]
        woodpile(PR, xk0 + 0.15, xk0 + 1.3, zk1 + 0.04, rows=5, r=0.07, ln=0.30)                                     # 倉の前の薪
    B.finish()
    return B


def build_rsw071():
    """B_P_RSW_071 板葺きの家＋前の下屋（Phase 3 B）：石置きの板葺き平入（低い棟 4.2 m）、巷側の左半分に深い板葺きの下屋（柴棚＝薪・農具の置き場）が掛かる。
    土壁＋腰板、小さな連子窓。入口＝x 0..1.8（下屋の外）。"""
    B = Bld('B_P_RSW_071', 7.191, 10.92, 3.1, hk='h27', fin=0, tone=0)
    w, zf = B.w, B.zf
    YE = 3.1
    xdl, xdr = 0.0, 1.8
    xl0, xl1 = -w / 2 + 0.05, -0.35
    MUD = (0.74, 0.62, 0.47)
    for lod in (0, 1):
        W, R = B.W[lod], B.R[lod]
        tm = tmp()
        H = board_roof(tm, lod, w, zf, YE, 0.30, 0.45, 0.12)
        put(R, tm)
        eave_roof(R, lod, xl0, xl1, 3.00, zf, 1.15, p=0.20, style='board', tone=0.72)   # R2（使用者 2026-10-15）：庇柱を無くし、壁付けの腕木だけで受ける（深さ 1.15 m < 1.55 m の庇は柱が要らない。柱の碰撞が SpringArm を 1.21 m 縮めていた）。斜材も付けない：相機が元の場景と同じ位置＝庇の下に入るので、斜材が画面の左右を塞いだ（近景遮蔽 31.5 %）
        for sx in (-1.0, 1.0):
            polyo(W, [(sx * w / 2, YE, -zf), (sx * w / 2, YE, zf), (sx * w / 2, H - 0.03, 0.0)], 'V2_Wood', BOARD * 0.68, out=(sx, 0.0, 0.0), grain=Y)
        if lod == 1:
            W.box((-w / 2, FL, -zf), (w / 2, YE, zf), 'V2_Plaster', MUD, grain=Y)
            continue
        # 前面：腰板＋荒壁、戸口（板戸）、右に連子窓
        for (xa, xb) in ((-w / 2, xdl), (xdr, w / 2)):
            W.box((xa, FL, zf - 0.12), (xb, 1.12, zf), 'V2_Wood', BOARD * 0.72, grain=X)
            W.box((xa, 1.12, zf - 0.12), (xb, YE, zf), 'V2_Plaster', MUD, grain=Y)
        W.box((xdl, 1.98, zf - 0.12), (xdr, YE, zf), 'V2_Plaster', MUD, grain=Y)
        W.box((xdl - 0.06, 1.90, zf - 0.14), (xdr + 0.06, 1.98, zf + 0.03), 'V2_Wood', DARK, grain=X)
        W.box((xdl + 0.05, FL, zf - 0.10), (xdl + 0.95, 1.90, zf - 0.05), 'V2_Wood', BOARD * 0.72, grain=Y)
        W.box((xdl + 0.95, FL, zf - 0.62), (xdr, 1.90, zf - 0.58), 'V2_Wood', 0.12, grain=Y)
        wx0, wx1, wy0, wy1 = 2.5, 3.35, 1.30, 1.86
        W.box((wx0, wy0, zf - 0.10), (wx1, wy1, zf - 0.07), 'V2_Wood', 0.14, grain=Y)
        nb_ = int((wx1 - wx0) / 0.075)
        for i in range(nb_ + 1):
            xx = wx0 + 0.04 + (wx1 - wx0 - 0.08) * i / nb_
            W.box((xx - 0.012, wy0, zf - 0.065), (xx + 0.012, wy1, zf - 0.015), 'V2_Wood', 0.78, grain=Y)
        for yy in (wy0 - 0.03, wy1):
            W.box((wx0 - 0.03, yy, zf - 0.10), (wx1 + 0.03, yy + 0.04, zf), 'V2_Wood', DARK, grain=X)
        for xp in (-w / 2 + 0.06, xdl, xdr, w / 2 - 0.06):
            W.box((xp - 0.06, FL, zf - 0.14), (xp + 0.06, YE + 0.04, zf + 0.02), 'V2_Wood', DARK, grain=Y)
        W.box((-w / 2, YE - 0.06, zf - 0.14), (w / 2, YE + 0.06, zf + 0.04), 'V2_Wood', DARK, grain=X)
        W.box((-w / 2, 1.08, zf - 0.13), (w / 2, 1.16, zf + 0.01), 'V2_Wood', DARK, grain=X)
        for sx in (-1.0, 1.0):
            xo, xi = sx * w / 2, sx * (w / 2 - 0.12)
            xlo, xhi = min(xo, xi), max(xo, xi)
            W.box((xlo, FL, -zf), (xhi, 1.12, zf), 'V2_Wood', BOARD * 0.72, grain=Z)
            W.box((xlo, 1.12, -zf), (xhi, YE, zf), 'V2_Plaster', MUD, grain=Z)
            for zz in (-zf + 0.08, -1.8, 1.8, zf - 0.08):
                W.box((xlo - 0.02, FL, zz - 0.06), (xhi + 0.02, YE + 0.04, zz + 0.06), 'V2_Wood', DARK, grain=Y)
        W.box((-w / 2, FL, -zf), (w / 2, 1.12, -zf + 0.12), 'V2_Wood', BOARD * 0.72, grain=X)
        W.box((-w / 2, 1.12, -zf), (w / 2, YE, -zf + 0.12), 'V2_Plaster', MUD, grain=X)
        # 下屋の下：柴棚（薪の大きな積み・割り台・農具掛け）。壁から 0.45 m 以内は碰撞なし、それより出る物は solid
        PR = B.P[0]
        woodpile(PR, xl0 + 0.10, xl1 - 0.60, zf, rows=7, r=0.075, ln=0.34)
        woodpile(PR, xl1 - 0.50, xl1 - 0.05, zf, rows=5, r=0.075, ln=0.34)
        for xs_ in (xl0 + 0.5, xl0 + 1.0, xl0 + 1.5, xl0 + 2.0):
            solid(xs_, zf + 0.17, 0.36, 1.05)      # 壁際の薪（R2：庇柱は無い。碰撞は薪の低い箱だけ＝top 1.05 m で SpringArm の線の下）
        kasa(PR, xl1 - 0.22, 1.55, zf + 0.02)
        mino(PR, xl1 - 0.62, 1.70, zf)
        W.box((xl1 - 0.95, -0.04, zf + 0.62), (xl1 - 0.45, 0.45, zf + 1.02), 'V2_Wood', 0.55, grain=Y)                 # 割り台（切り株）
        solid(xl1 - 0.70, zf + 0.82, 0.50, 0.95)
    B.finish()
    return B


# ═══════════════ Phase 3 C：農家の柴棚・農具小屋（独立した小屋・Kit 建築ではない）═══════════════
# 使用者 2026-10-15「農舍生活區的柴棚、簡易遮棚或農具存放空間」。前が開いた片流れの板葺き（石置き）小屋：奥壁と西壁は縦板、東（前）は柱だけ。
# 中：薪の大きな積み・柴束・農具の掛け板・割り台と斧・水桶。碰撞は w9p3_lib が持つ（Kit の Posts／gate に混ぜないため _CUR を外す）。

def farm_tools(dst, x0, x1, z, ytop):
    """奥壁の農具掛け：掛け板に鍬 2・熊手・鎌 1（柄は細く長く、刃は鉄色）。ytop＝掛け板の上端。"""
    dst.box((x0, ytop - 0.06, z), (x1, ytop, z + 0.05), 'V2_Wood', DARK, grain=X)
    for i, xx in enumerate((x0 + 0.20, x0 + 0.52)):
        dst.beam((xx, ytop - 0.05, z + 0.07), (xx + 0.03 * (1 - 2 * i), ytop - 1.42, z + 0.10), 0.032, 0.032, 'V2_Wood', DARK * 0.9)
        dst.box((xx - 0.10, ytop - 1.60, z + 0.06), (xx + 0.12, ytop - 1.40, z + 0.12), 'V2_KitStoneTri', 0.26)
    xr = x0 + 0.86
    dst.beam((xr, ytop - 0.05, z + 0.07), (xr, ytop - 1.30, z + 0.09), 0.032, 0.032, 'V2_Wood', DARK * 0.9)
    dst.box((xr - 0.17, ytop - 1.38, z + 0.07), (xr + 0.17, ytop - 1.31, z + 0.11), 'V2_Wood', DARK)
    for k in range(5):
        xx = xr - 0.15 + 0.075 * k
        dst.box((xx - 0.010, ytop - 1.56, z + 0.08), (xx + 0.010, ytop - 1.38, z + 0.10), 'V2_KitStoneTri', 0.30)
    xs_ = x1 - 0.14
    dst.beam((xs_, ytop - 0.30, z + 0.07), (xs_, ytop - 0.78, z + 0.07), 0.028, 0.028, 'V2_Wood', DARK)         # 鎌の柄
    dst.box((xs_ - 0.15, ytop - 0.84, z + 0.055), (xs_ + 0.02, ytop - 0.74, z + 0.075), 'V2_KitStoneTri', 0.30)  # 鎌の刃


def brushwood(dst, x0, z0, z1, y0, r=0.17, n=(3, 2, 1)):
    """柴束：細い枝を束ねた円筒（軸 z・縄の帯 2）を三角に積む。x0＝左端。"""
    for ri, nn in enumerate(n):
        for i in range(nn):
            xc = x0 + r + i * 2 * r * 1.03 + ri * r
            yc = y0 + r + ri * r * 1.75
            dst.cyl((xc, yc, z0), (xc, yc, z1), r, r * 0.96, 9, 'V2_Wood', 0.84 + 0.10 * ((i + ri) % 2), caps=(True, True))
            for zz in (z0 + (z1 - z0) * 0.28, z0 + (z1 - z0) * 0.72):
                dst.cyl((xc, yc, zz - 0.015), (xc, yc, zz + 0.015), r + 0.010, r + 0.010, 9, 'V2_Wood', DARK * 0.7, caps=(False, False))


def build_farm_shed():
    """B_P_FARM_SHED 柴棚・農具小屋（Phase 3 C）：3.6 × 2.8 m・前（+z）が開いた片流れ板葺き（石置き）。奥壁高 2.55 m→前縁 2.05 m。"""
    B = Bld('B_P_FARM_SHED', 3.6, 2.8, 2.75, hk='h27', fin=0, tone=0)
    _CUR[0] = None
    w, zf = B.w, B.zf
    zb = -zf
    YB, PS = 2.75, 0.15
    depth = 2.8 + 0.28
    s_ = depth - 0.04
    for lod in (0, 1):
        W, R, PR = B.W[lod], B.R[lod], B.P[lod]
        eave_roof(R, lod, -w / 2 - 0.12, w / 2 + 0.12, YB, zb, depth, p=PS, style='board', tone=0.80)
        # 奥壁（縦板）と西壁（縦板・屋面なりの台形）
        W.box((-w / 2, 0.0, zb), (w / 2, YB - 0.04, zb + 0.10), 'V2_Wood', BOARD * 0.86, grain=Y)
        xw = -w / 2
        yfront = YB - (zf - 0.12 - zb) * PS - 0.24
        polyo(W, [(xw, 0.0, zb), (xw, 0.0, zf - 0.12), (xw, yfront, zf - 0.12), (xw, YB - 0.04, zb)], 'V2_Wood', BOARD * 0.80, out=(-1.0, 0.0, 0.0), grain=Y)
        polyo(W, [(xw + 0.06, 0.0, zb), (xw + 0.06, 0.0, zf - 0.12), (xw + 0.06, yfront, zf - 0.12), (xw + 0.06, YB - 0.04, zb)], 'V2_Wood', BOARD * 0.72, out=(1.0, 0.0, 0.0), grain=Y)
        if lod == 1:
            continue
        for yy in (0.55, 1.30, 2.00):
            W.box((-w / 2, yy, zb + 0.10), (w / 2, yy + 0.07, zb + 0.14), 'V2_Wood', DARK, grain=X)                 # 貫
        for zz in (zb + 0.12, -0.2, 0.75):
            ytop_ = min(YB - 0.04, yfront + 0.03 + (zf - 0.12 - zz) * PS)
            W.box((xw - 0.04, 0.0, zz - 0.05), (xw + 0.02, ytop_, zz + 0.05), 'V2_Wood', DARK, grain=Y)             # 西壁の柱
        # 前の柱 3（礎石付き）と棟持ちの繋ぎ梁
        for xp in (-w / 2 + 0.12, 0.0, w / 2 - 0.12):
            zp = zf - 0.10
            ytop_ = YB - (zp - zb) * PS - 0.24
            W.box((xp - 0.07, 0.0, zp - 0.07), (xp + 0.07, ytop_, zp + 0.07), 'V2_Wood', DARK, grain=Y)
            W.box((xp - 0.12, -0.04, zp - 0.12), (xp + 0.12, 0.10, zp + 0.12), 'V2_KitStoneTri', 0.8)
            W.beam((xp, ytop_ - 0.02, zp), (xp, YB - 0.30, zb + 0.14), 0.07, 0.12, 'V2_Wood', DARK)
        # 石置き（屋面の 3 列 × 7）
        for ri, zr in enumerate((0.55, 1.40, 2.25)):
            yr = YB - zr * PS
            for i in range(7):
                xx = -w / 2 + 0.22 + i * 0.52 + 0.05 * (((i * 3 + ri) % 3) - 1)
                hs = 0.075 + 0.02 * ((i + ri) % 3)
                R.box((xx - hs, yr + 0.0, zb + zr - hs * 0.8), (xx + hs, yr + hs * 1.1, zb + zr + hs * 0.8), 'V2_KitStoneTri', 0.5 + 0.06 * ((i * 5 + ri) % 3))
        # 中身：薪の大きな積み（奥壁沿い・左 3/5）、柴束（西壁沿い・前）、農具掛け（奥壁・右）、割り台＋斧、水桶、藁束
        woodpile(PR, -w / 2 + 0.22, 0.30, zb + 0.14, rows=10, r=0.08, ln=0.70, y0=-0.02)
        # 外の薪の積み（割った薪を前の左に高く積む・両端に杭）：遠くからも『薪小屋』と読める大きな明るい塊
        woodpile(PR, -w / 2 + 0.20, -0.20, zf + 0.12, rows=9, r=0.085, ln=0.62, y0=-0.02)
        for xs_ in (-w / 2 + 0.12, -0.12):
            PR.box((xs_ - 0.05, -0.04, zf + 0.40), (xs_ + 0.05, 1.35, zf + 0.50), 'V2_Wood', DARK * 0.9, grain=Y)
        farm_tools(PR, 0.62, w / 2 - 0.10, zb + 0.14, 2.05)
        brushwood(PR, -w / 2 + 0.10, 0.15, 1.05, -0.02)
        PR.cyl((1.05, -0.04, 0.40), (1.05, 0.40, 0.40), 0.22, 0.19, 10, 'V2_Wood', 0.5, caps=(True, True))                 # 割り台
        PR.beam((1.08, 0.40, 0.40), (1.30, 0.12, 0.30), 0.032, 0.032, 'V2_Wood', DARK * 0.9)                                 # 斧の柄（台に立て掛け）
        PR.box((1.26, 0.07, 0.24), (1.37, 0.20, 0.36), 'V2_KitStoneTri', 0.26)                                              # 斧の刃
        tub(PR, 1.45, -0.55, 0.26, 0.55, y0=-0.02, col=0.58, water=True)                                                    # 水桶
        mino(PR, 0.38, 1.95, zb + 0.14, w=0.46, h=0.62)
        kasa(PR, 0.12, 1.78, zb + 0.14, r=0.2)
        for k in range(3):
            PR.cyl((-0.30 + 0.0, 0.0 + 0.18 * k, zf - 0.55), (0.20, 0.0 + 0.18 * k, zf - 0.55), 0.085, 0.085, 8, 'V2_Plaster', STRAW, caps=(True, True))   # 藁束（薪の前に横に積む）
    B.finish()
    return B


BUILDERS = [build_mkt012, build_mkt013, build_mkt011, build_mkt010, build_mkt009, build_mkt008,
            build_rsw047, build_rsw048, build_rsw061, build_rsw062,
            build_mkt025, build_mkt027, build_mkt026, build_mkt024, build_mkt006, build_mkt020,
            build_rsw074, build_mkt029, build_rsw014,      # 最後の 3 つ＝Phase 2 の新建築タイプ見本
            build_mkt030, build_mkt031, build_mxc005, build_mxc006, build_mxc007,      # Phase 3 A：主街 北ブロック（西側）5 棟
            build_rsw075, build_rsw076, build_rsw071,      # Phase 3 B：住宅巷（MidLane）の家 3 棟
            build_farm_shed]      # Phase 3 C：農家の柴棚・農具小屋（独立した小屋）


def write_json_retry(p, d, tries=8):
    """K.write_json と同じ書式。Windows で他のプロセス（ウイルス対策・同期・別 session の走査）が一瞬握っていると open(…, 'w') が Errno 22 で落ちることがあるため、
    待って再試行する（書式・内容は K.write_json と同一。失敗が続けば最後の例外をそのまま上げる）。"""
    import time
    for i in range(tries):
        try:
            K.write_json(p, d)
            return
        except OSError as e:
            if i == tries - 1:
                raise
            print('[W9R2] write_json 再試行 %d/%d：%r' % (i + 1, tries, e))
            time.sleep(2.0)


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
    write_json_retry(OUT + '/src/modules_blender.json', {
        '_note': 'build_w9r2_arch.py 產生；Godot prefab（tools/p13/w9/w9r2_prefab.gd）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total, 'eaves': EAVES, 'roofs': ROOFS, 'posts': POSTS})
    print('[W9R2] %d メッシュ、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/w9r2_arch.glb'))
    for k, v in manifest.items():
        print('[W9R2]  %s %d tri' % (k, v['tris']))


main()
