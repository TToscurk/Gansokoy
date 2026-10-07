"""NPC batch：Tripo rig の骨格監査（読むだけ）。各 FBX の骨名・親・rest（頭・尾・roll、高さ正規化）・メッシュ・材質・画像を JSON へ。
blender -b -P npc_skeleton_audit.py -- <out.json> <id>=<fbx> ...
"""
import bpy, sys, json, math
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:]
OUT, PAIRS = argv[0], [a.split('=', 1) for a in argv[1:]]
res = {}
for cid, f in PAIRS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if f.lower().endswith('.glb'):
        bpy.ops.import_scene.gltf(filepath=f)
    else:
        bpy.ops.import_scene.fbx(filepath=f)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    zs = [(m.matrix_world @ Vector(c)).z for m in meshes for c in m.bound_box]
    h = max(zs) - min(zs)
    bones = {}
    for b in arm.data.bones:
        hd = arm.matrix_world @ b.head_local
        tl = arm.matrix_world @ b.tail_local
        m = (arm.matrix_world.to_3x3() @ b.matrix_local.to_3x3()).normalized()
        bones[b.name] = {'parent': b.parent.name if b.parent else None,
                         'head': [round(x / h, 4) for x in hd], 'tail': [round(x / h, 4) for x in tl],
                         'y_axis': [round(x, 3) for x in m.col[1]], 'z_axis': [round(x, 3) for x in m.col[2]]}
    ms = []
    for o in meshes:
        groups = set(g.name for g in o.vertex_groups)
        ms.append({'name': o.name, 'tris': sum(len(p.vertices) - 2 for p in o.data.polygons),
                   'materials': [s.material.name if s.material else None for s in o.material_slots],
                   'uv_layers': len(o.data.uv_layers), 'vgroups': len(groups),
                   'unweighted_bones_in_groups': sorted(set(bones) - groups)[:80],
                   'z': [round(min((o.matrix_world @ Vector(c)).z for c in o.bound_box), 4), round(max((o.matrix_world @ Vector(c)).z for c in o.bound_box), 4)]})
    imgs = [(i.name, i.filepath, list(i.size)) for i in bpy.data.images]
    res[cid] = {'file': f, 'height': round(h, 4), 'armature': arm.name, 'arm_scale': [round(x, 4) for x in arm.scale],
                'arm_rot': [round(math.degrees(x), 2) for x in arm.rotation_euler], 'n_bones': len(bones), 'bones': bones,
                'meshes': ms, 'images': imgs}
    print('AUD', cid, len(bones), len(ms), round(h, 3))
json.dump(res, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
