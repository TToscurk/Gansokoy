# 散佈用樹木產生器 —— Blender headless 跑：
#   blender -b -P godot/assets/blender/make_trees.py -- godot/assets/models
#
# ⚠ 骨架**不在這裡**，在 `tree_lib.py`（跟稗田邸的楓／松同一份）。
# 這支只負責：品種參數 → 灌進 Blender mesh → 匯出 glb。
#
# 為什麼：這支的舊版是「圓錐樹幹 + 疊 2~3 顆壓扁的 icosphere」，也就是
# 稗田邸花了八版才修掉的那個棒棒糖 —— 而那八版的修正從來沒有回流過來。
# 於是每開一張新圖、每加一種新樹（人間之里的櫻、背景綠樹），棒棒糖就
# 再生一次。兩份合併之後樹的骨架只有一個實作，修一次全圖都吃得到。
#
# 產出：tree_round_a/b/c（闊葉）、tree_pine_a/b（杉）、
#       tree_sakura_a/b（花樹）、bamboo_a/b（竹叢，遠景）
#
# ── 材質槽 ──
# 每個 glb 一定要有 **兩個 surface**：0=bark、1=foliage。
# Godot 端靠 surface 索引分材質（gen_lib.tree_mesh 給樹冠貼森林貼圖、
# gen_town._sakura_mesh 給花冠**無貼圖雙面頂點色**）。合成一個 surface
# 的話兩邊都會把整棵樹當樹冠 —— 花樹會被森林貼圖乘成濁褐色（粉×綠）。
import bpy
import math
import random
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tree_lib as T

OUT_DIR = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "godot/assets/models"
os.makedirs(OUT_DIR, exist_ok=True)

SLOTS = ("bark", "foliage")


class MeshB:
    """tree_lib 的 builder：累積 tri/quad，依材質槽分面，最後灌進 bpy mesh。

    每張面自己一個色（BYTE_COLOR/CORNER 的 "Col"，linear）—— 跟專案其他
    產生器的慣例一致，Godot 端統一 vertex_color_use_as_albedo。"""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.cols = []
        self.mats = []
        self.slot = 0

    def use(self, slot):
        self.slot = SLOTS.index(slot)

    def tri(self, a, b, c, col, flip=False):
        i = len(self.verts)
        self.verts += [a, c, b] if flip else [a, b, c]
        self.faces.append((i, i + 1, i + 2))
        self.cols.append(col)
        self.mats.append(self.slot)

    def quad(self, a, b, c, d, col, flip=False):
        self.tri(a, b, c, col, flip)
        self.tri(a, c, d, col, flip)

    def tri2(self, a, b, c, col):
        """雙面三角形（葉片專用）：CULL_DISABLED 只讓背面畫得出來，照明用的
        還是原法線，背面會全黑（make_hedge.py 踩過的坑）—— 正反各給一張
        自己的面才是真的雙面。"""
        self.tri(a, b, c, col)
        self.tri(a, b, c, col, flip=True)

    def build(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        me.update()
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        # ⚠ 槽的加入順序就是匯出後 surface 的順序 —— bark 一定要是 0。
        for s in SLOTS:
            m = bpy.data.materials.get(s) or bpy.data.materials.new(s)
            ob.data.materials.append(m)
        attr = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        for fi, poly in enumerate(me.polygons):
            r, g, b = self.cols[fi]
            for li in poly.loop_indices:
                attr.data[li].color = (r, g, b, 1.0)
            poly.material_index = self.mats[fi]
            poly.use_smooth = False        # flat shading：每張面一塊乾淨色面
        return ob


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def export(ob, name):
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_yup=True, export_apply=True)
    print("exported %s（%d 面）" % (path, len(ob.data.polygons)))


def make_tree(name, cfg, h, seed):
    clear_scene()
    b = MeshB()
    T.build_tree(b, 0.0, 0.0, h, seed, cfg)
    ob = b.build(name)
    export(ob, name)


def make_bamboo(name, seed, n_culm=7, h=9.0):
    """竹叢（遠景用）：5~9 根細直的稈 + 稈上的葉。
    美術規格 §4：西南方是迷途竹林 —— 竹要**細、直、密、高**，跟闊葉樹的
    剪影完全不同才有辨識度。竹**不分枝**，所以不走 build_tree 的骨架，
    但葉子用同一支 leaf_tuft —— 舊版拿 icosphere 當葉團，那是最後一處
    球狀樹冠，一起拆掉。"""
    clear_scene()
    rng = random.Random(seed)
    b = MeshB()
    C_CULM = (0.255, 0.290, 0.150)
    C_LEAF_LO = (0.150, 0.235, 0.110)
    C_LEAF_HI = (0.320, 0.430, 0.180)
    for k in range(n_culm):
        a = rng.uniform(0.0, math.tau)
        rr = rng.uniform(0.0, 1.05)
        bx, by = math.cos(a) * rr, math.sin(a) * rr
        ch = h * rng.uniform(0.75, 1.08)
        lean = rng.uniform(0.02, 0.08)
        laz = rng.uniform(0.0, math.tau)
        # 稈：微彎的細管（5 節），上細下粗
        pts, rad = [], []
        for i in range(6):
            t = i / 5.0
            pts.append((bx + math.cos(laz) * lean * ch * t * t,
                        by + math.sin(laz) * lean * ch * t * t, ch * t))
            rad.append(0.070 * (1.0 - t * 0.42))
        b.use("bark")
        T.tube(b, pts, rad, C_CULM, sides=5)
        # 葉：上三分之一，稀疏 —— 竹葉是一撮一撮掛在節上的
        b.use("foliage")
        for _ in range(int(13 * (0.6 + rng.random() * 0.8))):
            t = rng.uniform(0.60, 1.0)
            p = pts[min(4, int(t * 5))]
            off = (rng.gauss(0, 0.34), rng.gauss(0, 0.34), rng.gauss(0, 0.30))
            org = (p[0] + off[0], p[1] + off[1], p[2] + off[2])
            nrm = T.norm3((off[0], off[1], off[2] * 0.5 + 0.35))
            T.leaf_tuft(b, rng, org, nrm, 0.46, C_LEAF_LO, C_LEAF_HI, n_leaf=2)
    ob = b.build(name)
    export(ob, name)


# 闊葉三變體：差在**骨架比例**不是只換 seed（只換 seed 的話統計輪廓一樣，
# 遠看仍是同一棵複製貼上）。b 是 vista／大量散佈用的精簡版。
make_tree("tree_round_a", T.FOREST_ROUND, 4.6, 11)
make_tree("tree_round_b", T.FOREST_FAR, 5.0, 47)
make_tree("tree_round_c", T.FOREST_TALL, 6.4, 88)      # 瘦高型，打破天際線
make_tree("tree_pine_a", T.FOREST_PINE, 5.4, 23)
make_tree("tree_pine_b", dict(T.FOREST_PINE, ntuft=420), 6.8, 61)
# 花樹：骨架同源、花色與灰樹皮由 profile 帶。
# ⚠ 花冠的材質路徑在 Godot 端（gen_town._sakura_mesh：無貼圖雙面頂點色）。
# 這裡只要保證 foliage 是 surface 1，那條路徑就不會被動到。
make_tree("tree_sakura_a", T.SAKURA, 4.4, 19)
make_tree("tree_sakura_b", dict(T.SAKURA, ang=(0.62, 1.10), up=(0.38, 0.14, -0.04),
                                fol=0.078, ntuft=400), 5.2, 53)
make_bamboo("bamboo_a", 71)
make_bamboo("bamboo_b", 137, n_culm=9, h=10.5)
print("done")
