"""人間之里 V2 P10 R4 Human-Use / Ambient Life Pilot：生活痕跡 Kit（humanuse_kit）— 缺件だけの新資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_humanuse_kit.py

棚卸し（P10 R4 Asset audit）：桶・箱・籠・箒・薪棚・稲架・藁塚・農具掛け・荷車・干し竿・井戸・天水桶・甕・縁台・腰掛け・梯子・縄・板材・
  大工／桶屋／藁細工の作業場は既存 Kit（street_kit・market_kit・school_kit・tower_kit・kiri_kit・suzu_kit・waterside_kit）に揃っている
  → 重用（重複資產は作らない）。既存に**無い**生活語彙だけをここで作る：
  hu_senba      千歯扱き（脱穀）：台木＋前脚 2・後ろ控え 2・踏み木、歯台に鉄の歯 22、下に筵・扱いた籾・稲束 2・扱き殻
  hu_tomi       唐箕（風選）：胴 0.84 × 0.44・羽根車の胴丸 Ø0.68・漏斗（籾入り）・一番口／二番口の樋・取っ手、脚 4、樋の下に籾の笊
  hu_momiboshi  籾干し筵：筵 2 枚（1.8 × 0.88）に籾を広げ、えぶり（木の熊手）で引いた筋、箕 1・えぶり 1
  hu_tarai      洗濯盥：盥 Ø0.72 × 0.24（箍 2、内側の板）に水と洗い物（藍・生成り）、縁に掛けた手拭い 1
  hu_makiwari   薪割り台：切り株 Ø0.46 × 0.42 に斧（刃を食い込ませて立つ）、割った薪 6・割る前の玉切り 2
  hu_seoikago   背負い籠（下ろした姿）：籠 Ø0.50（底 0.34）× 0.62、負い縄 2、刈った稲束を差して運ぶ途中（穂が上）
材質（町で使用中・承認済みだけ、新 atlas なし）：V2_Wood（_matlib）＋ST_Street（street_kit atlas：稲束 ine・藁 straw・笊 zaru・
  竹 take・鉄 tetsu／hagane・縄 nawa・籾 ine_ho・米 kome・藍 ai・生成り kinari・紺 kon）。
座標：Godot（x 右、y 上、+z 前＝使う人の側）；原點＝接地點（y 0）；單位 m。*_l1＝LOD1。
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/humanuse_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(G + '/assets/village_v2/street_kit/atlas.json')
REG = AT['regions']
SWC = AT['swatches']
WD = 'V2_Wood'
ST = 'ST_Street'
MATS = [WD, ST]
TILE = {WD: ML['V2_Wood']['tile_m'], ST: 1.0}

# 木：町家 Kit・市集・主街と同じ明るさ
WOODC = (0.84, 0.78, 0.68)
AGED = (0.66, 0.62, 0.56)
OLD = (0.52, 0.48, 0.43)
DARK = (0.34, 0.29, 0.24)
SHIBU = (0.62, 0.50, 0.40)     # 柿渋を引いた道具（唐箕）

MODS = {}
INFO = {}


def new(name, lod, note=''):
    n = name + ('_l1' if lod else '')
    m = K.Mesh(n, MATS, TILE)
    MODS[n] = m
    INFO[n] = note
    return m


# ─────────────────────────── 基本（build_street_kit.py と同じ作法） ───────────────────────────

def swr(key):
    u, v = SWC[key]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


def obx(m, c, h, key, ax=K.X, ay=K.Y, az=K.Z, col=1.0):
    m.abox(c, h, ST, {'*': swr(key)}, col, ax=ax, ay=ay, az=az)


def rbx(m, c, h, region, ax=K.X, ay=K.Y, az=K.Z, col=1.0):
    m.abox(c, h, ST, {'*': REG[region]}, col, ax=ax, ay=ay, az=az)


def cy(m, p0, p1, r0, r1, seg, key, caps=(True, True), col=1.0):
    m.cyl(p0, p1, r0, r1, seg, ST, col, caps=caps, uv_atlas=swr(key))


def rcy(m, p0, p1, r0, r1, seg, region, caps=(True, True), col=1.0):
    m.cyl(p0, p1, r0, r1, seg, ST, col, caps=caps, uv_atlas=REG[region])


def wcy(m, p0, p1, r0, r1, seg, col=AGED, caps=(True, True)):
    m.cyl(p0, p1, r0, r1, seg, WD, col, caps=caps)


def ball(m, c, r, key, seg, squash=1.0):
    x, y, z = c
    ry = r * squash
    cy(m, (x, y - ry, z), (x, y - ry * 0.55, z), r * 0.25, r * 0.85, seg, key, caps=(True, False))
    cy(m, (x, y - ry * 0.55, z), (x, y + ry * 0.55, z), r * 0.85, r * 0.85, seg, key, caps=(False, False))
    cy(m, (x, y + ry * 0.55, z), (x, y + ry, z), r * 0.85, r * 0.25, seg, key, caps=(False, True))


def inner_wall(m, x, z, y0, y1, r, seg, mat, col, uv=None):
    """内向きの円筒壁（桶・籠の内側：上から覗いても外殻の裏が抜けない）。"""
    for i in range(seg):
        a0 = 2 * math.pi * i / seg
        a1 = 2 * math.pi * (i + 1) / seg
        p = [(x + math.cos(a) * r, y, z + math.sin(a) * r) for a, y in ((a0, y0), (a1, y0), (a1, y1), (a0, y1))]
        # 外向き（cyl と同じ）は a0→a1 が反時計（上から見て）なので、内向きは逆順
        if uv:
            m.poly([p[1], p[0], p[3], p[2]], mat, col, uvs=[(uv[0], uv[3]), (uv[2], uv[3]), (uv[2], uv[1]), (uv[0], uv[1])])
        else:
            m.poly([p[1], p[0], p[3], p[2]], mat, col)


def disc(m, x, y, z, r, seg, key, col=1.0):
    u, v = SWC[key]
    ring = [(x + math.cos(2 * math.pi * i / seg) * r, y, z - math.sin(2 * math.pi * i / seg) * r) for i in range(seg)]
    m.poly(ring, ST, col, uvs=[(u, v)] * seg)


def sheaf(m, a, b, r, lod, ho_up=True):
    """稲束：藁の胴（a→b）＋穂先（b 側 1/3 を ine）。"""
    seg = 5 if lod else 7
    mid = K.lerp(a, b, 0.62)
    rcy(m, a, mid, r * 0.85, r, seg, 'straw', caps=(True, False))
    rcy(m, mid, b, r, r * 1.25, seg, 'ine', caps=(False, True))
    if not lod:
        tie = K.lerp(a, b, 0.4)
        cy(m, K.lerp(a, b, 0.36), tie, r * 0.95, r * 0.95, seg, 'nawa', caps=(False, False))


def kago(m, x, y, z, r0, r1, h, lod, rim='take'):
    seg = 8 if lod else 14
    m.cyl((x, y, z), (x, y + h, z), r0, r1, seg, ST, 1.0, caps=(True, False), uv_atlas=REG['zaru'])
    inner_wall(m, x, z, y + 0.03, y + h, r1 - 0.012, seg, ST, 0.7, uv=REG['zaru'])
    cy(m, (x, y + h - 0.014, z), (x, y + h + 0.014, z), r1 + 0.013, r1 + 0.013, seg, rim, caps=(False, False))
    return y + h


# ─────────────────────────── 農：千歯扱き・唐箕・籾干し・背負い籠 ───────────────────────────

def senba(lod):
    m = new('hu_senba', lod, '千歯扱き（脱穀）：台木 0.62 × 1.2、歯台 0.60（高 0.76）に鉄の歯 22（長 0.19、前へ 32°）、前脚 2・後ろ控え 2・踏み木；'
            '下に筵 1.24 × 1.0 と扱いた籾、扱く前の稲束 2、扱き殻の藁 1')
    rng = random.Random(41001)
    # 筵（前＝使う人の側へ広い）と籾
    rbx(m, (0.0, 0.012, 0.18), (0.62, 0.012, 0.5), 'straw')
    obx(m, (0.0, 0.03, 0.2), (0.36, 0.008, 0.22), 'ine_ho')
    if not lod:
        for i in range(5):
            obx(m, (rng.uniform(-0.3, 0.3), 0.04, 0.12 + i * 0.06), (rng.uniform(0.08, 0.18), 0.006, 0.02), 'ine_ho', col=0.88)
    # 前脚（少し開く）・後ろ控え・踏み木・歯台
    for s in (-1, 1):
        m.beam((s * 0.27, 0.0, 0.08), (s * 0.24, 0.72, 0.02), 0.06, 0.06, WD, OLD)
        m.beam((s * 0.24, 0.0, -0.62), (s * 0.24, 0.7, -0.02), 0.055, 0.07, WD, OLD)
    m.box((-0.31, 0.0, -0.66), (0.31, 0.07, -0.48), WD, AGED)
    m.box((-0.31, 0.24, -0.38), (0.31, 0.29, -0.32), WD, AGED)
    m.box((-0.3, 0.66, -0.05), (0.3, 0.77, 0.09), WD, DARK)
    n = 22 if not lod else 0
    for i in range(n):
        x = -0.27 + 0.54 * i / (n - 1)
        cy(m, (x, 0.76, 0.05), (x, 0.92, 0.15), 0.006, 0.004, 3, 'tetsu', caps=(False, True))
    if lod:
        obx(m, (0.0, 0.84, 0.1), (0.27, 0.085, 0.006), 'tetsu', ay=K.norm((0.0, 0.85, 0.53)), az=K.norm((0.0, -0.53, 0.85)))
    # 扱く前の稲束 2（筵の前、穂を歯の方へ）・扱き殻の藁
    sheaf(m, (-0.42, 0.07, 0.62), (-0.08, 0.1, 0.42), 0.07, lod)
    sheaf(m, (0.36, 0.07, 0.6), (0.12, 0.09, 0.38), 0.065, lod)
    rcy(m, (0.5, 0.06, -0.15), (0.56, 0.08, 0.38), 0.08, 0.1, 5 if lod else 7, 'straw')
    return m


def tomi(lod):
    m = new('hu_tomi', lod, '唐箕（風選）：胴 0.84 × 0.44 × 0.40（脚 0.42）、羽根車の胴丸 Ø0.68（左）・取っ手、漏斗 0.50 × 0.44（籾入り、上端 1.22）、'
            '一番口・二番口の樋（前へ）、尻の口（右）；柿渋の板、樋の下に籾の笊')
    seg = 10 if lod else 16
    for x in (-0.36, 0.42):
        for z in (-0.19, 0.19):
            m.box((x - 0.03, 0.0, z - 0.03), (x + 0.03, 0.44, z + 0.03), WD, OLD)
    m.box((-0.36, 0.42, -0.22), (0.48, 0.82, 0.22), WD, SHIBU)
    # 胴丸（羽根車の覆い）：z 軸の円筒＋胴との継ぎ
    wcy(m, (-0.6, 0.62, -0.23), (-0.6, 0.62, 0.23), 0.34, 0.34, seg, SHIBU)
    m.box((-0.62, 0.3, -0.225), (-0.34, 0.94, 0.225), WD, SHIBU)
    # 羽根車の軸と取っ手（前 +z）
    wcy(m, (-0.6, 0.62, 0.23), (-0.6, 0.62, 0.3), 0.04, 0.04, 6, DARK)
    m.beam((-0.6, 0.62, 0.29), (-0.43, 0.72, 0.29), 0.04, 0.03, WD, DARK)
    wcy(m, (-0.43, 0.72, 0.29), (-0.43, 0.72, 0.42), 0.018, 0.018, 6, DARK)
    # 漏斗（台形の 4 面）＋籾
    top_y, bot_y = 1.22, 0.82
    tx0, tx1, tz = -0.2, 0.3, 0.22
    bx0, bx1, bz = 0.0, 0.12, 0.07
    A = [(tx0, top_y, tz), (tx1, top_y, tz), (tx1, top_y, -tz), (tx0, top_y, -tz)]
    B = [(bx0, bot_y, bz), (bx1, bot_y, bz), (bx1, bot_y, -bz), (bx0, bot_y, -bz)]
    for i in range(4):
        j = (i + 1) % 4
        m.quad(B[i], B[j], A[j], A[i], WD, SHIBU)        # 外
        m.quad(A[i], A[j], B[j], B[i], WD, (0.45, 0.37, 0.3))   # 内
    u, v = SWC['ine_ho']
    m.poly([(tx0 + 0.05, 1.13, tz - 0.05), (tx1 - 0.05, 1.13, tz - 0.05), (tx1 - 0.05, 1.13, -tz + 0.05), (tx0 + 0.05, 1.13, -tz + 0.05)],
           ST, 1.0, uvs=[(u, v)] * 4)
    m.box((tx0 - 0.02, top_y - 0.03, tz - 0.01), (tx1 + 0.02, top_y + 0.01, tz + 0.02), WD, DARK)
    m.box((tx0 - 0.02, top_y - 0.03, -tz - 0.02), (tx1 + 0.02, top_y + 0.01, -tz + 0.01), WD, DARK)
    # 一番口（漏斗の下、前へ下がる樋）・二番口・尻の口
    m.beam((0.06, 0.46, 0.2), (0.06, 0.24, 0.48), 0.2, 0.025, WD, AGED)
    for s in (-1, 1):
        m.beam((0.06 + s * 0.1, 0.48, 0.2), (0.06 + s * 0.1, 0.27, 0.48), 0.02, 0.07, WD, AGED)
    m.beam((0.34, 0.5, 0.2), (0.34, 0.36, 0.36), 0.14, 0.022, WD, AGED)
    m.box((0.48, 0.48, -0.2), (0.62, 0.78, 0.2), WD, (0.5, 0.41, 0.33), skip=('+x',))
    # 笊（籾を受ける）
    y = kago(m, 0.06, 0.0, 0.58, 0.16, 0.21, 0.1, lod)
    disc(m, 0.06, y - 0.02, 0.58, 0.19, 8 if lod else 12, 'ine_ho')
    return m


def momiboshi(lod):
    m = new('hu_momiboshi', lod, '籾干し筵：筵 2 枚 1.8 × 0.88（少しずれる）に籾を広げ、えぶりで引いた筋 6／枚、箕 1（籾入り）・えぶり 1（筵の上に寝かせる）')
    rng = random.Random(41003)
    for k, (z, yaw) in enumerate(((-0.46, 0.0), (0.46, 0.035))):
        ax = (math.cos(yaw), 0.0, -math.sin(yaw))
        az = (math.sin(yaw), 0.0, math.cos(yaw))
        rbx(m, (0.0, 0.01, z), (0.9, 0.01, 0.44), 'straw', ax=ax, az=az)
        obx(m, (0.0, 0.026, z), (0.8, 0.007, 0.38), 'ine_ho', ax=ax, az=az)
        if not lod:
            for i in range(6):
                zz = z - 0.32 + i * 0.128 + rng.uniform(-0.01, 0.01)
                obx(m, (rng.uniform(-0.04, 0.04), 0.036, zz), (0.74, 0.005, 0.022), 'ine_ho', ax=ax, az=az, col=0.82)
    # えぶり：板の頭（0.46）＋柄 1.15（筵の上を斜めに）
    head = (0.48, 0.07, 0.34)
    m.beam((0.48, 0.05, 0.11), (0.48, 0.05, 0.57), 0.03, 0.08, WD, AGED)
    m.beam(head, (-0.55, 0.06, -0.38), 0.035, 0.035, WD, OLD)
    # 箕（浅い笊、籾入り）
    y = kago(m, -0.66, 0.02, 0.62, 0.17, 0.22, 0.07, lod)
    disc(m, -0.66, y - 0.015, 0.62, 0.2, 8 if lod else 12, 'ine_ho')
    return m


def seoikago(lod):
    m = new('hu_seoikago', lod, '背負い籠（下ろした姿）：籠 Ø0.50（底 0.34）× 0.62、負い縄 2（背の側 −z）、刈った稲束 5 を差して運ぶ途中（穂が上、高 0.98）')
    rng = random.Random(41004)
    y = kago(m, 0.0, 0.0, 0.0, 0.17, 0.25, 0.62, lod)
    # 中身：稲束（穂を上へ、少し開く）
    n = 5 if not lod else 3
    for i in range(n):
        a = 2 * math.pi * i / n + 0.3
        bx, bz = math.cos(a) * 0.08, math.sin(a) * 0.08
        sheaf(m, (bx * 0.6, y - 0.25, bz * 0.6), (bx * 1.9 + rng.uniform(-0.03, 0.03), y + 0.34 + rng.uniform(-0.03, 0.04), bz * 1.9), 0.055, lod)
    disc(m, 0.0, y - 0.03, 0.0, 0.235, 8 if lod else 12, 'wara', col=0.8)
    # 負い縄（背の側 −z）：上の縁から下の方へ 2 本の輪
    for s in (-1, 1):
        x = s * 0.1
        p0 = (x, y - 0.03, -0.26)
        p1 = (x * 1.2, y * 0.55, -0.31)
        p2 = (x, 0.12, -0.2)
        cy(m, p0, p1, 0.013, 0.013, 4, 'nawa', caps=(False, False))
        cy(m, p1, p2, 0.013, 0.013, 4, 'nawa', caps=(False, False))
    return m


# ─────────────────────────── 暮らし：洗濯盥・薪割り台 ───────────────────────────

def tarai(lod):
    m = new('hu_tarai', lod, '洗濯盥：盥 Ø0.72 × 0.24（板の側、箍 2、内側の板）に水（暗い面）と洗い物 3（藍・生成り）、縁に掛けた手拭い 1')
    seg = 12 if lod else 20
    wcy(m, (0.0, 0.0, 0.0), (0.0, 0.24, 0.0), 0.33, 0.36, seg, AGED, caps=(True, False))
    inner_wall(m, 0.0, 0.0, 0.15, 0.24, 0.335, seg, WD, (0.5, 0.45, 0.4))
    for y in (0.06, 0.19):
        cy(m, (0.0, y, 0.0), (0.0, y + 0.025, 0.0), 0.34 + y * 0.12 + 0.008, 0.34 + y * 0.12 + 0.009, seg, 'take', caps=(False, False))
    m.box((-0.37, 0.235, -0.015), (-0.31, 0.25, 0.015), WD, DARK)
    disc(m, 0.0, 0.155, 0.0, 0.335, seg, 'kon', col=0.62)
    for (x, z, r, key) in ((0.08, -0.06, 0.13, 'ai'), (-0.1, 0.08, 0.11, 'kinari'), (0.12, 0.13, 0.08, 'ai')):
        ball(m, (x, 0.16, z), r, key, 7 if lod else 10, 0.32)
    # 手拭い（縁から外へ垂れる）
    u, v = SWC['kinari']
    m.poly([(0.22, 0.25, -0.27), (0.36, 0.25, -0.12), (0.4, 0.06, -0.14), (0.27, 0.06, -0.3)], ST, 1.0, uvs=[(u, v)] * 4)
    m.poly([(0.36, 0.25, -0.12), (0.22, 0.25, -0.27), (0.27, 0.06, -0.3), (0.4, 0.06, -0.14)], ST, 0.85, uvs=[(u, v)] * 4)
    return m


def makiwari(lod):
    m = new('hu_makiwari', lod, '薪割り台：切り株 Ø0.46 × 0.42（斧の刃を食い込ませて柄が斜めに立つ、柄 0.72）、割った薪 6（散らばる）・割る前の玉切り 2')
    rng = random.Random(41006)
    seg = 10 if lod else 16
    wcy(m, (0.0, 0.0, 0.0), (0.0, 0.42, 0.0), 0.25, 0.23, seg, OLD)
    disc(m, 0.0, 0.421, 0.0, 0.225, seg, 'kanna' if 'kanna' in SWC else 'kinari', col=0.78)
    # 斧：刃（鉄）は株の上に食い込み、柄は前（+z）へ斜めに立つ
    obx(m, (0.02, 0.45, -0.03), (0.09, 0.05, 0.012), 'hagane', ax=K.norm((1.0, 0.0, 0.2)), az=K.norm((-0.2, 0.0, 1.0)))
    m.beam((0.02, 0.47, -0.02), (0.08, 0.98, 0.42), 0.035, 0.03, WD, AGED)
    # 割った薪（1/4 円柱を箱で近似、散らばり）・玉切り
    for i in range(6 if not lod else 3):
        a = rng.uniform(0.0, 2 * math.pi)
        r = rng.uniform(0.38, 0.62)
        x, z = math.cos(a) * r, math.sin(a) * r * 0.85
        yaw = rng.uniform(0.0, math.pi)
        ax = (math.cos(yaw), 0.0, -math.sin(yaw))
        az = (math.sin(yaw), 0.0, math.cos(yaw))
        m.obox((x, 0.045, z), (0.2, 0.045, 0.055), WD, WOODC if i % 2 else AGED, ax=ax, az=az)
    for (x, z) in ((-0.55, -0.3), (-0.62, 0.12)):
        wcy(m, (x, 0.0, z), (x, 0.36, z), 0.15, 0.15, 8 if lod else 12, OLD)
        disc(m, x, 0.361, z, 0.145, 8 if lod else 12, 'kanna' if 'kanna' in SWC else 'kinari', col=0.75)
    return m


# ─────────────────────────── 書き出し ───────────────────────────

def build_all():
    for lod in (0, 1):
        senba(lod)
        tomi(lod)
        momiboshi(lod)
        seoikago(lod)
        tarai(lod)
        makiwari(lod)


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
    K.export_glb(bpy, OUT + '/src/humanuse_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_humanuse_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=humanuse_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[HUKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/humanuse_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[HUKIT]   %-14s %5d 面  LOD1 %4d  dims %s  mats %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims'], v['mats']))


main()
