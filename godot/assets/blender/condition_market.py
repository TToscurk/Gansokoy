# 市集資產調校：去重 + 減面，輸出到 godot/assets/market/
#   blender -b -P godot/assets/blender/condition_market.py -- <src_dir> <out_dir>
#
# 使用者的 Meshy 市集組面數嚴重超標（屋台蔬果攤 974k、陶瓷 860k、絲綢 606k，
# 連一片布的旗子都有 647k）。對照：一棵樹 11k、整片 222 棵樹合計 240 萬面。
# 廣場要擺 15-20 攤，不減面會是一千萬面。
#
# 另外 屋台絲綢攤/平台絲綢攤、屋台陶瓷攤/平台陶瓷攤 二進位完全相同（MD5 一致），
# 只匯入 屋台 版本，平台 版本跳過。
import bpy, sys, os, shutil

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]

# 檔名 -> 目標面數；None = 原樣複製（本來就在預算內）
PLAN = {
    "屋台絲綢攤.glb": 22000,
    "屋台蔬果攤.glb": 22000,
    "屋台陶瓷攤.glb": 22000,
    "旗子紅色.glb": 8000,
    "旗子藍色.glb": 8000,
    "平台攤蔬菜.glb": None,
    "水井.glb": None,
    "雜物堆木桶.glb": None,
    "雜物堆瓢盆.glb": None,
    "雜物草捆.glb": None,
}
# 與上面某檔二進位相同，不重複匯入
SKIP = ["平台絲綢攤.glb", "平台陶瓷攤.glb"]


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for d in list(blk):
            if d.users == 0:
                blk.remove(d)


def tri_count():
    n = 0
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            ob.data.calc_loop_triangles()
            n += len(ob.data.loop_triangles)
    return n


os.makedirs(OUT, exist_ok=True)
for name, target in PLAN.items():
    src = os.path.join(SRC, name)
    dst = os.path.join(OUT, name)
    if not os.path.exists(src):
        print("MISSING %s" % name)
        continue
    if target is None:
        shutil.copyfile(src, dst)
        print("COPY   %-16s (已在預算內)" % name)
        continue
    clear()
    bpy.ops.import_scene.gltf(filepath=src)
    before = tri_count()
    ratio = min(1.0, float(target) / max(before, 1))
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        m = ob.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = ratio
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=m.name)
    after = tri_count()
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB")
    print("DECIM  %-16s %7d -> %6d  (ratio %.4f)" % (name, before, after, ratio))

for name in SKIP:
    print("SKIP   %-16s 與已匯入檔二進位相同" % name)
print("done")
