"""人間之里 V2 P10 R4b Human-Use Expansion：生活痕跡 Kit 追加（humanuse_exp_kit）— 缺件 3 件だけ。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_humanuse_exp_kit.py

棚卸し（R4b）：農具・桶・箱・籠・稲架・藁塚・荷車・干し竿・反物の掛け・漬物樽・荷積み・桶屋の作業場は既存 Kit と R4 humanuse_kit で足りる。
  既存に無いのは「家の裏の小さな菜園」「大根干し」「水路の泥上げ」だけ（R4b の住宅「小型家庭菜園」「冬の漬物」、水岸「水渠維護」に必要）→ この 3 件だけ作る。humanuse_kit（R4 封存）は触らない。
  hx_daikon_kake 大根干し：竹の X 脚＋竿 2 段に大根を振り分けに掛ける（R4b の住宅「冬の漬物」に必要、mk_hoshimono は布用で代用できない）
  hx_doroage 泥上げの山：水路から掻き上げた泥と藻の山に鋤を挿す・箕（R4b の水岸「水渠維護」の理由が見える物、既存に無い）
  hx_hatake  家庭菜園の畝：土の畝 3 本（2.2 × 1.3、高 0.12）に大根の葉・葱・青菜、端に竹の支柱と縄、畝に挿した鍬、水やりの手桶
材質（町で使用中・承認済みだけ、新 atlas なし）：V2_Wood（_matlib）＋ST_Street（street_kit atlas：土 tsuchi・大根葉 daikon_leaf・葱 negi・
  青菜 kyabetsu・竹 take・縄 nawa・鉄 hagane）。座標：Godot（x 右、y 上、+z 前＝通路側）；原點＝接地點；單位 m。*_l1＝LOD1。
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/humanuse_exp_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(G + '/assets/village_v2/street_kit/atlas.json')
REG = AT['regions']
SWC = AT['swatches']
WD = 'V2_Wood'
ST = 'ST_Street'
MATS = [WD, ST]
TILE = {WD: ML['V2_Wood']['tile_m'], ST: 1.0}
AGED = (0.66, 0.62, 0.56)
OLD = (0.52, 0.48, 0.43)

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


def obx(m, c, h, key, ax=K.X, ay=K.Y, az=K.Z, col=1.0):
    m.abox(c, h, ST, {'*': swr(key)}, col, ax=ax, ay=ay, az=az)


def cy(m, p0, p1, r0, r1, seg, key, caps=(True, True), col=1.0):
    m.cyl(p0, p1, r0, r1, seg, ST, col, caps=caps, uv_atlas=swr(key))


def leaf(m, base, ang, L, w, tilt, key, col=1.0):
    """葉カードの代わりの細い四角錐（両面読める薄い板 2 枚）。"""
    d = (math.cos(ang), 0.0, math.sin(ang))
    top = (base[0] + d[0] * L * math.cos(tilt), base[1] + L * math.sin(tilt), base[2] + d[2] * L * math.cos(tilt))
    s = (-d[2] * w, 0.0, d[0] * w)
    u, v = SWC[key]
    a = K.sub(base, s)
    b = K.add(base, s)
    m.poly([a, b, top], ST, col, uvs=[(u, v)] * 3)
    m.poly([b, a, top], ST, col * 0.85, uvs=[(u, v)] * 3)


def hatake(lod):
    m = new('hx_hatake', lod, '家庭菜園の畝：土の畝 3 本（2.2 × 1.3、高 0.12）に大根の葉 6・葱 10・青菜 6、端に竹の支柱 4 と縄、畝に挿した鍬、水やりの手桶')
    rng = random.Random(42001)
    # 畝 3 本（間の溝は低く）
    for i, z in enumerate((-0.42, 0.0, 0.42)):
        obx(m, (0.0, 0.06, z), (1.1, 0.06, 0.16), 'tsuchi', col=0.95 - 0.05 * i)
    obx(m, (0.0, 0.015, 0.0), (1.12, 0.015, 0.64), 'tsuchi', col=0.78)
    # 作物：手前＝大根（葉が大きい）・中＝葱（細く立つ）・奥＝青菜（低い株）
    n_d = 6 if not lod else 3
    for k in range(n_d):
        x = -0.9 + 1.8 * k / (n_d - 1)
        cy(m, (x, 0.1, 0.42), (x, 0.16, 0.42), 0.035, 0.03, 5, 'daikon', caps=(False, True))
        for j in range(5 if not lod else 3):
            leaf(m, (x, 0.13, 0.42), rng.uniform(0, 2 * math.pi), rng.uniform(0.22, 0.32), 0.05, rng.uniform(0.6, 1.0), 'daikon_leaf')
    n_n = 10 if not lod else 4
    for k in range(n_n):
        x = -0.95 + 1.9 * k / (n_n - 1)
        for j in range(3 if not lod else 1):
            cy(m, (x + rng.uniform(-0.03, 0.03), 0.12, rng.uniform(-0.04, 0.04)), (x + rng.uniform(-0.05, 0.05), 0.12 + rng.uniform(0.3, 0.42), rng.uniform(-0.06, 0.06)),
               0.012, 0.006, 4, 'negi', caps=(False, True))
    n_g = 6 if not lod else 3
    for k in range(n_g):
        x = -0.85 + 1.7 * k / (n_g - 1)
        for j in range(5 if not lod else 2):
            leaf(m, (x, 0.12, -0.42), rng.uniform(0, 2 * math.pi), rng.uniform(0.12, 0.18), 0.06, rng.uniform(0.3, 0.7), 'kyabetsu')
    # 竹の支柱と縄（畝の外周・通路側に低く）
    for x in (-1.18, 1.18):
        for z in (-0.6, 0.6):
            cy(m, (x, 0.0, z), (x, 0.55, z), 0.014, 0.012, 5, 'take', caps=(False, True))
    if not lod:
        for z in (-0.6, 0.6):
            cy(m, (-1.18, 0.42, z), (1.18, 0.42, z), 0.006, 0.006, 3, 'nawa', caps=(False, False))
        for x in (-1.18, 1.18):
            cy(m, (x, 0.42, -0.6), (x, 0.42, 0.6), 0.006, 0.006, 3, 'nawa', caps=(False, False))
    # 鍬（畝の端に刃を挿して柄が斜めに立つ）
    m.beam((1.0, 0.1, 0.18), (1.32, 0.95, 0.42), 0.032, 0.032, WD, AGED)
    obx(m, (0.99, 0.09, 0.17), (0.09, 0.05, 0.01), 'hagane', ax=K.norm((1.0, 0.0, 0.3)), az=K.norm((-0.3, 0.0, 1.0)))
    # 水やりの手桶（畝の手前の角）
    seg = 8 if lod else 12
    m.cyl((-1.32, 0.0, 0.72), (-1.32, 0.26, 0.72), 0.12, 0.14, seg, WD, OLD, caps=(True, False))
    u, v = SWC['kon']
    ring = [(-1.32 + math.cos(2 * math.pi * i / seg) * 0.13, 0.2, 0.72 - math.sin(2 * math.pi * i / seg) * 0.13) for i in range(seg)]
    m.poly(ring, ST, 0.6, uvs=[(u, v)] * seg)
    m.beam((-1.32, 0.24, 0.6), (-1.32, 0.42, 0.72), 0.03, 0.02, WD, OLD)
    m.beam((-1.32, 0.42, 0.72), (-1.32, 0.24, 0.84), 0.03, 0.02, WD, OLD)
    return m


def daikon_kake(lod):
    m = new('hx_daikon_kake', lod, '大根干し（沢庵の前）：竹の X 脚 2（高 1.75）＋竿 2 段（1.55／1.05、長 2.4）に葉で縛った大根を振り分けに掛ける（上 9 対・下 7 対）')
    rng = random.Random(42002)
    for x in (-1.1, 1.1):
        for s in (-1, 1):
            cy(m, (x, 0.0, s * 0.42), (x, 1.75, -s * 0.18), 0.022, 0.018, 5, 'take', caps=(False, True))
    for y in (1.55, 1.05):
        cy(m, (-1.25, y, 0.0), (1.25, y, 0.0), 0.02, 0.02, 6, 'take')
    for y, n in ((1.55, 9), (1.05, 7)):
        n = n if not lod else (n + 1) // 2
        for k in range(n):
            x = -1.0 + 2.0 * k / (n - 1)
            for s in (-1, 1):
                L = rng.uniform(0.38, 0.5)
                top = (x + rng.uniform(-0.02, 0.02), y - 0.03, s * 0.05)
                bot = (top[0] + rng.uniform(-0.03, 0.03), y - 0.03 - L, s * rng.uniform(0.08, 0.13))
                cy(m, bot, top, 0.012, 0.034, 6 if not lod else 4, 'daikon', caps=(True, False), col=rng.uniform(0.9, 1.0))
                if not lod:
                    for j in range(2):
                        leaf(m, (top[0], y + 0.01, 0.0), rng.uniform(0, 2 * math.pi), 0.14, 0.035, rng.uniform(-0.9, -0.4), 'daikon_leaf', col=0.75)
    return m


def doroage(lod):
    m = new('hx_doroage', lod, '泥上げの山：水路から掻き上げた泥と藻の山 1.6 × 1.0（高 0.42、濡れて暗い）に鋤を挿して柄が立つ、縁に垂れた藻、脇に泥を運ぶ箕')
    rng = random.Random(42003)
    seg = 10 if not lod else 7
    # 山：楕円の段 3（下ほど広い）＋頂
    rings = [(0.0, 0.80, 0.50), (0.16, 0.66, 0.40), (0.30, 0.44, 0.27), (0.40, 0.18, 0.12)]
    prev = None
    u, v = SWC['tsuchi']
    for y, rx, rz in rings:
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            j = rng.uniform(0.88, 1.08)
            ring.append((math.cos(a) * rx * j, y, math.sin(a) * rz * j))
        if prev:
            for i in range(seg):
                a0, a1 = prev[i], prev[(i + 1) % seg]
                b0, b1 = ring[i], ring[(i + 1) % seg]
                m.poly([a0, a1, b1, b0], ST, 0.42 + 0.06 * y, uvs=[(u, v)] * 4)
        prev = ring
    m.poly(list(reversed(prev)), ST, 0.5, uvs=[(u, v)] * seg)
    # 藻（緑の細い帯が縁に垂れる）
    for k in range(7 if not lod else 3):
        a = rng.uniform(0, 2 * math.pi)
        base = (math.cos(a) * 0.5, 0.2, math.sin(a) * 0.32)
        leaf(m, base, a, 0.32, 0.03, -0.55, 'negi', col=0.55)
    # 鋤（刃を山に挿し、柄が斜めに立つ）
    m.beam((0.18, 0.28, 0.05), (0.42, 1.22, -0.12), 0.034, 0.034, WD, AGED)
    obx(m, (0.16, 0.24, 0.06), (0.11, 0.13, 0.012), 'hagane', ax=K.norm((1.0, -0.25, 0.0)), az=K.norm((0.0, 0.0, 1.0)))
    # 箕（泥を運ぶ竹の箕を山の脇に伏せる）
    c = (-0.95, 0.0, 0.25)
    m.poly([K.add(c, (-0.28, 0.02, -0.24)), K.add(c, (0.28, 0.02, -0.24)), K.add(c, (0.22, 0.16, 0.22)), K.add(c, (-0.22, 0.16, 0.22))], ST, 0.9,
           uvs=[tuple(SWC['take'])] * 4)
    m.poly([K.add(c, (-0.22, 0.16, 0.22)), K.add(c, (0.22, 0.16, 0.22)), K.add(c, (0.28, 0.02, -0.24)), K.add(c, (-0.28, 0.02, -0.24))], ST, 0.75,
           uvs=[tuple(SWC['take'])] * 4)
    return m


def build_all():
    for lod in (0, 1):
        hatake(lod)
        daikon_kake(lod)
        doroage(lod)


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
    K.export_glb(bpy, OUT + '/src/humanuse_exp_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_humanuse_exp_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=humanuse_exp_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[HXKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/humanuse_exp_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[HXKIT]   %-14s %5d 面  LOD1 %4d  dims %s  mats %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims'], v['mats']))


main()
