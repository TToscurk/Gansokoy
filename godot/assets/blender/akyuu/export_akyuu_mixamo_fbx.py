"""阿求 → Mixamo 上傳用 FBX（65 骨 mixamorig，不含袖子彈簧骨）。來源 blend 只讀不存。
  - 全物件等比縮放到指定身高、正面 -Y、腳底 z=0、套用變換
  - 物件／材質／貼圖名改 ASCII；貼圖縮到 1024 內嵌（Mixamo 大貼圖會 veroldamo 逾時）
blender -b <阿求_rig_4K.blend> -P export_akyuu_mixamo_fbx.py -- <height_m> <out.fbx>
"""
import bpy, sys, math, json
import numpy as np
from mathutils import Matrix
argv = sys.argv[sys.argv.index('--') + 1:]
HEIGHT, OUT = float(argv[0]), argv[1]
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
lo, hi = bbox(); s = HEIGHT / float(hi[2] - lo[2])
roots = [o for o in bpy.data.objects if o.parent is None]
for r in roots: r.matrix_world = Matrix.Scale(s, 4) @ r.matrix_world
bpy.context.view_layer.update()
bw = lambda nm: arm.matrix_world @ arm.data.bones[nm].head_local
lr = bw('mixamorig:LeftArm') - bw('mixamorig:RightArm')
snap = round(math.degrees(math.atan2(lr.y, lr.x)) / 90.0) * 90.0
if snap:
    for r in roots: r.matrix_world = Matrix.Rotation(math.radians(-snap), 4, 'Z') @ r.matrix_world
bpy.context.view_layer.update()
lo, hi = bbox()
for r in roots: r.matrix_world = Matrix.Translation((0, 0, -float(lo[2]))) @ r.matrix_world
bpy.context.view_layer.update()
sel = list(bpy.context.view_layer.objects)
for o in sel: o.select_set(True)
bpy.context.view_layer.objects.active = arm
with bpy.context.temp_override(active_object=arm, object=arm, selected_objects=sel, selected_editable_objects=sel):
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o.type == 'EMPTY':
        for c in list(o.children):
            mw = c.matrix_world.copy(); c.parent = None; c.matrix_world = mw
        bpy.data.objects.remove(o, do_unlink=True)
names = {'身體': 'Body', '衣身': 'Kimono', '右袖': 'SleeveR', '左袖': 'SleeveL', '頭髮': 'Hair', '鞋子右': 'ShoeR', '鞋子左': 'ShoeL'}
# Mixamo 只收 65 骨 mixamorig：袖子彈簧骨 Sleeve_* 的權重併回其根的父骨（前臂），再刪骨
extra = [b.name for b in arm.data.bones if not b.name.startswith('mixamorig:')]
if extra:
    tgt = {}
    for n in extra:
        b = arm.data.bones[n]
        while not b.name.startswith('mixamorig:'):
            b = b.parent
        tgt[n] = b.name
    for m in meshes:
        gi = {g.index: g.name for g in m.vertex_groups}
        for v in m.data.vertices:
            add = {}
            for g in v.groups:
                if gi[g.group] in tgt:
                    add[tgt[gi[g.group]]] = add.get(tgt[gi[g.group]], 0.0) + g.weight
            for k, w in add.items():
                grp = m.vertex_groups.get(k) or m.vertex_groups.new(name=k)
                old = next((g.weight for g in v.groups if gi.get(g.group) == k), 0.0)
                grp.add([v.index], old + w, 'REPLACE')
        for n in extra:
            if m.vertex_groups.get(n):
                m.vertex_groups.remove(m.vertex_groups[n])
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    for n in extra:
        arm.data.edit_bones.remove(arm.data.edit_bones[n])
    bpy.ops.object.mode_set(mode='OBJECT')
for m in meshes:
    m.name = names.get(m.name, 'Mesh_%d' % meshes.index(m))
arm.name = 'Armature'
for i, mat in enumerate(bpy.data.materials):
    mat.name = 'M_%d' % i
import os, tempfile
TMP = os.path.join(os.environ.get('TMPDIR') or tempfile.gettempdir(), 'akyuu_mixamo_tex'); os.makedirs(TMP, exist_ok=True)
used = {n.image for m in bpy.data.materials if m.use_nodes for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image}
for i, im in enumerate(sorted(used, key=lambda x: x.name)):
    if im.size[0] > 1024:
        im.scale(1024, 1024)
    im.filepath_raw = os.path.join(TMP, 'T_%d.png' % i); im.file_format = 'PNG'; im.save()
    im.name = 'T_%d.png' % i
lo, hi = bbox()
for o in bpy.context.view_layer.objects: o.select_set(o.type in ('MESH', 'ARMATURE'))
bpy.ops.export_scene.fbx(filepath=OUT, use_selection=True, add_leaf_bones=False, bake_anim=False,
                         path_mode='COPY', embed_textures=True, apply_scale_options='FBX_SCALE_ALL',
                         armature_nodetype='NULL', use_armature_deform_only=True)
print('REPORT', json.dumps({'height': float(hi[2] - lo[2]), 'feet': float(lo[2]), 'scale': s, 'facing_fix': -snap,
      'bones': len(arm.data.bones), 'meshes': [m.name for m in meshes]}))
