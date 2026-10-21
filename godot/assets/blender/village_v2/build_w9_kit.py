"""人間之里 V2 P13 W9 Visible Village Enrichment：環境豐富化 Kit（w9_kit）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_w9_kit.py

目的（W9 第一輪，使用者 2026-10-14 授權）：住宅側巷・主街／市場・農路／農舍周邊の三区に、既存 Kit に無い「輪郭を変える中型物」を足す。
棚卸し（既存で足りる物は作らない）：薪棚 sk_woodpile・水甕 mk_kame・箒 kr_houki・籠 kr_kago・井戸 st_ido・稲架 st_hasa・藁塚 st_warazuka・鍬掛け st_kuwa・
  荷車 mk_kuruma_ni/kr_kuruma・菜園 hx_hatake・大根干し hx_daikon_kake・干し竿 mk_hoshimono・四つ目垣 gk_yotsume・柴垣 st_shibagaki・鉢 sz_hachi は既存を使う。
  町家 Kit の犬矢来 iy・煙出し kemu・袖看板 kbs・屋根看板 kbr・板庇 hisw も既存。
  無いのは：板塀・竹垣（建仁寺）・木戸・下屋（薪小屋／農具小屋）・軒の吊るし物（干し柿・唐辛子）・植木棚・朝顔棚・簾・祠・地蔵・杉玉・傘干し・草鞋掛け・笊掛け・案山子・野花の株。
材質（町で使用中・承認済みだけ、新 atlas なし）：V2_Wood／V2_Kawara（_matlib）＋ST_Street（street_kit atlas の色票）。
座標：Godot（x 右、y 上、+z 前＝通り側／壁から外へ）；原點＝接地点（壁付けの物は壁面中央・地面）；單位 m。*_l1＝LOD1。
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/w9_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(G + '/assets/village_v2/street_kit/atlas.json')
SWC = AT['swatches']
WD, KW, ST = 'V2_Wood', 'V2_Kawara', 'ST_Street'
MATS = [WD, KW, ST]
TILE = {WD: ML['V2_Wood']['tile_m'], KW: ML['V2_Kawara']['tile_m'], ST: 1.0}
NEW = (0.86, 0.80, 0.70)     # 新しい板
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


def mirror_x(src, name, note):
    """x を反転した複製（面の向きも反転）。下屋の「開いた側」を路へ向けるため。"""
    m = K.Mesh(name, src.mats, src.tile)
    m.v = [(-x, y, z) for (x, y, z) in src.v]
    for idx, mi, uvs, cols, sm in src.f:
        m.f.append((tuple(reversed(idx)), mi, tuple(reversed(uvs)), tuple(reversed(cols)), sm))
    MODS[name] = m
    INFO[name] = note
    return m


def swr(key):
    u, v = SWC[key]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


def obx(m, c, h, key, col=1.0, ax=K.X, ay=K.Y, az=K.Z):
    m.abox(c, h, ST, {'*': swr(key)}, col, ax=ax, ay=ay, az=az)


def cy(m, p0, p1, r0, r1, seg, key, caps=(True, True), col=1.0):
    m.cyl(p0, p1, r0, r1, seg, ST, col, caps=caps, uv_atlas=swr(key))


def stp(m, ps, key, col=1.0):
    u, v = SWC[key]
    m.poly(ps, ST, col, uvs=[(u, v)] * len(ps))


def stp2(m, ps, key, col=1.0):
    """両面（薄い板・布・紙）：表と裏を別の頂点で。"""
    stp(m, ps, key, col)
    stp(m, list(reversed(ps)), key, col * 0.85)


def newell(ps):
    nx = ny = nz = 0.0
    for i in range(len(ps)):
        a, b = ps[i], ps[(i + 1) % len(ps)]
        nx += (a[1] - b[1]) * (a[2] + b[2])
        ny += (a[2] - b[2]) * (a[0] + b[0])
        nz += (a[0] - b[0]) * (a[1] + b[1])
    return K.norm((nx, ny, nz))


def orient(ps, out=None, ctr=None):
    """面の外向き法線が out（または ctr から外）を向くように頂点順を整える。"""
    n = newell(ps)
    if out is None:
        c = (sum(p[0] for p in ps) / len(ps), sum(p[1] for p in ps) / len(ps), sum(p[2] for p in ps) / len(ps))
        out = K.sub(c, ctr)
    return list(ps) if K.dot(n, out) >= 0 else list(reversed(ps))


def stpo(m, ps, key, col=1.0, out=None, ctr=None):
    stp(m, orient(ps, out, ctr), key, col)


def wpo(m, ps, mat, col=1.0, out=None, ctr=None, grain=K.Y):
    m.poly(orient(ps, out, ctr), mat, col, grain=grain)


def bx(m, lo, hi, col=1.0, mat=WD):
    m.box(lo, hi, mat, col)


def leaf(m, base, ang, L, w, tilt, key, col=1.0):
    d = (math.cos(ang), 0.0, math.sin(ang))
    top = (base[0] + d[0] * L * math.cos(tilt), base[1] + L * math.sin(tilt), base[2] + d[2] * L * math.cos(tilt))
    s = (-d[2] * w, 0.0, d[0] * w)
    stp2(m, [K.sub(base, s), K.add(base, s), top], key, col)


def ball(m, c, r, key, seg=6, col=1.0):
    """低多角形の球（上下 2 極＋ 1 リング、外向き）。"""
    ring = [(c[0] + math.cos(2 * math.pi * i / seg) * r, c[1], c[2] + math.sin(2 * math.pi * i / seg) * r) for i in range(seg)]
    top = (c[0], c[1] + r * 0.95, c[2])
    bot = (c[0], c[1] - r * 0.95, c[2])
    for i in range(seg):
        a, b = ring[i], ring[(i + 1) % seg]
        stpo(m, [a, b, top], key, col, ctr=c)
        stpo(m, [a, b, bot], key, col * 0.8, ctr=c)


def cone(m, apex, base_c, r, seg, key, col=1.0, base=True):
    ring = [(base_c[0] + math.cos(2 * math.pi * i / seg) * r, base_c[1], base_c[2] + math.sin(2 * math.pi * i / seg) * r) for i in range(seg)]
    mid = ((apex[0] + base_c[0]) / 2, (apex[1] + base_c[1]) / 2, (apex[2] + base_c[2]) / 2)
    for i in range(seg):
        stpo(m, [ring[i], ring[(i + 1) % seg], apex], key, col, ctr=mid)
    if base:
        stpo(m, list(ring), key, col * 0.7, out=K.sub(base_c, apex))


# ───────────────────────── 垣・戸 ─────────────────────────

def itabei(lod, variant):
    """板塀 2.0 × 1.75：杭 2、貫 2（裏）、縦板 12（表）、笠木。b＝板が 2 枚新しく 1 枚は下半分だけ残り、当て板が斜めに打たれる。"""
    name = 'w9_itabei_a' if variant == 'a' else 'w9_itabei_b'
    m = new(name, lod, '板塀 2.0 × 1.75：杭 2＋貫 2（裏）＋縦板 12（表）＋笠木。' + ('' if variant == 'a' else '板 2 枚が新しく、1 枚は下半分だけ、斜めの当て板'))
    rng = random.Random(30101 if variant == 'a' else 30102)
    H = 1.72
    for x in (-0.96, 0.96):
        bx(m, (x - 0.05, -0.28, -0.07), (x + 0.05, H + 0.1, 0.07), OLD)
    for y in (0.42, 1.2):
        bx(m, (-0.96, y, -0.05), (0.96, y + 0.07, 0.0), AGED)
    n = 12 if not lod else 5
    pitch = 1.9 / n
    for i in range(n):
        xa = -0.95 + pitch * i
        xb = xa + pitch - (0.014 if not lod else 0.0)
        h = H - 0.1 + rng.uniform(-0.03, 0.03)
        col = rng.uniform(0.62, 0.8)
        if variant == 'b' and i in (3, 8) and not lod:
            col = 1.0
        if variant == 'b' and i == 6 and not lod:
            h = 0.78
        bx(m, (xa, 0.0, 0.0), (xb, h, 0.03), col)
    if variant == 'b':
        m.beam((-0.55, 0.15, 0.04), (-0.1, 0.62, 0.04), 0.07, 0.025, WD, NEW)
    bx(m, (-1.02, H, -0.09), (1.02, H + 0.05, 0.1), OLD)
    return m


def takegaki(lod):
    """建仁寺垣（竹垣）2.0 × 1.45：割り竹の縦（表・裏）＋竹の胴縁 3 段（縄で結ぶ）＋杭 2＋玉縁（上の押え竹）。枯れた竹の色（灰みの黄褐色）。"""
    m = new('w9_takegaki', lod, '建仁寺垣 2.0 × 1.45：割り竹（幅と高さが不揃い）を縦に並べ、胴縁 3 段を縄で結び、上端に玉縁。枯れた竹色')
    rng = random.Random(30103)
    n = 30 if not lod else 11
    xs = [rng.uniform(0.7, 1.3) for _ in range(n)]
    tot = sum(xs)
    xa = -0.96
    for i in range(n):
        wd = 1.92 * xs[i] / tot
        xb = xa + wd * 0.93
        h = 1.38 + rng.uniform(-0.03, 0.025)
        key = 'takebe' if rng.random() < 0.75 else 'komo'
        col = rng.uniform(0.62, 0.8)
        zf = rng.uniform(0.022, 0.04)
        stp(m, [(xa, 0.0, zf), (xb, 0.0, zf), (xb, h, zf), (xa, h, zf)], key, col)
        stp(m, [(xb, 0.0, -0.01), (xa, 0.0, -0.01), (xa, h, -0.01), (xb, h, -0.01)], 'takebe', col * 0.75)
        stpo(m, [(xa, h, -0.01), (xb, h, -0.01), (xb, h, zf), (xa, h, zf)], key, col * 0.9, out=(0.0, 1.0, 0.0))
        if not lod and rng.random() < 0.35:
            # 竹の節（細い横帯）
            yn = rng.uniform(0.2, 1.2)
            stp(m, [(xa, yn, zf + 0.002), (xb, yn, zf + 0.002), (xb, yn + 0.016, zf + 0.002), (xa, yn + 0.016, zf + 0.002)], 'kakishibu', 0.8)
        xa += wd
    seg = 6 if not lod else 4
    for y in (0.22, 0.72, 1.2):
        cy(m, (-1.0, y, 0.058), (1.0, y, 0.058), 0.022, 0.022, seg, 'takebe', caps=(True, True), col=0.55)
        if not lod:
            cy(m, (-1.0, y, -0.04), (1.0, y, -0.04), 0.022, 0.022, seg, 'takebe', caps=(True, True), col=0.5)
            # 縄の結び（胴縁と縦竹の交点）
            for xk in (-0.7, -0.2, 0.3, 0.8):
                cy(m, (xk, y - 0.03, 0.07), (xk, y + 0.03, 0.07), 0.02, 0.02, 5, 'nawa', caps=(False, False), col=0.7)
    cy(m, (-1.02, 1.41, 0.01), (1.02, 1.41, 0.01), 0.038, 0.038, seg + 2, 'takebe', caps=(True, True), col=0.62)
    for x in (-0.99, 0.99):
        bx(m, (x - 0.035, -0.25, -0.05), (x + 0.035, 1.5, 0.07), OLD)
    return m


def kido(lod):
    """木戸（小さな屋根門）：柱 2（0.13 角、高 2.05）＋冠木＋切妻の小さな板屋根＋戸 2 枚（閉じ）。幅 1.84。"""
    m = new('w9_kido', lod, '木戸：柱 2＋冠木＋板葺きの小さな切妻屋根＋縦板の戸 2 枚（閉じ）。幅 1.84、高 2.05')
    for x in (-0.69, 0.69):
        bx(m, (x - 0.065, -0.3, -0.07), (x + 0.065, 2.08, 0.07), OLD)
    bx(m, (-0.78, 1.86, -0.06), (0.78, 1.98, 0.06), AGED)
    # 屋根：前後 2 枚（棟 y 2.34、軒 y 2.04、z ±0.28）
    wpo(m, [(-0.9, 2.04, 0.28), (0.9, 2.04, 0.28), (0.9, 2.34, 0.0), (-0.9, 2.34, 0.0)], WD, AGED, out=(0.0, 0.5, 0.55), grain=K.Y)
    wpo(m, [(-0.9, 2.04, -0.28), (0.9, 2.04, -0.28), (0.9, 2.34, 0.0), (-0.9, 2.34, 0.0)], WD, OLD, out=(0.0, 0.5, -0.55), grain=K.Y)
    bx(m, (-0.92, 2.32, -0.04), (0.92, 2.37, 0.04), DARK)
    for sgn in (-1, 1):
        stpo(m, [(sgn * 0.9, 2.04, -0.28), (sgn * 0.9, 2.04, 0.28), (sgn * 0.9, 2.34, 0.0)], 'kakishibu', 0.8, out=(sgn, 0.0, 0.0))
    # 閉じた戸（右）
    nb = 5 if not lod else 2
    for i in range(nb):
        xa = 0.6 * i / nb
        bx(m, (xa + 0.03, 0.05, -0.03), (xa + 0.6 / nb, 1.78, 0.0), AGED)
    for y in (0.4, 1.4):
        bx(m, (0.03, y, 0.0), (0.64, y + 0.07, 0.035), OLD)
    # 閉じた戸（左）：通路を塞がない設計＝碰撞は全幅の箱なので、見た目も両扉を閉じる
    for i in range(nb):
        xa = -0.64 + 0.61 * i / nb
        bx(m, (xa + 0.0, 0.05, -0.03), (xa + 0.61 / nb - 0.01, 1.78, 0.0), AGED if i % 2 else OLD)
    for y in (0.4, 1.4):
        bx(m, (-0.64, y, 0.0), (-0.03, y + 0.07, 0.035), OLD)
    return m


# ───────────────────────── 下屋・軒 ─────────────────────────

def shita(lod, variant):
    """下屋（壁に寄せ掛けた片流れ）：w＝薪小屋 3.0 × 1.5（板葺き、薪の積み）／t＝農具小屋 2.4 × 1.3（桟瓦、農具と桶）。原點＝壁面中央・地面、+z＝外。"""
    if variant == 'w':
        m = new('w9_shita_wood', lod, '下屋・薪小屋 3.0 × 1.5（壁側 2.35／外 1.85 の片流れ、板葺き＋押縁）：外の柱 3、片側に板壁、積んだ薪（小口を表に）')
        W, D, HW, HO = 3.0, 1.5, 2.35, 1.85
        roof_mat, roof_col = WD, 0.72
    else:
        m = new('w9_shita_tool', lod, '下屋・農具小屋 2.4 × 1.3（壁側 2.3／外 1.9、桟瓦）：外の柱 2、片側板壁、立て掛けた鍬と箕、水桶')
        W, D, HW, HO = 2.4, 1.3, 2.3, 1.9
        roof_mat, roof_col = KW, 0.9
    rng = random.Random(30201 if variant == 'w' else 30202)
    x0, x1 = -W / 2, W / 2
    ex = 0.12
    # 屋根の上面（壁際 y=HW+0.02 → 外端 y=HO、奥行 D+0.18）
    top = [(x0 - ex, HW + 0.02, 0.0), (x1 + ex, HW + 0.02, 0.0), (x1 + ex, HO, D + 0.18), (x0 - ex, HO, D + 0.18)]
    sl = K.norm(K.sub(top[3], top[0]))
    if roof_mat == KW:
        wpo(m, top, KW, roof_col, out=(0.0, 1.0, 0.0), grain=sl)
    else:
        n_pl = 8 if not lod else 3
        for i in range(n_pl):
            xa = top[0][0] + (top[1][0] - top[0][0]) * i / n_pl
            xb = top[0][0] + (top[1][0] - top[0][0]) * (i + 1) / n_pl - 0.01
            wpo(m, [(xa, top[0][1], 0.0), (xb, top[0][1], 0.0), (xb, top[3][1], top[3][2]), (xa, top[3][1], top[3][2])], WD, roof_col * rng.uniform(0.85, 1.0), out=(0.0, 1.0, 0.0), grain=sl)
        # 押縁（板の継ぎ目の上の細い桟）
        for i in range(1, n_pl):
            xa = top[0][0] + (top[1][0] - top[0][0]) * i / n_pl
            m.beam((xa, HW + 0.035, 0.0), (xa, HO + 0.015, D + 0.18), 0.035, 0.02, WD, OLD)
    # 屋根の裏と厚み（前縁・側面）
    wpo(m, [(x0 - ex, HW - 0.04, 0.0), (x1 + ex, HW - 0.04, 0.0), (x1 + ex, HO - 0.07, D + 0.18), (x0 - ex, HO - 0.07, D + 0.18)], WD, OLD, out=(0.0, -1.0, 0.0), grain=sl)
    bx(m, (x0 - ex, HO - 0.07, D + 0.1), (x1 + ex, HO, D + 0.19), OLD)
    for sgn, sx in ((-1, x0 - ex), (1, x1 + ex)):
        stpo(m, [(sx, HW + 0.02, 0.0), (sx, HO, D + 0.18), (sx, HO - 0.07, D + 0.18), (sx, HW - 0.04, 0.0)], 'kakishibu', 0.7, out=(sgn, 0.0, 0.0))
    # 柱
    xs = (x0 + 0.05, 0.0, x1 - 0.05) if variant == 'w' else (x0 + 0.05, x1 - 0.05)
    for x in xs:
        bx(m, (x - 0.06, -0.25, D - 0.06), (x + 0.06, HO - 0.04, D + 0.06), OLD)
    # 垂木
    for i in range(5 if not lod else 3):
        x = x0 + W * i / (4 if not lod else 2)
        m.beam((x, HW - 0.05, 0.02), (x, HO - 0.06, D + 0.12), 0.05, 0.06, WD, OLD)
    # 側面の板壁（x0 側）
    nb = 8 if not lod else 3
    for i in range(nb):
        za = 0.05 + (D - 0.1) * i / nb
        zb = za + (D - 0.1) / nb - 0.01
        hh = HW - (HW - HO) * (za / D) - 0.06
        m.quad((x0 + 0.02, 0.0, zb), (x0 + 0.02, 0.0, za), (x0 + 0.02, hh, za), (x0 + 0.02, hh, zb), WD, AGED)
        m.quad((x0 + 0.02, 0.0, za), (x0 + 0.02, 0.0, zb), (x0 + 0.02, hh, zb), (x0 + 0.02, hh, za), WD, OLD)
    if variant == 'w':
        rows, cols = 5, 10
        if not lod:
            for r in range(rows):
                for c in range(cols):
                    x = x0 + 0.28 + c * 0.235 + (0.1 if r % 2 else 0.0) + rng.uniform(-0.01, 0.01)
                    if x > x1 - 0.32:
                        continue
                    y = 0.05 + r * 0.17
                    z0 = 0.18 + rng.uniform(0.0, 0.06)
                    L = 0.5 + rng.uniform(-0.04, 0.05)
                    hx = 0.085 + rng.uniform(-0.01, 0.01)
                    key = ('kuri', 'kakishibu', 'takebe')[rng.randrange(3)]
                    obx(m, (x, y + hx, z0 + L / 2), (hx, hx, L / 2), key, rng.uniform(0.75, 1.0))
            cy(m, (x1 - 0.45, 0.0, 1.15), (x1 - 0.45, 0.32, 1.15), 0.17, 0.17, 8, 'takebe', caps=(True, True))
            cy(m, (x1 - 0.8, 0.0, 1.0), (x1 - 0.8, 0.26, 1.0), 0.14, 0.14, 8, 'takebe', caps=(True, True))
        else:
            bx(m, (x0 + 0.2, 0.0, 0.18), (x1 - 0.3, 0.9, 0.7), AGED)
    else:
        if not lod:
            # 立て掛けた鍬 2（長い柄＋大きな鉄の刃）・熊手 1（柄＋櫛）・蓑（壁の釘に）・箕・水桶
            for k, (x, lean) in enumerate(((x0 + 0.3, 0.12), (x0 + 0.5, 0.18))):
                m.beam((x, 0.04, 0.34), (x + 0.05, 1.9, 0.1), 0.04, 0.04, WD, AGED)
                for t in (0.0, 1.0):
                    pass
                obx(m, (x - 0.02, 0.1, 0.38), (0.13, 0.1, 0.012), 'hagane')     # 刃（大きく、鉄色）
                m.beam((x - 0.02, 0.2, 0.38), (x, 0.55, 0.28), 0.03, 0.025, WD, OLD)   # 刃と柄の継ぎ
            x = x0 + 0.78
            m.beam((x, 0.04, 0.34), (x + 0.04, 1.8, 0.1), 0.04, 0.04, WD, AGED)
            m.beam((x - 0.18, 0.1, 0.34), (x + 0.18, 0.1, 0.34), 0.03, 0.03, WD, OLD)     # 熊手の頭
            for t in range(6):
                xx = x - 0.16 + 0.064 * t
                obx(m, (xx, 0.04, 0.34), (0.008, 0.06, 0.008), 'hagane')                  # 櫛の歯
            # 蓑（壁の釘に掛ける：茶の房状）
            for k in range(9):
                xx = x1 - 1.05 + k * 0.045
                stp2(m, [(xx, 1.55, 0.06), (xx + 0.04, 1.55, 0.06), (xx + 0.05, 0.85 + rng.uniform(-0.05, 0.05), 0.12), (xx - 0.01, 0.85, 0.12)], 'mino', rng.uniform(0.75, 1.0))
            stp2(m, [(x1 - 1.08, 1.6, 0.05), (x1 - 0.62, 1.6, 0.05), (x1 - 0.64, 1.45, 0.06), (x1 - 1.06, 1.45, 0.06)], 'wara')
            cy(m, (x1 - 0.5, 0.0, 0.62), (x1 - 0.5, 0.62, 0.62), 0.3, 0.33, 10, 'kakishibu', caps=(True, False))
            cy(m, (x1 - 0.5, 0.58, 0.62), (x1 - 0.5, 0.62, 0.62), 0.335, 0.335, 10, 'kokuyu', caps=(False, True))
            c = (0.2, 0.0, 0.55)
            stp2(m, [K.add(c, (-0.3, 0.02, -0.2)), K.add(c, (0.3, 0.02, -0.2)), K.add(c, (0.25, 0.34, 0.28)), K.add(c, (-0.25, 0.34, 0.28))], 'take', 0.9)
        else:
            bx(m, (x1 - 0.85, 0.0, 0.25), (x1 - 0.15, 0.62, 0.85), OLD)
            bx(m, (x0 + 0.25, 0.0, 0.25), (x0 + 0.95, 1.8, 0.4), AGED)
    return m


def tsurushi_kaki(lod):
    """軒の干し柿：竹竿（軒下に 2 本の腕木）から縄 9 本、各縄に 6 個。+z が外。原點＝壁面・地面（竿は高 2.12、壁から 0.3）。"""
    m = new('w9_tsurushi_kaki', lod, '軒の干し柿：竹竿 1.7（高 2.12、壁から 0.3）に縄 9 本、各 6 個の柿（橙→干して濃い茶の混在）')
    rng = random.Random(30301)
    for x in (-0.8, 0.8):
        m.beam((x, 2.1, 0.0), (x, 2.12, 0.3), 0.04, 0.04, WD, OLD)
    cy(m, (-0.88, 2.12, 0.3), (0.88, 2.12, 0.3), 0.022, 0.022, 6, 'take', caps=(True, True))
    n = 9 if not lod else 5
    for i in range(n):
        x = -0.75 + 1.5 * i / (n - 1)
        L = 0.8 + rng.uniform(-0.08, 0.06)
        cy(m, (x, 2.1, 0.3), (x, 2.1 - L, 0.3), 0.004, 0.004, 3, 'nawa', caps=(False, False))
        k = 6 if not lod else 3
        for j in range(k):
            y = 2.0 - j * (L - 0.1) / k
            key = 'kaki' if j < k - 2 else 'kakishibu'
            ball(m, (x + rng.uniform(-0.01, 0.01), y, 0.3), 0.035 if not lod else 0.04, key, 5 if not lod else 4, rng.uniform(0.85, 1.0))
    return m


def kaki_dai(lod):
    """干し柿の棚（庭先の独立した竹の枠）：支柱 2（高 2.15）＋上下の横竹＋縄 10 本×柿 6 個（互い違いに吊るして、丸い実の輪郭と隙間を残す）。幅 2.5。+z が外。日向の庭先に立つ。"""
    m = new('w9_kaki_dai', lod, '干し柿の棚：竹の支柱 2（高 2.15、間隔 2.4）＋上下の横竹、縄 10 本×柿 6 個（互い違い・橙と干して茶）。日向の庭先に独立して立つ')
    rng = random.Random(30311)
    for x in (-1.2, 1.2):
        cy(m, (x, -0.1, -0.12), (x, 2.15, 0.0), 0.045, 0.035, 6, 'take', caps=(True, True), col=0.78)
        cy(m, (x, -0.1, 0.12), (x, 2.15, 0.0), 0.045, 0.035, 6, 'take', caps=(True, True), col=0.78)
    cy(m, (-1.3, 2.1, 0.0), (1.3, 2.1, 0.0), 0.035, 0.035, 7, 'take', caps=(True, True), col=0.82)
    cy(m, (-1.25, 0.9, 0.0), (1.25, 0.9, 0.0), 0.025, 0.025, 6, 'take', caps=(True, True), col=0.7)
    n = 10 if not lod else 6
    for i in range(n):
        x = -1.0 + 2.0 * i / (n - 1)
        L = 0.95 + rng.uniform(-0.07, 0.05)
        cy(m, (x, 2.08, 0.0), (x, 2.08 - L, 0.0), 0.006, 0.006, 3, 'nawa', caps=(False, False))
        k = 6 if not lod else 4
        off = 0.06 if i % 2 else 0.0                 # 隣の縄と半個ずらす
        for j in range(k):
            y = 1.98 - off - j * (L - 0.1) / k
            key = 'kaki' if j < k - 2 else 'kakishibu'
            ball(m, (x + rng.uniform(-0.012, 0.012), y, rng.uniform(-0.02, 0.02)), 0.062 if not lod else 0.07, key, 6 if not lod else 4, rng.uniform(0.9, 1.0))
    return m


def tsurushi_togarashi(lod):
    """軒の唐辛子と大蒜：竿 1.4 に唐辛子の束 3（赤）＋大蒜の編み 2（淡色）。"""
    m = new('w9_tsurushi_togarashi', lod, '軒の唐辛子と大蒜：竹竿 1.4（高 2.15）に唐辛子の束 3（赤）と大蒜の編み 2（淡色）、縄で吊る')
    rng = random.Random(30302)
    for x in (-0.6, 0.6):
        m.beam((x, 2.13, 0.0), (x, 2.15, 0.28), 0.04, 0.04, WD, OLD)
    cy(m, (-0.68, 2.15, 0.28), (0.68, 2.15, 0.28), 0.02, 0.02, 6, 'take', caps=(True, True))
    spec = [(-0.45, 'togarashi', 0.62), (-0.1, 'togarashi', 0.5), (0.2, 'togarashi', 0.7), (0.5, 'kakishibu', 0.5), (0.05, 'togarashi', 0.55)]
    for x, key, L in spec:
        z = 0.28 + (0.04 if x == 0.05 else 0.0)
        cy(m, (x, 2.13, z), (x, 2.13 - L, z), 0.006, 0.006, 3, 'nawa', caps=(False, False))
        k = int(L / 0.05) if not lod else 3
        for j in range(k):
            y = 2.08 - j * 0.05 * (1.0 if not lod else 3.0)
            for s in range(3 if key == 'togarashi' and not lod else 1):
                a = rng.uniform(0, 2 * math.pi)
                if key == 'togarashi':
                    ap = (x + math.cos(a) * 0.045, y - 0.07, z + math.sin(a) * 0.045)
                    cone(m, (ap[0], ap[1] - 0.05, ap[2]), (x + math.cos(a) * 0.02, y, z + math.sin(a) * 0.02), 0.022, 4, 'togarashi', rng.uniform(0.85, 1.0), base=False)
                else:
                    ball(m, (x + math.cos(a) * 0.03, y, z + math.sin(a) * 0.03), 0.04, 'kakishibu', 5, rng.uniform(0.85, 1.0))
    return m


def sudare(lod):
    """簾（縁側・軒に下げる）1.8 × 1.55：上の横木＋半分巻き上げた簾の巻き（上）＋割り竹の横筋＋縄 2。+z が外。簾は高 0.55–2.05、壁から 0.18。"""
    m = new('w9_sudare', lod, '簾 1.8 × 1.55（高 0.55–2.05、壁から 0.18）：上の横木、巻き上げた簾の巻き、割り竹の横筋、吊り縄。裾は不揃い')
    rng = random.Random(30311)
    bx(m, (-0.95, 2.04, 0.12), (0.95, 2.12, 0.22), OLD)
    n = 22 if not lod else 8
    top = 1.88
    h = (top - 0.55) / n
    for i in range(n):
        y1 = top - i * h
        y0 = y1 - h * 0.86
        col = (0.78 if i % 2 else 0.62) * rng.uniform(0.9, 1.05)
        # 裾（下の数段）は左右の長さが不揃い
        xl = -0.9 + (rng.uniform(0.0, 0.18) if i > n - 5 else 0.0)
        xr = 0.9 - (rng.uniform(0.0, 0.2) if i > n - 5 else 0.0)
        stp(m, [(xl, y0, 0.19), (xr, y0, 0.19), (xr, y1, 0.19), (xl, y1, 0.19)], 'komo', col)
        stp(m, [(xr, y0, 0.17), (xl, y0, 0.17), (xl, y1, 0.17), (xr, y1, 0.17)], 'komo', col * 0.7)
    # 巻き上げた部分（上の太い巻き）
    cy(m, (-0.9, 1.97, 0.19), (0.9, 1.97, 0.19), 0.085, 0.085, 8 if not lod else 5, 'komo', caps=(True, True), col=0.75)
    for x in (-0.6, 0.55):
        cy(m, (x, 2.04, 0.2), (x, 0.58, 0.2), 0.008, 0.008, 3, 'nawa', caps=(False, False))
        cy(m, (x, 1.97, 0.19), (x, 1.9, 0.19), 0.1, 0.1, 6, 'nawa', caps=(False, False), col=0.7)
    return m


def ueki_tana(lod):
    """植木棚（3 段の階段棚）0.95 × 0.62 × 1.05：細い角材の側枠（斜材＋後ろの脚）、薄い棚板 3、鉢 7（素焼き・灰釉）、葉の叢と小さな花。背面＝壁（z 0）、+z が外。"""
    m = new('w9_ueki_tana', lod, '植木棚：細い角材の階段枠 0.95 × 0.62 × 1.05、棚板 3、鉢 7、葉の叢と花（白・桃・紅）')
    rng = random.Random(30401)
    # 側枠：前脚（短い）＋斜材（前下→後上）＋後脚（高い）＋横木
    for x in (-0.44, 0.44):
        m.beam((x, 0.0, 0.64), (x, 0.38, 0.64), 0.045, 0.045, WD, OLD)
        m.beam((x, 0.02, 0.62), (x, 1.07, 0.04), 0.045, 0.04, WD, AGED)
        m.beam((x, -0.02, 0.04), (x, 1.1, 0.04), 0.05, 0.05, WD, OLD)
        for y, z in ((0.34, 0.4), (0.69, 0.22)):
            m.beam((x, y - 0.03, 0.04), (x, y - 0.03, z + 0.08), 0.035, 0.03, WD, AGED)
    for (y, z0, z1) in ((0.36, 0.3, 0.64), (0.71, 0.14, 0.46), (1.06, 0.0, 0.3)):
        bx(m, (-0.48, y - 0.02, z0), (0.48, y + 0.012, z1), AGED)
        bx(m, (-0.48, y - 0.045, z1 - 0.025), (0.48, y + 0.02, z1), OLD)   # 手前の縁板
    spots = [(-0.3, 0.375, 0.5, 0.13), (0.0, 0.375, 0.5, 0.14), (0.3, 0.375, 0.5, 0.13), (-0.18, 0.725, 0.3, 0.13), (0.18, 0.725, 0.3, 0.13), (-0.12, 1.075, 0.14, 0.12), (0.16, 1.075, 0.14, 0.12)]
    fl = ['kinari', 'konpeito', 'akachochin', 'kinari', 'konpeito', 'akachochin', 'kinari']
    for k, (x, y, z, r) in enumerate(spots):
        seg = 8 if not lod else 5
        cy(m, (x, y, z), (x, y + 0.13, z), r * 0.72, r, seg, 'tsuchi' if k % 2 else 'haiyu', caps=(True, False))
        for j in range(7 if not lod else 3):
            leaf(m, (x, y + 0.12, z), rng.uniform(0, 2 * math.pi), rng.uniform(0.14, 0.24), 0.055, rng.uniform(0.5, 1.15), 'daikon_leaf' if j % 2 else 'kyabetsu', rng.uniform(0.85, 1.0))
        if not lod:
            for j in range(4):
                a = rng.uniform(0, 2 * math.pi)
                ball(m, (x + math.cos(a) * 0.07, y + 0.22 + rng.uniform(0, 0.07), z + math.sin(a) * 0.07), 0.027, fl[k], 5)
    return m


def asagao(lod):
    """朝顔の棚：竹の支柱 2（高 1.9）＋竹の横 3 段＋縦縄 5、蔓と葉（密）、花 22（藍・桃・白）。幅 1.28、奥 0.27。"""
    m = new('w9_asagao', lod, '朝顔の棚：竹の支柱 2（1.9）＋横竹 3＋縦縄 5、蔓と葉（密）、花 22（藍・桃・白）')
    rng = random.Random(30402)
    for x in (-0.6, 0.6):
        cy(m, (x, 0.0, -0.1), (x, 1.9, 0.0), 0.022, 0.018, 6, 'takebe', caps=(True, True), col=0.7)
        cy(m, (x, 0.0, 0.1), (x, 1.9, 0.0), 0.022, 0.018, 6, 'takebe', caps=(True, True), col=0.7)
    for y in (0.5, 1.1, 1.75):
        cy(m, (-0.64, y, 0.0), (0.64, y, 0.0), 0.014, 0.014, 5, 'takebe', caps=(True, True), col=0.66)
    n = 5 if not lod else 3
    for i in range(n):
        x = -0.5 + 1.0 * i / (n - 1)
        cy(m, (x, 0.0, 0.02), (x + rng.uniform(-0.04, 0.04), 1.85, 0.02), 0.005, 0.005, 3, 'nawa', caps=(False, False))
        # 蔓（縄に巻き付く細い緑）
        steps = 9 if not lod else 4
        for j in range(steps):
            y0 = 1.8 * j / steps
            y1 = 1.8 * (j + 1) / steps
            xo0 = math.sin(j * 1.9 + i) * 0.04
            xo1 = math.sin((j + 1) * 1.9 + i) * 0.04
            cy(m, (x + xo0, y0, 0.04), (x + xo1, y1, 0.04), 0.006, 0.006, 3, 'daikon_leaf', caps=(False, False), col=0.8)
    for i in range(n):
        x = -0.5 + 1.0 * i / (n - 1)
        for j in range(10 if not lod else 4):
            y = 0.1 + j * 0.18 + rng.uniform(-0.05, 0.05)
            base = (x + rng.uniform(-0.06, 0.06), y, 0.04)
            leaf(m, base, rng.uniform(-0.7, 0.7) + (math.pi / 2), 0.13, 0.075, rng.uniform(-0.2, 0.6), 'daikon_leaf', rng.uniform(0.7, 1.0))
            leaf(m, base, rng.uniform(-0.7, 0.7) - (math.pi / 2), 0.12, 0.07, rng.uniform(-0.2, 0.6), 'kyabetsu', rng.uniform(0.7, 1.0))
    if not lod:
        for j in range(22):
            x = rng.uniform(-0.55, 0.55)
            y = rng.uniform(0.3, 1.8)
            key = ('ai', 'konpeito', 'kinari', 'sometsuke')[j % 4]
            c = (x, y, 0.09)
            ring = [(c[0] + math.cos(2 * math.pi * k / 7) * 0.06, c[1] + math.sin(2 * math.pi * k / 7) * 0.06, c[2]) for k in range(7)]
            stp2(m, ring, key, 1.0)
    return m


# ───────────────────────── 祠・地蔵 ─────────────────────────

def jizo(lod):
    """地蔵：石の基壇 0.62 × 0.52 × 0.22＋台座＋立像（高 0.7、頭＋袈裟）、赤い前掛けと頭巾、供えの小皿と花。原點＝接地。"""
    m = new('w9_jizo', lod, '地蔵：石の基壇＋台座＋立像（高 0.7）、赤い前掛けと頭巾、供えの小皿と小さな花')
    obx(m, (0.0, 0.11, 0.0), (0.31, 0.11, 0.26), 'hagane', 0.82)
    obx(m, (0.0, 0.29, 0.0), (0.22, 0.07, 0.19), 'hagane', 0.9)
    seg = 10 if not lod else 6
    cy(m, (0.0, 0.36, 0.0), (0.0, 0.7, 0.0), 0.15, 0.1, seg, 'hagane', caps=(False, False), col=0.95)
    ball(m, (0.0, 0.8, 0.0), 0.095, 'hagane', 8 if not lod else 5, 0.95)
    # 苔（基壇の足元と角）
    for (mx, mz, mw) in ((-0.2, 0.27, 0.12), (0.12, 0.28, 0.16), (0.0, -0.26, 0.2), (0.3, 0.05, 0.1)):
        obx(m, (mx, 0.025, mz), (mw, 0.03, 0.06), 'daikon_leaf', 0.75)
    ball(m, (0.0, 0.83, -0.005), 0.1, 'shuurushi', 8 if not lod else 5, 0.95)
    stp2(m, [(-0.09, 0.55, 0.098), (0.09, 0.55, 0.098), (0.07, 0.71, 0.09), (-0.07, 0.71, 0.09)], 'shuurushi')
    if not lod:
        cy(m, (-0.2, 0.22, 0.28), (-0.2, 0.25, 0.28), 0.06, 0.07, 8, 'sometsuke', caps=(True, True))
        cy(m, (0.17, 0.22, 0.27), (0.17, 0.27, 0.27), 0.03, 0.03, 6, 'hakuji', caps=(True, True))
        for k in range(3):
            a = 0.6 + k * 2.1
            leaf(m, (0.17, 0.27, 0.27), a, 0.1, 0.02, 0.9, 'kyabetsu')
            ball(m, (0.17 + math.cos(a) * 0.03, 0.34 + 0.02 * k, 0.27 + math.sin(a) * 0.03), 0.016, ('konpeito', 'kinari', 'ame_y')[k], 4)
    return m


def hokora(lod):
    """祠：石の基壇 0.8 × 0.6 × 0.28＋木の社（幅 0.56、高 0.62、切妻の板屋根）＋小さな赤い鳥居（高 0.8）＋注連縄と紙垂。"""
    m = new('w9_hokora', lod, '祠：石の基壇＋木の社（切妻の板屋根）＋小さな赤鳥居＋注連縄と紙垂 3')
    obx(m, (0.0, 0.14, -0.05), (0.4, 0.14, 0.3), 'hagane', 0.85)
    for (mx, mz, mw) in ((-0.3, 0.27, 0.12), (0.22, 0.28, 0.15), (0.0, -0.3, 0.2)):
        obx(m, (mx, 0.03, mz), (mw, 0.03, 0.06), 'daikon_leaf', 0.75)
    bx(m, (-0.28, 0.28, -0.25), (0.28, 0.9, 0.12), AGED)
    stp(m, [(-0.2, 0.34, 0.121), (0.2, 0.34, 0.121), (0.2, 0.84, 0.121), (-0.2, 0.84, 0.121)], 'kokuyu', 0.6)
    wpo(m, [(-0.4, 0.88, 0.22), (0.4, 0.88, 0.22), (0.4, 1.12, -0.065), (-0.4, 1.12, -0.065)], WD, AGED, out=(0.0, 0.6, 0.5))
    wpo(m, [(-0.4, 1.12, -0.065), (0.4, 1.12, -0.065), (0.4, 0.88, -0.35), (-0.4, 0.88, -0.35)], WD, OLD, out=(0.0, 0.6, -0.5))
    bx(m, (-0.42, 1.1, -0.1), (0.42, 1.15, -0.03), DARK)
    stpo(m, [(0.4, 0.88, 0.22), (0.4, 0.88, -0.35), (0.4, 1.12, -0.065)], 'kakishibu', 0.7, out=(1.0, 0.0, 0.0))
    stpo(m, [(-0.4, 0.88, -0.35), (-0.4, 0.88, 0.22), (-0.4, 1.12, -0.065)], 'kakishibu', 0.7, out=(-1.0, 0.0, 0.0))
    seg = 6 if not lod else 4
    for x in (-0.3, 0.3):
        cy(m, (x, 0.0, 0.45), (x, 0.78, 0.45), 0.032, 0.03, seg, 'shuurushi', caps=(True, True))
    obx(m, (0.0, 0.76, 0.45), (0.42, 0.025, 0.025), 'shuurushi')
    obx(m, (0.0, 0.64, 0.45), (0.34, 0.018, 0.018), 'shuurushi')
    if not lod:
        cy(m, (-0.28, 0.7, 0.12), (0.28, 0.7, 0.12), 0.018, 0.018, 5, 'nawa', caps=(True, True))
        for x in (-0.18, 0.0, 0.18):
            stp2(m, [(x - 0.03, 0.7, 0.13), (x + 0.03, 0.7, 0.13), (x + 0.03, 0.58, 0.14), (x - 0.01, 0.58, 0.14), (x - 0.02, 0.52, 0.14)], 'hakuji')
    return m


# ───────────────────────── 商い（街） ─────────────────────────

def sugidama(lod):
    """杉玉（酒屋の印）：杉葉の球 Ø0.8（上は若い緑・下ほど枯れた茶の塊を球面に敷き詰めた「丸い玉」）＋吊り縄＋壁から出た腕木。原點＝壁面。玉の中心は高 2.3・壁から 0.85（庇の影から出す）。"""
    m = new('w9_sugidama', lod, '杉玉：杉葉の塊を球面に敷き詰めた丸い玉 Ø0.8（上は若い緑・下ほど枯れ茶）、壁から出た腕木と吊り縄。中心高 2.3、壁から 0.85')
    rng = random.Random(30601)
    m.beam((0.0, 2.95, 0.0), (0.0, 2.95, 0.9), 0.075, 0.07, WD, OLD)
    m.beam((0.0, 2.7, 0.04), (0.0, 2.95, 0.55), 0.045, 0.04, WD, OLD)
    cy(m, (0.0, 2.95, 0.85), (0.0, 2.72, 0.85), 0.012, 0.012, 4, 'nawa', caps=(False, False))
    # r2（2026-10-21 使用者「看不懂是什麼菱形的東西」）：旧版は 6 角の双角錐（ball＝菱形）の塊 40 個＋棘を若緑・黄緑・柿渋の 3 色で
    # 散らしていた → 遠目に多面体の宝石に読めた。実物の杉玉は刈り込んだ丸い杉葉の球で色はほぼ一色。
    # → 経緯の細かい球（半径 0.40・頂点を ±4 % 揺らして葉の凸凹）を深い杉緑（daikon_leaf × 0.70–0.78）一色で。下半球は少し暗く（陰）。
    #   LOD0 は表面に短い杉葉の毛羽 90 本（同じ緑・長さ 3.5 cm）で輪郭を柔らかくする（大きい塊や色の斑は作らない）。
    C, RB = (0.0, 2.3, 0.85), 0.40
    lat, lon = (14, 24) if not lod else (7, 12)
    grid = []
    for a in range(lat + 1):
        th = math.pi * a / lat
        row = []
        for b in range(lon):
            ph = 2 * math.pi * (b + (0.5 if a % 2 else 0.0)) / lon
            r = RB * (1.0 + (rng.uniform(-0.04, 0.04) if 0 < a < lat else 0.0))
            row.append(K.add(C, (r * math.sin(th) * math.cos(ph), r * math.cos(th), r * math.sin(th) * math.sin(ph))))
        grid.append(row)
    for a in range(lat):
        up = math.cos(math.pi * (a + 0.5) / lat)                                # 1＝上・−1＝下
        for b in range(lon):
            col = rng.uniform(0.70, 0.78) * (0.90 + 0.10 * up)
            p00, p01 = grid[a][b], grid[a][(b + 1) % lon]
            p10, p11 = grid[a + 1][b], grid[a + 1][(b + 1) % lon]
            if a == 0:
                stpo(m, [p00, p10, p11], 'daikon_leaf', col, ctr=C)
            elif a == lat - 1:
                stpo(m, [p00, p01, p10], 'daikon_leaf', col, ctr=C)
            else:
                stpo(m, [p00, p01, p11, p10], 'daikon_leaf', col, ctr=C)
    if not lod:
        n_t = 90
        for i in range(n_t):                                                    # 毛羽：黄金角の螺旋で球面に均等
            yy = 1.0 - 2.0 * (i + 0.5) / n_t
            rr = math.sqrt(max(0.0, 1.0 - yy * yy))
            ph = i * 2.399963
            d = (rr * math.cos(ph), yy, rr * math.sin(ph))
            cy(m, K.add(C, K.mul(d, RB * 0.96)), K.add(C, K.mul(d, RB + 0.035)), 0.026, 0.004, 3, 'daikon_leaf',
               caps=(False, False), col=rng.uniform(0.62, 0.72) * (0.90 + 0.10 * yy))
    return m


def kasa_dai(lod):
    """傘干し台（唐傘屋の店先）：竹の A 型の台 1.5 × 0.7 × 1.7、開いた唐傘 5（朱・藍・生成り・黄・渋）を掛け、閉じた傘 3 を立て掛ける。+z が外。"""
    m = new('w9_kasa_dai', lod, '傘干し台：竹の A 型の台 1.5 × 0.7 × 1.7、開いた唐傘 5（朱・藍・生成り・黄・渋）と閉じた傘 3')
    for x in (-0.72, 0.72):
        cy(m, (x, 0.0, -0.3), (x, 1.7, 0.0), 0.025, 0.02, 6, 'take', caps=(True, True))
        cy(m, (x, 0.0, 0.3), (x, 1.7, 0.0), 0.025, 0.02, 6, 'take', caps=(True, True))
    cy(m, (-0.8, 1.7, 0.0), (0.8, 1.7, 0.0), 0.022, 0.022, 6, 'take', caps=(True, True))
    cy(m, (-0.75, 0.9, -0.15), (0.75, 0.9, -0.15), 0.018, 0.018, 5, 'take', caps=(True, True))
    cy(m, (-0.75, 0.9, 0.15), (0.75, 0.9, 0.15), 0.018, 0.018, 5, 'take', caps=(True, True))
    keys = ['akachochin', 'ai', 'kinari', 'ame_y', 'kakishibu']
    sp = [(-0.6, 1.45, 0.32), (-0.3, 1.25, 0.34), (0.0, 1.45, 0.32), (0.3, 1.25, 0.34), (0.6, 1.45, 0.32)]
    seg = 12 if not lod else 8
    for i, (x, y, z) in enumerate(sp):
        top = (x, y + 0.2, z)
        rim_c = (x, y - 0.02, z + 0.18)
        r = 0.34
        rim = [(rim_c[0] + math.cos(2 * math.pi * k / seg) * r, rim_c[1] + math.sin(2 * math.pi * k / seg) * r * 0.5, rim_c[2] + math.sin(2 * math.pi * k / seg) * r * 0.5) for k in range(seg)]
        for k in range(seg):
            col = (0.95 if k % 2 else 0.82) * (1.0 if not lod else 0.9)
            stp2(m, [rim[k], rim[(k + 1) % seg], top], keys[i], col)
        if not lod:
            cy(m, top, (x, y - 0.22, z + 0.02), 0.01, 0.01, 4, 'take', caps=(False, True))
    for i, x in enumerate((-0.45, 0.0, 0.5)):
        cy(m, (x, 0.0, 0.5), (x + 0.05, 1.0, 0.18), 0.03, 0.045, 6, keys[(i + 1) % 5], caps=(True, True))
        cy(m, (x + 0.05, 1.0, 0.18), (x + 0.055, 1.12, 0.17), 0.05, 0.01, 6, 'kokuyu', caps=(False, True))
    return m


def zori_kake(lod):
    """草鞋掛け（草履屋）：二本脚の掛け竿 1.4 × 1.6 に、草鞋 10 足（二つずつ紐で結んで）と大きな藁の束を吊る。+z が外。"""
    m = new('w9_zori_kake', lod, '草鞋掛け：二本脚の掛け竿 1.4 × 1.6 に草鞋 10 足（二つずつ結んで、鼻緒つき）と藁の束 2')
    rng = random.Random(30603)
    for x in (-0.65, 0.65):
        cy(m, (x, 0.0, -0.18), (x, 1.62, 0.0), 0.025, 0.02, 6, 'take', caps=(True, True))
        cy(m, (x, 0.0, 0.18), (x, 1.62, 0.0), 0.025, 0.02, 6, 'take', caps=(True, True))
    cy(m, (-0.72, 1.6, 0.0), (0.72, 1.6, 0.0), 0.022, 0.022, 6, 'take', caps=(True, True))
    cy(m, (-0.72, 1.12, 0.0), (0.72, 1.12, 0.0), 0.018, 0.018, 5, 'take', caps=(True, True))
    n = 5 if not lod else 3
    for i in range(n):
        x = -0.5 + 1.0 * i / (n - 1)
        for yy in (1.58, 1.1):
            cy(m, (x, yy, 0.0), (x, yy - 0.2, 0.0), 0.006, 0.006, 3, 'nawa', caps=(False, False))
            for s_ in (-1, 1):
                cx = x + s_ * 0.075
                # 草鞋の本体：踵（下）が太く爪先（上）が細い厚み 3 cm の板。足の長さ 0.3 を縦に吊る
                top_y = yy - 0.2
                sole = [(cx - 0.055, top_y, 0.0), (cx + 0.055, top_y, 0.0), (cx + 0.07, top_y - 0.16, 0.0), (cx + 0.06, top_y - 0.31, 0.0), (cx, top_y - 0.35, 0.0), (cx - 0.06, top_y - 0.31, 0.0), (cx - 0.07, top_y - 0.16, 0.0)]
                col = rng.uniform(0.8, 1.0)
                stpo(m, [(p[0], p[1], p[2] + 0.015) for p in sole], 'wara', col, out=(0.0, 0.0, 1.0))
                stpo(m, [(p[0], p[1], p[2] - 0.015) for p in sole], 'wara', col * 0.8, out=(0.0, 0.0, -1.0))
                for a_, b_ in zip(sole, sole[1:] + sole[:1]):
                    stpo(m, [(a_[0], a_[1], a_[2] - 0.015), (b_[0], b_[1], b_[2] - 0.015), (b_[0], b_[1], b_[2] + 0.015), (a_[0], a_[1], a_[2] + 0.015)], 'wara', col * 0.65, ctr=(cx, top_y - 0.17, 0.0))
                # 鼻緒（朱）：爪先側の小さな三角
                stp2(m, [(cx - 0.05, top_y - 0.04, 0.02), (cx + 0.05, top_y - 0.04, 0.02), (cx, top_y - 0.12, 0.022)], 'shuurushi')
    if not lod:
        for x in (-0.4, 0.4):
            cy(m, (x, 0.02, 0.4), (x, 0.8, 0.38), 0.12, 0.09, 8, 'wara', caps=(True, True), col=0.95)
            cy(m, (x, 0.5, 0.4), (x, 0.52, 0.4), 0.125, 0.125, 8, 'nawa', caps=(False, False))
    return m


def zaru_kake(lod):
    """笊・籠の吊り棚（竹細工屋）：二本脚の棚 1.5 × 1.7 に、笊（浅い鉢）7・籠 3 を二段に吊る。+z が外。"""
    m = new('w9_zaru_kake', lod, '笊・籠の吊り棚：二本脚 1.5 × 1.7 に笊 7 と籠 3 を二段に吊る')
    rng = random.Random(30604)
    for x in (-0.7, 0.7):
        cy(m, (x, 0.0, -0.2), (x, 1.7, 0.0), 0.026, 0.02, 6, 'take', caps=(True, True))
        cy(m, (x, 0.0, 0.2), (x, 1.7, 0.0), 0.026, 0.02, 6, 'take', caps=(True, True))
    cy(m, (-0.78, 1.68, 0.0), (0.78, 1.68, 0.0), 0.022, 0.022, 6, 'take', caps=(True, True))
    cy(m, (-0.78, 0.98, 0.0), (0.78, 0.98, 0.0), 0.02, 0.02, 6, 'take', caps=(True, True))
    seg = 10 if not lod else 6
    for row, (yy, xs) in enumerate(((1.64, (-0.55, -0.18, 0.18, 0.55)), (0.94, (-0.4, 0.0, 0.4)))):
        for x in xs:
            r = 0.2 + rng.uniform(-0.03, 0.04)
            cy(m, (x, yy, 0.0), (x, yy - 0.12, 0.0), 0.005, 0.005, 3, 'nawa', caps=(False, False))
            c = (x, yy - 0.2, 0.04)
            ring = [(c[0] + math.cos(2 * math.pi * k / seg) * r, c[1] + math.sin(2 * math.pi * k / seg) * r, c[2] + 0.1) for k in range(seg)]
            apex = (c[0], c[1], c[2] - 0.02)
            for k in range(seg):
                stp2(m, [ring[k], ring[(k + 1) % seg], apex], 'take', rng.uniform(0.78, 1.0) * (0.86 if k % 2 else 1.0))
    if not lod:
        for x in (-0.55, 0.0, 0.55):
            cy(m, (x, 0.02, 0.45), (x, 0.42, 0.45), 0.14, 0.2, 8, 'take', caps=(True, False))
            cy(m, (x, 0.4, 0.45), (x, 0.43, 0.45), 0.205, 0.205, 8, 'nawa', caps=(False, False))
    return m


# ───────────────────────── 農村 ─────────────────────────

def kakashi(lod):
    """案山子：竹の十字（高 1.65、腕 1.16）に、藁（蓑）の胴＋藍染めの袖＋布の頭＋編み笠、足元の杭と縄。"""
    m = new('w9_kakashi', lod, '案山子：竹の十字（高 1.65／腕 1.16）に蓑の胴、藍の袖と布の頭、編み笠、足元の杭と縄')
    cy(m, (0.0, 0.0, 0.0), (0.0, 1.65, 0.0), 0.028, 0.024, 6, 'take', caps=(True, True))
    cy(m, (-0.58, 1.22, 0.0), (0.58, 1.18, 0.0), 0.022, 0.022, 6, 'take', caps=(True, True))
    seg = 8 if not lod else 5
    cy(m, (0.0, 0.78, 0.0), (0.0, 1.3, 0.0), 0.2, 0.15, seg, 'mino', caps=(False, False), col=0.95)
    cy(m, (0.0, 0.55, 0.0), (0.0, 0.8, 0.0), 0.26, 0.2, seg, 'mino', caps=(False, True), col=0.85)
    for s in (-1, 1):
        stp2(m, [(s * 0.1, 1.28, 0.02), (s * 0.55, 1.26, 0.02), (s * 0.5, 1.07, 0.03), (s * 0.12, 1.0, 0.03)], 'ai', 0.9)
    ball(m, (0.0, 1.46, 0.02), 0.12, 'kinari', 8 if not lod else 5, 0.95)
    cone(m, (0.0, 1.78, 0.0), (0.0, 1.55, 0.0), 0.3, 10 if not lod else 6, 'wara', 0.95)
    if not lod:
        for x in (-0.04, 0.04):
            stp(m, [(x - 0.012, 1.48, 0.134), (x + 0.012, 1.48, 0.134), (x + 0.012, 1.5, 0.134), (x - 0.012, 1.5, 0.134)], 'sumi')
        stp(m, [(-0.04, 1.42, 0.134), (0.04, 1.42, 0.134), (0.04, 1.435, 0.134), (-0.04, 1.435, 0.134)], 'sumi')
        for k in range(12):
            a = 2 * math.pi * k / 12
            base = (math.cos(a) * 0.24, 0.58, math.sin(a) * 0.24)
            leaf(m, base, a, 0.18, 0.025, -1.2, 'mino', 0.8)
        cy(m, (0.35, 0.0, 0.18), (0.35, 0.5, 0.18), 0.02, 0.02, 5, 'take', caps=(True, True))
        cy(m, (0.0, 0.1, 0.0), (0.35, 0.3, 0.18), 0.007, 0.007, 3, 'nawa', caps=(False, False))
    return m


def hana_clump(lod, kind):
    """野花の株（直径 0.5）：茎 12–16 本に花。higanbana＝紅の彼岸花（細長い 6 弁が反る）／kiiro＝黄／shiro＝白の野菊／pink＝コスモス。"""
    name = 'w9_hana_' + kind
    m = new(name, lod, '野花の株 Ø0.5（%s）' % kind)
    rng = random.Random({'higanbana': 30801, 'kiiro': 30802, 'shiro': 30803, 'pink': 30804}[kind])
    n = (14 if kind == 'higanbana' else 12) if not lod else 6
    for i in range(n):
        a = rng.uniform(0, 2 * math.pi)
        r = math.sqrt(rng.random()) * 0.22
        bx0, bz0 = math.cos(a) * r, math.sin(a) * r
        if kind == 'higanbana':
            h = rng.uniform(0.38, 0.55)
            lean = (rng.uniform(-0.04, 0.04), rng.uniform(-0.04, 0.04))
            top = (bx0 + lean[0], h, bz0 + lean[1])
            cy(m, (bx0, 0.0, bz0), top, 0.006, 0.004, 4, 'take_ao', caps=(False, True))
            npet = 6 if not lod else 4
            for k in range(npet):
                ang = 2 * math.pi * k / npet + rng.uniform(-0.2, 0.2)
                d = (math.cos(ang), 0.0, math.sin(ang))
                p1 = (top[0] + d[0] * 0.07, top[1] + 0.05, top[2] + d[2] * 0.07)
                p2 = (top[0] + d[0] * 0.11, top[1] + 0.03, top[2] + d[2] * 0.11)
                s = (-d[2] * 0.008, 0.0, d[0] * 0.008)
                stp2(m, [K.sub(top, s), K.add(top, s), K.add(p1, s), K.add(p2, K.mul(s, 0.4)), K.sub(p1, s)], 'akachochin' if k % 2 else 'mousen', rng.uniform(0.9, 1.0))
        else:
            h = rng.uniform(0.22, 0.42)
            top = (bx0, h, bz0)
            cy(m, (bx0, 0.0, bz0), top, 0.004, 0.003, 4, 'take_ao', caps=(False, True))
            if not lod:
                leaf(m, (bx0, 0.05, bz0), rng.uniform(0, 6.28), 0.1, 0.02, 0.5, 'kyabetsu')
            key = {'kiiro': 'ame_y', 'shiro': 'kinari', 'pink': 'konpeito'}[kind]
            np_ = 5 if kind != 'pink' else 8
            if lod:
                np_ = 4
            R = 0.04 if kind != 'pink' else 0.05
            ring = [(top[0] + math.cos(2 * math.pi * k / np_) * R, top[1] + 0.01, top[2] + math.sin(2 * math.pi * k / np_) * R) for k in range(np_)]
            for k in range(np_):
                stp2(m, [top, ring[k], ring[(k + 1) % np_]], key, rng.uniform(0.9, 1.0))
    return m


def build_all():
    for lod in (0, 1):
        itabei(lod, 'a')
        itabei(lod, 'b')
        takegaki(lod)
        kido(lod)
        a_ = shita(lod, 'w')
        b_ = shita(lod, 't')
        sfx = '_l1' if lod else ''
        mirror_x(a_, 'w9_shita_wood_m' + sfx, '下屋・薪小屋の左右反転（開いた側／板壁の側が逆）')
        mirror_x(b_, 'w9_shita_tool_m' + sfx, '下屋・農具小屋の左右反転')
        tsurushi_kaki(lod)
        kaki_dai(lod)
        tsurushi_togarashi(lod)
        sudare(lod)
        ueki_tana(lod)
        asagao(lod)
        jizo(lod)
        hokora(lod)
        sugidama(lod)
        kasa_dai(lod)
        zori_kake(lod)
        zaru_kake(lod)
        kakashi(lod)
        for kd in ('higanbana', 'kiiro', 'shiro', 'pink'):
            hana_clump(lod, kd)


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
    K.export_glb(bpy, OUT + '/src/w9_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_w9_kit.py 產生；Godot 端 tools/p13/w9/w9_kit_prefab.gd 讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[W9KIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/w9_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[W9KIT]   %-24s %5d 面  LOD1 %4d  dims %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims']))


main()
