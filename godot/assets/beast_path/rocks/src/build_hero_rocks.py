"""獸道 S04 Hero Rock 生成器（Blender 5.x，bpy + bmesh，純程序、可重現）。

用法（在 Blender 內）：
    exec(open(r"D:/神社/shrine/godot/assets/beast_path/rocks/src/build_hero_rocks.py", encoding="utf-8").read())
    export_all()        # 存 hero_rocks.blend 與 hero_rock_a/b/c.glb
輸出（rocks/）：
    hero_rocks.blend             三顆 Hero Rock 的原始檔（Z 向上、原點在底面中心）
    hero_rock_a.glb / b / c      匯入用 GLB（Y 向上、單一網格；Godot 端換成 bp_rock.tres 並重算頂點色）

設計：V1.1 的 RockBuilder 把所有岩石都做成「圓角方盒＋位移」→ 輪廓重複、像軟墊。Hero Rock 改用另一套語彙：
    岩塊堆疊——每個岩塊是一組隨機點的凸包（天然帶平整的節理面與銳利的稜），按層疊起、錯位、轉角、傾斜，
    再拼出懸挑、支撐岩、崩落的碎塊。塊與塊之間的交線就是裂隙／層界，不用位移雜訊去「假裝」。
    凸包面做 2 次細分後只加幾公分的起伏（面是平的，但不是玻璃）；Edge Split 30° 保留硬稜。
A：細高層狀岩柱（約 9 m）；B：兩段式寬肩岩體（約 6.5 m × 9 m，含懸挑）；C：兩片斜倚的薄岩板（約 7 m，頂端被縫分開）。
"""
import bpy, bmesh, math, random, os
from mathutils import Vector, Matrix, Euler, noise

OUT_DIR = r"D:/神社/shrine/godot/assets/beast_path/rocks"
os.makedirs(OUT_DIR, exist_ok=True)


def fbm(p, seed, octaves=3, lac=2.1, gain=0.5):
    v = 0.0
    a = 1.0
    f = 1.0
    for i in range(octaves):
        v += a * noise.noise(Vector((p.x * f + seed * 1.7, p.y * f - seed * 0.9, p.z * f + seed * 0.4)))
        a *= gain
        f *= lac
    return v


def hull_block(bm, c, size, yaw, tilt, rng, n_pts=15, squash=0.62, amp=0.07, seed=1):
    """凸包岩塊：n_pts 個點落在超橢球殼上（squash 越小越接近方塊），取凸包 → 細分 → 微起伏。"""
    pts = []
    for _ in range(n_pts):
        v = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
        if v.length < 1e-6:
            continue
        v.normalize()
        v = Vector((math.copysign(abs(v.x) ** squash, v.x), math.copysign(abs(v.y) ** squash, v.y), math.copysign(abs(v.z) ** squash, v.z)))
        v *= rng.uniform(0.86, 1.0)
        pts.append(Vector((v.x * size[0] * 0.5, v.y * size[1] * 0.5, v.z * size[2] * 0.5)))
    # 保證有明確的頂面與底面（岩塊疊起來要有可以靠的平面）
    for _ in range(4):
        pts.append(Vector((rng.uniform(-0.55, 0.55) * size[0] * 0.5, rng.uniform(-0.55, 0.55) * size[1] * 0.5, size[2] * 0.5 * rng.uniform(0.93, 1.0))))
        pts.append(Vector((rng.uniform(-0.6, 0.6) * size[0] * 0.5, rng.uniform(-0.6, 0.6) * size[1] * 0.5, -size[2] * 0.5 * rng.uniform(0.93, 1.0))))
    rot = Euler((math.radians(tilt[0]), math.radians(tilt[1]), math.radians(yaw)), 'XYZ').to_matrix()
    tb = bmesh.new()
    verts = [tb.verts.new(p) for p in pts]
    bmesh.ops.convex_hull(tb, input=verts)
    for v in list(tb.verts):                     # 凸包沒用到的內部點
        if not v.link_faces:
            tb.verts.remove(v)
    bmesh.ops.subdivide_edges(tb, edges=tb.edges[:], cuts=2, use_grid_fill=False)
    tb.normal_update()
    for v in tb.verts:
        n = fbm(v.co * 0.9, seed, 3)
        v.co += v.normal * n * amp
    for v in tb.verts:
        v.co = rot @ v.co + Vector(c)
    vmap = {}
    for v in tb.verts:
        vmap[v] = bm.verts.new(v.co)
    for f in tb.faces:
        try:
            bm.faces.new([vmap[v] for v in f.verts])
        except ValueError:
            pass
    tb.free()


def build_rock(name, blocks, seed, amp=0.07):
    rng = random.Random(seed)
    bm = bmesh.new()
    for i, b in enumerate(blocks):
        c, size, yaw, tilt = b[0], b[1], b[2], b[3]
        sq = b[4] if len(b) > 4 else 0.62
        hull_block(bm, c, size, yaw, tilt, rng, n_pts=15, squash=sq, amp=amp, seed=seed * 7 + i)
    bm.normal_update()
    minz = min(v.co.z for v in bm.verts)
    cx = sum(v.co.x for v in bm.verts) / len(bm.verts)
    cy = sum(v.co.y for v in bm.verts) / len(bm.verts)
    for v in bm.verts:
        v.co -= Vector((cx, cy, minz))
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for p_ in me.polygons:
        p_.use_smooth = True
    mod = ob.modifiers.new("EdgeSplit", 'EDGE_SPLIT')
    mod.split_angle = math.radians(30.0)
    mod.use_edge_angle = True
    mod.use_edge_sharp = False
    return ob


def clear_scene_objects():
    for ob in list(bpy.data.objects):
        if ob.type == 'MESH':
            bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


clear_scene_objects()

# (中心, 尺寸(w,d,h), yaw°, tilt(x°,y°)[, squash])
A = build_rock("hero_rock_a", [
    ((0.0, 0.0, 2.6), (5.6, 4.8, 5.4), 8, (2, -2), 0.64),
    ((0.1, 0.1, 6.9), (3.5, 3.1, 4.8), 24, (4, -3), 0.68),
    ((-2.0, -0.8, 3.4), (1.9, 2.5, 6.6), 6, (3, -7), 0.52),
    ((1.0, 1.5, 4.8), (2.2, 1.7, 5.8), -20, (-6, 4), 0.52),
    ((2.1, 1.0, 0.8), (2.4, 2.0, 1.7), 40, (8, 0), 0.62),
    ((-1.2, -2.1, 0.7), (2.0, 1.6, 1.4), -35, (6, 5), 0.62),
], seed=17)
B = build_rock("hero_rock_b", [
    ((0.0, 0.0, 2.8), (8.4, 6.2, 5.6), 4, (1, -1), 0.68),
    ((-2.0, 1.6, 4.6), (5.4, 4.4, 4.2), -14, (-3, 3), 0.70),
    ((-3.9, -1.8, 1.4), (3.4, 3.0, 2.8), -26, (4, 0), 0.64),
    ((3.6, 0.4, 1.6), (4.0, 3.4, 3.2), 12, (-4, 3), 0.66),
    ((0.6, 2.6, 3.4), (4.8, 2.6, 5.2), -8, (-3, 0), 0.60),
    ((-0.6, -3.3, 0.6), (2.5, 1.8, 1.3), 40, (6, 4), 0.62),
    ((4.8, -1.8, 0.6), (2.0, 1.6, 1.2), -22, (5, -6), 0.62),
], seed=31)
C = build_rock("hero_rock_c", [
    ((-1.2, 0.0, 3.6), (3.4, 2.0, 7.0), 0, (0, 12), 0.5),
    ((1.6, 0.4, 3.0), (3.0, 1.8, 6.0), 6, (0, -8), 0.5),
    ((0.2, -0.4, 1.6), (3.0, 2.2, 3.0), -12, (3, 3), 0.58),
    ((-3.2, 0.5, 0.8), (2.2, 1.8, 1.6), 30, (6, -4), 0.6),
    ((3.4, -0.8, 0.7), (2.0, 1.4, 1.4), -40, (10, 8), 0.6),
], seed=47)

# 材質（原始檔用；Godot 端換成 bp_rock.tres）
mat = bpy.data.materials.get("BP_HeroRock") or bpy.data.materials.new("BP_HeroRock")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
if bsdf:
    bsdf.inputs["Base Color"].default_value = (0.36, 0.34, 0.31, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.92
for ob in (A, B, C):
    ob.data.materials.clear()
    ob.data.materials.append(mat)
A.location = (-9.0, 0.0, 0.0)
B.location = (0.0, 0.0, 0.0)
C.location = (9.0, 0.0, 0.0)


def stats():
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in (A, B, C):
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        xs = [v.co.x for v in me.vertices]
        ys = [v.co.y for v in me.vertices]
        zs = [v.co.z for v in me.vertices]
        print("HERO", ob.name, "tris", len(me.loop_triangles), "verts", len(me.vertices), "bbox(m) %.2f x %.2f x %.2f" % (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)))
        ev.to_mesh_clear()


def export_all():
    """存 .blend，並逐顆輸出 GLB（只選該顆、套用修改器、Y 向上）。"""
    for ob in (A, B, C):
        ob.location = (0.0, 0.0, 0.0)
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, ob.name + ".glb"), export_format='GLB', use_selection=True,
                                  export_apply=True, export_yup=True, export_normals=True, export_texcoords=False,
                                  export_materials='EXPORT', export_cameras=False, export_lights=False)
    A.location = (-9.0, 0.0, 0.0)
    B.location = (0.0, 0.0, 0.0)
    C.location = (9.0, 0.0, 0.0)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "hero_rocks.blend"))
    print("exported:", sorted(f for f in os.listdir(OUT_DIR) if f.endswith((".glb", ".blend"))))


stats()
