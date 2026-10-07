"""Profile how far each NPC's geometry sticks out behind the spine line, per 5 cm height slice (read-only).
blender -b -P basket_profile.py -- <npc.glb>
"""
import bpy, sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import basket_fix
argv = sys.argv[sys.argv.index('--') + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
body = max([o for o in bpy.data.objects if o.type == 'MESH'], key=lambda o: len(o.data.vertices))
co = np.array([(body.matrix_world @ v.co)[:] for v in body.data.vertices])
zs, ys = basket_fix.spine_line(arm)
dy = co[:, 1] - np.interp(co[:, 2], zs, ys)
print('PROFILE spine z', np.round(zs, 2).tolist(), 'y', np.round(ys, 3).tolist())
for z in np.arange(0.4, 1.8, 0.05):
    m = (co[:, 2] >= z) & (co[:, 2] < z + 0.05) & (np.abs(co[:, 0]) < 0.35)
    if not m.any():
        continue
    d = dy[m]
    b = m & (dy > 0.08)
    xr = (round(float(co[b, 0].min()), 2), round(float(co[b, 0].max()), 2)) if b.any() else None
    print('PROFILE z %.2f  n %5d  dy_max %.3f  dy_p90 %.3f  n(dy>.08) %4d  x %s' % (z, m.sum(), d.max(), np.percentile(d, 90), b.sum(), xr))
