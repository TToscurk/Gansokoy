"""捌ノ型 陽華突 —— 直線突刺動畫（Yoriichi Meshy 24-bone rig）。

執行：
  blender --background --python tools/blender/make_form08_thrust.py

輸出：
  godot/characters/yoriichi/anim_src/form08_thrust.glb

設計（緣一風格＝沉穩、精準、不炫技）：
  蓄（f0-7）   右手收刀至腰側，重心沉向後腳，肩胛內收 —— 前搖看得見
  突（f8-12）  爆發前刺：右臂完全伸展、腰胯送出、後腳蹬直
  留（f13-17） 刀尖停住不抖（「刺中了」的停頓，緣一的精準感在這裡）
  收（f18-30） 收刀回架勢，重心回中

⚠ 本 rig 的鐵則（README 記載，偵察實證）：
  * 物件 scale = 0.01（FBX 公分制）
  * Hips position 的 **Z 是垂直軸**，X/Y 是水平
  * **水平 root motion 一律為 0** —— 位移由 GDScript 驅動。
    本腳本只寫 Hips 的垂直（Z）與旋轉，水平永遠鎖在 rest。
"""
import bpy
import math
import os
from mathutils import Quaternion, Vector

FBX = r"D:/神社/shrine/godot/characters/yoriichi/yoriichi_body.fbx"
OUT_DIR = r"D:/神社/shrine/godot/characters/yoriichi/anim_src"
OUT = os.path.join(OUT_DIR, "form08_thrust.glb")
ACTION_NAME = "Form08_Thrust"

FPS = 24
LAST = 30

# ---------------------------------------------------------------------------
# 關鍵姿勢表
#
# 每個骨頭給 (frame, (axis_x, axis_y, axis_z), degrees)，以 rest 為基準的
# 局部旋轉。用「軸＋角度」而不是四元數字面值，是為了讓這張表人看得懂、
# 之後能照著使用者的回饋直接改數字。
#
# 軸的意義 —— **probe_arm_axes.py 實測，不是推測**（第一版猜錯，渲圖顯示
# 手臂往後上方翹起而非前刺）：
#   角色面朝 **-Y**（headfront - Head = (0, -0.161, 0)）
#   右臂：繞 **Z 負向** = 手往前（-Y）  ← 突刺主軸，正值會往後
#         繞 X 負向 = 手往上抬
#         繞 Y      = 影響極小（< 0.12），只適合微調
#   ⚠ 繞 X 或 Z 任一方向都會讓手往體側外推（Δx 恆為正 0.2~0.5），
#     所以突刺要靠 Spine 的 Z 負向扭轉把身體帶正，否則會變成側向揮舞。
# ---------------------------------------------------------------------------

POSES = {
    # --- 右臂：持刀手，突刺的主角 ---------------------------------------
    # 全部繞 Z **負向** = 往角色正前方（-Y）。正值會往後翹（第一版的錯）。
    "RightShoulder": [
        (0,  (0, 0, 1),   0.0),
        (7,  (0, 0, 1),  22.0),   # 蓄：肩胛內收，刀收到身後（正 = 往後）
        (12, (0, 0, 1), -30.0),   # 突：肩往前送，延長突刺距離
        (13, (0, 0, 1), -30.0),   # 留：鎖住
        (17, (0, 0, 1), -30.0),
        (30, (0, 0, 1),   0.0),
    ],
    "RightArm": [
        (0,  (0, 0, 1),   0.0),
        (7,  (0, 0, 1),  46.0),   # 蓄：上臂後拉
        (12, (0, 0, 1), -52.0),   # 突：上臂前送
        (13, (0, 0, 1), -52.0),   # 留：鎖住
        (17, (0, 0, 1), -52.0),
        (30, (0, 0, 1),   0.0),
    ],
    "RightForeArm": [
        (0,  (0, 0, 1),   0.0),
        (7,  (0, 0, 1),  78.0),   # 蓄：肘大幅彎曲，刀收在腰側
        (12, (0, 0, 1),  -6.0),   # 突：肘完全打直 —— 這一幀決定突刺的「直」
        (13, (0, 0, 1),  -6.0),   # 留：鎖住
        (17, (0, 0, 1),  -6.0),
        (30, (0, 0, 1),   0.0),
    ],
    "RightHand": [
        (0,  (1, 0, 0),   0.0),
        (7,  (1, 0, 0),  16.0),   # 蓄：手腕內扣，刀尖朝前備妥
        (12, (1, 0, 0),  -8.0),   # 突：手腕打平，刀身與手臂成一直線
        (13, (1, 0, 0),  -8.0),   # 留：鎖住
        (17, (1, 0, 0),  -8.0),
        (30, (1, 0, 0),   0.0),
    ],
    # --- 左臂：**單手突刺**的平衡側 ---------------------------------------
    # ⚠ probe_arm_axes 實測：左臂與右臂完全鏡像 —— 左臂前伸是 Z **正**、
    #   右臂前伸是 Z **負**。第一版左右同號，導致左手跟著往前伸，
    #   整個動作變成「雙手前推」而不是單手突刺（渲圖實證）。
    #   單手突刺時左臂要**往後下方收**，所以左臂取 Z 負值。
    "LeftShoulder": [
        (0,  (0, 0, 1),   0.0),
        (7,  (0, 0, 1),  -8.0),   # 蓄：左肩微開
        (12, (0, 0, 1), -20.0),   # 突：左肩後收，讓出突刺軸線
        (13, (0, 0, 1), -20.0),
        (17, (0, 0, 1), -20.0),
        (30, (0, 0, 1),   0.0),
    ],
    "LeftArm": [
        (0,  (0, 0, 1),   0.0),
        (7,  (0, 0, 1), -18.0),   # 蓄：左臂已在後方待命
        (12, (0, 0, 1), -46.0),   # 突：左臂大幅後擺 = 右手前刺的反作用力
        (13, (0, 0, 1), -46.0),
        (17, (0, 0, 1), -46.0),
        (30, (0, 0, 1),   0.0),
    ],
    "LeftForeArm": [
        (0,  (0, 0, 1),   0.0),
        (7,  (0, 0, 1), -24.0),
        (12, (0, 0, 1), -34.0),   # 突：左肘收在體側後方，不進入畫面主軸
        (13, (0, 0, 1), -34.0),
        (17, (0, 0, 1), -34.0),
        (30, (0, 0, 1),   0.0),
    ],
    # 左臂同時略為下垂（X 正 = 往下），避免與刀身搶同一條水平線
    "LeftHand": [
        (0,  (1, 0, 0),   0.0),
        (7,  (1, 0, 0),  10.0),
        (12, (1, 0, 0),  22.0),
        (17, (1, 0, 0),  22.0),
        (30, (1, 0, 0),   0.0),
    ],
    # --- 軀幹：突刺的力量來源是腰，不是手臂 -------------------------------
    # 同樣是 Z 負向送前。這一段還負責把右臂被推到體側的量帶回正面。
    "Spine02": [
        (0,  (0, 0, 1),   0.0),
        (7,  (0, 0, 1),  12.0),   # 蓄：腰向後擰
        (12, (0, 0, 1), -16.0),   # 突：腰送出（力量從這裡來）
        (13, (0, 0, 1), -16.0),   # 留：鎖住
        (17, (0, 0, 1), -16.0),
        (30, (0, 0, 1),   0.0),
    ],
    "Spine01": [
        (0,  (0, 0, 1),   0.0),
        (7,  (0, 0, 1),   8.0),
        (12, (0, 0, 1), -11.0),
        (13, (0, 0, 1), -11.0),   # 留：鎖住
        (17, (0, 0, 1), -11.0),
        (30, (0, 0, 1),   0.0),
    ],
    "Spine": [
        (0,  (0, 0, 1),   0.0),
        (7,  (0, 0, 1),   6.0),
        (12, (0, 0, 1),  -8.0),
        (30, (0, 0, 1),   0.0),
    ],
    # --- 頭：視線鎖定目標，突刺全程不飄（抵銷腰的擰轉）---------------------
    "neck": [
        (0,  (0, 0, 1),  0.0),
        (7,  (0, 0, 1), -7.0),
        (12, (0, 0, 1),  9.0),
        (30, (0, 0, 1),  0.0),
    ],
    # --- 腿：後腳蹬地是突刺的推進 -----------------------------------------
    # 腿繞 X：正 = 往後，負 = 往前（與手臂不同軸，實測 probe_arm_axes 同理）
    "RightUpLeg": [
        (0,  (1, 0, 0),   0.0),
        (7,  (1, 0, 0),   9.0),   # 蓄：重心沉向後腳
        (12, (1, 0, 0), -12.0),   # 突：後腳蹬直
        (30, (1, 0, 0),   0.0),
    ],
    "RightLeg": [
        (0,  (1, 0, 0),   0.0),
        (7,  (1, 0, 0), -14.0),   # 蓄：屈膝（-26 會把腳壓進地面，實測後收斂）
        (12, (1, 0, 0),  -3.0),   # 突：蹬直
        (30, (1, 0, 0),   0.0),
    ],
    "LeftUpLeg": [
        (0,  (1, 0, 0),   0.0),
        (7,  (1, 0, 0),  -8.0),
        (12, (1, 0, 0),  20.0),   # 突：前腳踏出承接
        (17, (1, 0, 0),  16.0),
        (30, (1, 0, 0),   0.0),
    ],
    "LeftLeg": [
        (0,  (1, 0, 0),   0.0),
        (7,  (1, 0, 0),  10.0),
        (12, (1, 0, 0), -14.0),
        (30, (1, 0, 0),   0.0),
    ],
}

# Hips 的**垂直**起伏（公尺，相對 rest）。蓄力下沉、突刺時略升再落回。
# ⚠ 只有垂直：水平永遠是 rest，水平位移由 GDScript 驅動。
# ⚠ 數值是量出來的，不是憑感覺：初版 f7 沉腰 -0.075 造成腳底穿地 5.6 cm
#   （check_form08_thrust.py 實測）。沉腰量必須小於腳底餘裕（rest 腳底 ≈ 0.031），
#   收到 -0.018 後實測腳底最低 0.028，貼地但不穿。
HIPS_Z = [
    (0,   0.000),
    (7,  -0.018),   # 蓄：沉腰（量測上限，再深就穿地）
    (12,  0.012),   # 突：蹬起
    (17,  0.004),
    (30,  0.000),
]


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def find_armature():
    for o in bpy.data.objects:
        if o.type == 'ARMATURE':
            return o
    raise RuntimeError("找不到骨架")


def key_bone(arm, bone_name, entries, hips_z=None):
    """把一條骨頭的姿勢表寫成 keyframe。"""
    pb = arm.pose.bones.get(bone_name)
    if pb is None:
        print(f"  [略過] 找不到骨頭 {bone_name}")
        return
    pb.rotation_mode = 'QUATERNION'

    for frame, axis, deg in entries:
        q = Quaternion(Vector(axis).normalized(), math.radians(deg))
        pb.rotation_quaternion = q
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)

    if hips_z is not None:
        # ⚠ 水平 root motion 必須顯式鎖 0 並且**寫進 key**：只是「不 key」
        #   不夠 —— 匯出器會沿用最後的 pose 值。x/z 每一幀都釘死在 0。
        for frame, dz in hips_z:
            # ⚠ 骨頭 local space：bone local Y = 沿骨長。此 rig 的 Hips 骨朝上，
            #   故垂直起伏寫在 location.y。
            #   **單位直接就是公尺，不要再 ×100**：glTF 匯出器已經處理過
            #   骨架的 scale 0.01。初版乘了 100，Godot 端實測髖部被抬高 4.7 m
            #   （diag_form08_hips.gd：Z 跨度 1.4584 m，應為 0.030）。
            pb.location = Vector((0.0, dz, 0.0))
            pb.keyframe_insert(data_path="location", frame=frame, index=0)
            pb.keyframe_insert(data_path="location", frame=frame, index=1)
            pb.keyframe_insert(data_path="location", frame=frame, index=2)


def set_interpolation(action):
    """曲線手感：
    蓄力段用 EASE_OUT（慢慢收），突刺段用 EASE_IN 的爆發，收招段平滑。
    緣一的「突然且快」= 蓄力到突刺之間幾乎沒有過渡。
    """
    for fc in _fcurves(action):
        for kp in fc.keyframe_points:
            f = kp.co.x
            if f <= 7:
                kp.interpolation = 'BEZIER'
                kp.easing = 'EASE_IN_OUT'
            elif f <= 12:
                # 突刺：爆發
                kp.interpolation = 'BEZIER'
                kp.easing = 'EASE_OUT'
                kp.handle_left_type = 'AUTO_CLAMPED'
                kp.handle_right_type = 'AUTO_CLAMPED'
            elif f <= 17:
                # 留：刀尖停住，不要有回彈
                kp.interpolation = 'BEZIER'
                kp.easing = 'EASE_IN_OUT'
            else:
                kp.interpolation = 'BEZIER'
                kp.easing = 'EASE_IN_OUT'


def main():
    clear()
    print("=== 捌ノ型 陽華突 ===")
    bpy.ops.import_scene.fbx(filepath=FBX)
    arm = find_armature()
    print(f"骨架 {arm.name}，{len(arm.data.bones)} 骨")

    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start = 0
    scene.frame_end = LAST

    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')

    # 全部歸零，從 rest 開始
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.location = Vector((0, 0, 0))

    if arm.animation_data is None:
        arm.animation_data_create()
    action = bpy.data.actions.new(ACTION_NAME)
    arm.animation_data.action = action
    # Blender 4.4+ slotted actions：新建的 action 需要 slot 才能綁上物件
    if hasattr(action, "slots"):
        slot = action.slots.new(id_type='OBJECT', name=ACTION_NAME)
        arm.animation_data.action_slot = slot

    for bone_name, entries in POSES.items():
        key_bone(arm, bone_name, entries)
    key_bone(arm, "Hips", [(0, (0, 0, 1), 0.0), (LAST, (0, 0, 1), 0.0)], hips_z=HIPS_Z)

    set_interpolation(action)
    bpy.ops.object.mode_set(mode='OBJECT')

    n_curves = sum(len(fc.keyframe_points) for fc in _fcurves(action))
    print(f"動作 {action.name}：曲線 {len(list(_fcurves(action)))} 條、關鍵幀 {n_curves} 個")
    print(f"長度 {LAST / FPS:.3f} s @ {FPS} fps")

    os.makedirs(OUT_DIR, exist_ok=True)
    # ⚠ 只輸出骨架＋動畫，**不帶網格與貼圖**。
    #   初版連 242k 頂點的角色網格一起匯出 = 68 MB GLB ＋ 兩張貼圖被 Godot
    #   當成新資產匯入，純粹是倉庫垃圾 —— 轉檔腳本只讀動畫軌，網格用不到。
    for o in list(bpy.data.objects):
        if o.type != 'ARMATURE':
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format='GLB',
        use_selection=True,
        export_animations=True,
        export_frame_range=True,
        export_anim_slide_to_zero=True,
        export_skins=False,
        export_materials='NONE',
        export_yup=True,
    )
    size_mb = os.path.getsize(OUT) / 1024 / 1024
    print(f"已輸出 {OUT}（{size_mb:.2f} MB）")


def _fcurves(action):
    """Blender 4.4+ 的 action 把 fcurves 藏在 layers/strips/channelbags 裡。"""
    if hasattr(action, "fcurves"):
        return action.fcurves
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out


main()
