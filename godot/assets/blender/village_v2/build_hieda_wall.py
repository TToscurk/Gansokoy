"""稗田邸 圍牆（整圈宅邸邊界）Hero — 人間之里 V2 P6（全新程序化建模）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_hieda_wall.py

外觀 authority：docs/reference/重點地標/裨田邸正面.PNG（宅邸圍牆＝石積腰＋灰泥＋真壁柱＋瓦頂，牆直接接進大宅門兩側）、
  docs/reference/民宅/圍牆.png（土塀剖面：石積腰→地覆→灰泥→桁→瓦頂；柱等距）。狹間（城郭用）不做。
斷面＝已核准大宅門（R6）袖牆：石積腰頂 0.45、灰泥頂 1.72、瓦頂簷口 1.84、坡 0.60、簷 z 0.40、棟頂 2.255；
  灰泥半厚 0.17、腰石半厚 0.24 → 門旁銜接（x ±3.42）瓦頂、牆面、腰石都連續。
平面＝大宅門 P0 地標 LANDMARK_HIEDA_GATE 局部（原點＝地標原點；+z＝南）：南牆 z 0（門兩側）、東 x +23.5、西 x −13.5、
  北 z −50 → 世界 x 384.5–421.5、z −10 ～ −60，在 P0 district MansionEstate（x 380–426、z −64 ～ −8）內，
  圍住本屋 P_LM_HIEDA（x 386–420、z −52 ～ −28）；西牆外 1.5 m 是 CrossStreetMid 路端（路面到 x 383.0）。
接地：tools/village_v2_hieda_wall_profile.gd 從場景地形碰撞量出沿牆剖面（src/terrain_profile.json），
  每段牆的頂點依剖面垂直錯切（y += 地形高），腰石埋 0.30 m；牆頂隨地形（全長最大坡 0.6 %）。
池庭／庭院、燈籠、石段不在本輪（P9／P10）。
"""
import bisect
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402
from v2_kit import X, Y, Z, add, mul, norm  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/hieda_wall'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
TILE = {k: v['tile_m'] for k, v in ML.items()}
KW = ML['V2_Kawara']
MATS = ['V2_Wood', 'V2_Kawara', 'V2_Stone', 'V2_Plaster']
DARK = 0.34
PROF = K.load_json(OUT + '/src/terrain_profile.json')

# ── 斷面（＝大宅門袖牆，build_hieda_gate.py WT/WB/W_STONE/W_TOP/WP/WZ/WY_E）
WT = 0.17
WB = 0.24
W_STONE = 0.45
W_TOP = 1.72
WP, WZ, WY_E = 0.60, 0.40, 1.84
WY = WY_E + WP * WZ
EMBED = 0.30                      # 腰石埋深
BAY = 1.82                        # 真壁柱間（一間）
POST, POST_C = 0.15, 0.20         # 柱斷面、轉角柱斷面
# ── 平面（大宅門局部）
PL = PROF['plan']
X0, X1, ZS, ZN, GH = PL['x0'], PL['x1'], PL['zs'], PL['zn'], PL['gate_half']
GATE_COPING_END = 3.44            # 大宅門袖牆瓦頂止於 x ±3.44（WCX1）、棟止於 ±3.46
GATE_COL_END = 3.48               # 大宅門 SideL/R 碰撞止於 x ±3.48

# 邊：名稱 → (起點, 終點, 起點端型, 終點端型)。端型：gate＝接大宅門、gable＝轉角外露妻、hide＝收進相鄰牆
SIDES = [
    ('S_W', (-GH, ZS), (X0, ZS), 'gate', 'hide'),
    ('S_E', (GH, ZS), (X1, ZS), 'gate', 'hide'),
    ('E', (X1, ZS), (X1, ZN), 'gable', 'gable'),
    ('N', (X1, ZN), (X0, ZN), 'hide', 'hide'),
    ('W', (X0, ZN), (X0, ZS), 'gable', 'gable'),
]


def g_of(name):
    """邊 name 的地形剖面：t（沿邊 m）→ 地形最低高（相對地標原點；牆厚 ±0.30 三條線取最低）。"""
    smp = PROF['sides'][name]['samples']
    ts = [s[0] for s in smp]
    ys = [s[1] for s in smp]

    def g(t):
        if t <= ts[0]:
            return ys[0]
        if t >= ts[-1]:
            return ys[-1]
        i = bisect.bisect_right(ts, t) - 1
        u = (t - ts[i]) / (ts[i + 1] - ts[i])
        return ys[i] + (ys[i + 1] - ys[i]) * u
    return g


def roof_run(m, lod, x0, x1, rx0, rx1, verge0, verge1, col=0.92):
    """瓦頂（邊局部：棟沿 x、z＝0）：前後兩坡 tile_roof＋野地裏＋簷桁；破風板只在外露妻端；棟 rx0..rx1。"""
    sec = math.sqrt(1 + WP * WP)
    S = WZ * sec
    TW = TILE['V2_Wood']
    for sg in (1, -1):
        dsl = norm((0.0, -WP, float(sg)))
        n = norm((0.0, 1.0, WP * sg))
        o = (0.0, WY, 0.0)
        K.tile_roof(m, o, dsl, n, x0, x1, S, KW, lod, u_sign=float(sg), ends=(lod == 0), col=col, seg_per_col=2)
        if lod <= 1:
            uo = add(o, mul(n, -0.12))
            m.grid(lambda i, j: add(add(uo, mul(X, x0 + (x1 - x0) * i)), mul(dsl, S * j)),
                   lambda i, j: ((x0 + (x1 - x0) * i) / TW, S * j / TW), 1, 1, 'V2_Wood', DARK * 0.55, mul(n, -1.0),
                   smooth=False)
            e0 = add(add(o, mul(X, x0)), mul(dsl, S))
            e1 = add(add(o, mul(X, x1)), mul(dsl, S))
            m.beam(add(e0, mul(n, -0.06)), add(e1, mul(n, -0.06)), 0.05, 0.16, 'V2_Wood', DARK * 0.9, up=n)
        for xs, on in ((x0, verge0), (x1, verge1)):   # 破風板
            if not on:
                continue
            a = add(add(o, mul(X, xs)), mul(n, -0.05))
            b = add(add(add(o, mul(X, xs)), mul(dsl, S)), mul(n, -0.05))
            m.beam(add(a, mul(dsl, -0.02)), b, 0.05, 0.20, 'V2_Wood', DARK * 0.85, up=n)
    m.box((rx0, WY - 0.06, -0.11), (rx1, WY + 0.10, 0.11), 'V2_Kawara', 0.60, grain=X)
    if lod <= 1:
        m.cyl((rx0, WY + 0.10, 0), (rx1, WY + 0.10, 0), 0.075, 0.075, 10 if lod == 0 else 6, 'V2_Kawara', 0.55,
              caps=(lod == 0, lod == 0))


def gable_face(m, x, sgn, col=0.9):
    """妻（x 平面，朝 sgn·x）：灰泥三角＋台（與大宅門袖牆端同式）。"""
    ze = WZ - 0.10
    yb_edge = WY - WP * ze - 0.14
    ps = [(x, W_TOP, -ze + 0.02), (x, W_TOP, ze - 0.02), (x, max(W_TOP, yb_edge), ze - 0.02), (x, WY - 0.16, 0.0),
          (x, max(W_TOP, yb_edge), -ze + 0.02)]
    if yb_edge <= W_TOP + 1e-3:
        ps = [ps[0], ps[1], ps[3]]
    uvs = [(p_[2] / TILE['V2_Plaster'], p_[1] / TILE['V2_Plaster']) for p_ in ps]
    n = (float(sgn), 0.0, 0.0)
    cr = K.cross(K.sub(ps[1], ps[0]), K.sub(ps[2], ps[0]))
    if K.dot(cr, n) < 0:
        ps, uvs = ps[::-1], uvs[::-1]
    m.face(m.verts(ps), 'V2_Plaster', uvs, col)


def bays(t0, t1, step):
    """[t0, t1] 切成約 step 的段（端點含）。"""
    n = max(1, int(round((t1 - t0) / step)))
    return [t0 + (t1 - t0) * i / n for i in range(n + 1)]


def build_side(name, L, e0, e1, lod, seed):
    """一段牆（邊局部：沿 +x 0..L、z＝0 為牆心、y 0＝地形前的基準）。回傳 K.Mesh。"""
    m = K.Mesh('side', MATS, TILE)
    # 各層沿 x 的範圍：gable 端伸出轉角（蓋住相鄰牆端），hide 端收在相鄰牆心，gate 端對接大宅門袖牆（x＝0 是 ±3.42）
    def ext(e, half):
        return half if e == 'gable' else 0.0
    s0, s1 = -ext(e0, WB), L + ext(e1, WB)
    p0, p1 = -ext(e0, WT), L + ext(e1, WT)
    r0, r1 = -ext(e0, WT + 0.02), L + ext(e1, WT + 0.02)
    # 瓦頂：gable 端出簷 WZ（妻側也出 0.40）；gate 端從大宅門瓦頂終點起；hide 端止於相鄰牆棟線（藏在它的屋面下）
    c0 = -(WZ + 0.02) if e0 == 'gable' else (GATE_COPING_END - GH if e0 == 'gate' else 0.0)
    c1 = L + (WZ + 0.02) if e1 == 'gable' else L
    rd0 = c0 - 0.02 if e0 == 'gable' else (GATE_COPING_END + 0.02 - GH if e0 == 'gate' else 0.0)
    rd1 = c1 + 0.02 if e1 == 'gable' else L
    seg = 5.0 if lod == 2 else BAY
    xs = bays(s0, s1, seg)
    for a, b in zip(xs, xs[1:]):
        # 腰石（石積）、地覆、灰泥、桁（瓦頂の台）
        m.box((a, -EMBED, -WB), (b, W_STONE, WB), 'V2_Stone', 0.80, skip=('-y',))
    xs = bays(p0, p1, seg)
    for a, b in zip(xs, xs[1:]):
        m.box((a, W_STONE, -WT), (b, W_TOP, WT), 'V2_Plaster', 0.97, grain=X, skip=('-y',))
    if lod <= 1:
        xs = bays(r0, r1, seg)
        for a, b in zip(xs, xs[1:]):
            m.box((a - 0.005, W_TOP - 0.10, -WT - 0.02), (b + 0.005, W_TOP, WT + 0.02), 'V2_Wood', DARK, grain=X)
            m.box((a - 0.005, W_STONE, -WT - 0.015), (b + 0.005, W_STONE + 0.07, WT + 0.015), 'V2_Wood', DARK * 0.9,
                  grain=X)
            m.box((a, W_TOP, -WT - 0.04), (b, WY_E + 0.02, WT + 0.04), 'V2_Wood', DARK * 0.7, grain=X, skip=('-y',))
    else:
        m.box((r0, W_TOP, -WT - 0.04), (r1, WY_E + 0.02, WT + 0.04), 'V2_Wood', DARK * 0.7, grain=X, skip=('-y',))
    # 真壁柱：一間一根（gate 端第一根離接縫一間，接縫處不立柱）；轉角柱只在 gable 邊（兩端）
    if lod <= 1:
        pts = bays(0.0, L, BAY)[1:-1]
        for t in pts:
            m.box((t - POST / 2, W_STONE + 0.07, -WT - 0.025), (t + POST / 2, W_TOP - 0.10, WT + 0.025), 'V2_Wood',
                  DARK * 1.05, grain=Y, skip=('-y', '+y'))
        for t, e in ((0.0, e0), (L, e1)):
            if e == 'gable':
                m.box((t - POST_C / 2, W_STONE, -POST_C / 2 - 0.02), (t + POST_C / 2, W_TOP, POST_C / 2 + 0.02),
                      'V2_Wood', DARK * 1.05, grain=Y, skip=('-y',))
    # 石積の目地（LOD0：兩面二段、長短不一、外凸 0.015；同大宅門袖牆）
    if lod == 0:
        rnd = random.Random(seed)
        for sz in (-1, 1):
            for (ya, yb) in ((-0.02, 0.20), (0.20, W_STONE - 0.02)):
                t = s0
                while t < s1 - 0.05:
                    Lr = rnd.uniform(0.35, 0.70)
                    e = min(s1, t + Lr)
                    if s1 - e < 0.20:
                        e = s1
                    zz = sz * WB
                    z0, z1 = sorted((zz, zz + sz * 0.015))
                    m.box((t + 0.015, ya + 0.01, z0), (e - 0.015, yb - 0.01, z1), 'V2_Stone', rnd.uniform(0.70, 0.92),
                          skip=('-y', '-z' if sz > 0 else '+z'))
                    t = e
    # 瓦頂＋妻
    xs = bays(c0, c1, 50.0 if lod == 2 else 12.0)   # 瓦頂分段（錯切跟地形；LOD2 一段）
    for i, (a, b) in enumerate(zip(xs, xs[1:])):
        first, last = i == 0, i == len(xs) - 2
        roof_run(m, lod, a, b, rd0 if first else a, rd1 if last else b,
                 verge0=first and e0 == 'gable', verge1=last and e1 == 'gable')
    for t, e, sg in ((p0, e0, -1), (p1, e1, 1)):
        if e == 'gable':
            gable_face(m, t + sg * 0.002, sg)
    return m


def place_side(dst, src, p0, p1, g):
    """邊局部 → 大宅門局部：沿邊方向旋轉＋平移，y 依地形剖面錯切（t＝邊局部 x，端外夾在端點值）。"""
    dx, dz = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dz)
    dx, dz = dx / L, dz / L
    base = len(dst.v)
    for (x, y, z) in src.v:
        dst.v.append((p0[0] + dx * x - dz * z, y + g(x), p0[1] + dz * x + dx * z))
    for (idx, mi, uvs, cols, sm) in src.f:
        dst.f.append((tuple(i + base for i in idx), mi, uvs, cols, sm))


def build(lod):
    m = K.Mesh('HiedaWall_LOD%d' % lod, MATS, TILE)
    for k, (name, p0, p1, e0, e1) in enumerate(SIDES):
        L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        place_side(m, build_side(name, L, e0, e1, lod, 7301 + k), p0, p1, g_of(name))
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


def side_geom():
    """每邊：大宅門局部的起訖、長度、方向、地形函式、最低／最高地形。"""
    out = []
    for name, p0, p1, e0, e1 in SIDES:
        L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        g = g_of(name)
        ys = [s[1] for s in PROF['sides'][name]['samples']]
        out.append({'name': name, 'p0': p0, 'p1': p1, 'e0': e0, 'e1': e1, 'L': L, 'g': g,
                    'gmin': min(ys), 'gmax': max(ys)})
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
    glb = OUT + '/src/hieda_wall.glb'
    K.export_glb(bpy, glb, objs)
    cnt = tri_count(glb)
    stats = {'LOD%d' % l: cnt['HiedaWall_LOD%d' % l] for l in (0, 1, 2)}
    SG = side_geom()
    top = aabb[0][1][1]
    bot = aabb[0][0][1]
    ridge_h = WY + 0.175
    # 接地件：每邊每一間的腰石（gate 端從大宅門碰撞外 0.02 m 起，避免腳下第一個碰撞體是大宅門）
    ground = []
    for s in SG:
        t0 = (GATE_COL_END + 0.02 - GH) if s['e0'] == 'gate' else 0.0
        xs = bays(t0, s['L'], BAY)
        dx, dz = (s['p1'][0] - s['p0'][0]) / s['L'], (s['p1'][1] - s['p0'][1]) / s['L']
        for i, (a, b) in enumerate(zip(xs, xs[1:])):
            gl = min(s['g'](a), s['g'](b), s['g']((a + b) / 2))
            ax, az = s['p0'][0] + dx * a, s['p0'][1] + dz * a
            bx, bz = s['p0'][0] + dx * b, s['p0'][1] + dz * b
            nx, nz = abs(dz) * WB, abs(dx) * WB
            ground.append({'name': '腰石 %s-%02d' % (s['name'], i + 1),
                           'rect': [round(min(ax, bx) - nx, 3), round(min(az, bz) - nz, 3),
                                    round(max(ax, bx) + nx, 3), round(max(az, bz) + nz, 3)],
                           'bottom': round(gl - EMBED, 4), 'top': round(gl + W_STONE, 4), 'embed_max': 0.40})
    # 碰撞：每邊一個 box（大宅門局部、軸對齊）；gate 端從 x ±3.44 起：與大宅門 SideL/R（止於 ±3.48）重疊 0.04 m，
    # 接縫不留無碰撞縫；又避開大宅門袖牆腰石接地件（止於 ±3.42），大宅門 grounding「正下方第一個碰撞體是地形」不受影響
    col = []
    CH = WB + 0.02
    for s in SG:
        (ax, az), (bx, bz) = s['p0'], s['p1']
        if s['e0'] == 'gate':
            ax = math.copysign(GATE_COL_END - 0.04, ax)
        if s['e1'] == 'hide':        # 收進相鄰牆：止於相鄰牆碰撞面
            if abs(bz - az) < 1e-6:
                bx = bx - math.copysign(CH, bx - ax)
            else:
                bz = bz - math.copysign(CH, bz - az)
        if s['e0'] == 'hide':
            if abs(bz - az) < 1e-6:
                ax = ax + math.copysign(CH, bx - ax)
            else:
                az = az + math.copysign(CH, bz - az)
        x_lo, x_hi = min(ax, bx), max(ax, bx)
        z_lo, z_hi = min(az, bz), max(az, bz)
        if abs(bz - az) < 1e-6:
            z_lo, z_hi = az - CH, az + CH
        else:
            x_lo, x_hi = ax - CH, ax + CH
            if s['e0'] == 'gable' or s['e1'] == 'gable':
                z_lo, z_hi = z_lo - CH, z_hi + CH
        y_lo, y_hi = s['gmin'] - EMBED, s['gmax'] + ridge_h
        col.append({'type': 'box', 'name': 'Wall%s' % s['name'],
                    'center': [round((x_lo + x_hi) / 2, 4), round((y_lo + y_hi) / 2, 4), round((z_lo + z_hi) / 2, 4)],
                    'size': [round(x_hi - x_lo, 4), round(y_hi - y_lo, 4), round(z_hi - z_lo, 4)]})
    wall_sides = [{'name': s['name'], 'from': list(s['p0']), 'to': list(s['p1']),
                   'skip0': 0.10 if s['e0'] == 'gate' else 0.0} for s in SG]
    spec = {
        '_note': '稗田邸 圍牆 Hero 資產規格（build_hieda_wall.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、'
                 'verify_village_v2_hero_gate.gd 讀取）。整圈宅邸邊界（南牆門兩側＋東西北），掛在大宅門 P0 地標下'
                 '（節點 HeroWall；大宅門 Hero 不動）；斷面＝已核准大宅門袖牆；接地＝地形剖面錯切。池庭／庭院延 P9／P10。',
        'id': 'hieda_wall', 'landmark': 'LANDMARK_HIEDA_GATE', 'kind': 'hero', 'budget_class': '稗田邸',
        'glb': 'res://assets/village_v2/hieda_wall/src/hieda_wall.glb',
        'scene': 'res://assets/village_v2/hieda_wall/hieda_wall.scn',
        'lod_objects': ['HiedaWall_LOD0', 'HiedaWall_LOD1', 'HiedaWall_LOD2'],
        # 可見距離量到實例 AABB 中心（牆圍 37 × 50 m，中心在院子中央）→ LOD0 放到 60 m
        'lod_ranges_m': [0, 60, 150, 700],
        'budget': {'lod0': 150000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 4, 'collision': 5},
        'materials': {k: ML[k]['tres'] for k in MATS},
        'spec': {'plan_local': PL, 'perimeter_m': round(sum(s['L'] for s in SG), 2),
                 'section_m': {'stone_top': W_STONE, 'plaster_top': W_TOP, 'coping_eave': WY_E, 'ridge_top': ridge_h,
                               'plaster_half': WT, 'stone_half': WB, 'coping_eave_half': WZ, 'embed': EMBED},
                 'bay_m': BAY, 'terrain_profile': 'src/terrain_profile.json（tools/village_v2_hieda_wall_profile.gd）',
                 'design': '石積腰（二段目地）＋地覆＋灰泥＋真壁柱（一間）＋桁＋切妻瓦頂（棟＋瓦當）；轉角＝東西牆妻端外露、'
                           '南北牆瓦頂收進東西牆棟下；門旁接大宅門袖牆（瓦頂、牆面、腰石連續，接縫不立柱）'},
        'gate_spec': {
            'placement': 'anchor', 'anchor': 'Landmarks/LANDMARK_HIEDA_GATE', 'replaces': '', 'node': 'HeroWall',
            'p4_id': '', 'parcel': 'P_LM_HIEDA_GATE', 'estate_parcels': ['P_LM_HIEDA', 'P_LM_HIEDA_GATE'],
            'district': 'MansionEstate', 'road': 'FarmPath_4',
            'size': {'x_half_max': round(max(abs(aabb[0][0][0]), abs(aabb[0][1][0])) + 0.01, 3),
                     # 東西牆妻端外露：破風＋瓦當比牆心多出 WZ 以外的懸挑 → 以實際 LOD0 外框＋0.01
                     'z_min': round(aabb[0][0][2] - 0.01, 3), 'z_max': round(aabb[0][1][2] + 0.01, 3),
                     'top': [round(ridge_h - 0.02, 3), round(max(s['gmax'] for s in SG) + ridge_h + 0.02, 3)],
                     'bottom': round(min(s['gmin'] for s in SG) - EMBED, 3)},
            'ground': ground,
            # 通路：大宅門內 → 本屋玄關的院子中線（圍牆碰撞不可擋）
            'walkway': {'rect': [-1.0, -18.0, 1.0, -2.0], 'head': 1.95, 'min_clear': 2.5, 'step': 0.5},
            'entry': [0.0, 2.0], 'inside': [10.0, 0.0],
            'wall': {'sides': wall_sides, 'step': 1.0, 'h_min': round(ridge_h - 0.08, 3), 'h_max': round(ridge_h + 0.08, 3),   # 坡地錯切：剖面 0.25 m 取樣 vs 射線 1 m 站
                     't_min': 2 * WT - 0.01, 't_max': 2 * (WT + 0.025) + 0.01, 'junction_x': GH, 'plaster_half': WT},
            # 鏡位 [名, 站 x, 站 z, 看 x, 看 z]（大宅門局部）
            'shots': [['south_street', 12.0, 10.0, 12.0, 0.0], ['gate_join', -7.0, 7.0, -3.4, 0.0],
                      ['corner_se', 29.0, 7.0, 23.5, 0.0], ['west_road_end', -19.5, -26.0, -13.5, -26.0],
                      ['north', 5.0, -57.0, 5.0, -50.0], ['courtyard', 8.0, -8.0, 8.0, 0.0],
                      ['join_w_close', -5.2, 3.2, -3.4, 0.0], ['join_e_close', 5.2, 3.2, 3.4, 0.0]],
            # F5 實走：東牆外 → 院子，必須被牆擋在外
            'walk': {'from': [31.0, -25.0], 'to': [12.0, -25.0], 'box': [X0 + 0.3, ZN + 0.3, X1 - 0.3, ZS - 0.3]}},
        'collision': col,
        'measured_blender': dict(stats, aabb=aabb[0], aabb_lod1=aabb[1], aabb_lod2=aabb[2]),
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[WALL]', stats, aabb[0], 'ground %d col %d perimeter %.1f' % (len(ground), len(col), spec['spec']['perimeter_m']))


main()
