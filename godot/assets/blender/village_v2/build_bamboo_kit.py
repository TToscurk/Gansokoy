"""人間之里 V2 P9 R3：竹 Kit（bamboo_kit，自製 procedural bamboo）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_bamboo_kit.py [-- --only=id1,id2（試算，不寫檔）]

R1 樹庫（build_veg_kit.py／veg_kit）已封存不動；本檔只 import v2_kit 共用工具，網格緩衝 MB 與 R1 同格式（同一套 Godot prefab／shader）。
竹語彙（§31.2）：竹稈 young／mature／thick／thin／leaning／dead／broken＋筍＋竹葉地被；葉叢＝tools/build_village_v2_bamboo_textures.py
的 BL_A atlas（spray_a／spray_b／spray_young／spray_dry／spray_hang 五種共用枝葉卡＋筍皮＋落葉）。

竹稈結構（真竹／孟宗竹／淡竹的 Phyllostachys 型）：
  - 節間長：基部極短 → 稈高 30–40 % 最長 → 往梢漸短；稈徑：緩慢漸細，梢端收尖。
  - 每節一圈節環（LOD0：上下兩圈微凸）；貼圖 u＝稈周、v＝一個節間（0＝上節、1＝下節）。
  - 枝：枝下高以上，每節 2 枝（主＋副）、左右交互（180°）；枝長下長上短，斜上 40–60° 再受重下垂；梢頭弓垂（孟宗最強）。
  - 葉叢卡：沿枝外側 2/3 掛 spray 卡（卡面朝外、往下垂），梢頭掛 spray_hang；若竹下部節帶筍皮卡。
輸出（godot/assets/village_v2/bamboo_kit/src/）：bamboo_kit.glb（<id>_LOD0..LOD3）＋ modules_blender.json（同 R1 格式）。
慣例：Godot 座標（x 右、y 上、+z 前）、公尺；原點＝稈基接地點，稈往地下延伸 embed。頂點資料同 R1：
  COLOR.rgb＝反照率乘數、COLOR.a＝葉卡細抖遮罩；UV2.x＝風權重（稈基 0 → 梢 0.35；枝 0.45–0.6；葉 0.75–1.0）、UV2.y＝相位。
"""
import json
import math
import os
import random
import sys
import time

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
KIT = G + '/assets/village_v2/bamboo_kit'
TEXJ = K.load_json(KIT + '/tex/bamboo_tex.json')
AT = TEXJ['atlas']['A']
AW, AH = AT['size']
UP = np.array((0.0, 1.0, 0.0))
MAT_CULM = {'green': 'BK_Culm_green', 'dead': 'BK_Culm_dead'}
MAT_LEAF = 'BK_Leaf_A'


def V(x, y, z):
    return np.array((x, y, z), dtype=np.float64)


def nrm(a):
    n = float(np.linalg.norm(a))
    return a / n if n > 1e-12 else a


def rot(v, axis, ang):
    axis = nrm(axis)
    return v * math.cos(ang) + np.cross(axis, v) * math.sin(ang) + axis * float(np.dot(axis, v)) * (1 - math.cos(ang))


def perp(d):
    a = V(1, 0, 0) if abs(d[0]) < 0.9 else V(0, 0, 1)
    return nrm(np.cross(d, a))


def sstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ───────────────────────── 網格緩衝（與 build_veg_kit.py MB 同格式） ─────────────────────────
class MB:
    def __init__(self, name):
        self.name = name
        self.P, self.N, self.UV, self.UV2, self.C = [], [], [], [], []
        self.F, self.FM = [], []
        self.mats = []

    def mat(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def v(self, p, n, uv, uv2, c):
        self.P.append((float(p[0]), float(p[1]), float(p[2])))
        self.N.append(tuple(float(x) for x in nrm(np.asarray(n, dtype=np.float64))))
        self.UV.append((float(uv[0]), float(uv[1])))
        self.UV2.append((float(min(1.0, max(0.0, uv2[0]))), float(uv2[1])))
        self.C.append((float(c[0]), float(c[1]), float(c[2]), float(c[3])))
        return len(self.P) - 1

    def f(self, idx, m):
        self.F.append(tuple(idx))
        self.FM.append(m)

    def tris(self):
        return sum(len(f) - 2 for f in self.F)

    def aabb(self):
        a = np.asarray(self.P)
        return a.min(0), a.max(0)

    def to_blender(self, bmats):
        me = bpy.data.meshes.new(self.name)
        bv = [(p[0], -p[2], p[1]) for p in self.P]
        me.from_pydata(bv, [], [list(f) for f in self.F])
        me.update()
        lvi = np.zeros(len(me.loops), dtype=np.int64)
        me.loops.foreach_get('vertex_index', lvi)
        uv = np.asarray(self.UV, dtype=np.float32)[lvi]
        uv[:, 1] = 1.0 - uv[:, 1]
        l1 = me.uv_layers.new(name='UVMap')
        l1.data.foreach_set('uv', uv.ravel())
        uv2 = np.asarray(self.UV2, dtype=np.float32)[lvi]
        uv2[:, 1] = 1.0 - uv2[:, 1]
        l2 = me.uv_layers.new(name='UV2')
        l2.data.foreach_set('uv', uv2.ravel())
        me.uv_layers.active = l1
        col = me.color_attributes.new(name='Col', type='FLOAT_COLOR', domain='CORNER')
        col.data.foreach_set('color', np.asarray(self.C, dtype=np.float32)[lvi].ravel())
        me.color_attributes.active_color = col
        me.polygons.foreach_set('material_index', np.asarray(self.FM, dtype=np.int32))
        me.polygons.foreach_set('use_smooth', np.ones(len(me.polygons), dtype=bool))
        for m in self.mats:
            me.materials.append(bmats[m])
        n = np.asarray(self.N, dtype=np.float64)[lvi]
        me.normals_split_custom_set([tuple(x) for x in np.stack([n[:, 0], -n[:, 2], n[:, 1]], 1)])
        me.update()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


# ───────────────────────── 竹稈骨架 ─────────────────────────
class Culm:
    """稈中心線（弧長參數）＋節位置＋半徑。"""

    def __init__(self, sp, rng):
        self.sp = sp
        H = sp['H']
        self.az = 0.0                                           # 傾斜／弓垂方位固定 +x：擺放時以 yaw 控制朝向（林緣朝外）
        lean = math.radians(sp.get('lean', 2.0) * rng.uniform(0.8, 1.2))
        droop = math.radians(sp.get('droop', 15.0) * rng.uniform(0.85, 1.15))
        hd = V(math.cos(self.az), 0, math.sin(self.az))
        wob = sp.get('wob', 0.015)
        n = 240
        pts = [V(0, 0, 0)]
        ph = rng.uniform(0, 6.28)
        for i in range(n):
            s = (i + 0.5) / n
            a = lean * (0.35 + 0.65 * s) + droop * sstep(0.5, 1.0, s) ** 1.35
            d = nrm(UP * math.cos(a) + hd * math.sin(a) + perp(hd + V(0, 0.01, 0)) * wob * math.sin(s * 9 + ph))
            pts.append(pts[-1] + d * (H / n))
        self.line = np.asarray(pts)
        seg = np.linalg.norm(np.diff(self.line, axis=0), axis=1)
        self.cum = np.concatenate([[0.0], np.cumsum(seg)])
        self.L = float(self.cum[-1])
        # 節：節間長分布（基部極短 → 30–40 % 最長 → 梢短）
        nn = sp['n_node']
        f = []
        for k in range(nn):
            x = (k + 0.5) / nn
            f.append(0.16 + 0.84 * (x / 0.36) ** 0.75 if x < 0.36 else 1.0 - 0.6 * ((x - 0.36) / 0.64) ** 1.25)
        f = np.asarray(f)
        f = f / f.sum() * self.L
        self.nodes = np.concatenate([[0.0], np.cumsum(f)])       # 弧長
        self.R = sp['D'] * 0.5

    def at(self, s_len):
        s_len = min(max(s_len, 0.0), self.L)
        i = int(np.searchsorted(self.cum, s_len) - 1)
        i = min(max(i, 0), len(self.cum) - 2)
        t = (s_len - self.cum[i]) / max(self.cum[i + 1] - self.cum[i], 1e-9)
        p = self.line[i] * (1 - t) + self.line[i + 1] * t
        d = nrm(self.line[i + 1] - self.line[i])
        return p, d

    def r(self, s_len):
        s = s_len / self.L
        return max(0.004, self.R * (1.0 - 0.10 * s - 0.55 * s ** 3.2))


def frame(d, ref):
    x = ref - d * float(np.dot(ref, d))
    if float(np.linalg.norm(x)) < 1e-6:
        x = perp(d)
    x = nrm(x)
    return x, nrm(np.cross(d, x))


def culm_mesh(mb, C, lod, sp, mat, top_len=None, tint=(1.0, 1.0, 1.0), splinter=False, rng=None):
    """稈：每節間一段（v 1→0），LOD0 節處上下兩圈微凸；LOD2+ 合併節間（v 跨多個節間，貼圖重複節環）。"""
    mi = mb.mat(mat)
    sides = {0: sp.get('sides', 8), 1: max(4, sp.get('sides', 8) - 3), 2: 4, 3: 3}[lod]
    merge = {0: 1, 1: 1, 2: 2, 3: 4}[lod]
    Ltop = C.L if top_len is None else top_len
    nodes = [x for x in C.nodes if x <= Ltop + 1e-6]
    if nodes[-1] < Ltop - 0.01:
        nodes.append(Ltop)
    nodes = nodes[::merge] if merge > 1 else nodes
    if merge > 1:   # 弓垂段（上 40 %）每節保留，避免遠景梢頭變直
        nodes = sorted(set([x for x in nodes if x < 0.6 * C.L] + [x for x in C.nodes if 0.6 * C.L <= x <= Ltop][::2]))
    if nodes[-1] < Ltop - 0.01:
        nodes.append(Ltop)
    embed = sp.get('embed', 0.25)
    ph = sp['_phase']
    ref = V(1, 0, 0)
    first = True
    top_ring = None
    for k in range(len(nodes) - 1):
        a, b = nodes[k], nodes[k + 1]
        span = max(1, merge)
        low = a / C.L < 0.5
        if lod == 0 and low:
            # 節環：節下緣一圈外凸 6 %、5 % 節間內收回 → 與上一節間頂（×1.0）形成小台階＝節脊
            ts, bulge = [0.0, 0.05, 1.0], [1.06, 1.0, 1.0]
        elif lod <= 1:
            ts, bulge = [0.0, 1.0], [1.03, 1.0]
        else:
            ts, bulge = [0.0, 1.0], [1.0, 1.0]
        sides_k = sides if (low or lod >= 2) else max(3, sides - 2)
        rings = []
        for t, bg in zip(ts, bulge):
            sl = a + (b - a) * t
            p, d = C.at(sl)
            if first and t == 0.0:
                p = p - d * embed
            x, y = frame(d, ref)
            r = C.r(sl) * bg
            h = p[1]
            ao = 0.78 + 0.22 * sstep(0.0, 1.6, h)
            w = 0.55 * (sl / C.L) ** 1.5          # 竹：整稈擺動（梢 0.55），比樹幹（≤ 0.35）柔
            ring = []
            for j in range(sides_k + 1):
                th = j / sides_k * math.tau
                nv = x * math.cos(th) + y * math.sin(th)
                col = (tint[0] * ao, tint[1] * ao, tint[2] * ao, 0.0)
                ring.append(mb.v(p + nv * r, nv, (j / sides_k, (1.0 - t) * span), (w, ph), col))
            rings.append(ring)
        first = False
        for q in range(len(rings) - 1):
            r0, r1 = rings[q], rings[q + 1]
            for j in range(sides_k):
                mb.f((r0[j], r0[j + 1], r1[j + 1], r1[j]), mi)
        top_ring = rings[-1]
    # 梢端收口（或折斷面：鋸齒狀竹纖維）
    p, d = C.at(Ltop)
    if splinter and rng is not None:
        x, y = frame(d, ref)
        r = C.r(Ltop)
        n = sides * 2 if lod == 0 else sides
        qs = []
        for j in range(n + 1):
            th = j / n * math.tau
            nv = x * math.cos(th) + y * math.sin(th)
            spike = rng.uniform(0.0, 0.32) if (j % 2 == 0 and lod <= 1) else rng.uniform(0.0, 0.06)
            qs.append((p + nv * r * (0.85 if spike > 0.1 else 1.0) + d * spike, nv))
        # 正面（外）與背面（看得到內壁）各用自己的頂點：共用頂點的反向面在 Blender 會被當成重複面合併
        for side in (1.0, -1.0):
            cen = mb.v(p + d * 0.01, d * side, (0.5, 0.0), (0.3, ph), (0.7, 0.66, 0.55, 0.0))
            ids = [mb.v(q, nv * side, (j / n, 0.0), (0.3, ph), (0.75, 0.7, 0.58, 0.0)) for j, (q, nv) in enumerate(qs)]
            for j in range(n):
                mb.f((cen, ids[j + 1], ids[j]) if side > 0 else (cen, ids[j], ids[j + 1]), mi)
    elif top_ring is not None:
        tip = mb.v(p + d * 0.05, d, (0.5, 0.0), (0.35, ph), (tint[0], tint[1], tint[2], 0.0))
        for j in range(len(top_ring) - 1):
            mb.f((top_ring[j], top_ring[j + 1], tip), mi)


def sheath_wrap(mb, C, sl, hlen, az0, cell, lod, ph):
    """筍皮：自節處包住稈的錐面（張角 330°），u 沿稈周對應筍皮貼圖寬、v 沿稈軸；貼圖三角 alpha 給往上收尖的輪廓。"""
    r = AT['regions'][cell]
    mi = mb.mat(MAT_LEAF)
    u0, v0, u1, v1 = r['bbox_uv']
    cols = 10 if lod == 0 else 6
    rows = 3 if lod == 0 else 2
    span = math.radians(330)
    ids = []
    for i in range(rows + 1):
        hv = i / rows
        s_ = sl + hv * hlen
        p, d = C.at(s_)
        x, y = frame(d, V(1, 0, 0))
        rr = C.r(s_) * (1.08 + 1.1 * hv ** 2.0) + 0.002           # 上緣外翻（筍皮剝離中）
        row = []
        for j in range(cols + 1):
            th = az0 + (j / cols - 0.5) * span
            nv = x * math.cos(th) + y * math.sin(th)
            row.append(mb.v(p + nv * rr, nv, (u0 + (u1 - u0) * j / cols, v1 - (v1 - v0) * hv), (0.05 * hv, ph),
                            (1.0, 1.0, 1.0, 0.0)))
        ids.append(row)
    for i in range(rows):
        for j in range(cols):
            mb.f((ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j]), mi)


def fold_segment(mb, C, Ltop, lod, mat, ph, rng):
    """折れ竹：折斷處未斷離的上段——從斷口往外折下垂（≈ 150°），長 2.4 m，末端掛在下方。"""
    p, d = C.at(Ltop)
    out = nrm(V(d[0], 0, d[2]) + V(0.4, 0, 0.2))
    sides = {0: 6, 1: 4, 2: 3, 3: 3}[lod]
    n = {0: 6, 1: 3, 2: 2, 3: 1}[lod]
    L = 3.6
    r0 = C.r(Ltop) * 0.92
    # 鉸鏈：斷口處先往外橫折 0.18 m（銳角 kink），再幾乎垂直往下掛（末端略外擺）
    hinge = p + out * 0.32 + UP * 0.06
    pts = [p, hinge]
    for i in range(1, n + 1):
        t = i / n
        pts.append(hinge + out * (0.35 + 1.0 * t ** 0.8) - UP * (L * 0.88 * t))   # 斜掛 ≈ 20–25°，不與立稈平行
    n = len(pts) - 1
    mi = mb.mat(mat)
    rings = []
    for k, q in enumerate(pts):
        dd = nrm(pts[min(k + 1, n)] - pts[max(k - 1, 0)])
        x, y = frame(dd, V(0, 1, 0))
        rr = r0 * (1.0 - 0.15 * k / n) * (0.6 if k == 0 else 1.0)
        ring = []
        for j in range(sides + 1):
            th = j / sides * math.tau
            nv = x * math.cos(th) + y * math.sin(th)
            ring.append(mb.v(q + nv * rr, nv, (j / sides, (1 - k / n) * 4.0), (0.4 + 0.3 * k / n, ph), (0.95, 0.92, 0.85, 0.0)))
        rings.append(ring)
    for q in range(len(rings) - 1):
        for j in range(sides):
            mb.f((rings[q][j], rings[q][j + 1], rings[q + 1][j + 1], rings[q + 1][j]), mi)


def twig_mesh(mb, pts, r0, r1, mat, w0, w1, ph, lod, col=(0.9, 0.92, 0.85)):
    """枝：3 面細管（LOD0 2 段、LOD1 1 段）。"""
    mi = mb.mat(mat)
    if lod >= 2:
        return
    pts = [pts[0], pts[-1]] if lod == 1 else pts
    sides = 3
    rings = []
    ref = V(0, 1, 0)
    for k, p in enumerate(pts):
        t = k / (len(pts) - 1)
        d = nrm(pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)])
        x, y = frame(d, ref)
        r = r0 + (r1 - r0) * t
        ring = []
        for j in range(sides + 1):
            th = j / sides * math.tau
            nv = x * math.cos(th) + y * math.sin(th)
            ring.append(mb.v(p + nv * r, nv, (j / sides * 0.15, (1 - t) * 0.6), (w0 + (w1 - w0) * t, ph),
                             (col[0], col[1], col[2], 0.0)))
        rings.append(ring)
    for q in range(len(rings) - 1):
        for j in range(sides):
            mb.f((rings[q][j], rings[q][j + 1], rings[q + 1][j + 1], rings[q + 1][j]), mi)


# ───────────────────────── 葉叢卡 ─────────────────────────
class Card:
    __slots__ = ('cell', 'p', 'up', 'rt', 's', 'w', 'ph', 'tint', 'imp', 'nc', 'fold')

    def __init__(self, cell, p, up, rt, s, w, ph, tint, imp, nc, fold=0.0):
        self.cell, self.p, self.up, self.rt, self.s, self.w, self.ph = cell, p, up, rt, s, w, ph
        self.tint, self.imp, self.nc, self.fold = tint, imp, nc, fold


def emit_card(mb, c, scale, pull_to=None, fold=True):
    r = AT['regions'][c.cell]
    mi = mb.mat(MAT_LEAF)
    u0, v0, u1, v1 = r['bbox_uv']
    ua, va = r['anchor_uv']
    if r['anchor'] == 'center':
        ua, va = (u0 + u1) * 0.5, (v0 + v1) * 0.5
    Su0 = r['cm_per_px'] / 100.0 * AW * c.s
    Sv0 = r['cm_per_px'] / 100.0 * AH * c.s
    Su, Sv = Su0 * scale, Sv0 * scale
    up, rt = nrm(c.up), nrm(c.rt)
    base = c.p
    if scale != 1.0:
        uc, vc = (u0 + u1) * 0.5, (v0 + v1) * 0.5
        base = c.p + rt * ((uc - ua) * (Su0 - Su)) + up * ((va - vc) * (Sv0 - Sv))
        if pull_to is not None and scale > 1.05:
            dv = pull_to - base
            dl = float(np.linalg.norm(dv))
            if dl > 1e-3:
                base = base + dv / dl * min((max(Su, Sv) - max(Su0, Sv0)) * 0.35, dl * 0.6)
    n0 = nrm(np.cross(rt, up))
    fa = math.radians(18.0) if (fold and c.fold > 0) else 0.0

    def pos(u, v):
        x = (u - ua) * Su
        q = base + rt * x + up * ((va - v) * Sv)
        if fa:
            q = q + n0 * abs(x) * math.tan(fa)
        return q

    def nrm_at(q):
        return nrm(nrm(q - c.nc) * 0.75 + n0 * 0.25 + UP * 0.25)

    def wv(u, v):
        x = abs(u - ua) * Su
        y = abs(va - v) * Sv
        return min(1.0, (x * x + y * y) ** 0.5 / max(Su0 * (u1 - u0), Sv0 * (v1 - v0), 0.1))

    col = c.tint
    if fa:
        um = ua if u0 < ua < u1 else (u0 + u1) * 0.5
        corners = [(u0, v1), (um, v1), (um, v0), (u0, v0), (um, v1), (u1, v1), (u1, v0), (um, v0)]
        ids = []
        for (u, v) in corners:
            q = pos(u, v)
            ids.append(mb.v(q, nrm_at(q), (u, v), (c.w, c.ph), (col[0], col[1], col[2], wv(u, v))))
        mb.f((ids[0], ids[1], ids[2], ids[3]), mi)
        mb.f((ids[4], ids[5], ids[6], ids[7]), mi)
    else:
        ids = []
        for (u, v) in [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]:
            q = pos(u, v)
            ids.append(mb.v(q, nrm_at(q), (u, v), (c.w, c.ph), (col[0], col[1], col[2], wv(u, v))))
        mb.f(tuple(ids), mi)


def cell_h_m(cell):
    r = AT['regions'][cell]
    return (r['bbox_uv'][3] - r['bbox_uv'][1]) * AH * r['cm_per_px'] / 100.0


# ───────────────────────── 生成 ─────────────────────────
def gen_culm(tid, sp):
    rng = random.Random(sp.get('seed', 1) * 7919 + sum(map(ord, tid)))
    sp['_phase'] = rng.random()
    C = Culm(sp, rng)
    kind = sp.get('kind', 'live')
    top_len = C.L * sp['break_at'] if kind == 'broken' else None
    Ltop = top_len or C.L
    cards, twigs = [], []
    br_from = sp['br_from'] * C.L
    crown_r = sp['crown_r']
    sprays = sp['sprays']
    tint_leaf = sp.get('leaf_tint', (1.0, 1.0, 1.0))
    az_branch = rng.uniform(0, math.tau)
    dens = sp.get('density', 1.0)
    for k, sl in enumerate(C.nodes):
        if sl < br_from or sl > Ltop - (0.15 if kind != 'broken' else 0.6):
            continue
        s_rel = (sl - br_from) / max(C.L - br_from, 1e-6)
        p, d = C.at(sl)
        x, y = frame(d, V(1, 0, 0))
        az = az_branch + (k % 2) * math.pi + rng.uniform(-0.35, 0.35)
        # 枝長：枝下高上方 25 % 最長、往梢漸短
        Lb = crown_r * (0.45 + 0.55 * math.sin(math.pi * min(1.0, s_rel / 0.5) * 0.5)) * (1.0 - 0.65 * s_rel ** 1.4)
        Lb *= rng.uniform(0.8, 1.15)
        dead_branch = kind == 'dead' and rng.random() < sp.get('broken_branch', 0.5)
        if dead_branch:
            Lb *= rng.uniform(0.25, 0.5)
        for bi, (az_b, f_len) in enumerate(((az, 1.0), (az + rng.uniform(0.5, 0.9) * (1 if k % 3 else -1), 0.6))):
            if bi == 1 and rng.random() > 0.7:
                continue
            out = nrm(x * math.cos(az_b) + y * math.sin(az_b))
            elev = math.radians(rng.uniform(45, 68))   # 與稈軸夾角（越大越水平）
            b0 = nrm(d * math.cos(elev) + out * math.sin(elev))
            L = Lb * f_len
            q0 = p + out * C.r(sl)
            q1 = q0 + b0 * L * 0.5
            b1 = nrm(b0 + V(0, -0.75, 0) + out * 0.35)
            q2 = q1 + b1 * L * 0.5
            twigs.append(([q0, q1, q2] if bi == 0 else [q0, q2], max(0.006, C.r(sl) * (0.26 if bi == 0 else 0.17)), 0.003,
                          0.45 + 0.15 * s_rel, 0.62))
            if dead_branch:
                continue
            n = max(1, int(round(L / 0.2 * dens * rng.uniform(0.8, 1.2))))
            for j in range(n):
                t = 0.35 + 0.65 * (j + rng.random() * 0.6) / n
                qa = q0 * (1 - t) + q2 * t if t > 0.5 else q0 * (1 - t * 2) * 0 + (q0 * (1 - t * 2) + q1 * (t * 2))
                if t > 0.5:
                    tt = (t - 0.5) * 2
                    qa = q1 * (1 - tt) + q2 * tt
                bd = b0 if t < 0.5 else b1
                upv = nrm(bd * 0.55 + V(0, -0.35, 0) + out * 0.5 + V(rng.gauss(0, 0.2), rng.gauss(0, 0.15), rng.gauss(0, 0.2)))
                rt = nrm(np.cross(upv, out + V(rng.gauss(0, 0.3), 0, rng.gauss(0, 0.3))))
                cell = rng.choices(sprays, weights=sp.get('spray_w', [1] * len(sprays)))[0]
                ao = 0.84 + 0.2 * t
                tn = tuple(tint_leaf[i] * ao * rng.uniform(0.94, 1.06) for i in range(3))
                axis_p, _ = C.at(sl)
                cards.append(Card(cell, qa, upv, rt, sp.get('card_s', 1.0) * rng.uniform(0.85, 1.15),
                                  0.75 + 0.2 * t, sp['_phase'], tn, rng.random() + t, axis_p + V(0, -0.3, 0), fold=1))
    # 梢頭：弓垂枝端掛 spray_hang
    if kind == 'live' and sp.get('hang', 0) > 0:
        for j in range(sp['hang']):
            sl = C.L * rng.uniform(0.86, 0.995)
            p, d = C.at(sl)
            side = perp(d)
            rt = nrm(rot(side, d, rng.uniform(0, 6.28)))
            upv = nrm(UP * 0.8 + d * 0.2)
            rt = nrm(rt - upv * float(np.dot(rt, upv)))
            tn = tuple(tint_leaf[i] * rng.uniform(0.95, 1.05) for i in range(3))
            cards.append(Card('spray_hang', p, upv, rt, sp.get('card_s', 1.0) * rng.uniform(0.9, 1.1), 0.95,
                              sp['_phase'], tn, 2.0 + rng.random(), p + V(0, -0.8, 0)))
    # 若竹：下部節帶筍皮——包覆稈的錐面（gen 端只記節位，網格在 sheath_wrap）
    sheath_to = sp.get('sheath_to', 0.0) * C.L
    sheaths = []
    for k, sl in enumerate(C.nodes[:-1]):
        if sl > sheath_to:
            break
        nxt = C.nodes[k + 1]
        sheaths.append((sl, (nxt - sl) * rng.uniform(0.95, 1.15), rng.uniform(0, math.tau),
                        'sheath' if rng.random() < 0.8 else 'sheath_dry'))
    return C, cards, twigs, sheaths, top_len


def build_culm(tid, sp):
    C, cards, twigs, sheaths, top_len = gen_culm(tid, sp)
    mat = MAT_CULM['dead' if sp.get('kind') in ('dead', 'broken') else 'green']
    tint = sp.get('culm_tint', (1.0, 1.0, 1.0))
    rng_card = random.Random(17)
    order = sorted(cards, key=lambda c: -c.imp)
    keep = {0: 1.0, 1: 0.4, 2: 0.14, 3: 0.075}
    scale = {0: 1.0, 1: 1.45, 2: 2.3, 3: 3.0}
    lods = []
    for lod in range(4):
        mb = MB('%s_LOD%d' % (tid, lod))
        culm_mesh(mb, C, lod, sp, mat, top_len, tint, splinter=sp.get('kind') == 'broken', rng=random.Random(5))
        for (pts, r0, r1, w0, w1) in twigs:
            twig_mesh(mb, pts, r0, r1, mat, w0, w1, sp['_phase'], lod)
        n_keep = max(2, int(round(len(order) * keep[lod]))) if order else 0
        # LOD 子集＝沿稈高度分層均勻抽（按卡片離地高度排序後等距取），避免遠景葉量全擠到梢頭
        by_h = sorted(cards, key=lambda c: c.p[1])
        pick = [by_h[min(len(by_h) - 1, int((i + 0.5) * len(by_h) / n_keep))] for i in range(n_keep)] if n_keep else []
        for c in pick:
            axis_p, _ = C.at(C.L * 0.75)
            emit_card(mb, c, scale[lod], pull_to=c.nc, fold=lod == 0)
        if lod <= 1:
            for (sl, hlen, az0, cell) in sheaths:
                sheath_wrap(mb, C, sl, hlen, az0, cell, lod, sp['_phase'])
        if sp.get('kind') == 'broken':
            fold_segment(mb, C, top_len, lod, mat, sp['_phase'], random.Random(9))
        lods.append(mb)
    coll = [{'type': 'cylinder', 'a': [0.0, -0.2, 0.0], 'b': [float(x) for x in C.at(min(3.0, (top_len or C.L) * 0.9))[0]],
             'r': float(C.r(0.5) * 1.02)}]
    coll[0]['b'][1] = float(min(3.0, (top_len or C.L) * 0.9))
    return lods, {'cards': len(cards), 'collision': coll, 'dbh_m': float(C.r(1.3) * 2), 'internodes': len(C.nodes) - 1}


def build_shoot(tid, sp):
    """筍：圓錐＋筍皮卡（3 圈、互疊、往上收）。"""
    rng = random.Random(41)
    H, R = sp['H'], sp['R']
    lods = []
    for lod in range(3):
        mb = MB('%s_LOD%d' % (tid, lod))
        mi = mb.mat(MAT_CULM['dead'])
        sides = {0: 8, 1: 5, 2: 4}[lod]
        hs = {0: [0.0, 0.25, 0.5, 0.75, 1.0], 1: [0.0, 0.5, 1.0], 2: [0.0, 0.5, 1.0]}[lod]
        rings = []
        for h in hs:
            y = -0.06 + h * (H + 0.06)
            r = R * (1 - h) ** 0.8 + 0.002
            ring = []
            for j in range(sides + 1):
                th = j / sides * math.tau
                nv = V(math.cos(th), 0.35, math.sin(th))
                ring.append(mb.v(V(math.cos(th) * r, y, math.sin(th) * r), nv, (j / sides, 1 - h), (0.05 * h, 0.3),
                                 (0.78, 0.6, 0.4, 0.0)))
            rings.append(ring)
        for q in range(len(rings) - 1):
            for j in range(sides):
                mb.f((rings[q][j], rings[q][j + 1], rings[q + 1][j + 1], rings[q + 1][j]), mi)
        n_sh = {0: 9, 1: 4, 2: 1}[lod]
        for k in range(n_sh):
            lvl = k // 3
            th = k * 2.1 + lvl * 0.6
            y0 = lvl * H * 0.22
            nv = V(math.cos(th), 0, math.sin(th))
            r = R * (1 - y0 / H) ** 0.8
            d = nrm(UP * 1.0 - nv * 0.18)
            rtv = nrm(np.cross(d, nv))
            hlen = H * (0.95 - lvl * 0.2)
            s = hlen / max(cell_h_m('sheath'), 1e-3)
            c = Card('sheath' if k % 4 else 'sheath_dry', nv * r * 1.05 + V(0, y0 - 0.03, 0), d, rtv, s * (1.25 if lod == 2 else 1.0),
                     0.05, 0.3, (1.0, 1.0, 1.0), 1.0, V(0, y0 + 0.1, 0))
            emit_card(mb, c, 1.0, fold=False)
        lods.append(mb)
    return lods, {'cards': 9, 'collision': [], 'dbh_m': 0.0}


def build_litter(tid, sp):
    """竹葉地被：落葉卡平鋪（離地 1–3 cm、方位亂、彼此重疊），中心密、外圈疏；與地面貼圖疊加。"""
    rng = random.Random(53)
    cards = []
    for k in range(sp['n']):
        rr = sp['R'] * math.sqrt(rng.random())
        th = rng.uniform(0, math.tau)
        p = V(math.cos(th) * rr, 0.012 + 0.002 * (k % 5), math.sin(th) * rr)
        a = rng.uniform(0, math.tau)
        upv = V(math.cos(a), 0, math.sin(a))
        rt = nrm(np.cross(UP, upv))
        cards.append(Card('litter', p, upv, rt, sp['card_s'] * rng.uniform(0.85, 1.15), 0.0, 0.0,
                          (rng.uniform(0.9, 1.05),) * 3, rng.random(), p + V(0, -1, 0)))
    lods = []
    for lod, frac in enumerate((1.0, 0.5, 0.215)):
        mb = MB('%s_LOD%d' % (tid, lod))
        n = max(3, int(round(len(cards) * frac)))
        for c in sorted(cards, key=lambda c: -c.imp)[:n]:
            r = AT['regions'][c.cell]
            mi = mb.mat(MAT_LEAF)
            u0, v0, u1, v1 = r['bbox_uv']
            S = r['cm_per_px'] / 100.0 * AW * c.s * (1.0 if lod == 0 else (1.25 if lod == 1 else 1.6))
            Sv = r['cm_per_px'] / 100.0 * AH * c.s * (1.0 if lod == 0 else (1.25 if lod == 1 else 1.6))
            uc, vc = (u0 + u1) * 0.5, (v0 + v1) * 0.5
            ids = []
            for (u, v) in [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]:
                q = c.p + c.rt * ((u - uc) * S) + c.up * ((vc - v) * Sv)
                ids.append(mb.v(q, UP, (u, v), (0.0, 0.0), (c.tint[0], c.tint[1], c.tint[2], 0.0)))
            mb.f(tuple(ids), mi)
        lods.append(mb)
    return lods, {'cards': len(cards), 'collision': [], 'dbh_m': 0.0}


# ───────────────────────── 變體 ─────────────────────────
SPRAY_LIVE = ['spray_a', 'spray_b']
SPECIES = {
    'take_mature': dict(group='bamboo', name='真竹（成竹、節下白粉、枝下高 5 m）', cls='bamboo', budget=3000, gen='culm',
                        H=13.5, D=0.085, n_node=46, br_from=0.40, lean=3.0, droop=42, crown_r=2.2, sprays=SPRAY_LIVE,
                        spray_w=[3, 2], density=1.0, hang=8, sides=8, seed=1),
    'take_thick': dict(group='bamboo', name='孟宗竹（太稈、梢大きく弓垂）', cls='bamboo', budget=3000, gen='culm',
                       H=17.5, D=0.17, n_node=58, br_from=0.55, lean=2.0, droop=80, crown_r=2.6, sprays=SPRAY_LIVE,
                       spray_w=[1, 4], density=1.35, hang=14, sides=10, seed=2, culm_tint=(0.86, 0.95, 0.9),
                       leaf_tint=(1.02, 1.06, 0.92), card_s=0.85),
    'take_thin': dict(group='bamboo', name='淡竹（細稈、密な小枝）', cls='bamboo', budget=3000, gen='culm',
                      H=9.5, D=0.055, n_node=38, br_from=0.34, lean=4.0, droop=30, crown_r=1.6, sprays=['spray_a', 'spray_b'],
                      spray_w=[2, 1], density=1.05, hang=4, sides=6, seed=3, card_s=0.9),
    'take_young': dict(group='bamboo', name='若竹（今年竹、籜付き、明るい緑）', cls='bamboo', budget=3000, gen='culm',
                       H=11.5, D=0.085, n_node=42, br_from=0.64, lean=1.5, droop=14, crown_r=1.3, sprays=['spray_young'],
                       density=0.8, hang=2, sides=8, seed=4, sheath_to=0.3, culm_tint=(1.08, 1.12, 0.9),
                       leaf_tint=(1.04, 1.06, 0.95)),
    'take_lean': dict(group='bamboo', name='傾き竹（斜立・弓なり、林縁で外へ）', cls='bamboo', budget=3000, gen='culm',
                      H=13.0, D=0.09, n_node=44, br_from=0.4, lean=18.0, droop=48, crown_r=2.1, sprays=SPRAY_LIVE,
                      spray_w=[3, 2], density=0.95, hang=8, sides=8, seed=5, wob=0.03),
    'take_dead': dict(group='bamboo', name='枯竹（立枯れ、灰黄、枝折れ）', cls='bamboo', budget=3000, gen='culm', kind='dead',
                      H=10.5, D=0.08, n_node=40, br_from=0.42, lean=5.0, droop=8, crown_r=1.4, sprays=['spray_dry'],
                      density=0.25, broken_branch=0.6, sides=7, seed=6, leaf_tint=(0.95, 0.93, 0.88), culm_tint=(0.82, 0.8, 0.76)),
    'take_broken': dict(group='bamboo', name='折れ竹（中折れ、裂けた稈口）', cls='bamboo', budget=3000, gen='culm', kind='broken',
                        H=13.0, break_at=0.52, D=0.09, n_node=44, br_from=0.36, lean=6.0, droop=4, crown_r=1.3,
                        sprays=['spray_dry'], density=0.45, sides=8, seed=7),
    'takenoko': dict(group='bamboo_under', name='筍（地上部 0.35 m、籜で包まれる）', cls='under', budget=500, gen='shoot',
                     H=0.36, R=0.075),
    'take_litter': dict(group='bamboo_under', name='竹の落葉（地被パッチ、径 2.4 m）', cls='litter', budget=200, gen='litter',
                        n=26, R=1.2, card_s=1.05),
}
GROUP_NAMES = {'bamboo': '竹稈（真竹／孟宗竹／淡竹 系）', 'bamboo_under': '筍／竹の落葉'}
LOD_DIST = {'bamboo': [0, 25, 60, 140, 500], 'under': [0, 15, 35, 70], 'litter': [0, 12, 30, 60]}
BUDGET_CAP = {'bamboo': 3000, 'under': 1000, 'litter': 600}


def build(tid):
    sp = dict(SPECIES[tid])
    t0 = time.time()
    if sp['gen'] == 'culm':
        lods, extra = build_culm(tid, sp)
    elif sp['gen'] == 'shoot':
        lods, extra = build_shoot(tid, sp)
    else:
        lods, extra = build_litter(tid, sp)
    info = {'group': sp['group'], 'group_name': GROUP_NAMES[sp['group']], 'name': sp['name'], 'cls': sp['cls'],
            'budget': sp['budget'], 'budget_cap': BUDGET_CAP[sp['cls']], 'lod_dist': LOD_DIST[sp['cls']][:len(lods) + 1],
            'lods': [], 'collision': extra['collision'], 'cards': extra['cards']}
    for mb in lods:
        a, b = mb.aabb()
        info['lods'].append({'name': mb.name, 'tris': mb.tris(), 'mats': mb.mats, 'aabb': [a.tolist(), b.tolist()]})
    a, b = lods[0].aabb()
    info['height'] = float(b[1])
    info['crown_w'] = float(max(b[0] - a[0], b[2] - a[2]))
    info['dbh_m'] = extra['dbh_m']
    if 'internodes' in extra:
        info['internodes'] = extra['internodes']
    info['secs'] = round(time.time() - t0, 2)
    return lods, info


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    only = []
    for a in argv:
        if a.startswith('--only='):
            only = [x for x in a[7:].split(',') if x]
    ids = only or list(SPECIES)
    K.clear_scene(bpy)
    mats = set()
    built = {}
    for tid in ids:
        lods, info = build(tid)
        built[tid] = (lods, info)
        for mb in lods:
            mats.update(mb.mats)
        print('[bamboo] %-12s %s  LOD tris %s  cards %d  H %.2f  W %.2f  dbh %.3f  (%.2fs)' % (
            tid, info['name'], [l['tris'] for l in info['lods']], info['cards'], info['height'], info['crown_w'],
            info['dbh_m'], info['secs']), flush=True)
    if only:
        print('[bamboo] --only 試算完成（未寫 src/）')
        return
    bm = K.blender_mats(bpy, sorted(mats))
    objs = []
    modules = {}
    for tid, (lods, info) in built.items():
        for mb in lods:
            objs.append(mb.to_blender(bm))
            modules[mb.name] = {'tris': mb.tris()}
    os.makedirs(KIT + '/src', exist_ok=True)
    K.export_glb(bpy, KIT + '/src/bamboo_kit.glb', objs)
    K.write_json(KIT + '/src/modules_blender.json', {
        '_note': 'P9 R3 竹 Kit。由 godot/assets/blender/village_v2/build_bamboo_kit.py 產生，勿手改。',
        'modules': modules, 'total_tris': sum(m['tris'] for m in modules.values()),
        'trees': {tid: info for tid, (lods, info) in built.items()}, 'groups': GROUP_NAMES, 'only': only})
    print('[bamboo] %d 變體、%d 物件 → %s/src/bamboo_kit.glb' % (len(built), len(objs), KIT))


main()
