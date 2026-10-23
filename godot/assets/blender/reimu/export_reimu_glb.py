"""靈夢 → Godot（袴＝SpringBoneSimulator3D 骨鏈驅動裙擺骨 → 蒙皮袴）。來源 blend 只讀不存。
  - 依「身體」網格高度等比縮放（HEIGHT＝頭頂到腳底，不含蝴蝶結）、正面 -Y（glTF/Godot +Z）、腳底 z=0、套用變換
  - reimu.glb：骨架（65 骨 mixamorig＋48 根 Skirt_* 裙擺骨）＋全部網格（袴蒙皮在裙擺骨上），不含動作
  - reimu_skirt_chains.json：16 條裙擺鏈各關節的靜止位置；Godot 端 reimu_skirt.gd 用來設彈簧骨鏈長度
  - reimu_colliders.json：骨盆每層凸包（跟 Hips）＋大腿／小腿膠囊；Blender 世界座標（Z 上）
  - 卡通材質（TOON_Shade 節點群組）匯出前暫時把輸出改接回原則化 BSDF，glTF 才會帶貼圖
blender -b <靈夢_rig_權重v2_裙擺骨.blend> -P export_reimu_glb.py -- <height_m> <out_dir> [name=reimu]
  name：輸出檔名前綴（<name>.glb／<name>_skirt_chains.json／<name>_colliders.json／<name>_export_report.json）。
  魔理莎等同一套 Tripo 65 骨＋Skirt_NN_s 裙擺骨的角色共用這支（2026-10-20：傳 marisa）。
"""
import bpy, bmesh, sys, os, json, math
import numpy as np
from mathutils import Matrix, Vector
argv = sys.argv[sys.argv.index('--') + 1:]
HEIGHT, OUT = float(argv[0]), argv[1]
NAME = argv[2] if len(argv) > 2 else 'reimu'
os.makedirs(OUT, exist_ok=True)
SRC = bpy.data.filepath
for o in list(bpy.data.objects):
    if o.type in ('CAMERA', 'LIGHT'):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.data.objects if o.type == 'MESH' and o.find_armature() == arm]
for o in [o for o in bpy.data.objects if o.type == 'MESH' and o not in meshes]:
    bpy.data.objects.remove(o, do_unlink=True)          # 預覽用代理物件（無蒙皮）
for pb in arm.pose.bones:
    pb.matrix_basis = Matrix()
if arm.animation_data:
    arm.animation_data.action = None
for o in bpy.data.objects:
    o.hide_set(False); o.hide_viewport = False
bpy.context.view_layer.update()
def bbox(objs):
    a = np.array([tuple(m.matrix_world @ v.co) for m in objs for v in m.data.vertices]); return a.min(0), a.max(0)
body = bpy.data.objects['身體']
lo, hi = bbox([body])
rep = {'src': SRC, 'target_body_height': HEIGHT, 'src_body_height': float(hi[2] - lo[2]), 'bones_src': len(arm.data.bones)}
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
lo, hi = bbox(meshes)
for r in roots: r.matrix_world = Matrix.Translation((0, 0, -float(lo[2]))) @ r.matrix_world
bpy.context.view_layer.update()
sel = list(bpy.context.view_layer.objects)
for o in sel: o.select_set(True)
bpy.context.view_layer.objects.active = arm
if bpy.context.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
for o in meshes:                                       # 形狀鍵（下半臉等）以目前值烘進網格，transform_apply 才不會擋
    if o.data.shape_keys:
        mix = o.shape_key_add(name='__mix', from_mix=True)
        cos = [d.co.copy() for d in mix.data]
        o.shape_key_clear()
        for v, c in zip(o.data.vertices, cos): v.co = c
for o in meshes:
    for m in list(o.modifiers):
        if m.type == 'DATA_TRANSFER' and m.object is None: o.modifiers.remove(m)
with bpy.context.temp_override(active_object=arm, object=arm, selected_objects=sel, selected_editable_objects=sel):
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o.type == 'EMPTY':
        for c in list(o.children):
            mw = c.matrix_world.copy(); c.parent = None; c.matrix_world = mw
        bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.update()
arm.name = 'Armature'
lo, hi = bbox(meshes); rep['height_all_m'] = float(hi[2] - lo[2]); rep['feet_z'] = float(lo[2])
lo_b, hi_b = bbox([body]); rep['body_height_m'] = float(hi_b[2] - lo_b[2])
K = s
def seg(p, a, b):
    ab = b - a; t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared)); return (p - (a + ab * t)).length, t

# ---------- 卡通材質 → 匯出前接回原則化 BSDF ----------
swapped = []
for mat in bpy.data.materials:
    if not mat.use_nodes: continue
    nt = mat.node_tree
    out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL' and n.is_active_output), None) or next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None)
    bs = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if out and bs and out.inputs['Surface'].links and out.inputs['Surface'].links[0].from_node != bs:
        nt.links.new(bs.outputs[0], out.inputs['Surface']); swapped.append(mat.name)
rep['toon_materials_rerouted'] = swapped

# ---------- 碰撞：骨盆每 3 cm 一層凸包（跟 Hips）＋大腿／小腿膠囊 ----------
BV = [body.matrix_world @ v.co for v in body.data.vertices]
z_lo = bw('LeftUpLeg').z - 0.02 * K; z_hi = bw('Spine').z + 0.02 * K
slabs = []; z0 = z_lo
while z0 <= z_hi:
    sl = [p for p in BV if abs(p.z - z0) <= 0.02 * K]
    if len(sl) >= 8:
        cx = sum(p.x for p in sl) / len(sl); cy = sum(p.y for p in sl) / len(sl)
        pts = []
        for p in sl:
            d = Vector((p.x - cx, p.y - cy, 0)); L = d.length
            q = p - d.normalized() * min(0.004 * K, L * 0.5) if L > 1e-6 else p
            pts.append([round(q.x, 4), round(q.y, 4), round(q.z, 4)])
        slabs.append({'z': round(z0, 3), 'bone': P + 'Hips', 'pts_blender': pts})
    z0 += 0.03 * K
gi = {g.name: g.index for g in body.vertex_groups}
def limb_r(group, a, b, pct=90):
    pa, pb_ = bw(a), bw(b); d = []
    for v in body.data.vertices:
        if any(g.group == gi.get(P + group) and g.weight > 0.5 for g in v.groups):
            d.append(seg(body.matrix_world @ v.co, pa, pb_)[0])
    return float(np.percentile(d, pct)) if d else 0.05 * K
caps = []
for side in ('Left', 'Right'):
    caps += [{'name': side + 'UpLeg', 'a': P + side + 'UpLeg', 'b': P + side + 'Leg', 'r': round(limb_r(side + 'UpLeg', side + 'UpLeg', side + 'Leg') + 0.004 * K, 4)},
             {'name': side + 'Leg', 'a': P + side + 'Leg', 'b': P + side + 'Foot', 'r': round(limb_r(side + 'Leg', side + 'Leg', side + 'Foot') + 0.004 * K, 4)}]
json.dump({'slabs': slabs, 'capsules': caps, 'note': 'pts in Blender world (Z up); Godot = (x, z, -y)'},
          open(os.path.join(OUT, NAME + '_colliders.json'), 'w'))
rep['slabs'] = len(slabs); rep['capsules'] = {c['name']: c['r'] for c in caps}

# ---------- 主體 GLB：含 Skirt_* 裙擺骨與袴（袴由彈簧骨鏈驅動，見 reimu_skirt.gd）----------
extra = [b.name for b in arm.data.bones if not b.name.startswith(P)]
rep['bones_exported'] = len(arm.data.bones); rep['skirt_bones'] = len(extra)
chains = {}
for n in extra:
    k, sgm = n.split('_')[1], int(n.split('_')[2])
    b = arm.data.bones[n]
    chains.setdefault(k, {})[sgm] = (list(arm.matrix_world @ b.head_local), list(arm.matrix_world @ b.tail_local))
cage = []
for k in sorted(chains):
    segs = chains[k]; pts = [segs[1][0]] + [segs[i][1] for i in sorted(segs)]
    cage.append({'chain': int(k), 'bones': ['Skirt_%s_%d' % (k, i) for i in sorted(segs)], 'joints_blender': [[round(c, 5) for c in p] for p in pts]})
json.dump({'chains': cage, 'note': 'Blender world (Z up); Godot = (x, z, -y)'}, open(os.path.join(OUT, NAME + '_skirt_chains.json'), 'w'))
body_meshes = list(meshes)
rep['meshes'] = {}
for m in body_meshes:
    m.data.calc_loop_triangles()
    infl = max((len([g for g in v.groups if g.weight > 0]) for v in m.data.vertices), default=0)
    zero = sum(1 for v in m.data.vertices if not any(g.weight > 0 for g in v.groups))
    rep['meshes'][m.name] = {'verts': len(m.data.vertices), 'tris': len(m.data.loop_triangles), 'max_influences': infl, 'zero_weight_verts': zero}
for o in bpy.context.view_layer.objects: o.select_set(False)
arm.select_set(True)
for m in body_meshes: m.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, NAME + '.glb'), export_format='GLB', use_selection=True, export_materials='EXPORT',
                          export_image_format='AUTO', export_animations=False, export_skins=True, export_yup=True,
                          export_apply=False, export_influence_nb=4)
json.dump(rep, open(os.path.join(OUT, NAME + '_export_report.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('REPORT', json.dumps(rep, ensure_ascii=False))
