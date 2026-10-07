"""Preview the basket_fix selection on a built NPC GLB (read-only): colour the rigid factor t (red = 100 % rigid,
yellow = blend band, grey = untouched skin) and render back / left / right / back-3/4 views with Workbench.
blender -b -P basket_preview.py -- <npc.glb> '<params json>' <out_prefix>
"""
import bpy, sys, json, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import basket_fix
argv = sys.argv[sys.argv.index('--') + 1:]
GLB, P, OUT = argv[0], json.loads(argv[1]), argv[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o.name.startswith('Icosphere'):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
bodies = [o for o in bpy.data.objects if o.type == 'MESH']
body = max(bodies, key=lambda o: len(o.data.vertices))
t, dom = basket_fix.rigid_t(body, arm, P)
ca = body.data.color_attributes.new('sel', 'FLOAT_COLOR', 'POINT')
for i, v in enumerate(t):
    ca.data[i].color = (1, 0.1, 0.1, 1) if v >= 0.999 else ((1, 0.85, 0.1, 1) if v > 1e-4 else (0.55, 0.55, 0.55, 1))
for o in bodies:
    if o is not body:
        o.hide_render = True
print('BASKETSEL rigid', int((t >= 0.999).sum()), 'blend', int(((t > 1e-4) & (t < 0.999)).sum()), 'of', len(t))
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.color_type = 'VERTEX'
sc.display.shading.light = 'STUDIO'
sc.render.resolution_x, sc.render.resolution_y = 600, 800
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 2.0
for name, yaw in (('back', 0), ('left', 90), ('right', -90), ('back34', 35)):
    a = math.radians(yaw)
    cam.location = (3.0 * math.sin(a), 3.0 * math.cos(a), 0.85)   # +Y = behind the character (front is -Y)
    cam.rotation_euler = (math.radians(90), 0, math.radians(180) - a)
    sc.render.filepath = f'{OUT}_{name}.png'
    bpy.ops.render.render(write_still=True)
