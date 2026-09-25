"""水車×3（LANDMARK_WATERWHEEL_1–3）— 人間之里 V2 P5 R4 新資產（一件資產、三處放置）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_waterwheel.py

尺寸 authority：layout_v2.json LANDMARK_WATERWHEEL_1–3（r 3.2，上限）；水渠 Canal（half_w 3.0）。
參考：docs/reference/河岸/水車齒輪(寬).png、水車小屋整組.png（vision：每側兩圈輪緣、10 支輻條、平板葉板、
輪寬：直徑 ≈ 1:3 以下、軸承在石積橋台上；木色風化深褐）。
使用者 2026-09-25：水車要轉——輪子拆成獨立節點（asset.json rotors），prefab 加 AnimationPlayer 慢速轉。
形式：下掛式（水渠水面比西岸低約 1.3–2.1 m，probe 實測；上掛式沒有落差可用）。

局部座標（Godot）：原點＝P0 地標 xz、y＝水渠水面；+z＝水流方向；+x＝朝水渠中心（西岸 → 東）。
  西岸石積橋台（軸承）x −2.9～−1.7；輪子在水渠內 x 1.05～2.15（水渠中心在 x 2.15～2.55，半寬 3.0）；
  東側木柱（另一端軸承）立在渠底。輪半徑 3.0（葉板尖；P0 r 3.2 以內），輪心 y 2.65 → 輪下緣泡水 0.35 m。
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/waterwheel'
MATLIB = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')
TILE = {k: v['tile_m'] for k, v in MATLIB['materials'].items()}
MATS = ['V2_Wood', 'V2_Stone', 'V2_Metal']
X, Y, Z = K.X, K.Y, K.Z

R = 3.00            # 葉板尖半徑
PV = (1.60, 2.65, 0.0)   # 輪心（局部）
XW0, XW1 = 1.05, 2.15    # 輪寬（兩輪緣外面；資產局部）
XA, XB = XW0 - PV[0], XW1 - PV[0]   # 同上，輪心座標
N_PAD = 16
N_SPOKE = 10
PERIOD = 14.0       # 一圈秒數（慢速）
# 各放置點：yaw＝水渠中心線方向（+z 順流）、dy＝水面比 P0 地標原點高（probe 實測，gate 對水面網格再驗）
SITES = [('LANDMARK_WATERWHEEL_1', -4.574, 0.094), ('LANDMARK_WATERWHEEL_2', -13.496, 0.5596),
         ('LANDMARK_WATERWHEEL_3', -26.565, 0.8507)]
PIER = (-2.90, -1.70, -0.70, 0.70, 0.30, 2.45)    # x0 x1 z0 z1 y0 y1（y 相對水面；底埋進岸坡）
POST = (2.40, 2.70, -0.15, 0.15, -1.60, 3.10)
BEAR = (-2.85, 2.45, -0.55, -1.75, 3.05, 0.55)   # 軸受け台 lo(x,y,z) hi(x,y,z)
AXLE_R = 0.11


def rdir(t):
    """輪心座標系：角 t 的半徑方向（局部 yz 平面）。"""
    return (0.0, math.cos(t), math.sin(t))


def P(x, r, t):
    d = rdir(t)
    return (x, r * d[1], r * d[2])


def quad_out(m, ps, mat, col, out):
    n = K.norm(K.cross(K.sub(ps[1], ps[0]), K.sub(ps[2], ps[0])))
    if K.dot(n, out) < 0:
        ps = list(reversed(ps))
    m.poly(ps, mat, col, grain=X)


def ring(m, x0, x1, r0, r1, seg, mat, col):
    """繞 x 軸的方形斷面圓環（輪緣）：外、內、兩側面。"""
    for i in range(seg):
        a, b = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        mid = (a + b) / 2
        quad_out(m, [P(x0, r1, a), P(x1, r1, a), P(x1, r1, b), P(x0, r1, b)], mat, col, rdir(mid))
        quad_out(m, [P(x0, r0, a), P(x0, r0, b), P(x1, r0, b), P(x1, r0, a)], mat, col, K.mul(rdir(mid), -1))
        quad_out(m, [P(x1, r0, a), P(x1, r0, b), P(x1, r1, b), P(x1, r1, a)], mat, col, X)
        quad_out(m, [P(x0, r0, a), P(x0, r1, a), P(x0, r1, b), P(x0, r0, b)], mat, col, K.mul(X, -1))


def build_rotor(lod):
    """輪子（頂點以輪心為原點；prefab 把 Wheel 節點放在 PV）。"""
    XW0 = XA
    XW1 = XB
    m = K.Mesh('Waterwheel_Rotor_LOD%d' % lod, MATS, TILE)
    if lod == 2:
        # 遠景：一個 16 邊扁圓柱＋十字葉板剪影
        m.cyl((XW0, 0, 0), (XW1, 0, 0), R, R, 16, 'V2_Wood', 0.56)
        return m
    seg = 40 if lod == 0 else 20
    rim_w = 0.12
    # 輪緣：每側兩圈（外圈承葉板、內圈加強）
    for x0 in (XW0, XW1 - rim_w):
        ring(m, x0, x0 + rim_w, 2.48, 2.70, seg, 'V2_Wood', 0.64)
        if lod == 0:
            ring(m, x0, x0 + rim_w, 1.52, 1.64, 24, 'V2_Wood', 0.62)
    # 輻條：每側 N_SPOKE 支（轂 → 外圈）
    ns = N_SPOKE if lod == 0 else N_SPOKE // 2
    for x0 in (XW0, XW1 - rim_w):
        xc = x0 + rim_w / 2
        for k in range(ns):
            t = 2 * math.pi * (k + 0.5) / ns
            m.beam(P(xc, 0.30, t), P(xc, 2.52, t), rim_w, 0.12, 'V2_Wood', 0.58, up=X)
    # 葉板：N_PAD 片平板，外緣到 R，跨兩輪緣
    npd = N_PAD if lod == 0 else N_PAD // 2
    for k in range(npd):
        t = 2 * math.pi * k / npd
        rc = (2.30 + R) / 2
        c = P((XW0 + XW1) / 2, rc, t)
        ay = rdir(t)
        az = K.cross(X, ay)
        m.obox(c, ((XW1 - XW0) / 2, (R - 2.30) / 2, 0.03), 'V2_Wood', 0.54, ax=X, ay=ay, az=az, grain=ay)
        if lod == 0:
            # 葉板撐木（外圈 → 葉板根部斜撐，每片一支，居中）
            m.beam(P((XW0 + XW1) / 2, 2.30, t), P((XW0 + XW1) / 2, 2.30, t + 0.20), 0.08, 0.06, 'V2_Wood', 0.60, up=X)
    # 轂（兩端鐵箍）
    m.cyl((XW0 - 0.05, 0, 0), (XW1 + 0.05, 0, 0), 0.34, 0.34, 16 if lod == 0 else 10, 'V2_Wood', 0.52)
    if lod == 0:
        for xb in (XW0 - 0.07, XW1 - 0.03):
            m.cyl((xb, 0, 0), (xb + 0.10, 0, 0), 0.37, 0.37, 16, 'V2_Metal', 0.9)
    return m


def build_body(lod):
    m = K.Mesh('Waterwheel_LOD%d' % lod, MATS, TILE)
    x0, x1, z0, z1, y0, y1 = PIER
    # 西岸石積橋台：LOD0 兩段（下段略寬）＋笠石
    if lod == 0:
        m.box((x0, y0, z0 - 0.05), (x1, 1.30, z1 + 0.05), 'V2_Stone', 0.80, skip=('-y',))
        m.box((x0 + 0.05, 1.30, z0), (x1 - 0.05, y1 - 0.18, z1), 'V2_Stone', 0.86, skip=('-y',))
        m.box((x0, y1 - 0.18, z0 - 0.04), (x1, y1, z1 + 0.04), 'V2_Stone', 0.95, skip=('-y',))
    else:
        m.box((x0, y0, z0 - 0.05), (x1, y1, z1 + 0.05), 'V2_Stone', 0.86, skip=('-y',))
    # 軸受け台（木）：蓋滿橋台頂（岸側不留可站的台面；W1 岸高只比石頂低 0.3 m，玩家會踩上去沿軸走）
    m.box(BEAR[:3], BEAR[3:], 'V2_Wood', 0.50, skip=('-y',))
    if lod == 0:
        for zz in (-0.40, 0.40):   # 壓木上的鐵箍
            m.box((BEAR[0] - 0.01, 2.90, zz - 0.04), (BEAR[3] + 0.01, 3.06, zz + 0.04), 'V2_Metal', 0.9)
    # 東側木柱＋柱頭軸承
    a0, a1, c0, c1, b0, b1 = POST
    m.box((a0, b0, c0), (a1, b1, c1), 'V2_Wood', 0.46, skip=('-y',))
    if lod == 0:
        m.box((a0 - 0.04, 2.40, c0 - 0.10), (a1 + 0.04, 2.90, c1 + 0.10), 'V2_Wood', 0.52)
        # 柱腳根卷（渠底水中，防腐石）
        m.box((a0 - 0.08, b0, c0 - 0.08), (a1 + 0.08, -0.95, c1 + 0.08), 'V2_Stone', 0.70, skip=('-y',))
    # 軸（固定；輪轂套在軸上轉）：西軸承 → 東柱
    seg = 12 if lod == 0 else 8
    m.cyl((-1.75, PV[1], 0), (2.70, PV[1], 0), AXLE_R, AXLE_R, seg, 'V2_Wood', 0.44, caps=(lod == 0, lod == 0))
    if lod == 0:
        for xb in (-1.70, 2.25):
            m.cyl((xb, PV[1], 0), (xb + 0.08, PV[1], 0), AXLE_R + 0.03, AXLE_R + 0.03, 12, 'V2_Metal', 0.9)
    return m


def tri_count(path, prefix):
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
    objs = []
    for lod in (0, 1, 2):
        objs.append(build_body(lod).to_blender(bpy, bmats=bm))
    for lod in (0, 1, 2):
        objs.append(build_rotor(lod).to_blender(bpy, bmats=bm))
    glb = OUT + '/src/waterwheel.glb'
    K.export_glb(bpy, glb, objs)
    cnt = tri_count(glb, 'Waterwheel')
    stats = {}
    for lod in (0, 1, 2):
        stats['LOD%d' % lod] = cnt['Waterwheel_LOD%d' % lod] + cnt['Waterwheel_Rotor_LOD%d' % lod]
        stats['LOD%d_body' % lod] = cnt['Waterwheel_LOD%d' % lod]
        stats['LOD%d_rotor' % lod] = cnt['Waterwheel_Rotor_LOD%d' % lod]
    mats = {k: MATLIB['materials'][k]['tres'] for k in MATS}
    x0, x1, z0, z1, y0, y1 = PIER
    a0, a1, c0, c1, b0, b1 = POST
    top = PV[1] + R
    gs = {
        'placement': 'anchor', 'anchor': 'Landmarks/' + SITES[0][0], 'replaces': 'Wheel',
        'p4_id': '', 'parcel': '', 'road': '', 'water_ref': 'Canal',
        'size': {'x_half_max': 2.95, 'z_min': -3.05, 'z_max': 3.05, 'top': [round(top - 0.05, 3), round(top + 0.05, 3)],
                 'bottom': b0},
        'ground': [
            {'name': '西岸石積橋台', 'rect': [x0, z0 - 0.05, x1, z1 + 0.05], 'bottom': y0, 'top': y1, 'embed_max': 1.3},
            {'name': '東側軸承柱', 'rect': [a0, c0, a1, c1], 'bottom': b0, 'top': b1, 'embed_max': 0.6}],
        'dip': [0.15, 0.60],
        # 西岸步行帶（橋台背後 1.5–2.5 m）
        'walkway': {'rect': [-5.6, -2.5, -4.6, 2.5], 'head': 1.95, 'min_clear': 3.0, 'step': 0.5},
        'entry': [-5.0, 3.5], 'inside': [-2.3, 0.0],
        'shots': [['bank', -9.0, 6.0], ['bank_up', -8.0, -7.0], ['bank_far', -16.0, 16.0]],
        'walk': {'from': [-7.5, 0.0], 'to': [1.6, 0.0], 'box': [x0, -3.0, 2.8, 3.0]},
        'instances': [{'anchor': 'Landmarks/' + s[0], 'landmark': s[0], 'yaw_deg': s[1], 'dy': s[2]} for s in SITES],
    }
    spec = {
        '_note': '水車 資產規格（build_waterwheel.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、verify_village_v2_hero_gate.gd 讀取）。'
                 ' 一件資產放三處（gate_spec.instances）；輪子是轉動部件（rotors），prefab 以 AnimationPlayer 轉。',
        'id': 'waterwheel', 'landmark': SITES[0][0], 'kind': 'landmark', 'budget_class': '水車',
        'glb': 'res://assets/village_v2/waterwheel/src/waterwheel.glb',
        'scene': 'res://assets/village_v2/waterwheel/waterwheel.scn',
        'lod_objects': ['Waterwheel_LOD0', 'Waterwheel_LOD1', 'Waterwheel_LOD2'],
        'rotors': [{'name': 'Wheel', 'pivot': list(PV), 'axis': 'x', 'dir': -1.0, 'period_s': PERIOD,
                    'lod_objects': ['Waterwheel_Rotor_LOD0', 'Waterwheel_Rotor_LOD1', 'Waterwheel_Rotor_LOD2']}],
        'lod_ranges_m': [0, 50, 140, 600],
        'budget': {'lod0': 15000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': mats,
        'spec': {'radius_m': R, 'radius_p0_max_m': 3.2, 'width_m': round(XW1 - XW0, 3), 'hub_y_m': PV[1],
                 'dip_m': round(R - PV[1], 3), 'paddles': N_PAD, 'spokes_per_side': N_SPOKE, 'period_s': PERIOD,
                 'type': '下掛式（undershot）', 'front': '+z＝水流方向；+x＝水渠中心',
                 'sites': [{'landmark': s[0], 'yaw_deg': s[1], 'water_above_origin_m': s[2]} for s in SITES]},
        'gate_spec': gs,
        'collision': [
            {'type': 'box', 'name': 'Pier', 'center': [(x0 + x1) / 2, (y0 + y1) / 2, 0], 'size': [x1 - x0, y1 - y0, z1 - z0 + 0.1]},
            {'type': 'box', 'name': 'Bearing', 'center': [(BEAR[0] + BEAR[3]) / 2, (BEAR[1] + BEAR[4]) / 2, 0], 'size': [BEAR[3] - BEAR[0] + 0.08, BEAR[4] - BEAR[1], BEAR[5] - BEAR[2] + 0.08]},
            {'type': 'box', 'name': 'Axle', 'center': [0.475, PV[1], 0], 'size': [4.45, 2 * AXLE_R + 0.06, 2 * AXLE_R + 0.06]},
            {'type': 'box', 'name': 'Post', 'center': [(a0 + a1) / 2, (b0 + b1) / 2, 0], 'size': [a1 - a0 + 0.20, b1 - b0, c1 - c0 + 0.24]},
            {'type': 'cylinder', 'name': 'WheelHull', 'center': list(PV), 'radius': R + 0.01, 'height': XW1 - XW0 + 0.14,
             'roll_deg': 90.0}],
        'measured_blender': stats,
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[WHEEL]', stats)


main()
