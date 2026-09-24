"""南大門鳥居（LANDMARK_SOUTH_GATE）— 人間之里 V2 P5 R1 新資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_south_torii.py

參考：docs/reference/重點地標/鳥居.png（明神鳥居：笠木深灰反り、島木朱、額束無額、貫出、圓柱微收分、
上下黑銅箍（上箍圓紋）、石台座三段〔方板＋斜台＋饅頭〕、無稚兒柱、風化剝漆）。
尺寸 authority：layout_v2.json LANDMARK_SOUTH_GATE span 10（柱心距）、h 10；P4 placeholder 外包
（柱 1×10、笠木 13.5×0.8×1.1 頂 10.8、貫 11×0.55 @7.8）。新檔，不覆寫 Protected 的 大鳥居／博麗鳥居。
座標：Godot（+z 朝南＝入村方向），原點＝兩柱中點地面。
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/south_torii'
MATLIB = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')
TILE = {k: v['tile_m'] for k, v in MATLIB['materials'].items()}
MATS = ['V2_WoodRed', 'V2_Metal', 'V2_Stone']

SPAN = 10.0          # 柱心距（地面）
LEAN = 0.10          # 転び：柱頂內傾（每側）
EMBED = 0.25         # 台座埋深
Y_NUKI = (7.75, 8.28)
NUKI_HALF = 5.75
Y_SHIMA = 9.30       # 島木底（中央）
SHIMA_H = 0.40
SHIMA_HALF = 6.30
KASA_H = 0.60        # 笠木中央厚（含雨覆頂）
KASA_HALF = 6.75
SORI = 0.42          # 笠木端反り
SORI_X0 = 2.8        # 反り起點


def lift(x):
    a = abs(x)
    if a <= SORI_X0:
        return 0.0
    t = (a - SORI_X0) / (KASA_HALF - SORI_X0)
    return SORI * t ** 2


def pillar_x(y, side):
    """柱軸 x（含転び）：地面 SPAN/2，島木底 SPAN/2 − LEAN。"""
    t = y / Y_SHIMA
    return side * (SPAN / 2 - LEAN * t)


def loft(m, xs, profile, y0fn, mat, col=1.0, z_off=0.0, end_slant=0.0):
    """沿 x 的斷面放樣。profile：[(z, y)] 逆時針（從 +x 看）；y0fn(x)＝斷面基準高。"""
    rings = []
    for i, x in enumerate(xs):
        ring = []
        for (z, y) in profile:
            xx = x
            if i == 0:
                xx = x - end_slant * (y / max(p[1] for p in profile))
            elif i == len(xs) - 1:
                xx = x + end_slant * (y / max(p[1] for p in profile))
            ring.append((xx, y0fn(x) + y, z + z_off))
        rings.append(ring)
    n = len(profile)
    for i in range(len(xs) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(n):
            k2 = (k + 1) % n
            m.quad(a[k], b[k], b[k2], a[k2], mat, col, grain=K.X)
    m.poly(list(reversed(rings[0])), mat, col, grain=K.Y)
    m.poly(list(rings[-1]), mat, col, grain=K.Y)


def build(lod):
    # LOD1 ≤ 35 % LOD0（§14.8）：LOD1 柱 8 邊、笠木島木 6 段、不做饅頭
    seg = {0: 24, 1: 8, 2: 6}[lod]
    nx = {0: 28, 1: 6, 2: 4}[lod]
    m = K.Mesh('South_Torii_LOD%d' % lod, MATS, TILE)
    xs_k = [-KASA_HALF + 2 * KASA_HALF * i / nx for i in range(nx + 1)]
    xs_s = [-SHIMA_HALF + 2 * SHIMA_HALF * i / nx for i in range(nx + 1)]

    for side in (-1, 1):
        px = pillar_x(0.0, side)
        # ── 石台座三段：方板 → 斜台 → 饅頭（饅頭 LOD2 省略）
        if lod == 2:
            # 遠景（160 m 起）：台座一個方塊到 0.48、不做斜台與根巻（LOD2 ≤ 10 % LOD0）
            m.box((px - 0.80, -EMBED, -0.80), (px + 0.80, 0.48, 0.80), 'V2_Stone', 0.95, skip=('-y',))
        else:
            m.box((px - 0.85, -EMBED, -0.85), (px + 0.85, 0.20, 0.85), 'V2_Stone', 0.95, skip=('-y',))
        # 斜台（截錐方台）
        lo, hi = 0.78, 0.60
        y0, y1 = 0.20, 0.48
        ring0 = [(px - lo, y0, -lo), (px + lo, y0, -lo), (px + lo, y0, lo), (px - lo, y0, lo)]
        ring1 = [(px - hi, y1, -hi), (px + hi, y1, -hi), (px + hi, y1, hi), (px - hi, y1, hi)]
        for k in range(4 if lod < 2 else 0):
            k2 = (k + 1) % 4
            m.quad(ring0[k], ring0[k2], ring1[k2], ring1[k], 'V2_Stone', 1.0)
        if lod < 2:
            m.poly([ring1[3], ring1[2], ring1[1], ring1[0]][::-1], 'V2_Stone', 1.0)
        if lod < 1:
            prof = [(0.48, 0.56), (0.56, 0.58), (0.66, 0.54), (0.78, 0.48)]
            for (ya, ra), (yb, rb) in zip(prof, prof[1:]):
                m.cyl((px, ya, 0), (px, yb, 0), ra, rb, seg, 'V2_Stone', 1.0, caps=(False, False))
        # ── 柱：根巻（黑銅）＋柱身（朱、收分、転び）＋上箍（黑銅、圓紋）
        top = Y_SHIMA + lift(pillar_x(Y_SHIMA, side)) + 0.04
        base_y = 0.78 if lod < 1 else 0.48
        p0 = (px, base_y, 0.0)
        p1 = (pillar_x(top, side), top, 0.0)
        m.cyl(p0, p1, 0.45, 0.40, seg, 'V2_WoodRed', 1.0, caps=(False, False))
        if lod < 2:
            y_nm = 1.55
            pb = (pillar_x(y_nm, side), y_nm, 0.0)
            m.cyl(p0, pb, 0.475, 0.470, seg, 'V2_Metal', 1.0, caps=(False, True))
            m.cyl((px, base_y - 0.02, 0), (px, base_y + 0.08, 0), 0.50, 0.50, seg, 'V2_Metal', 1.0,
                  caps=(False, True))
            yb0, yb1 = Y_SHIMA - 0.42, Y_SHIMA - 0.08
            q0 = (pillar_x(yb0, side), yb0, 0.0)
            q1 = (pillar_x(yb1, side), yb1, 0.0)
            m.cyl(q0, q1, 0.43, 0.425, seg, 'V2_Metal', 1.0, caps=(True, False))
            if lod == 0:
                # 圓紋：前後各一片 r 0.13 圓牌（貼上箍外面）
                yc = (yb0 + yb1) / 2
                for zs in (1, -1):
                    cx = pillar_x(yc, side)
                    c0 = (cx, yc, zs * 0.415)
                    c1 = (cx, yc, zs * 0.455)
                    m.cyl(c0, c1, 0.13, 0.13, 12, 'V2_Metal', 1.35, caps=(False, True))
        elif lod == 1:
            m.cyl((px, base_y, 0), (px, base_y + 1.0, 0), 0.475, 0.47, seg, 'V2_Metal', 1.0, caps=(False, False))

    # ── 貫（兩端出柱 0.5 m）＋楔
    m.box((-NUKI_HALF, Y_NUKI[0], -0.16), (NUKI_HALF, Y_NUKI[1], 0.16), 'V2_WoodRed', 0.97, grain=K.X)
    if lod == 0:
        for side in (-1, 1):
            wx = pillar_x(Y_NUKI[1], side) + side * 0.52
            m.box((wx - 0.06, Y_NUKI[0] - 0.05, -0.10), (wx + 0.06, Y_NUKI[1] + 0.07, 0.10), 'V2_WoodRed', 0.8)
    # ── 額束（無額）
    m.box((-0.27, Y_NUKI[1], -0.14), (0.27, Y_SHIMA + 0.02, 0.14), 'V2_WoodRed', 1.0, grain=K.Y)
    # ── 島木（朱）
    loft(m, xs_s, [(0.31, 0.0), (0.31, SHIMA_H), (-0.31, SHIMA_H), (-0.31, 0.0)],
         lambda x: Y_SHIMA + lift(x), 'V2_WoodRed', 1.0, end_slant=0.10)
    # ── 笠木（黑銅包板，雨覆頂微起脊）
    yk = Y_SHIMA + SHIMA_H
    loft(m, xs_k, [(0.42, 0.0), (0.50, 0.48), (0.0, KASA_H), (-0.50, 0.48), (-0.42, 0.0)],
         lambda x: yk + lift(x), 'V2_Metal', 0.92, end_slant=0.16)
    return m


def main():
    K.clear_scene(bpy)
    bm = K.blender_mats(bpy, MATS)
    objs = []
    stats = {}
    for lod in (0, 1, 2):
        m = build(lod)
        objs.append(m.to_blender(bpy, bmats=bm))
        stats['LOD%d' % lod] = m.tris()
        if lod == 0:
            xs = [p[0] for p in m.v]
            ys = [p[1] for p in m.v]
            zs = [p[2] for p in m.v]
            stats['aabb'] = [[min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)]]
    K.export_glb(bpy, OUT + '/src/south_torii.glb', objs)
    top = SHIMA_H + KASA_H + Y_SHIMA
    spec = {
        '_note': '南大門鳥居 資產規格（build_south_torii.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、verify_village_v2_hero_gate.gd 讀取）。',
        'id': 'south_torii', 'landmark': 'LANDMARK_SOUTH_GATE', 'kind': 'landmark', 'budget_class': '鳥居',
        'glb': 'res://assets/village_v2/south_torii/src/south_torii.glb',
        'scene': 'res://assets/village_v2/south_torii/south_torii.scn',
        'lod_objects': ['South_Torii_LOD0', 'South_Torii_LOD1', 'South_Torii_LOD2'],
        'lod_ranges_m': [0, 60, 160, 700],
        'budget': {'lod0': 5000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': {k: MATLIB['materials'][k]['tres'] for k in MATS},
        'spec': {'span_m': SPAN, 'height_m': 10.0, 'envelope_top_m': 10.8, 'kasagi_len_m': 2 * KASA_HALF,
                 'nuki_y_m': Y_NUKI[0], 'embed_m': EMBED, 'top_center_m': round(top, 3),
                 'top_end_m': round(top + SORI, 3), 'tolerance_m': 0.3},
        'gate_spec': {
            # 放置：P0 地標節點原點（兩柱中點地面、yaw 0）；取代 _torii() 的 placeholder 子節點「Torii」
            'placement': 'anchor', 'anchor': 'Landmarks/LANDMARK_SOUTH_GATE', 'replaces': 'Torii',
            'p4_id': '', 'parcel': '', 'road': 'EntranceRoad',
            'size': {'x_half_max': KASA_HALF + 0.30, 'z_min': -0.95, 'z_max': 0.95, 'top': [10.0, 10.8],
                     'bottom': -EMBED},
            'span': {'axis_m': SPAN, 'clear_min': 8.5},
            'ground': [
                {'name': '台座%s' % ('左' if s < 0 else '右'), 'rect': [s * SPAN / 2 - 0.85, -0.85, s * SPAN / 2 + 0.85, 0.85],
                 'bottom': -EMBED, 'top': 0.20, 'embed_max': 0.40} for s in (-1, 1)],
            'walkway': {'rect': [-3.9, -1.2, 3.9, 1.2], 'head': 1.95, 'min_clear': 6.0, 'step': 0.5},
            'entry': [0.0, 3.0], 'inside': [-SPAN / 2, 0.0]},
        'collision': [
            {'type': 'cylinder', 'center': [s * SPAN / 2, (Y_NUKI[0] - EMBED) / 2, 0], 'radius': 0.5,
             'height': Y_NUKI[0] + EMBED, 'name': 'Pillar_%s' % ('L' if s < 0 else 'R')} for s in (-1, 1)] + [
            {'type': 'box', 'center': [s * SPAN / 2, (0.48 - EMBED) / 2, 0], 'size': [1.7, 0.48 + EMBED, 1.7],
             'name': 'Base_%s' % ('L' if s < 0 else 'R')} for s in (-1, 1)],
        'measured_blender': stats,
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[TORII]', stats)


main()
