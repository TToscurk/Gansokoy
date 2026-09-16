"""軀幹／頸／腿骨軸實測：受擊、格擋、硬直動畫該繞哪一軸轉？

probe_arm_axes.py 只量了手臂；受擊反應主要靠軀幹後仰與腿的踉蹌，
軸向一樣不能猜。對每根骨頭繞 X/Y/Z ±30°，量 Head（軀幹）／腳 tail（腿）
在世界座標的位移。角色面朝 -Y、+Z 為上。
"""
import bpy
import math
from mathutils import Quaternion, Vector

FBX = r"D:/神社/shrine/godot/characters/yoriichi/yoriichi_body.fbx"

PROBES = [
    ("Spine", "Head"), ("Spine01", "Head"), ("Spine02", "Head"),
    ("neck", "headfront"), ("Head", "headfront"),
    ("Hips", "Head"),
    ("LeftUpLeg", "LeftToeBase"), ("LeftLeg", "LeftToeBase"), ("LeftFoot", "LeftToeBase"),
    ("RightUpLeg", "RightToeBase"), ("RightLeg", "RightToeBase"), ("RightFoot", "RightToeBase"),
    ("RightHand", "RightHand"), ("LeftHand", "LeftHand"),
]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=FBX)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')

    def reset():
        for pb in arm.pose.bones:
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
            pb.location = Vector((0, 0, 0))
        bpy.context.view_layer.update()

    reset()
    print("=== 骨軸實測（+30°）===")
    for b in ("Hips", "Head", "LeftToeBase", "RightToeBase", "RightHand", "LeftHand"):
        p = arm.matrix_world @ arm.pose.bones[b].head
        print(f"rest {b} head = ({p.x:.3f}, {p.y:.3f}, {p.z:.3f})")

    for bone, probe in PROBES:
        pb = arm.pose.bones.get(bone)
        if pb is None:
            print(f"[缺] {bone}")
            continue
        reset()
        ref = (arm.matrix_world @ arm.pose.bones[probe].tail).copy()
        line = f"{bone:<12} → {probe:<13}"
        for axis_name, axis in (("X", (1, 0, 0)), ("Y", (0, 1, 0)), ("Z", (0, 0, 1))):
            reset()
            pb.rotation_quaternion = Quaternion(Vector(axis), math.radians(30))
            bpy.context.view_layer.update()
            d = (arm.matrix_world @ arm.pose.bones[probe].tail) - ref
            line += f"  {axis_name}+: dx{d.x:+.3f} dy{d.y:+.3f} dz{d.z:+.3f}"
        print(line)
    print("（面朝 -Y：dy 負 = 往前；dz 正 = 往上；dx = 側向）")


main()
