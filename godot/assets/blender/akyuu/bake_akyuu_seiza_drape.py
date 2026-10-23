"""阿求 正座的袴垂放：Blender 布料模擬（含自碰撞）烘成 rest 空間形狀，給 SeizaDrape shape key 用。來源 blend 只讀不存。
  1. 與 export_akyuu_glb.py 相同的變換（1.60 m、正面 -Y、腳底 z=0）
  2. 套 Godot 端輸出的正座骨姿（export_akyuu_pose_json.gd：世界旋轉差量＋骨架空間位置；Godot→Blender：(x, -z, y)），讀回關節誤差
  3. 動畫：1–10 格 rest，10→60 格內插到正座，60–F 格靜止讓布落定
  4. 衣身複本：Armature → Cloth（腰帶以上釘住、往下 4 cm 淡出；自碰撞）；碰撞體＝身體減面代理（含 Armature）＋鞋＋地板
  5. 最後一格的布（正座空間）用逐頂點 LBS 反算回 rest 空間 → npz（含來源 local 空間轉換矩陣）
限制 CPU：命令列加 -t 4；每格計時，超過 budget 秒中止並回報。
pose.json 若是多格序列（export_akyuu_pose_json.gd … all）→ 逐格播轉場 clip，cap=格號,… 擷取那些格的布（npz cap_<格號>），hold=結尾保持格數
blender -b -t 4 <阿求_rig_4K.blend> -P bake_akyuu_seiza_drape.py -- <pose.json> <out.npz> [frames=100] [budget_s=900] [bend=1] [dec=1] [bthick=0.008] [sthick=0.018] [subdiv=0] [quality=5] [cquality=2]
"""
import bpy, bmesh, sys, os, json, math, time
import numpy as np
from mathutils import Matrix, Vector, Quaternion
argv = sys.argv[sys.argv.index('--') + 1:]
POSE, OUT = argv[0], argv[1]
FRAMES = int(argv[2]) if len(argv) > 2 else 100
BUDGET = float(argv[3]) if len(argv) > 3 else 900.0
OPT = dict(a.split('=', 1) for a in argv[4:])
BEND = float(OPT.get('bend', 1.0)); DEC = float(OPT.get('dec', 1.0)); BTHICK = float(OPT.get('bthick', 0.008)); STHICK = float(OPT.get('sthick', 0.018))
SUBDIV = int(OPT.get('subdiv', 0)); QUAL = int(OPT.get('quality', 5)); CQUAL = int(OPT.get('cquality', 2))
HEIGHT = 1.6
t0 = time.time()
for o in list(bpy.data.objects):
    if o.type in ('CAMERA', 'LIGHT'):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for pb in arm.pose.bones:
    pb.matrix_basis = Matrix()
if arm.animation_data:
    arm.animation_data.action = None
for o in bpy.data.objects:
    o.hide_set(False); o.hide_viewport = False
bpy.context.view_layer.update()
def bbox():
    a = np.array([tuple(m.matrix_world @ v.co) for m in meshes for v in m.data.vertices]); return a.min(0), a.max(0)
lo, hi = bbox(); s = HEIGHT / float(hi[2] - lo[2])
roots = [o for o in bpy.data.objects if o.parent is None]
for r in roots: r.matrix_world = Matrix.Scale(s, 4) @ r.matrix_world
bpy.context.view_layer.update()
P = 'mixamorig:'
B = arm.data.bones
bw = lambda n: arm.matrix_world @ B[P + n].head_local
lr = bw('LeftArm') - bw('RightArm')
snap = round(math.degrees(math.atan2(lr.y, lr.x)) / 90.0) * 90.0
if snap:
    for r in roots: r.matrix_world = Matrix.Rotation(math.radians(-snap), 4, 'Z') @ r.matrix_world
bpy.context.view_layer.update()
lo, hi = bbox()
for r in roots: r.matrix_world = Matrix.Translation((0, 0, -float(lo[2]))) @ r.matrix_world
bpy.context.view_layer.update()
kimono = bpy.data.objects['衣身']
M_EXP = np.array(kimono.matrix_world)          # 來源 local → 匯出空間（transform_apply 前）
sel = list(bpy.context.view_layer.objects)
for o in sel: o.select_set(True)
bpy.context.view_layer.objects.active = arm
with bpy.context.temp_override(active_object=arm, object=arm, selected_objects=sel, selected_editable_objects=sel):
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o.type == 'EMPTY':
        for c in list(o.children):
            mw = c.matrix_world.copy(); c.parent = None; c.matrix_world = mw
        bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.update()
# ---------- 套骨姿（單一正座，或序列＝轉場 clip 逐格）----------
pose_in = json.load(open(POSE, encoding='utf-8'))
SEQ = 'frames' in pose_in
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))       # Godot(Y up, +Z 前) → Blender(Z up, -Y 前)
def g2b(v): return C @ Vector(v)
order = []
def walk(b):
    order.append(b)
    for c in b.children: walk(c)
for b in B:
    if b.parent is None: walk(b)
for pb in arm.pose.bones: pb.rotation_mode = 'QUATERNION'
def solve(pose):
    for pb in arm.pose.bones: pb.matrix_basis = Matrix()
    bpy.context.view_layer.update()
    for b in order:
        if b.name not in pose: continue
        q = pose[b.name]['dq_xyzw']
        Dg = Quaternion((q[3], q[0], q[1], q[2])).to_matrix()
        rot = (C @ Dg @ C.transposed()) @ b.matrix_local.to_3x3()
        pb = arm.pose.bones[b.name]
        pb.matrix = Matrix.Translation(g2b(pose[b.name]['pos'])) @ rot.to_4x4()
        bpy.context.view_layer.update()
    err = max((arm.pose.bones[b.name].head - g2b(pose[b.name]['pos'])).length for b in B if b.name in pose)
    return {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in arm.pose.bones}, err
p0 = pose_in['frames'][0] if SEQ else pose_in
rest_err = max((g2b(p0[b.name]['rest_pos']) - b.head_local).length for b in B if b.name in p0)
sc = bpy.context.scene
arm.animation_data_create()
keys = []   # (frame, solved)
pose_err = 0.0
if SEQ:
    # 1–10 rest → 40 轉場首格（站姿）→ 55 靜止 → 56.. 逐格播 clip → 最後一格保持 HOLD 格
    seq = []
    for fr in pose_in['frames']:
        sv, e = solve(fr); seq.append(sv); pose_err = max(pose_err, e)
    S0 = 56; HOLD = int(OPT.get('hold', 30))
    keys = [(1, None), (10, None), (40, seq[0]), (S0 - 1, seq[0])] + [(S0 + i, sv) for i, sv in enumerate(seq)] + [(S0 + len(seq) - 1 + HOLD, seq[-1])]
    FRAMES = S0 + len(seq) - 1 + HOLD
    CAPS = [int(x) for x in OPT.get('cap', '').split(',') if x != '']   # 要擷取的 clip 格號
    CAP_FRAMES = {S0 + c: c for c in CAPS}
    print('SEQ frames', len(seq), 'blender frames', FRAMES, 'caps', CAPS, flush=True)
else:
    seiza, pose_err = solve(pose_in)
    keys = [(1, None), (10, None), (60, seiza), (FRAMES, seiza)]
    CAP_FRAMES = {}
sc.frame_start, sc.frame_end = 1, FRAMES
for pb in arm.pose.bones:
    for f, sv in keys:
        q, l = (Quaternion(), Vector()) if sv is None else sv[pb.name]
        pb.rotation_quaternion = q; pb.location = l
        pb.keyframe_insert('rotation_quaternion', frame=f); pb.keyframe_insert('location', frame=f)
# ---------- 碰撞體 ----------
hz = (arm.matrix_world @ B[P + 'Hips'].head_local).z
body = bpy.data.objects['身體']
proxy = body.copy(); proxy.data = body.data.copy(); proxy.name = 'BodyProxy'; sc.collection.objects.link(proxy)
# 代理：全解析度身體，只留腰以下＋手（T-pose 時 |x| 大的部分）；上身頭臂中段刪掉省 CPU
bm = bmesh.new(); bm.from_mesh(proxy.data)
kill = [v for v in bm.verts if not (v.co.z < hz + 0.12 or abs(v.co.x) > 0.5)]
bmesh.ops.delete(bm, geom=kill, context='VERTS'); bm.to_mesh(proxy.data); bm.free()
if DEC < 1.0:
    dec = proxy.modifiers.new('Dec', 'DECIMATE'); dec.ratio = DEC
    proxy.modifiers.move(len(proxy.modifiers) - 1, 0)
print('PROXY verts', len(proxy.data.vertices), 'of', len(body.data.vertices))
for o in [proxy, bpy.data.objects['鞋子右'], bpy.data.objects['鞋子左']]:
    cm = o.modifiers.new('Col', 'COLLISION')
    o.collision.thickness_outer = BTHICK if o is proxy else STHICK; o.collision.cloth_friction = 5.0
body.hide_render = True
bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0)); floor_ = bpy.context.active_object; floor_.name = 'Floor'
floor_.modifiers.new('Col', 'COLLISION'); floor_.collision.thickness_outer = 0.004; floor_.collision.cloth_friction = 4.0
# ---------- 布 ----------
cloth = kimono   # 直接在（未存檔的）衣身上模擬
N_ORIG = len(cloth.data.vertices)
if SUBDIV > 0:
    # 模擬網格加密（bmesh 細分：原頂點索引 0..N-1 與位置不變、新頂點接在後面，頂點群組權重內插）→ 大褶子較平順、少碎稜角；輸出只取原頂點
    bm2 = bmesh.new(); bm2.from_mesh(cloth.data)
    for _ in range(SUBDIV):
        bmesh.ops.subdivide_edges(bm2, edges=bm2.edges[:], cuts=1, use_grid_fill=True, smooth=0.0)
    bm2.to_mesh(cloth.data); bm2.free(); cloth.data.update()
    print('SUBDIV verts', N_ORIG, '->', len(cloth.data.vertices))
pin = cloth.vertex_groups.new(name='PIN')
for v in cloth.data.vertices:
    z = (cloth.matrix_world @ v.co).z
    w = min(1.0, max(0.0, (z - (hz + 0.02)) / 0.04))
    pin.add([v.index], w, 'REPLACE')
cm = cloth.modifiers.new('Cloth', 'CLOTH')
st = cm.settings; cs = cm.collision_settings
st.quality = QUAL; st.mass = 0.3; st.air_damping = 1.0
st.tension_stiffness = 20; st.compression_stiffness = 20; st.shear_stiffness = 5; st.bending_stiffness = BEND
st.vertex_group_mass = 'PIN'; st.pin_stiffness = 1.0
cs.use_collision = True; cs.distance_min = 0.005; cs.collision_quality = CQUAL
cs.use_self_collision = True; cs.self_distance_min = 0.003; cs.self_friction = 5
cm.point_cache.frame_start = 1; cm.point_cache.frame_end = FRAMES
# ---------- 模擬（逐格、計時）----------
times = []
aborted = False
CAPTURED = {}
for f in range(1, FRAMES + 1):
    ts = time.time()
    sc.frame_set(f)
    times.append(time.time() - ts)
    if f in CAP_FRAMES:
        dg0 = bpy.context.evaluated_depsgraph_get(); ev0 = cloth.evaluated_get(dg0); me0 = ev0.to_mesh()
        CAPTURED[CAP_FRAMES[f]] = np.array([tuple(v.co) for v in me0.vertices])[:N_ORIG]; ev0.to_mesh_clear()
    if time.time() - t0 > BUDGET:
        aborted = True; break
    if f % 10 == 0:
        print('FRAME %d  %.2fs/frame  total %.0fs' % (f, times[-1], time.time() - t0), flush=True)
dg = bpy.context.evaluated_depsgraph_get()
ev = cloth.evaluated_get(dg); me = ev.to_mesh()
Pc = np.array([tuple(v.co) for v in me.vertices]); ev.to_mesh_clear()
# ---------- LBS 反算回 rest ----------
V = np.array([tuple(v.co) for v in cloth.data.vertices])
gi = {g.index: g.name for g in cloth.vertex_groups}
Mb = {pb.name: np.array(pb.matrix @ pb.bone.matrix_local.inverted()) for pb in arm.pose.bones}
R = np.zeros_like(V); sk_pos = np.zeros_like(V)
for v in cloth.data.vertices:
    M = np.zeros((4, 4)); wsum = 0.0
    for g in v.groups:
        n = gi[g.group]
        if n in Mb and g.weight > 0: M += Mb[n] * g.weight; wsum += g.weight
    if wsum <= 0: R[v.index] = V[v.index]; continue
    M /= wsum
    p = np.append(Pc[v.index], 1.0)
    R[v.index] = (np.linalg.inv(M) @ p)[:3]
    sk_pos[v.index] = (M @ np.append(V[v.index], 1.0))[:3]
disp = np.linalg.norm(R - V, axis=1)
E = np.array([e.vertices[:] for e in cloth.data.edges])
l0 = np.linalg.norm(V[E[:, 0]] - V[E[:, 1]], axis=1); l1 = np.linalg.norm(Pc[E[:, 0]] - Pc[E[:, 1]], axis=1)
r = l1 / np.maximum(l0, 1e-6)
rep = {'rest_err_m': round(rest_err, 4), 'pose_err_m': round(pose_err, 4), 'frames_done': len(times), 'aborted': aborted,
       'sec_per_frame_mean': round(float(np.mean(times)), 2), 'total_s': round(time.time() - t0, 1),
       'below_floor': int((Pc[:, 2] < -0.002).sum()), 'skinned_below_floor': int((sk_pos[:, 2] < -0.002).sum()),
       'rest_disp_max_m': round(float(disp.max()), 3), 'edge_stretch_max': round(float(r.max()), 2), 'edges_over_1.5x': int((r > 1.5).sum()), 'edges': len(r),
       'nan': int(np.isnan(Pc).any(axis=1).sum())}
extra = {'cap_%d' % k: v for k, v in CAPTURED.items()}
np.savez(OUT, rest_new=R[:N_ORIG], rest=V[:N_ORIG], posed=Pc[:N_ORIG], M_exp=M_EXP, **extra)
rep['captured'] = sorted(CAPTURED.keys())
print('BAKE ' + json.dumps(rep))
