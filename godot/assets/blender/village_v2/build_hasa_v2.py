"""人間之里 V2 P10 R4c：稲架 v2（st_hasa_v2）— 新資產（不覆寫封存的 street_kit／st_hasa）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_hasa_v2.py

使用者 2026-10-09 D9：R4c st_hasa LIMITED REPAIR——修正竹竿與稲束的幾何穿插。
根因（MASTER AUDIT R4c-01，build_street_kit.py hasa() 606–621）：
  稲束兩半的頂端圓心離竿軸 0.03 m < 束半徑 0.06＋竿半徑 0.025 → 竿穿過稲束約 5 cm；上段穗端 y 1.12 碰下段束頭；X 脚斜穿中央束列。
v2：
  · 稲束「跨竿」：束頭（結び）是一段橫跨竿頂的短束（坐在竿頂上、不穿竿），兩半從竿兩側外掛（與竿淨距 ≥ 0.012 m），穗端朝下外開
  · 上段束長 0.36–0.42（穗端 ≥ 下段束頭頂 + 0.03）；下段 0.38–0.44
  · X 脚 3 組位置不變（x −1.45／0／1.45），束列避開脚（上段 |x − 脚| ≥ 0.22、下段 ≥ 0.36：脚下部外開）
  · 束長／開角／穗端位置不規則（固定 seed）
材質：與 st_hasa 相同（V2_Wood 脚、ST_Street atlas 的 take 竿／ine 稲束）。另寫 src/hasa_v2_spec.json（全部基本體參數）供 Godot 端 gate 做穿插量測。
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
SRC_KIT = G + '/assets/village_v2/street_kit'
OUT = G + '/assets/village_v2/r4c_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(SRC_KIT + '/atlas.json')
REG = AT['regions']
SWC = AT['swatches']
WD = 'V2_Wood'
ST = 'ST_Street'
MATS = [WD, ST]
TILE = {WD: ML['V2_Wood']['tile_m'], ST: 1.0}
OLD = (0.52, 0.48, 0.43)

MODS = {}
INFO = {}
SPEC = {}

POLE_R = 0.025
POLE_Y = (1.1, 1.6)
LEGS_X = (-1.45, 0.0, 1.45)
CLEAR = 0.012
HALF_R = (0.042, 0.068)       # 半束：頭→穗端半徑
TIE_R = 0.028                 # 束頭（跨竿の結び）半徑
LEG_GAP = (0.22, 0.36)       # 上段／下段：X 脚下部外開，下段束尖要離脚更遠


def new(name, lod, note=''):
    n = name + ('_l1' if lod else '')
    m = K.Mesh(n, MATS, TILE)
    MODS[n] = m
    INFO[n] = note
    SPEC[n] = {'poles': [], 'legs': [], 'sheaves': []}
    return m


def swr(key):
    u, v = SWC[key]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


def cy(m, p0, p1, r0, r1, seg, key, caps=(True, True)):
    m.cyl(p0, p1, r0, r1, seg, ST, 1.0, caps=caps, uv_atlas=swr(key))


def rcy(m, p0, p1, r0, r1, seg, region, caps=(True, True)):
    m.cyl(p0, p1, r0, r1, seg, ST, 1.0, caps=caps, uv_atlas=REG[region])


def bay_positions(n, lod, gap):
    """x 位置：兩個柱間（−1.45..0、0..1.45）各自均分，離脚 ≥ gap。"""
    per = n // 2
    if lod:
        per = max(2, per // 2)
    xs = []
    for a, b in ((LEGS_X[0], LEGS_X[1]), (LEGS_X[1], LEGS_X[2])):
        lo = a + gap
        hi = b - gap
        for i in range(per):
            xs.append(lo + (hi - lo) * i / max(1, per - 1))
    return xs


def hasa_v2(lod):
    m = new('st_hasa_v2', lod, '稲架 v2 3.0 × 0.8（高 1.90）：X 脚 3 組＋横竿 2 段（1.10／1.60）、稲束を竿に跨がせて掛ける（上段 12・下段 10、穂が下、竿と束は非貫通）')
    sp = SPEC[m.name]
    rng = random.Random(20401)
    for x in LEGS_X:
        for a, b in (((x - 0.35, 0.0, 0.3), (x + 0.1, 1.9, -0.05)), ((x + 0.35, 0.0, -0.3), (x - 0.1, 1.9, 0.05))):
            m.beam(a, b, 0.05, 0.05, WD, OLD)
            sp['legs'].append({'a': a, 'b': b, 'w': 0.05})
    for y in POLE_Y:
        cy(m, (-1.55, y, 0.0), (1.55, y, 0.0), POLE_R, POLE_R * 0.9, 6, 'take', caps=(False, True))
        sp['poles'].append({'a': (-1.55, y, 0.0), 'b': (1.55, y, 0.0), 'r': POLE_R})
    for row, (y, n, L0, L1) in enumerate(((1.6, 12, 0.36, 0.42), (1.1, 10, 0.38, 0.44))):
        for x in bay_positions(n, lod, LEG_GAP[row]):
            x = x + rng.uniform(-0.015, 0.015)
            # 束頭：跨竿の結び（軸＝z），坐在竿頂（底＝竿頂＋0.001）
            ty = y + POLE_R + TIE_R + 0.001
            rcy(m, (x, ty, -0.095), (x, ty, 0.095), TIE_R, TIE_R, 5 if lod else 6, 'ine', caps=(True, True))
            sh = {'tie': {'a': (x, ty, -0.095), 'b': (x, ty, 0.095), 'r': TIE_R}, 'halves': []}
            for s in (-1, 1):
                zt = s * (POLE_R + HALF_R[0] + CLEAR)
                top = (x, y + 0.03, zt)
                Lh = rng.uniform(L0, L1)
                spread = rng.uniform(0.07, 0.11)
                bot = (x + rng.uniform(-0.025, 0.025), y + 0.03 - Lh, s * (abs(zt) + spread))
                rcy(m, top, bot, HALF_R[0], HALF_R[1], 5 if lod else 6, 'ine', caps=(True, True))
                sh['halves'].append({'a': top, 'b': bot, 'r0': HALF_R[0], 'r1': HALF_R[1]})
            sp['sheaves'].append(sh)
    return m


def dims(m):
    xs = [p[0] for p in m.v]
    ys = [p[1] for p in m.v]
    zs = [p[2] for p in m.v]
    return [round(min(xs), 4), round(min(ys), 4), round(min(zs), 4), round(max(xs), 4), round(max(ys), 4), round(max(zs), 4)]


def main():
    K.clear_scene(bpy)
    for lod in (0, 1):
        hasa_v2(lod)
    bm = K.blender_mats(bpy, MATS)
    objs = []
    manifest = {}
    for name, m in MODS.items():
        ob = m.to_blender(bpy, bmats=bm)
        objs.append(ob)
        tri = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        manifest[name] = {'tris': tri, 'dims': dims(m), 'mats': sorted({m.mats[f[1]] for f in m.f}), 'note': INFO[name]}
    os.makedirs(OUT + '/src', exist_ok=True)
    K.export_glb(bpy, OUT + '/src/r4c_kit.glb', objs)
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_hasa_v2.py 產生（P10 R4c Pilot）；Godot 端 tools/verify_village_v2_prop_fix.gd -- --convert 轉成 maps/village_v2/gen/r4c/<名>.res（材質＝_matlib V2_Wood／street_kit ST_Street）。',
        'materials': MATS, 'modules': manifest, 'total_tris': sum(v['tris'] for v in manifest.values())})
    K.write_json(OUT + '/src/hasa_v2_spec.json', {'_note': '基本體參數（Godot 座標、m）：poles／legs／sheaves（tie＋2 halves）；gate 用來量穿插。',
                                                  'pole_r': POLE_R, 'clear': CLEAR, 'modules': SPEC})
    for n, v in manifest.items():
        print('[R4C] %-16s %5d 面  dims %s' % (n, v['tris'], v['dims']))


main()
