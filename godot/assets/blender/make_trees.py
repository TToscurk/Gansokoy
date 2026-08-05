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
    # subdiv 2（320 面）：subdiv 1 的 80 面在近景是「一顆低模球」，
    # 跟 PBR 建築擺在一起打架（美術規格 §1.1）。翻倍後仍是 flat shading
    # 的塊面感，但塊小到看起來是「葉團」而不是「多面體」。
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=center)
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


def add_branch(base, tip, r, seed):
    """一根分枝：兩端掃掠的細圓錐。剪影裡看得到「樹幹分岔」，
    才不是棒棒糖（美術規格：加分枝、修剪影）。"""
    rng = random.Random(seed)
    dx, dy, dz = tip[0] - base[0], tip[1] - base[1], tip[2] - base[2]
    ln = math.sqrt(dx * dx + dy * dy + dz * dz)
    mid = ((base[0] + tip[0]) / 2, (base[1] + tip[1]) / 2, (base[2] + tip[2]) / 2)
    bpy.ops.mesh.primitive_cone_add(vertices=5, radius1=r, radius2=r * 0.45, depth=ln,
                                    location=mid)
    obj = bpy.context.active_object
    # 把 +z 轉到 base→tip 方向
    import mathutils
    obj.rotation_euler = mathutils.Vector((dx, dy, dz)).to_track_quat("Z", "X").to_euler()
    set_vertex_colors(obj, lambda co, n: BARK)
    assign_mat(obj, "bark")
    return obj


def tree_round(name, seed, h=3.2, spread=1.0):
    clear_scene()
    rng = random.Random(seed)
    # 主幹只到分岔點（0.62h），上面交給分枝 —— 一根圓錐直通樹頂就是棒棒糖
    fork = h * 0.62
    objs = [add_trunk(fork * 1.06, 0.30, 0.20, seed=seed)]
    # 3~4 根分枝，枝端就是外圈樹冠的中心 —— 樹冠「長在枝上」而不是浮著
    n_br = 3 + (seed % 2)
    branch_tips = []
    for k in range(n_br):
        a = rng.uniform(0, 6.28) + k * (6.28 / n_br)
        # ⚠ 枝端要**張開、放低**（d 0.9~1.6、z 比軸心冠低）。
        # 第一版 d 只到 0.95、z 全在 h 以上，七顆樹冠疊在同一個點 ——
        # 預覽照出來又是一顆球插在棍子上。樹冠的寬度來自枝端的水平距離。
        d = rng.uniform(0.95, 1.55) * spread
        # 枝端 z 壓在 0.72h~0.92h：樹冠底要蓋住分岔點（0.66h），
        # 不然幹與冠之間有一段裸縫（preview 抓到的）
        tip = (math.cos(a) * d, math.sin(a) * d, h * rng.uniform(0.72, 0.92))
        branch_tips.append(tip)
        objs.append(add_branch((0, 0, fork * 0.92), tip, 0.11, seed * 7 + k))
    si = 0
    # 枝端各掛一顆樹冠（低層用暗色）
    for k, tip in enumerate(branch_tips):
        si += 1
        c = TIERS_ROUND[1] if k % 2 == 0 else TIERS_ROUND[2]
        objs.append(add_cluster(tip, rng.uniform(1.05, 1.35) * spread,
                                rng.uniform(0.62, 0.72), c, seed * 31 + si))
    # ⚠ 軸心一定要有一顆，而且中心壓在分岔點上方 —— v1 的樹冠全在側面，
    # 樹幹頂端那截裸露在外（截圖裡的「縫」）
    objs.append(add_cluster((0, 0, h * 0.82), 1.50 * spread, 0.68,
                            TIERS_ROUND[0], seed * 31 + 88))
    objs.append(add_cluster((0, 0, h * 1.06), 1.15 * spread, 0.68,
                            TIERS_ROUND[2], seed * 31 + 97))
    objs.append(add_cluster((0, 0, h * 1.26), 0.85 * spread, 0.70,
                            TIERS_ROUND[3], seed * 31 + 99))
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


def bamboo_clump(name, seed, n_culm=7, h=9.0):
    """竹叢（遠景用）：5~9 根細直的稈 + 頂部小葉團。
    美術規格 §4：西南方是迷途竹林 —— 竹要**細、直、密、高**，
    跟闊葉樹的剪影完全不同才有辨識度。遠景資產，面數壓到最低
    （稈 5 邊形、葉團 subdiv 1）。"""
    clear_scene()
    rng = random.Random(seed)
    objs = []
    CULM = (0.32, 0.44, 0.20)          # 竹稈的黃綠
    CULM_DK = (0.22, 0.32, 0.15)
    for k in range(n_culm):
        a = rng.uniform(0, 6.28)
        d = rng.uniform(0.0, 1.1)
        hx, hz = math.cos(a) * d, math.sin(a) * d
        ch = h * rng.uniform(0.75, 1.1)
        bpy.ops.mesh.primitive_cone_add(vertices=5, radius1=0.09, radius2=0.055,
                                        depth=ch, location=(hx, hz, ch / 2))
        culm = bpy.context.active_object
        culm.rotation_euler = (rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), 0)
        cc = CULM if k % 2 == 0 else CULM_DK
        set_vertex_colors(culm, lambda co, n, c=cc: c)
        assign_mat(culm, "bark")
        objs.append(culm)
        # 頂部 2 顆小葉團（竹葉是稀疏的，不要做成闊葉樹冠）
        for j in range(2):
            objs.append(add_cluster(
                (hx + rng.uniform(-0.5, 0.5), hz + rng.uniform(-0.5, 0.5),
                 ch - 0.4 - j * 1.1),
                rng.uniform(0.55, 0.85), 0.5,
                TIERS_PINE[2] if j == 0 else TIERS_PINE[1], seed * 13 + k * 3 + j))
    join_and_export(objs, name)


tree_round("tree_round_a", 11, h=4.6)
tree_round("tree_round_b", 47, h=5.0)
tree_round("tree_round_c", 88, h=6.4, spread=0.72)      # 瘦高型，打破天際線
tree_pine("tree_pine_a", 23)
tree_pine("tree_pine_b", 61, h=4.6, layers=TIERS_PINE + [TIERS_PINE[-1]])  # 高杉五層
bamboo_clump("bamboo_a", 71)
bamboo_clump("bamboo_b", 137, n_culm=9, h=10.5)
print("done")
