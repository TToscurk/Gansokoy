"""shrine_v3_arch.blend 預覽：每個資產一張 Workbench 3/4 視角圖（存 scratch，不進專案）。
  blender -b godot/assets/shrine_v3/src/shrine_v3_arch.blend --python godot/assets/shrine_v3/src/preview_arch.py -- <out_dir> [name,...]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
OUT = argv[0] if argv else os.path.join(os.environ.get('LOCALAPPDATA', '.'), 'hermes', 'cache', 'scratch', 'shrine_v3', 'arch_prev')
ONLY = argv[1].split(',') if len(argv) > 1 else None
os.makedirs(OUT, exist_ok=True)

sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = True
sc.display.shading.cavity_type = 'BOTH'
sc.display.shading.show_shadows = True
sc.render.resolution_x = 900
sc.render.resolution_y = 700
sc.render.film_transparent = False
cam_d = bpy.data.cameras.new('cam')
cam = bpy.data.objects.new('cam', cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
objs = [o for o in sc.objects if o.type == 'MESH']
for o in objs:
    o.hide_render = True
views = [('fl', 35.0, 18.0), ('br', 215.0, 22.0), ('low', 20.0, 4.0)]
for o in objs:
    if ONLY and o.name not in ONLY:
        continue
    o.hide_render = False
    bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    c = (lo + hi) / 2
    r = (hi - lo).length / 2
    for tag, az, el in views:
        a = math.radians(az)
        e = math.radians(el)
        # Godot 正面 +z ＝ Blender −y：從前方（−y）偏左看
        d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
        cam.location = c + d * r * 2.6
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        cam_d.lens = 50
        sc.render.filepath = os.path.join(OUT, '%s_%s.png' % (o.name, tag))
        bpy.ops.render.render(write_still=True)
    o.hide_render = True
    print('[PREV]', o.name, 'size', tuple(round(v, 2) for v in (hi - lo)))
