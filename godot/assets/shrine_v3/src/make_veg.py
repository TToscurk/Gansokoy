"""博麗神社 v3 植被（全部從零程序生成；Godot 空間撰寫，原點＝樹根地面中心）。
  "D:/Blender/blender-5.2.1-windows-x64/blender.exe" -b --factory-startup --python godot/assets/shrine_v3/src/make_veg.py
輸出 godot/assets/shrine_v3/models/veg/<物種>_v3_<變體>.glb ＋ .json（高度、冠幅、樹幹半徑＝碰撞）。
檔名前綴＝風力物種（scripts/wind/wind_species.gd MESH_PREFIX）：sakura_yama／konara／keyaki→broad_tall、momiji→broad_small、
sugi／akamatsu→conifer、tsutsuji／fern→bush。草叢另由 Godot 端執行期 MultiMesh 生成。
網格約定（veg_common.gdshaderinc）：UV2＝(階層風權重 0–1, 相位 0–1)；COLOR.rgb＝明暗（冠內較暗）、COLOR.a＝葉顫權重；
葉卡法線＝樹冠球狀法線；兩個材質：<物種>_bark（veg_bark）、<物種>_leaf（veg_leaf）。
"""
import json
import math
import os
import random
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
OUT = os.path.join(GODOT, 'assets', 'shrine_v3', 'models', 'veg')
os.makedirs(OUT, exist_ok=True)


def nrm(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-9)


def perp(d):
    a = np.array([0.0, 1.0, 0.0]) if abs(d[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    p = np.cross(d, a)
    return p / np.linalg.norm(p)


class Tree:
    def __init__(self, name, seed):
        self.name = name
        self.rng = random.Random(seed)
        self.V = []      # (pos, nrm, uv, uv2, col, mat)
        self.F = []      # (i0, i1, i2, mat)
        self.branches = []

    def vert(self, p, n, uv, uv2, col):
        self.V.append((np.asarray(p, float), nrm(n), uv, uv2, col))
        return len(self.V) - 1

    def tube(self, pts, radii, sides, w0, w1, phase, mat='bark', tile=0.9, col=(1, 1, 1, 0)):
        """沿點列的錐管；w0→w1＝階層風權重沿長度線性。回傳每環中心。"""
        P = [np.asarray(p, float) for p in pts]
        m = len(P)
        T = [nrm(P[min(i + 1, m - 1)] - P[max(i - 1, 0)]) for i in range(m)]
        n0 = perp(T[0])
        rings = []
        s = 0.0
        acc = [0.0]
        for i in range(1, m):
            s += float(np.linalg.norm(P[i] - P[i - 1]))
            acc.append(s)
        L = max(s, 1e-6)
        nn = n0
        for i in range(m):
            if i > 0:
                v = np.cross(T[i - 1], T[i])
                if np.linalg.norm(v) > 1e-8:
                    ang = math.acos(max(-1.0, min(1.0, float(np.dot(T[i - 1], T[i])))))
                    vv = nrm(v)
                    nn = nn * math.cos(ang) + np.cross(vv, nn) * math.sin(ang) + vv * np.dot(vv, nn) * (1 - math.cos(ang))
            bn = np.cross(T[i], nn)
            ring = []
            for k in range(sides + 1):
                a = 2 * math.pi * k / sides
                d = nn * math.cos(a) + bn * math.sin(a)
                p = P[i] + d * radii[i]
                w = w0 + (w1 - w0) * (acc[i] / L)
                circ = 2 * math.pi * max(radii[0], 0.03)
                ring.append(self.vert(p, d, (k / sides * max(circ / tile, 1.0), acc[i] / tile), (w, phase), col))
            rings.append(ring)
        for i in range(m - 1):
            for k in range(sides):
                a, b, c, d = rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k]
                self.F.append((a, b, c, mat))
                self.F.append((a, c, d, mat))
        return P

    def card(self, base, up, side, w, h, crown_c, crown_r, w2, phase, mat='leaf', ao_axis=False, uvrect=(0, 0, 1, 1)):
        """葉卡：下緣中央在 base，往 up 長 h，寬 w（沿 side）。"""
        up = nrm(up)
        side = nrm(side)
        q = [base - side * w / 2, base + side * w / 2, base + side * w / 2 + up * h, base - side * w / 2 + up * h]
        u0, v0, u1, v1 = uvrect
        uvs = [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]
        ids = []
        for p, uv in zip(q, uvs):
            if ao_axis:
                rel = np.array([p[0] - crown_c[0], (p[1] - crown_c[1]) * 0.35, p[2] - crown_c[2]])
            else:
                rel = p - crown_c
            n = nrm(rel + np.array([0, crown_r * 0.25, 0]))
            dist = float(np.linalg.norm(rel)) / max(crown_r, 0.1)
            ao = 0.50 + 0.50 * min(max(dist, 0.0), 1.0)
            t = 1.0 + self.rng.uniform(-0.07, 0.07)
            ids.append(self.vert(p, n, uv, (min(1.0, w2), phase), (ao * t, ao * t, ao * t, 1.0)))
        self.F.append((ids[0], ids[1], ids[2], mat))
        self.F.append((ids[0], ids[2], ids[3], mat))

    def tris(self, mat=None):
        return sum(1 for f in self.F if mat is None or f[3] == mat)


# ───────────────────────── 物種 ─────────────────────────
def bend_path(p0, d, L, n, droop=0.0, wobble=0.15, rng=None):
    pts = [np.asarray(p0, float)]
    d = nrm(d)
    seg = L / n
    for i in range(n):
        d = nrm(d + np.array([rng.uniform(-wobble, wobble), -droop * (i / n), rng.uniform(-wobble, wobble)]))
        pts.append(pts[-1] + d * seg)
    return pts


def broadleaf(name, seed, H, trunk_h, r0, n_main, elev, main_len, crown_w, card_w, n_cards_per, spread_up=0.25, droop=0.05, multi_stem=1, card_rect=(0, 0, 1, 1)):
    t = Tree(name, seed)
    rng = t.rng
    crown_c = np.array([0.0, trunk_h + (H - trunk_h) * 0.5, 0.0])
    crown_r = max(crown_w * 0.5, (H - trunk_h) * 0.5)
    stems = []
    for si in range(multi_stem):
        lean = np.array([rng.uniform(-0.12, 0.12), 1.0, rng.uniform(-0.12, 0.12)]) if multi_stem > 1 else np.array([rng.uniform(-0.04, 0.04), 1.0, rng.uniform(-0.04, 0.04)])
        if multi_stem > 1:
            ang = 2 * math.pi * si / multi_stem + rng.uniform(-0.4, 0.4)
            lean = nrm(np.array([math.cos(ang) * 0.35, 1.0, math.sin(ang) * 0.35]))
        top_h = H * (0.62 if multi_stem == 1 else 0.55)
        pts = bend_path([0, -0.15, 0], lean, top_h + 0.15, 9, 0.0, 0.05, rng)
        rr = [r0 * (1.35 if i == 0 else 1.0) * (1.0 - 0.72 * i / 9) / (1.0 if multi_stem == 1 else 1.4) for i in range(10)]
        rr[1] *= 1.12
        t.tube(pts, rr, 10, 0.0, 0.10, rng.random(), 'bark')
        stems.append((pts, rr))
    # 主枝
    k = 0
    for (pts, rr) in stems:
        for bi in range(n_main // multi_stem + (1 if multi_stem > 1 else 0)):
            k += 1
            f = 0.15 + 0.85 * bi / max(n_main // multi_stem, 1)
            idx = min(int(round((trunk_h / (H * 0.62)) * 9 + f * (9 - (trunk_h / (H * 0.62)) * 9))), 8)
            idx = max(2, idx)
            base = pts[idx]
            az = k * 2.39996 + rng.uniform(-0.3, 0.3)
            el = math.radians(rng.uniform(*elev))
            d = nrm(np.array([math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el)]))
            L = main_len * rng.uniform(0.8, 1.15) * (1.0 - 0.35 * f)
            bp = bend_path(base, d, L, 5, droop, 0.18, rng)
            br0 = rr[idx] * 0.55
            ph = rng.random()
            t.tube(bp, [br0 * (1.0 - 0.8 * i / 5) for i in range(6)], 6, 0.12, 0.40, ph, 'bark')
            # 次枝＋葉卡
            n2 = rng.randint(3, 5)
            for j in range(n2):
                s = 0.35 + 0.65 * (j + 1) / n2
                ii = min(int(s * 5), 5)
                b2 = bp[ii]
                dd = nrm(d + np.array([rng.uniform(-0.9, 0.9), rng.uniform(-0.1, 0.6) + spread_up, rng.uniform(-0.9, 0.9)]))
                L2 = L * rng.uniform(0.35, 0.55)
                bp2 = bend_path(b2, dd, L2, 3, droop * 0.5, 0.25, rng)
                ph2 = (ph + rng.uniform(-0.15, 0.15)) % 1.0
                t.tube(bp2, [br0 * 0.45 * (1.0 - 0.8 * i / 3) for i in range(4)], 4, 0.42, 0.62, ph2, 'bark')
                for c in range(n_cards_per):
                    s2 = rng.uniform(0.25, 1.0)
                    p = bp2[0] + (bp2[-1] - bp2[0]) * s2
                    up = nrm(dd + np.array([rng.uniform(-0.8, 0.8), rng.uniform(-0.2, 0.7), rng.uniform(-0.8, 0.8)]))
                    side = perp(up)
                    rot = rng.uniform(0, math.pi)
                    side = nrm(side * math.cos(rot) + np.cross(up, side) * math.sin(rot))
                    cw = card_w * rng.uniform(0.75, 1.2)
                    t.card(p, up, side, cw, cw, crown_c, crown_r, 0.78 + 0.22 * s2, ph2, 'leaf', uvrect=card_rect)
    return t, {'height': H, 'crown_w': crown_w, 'trunk_r': r0, 'trunk_h': trunk_h}


def conifer(name, seed, H, r0, crown_base, n_whorl, max_len, card_w, cards_per, droop=0.25, crooked=0.0, flat_top=False):
    t = Tree(name, seed)
    rng = t.rng
    pts = bend_path([0, -0.15, 0], [rng.uniform(-0.02, 0.02) + crooked, 1.0, rng.uniform(-0.02, 0.02)], H + 0.15, 12, 0.0, 0.02 + crooked * 0.4, rng)
    rr = [r0 * (1.3 if i == 0 else 1.0) * (1.0 - 0.9 * i / 12) for i in range(13)]
    t.tube(pts, rr, 9, 0.0, 0.12, rng.random(), 'bark')
    crown_c = np.array([pts[-1][0] * 0.5, crown_base + (H - crown_base) * 0.5, pts[-1][2] * 0.5])
    crown_r = max((H - crown_base) * 0.5, max_len)
    for wi in range(n_whorl):
        f = wi / max(n_whorl - 1, 1)
        y = crown_base + (H - crown_base) * f * 0.97
        idx = min(int(y / H * 12), 11)
        tt = y / H * 12 - idx
        base = pts[idx] + (pts[idx + 1] - pts[idx]) * tt
        L = max_len * ((1.0 - f) ** 0.85 * 0.9 + 0.12) * rng.uniform(0.85, 1.1)
        if flat_top:
            L = max_len * (0.5 + 0.5 * math.sin(f * math.pi)) * rng.uniform(0.7, 1.2)
        nb = 4 if L > 1.0 else 3
        for bi in range(nb):
            az = wi * 1.1 + bi * 2 * math.pi / nb + rng.uniform(-0.3, 0.3)
            el = rng.uniform(-0.25, 0.15) - droop * (1 - f) * 0.5
            d = nrm(np.array([math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el)]))
            bp = bend_path(base, d, L, 3, droop * 0.6, 0.12, rng)
            ph = rng.random()
            t.tube(bp, [rr[idx] * 0.35 * (1.0 - 0.85 * i / 3) for i in range(4)], 4, 0.18, 0.5, ph, 'bark')
            for c in range(cards_per):
                s = rng.uniform(0.15, 1.0)
                p = bp[0] + (bp[-1] - bp[0]) * s
                up = nrm(d + np.array([rng.uniform(-0.5, 0.5), rng.uniform(-0.6, 0.2), rng.uniform(-0.5, 0.5)]))
                side = perp(up)
                rot = rng.uniform(0, math.pi)
                side = nrm(side * math.cos(rot) + np.cross(up, side) * math.sin(rot))
                cw = card_w * rng.uniform(0.7, 1.1) * (0.6 + 0.4 * (1 - f))
                t.card(p - up * cw * 0.15, up, side, cw * 0.75, cw, crown_c, crown_r, 0.7 + 0.3 * s, ph, 'leaf', ao_axis=True)
    # 樹梢
    for c in range(6):
        up = nrm(np.array([rng.uniform(-0.4, 0.4), 1.0, rng.uniform(-0.4, 0.4)]))
        side = perp(up)
        t.card(pts[-2], up, side, card_w * 0.5, card_w * 0.8, crown_c, crown_r, 0.95, rng.random(), 'leaf', ao_axis=True)
    return t, {'height': H, 'crown_w': max_len * 2, 'trunk_r': r0, 'trunk_h': crown_base}


def shrub(name, seed, H, W, n_cards, card_w):
    t = Tree(name, seed)
    rng = t.rng
    c = np.array([0.0, H * 0.55, 0.0])
    for k in range(5):
        ang = rng.uniform(0, 2 * math.pi)
        d = nrm(np.array([math.cos(ang) * 0.5, 1.0, math.sin(ang) * 0.5]))
        bp = bend_path([0, -0.05, 0], d, H * 0.7, 3, 0.0, 0.2, rng)
        t.tube(bp, [0.025, 0.02, 0.014, 0.008], 4, 0.2, 0.5, rng.random(), 'bark')
    for i in range(n_cards):
        # 半球上隨機點
        u = rng.random()
        v = rng.random()
        th = 2 * math.pi * u
        ph = math.acos(1 - v)   # 上半球
        r = W * 0.5 * rng.uniform(0.55, 1.0)
        p = np.array([math.sin(ph) * math.cos(th) * r, H * 0.15 + math.cos(ph) * (H * 0.8) * rng.uniform(0.6, 1.0), math.sin(ph) * math.sin(th) * r])
        up = nrm(p - np.array([0, 0, 0]) + np.array([0, 0.3, 0]))
        side = perp(up)
        rot = rng.uniform(0, math.pi)
        side = nrm(side * math.cos(rot) + np.cross(up, side) * math.sin(rot))
        cw = card_w * rng.uniform(0.75, 1.15)
        t.card(p - up * cw * 0.45, up, side, cw, cw, c, max(W, H) * 0.5, 0.75 + 0.25 * rng.random(), rng.random(), 'leaf')
    return t, {'height': H, 'crown_w': W, 'trunk_r': 0.0, 'trunk_h': 0.0}


def fern(name, seed, R, n=9):
    t = Tree(name, seed)
    rng = t.rng
    c = np.array([0.0, 0.3, 0.0])
    for i in range(n):
        az = 2 * math.pi * i / n + rng.uniform(-0.25, 0.25)
        el = math.radians(rng.uniform(35, 60))
        d = nrm(np.array([math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el)]))
        L = R * rng.uniform(0.8, 1.15)
        # 拱形：兩段卡片（下段較直、上段垂下）
        mid = d * L * 0.5
        d2 = nrm(d + np.array([0, -0.9, 0]))
        side = nrm(np.cross(d, np.array([0, 1, 0])))
        ph = rng.random()
        t.card(np.array([0, 0.02, 0]), d, side, L * 0.42, L * 0.55, c, R, 0.6, ph, 'leaf', uvrect=(0, 0.45, 1, 1))
        t.card(mid, d2, side, L * 0.42, L * 0.5, c, R, 1.0, ph, 'leaf', uvrect=(0, 0, 1, 0.47))
    return t, {'height': R * 0.7, 'crown_w': R * 2, 'trunk_r': 0.0, 'trunk_h': 0.0}


# ───────────────────────── Blender ─────────────────────────
def to_blender(t, mats):
    import bpy
    me = bpy.data.meshes.new(t.name)
    verts = [(float(p[0]), float(-p[2]), float(p[1])) for (p, n, uv, uv2, col) in t.V]
    faces = [(a, b, c) for (a, b, c, m) in t.F]
    me.from_pydata(verts, [], faces)
    mat_names = []
    for f in t.F:
        if f[3] not in mat_names:
            mat_names.append(f[3])
    for m in mat_names:
        me.materials.append(mats[m])
    for i, f in enumerate(t.F):
        me.polygons[i].material_index = mat_names.index(f[3])
        me.polygons[i].use_smooth = True
    uv1 = me.uv_layers.new(name='UVMap')
    uv2 = me.uv_layers.new(name='UV2')
    col = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
    loop_normals = []
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            p, n, uv, u2, c = t.V[vi]
            uv1.data[li].uv = (float(uv[0]), float(uv[1]))
            uv2.data[li].uv = (float(u2[0]), float(u2[1]))
            col.data[li].color = (float(c[0]), float(c[1]), float(c[2]), float(c[3]))
            loop_normals.append((float(n[0]), float(-n[2]), float(n[1])))
    me.normals_split_custom_set(loop_normals)
    me.update()
    ob = bpy.data.objects.new(t.name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def main():
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = {}
    for k, c in (('bark', (0.3, 0.25, 0.2)), ('leaf', (0.3, 0.5, 0.2))):
        m = bpy.data.materials.new(k)
        m.diffuse_color = (c[0], c[1], c[2], 1.0)
        mats[k] = m
    defs = [
        # 山櫻：寬展樹冠
        lambda: broadleaf('sakura_yama_v3_a', 101, 9.5, 2.4, 0.24, 7, (22, 48), 4.4, 9.0, 1.45, 16, 0.15, 0.10),
        lambda: broadleaf('sakura_yama_v3_b', 102, 7.5, 1.9, 0.19, 6, (25, 52), 3.6, 7.0, 1.30, 16, 0.15, 0.10),
        lambda: broadleaf('sakura_yama_v3_c', 103, 11.5, 2.8, 0.28, 8, (28, 55), 5.0, 10.0, 1.55, 16, 0.18, 0.08),
        # 枹櫟／欅：新綠，往上展開
        lambda: broadleaf('konara_v3_a', 111, 13.0, 4.0, 0.25, 8, (45, 70), 4.2, 8.0, 1.5, 16, 0.35, 0.02),
        lambda: broadleaf('konara_v3_b', 112, 15.5, 4.8, 0.30, 9, (48, 72), 4.8, 9.0, 1.6, 16, 0.35, 0.02),
        lambda: broadleaf('keyaki_v3_a', 113, 16.0, 3.6, 0.34, 9, (52, 75), 6.0, 11.0, 1.6, 16, 0.45, 0.0),
        # 野村楓：低、多幹、傘形
        lambda: broadleaf('momiji_v3_a', 121, 5.2, 1.2, 0.10, 6, (15, 40), 2.6, 5.0, 1.05, 14, 0.10, 0.12, multi_stem=2),
        lambda: broadleaf('momiji_v3_b', 122, 4.2, 1.0, 0.08, 5, (18, 42), 2.2, 4.0, 0.95, 14, 0.10, 0.12, multi_stem=3),
        # 杉：高直、圓錐形樹冠
        lambda: conifer('sugi_v3_a', 131, 22.0, 0.33, 6.0, 18, 3.0, 1.5, 12, 0.25),
        lambda: conifer('sugi_v3_b', 132, 26.0, 0.38, 8.0, 20, 3.3, 1.6, 12, 0.25),
        lambda: conifer('sugi_v3_c', 133, 17.0, 0.26, 4.5, 15, 2.6, 1.4, 12, 0.25),
        # 崖松（赤松）：彎幹、平頂
        lambda: conifer('akamatsu_v3_a', 141, 7.0, 0.20, 3.4, 8, 2.4, 1.2, 14, 0.05, crooked=0.35, flat_top=True),
        lambda: conifer('akamatsu_v3_b', 142, 5.5, 0.17, 2.6, 7, 2.0, 1.1, 14, 0.05, crooked=-0.30, flat_top=True),
        # 杜鵑灌叢、蕨
        lambda: shrub('tsutsuji_v3_a', 151, 1.2, 1.6, 44, 0.7),
        lambda: shrub('tsutsuji_v3_b', 152, 0.9, 1.2, 32, 0.6),
        lambda: shrub('shrub_v3_a', 153, 1.5, 1.8, 50, 0.8),
        lambda: fern('fern_v3_a', 161, 0.75),
        lambda: fern('fern_v3_b', 162, 0.55, 7),
    ]
    rep = []
    for fn in defs:
        t, info = fn()
        ob = to_blender(t, mats)
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        path = os.path.join(OUT, t.name + '.glb')
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                                  export_image_format='NONE', export_vertex_color='ACTIVE', export_yup=True,
                                  export_normals=True, export_texcoords=True)
        P = np.array([v[0] for v in t.V])
        info.update({'name': t.name, 'tris': len(t.F), 'tris_leaf': t.tris('leaf'), 'tris_bark': t.tris('bark'),
                     'aabb_min': P.min(0).tolist(), 'aabb_max': P.max(0).tolist()})
        json.dump(info, open(os.path.join(OUT, t.name + '.json'), 'w', encoding='utf-8'), indent=1)
        rep.append(info)
        bpy.data.objects.remove(ob)
    for r in rep:
        print('[VEG] %-18s tris %5d (leaf %5d) h %.1f  aabb y %.2f..%.2f  w %.1f' % (r['name'], r['tris'], r['tris_leaf'], r['height'], r['aabb_min'][1], r['aabb_max'][1], r['aabb_max'][0] - r['aabb_min'][0]))


if __name__ == '__main__':
    main()
