"""慧音 → Godot GLB（NPC 管線用；不含舊袴骨鏈）。來源 blend 只讀不存。
  - 全物件一樣縮放到指定身高（帽頂），套用變換，腳底 z=0、正面 -Y（glTF/Godot +Z）
  - 保留原材質與貼圖；不帶動作（動作由 characters/npc/_shared 的 GeneralSkeleton clip 提供）
  - 權重：每頂點最多 4 影響（已在來源 blend 正規化）
blender -b <慧音權重_v2.blend> -P export_keine_glb.py -- <height_m> <out.glb> <report.json>
"""
import bpy, sys, json, math
import numpy as np
from mathutils import Matrix

argv = sys.argv[sys.argv.index('--') + 1:]
HEIGHT, OUT, REPORT = float(argv[0]), argv[1], argv[2]
SRC = bpy.data.filepath

for o in list(bpy.data.objects):
    if o.type in ('CAMERA', 'LIGHT'):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for pb in arm.pose.bones:
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.rotation_euler = (0, 0, 0); pb.scale = (1, 1, 1)
if arm.animation_data:
    arm.animation_data.action = None
for o in bpy.data.objects:
    o.hide_set(False); o.hide_viewport = False
bpy.context.view_layer.update()


def bbox():
    a = np.array([tuple(m.matrix_world @ v.co) for m in meshes for v in m.data.vertices])
    return a.min(0), a.max(0)


lo, hi = bbox()
rep = {'src': SRC, 'target_height': HEIGHT, 'src_height': float(hi[2] - lo[2]), 'bones': len(arm.data.bones)}
s = HEIGHT / float(hi[2] - lo[2])
rep['scale'] = s
roots = [o for o in bpy.data.objects if o.parent is None]
for r in roots:
    r.matrix_world = Matrix.Scale(s, 4) @ r.matrix_world
bpy.context.view_layer.update()
# 正面：右肩→左肩向量應指 +X（角色面向 -Y）
bw = lambda nm: arm.matrix_world @ arm.data.bones[nm].head_local
lr = bw('mixamorig:LeftArm') - bw('mixamorig:RightArm')
snap = round(math.degrees(math.atan2(lr.y, lr.x)) / 90.0) * 90.0
rep['facing_fix_deg'] = -snap
if snap:
    R = Matrix.Rotation(math.radians(-snap), 4, 'Z')
    for r in roots:
        r.matrix_world = R @ r.matrix_world
bpy.context.view_layer.update()
lo, hi = bbox()
for r in roots:
    r.matrix_world = Matrix.Translation((0, 0, -float(lo[2]))) @ r.matrix_world
bpy.context.view_layer.update()
for o in bpy.context.view_layer.objects:
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
if bpy.context.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
_sel = [o for o in bpy.context.view_layer.objects]
with bpy.context.temp_override(active_object=arm, object=arm, selected_objects=_sel, selected_editable_objects=_sel):
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o.type == 'EMPTY':
        for c in list(o.children):
            mw = c.matrix_world.copy(); c.parent = None; c.matrix_world = mw
        bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.update()
# 節點名＝import 的 retarget 路徑（PATH:Armature/Skeleton3D）與 npc_visual.gd 的 ../Armature
arm.name = 'Armature'
for m in meshes:
    if m.name.endswith('.001'):
        m.name = m.name[:-4]
lo, hi = bbox()
rep['height_m'] = float(hi[2] - lo[2]); rep['feet_z'] = float(lo[2])

# ---- 臉部修正（只動身體顏色貼圖的眼下窄帶＋眼周法線；不動頂點／UV／權重）----
# 1) 貼圖：下眼瞼臉頰側的灰月牙往膚色提亮（keine_face_fix.lift_under_eye；睫毛／眼睛／眉毛不動）
# 2) 法線：Tripo 眼窩深、上眼瞼凸緣，太陽光下照出灰色「黑眼圈」→ 只在兩眼周圍（r_in→r_out 淡出）做法線拓撲平均；
#    鼻子／嘴維持原法線；法線改變 >75° 的頂點保留原值（防薄殼翻面）。
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keine_face_fix import lift_under_eye
FACE_SMOOTH = int(os.environ.get('KEINE_FACE_SMOOTH', '30'))
TEX_LIFT = float(os.environ.get('KEINE_TEX_LIFT', '0.8'))
EYE_RIN, EYE_ROUT = 0.012, 0.030
body = next((m for m in meshes if m.name.startswith('身體')), None)
if body is not None:
    me = body.data
    img = None
    for ms in body.material_slots:
        if ms.material and ms.material.use_nodes:
            for nd in ms.material.node_tree.nodes:
                if nd.type == 'TEX_IMAGE' and nd.outputs['Color'].links and any(l.to_socket.name == 'Base Color' for l in nd.outputs['Color'].links):
                    img = nd.image
    W, H = img.size
    px = np.zeros(W * H * 4, np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(H, W, 4)
    td = np.flipud(px[:, :, :3]).astype(np.float64)
    td2, finfo = lift_under_eye(td, strength=TEX_LIFT) if TEX_LIFT > 0 else (td, {'eyes_px_box': []})
    px[:, :, :3] = np.flipud(td2)
    img.pixels.foreach_set(px.ravel())
    img.pack()
    rep['face_tex_lift'] = {k: finfo[k] for k in finfo}
    # 眼睛 3D 中心：UV 落在偵測到的眼睛框內的頂點的平均位置
    uv = np.zeros(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get('uv', uv)
    uv = uv.reshape(-1, 2)
    lv = np.zeros(len(me.loops), dtype=np.int64)
    me.loops.foreach_get('vertex_index', lv)
    co = np.zeros(len(me.vertices) * 3)
    me.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    eyes = []
    for (bx0, by0, bx1, by1) in finfo['eyes_px_box']:
        u0, u1 = bx0 / W, (bx1 + 1) / W
        v0, v1 = 1 - (by1 + 1) / H, 1 - by0 / H
        sel = (uv[:, 0] >= u0) & (uv[:, 0] <= u1) & (uv[:, 1] >= v0) & (uv[:, 1] <= v1)
        if sel.any():
            eyes.append(co[np.unique(lv[sel])].mean(0))
    rep['eye_centers'] = [list(map(float, e)) for e in eyes]
    if FACE_SMOOTH > 0 and len(eyes) == 2:
        nv = len(me.vertices)
        cn = np.zeros((len(me.loops), 3))
        me.corner_normals.foreach_get('vector', cn.ravel())
        n0 = np.zeros((nv, 3))
        np.add.at(n0, lv, cn)
        n0 /= np.maximum(np.linalg.norm(n0, axis=1, keepdims=True), 1e-9)
        d = np.min([np.linalg.norm(co - e, axis=1) for e in eyes], axis=0)
        t = np.clip((EYE_ROUT - d) / (EYE_ROUT - EYE_RIN), 0, 1)
        t = t * t * (3 - 2 * t)
        region = d < EYE_ROUT + 0.01
        ev = np.zeros(len(me.edges) * 2, dtype=np.int64)
        me.edges.foreach_get('vertices', ev)
        ev = ev.reshape(-1, 2)
        n = n0.copy()
        for _ in range(FACE_SMOOTH):
            acc = n.copy()
            np.add.at(acc, ev[:, 0], n[ev[:, 1]])
            np.add.at(acc, ev[:, 1], n[ev[:, 0]])
            acc /= np.maximum(np.linalg.norm(acc, axis=1, keepdims=True), 1e-9)
            n = np.where(region[:, None], acc, n0)
        nf = n0 * (1 - t[:, None]) + n * t[:, None]
        nf /= np.maximum(np.linalg.norm(nf, axis=1, keepdims=True), 1e-9)
        ang = np.degrees(np.arccos(np.clip((n0 * nf).sum(1), -1, 1)))
        flip = ang > 75
        nf[flip] = n0[flip]
        me.normals_split_custom_set_from_vertices([tuple(x) for x in nf])
        ang2 = np.degrees(np.arccos(np.clip((n0 * nf).sum(1), -1, 1)))
        rep['face_smooth'] = {'iterations': FACE_SMOOTH, 'verts': int((t > 0).sum()), 'kept_flip_verts': int(flip.sum()),
                              'normal_change_deg_p50': float(np.percentile(ang2[t > 0], 50)),
                              'normal_change_deg_max': float(ang2.max())}
rep['meshes'] = {}
for m in meshes:
    m.data.calc_loop_triangles()
    infl = max((len([g for g in v.groups if g.weight > 0]) for v in m.data.vertices), default=0)
    zero = sum(1 for v in m.data.vertices if not any(g.weight > 0 for g in v.groups))
    rep['meshes'][m.name] = {'verts': len(m.data.vertices), 'tris': len(m.data.loop_triangles),
                             'max_influences': infl, 'zero_weight_verts': zero}
rep['total_tris'] = sum(v['tris'] for v in rep['meshes'].values())

for o in bpy.context.view_layer.objects:
    o.select_set(False)
arm.select_set(True)
for m in meshes:
    m.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_materials='EXPORT',
                          export_image_format='AUTO', export_animations=False, export_skins=True, export_yup=True,
                          export_apply=False, export_influence_nb=4)
json.dump(rep, open(REPORT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('REPORT', json.dumps(rep, ensure_ascii=False))
