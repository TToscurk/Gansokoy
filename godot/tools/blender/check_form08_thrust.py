"""捌ノ型 陽華突 —— 量測驗收。

執行：
  blender --background --python tools/blender/check_form08_thrust.py

不是渲圖好看就算數。這支量的是**會不會出事**的數字：
  1. 腳底有沒有穿地／懸空（本專案的 rig 腳底基準 ≈ 0.03，見 animations/README）
  2. 水平 root motion 是不是真的 0（不是 0 就會和 CharacterBody3D 打架）
  3. 刀手（RightHand）的前伸距離 —— 突刺的「突」有沒有真的突出去
  4. 突刺爆發段的角速度 —— 太慢就不是「突然且快」
"""
import bpy
import os
from mathutils import Vector

GLB = r"D:/神社/shrine/godot/characters/yoriichi/anim_src/form08_thrust.glb"

FPS = 24
LAST = 30
# animations/README：本 rig 的腳底接觸基準（Walk 接觸幀實測 0.027~0.039）
FOOT_FLOOR = 0.031
FOOT_TOL = 0.045


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)

    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    scene = bpy.context.scene

    hips = arm.pose.bones.get("Hips")
    rhand = arm.pose.bones.get("RightHand")
    ltoe = arm.pose.bones.get("LeftToeBase")
    rtoe = arm.pose.bones.get("RightToeBase")

    print("=== 捌ノ型 陽華突 量測 ===")
    print(f"骨架 {arm.name}、{len(arm.data.bones)} 骨")
    print(f"動作數 {len(bpy.data.actions)}：{[a.name for a in bpy.data.actions]}")

    # ⚠ GLB 裡有兩個動作（源 FBX 的 walking_man ＋ 我做的 Form08）。
    #   匯入後預設綁上的不一定是哪一個 —— 必須顯式指定，否則量到的是走路。
    target = None
    for a in bpy.data.actions:
        if "Form08" in a.name or "Thrust" in a.name:
            target = a
            break
    if target is None:
        raise RuntimeError("GLB 裡找不到 Form08 動作")
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = target
    if hasattr(target, "slots") and len(target.slots) > 0:
        arm.animation_data.action_slot = target.slots[0]
    print(f"量測對象：{target.name}（幀 {target.frame_range[0]:.0f}~{target.frame_range[1]:.0f}）")

    rows = []
    for f in range(0, LAST + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        mw = arm.matrix_world

        hip_w = mw @ hips.head
        hand_w = mw @ rhand.head
        lt = (mw @ ltoe.head).z
        rt = (mw @ rtoe.head).z
        rows.append({
            "f": f,
            "hip": hip_w,
            "hand": hand_w,
            "foot_min": min(lt, rt),
        })

    # --- 1. 水平 root motion ---
    hx = [r["hip"].x for r in rows]
    hy = [r["hip"].y for r in rows]
    drift = max(max(hx) - min(hx), max(hy) - min(hy))
    print(f"\n[1] 水平 root motion 漂移 = {drift * 1000:.2f} mm "
          f"({'OK 可視為 0' if drift < 0.002 else '⚠ 有水平位移，會和程式位移打架'})")

    # --- 2. 腳底 ---
    fmin = min(r["foot_min"] for r in rows)
    fmax = max(r["foot_min"] for r in rows)
    worst = min(rows, key=lambda r: r["foot_min"])
    print(f"[2] 腳底最低 {fmin:.4f} m（第 {worst['f']} 幀）、最高 {fmax:.4f} m")
    if fmin < 0:
        print(f"    ⚠ 穿地 {abs(fmin)*100:.1f} cm")
    elif fmin > FOOT_TOL:
        print(f"    ⚠ 全程懸空，最低點仍有 {fmin*100:.1f} cm")
    else:
        print(f"    OK（基準 {FOOT_FLOOR:.3f}、容許 {FOOT_TOL:.3f}）")

    # --- 3. 刀手前伸 ---
    # ⚠ 角色面朝 **-Y**（probe_arm_axes 實測），所以「最伸」= y 最小、
    #   「最縮」= y 最大。第一版標籤寫反，看起來像突刺方向顛倒。
    hand_y = [r["hand"].y for r in rows]
    reach = max(hand_y) - min(hand_y)
    f_fwd = min(rows, key=lambda r: r["hand"].y)["f"]
    f_back = max(rows, key=lambda r: r["hand"].y)["f"]
    print(f"\n[3] 刀手前後行程 = {reach:.3f} m（最縮 f{f_back} → 最伸 f{f_fwd}）")
    if reach < 0.25:
        print("    ⚠ 行程太短，看起來不像突刺")
    else:
        print("    OK")

    # --- 4. 爆發速度 ---
    print("\n[4] 刀手逐幀位移（突刺段 f7→f12 應該最大）")
    for i in range(1, len(rows)):
        d = (rows[i]["hand"] - rows[i-1]["hand"]).length
        bar = "#" * int(d * 120)
        mark = ""
        if 8 <= rows[i]["f"] <= 12:
            mark = "  ← 突"
        elif rows[i]["f"] <= 7:
            mark = "  蓄"
        elif rows[i]["f"] <= 17:
            mark = "  留"
        print(f"    f{rows[i]['f']:>2}  {d*100:5.2f} cm  {bar}{mark}")

    # 突刺段 vs 收招段的速度比
    def seg_speed(a, b):
        tot = 0.0
        for i in range(1, len(rows)):
            if a < rows[i]["f"] <= b:
                tot += (rows[i]["hand"] - rows[i-1]["hand"]).length
        return tot / max(b - a, 1) * FPS

    v_thrust = seg_speed(7, 12)
    v_recover = seg_speed(17, 30)
    print(f"\n    突刺段均速 {v_thrust:.2f} m/s、收招段 {v_recover:.2f} m/s")
    print(f"    比值 {v_thrust / max(v_recover, 0.001):.1f}x "
          f"({'OK 爆發明確' if v_thrust > v_recover * 2.0 else '⚠ 突刺不夠突然'})")

    # --- 5. 留」段是否真的停住 ---
    hold = [ (rows[i]['hand'] - rows[i-1]['hand']).length
             for i in range(1, len(rows)) if 13 <= rows[i]['f'] <= 17 ]
    print(f"\n[5] 留段（f13-17）逐幀位移最大 {max(hold)*100:.2f} cm "
          f"({'OK 刀尖停得住' if max(hold) < 0.02 else '⚠ 刀尖還在飄'})")

    print("\n=== 量測完成 ===")


main()
