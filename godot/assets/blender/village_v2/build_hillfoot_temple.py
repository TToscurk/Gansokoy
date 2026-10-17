"""丘腳社寺（LANDMARK_HILLFOOT_TEMPLE）— 人間之里 V2 Hero 資產（P13 W9 收尾後，使用者 2026-10-17 指示）。

  python tools/build_village_v2_hillfoot_temple_tex.py      # 先產底色（hillfoot_temple_albedo.jpg、V2_HillfootTemple.tres）
  blender -b --factory-startup --python godot/assets/blender/village_v2/build_hillfoot_temple.py
  godot --headless --path godot --script res://tools/village_v2_hero_prefab.gd -- --asset=hillfoot_temple

來源：使用者提供的 Tripo 模型（D:/資產glb/丘腳社寺/japanese+shrine+3d+model.glb，92,902 面、單材質、4K 底色），
原樣複製為 assets/village_v2/hillfoot_temple/src/hillfoot_temple_source.glb（本腳本只讀入 Blender 記憶體，不寫回）。
做法沿用龍神像（build_dragon_statue.py）：等比縮放、三級 LOD 由 Decimate 減面、清細片、減面摺疊處改平面著色。
尺寸 authority：layout_v2.json LANDMARK_HILLFOOT_TEMPLE（P0 量體 寬 18 × 高 9 × 深 12，只能小於等於）。
原檔高 0.733 → 等比放大到總高 9.00 m（＝P0 高）；腳印 12.0 × 10.6 m（P0 18 × 12 以內）。
原點＝P0 地標原點（地面）、+z＝正面（南，面向丘腳街）；台基整體下沉 SINK（石積埋入地面）。
原檔前方（glTF +z）＝Godot +z：不旋轉。
碰撞（≤ 8 個 box／convex）：台基、社殿本體（含緣、向拝柱線）、石段斜面（可走上台基前的段頂）、
石段兩側的燈籠＋袖石＋右前高札、兩側石燈籠。建置時以 gate 同一套周邊射線演算法自檢（可見網格不得比碰撞突出 > 0.15 m）。
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
AID = 'hillfoot_temple'
OUT = G + '/assets/village_v2/' + AID
SRC = OUT + '/src/hillfoot_temple_source.glb'
AMAT = 'V2_HillfootTemple'
MATS = [AMAT]
H_TOTAL = 9.00            # P0 高（上限）
SINK = 0.08               # 台基石積埋入
TARGET = {0: 58000, 1: 19500, 2: 5600}
STATS_FLAT = {}
SLIVERS = {}
NONMAN = {}

# ── 碰撞（Godot 局部座標；高度已扣 SINK）。數值來自原檔 S＝9.00/0.733 縮放後的切片量測（建置時自檢周邊射線）
KT = round(1.55 - SINK, 3)          # 台基頂（石段頂＝段頂踊場）
COLL = [
    # 台基（石積）：前緣 z 2.76＝石段最上段段鼻（再往前會在石段斜面上冒出段差）；前角石由 FrontL／FrontR 蓋；
    # 後緣含背面低石（z −5.25）
    {'type': 'box', 'name': 'Kidan', 'lo': [-5.05, -SINK - 0.02, -5.30], 'hi': [5.05, KT, 2.76]},
    # 社殿本體＋緣＋向拝柱線：前面＝向拝柱前緣 z 2.80（賽錢箱、格子戶都在這之內）
    {'type': 'box', 'name': 'Hall', 'lo': [-4.90, KT, -4.65], 'hi': [4.90, 4.60, 2.80]},
    # 石段（LOD0 實測 5 段：踏面 0.28／0.52／0.76／1.00／1.23 → 台基 1.46，蹴上 0.24、踏面 0.35）：
    # 斜面通過各段段鼻（z 4.45 → 2.775），底 z 4.98、頂 z 2.76＝台基頂；寬 ±1.75（兩側袖石另算）
    {'type': 'ramp', 'name': 'Steps', 'x': [-1.75, 1.75], 'z_bot': 4.98, 'z_top': 2.76, 'y0': -SINK - 0.02, 'y1': KT},
    # 石段左：袖石＋前燈籠＋台基左前角石（角石外擴到 x −5.37、z 2.5–3.3，只在左前角）
    {'type': 'box', 'name': 'FrontL', 'lo': [-5.45, -SINK - 0.02, 2.40], 'hi': [-1.75, 2.45, 4.98]},
    # 石段右：袖石＋前燈籠＋高札（小屋根掛）
    {'type': 'box', 'name': 'FrontR', 'lo': [1.75, -SINK - 0.02, 2.40], 'hi': [5.35, 2.85, 5.58]},
    # 兩側石燈籠（左後、右後、右中）
    {'type': 'cyl', 'name': 'LanternL', 'c': [-5.48, -2.76], 'r': 0.74, 'y0': -SINK - 0.02, 'y1': 2.40},
    {'type': 'cyl', 'name': 'LanternR', 'c': [5.48, -2.76], 'r': 0.74, 'y0': -SINK - 0.02, 'y1': 2.40},
    {'type': 'cyl', 'name': 'LanternR2', 'c': [5.48, 0.88], 'r': 0.74, 'y0': -SINK - 0.02, 'y1': 2.40},
]


def load_source():
    bpy.ops.import_scene.gltf(filepath=SRC, merge_vertices=True)
    obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    assert len(obs) == 1, obs
    ob = obs[0]
    me = ob.data.copy()
    me.transform(ob.matrix_world)
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    s = H_TOTAL / (max(zs) - min(zs))
    # 只做等比縮放＋底面落到 −SINK（原檔 xy 已近中心：x ±0.490、y −0.464～0.463，不再平移以免偏離量測）
    me.transform(Matrix.Translation(Vector((0, 0, -SINK))) @ Matrix.Scale(s, 4) @ Matrix.Translation(Vector((0, 0, -min(zs)))))
    for an in [a_.name for a_ in me.attributes if a_.name in ('custom_normal', 'sharp_face', 'sharp_edge')]:
        me.attributes.remove(me.attributes[an])
    n0 = sum(len(p.vertices) - 2 for p in me.polygons)
    return me, s, n0, [(min(xs) * s, max(xs) * s), (min(ys) * s, max(ys) * s)]


def lod_mesh(src_me, lod, bm_mats):
    """龍神像同法（build_dragon_statue.py lod_statue）：Decimate COLLAPSE → 清退化／細片 → 平滑＋依角度斷硬邊。"""
    me = src_me.copy()
    me.name = 'HillfootTemple_tmp%d' % lod
    ob = bpy.data.objects.new(me.name, me)
    bpy.context.scene.collection.objects.link(ob)
    n0 = sum(len(p.vertices) - 2 for p in me.polygons)
    mod = ob.modifiers.new('dec', 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = min(1.0, TARGET[lod] / n0)
    mod.use_collapse_triangulate = True
    with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob]):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bmm = bmesh.new()
    bmm.from_mesh(ob.data)
    bmesh.ops.dissolve_degenerate(bmm, dist=2e-3, edges=bmm.edges[:])
    tri = [f for f in bmm.faces if len(f.verts) > 3]
    if tri:
        bmesh.ops.triangulate(bmm, faces=tri)

    def _sliver(f):
        a_ = f.calc_area()
        l2 = max(e.calc_length() for e in f.edges) ** 2
        return a_ < 4e-4 and (a_ < 1e-5 or a_ / max(l2, 1e-12) < 0.02)
    for _ in range(3):
        bad = [f for f in bmm.faces if _sliver(f)]
        if not bad:
            break
        bmesh.ops.delete(bmm, geom=bad, context='FACES')
        SLIVERS[lod] = SLIVERS.get(lod, 0) + len(bad)
    loose = [v for v in bmm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bmm, geom=loose, context='VERTS')
    nm = set()
    for v in bmm.verts:
        if not v.is_manifold:
            for f in v.link_faces:
                nm.add(f.index)
    bmm.faces.ensure_lookup_table()
    NONMAN[lod] = len(nm)
    bmm.to_mesh(ob.data)
    bmm.free()
    me = ob.data
    for p in me.polygons:
        p.use_smooth = p.index not in nm
    me.set_sharp_from_angle(angle=math.radians(38))
    col = me.color_attributes.new(name='Col', type='FLOAT_COLOR', domain='CORNER')
    for d in col.data:
        d.color = (1.0, 1.0, 1.0, 1.0)
    me.color_attributes.active_color = col
    me.materials.clear()
    for n in MATS:
        me.materials.append(bm_mats[n])
    for p in me.polygons:
        p.material_index = 0
    ob.name = 'HillfootTemple_LOD%d' % lod
    me.name = ob.name
    return ob


def fix_flat(me, lod):
    """龍神像同法（build_dragon_statue.py fix_flat）：減面摺疊處平滑法線與面朝向相反 → 改平面著色。"""
    flat = 0
    for _ in range(40):
        cn = me.corner_normals
        n_fix = 0
        for p in me.polygons:
            if not p.use_smooth:
                continue
            s_ = Vector((0.0, 0.0, 0.0))
            worst = 1.0
            for li in p.loop_indices:
                s_ += cn[li].vector
                worst = min(worst, cn[li].vector.dot(p.normal))
            if s_.length < 1e-6 or s_.normalized().dot(p.normal) < 0.5 or worst < 0.0:
                p.use_smooth = False
                n_fix += 1
        flat += n_fix
        me.update()
        if n_fix == 0:
            break
    STATS_FLAT[lod] = flat
    left = 0
    cn = me.corner_normals
    for p in me.polygons:
        if p.use_smooth and min(cn[li].vector.dot(p.normal) for li in p.loop_indices) < 0.0:
            left += 1
    STATS_FLAT['left%d' % lod] = left


# ── Godot 局部座標的射線（BVH 在 Blender 座標：b = (gx, −gz, gy)）
def _bvh(ob):
    bm_ = bmesh.new()
    bm_.from_mesh(ob.data)
    t = BVHTree.FromBMesh(bm_)
    bm_.free()
    return t


def vis_dist(bvh, a, b):
    fa = Vector((a[0], -a[2], a[1]))
    fb = Vector((b[0], -b[2], b[1]))
    d = fb - fa
    L = d.length
    h = bvh.ray_cast(fa, d.normalized(), L)
    return math.inf if h[0] is None else h[3]


def _planes(c):
    """碰撞 → 凸多面體半空間 [(n, d)]（n·p ≤ d），Godot 局部座標。"""
    if c['type'] == 'box':
        lo, hi = c['lo'], c['hi']
        return [((1, 0, 0), hi[0]), ((-1, 0, 0), -lo[0]), ((0, 1, 0), hi[1]), ((0, -1, 0), -lo[1]),
                ((0, 0, 1), hi[2]), ((0, 0, -1), -lo[2])]
    if c['type'] == 'ramp':
        x0, x1 = c['x']
        zb, zt, y0, y1 = c['z_bot'], c['z_top'], c['y0'], c['y1']
        # 斜面：通過 (zb, y0)、(zt, y1)；法線朝前上
        ny, nz = (zb - zt), (y1 - y0)
        ln = math.hypot(ny, nz)
        ny, nz = ny / ln, nz / ln
        return [((1, 0, 0), x1), ((-1, 0, 0), -x0), ((0, -1, 0), -y0), ((0, 0, -1), -zt), ((0, 1, 0), y1),
                ((0, ny, nz), ny * y0 + nz * zb)]
    if c['type'] == 'cyl':
        out = [((0, 1, 0), c['y1']), ((0, -1, 0), -c['y0'])]
        for k in range(24):
            a = 2 * math.pi * k / 24
            n = (math.cos(a), 0, math.sin(a))
            out.append((n, n[0] * c['c'][0] + n[2] * c['c'][1] + c['r']))
        return out
    raise ValueError(c['type'])


def col_dist(a, b):
    """a→b 線段第一個碰撞形狀的距離（INF＝沒有）。"""
    d = [b[i] - a[i] for i in range(3)]
    L = math.sqrt(sum(x * x for x in d))
    best = math.inf
    for c in COLL:
        t0, t1 = 0.0, 1.0
        ok = True
        for n, dd in _planes(c):
            den = sum(n[i] * d[i] for i in range(3))
            num = dd - sum(n[i] * a[i] for i in range(3))
            if abs(den) < 1e-12:
                if num < 0:
                    ok = False
                    break
                continue
            t = num / den
            if den > 0:
                t1 = min(t1, t)
            else:
                t0 = max(t0, t)
            if t0 > t1:
                ok = False
                break
        if ok:
            best = min(best, t0 * L)
    return best


def poke_check(bvh, aabb):
    """verify_village_v2_hero_gate.gd _c_collision_poke 同演算法（地形高 gl 取 −0.8～0.8 五種，從嚴）。"""
    (x0, y0, z0), (x1, y1, z1) = aabb
    R0 = 3.0
    rays = 0
    pokes = []
    for gl in (-0.8, -0.4, 0.0, 0.4, 0.8):
        for side in range(4):
            along_z = side < 2
            sgn = 1.0 if side % 2 == 0 else -1.0
            lo, hi = (x0, x1) if along_z else (z0, z1)
            s = lo + 0.05
            while s <= hi:
                outer = ((z1 + R0) if sgn > 0 else (z0 - R0)) if along_z else ((x1 + R0) if sgn > 0 else (x0 - R0))

                def P(h, w):
                    return (s, h, w) if along_z else (w, h, s)
                dc = min(col_dist(P(gl + ch, outer), P(gl + ch, 0.0)) for ch in (0.3, 0.6, 1.0, 1.3, 1.6))
                for hh in (0.3, 1.0, 1.6):
                    y = gl + hh
                    if y < -SINK:
                        continue
                    dv = vis_dist(bvh, P(y, outer), P(y, 0.0))
                    if dv == math.inf:
                        continue
                    hp_y = y   # 水平射線：命中點高＝y；離「該處地面」> 1.7 m 的屋簷略過（地面取 max(gl, 0)）
                    if hp_y - max(gl, -SINK) > 1.7:
                        continue
                    rays += 1
                    d = (dc - dv) if dc != math.inf else abs(outer) - dv
                    if d > 0.15:
                        pokes.append((round(d, 2), ['前', '後', '右', '左'][side], round(s, 2), round(y, 2), gl))
                s += 0.2
    pokes.sort(reverse=True)
    return rays, pokes


def ray_measure(bvh, top):
    """building 規格：與 gate _c_size（building）同一組射線。"""
    py, pz, px, gx = 2.8, -1.0, -2.5, 0.0
    xr = 30.0 - vis_dist(bvh, (30, py, pz), (-30, py, pz))
    xl = -30.0 + vis_dist(bvh, (-30, py, pz), (30, py, pz))
    zb = -30.0 + vis_dist(bvh, (px, py, -30), (px, py, 30))
    zfr = 30.0 - vis_dist(bvh, (px, py, 30), (px, py, -30))
    zg = 30.0 - vis_dist(bvh, (gx, py, 30), (gx, py, -30))
    zgb = -30.0 + vis_dist(bvh, (gx, py, -30), (gx, py, 30))
    ridge = 30.0 - vis_dist(bvh, (0.137, 30, 0.043), (0.137, -5, 0.043))
    w, d = xr - xl, zfr - zb
    ze = 4.60                       # 背面簷下（背面牆 z ≈ −3.8、背簷出到 z ≈ −5.6）
    ov = ze - d * 0.5 + 0.05        # gate：ze＝d/2＋ov_eave−0.05 → 反推 ov_eave
    eave = 30.0 - vis_dist(bvh, (px, 30, -ze), (px, -5, -ze))
    return {'w': round(w, 3), 'd': round(d, 3), 'zf': round(zfr, 3), 'zb': round(zb, 3), 'd_tot': round(zg - zgb, 3),
            'plinth': KT, 'ridge': round(ridge, 3), 'eave_edge': round(eave, 3), 'ov_eave': round(ov, 3),
            'probe': {'x': px, 'y': py, 'z': pz, 'gx': gx}, 'top': round(top, 3)}


def _aabb(ob):
    xs = [v.co.x for v in ob.data.vertices]
    ys = [v.co.y for v in ob.data.vertices]
    zs = [v.co.z for v in ob.data.vertices]
    return [[min(xs), min(zs), -max(ys)], [max(xs), max(zs), -min(ys)]]


def godot_shapes():
    out = []
    for c in COLL:
        if c['type'] == 'box':
            lo, hi = c['lo'], c['hi']
            out.append({'type': 'box', 'name': c['name'], 'center': [round((lo[i] + hi[i]) / 2, 4) for i in range(3)],
                        'size': [round(hi[i] - lo[i], 4) for i in range(3)]})
        elif c['type'] == 'cyl':
            out.append({'type': 'cylinder', 'name': c['name'], 'center': [c['c'][0], round((c['y0'] + c['y1']) / 2, 4), c['c'][1]],
                        'radius': c['r'], 'height': round(c['y1'] - c['y0'], 4)})
        elif c['type'] == 'ramp':
            x0, x1 = c['x']
            pts = []
            for x in (x0, x1):
                pts += [[x, c['y0'], c['z_bot']], [x, c['y0'], c['z_top']], [x, c['y1'], c['z_top']]]
            out.append({'type': 'convex', 'name': c['name'], 'center': [0, 0, 0], 'points': pts})
    return out


def main():
    K.clear_scene(bpy)
    bm_mats = K.blender_mats(bpy, MATS)
    src_me, scale, n_src, fp = load_source()
    objs = []
    stats = {'source_tris': n_src, 'scale': round(scale, 4)}
    for lod in (0, 1, 2):
        ob = lod_mesh(src_me, lod, bm_mats)
        fix_flat(ob.data, lod)
        objs.append(ob)
        stats['LOD%d' % lod] = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        ab = _aabb(ob)
        stats['aabb' if lod == 0 else 'aabb_lod%d' % lod] = [[round(v, 3) for v in a] for a in ab]
    K.export_glb(bpy, OUT + '/src/' + AID + '.glb', objs)
    stats['pre_export'] = {k: stats[k] for k in ('LOD0', 'LOD1', 'LOD2')}
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=OUT + '/src/' + AID + '.glb')
    for o in [o for o in bpy.data.objects if o not in before]:
        if o.type == 'MESH':
            nm = o.name.split('.')[0]
            stats[nm.replace('HillfootTemple_', '')] = sum(len(p.vertices) - 2 for p in o.data.polygons)
        bpy.data.objects.remove(o, do_unlink=True)
    ab0 = stats['aabb']
    bvh = _bvh(objs[0])
    rays, pokes = poke_check(bvh, ab0)
    bld = ray_measure(bvh, ab0[1][1])
    stats['poke_selfcheck'] = {'rays': rays, 'over_0.15': len(pokes), 'worst': pokes[:30]}
    # 石段：斜面 vs 各段段鼻（x 0、±1.2；前→後找每 0.05 m 高度的可見前緣）
    nos = []
    for x in (0.0, -1.2, 1.2):
        for k in range(1, 32):
            y = -SINK + 0.05 * k
            dv = vis_dist(bvh, (x, y, 9.0), (x, y, 0.0))
            if dv != math.inf:
                nos.append((x, round(y, 2), round(9.0 - dv, 3)))
    R = COLL[2]
    worst_float = 0.0
    for x, y, z in nos:
        if R['z_top'] <= z <= R['z_bot']:
            ry = R['y0'] + (R['z_bot'] - z) / (R['z_bot'] - R['z_top']) * (R['y1'] - R['y0'])
            worst_float = max(worst_float, ry - y)
    stats['steps'] = {'ramp_deg': round(math.degrees(math.atan2(R['y1'] - R['y0'], R['z_bot'] - R['z_top'])), 1),
                      'front_profile_x0': [p for p in nos if p[0] == 0.0][::2]}
    lm_top = H_TOTAL
    spec = {
        '_note': '丘腳社寺 Hero 資產規格（build_hillfoot_temple.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、'
                 'verify_village_v2_hero_gate.gd 讀取）。幾何取自使用者 2026-10-17 提供的 Tripo 模型'
                 '（src/hillfoot_temple_source.glb，原檔 D:/資產glb/丘腳社寺/japanese+shrine+3d+model.glb；唯讀讀入、減面、另存）。'
                 ' 放在 P0 地標原點（anchor），取代 P0 佔位 Block；尺寸以 P0 量體 18 × 9 × 12 為上限、地塊 P_LM_HILLFOOT_TEMPLE 為界。'
                 ' building.ov_eave 是讓 gate 的背面簷口射線落在背簷下（z −4.60）反推的值，不是實際出簷。',
        'id': AID, 'landmark': 'LANDMARK_HILLFOOT_TEMPLE', 'kind': 'hero', 'budget_class': '社殿',
        'glb': 'res://assets/village_v2/%s/src/%s.glb' % (AID, AID),
        'scene': 'res://assets/village_v2/%s/%s.scn' % (AID, AID),
        'lod_objects': ['HillfootTemple_LOD0', 'HillfootTemple_LOD1', 'HillfootTemple_LOD2'],
        'lod_ranges_m': [0, 45, 130, 700],
        'budget': {'lod0': 60000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.1, 'materials': 5, 'collision': 8},
        'materials': {AMAT: 'res://assets/village_v2/%s/%s.tres' % (AID, AMAT)},
        'spec': {'source': 'Tripo（使用者 2026-10-17 提供）', 'source_tris': n_src, 'scale': round(scale, 4),
                 'height_m': H_TOTAL, 'sink_m': SINK, 'kidan_top_m': KT, 'front': '+z（南，面向丘腳街）',
                 'footprint_m': [round(ab0[1][0] - ab0[0][0], 2), round(ab0[1][2] - ab0[0][2], 2)],
                 'design': {'kidan': '石積台基（頂 %.2f m）＋正面石段 6 段（斜面碰撞沿段鼻、%s°）' % (KT, stats['steps']['ramp_deg']),
                            'hall': '入母屋系瓦屋根、向拝、緣＋高欄、格子戶、注連繩、賽錢箱',
                            'props': '石燈籠（石段兩側、台基左後／右後／右中）、右前高札（小屋根）'}},
        'gate_spec': {
            'placement': 'anchor', 'anchor': 'Landmarks/LANDMARK_HILLFOOT_TEMPLE', 'replaces': 'Block', 'p4_id': '',
            'parcel': 'P_LM_HILLFOOT_TEMPLE', 'road': 'HillFootStreet',
            'size': {'x_half_max': 9.0, 'z_min': -6.0, 'z_max': 6.0, 'top': [round(lm_top - SINK - 0.3, 3), lm_top],
                     'bottom': -SINK},
            'building': {k: bld[k] for k in ('zf', 'plinth', 'ridge', 'eave_edge', 'ov_eave', 'probe')} | {'w': bld['w'], 'd': bld['d']},
            'ground': [{'name': '台基', 'rect': [-4.85, -4.45, 4.85, 2.85], 'bottom': -SINK, 'top': KT, 'embed_max': 0.15},
                       {'name': '石段', 'rect': [-1.70, 2.95, 1.70, 4.40], 'bottom': -SINK, 'top': round(0.30 - SINK, 3),
                        'embed_max': 0.15}],
            'walkway': {'rect': [-3.0, 5.7, 3.0, 6.6], 'head': 1.95, 'min_clear': 2.5, 'step': 0.25},
            'entry': [0.0, 6.2], 'inside': [0.0, -1.0],
            # 入口石段：各段踏面中心（局部 x, z）；gate 以 LOD0 實測踏面高，路面→各段→台基頂每階 ≤ 0.30
            'steps': [[0.0, 4.27], [0.0, 3.90], [0.0, 3.55], [0.0, 3.20], [0.0, 2.90]],
            # F5 實走：自西側朝台基走 4 秒 → 必須被台基石積擋在外（石段可登，另由收尾 smoke 實走驗）
            'walk': {'from': [-9.0, -1.0], 'to': [0.0, -1.0], 'box': [-5.05, -5.30, 5.05, 3.10]},
            'shots': [['front', 0.0, 10.0], ['front_l', 7.0, 9.5], ['front_r', -7.0, 9.5], ['approach', -8.0, 16.0]]},   # approach：丘腳街西側斜望（相機在街心；(4, 21) 會讓相機塞進街南民家簷下）
        'collision': godot_shapes(),
        'measured_blender': stats,
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[HILLFOOT]', {k: stats[k] for k in ('source_tris', 'scale', 'LOD0', 'LOD1', 'LOD2', 'aabb', 'aabb_lod1', 'aabb_lod2')})
    print('[HILLFOOT] building', bld)
    print('[HILLFOOT] poke', stats['poke_selfcheck'])
    print('[HILLFOOT] steps', stats['steps'], 'ramp above visible step (max) %.3f m' % worst_float)
    print('[HILLFOOT] flat-fixed', STATS_FLAT, 'slivers', SLIVERS, 'nonmanifold-flat', NONMAN)


main()
