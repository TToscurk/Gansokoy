"""參道鳥居（LANDMARK_HILL_TORII）— 人間之里 V2 P5 R4 新資產。

  python tools/build_village_v2_r4_atlas.py          # 先產 atlas（額「龍神社」、注連繩、房、紙垂）
  blender -b --factory-startup --python godot/assets/blender/village_v2/build_sando_torii.py

參考：docs/reference/神社/博麗神社鳥居.png（使用者 2026-09-24：「參道鳥居可以暫時沿用博麗鳥居作 reference，
但額牌文字不清楚的版本不要直接定稿」）。vision 判讀：明神鳥居、笠木黑、島木朱、貫出柱、石台座、
注連繩在貫下＋房 3＋紙垂 2、額直立古金框、笠木反り溫和。額字「龍神社」（使用者 2026-09-25 裁示）。
尺寸 authority：layout_v2.json LANDMARK_HILL_TORII span 4.5（柱心距）、h 6、yaw 22；參道 HillApproach 寬 5.0 m。
使用者 2026-09-25 裁示：維持 P0 4.5 m，柱腳壓路肩；gate 檢查中間淨寬 ≥ 3.5 m 並報壓路肩量。
新檔，不覆寫 Protected 的 大鳥居／博麗鳥居。
座標：Godot（+z 朝南＝參道下坡、玩家來的方向），原點＝兩柱中點地面。地形沿 −z 上坡（柱心線 ±0.35 m）。
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402
from v2_kit import X, Y, Z, add, cross, mul, norm, sub  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/sando_torii'
MATLIB = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')
TILE = {k: v['tile_m'] for k, v in MATLIB['materials'].items()}
AT = K.load_json(OUT + '/atlas.json')['regions']
AMAT = 'V2_SandoTorii'
MATS = ['V2_WoodRed', 'V2_Metal', 'V2_Stone', AMAT]

SPAN = 4.5           # 柱心距（地面）
LEAN = 0.06          # 転び：柱頂內傾（每側）
EMBED = 0.45         # 台座底（地形沿參道坡：柱腳範圍 −0.20～+0.36 m）
BASE_LO = 0.42       # 下段方台頂（高於上坡側地面）
BASE_TOP = 0.58
BASE_H = 0.36        # 台座半寬
PR0, PR1 = 0.215, 0.195
Y_NUKI = (3.95, 4.25)
NUKI_HALF = 2.85
Y_SHIMA = 5.30       # 島木底（中央）
SHIMA_H = 0.28
SHIMA_HALF = 2.90
KASA_H = 0.44
KASA_HALF = 3.15
SORI = 0.24
SORI_X0 = 1.2
PLAQUE = (0.56, 0.90)    # 額面寬×高（與 atlas 腳本 PLAQUE_M 一致）
Y_PLAQUE = 4.775
ROPE_X = 2.10            # 注連繩兩端（插進柱內）
ROPE_Y0, ROPE_SAG = 3.80, 0.30
ROPE_Z = 0.0


def lift(x):
    a = abs(x)
    if a <= SORI_X0:
        return 0.0
    t = (a - SORI_X0) / (KASA_HALF - SORI_X0)
    return SORI * t ** 2


def pillar_x(y, side):
    return side * (SPAN / 2 - LEAN * y / Y_SHIMA)


def loft(m, xs, profile, y0fn, mat, col=1.0, end_slant=0.0):
    """沿 x 的斷面放樣（同 build_south_torii.py）。profile：[(z, y)] 逆時針（從 +x 看）。"""
    rings = []
    ymax = max(p[1] for p in profile)
    for i, x in enumerate(xs):
        ring = []
        for (z, y) in profile:
            xx = x
            if i == 0:
                xx = x - end_slant * (y / ymax)
            elif i == len(xs) - 1:
                xx = x + end_slant * (y / ymax)
            ring.append((xx, y0fn(x) + y, z))
        rings.append(ring)
    n = len(profile)
    for i in range(len(xs) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(n):
            k2 = (k + 1) % n
            m.quad(a[k], b[k], b[k2], a[k2], mat, col, grain=X)
    m.poly(list(reversed(rings[0])), mat, col, grain=Y)
    m.poly(list(rings[-1]), mat, col, grain=Y)


def rope_pt(x):
    t = x / ROPE_X
    return (x, ROPE_Y0 - ROPE_SAG * (1 - t * t), ROPE_Z)


def rope_r(x):
    t = abs(x) / ROPE_X
    return 0.115 - 0.05 * t * t


def tube(m, path, radii, seg, region):
    """管狀網格（注連繩）：path 點列、每點半徑；UV u 沿長（整條＝region 寬）、v 繞一圈。兩端封蓋。"""
    u0, v0, u1, v1 = region
    rings = []
    n = len(path)
    for j, p in enumerate(path):
        t = norm(sub(path[min(j + 1, n - 1)], path[max(j - 1, 0)]))
        e1 = norm(cross(Z, t))            # 繩在 xy 平面：e1 朝繩的「上方」法線
        e2 = cross(t, e1)
        ring = [add(p, add(mul(e1, math.cos(2 * math.pi * k / seg) * radii[j]),
                           mul(e2, math.sin(2 * math.pi * k / seg) * radii[j]))) for k in range(seg)]
        rings.append(m.verts(ring))
    for j in range(n - 1):
        ua = u0 + (u1 - u0) * j / (n - 1)
        ub = u0 + (u1 - u0) * (j + 1) / (n - 1)
        for k in range(seg):
            k2 = (k + 1) % seg
            va = v0 + (v1 - v0) * k / seg
            vb = v0 + (v1 - v0) * (k + 1) / seg
            # 環 k→k+1 沿 e1→e2（＝t×e1 方向），再沿 t：從外面看逆時針
            m.face([rings[j][k], rings[j][k2], rings[j + 1][k2], rings[j + 1][k]], AMAT,
                   [(ua, va), (ua, vb), (ub, vb), (ub, va)], 1.0, smooth=True)
    cu = ((u0 + u1) / 2, (v0 + v1) / 2)
    m.face(list(reversed(rings[0])), AMAT, [cu] * seg, 0.9)
    m.face(list(rings[-1]), AMAT, [cu] * seg, 0.9)


def build(lod):
    seg = {0: 20, 1: 8, 2: 6}[lod]
    nx = {0: 20, 1: 6, 2: 2}[lod]
    m = K.Mesh('Sando_Torii_LOD%d' % lod, MATS, TILE)
    xs_k = [-KASA_HALF + 2 * KASA_HALF * i / nx for i in range(nx + 1)]
    xs_s = [-SHIMA_HALF + 2 * SHIMA_HALF * i / nx for i in range(nx + 1)]

    for side in (-1, 1):
        px = pillar_x(0.0, side)
        # ── 石台座：下段方台（地形坡上）＋上段斜台（LOD2 只留方台）
        m.box((px - BASE_H, -EMBED, -BASE_H), (px + BASE_H, BASE_LO if lod < 2 else BASE_TOP, BASE_H),
              'V2_Stone', 0.95, skip=('-y',))
        if lod < 2:
            lo, hi = BASE_H - 0.03, 0.27
            y0, y1 = BASE_LO, BASE_TOP
            r0 = [(px - lo, y0, -lo), (px + lo, y0, -lo), (px + lo, y0, lo), (px - lo, y0, lo)]
            r1 = [(px - hi, y1, -hi), (px + hi, y1, -hi), (px + hi, y1, hi), (px - hi, y1, hi)]
            for k in range(4):
                k2 = (k + 1) % 4
                m.quad(r0[k], r0[k2], r1[k2], r1[k], 'V2_Stone', 1.0)
            m.poly([r1[0], r1[1], r1[2], r1[3]][::-1], 'V2_Stone', 1.0)
        # ── 柱（朱、收分、転び）＋柱腳黑銅箍
        top = Y_SHIMA + lift(pillar_x(Y_SHIMA, side)) + 0.03
        p0 = (px, BASE_TOP, 0.0)
        p1 = (pillar_x(top, side), top, 0.0)
        m.cyl(p0, p1, PR0, PR1, seg, 'V2_WoodRed', 1.0, caps=(False, False))
        if lod < 2:
            ya = BASE_TOP + 0.34
            m.cyl(p0, (pillar_x(ya, side), ya, 0.0), PR0 + 0.018, PR0 + 0.015, seg, 'V2_Metal', 1.0,
                  caps=(False, True))
        # ── 楔（貫出柱外）
        if lod == 0:
            wx = pillar_x(Y_NUKI[1], side) + side * (PR1 + 0.08)
            m.box((wx - 0.04, Y_NUKI[0] - 0.04, -0.07), (wx + 0.04, Y_NUKI[1] + 0.05, 0.07), 'V2_WoodRed', 0.8)

    # ── 貫
    m.box((-NUKI_HALF, Y_NUKI[0], -0.10), (NUKI_HALF, Y_NUKI[1], 0.10), 'V2_WoodRed', 0.97, grain=X)
    # ── 額束＋額（「龍神社」atlas；正面 +z）
    if lod < 2:
        m.box((-0.11, Y_NUKI[1], -0.08), (0.11, Y_SHIMA + 0.02, 0.08), 'V2_WoodRed', 1.0, grain=Y)
    hw, hh = PLAQUE[0] / 2, PLAQUE[1] / 2
    m.abox((0.0, Y_PLAQUE, 0.125), (hw, hh, 0.045), AMAT,
           {'+z': AT['plaque'], '-z': AT['wood_dark'], '*': AT['gold']}, 1.0)
    # ── 島木（朱）
    loft(m, xs_s, [(0.17, 0.0), (0.17, SHIMA_H), (-0.17, SHIMA_H), (-0.17, 0.0)],
         lambda x: Y_SHIMA + lift(x), 'V2_WoodRed', 1.0, end_slant=0.06)
    # ── 笠木（黑）
    yk = Y_SHIMA + SHIMA_H
    loft(m, xs_k, [(0.23, 0.0), (0.28, 0.34), (0.0, KASA_H), (-0.28, 0.34), (-0.23, 0.0)],
         lambda x: yk + lift(x), 'V2_Metal', 0.92, end_slant=0.10)

    # ── 注連繩（貫下、兩端插進柱）＋房 3＋紙垂 2
    if lod < 2:
        nseg = {0: 24, 1: 8}[lod]
        path = [rope_pt(-ROPE_X + 2 * ROPE_X * i / nseg) for i in range(nseg + 1)]
        radii = [rope_r(p[0]) for p in path]
        tube(m, path, radii, {0: 10, 1: 5}[lod], AT['rope'])
        for tx in (-1.05, 0.0, 1.05):
            ry = rope_pt(tx)[1] - rope_r(tx) + 0.02
            tseg = {0: 8, 1: 5}[lod]
            m.cyl((tx, ry, ROPE_Z), (tx, ry - 0.52, ROPE_Z), 0.045, 0.085, tseg, AMAT, 1.0,
                  caps=(True, True), uv_atlas=AT['tassel'])
        if lod == 0:
            for sx in (-0.52, 0.52):
                y = rope_pt(sx)[1] - rope_r(sx) + 0.01
                for k in range(4):           # 四折紙垂：左右交錯
                    dx = 0.035 if k % 2 == 0 else -0.035
                    m.abox((sx + dx, y - 0.06 - 0.11 * k, ROPE_Z), (0.045, 0.055, 0.004), AMAT, {'*': AT['shide']}, 1.0)
    else:
        # 遠景：注連繩一條細方條（只留前、後、下三面）
        m.abox((0.0, ROPE_Y0 - ROPE_SAG * 0.6, 0.0), (ROPE_X, 0.10, 0.07), AMAT, {'*': AT['rope']}, 1.0,
               skip=('+x', '-x', '+y'))
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
            stats['aabb'] = [[round(min(xs), 3), round(min(ys), 3), round(min(zs), 3)],
                             [round(max(xs), 3), round(max(ys), 3), round(max(zs), 3)]]
    K.export_glb(bpy, OUT + '/src/sando_torii.glb', objs)
    top = Y_SHIMA + SHIMA_H + KASA_H
    clear_inner = SPAN / 2 - BASE_H      # 台座內緣（地面最窄處）
    mats = {k: MATLIB['materials'][k]['tres'] for k in MATS if k != AMAT}
    mats[AMAT] = 'res://assets/village_v2/sando_torii/V2_SandoTorii.tres'
    spec = {
        '_note': '參道鳥居 資產規格（build_sando_torii.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、verify_village_v2_hero_gate.gd 讀取）。',
        'id': 'sando_torii', 'landmark': 'LANDMARK_HILL_TORII', 'kind': 'landmark', 'budget_class': '鳥居',
        'glb': 'res://assets/village_v2/sando_torii/src/sando_torii.glb',
        'scene': 'res://assets/village_v2/sando_torii/sando_torii.scn',
        'lod_objects': ['Sando_Torii_LOD0', 'Sando_Torii_LOD1', 'Sando_Torii_LOD2'],
        'lod_ranges_m': [0, 60, 160, 700],
        'budget': {'lod0': 5000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': mats,
        'spec': {'span_m': SPAN, 'height_m': 6.0, 'kasagi_len_m': 2 * KASA_HALF, 'nuki_y_m': Y_NUKI[0],
                 'embed_m': EMBED, 'top_center_m': round(top, 3), 'top_end_m': round(top + SORI, 3),
                 'plaque_m': list(PLAQUE), 'plaque_text': '龍神社', 'clear_inner_half_m': clear_inner,
                 'road': 'HillApproach 寬 5.0 m（half_w 2.5）'},
        'gate_spec': {
            # 放置：P0 地標節點原點（兩柱中點地面）＋ yaw 22（P0 placeholder 的 yaw 在子節點 Torii 上，地標節點本身沒轉）
            'placement': 'anchor', 'anchor': 'Landmarks/LANDMARK_HILL_TORII', 'replaces': 'Torii', 'yaw_deg': 22.0,
            'p4_id': '', 'parcel': '', 'road': 'HillApproach',
            'size': {'x_half_max': KASA_HALF + 0.15, 'z_min': -0.45, 'z_max': 0.45, 'top': [6.0, 6.35],
                     'bottom': -EMBED},
            # 使用者 2026-09-25：維持 P0 4.5 m、柱腳壓路肩；中間淨寬 ≥ 3.5 m，報壓路肩量（上限＝路半寬−台座內緣）
            'span': {'axis_m': SPAN, 'clear_min': 3.5, 'inner_half': clear_inner,
                     'shoulder_max': round(2.5 - clear_inner + 0.02, 3)},
            'ground': [
                {'name': '台座%s' % ('左' if s < 0 else '右'),
                 'rect': [s * SPAN / 2 - BASE_H, -BASE_H, s * SPAN / 2 + BASE_H, BASE_H],
                 'bottom': -EMBED, 'top': BASE_LO, 'embed_max': 0.40,
                 # 使用者 2026-09-25：柱腳壓 HillApproach 路肩；gate 報面積、不判失敗（上限＝shoulder_max × 台座深）
                 'road_ok': 'HillApproach'} for s in (-1, 1)],
            'walkway': {'rect': [-(clear_inner - 0.05), -1.2, clear_inner - 0.05, 1.2], 'head': 1.95, 'min_clear': 2.6,
                        'step': 0.25},
            'entry': [0.0, 3.0], 'inside': [-SPAN / 2, 0.0],
            # 鳥居兩側 6–15 m 是 P1 北丘林冠（Forest_HillCrown，無碰撞的樹冠網格，頂高 1–8 m），北側是上坡參道：
            # 北 14／7 m、北東 8.5 m、東 11 m 鏡位的 3P 相機都鑽進林冠或坡面（實測畫面亮度標準差 0.009–0.017）。
            # 參道軸線上沒有林冠 → 三個鏡位都取玩家實際走來的方向（村 → 山）：近 8、中 16、遠 34 m。
            'shots': [['south', 0.0, 16.0], ['south_near', 0.0, 8.0], ['south_far', 0.0, 34.0]]},
        'collision': [
            {'type': 'cylinder', 'center': [s * SPAN / 2, (Y_NUKI[0] - EMBED) / 2, 0], 'radius': 0.24,
             'height': Y_NUKI[0] + EMBED, 'name': 'Pillar_%s' % ('L' if s < 0 else 'R')} for s in (-1, 1)] + [
            {'type': 'box', 'center': [s * SPAN / 2, (BASE_TOP - EMBED) / 2, 0], 'size': [2 * BASE_H, BASE_TOP + EMBED, 2 * BASE_H],
             'name': 'Base_%s' % ('L' if s < 0 else 'R')} for s in (-1, 1)],
        'measured_blender': stats,
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[SANDO]', stats)


main()
