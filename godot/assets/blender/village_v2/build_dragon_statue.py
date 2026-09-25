"""龍神像（LANDMARK_DRAGON）— 人間之里 V2 P5 R4 新資產（REWORK 產物另存）。

  python tools/build_village_v2_r4_atlas.py        # 先產底色（dragon_statue_albedo.jpg）
  blender -b --factory-startup --python godot/assets/blender/village_v2/build_dragon_statue.py

來源：Protected 原檔 res://maps/village/gen/龍神像/龍神像.glb（Meshy AI，312,858 面、單材質）。registry：
「可 REWORK／拆件／重做基座／減面／修材質；原檔不得改、不得移。REWORK 產物另存新檔」。本腳本只**讀入**
（Blender 記憶體內），不存 .blend、不寫回原檔；輸出全在 assets/village_v2/dragon_statue/。
參考：docs/reference/重點地標/龍神像.png、龍神像2.png（vision：四足直立守護龍、頭高舉、雙角、張口、
八角形多層石台座、無岩座、風化灰褐石材；台座：龍身 ≈ 1:1）。原檔 vision 判讀：構圖相符、輪廓可讀。
尺寸 authority：layout_v2.json LANDMARK_DRAGON：base 10×10（河岸基壇，從河床起到 base_top 世界 2.5）、
statue_r 2、statue_h 12（上限，不超過）。原點＝P0 地標原點（地面），+z＝龍頭朝向（南，面向村）。
做法：P0 基壇（V2_Stone，10×10）＋原檔雕像等比縮放到腳印 ≤ 9.4 m 放在基壇頂；三級 LOD 由 Decimate 減面。
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
SRC = G + '/maps/village/gen/龍神像/龍神像.glb'          # Protected（唯讀）
OUT = G + '/assets/village_v2/dragon_statue'
MATLIB = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')
TILE = {k: v['tile_m'] for k, v in MATLIB['materials'].items()}
AMAT = 'V2_DragonStatue'
MATS = ['V2_Stone', AMAT]

ORIGIN_Y = -0.169436       # P0 地標原點世界高（gen_village_v2 _hgrid；probe 實測）
BASE_TOP_W = 2.5           # P0 base_top（世界）
Y_F = round(BASE_TOP_W - ORIGIN_Y, 3)      # 基壇頂（局部）2.669
BOT = -3.80                # 基壇底（河床側地形最低 −3.1 以下）
HALF = 5.0                 # P0 base 10×10
STATUE_H_MAX = 12.0        # P0 statue_h（上限）
FOOT = 9.40                # 雕像腳印上限（基壇內留 0.3 m 緣）
TARGET = {0: 88000, 1: 30000, 2: 8200}
STATS_FLAT = {}
SLIVERS = {}
NONMAN = {}


def build_base(lod):
    m = K.Mesh('Dragon_Base_LOD%d' % lod, MATS, TILE)
    b = HALF - 0.15
    m.box((-b, BOT, -b), (b, Y_F - 0.28, b), 'V2_Stone', 0.92, skip=('-y',))
    # 笠石（壓頂）：外緣 ±5.0，頂面被雕像台座蓋住的部分照樣做（遠看是台座下一圈石緣）
    m.box((-HALF, Y_F - 0.28, -HALF), (HALF, Y_F, HALF), 'V2_Stone', 1.0)
    if lod == 0:
        # 石積目地：每 0.7 m 一道淺凹帶（四面），打破 10 m 大平面
        for y in (Y_F - 1.0, Y_F - 1.7, Y_F - 2.4, Y_F - 3.1, Y_F - 3.8, Y_F - 4.5, Y_F - 5.2):
            if y <= BOT + 0.1:
                continue
            m.box((-b - 0.04, y - 0.05, -b - 0.04), (b + 0.04, y + 0.05, b + 0.04), 'V2_Stone', 0.70,
                  skip=('-y', '+y'))
    return m


def load_statue():
    bpy.ops.import_scene.gltf(filepath=SRC)
    obs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    assert len(obs) == 1, obs
    ob = obs[0]
    me = ob.data.copy()
    me.transform(ob.matrix_world)
    # 丟掉匯入時的物件與材質；只留幾何＋UV
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    foot = max(max(xs) - min(xs), max(ys) - min(ys))
    s = min(FOOT / foot, STATUE_H_MAX / (max(zs) - min(zs)))
    # Blender 座標（z 上、−y＝原檔正面＝龍頭）：底面放到基壇頂、置中；Godot +z ＝ Blender −y（glTF 轉換）
    me.transform(Matrix.Translation(Vector((0, 0, Y_F))) @ Matrix.Scale(s, 4) @ Matrix.Translation(Vector((-cx, -cy, -min(zs)))))
    # 原檔自帶自訂法線（Meshy）：減面後會被內插成亂向 → 移除，改由幾何重算
    for an in [a_.name for a_ in me.attributes if a_.name in ('custom_normal', 'sharp_face', 'sharp_edge')]:
        me.attributes.remove(me.attributes[an])
    return me, s, (max(zs) - min(zs)) * s


def lod_statue(src_me, lod, bm_mats):
    me = src_me.copy()
    me.name = 'Dragon_Statue_tmp%d' % lod
    ob = bpy.data.objects.new(me.name, me)
    bpy.context.scene.collection.objects.link(ob)
    n0 = sum(len(p.vertices) - 2 for p in me.polygons)
    mod = ob.modifiers.new('dec', 'DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = TARGET[lod] / n0
    mod.use_collapse_triangulate = True
    with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob]):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bmm = bmesh.new()
    bmm.from_mesh(ob.data)
    bmesh.ops.dissolve_degenerate(bmm, dist=2e-3, edges=bmm.edges[:])   # 2 mm：清掉細長碎片（法線不穩）
    tri = [f for f in bmm.faces if len(f.verts) > 3]
    if tri:
        bmesh.ops.triangulate(bmm, faces=tri)
    # 細長／極小殘片（減面摺疊後的 sliver；float32 匯出後法線不穩、Godot 匯入會丟）：刪掉。
    # 門檻：面積 < 4 cm²，或 面積／最長邊² < 0.02（高 ≤ 最長邊 4 %）。雕像 5.2 倍放大後這些片寬 < 1 cm。
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
    # 繞向沿用原檔（背面剔除渲染實測：原檔無破洞）。recalc_face_normals 在非流形殼上會把整片翻成朝內
    # → 遊戲內背面剔除下看成大破洞（R4 第一版 F6 截圖），故不重算。
    # 非流形頂點（多片扇面共點）：平滑法線在各扇面間互相抵消 → 周圍面一律平面著色
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
    # 平滑＋依角度斷硬邊（台座稜線保持銳利、龍身平滑）
    for p in me.polygons:
        p.use_smooth = p.index not in nm
    me.set_sharp_from_angle(angle=math.radians(38))
    # 頂點色：反照率乘數（材質 vertex_color_use_as_albedo）。1.0＝貼圖原色
    col = me.color_attributes.new(name='Col', type='FLOAT_COLOR', domain='CORNER')
    for d in col.data:
        d.color = (1.0, 1.0, 1.0, 1.0)
    me.color_attributes.active_color = col
    me.materials.clear()
    for n in MATS:
        me.materials.append(bm_mats[n])
    for p in me.polygons:
        p.material_index = 1
    return ob


def fix_flat(me, lod):
    """減面後的摺疊處：平滑法線與面朝向相反（gate「繞向反」＝頂點法線和面法線夾角 > 101°）→ 改平面著色。
    在 join 之後、匯出之前跑（join 會重算法線）。"""
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
    STATS_FLAT['custom%d' % lod] = bool(me.has_custom_normals)


def join(base_ob, statue_ob, name):
    with bpy.context.temp_override(active_object=base_ob, object=base_ob,
                                   selected_objects=[base_ob, statue_ob],
                                   selected_editable_objects=[base_ob, statue_ob]):
        bpy.ops.object.join()
    base_ob.name = name
    base_ob.data.name = name
    return base_ob


def hull_points(ob, z0, z1):
    """LOD 物件在 Blender z∈[z0, z1) 的頂點凸殼 → Godot 座標點列（碰撞 convex）。"""
    bmm = bmesh.new()
    pts = [v.co.copy() for v in ob.data.vertices if z0 <= v.co.z < z1]
    for p in pts:
        bmm.verts.new(p)
    res = bmesh.ops.convex_hull(bmm, input=bmm.verts[:])
    hv = [v for v in res['geom'] if isinstance(v, bmesh.types.BMVert)]
    out = [[round(v.co.x, 3), round(v.co.z, 3), round(-v.co.y, 3)] for v in hv]
    bmm.free()
    return out


def main():
    K.clear_scene(bpy)
    bm_mats = K.blender_mats(bpy, MATS)
    src_me, scale, h = load_statue()
    top = Y_F + h
    objs = []
    stats = {'statue_scale': round(scale, 4), 'statue_h_m': round(h, 3), 'source_tris': 312858}
    hulls = []
    for lod in (0, 1, 2):
        st = lod_statue(src_me, lod, bm_mats)
        if lod == 2:
            zb = [Y_F, Y_F + 0.20 * h, Y_F + 0.45 * h, Y_F + 0.70 * h, top + 0.01]
            hulls = [hull_points(st, zb[i], zb[i + 1]) for i in range(4)]
        n_st = sum(len(p.vertices) - 2 for p in st.data.polygons)
        base = build_base(lod).to_blender(bpy, bmats=bm_mats)
        ob = join(base, st, 'Dragon_Statue_LOD%d' % lod)
        fix_flat(ob.data, lod)
        objs.append(ob)
        me = ob.data
        stats['LOD%d' % lod] = sum(len(p.vertices) - 2 for p in me.polygons)
        stats['LOD%d_statue' % lod] = n_st
        if lod == 0:
            xs = [v.co.x for v in me.vertices]
            ys = [v.co.y for v in me.vertices]
            zs = [v.co.z for v in me.vertices]
            stats['aabb'] = [[round(min(xs), 3), round(min(zs), 3), round(-max(ys), 3)],
                             [round(max(xs), 3), round(max(zs), 3), round(-min(ys), 3)]]
    K.export_glb(bpy, OUT + '/src/dragon_statue.glb', objs)
    # 面數以匯出後的 GLB 為準（glTF exporter 會丟掉少數零面積三角形；gate 比的是 Godot 讀到的 GLB）
    stats['pre_export'] = {k: stats[k] for k in ('LOD0', 'LOD1', 'LOD2')}
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=OUT + '/src/dragon_statue.glb')
    for o in [o for o in bpy.data.objects if o not in before]:
        if o.type == 'MESH':
            nm = o.name.split('.')[0]
            stats[nm.replace('Dragon_Statue_', '')] = sum(len(p.vertices) - 2 for p in o.data.polygons)
        bpy.data.objects.remove(o, do_unlink=True)
    mats = {k: MATLIB['materials'][k]['tres'] for k in MATS if k != AMAT}
    mats[AMAT] = 'res://assets/village_v2/dragon_statue/V2_DragonStatue.tres'
    top_p0 = BASE_TOP_W - ORIGIN_Y + STATUE_H_MAX
    b = HALF - 0.15
    spec = {
        '_note': '龍神像 資產規格（build_dragon_statue.py 產生；Godot 端 tools/village_v2_hero_prefab.gd、verify_village_v2_hero_gate.gd 讀取）。'
                 ' 雕像幾何取自 Protected 原檔 maps/village/gen/龍神像/龍神像.glb（唯讀讀入、減面、另存），原檔未改。',
        'id': 'dragon_statue', 'landmark': 'LANDMARK_DRAGON', 'kind': 'landmark', 'budget_class': '龍神像',
        'glb': 'res://assets/village_v2/dragon_statue/src/dragon_statue.glb',
        'scene': 'res://assets/village_v2/dragon_statue/dragon_statue.scn',
        'lod_objects': ['Dragon_Statue_LOD0', 'Dragon_Statue_LOD1', 'Dragon_Statue_LOD2'],
        'lod_ranges_m': [0, 70, 200, 800],
        'budget': {'lod0': 100000, 'lod1_ratio': 0.35, 'lod2_ratio': 0.10, 'materials': 5, 'collision': 8},
        'materials': mats,
        'spec': {'base_m': [2 * HALF, 2 * HALF], 'base_top_local_m': Y_F, 'base_top_world_m': BASE_TOP_W,
                 'statue_h_m': round(h, 3), 'statue_h_p0_max_m': STATUE_H_MAX, 'statue_scale': round(scale, 4),
                 'top_local_m': round(top, 3), 'top_p0_max_local_m': round(top_p0, 3), 'front': '+z（南，面向村）',
                 'source': 'res://maps/village/gen/龍神像/龍神像.glb（Protected，唯讀）'},
        'gate_spec': {
            'placement': 'anchor', 'anchor': 'Landmarks/LANDMARK_DRAGON', 'replaces': 'Statue', 'also_retire': ['Base'],
            'p4_id': '', 'parcel': '', 'road': 'RiverNorthPath',
            'size': {'x_half_max': HALF, 'z_min': -HALF, 'z_max': HALF, 'top': [round(top - 0.3, 3), round(top_p0, 3)],
                     'bottom': BOT},
            'ground': [{'name': '河岸基壇', 'rect': [-b, -b, b, b], 'bottom': BOT, 'top': Y_F - 0.28, 'embed_max': 0.9}],
            # 村側（西）步行帶：基壇外 1.2–2.7 m
            'walkway': {'rect': [-7.8, -4.0, -6.3, 4.0], 'head': 1.95, 'min_clear': 3.0, 'step': 0.5},
            'entry': [-3.0, 7.5], 'inside': [0.0, 0.0],
            # F5 實走：從村側（西）步行帶朝基壇走 4 秒 → 必須被基壇擋在外
            'walk': {'from': [-9.5, 0.0], 'to': [0.0, 0.0], 'box': [-HALF, -HALF, HALF, HALF]}},
        'collision': [
            {'type': 'box', 'center': [0, (Y_F + BOT) / 2, 0], 'size': [2 * b, Y_F - BOT, 2 * b], 'name': 'Base'},
            {'type': 'box', 'center': [0, Y_F - 0.14, 0], 'size': [2 * HALF, 0.28, 2 * HALF], 'name': 'Coping'}] + [
            {'type': 'convex', 'center': [0, 0, 0], 'points': hp, 'name': 'Statue_%d' % i} for i, hp in enumerate(hulls)],
        'measured_blender': stats,
    }
    K.write_json(OUT + '/asset.json', spec)
    print('[DRAGON]', stats, 'hull pts', [len(h2) for h2 in hulls], 'flat-fixed', STATS_FLAT, 'slivers', SLIVERS, 'nonmanifold-flat', NONMAN)


main()
