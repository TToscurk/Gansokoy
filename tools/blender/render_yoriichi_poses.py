"""渲染緣一骨架測試姿勢，供目視驗收。

姿勢皆為程式擺出（非手 K），用來檢查權重與形變：
  rest        T-pose 基準
  elbow       雙肘彎 90，看肘窩有無塌陷
  fist        握拳，看手指是否成形
  katana      握刀架勢（雙手併握、腰微扭）
  iai         居合拔刀前姿（右手腰際、左手扶鞘、腰扭）
"""
import math

import bpy
from mathutils import Euler, Quaternion, Vector

RIGGED = r"D:/神社/shrine/work/緣一_rigged.blend"
OUT = r"D:/神社/shrine/artifacts/yoriichi_rig/"
RES = (900, 1200)


def reset_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.location = Vector((0, 0, 0))
    bpy.context.view_layer.update()


def rot(arm, bone, x=0.0, y=0.0, z=0.0):
    """骨局部軸：Y=骨長軸（扭轉），X=彎曲軸，Z=側擺軸。"""
    pb = arm.pose.bones.get(bone)
    if not pb:
        return
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = Euler((math.radians(x), math.radians(y), math.radians(z)), "XYZ")


def curl_fingers(arm, side, deg=-75, thumb=-35):
    s = 1 if side == "Left" else -1
    for f in ("Index", "Middle", "Ring", "Pinky"):
        for i in (1, 2, 3):
            rot(arm, f"{side}Hand{f}{i}", x=deg * s)
    for i in (1, 2, 3):
        rot(arm, f"{side}HandThumb{i}", x=thumb * s)


def pose_rest(arm):
    pass


def pose_elbow(arm):
    rot(arm, "LeftForeArm", x=90)
    rot(arm, "RightForeArm", x=-90)


def pose_fist(arm):
    rot(arm, "LeftForeArm", x=75)
    curl_fingers(arm, "Left")
    curl_fingers(arm, "Right")


def pose_katana(arm):
    """雙手在身前併握：上臂由 T-pose 下放並前收，肘彎。"""
    rot(arm, "LeftArm", x=48, z=-62)
    rot(arm, "RightArm", x=-48, z=62)
    rot(arm, "LeftForeArm", x=72)
    rot(arm, "RightForeArm", x=-72)
    rot(arm, "LeftHand", y=-30)
    rot(arm, "RightHand", y=30)
    curl_fingers(arm, "Left", -80, -45)
    curl_fingers(arm, "Right", -80, -45)
    rot(arm, "Spine01", y=-8)
    rot(arm, "LeftUpLeg", x=-12)
    rot(arm, "RightUpLeg", x=10)


def pose_iai(arm):
    """居合拔刀前：腰扭、右手落腰際、左手扶鞘口。"""
    rot(arm, "Spine02", y=18)
    rot(arm, "Spine01", y=14)
    rot(arm, "Spine", y=8)
    rot(arm, "neck", y=-16)
    rot(arm, "RightArm", x=-62, z=58)
    rot(arm, "RightForeArm", x=-58)
    rot(arm, "RightHand", y=20)
    curl_fingers(arm, "Right", -82, -48)
    rot(arm, "LeftArm", x=55, z=-44)
    rot(arm, "LeftForeArm", x=78)
    rot(arm, "LeftHand", y=-25)
    curl_fingers(arm, "Left", -70, -40)
    rot(arm, "LeftUpLeg", x=-20, z=6)
    rot(arm, "LeftLeg", x=18)
    rot(arm, "RightUpLeg", x=16)
    rot(arm, "RightLeg", x=10)


POSES = {
    "1_rest": pose_rest,
    "2_elbow90": pose_elbow,
    "3_fist": pose_fist,
    "4_katana": pose_katana,
    "5_iai": pose_iai,
}


def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = RES
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"

    world = bpy.data.worlds.new("W")
    sc.world = world
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg is None:
        bg = world.node_tree.nodes.new("ShaderNodeBackground")
        out = next((n for n in world.node_tree.nodes if n.type == "OUTPUT_WORLD"), None)
        if out is None:
            out = world.node_tree.nodes.new("ShaderNodeOutputWorld")
        world.node_tree.links.new(bg.outputs[0], out.inputs[0])
    bg.inputs[0].default_value = (0.05, 0.05, 0.06, 1)
    bg.inputs[1].default_value = 1.0

    for nm, loc, rotd, energy in [
        ("key", (2.6, -3.4, 2.4), (66, 0, 38), 900),
        ("fill", (-3.0, -2.2, 1.6), (78, 0, -54), 320),
        ("rim", (0.4, 3.4, 2.6), (64, 0, 186), 600),
    ]:
        ld = bpy.data.lights.new(nm, "AREA")
        ld.energy = energy
        ld.size = 3.0
        lo = bpy.data.objects.new(nm, ld)
        lo.location = loc
        lo.rotation_euler = Euler([math.radians(a) for a in rotd], "XYZ")
        bpy.context.scene.collection.objects.link(lo)

    cd = bpy.data.cameras.new("Cam")
    cd.lens = 70
    cam = bpy.data.objects.new("Cam", cd)
    bpy.context.scene.collection.objects.link(cam)
    sc.camera = cam
    return cam


def aim(cam, target, dist, height, yaw_deg):
    a = math.radians(yaw_deg)
    cam.location = Vector((math.sin(a) * dist, -math.cos(a) * dist, height))
    d = Vector(target) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def main():
    import os
    bpy.ops.wm.open_mainfile(filepath=RIGGED)
    os.makedirs(OUT, exist_ok=True)
    arm = bpy.data.objects["Armature"]
    cam = setup_scene()

    shots = []
    for name, fn in POSES.items():
        reset_pose(arm)
        fn(arm)
        bpy.context.view_layer.update()

        views = [("front", 0.0)] if name in ("1_rest",) else [("front", 0.0), ("q34", 38.0)]
        if name == "3_fist":
            views = [("hand", 0.0)]

        for vn, yaw in views:
            if name == "3_fist":
                # 相機追手：從 pose 後的實際骨位取目標，不可寫死
                pb = arm.pose.bones["LeftHandMiddle1"]
                tgt = arm.matrix_world @ pb.head
                cam.data.lens = 85
                aim(cam, tgt, 0.40, float(tgt.z) + 0.03, 26.0)
            else:
                aim(cam, (0.0, 0.03, 1.02), 3.9, 1.18, yaw)
                cam.data.lens = 70
            p = os.path.join(OUT, f"{name}_{vn}.png")
            bpy.context.scene.render.filepath = p
            bpy.ops.render.render(write_still=True)
            shots.append(p)
            print("SHOT", p)
    print("SHOTS_DONE", len(shots))


if __name__ == "__main__":
    main()
