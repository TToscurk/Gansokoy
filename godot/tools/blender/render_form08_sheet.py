"""捌ノ型 陽華突 —— 關鍵幀連拍（驗收用）。

執行：
  blender --background --python tools/blender/render_form08_sheet.py

輸出 4 張側視圖到 anim_src/preview/：蓄 / 突 / 留 / 收。
側視是因為突刺是前後方向的動作 —— 正面看不出行程。
"""
import bpy
import os
import math
from mathutils import Vector

GLB = r"D:/神社/shrine/godot/characters/yoriichi/anim_src/form08_thrust.glb"
SWORD = r"D:/神社/shrine/godot/characters/yoriichi/yoriichi_sword.glb"
OUT_DIR = r"D:/神社/shrine/godot/characters/yoriichi/anim_src/preview"

# (幀, 標籤)
SHOTS = [(0, "00_kamae"), (7, "07_tame"), (12, "12_tsuki"), (17, "17_tome"), (30, "30_osame")]
RES = (700, 900)


def _attach_sword(arm):
    """把刀掛到 RightHand 骨上（對應 Godot 的 HandSocket）。"""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=SWORD)
    new = [o for o in bpy.data.objects if o not in before and o.parent is None]
    if not new:
        print("  [警告] 刀沒匯進來")
        return
    for o in new:
        o.parent = arm
        o.parent_type = 'BONE'
        o.parent_bone = "RightHand"
        # 骨頭 parent 以 tail 為原點；往回退一個骨長讓刀柄落在掌心
        o.matrix_parent_inverse = arm.pose.bones["RightHand"].matrix.inverted()
        print(f"  刀 {o.name} 已掛上 RightHand")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)

    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    act = next(a for a in bpy.data.actions if "Form08" in a.name)
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    if hasattr(act, "slots") and len(act.slots) > 0:
        arm.animation_data.action_slot = act.slots[0]

    # ⚠ 沒有刀就看不出是不是突刺（第一版渲圖的教訓：評審說「沒有武器、
    #   讀不出是劍術」）。刀在 Godot 端是掛 HandSocket 的獨立 GLB，
    #   這裡用 bone constraint 手動掛回 RightHand 才能驗收。
    _attach_sword(arm)

    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x, scene.render.resolution_y = RES
    scene.render.film_transparent = False
    sh = scene.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'SINGLE'
    sh.single_color = (0.62, 0.62, 0.66)
    sh.show_cavity = True
    # factory_settings(use_empty=True) 的場景沒有 world，要自己建
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.color = (0.09, 0.09, 0.11)

    # 側視鏡頭：角色面朝 -Y，相機放在 +X 看過去，才看得到突刺行程
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 2.6
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = Vector((4.2, -0.30, 0.95))
    cam.rotation_euler = (math.radians(90), 0, math.radians(90))
    scene.camera = cam

    os.makedirs(OUT_DIR, exist_ok=True)
    for frame, label in SHOTS:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        path = os.path.join(OUT_DIR, f"form08_{label}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print(f"  渲出 f{frame:>2} → {path}")

    print("完成")


main()
