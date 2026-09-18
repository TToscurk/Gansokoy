"""居合蓄力兩支 clip —— Yoriichi rig（Blender MCP 端，v5）。

Iai_Stance（蓄力架勢，loop 段 f8-f32）：mid-draw kamae —— 沉腰深蹲、上身前傾右擰、
  雙手疊握低橫身前的刀、頭平視。f0 Idle → f8 進姿 → f20 呼吸 → f32=kamae（loop 無縫）。
  引擎用 custom timeline 只播 f8-f32 循環（同 Jump 的 Fall loop 寫法）。
Iai_Slash（拔刀斬，f0-f24）：kamae → 壓(f3) → 逆袈裟拔斬(f7，刀從右腰前掃到左上高) →
  殘心(f11) → 收刀勢回 Idle(f17-24)。Hips 水平鎖 0（位移由 GDScript 衝刺驅動）。

v3/v4 教訓（渲染＋實測）：
  * 拉 IK 到「鞘軸點」得到拄棍姿 —— 這遊戲的鞘是 65° 陡角插身前（實測鞘口 z1.11、
    刀尖 z0.23），柄在胸口高。且引擎流程是收刀 RMB 先拔刀才進蓄力，蓄力時刀已在手：
    目標姿勢 = mid-draw kamae，不是納刀蹲姿。
  * left_hand_on_hilt 在刀 local 空間退 z_gap，而 Sword 物件在 0.01 縮放下
    local 0.13 → 世界 1.3 mm → 雙手重疊（v4 實測 hand-dist 7 mm）。左手一律
    世界空間沿 -刀向 退 LH_BACK。
  * 蹲姿會穿地（v4 mesh min z −0.017）：每個姿勢 bake 後做地面夾取（Hips 抬缺額）。
  * upper 層 filter 不含腿/Hips → 蹲姿讀不出來；引擎端必須走 full 層（另行接線）。

產出：pose_* 快照（armature custom props）＋ actions Iai_Stance / Iai_Slash
      ＋ preview/mcp_iai*.png。匯出用 react_lib.export_react_glb。
機制全部沿用 react_lib.py（同一條 MCP 手調管線，憲法第 1 條）。
"""
import bpy, math, traceback
from mathutils import Vector, Quaternion

LIB = r"D:/神社/shrine/godot/tools/blender/react_lib.py"
exec(open(LIB, encoding="utf-8").read(), globals())

LH_BACK = 0.14        # 左手疊握：沿 -刀向、離「右手握點」14 cm（世界空間，兩手恆在柄上）
# ⚠ 左手目標從「右手實際中點」沿 -刀向退，不用 sword_line base —— base 是刀網格原點，
#   刀一旋轉 base 就飄，iaidraw 曾算出 hand-dist 0.165（雙手離開柄）。從右手退才恆距 14 cm。
# 左臂可及：LeftArm+LeftForeArm+半掌 = 0.583 m（bone.length 是 cm，×0.01）；各姿 need ≤ 0.44 m，構得到。

# 每姿 = (grip 世界位置, 刀向 aim, 沉腰 dz, 躯幹/腿差分)
#   差分疊在 SPINE/HEAD/LEGS 基底上：(bone, axis, deg)
POSES = {
    "iaikamae": dict(
        grip=Vector((-0.16, -0.30, 0.98)),
        aim=Vector((0.25, -0.95, -0.14)),
        dz=-0.12, twist=(-7.0, -4.0), extra=[],
    ),
    "iaiwindup": dict(
        grip=Vector((-0.14, -0.26, 0.90)),
        aim=Vector((0.35, -0.88, -0.32)),
        dz=-0.145, twist=(-10.0, -6.0),
        extra=[("LeftLeg", (1, 0, 0), 6.0), ("RightLeg", (1, 0, 0), 6.0),
               ("Spine02", (1, 0, 0), 2.0)],
    ),
    # 抜刀中段（可選 key）：刀已離腰、橫在身前。v5 教訓：沒有中段 key 時
    # kamae→extend 大角度插值會讓刀從「身後」繞過去（實測 f5 刀尖 y=+1.19）。
    "iaidraw": dict(
        grip=Vector((-0.10, -0.34, 1.08)),
        aim=Vector((-0.10, -0.97, 0.20)),
        dz=-0.08, twist=(-2.0, -1.0),
        extra=[("LeftUpLeg", (1, 0, 0), 6.0), ("LeftLeg", (1, 0, 0), -8.0),
               ("RightUpLeg", (1, 0, 0), -4.0), ("RightLeg", (1, 0, 0), -6.0)],
    ),
    # 斬擊完成（f7）＝ nuki-tsuke 橫斬到位：刀水平指前、手在胸前、身體立起前送。
    #   ⚠ 不用高舉過頭殘心：extend→zanshin 若差近 180° 旋轉，slerp 捷徑會讓刀
    #   從身後貼地繞回（v5 實測 f9 刀尖 y=+0.64 z=0.19）。斬與殘心都朝前才乾淨。
    "iaiextend": dict(
        grip=Vector((-0.10, -0.44, 1.06)),
        aim=Vector((0.18, -0.98, 0.06)),
        dz=-0.04, twist=(4.0, 2.0),
        extra=[("LeftUpLeg", (1, 0, 0), 6.0), ("LeftLeg", (1, 0, 0), -10.0),
               ("RightUpLeg", (1, 0, 0), -6.0), ("RightLeg", (1, 0, 0), -12.0),
               ("Spine02", (1, 0, 0), 3.0), ("neck", (1, 0, 0), 4.0)],
    ),
    "iaizanshin": dict(
        grip=Vector((-0.08, -0.38, 1.10)),
        aim=Vector((0.22, -0.96, 0.05)),
        dz=-0.01, twist=(5.0, 2.5),
        extra=[("LeftUpLeg", (1, 0, 0), 2.0), ("LeftLeg", (1, 0, 0), -4.0),
               ("RightUpLeg", (1, 0, 0), -2.0), ("RightLeg", (1, 0, 0), -4.0),
               ("neck", (1, 0, 0), 4.0)],
    ),
}

SPINE_BASE = [  # 前傾基底（X+ 前彎）
    ("Spine02", (1, 0, 0), 9.0),
    ("Spine01", (1, 0, 0), 6.0),
    ("Spine",   (1, 0, 0), 4.0),
]
HEAD_BASE = [("neck", (1, 0, 0), -9.0), ("Head", (1, 0, 0), -6.0)]  # 抬頭平視
LEGS_BASE = [  # 右腳在後蹬、左腳在前弓（抜刀術站位）
    ("LeftUpLeg",  (1, 0, 0), -14.0), ("LeftLeg",  (1, 0, 0), 26.0), ("LeftFoot",  (1, 0, 0), -12.0),
    ("RightUpLeg", (1, 0, 0),  12.0), ("RightLeg", (1, 0, 0), 30.0), ("RightFoot", (1, 0, 0), -14.0),
]


def idle_ground_z():
    """Idle 基底姿的 mesh min z（源 FBX 既有 −0.0185 穿地）：地面夾取的基準。
    以絕對 0 夾取會把蹲姿整個抬高 1.85 cm，淡回 Idle 時腳會 pop。"""
    reset_to_base(); ik_mute(True)
    bpy.context.view_layer.update()
    return mesh_min_z()


def save_pose_raw(tag):
    """不經 bake_ik_to_fk 的快照。⚠ iaiidle 必須用這個：IK 約束活著時 bake，
    手臂會被 rest 位置的 IK 目標拉離 BASE（實測右手 head z 0.913→0.848，差 6 cm），
    clip 的 f0/收尾幀就跟引擎 Idle_Grounded 對不上，OneShot 進出都会 pop。"""
    q, hl = snapshot()
    import json as _json
    arm['pose_' + tag] = _json.dumps({k: list(v) for k, v in q.items()})
    arm['pose_' + tag + '_hips'] = list(hl)


def aim_near(want, refq, steps=10, dot_min=0.99):
    """同 aim_sword，但在「達標解」中挑離 refq 旋轉最近的一個。
    ⚠ aim_sword 只最大化刀向 dot：兩個姿勢刀向相同但 roll 差 180° 時它會各挑
    一個分支，slerp 在兩幀間把整條手臂甩過去（實測 f9 刀尖 x=−1.21 橫掃穿身）。"""
    want = Vector(want).normalized()
    base_q = P['RightHand'].rotation_quaternion.copy()
    best_dot = (-2.0, None)
    near = None
    for ax in range(0, 360, steps):
        for az in range(0, 360, steps):
            for ay in (-45, -15, 0, 15, 45):
                q = base_q @ Quaternion((1, 0, 0), math.radians(ax)) @ Quaternion((0, 0, 1), math.radians(az)) @ Quaternion((0, 1, 0), math.radians(ay))
                P['RightHand'].rotation_quaternion = q
                bpy.context.view_layer.update()
                dot = sword_line()[2].dot(want)
                if dot > best_dot[0]:
                    best_dot = (dot, q.copy())
                if refq is not None and dot >= dot_min:
                    # ⚠ mathutils 的 q.angle 是「屬性」（軸角的旋轉角）；
                    #   兩四元數夾角 = q.rotation_difference(refq).angle
                    ang = q.rotation_difference(refq).angle
                    if near is None or ang < near[0]:
                        near = (ang, q.copy(), dot)
    pick = near[1] if near is not None else best_dot[1]
    P['RightHand'].rotation_quaternion = pick
    bpy.context.view_layer.update()
    return sword_line()[2].dot(want), (near[0] if near else None)


def build_pose(spec, ground_z, refq=None):
    """FK 基底 → IK 右手 → 刀向 → 左手疊握（從右手中點沿 -刀向退）→ bake → 地面夾取。"""
    reset_to_base()
    set_hips_dz(spec["dz"])
    tz, t1 = spec["twist"]
    base = list(SPINE_BASE) + [("Spine02", (0, 0, 1), tz), ("Spine01", (0, 0, 1), t1)] \
        + HEAD_BASE + LEGS_BASE + spec["extra"]
    for b, a, d in base:
        rot(b, a, d)
    bpy.context.view_layer.update()
    ensure_ik(); ik_mute(False)
    ik_pull('IK_R', 'RightHand', spec["grip"])
    dot, _ = aim_near(spec["aim"].normalized(), refq)
    # aim（手骨滾轉）與 IK（手位）互相拉扯：輪流收斂 2 輪
    for _ in range(2):
        e_r = ik_pull('IK_R', 'RightHand', spec["grip"])
        ref2 = P['RightHand'].rotation_quaternion.copy()
        dot, _ = aim_near(spec["aim"].normalized(), ref2, steps=20)
    e_r = ik_pull('IK_R', 'RightHand', spec["grip"])
    # 左手：從「右手實際中點」沿 -刀向退 LH_BACK（恆距疊握，不用會飄的 sword base）
    b, t, d = sword_line()
    rh_mid = (W(P['RightHand'].head) + W(P['RightHand'].tail)) * 0.5
    lh_target = rh_mid - d * LH_BACK
    e_l = ik_pull('IK_L', 'LeftHand', lh_target)
    align_left_wrist_to_right()
    e_l = ik_pull('IK_L', 'LeftHand', lh_target)
    bake_ik_to_fk()
    ik_mute(True)
    # 地面夾取（雙向）：穿地抬、懸空降 —— 站姿（extend/zanshin）腿伸直後
    # min z 會高於基準（實測 zanshin +0.074 = 整個人浮空 7 cm）。
    zmin = mesh_min_z()
    if abs(zmin - ground_z) > 0.001:
        P['Hips'].location += UP_LOCAL * ((ground_z - zmin) * 100.0)
        bpy.context.view_layer.update()
    return e_r, e_l, dot


def ik_pull(name, bone, want, gain=0.8, iters=30):
    def mid():
        h = W(P[bone].head); t = W(P[bone].tail)
        return (h + t) * 0.5
    for _ in range(iters):
        bpy.context.view_layer.update()
        err = want - mid()
        if err.length < 0.012:
            return err.length
        ik_to(name, W(P[name].head) + err * gain)
    # 没收斂（aim 滾轉與 IK 互相拉扯會震盪）：降增益再收一輪
    for _ in range(iters):
        bpy.context.view_layer.update()
        err = want - mid()
        if err.length < 0.012:
            return err.length
        ik_to(name, W(P[name].head) + err * 0.3)
    bpy.context.view_layer.update()
    return (want - mid()).length


def mesh_min_z():
    mesh = bpy.data.objects['char1']
    ev = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return min((ev.matrix_world @ v.co).z for v in ev.data.vertices)


def compose_all():
    reset_to_base(); ik_mute(True); bpy.context.view_layer.update()
    save_pose_raw('iaiidle')   # ⚠ 不能 save_pose（bake 會把手臂拉離 BASE，f0 對不上引擎 Idle）
    ground_z = mesh_min_z()
    print(f"[ground] Idle 基底 mesh min z = {ground_z:.4f}（夾取基準）")
    results = {}
    refq = None   # roll 連續鏈：沿 clip 順序（kamae→windup→draw→extend→zanshin）
    for tag, spec in POSES.items():
        e_r, e_l, dot = build_pose(spec, ground_z, refq=refq)
        save_pose(tag)
        refq = P['RightHand'].rotation_quaternion.copy()
        b, t, d = sword_line()
        rh = (W(P['RightHand'].head) + W(P['RightHand'].tail)) * 0.5
        lh = (W(P['LeftHand'].head) + W(P['LeftHand'].tail)) * 0.5
        results[tag] = dict(e_r=e_r, e_l=e_l, dot=dot, meshz=mesh_min_z(),
                            hand_dist=(rh - lh).length)
        print(f"[{tag}] err R {e_r:.3f} L {e_l:.3f} aim dot {dot:.3f} meshz {results[tag]['meshz']:.4f} "
              f"hand-dist {results[tag]['hand_dist']:.3f} hipsZ {W(P['Hips'].head).z:.3f}")
        print(f"    刀向 {tuple(round(v, 2) for v in d)} 柄 {tuple(round(v, 3) for v in b)} 尖 {tuple(round(v, 3) for v in t)}")
    # 呼吸 variant（kamae 之上）
    load_pose('iaikamae'); ik_mute(True)
    rot('Spine02', (1, 0, 0), 1.5); rot('Spine01', (1, 0, 0), 1.0)
    P['Hips'].location += UP_LOCAL * 0.4
    bpy.context.view_layer.update()
    save_pose('iaibreathe')
    load_pose('iaikamae'); ik_mute(True)
    return results


def build_actions():
    # Iai_Stance：f0 Idle → f8 kamae → f20 breathe → f32 kamae（引擎只循環 f8-f32）
    a1 = author_clip('Iai_Stance', {0: 'iaiidle', 8: 'iaikamae', 20: 'iaibreathe', 32: 'iaikamae'}, 32)
    a1.use_frame_range = True; a1.frame_start = 0; a1.frame_end = 32
    a1.use_cyclic = True
    # Iai_Slash：kamae → 壓 → 拔刀出鞘 → 逆袈裟斬 → 殘心 → Idle
    a2 = author_clip('Iai_Slash', {0: 'iaikamae', 3: 'iaiwindup', 5: 'iaidraw', 7: 'iaiextend',
                                   11: 'iaizanshin', 17: 'iaiidle', 24: 'iaiidle'}, 24)
    a2.use_frame_range = True; a2.frame_start = 0; a2.frame_end = 24
    a2.use_cyclic = False
    return a1, a2


def verify_clip(act, frames):
    """逐幀：mesh min z、刀尖世界位置、Hips z。"""
    ad = arm.animation_data
    prev = ad.action
    for tr in ad.nla_tracks:
        tr.mute = True
    ad.action = act
    # Blender 4.4+ 分層 action：換 action 不帶 slot 就完全不評估（骨頭凍在上一姿勢）。
    if hasattr(act, 'slots') and len(act.slots):
        try:
            ad.action_slot = act.slots[0]
        except Exception:
            pass
    rows = []
    for f in frames:
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        b, t, d = sword_line()
        rows.append((f, mesh_min_z(), tuple(round(v, 3) for v in t), round(W(P['Hips'].head).z, 3)))
    for r in rows:
        print('  f%-3d meshz=%+.4f tip=%s hipsZ=%.3f' % r)
    ad.action = prev
    return rows


if __name__ == "__main__" or True:
    try:
        old = bpy.data.objects.get('IaiPreviewSheath')
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
        compose_all()
        a1, a2 = build_actions()
        print('actions:', [(a.name, tuple(a.frame_range), a.use_cyclic) for a in (a1, a2)])
        print('--- Iai_Stance')
        verify_clip(a1, (0, 4, 8, 16, 20, 26, 32))
        print('--- Iai_Slash')
        verify_clip(a2, (0, 3, 5, 7, 9, 11, 14, 17, 24))
    except Exception:
        print('EXC', traceback.format_exc())
