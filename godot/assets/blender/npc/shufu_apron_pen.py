"""主婦 前掛け：脚（股引）の前掛け貫通を幾何で測る（読むだけ）。任意で前掛けの重み修正をメモリ上で試す。
blender -b -P shufu_apron_pen.py -- <npc.glb> <anim.glb> <action> <out.json> [fix.json]
貫通＝股引の頂点から +Y（後ろ）へ光線を飛ばし、正面側の前掛け面（本体最大成分・y<-0.06・0.3<z<0.95）に当たる＝前掛けより前に出ている。深さ＝当たるまでの距離。
"""
import bpy, bmesh, sys, json, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
argv = sys.argv[sys.argv.index('--') + 1:]
NPC, ANIM, ACT, OUT = argv[:4]
FIX = json.load(open(argv[4])) if len(argv) > 4 else None
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=ANIM)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=NPC)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
body = bpy.data.objects['NPC_Body']
bm = bmesh.new(); bm.from_mesh(body.data); bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5); bm.to_mesh(body.data); bm.free()
me = body.data
sys.path.insert(0, __import__('os').path.dirname(__file__))
import apron_fix
reg = apron_fix.regions(body)
if FIX:
    rep = apron_fix.apply(body, reg, FIX)
    print('FIX', json.dumps(rep))
act = bpy.data.actions[ACT]
arm.animation_data_create(); arm.animation_data.action = act
try:
    arm.animation_data.action_slot = act.slots[0]
except Exception:
    pass
f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
dep = bpy.context.evaluated_depsgraph_get()
apron_faces = reg['apron_faces']
trouser = reg['trouser_verts']
res = {'action': ACT, 'frames': []}
for f in range(f0, f1 + 1):
    bpy.context.scene.frame_set(f)
    dep.update()
    ev = body.evaluated_get(dep)
    m2 = ev.to_mesh()
    mw = body.matrix_world
    verts = [mw @ v.co for v in m2.vertices]
    polys = [list(m2.polygons[i].vertices) for i in apron_faces]
    tree = BVHTree.FromPolygons(verts, polys)
    depths = []
    pts = []
    for i in trouser:
        p = verts[i]
        if p.y > 0.0:
            continue
        hit = tree.ray_cast(p, Vector((0, 1, 0)), 0.3)
        if hit[0] is not None:
            depths.append(hit[3])
            pts.append((int(i), round(p.x, 3), round(p.z, 3), round(hit[3], 3)))
    # 前掛けの形：中央下端の頂点の左右振れ（V 字・抽動の指標）
    hem = [verts[i] for i in reg['apron_hem_center']]
    ev.to_mesh_clear()
    res['frames'].append({'f': f, 'n_pen': len(depths), 'max_depth': round(max(depths), 4) if depths else 0.0,
                          'hem_center_x': round(sum(h.x for h in hem) / max(1, len(hem)), 4), 'hem_center_y': round(sum(h.y for h in hem) / max(1, len(hem)), 4), 'pts': pts})
fr = res['frames']
res['summary'] = {'frames': len(fr), 'frames_with_pen': sum(1 for x in fr if x['n_pen'] > 0), 'max_depth': max(x['max_depth'] for x in fr),
                  'worst': sorted(fr, key=lambda x: -x['max_depth'])[:3], 'hem_x_range': [min(x['hem_center_x'] for x in fr), max(x['hem_center_x'] for x in fr)]}
print('PEN', json.dumps(res['summary']))
print('PENF', ' '.join('%d:%d/%.3f' % (x['f'], x['n_pen'], x['max_depth']) for x in fr))
json.dump(res, open(OUT, 'w'), indent=1)
# 貫通した股引頂点の重み（診断）と、その位置の前掛け面の重み
gname = {g.index: g.name.split(':')[-1].replace('mixamorig_', '') for g in body.vertex_groups}
seen = sorted(set(pp[0] for x in fr for pp in x['pts']))
co0 = reg['co']
for i in seen:
    w = sorted(((gname[g.group], round(g.weight, 2)) for g in me.vertices[i].groups if g.weight > 0.02), key=lambda t: -t[1])
    # 最寄りの前掛け頂点
    av = reg['apron_verts']
    j = min(av, key=lambda a: (co0[a][0] - co0[i][0]) ** 2 + (co0[a][2] - co0[i][2]) ** 2)
    wa = sorted(((gname[g.group], round(g.weight, 2)) for g in me.vertices[j].groups if g.weight > 0.02), key=lambda t: -t[1])
    print('TRV', i, 'rest', [round(float(c), 3) for c in co0[i]], w, '| apron', j, [round(float(c), 3) for c in co0[j]], wa)
