# 多層次卡通樹產生器 —— Blender headless 跑：
#   blender -b -P godot/assets/blender/make_trees.py -- godot/assets/models
#
# 風格定位（見 docs/art-style-notes.md）：吉卜力/低多邊形混合 ——
# 樹冠是「分層的雲朵」，每層一個色階（下暗上亮），flat shading 讓
# 每個面都是一塊乾淨的色面。顏色全部烤進頂點色（COLOR_0），
# Godot 端統一換上 vertex_color_use_as_albedo 的材質，不吃貼圖。
#
# 產出：tree_round_a / tree_round_b（闊葉，圓雲層）、tree_pine_a（杉，堆疊錐）
import bpy
import bmesh
import math
import random
import sys
import os

OUT_DIR = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "godot/assets/models"
os.makedirs(OUT_DIR, exist_ok=True)

BARK = (0.30, 0.23, 0.16)
# 樹冠層色：由下到上（暗 → 亮），帶一點黃綠偏移，吉卜力的「陽光打在樹頂」
TIERS_ROUND = [(0.13, 0.22, 0.11), (0.19, 0.30, 0.14), (0.26, 0.38, 0.17), (0.34, 0.46, 0.21)]
TIERS_PINE = [(0.10, 0.19, 0.12), (0.14, 0.25, 0.14), (0.19, 0.32, 0.16), (0.26, 0.40, 0.19)]


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def get_mat(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    return m


def assign_mat(obj, name):
    obj.data.materials.clear()
    obj.data.materials.append(get_mat(name))


def set_vertex_colors(obj, color_fn):
    """color_fn(world_co, normal) -> (r,g,b)。烤進 CORNER domain 的 COLOR_0。"""
    mesh = obj.data
    attr = mesh.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            v = mesh.vertices[mesh.loops[li].vertex_index]
            r, g, b = color_fn(v.co, poly.normal)
            attr.data[li].color = (r, g, b, 1.0)


def add_trunk(height, r_bot, r_top, lean=0.06, seed=0):
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=r_bot, radius2=r_top, depth=height,
                                    location=(0, 0, height / 2))
    obj = bpy.context.active_object
    # 微傾＋頂端隨機偏，看起來不像釘子
    obj.rotation_euler = (lean * rng.uniform(0.5, 1.5), 0, rng.uniform(0, 6.28))
    set_vertex_colors(obj, lambda co, n: BARK)
    assign_mat(obj, "bark")
    return obj


def add_cluster(center, radius, squash, tier_color, seed):
    """一層樹冠：低細分 icosphere 壓扁，頂點色 = 層色 × 高度漸層，底面壓暗。"""
    rng = random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=radius, location=center)
    obj = bpy.context.active_object
    obj.scale = (1 + rng.uniform(-0.12, 0.12), 1 + rng.uniform(-0.12, 0.12), squash)
    obj.rotation_euler = (0, 0, rng.uniform(0, 6.28))
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    r, g, b = tier_color
    cz, rad = center[2], radius * squash

    def col(co, n):
        # 層內漸層：頂亮底暗；朝下的面再壓一階（樹冠的陰影腹）
        t = max(0.0, min(1.0, (co.z - (cz - rad)) / (2 * rad)))
        k = 0.72 + 0.55 * t
        if n.z < -0.25:
            k *= 0.62
        return (min(1, r * k), min(1, g * k), min(1, b * k))

    set_vertex_colors(obj, col)
    assign_mat(obj, "foliage")
    return obj


def join_and_export(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    tree = bpy.context.active_object
    tree.name = name
    # flat shading：每個面一塊色面
    bpy.ops.object.shade_flat()
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_yup=True, export_apply=True)
    print("exported", path)


def tree_round(name, seed, h=3.2, spread=1.0):
    clear_scene()
    rng = random.Random(seed)
    objs = [add_trunk(h, 0.30, 0.16, seed=seed)]
    # 三圈環繞層 + 一顆頂冠：多層次的重點在「看得出一層一層」
    tiers = [
        (h + 0.1, 1.55 * spread, 2, TIERS_ROUND[0], TIERS_ROUND[1]),
        (h + 1.1, 1.30 * spread, 3, TIERS_ROUND[1], TIERS_ROUND[2]),
        (h + 2.0, 1.00 * spread, 2, TIERS_ROUND[2], TIERS_ROUND[3]),
    ]
    si = 0
    for (z, rad, count, c_lo, c_hi) in tiers:
        for k in range(count):
            si += 1
            a = rng.uniform(0, 6.28) + k * (6.28 / max(count, 1))
            d = rad * 0.55 if count > 1 else 0.0
            c = c_lo if k % 2 == 0 else c_hi
            objs.append(add_cluster((math.cos(a) * d, math.sin(a) * d, z),
                                    rad, rng.uniform(0.62, 0.72), c, seed * 31 + si))
    objs.append(add_cluster((0, 0, h + 2.7), 0.85 * spread, 0.7, TIERS_ROUND[3], seed * 31 + 99))
    join_and_export(objs, name)


def tree_pine(name, seed, h=3.2, layers=None):
    clear_scene()
    rng = random.Random(seed)
    layers = layers or TIERS_PINE
    objs = [add_trunk(h + 0.6, 0.26, 0.12, seed=seed)]
    # 四層堆疊錐，往上縮小變亮 —— 剪影就是「一棵杉樹」
    z = h * 0.8
    rad = 1.5
    for i, c in enumerate(layers):
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=rad, radius2=rad * 0.12,
                                        depth=1.7, location=(0, 0, z + 0.55))
        cone = bpy.context.active_object
        cone.rotation_euler = (0, 0, rng.uniform(0, 6.28))
        bpy.ops.object.transform_apply(rotation=True)
        r, g, b = c
        zc = z + 0.55

        def col(co, n, r=r, g=g, b=b, zc=zc):
            t = max(0.0, min(1.0, (co.z - (zc - 0.85)) / 1.7))
            k = 0.75 + 0.5 * t
            if n.z < -0.3:
                k *= 0.6
            return (min(1, r * k), min(1, g * k), min(1, b * k))

        set_vertex_colors(cone, col)
        assign_mat(cone, "foliage")
        objs.append(cone)
        z += 1.05
        rad *= 0.74
    join_and_export(objs, name)


tree_round("tree_round_a", 11, h=4.6)
tree_round("tree_round_b", 47, h=5.0)
tree_round("tree_round_c", 88, h=6.4, spread=0.72)      # 瘦高型，打破天際線
tree_pine("tree_pine_a", 23)
tree_pine("tree_pine_b", 61, h=4.6, layers=TIERS_PINE + [TIERS_PINE[-1]])  # 高杉五層
print("done")
