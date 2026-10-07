"""Analyse back-basket geometry of an NPC GLB (read-only): connected components of the body mesh with
bbox (Blender space: up +Z, character front = -Y), vertex count and the dominant bones of each component.
blender -b -P npc_basket_audit.py -- <npc.glb> [<out.json>]
"""
import bpy, sys, json
import numpy as np
argv = sys.argv[sys.argv.index('--') + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
out = {}
for m in [o for o in bpy.data.objects if o.type == 'MESH']:
    me = m.data
    nv = len(me.vertices)
    co = np.array([(m.matrix_world @ v.co)[:] for v in me.vertices])
    parent = list(range(nv))

    def f(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for e in me.edges:
        a, b = f(e.vertices[0]), f(e.vertices[1])
        if a != b:
            parent[a] = b
    comp = {}
    for i in range(nv):
        comp.setdefault(f(i), []).append(i)
    names = {g.index: g.name for g in m.vertex_groups}
    rows = []
    for root, idx in sorted(comp.items(), key=lambda kv: -len(kv[1])):
        c = co[idx]
        bw = {}
        for i in idx:
            for g in me.vertices[i].groups:
                bw[names[g.group]] = bw.get(names[g.group], 0.0) + g.weight
        top = sorted(bw.items(), key=lambda kv: -kv[1])[:4]
        rows.append({'n': len(idx), 'min': np.round(c.min(0), 3).tolist(), 'max': np.round(c.max(0), 3).tolist(),
                     'bones': [(k.split(':')[-1], round(v / len(idx), 2)) for k, v in top]})
    out[m.name] = {'verts': nv, 'components': len(rows), 'top': rows[:25]}
print('BASKETAUDIT', json.dumps(out))
if len(argv) > 1:
    json.dump(out, open(argv[1], 'w'), indent=1)
