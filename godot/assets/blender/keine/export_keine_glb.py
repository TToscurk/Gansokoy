"""慧音（含袴骨鏈 Hakama_*）→ Godot GLB。來源 blend 只讀不存。
  - 全物件一樣縮放到指定身高（帽頂），套用變換（骨、頂點、裙袴的非一樣物件縮放都烘進資料），腳底 z=0、正面 -Y（glTF/Godot +Z）
  - 保留原材質與貼圖；不帶動作（坐姿垂放 Action 只在 Blender 用；遊戲裡由 SpringBoneSimulator3D 取代）
  - 另輸出 keine_springs.json：24 根袴骨鏈＋身體碰撞半徑（由身體網格實測）＋驗證用的靜止資料
blender -b <慧音權重.blend> -P export_keine_glb.py -- <height_m> <out.glb> <springs.json>
"""
import bpy, sys, json, math
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index('--') + 1:]
HEIGHT, OUT, SPRINGS = float(argv[0]), argv[1], argv[2]
SRC = bpy.data.filepath

for o in list(bpy.data.objects):
    if o.type in ('CAMERA', 'LIGHT'):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
# 休息姿勢＋清掉動作（坐姿垂放 Action 留在來源檔，不匯出）
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
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o.type == 'EMPTY':
        for c in list(o.children):
            mw = c.matrix_world.copy(); c.parent = None; c.matrix_world = mw
        bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.update()
lo, hi = bbox()
rep['height_m'] = float(hi[2] - lo[2]); rep['feet_z'] = float(lo[2])
rep['arm_obj'] = {'loc': list(arm.location), 'rot': list(arm.rotation_euler), 'scale': list(arm.scale)}
rep['meshes'] = {}
for m in meshes:
    a = np.array([tuple(m.matrix_world @ v.co) for v in m.data.vertices])
    m.data.calc_loop_triangles()
    rep['meshes'][m.name] = {'verts': len(m.data.vertices), 'tris': len(m.data.loop_triangles),
                             'min': a.min(0).tolist(), 'max': a.max(0).tolist(), 'obj_scale': list(m.scale)}
rep['total_tris'] = sum(v['tris'] for v in rep['meshes'].values())


# ---- 袴骨鏈 ----
def gl(v):   # Blender Z-up → glTF/Godot Y-up（x, z, -y）
    return [v[0], v[2], -v[1]]


B = arm.data.bones
# 坐姿垂放（Hakama_SitDrape_90，作者在 Blender 對「大腿前抬 90°、小腿彎 90°」手調的 24 根袴骨旋轉）。
# 只取旋轉 delta（骨本地、相對靜止）；骨本地軸在 glTF 匯出後不變（Godot 端以 rest_basis 驗證）。
drape = {}
act = bpy.data.actions.get('Hakama_SitDrape_90')
if act:
    fr = act.frame_range[0]
    curves = list(act.fcurves) if hasattr(act, 'fcurves') else [fc for l in act.layers for s in l.strips for cb in s.channelbags for fc in cb.fcurves]
    for fc in curves:
        if 'rotation_quaternion' not in fc.data_path:
            continue
        bn = fc.data_path.split('"')[1]
        drape.setdefault(bn, [1.0, 0.0, 0.0, 0.0])[fc.array_index] = fc.evaluate(fr)
rep['sit_drape_bones'] = len(drape)
rep['rotation_modes'] = sorted({pb.rotation_mode for pb in arm.pose.bones if pb.name.startswith('Hakama')})


def basis_gl(b):   # 骨在骨架空間的旋轉（Blender Z-up）→ Godot Y-up：C·R，C=(x,z,-y)
    R = (arm.matrix_world @ b.matrix_local).to_3x3().normalized()
    C = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))
    M = C @ R
    return [list(M.col[0]), list(M.col[1]), list(M.col[2])]


chains = []
for d in ['F', 'FL', 'L', 'BL', 'B', 'BR', 'R', 'FR']:
    names = ['Hakama_%s_%d' % (d, i) for i in (1, 2, 3)]
    bs = [B[n] for n in names]
    chains.append({'dir': d, 'bones': names, 'parent': bs[0].parent.name,
                   'connected': [b.use_connect for b in bs[1:]],
                   'heads': [gl(arm.matrix_world @ b.head_local) for b in bs],
                   'tail': gl(arm.matrix_world @ bs[2].tail_local),
                   'lengths': [b.length for b in bs],
                   'rest_basis': [basis_gl(b) for b in bs],
                   'sit_drape_wxyz': [drape.get(n, [1.0, 0.0, 0.0, 0.0]) for n in names]})

# ---- 身體碰撞半徑：身體網格中主要權重屬於該骨的頂點，到骨段（head→子骨 head）的距離取 85 百分位 ----
body = bpy.data.objects['身體']
idx = {g.index: g.name for g in body.vertex_groups}
COL = [('Hips', 'mixamorig:Hips', 'mixamorig:Spine'),
       ('Spine', 'mixamorig:Spine', 'mixamorig:Spine1'),
       ('LeftUpLeg', 'mixamorig:LeftUpLeg', 'mixamorig:LeftLeg'),
       ('LeftLeg', 'mixamorig:LeftLeg', 'mixamorig:LeftFoot'),
       ('RightUpLeg', 'mixamorig:RightUpLeg', 'mixamorig:RightLeg'),
       ('RightLeg', 'mixamorig:RightLeg', 'mixamorig:RightFoot')]
P = np.array([tuple(body.matrix_world @ v.co) for v in body.data.vertices])
dom = []
for v in body.data.vertices:
    g = max(v.groups, key=lambda g: g.weight) if v.groups else None
    dom.append(idx[g.group] if g and g.weight > 0.5 else '')
dom = np.array(dom)
colliders = []
for nm, b0, b1 in COL:
    h = np.array(arm.matrix_world @ B[b0].head_local); t = np.array(arm.matrix_world @ B[b1].head_local)
    sel = P[dom == b0]
    ax = t - h; L = float(np.linalg.norm(ax)); u = ax / L
    tt = np.clip((sel - h) @ u, 0, L)
    r = np.linalg.norm(sel - (h + np.outer(tt, u)), axis=1)
    colliders.append({'name': nm, 'bone': b0, 'child': b1, 'n_verts': int(len(sel)),
                      'radius_p50': float(np.percentile(r, 50)), 'radius_p85': float(np.percentile(r, 85)),
                      'head': gl(h.tolist()), 'child_head': gl(t.tolist()), 'length': L})
json.dump({'_doc': '慧音袴骨鏈與身體碰撞（export_keine_glb.py 產生；公尺、Godot Y-up；身高 %.2f m 帽頂）' % HEIGHT,
           'chains': chains, 'colliders': colliders, 'report': rep},
          open(SPRINGS, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
for m in meshes:
    m.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_materials='EXPORT',
                          export_image_format='AUTO', export_animations=False, export_skins=True, export_yup=True,
                          export_apply=False, export_influence_nb=4)
print('REPORT', json.dumps(rep, ensure_ascii=False))
