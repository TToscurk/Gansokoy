"""耳飾特寫渲染（用於驗收貼圖是否正確貼合面板）。

在使用者開著的場景中執行，故：不改任何物件、不存檔，
渲染用的相機與燈用完即刪。
"""
import math
import os

import bpy
from mathutils import Euler, Vector

OUT = r"D:/神社/shrine/artifacts/yoriichi_earring/"
TMP = "_EARSHOT_"


def main():
    os.makedirs(OUT, exist_ok=True)
    sc = bpy.context.scene
    obj = bpy.data.objects.get("耳飾右")
    if obj is None:
        print("EARSHOT missing 耳飾右")
        return

    # 面板中心（世界座標）
    M = obj.matrix_world
    pts = [M @ v.co for v in obj.data.vertices]
    cx = sum(p.x for p in pts) / len(pts)
    cy = sum(p.y for p in pts) / len(pts)
    zs = [p.z for p in pts]
    # 面板在下半部
    cz = min(zs) + (max(zs) - min(zs)) * 0.35

    prev = {"engine": sc.render.engine,
            "rx": sc.render.resolution_x, "ry": sc.render.resolution_y,
            "cam": sc.camera, "vt": sc.view_settings.view_transform,
            "exp": sc.view_settings.exposure,
            "path": sc.render.filepath,
            "world": sc.world}

    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 900
    sc.render.resolution_y = 1400
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.exposure = -0.3

    w = bpy.data.worlds.new(TMP + "W")
    sc.world = w
    w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.04, 0.04, 0.05, 1)

    tmp = []
    for nm, loc, rd, e in [("k", (0.25, -0.35, 1.95), (70, 0, 34), 22),
                           ("f", (-0.3, -0.25, 1.75), (80, 0, -50), 8),
                           ("r", (0.05, 0.3, 1.9), (68, 0, 184), 16)]:
        ld = bpy.data.lights.new(TMP + nm, "AREA")
        ld.energy, ld.size = e, 0.5
        lo = bpy.data.objects.new(TMP + nm, ld)
        lo.location = loc
        lo.rotation_euler = Euler([math.radians(a) for a in rd], "XYZ")
        sc.collection.objects.link(lo)
        tmp.append(lo)

    cd = bpy.data.cameras.new(TMP + "C")
    cd.lens = 85
    cam = bpy.data.objects.new(TMP + "C", cd)
    sc.collection.objects.link(cam)
    tmp.append(cam)
    sc.camera = cam

    target = Vector((cx, cy, cz))
    for tag, yaw, dist in [("front", 0.0, 0.16), ("q34", 32.0, 0.17)]:
        a = math.radians(yaw)
        cam.location = target + Vector((math.sin(a) * dist,
                                        -math.cos(a) * dist, 0.01))
        cam.rotation_euler = (target - cam.location).to_track_quat(
            "-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(OUT, "earring_" + tag + ".png")
        bpy.ops.render.render(write_still=True)
        print("EARSHOT", sc.render.filepath)

    # 還原
    for o in tmp:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.worlds.remove(w)
    sc.render.engine = prev["engine"]
    sc.render.resolution_x, sc.render.resolution_y = prev["rx"], prev["ry"]
    sc.camera = prev["cam"]
    sc.view_settings.view_transform = prev["vt"]
    sc.view_settings.exposure = prev["exp"]
    sc.render.filepath = prev["path"]
    sc.world = prev["world"]
    print("EARSHOT restored")


main()
