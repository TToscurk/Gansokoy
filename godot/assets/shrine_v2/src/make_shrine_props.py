"""博麗神社 r3 小型資產（Blender headless）：賽錢箱、板倉（小倉庫）、掃帚。
  D:/Blender/blender-5.2.1-windows-x64/blender.exe -b -P godot/assets/shrine_v2/src/make_shrine_props.py -- <out_dir> <src_dir>
產出 <out_dir>/{saisen_box,storehouse,broom}.glb ＋ <src_dir>/shrine_props_r3.blend
座標：Blender Z 上；正面朝 -Y（匯出後＝Godot +Z，即「正面+z」慣例）。單位公尺，原點＝底面中心。
UV 一律以世界公尺投影（1 UV = 1 m），紋理走向由 grain 軸決定；材質只留名稱，Godot 端依名稱掛專案貼圖
（見 tools/shrine_v2/build_props.gd 的 MATS），避免在 GLB 裡重複內嵌貼圖。
賽錢箱規格依 docs/reference/神社/賽錢箱.png：長:深:高 ≈ 2:0.9:1、短腳、頂部 10 根前後向厚木格柵、
古銅四角護角與腳套、正面二つ巴徽、側面「奉納」。
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Euler

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = args[0] if len(args) > 0 else "godot/assets/shrine_v2/props"
SRC = args[1] if len(args) > 1 else "godot/assets/shrine_v2/src"
os.makedirs(OUT, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


class B:
    """bmesh 累積器：一個資產一個 mesh，多材質槽。"""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()
        self.mats = []

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _finish(self, faces, mat, grain, uvs, mode="world"):
        mi = self.mi(mat)
        for f in faces:
            f.material_index = mi
            f.normal_update()
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            others = [i for i in range(3) if i != ax]
            if grain in others:
                u_ax = grain
                v_ax = [i for i in others if i != grain][0]
            else:
                u_ax, v_ax = others
            for lp in f.loops:
                co = lp.vert.co
                lp[self.uv].uv = (co[u_ax] * uvs, co[v_ax] * uvs)

    def box(self, size, loc, mat, grain=0, rot=(0, 0, 0), bevel=0.0, uvs=1.0):
        bm = self.bm
        old = set(bm.faces)
        g = bmesh.ops.create_cube(bm, size=1.0)
        verts = g["verts"]
        bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
        if bevel > 0:
            edges = list({e for v in verts for e in v.link_edges})
            bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, profile=0.5, affect="EDGES")
        faces = [f for f in bm.faces if f not in old]
        verts = list({v for f in faces for v in f.verts})
        if any(abs(a) > 1e-9 for a in rot):
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Euler(rot).to_matrix(), verts=verts)
        bmesh.ops.translate(bm, vec=Vector(loc), verts=verts)
        self._finish(faces, mat, grain, uvs)

    def cyl(self, r1, r2, h, loc, mat, seg=12, axis="z", grain=2, uvs=1.0):
        bm = self.bm
        g = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r1, radius2=r2, depth=h)
        verts = g["verts"]
        faces = list({f for v in verts for f in v.link_faces})
        if axis == "x":
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Euler((0, math.pi / 2, 0)).to_matrix(), verts=verts)
        elif axis == "y":
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Euler((math.pi / 2, 0, 0)).to_matrix(), verts=verts)
        bmesh.ops.translate(bm, vec=Vector(loc), verts=verts)
        self._finish(faces, mat, grain, uvs)

    def prism(self, pts, x0, thick, mat, grain=2, uvs=1.0):
        """沿 x 方向擠出的多邊形（y,z 平面），x0 起、厚 thick。pts 逆時針（由 +x 看）。"""
        bm = self.bm
        v0 = [bm.verts.new((x0, y, z)) for (y, z) in pts]
        v1 = [bm.verts.new((x0 + thick, y, z)) for (y, z) in pts]
        faces = [bm.faces.new(v0[::-1]), bm.faces.new(v1)]
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            faces.append(bm.faces.new((v0[i], v0[j], v1[j], v1[i])))
        bmesh.ops.recalc_face_normals(bm, faces=faces)
        self._finish(faces, mat, grain, uvs)

    def quad(self, p, mat, uvs_rect=(0, 0, 1, 1)):
        """給定 4 個 3D 點的貼花四邊形，UV 0..1（左下→右上）。"""
        bm = self.bm
        vs = [bm.verts.new(q) for q in p]
        f = bm.faces.new(vs)
        f.material_index = self.mi(mat)
        uv = [(0, 0), (1, 0), (1, 1), (0, 1)]
        for lp, t in zip(f.loops, uv):
            lp[self.uv].uv = t
        f.normal_update()

    def build(self, collection=None):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-6)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        for m in self.mats:
            mat = bpy.data.materials.get(m) or bpy.data.materials.new(m)
            me.materials.append(mat)
        ob = bpy.data.objects.new(self.name, me)
        (collection or bpy.context.scene.collection).objects.link(ob)
        for p in me.polygons:
            p.use_smooth = False
        return ob


def set_mat_look(name, color, metallic=0.0, rough=0.85, tex=None, alpha=False):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    if tex:
        img = bpy.data.images.load(tex)
        node = m.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = img
        m.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha:
            m.node_tree.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
            m.blend_method = "BLEND" if hasattr(m, "blend_method") else None
    return m


# ───────────────────────── 賽錢箱 ─────────────────────────
def saisen_box():
    b = B("SaisenBox")
    W, D, H = 1.70, 0.78, 0.86            # 長 深 高（含短腳）
    P = 0.11                              # 角柱邊長
    FOOT = 0.10
    hx, hy = W / 2, D / 2
    # 腳套（古銅）＋角柱（深木）
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * (hx - P / 2), sy * (hy - P / 2)
            b.box((P + 0.012, P + 0.012, FOOT), (cx, cy, FOOT / 2), "bronze", bevel=0.006)
            b.box((P, P, H - FOOT), (cx, cy, FOOT + (H - FOOT) / 2), "wood_dark", grain=2, bevel=0.004)
    # 下框（地覆）與上框（桁）
    inner_x, inner_y = W - 2 * P, D - 2 * P
    for sy in (-1, 1):
        b.box((inner_x, 0.10, 0.12), (0, sy * (hy - 0.05), FOOT + 0.16), "wood_dark", grain=0, bevel=0.004)
        b.box((inner_x, 0.11, 0.14), (0, sy * (hy - 0.055), H - 0.07), "wood_dark", grain=0, bevel=0.005)
    for sx in (-1, 1):
        b.box((0.10, inner_y, 0.12), (sx * (hx - 0.05), 0, FOOT + 0.16), "wood_dark", grain=1, bevel=0.004)
        b.box((0.11, inner_y, 0.14), (sx * (hx - 0.055), 0, H - 0.07), "wood_dark", grain=1, bevel=0.005)
    # 壁板：直向木板，內縮於框後方
    z0, z1 = FOOT + 0.22, H - 0.14
    ph = z1 - z0
    nb = 8
    bw = inner_x / nb
    for sy in (-1, 1):                                  # 前後
        for i in range(nb):
            x = -inner_x / 2 + bw * (i + 0.5)
            b.box((bw - 0.004, 0.035, ph), (x, sy * (hy - 0.075), (z0 + z1) / 2), "wood_dark", grain=2, bevel=0.002)
    nb2 = 4
    bw2 = inner_y / nb2
    for sx in (-1, 1):                                  # 兩側
        for i in range(nb2):
            y = -inner_y / 2 + bw2 * (i + 0.5)
            b.box((0.035, bw2 - 0.004, ph), (sx * (hx - 0.075), y, (z0 + z1) / 2), "wood_dark", grain=2, bevel=0.002)
    # 內部暗箱（從格柵看進去不見底）
    b.box((inner_x - 0.02, inner_y - 0.02, 0.50), (0, 0, FOOT + 0.31), "dark_inside")
    # 頂部格柵：10 根前後向厚木條
    ns = 10
    sw = 0.078
    gap = (inner_x - ns * sw) / (ns - 1)
    for i in range(ns):
        x = -inner_x / 2 + sw / 2 + i * (sw + gap)
        b.box((sw, inner_y + 0.02, 0.075), (x, 0, H - 0.0375 - 0.01), "wood_dark", grain=1, bevel=0.005)
    # 古銅四角護角（頂面＋兩側折彎）＋鉚釘
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * (hx - 0.115), sy * (hy - 0.115)
            b.box((0.23, 0.23, 0.014), (cx, cy, H + 0.007), "bronze", bevel=0.003)
            b.box((0.014, 0.23, 0.20), (sx * (hx + 0.005), cy, H - 0.10), "bronze", bevel=0.003)
            b.box((0.23, 0.014, 0.20), (cx, sy * (hy + 0.005), H - 0.10), "bronze", bevel=0.003)
            for k in range(3):
                rx = cx - sx * (0.07 - 0.07 * k) if False else cx + sx * (-0.06 + 0.06 * k)
                b.cyl(0.013, 0.010, 0.010, (rx, cy + sy * 0.0, H + 0.019), "bronze", seg=8)
            for k in range(2):
                b.cyl(0.012, 0.009, 0.010, (sx * (hx + 0.013), cy + sy * (-0.05 + 0.05 * k), H - 0.06 - 0.06 * k),
                      "bronze", seg=8, axis="x")
    # 前角柱的曲邊包片（簡化成長條片）
    for sx in (-1, 1):
        b.box((0.118, 0.012, 0.30), (sx * (hx - P / 2), -hy - 0.002, FOOT + 0.42), "bronze", bevel=0.003)
        b.box((0.118, 0.012, 0.18), (sx * (hx - P / 2), -hy - 0.002, FOOT + 0.20), "bronze", bevel=0.003)
    # 正面二つ巴徽：古銅外圈＋貼圖圓盤
    ez = (z0 + z1) / 2 + 0.02
    b.cyl(0.175, 0.175, 0.022, (0, -hy + 0.045, ez), "bronze", seg=28, axis="y")
    # 徽面（有貼圖）：朝 -Y 的圓盤用 24 邊形 fan
    r = 0.150
    cy_face = -hy + 0.045 - 0.0115
    bm = b.bm
    ctr = bm.verts.new((0, cy_face, ez))
    ring = [bm.verts.new((r * math.cos(2 * math.pi * i / 32), cy_face, ez + r * math.sin(2 * math.pi * i / 32))) for i in range(32)]
    mi = b.mi("emblem")
    for i in range(32):
        f = bm.faces.new((ctr, ring[i], ring[(i + 1) % 32]))
        f.material_index = mi
        for lp in f.loops:
            co = lp.vert.co
            lp[b.uv].uv = (0.5 + (co.x) / (2 * r), 0.5 + (co.z - ez) / (2 * r))
    # 側面「奉納」貼花：兩側板外面各一張（朝外，UV 左下→右上對應觀看者的左下→右上）
    tw, th = 0.10, 0.20
    for sx in (1, -1):
        xs = sx * (hx - 0.075 + 0.0185)
        if sx > 0:      # 站在 +X 看向 -X：右 = +Y
            pts = [(xs, -tw, ez - th), (xs, tw, ez - th), (xs, tw, ez + th), (xs, -tw, ez + th)]
        else:           # 站在 -X 看向 +X：右 = -Y
            pts = [(xs, tw, ez - th), (xs, -tw, ez - th), (xs, -tw, ez + th), (xs, tw, ez + th)]
        b.quad(pts, "hono_engraved")
    return b


# ───────────────────────── 板倉 ─────────────────────────
def storehouse():
    b = B("Storehouse")
    Wx, Dy = 3.6, 2.7
    hx, hy = Wx / 2, Dy / 2
    Fz = 0.62                        # 地板面高
    Wb, Wt = Fz - 0.10, 2.77         # 牆底 / 牆頂
    # 束石：8 顆，略不規則
    import random
    rnd = random.Random(11)
    for x in (-1.55, 0.0, 1.55):
        for y in (-1.05, 1.05):
            rr = 0.17 + rnd.uniform(-0.02, 0.025)
            b.cyl(rr, rr * 0.88, 0.46, (x + rnd.uniform(-0.02, 0.02), y, 0.23), "stone_foot", seg=9, uvs=1.0)
    for x in (-1.55, 1.55):
        b.cyl(0.17, 0.15, 0.46, (x, 0.0, 0.23), "stone_foot", seg=9)
    # 土台（地覆）＋地板
    for sy in (-1, 1):
        b.box((Wx, 0.14, 0.12), (0, sy * (hy - 0.07), 0.46), "wood_dark", grain=0, bevel=0.006)
    for sx in (-1, 1):
        b.box((0.14, Dy - 0.28, 0.12), (sx * (hx - 0.07), 0, 0.46), "wood_dark", grain=1, bevel=0.006)
    b.box((Wx - 0.1, Dy - 0.1, 0.09), (0, 0, Fz - 0.045), "wood_dark", grain=0)
    # 牆板（直板張り）：正面左右＋門上、背面、兩側
    tkn = 0.07
    door_w, door_top = 1.40, 2.32
    fl = (hx - door_w / 2)
    # 前牆
    b.box((fl, tkn, Wt - Wb), (-(hx - fl / 2), -hy + tkn / 2, (Wb + Wt) / 2), "plank", grain=2)
    b.box((fl, tkn, Wt - Wb), ((hx - fl / 2), -hy + tkn / 2, (Wb + Wt) / 2), "plank", grain=2)
    b.box((door_w, tkn, Wt - door_top), (0, -hy + tkn / 2, (door_top + Wt) / 2), "plank", grain=2)
    # 背牆與兩側
    b.box((Wx, tkn, Wt - Wb), (0, hy - tkn / 2, (Wb + Wt) / 2), "plank", grain=2)
    for sx in (-1, 1):
        b.box((tkn, Dy - 2 * tkn, Wt - Wb), (sx * (hx - tkn / 2), 0, (Wb + Wt) / 2), "plank", grain=2)
    # 押縁（縦の見切り）：每 0.62 m 一條
    def battens_front(xs_list):
        for x in xs_list:
            b.box((0.05, 0.03, Wt - Wb - 0.05), (x, -hy - 0.015, (Wb + Wt) / 2), "wood_dark", grain=2, bevel=0.003)
    battens_front([-1.65, -1.25, -0.85, 0.85, 1.25, 1.65])
    for x in (-1.2, -0.6, 0.0, 0.6, 1.2):
        b.box((0.05, 0.03, Wt - Wb - 0.05), (x, hy + 0.015, (Wb + Wt) / 2), "wood_dark", grain=2, bevel=0.003)
    for sx in (-1, 1):
        for y in (-0.9, -0.45, 0.0, 0.45, 0.9):
            b.box((0.03, 0.05, Wt - Wb - 0.05), (sx * (hx + 0.015), y, (Wb + Wt) / 2), "wood_dark", grain=2, bevel=0.003)
    # 腰の横桟（下端と上端の押さえ）
    for sy in (-1, 1):
        b.box((Wx + 0.04, 0.04, 0.07), (0, sy * (hy + 0.02), Wb + 0.05), "wood_dark", grain=0, bevel=0.003)
        b.box((Wx + 0.04, 0.04, 0.07), (0, sy * (hy + 0.02), Wt - 0.06), "wood_dark", grain=0, bevel=0.003)
    # 桁（軒桁）
    for sy in (-1, 1):
        b.box((Wx + 0.04, 0.15, 0.17), (0, sy * (hy + 0.01), Wt + 0.085), "wood_dark", grain=0, bevel=0.006)
    # 戸枠 ＋ 両開き板戸 ＋ 閂
    jamb = 0.09
    for sx in (-1, 1):
        b.box((jamb, 0.10, door_top - Fz), (sx * (door_w / 2 + jamb / 2 - 0.005), -hy - 0.02, (Fz + door_top) / 2), "wood_dark", grain=2, bevel=0.004)
    b.box((door_w + 2 * jamb, 0.10, 0.10), (0, -hy - 0.02, door_top + 0.05), "wood_dark", grain=0, bevel=0.004)
    b.box((door_w + 2 * jamb, 0.11, 0.08), (0, -hy - 0.02, Fz + 0.04), "wood_dark", grain=0, bevel=0.004)
    b.box((door_w, 0.02, door_top - Fz), (0, -hy + 0.045, (Fz + door_top) / 2), "dark_inside")     # 門縫後的暗面
    leaf_w = (door_w - 0.05) / 2
    for sx in (-1, 1):
        b.box((leaf_w, 0.05, door_top - Fz - 0.12), (sx * (leaf_w / 2 + 0.0125), -hy - 0.005, (Fz + 0.08 + door_top - 0.02) / 2), "plank", grain=2)
        for z in (Fz + 0.35, door_top - 0.32):
            b.box((leaf_w - 0.06, 0.03, 0.09), (sx * (leaf_w / 2 + 0.0125), -hy - 0.04, z), "wood_dark", grain=0, bevel=0.003)
    b.box((door_w + 0.14, 0.045, 0.06), (0, -hy - 0.07, 1.42), "iron", grain=0, bevel=0.003)           # 閂
    for sx in (-1, 1):
        b.box((0.10, 0.012, 0.16), (sx * (door_w / 2 + 0.07), -hy - 0.098, 1.42), "iron", bevel=0.003)
    # 石の踏み台（2段）
    b.box((1.8, 0.55, 0.20), (0, -hy - 0.60, 0.10), "stone_foot", grain=0, bevel=0.012)
    b.box((1.6, 0.42, 0.20), (0, -hy - 0.25, 0.41 - 0.10 + 0.10), "stone_foot", grain=0, bevel=0.012)
    # 屋根：切妻（棟は x 方向）。勾配 27°、軒の出 前後 0.55 / 妻 0.40
    ang = math.radians(27.0)
    zt = Wt + 0.17                       # 桁天端
    over_y, over_x = 0.55, 0.40
    half_run = hy + over_y
    L = half_run / math.cos(ang)
    ridge_z = zt + hy * math.tan(ang) + 0.07
    slab_t = 0.14
    for sy in (-1, 1):
        cy = sy * half_run / 2
        cz = zt + (hy - half_run / 2) * math.tan(ang) + 0.07 - 0.0
        # 傾斜スラブ：x 軸まわりに回転（前面 -y は下り）
        b.box((Wx + 2 * over_x, L, slab_t), (0, cy, cz - slab_t / 2 + 0.07), "roof_tile", grain=0,
              rot=(-sy * ang * -1.0 if False else sy * ang, 0, 0), bevel=0.004, uvs=0.9)
    # 棟瓦
    b.cyl(0.13, 0.13, Wx + 2 * over_x + 0.06, (0, 0, ridge_z + 0.02), "roof_ridge", seg=10, axis="x", grain=0)
    for sx in (-1, 1):
        b.box((0.10, 0.34, 0.30), (sx * (hx + over_x + 0.02), 0, ridge_z + 0.02), "roof_ridge", bevel=0.01)   # 鬼瓦代わり
    # 鼻隠し（軒先の化粧板）と破風板
    for sy in (-1, 1):
        ez_ = zt + (hy - half_run) * math.tan(ang) + 0.07 - slab_t - 0.01
        b.box((Wx + 2 * over_x + 0.04, 0.05, 0.13), (0, sy * (half_run + 0.0), ez_ + 0.05), "wood_dark", grain=0, bevel=0.004)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((0.05, L + 0.04, 0.15), (sx * (hx + over_x + 0.005), sy * half_run / 2,
                  zt + (hy - half_run / 2) * math.tan(ang) + 0.07 - 0.0 - slab_t * 0.35), "wood_dark", grain=1,
                  rot=(sy * ang, 0, 0), bevel=0.004)
    # 妻壁（三角部）
    for sx in (-1, 1):
        x0 = sx * (hx - tkn) if sx < 0 else (hx - tkn)
        b.prism([(-hy, Wt), (hy, Wt), (hy, zt), (0, ridge_z - 0.1), (-hy, zt)], x0, tkn, "plank", grain=2)
    return b


# ───────────────────────── 掃帚 ─────────────────────────
def broom():
    import random
    rnd = random.Random(5)
    b = B("Broom")
    b.cyl(0.014, 0.014, 1.38, (0, 0, 0.69), "bamboo", seg=8, grain=2)
    # 掃頭：18 束草稈，從束口向下外張，末端不齊
    n = 44
    for k in range(n):
        a = 2 * math.pi * k / n + rnd.uniform(-0.12, 0.12)
        ln = 0.40 + rnd.uniform(-0.06, 0.03)
        spread = 0.095 + rnd.uniform(-0.02, 0.03)
        tilt = math.atan2(spread, ln)
        cx = math.cos(a) * (0.012 + spread * 0.5) * (0.55 + 0.45 * rnd.random())
        cy = math.sin(a) * (0.012 + spread * 0.5) * (0.55 + 0.45 * rnd.random())
        bm = b.bm
        old = set(bm.faces)
        g = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=4, radius1=0.011, radius2=0.0055, depth=ln)
        vs = g["verts"]
        # 傾斜：繞垂直於徑向的水平軸，頂端靠柄、底端外張
        axis_rot = Euler((math.sin(a) * -tilt * -1.0 * -1.0, math.cos(a) * tilt * -1.0 * -1.0, 0)).to_matrix()
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=axis_rot, verts=vs)
        bmesh.ops.translate(bm, vec=Vector((cx, cy, 0.40 - ln / 2 + 0.02)), verts=vs)
        fs = [f for f in bm.faces if f not in old]
        b._finish(fs, "straw", 2, 2.0)
    b.cyl(0.050, 0.050, 0.035, (0, 0, 0.385), "bamboo", seg=10)
    b.cyl(0.058, 0.058, 0.03, (0, 0, 0.30), "bamboo", seg=10)
    return b


def main():
    reset()
    set_mat_look("wood_dark", (0.20, 0.13, 0.09), 0.0, 0.85)
    set_mat_look("plank", (0.55, 0.50, 0.44), 0.0, 0.9)
    set_mat_look("roof_tile", (0.20, 0.21, 0.22), 0.0, 0.8)
    set_mat_look("roof_ridge", (0.16, 0.17, 0.18), 0.0, 0.8)
    set_mat_look("stone_foot", (0.46, 0.44, 0.40), 0.0, 0.95)
    set_mat_look("iron", (0.10, 0.10, 0.11), 0.7, 0.55)
    set_mat_look("bronze", (0.50, 0.34, 0.14), 0.75, 0.5)
    set_mat_look("dark_inside", (0.02, 0.015, 0.01), 0.0, 1.0)
    set_mat_look("straw", (0.72, 0.60, 0.34), 0.0, 0.95)
    set_mat_look("bamboo", (0.52, 0.45, 0.24), 0.0, 0.7)
    set_mat_look("emblem", (1, 1, 1), 0.5, 0.55, tex=os.path.abspath(os.path.join(SRC, "tex", "emblem_futatsudomoe.png")))
    set_mat_look("hono_engraved", (1, 1, 1), 0.0, 0.9, tex=os.path.abspath(os.path.join(SRC, "tex", "hono_engraved.png")), alpha=True)
    items = []
    x = 0.0
    for fn in (saisen_box, storehouse, broom):
        b = fn()
        ob = b.build()
        items.append((b.name, ob))
    # 單檔匯出
    names = {"SaisenBox": "saisen_box", "Storehouse": "storehouse", "Broom": "broom"}
    for nm, ob in items:
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        fp = os.path.join(OUT, names[nm] + ".glb")
        bpy.ops.export_scene.gltf(filepath=fp, export_format="GLB", use_selection=True, export_apply=True,
                                  export_image_format="AUTO", export_yup=True)
        print("[PROPS] exported", fp, os.path.getsize(fp) // 1024, "KB", "tris=", sum(len(p.vertices) - 2 for p in ob.data.polygons))
    # 排好位置存 .blend 供檢視
    off = 0.0
    for nm, ob in items:
        ob.location.x = off
        off += 5.0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "shrine_props_r3.blend"))
    print("[PROPS] saved blend")


main()
