"""反應動畫組 —— 量測 + 連拍（驗收用）。

由 make_react_clips.py 在匯出前呼叫 measure_and_render(arm, actions)：
GLB 不帶 skin（export_skins=False），回讀後骨頭變成 Empty，量不到也渲不到，
所以量測必須在建 clip 的同一個 session、網格還掛在骨架上時做。

每個 clip：
  1. 水平 root motion 漂移（必須 ≈ 0）
  2. 腳底最低／最高（基準 0.031、容許 0.045；Stagger 允許沉但不准穿地）
  3. 特徵量：Head 前後／上下位移、RightHand 位移（撥開行程）、Hips 下沉
  4. 側視＋3/4 視連拍，刀掛 RightHand，輸出 anim_src/preview/react_<clip>_<frame>.png
"""
import bpy
import math
import os
from mathutils import Vector

GLB = r"D:/神社/shrine/godot/characters/yoriichi/anim_src/react_clips.glb"
SWORD = r"D:/神社/shrine/godot/characters/yoriichi/yoriichi_sword.glb"
OUT_DIR = r"D:/神社/shrine/godot/characters/yoriichi/anim_src/preview"
FOOT_FLOOR, FOOT_TOL = 0.031, 0.045

SHOTS = {
    "Guard_Hold":   [0, 6, 12],
    "Block_Impact": [0, 2, 8],
    "Deflect":      [0, 2, 5, 10],
    "Hit_React":    [0, 2, 5, 10],
    "Stagger":      [0, 5, 20, 48],
}


def attach_sword(arm):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=SWORD)
    new = [o for o in bpy.data.objects if o not in before and o.parent is None]
    for o in new:
        o.parent = arm
        o.parent_type = 'BONE'
        o.parent_bone = "RightHand"
        o.matrix_parent_inverse = arm.pose.bones["RightHand"].matrix.inverted()


def setup_render(scene):
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x, scene.render.resolution_y = 560, 800
    sh = scene.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'SINGLE'
    sh.single_color = (0.62, 0.62, 0.66)
    sh.show_cavity = True
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.color = (0.09, 0.09, 0.11)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 2.4
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def cam_side(cam):
    cam.location = Vector((4.2, -0.10, 0.95))
    cam.rotation_euler = (math.radians(90), 0, math.radians(90))


def cam_front34(cam):
    # 角色面朝 -Y：相機放 -Y 偏 +X，看向原點
    cam.location = Vector((2.6, -3.4, 1.0))
    d = Vector((0, 0, 0.95)) - cam.location
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()


def measure_and_render(arm, actions):
    for tr in arm.animation_data.nla_tracks:
        tr.mute = True
    attach_sword(arm)
    scene = bpy.context.scene
    cam = setup_render(scene)
    os.makedirs(OUT_DIR, exist_ok=True)

    P = arm.pose.bones
    for pb in P:
        pb.matrix_basis.identity()
    arm.animation_data.action = None
    bpy.context.view_layer.update()
    rest_hip_z = (arm.matrix_world @ P["Hips"].head).z
    print("=== 反應動畫組 量測 ===")
    print(f"rest Hips z = {rest_hip_z:.4f}")
    print(f"動作：{[a.name for a in bpy.data.actions]}")

    for act in actions:
        if act.name not in SHOTS:
            continue
        for pb in P:
            pb.matrix_basis.identity()
        arm.animation_data.action = act
        if hasattr(act, "slots") and len(act.slots) > 0:
            arm.animation_data.action_slot = act.slots[0]
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        rows = []
        for f in range(f0, f1 + 1):
            scene.frame_set(f)
            bpy.context.view_layer.update()
            mw = arm.matrix_world
            rows.append({
                "f": f,
                "hip": mw @ P["Hips"].head,
                "head": mw @ P["Head"].head,
                "hand": mw @ P["RightHand"].head,
                "foot": min((mw @ P["LeftToeBase"].head).z, (mw @ P["RightToeBase"].head).z),
            })
        hx = [r["hip"].x for r in rows]; hy = [r["hip"].y for r in rows]
        drift = max(max(hx) - min(hx), max(hy) - min(hy))
        fmin = min(rows, key=lambda r: r["foot"]); fmax = max(r["foot"] for r in rows)
        hz0 = rows[0]["hip"].z; hzmin = min(r["hip"].z for r in rows)
        head0 = rows[0]["head"]
        head_dy = [(r["head"].y - head0.y) for r in rows]
        head_dz = [(r["head"].z - head0.z) for r in rows]
        hand0 = rows[0]["hand"]
        hand_d = [(r["hand"] - hand0) for r in rows]
        hand_reach = max(v.length for v in hand_d)
        f_hand = max(rows, key=lambda r: (r["hand"] - hand0).length)["f"]
        print(f"\n[{act.name}] f{f0}-{f1} ({(f1 - f0) / 24:.2f} s)")
        print(f"  水平 root 漂移 {drift * 1000:.2f} mm  {'OK' if drift < 0.002 else '⚠'}")
        print(f"  Hips f0 z = {hz0:.4f}（相對 rest {hz0 - rest_hip_z:+.4f}）← Godot 端 z_shift")
        fl = "穿地 ⚠" if fmin["foot"] < 0 else ("懸空 ⚠" if fmin["foot"] > FOOT_TOL else "OK")
        print(f"  腳底 最低 {fmin['foot']:.4f}@f{fmin['f']}、最高 {fmax:.4f}  {fl}")
        print(f"  Hips 下沉 最大 {hz0 - hzmin:.3f} m")
        print(f"  Head 前後 [{min(head_dy):+.3f}, {max(head_dy):+.3f}] m（負=往前）、上下 [{min(head_dz):+.3f}, {max(head_dz):+.3f}] m")
        print(f"  RightHand 最大位移 {hand_reach:.3f} m @f{f_hand}  Δ=({hand_d[f_hand - f0].x:+.2f}, {hand_d[f_hand - f0].y:+.2f}, {hand_d[f_hand - f0].z:+.2f})")
        # 每個連拍幀的刀手位置（相對 f0；-Y = 角色正前、+X = 角色左手側、+Z = 上）
        for f in SHOTS[act.name]:
            d = hand_d[min(max(f - f0, 0), len(hand_d) - 1)]
            print(f"    f{f:02d} RightHand Δ=({d.x:+.2f}, {d.y:+.2f}, {d.z:+.2f})  腳底 {rows[min(max(f - f0, 0), len(rows) - 1)]['foot']:.3f}")

        for f in SHOTS[act.name]:
            scene.frame_set(f)
            bpy.context.view_layer.update()
            for tag, fn in (("side", cam_side), ("f34", cam_front34)):
                fn(cam)
                path = os.path.join(OUT_DIR, f"react_{act.name}_{f:02d}_{tag}.png")
                scene.render.filepath = path
                bpy.ops.render.render(write_still=True)
        print(f"  渲出 {SHOTS[act.name]} × side/f34")
    print("\n=== 完成 ===")
