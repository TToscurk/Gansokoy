"""Yoriichi rig 偵察：匯入 FBX，把骨架、骨名、rest 姿態、既有動作全部印出來。

執行：
  blender --background --python tools/blender/probe_yoriichi_rig.py

唯讀 —— 只讀不寫，不碰任何來源檔。
"""
import bpy
import sys
from mathutils import Vector

FBX = r"D:/神社/shrine/godot/characters/yoriichi/yoriichi_body.fbx"


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def main():
    clear()
    print("=== Yoriichi rig 偵察 ===")
    print("Blender", bpy.app.version_string)

    bpy.ops.import_scene.fbx(filepath=FBX)

    arms = [o for o in bpy.data.objects if o.type == 'ARMATURE']
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    print(f"\n骨架 {len(arms)} 個、網格 {len(meshes)} 個")

    for a in arms:
        print(f"\n--- 骨架 {a.name} ---")
        print(f"  物件 scale = {tuple(round(v, 4) for v in a.scale)}")
        print(f"  物件 rotation_euler = {tuple(round(v, 4) for v in a.rotation_euler)}")
        bones = a.data.bones
        print(f"  骨頭數 = {len(bones)}")
        print(f"\n  {'骨名':<22} {'父':<20} {'head(世界)':<34} 長度")
        for b in bones:
            head = a.matrix_world @ b.head_local
            parent = b.parent.name if b.parent else "-"
            print(f"  {b.name:<22} {parent:<20} "
                  f"({head.x:7.3f},{head.y:7.3f},{head.z:7.3f})  {b.length:.4f}")

        # 角色整體尺寸
        zs = [(a.matrix_world @ b.head_local).z for b in bones]
        print(f"\n  骨架 Z 範圍：{min(zs):.3f} ~ {max(zs):.3f}  (高約 {max(zs)-min(zs):.3f} m)")

    for m in meshes:
        bb = [m.matrix_world @ Vector(c) for c in m.bound_box]
        xs = [v.x for v in bb]; ys = [v.y for v in bb]; zs = [v.z for v in bb]
        print(f"\n--- 網格 {m.name} ---")
        print(f"  尺寸 X {max(xs)-min(xs):.3f} / Y {max(ys)-min(ys):.3f} / Z {max(zs)-min(zs):.3f} m")
        print(f"  Z 範圍 {min(zs):.3f} ~ {max(zs):.3f}")
        print(f"  頂點 {len(m.data.vertices)}、面 {len(m.data.polygons)}")
        print(f"  頂點群組 {len(m.vertex_groups)}")

    print(f"\n--- FBX 內含動作 {len(bpy.data.actions)} 個 ---")
    for act in bpy.data.actions:
        rng = act.frame_range
        print(f"  {act.name:<40} 幀 {rng[0]:.0f}~{rng[1]:.0f}  曲線 {len(act.fcurves)}")

    print("\n=== 偵察完成 ===")


main()
