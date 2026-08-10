# 單一模型預覽（Blender headless）：
#   blender -b -P godot/assets/blender/preview.py -- hedge_a
#   blender -b -P godot/assets/blender/preview.py -- hedge_a hedge_b rock_a
#   blender -b -P godot/assets/blender/preview.py -- hedge_a --out /tmp/x.png
#
# ⚠ **做新資產的第一件事是先跑這支。**
#
# v16 的生垣花了兩個小時，其中約 100 分鐘是在等 Godot 重算整張村子 ——
# 只為了看一個 2.4 公尺的東西長怎樣。而且村裡的預設時刻是 17:5x 斜陽，
# 一半的角度是背光的，模型看起來全黑，害我兩次以為是材質壞了。
#
# 真正的問題全部在模型本身，用這支 10 秒就看得出來：
#   ・整條樹籬是躺著的（Blender 是 Z-up，我用 Y-up 建模）
#   ・鏡射面法線朝內（整片黑）
#   ・枝葉撒不到側面（殼露出來）
#
# 所以：**先在這裡看對了，再進 Godot。** 進 Godot 是為了驗「擺得對不對」，
# 不是為了驗「模型長得對不對」。
#
# 這台機器的限制：EEVEE 不能用（缺 libEGL），所以走 CYCLES + CPU，
# 而且要關 denoising（build without OpenImageDenoiser）。
import bpy
import math
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import blender_compat as BC   # shader nodes by TYPE, not by (localized) name

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out_path = None
if "--out" in argv:
    i = argv.index("--out")
    out_path = argv[i + 1]
    argv = argv[:i] + argv[i + 2:]
names = argv or ["hedge_a"]

MODEL_DIR = "godot/assets/models"
OUT_DIR = os.environ.get("PREVIEW_DIR", "/tmp/asset_preview")
os.makedirs(OUT_DIR, exist_ok=True)


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def vertex_color_mat():
    """用頂點色當 albedo —— 專案的 Blender 資產都走頂點色
    （Godot 端對應 lib.vc_mat() / lib.foliage_vc_mat()）。"""
    m = bpy.data.materials.new("preview_vc")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = BC.principled(m)
    ca = nt.nodes.new("ShaderNodeVertexColor")
    ca.layer_name = "Col"
    nt.links.new(ca.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return m


def setup_stage(size):
    """地面 + 天空 + 太陽。太陽放在**鏡頭同側**——
    背光的預覽圖看不出任何東西（v16 就是這樣浪費了兩輪）。"""
    bpy.ops.mesh.primitive_plane_add(size=size * 20.0, location=(0, 0, 0))
    gp = bpy.data.materials.new("ground")
    gp.use_nodes = True
    BC.principled(gp).inputs["Base Color"].default_value = (0.22, 0.28, 0.13, 1)
    bpy.context.active_object.data.materials.append(gp)

    bpy.ops.object.light_add(type="SUN")
    sun = bpy.context.object
    sun.data.energy = 4.0
    sun.data.angle = math.radians(2.0)
    sun.rotation_euler = (math.radians(52), 0, math.radians(38))

    w = BC.background(bpy.context.scene.world)
    w.inputs[0].default_value = (0.42, 0.55, 0.76, 1)
    w.inputs[1].default_value = 1.2


def frame(obj, angle_deg, size):
    """把相機擺到能框住整個物件的距離 —— 手調相機是 v16 另一個時間黑洞。
    可用環境變數換視角：PREVIEW_YAW（度，預設 35）、PREVIEW_ELEV（0~1，
    預設 0.85 = 高角俯視；0.15 左右是人視角低角）。"""
    yaw = float(os.environ.get("PREVIEW_YAW", angle_deg))
    elev = float(os.environ.get("PREVIEW_ELEV", 0.85))
    d = size * 2.1
    a = math.radians(yaw)
    h = size * elev
    bpy.ops.object.camera_add(location=(math.sin(a) * d, -math.cos(a) * d, max(h, 1.2)))
    cam = bpy.context.object
    # 俯角照高度算，低角時接近水平
    pitch = math.radians(90) - math.atan2(h - size * 0.35, d)
    cam.rotation_euler = (pitch, 0, a)
    bpy.context.scene.camera = cam
    return cam


def preview(name):
    clear()
    path = os.path.join(MODEL_DIR, name + ".glb")
    if not os.path.exists(path):
        print("!! 找不到 %s" % path)
        return
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("!! %s 裡沒有 mesh" % name)
        return
    mat = vertex_color_mat()
    tris = 0
    dims = [0.0, 0.0, 0.0]
    for o in meshes:
        o.data.materials.clear()
        o.data.materials.append(mat)
        tris += len(o.data.loop_triangles) or len(o.data.polygons)
        for k in range(3):
            dims[k] = max(dims[k], o.dimensions[k])
    size = max(dims) or 1.0
    setup_stage(size)
    frame(meshes[0], 35.0, size)

    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 40
    sc.cycles.use_denoising = False          # 這個 build 沒有 OpenImageDenoiser
    sc.render.resolution_x = 900
    sc.render.resolution_y = 560
    sc.render.filepath = out_path or os.path.join(OUT_DIR, name + ".png")
    bpy.ops.render.render(write_still=True)
    # 尺寸與面數一起印出來 —— 「這東西到底多大」是最常問的問題
    print("預覽 %s → %s ｜ %.2f × %.2f × %.2f m ｜ %d 面"
          % (name, sc.render.filepath, dims[0], dims[1], dims[2], tris))


for n in names:
    preview(n)
print("done")
