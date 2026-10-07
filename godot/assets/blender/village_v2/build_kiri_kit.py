"""人間之里 V2 P9 R4-8：霧雨店周邊 奇物雜貨店＋魔法材料工作坊 Kit（kiri_kit）— 新資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_kiri_kit.py

讀感：「東西很多、類型很雜、有人在分類・曬乾・搬運・研究」——普通の雜貨屋ではない（5–10 m で分かる 3 つの印：
藥草・茸の干し棚／奇石・鉱物の棚／箒＋瓶の作業角）。
材質：V2_Wood・V2_Stone（_matlib）、SK_School（R4-3 已核准 atlas：稲藁＝箒の穂・籠・笊・縄・麻袋、和紙＝帳面・頁・札，只讀）、
V2_Kirisame（霧雨店 Hero atlas の非發光色票：紫・藍・緑・金・赤茶・生成り・茶・近黑、魔女の楕円札 region，只讀；
「魔」提燈・硝子 region は發光するので使わない）。霧雨店 Hero 本體（P5 R2）不動。
座標：Godot（x 右、y 上、+z 前）；原點＝接地點（y 0）；單位 m。
  門前（控えめ）：kr_fuda_ma 魔女の楕円札の立て札／kr_hako_ishi 奇石を盛った開け箱／kr_kago 茸を盛った籠／kr_bin 瓶と壺の小台
  側院（作業場）：kr_hoshidana 藥草・茸の干し棚（印 1）／kr_ishidana 奇石・鉱物の棚（印 2）／kr_sagyo 作業台（薬研・開いた帳面・瓶）＋
                  kr_houki 壁に立て掛けた箒（印 3）／kr_nawa 縄の束
  後院（倉庫・やや乱雜）：kr_hakozumi 積んだ材料箱／kr_fukuro 麻袋 3／kr_akibin 空き瓶の箱／kr_zaimoku 板材の山／kr_furudana 古い棚
  搬運：kr_kuruma 大八車／kr_ni 荷（菰包み＋風呂敷）／kr_okeyama 桶の積み出し
  植生（材料にもなる雜草）：kr_yakuso 藥草の株（花つき）／kr_kinoko 茸の群れ
  *_l1         LOD1
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/kiri_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
KRA = K.load_json(G + '/assets/village_v2/kirisame/atlas.json')
SWATCH = {k: v['uv'] for k, v in KRA['swatches'].items()}
AT = K.load_json(G + '/assets/village_v2/school_kit/atlas.json')['regions']
WD = 'V2_Wood'
ST = 'V2_Stone'
KR = 'V2_Kirisame'
SK = 'SK_School'
MATS = [WD, ST, KR, SK]
TILE = {WD: ML['V2_Wood']['tile_m'], ST: ML['V2_Stone']['tile_m'], KR: 1.0, SK: 1.0}

WOODC = (0.84, 0.78, 0.68)
AGED = (0.66, 0.62, 0.56)
OLD = (0.50, 0.47, 0.42)
DARK = (0.30, 0.26, 0.22)
ROPE = (0.60, 0.52, 0.38)
STRAW = (0.84, 0.76, 0.60)
SACK = (0.66, 0.56, 0.42)
STRAW_RG = AT['straw']
PAPER_RG = AT['paper']
PAPER = 0.30

MODS = {}
INFO = {}


def new(name, note=''):
    m = K.Mesh(name, MATS, TILE)
    MODS[name] = m
    INFO[name] = note
    return m


def sw(hexcol):
    u, v = SWATCH[hexcol]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


LAV = '#B7A6C9'
INDIGO = '#3A5F6E'
GREEN = '#4B6B45'
GOLD = '#C9A24A'
RED = '#8E3B2C'
CREAM = '#D8CFB8'
BROWN = '#7A5A36'
BLACK = '#1E1B18'


def board(m, lo, hi, col=WOODC):
    m.box(lo, hi, WD, col)


def oke(m, x, y, z, r0, r1, h, lod):
    seg = 10 if lod else 16
    m.cyl((x, y, z), (x, y + h, z), r0, r1, seg, WD, AGED, caps=(True, False))
    m.cyl((x, y + h, z), (x, y + h - 0.03, z), r1, r1 - 0.012, seg, WD, AGED, caps=(False, False))
    m.cyl((x, y + h - 0.031, z), (x, y + h - 0.03, z), r1 - 0.012, r1 - 0.012, seg, WD, DARK, caps=(False, True))
    if not lod:
        for t in (0.18, 0.78):
            yy = y + h * t
            rr = r0 + (r1 - r0) * t + 0.006
            m.cyl((x, yy - 0.015, z), (x, yy + 0.015, z), rr, rr, seg, KR, 1.0, caps=(False, False), uv_atlas=sw(BLACK))


def bottle(m, x, y, z, r, h, col, lod, cork=True):
    """瓶：胴＋肩＋首＋栓（色票）。"""
    seg = 6 if lod else 10
    m.cyl((x, y, z), (x, y + h * 0.62, z), r, r, seg, KR, 1.0, caps=(True, False), uv_atlas=sw(col))
    m.cyl((x, y + h * 0.62, z), (x, y + h * 0.80, z), r, r * 0.38, seg, KR, 1.0, caps=(False, False), uv_atlas=sw(col))
    m.cyl((x, y + h * 0.80, z), (x, y + h * 0.95, z), r * 0.36, r * 0.36, seg, KR, 1.0, caps=(False, True), uv_atlas=sw(col))
    if cork and not lod:
        m.cyl((x, y + h * 0.95, z), (x, y + h * 1.02, z), r * 0.30, r * 0.33, 6, KR, 1.0, caps=(False, True), uv_atlas=sw(BROWN))


def jar(m, x, y, z, r, h, col, lod):
    """壺：胴が膨らむ＋口。"""
    seg = 8 if lod else 12
    m.cyl((x, y, z), (x, y + h * 0.55, z), r * 0.75, r, seg, KR, 1.0, caps=(True, False), uv_atlas=sw(col))
    m.cyl((x, y + h * 0.55, z), (x, y + h * 0.9, z), r, r * 0.55, seg, KR, 1.0, caps=(False, False), uv_atlas=sw(col))
    m.cyl((x, y + h * 0.9, z), (x, y + h, z), r * 0.58, r * 0.58, seg, KR, 1.0, caps=(False, True), uv_atlas=sw(col))


def crystal(m, x, y, z, r, h, col, tilt=(0.0, 0.0), lod=0):
    """六角柱の結晶（先端は尖る）。tilt＝(x, z) 方向の傾き。"""
    top = (x + tilt[0] * h, y + h, z + tilt[1] * h)
    mid = (x + tilt[0] * h * 0.75, y + h * 0.75, z + tilt[1] * h * 0.75)
    m.cyl((x, y, z), mid, r, r, 6, KR, 1.0, caps=(False, False), uv_atlas=sw(col))
    m.cyl(mid, top, r, 0.002, 6, KR, 1.0, caps=(False, False), uv_atlas=sw(col))


def rock(m, c, h, rng, col=(0.72, 0.70, 0.66), mat=ST):
    """不規則な石：6 角の錐台（底広・頂狭）を傾け、ひしゃげさせる。c＝中心、h＝(半幅, 半高, 半奥)。"""
    seg = 6
    ph = rng.uniform(0, math.pi)
    tl = (rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25))
    x, y, z = c
    rx, ry, rz = h
    b0 = [(x + rx * math.cos(ph + 2 * math.pi * i / seg) * rng.uniform(0.8, 1.15), y - ry,
           z + rz * math.sin(ph + 2 * math.pi * i / seg) * rng.uniform(0.8, 1.15)) for i in range(seg)]
    t0 = [(x + tl[0] * ry + rx * 0.55 * math.cos(ph + 0.4 + 2 * math.pi * i / seg) * rng.uniform(0.7, 1.1), y + ry * rng.uniform(0.75, 1.0),
           z + tl[1] * ry + rz * 0.55 * math.sin(ph + 0.4 + 2 * math.pi * i / seg) * rng.uniform(0.7, 1.1)) for i in range(seg)]
    for i in range(seg):
        j = (i + 1) % seg
        m.poly([b0[i], b0[j], t0[j], t0[i]][::-1], mat, col)
    m.poly(t0[::-1], mat, col)
    m.poly(b0, mat, col)


def mushroom(m, x, y, z, r, h, cap, lod, lean=(0.0, 0.0)):
    seg = 5 if lod else 8
    top = (x + lean[0], y + h, z + lean[1])
    m.cyl((x, y, z), top, r * 0.28, r * 0.24, seg, KR, 1.0, caps=(False, False), uv_atlas=sw(CREAM))
    m.cyl((top[0], top[1] - r * 0.15, top[2]), (top[0], top[1] + r * 0.35, top[2]), r, r * 0.45, seg, KR, 1.0, caps=(True, False),
          uv_atlas=sw(cap))
    m.cyl((top[0], top[1] + r * 0.35, top[2]), (top[0], top[1] + r * 0.5, top[2]), r * 0.45, 0.003, seg, KR, 1.0, caps=(False, False),
          uv_atlas=sw(cap))


FLOWERS_RG = KRA['regions']['flowers']


def strand(m, top, bot, w0, w1, mat, rg, col):
    """垂れる葉の房 1 本：top→bot の細い面を 2 枚交差、両面。"""
    d = K.norm(K.sub(bot, top))
    for side in ((1.0, 0.0, 0.0), (0.0, 0.0, 1.0)):
        s = K.norm(K.sub(side, K.mul(d, K.dot(side, d))))
        q = [K.add(top, K.mul(s, -w0)), K.add(top, K.mul(s, w0)), K.add(bot, K.mul(s, w1)), K.add(bot, K.mul(s, -w1))]
        m.rect_uv(q[3], q[2], q[1], q[0], mat, rg, col)
        m.rect_uv(q[2], q[3], q[0], q[1], mat, rg, col)


def herb_bundle(m, x, ytop, z, length, rng, lod, flower=None):
    """吊るした藥草の束（逆さ吊り）：縄の結び目から茎が束になって下り、途中から葉・花の房が外へ跳ねて垂れる。
    房 4–9 本、二段に折れる（束→外へ）、長さ・色ばらばら（乾いた金・茶・緑、花つきは atlas の花 region）。"""
    m.cyl((x, ytop + 0.02, z), (x, ytop - 0.08, z), 0.018, 0.018, 5, SK, ROPE, caps=(False, False), uv_atlas=STRAW_RG)
    n = 4 if lod else 7
    tones = [GOLD, BROWN, GREEN] if rng.random() < 0.5 else [GREEN, GOLD, BROWN]
    for k in range(n):
        a = 2 * math.pi * k / n + rng.uniform(-0.6, 0.6)
        L = length * rng.uniform(0.5, 1.15)
        top = (x + 0.01 * math.cos(a), ytop - 0.07, z + 0.01 * math.sin(a))
        # 茎は束のまま少し下り、外へ跳ねてから垂れる（3 段）；房の先は 2 つに割れる
        mid = (x + 0.05 * math.cos(a), ytop - 0.07 - L * 0.30, z + 0.05 * math.sin(a))
        sp = rng.uniform(0.12, 0.22)
        knee = (x + sp * math.cos(a), ytop - 0.07 - L * 0.62, z + sp * math.sin(a))
        rg = FLOWERS_RG if (flower and k % 3 == 0) else sw(tones[k % 3])
        strand(m, top, mid, 0.006, 0.01, KR, sw(BROWN), 1.0)
        strand(m, mid, knee, 0.012, rng.uniform(0.022, 0.032), KR, rg, 1.0)
        if not lod:
            for t in (-0.5, 0.5):
                b2 = (knee[0] + 0.04 * math.cos(a + t), knee[1] - L * rng.uniform(0.25, 0.45), knee[2] + 0.04 * math.sin(a + t))
                strand(m, knee, b2, 0.016, 0.006, KR, rg, 1.0)


def zaru_tray(m, x, y, z, r, lod):
    seg = 8 if lod else 14
    m.cyl((x, y, z), (x, y + 0.05, z), r * 0.85, r, seg, SK, STRAW, caps=(True, False), uv_atlas=STRAW_RG)
    m.cyl((x, y + 0.012, z), (x, y + 0.013, z), r * 0.85, r * 0.85, seg, SK, (0.74, 0.66, 0.50), caps=(False, True), uv_atlas=STRAW_RG)


def crate(m, c, w, d, h, rot, col=AGED, open_top=True):
    """木箱（rot＝y 回轉）：底＋側板 4（open_top=False で蓋、開けは中に暗い面）。"""
    x, y, z = c
    t = 0.022
    ax = (math.cos(rot), 0.0, -math.sin(rot))
    az = (math.sin(rot), 0.0, math.cos(rot))
    ay = (0.0, 1.0, 0.0)

    def P(lx, ly, lz):
        return (x + ax[0] * lx + az[0] * lz, y + ly, z + ax[2] * lx + az[2] * lz)
    m.obox(P(0, t / 2, 0), (w / 2, t / 2, d / 2), WD, col, ax=ax, ay=ay, az=az)
    for s in (-1, 1):
        m.obox(P(s * (w / 2 - t / 2), h / 2, 0), (t / 2, h / 2, d / 2), WD, col, ax=ax, ay=ay, az=az)
        m.obox(P(0, h / 2, s * (d / 2 - t / 2)), (w / 2 - t, h / 2, t / 2), WD, col, ax=ax, ay=ay, az=az)
    if not open_top:
        m.obox(P(0, h - t / 2, 0), (w / 2, t / 2, d / 2), WD, col, ax=ax, ay=ay, az=az)
    else:
        m.obox(P(0, h * 0.7, 0), (w / 2 - t, 0.002, d / 2 - t), WD, DARK, ax=ax, ay=ay, az=az)


# ─────────────────────────── 門前 ───────────────────────────

def fuda_ma(name, lod):
    m = new(name + ('_l1' if lod else ''), '魔女の楕円札の立て札：柱 1.30（埋 0.25）＋腕木＋楕円札 0.56 × 0.40（Hero の oval_ma region）＋和紙の小札')
    board(m, (-0.035, -0.25, -0.035), (0.035, 1.30, 0.035), AGED)
    board(m, (-0.03, 1.22, -0.03), (0.42, 1.27, 0.03), AGED)
    ox, oy = 0.24, 0.88
    n = 10 if lod else 16
    u0, v0, u1, v1 = KRA['regions']['oval_ma']
    for s in (1, -1):
        zz = 0.012 * s
        pts = [(ox + 0.28 * math.cos(2 * math.pi * i / n), oy + 0.20 * math.sin(2 * math.pi * i / n)) for i in range(n)]
        if s < 0:
            pts = pts[::-1]
        uvs = [(u0 + (u1 - u0) * (0.5 + 0.5 * s * (p[0] - ox) / 0.28), v0 + (v1 - v0) * (0.5 - 0.5 * (p[1] - oy) / 0.20)) for p in pts]
        m.face(m.verts([(p[0], p[1], zz) for p in pts]), KR, uvs, 1.0)
    for x in (0.10, 0.38):
        m.beam((x, 1.22, 0.0), (x, oy + 0.17, 0.0), 0.007, 0.007, WD, DARK)
    m.rect_uv((-0.09, 0.32, 0.032), (0.09, 0.32, 0.032), (0.09, 0.58, 0.032), (-0.09, 0.58, 0.032), SK, PAPER_RG, PAPER)
    return m


def hako_ishi(name, lod):
    m = new(name + ('_l1' if lod else ''), '奇石を盛った開け箱 0.56 × 0.38 × 0.26：灰・緑・金の石＋紫・藍の結晶')
    crate(m, (0, 0, 0), 0.56, 0.38, 0.26, 0.0, AGED)
    rng = random.Random(4801)
    cols = [(0.72, 0.70, 0.66), (0.55, 0.62, 0.52), (0.80, 0.70, 0.45), (0.60, 0.58, 0.60)]
    for i in range(7 if not lod else 4):
        x = rng.uniform(-0.19, 0.19)
        z = rng.uniform(-0.11, 0.11)
        s = rng.uniform(0.05, 0.08)
        rock(m, (x, 0.20 + s * 0.6, z), (s, s * 0.7, s * 0.85), rng, cols[i % 4])
    crystal(m, 0.08, 0.20, 0.02, 0.05, 0.34, LAV, (0.25, 0.1), lod)
    crystal(m, 0.15, 0.20, -0.05, 0.04, 0.24, LAV, (0.45, -0.2), lod)
    crystal(m, -0.12, 0.21, 0.05, 0.035, 0.2, INDIGO, (-0.3, 0.2), lod)
    crystal(m, 0.0, 0.21, -0.06, 0.03, 0.16, LAV, (-0.1, -0.4), lod)
    return m


def kago(name, lod):
    m = new(name + ('_l1' if lod else ''), '茸を盛った籠 Ø0.40 × 0.26（赤茶・生成り・紫の傘）＋金の持ち手')
    seg = 8 if lod else 14
    r, h = 0.20, 0.26
    m.cyl((0, 0.0, 0), (0, h, 0), r * 0.80, r, seg, SK, STRAW, caps=(True, False), uv_atlas=STRAW_RG)
    m.cyl((0, h * 0.75, 0), (0, h * 0.75 + 0.001, 0), r * 0.94, r * 0.94, seg, SK, (0.42, 0.37, 0.28), caps=(False, True), uv_atlas=STRAW_RG)
    if not lod:
        m.cyl((0, h - 0.012, 0), (0, h + 0.012, 0), r + 0.01, r + 0.01, seg, KR, 1.0, caps=(False, False), uv_atlas=sw(GOLD))
        for a, b in (((-r, h, 0), (-r * 0.4, h + 0.20, 0)), ((-r * 0.4, h + 0.20, 0), (r * 0.4, h + 0.20, 0)), ((r * 0.4, h + 0.20, 0), (r, h, 0))):
            m.cyl(a, b, 0.012, 0.012, 5, KR, 1.0, caps=(False, False), uv_atlas=sw(GOLD))
    rng = random.Random(4802)
    for i in range(9 if not lod else 5):
        a = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(0.0, 0.13)
        cap = [RED, RED, CREAM, LAV, BROWN][i % 5]
        mushroom(m, rr * math.cos(a), h * 0.72, rr * math.sin(a), rng.uniform(0.035, 0.055), rng.uniform(0.04, 0.08), cap, lod,
                 (rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02)))
    return m


def bin_dai(name, lod):
    m = new(name + ('_l1' if lod else ''), '瓶と壺の小台：台 0.44 × 0.30 × 0.32 ＋瓶 4–5（緑・藍・茶・紫）＋壺 1（生成り）')
    board(m, (-0.22, 0.29, -0.15), (0.22, 0.32, 0.15), WOODC)
    for x in (-0.18, 0.18):
        for z in (-0.11, 0.11):
            board(m, (x - 0.02, 0.0, z - 0.02), (x + 0.02, 0.29, z + 0.02), AGED)
    bottle(m, -0.13, 0.32, -0.04, 0.045, 0.24, GREEN, lod)
    bottle(m, -0.03, 0.32, 0.06, 0.035, 0.19, INDIGO, lod)
    bottle(m, 0.07, 0.32, -0.06, 0.04, 0.27, BROWN, lod)
    jar(m, 0.15, 0.32, 0.06, 0.055, 0.15, CREAM, lod)
    if not lod:
        bottle(m, 0.03, 0.32, 0.09, 0.025, 0.13, LAV, lod)
    return m


# ─────────────────────────── 側院（作業場） ───────────────────────────

def hoshidana(name, lod):
    m = new(name + ('_l1' if lod else ''), '藥草・茸の干し棚：A 字脚 2（1.90）＋竹竿 2 段（2.3 m）、吊るし束 11＋茸の連、下段に笊 2（干し茸）')
    rng = random.Random(4803)
    H = 1.90
    for x in (-1.05, 1.05):
        for s in (-1, 1):
            m.beam((x, H, 0.0), (x + rng.uniform(-0.02, 0.02), 0.0, s * 0.44), 0.06, 0.06, WD, AGED)
        board(m, (x - 0.03, 0.70, -0.24), (x + 0.03, 0.75, 0.24), AGED)
    m.cyl((-1.18, H - 0.03, 0.0), (1.18, H - 0.03, 0.0), 0.025, 0.025, 6, KR, 1.0, uv_atlas=sw(GOLD))
    m.cyl((-1.12, 1.40, 0.10), (1.12, 1.40, 0.10), 0.02, 0.02, 6, KR, 1.0, uv_atlas=sw(GOLD))
    for x in (-1.05, 1.05):
        m.beam((x, 1.40, 0.0), (x, 1.40, 0.13), 0.04, 0.04, WD, DARK)
    for z in (-0.20, 0.20):
        m.cyl((-1.05, 0.77, z), (1.05, 0.77, z), 0.018, 0.018, 6, KR, 1.0, uv_atlas=sw(GOLD))
    for x0 in (-0.48, 0.42):
        for dx in (-0.2, 0.2):
            board(m, (x0 + dx - 0.03, 0.77, -0.22), (x0 + dx + 0.03, 0.795, 0.22), AGED)
        zaru_tray(m, x0, 0.795, 0.0, 0.30, lod)
        for k in range(7 if not lod else 3):
            a = rng.uniform(0, 2 * math.pi)
            rr = rng.uniform(0.0, 0.2)
            mushroom(m, x0 + rr * math.cos(a), 0.80, rr * math.sin(a), rng.uniform(0.035, 0.05), 0.025, [BROWN, RED, CREAM][k % 3], lod)
    for i in range(6):
        x = -0.95 + i * 0.36 + rng.uniform(-0.05, 0.05)
        herb_bundle(m, x, H - 0.05, 0.0, rng.uniform(0.40, 0.58), rng, lod, [None, True, None, True][i % 4])
    for i in range(3):
        x = -0.62 + i * 0.55 + rng.uniform(-0.05, 0.05)
        herb_bundle(m, x, 1.37, 0.10, rng.uniform(0.30, 0.42), rng, lod, [True, None, None, True][i])
    if not lod:
        xs = 0.86
        m.cyl((xs, H - 0.05, 0.0), (xs, 1.05, 0.0), 0.006, 0.006, 4, SK, ROPE, caps=(False, False), uv_atlas=STRAW_RG)
        for k in range(6):
            y = H - 0.15 - k * 0.12
            m.cyl((xs, y - 0.02, 0.0), (xs, y + 0.02, 0.0), 0.045, 0.03, 7, KR, 1.0, uv_atlas=sw([BROWN, RED][k % 2]))
    return m


def ishidana(name, lod):
    m = new(name + ('_l1' if lod else ''), '奇石・鉱物の棚：1.30 × 0.38 × 1.30、3 段（原石・金の鉱石／紫・藍の結晶群／壺・瓶・木片・帳面）＋足元の大きな奇石')
    W, D = 1.30, 0.38
    for x in (-W / 2 + 0.03, W / 2 - 0.03):
        board(m, (x - 0.03, 0.0, -D / 2), (x + 0.03, 1.30, D / 2), AGED)
    for y in (0.08, 0.50, 0.92, 1.28):
        board(m, (-W / 2 + 0.06, y - 0.025, -D / 2), (W / 2 - 0.06, y, D / 2), WOODC)
    board(m, (-W / 2, 0.0, -D / 2), (W / 2, 1.30, -D / 2 + 0.015), OLD)
    rng = random.Random(4804)
    for i in range(5 if not lod else 3):
        x = -0.48 + i * 0.24
        s = rng.uniform(0.06, 0.09)
        rock(m, (x, 0.08 + s * 0.6, rng.uniform(-0.06, 0.06)), (s, s * 0.65, s * 0.8), rng,
             [(0.70, 0.68, 0.64), (0.82, 0.68, 0.38), (0.56, 0.60, 0.54)][i % 3])
    for cx, col in ((-0.38, LAV), (0.05, INDIGO), (0.38, LAV)):
        rock(m, (cx, 0.53, 0.0), (0.09, 0.03, 0.07), rng, (0.62, 0.60, 0.60))
        for k in range(4 if not lod else 2):
            crystal(m, cx + rng.uniform(-0.06, 0.06), 0.53, rng.uniform(-0.05, 0.05), rng.uniform(0.032, 0.05), rng.uniform(0.2, 0.34),
                    col, (rng.uniform(-0.35, 0.35), rng.uniform(-0.25, 0.25)), lod)
    jar(m, -0.42, 0.92, 0.0, 0.07, 0.20, BROWN, lod)
    bottle(m, -0.22, 0.92, 0.05, 0.04, 0.22, GREEN, lod)
    bottle(m, -0.12, 0.92, -0.04, 0.035, 0.17, INDIGO, lod)
    for k in range(3):
        board(m, (0.12 + k * 0.06 - 0.025, 0.92, -0.12), (0.12 + k * 0.06 + 0.025, 1.00, 0.12), [AGED, DARK, WOODC][k])
    m.abox((0.42, 0.95, 0.02), (0.12, 0.03, 0.09), SK, {'*': PAPER_RG}, PAPER)
    rock(m, (0.82, 0.16, 0.10), (0.17, 0.16, 0.14), rng, (0.58, 0.56, 0.58))
    for k in range(4):
        crystal(m, 0.78 + k * 0.05, 0.24, 0.10 - k * 0.04, 0.045, 0.34 - k * 0.06, [LAV, LAV, INDIGO, LAV][k], (0.35 - k * 0.22, 0.25), lod)
    return m


def yagen(m, x, y, z, rot, lod):
    """薬研：舟形の臼（長 0.46、両端が反る V 溝の側板 2＋台）＋溝に立つ車輪 Ø0.22＋左右へ張り出す握り軸。"""
    ax = (math.cos(rot), 0.0, -math.sin(rot))
    az = (math.sin(rot), 0.0, math.cos(rot))
    up = (0.0, 1.0, 0.0)
    IRON = (0.36, 0.34, 0.33)

    def P(lx, ly, lz):
        return (x + ax[0] * lx + az[0] * lz, y + ly, z + ax[2] * lx + az[2] * lz)
    m.obox(P(0, 0.02, 0), (0.20, 0.02, 0.07), WD, DARK, ax=ax, ay=up, az=az)
    for s in (-1, 1):
        n = K.norm(K.add(K.mul(az, -s), K.mul(up, 0.9)))
        m.obox(P(0, 0.075, s * 0.045), (0.23, 0.012, 0.05), ST, IRON, ax=ax, ay=n, az=K.norm(K.cross(ax, n)))
    for e in (-1, 1):
        m.obox(P(e * 0.23, 0.08, 0), (0.025, 0.05, 0.075), ST, IRON, ax=ax, ay=up, az=az)
    c = P(0.04, 0.12, 0)
    m.cyl(K.sub(c, K.mul(az, 0.015)), K.add(c, K.mul(az, 0.015)), 0.11, 0.11, 10 if lod else 16, ST, (0.30, 0.29, 0.28))
    m.cyl(K.sub(c, K.mul(az, 0.17)), K.add(c, K.mul(az, 0.17)), 0.014, 0.014, 6, WD, AGED)
    for s in (-1, 1):
        h0 = K.add(c, K.mul(az, s * 0.17))
        m.cyl(h0, K.add(h0, K.mul(az, s * 0.06)), 0.022, 0.022, 6, WD, DARK)


def sagyo(name, lod):
    m = new(name + ('_l1' if lod else ''), '作業台 1.15 × 0.50 × 0.66：薬研・開いた帳面・紙束・巻物・瓶 3・紫の粉の鉢、下に奇石の材料箱')
    L, Dp, H = 1.15, 0.50, 0.66
    board(m, (-L / 2, H - 0.04, -Dp / 2), (L / 2, H, Dp / 2), WOODC)
    for x in (-L / 2 + 0.05, L / 2 - 0.05):
        for z in (-Dp / 2 + 0.05, Dp / 2 - 0.05):
            board(m, (x - 0.03, 0.0, z - 0.03), (x + 0.03, H - 0.04, z + 0.03), AGED)
    board(m, (-L / 2 + 0.05, 0.14, -Dp / 2 + 0.03), (L / 2 - 0.05, 0.17, Dp / 2 - 0.03), AGED)
    yagen(m, -0.27, H, 0.04, 0.12, lod)
    m.abox((0.12, H + 0.004, 0.0), (0.215, 0.004, 0.10), KR, {'*': sw(RED)}, 1.0)
    for s in (-1, 1):
        cx = 0.12 + s * 0.105
        m.rect_uv((cx - 0.10, H + 0.010, 0.085), (cx + 0.10, H + 0.010, 0.085), (cx + 0.10, H + 0.010, -0.085),
                  (cx - 0.10, H + 0.010, -0.085), SK, PAPER_RG, PAPER + 0.05)
    m.abox((0.42, H + 0.03, -0.14), (0.10, 0.03, 0.07), SK, {'*': PAPER_RG}, PAPER)
    m.cyl((0.30, H + 0.025, 0.17), (0.48, H + 0.025, 0.15), 0.022, 0.022, 6, SK, PAPER, uv_atlas=PAPER_RG)
    bottle(m, 0.50, H, 0.06, 0.035, 0.20, GREEN, lod)
    bottle(m, -0.05, H, -0.18, 0.03, 0.16, INDIGO, lod)
    jar(m, -0.50, H, -0.15, 0.05, 0.12, CREAM, lod)
    m.cyl((-0.10, H, 0.16), (-0.10, H + 0.05, 0.16), 0.05, 0.075, 10, KR, 1.0, caps=(True, False), uv_atlas=sw(CREAM))
    m.cyl((-0.10, H + 0.04, 0.16), (-0.10, H + 0.041, 0.16), 0.068, 0.068, 10, KR, 1.0, caps=(False, True), uv_atlas=sw(LAV))
    crate(m, (0.18, 0.17, 0.0), 0.42, 0.32, 0.20, 0.1, OLD)
    rng = random.Random(4805)
    for k in range(3):
        rock(m, (0.12 + k * 0.08, 0.33, rng.uniform(-0.06, 0.06)), (0.04, 0.03, 0.035), rng, (0.62, 0.66, 0.56))
    return m


def houki(name, lod):
    m = new(name + ('_l1' if lod else ''), '箒（壁に立て掛け、穂を下に）：全長 1.50、穂（小枝の束）長 0.48 Ø0.30、縛り 3 段；後ろ（−z）へ 13° 傾く')
    lean = math.radians(13)

    def P(y):
        return (0.0, y * math.cos(lean), -y * math.sin(lean))
    seg = 6 if lod else 10
    m.cyl(P(0.42), P(1.50), 0.024, 0.022, 6, WD, AGED)
    m.cyl(P(0.48), P(0.02), 0.05, 0.15, seg, SK, (0.70, 0.60, 0.42), caps=(False, False), uv_atlas=STRAW_RG)
    m.cyl(P(0.02), P(0.0), 0.15, 0.14, seg, SK, (0.60, 0.52, 0.36), caps=(False, True), uv_atlas=STRAW_RG)
    if not lod:
        for t in (0.30, 0.36, 0.42):
            r = 0.05 + (0.15 - 0.05) * (0.48 - t) / 0.46 + 0.006
            m.cyl(P(t - 0.012), P(t + 0.012), r, r, seg, KR, 1.0, caps=(False, False), uv_atlas=sw(BROWN))
    return m


def nawa(name, lod):
    m = new(name + ('_l1' if lod else ''), '縄の束：太さ 0.05 の縄を巻いた輪 3（Ø0.40–0.46、少しずれて重なる）＋垂れた端')
    n = 12 if lod else 20
    for k, (r, y, ox) in enumerate(((0.21, 0.0, 0.0), (0.195, 0.045, 0.025), (0.20, 0.09, -0.02))):
        col = ROPE if k % 2 == 0 else (0.54, 0.46, 0.33)
        m.cyl((ox, y, 0.0), (ox, y + 0.05, 0.0), r, r, n, SK, col, caps=(False, False), uv_atlas=STRAW_RG)
        m.cyl((ox, y + 0.05, 0.0), (ox, y, 0.0), r - 0.055, r - 0.055, n, SK, (0.40, 0.34, 0.25), caps=(False, False), uv_atlas=STRAW_RG)
        ri, ro = r - 0.055, r
        for i in range(n):
            a0 = 2 * math.pi * i / n
            a1 = 2 * math.pi * (i + 1) / n
            qd = [(ox + ri * math.cos(a0), y + 0.05, ri * math.sin(a0)), (ox + ro * math.cos(a0), y + 0.05, ro * math.sin(a0)),
                  (ox + ro * math.cos(a1), y + 0.05, ro * math.sin(a1)), (ox + ri * math.cos(a1), y + 0.05, ri * math.sin(a1))]
            m.poly(qd[::-1], SK, col, uvs=[(STRAW_RG[0], STRAW_RG[1]), (STRAW_RG[2], STRAW_RG[1]), (STRAW_RG[2], STRAW_RG[3]), (STRAW_RG[0], STRAW_RG[3])])
    m.cyl((0.20, 0.12, 0.0), (0.42, 0.025, 0.12), 0.022, 0.022, 5, SK, ROPE, caps=(False, True), uv_atlas=STRAW_RG)
    return m


# ─────────────────────────── 後院（倉庫） ───────────────────────────

def hakozumi(name, lod):
    m = new(name + ('_l1' if lod else ''), '積んだ材料箱：下 2（0.60 × 0.42 × 0.38、蓋 1・開け 1）＋上 1（15° ずらし、蓋が立て掛かる）、札 1')
    crate(m, (-0.32, 0.0, 0.0), 0.60, 0.42, 0.38, 0.0, AGED, open_top=False)
    crate(m, (0.33, 0.0, 0.02), 0.58, 0.42, 0.36, -0.06, OLD)
    rng = random.Random(4806)
    for k in range(3):
        rock(m, (0.23 + k * 0.1, 0.30, rng.uniform(-0.08, 0.08)), (0.06, 0.04, 0.05), rng, (0.66, 0.64, 0.60))
    crate(m, (-0.25, 0.38, 0.03), 0.52, 0.38, 0.30, 0.26, WOODC)
    up = K.norm((0.0, 0.93, 0.35))
    lx = K.norm((math.cos(0.26), 0.0, -math.sin(0.26)))
    m.obox((-0.22, 0.38 + 0.30 + 0.05, 0.03 - 0.19), (0.27, 0.2, 0.012), WD, AGED, ax=lx, ay=up, az=K.norm(K.cross(lx, up)))
    m.rect_uv((-0.48, 0.10, 0.212), (-0.30, 0.10, 0.212), (-0.30, 0.26, 0.212), (-0.48, 0.26, 0.212), SK, PAPER_RG, PAPER)
    return m


def fukuro(name, lod):
    m = new(name + ('_l1' if lod else ''), '麻袋 3（材料入り、口を縄で縛る）：1 つは寄り掛かる')
    rng = random.Random(4807)
    for (x, z, h, tl) in ((-0.42, 0.0, 0.58, 0.0), (0.10, 0.04, 0.50, 0.0), (0.62, -0.02, 0.46, -0.32)):
        w = rng.uniform(0.20, 0.24)
        ay = K.norm((math.sin(tl), math.cos(tl), 0.0))
        ax = K.norm((math.cos(tl), -math.sin(tl), 0.0))
        c = (x + ay[0] * h * 0.4, ay[1] * h * 0.4, z)
        m.abox(c, (w, h * 0.4, 0.16), SK, {'*': STRAW_RG}, SACK, ax=ax, ay=ay, az=(0.0, 0.0, 1.0))
        top = K.add(c, K.mul(ay, h * 0.4))
        nk = K.add(top, K.mul(ay, h * 0.12))
        m.cyl(top, nk, w * 0.55, w * 0.25, 6 if lod else 8, SK, SACK, caps=(False, False), uv_atlas=STRAW_RG)
        m.cyl(nk, K.add(nk, K.mul(ay, h * 0.08)), w * 0.25, w * 0.4, 6, SK, SACK, uv_atlas=STRAW_RG)
        if not lod:
            m.cyl(K.add(nk, K.mul(ay, -0.01)), K.add(nk, K.mul(ay, 0.02)), w * 0.27, w * 0.27, 6, SK, ROPE, caps=(False, False),
                  uv_atlas=STRAW_RG)
    return m


def akibin(name, lod):
    m = new(name + ('_l1' if lod else ''), '空き瓶の箱 0.50 × 0.36 × 0.22：瓶 6（栓なし）＋足元に寝た瓶 2')
    crate(m, (0, 0, 0), 0.50, 0.36, 0.22, 0.0, OLD)
    cols = [GREEN, BROWN, INDIGO, GREEN, CREAM, BROWN]
    k = 0
    for x in (-0.15, 0.0, 0.15):
        for z in (-0.08, 0.08):
            bottle(m, x, 0.02, z, 0.04, 0.26 + 0.03 * ((k * 7) % 3), cols[k], lod, cork=False)
            k += 1
    for (x, z, a, col) in ((0.40, 0.10, 0.4, GREEN), (0.36, -0.14, -0.9, BROWN)):
        d = (math.cos(a), 0.0, math.sin(a))
        p0 = (x, 0.04, z)
        m.cyl(p0, K.add(p0, K.mul(d, 0.16)), 0.04, 0.04, 8, KR, 1.0, uv_atlas=sw(col))
        m.cyl(K.add(p0, K.mul(d, 0.16)), K.add(p0, K.mul(d, 0.25)), 0.04, 0.015, 8, KR, 1.0, uv_atlas=sw(col))
    return m


def zaimoku(name, lod):
    m = new(name + ('_l1' if lod else ''), '板材の山：枕木 2＋板 7（長 1.9–2.1）を雜に積む')
    board(m, (-0.75, 0.0, -0.26), (-0.65, 0.09, 0.26), DARK)
    board(m, (0.65, 0.0, -0.26), (0.75, 0.09, 0.26), DARK)
    rng = random.Random(4808)
    y = 0.09
    for layer in range(3):
        n = 3 if layer < 2 else 1
        for i in range(n):
            L = rng.uniform(0.95, 1.05)
            w = rng.uniform(0.09, 0.12)
            z = -0.16 + i * 0.16 + rng.uniform(-0.02, 0.02)
            a = rng.uniform(-0.06, 0.06)
            m.obox((rng.uniform(-0.05, 0.05), y + 0.015, z), (L, 0.015, w), WD, [AGED, WOODC, OLD][(layer + i) % 3],
                   ax=(math.cos(a), 0.0, -math.sin(a)), ay=(0.0, 1.0, 0.0), az=(math.sin(a), 0.0, math.cos(a)))
        y += 0.032
    return m


def furudana(name, lod):
    m = new(name + ('_l1' if lod else ''), '古い棚（壁に寄せる）1.00 × 0.34 × 1.50：中段の板が落ちて斜め、壺・瓶・縄の束・帳面')
    W, D = 1.00, 0.34
    for x in (-W / 2 + 0.03, W / 2 - 0.03):
        board(m, (x - 0.03, 0.0, -D / 2), (x + 0.03, 1.50, D / 2), OLD)
    for y in (0.10, 1.05, 1.48):
        board(m, (-W / 2 + 0.06, y - 0.025, -D / 2), (W / 2 - 0.06, y, D / 2), AGED)
    a = math.atan2(0.30, 0.88)
    m.obox((0.0, 0.42, 0.0), (0.44, 0.012, D / 2 - 0.01), WD, AGED, ax=(math.cos(a), math.sin(a), 0.0), ay=(-math.sin(a), math.cos(a), 0.0),
           az=(0.0, 0.0, 1.0))
    jar(m, -0.28, 0.10, 0.02, 0.08, 0.24, CREAM, lod)
    jar(m, 0.22, 1.05, 0.0, 0.06, 0.18, BROWN, lod)
    bottle(m, -0.05, 1.05, 0.05, 0.035, 0.18, GREEN, lod, cork=False)
    m.abox((-0.25, 1.08, 0.0), (0.12, 0.03, 0.09), SK, {'*': PAPER_RG}, PAPER)
    for (r, y) in ((0.12, 0.10), (0.11, 0.135)):
        m.cyl((0.24, y, 0.0), (0.24, y + 0.035, 0.0), r, r, 10, SK, ROPE, caps=(False, True), uv_atlas=STRAW_RG)
    return m


# ─────────────────────────── 搬運 ───────────────────────────

AX = 0.46
TH = math.asin((AX + 0.025) / 2.05)


def tilt(p):
    x, y, z = p
    dy = y - AX
    c, s = math.cos(TH), math.sin(TH)
    return (x, AX + dy * c - z * s, z * c + dy * s)


def tilt_dir(d):
    c, s = math.cos(TH), math.sin(TH)
    return (d[0], d[1] * c - d[2] * s, d[2] * c + d[1] * s)


def tbeam(m, a, b, w, h, col):
    m.beam(tilt(a), tilt(b), w, h, WD, col, up=tilt_dir((0.0, 1.0, 0.0)))


def kuruma(name, lod):
    m = new(name + ('_l1' if lod else ''), '大八車：車輪 Ø0.92 ×2、荷台 0.84 × 1.75、梶棒先 2.05；梶棒を地に下ろした駐車姿勢（前傾 %.1f°）＋筵 2＋縄の輪' % math.degrees(TH))
    nrim = 10 if lod else 14
    for sx in (-1, 1):
        x = sx * 0.50
        pts = [(x, AX + 0.43 * math.cos(2 * math.pi * i / nrim), 0.43 * math.sin(2 * math.pi * i / nrim)) for i in range(nrim)]
        for i in range(nrim):
            m.beam(pts[i], pts[(i + 1) % nrim], 0.06, 0.06, WD, DARK)
        nsp = 4 if lod else 8
        for i in range(nsp):
            a = 2 * math.pi * i / nsp + 0.2
            m.beam((x, AX, 0.0), (x, AX + 0.41 * math.cos(a), 0.41 * math.sin(a)), 0.035, 0.03, WD, AGED)
        m.cyl((x - sx * 0.05, AX, 0.0), (x + sx * 0.06, AX, 0.0), 0.07, 0.06, 8, WD, DARK)
    m.cyl((-0.47, AX, 0.0), (0.47, AX, 0.0), 0.035, 0.035, 6, WD, DARK, caps=(False, False))
    yr = AX + 0.06
    for sx in (-1, 1):
        tbeam(m, (sx * 0.40, yr, -0.75), (sx * 0.40, yr, 2.05), 0.07, 0.07, AGED)
    for z in (-0.72, -0.15, 0.45, 1.0):
        tbeam(m, (-0.40, yr - 0.005, z), (0.40, yr - 0.005, z), 0.06, 0.05, AGED)
    tbeam(m, (-0.40, yr, 1.98), (0.40, yr, 1.98), 0.05, 0.05, WOODC)
    for i in range(5 if not lod else 1):
        if lod:
            x0, x1 = -0.42, 0.42
        else:
            x0 = -0.42 + i * 0.168 + 0.004
            x1 = x0 + 0.16
        c = tilt(((x0 + x1) / 2, yr + 0.048, 0.125))
        m.obox(c, ((x1 - x0) / 2, 0.012, 0.875), WD, WOODC if i % 2 == 0 else (0.78, 0.72, 0.62),
               ax=(1.0, 0.0, 0.0), ay=tilt_dir((0.0, 1.0, 0.0)), az=tilt_dir((0.0, 0.0, 1.0)))
    for sx in (-1, 1):
        c = tilt((sx * 0.43, yr + 0.10, 0.125))
        m.obox(c, (0.012, 0.045, 0.875), WD, AGED, ax=(1.0, 0.0, 0.0), ay=tilt_dir((0.0, 1.0, 0.0)), az=tilt_dir((0.0, 0.0, 1.0)))
    c = tilt((0.05, yr + 0.085, 0.35))
    m.abox(c, (0.34, 0.02, 0.30), SK, {'*': STRAW_RG}, (0.66, 0.58, 0.44), ax=(1.0, 0.0, 0.0), ay=tilt_dir((0.0, 1.0, 0.0)), az=tilt_dir((0.0, 0.0, 1.0)))
    c2 = tilt((-0.06, yr + 0.115, -0.30))
    m.abox(c2, (0.30, 0.012, 0.26), SK, {'*': STRAW_RG}, (0.58, 0.50, 0.38), ax=(1.0, 0.0, 0.0), ay=tilt_dir((0.0, 1.0, 0.0)),
           az=tilt_dir((0.0, 0.0, 1.0)))
    if not lod:
        cc = tilt((0.18, yr + 0.14, -0.42))
        up = tilt_dir((0.0, 1.0, 0.0))
        m.cyl(cc, K.add(cc, K.mul(up, 0.04)), 0.13, 0.13, 10, SK, ROPE, caps=(False, True), uv_atlas=STRAW_RG)
    return m


def okeyama(name, lod):
    m = new(name + ('_l1' if lod else ''), '桶の積み出し：台 0.95 × 0.50 × 0.12、盥 Ø0.62 ＋桶 2 段、手桶 2')
    W, D, H = 0.95, 0.50, 0.12
    board(m, (-W / 2, H - 0.03, -D / 2), (W / 2, H, D / 2), AGED)
    for x in (-W / 2 + 0.05, W / 2 - 0.05):
        board(m, (x - 0.035, 0.0, -D / 2 + 0.03), (x + 0.035, H - 0.03, D / 2 - 0.03), DARK)
    oke(m, -0.16, H, 0.0, 0.29, 0.31, 0.20, lod)
    oke(m, -0.16, H + 0.20, 0.0, 0.19, 0.21, 0.30, lod)
    oke(m, -0.15, H + 0.50, 0.01, 0.15, 0.17, 0.26, lod)
    for (x, z) in ((0.30, -0.10), (0.31, 0.13)):
        oke(m, x, H, z, 0.12, 0.135, 0.24, lod)
        for s in (-1, 1):
            board(m, (x - 0.02, H + 0.20, z + s * 0.135 - 0.012), (x + 0.02, H + 0.36, z + s * 0.135 + 0.012), AGED)
        board(m, (x - 0.02, H + 0.33, z - 0.15), (x + 0.02, H + 0.36, z + 0.15), WOODC)
    return m


def ni(name, lod):
    m = new(name + ('_l1' if lod else ''), '荷：菰包み 0.62 × 0.36 × 0.40（縄十字）＋上に藍の風呂敷包み')
    m.abox((0.0, 0.20, 0.0), (0.31, 0.20, 0.18), SK, {'*': STRAW_RG}, STRAW)
    if not lod:
        m.abox((0.0, 0.206, 0.0), (0.322, 0.206, 0.025), SK, {'*': STRAW_RG}, ROPE, skip=('-y',))
        for x in (-0.15, 0.15):
            m.abox((x, 0.206, 0.0), (0.022, 0.206, 0.192), SK, {'*': STRAW_RG}, ROPE, skip=('-y',))
    ind = sw(INDIGO)
    m.abox((0.04, 0.53, 0.0), (0.20, 0.12, 0.15), KR, {'*': ind}, 1.0)
    m.abox((0.04, 0.66, 0.0), (0.06, 0.03, 0.05), KR, {'*': ind}, 0.85)
    if not lod:
        for s in (-1, 1):
            m.abox((0.04 + s * 0.08, 0.68, 0.0), (0.04, 0.012, 0.03), KR, {'*': ind}, 0.85)
    return m


# ─────────────────────────── 植生 ───────────────────────────

def yakuso(name, lod):
    m = new(name + ('_l1' if lod else ''), '藥草の株：葉 11（高 0.26–0.46）＋花穂 5（紫・金・生成り）')
    rng = random.Random(4809)
    n = 11 if not lod else 6
    for i in range(n):
        a = 2 * math.pi * i / n + rng.uniform(-0.2, 0.2)
        h = rng.uniform(0.26, 0.46)
        out = rng.uniform(0.10, 0.18)
        d = K.norm((math.cos(a) * out, h, math.sin(a) * out))
        side = K.norm((-math.sin(a), 0.0, math.cos(a)))
        nrm = K.cross(side, d)
        L = math.sqrt(h * h + out * out)
        m.abox(K.mul(d, L / 2), (0.03, L / 2, 0.004), KR, {'*': sw(GREEN)}, 1.0, ax=side, ay=d, az=nrm)
    for k in range(5 if not lod else 2):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.0, 0.1)
        h = rng.uniform(0.38, 0.55)
        x, z = r * math.cos(a), r * math.sin(a)
        m.cyl((x, 0.0, z), (x, h, z), 0.005, 0.005, 4, KR, 1.0, caps=(False, False), uv_atlas=sw(GREEN))
        m.cyl((x, h - 0.07, z), (x, h + 0.02, z), 0.028, 0.012, 6, KR, 1.0, uv_atlas=sw([LAV, GOLD, CREAM, LAV, GOLD][k]))
    return m


def kinoko(name, lod):
    m = new(name + ('_l1' if lod else ''), '茸の群れ（日陰の牆腳・木材の脇）：大小 8、赤茶・生成り・紫の傘、Ø0.45')
    rng = random.Random(4810)
    for i in range(8 if not lod else 4):
        a = rng.uniform(0, 2 * math.pi)
        rr = rng.uniform(0.0, 0.18)
        big = i < 2
        mushroom(m, rr * math.cos(a), -0.01, rr * math.sin(a), 0.07 if big else rng.uniform(0.03, 0.05),
                 0.10 if big else rng.uniform(0.04, 0.07), [RED, CREAM, RED, LAV, BROWN, RED, CREAM, BROWN][i], lod,
                 (rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02)))
    return m


def build_all():
    for lod in (0, 1):
        fuda_ma('kr_fuda_ma', lod)
        hako_ishi('kr_hako_ishi', lod)
        kago('kr_kago', lod)
        bin_dai('kr_bin', lod)
        hoshidana('kr_hoshidana', lod)
        ishidana('kr_ishidana', lod)
        sagyo('kr_sagyo', lod)
        houki('kr_houki', lod)
        nawa('kr_nawa', lod)
        hakozumi('kr_hakozumi', lod)
        fukuro('kr_fukuro', lod)
        akibin('kr_akibin', lod)
        zaimoku('kr_zaimoku', lod)
        furudana('kr_furudana', lod)
        kuruma('kr_kuruma', lod)
        okeyama('kr_okeyama', lod)
        ni('kr_ni', lod)
        yakuso('kr_yakuso', lod)
        kinoko('kr_kinoko', lod)


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
    K.export_glb(bpy, OUT + '/src/kiri_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_kiri_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=kiri_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[KRKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/kiri_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[KRKIT]   %-13s %5d 面  LOD1 %4d  dims %s  %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims'], v['mats']))


main()
