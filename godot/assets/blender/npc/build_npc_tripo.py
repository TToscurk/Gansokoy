"""P10 NPC Asset Library：使用者の Tripo NPC（Mixamo rig 済み FBX）を Godot 用 GLB へ整える。外観は変えない。
  - 原 FBX は読むだけ（保存しない）
  - 指定身長へ一様スケール（骨・頂点に適用、親ノードの回転・縮尺も適用）、足裏を床 z=0 へ
  - メッシュは原構成のまま：頭頂側だけにある別メッシュ＝NPC_Hair、他＝NPC_Body（1 メッシュなら NPC_Body のみ）
  - 材質は名前だけ（M_Body／M_Hair）——Godot で外部 .tres（原 basecolor を albedo）へ差し替え
  - 動作・カメラ・ライトは持たない
blender -b -P build_npc_tripo.py -- <src.fbx> <height_m> <out.glb> <report.json>
"""
import bpy, sys, json
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:]
SRC, HEIGHT, OUT, REPORT = argv[0], float(argv[1]), argv[2], argv[3]
# 任意：--uv-from=<使用者 blend>：骨架版 FBX の UV／basecolor ではなく、使用者 blend（Tripo 原版）の UV と原画像を使う。
# 理由：布料老闆娘の骨架 ZIP は再ベイクされた atlas の肌が灰色化（同じループで原画像 0.93/0.74/0.64 → atlas 0.63/0.59/0.57）。
# ループ順（loop→vertex）が原版と完全一致することを確かめてから写す。
UV_FROM = next((a.split('=', 1)[1] for a in argv[4:] if a.startswith('--uv-from=')), '')
# 任意：--apron-fix=<json>：前掛けの幾何クリアランス＋左右対称の太腿重み（apron_fix.py、主婦 shufu_f01；使用者裁定 2026-10-06）
APRON_FIX = next((a.split('=', 1)[1] for a in argv[4:] if a.startswith('--apron-fix=')), '')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC)
for o in list(bpy.data.objects):
    if o.type in ('CAMERA', 'LIGHT'):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
rep = {'src': SRC, 'target_height': HEIGHT, 'bones': len(arm.data.bones), 'src_armature_obj': {'name': arm.name, 'scale': list(arm.scale), 'rot': list(arm.rotation_euler)}}
UV_TEX = {}   # rig メッシュ名 → 原画像の絶対パス
if UV_FROM:
    import os
    import numpy as np
    names = [m.name for m in meshes]
    with bpy.data.libraries.load(UV_FROM, link=False) as (src, dst):
        want = [n for n in src.objects if n in names]
        dst.objects = list(want)   # 同じ list を渡すと読み込み後にオブジェクトへ置き換わる
    rep['uv_from'] = {'blend': UV_FROM, 'parts': {}, 'safety': {}}
    if sorted(want) != sorted(names):
        raise SystemExit('uv-from STOP: 原版 blend に無いメッシュがある（rig %s／原版 %s）' % (names, want))

    def arr(coll, attr, n, dt=np.int32):
        a = np.zeros(len(coll) * n, dtype=dt)
        coll.foreach_get(attr, a)
        return a

    for want_name, so in zip(want, dst.objects):   # 追加したオブジェクトは名前衝突で .001 になる → 要求順で対応
        if so is None or so.type != 'MESH':
            raise SystemExit('uv-from STOP: %s を原版から読めない' % want_name)
        m = next(x for x in meshes if x.name == want_name)
        A, B = so.data, m.data
        # 安全確認（使用者裁定 2026-10-06 改）：UV 移植の互換性は「描画される面の位相」で判定する。
        #   必須一致：頂点数・頂点順／頂点対応・面数・面の頂点添字・ループ数・面を構成する辺の集合・連結成分の対応。
        #   許容（report に記録）：どの面にも属さない loose edge／loose vertex（UV ループを持たず、面・skin 面に影響しない）。
        #   面・ループ・面の辺・頂点順・頂点対応のどれかが違えば STOP。
        def face_edges(me):
            return set(ek for p in me.polygons for ek in p.edge_keys)

        def all_edges(me):
            return set(tuple(sorted(e.vertices)) for e in me.edges)

        def face_verts(me):
            return set(int(v) for p in me.polygons for v in p.vertices)

        def components(me, nv):
            par = list(range(nv))

            def f(x):
                while par[x] != x:
                    par[x] = par[par[x]]
                    x = par[x]
                return x
            for a_, b_ in face_edges(me):
                ra, rb = f(a_), f(b_)
                if ra != rb:
                    par[ra] = rb
            return [f(i) for i in range(nv)]

        chk = {'verts': [len(A.vertices), len(B.vertices)], 'polys': [len(A.polygons), len(B.polygons)], 'loops': [len(A.loops), len(B.loops)]}
        ok = chk['verts'][0] == chk['verts'][1] and chk['polys'][0] == chk['polys'][1] and chk['loops'][0] == chk['loops'][1]
        if ok:
            chk['loop_vertex_order_equal'] = bool((arr(A.loops, 'vertex_index', 1) == arr(B.loops, 'vertex_index', 1)).all())
            chk['poly_loop_start_equal'] = bool((arr(A.polygons, 'loop_start', 1) == arr(B.polygons, 'loop_start', 1)).all()
                                                and (arr(A.polygons, 'loop_total', 1) == arr(B.polygons, 'loop_total', 1)).all())
            fa, fb = face_edges(A), face_edges(B)
            chk['face_edges'] = [len(fa), len(fb)]
            chk['face_edge_set_equal'] = fa == fb
            # 連結成分の対応：同じ添字の頂点が同じ成分どうしに対応（成分ラベルの対応が全単射）
            ca_, cb_ = components(A, len(A.vertices)), components(B, len(B.vertices))
            fwd, bwd = {}, {}
            comp_ok = True
            for x, y in zip(ca_, cb_):
                if fwd.setdefault(x, y) != y or bwd.setdefault(y, x) != x:
                    comp_ok = False
                    break
            chk['components'] = [len(set(ca_)), len(set(cb_))]
            chk['component_correspondence'] = comp_ok
            # 頂点の対応：同じ添字どうしの距離比が一定（剛体＋一様縮尺に不変）
            ca = np.array([so.matrix_world @ v.co for v in A.vertices])
            cb = np.array([m.matrix_world @ v.co for v in B.vertices])
            rng = np.random.default_rng(0)
            i, j = rng.integers(0, len(ca), 4000), rng.integers(0, len(ca), 4000)
            da, db = np.linalg.norm(ca[i] - ca[j], axis=1), np.linalg.norm(cb[i] - cb[j], axis=1)
            keep = da > 1e-4
            ratio = db[keep] / da[keep]
            chk['dist_ratio_rel_std'] = float(ratio.std() / ratio.mean())
            # 追加読み込みした原版オブジェクトは親（空ノード等）が付かないため、世界座標が非一様縮尺ぶん歪むことがある →
            # 頂点対応は「アフィン写像で一致するか」で判定（最小二乗の残差 / bbox 対角）
            X = np.hstack([ca, np.ones((len(ca), 1))])
            M, *_ = np.linalg.lstsq(X, cb, rcond=None)
            diag = float(np.linalg.norm(cb.max(0) - cb.min(0)))
            chk['affine_residual_rel'] = float(np.sqrt(((X @ M - cb) ** 2).sum(1).mean()) / diag)
            # 許容差（記録のみ）：面に属さない辺・頂点
            la_, lb_ = all_edges(A) - fa, all_edges(B) - fb
            chk['loose_edges'] = {'orig': [list(e) for e in sorted(la_)], 'rig': [list(e) for e in sorted(lb_)]}
            chk['loose_edge_len_orig_units'] = [round(float(np.linalg.norm(ca[u] - ca[v])), 5) for u, v in sorted(la_)]
            fva, fvb = face_verts(A), face_verts(B)
            chk['loose_verts'] = {'orig': sorted(set(range(len(A.vertices))) - fva), 'rig': sorted(set(range(len(B.vertices))) - fvb)}
            chk['loose_only_differences'] = bool((all_edges(A) != all_edges(B)) or fva != fvb or bool(chk['loose_verts']['orig'] or chk['loose_verts']['rig']))
            ok = (chk['loop_vertex_order_equal'] and chk['poly_loop_start_equal'] and chk['face_edge_set_equal'] and comp_ok
                  and fva == fvb and chk['affine_residual_rel'] < 1e-4)
        rep['uv_from']['safety'][m.name] = chk
        print('UVFROM_SAFETY', m.name, json.dumps(chk))
        if not ok:
            raise SystemExit('uv-from STOP: %s の頂点数・頂点順・位相が原版と一致しない %s' % (m.name, chk))
        uv = np.zeros(len(so.data.loops) * 2, dtype=np.float32)
        so.data.uv_layers.active.data.foreach_get('uv', uv)
        m.data.uv_layers.active.data.foreach_set('uv', uv)
        img = next(n.image for s in so.material_slots for n in s.material.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image and n.outputs['Color'].is_linked)
        p = img.filepath
        if p.startswith('//'):
            p = os.path.join(os.path.dirname(UV_FROM), p[2:])
        UV_TEX[m.name] = os.path.normpath(bpy.path.abspath(p))
        rep['uv_from']['parts'][m.name] = UV_TEX[m.name]
        bpy.data.objects.remove(so, do_unlink=True)


def bbox_z():
    zs = [(m.matrix_world @ v.co).z for m in meshes for v in m.data.vertices]
    return min(zs), max(zs)


z0, z1 = bbox_z()
rep['src_height'] = round(z1 - z0, 4)
# 親の空ノード（ParentNode 等）も含め、全オブジェクトの変換を適用してから縮尺
for o in bpy.data.objects:
    o.hide_set(False)
    o.hide_viewport = False
s = HEIGHT / (z1 - z0)
roots = [o for o in bpy.data.objects if o.parent is None]
for r in roots:
    r.scale = r.scale * s
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
z0, z1 = bbox_z()
# 正面を Blender の -Y（glTF/Godot の +Z）へ：キャラの左肩→右肩ではなく「右→左」ベクトルが +X を向くよう Z 軸回り 90° 単位で回す
# （mixamo65_a 系の原 FBX は横〔±X〕を向いていた）
def _bone_w(nm):
    for b in arm.data.bones:
        if b.name.endswith(nm):
            return arm.matrix_world @ b.head_local
    return None


lr = _bone_w('LeftArm') - _bone_w('RightArm')
import math
yaw = math.degrees(math.atan2(lr.y, lr.x))
snap = round(yaw / 90.0) * 90.0
rep['facing_fix_deg'] = -snap
if snap != 0:
    from mathutils import Matrix
    R = Matrix.Rotation(math.radians(-snap), 4, 'Z')
    for r in roots:
        r.matrix_world = R @ r.matrix_world
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    z0, z1 = bbox_z()
for r in roots:
    r.location.z -= z0
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
# 空の親ノードを外す（Armature を最上位に）
for o in list(bpy.data.objects):
    if o.type == 'EMPTY':
        for c in list(o.children):
            mw = c.matrix_world.copy()
            c.parent = None
            c.matrix_world = mw
        bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.update()
z0, z1 = bbox_z()
rep['height_m'] = round(z1 - z0, 4)
rep['feet_z'] = round(z0, 4)
rep['scale'] = round(s, 5)
arm.name = 'Armature'
for pb in arm.pose.bones:
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.rotation_euler = (0, 0, 0); pb.scale = (1, 1, 1)
if arm.animation_data:
    arm.animation_data.action = None
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)

# 部位：頭頂側にだけある別メッシュ＝髪
rep['parts'] = {}
hair_cut = 0.55 * HEIGHT
parts = {}
for m in meshes:
    zs = [(m.matrix_world @ v.co).z for v in m.data.vertices]
    key = 'Hair' if len(meshes) > 1 and min(zs) > hair_cut else 'Body'
    if key in parts:
        raise SystemExit('二つのメッシュが同じ部位 %s に分類された' % key)
    parts[key] = m
for key, m in parts.items():
    # 重みゼロの頂点（布料老闆娘の髪に 2 個）→ 最寄りの重みあり頂点の重みを写す（glTF は全頂点に重みが必要；無いと neutral_bone が足され、動かすと頂点が置き去り）
    from mathutils import kdtree
    wv = [v for v in m.data.vertices if sum(g.weight for g in v.groups) > 1e-4]
    zv = [v for v in m.data.vertices if sum(g.weight for g in v.groups) <= 1e-4]
    if zv:
        kd = kdtree.KDTree(len(wv))
        for i, v in enumerate(wv):
            kd.insert(v.co, i)
        kd.balance()
        for v in zv:
            src_v = wv[kd.find(v.co)[1]]
            for g in src_v.groups:
                m.vertex_groups[g.group].add([v.index], g.weight, 'REPLACE')
    rep.setdefault('unweighted_fixed', {})[key] = len(zv)
    tex = None
    for sl in m.material_slots:
        if sl.material and sl.material.use_nodes:
            for n in sl.material.node_tree.nodes:
                if n.type == 'TEX_IMAGE' and n.image:
                    tex = bpy.path.abspath(n.image.filepath)
                    break
    if m.name in UV_TEX:
        tex = UV_TEX[m.name]
    m.name = m.data.name = 'NPC_' + key
    mat = bpy.data.materials.new('M_' + key)
    m.data.materials.clear()
    m.data.materials.append(mat)
    skinned = [md for md in m.modifiers if md.type == 'ARMATURE']
    if m.parent != arm:
        mw = m.matrix_world.copy()
        m.parent = arm
        m.matrix_world = mw
    m.data.calc_loop_triangles()
    zs = [(m.matrix_world @ v.co).z for v in m.data.vertices]
    rep['parts'][key] = {'tris': len(m.data.loop_triangles), 'verts': len(m.data.vertices), 'texture': tex,
                         'skinned': bool(skinned), 'vgroups': len(m.vertex_groups), 'z': [round(min(zs), 4), round(max(zs), 4)]}
if APRON_FIX:
    import os as _os
    sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
    import apron_fix
    _P = json.load(open(APRON_FIX, encoding='utf-8')) if _os.path.exists(APRON_FIX) else json.loads(APRON_FIX)
    _body = parts['Body']
    bpy.context.view_layer.update()
    rep['apron_fix'] = apron_fix.apply(_body, apron_fix.regions(_body), _P)
    _body.data.calc_loop_triangles()
    print('APRONFIX', json.dumps(rep['apron_fix']))
rep['total_tris'] = sum(p['tris'] for p in rep['parts'].values())
bpy.ops.object.select_all(action='DESELECT')
arm.select_set(True)
for m in parts.values():
    m.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_materials='EXPORT', export_image_format='NONE',
                          export_animations=False, export_skins=True, export_yup=True, export_apply=False)
json.dump(rep, open(REPORT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('REPORT', json.dumps(rep, ensure_ascii=False))
