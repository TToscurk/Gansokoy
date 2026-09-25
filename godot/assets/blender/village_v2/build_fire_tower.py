"""火見櫓（LANDMARK_TOWER）— 人間之里 V2 P5 R5 新資產（木構新做；舊 Tripo 版 Protected，只作輪廓參考、未讀取）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_fire_tower.py

外觀 authority：docs/reference/重點地標/火見橹.png（vision 建模 brief）：四根粗角柱向下外八、三段 X 斜撐、
各柱獨立石積基礎、單側近垂直木梯、出挑方形木台＋兩道扶欄、四柱撐的陡切妻板葺屋根（露垂木、開放山牆）、
屋根下正中吊一口暗銅半鐘（直徑約台寬 1/4）；無招牌、無燈籠。
尺寸 authority：P0 LANDMARK_TOWER（box 7 × 18 × 7，P4 核准保留；沒有 P4 灰盒）＋地塊 P_LM_TOWER（11 × 11）。
  全部在 P0 量體內：外框 x、z ±3.50、最高點 ≤ 18.0。
座標：Godot；原點＝P0 地標原點（地塊中心）、y 0＝地標節點高度（地塊整平面）、+z＝南。
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

X, Y, Z = K.X, K.Y, K.Z
G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/fire_tower'
MATLIB = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')
TILE = {k: v['tile_m'] for k, v in MATLIB['materials'].items()}
MATS = ['V2_Wood', 'V2_Stone', 'V2_Metal']

# ── 主構
LEG_B, LEG_T = 2.55, 1.60      # 柱心半距：柱腳 → 台下
Y_FOOT, Y_DECK = 0.45, 12.60   # 柱腳（石基礎頂）、台下緣
LEG_W = 0.30
TIES = [2.60, 6.00, 9.30, Y_DECK]   # 貫（水平繫材）高度；三段 X 斜撐在其間
PED = 0.95                      # 石基礎邊長（上段）
PED_BOT = -0.40
DECK_H, DECK_T = 2.25, 0.20     # 台半寬、厚
RAIL = (13.30, 13.85)           # 兩道扶欄
Y_RAIL_TOP = 13.92
POST_H = 1.90                   # 屋根柱半距
Y_EAVE, Y_RIDGE = 15.35, 17.35  # 屋根：簷口、棟（屋面）
ROOF_X, ROOF_Z = 2.90, 2.95     # 屋面外緣（含出簷）
RIDGE_CAP = 0.18
TOP = Y_RIDGE + RIDGE_CAP + 0.26   # 棟端小飾
# 半鐘
BELL_Y0, BELL_Y1 = 14.30, 15.05
# 梯子：−x 面外側，柱腳 x −3.20 → 台邊 x −2.30（頂端伸出台面 1.0 m 當扶手）
LAD_Z = 0.30
LAD_X0, LAD_Y0 = -3.20, -0.05
LAD_X1, LAD_Y1 = -2.33, 13.80


def leg_xz(y, sx, sz):
    t = (y - Y_FOOT) / (Y_DECK - Y_FOOT)
    h = LEG_B + (LEG_T - LEG_B) * t
    return (sx * h, y, sz * h)


def lad_x(y):
    return LAD_X0 + (LAD_X1 - LAD_X0) * (y - LAD_Y0) / (LAD_Y1 - LAD_Y0)


def pedestals(m, lod):
    for sx in (-1, 1):
        for sz in (-1, 1):
            cx, cz = sx * LEG_B, sz * LEG_B
            if lod == 0:
                # 野面積：下段略寬（2×2 塊）、上段收分（錯縫 2 塊）＋笠石
                h = PED / 2 + 0.05
                for i, (a0, a1) in enumerate(((-h, -0.02), (0.02, h))):
                    for j, (b0, b1) in enumerate(((-h, 0.03), (0.07, h))):
                        m.box((cx + a0, PED_BOT, cz + b0), (cx + a1, 0.10 - 0.03 * ((i + j) % 2), cz + b1), 'V2_Stone',
                              0.74 + 0.05 * ((i * 2 + j) % 3), skip=('-y',))
                m.box((cx - h, PED_BOT, cz - h), (cx + h, 0.04, cz + h), 'V2_Stone', 0.60, skip=('-y', '+y'))
                h2 = PED / 2
                for k, (a0, a1) in enumerate(((-h2, 0.12), (0.16, h2))):
                    m.box((cx - h2, 0.10, cz + a0), (cx + h2, Y_FOOT - 0.08, cz + a1), 'V2_Stone', 0.80 + 0.06 * k,
                          skip=('-y',))
                m.box((cx - PED / 2 + 0.06, Y_FOOT - 0.08, cz - PED / 2 + 0.06),
                      (cx + PED / 2 - 0.06, Y_FOOT, cz + PED / 2 - 0.06), 'V2_Stone', 0.92, skip=('-y',))
            else:
                m.box((cx - PED / 2 - 0.05, PED_BOT, cz - PED / 2 - 0.05), (cx + PED / 2 + 0.05, Y_FOOT, cz + PED / 2 + 0.05),
                      'V2_Stone', 0.84, skip=('-y',))


def frame(m, lod):
    for sx in (-1, 1):
        for sz in (-1, 1):
            a = leg_xz(Y_FOOT, sx, sz)
            b = leg_xz(Y_DECK, sx, sz)
            m.beam(a, b, LEG_W, LEG_W, 'V2_Wood', 0.56, up=X)
    faces = [((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))]
    ties = TIES if lod <= 1 else [TIES[-1]]
    for y in ties:
        for (p, q) in faces:
            a, b = leg_xz(y, *p), leg_xz(y, *q)
            # 貫：柱外皮再出 0.25 m（木鼻）
            d = K.norm(K.sub(b, a))
            m.beam(K.sub(a, K.mul(d, 0.25)), K.add(b, K.mul(d, 0.25)), 0.16, 0.22, 'V2_Wood', 0.60, up=Y)
    if lod == 0:
        for i in range(3):
            ym = (TIES[i] + TIES[i + 1]) / 2
            for (p, q) in faces:
                a, b = leg_xz(ym, *p), leg_xz(ym, *q)
                c = K.mul(K.add(a, b), 0.5)
                out = K.norm((c[0], 0.0, c[2]))
                c = K.add(c, K.mul(out, 0.10))
                ax = K.norm(K.sub(b, a))
                m.obox(c, (0.16, 0.16, 0.012), 'V2_Metal', 0.85, ax=ax, ay=Y, az=out, skip=('-z',))
                m.cyl(K.add(c, K.mul(out, 0.01)), K.add(c, K.mul(out, 0.06)), 0.04, 0.04, 6, 'V2_Metal', 0.9,
                      caps=(False, True))
    if lod <= 1:
        for i in range(3):
            y0, y1 = TIES[i] + 0.11, TIES[i + 1] - 0.11
            for (p, q) in faces:
                for (u, v) in ((p, q), (q, p)):
                    m.beam(leg_xz(y0, *u), leg_xz(y1, *v), 0.14, 0.18, 'V2_Wood', 0.62, up=X if u[0] == v[0] else Z,
                           skip_ends=True)


def deck(m, lod):
    h = DECK_H
    m.box((-h, Y_DECK, -h), (h, Y_DECK + DECK_T, h), 'V2_Wood', 0.66, grain=X)
    if lod == 0:
        # 根太（台下，四周出挑的受け）
        for s in (-1, 1):
            m.box((-h, Y_DECK - 0.20, s * (h - 0.12) - 0.08), (h, Y_DECK, s * (h - 0.12) + 0.08), 'V2_Wood', 0.55, grain=X,
                  skip=('+y',))
            m.box((s * (h - 0.12) - 0.08, Y_DECK - 0.20, -h), (s * (h - 0.12) + 0.08, Y_DECK, h), 'V2_Wood', 0.55, grain=Z,
                  skip=('+y',))
        # 板目（淺溝）
        for k in range(1, 9):
            x = -h + 2 * h * k / 9
            m.box((x - 0.01, Y_DECK + DECK_T, -h + 0.02), (x + 0.01, Y_DECK + DECK_T + 0.006, h - 0.02), 'V2_Wood', 0.40,
                  grain=Z, skip=('-y',))
    if lod == 2:
        return
    # 扶欄：角柱＋中柱，兩道橫欄；−x 面中央留梯口（z ±0.45）
    yb = Y_DECK + DECK_T
    e = h - 0.06
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.box((sx * e - 0.06, yb, sz * e - 0.06), (sx * e + 0.06, Y_RAIL_TOP, sz * e + 0.06), 'V2_Wood', 0.58,
                  skip=('-y',))
    mids = [((0.0, e), X), ((0.0, -e), X), ((e, 0.0), Z)]
    for ((x, z), _) in (mids if lod == 0 else ()):
        m.box((x - 0.05, yb, z - 0.05), (x + 0.05, Y_RAIL_TOP - 0.06, z + 0.05), 'V2_Wood', 0.58, skip=('-y',))
    for y in (RAIL if lod == 0 else RAIL[1:]):
        for sz in (-1, 1):
            m.box((-e, y - 0.04, sz * e - 0.04), (e, y + 0.04, sz * e + 0.04), 'V2_Wood', 0.60, grain=X)
        m.box((e - 0.04, y - 0.04, -e), (e + 0.04, y + 0.04, e), 'V2_Wood', 0.60, grain=Z)
        for sz in (-1, 1):   # −x 面：梯口兩側
            z0, z1 = sorted((sz * e, sz * 0.45))
            m.box((-e - 0.04, y - 0.04, z0), (-e + 0.04, y + 0.04, z1), 'V2_Wood', 0.60, grain=Z)
    for sz in (-1, 1):
        m.box((-e - 0.05, yb, sz * 0.45 - 0.05), (-e + 0.05, Y_RAIL_TOP - 0.06, sz * 0.45 + 0.05), 'V2_Wood', 0.58,
              skip=('-y',))


def roof(m, lod):
    yb = Y_DECK + DECK_T
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.box((sx * POST_H - 0.09, yb, sz * POST_H - 0.09), (sx * POST_H + 0.09, Y_EAVE + 0.10, sz * POST_H + 0.09),
                  'V2_Wood', 0.56, skip=('-y',))
    # 軒桁（x 向兩側）＋梁（z 向；棟木在 x＝0）
    for sz in (-1, 1) if lod <= 1 else ():
        m.box((-POST_H - 0.35, Y_EAVE - 0.05, sz * POST_H - 0.10), (POST_H + 0.35, Y_EAVE + 0.15, sz * POST_H + 0.10),
              'V2_Wood', 0.55, grain=X)
    for sx in (-1, 1) if lod <= 1 else ():
        m.box((sx * POST_H - 0.10, Y_EAVE - 0.05, -ROOF_Z + 0.15), (sx * POST_H + 0.10, Y_EAVE + 0.15, ROOF_Z - 0.15),
              'V2_Wood', 0.55, grain=Z)
    slope = (Y_RIDGE - Y_EAVE) / ROOF_X
    sec = math.sqrt(1 + slope * slope)
    th = 0.10
    for sx in (-1, 1):
        # 屋面板（厚 th；沿斜面）：從棟（x 0）到簷（x ±ROOF_X）
        dsl = K.norm((sx * 1.0, -slope, 0.0))
        n = K.norm((sx * slope, 1.0, 0.0))
        L = ROOF_X * sec
        c = K.add((0.0, Y_RIDGE, 0.0), K.mul(dsl, L / 2))
        c = K.add(c, K.mul(n, -th / 2))
        m.obox(c, (L / 2, th / 2, ROOF_Z), 'V2_Wood', 0.46, ax=dsl, ay=n, az=Z, grain=dsl)
        if lod == 0:
            # 板葺の段（14 段重ね：每段下緣露出厚 0.035、色略跳）
            for k in range(14):
                s0, s1 = L * k / 14, L * (k + 1) / 14
                p = K.add(K.add((0.0, Y_RIDGE, 0.0), K.mul(dsl, (s0 + s1) / 2)), K.mul(n, 0.02 + 0.012 * (k % 2)))
                m.obox(p, ((s1 - s0) / 2 + 0.03, 0.02, ROOF_Z + 0.02), 'V2_Wood', 0.40 + 0.05 * ((k * 3) % 4),
                       ax=dsl, ay=n, az=Z, grain=dsl, skip=('-y',))
            # 垂木（露出）
            for k in range(7):
                z = -ROOF_Z + 0.25 + k * (2 * ROOF_Z - 0.5) / 6
                a = (0.0, Y_RIDGE - th - 0.05, z)
                b = (sx * (ROOF_X - 0.05), Y_EAVE - th - 0.05, z)
                m.beam(a, b, 0.07, 0.09, 'V2_Wood', 0.50, up=Y)
        # 破風板（山牆兩端、沿斜邊）
        if lod <= 1:
            for sz in (-1, 1):
                a = (0.0, Y_RIDGE + 0.02, sz * (ROOF_Z + 0.03))
                b = (sx * (ROOF_X + 0.05), Y_EAVE - 0.06, sz * (ROOF_Z + 0.03))
                m.beam(a, b, 0.06, 0.30, 'V2_Wood', 0.50, up=Y)
    # 棟：棟木＋棟押さえ、兩端小飾
    m.box((-0.16, Y_RIDGE - 0.06, -ROOF_Z - 0.08), (0.16, Y_RIDGE + RIDGE_CAP, ROOF_Z + 0.08), 'V2_Wood', 0.42, grain=Z)
    for sz in (-1, 1):   # 棟端小飾（LOD2 也留：外框頂）
        z0, z1 = sorted((sz * (ROOF_Z - 0.10), sz * (ROOF_Z + 0.12)))
        m.box((-0.10, Y_RIDGE + RIDGE_CAP, z0), (0.10, TOP, z1), 'V2_Wood', 0.40, grain=Y, skip=('-y',))
    if lod <= 1:
        # 開放山牆：梁上束（棟木受け）
        for sz in (-1, 1):
            m.box((-0.08, Y_EAVE + 0.15, sz * POST_H - 0.08), (0.08, Y_RIDGE - 0.10, sz * POST_H + 0.08), 'V2_Wood', 0.52)
            m.box((-POST_H, Y_EAVE + 0.15, sz * POST_H - 0.08), (POST_H, Y_EAVE + 0.35, sz * POST_H + 0.08), 'V2_Wood',
                  0.55, grain=X)


def bell(m, lod):
    seg = 16 if lod == 0 else (10 if lod == 1 else 6)
    y0, y1 = BELL_Y0, BELL_Y1
    # 吊り木（棟木 → 鐘）＋龍頭
    m.box((-0.07, y1, -0.07), (0.07, Y_RIDGE - 0.10, 0.07), 'V2_Wood', 0.50, skip=('+y', '-y'))
    if lod <= 1:
        m.box((-POST_H, Y_EAVE + 0.40, -0.09), (POST_H, Y_EAVE + 0.58, 0.09), 'V2_Wood', 0.52, grain=X)
        m.cyl((0, y1, 0), (0, y1 + 0.18, 0), 0.10, 0.06, seg // 2 if seg >= 8 else 4, 'V2_Metal', 0.85)
    if lod == 2:
        m.cyl((0, y1, 0), (0, y0, 0), 0.30, 0.54, 6, 'V2_Metal', 1.0, caps=(False, True))
        return
    # 鐘身：肩 → 胴 → 口（外緣略張）
    m.cyl((0, y1, 0), (0, y1 - 0.14, 0), 0.20, 0.40, seg, 'V2_Metal', 1.0, caps=(True, False))
    m.cyl((0, y1 - 0.14, 0), (0, y0 + 0.12, 0), 0.40, 0.47, seg, 'V2_Metal', 1.0, caps=(False, False))
    m.cyl((0, y0 + 0.12, 0), (0, y0, 0), 0.47, 0.54, seg, 'V2_Metal', 0.92, caps=(False, True))
    if lod == 0:
        for yy in (y1 - 0.30, y0 + 0.26):   # 帶
            m.cyl((0, yy, 0), (0, yy + 0.05, 0), 0.46, 0.46, seg, 'V2_Metal', 0.70)


def ladder(m, lod):
    for sz in (-1, 1):
        a = (LAD_X0, LAD_Y0, sz * LAD_Z)
        b = (LAD_X1, LAD_Y1, sz * LAD_Z)
        m.beam(a, b, 0.07, 0.10, 'V2_Wood', 0.54, up=X)
    if lod >= 1:
        return
    step = 0.32
    y = 0.30
    while y < Y_DECK + 0.05:
        x = lad_x(y)
        if lod == 0:
            m.cyl((x, y, -LAD_Z + 0.03), (x, y, LAD_Z - 0.03), 0.030, 0.030, 8, 'V2_Wood', 0.58, caps=(False, False))
        else:
            m.box((x - 0.03, y - 0.03, -LAD_Z + 0.03), (x + 0.03, y + 0.03, LAD_Z - 0.03), 'V2_Wood', 0.58, grain=Z)
        y += step
    # 控え（梯子 → 貫）
    for yy in (TIES[1], TIES[2]):
        xl = leg_xz(yy, -1, 1)[0]
        for sz in (-1, 1):
            m.beam((lad_x(yy), yy, sz * LAD_Z), (xl - 0.10, yy, sz * LAD_Z), 0.06, 0.08, 'V2_Wood', 0.56, up=Y)


def build(lod):
    m = K.Mesh('FireTower_LOD%d' % lod, MATS, TILE)
    pedestals(m, lod)
    frame(m, lod)
    deck(m, lod)
    roof(m, lod)
    bell(m, lod)
    ladder(m, lod)
    return m


def tri_count(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    out = {}
    for o in [o for o in bpy.data.objects if o not in before]:
        if o.type == 'MESH':
            out[o.name.split('.')[0]] = sum(len(p.vertices) - 2 for p in o.data.polygons)
        bpy.data.objects.remove(o, do_unlink=True)
    return out


def main():
    K.clear_scene(bpy)
    bm = K.blender_mats(bpy, MATS)
    objs, aabb = [], {}
    for lod in (0, 1, 2):
        m = build(lod)
        objs.append(m.to_blender(bpy, bmats=bm))
        xs, ys, zs = [p[0] for p in m.v], [p[1] for p in m.v], [p[2] for p in m.v]
        aabb[lod] = [[round(min(xs), 3), round(min(ys), 3), round(min(zs), 3)],
                     [round(max(xs), 3), round(max(ys), 3), round(max(zs), 3)]]
    glb = OUT + '/src/fire_tower.glb'
    K.export_glb(bpy, glb, objs)
    cnt = tri_count(glb)     # 面數以匯出後 GLB 為準（exporter 會丟零面積面）
    stats = {'LOD%d' % l: cnt['FireTower_LOD%d' % l] for l in (0, 1, 2)}
    lad_pts = [[x, y, sz * (LAD_Z + 0.06)] for (x, y) in ((LAD_X0 - 0.08, LAD_Y0), (LAD_X0 + 0.08, LAD_Y0),
                                                          (LAD_X1 - 0.08, LAD_Y1), (LAD_X1 + 0.08, LAD_Y1))
               for sz in (-1, 1)]
    ped = PED + 0.10
    pc = ped + 0.16      # 碰撞外擴（與石基礎可見面錯開，避免射線掠面）
    spec = {
        '_note': '火見櫓 資產規格（build_fire_tower.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、'
                 'verify_village_v2_hero_gate.gd 讀取）。沒有 P4 灰盒：放在 P0 地標原點（anchor），取代 P0 佔位 Block；'
                 '尺寸以 P0 量體 7 × 18 × 7 為上限、地塊 P_LM_TOWER 為界。舊 Tripo 火見櫓（Protected）未讀取、未改動。',
        'id': 'fire_tower', 'landmark': 'LANDMARK_TOWER', 'kind': 'landmark', 'budget_class': '火見櫓',
        'glb': 'res://assets/village_v2/fire_tower/src/fire_tower.glb',
        'scene': 'res://assets/village_v2/fire_tower/fire_tower.scn',
        'lod_objects': ['FireTower_LOD0', 'FireTower_LOD1', 'FireTower_LOD2'],
        'lod_ranges_m': [0, 60, 160, 700],
        'budget': {'lod0': 20000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': {k: MATLIB['materials'][k]['tres'] for k in MATS},
        'spec': {'p0_box_m': [7, 18, 7], 'leg_half_span_m': [LEG_B, LEG_T], 'deck_y_m': Y_DECK + DECK_T,
                 'deck_m': 2 * DECK_H, 'eave_y_m': Y_EAVE, 'ridge_y_m': Y_RIDGE, 'top_m': TOP,
                 'bell_d_m': 1.08, 'bell_y_m': [BELL_Y0, BELL_Y1], 'ladder': '−x 面（朝 MainStreet）',
                 'design': '四柱外八、三段 X 斜撐、獨立石基礎、出挑方台＋兩道扶欄、陡切妻板葺（露垂木、開放山牆）、半鐘'},
        'gate_spec': {
            'placement': 'anchor', 'anchor': 'Landmarks/LANDMARK_TOWER', 'replaces': 'Block',
            'p4_id': '', 'parcel': 'P_LM_TOWER', 'road': 'MainStreet',
            'size': {'x_half_max': 3.50, 'z_min': -3.50, 'z_max': 3.50, 'top': [round(TOP - 0.05, 3), 18.0],
                     'bottom': PED_BOT},
            'ground': [{'name': '石基礎%s%s' % (a, b), 'rect': [sx * LEG_B - ped / 2, sz * LEG_B - ped / 2,
                                                              sx * LEG_B + ped / 2, sz * LEG_B + ped / 2],
                        'bottom': PED_BOT, 'top': Y_FOOT, 'embed_max': 0.50}
                       for (sx, a) in ((-1, '西'), (1, '東')) for (sz, b) in ((-1, '北'), (1, '南'))] + [
                {'name': '梯腳', 'rect': [LAD_X0 - 0.08, -LAD_Z - 0.06, LAD_X0 + 0.08, LAD_Z + 0.06], 'bottom': LAD_Y0,
                 'top': 0.30, 'embed_max': 0.20}],
            # 柱間（四面開口 4.1 m）可以走進去：櫓下步行帶
            'walkway': {'rect': [-1.4, -1.4, 1.4, 1.4], 'head': 1.95, 'min_clear': 2.3, 'step': 0.35},
            'entry': [0.0, 5.0], 'inside': [LEG_B, LEG_B],
            # 鏡位（局部 xz）：市場內，南 34 m 被 B_P_MKT_001 擋 → 改從 MainStreet（西 11.6 m）與北側空地看；
            # 塔高 17.8 m，3P 鏡頭 ≤ 15 m 內框不到屋根與半鐘 → 拉到 24–30 m
            'shots': [['street_w', -24.0, 0.0], ['north', 0.0, -24.0], ['street_n', -11.5, -28.0]],
            'walk': {'from': [-8.0, -LEG_B], 'to': [-LEG_B, -LEG_B],
                     'box': [-LEG_B - ped / 2, -LEG_B - ped / 2, -LEG_B + ped / 2, -LEG_B + ped / 2]}},
        'collision': [
            {'type': 'box', 'name': 'Foot%d' % i, 'center': [sx * LEG_B, (PED_BOT + 3.0) / 2, sz * LEG_B],
             'size': [pc, 3.0 - PED_BOT, pc]}
            for i, (sx, sz) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1)))] + [
            {'type': 'convex', 'name': 'Ladder', 'center': [0, 0, 0], 'points': lad_pts}],
        'measured_blender': dict(stats, aabb=aabb[0], aabb_lod1=aabb[1], aabb_lod2=aabb[2]),
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[TOWER]', stats, aabb[0])


main()
