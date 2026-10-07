"""P10 R3a NPC Prototype — 普通町人（男）chonin_m01：使用者の Tripo モデルを量産可能な構成へ組み直す。
入力＝使用者の blend（Tripo：単一メッシュ 10,220 三角、78 骨の CC 系 rig〔指・twist 骨つき〕、高さ 1.0 m、4k テクスチャ 4 枚）。
元ファイルは読むだけ（このスクリプトは保存しない）。

  - 高さ 1.68 m へ一様スケール（骨と頂点に適用）
  - 部位メッシュ 5（同じ骨格・同じ重み・継ぎ目は同一頂点位置）：
      Head（顔・耳・首＋髪の下の短い地毛 scalp）／Hair／Upper（上衣・腕・手・手拭い）／Lower（帯・前掛け・巾着・股引・脛）／Feet（足・草鞋）
  - 材質スロット 3（M_Skin／M_Cloth／M_Hair、同じ atlas を共有；名前だけ運び Godot で外部 .tres に差し替え）
  - 動作は持たない（Godot で SkeletonProfileHumanoid に retarget した idle／walk を載せる）

blender -b <user.blend> -P build_npc_chonin_m01.py -- <base_color.jpg> <out.glb> <report.json> [preview_prefix]
"""
import bpy
import bmesh
import sys
import json
import math
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
TEX, OUT, REPORT = argv[0], argv[1], argv[2]
PREV = argv[3] if len(argv) > 3 else ''
HEIGHT = 1.68

for o in list(bpy.data.objects):
    if o.type in ('CAMERA', 'LIGHT'):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
body = next(o for o in bpy.data.objects if o.type == 'MESH')
arm.name = 'Armature'
arm.hide_set(False)          # 使用者 blend では Armature が非表示（H）——選択・適用・書き出しのため表示に戻す
arm.hide_viewport = False
body.hide_set(False)
rep = {'source': {'tris': 0, 'bones': len(arm.data.bones)}, 'parts': {}}

# ---------- 1.68 m へ ----------
zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
s = HEIGHT / (max(zs) - min(zs))
rep['source']['height_m'] = round(max(zs) - min(zs), 4)
rep['scale'] = round(s, 5)
arm.scale = arm.scale * s
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
rep['height_m'] = round(max(zs) - min(zs), 4)
rep['feet_z'] = round(min(zs), 4)

# BoneRoot を床へ：Tripo の BoneRoot は腰の高さ（0.948 m）にあり、Godot の retarget（SkeletonProfileHumanoid の Root は床）では
# Hips の位置トラックが Root の上に二重に乗って 0.95 m 浮く。BoneRoot には重みが無い（頂点グループ無し）ので head／tail だけ動かす。
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones['BoneRoot']
rep['bone_root_z_before'] = round(eb.head.z, 4)
eb.use_connect = False
eb.head = (eb.head.x, eb.head.y, 0.0)
eb.tail = (eb.head.x, eb.head.y + 0.0, 0.15)
for c in eb.children:
    c.use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')
rep['bone_root_moved_to_floor'] = 'BoneRoot' not in [g.name for g in body.vertex_groups]

me = body.data
img = bpy.data.images.load(TEX)
img.scale(1024, 1024)
px = np.array(img.pixels[:], dtype=np.float32).reshape(1024, 1024, 4)[:, :, :3]


def sample(uv):
    return px[min(1023, max(0, int(uv.y % 1.0 * 1024))), min(1023, max(0, int(uv.x % 1.0 * 1024)))]


def hsv(c):
    r, g, b = float(c[0]), float(c[1]), float(c[2])
    mx_, mn_ = max(r, g, b), min(r, g, b)
    sat = 0.0 if mx_ <= 1e-6 else (mx_ - mn_) / mx_
    if mx_ - mn_ < 1e-6:
        h = 0.0
    elif mx_ == r:
        h = ((g - b) / (mx_ - mn_)) % 6
    elif mx_ == g:
        h = (b - r) / (mx_ - mn_) + 2
    else:
        h = (r - g) / (mx_ - mn_) + 4
    return h * 60.0, sat, mx_


gidx = {g.index: g.name for g in body.vertex_groups}
vdom = []
for v in me.vertices:
    best, bw_ = None, -1.0
    for ge in v.groups:
        if ge.weight > bw_:
            best, bw_ = gidx.get(ge.group), ge.weight
    vdom.append(best)

bm = bmesh.new()
bm.from_mesh(me)
bm.faces.ensure_lookup_table()
uvl = bm.loops.layers.uv.active
rep['source']['tris'] = sum(len(f.verts) - 2 for f in bm.faces)

bz = {b.name: arm.matrix_world @ b.head_local for b in arm.data.bones}
FOOT_B = {'L_Foot', 'L_ToeBase', 'R_Foot', 'R_ToeBase'}
ARM_B = {g for g in gidx.values() if g[:2] in ('L_', 'R_') and any(k in g for k in ('Clavicle', 'Upperarm', 'Forearm', 'Hand', 'Pinky', 'Ring', 'Mid', 'Index', 'Thumb'))}
z_head = bz['Head'].z
z_neck_cut = bz['Spine02'].z + 0.75 * (z_head - bz['Spine02'].z)
z_waist = bz['Waist'].z + 0.4 * (bz['Spine01'].z - bz['Waist'].z)
z_ankle = (bz['L_Foot'].z + bz['R_Foot'].z) / 2
rep['seams'] = {'neck_z': round(z_neck_cut, 3), 'waist_z': round(z_waist, 3), 'ankle_z': round(z_ankle + 0.02, 3)}

fdata = []
for f in bm.faces:
    c = body.matrix_world @ f.calc_center_median()
    doms = [vdom[v.index] for v in f.verts]
    dom = max(set(doms), key=doms.count)
    uvc = sum((l[uvl].uv for l in f.loops), Vector((0, 0))) / len(f.loops)
    fdata.append((c, dom, sample(uvc)))


def _pk(co):
    return (round(co.x, 5), round(co.y, 5), round(co.z, 5))


edge_faces = {}
for f in bm.faces:
    ks = [_pk(v.co) for v in f.verts]
    for a_, b_ in zip(ks, ks[1:] + ks[:1]):
        edge_faces.setdefault((a_, b_) if a_ < b_ else (b_, a_), []).append(f.index)
nbrs = [set() for _ in bm.faces]
for fl in edge_faces.values():
    for i in fl:
        for j in fl:
            if i != j:
                nbrs[i].add(j)

part = [''] * len(bm.faces)
for i, (c, dom, col) in enumerate(fdata):
    r_neck = math.hypot(c.x - bz['Head'].x, c.y - bz['Head'].y)
    # 顎・口は首軸より前へ出る（r が大きい）ので、首の切れ目より 2.5 cm 上は半径を問わず頭；それ以下は首の円柱内だけ
    chin = c.z > z_neck_cut - 0.01 and c.y < bz['Head'].y - 0.045   # 顎の下面（正面へ張り出す）
    if dom == 'Head' and (c.z >= z_neck_cut + 0.025 or chin or (c.z > z_neck_cut and r_neck < 0.075)):
        part[i] = 'Head'
    elif dom in FOOT_B or c.z < z_ankle + 0.02:
        part[i] = 'Feet'
    elif dom not in ARM_B and c.z < z_waist:
        part[i] = 'Lower'
    else:
        part[i] = 'Upper'

# 髪：頭部の暗色面の大きな連結成分（目・眉は小島として顔に残る）
head_ids = [i for i in range(len(part)) if part[i] == 'Head']
vals = sorted(hsv(fdata[i][2])[2] for i in head_ids)
dark = set(i for i in head_ids if hsv(fdata[i][2])[2] < 0.42)
seen, comps = set(), []
for i in dark:
    if i in seen:
        continue
    stack, comp = [i], []
    seen.add(i)
    while stack:
        k = stack.pop()
        comp.append(k)
        for j in nbrs[k]:
            if j in dark and j not in seen:
                seen.add(j)
                stack.append(j)
    comps.append(comp)
comps.sort(key=len, reverse=True)
hair = set()
for comp in comps:
    if len(comp) >= 0.03 * max(1, len(head_ids)):
        hair.update(comp)
for i in head_ids:
    if i not in hair and nbrs[i] and all(j in hair for j in nbrs[i]):
        hair.add(i)
# 明るいアホ毛・細い房：頭部の「髪でない面」を連結成分に分け、最大（顔・耳・首）以外で首より上の島は髪
rest_ids = set(i for i in head_ids if i not in hair)
seen2, rcomps = set(), []
for i in rest_ids:
    if i in seen2:
        continue
    stack, comp = [i], []
    seen2.add(i)
    while stack:
        k = stack.pop()
        comp.append(k)
        for j in nbrs[k]:
            if j in rest_ids and j not in seen2:
                seen2.add(j)
                stack.append(j)
    rcomps.append(comp)
rcomps.sort(key=len, reverse=True)
strands = 0
for comp in rcomps[1:]:
    cz = sum(fdata[k][0].z for k in comp) / len(comp)
    if cz > z_neck_cut + 0.08:
        hair.update(comp)
        strands += len(comp)
rep['strand_faces_to_hair'] = strands
for i in hair:
    part[i] = 'Hair'
rep['hair_components'] = [len(c) for c in comps[:6]]
rep['head_value_quartiles'] = [round(vals[int(len(vals) * q)], 3) for q in (0.1, 0.25, 0.5, 0.75, 0.9)] if vals else None


def is_skin(col):
    h, sat, v = hsv(col)
    return (h < 40 or h > 345) and 0.12 < sat < 0.62 and v > 0.45


mat_of = []
for i, (c, dom, col) in enumerate(fdata):
    mat_of.append(2 if part[i] == 'Hair' else 0 if part[i] == 'Head' or is_skin(col) else 1)
for _ in range(2):
    new = list(mat_of)
    for i in range(len(mat_of)):
        if mat_of[i] == 2 or part[i] == 'Head':
            continue
        cnt = {}
        for j in nbrs[i]:
            cnt[mat_of[j]] = cnt.get(mat_of[j], 0) + 1
        if cnt:
            m, k = max(cnt.items(), key=lambda t: t[1])
            if k >= 3 and m != 2:
                new[i] = m
    mat_of = new

mats = []
for nm, col in (('M_Skin', (0.85, 0.66, 0.55, 1)), ('M_Cloth', (0.25, 0.3, 0.45, 1)), ('M_Hair', (0.12, 0.08, 0.06, 1))):
    m = bpy.data.materials.new(nm)
    m.diffuse_color = col
    mats.append(m)
me.materials.clear()
for m in mats:
    me.materials.append(m)
for f in bm.faces:
    f.material_index = mat_of[f.index]
bm.to_mesh(me)
bm.free()

PARTS = ['Head', 'Hair', 'Upper', 'Lower', 'Feet']
objs = {}
for p in PARTS:
    dup = body.copy()
    dup.data = body.data.copy()
    dup.name = dup.data.name = 'NPC_' + p
    bpy.context.scene.collection.objects.link(dup)
    b2 = bmesh.new()
    b2.from_mesh(dup.data)
    b2.faces.ensure_lookup_table()
    bmesh.ops.delete(b2, geom=[f for f in b2.faces if part[f.index] != p], context='FACES')
    b2.to_mesh(dup.data)
    b2.free()
    objs[p] = dup

# scalp：髪を複製→強く平滑化→頭の中心へ 6 mm→15 % に間引き→Head に結合（髪を外しても頭が開かない短い地毛）
hair_o = objs['Hair']
if len(hair_o.data.polygons):
    b3 = bmesh.new()
    b3.from_mesh(hair_o.data)
    for _ in range(25):
        bmesh.ops.smooth_vert(b3, verts=b3.verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    hc = sum((v.co for v in b3.verts), Vector()) / max(1, len(b3.verts))
    for v in b3.verts:
        d = v.co - hc
        if d.length > 1e-6:
            v.co -= d.normalized() * 0.006
    scalp_me = bpy.data.meshes.new('scalp')
    b3.to_mesh(scalp_me)
    b3.free()
    for m in hair_o.data.materials:
        scalp_me.materials.append(m)
    scalp = hair_o.copy()
    scalp.data = scalp_me
    bpy.context.scene.collection.objects.link(scalp)
    bpy.ops.object.select_all(action='DESELECT')
    scalp.select_set(True)
    bpy.context.view_layer.objects.active = scalp
    dm = scalp.modifiers.new('dec', 'DECIMATE')
    dm.ratio = 0.3
    scalp.modifiers.move(scalp.modifiers.find('dec'), 0)
    bpy.ops.object.modifier_apply(modifier='dec')
    bpy.ops.object.select_all(action='DESELECT')
    objs['Head'].select_set(True)
    scalp.select_set(True)
    bpy.context.view_layer.objects.active = objs['Head']
    bpy.ops.object.join()
bpy.data.objects.remove(body, do_unlink=True)

for p, o in objs.items():
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.material_slot_remove_unused()
    o.data.calc_loop_triangles()
    mi = {}
    for t in o.data.loop_triangles:
        n = o.data.materials[t.material_index].name
        mi[n] = mi.get(n, 0) + 1
    zz = [(o.matrix_world @ v.co).z for v in o.data.vertices]
    rep['parts'][p] = {'tris': len(o.data.loop_triangles), 'verts': len(o.data.vertices), 'materials': mi,
                       'z': [round(min(zz), 3), round(max(zz), 3)] if zz else None}
rep['total_tris'] = sum(v['tris'] for v in rep['parts'].values())
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)

if PREV:
    pal = {'Head': (0.95, 0.75, 0.6, 1), 'Hair': (0.15, 0.1, 0.08, 1), 'Upper': (0.2, 0.35, 0.8, 1), 'Lower': (0.75, 0.55, 0.25, 1), 'Feet': (0.3, 0.75, 0.3, 1)}
    saved = {p: [s_.material for s_ in o.material_slots] for p, o in objs.items()}
    for p, o in objs.items():
        m = bpy.data.materials.new('prev_' + p)
        m.use_nodes = True
        nt_ = m.node_tree
        bsdf = nt_.nodes.get('Principled BSDF') or nt_.nodes.new('ShaderNodeBsdfPrincipled')
        mo = nt_.nodes.get('Material Output') or nt_.nodes.new('ShaderNodeOutputMaterial')
        nt_.links.new(bsdf.outputs[0], mo.inputs[0])
        bsdf.inputs['Base Color'].default_value = pal[p]
        for s_ in o.material_slots:
            s_.material = m
    sc = bpy.context.scene
    for p, o in objs.items():
        for s_ in o.material_slots:
            s_.material.diffuse_color = pal[p]
    sc.render.engine = 'BLENDER_WORKBENCH'   # 部位色は viewport 色で（使用者 blend の render 設定に左右されない）
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'MATERIAL'
    sc.render.resolution_x, sc.render.resolution_y = 700, 1000
    w = bpy.data.worlds.new('w')
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes.get('Background') or nt.nodes.new('ShaderNodeBackground')
    wo = nt.nodes.get('World Output') or nt.nodes.new('ShaderNodeOutputWorld')
    nt.links.new(bg.outputs[0], wo.inputs[0])
    bg.inputs[0].default_value = (0.5, 0.5, 0.5, 1)
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN'))
    sun.data.energy = 3
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = 'ORTHO'
    for nm, ang, z, os_ in (('front', 0, 0.86, 2.0), ('back', 180, 0.86, 2.0), ('side', 90, 0.86, 2.0),
                            ('headfront', 0, 1.5, 0.45), ('headback', 180, 1.5, 0.45), ('headside', 90, 1.5, 0.45)):
        a = math.radians(ang)
        cam.data.ortho_scale = os_
        cam.location = Vector((math.sin(a) * 5, -math.cos(a) * 5, z))
        cam.rotation_euler = (Vector((0, 0, z)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = '%s_%s.png' % (PREV, nm)
        bpy.ops.render.render(write_still=True)
    for p, o in objs.items():
        for s_, m in zip(o.material_slots, saved[p]):
            s_.material = m
    bpy.data.objects.remove(sun, do_unlink=True)
    bpy.data.objects.remove(cam, do_unlink=True)

for m in mats:
    m.use_nodes = False
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
for o in objs.values():
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_materials='EXPORT', export_image_format='NONE',
                          export_animations=False, export_skins=True, export_yup=True, export_apply=False)
json.dump(rep, open(REPORT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('REPORT', json.dumps(rep, ensure_ascii=False))
