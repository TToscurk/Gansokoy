"""右臂骨軸實測：突刺該繞哪一軸轉？

make_form08_thrust.py 的第一版**猜**「Z 軸旋轉 = 手臂前後擺」，渲圖顯示手臂
往後上方翹起，不是前刺 —— 猜錯了。本腳本用實驗確定正確軸向：
對 RightForeArm 分別繞 X/Y/Z 轉 +60°，量手掌往角色正前方（-Y）移動多少。
移動最多的那一軸，就是突刺的主軸。
"""
import bpy
import math
from mathutils import Quaternion, Vector

FBX = r"D:/神社/shrine/godot/characters/yoriichi/yoriichi_body.fbx"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=FBX)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')

    print("=== 右臂骨軸實測 ===")

    # rest 狀態下的參考點
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
    bpy.context.view_layer.update()

    rest_tips = {}
    for hn in ("RightHand", "LeftHand"):
        t = arm.matrix_world @ arm.pose.bones[hn].tail
        rest_tips[hn] = t.copy()
        print(f"rest 時 {hn} tail = ({t.x:.3f}, {t.y:.3f}, {t.z:.3f})")

    # 角色朝向：用雙肩連線的法線判定，而不是假設
    ls = arm.matrix_world @ arm.pose.bones["LeftShoulder"].head
    rs = arm.matrix_world @ arm.pose.bones["RightShoulder"].head
    print(f"左肩 x={ls.x:.3f}  右肩 x={rs.x:.3f}  → 手臂沿 ±X 展開")

    for bone in ["RightArm", "RightForeArm", "RightShoulder",
                 "LeftArm", "LeftForeArm", "LeftShoulder"]:
        print(f"\n--- {bone} ---")
        pb = arm.pose.bones[bone]
        # ⚠ 量左臂要看左手，不是右手（第一版只量右手，左臂結果會全是 0）
        probe_hand = arm.pose.bones["LeftHand" if bone.startswith("Left") else "RightHand"]
        results = {}
        for axis_name, axis in [("X", (1, 0, 0)), ("Y", (0, 1, 0)), ("Z", (0, 0, 1))]:
            for sign in (1, -1):
                for b2 in arm.pose.bones:
                    b2.rotation_quaternion = Quaternion((1, 0, 0, 0))
                pb.rotation_quaternion = Quaternion(Vector(axis), math.radians(60 * sign))
                bpy.context.view_layer.update()
                tip = arm.matrix_world @ probe_hand.tail
                d = tip - rest_tips[probe_hand.name]
                label = f"{axis_name}{'+' if sign > 0 else '-'}"
                results[label] = d
                print(f"  繞 {label}60°：手 tail 位移 "
                      f"Δx={d.x:+.3f} Δy={d.y:+.3f} Δz={d.z:+.3f}")

        # 突刺 = 往角色正前方伸。先找出哪個方向是「前」：
        # 角色面朝 -Y（FBX 匯入慣例，由 headfront 骨確認）
        best = min(results.items(), key=lambda kv: kv[1].y)
        print(f"  → 最往前（-Y）的是 {best[0]}，Δy={best[1].y:+.3f}")
        best_up = max(results.items(), key=lambda kv: kv[1].z)
        print(f"  → 最往上（+Z）的是 {best_up[0]}，Δz={best_up[1].z:+.3f}")

    # 確認角色面朝方向
    head = arm.pose.bones["Head"]
    hf = arm.pose.bones["headfront"]
    for b2 in arm.pose.bones:
        b2.rotation_quaternion = Quaternion((1, 0, 0, 0))
    bpy.context.view_layer.update()
    hw = arm.matrix_world @ head.head
    fw = arm.matrix_world @ hf.head  # noqa: E501
    facing = (fw - hw)
    print(f"\n=== 角色面朝方向（headfront - Head）= "
          f"({facing.x:+.3f}, {facing.y:+.3f}, {facing.z:+.3f}）")
    dom = max("xyz", key=lambda a: abs(getattr(facing, a)))
    print(f"    主軸 = {dom}，{'負' if getattr(facing, dom) < 0 else '正'}向")


main()
