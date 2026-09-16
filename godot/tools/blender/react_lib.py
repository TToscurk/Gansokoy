"""緣一 反應 clip 的 Blender MCP 工作庫（在開著的 Blender 裡 exec）。

exec(open(r'D:/神社/shrine/godot/tools/blender/react_lib.py', encoding='utf-8').read(), globals())

前提：場景裡有 'Yoriichi' 骨架（Idle 基底姿）、'Sword' 掛在 RightHand（Godot socket 換算）。
座標：骨架空間 -Y 前、+Z 上、+X 為角色左手側（LeftHand x=+0.656）。
"""
import bpy, math
from mathutils import Vector, Quaternion, Matrix

arm = bpy.data.objects['Yoriichi']
sw = bpy.data.objects['Sword']
P = arm.pose.bones
FWD = Vector((0, -1, 0)); UP = Vector((0, 0, 1)); LEFT = Vector((1, 0, 0))


def W(v):
    return arm.matrix_world @ v


BLADE_LEN = 0.95   # Godot 實測：BladeBase→BladeTip 0.95 m（probe_sword_skel，Idle_Grounded f0）


def sword_line():
    """回傳 (柄 world, 尖 world, 方向)。刀本地 +Z 為刀長軸。
    ⚠ 刀尖用 BLADE_LEN 沿方向外推：Sword 物件掛在 0.01 縮放的骨架下，直接 M @ (0,0,1.085)
    只得到 1 cm 外的點（之前的「刀尖」其實是柄）。"""
    M = sw.matrix_world
    base = M @ Vector((0, 0, -0.05))
    d = (M.to_3x3() @ Vector((0, 0, 1))).normalized()
    tip = base + d * BLADE_LEN
    return base, tip, d


def report(tag=''):
    bpy.context.view_layer.update()
    b, t, d = sword_line()
    rh = W(P['RightHand'].head); lh = W(P['LeftHand'].head); hd = W(P['Head'].head)
    foot = min(W(P['LeftToeBase'].head).z, W(P['RightToeBase'].head).z)
    print(f"[{tag}] 刀尖 ({t.x:+.2f},{t.y:+.2f},{t.z:+.2f}) 刀向 ({d.x:+.2f},{d.y:+.2f},{d.z:+.2f}) "
          f"| 右手 ({rh.x:+.2f},{rh.y:+.2f},{rh.z:+.2f}) 左手 ({lh.x:+.2f},{lh.y:+.2f},{lh.z:+.2f}) "
          f"| 頭 y{hd.y:+.2f} z{hd.z:+.2f} | 腳底 {foot:.3f}")
    return dict(tip=t, dir=d, rh=rh, lh=lh, foot=foot)


def reset_to_base():
    for pb in P:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = BASE[pb.name][0] if pb.name in BASE else Quaternion((1, 0, 0, 0))
        pb.location = Vector((0, 0, 0))
    P['Hips'].location = HIPS_BASE.copy()
    bpy.context.view_layer.update()


def rot(bone, axis, deg):
    """在 Idle 基底上疊一個骨-local 軸旋轉（與 make_react_clips 的姿勢表同語意）。"""
    pb = P[bone]
    pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion(Vector(axis).normalized(), math.radians(deg))


def set_hips_dz(dz_m):
    P['Hips'].location = HIPS_BASE + UP_LOCAL * (dz_m * 100.0)


# ---- IK：右手→目標，左手→目標（暫時性，量完 bake 成 FK） -----------------
def ensure_ik():
    """IK 掛在 ForeArm（chain 2、目標=手腕）：手骨旋轉留給 FK 控刀向。"""
    bpy.context.view_layer.objects.active = arm
    if 'IK_R' not in arm.data.bones:
        bpy.ops.object.mode_set(mode='EDIT')
        eb = arm.data.edit_bones
        for nm, src in (('IK_R', 'RightHand'), ('IK_L', 'LeftHand')):
            b = eb.new(nm); b.head = eb[src].head.copy(); b.tail = b.head + Vector((0, 0, 5)); b.use_deform = False
        bpy.ops.object.mode_set(mode='POSE')
    for fa, nm in (('RightForeArm', 'IK_R'), ('LeftForeArm', 'IK_L')):
        if not any(c.type == 'IK' for c in P[fa].constraints):
            c = P[fa].constraints.new('IK'); c.name = 'ik'; c.target = arm; c.subtarget = nm
            c.chain_count = 2; c.use_tail = True


def ik_mute(m):
    for fa in ('RightForeArm', 'LeftForeArm'):
        for c in P[fa].constraints:
            if c.type == 'IK': c.mute = m


def aim_sword(want, steps=15):
    """搜尋 RightHand 局部旋轉讓刀向最貼近 want（骨架空間單位向量）。回傳 (dot, (ax,az,ay))。"""
    want = Vector(want).normalized()
    base_q = P['RightHand'].rotation_quaternion.copy()
    best = (-2, None)
    for ax in range(0, 360, steps):
        for az in range(0, 360, steps):
            for ay in (-45, -15, 0, 15, 45):
                P['RightHand'].rotation_quaternion = base_q @ Quaternion((1, 0, 0), math.radians(ax)) @ Quaternion((0, 0, 1), math.radians(az)) @ Quaternion((0, 1, 0), math.radians(ay))
                bpy.context.view_layer.update()
                s = sword_line()[2].dot(want)
                if s > best[0]: best = (s, (ax, az, ay))
    ax, az, ay = best[1]
    P['RightHand'].rotation_quaternion = base_q @ Quaternion((1, 0, 0), math.radians(ax)) @ Quaternion((0, 0, 1), math.radians(az)) @ Quaternion((0, 1, 0), math.radians(ay))
    bpy.context.view_layer.update()
    return best


def ik_to(nm, world_pos):
    """把 IK 目標放到骨架空間座標（公尺）。"""
    pb = P[nm]
    pb.matrix = Matrix.Translation(arm.matrix_world.inverted() @ world_pos)
    bpy.context.view_layer.update()


def left_hand_on_hilt(z_gap=0.13, iters=4):
    """左手骨中點 = 右手骨中點在刀本地的同一橫向偏移，只沿柄往尾端退 z_gap。
    右手對柄的偏移是 Godot socket 的實測校準（骨中點離軸 5.5 cm = 掌厚），
    左手照抄才會是同一種握法，而不是把骨頭釘在刀軸上。"""
    for _ in range(iters):
        bpy.context.view_layer.update()
        M = sw.matrix_world; Mi = M.inverted()
        rmid = Mi @ ((W(P['RightHand'].head) + W(P['RightHand'].tail)) * 0.5)
        hilt = M @ Vector((rmid.x, rmid.y, rmid.z - z_gap))
        h = W(P['LeftHand'].head); t = W(P['LeftHand'].tail)
        mid = (h + t) * 0.5
        ik_to('IK_L', W(P['IK_L'].head) + (hilt - mid))
    bpy.context.view_layer.update()
    h = W(P['LeftHand'].head); t = W(P['LeftHand'].tail)
    return ((h + t) * 0.5 - hilt).length


def align_left_wrist_to_right():
    """左手骨方向對齊右手骨方向（同樣橫跨刀柄）。"""
    rd = (W(P['RightHand'].tail) - W(P['RightHand'].head)).normalized()
    bq = P['LeftHand'].rotation_quaternion.copy(); best = (-2, None)
    for ax in range(0, 360, 15):
        for az in range(0, 360, 15):
            P['LeftHand'].rotation_quaternion = bq @ Quaternion((1, 0, 0), math.radians(ax)) @ Quaternion((0, 0, 1), math.radians(az))
            bpy.context.view_layer.update()
            s = (W(P['LeftHand'].tail) - W(P['LeftHand'].head)).normalized().dot(rd)
            if s > best[0]: best = (s, (ax, az))
    ax, az = best[1]
    P['LeftHand'].rotation_quaternion = bq @ Quaternion((1, 0, 0), math.radians(ax)) @ Quaternion((0, 0, 1), math.radians(az))
    bpy.context.view_layer.update()
    return best


def hand_axis_report():
    b, t, d = sword_line()
    for nm in ('RightHand', 'LeftHand'):
        h = W(P[nm].head); tl = W(P[nm].tail); mid = (h + tl) * 0.5
        along = (mid - b).dot(d); off = ((mid - b) - d * along).length
        print(f"  {nm} 骨中點：沿柄 {along:+.3f}  離軸 {off:.3f}")


def bake_ik_to_fk():
    """把 IK 解出的手臂姿勢寫回 FK（rotation_quaternion），然後關 IK。"""
    bpy.context.view_layer.update()
    got = {}
    for b in ('RightArm', 'RightForeArm', 'LeftArm', 'LeftForeArm'):
        got[b] = P[b].matrix.copy()
    ik_mute(True)
    for b in ('RightArm', 'RightForeArm', 'LeftArm', 'LeftForeArm'):
        P[b].matrix = got[b]
        bpy.context.view_layer.update()
    return {b: P[b].rotation_quaternion.copy() for b in got}


def snapshot(bones=None):
    """目前姿勢（相對 Idle 基底）→ {bone: (axis, deg)} 近似不可逆；改回傳絕對四元數。"""
    bones = bones or [pb.name for pb in P]
    return {b: P[b].rotation_quaternion.copy() for b in bones}, P['Hips'].location.copy()


def apply_snapshot(snap):
    q, hl = snap
    for b, v in q.items(): P[b].rotation_quaternion = v
    P['Hips'].location = hl
    bpy.context.view_layer.update()


def view(side=True, dist=2.4, target=(0, -0.1, 0.95)):
    for a in bpy.context.screen.areas:
        if a.type == 'VIEW_3D':
            r3 = a.spaces[0].region_3d
            r3.view_perspective = 'ORTHO'
            r3.view_rotation = Quaternion((0.5, 0.5, 0.5, 0.5)) if side else Quaternion((0.7071, 0.7071, 0, 0))
            if not side:
                # front-ish 3/4: from -Y +X
                r3.view_rotation = Quaternion((0.65, 0.65, 0.27, 0.27))
            r3.view_location = Vector(target); r3.view_distance = dist


def render_pose(tag, out_dir=r"D:/神社/shrine/godot/characters/yoriichi/anim_src/preview"):
    """側視＋前 3/4 兩張，Workbench，回傳路徑列表。"""
    import os
    sc = bpy.context.scene
    cam = bpy.data.objects.get('ReactCam')
    if cam is None:
        cd = bpy.data.cameras.new('ReactCam'); cd.type = 'ORTHO'; cd.ortho_scale = 2.3
        cam = bpy.data.objects.new('ReactCam', cd); sc.collection.objects.link(cam)
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'; sc.render.resolution_x, sc.render.resolution_y = 600, 800
    sh = sc.display.shading; sh.light = 'STUDIO'; sh.color_type = 'SINGLE'; sh.single_color = (0.62, 0.62, 0.66); sh.show_cavity = True
    if sc.world is None: sc.world = bpy.data.worlds.new('World')
    sc.world.color = (0.09, 0.09, 0.11)
    tgt = Vector((0, -0.15, 0.95))
    outs = []
    for name, pos in (('side', Vector((4.0, -0.15, 0.95))), ('f34', Vector((-2.8, -3.2, 1.1)))):
        cam.location = pos
        cam.rotation_euler = (tgt - pos).to_track_quat('-Z', 'Y').to_euler()
        path = os.path.join(out_dir, f"mcp_{tag}_{name}.png")
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        outs.append(path)
    return outs


def load_pose(tag):
    import json
    q = {k: Quaternion(v) for k, v in json.loads(arm['pose_' + tag]).items()}
    apply_snapshot((q, Vector(arm['pose_' + tag + '_hips'])))


def save_pose(tag):
    """先把 IK 解出的手臂烤進 FK 四元數（否則快照只有 Idle 手臂），再存。"""
    import json
    bake_ik_to_fk()
    q, hl = snapshot(); arm['pose_' + tag] = json.dumps({k: list(v) for k, v in q.items()}); arm['pose_' + tag + '_hips'] = list(hl)


def _fcurves(action):
    if hasattr(action, 'fcurves'): return action.fcurves
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for cb in strip.channelbags: out.extend(cb.fcurves)
    return out


def author_clip(name, keys, last):
    """keys: {frame: pose_tag}。每個 key 幀寫全部骨頭的四元數＋Hips location；最後多 pad 一幀。"""
    ik_mute(True)
    old = bpy.data.actions.get(name)
    if old: bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name); action.use_fake_user = True
    if arm.animation_data is None: arm.animation_data_create()
    arm.animation_data.action = action
    if hasattr(action, 'slots'):
        arm.animation_data.action_slot = action.slots.new(id_type='OBJECT', name=name)
    frames = dict(keys); frames[last + 1] = keys[max(keys)]
    for f in sorted(frames):
        load_pose(frames[f])
        for pb in P:
            if pb.name.startswith('IK_'): continue
            pb.keyframe_insert('rotation_quaternion', frame=f)
        for i in range(3): P['Hips'].keyframe_insert('location', frame=f, index=i)
    for fc in _fcurves(action):
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'; kp.handle_left_type = 'AUTO_CLAMPED'; kp.handle_right_type = 'AUTO_CLAMPED'
    return action


def export_react_glb(names, out=r"D:/神社/shrine/godot/characters/yoriichi/anim_src/react_mcp.glb"):
    """匯出前 Hips location ×0.01（cm→m，與 make_react_clips 同規則），匯出後還原。"""
    acts = [bpy.data.actions[n] for n in names]
    bpy.ops.object.mode_set(mode='OBJECT')
    ad = arm.animation_data; ad.action = None
    for tr in list(ad.nla_tracks): ad.nla_tracks.remove(tr)
    for a in acts:
        for fc in _fcurves(a):
            if fc.data_path.endswith('["Hips"].location'):
                for kp in fc.keyframe_points: kp.co.y *= 0.01; kp.handle_left.y *= 0.01; kp.handle_right.y *= 0.01
        tr = ad.nla_tracks.new(); tr.name = a.name; tr.strips.new(a.name, 0, a)
    sw.hide_set(True); sw.hide_viewport = True
    bpy.ops.object.select_all(action='DESELECT'); arm.select_set(True); bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_animations=True,
        export_animation_mode='NLA_TRACKS', export_nla_strips=True, export_frame_range=True,
        export_anim_slide_to_zero=True, export_skins=False, export_materials='NONE', export_yup=True)
    sw.hide_set(False); sw.hide_viewport = False
    for a in acts:
        for fc in _fcurves(a):
            if fc.data_path.endswith('["Hips"].location'):
                for kp in fc.keyframe_points: kp.co.y *= 100; kp.handle_left.y *= 100; kp.handle_right.y *= 100
    for tr in list(ad.nla_tracks): ad.nla_tracks.remove(tr)
    bpy.ops.object.mode_set(mode='POSE')
    import os
    return out, os.path.getsize(out)


# ---- 基底快取 ---------------------------------------------------------------
import json
if 'react_base' not in arm:
    arm['react_base'] = json.dumps({pb.name: list(pb.rotation_quaternion) for pb in P})
    arm['react_hips'] = list(P['Hips'].location)
_b = json.loads(arm['react_base'])
BASE = {k: (Quaternion(v), Vector((0, 0, 0))) for k, v in _b.items()}
HIPS_BASE = Vector(arm['react_hips'])
UP_LOCAL = (P['Hips'].bone.matrix_local.to_3x3().inverted() @ UP).normalized()
if 'locked_basis' in sw:
    sw.matrix_parent_inverse = Matrix.Identity(4)
    sw.matrix_basis = Matrix([list(r) for r in sw['locked_basis']])
bpy.context.view_layer.objects.active = arm
if bpy.context.mode != 'POSE':
    bpy.ops.object.mode_set(mode='POSE')
print('react_lib ready; BASE bones', len(BASE))
