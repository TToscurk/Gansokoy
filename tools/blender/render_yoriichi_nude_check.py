"""裸身形變驗收：隱藏衣物，直接看骨架對身體的形變品質。

外層羽織袖子會完全蓋住肘與手，穿著渲染無法驗收關節。本腳本只渲身體，
並用骨位動態定位相機，確保主體入框。
"""
import math
import os

import bpy
from mathutils import Euler, Quaternion, Vector

RIGGED = r"D:/神社/shrine/work/緣一_rigged.blend"
OUT = r"D:/神社/shrine/artifacts/yoriichi_rig/nude/"
BODY = "身體2"
CLOTHES = ["上衣", "羽織", "袴", "腰帶", "頭髮"]


def reset(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
    bpy.context.view_layer.update()


def rot(arm, bone, x=0.0, y=0.0, z=0.0):
    pb = arm.pose.bones.get(bone)
    if not pb:
        return
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = Euler((math.radians(x), math.radians(y), math.radians(z)), "XYZ")


def curl(arm, side, deg=-80, thumb=-45):
    s = 1 if side == "Left" else -1
    for f in ("Index", "Middle", "Ring", "Pinky"):
        for i in (1, 2, 3):
            rot(arm, f"{side}Hand{f}{i}", x=deg * s)
    for i in (1, 2, 3):
        rot(arm, f"{side}HandThumb{i}", x=thumb * s)


def setup():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1000, 1000
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.exposure = -0.6

    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.08, 0.08, 0.09, 1)

    for nm, loc, rd, e in [("k", (2.2, -2.8, 2.2), (64, 0, 38), 400),
                           ("f", (-2.6, -1.8, 1.5), (76, 0, -56), 150),
                           ("r", (0.3, 2.8, 2.2), (62, 0, 186), 260)]:
        ld = bpy.data.lights.new(nm, "AREA")
        ld.energy, ld.size = e, 3.0
        lo = bpy.data.objects.new(nm, ld)
        lo.location = loc
        lo.rotation_euler = Euler([math.radians(a) for a in rd], "XYZ")
        sc.collection.objects.link(lo)

    cd = bpy.data.cameras.new("C")
    cam = bpy.data.objects.new("C", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def aim(cam, target, dist, yaw, pitch=0.0, lens=70):
    cam.data.lens = lens
    a, p = math.radians(yaw), math.radians(pitch)
    off = Vector((math.sin(a) * math.cos(p), -math.cos(a) * math.cos(p), math.sin(p))) * dist
    cam.location = Vector(target) + off
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()


def bone_head(arm, n):
    return arm.matrix_world @ arm.pose.bones[n].head


def main():
    bpy.ops.wm.open_mainfile(filepath=RIGGED)
    os.makedirs(OUT, exist_ok=True)
    arm = bpy.data.objects["Armature"]
    for n in CLOTHES:
        o = bpy.data.objects.get(n)
        if o:
            o.hide_render = True
    cam = setup()
    sc = bpy.context.scene
    shots = []

    def shot(tag, target, dist, yaw, pitch=0.0, lens=70):
        aim(cam, target, dist, yaw, pitch, lens)
        p = os.path.join(OUT, tag + ".png")
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        shots.append(p)
        print("SHOT", p)

    # 1 rest 全身
    reset(arm)
    shot("1_rest", (0, 0.03, 0.95), 3.2, 0)

    # 2 肘彎 90：對準肘，側視最能看關節
    reset(arm)
    rot(arm, "LeftForeArm", x=90)
    rot(arm, "RightForeArm", x=-90)
    bpy.context.view_layer.update()
    shot("2_elbow90_body", (0, 0.03, 1.30), 2.0, 0)
    shot("2_elbow90_closeL", tuple(bone_head(arm, "LeftForeArm")), 0.55, -60, 10, 60)

    # 3 握拳：相機追手
    reset(arm)
    rot(arm, "LeftForeArm", x=70)
    curl(arm, "Left")
    curl(arm, "Right")
    bpy.context.view_layer.update()
    h = bone_head(arm, "LeftHand")
    shot("3_fist_closeL", tuple(h), 0.30, 20, 18, 55)
    shot("3_fist_wide", tuple(h), 0.75, 20, 12, 55)

    # 4 腕轉 90（麻花檢查）
    reset(arm)
    rot(arm, "LeftHand", y=90)
    bpy.context.view_layer.update()
    shot("4_twist90", tuple(bone_head(arm, "LeftForeArm")), 0.60, -50, 12, 60)

    # 5 居合架勢（裸身，看肩腰肘鏈）
    reset(arm)
    rot(arm, "Spine02", y=18)
    rot(arm, "Spine01", y=14)
    rot(arm, "Spine", y=8)
    rot(arm, "RightArm", x=-62, z=58)
    rot(arm, "RightForeArm", x=-58)
    curl(arm, "Right", -82, -48)
    rot(arm, "LeftArm", x=55, z=-44)
    rot(arm, "LeftForeArm", x=78)
    curl(arm, "Left", -70, -40)
    rot(arm, "LeftUpLeg", x=-20, z=6)
    rot(arm, "LeftLeg", x=18)
    rot(arm, "RightUpLeg", x=16)
    rot(arm, "RightLeg", x=10)
    bpy.context.view_layer.update()
    shot("5_iai_front", (0, 0.03, 0.95), 3.0, 0)
    shot("5_iai_q34", (0, 0.03, 0.95), 3.0, 40)

    # 6 膝彎 90
    reset(arm)
    rot(arm, "LeftLeg", x=-90)
    bpy.context.view_layer.update()
    shot("6_knee90", (0.15, 0.03, 0.55), 1.6, 70)

    print("DONE", len(shots))


if __name__ == "__main__":
    main()
