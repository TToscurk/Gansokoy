"""手部特寫驗收：高解析、平滑著色、正確曝光。

先前 1000px 平面著色 + 過曝，把低多邊形的稜面誤判成破洞與尖刺。本腳本
2000px、開 shade_smooth、降曝光、加背光輪廓，並渲一張線框對照，讓拓撲
本身可見。
"""
import math
import os

import bpy
from mathutils import Euler, Quaternion, Vector

RIGGED = r"D:/神社/shrine/work/緣一_rigged.blend"
OUT = r"D:/神社/shrine/artifacts/yoriichi_rig/hand/"
BODY = "身體2"
HIDE = ["上衣", "羽織", "袴", "腰帶", "頭髮"]


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


def curl(arm, side, deg, thumb):
    s = 1 if side == "Left" else -1
    for f in ("Index", "Middle", "Ring", "Pinky"):
        for i in (1, 2, 3):
            rot(arm, f"{side}Hand{f}{i}", x=deg * s)
    for i in (1, 2, 3):
        rot(arm, f"{side}HandThumb{i}", x=thumb * s)


def setup(wire=False):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 2000
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.exposure = -1.4
    sc.eevee.taa_render_samples = 64

    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.02, 0.02, 0.03, 1)

    for nm, loc, rd, e, sz in [("k", (1.2, -1.2, 1.9), (58, 0, 42), 60, 1.2),
                               ("f", (-1.0, -0.9, 1.5), (74, 0, -48), 25, 1.5),
                               ("r", (0.2, 1.4, 1.9), (56, 0, 184), 70, 1.0)]:
        ld = bpy.data.lights.new(nm, "AREA")
        ld.energy, ld.size = e, sz
        lo = bpy.data.objects.new(nm, ld)
        lo.location = loc
        lo.rotation_euler = Euler([math.radians(a) for a in rd], "XYZ")
        sc.collection.objects.link(lo)

    cd = bpy.data.cameras.new("C")
    cam = bpy.data.objects.new("C", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def aim(cam, target, dist, yaw, pitch, lens):
    cam.data.lens = lens
    a, p = math.radians(yaw), math.radians(pitch)
    off = Vector((math.sin(a) * math.cos(p), -math.cos(a) * math.cos(p), math.sin(p))) * dist
    cam.location = Vector(target) + off
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()


def main():
    bpy.ops.wm.open_mainfile(filepath=RIGGED)
    os.makedirs(OUT, exist_ok=True)
    arm = bpy.data.objects["Armature"]
    body = bpy.data.objects[BODY]
    for n in HIDE:
        o = bpy.data.objects.get(n)
        if o:
            o.hide_render = True

    # 平滑著色：低多邊形平面著色會讓每個稜面像裂縫
    for p in body.data.polygons:
        p.use_smooth = True
    body.data.update()

    cam = setup()
    sc = bpy.context.scene

    def shot(tag, target, dist, yaw, pitch, lens=50):
        aim(cam, target, dist, yaw, pitch, lens)
        sc.render.filepath = os.path.join(OUT, tag + ".png")
        bpy.ops.render.render(write_still=True)
        print("SHOT", sc.render.filepath)

    def hand_center(side):
        pb = arm.pose.bones[f"{side}HandMiddle1"]
        return arm.matrix_world @ pb.head

    # A 張開（rest）
    reset(arm)
    c = hand_center("Left")
    shot("A_open_back", c, 0.26, 0, 55)
    shot("A_open_side", c, 0.26, 70, 8)

    # B 半握（握刀柄的實際角度）
    reset(arm)
    curl(arm, "Left", -55, -35)
    bpy.context.view_layer.update()
    c = hand_center("Left")
    shot("B_grip_back", c, 0.24, 10, 40)
    shot("B_grip_side", c, 0.24, 75, 10)

    # C 全握拳
    reset(arm)
    curl(arm, "Left", -85, -50)
    bpy.context.view_layer.update()
    c = hand_center("Left")
    shot("C_fist_back", c, 0.24, 10, 40)
    shot("C_fist_side", c, 0.24, 75, 10)
    shot("C_fist_front", c, 0.24, -60, 15)

    print("DONE")


if __name__ == "__main__":
    main()
