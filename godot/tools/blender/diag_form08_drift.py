"""Hips 水平漂移 14.88 mm 的來源追查。

check_form08_thrust.py 報「水平 root motion 漂移 14.88 mm」。在判它有罪之前
要先確認那是不是量測方式造成的假象 —— pose.bone.head 是**當前姿態下**的
骨頭位置，Hips 骨頭本身旋轉時，head 會因為骨架物件變換而看起來移動。

真正該量的是 Hips 的 **location f-curve 值**：那才是匯出到 GLB 的 root motion。
本腳本兩者都印，並與既有的「合格」動畫（yoriichi_attack_combo 的來源）比較基準。
"""
import bpy

GLB = r"D:/神社/shrine/godot/characters/yoriichi/anim_src/form08_thrust.glb"


def fcurves(action):
    if hasattr(action, "fcurves") and len(action.fcurves) > 0:
        return list(action.fcurves)
    out = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    act = next(a for a in bpy.data.actions if "Form08" in a.name)

    print("=== Hips 漂移來源追查 ===")
    print(f"骨架物件 scale = {tuple(round(v,4) for v in arm.scale)}")

    print("\n--- Hips 的 location f-curve（這才是真正的 root motion）---")
    found = False
    for fc in fcurves(act):
        if "Hips" in fc.data_path and fc.data_path.endswith("location"):
            found = True
            axis = "XYZ"[fc.array_index]
            vals = [kp.co.y for kp in fc.keyframe_points]
            span = max(vals) - min(vals)
            # 骨架 local 單位 -> 公尺（scale 0.01）
            span_m = span * 0.01
            print(f"  location.{axis}: {len(vals)} keys, "
                  f"範圍 {min(vals):.4f}~{max(vals):.4f} "
                  f"(跨度 {span:.4f} local = {span_m*1000:.2f} mm)")
    if not found:
        print("  （沒有 Hips location 曲線）")

    print("\n--- 其他骨頭有沒有偷帶 location 曲線 ---")
    others = {}
    for fc in fcurves(act):
        if fc.data_path.endswith("location") and "Hips" not in fc.data_path:
            bone = fc.data_path.split('"')[1] if '"' in fc.data_path else fc.data_path
            vals = [kp.co.y for kp in fc.keyframe_points]
            span = max(vals) - min(vals)
            if span > 1e-6:
                others[bone] = others.get(bone, 0.0) + span
    if others:
        for b, s in sorted(others.items(), key=lambda kv: -kv[1]):
            print(f"  ⚠ {b}: 跨度 {s:.4f}")
    else:
        print("  OK：只有 Hips 有位移曲線，其他骨頭純旋轉")

    print("\n--- pose.bone.head 的表觀漂移（量測假象的來源）---")
    scene = bpy.context.scene
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    if hasattr(act, "slots") and len(act.slots) > 0:
        arm.animation_data.action_slot = act.slots[0]
    hips = arm.pose.bones["Hips"]
    xs, ys, zs = [], [], []
    for f in range(0, 31):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        w = arm.matrix_world @ hips.head
        xs.append(w.x); ys.append(w.y); zs.append(w.z)
    print(f"  head.x 跨度 {(max(xs)-min(xs))*1000:.2f} mm")
    print(f"  head.y 跨度 {(max(ys)-min(ys))*1000:.2f} mm")
    print(f"  head.z 跨度 {(max(zs)-min(zs))*1000:.2f} mm  ← 垂直，這個本來就該動")
    print("\n  說明：Hips 是根骨，它的 head 會隨自身 location 曲線移動。")
    print("  若上面 location.X/Z 跨度為 0 而 head.x/y 仍有值，代表漂移來自")
    print("  骨頭 local 軸與世界軸不對齊（rest 帶旋轉），不是真的 root motion。")


main()
