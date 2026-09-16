"""緣一 反應動畫組（受擊／格擋／彈刀／架勢／軀幹爆）—— Meshy 24-bone rig。

執行：
  blender --background --python tools/blender/make_react_clips.py

輸出：
  godot/characters/yoriichi/anim_src/react_clips.glb   （一個 GLB、五個動作）

沿用 make_form08_thrust.py 的機制（姿勢表 → keyframe → GLB，Hips 水平鎖 0）。
軸向全部來自 probe_arm_axes.py / probe_torso_axes.py 實測，不是猜：
  角色面朝 -Y、+Z 上、手臂沿 ±X 展開
  Spine*/Hips  X+ = 前彎（頭往前下）   X- = 後仰       Z+ = 頭往 -X 側彎
  neck/Head    X+ = 低頭               X- = 抬頭
  *UpLeg       X+ = 腿往後擺           X- = 腿往前踢
  *Leg (膝)    X+ = 屈膝（腳跟往後上）
  *Foot        X+ = 腳尖下壓
  RightArm     Z- = 往前  Z+ = 往後    X- = 往上抬  X+ = 往下放
  LeftArm      Z+ = 往前  Z- = 往後    X- = 往上抬
  RightForeArm Z+ = 屈肘（刀收回）     Z- = 打直
  RightHand    X+ = 手腕下折           Z+ = 手往後
"""
import bpy
import math
import os
from mathutils import Quaternion, Vector

FBX = r"D:/神社/shrine/godot/characters/yoriichi/yoriichi_body.fbx"
# 基底姿勢：Idle_11 首幀。這支 rig 的 rest 是 T-pose，從 identity 起 key 的 clip
# 首尾幀都是 T-pose（form08 的 00_kamae 預覽就是這樣）。所有反應 clip 的旋轉
# 都寫成「Idle 姿 × 差分」，首尾幀＝Idle，和 loco 層 Idle_Grounded 無縫混合。
IDLE_FBX = r"D:/神社/shrine/角色/緣一動作/Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Idle_11_withSkin.fbx"
IDLE_Z_SHIFT = -0.123   # animations/README：Idle 源腳趾懸空 0.123，衍生版 Hips 下移
OUT_DIR = r"D:/神社/shrine/godot/characters/yoriichi/anim_src"
OUT = os.path.join(OUT_DIR, "react_clips.glb")
FPS = 24

X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)

# ---------------------------------------------------------------------------
# 架勢（Guard_Hold）：刀舉在胸前偏右、刃朝外，微沉重心。這是格擋／彈刀的基底。
# 12 幀，f0 從 rest 進入、f6 到位、f12 保持（給 loop 留呼吸）。
# ---------------------------------------------------------------------------
GUARD = {
    "RightShoulder": [(0, Z, 0), (6, Z, -10), (12, Z, -10)],
    "RightArm":      [(0, Z, 0), (6, Z, -40), (12, Z, -40)],
    "RightArm.x":    [(0, X, 0), (6, X, -18), (12, X, -18)],
    "RightForeArm":  [(0, Z, 0), (6, Z, 62), (12, Z, 62)],
    "RightHand":     [(0, X, 0), (6, X, -28), (12, X, -28)],
    "LeftShoulder":  [(0, Z, 0), (6, Z, 6), (12, Z, 6)],
    "LeftArm":       [(0, Z, 0), (6, Z, 30), (12, Z, 30)],
    "LeftArm.x":     [(0, X, 0), (6, X, 12), (12, X, 12)],
    "LeftForeArm":   [(0, Z, 0), (6, Z, -48), (12, Z, -48)],
    "Spine02":       [(0, X, 0), (6, X, 7), (12, X, 7)],
    "Spine01":       [(0, X, 0), (6, X, 4), (12, X, 4)],
    "Spine02.z":     [(0, Z, 0), (6, Z, -6), (12, Z, -6)],
    "neck":          [(0, X, 0), (6, X, -3), (12, X, -3)],
}
# upper 層：Hips 不在 filter 內，位置由 locomotion 決定 → 這三支不寫 Hips、不寫腿。
GUARD_HIPS = [(0, 0.0), (12, 0.0)]

# ---------------------------------------------------------------------------
# 格擋受衝（Block_Impact，upper 層）：架勢被砸一下，刀手往後壓、肩縮，再彈回。
# 8 幀 = 0.33 s。以 GUARD 到位姿為基底（差分寫在 base 上）。
# ---------------------------------------------------------------------------
BLOCK = {
    "RightArm":      [(0, Z, -40), (2, Z, -22), (8, Z, -40)],
    "RightArm.x":    [(0, X, -18), (2, X, -10), (8, X, -18)],
    "RightForeArm":  [(0, Z, 62), (2, Z, 80), (8, Z, 62)],
    "RightHand":     [(0, X, -28), (2, X, -12), (8, X, -28)],
    "RightShoulder": [(0, Z, -10), (2, Z, 4), (8, Z, -10)],
    "LeftArm":       [(0, Z, 30), (2, Z, 18), (8, Z, 30)],
    "LeftForeArm":   [(0, Z, -48), (2, Z, -60), (8, Z, -48)],
    "Spine02":       [(0, X, 7), (2, X, -4), (8, X, 7)],
    "Spine01":       [(0, X, 4), (2, X, -2), (8, X, 4)],
    "neck":          [(0, X, -3), (2, X, -9), (8, X, -3)],
    "Head":          [(0, X, 0), (2, X, -6), (8, X, 0)],
}
BLOCK_HIPS = [(0, 0.0), (8, 0.0)]

# ---------------------------------------------------------------------------
# 彈刀（Deflect，upper 層）：架勢瞬間往外上方撥開，刀走一個小弧再收回。
# 10 幀 = 0.42 s。f0 架勢 → f2 撥開最大 → f5 稍過 → f10 回架勢。
# ---------------------------------------------------------------------------
DEFLECT = {
    "RightShoulder": [(0, Z, -10), (2, Z, -22), (10, Z, -10)],
    "RightArm":      [(0, Z, -40), (2, Z, -58), (5, Z, -50), (10, Z, -40)],
    "RightArm.x":    [(0, X, -18), (2, X, -48), (5, X, -36), (10, X, -18)],
    "RightForeArm":  [(0, Z, 62), (2, Z, 30), (5, Z, 44), (10, Z, 62)],
    "RightHand":     [(0, X, -28), (2, X, 6), (5, X, -12), (10, X, -28)],
    "RightHand.z":   [(0, Z, 0), (2, Z, -22), (10, Z, 0)],
    "LeftArm":       [(0, Z, 30), (2, Z, 14), (10, Z, 30)],
    "LeftForeArm":   [(0, Z, -48), (2, Z, -40), (10, Z, -48)],
    "Spine02":       [(0, X, 7), (2, X, 2), (10, X, 7)],
    "Spine02.y":     [(0, Y, 0), (2, Y, -10), (5, Y, -6), (10, Y, 0)],
    "Spine01.y":     [(0, Y, 0), (2, Y, -6), (10, Y, 0)],
    "neck":          [(0, X, -3), (2, X, -6), (10, X, -3)],
}
DEFLECT_HIPS = [(0, 0.0), (10, 0.0)]

# ---------------------------------------------------------------------------
# 受擊（Hit_React，full 層）：從 rest 被砍中 —— 上身猛後仰、頭甩、右腳往後踉蹌半步，
# 再收回。10 幀 = 0.42 s；遊戲端 1.5x ≈ 0.28 s，對上 hit_stun_time 0.25。
# ---------------------------------------------------------------------------
HIT = {
    "Spine02":       [(0, X, 0), (2, X, -22), (5, X, -14), (10, X, 0)],
    "Spine01":       [(0, X, 0), (2, X, -14), (5, X, -9), (10, X, 0)],
    "Spine":         [(0, X, 0), (2, X, -8), (10, X, 0)],
    "Spine02.z":     [(0, Z, 0), (2, Z, 9), (10, Z, 0)],
    "neck":          [(0, X, 0), (2, X, -18), (5, X, -6), (10, X, 0)],
    "Head":          [(0, X, 0), (2, X, -12), (10, X, 0)],
    "RightShoulder": [(0, Z, 0), (2, Z, 12), (10, Z, 0)],
    "RightArm":      [(0, Z, 0), (2, Z, 18), (10, Z, 0)],
    "RightArm.x":    [(0, X, 0), (2, X, -22), (10, X, 0)],
    "RightForeArm":  [(0, Z, 0), (2, Z, 28), (10, Z, 0)],
    "LeftArm":       [(0, Z, 0), (2, Z, -16), (10, Z, 0)],
    "LeftArm.x":     [(0, X, 0), (2, X, -26), (10, X, 0)],
    "LeftForeArm":   [(0, Z, 0), (2, Z, -30), (10, Z, 0)],
    # 右腳往後踉蹌：髖後擺、膝彎；左腿撐住微彎
    "RightUpLeg":    [(0, X, 0), (2, X, 16), (6, X, 12), (10, X, 0)],
    "RightLeg":      [(0, X, 0), (2, X, 24), (6, X, 16), (10, X, 0)],
    "LeftUpLeg":     [(0, X, 0), (2, X, -6), (10, X, 0)],
    "LeftLeg":       [(0, X, 0), (2, X, 12), (10, X, 0)],
}
HIT_HIPS = [(0, 0.0), (2, -0.03), (6, -0.02), (10, 0.0)]

# ---------------------------------------------------------------------------
# 軀幹爆（Stagger，full 層）：break_time 2.0 s = 48 幀。
# f0 rest → f5 膝軟、上身前傾、刀手垂下 → f8~f40 撐住顫抖（2 Hz 小幅） → f48 站回。
# 破綻窗口要「看得出能被處決」：頭低、刀垂、重心下沉，全程不站直。
# ---------------------------------------------------------------------------
def _tremble(base, amp, f0, f1, period=12, axis=Z):
    out = []
    f = f0
    s = 1
    while f <= f1:
        out.append((f, axis, base + amp * s))
        s = -s
        f += period // 2
    return out

STAGGER = {
    "Spine02":       [(0, X, 0), (5, X, 26), (8, X, 30), (40, X, 30), (48, X, 0)],
    "Spine01":       [(0, X, 0), (5, X, 14), (40, X, 14), (48, X, 0)],
    "Spine":         [(0, X, 0), (5, X, 8), (40, X, 8), (48, X, 0)],
    "Spine02.z":     [(0, Z, 0)] + _tremble(0, 3.5, 8, 40) + [(48, Z, 0)],
    "neck":          [(0, X, 0), (5, X, 14), (40, X, 14), (48, X, 0)],
    "Head":          [(0, X, 0), (5, X, 10), (40, X, 10), (48, X, 0)],
    "RightShoulder": [(0, Z, 0), (5, Z, 8), (40, Z, 8), (48, Z, 0)],
    "RightArm.x":    [(0, X, 0), (5, X, 38), (40, X, 38), (48, X, 0)],
    "RightArm":      [(0, Z, 0), (5, Z, -12), (40, Z, -12), (48, Z, 0)],
    "RightForeArm":  [(0, Z, 0), (5, Z, 18), (40, Z, 18), (48, Z, 0)],
    "RightHand":     [(0, X, 0), (5, X, 20), (40, X, 20), (48, X, 0)],
    "LeftArm.x":     [(0, X, 0), (5, X, 34), (40, X, 34), (48, X, 0)],
    "LeftArm":       [(0, Z, 0), (5, Z, 14), (40, Z, 14), (48, Z, 0)],
    "LeftForeArm":   [(0, Z, 0), (5, Z, -20), (40, Z, -20), (48, Z, 0)],
    # 膝軟：兩膝屈、髖前擺補償，腳掌留在原地（垂直由 Hips 下沉配合）
    "LeftUpLeg":     [(0, X, 0), (5, X, -22), (40, X, -22), (48, X, 0)],
    "LeftLeg":       [(0, X, 0), (5, X, 34), (40, X, 34), (48, X, 0)],
    "RightUpLeg":    [(0, X, 0), (5, X, -14), (40, X, -14), (48, X, 0)],
    "RightLeg":      [(0, X, 0), (5, X, 26), (40, X, 26), (48, X, 0)],
    "LeftFoot":      [(0, X, 0), (5, X, -10), (40, X, -10), (48, X, 0)],
    "RightFoot":     [(0, X, 0), (5, X, -10), (40, X, -10), (48, X, 0)],
}
STAGGER_HIPS = [(0, 0.0), (5, -0.11), (8, -0.12), (40, -0.12), (48, 0.0)]

CLIPS = [
    ("Guard_Hold",   GUARD,   GUARD_HIPS,   12),
    ("Block_Impact", BLOCK,   BLOCK_HIPS,   8),
    ("Deflect",      DEFLECT, DEFLECT_HIPS, 10),
    ("Hit_React",    HIT,     HIT_HIPS,     10),
    ("Stagger",      STAGGER, STAGGER_HIPS, 48),
]


def find_armature():
    for o in bpy.data.objects:
        if o.type == 'ARMATURE':
            return o
    raise RuntimeError("找不到骨架")


def _fcurves(action):
    if hasattr(action, "fcurves"):
        return action.fcurves
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out


def _scale_hips_for_export(action, k):
    for fc in _fcurves(action):
        if fc.data_path.endswith('["Hips"].location'):
            for kp in fc.keyframe_points:
                kp.co.y *= k
                kp.handle_left.y *= k
                kp.handle_right.y *= k


def load_idle_base():
    """回傳 {bone: Quaternion} 與 Hips location（bone-local, cm）—— Idle_11 第 0 幀。"""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=IDLE_FBX)
    new = [o for o in bpy.data.objects if o not in before]
    idle_arm = next(o for o in new if o.type == 'ARMATURE')
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    base = {}
    for pb in idle_arm.pose.bones:
        base[pb.name] = (pb.matrix_basis.to_quaternion().copy(), pb.matrix_basis.to_translation().copy())
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    return base


def build_clip(arm, name, poses, hips_z, last, base):
    """一個 clip = 一個 action。同一骨頭可有多條軸表（"Bone.x"），逐幀合成四元數。"""
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = base[pb.name][0] if pb.name in base else Quaternion((1, 0, 0, 0))
        pb.location = Vector((0, 0, 0))

    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data.action = action
    if hasattr(action, "slots"):
        slot = action.slots.new(id_type='OBJECT', name=name)
        arm.animation_data.action_slot = slot

    # 合併：bone -> {axis_tuple: [(f, deg)]}
    per_bone = {}
    for key, entries in poses.items():
        bone = key.split(".")[0]
        per_bone.setdefault(bone, []).append(entries)

    frames = set()
    for lists in per_bone.values():
        for entries in lists:
            for f, _, _ in entries:
                frames.add(f)
    # 匯出器把範圍當半開區間 [0, end)，多 key 一幀（末姿勢複製）才包得到 f=last。
    pad = last + 1
    frames = sorted(frames | {0, last, pad})
    hips_z = list(hips_z) + [(pad, hips_z[-1][1])]

    def interp(entries, f):
        pts = [(ff, d) for ff, _, d in entries]
        if f <= pts[0][0]:
            return pts[0][1]
        if f >= pts[-1][0]:
            return pts[-1][1]
        for (f0, d0), (f1, d1) in zip(pts, pts[1:]):
            if f0 <= f <= f1:
                t = (f - f0) / max(f1 - f0, 1)
                t = t * t * (3 - 2 * t)   # smoothstep，讓多軸合成時不互相打架
                return d0 + (d1 - d0) * t
        return pts[-1][1]

    # 沒列在姿勢表的骨頭也要 key 成 Idle 姿（否則 Godot 端缺軌＝停在 T-pose）
    for pb in arm.pose.bones:
        if pb.name in per_bone or pb.name == "Hips":
            continue
        pb.rotation_quaternion = base.get(pb.name, (Quaternion((1, 0, 0, 0)),))[0]
        pb.keyframe_insert(data_path="rotation_quaternion", frame=0)
        pb.keyframe_insert(data_path="rotation_quaternion", frame=pad)

    for bone, lists in per_bone.items():
        pb = arm.pose.bones.get(bone)
        if pb is None:
            print(f"  [略過] 找不到骨頭 {bone}")
            continue
        for f in frames:
            q = base[bone][0].copy() if bone in base else Quaternion((1, 0, 0, 0))
            for entries in lists:
                axis = entries[0][1]
                q = q @ Quaternion(Vector(axis).normalized(), math.radians(interp(entries, f)))
            pb.rotation_quaternion = q
            pb.keyframe_insert(data_path="rotation_quaternion", frame=f)

    hips = arm.pose.bones["Hips"]
    # Hips 骨的 local Y 不是正上（實測沿骨長寫會漏 ~57% 到水平）：
    # 把世界 +Z 轉進骨 local 再乘量，下沉才是純垂直。
    up_local = hips.bone.matrix_local.to_3x3().inverted() @ Vector((0.0, 0.0, 1.0))
    up_local.normalize()
    hips.rotation_quaternion = base["Hips"][0]
    hips.keyframe_insert(data_path="rotation_quaternion", frame=0)
    hips.keyframe_insert(data_path="rotation_quaternion", frame=pad)
    # Hips 基底 = Idle 首幀位置（cm）＋ README 的 −0.123 m 落地補正；差分再疊上去。
    hips_base = base["Hips"][1] + up_local * (IDLE_Z_SHIFT * 100.0)
    for f, dz in hips_z:
        # bone local Y = 沿骨長（Hips 骨朝上）→ 垂直起伏寫 location.y。
        # ⚠ 骨架物件 scale 0.01：bone-local 單位是**公分**。Blender 內量測要 ×100
        #   才是真的公尺；匯出前再 ÷100（Godot 讀 GLB 骨骼平移不套物件 scale，
        #   form08 實測 ×100 直接匯出會把髖抬高 4.7 m）。見 _scale_hips_for_export。
        hips.location = hips_base + up_local * (dz * 100.0)
        for i in range(3):
            hips.keyframe_insert(data_path="location", frame=f, index=i)

    for fc in _fcurves(action):
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
            kp.handle_left_type = 'AUTO_CLAMPED'
            kp.handle_right_type = 'AUTO_CLAMPED'

    # 不用 use_frame_range：手動範圍會被匯出器當半開區間，掉最後一幀
    # （實測 12 幀只出 0~11）。所有骨頭都在 f0 與 f=last 有 key，範圍由 key 決定。
    n_keys = sum(len(fc.keyframe_points) for fc in _fcurves(action))
    print(f"  {name}: {last} 幀 = {last / FPS:.3f} s，曲線 {len(list(_fcurves(action)))} 條、key {n_keys}")
    return action


def main(clips=None, out=None, title="緣一 反應動畫組", extra_shots=None):
    """clips/out 可由其他姿勢表腳本（make_form_clips.py）傳入，共用同一條管線。"""
    clips = CLIPS if clips is None else clips
    out = OUT if out is None else out
    bpy.ops.wm.read_factory_settings(use_empty=True)
    print(f"=== {title} ===")
    bpy.ops.import_scene.fbx(filepath=FBX)
    arm = find_armature()
    print(f"骨架 {arm.name}，{len(arm.data.bones)} 骨")
    scene = bpy.context.scene
    scene.render.fps = FPS

    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    if arm.animation_data is None:
        arm.animation_data_create()
    # 源 FBX 自帶的走路動作不要一起匯出
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)

    bpy.ops.object.mode_set(mode='OBJECT')
    base = load_idle_base()
    # ⚠ 每次 import_scene.fbx 都會把場景 fps 改成 30；Idle 基底載入後才鎖 24
    #   （第一版量到 dt=1/30、Stagger 1.567 s 而非 2.0）。
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    print(f"Idle 基底：{len(base)} 骨，Hips loc(cm)={tuple(round(v, 2) for v in base['Hips'][1])}")
    actions = []
    for name, poses, hips_z, last in clips:
        actions.append(build_clip(arm, name, poses, hips_z, last, base))
    bpy.ops.object.mode_set(mode='OBJECT')

    # 每個 action 推進自己的 NLA track，匯出器才會全部帶出
    arm.animation_data.action = None
    for a in actions:
        tr = arm.animation_data.nla_tracks.new()
        tr.name = a.name
        tr.strips.new(a.name, 0, a)

    # 量測＋連拍要在網格還在的時候做（GLB 不帶 skin，回讀後沒有骨架可量）
    import importlib.util, sys
    spec = importlib.util.spec_from_file_location(
        "check_react_clips", os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_react_clips.py"))
    chk = importlib.util.module_from_spec(spec)
    sys.modules["check_react_clips"] = chk
    spec.loader.exec_module(chk)
    if extra_shots:
        chk.SHOTS.update(extra_shots)
    chk.measure_and_render(arm, actions)
    for a in actions:
        _scale_hips_for_export(a, 0.01)

    for o in list(bpy.data.objects):
        if o.type != 'ARMATURE':
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format='GLB',
        use_selection=True,
        export_animations=True,
        export_animation_mode='NLA_TRACKS',
        export_nla_strips=True,
        export_frame_range=True,
        export_anim_slide_to_zero=True,
        export_skins=False,
        export_materials='NONE',
        export_yup=True,
    )
    print(f"已輸出 {out}（{os.path.getsize(out) / 1024:.1f} KB）")


if __name__ == "__main__":
    main()
