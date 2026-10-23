"""阿求 → Godot（小鈴同款：袖子用 Jolt SoftBody3D 布料）。來源 blend 只讀不存（照目前存檔的材質原樣匯出）。
  - 全物件等比縮放到指定身高（髮頂）、正面 -Y（glTF/Godot +Z）、腳底 z=0、套用變換
  - akyuu.glb：骨架（65 骨 mixamorig）＋身體／衣身／頭髮／鞋，不含袖、不含動作（動作由 Mixamo clip 經 Godot retarget）
  - akyuu_sleeve_{L,R}.glb：袖子靜態網格（rest），長邊細分，頂點色釘點 R＝上臂上緣、G＝前臂上緣、B＝肩縫
  - akyuu_colliders.json：衣身每層凸包（給袖子碰）＋大腿／上臂／前臂／手膠囊；Blender 世界座標（Z 上）
blender -b <阿求_rig_4K.blend> -P export_akyuu_glb.py -- <height_m> <out_dir>
"""
import bpy, bmesh, sys, os, json, math
import numpy as np
from mathutils import Matrix, Vector
argv = sys.argv[sys.argv.index('--') + 1:]
HEIGHT, OUT = float(argv[0]), argv[1]
os.makedirs(OUT, exist_ok=True)
SRC = bpy.data.filepath
for o in list(bpy.data.objects):
    if o.type in ('CAMERA', 'LIGHT'):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for pb in arm.pose.bones:
    pb.matrix_basis = Matrix()
if arm.animation_data:
    arm.animation_data.action = None
for o in bpy.data.objects:
    o.hide_set(False); o.hide_viewport = False
bpy.context.view_layer.update()
def bbox():
    a = np.array([tuple(m.matrix_world @ v.co) for m in meshes for v in m.data.vertices]); return a.min(0), a.max(0)
lo, hi = bbox()
rep = {'src': SRC, 'target_height': HEIGHT, 'src_height': float(hi[2] - lo[2]), 'bones': len(arm.data.bones)}
s = HEIGHT / float(hi[2] - lo[2]); rep['scale'] = s
roots = [o for o in bpy.data.objects if o.parent is None]
for r in roots: r.matrix_world = Matrix.Scale(s, 4) @ r.matrix_world
bpy.context.view_layer.update()
P = 'mixamorig:'
B = arm.data.bones
def bw(n): return arm.matrix_world @ B[P + n].head_local
lr = bw('LeftArm') - bw('RightArm')
snap = round(math.degrees(math.atan2(lr.y, lr.x)) / 90.0) * 90.0
rep['facing_fix_deg'] = -snap
if snap:
    for r in roots: r.matrix_world = Matrix.Rotation(math.radians(-snap), 4, 'Z') @ r.matrix_world
bpy.context.view_layer.update()
lo, hi = bbox()
for r in roots: r.matrix_world = Matrix.Translation((0, 0, -float(lo[2]))) @ r.matrix_world
bpy.context.view_layer.update()
sel = list(bpy.context.view_layer.objects)
for o in sel: o.select_set(True)
bpy.context.view_layer.objects.active = arm
if bpy.context.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
with bpy.context.temp_override(active_object=arm, object=arm, selected_objects=sel, selected_editable_objects=sel):
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o.type == 'EMPTY':
        for c in list(o.children):
            mw = c.matrix_world.copy(); c.parent = None; c.matrix_world = mw
        bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.update()
arm.name = 'Armature'
lo, hi = bbox(); rep['height_m'] = float(hi[2] - lo[2]); rep['feet_z'] = float(lo[2])
K = s   # 小鈴的門檻值是在約 1 m 高的 blend 單位量的；阿求來源也是約 1 m → 依縮放等比放大
def seg(p, a, b):
    ab = b - a; t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared)); return (p - (a + ab * t)).length, t
# ---------- 袖：靜態網格（rest），細分長邊，釘點色 R=上臂 G=前臂 B=肩 ----------
for side, nm in [('Left', '左袖'), ('Right', '右袖')]:
    o = bpy.data.objects[nm]
    me = o.data.copy(); mw = o.matrix_world.copy()
    bm = bmesh.new(); bm.from_mesh(me); bm.transform(mw)
    for it in range(4):
        le = [e for e in bm.edges if e.calc_length() > 0.025 * K]
        if not le: break
        bmesh.ops.subdivide_edges(bm, edges=le, cuts=1, use_grid_fill=False)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
    el = sorted(e.calc_length() for e in bm.edges)
    new = bpy.data.meshes.new('Sleeve_' + side); bm.to_mesh(new); bm.free()
    so = bpy.data.objects.new('Sleeve_' + side, new); bpy.context.scene.collection.objects.link(so)
    for m in me.materials: new.materials.append(m)
    sh, el_, wr = bw(side + 'Arm'), bw(side + 'ForeArm'), bw(side + 'Hand')
    # 釘點顏色＝該點自己的蒙皮權重（B＝肩＋Spine2、R＝上臂、G＝前臂，正規化）：引擎端依權重混合骨頭變換，
    # 避免「肩釘」與「上臂釘」相鄰兩點各跟一根骨頭，手臂一放下就把中間的布拉長 8 倍（2026-10-19 實測）。
    gname = {g.index: g.name for g in o.vertex_groups}
    col = new.color_attributes.new('pin', 'FLOAT_COLOR', 'POINT')
    npin = [0, 0, 0]
    for v in new.vertices:
        p = v.co
        d1, t1 = seg(p, sh, el_); d2, t2 = seg(p, el_, wr)
        axz1 = sh.z + (el_.z - sh.z) * t1
        axz2 = el_.z + (wr.z - el_.z) * t2
        pin = -1
        if abs(p.x) < abs(sh.x) + 0.012 * K:                         # 肩縫一帶（正面 -Y 後手臂沿 ±X）
            pin = 2
        elif d1 < 0.04 * K and p.z > axz1 - 0.02 * K and t1 < 0.98:  # 上臂上緣筒
            pin = 0
        elif d2 < 0.04 * K and p.z > axz2 - 0.02 * K and t2 < 0.98:  # 前臂上緣筒（阿求的袖子包到手腕）
            pin = 1
        c = (0, 0, 0, 1)
        if pin >= 0:
            w = {'R': 0.0, 'G': 0.0, 'B': 0.0}
            for g in v.groups:
                n = gname.get(g.group, '')
                if n.endswith(side + 'ForeArm'): w['G'] += g.weight
                elif n.endswith(side + 'Arm'): w['R'] += g.weight
                elif n.endswith(side + 'Shoulder') or n.endswith('Spine2'): w['B'] += g.weight
            s_ = w['R'] + w['G'] + w['B']
            if s_ < 1e-4:
                w = {'R': float(pin == 0), 'G': float(pin == 1), 'B': float(pin == 2)}; s_ = 1.0
            c = (w['R'] / s_, w['G'] / s_, w['B'] / s_, 1)
            npin[pin] += 1
        col.data[v.index].color = c
    new.color_attributes.active_color = col
    bpy.ops.object.select_all(action='DESELECT'); so.select_set(True); bpy.context.view_layer.objects.active = so
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, 'akyuu_sleeve_%s.glb' % side[0]), use_selection=True, export_format='GLB',
                              export_skins=False, export_animations=False, export_vertex_color='ACTIVE', export_yup=True)
    rep[nm] = {'verts': len(new.vertices), 'edge_med_mm': round(el[len(el) // 2] * 1000, 1), 'edge_max_mm': round(el[-1] * 1000, 1),
               'pins_upperarm_forearm_shoulder': npin}
    bpy.data.objects.remove(so)
# ---------- 衣身碰撞：每 4 cm 一層凸包點（略內縮 0.5 cm），依高度分給 Hips/Spine/Spine1/Spine2 ----------
k = bpy.data.objects['衣身']; KV = [k.matrix_world @ v.co for v in k.data.vertices]
zs = {n: bw(n).z for n in ('Hips', 'Spine', 'Spine1', 'Spine2')}
slabs = []
z0 = min(p.z for p in KV) + 0.02
ztop = zs['Spine1']   # 只到胸下：再往上袖根在 T-pose 就壓在胸殼裡，Jolt 一推就把腋下布拉長（實測 9 倍）
while z0 <= ztop:
    sl = [p for p in KV if abs(p.z - z0) <= 0.025]
    if len(sl) >= 8:
        cx = sum(p.x for p in sl) / len(sl); cy = sum(p.y for p in sl) / len(sl)
        pts = []
        for p in sl:
            d = Vector((p.x - cx, p.y - cy, 0)); L = d.length
            q = p - d.normalized() * min(0.005, L * 0.5) if L > 1e-6 else p
            pts.append([round(q.x, 4), round(q.y, 4), round(q.z, 4)])
        bone = 'Spine2' if z0 > zs['Spine2'] else ('Spine1' if z0 > zs['Spine1'] else ('Spine' if z0 > zs['Spine'] else 'Hips'))
        slabs.append({'z': round(z0, 3), 'bone': P + bone, 'pts_blender': pts})
    z0 += 0.04
caps = []
for side in ['Left', 'Right']:
    caps += [{'name': side + 'UpLeg', 'a': P + side + 'UpLeg', 'b': P + side + 'Leg', 'r': round(0.055 * K, 4)},
             {'name': side + 'Arm', 'a': P + side + 'Arm', 'b': P + side + 'ForeArm', 'r': round(0.018 * K, 4)},
             {'name': side + 'ForeArm', 'a': P + side + 'ForeArm', 'b': P + side + 'Hand', 'r': round(0.016 * K, 4)},
             {'name': side + 'Hand', 'a': P + side + 'Hand', 'b': P + side + 'HandMiddle2', 'r': round(0.014 * K, 4)}]
json.dump({'slabs': slabs, 'capsules': caps, 'note': 'pts in Blender world (Z up); Godot = (x, z, -y)'},
          open(os.path.join(OUT, 'akyuu_colliders.json'), 'w'))
rep['slabs'] = len(slabs)
# ---------- 主體 GLB（不含袖、不含動作）----------
body_meshes = [m for m in meshes if m.name not in ('左袖', '右袖')]
rep['meshes'] = {}
for m in body_meshes:
    m.data.calc_loop_triangles()
    infl = max((len([g for g in v.groups if g.weight > 0]) for v in m.data.vertices), default=0)
    zero = sum(1 for v in m.data.vertices if not any(g.weight > 0 for g in v.groups))
    rep['meshes'][m.name] = {'verts': len(m.data.vertices), 'tris': len(m.data.loop_triangles), 'max_influences': infl, 'zero_weight_verts': zero}
rep['materials'] = {}
for m in body_meshes:
    for sl in m.material_slots:
        mat = sl.material
        if mat and mat.use_nodes:
            bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
            nl = bsdf.inputs['Normal'].links if bsdf else []
            rep['materials'][mat.name] = 'normal<-' + (nl[0].from_node.bl_idname + ':' + nl[0].from_socket.name if nl else 'none')
for o in bpy.context.view_layer.objects: o.select_set(False)
arm.select_set(True)
for m in body_meshes: m.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, 'akyuu.glb'), export_format='GLB', use_selection=True, export_materials='EXPORT',
                          export_image_format='AUTO', export_animations=False, export_skins=True, export_yup=True,
                          export_apply=False, export_influence_nb=4)
json.dump(rep, open(os.path.join(OUT, 'akyuu_export_report.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('REPORT', json.dumps(rep, ensure_ascii=False))
