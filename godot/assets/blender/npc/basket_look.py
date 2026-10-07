"""Textured orthographic views of an NPC GLB with coordinate marker rods (read-only), to locate a carried basket.
Markers: thin vertical rods every 0.1 m in x (at the back plane) and horizontal rods every 0.1 m in z.
blender -b -P basket_look.py -- <npc.glb> <out_prefix>
"""
import bpy, sys, os, glob, math
argv = sys.argv[sys.argv.index('--') + 1:]
GLB, OUT = argv
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o.name.startswith('Icosphere'):
        bpy.data.objects.remove(o, do_unlink=True)
cid = os.path.splitext(os.path.basename(GLB))[0]
tex = [f for f in glob.glob(os.path.join(os.path.dirname(GLB), 'tex', cid + '_albedo.*')) if not f.endswith('.import')][0]
img = bpy.data.images.load(tex)
for o in [o for o in bpy.data.objects if o.type == 'MESH']:
    for sl in o.material_slots:
        nt = sl.material.node_tree
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = img
        bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
        nt.links.new(t.outputs[0], bsdf.inputs['Base Color'])
mat = bpy.data.materials.new('mk'); mat.diffuse_color = (1, 0, 1, 1)
for i in range(-6, 7):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.003, depth=1.8, location=(i * 0.1, 0.45, 0.9))
    bpy.context.object.data.materials.append(mat)
for k in range(4, 17):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.003, depth=1.4, location=(0, 0.45, k * 0.1), rotation=(0, math.radians(90), 0))
    bpy.context.object.data.materials.append(mat)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.003, depth=1.4, location=(0.7 if k % 2 else -0.7, 0, k * 0.1), rotation=(math.radians(90), 0, 0))
    bpy.context.object.data.materials.append(mat)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.color_type = 'TEXTURE'
sc.render.resolution_x, sc.render.resolution_y = 700, 900
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 1.8
for name, yaw in (('back', 0), ('right', -90), ('left', 90)):
    a = math.radians(yaw)
    cam.location = (3.0 * math.sin(a), 3.0 * math.cos(a), 0.9)
    cam.rotation_euler = (math.radians(90), 0, math.radians(180) - a)
    sc.render.filepath = f'{OUT}_{name}.png'
    bpy.ops.render.render(write_still=True)
