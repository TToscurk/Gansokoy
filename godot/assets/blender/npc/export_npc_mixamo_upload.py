"""P10 NPC Asset Library：NPC GLB → Mixamo 上傳用 FBX（骨格そのまま・ASCII 名・葉骨なし・albedo 埋め込み・メッシュ 1 つに結合）。
Mixamo は既存骨格（mixamorig／Tripo CC）をそのまま使い、書き出す動作も同じ骨格になる。
blender -b -P export_npc_mixamo_upload.py -- <npc.glb> <albedo> <out.fbx>
"""
import bpy, sys
argv = sys.argv[sys.argv.index('--') + 1:]
GLB, ALB, OUT = argv
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o.name.startswith('Icosphere'):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
arm.name = 'NPC_Armature'
img = bpy.data.images.load(ALB)
mat = bpy.data.materials.new('NPC_Mat')
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes.get('Principled BSDF') or nt.nodes.new('ShaderNodeBsdfPrincipled')
out = nt.nodes.get('Material Output') or nt.nodes.new('ShaderNodeOutputMaterial')
nt.links.new(bsdf.outputs[0], out.inputs[0])
tex = nt.nodes.new('ShaderNodeTexImage')
tex.image = img
nt.links.new(tex.outputs[0], bsdf.inputs['Base Color'])
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in meshes:
    o.data.materials.clear()
    o.data.materials.append(mat)
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = 'NPC_Body'
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
if arm.animation_data:
    arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.rotation_euler = (0, 0, 0); pb.scale = (1, 1, 1)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.fbx(filepath=OUT, use_selection=True, add_leaf_bones=False, path_mode='COPY', embed_textures=True,
                         apply_scale_options='FBX_SCALE_ALL', bake_anim=False, armature_nodetype='NULL')
print('DONE', OUT)
