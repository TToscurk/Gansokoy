"""人間之里 V2 P9 R1：Gensokyo Vegetation Library（自製 production tree kit）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_veg_kit.py [-- --only=id1,id2（試算，不寫檔）]

不用舊 Tripo 樹：全部程序生成（杉檜／松／枯木＝顯式分枝規則；闊葉／櫻／楓／柳／Hero＝space colonization，
樹冠包絡＝數個橢球 lobe ＋ 挖洞 → 不對稱、偏心、局部缺口、留光洞），葉＝共用葉叢卡（tools/build_village_v2_veg_textures.py
的 atlas，每種 2–4 種 cluster），樹皮＝Poly Haven CC0 校色。

輸出（godot/assets/village_v2/veg_kit/src/）：
  veg_kit.glb              每個變體 <id>_LOD0..LOD3（灌木地被 LOD0..LOD2）；材質佔位名 VK_Bark_<種>／VK_Leaf_A／VK_Leaf_B
  modules_blender.json     prefab 用：每物件三角面；trees＝每變體尺寸、碰撞、LOD 距離、預算、實測 AABB

慣例（與 v2_kit 相同）：Godot 座標（x 右、y 上、+z 前）、公尺。原點＝根部自然接地點（樹幹中心、y 0＝地面）；
樹幹往地下延伸 embed（坡地不懸空），不帶土台。
頂點資料（wind-ready；之後接 Global Wind Manager，見 veg_kit/shader/veg_wind.gdshaderinc）：
  COLOR.rgb＝反照率乘數（樹皮：根部 AO／北側苔／赤松上部赤褐；葉卡：叢內 AO、lobe 間克制色差）
  COLOR.a  ＝葉卡細抖遮罩（附著端 0 → 外緣 1；樹皮 0）
  UV2.x    ＝彎曲權重：樹幹 ≈ 0（頂端 ≤ 0.1）→ 主枝弱 → 小枝中 → 葉叢強（外緣 → 1.0）
  UV2.y    ＝相位（每主枝一個，子枝沿用＋微差）
葉卡法線＝樹冠 lobe 球面法線（遠看像體積而不是一片片卡）；shader 背面不翻法線。
"""
import json
import math
import os
import random
import sys
import time
import zlib

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
KIT = G + '/assets/village_v2/veg_kit'
TEXJ = K.load_json(KIT + '/tex/veg_tex.json')
ATLAS = 2048
UP = np.array((0.0, 1.0, 0.0))
GOLD = math.radians(137.508)


# ───────────────────────── 向量 ─────────────────────────
def V(x, y, z):
    return np.array((x, y, z), dtype=np.float64)


def nrm(a):
    n = float(np.linalg.norm(a))
    return a / n if n > 1e-9 else np.array(a, dtype=np.float64)


def rot(v, axis, ang):
    k = nrm(axis)
    c, s = math.cos(ang), math.sin(ang)
    return v * c + np.cross(k, v) * s + k * float(np.dot(k, v)) * (1 - c)


def perp(d):
    a = UP if abs(d[1]) < 0.9 else V(1, 0, 0)
    return nrm(np.cross(d, a))


def clamp(x, a, b):
    return a if x < a else (b if x > b else x)


def sstep(a, b, x):
    t = clamp((x - a) / (b - a), 0.0, 1.0) if b != a else (1.0 if x >= a else 0.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def hdir(az, elev=0.0):
    """方位角 az（x→z）、仰角 elev（rad）→ 單位向量。"""
    return V(math.cos(elev) * math.cos(az), math.sin(elev), math.cos(elev) * math.sin(az))


def turn_toward(d, target, ang):
    """d 往 target 轉 ang（rad），不超過。"""
    d, target = nrm(d), nrm(target)
    c = clamp(float(np.dot(d, target)), -1.0, 1.0)
    a = math.acos(c)
    if a < 1e-6:
        return d
    ax = np.cross(d, target)
    if np.linalg.norm(ax) < 1e-9:
        ax = perp(d)
    return nrm(rot(d, ax, min(ang, a)))


# ───────────────────────── 網格建構 ─────────────────────────
class MB:
    """單一 LOD 網格：每頂點 位置／法線／UV／UV2／RGBA；面＝頂點索引＋材質。"""

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
        self.N.append(tuple(float(x) for x in nrm(n)))
        self.UV.append((float(uv[0]), float(uv[1])))
        self.UV2.append((float(uv2[0]), float(uv2[1])))
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
        nl = len(me.loops)
        lvi = np.zeros(nl, dtype=np.int64)
        me.loops.foreach_get('vertex_index', lvi)
        uv = np.asarray(self.UV, dtype=np.float32)[lvi]
        uv[:, 1] = 1.0 - uv[:, 1]
        l1 = me.uv_layers.new(name='UVMap')
        l1.data.foreach_set('uv', uv.ravel())
        uv2 = np.asarray(self.UV2, dtype=np.float32)[lvi]
        uv2[:, 1] = 1.0 - uv2[:, 1]          # glTF 匯出再翻一次 → Godot UV2 ＝ (權重, 相位)
        l2 = me.uv_layers.new(name='UV2')
        l2.data.foreach_set('uv', uv2.ravel())
        me.uv_layers.active = l1
        col = me.color_attributes.new(name='Col', type='FLOAT_COLOR', domain='CORNER')
        col.data.foreach_set('color', np.asarray(self.C, dtype=np.float32)[lvi].ravel())
        me.color_attributes.active_color = col
        np_ = len(me.polygons)
        me.polygons.foreach_set('material_index', np.asarray(self.FM, dtype=np.int32))
        me.polygons.foreach_set('use_smooth', np.ones(np_, dtype=bool))
        for m in self.mats:
            me.materials.append(bmats[m])
        n = np.asarray(self.N, dtype=np.float64)[lvi]
        bn = np.stack([n[:, 0], -n[:, 2], n[:, 1]], 1)
        me.normals_split_custom_set([tuple(x) for x in bn])
        me.update()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


# ───────────────────────── 骨架 ─────────────────────────
class Chain:
    """一條枝（或樹幹、根、殘枝）：點列＋半徑。kind：wood／stub（枯殘枝）／root（地表根）。"""

    def __init__(self, pts, rad, lvl, parent=None, kind='wood'):
        self.pts = [np.asarray(p, dtype=np.float64) for p in pts]
        self.rad = [float(r) for r in rad]
        self.lvl = lvl
        self.parent = parent
        self.kind = kind
        self.w = None
        self.phase = 0.0
        self.attach_w = 0.0

    def length(self):
        return sum(float(np.linalg.norm(self.pts[i + 1] - self.pts[i])) for i in range(len(self.pts) - 1))


class Card:
    __slots__ = ('cell', 'p', 'up', 'rt', 's', 'w', 'phase', 'tint', 'imp', 'kind', 'nc', 'cl')

    def __init__(self, cell, p, up, rt, s, w, phase, tint=(1.0, 1.0, 1.0), imp=1.0, kind='leaf', nc=None, cl=-1):
        self.cell, self.p, self.up, self.rt, self.s = cell, np.asarray(p, dtype=np.float64), up, rt, s
        self.w, self.phase, self.tint, self.imp, self.kind = w, phase, tint, imp, kind
        self.nc = nc       # 葉卡法線中心覆寫（杉檜葉團：團心偏內下；None＝依 normal_mode）
        self.cl = cl       # 所屬葉團（lod_mode='clump' 的 LOD 依葉團配額／合併；-1＝無）


def cell_info(cell):
    at, name = cell
    r = TEXJ['atlas'][at]['regions'][name]
    return at, r


def card_axes(up, roll, rng=None, flat=False, tilt=0.0, face=None):
    """card 平面：up（附著端→外緣）＋ rt。flat＝平面接近水平；face＝希望法線大致朝的方向。"""
    up = nrm(up)
    if flat:
        rt = np.cross(up, UP)
        if np.linalg.norm(rt) < 1e-3:
            rt = perp(up)
        rt = nrm(rt)
        rt = nrm(rot(rt, up, roll * tilt))
    else:
        rt = nrm(rot(perp(up), up, roll))
        if face is not None:
            n = np.cross(rt, up)
            if float(np.dot(n, face)) < 0:
                rt = -rt
    return up, rt


# ───────────────────────── space colonization ─────────────────────────
def sc_grow(seed_pos, seed_par, seed_grow, attract, D, di, dk, trop, rng, iters=500, max_nodes=7000):
    P = np.zeros((max_nodes + 64, 3))
    n = len(seed_pos)
    P[:n] = np.asarray(seed_pos)
    par = list(seed_par)
    A = np.asarray(attract, dtype=np.float64)
    alive = np.ones(len(A), dtype=bool)
    nd = np.full(len(A), np.inf)
    ni = np.full(len(A), -1, dtype=np.int64)
    lastchild = {}

    def upd(idx):
        if not idx:
            return
        idx = np.asarray(idx, dtype=np.int64)
        Q = P[idx]
        d = np.sqrt(((A[:, None, :] - Q[None, :, :]) ** 2).sum(2))
        j = d.argmin(1)
        dm = d[np.arange(len(A)), j]
        b = dm < nd
        nd[b] = dm[b]
        ni[b] = idx[j[b]]

    upd([i for i in range(n) if seed_grow[i]])
    for it in range(iters):
        alive &= ~(nd < dk)
        sel = alive & (nd < di)
        if not sel.any():
            break
        src = ni[sel]
        vec = A[sel] - P[src]
        vec /= np.linalg.norm(vec, axis=1, keepdims=True) + 1e-9
        acc = np.zeros((n, 3))
        np.add.at(acc, src, vec)
        cnt = np.bincount(src, minlength=n)
        new = []
        for j in np.nonzero(cnt)[0]:
            v = acc[j]
            L = float(np.linalg.norm(v))
            if L < 0.15 * cnt[j]:      # 兩側拉扯幾乎抵銷 → 加一點擾動
                v = v + V(rng.gauss(0, 0.3), rng.gauss(0, 0.3), rng.gauss(0, 0.3)) * cnt[j]
                L = float(np.linalg.norm(v))
            d = v / max(L, 1e-9) + trop
            d = nrm(d)
            q = P[j] + d * D
            lc = lastchild.get(int(j))
            if lc is not None and float(np.linalg.norm(P[lc] - q)) < 0.25 * D:
                continue
            if n >= max_nodes:
                break
            P[n] = q
            par.append(int(j))
            lastchild[int(j)] = n
            new.append(n)
            n += 1
        if not new:
            break
        upd(new)
        if n >= max_nodes:
            break
    return P[:n].copy(), par


def sample_lobes(lobes, n, rng, holes=()):
    """在 lobe（橢球聯集）內均勻取樣；holes＝(中心, 半徑) 挖空。"""
    lo = np.min([c - r for c, r, _ in lobes], 0)
    hi = np.max([c + r for c, r, _ in lobes], 0)
    out = []
    tries = 0
    while len(out) < n and tries < n * 60:
        tries += 1
        p = V(rng.uniform(lo[0], hi[0]), rng.uniform(lo[1], hi[1]), rng.uniform(lo[2], hi[2]))
        ok = False
        for c, r, w in lobes:
            q = (p - c) / r
            if float(np.dot(q, q)) <= 1.0 and rng.random() < w:
                ok = True
                break
        if not ok:
            continue
        if any(float(np.linalg.norm(p - hc)) < hr for hc, hr in holes):
            continue
        out.append(p)
    return np.asarray(out)


def nodes_to_chains(P, par, R, node_kind=None):
    n = len(P)
    kids = [[] for _ in range(n)]
    for i in range(1, n):
        if par[i] >= 0:
            kids[par[i]].append(i)
    desc = np.ones(n)
    for i in range(n - 1, 0, -1):
        if par[i] >= 0:
            desc[par[i]] += desc[i]
    chains = []
    node_chain = {}
    stack = [(0, None, None, 0)]
    while stack:
        start, pch, from_node, lvl = stack.pop()
        nodes = [from_node] if from_node is not None else []
        k = start
        side = []
        while True:
            nodes.append(k)
            ks = sorted(kids[k], key=lambda c: -desc[c])
            if not ks:
                break
            for s in ks[1:]:
                side.append((s, k))
            k = ks[0]
        ch = Chain([P[i] for i in nodes], [R[i] for i in nodes], lvl, pch)
        ch.nodes = nodes
        chains.append(ch)
        for i in nodes[1:] if from_node is not None else nodes:
            node_chain[i] = ch
        for s, at in side:
            stack.append((s, ch, at, lvl + 1))
    return chains, node_chain, kids, desc


# ───────────────────────── 樹 ─────────────────────────
class Tree:
    def __init__(self, tid, sp):
        self.id, self.sp = tid, sp
        self.rng = random.Random(zlib.crc32(tid.encode()) ^ sp.get('seed', 0))
        self.chains = []
        self.cards = []
        self.H = sp.get('H', 1.0)
        self.r0 = sp.get('dbh', 0.1) / 2
        self.light_az = sp.get('light_az', self.rng.uniform(0, 2 * math.pi))
        self.lobes = []          # 葉卡法線中心（k-means 後填）
        self.trunk = None
        self.flare_lobes = []
        self.coll = []

    # 樹幹路徑：傾斜＋低頻彎曲（＋S 形）
    def trunk_path(self, h_top, n=None, lean=None, wob=None, s_curve=0.0, base=V(0, 0, 0), lean_az=None):
        sp, rng = self.sp, self.rng
        lean = math.radians(sp.get('lean', 1.5) if lean is None else lean)
        wob = sp.get('wob', 0.2) if wob is None else wob
        laz = self.light_az + rng.uniform(-0.6, 0.6) if lean_az is None else lean_az
        ldir = V(math.cos(laz), 0, math.sin(laz))
        ph = [rng.uniform(0, 6.28) for _ in range(4)]
        n = n or max(6, int(h_top / 0.5))
        pts = []
        for i in range(n + 1):
            y = h_top * i / n
            t = y / max(h_top, 1e-6)
            off = ldir * math.tan(lean) * y * (0.6 + 0.4 * t)
            off = off + V(math.sin(t * 3.1 + ph[0]) - math.sin(ph[0]), 0, math.sin(t * 2.7 + ph[1]) - math.sin(ph[1])) * wob * t
            if s_curve:
                off = off + V(math.cos(laz + 1.57), 0, math.sin(laz + 1.57)) * s_curve * math.sin(t * math.pi * 1.6 + ph[2]) * t
            pts.append(base + V(off[0], y, off[2]))
        return pts

    def setup_flare(self):
        sp, rng = self.sp, self.rng
        nl = sp.get('lobes', 5)
        a0 = rng.uniform(0, 6.28)
        self.flare_lobes = [(a0 + i * 2 * math.pi / nl + rng.uniform(-0.35, 0.35), rng.uniform(0.5, 1.0) * sp.get('lobe_amp', 0.2),
                             rng.uniform(0.25, 0.45)) for i in range(nl)]

    def flare_mul(self, y, th):
        sp = self.sp
        fh = sp.get('flare_h', 1.2)
        yy = max(0.0, y)
        m = 1.0 + sp.get('flare', 0.35) * math.exp(-yy / fh * 2.2)
        lob = 0.0
        for a, s, w in self.flare_lobes:
            d = math.atan2(math.sin(th - a), math.cos(th - a))
            lob += s * math.exp(-(d / w) ** 2)
        m *= 1.0 + lob * math.exp(-yy / (fh * 0.8) * 2.0)
        return m

    def trunk_r(self, y):
        ch = self.trunk
        if ch is None:
            return self.r0
        ys = [p[1] for p in ch.pts]
        if y <= ys[0]:
            return ch.rad[0]
        for i in range(len(ys) - 1):
            if ys[i] <= y <= ys[i + 1]:
                t = (y - ys[i]) / max(ys[i + 1] - ys[i], 1e-6)
                return lerp(ch.rad[i], ch.rad[i + 1], t)
        return ch.rad[-1]

    def trunk_at(self, y):
        ch = self.trunk
        ys = [p[1] for p in ch.pts]
        for i in range(len(ys) - 1):
            if ys[i] <= y <= ys[i + 1]:
                t = (y - ys[i]) / max(ys[i + 1] - ys[i], 1e-6)
                return ch.pts[i] + (ch.pts[i + 1] - ch.pts[i]) * t, nrm(ch.pts[i + 1] - ch.pts[i])
        return ch.pts[-1], nrm(ch.pts[-1] - ch.pts[-2])

    def pick_cell(self, cells=None):
        cells = cells or self.sp['cells']
        tot = sum(c[2] for c in cells)
        r = self.rng.random() * tot
        for c in cells:
            r -= c[2]
            if r <= 0:
                return (c[0], c[1])
        return (cells[-1][0], cells[-1][1])

    def add_card(self, p, up, rt, s, w, phase, cell=None, imp=1.0, tint=(1.0, 1.0, 1.0), kind='leaf', nc=None, cl=-1):
        self.cards.append(Card(cell or self.pick_cell(), p, up, rt, s, w, phase, tint, imp, kind, nc, cl))


# ───────────── 顯式針葉（杉／檜） ─────────────
def gen_conifer(T):
    sp, rng = T.sp, T.rng
    H, r0 = T.H, T.r0
    T.setup_flare()
    top_h = H * sp.get('broken', 1.0)
    pts = T.trunk_path(top_h)
    # 斷頂：以「原本的樹高」算 taper（斷口處仍粗，約 r0 的 45 %）→ 遠看是折斷的粗幹，不是細尖
    Ht = top_h / sp.get('break_frac', 0.6) if sp.get('broken', 1.0) < 1.0 else H
    rad = [max(0.012, r0 * (1 - p[1] / Ht) ** sp.get('taper', 0.85) * (1 + 0.10 * math.exp(-p[1] / 1.5))) for p in pts]
    if sp.get('broken', 1.0) < 1.0:
        rad[-1] = rad[-2] * 0.9
    T.trunk = Chain(pts, rad, 0)
    T.chains.append(T.trunk)
    cbH = H * sp['cb']
    # 斷頂老杉：上部 2–3 根側枝轉成副主幹（燭台狀頂）
    if sp.get('broken', 1.0) < 1.0:
        # 燭台：側枝轉成副主幹，先外張 1.5–2.6 m 再轉上，頂端在斷口上下 → 多峰平頂，中央是裸露斷幹
        a0 = T.light_az + rng.uniform(-0.5, 0.5)
        nl = sp.get('leaders', 2)
        for k in range(nl):
            y0 = top_h - rng.uniform(*sp.get('leader_from', (3.8, 5.6)))
            p0, d0 = T.trunk_at(y0)
            az = a0 + k * 2 * math.pi / nl + rng.uniform(-0.4, 0.4)
            out = rng.uniform(*sp.get('leader_out', (1.5, 2.6)))
            rise = (top_h - y0) + rng.uniform(*sp.get('leader_rise', (-1.2, 0.3)))
            # 外張段（近水平、略上）＋ 立起段
            q = [p0]
            m1, m2 = 4, 7
            for i in range(1, m1 + 1):
                q.append(p0 + hdir(az) * out * i / m1 + UP * rise * 0.18 * (i / m1) ** 1.5)
            pe = q[-1]
            for i in range(1, m2 + 1):
                t = i / m2
                q.append(pe + hdir(az) * 0.35 * t + UP * rise * 0.82 * t + V(rng.gauss(0, 0.05), 0, rng.gauss(0, 0.05)))
            n = len(q)
            rr = T.trunk_r(y0) * 0.55
            ch = Chain(q, [rr * (1 - 0.75 * i / (n - 1)) + 0.01 for i in range(n)], 1, T.trunk)
            T.chains.append(ch)
            emit_conifer_branches(T, ch, y_from=pe[1] + 0.2, y_to=q[-1][1] - 0.3, Lscale=sp.get('leader_L', 0.45))
            # 每個副峰自己的尖頂葉卡
            for j in range(sp.get('leader_top_cards', 4)):
                tp = q[-1] - UP * rng.uniform(0.0, 1.0)
                up = nrm(UP + hdir(rng.uniform(0, 6.28)) * rng.uniform(0.15, 0.45))
                u, rt = card_axes(up, rng.uniform(0, 6.28))
                T.add_card(tp, u, rt, rng.uniform(*sp['card']) * 0.75, 0.12, rng.random(), imp=3.0)
    emit_conifer_branches(T, T.trunk, y_from=cbH, y_to=(top_h - sp.get('bare_top', 2.4)) if sp.get('broken', 1.0) < 1.0
                          else top_h * 0.985, Lscale=1.0)
    if sp.get('broken', 1.0) < 1.0:
        T.trunk.broken = True
        add_splinters(T)
    cf = sp.get('core_fill', 0.0)
    if cf:
        y_hi = (top_h - sp.get('bare_top', 2.4)) if sp.get('broken', 1.0) < 1.0 else top_h * 0.96
        y = cbH + 0.2
        while y < y_hi:
            h = (y - cbH) / max(y_hi - cbH, 1e-6)
            env = max(0.08, 1 - h ** sp.get('env_q', 1.0)) ** sp.get('env_pow', 0.85)
            rr = sp['Lmax'] * env
            for k in range(2):
                az = rng.uniform(0, 6.28)
                tp, _ = T.trunk_at(y)
                o = hdir(az) * rr * rng.uniform(0.15, 0.5)
                d = nrm(hdir(az, math.radians(rng.uniform(-10, 25))))
                place_conifer_card(T, tp + o, d, h, 1.0, imp=0.6)
            y += cf * rng.uniform(0.8, 1.2)
    # 樹冠下的枯殘枝（分枝高度差、老樹感）
    if sp.get('stubs', True):
        y = 1.6
        while y < cbH - 0.3:
            y += rng.uniform(0.35, 1.0)
            if rng.random() > 0.55 or y >= cbH:
                continue
            p0, _ = T.trunk_at(y)
            d = hdir(rng.uniform(0, 6.28), math.radians(rng.uniform(-25, 5)))
            L = rng.uniform(0.12, 0.6) * (1 + y / H)
            rr = rng.uniform(0.015, 0.035) * (r0 / 0.35) ** 0.5
            T.chains.append(Chain([p0, p0 + d * (T.trunk_r(y) + L)], [rr * 1.2, rr * 0.7], 1, T.trunk, 'stub'))
    # 樹頂：沿主幹最上 1.3 m 的朝上葉卡（杉的尖頂）
    if sp.get('broken', 1.0) >= 1.0:
        for k in range(sp.get('top_cards', 6)):
            y = top_h - rng.uniform(0.0, 1.4)
            p0, d0 = T.trunk_at(min(y, top_h - 0.05))
            up = nrm(d0 + hdir(rng.uniform(0, 6.28)) * rng.uniform(0.15, 0.5))
            u, rt = card_axes(up, rng.uniform(0, 6.28))
            T.add_card(p0, u, rt, rng.uniform(*sp['card']) * 0.8, 0.12, rng.random(), imp=3.0)


def emit_conifer_branches(T, host, y_from, y_to, Lscale):
    sp, rng = T.sp, T.rng
    H = T.H
    y = y_from
    az = rng.uniform(0, 6.28)
    gap_sec = [(rng.uniform(0, 6.28), rng.uniform(0.5, 1.1), rng.uniform(y_from, y_to), rng.uniform(1.5, 4.0))
               for _ in range(sp.get('gaps', 2))]
    Lmax = sp['Lmax'] * Lscale
    host_is_trunk = host is T.trunk
    while y < y_to:
        y += rng.uniform(*sp['br_step']) * (0.7 + 0.5 * (H / 24.0) ** 0.5)
        if y >= y_to:
            break
        h = (y - y_from) / max(y_to - y_from, 1e-6)
        az += GOLD + rng.uniform(-0.45, 0.45)
        if rng.random() < sp.get('gap', 0.1):
            continue
        Lf = 1.0
        for ga, gw, gy, gh in gap_sec:
            dd = abs(math.atan2(math.sin(az - ga), math.cos(az - ga)))
            if dd < gw and abs(y - gy) < gh * 0.5:
                Lf = rng.uniform(0.0, 0.4)
        if Lf < 0.12:
            continue
        q = sp.get('env_q', 1.0)
        env = max(0.0, 1 - h ** q) ** sp.get('env_pow', 0.85)
        env = max(env, 0.08)
        L = Lmax * env * Lf * (1 + sp.get('ecc', 0.2) * math.cos(az - T.light_az)) * rng.uniform(0.75, 1.15)
        L = max(L, 0.35)
        elev = math.radians(lerp(sp['ang'][0], sp['ang'][1], h) + rng.uniform(-8, 8))
        if host_is_trunk:
            p0, _ = T.trunk_at(y)
            rt = T.trunk_r(y)
        else:
            # 副主幹：找最近點
            i = min(range(len(host.pts)), key=lambda k: abs(host.pts[k][1] - y))
            p0, rt = host.pts[i], host.rad[i]
        d = hdir(az, elev)
        nseg = max(3, int(L / 0.45))
        pts = [p0]
        droop = math.radians(sp.get('droop', 10)) * (1 - h)
        upturn = math.radians(sp.get('upturn', 25))
        for k in range(nseg):
            t = k / nseg
            if t < 0.5:
                d = turn_toward(d, -UP, droop / nseg * 2)
            else:
                d = turn_toward(d, UP, upturn / nseg * 2)
            d = nrm(d + V(rng.gauss(0, 0.06), rng.gauss(0, 0.04), rng.gauss(0, 0.06)))
            pts.append(pts[-1] + d * (L + (rt if k == 0 else 0)) / nseg)
        rb = clamp(rt * 0.42 * (L / max(Lmax, 0.1)) ** 0.5, 0.012, rt * 0.75)
        rad = [rb * (1 - 0.8 * k / nseg) for k in range(nseg + 1)]
        br = Chain(pts, rad, host.lvl + 1, host)
        dead_branch = rng.random() < sp.get('dead_br', 0.0) * (1 - h)
        if dead_branch:
            br.kind = 'stub'
            br.pts = br.pts[:max(2, nseg // 2 + 1)]
            br.rad = br.rad[:len(br.pts)]
        T.chains.append(br)
        if dead_branch:
            continue
        # 二次枝＋葉卡
        side = 1 if rng.random() < 0.5 else -1
        Lb = br.length()
        s = Lb * rng.uniform(0.18, 0.3)
        while s < Lb * 0.97:
            idx = min(len(br.pts) - 2, int(s / Lb * (len(br.pts) - 1)))
            tt = s / Lb
            p = br.pts[idx] + (br.pts[idx + 1] - br.pts[idx]) * ((s / Lb * (len(br.pts) - 1)) - idx)
            bd = nrm(br.pts[idx + 1] - br.pts[idx])
            hz = nrm(np.cross(bd, UP)) if abs(bd[1]) < 0.95 else perp(bd)
            sd = nrm(rot(bd, np.cross(bd, hz), side * math.radians(rng.uniform(*sp.get('sec_ang', (35, 60))))))
            sd = nrm(sd + UP * sp.get('sec_up', 0.05))
            side = -side
            Ls = max(0.25, L * sp.get('sec_len', 0.36) * (1 - 0.55 * tt) * rng.uniform(0.7, 1.2))
            q2 = [p, p + sd * Ls * 0.5, p + nrm(sd + UP * 0.1) * Ls]
            rr = max(0.006, rad[min(idx, len(rad) - 1)] * 0.4)
            sec = Chain(q2, [rr, rr * 0.7, rr * 0.3], br.lvl + 1, br)
            T.chains.append(sec)
            # 葉卡沿二次枝
            st = sp.get('card_step', 0.45)
            u = Ls * 0.35
            while u <= Ls + 1e-6:
                pp = p + sd * u if u < Ls * 0.5 else q2[1] + nrm(q2[2] - q2[1]) * (u - Ls * 0.5)
                place_conifer_card(T, pp, sd, h, 1.0)
                u += st * rng.uniform(0.8, 1.2)
            s += rng.uniform(*sp.get('sec_step', (0.3, 0.45)))
        # 主枝外段葉卡＋枝端簇
        u = Lb * 0.45
        while u < Lb:
            idx = min(len(br.pts) - 2, int(u / Lb * (len(br.pts) - 1)))
            place_conifer_card(T, br.pts[idx], nrm(br.pts[idx + 1] - br.pts[idx]), h, 1.1)
            u += sp.get('card_step', 0.45) * 1.3
        for k in range(sp.get('tip_cards', 2)):
            place_conifer_card(T, br.pts[-1], nrm(br.pts[-1] - br.pts[-2]), h, 1.15, imp=2.0)


def place_conifer_card(T, p, d, h, sm, imp=1.0):
    sp, rng = T.sp, T.rng
    out = V(p[0], 0, p[2]) - V(*T.trunk_at(p[1])[0][[0]], 0, T.trunk_at(p[1])[0][2]) if False else None
    tp, _ = T.trunk_at(clamp(p[1], 0.01, T.trunk.pts[-1][1] - 0.01))
    o = p - tp
    o[1] = 0
    o = nrm(o) if np.linalg.norm(o) > 1e-3 else perp(d)
    up = nrm(d * 0.6 + o * 0.45 + UP * sp.get('card_up', 0.05) + V(rng.gauss(0, 0.12), rng.gauss(0, 0.1), rng.gauss(0, 0.12)))
    if sp.get('roll') == 'flat':
        u, rt = card_axes(up, rng.uniform(-1, 1), flat=True, tilt=math.radians(sp.get('flat_tilt', 35)))
        if rng.random() < sp.get('flat_mix', 0.3):
            u, rt = card_axes(up, rng.uniform(0, 6.28), face=o)
    else:
        u, rt = card_axes(up, rng.uniform(0, 6.28), face=o)
    s = rng.uniform(*sp['card']) * sm * (0.8 + 0.3 * (1 - h))
    T.add_card(p, u, rt, s, None, None, imp=imp * (1.0 + 0.5 * (1 - h)))


# ───────────── 杉／檜 R1b：葉團（clump）＋樹齡脫枝＋方位不對稱＋樹梢個體差 ─────────────
# R1 審圖（使用者 2026-10-01）：杉近實心錐／聖誕樹輪廓、枝從冠底等距排到頂、樹梢一律尖錐；檜是一層層水平板；
#   御神木只靠粗幹。重做：
#   ・葉＝葉團（杉：枝端圓團狀簇；檜：沿枝下垂的扇形噴枝，扇面繞枝軸各自傾轉 → 有厚度、不疊盤子）
#   ・冠層分布＝樹齡模型：冠下層枝存活率低（脫枝、留枯殘枝），中層最密，上層短而上揚；高度向密度噪聲（疏密帶）
#   ・方位不對稱＝低頻方位場（1–3 次諧波、相位隨高度漂移）＋向光偏冠＋冠隙窗（方位×高度）＋裸幹帶
#   ・老枝（較長、較平、肘狀上翹、端團大）、枯枝（裸、灰、斷口）
#   ・樹梢樣式：spire（微彎尖梢）、twin（副梢競爭）、round（老杉圓頭）、nod（檜點頭）、broken（斷頂燭台）
#   ・LOD（lod_mode='clump'）：依葉團配額取卡、卡心往團心收；遠級合併葉團；全部卡角夾在 LOD0 外包絡內
#     → 冠寬、冠心、主要缺口、樹頂位置跨級一致（R1 的 LOD2→3 冠團重排）
def card_s_for(cell, h_m):
    """卡片可見高度（bbox 高）＝ h_m 公尺時的 s。"""
    at, r = cell_info(cell)
    return h_m / max((r['bbox_uv'][3] - r['bbox_uv'][1]) * r['cm_per_px'] / 100.0 * ATLAS, 1e-4)


def vnoise_fn(rng, amp):
    ks = [(rng.uniform(2.2, 3.6), rng.uniform(0, 6.28), 0.6), (rng.uniform(5.5, 8.5), rng.uniform(0, 6.28), 0.4)]
    return lambda h: 1.0 + amp * sum(w * math.sin(f * math.pi * h + p) for f, p, w in ks)


def az_field(rng, amp):
    hs = [(k, amp * rng.uniform(0.6, 1.0) / k ** 0.6, rng.uniform(0, 6.28), rng.uniform(-1.6, 1.6)) for k in (1, 2, 3)]
    return lambda az, h: 1.0 + sum(a * math.cos(k * (az - ph - dr * h)) for k, a, ph, dr in hs)


def chain_point(ch, s):
    """沿枝長 s 處的點與方向。"""
    acc = 0.0
    for i in range(len(ch.pts) - 1):
        seg = float(np.linalg.norm(ch.pts[i + 1] - ch.pts[i]))
        if acc + seg >= s or i == len(ch.pts) - 2:
            t = clamp((s - acc) / max(seg, 1e-6), 0.0, 1.0)
            return ch.pts[i] + (ch.pts[i + 1] - ch.pts[i]) * t, nrm(ch.pts[i + 1] - ch.pts[i]), i
        acc += seg
    return ch.pts[-1], nrm(ch.pts[-1] - ch.pts[-2]), len(ch.pts) - 2


def axis_out(T, p):
    tp, _ = T.trunk_at(clamp(p[1], 0.01, T.trunk.pts[-1][1] - 0.01))
    o = p - tp
    o[1] = 0
    return (nrm(o) if np.linalg.norm(o) > 1e-3 else hdir(T.rng.uniform(0, 6.28))), tp


def clump_nc(T, p, local):
    """葉團法線中心：團內局部中心與樹冠軸（同高度往下 1.2 m 的樹幹點）混合。
    純局部 → 每團各自「上亮下暗」＝一團團坐墊／層板；混入樹冠軸 → 明暗沿整個樹冠連續。"""
    w = T.sp.get('nc_crown', 0.0)
    if not w:
        return local
    tp, _ = T.trunk_at(clamp(p[1] - 1.2, 0.01, T.trunk.pts[-1][1] - 0.01))
    return local * (1 - w) + tp * w


def new_clump(T, c, r, kind, imp):
    T.clumps.append(dict(c=np.asarray(c, dtype=np.float64), r=float(r), kind=kind, imp=float(imp)))
    return len(T.clumps) - 1


def sugi_tuft(T, p, d, r, imp=1.0, cells=None, up_bias=None):
    """杉葉團：枝端／小枝上的一團繩狀針葉簇（數張卡交錯、偏上揚），法線中心在團心內下 → 遠看一團一團的圓簇。"""
    sp, rng = T.sp, T.rng
    o, _ = axis_out(T, p)
    cl = new_clump(T, p, r, 'tuft', imp)
    nc = clump_nc(T, p, p - o * r * 1.3 - UP * r * 0.35)
    n = int(clamp(round(sp.get('tuft_n', 5) * (r / sp['cl_r']) ** 1.4), 2, 9))
    ub = sp.get('tuft_up', 0.55) if up_bias is None else up_bias
    for k in range(n):
        q = p + V(rng.gauss(0, r * 0.32), rng.gauss(0, r * 0.22), rng.gauss(0, r * 0.32))
        up = nrm(d * sp.get('tuft_fwd', 0.5) + UP * ub + o * 0.25 + V(rng.gauss(0, 0.28), rng.gauss(0, 0.15), rng.gauss(0, 0.28)))
        u, rt = card_axes(up, rng.uniform(0, 6.28), face=o)
        cell = T.pick_cell(cells)
        hm = r * rng.uniform(1.45, 2.0)
        T.add_card(q - u * hm * 0.5, u, rt, card_s_for(cell, hm), None, None, cell=cell,
                   imp=imp * rng.uniform(0.85, 1.15), nc=nc, cl=cl)


def hinoki_fan(T, p, d, r, plane_n, imp=1.0, cells=None):
    """檜噴枝扇團：卡面含枝向（下垂），繞枝軸各自傾轉 ±rollj、前後錯開 → 有厚度的下垂扇團（不是水平板）。"""
    sp, rng = T.sp, T.rng
    o, _ = axis_out(T, p)
    cl = new_clump(T, p, r, 'fan', imp)
    nc = clump_nc(T, p, p - o * r * 1.2 - UP * r * 0.6)
    n = int(clamp(round(sp.get('fan_n', 4) * (r / sp['cl_r']) ** 1.4), 2, 8))
    droop = math.radians(sp.get('fan_droop', 28))
    rj = math.radians(sp.get('fan_rollj', 32))
    for k in range(n):
        dd = turn_toward(d, -UP, droop * rng.uniform(0.4, 1.25))
        dd = nrm(rot(dd, plane_n, rng.uniform(-0.65, 0.65)))           # 扇面內散開
        rt = nrm(np.cross(plane_n, dd))
        rt = nrm(rot(rt, dd, rng.uniform(-rj, rj)))                      # 卡面繞枝向傾轉（厚度）
        q = p + plane_n * rng.gauss(0, r * 0.28) + dd * rng.uniform(-0.25, 0.2) * r + V(0, rng.gauss(0, r * sp.get('fan_vy', 0.12)), 0)
        cell = T.pick_cell(cells)
        hm = r * rng.uniform(1.5, 2.1)
        T.add_card(q - dd * hm * 0.45, dd, rt, card_s_for(cell, hm), None, None, cell=cell,
                   imp=imp * rng.uniform(0.85, 1.15), nc=nc, cl=cl)


def spray_plane(T, d, roll_base):
    """檜噴枝面法線：含枝向 d 的平面，繞 d 傾轉 roll；|roll| 不小於 roll_min（不出現水平扇面）。"""
    sp, rng = T.sp, T.rng
    rmin = math.radians(sp.get('roll_min', 35))
    roll = roll_base + math.radians(rng.uniform(-18, 18))
    if abs(roll) < rmin:
        roll = math.copysign(rmin + rng.uniform(0, 0.15), roll if roll else 1.0)
    hz = nrm(np.cross(d, UP)) if abs(d[1]) < 0.95 else perp(d)
    return nrm(rot(nrm(np.cross(hz, d)), d, roll))


def hinoki_spray(T, p, d, r, plane_n, imp=1.0, edge=False):
    """檜噴枝（final pass）：1–3 張小而薄的卡，長軸沿枝向 d、同在傾斜的 plane_n 面內（厚度極小）→ 讀成「沿枝延伸的薄噴枝」，
    不是一團各向卡片的闊葉球。edge＝枝端外緣：更小、更散、卡數少（外緣碎）。"""
    sp, rng = T.sp, T.rng
    o, _ = axis_out(T, p)
    cl = new_clump(T, p, r, 'fan', imp)
    nc = clump_nc(T, p, p - o * r * 1.2 - UP * r * 0.6)
    droop = math.radians(sp.get('fan_droop', 28))
    n = 1 if edge else (2 if rng.random() < sp.get('spray_two', 0.55) else 1)
    if not edge and r > sp['spr_r'] * 1.05 and rng.random() < 0.5:
        n += 1
    off = 0.0
    for k in range(n):
        dd = turn_toward(d, -UP, droop * rng.uniform(0.25, 1.0))
        dd = nrm(rot(dd, plane_n, rng.uniform(-0.45, 0.45) if k else rng.uniform(-0.15, 0.15)))   # 面內散開（同一平面）
        rt = nrm(np.cross(plane_n, dd))
        rt = nrm(rot(rt, dd, math.radians(rng.uniform(-10, 10))))                                 # 薄：只容小幅扭轉
        hm = r * rng.uniform(1.0, 1.45) * (0.8 if k else 1.0) * (0.85 if edge else 1.0)
        q = p + dd * off + plane_n * rng.gauss(0, r * 0.06) + (rt * rng.uniform(-0.3, 0.3) * r if k else 0)
        cell = T.pick_cell()
        T.add_card(q - dd * hm * 0.2, dd, rt, card_s_for(cell, hm), None, None, cell=cell,
                   imp=imp * rng.uniform(0.85, 1.15), nc=nc, cl=cl)
        off += hm * rng.uniform(0.35, 0.6)


def hinoki_foliage(T, br, h, kind, Lmax):
    """檜枝葉（final pass）：主枝上互生的羽狀小枝（同在一個傾斜的枝葉面內），每根小枝帶 1–3 片薄噴枝；
    主軸也帶噴枝。噴枝大小／間距／角度逐片變化；靠內（t 小）較大較密、枝端較小較碎；下部枝更疏（避免盤狀）。"""
    sp, rng = T.sp, T.rng
    Lb = br.length()
    start = lerp(sp.get('fol_start_low', 0.55), sp.get('fol_start_top', 0.12), sstep(0.0, 0.85, h))
    rmin, rmax = sp.get('roll_min', 35), sp.get('roll_max', 80)
    roll_b = (1 if rng.random() < 0.5 else -1) * math.radians(rng.uniform(rmin, rmax))
    low = 1.0 - sstep(0.0, sp.get('spr_low_h', 0.45), h)            # 1＝最下層
    skip0 = lerp(0.03, sp.get('spr_low_skip', 0.4), low)
    step0 = sp['spr_step'] * lerp(1.0, sp.get('spr_low_step', 1.6), low)
    R = sp['spr_r'] * (0.6 + 0.4 * min(1.0, Lb / max(Lmax, 0.1)) ** 0.5) * (1.15 if kind == 'old' else 1.0)
    s = Lb * start
    sg = 1 if rng.random() < 0.5 else -1
    while s < Lb * 0.95:
        p, dv, _ = chain_point(br, s)
        t = s / Lb
        edge = t > 0.78
        pn = spray_plane(T, dv, roll_b)
        r = R * rng.uniform(0.7, 1.3) * lerp(1.1, 0.7, t)
        if rng.random() > skip0 + (0.2 if edge else 0.0):
            hinoki_spray(T, p, dv, r, pn, imp=0.8 + 0.6 * t, edge=edge)
        # 羽狀小枝：在枝葉面內左右互生（每節 spr_side 根）
        for _ in range(sp.get('spr_side', 1) if t < 0.9 else 0):
            if rng.random() < skip0 * 0.8:
                continue
            sg = -sg
            side = nrm(np.cross(pn, dv)) * sg
            sd = nrm(dv * rng.uniform(0.45, 0.8) + side * rng.uniform(0.7, 1.0) - UP * rng.uniform(0.0, 0.2))
            Ls = max(0.3, Lb * sp.get('sec_len', 0.3) * (1 - 0.55 * t) * rng.uniform(0.6, 1.35))
            q = [p, p + sd * Ls * 0.5, p + nrm(sd - UP * 0.2) * Ls]
            rr = max(0.006, br.rad[min(len(br.rad) - 1, int(t * (len(br.rad) - 1)))] * 0.45)
            T.chains.append(Chain(q, [rr, rr * 0.7, rr * 0.35], br.lvl + 1, br))
            pn2 = spray_plane(T, sd, roll_b)
            r2 = r * rng.uniform(0.6, 0.95)
            hinoki_spray(T, q[-1], nrm(q[-1] - q[1]), r2, pn2, imp=0.7 + 0.5 * t, edge=edge or Ls < 0.5)
            # 小枝沿途：每 ~spr_step 一片（內側較大、往外漸小）
            nmid = int(Ls / sp['spr_step'])
            for j in range(nmid):
                u = (j + rng.uniform(0.3, 0.8)) / (nmid + 1)
                qm = q[0] + (q[-1] - q[0]) * u
                hinoki_spray(T, qm, sd, r2 * lerp(1.0, 0.75, u) * rng.uniform(0.75, 1.05), pn2, imp=0.6 + 0.4 * t)
        s += step0 * rng.uniform(0.55, 1.6) * lerp(0.85, 1.2, t)
    # 枝端：2–3 片小噴枝散開（外緣碎），不是一個大端團
    pe, de = br.pts[-1], nrm(br.pts[-1] - br.pts[-2])
    for k in range(rng.randint(2, 3)):
        dk = nrm(de + perp(de) * rng.uniform(-0.5, 0.5) - UP * rng.uniform(0.0, 0.3))
        hinoki_spray(T, pe + dk * R * rng.uniform(0.0, 0.4), dk, R * rng.uniform(0.6, 0.9), spray_plane(T, dk, roll_b),
                     imp=1.8, edge=True)


def cedar_foliage(T, br, h, kind, Lmax):
    sp, rng = T.sp, T.rng
    Lb = br.length()
    hin = sp.get('foliage') == 'fan'
    if hin and sp.get('spr_r'):
        hinoki_foliage(T, br, h, kind, Lmax)
        return
    # 下層枝只有外段有葉（內段遮光脫葉）；上層枝幾乎全長有葉
    start = lerp(sp.get('fol_start_low', 0.55), sp.get('fol_start_top', 0.12), sstep(0.0, 0.85, h))
    # 檜：每枝一個扇面傾角（繞枝軸 roll ±roll_max，不是水平）
    # roll_min：扇面最小傾角（> 0 → 沒有水平扇面；R1 的「層板」就是 roll≈0 的水平扇面）
    plane_roll = (1 if rng.random() < 0.5 else -1) * math.radians(rng.uniform(sp.get('roll_min', 0), sp.get('roll_max', 55)))
    s = Lb * start
    old = kind == 'old'
    while s < Lb * 0.92:
        p, dv, _ = chain_point(br, s)
        t = s / Lb
        r = sp['cl_r'] * (0.6 + 0.55 * t) * (0.55 + 0.45 * min(1.0, Lb / max(Lmax, 0.1)) ** 0.5)
        if rng.random() > sp.get('cl_skip', 0.12):
            if hin:
                hz = nrm(np.cross(dv, UP)) if abs(dv[1]) < 0.95 else perp(dv)
                pn = nrm(rot(nrm(np.cross(hz, dv)), dv, plane_roll + rng.uniform(-0.25, 0.25)))
                hinoki_fan(T, p, dv, r, pn, imp=0.8 + 0.6 * t)
            else:
                sugi_tuft(T, p + UP * r * 0.15, dv, r, imp=0.8 + 0.6 * t)
        # 側小枝：向側上方，端點帶一團（打破「一串珠」）
        nside = int(sp.get('side_p', 0.45)) + (1 if rng.random() < sp.get('side_p', 0.45) % 1.0 else 0)
        for _k in range(nside if t < 0.88 else 0):
            hz = nrm(np.cross(dv, UP)) if abs(dv[1]) < 0.95 else perp(dv)
            sg = 1 if rng.random() < 0.5 else -1
            vy = rng.uniform(0.1, 0.5) if not hin else rng.uniform(-sp.get('side_vy', 0.15), sp.get('side_vy', 0.15))
            sd = nrm(dv * 0.55 + hz * sg * rng.uniform(0.6, 1.0) + UP * vy)
            Ls = max(0.35, Lb * sp.get('sec_len', 0.3) * (1 - 0.5 * t) * rng.uniform(0.7, 1.2))
            q = [p, p + sd * Ls * 0.5, p + nrm(sd + (UP * 0.15 if not hin else -UP * 0.15)) * Ls]
            rr = max(0.006, br.rad[min(len(br.rad) - 1, int(t * (len(br.rad) - 1)))] * 0.45)
            T.chains.append(Chain(q, [rr, rr * 0.7, rr * 0.35], br.lvl + 1, br))
            r2 = r * rng.uniform(0.7, 0.95)
            if hin:
                pn2 = nrm(rot(nrm(np.cross(hz, sd)), sd, plane_roll + rng.uniform(-0.4, 0.4)))
                hinoki_fan(T, q[-1], nrm(q[-1] - q[1]), r2, pn2, imp=0.7 + 0.5 * t)
                if Ls > 0.8:
                    hinoki_fan(T, q[1], sd, r2 * 0.8, pn2, imp=0.6 + 0.4 * t)
            else:
                sugi_tuft(T, q[-1], nrm(q[-1] - q[1]), r2, imp=0.7 + 0.5 * t)
                if Ls > 0.9:
                    sugi_tuft(T, q[1], sd, r2 * 0.8, imp=0.6 + 0.4 * t)
        s += sp['cl_sp'] * rng.uniform(0.8, 1.25) * (r / sp['cl_r']) ** 0.6
    # 老枝的再生枝（reiteration）：外段長出 1–2 根直立小主幹、沿途帶葉團 → 古杉「枝上又長出樹」的骨架感
    if old and not hin and sp.get('reit', 0):
        for _k in range(rng.randint(1, sp['reit'])):
            pr, dr, ir = chain_point(br, Lb * rng.uniform(0.45, 0.85))
            Lr = rng.uniform(*sp.get('reit_len', (1.4, 2.8)))
            dd = nrm(UP + hdir(rng.uniform(0, 6.28)) * rng.uniform(0.1, 0.35))
            q = [pr + dd * Lr * i / 4 + V(rng.gauss(0, 0.04), 0, rng.gauss(0, 0.04)) * (i > 0) for i in range(5)]
            rr = max(0.02, br.rad[min(ir, len(br.rad) - 1)] * 0.55)
            T.chains.append(Chain(q, [rr * (1 - 0.75 * i / 4) for i in range(5)], br.lvl + 1, br))
            for i in (2, 3, 4):
                sugi_tuft(T, q[i], dd, sp['cl_r'] * lerp(0.95, 0.7, (i - 2) / 2), imp=1.6, up_bias=1.0)
    # 枝端團（最大；老枝更大）
    pe, de = br.pts[-1], nrm(br.pts[-1] - br.pts[-2])
    re = sp['cl_r'] * (1.05 if not old else 1.35) * (0.6 + 0.4 * min(1.0, Lb / max(Lmax, 0.1)) ** 0.5)
    if hin:
        hz = nrm(np.cross(de, UP)) if abs(de[1]) < 0.95 else perp(de)
        pn = nrm(rot(nrm(np.cross(hz, de)), de, plane_roll))
        hinoki_fan(T, pe, de, re, pn, imp=1.8)
    else:
        sugi_tuft(T, pe + de * re * 0.25, de, re, imp=1.8)


def cedar_branch(T, host, p0, rt0, az, h, L, kind, Lmax):
    sp, rng = T.sp, T.rng
    ej = sp.get('elev_j', 8)
    elev = math.radians(lerp(sp['ang'][0], sp['ang'][1], h) + rng.uniform(-ej, ej) - (9 if kind == 'old' else 0))
    d = hdir(az, elev)
    nseg = max(3, int(L / 0.4))
    pts = [p0]
    droop = math.radians(sp.get('droop', 10)) * (1 - h) * (1.7 if kind == 'old' else 1.0)
    upturn = math.radians(sp.get('upturn', 25)) * (1.35 if kind == 'old' else 1.0)
    bend_at = sp.get('bend_at', 0.55)
    for k in range(nseg):
        t = k / nseg
        if t < bend_at:
            d = turn_toward(d, -UP, droop / nseg * 2)
        elif upturn >= 0:
            d = turn_toward(d, UP, upturn / nseg * 2)
        else:
            d = turn_toward(d, -UP, -upturn / nseg * 2)
        d = nrm(d + V(rng.gauss(0, 0.07), rng.gauss(0, 0.04), rng.gauss(0, 0.07)))
        pts.append(pts[-1] + d * (L + (rt0 if k == 0 else 0)) / nseg)
    rb = clamp(rt0 * 0.42 * (L / max(Lmax, 0.1)) ** 0.5 * (sp.get('old_r', 1.3) if kind == 'old' else 1.0), 0.012, rt0 * 0.75)
    rad = [rb * (1 - 0.8 * k / nseg) for k in range(nseg + 1)]
    br = Chain(pts, rad, host.lvl + 1, host)
    if kind == 'dead':
        cut = max(2, int(len(pts) * rng.uniform(0.5, 1.0)))
        br.pts, br.rad = br.pts[:cut], br.rad[:cut]
        br.kind = 'deadlimb' if rb >= sp.get('deadlimb_r', 0.05) else 'stub'
        # 枯小枝（短、亂向）
        for j in range(1, len(br.pts) - 1):
            if rng.random() < 0.45:
                q0 = br.pts[j]
                dd = nrm(hdir(rng.uniform(0, 6.28), math.radians(rng.uniform(-20, 40))))
                ls = rng.uniform(0.25, 0.8)
                T.chains.append(Chain([q0, q0 + dd * ls], [br.rad[j] * 0.4, br.rad[j] * 0.2], br.lvl + 1, br, 'stub'))
    return br


def cedar_branches(T, host, y_from, y_to, Lscale, bare_bands=()):
    sp, rng = T.sp, T.rng
    y = y_from
    az = rng.uniform(0, 6.28)
    Lmax = sp['Lmax'] * Lscale
    gaps = [(rng.uniform(0, 6.28), rng.uniform(*sp.get('gap_w', (0.5, 1.0))), rng.uniform(y_from, y_to),
             rng.uniform(*sp.get('gap_h', (1.5, 3.5)))) for _ in range(sp.get('gaps', 2))]
    host_is_trunk = host is T.trunk
    prof = sp['prof']
    while True:
        h0 = (y - y_from) / max(y_to - y_from, 1e-6)
        y += rng.uniform(*sp['br_step']) * lerp(sp.get('step_low', 1.3), 0.8, clamp(h0, 0, 1)) \
            * (rng.choice((0.35, 1.0, 1.0, 1.9)) if sp.get('step_irr') else 1.0)
        if y >= y_to:
            break
        h = (y - y_from) / max(y_to - y_from, 1e-6)
        az += GOLD + rng.uniform(-0.5, 0.5)
        dens = T.vnoise(h) if host_is_trunk else 1.0
        surv = lerp(sp.get('low_surv', 0.5), 1.0, sstep(0.0, sp.get('shed_h', 0.3), h)) * clamp(dens, 0.35, 1.25)
        for b0, b1, bs in bare_bands:
            if b0 <= y <= b1:
                surv *= bs
        gapf = 1.0
        for ga, gw, gy, gh in gaps:
            if abs(math.atan2(math.sin(az - ga), math.cos(az - ga))) < gw and abs(y - gy) < gh * 0.5:
                gapf = rng.uniform(0.0, 0.3)
        if host_is_trunk:
            p0, _ = T.trunk_at(y)
            rt = T.trunk_r(y)
        else:
            i = min(range(len(host.pts)), key=lambda k: abs(host.pts[k][1] - y))
            p0, rt = host.pts[i], host.rad[i]
        if rng.random() > surv or gapf < 0.12:
            # 脫落的枝：下層留枯殘枝（樹齡脫枝痕）
            if h < 0.45 and rng.random() < sp.get('shed_stub', 0.55):
                dd = hdir(az, math.radians(rng.uniform(-25, 10)))
                Ls = rng.uniform(0.15, 0.7) * (1 + y / T.H)
                rr = rng.uniform(0.018, 0.04) * (T.r0 / 0.35) ** 0.5
                T.chains.append(Chain([p0, p0 + dd * (rt + Ls)], [rr * 1.2, rr * 0.7], host.lvl + 1, host, 'stub'))
            continue
        L = Lmax * prof(h) * (T.azf(az, h) if host_is_trunk else 1.0) * (1 + sp.get('ecc', 0.2) * math.cos(az - T.light_az)) \
            * gapf * rng.uniform(0.8, 1.15) * lerp(1.0, clamp(dens, 0.7, 1.2), 0.5)
        kind = 'live'
        if h < 0.65 and rng.random() < sp.get('old_p', 0.0) * (1 - h):
            kind = 'old'
            L *= rng.uniform(1.15, 1.35)
        elif rng.random() < sp.get('dead_p', 0.0) * (1 - h) ** 1.2:
            kind = 'dead'
        L = max(L, 0.4)
        br = cedar_branch(T, host, p0, rt, az, h, L, kind, Lmax)
        T.chains.append(br)
        if kind != 'dead':
            cedar_foliage(T, br, h, kind, Lmax)


def cedar_top(T, style):
    """樹梢（個體差）：spire 微彎尖梢／twin 副梢競爭／round 老杉圓頭／nod 檜點頭。"""
    sp, rng = T.sp, T.rng
    tr = T.trunk
    top = tr.pts[-1]
    d0 = nrm(tr.pts[-1] - tr.pts[-2])
    hin = sp.get('foliage') == 'fan'
    r0 = sp['cl_r']
    if style in ('spire', 'twin', 'nod'):
        Ll = sp.get('leader_len', 1.6)
        n = max(3, int(Ll / 0.45))
        for k in range(n):
            t = k / max(n - 1, 1)
            p, d = T.trunk_at(top[1] - Ll * (1 - t))
            r = r0 * lerp(0.75, 0.38, t)
            if hin and sp.get('spr_r'):
                for _j in range(2):
                    dk = nrm(d + hdir(rng.uniform(0, 6.28)) * 0.6)
                    hinoki_spray(T, p, dk, sp['spr_r'] * lerp(1.0, 0.6, t), spray_plane(T, dk, math.radians(60)), imp=3.0)
            elif hin:
                hz = perp(d)
                hinoki_fan(T, p, nrm(d + hdir(rng.uniform(0, 6.28)) * 0.6), r, nrm(np.cross(hz, d)), imp=3.0)
            else:
                sugi_tuft(T, p, d, r, imp=3.0, up_bias=1.2)
        if not hin:
            # 梢頭：朝上的細長卡（尖）
            for k in range(2):
                up = nrm(d0 + hdir(rng.uniform(0, 6.28)) * rng.uniform(0.05, 0.25))
                u, rt = card_axes(up, rng.uniform(0, 6.28))
                cell = T.pick_cell()
                hm = r0 * rng.uniform(1.0, 1.4)
                cl = new_clump(T, top + up * hm * 0.3, hm * 0.5, 'tip', 3.5)
                T.add_card(top - up * hm * 0.35, u, rt, card_s_for(cell, hm), None, None, cell=cell, imp=3.5, cl=cl,
                           nc=top - UP * hm)
    if style == 'twin':
        # 副梢：頂下 1.5–2.6 m 分出、斜 18–28° 上揚，梢頭低於主梢 0.6–1.4 m
        y0 = top[1] - rng.uniform(1.5, 2.6)
        p0, d = T.trunk_at(y0)
        az = rng.uniform(0, 6.28)
        Ld = (top[1] - y0) - rng.uniform(0.6, 1.4)
        dd = nrm(UP + hdir(az) * math.tan(math.radians(rng.uniform(18, 28))))
        q = [p0 + dd * Ld * i / 4 + hdir(az) * 0.15 * (i / 4) ** 2 for i in range(5)]
        rr = T.trunk_r(y0) * 0.5
        T.chains.append(Chain(q, [rr * (1 - 0.8 * i / 4) + 0.008 for i in range(5)], 1, tr))
        for i in (2, 3, 4):
            sugi_tuft(T, q[i], dd, r0 * lerp(0.7, 0.45, (i - 2) / 2), imp=2.6, up_bias=1.1)
    if style == 'round':
        # 老杉圓頭：頂部 2–3 m 內 5–7 根陡升短枝，端團 → 鈍圓頭（不是尖錐）
        nb = rng.randint(5, 7)
        for k in range(nb):
            y = top[1] - rng.uniform(0.3, 2.8)
            p0, _ = T.trunk_at(y)
            az = k * 2 * math.pi / nb + rng.uniform(-0.4, 0.4)
            L = rng.uniform(0.8, 1.6)
            d = hdir(az, math.radians(rng.uniform(45, 70)))
            q = [p0, p0 + d * L * 0.5, p0 + nrm(d + UP * 0.3) * L]
            rr = max(0.02, T.trunk_r(y) * 0.4)
            T.chains.append(Chain(q, [rr, rr * 0.7, rr * 0.35], 1, tr))
            if hin and sp.get('spr_r'):
                for _j in range(3):
                    dk = nrm(d - UP * 0.5 + perp(d) * rng.uniform(-0.5, 0.5))
                    hinoki_spray(T, q[-1] + dk * rng.uniform(0.0, 0.3), dk, sp['spr_r'] * rng.uniform(0.8, 1.1),
                                 spray_plane(T, dk, math.radians(55)), imp=2.8)
            elif hin:
                hinoki_fan(T, q[-1], nrm(d - UP * 0.5), r0 * rng.uniform(0.9, 1.15), nrm(np.cross(perp(d), d)), imp=2.8)
            else:
                sugi_tuft(T, q[-1], d, r0 * rng.uniform(0.85, 1.1), imp=2.8, up_bias=0.9)
        if hin and sp.get('spr_r'):
            for _j in range(4):
                dk = nrm(hdir(rng.uniform(0, 6.28)) + UP * rng.uniform(0.2, 0.6))
                hinoki_spray(T, top + UP * 0.1, dk, sp['spr_r'] * 0.9, spray_plane(T, dk, math.radians(60)), imp=3.2)
        elif hin:
            hinoki_fan(T, top + UP * 0.1, hdir(rng.uniform(0, 6.28)), r0 * 1.1, UP, imp=3.2)
        else:
            sugi_tuft(T, top + UP * 0.2, UP, r0 * 1.0, imp=3.2, up_bias=1.0)


def gen_cedar(T):
    sp, rng = T.sp, T.rng
    H, r0 = T.H, T.r0
    T.clumps = []
    T.vnoise = vnoise_fn(rng, sp.get('vamp', 0.25))
    T.azf = az_field(rng, sp.get('az_amp', 0.18))
    T.setup_flare()
    broken = sp.get('broken', 1.0) < 1.0
    top_h = H * sp.get('broken', 1.0)
    pts = T.trunk_path(top_h, s_curve=sp.get('s_curve', 0.0))
    tb = sp.get('top_bend', 0.0)
    if tb and not broken:
        # 樹梢彎（點頭／偏梢）：最上 top_bend_len 公尺往一側彎
        taz = rng.uniform(0, 6.28)
        Lb = sp.get('top_bend_len', 2.0)
        k = math.tan(math.radians(tb))
        for i, p in enumerate(pts):
            dy = p[1] - (top_h - Lb)
            if dy > 0:
                pts[i] = p + hdir(taz) * (dy * dy / Lb) * k * 0.5 - UP * (dy * dy / Lb) * k * k * 0.12
    Ht = top_h / sp.get('break_frac', 0.6) if broken else H
    rad = [max(0.012, r0 * (1 - min(p[1], Ht * 0.999) / Ht) ** sp.get('taper', 0.85) * (1 + 0.10 * math.exp(-p[1] / 1.5)))
           for p in pts]
    if broken:
        rad[-1] = rad[-2] * 0.9
    tb_amp = sp.get('trunk_bulge', 0.0)
    if tb_amp:
        # 不均勻 taper（古樹：瘤、膨大、枝下收縮）
        ph = [rng.uniform(0, 6.28) for _ in range(3)]
        rad = [r * (1 + tb_amp * (0.6 * math.sin(p[1] * 0.55 + ph[0]) + 0.4 * math.sin(p[1] * 1.4 + ph[1]))) for r, p in zip(rad, pts)]
    T.trunk = Chain(pts, rad, 0)
    T.chains.append(T.trunk)
    cbH = H * sp['cb']
    bare = [(H * a, H * b, s) for a, b, s in sp.get('bare_bands', ())]
    # 斷頂：燭台副主幹（老杉）／御神木的再生幹（reiteration）
    if broken:
        T.trunk.broken = True
        a0 = T.light_az + rng.uniform(-0.6, 0.6)
        nl = sp.get('leaders', 2)
        for k in range(nl):
            fr = sp.get('leader_from', (3.8, 5.6))
            y0 = top_h - rng.uniform(*fr)
            p0, d0 = T.trunk_at(y0)
            az = a0 + k * 2 * math.pi / nl + rng.uniform(-0.45, 0.45)
            out = rng.uniform(*sp.get('leader_out', (1.5, 2.6)))
            rise = (top_h - y0) + rng.uniform(*sp.get('leader_rise', (-1.2, 0.3)))
            if k == 0 and sp.get('leader_lead', 0.0):
                rise += sp['leader_lead']        # 一根副幹明顯高出（不整頂）
            q = [p0]
            m1, m2 = 4, 8
            for i in range(1, m1 + 1):
                q.append(p0 + hdir(az) * out * i / m1 + UP * rise * 0.18 * (i / m1) ** 1.5)
            pe = q[-1]
            lean2 = hdir(az + rng.uniform(-0.5, 0.5)) * rng.uniform(0.2, 0.7)
            for i in range(1, m2 + 1):
                t = i / m2
                q.append(pe + hdir(az) * 0.3 * t + lean2 * t * t + UP * rise * 0.82 * t + V(rng.gauss(0, 0.05), 0, rng.gauss(0, 0.05)))
            n = len(q)
            rr = T.trunk_r(y0) * sp.get('leader_r', 0.55)
            ch = Chain(q, [rr * (1 - 0.78 * i / (n - 1)) + 0.012 for i in range(n)], 1, T.trunk)
            T.chains.append(ch)
            cedar_branches(T, ch, pe[1] + 0.3, q[-1][1] - 0.6, sp.get('leader_L', 0.45))
            # 副峰頂：圓頭葉團（老杉的副峰是鈍圓，不是尖）
            for j in range(3):
                tp = q[-1] - UP * rng.uniform(0.0, 1.2) + hdir(rng.uniform(0, 6.28)) * rng.uniform(0.0, 0.4)
                sugi_tuft(T, tp, UP, sp['cl_r'] * rng.uniform(0.8, 1.05), imp=3.0, up_bias=1.0)
        add_splinters(T)
        y_to = top_h - sp.get('bare_top', 2.4)
    else:
        y_to = top_h - sp.get('leader_len', 1.6) * 0.8
    cedar_branches(T, T.trunk, cbH, y_to, 1.0, bare)
    if not broken:
        cedar_top(T, sp.get('top', 'spire'))
    # 冠下枯殘枝（脫枝痕；老樹較粗較多）
    y = 1.4
    sr = sp.get('stub_r', (0.015, 0.035))
    while y < cbH - 0.3:
        y += rng.uniform(0.3, 0.9)
        if rng.random() > sp.get('stub_p', 0.55) or y >= cbH:
            continue
        p0, _ = T.trunk_at(y)
        d = hdir(rng.uniform(0, 6.28), math.radians(rng.uniform(-25, 5)))
        L = rng.uniform(0.12, 0.6) * (1 + y / H) * sp.get('stub_len', 1.0)
        rr = rng.uniform(*sr) * (r0 / 0.35) ** 0.5
        T.chains.append(Chain([p0, p0 + d * (T.trunk_r(y) + L)], [rr * 1.2, rr * 0.7], 1, T.trunk, 'stub'))
    # 冠下偶發活枝（低處殘存一兩根細枝帶小團：脫枝不完全）
    for k in range(sp.get('low_live', 0)):
        y = rng.uniform(cbH * 0.55, cbH * 0.95)
        p0, _ = T.trunk_at(y)
        az = rng.uniform(0, 6.28)
        br = cedar_branch(T, T.trunk, p0, T.trunk_r(y), az, 0.0, sp['Lmax'] * rng.uniform(0.3, 0.55), 'live', sp['Lmax'])
        T.chains.append(br)
        cedar_foliage(T, br, 0.0, 'live', sp['Lmax'])


def card_frame(T, c):
    """卡片（scale 1）的視覺中心、半徑、軸。"""
    at, r = cell_info(c.cell)
    u0, v0, u1, v1 = r['bbox_uv']
    ua, va = r['anchor_uv']
    S0 = r['cm_per_px'] / 100.0 * ATLAS * c.s
    up, rt = nrm(c.up), nrm(c.rt)
    uc, vc = (u0 + u1) * 0.5, (v0 + v1) * 0.5
    X = c.p + rt * ((uc - ua) * S0) + up * ((va - vc) * S0)
    hw, hh = (u1 - u0) * 0.5 * S0, (v1 - v0) * 0.5 * S0
    return X, max(hw, hh), rt, up, hw, hh


ENV_DY = 0.5
ENV_NS = 16


def build_env(T):
    """LOD0 外包絡：每 0.5 m 高 × 16 方位扇區，葉卡四角離樹軸的最大水平距離；另記樹頂。"""
    env = {}
    ytop = -1e9
    for c in T.cards:
        X, R, rt, up, hw, hh = card_frame(T, c)
        for a in (-1, 1):
            for b in (-1, 1):
                q = X + rt * hw * a + up * hh * b
                ytop = max(ytop, q[1])
                tp, _ = T.trunk_at(clamp(q[1], 0.01, T.trunk.pts[-1][1] - 0.01))
                dx, dz = q[0] - tp[0], q[2] - tp[2]
                key = (int(math.floor(q[1] / ENV_DY)), int(((math.atan2(dz, dx) % (2 * math.pi)) / (2 * math.pi)) * ENV_NS) % ENV_NS)
                env[key] = max(env.get(key, 0.0), math.hypot(dx, dz))
    T.env, T.env_top = env, ytop


def env_lim(T, q):
    tp, _ = T.trunk_at(clamp(q[1], 0.01, T.trunk.pts[-1][1] - 0.01))
    dx, dz = q[0] - tp[0], q[2] - tp[2]
    yb = int(math.floor(q[1] / ENV_DY))
    sb = int(((math.atan2(dz, dx) % (2 * math.pi)) / (2 * math.pi)) * ENV_NS) % ENV_NS
    lim = 0.0
    for a in (-1, 0, 1):
        for b in (-1, 0, 1):
            lim = max(lim, T.env.get((yb + a, (sb + b) % ENV_NS), 0.0) * (1.0 if (a, b) == (0, 0) else 0.92))
    return math.hypot(dx, dz) - lim - 0.15, tp


def clamp_card(T, X, k, rt, up, hw, hh):
    """把放大後的卡（視覺中心 X、倍率 k）夾回 LOD0 外包絡：超出 → 縮小並往樹軸收；樹頂不超過 LOD0 樹頂。"""
    for it in range(12):
        over, otop = 0.0, -1.0
        for a in (-1, 1):
            for b in (-1, 1):
                q = X + rt * hw * k * a + up * hh * k * b
                o, _ = env_lim(T, q)
                over = max(over, o)
                otop = max(otop, q[1] - T.env_top)
        if over <= 0.0 and otop <= 0.05:
            break
        if k > 1.0:
            k = max(1.0, k * 0.92)
        tp, _ = T.trunk_at(clamp(X[1], 0.01, T.trunk.pts[-1][1] - 0.01))
        hv = V(tp[0] - X[0], 0, tp[2] - X[2])
        if over > 0:
            X = X + hv * min(0.25, over / max(np.linalg.norm(hv), 1e-3) * 0.5)
        if otop > 0.05:
            X = X - UP * otop * 0.6
    return X, k


def clump_select(T, nc, lod):
    """lod_mode='clump' 的取卡：回傳 [(卡 index, 視覺中心, 倍率)]。
    nc ≥ 葉團數：每團依成員比例配額（≥ 1），卡心往團心收、放大不超出團半徑；
    nc < 葉團數：葉團 k-means 合併成 nc/m 群，每群 m 張（LOD3：m＝2、取法線差最大的兩張）蓋住群範圍；
    樹梢葉團（頂 1.2 m）自成一群。全部經 clamp_card 夾回 LOD0 外包絡。"""
    rng = random.Random(zlib.crc32((T.id + str(lod)).encode()))
    N = len(T.cards)
    fr = [card_frame(T, c) for c in T.cards]
    groups = {}
    for i, c in enumerate(T.cards):
        groups.setdefault(c.cl, []).append(i)
    for g in groups.values():
        g.sort(key=lambda i: -(T.cards[i].imp + rng.random() * 0.3))
    fill = T.sp.get('cl_fill', (1.0, 0.95, 0.9, 0.72))[lod]
    smax = T.sp.get('lod_scale_max', 3.0) * (1.6 if lod >= 3 else 1.0)
    out = []
    G = len(groups)
    if nc >= N:
        return [(i, fr[i][0], 1.0) for i in range(N)]
    if nc >= G:
        keys = list(groups)
        q = {g: len(groups[g]) * nc / N for g in keys}
        keep = {g: max(1, int(q[g])) for g in keys}
        rest = nc - sum(keep.values())
        for g in sorted(keys, key=lambda g: -(q[g] - int(q[g]))):
            if rest <= 0:
                break
            if keep[g] < len(groups[g]):
                keep[g] += 1
                rest -= 1
        for g in keys:
            mem = groups[g]
            Xs = np.asarray([fr[i][0] for i in mem])
            cc = Xs.mean(0)
            R = max(float(np.linalg.norm(fr[i][0] - cc)) + fr[i][1] for i in mem)
            ks = clamp(math.sqrt(len(mem) / keep[g]) * fill, 1.0, smax)
            for i in mem[:keep[g]]:
                X, half = fr[i][0], fr[i][1]
                k = min(ks, max(1.0, R * 1.05 / max(half, 1e-3)))
                dv = X - cc
                dl = float(np.linalg.norm(dv))
                allow = max(0.0, R * 1.05 - half * k)
                if dl > allow:
                    X = cc + dv / dl * allow
                X, k = clamp_card(T, X, k, fr[i][2], fr[i][3], fr[i][4], fr[i][5])
                out.append((i, X, k))
        return out
    # 合併葉團
    m = 2 if lod >= 3 else 1
    cid = [g for g in groups if g >= 0]
    CC = np.asarray([np.mean([fr[i][0] for i in groups[g]], 0) for g in cid])
    W = np.asarray([len(groups[g]) for g in cid], dtype=np.float64)
    top_y = max(fr[i][0][1] for i in range(N))
    top_ids = [j for j, g in enumerate(cid) if CC[j][1] >= top_y - 1.2]
    rest_ids = [j for j in range(len(cid)) if j not in top_ids]
    K = max(1, nc // m - (1 if top_ids else 0))
    sub = CC[rest_ids]
    labs = np.zeros(len(rest_ids), int)
    if len(rest_ids) > K:
        Cg, labs = kmeans(sub, K, rng, it=20)
    else:
        labs = np.arange(len(rest_ids))
    glist = [[rest_ids[j] for j in range(len(rest_ids)) if labs[j] == k] for k in range(max(labs, default=-1) + 1)]
    if top_ids:
        glist.append(top_ids)
    for gj in glist:
        if not gj:
            continue
        mem = [i for j in gj for i in groups[cid[j]]]
        if gj is glist[-1] and top_ids and gj == top_ids:
            # 樹梢群：不往群心收（否則樹頂下沉）；取頂端最高的 m 張、原位、不放大
            mem.sort(key=lambda i: -(fr[i][0][1] + fr[i][5]))
            for i in mem[:max(m, 2)]:
                out.append((i, fr[i][0], 1.0))
            continue
        w = W[gj]
        gc = (CC[gj] * w[:, None]).sum(0) / w.sum()
        R = max(float(np.linalg.norm(fr[i][0] - gc)) + fr[i][1] for i in mem)
        mem.sort(key=lambda i: -(T.cards[i].imp - float(np.linalg.norm(fr[i][0] - gc)) / max(R, 0.1)))
        pick = [mem[0]]
        if m > 1 and len(mem) > 1:
            n0 = np.cross(fr[mem[0]][2], fr[mem[0]][3])
            pick.append(min(mem[1:], key=lambda i: abs(float(np.dot(np.cross(fr[i][2], fr[i][3]), n0)))))
        for i in pick:
            half = fr[i][1]
            k = clamp(R * fill / max(half, 1e-3), 1.0, smax)
            X = gc + (fr[i][0] - gc) * 0.25
            X, k = clamp_card(T, X, k, fr[i][2], fr[i][3], fr[i][4], fr[i][5])
            out.append((i, X, k))
    return out


# ───────────── 顯式松 ─────────────
def gen_pine(T):
    sp, rng = T.sp, T.rng
    H, r0 = T.H, T.r0
    T.clumps = []
    T.setup_flare()
    top_f = sp.get('trunk_top', 0.97)
    pts = T.trunk_path(H * top_f, lean=sp.get('lean', 4), wob=sp.get('wob', 0.5), s_curve=sp.get('s_curve', 0.0))
    rad = [max(0.03, r0 * (1 - p[1] / H) ** sp.get('taper', 0.7) * (1 + 0.08 * math.exp(-p[1] / 1.2))) for p in pts]
    T.trunk = Chain(pts, rad, 0)
    T.chains.append(T.trunk)
    cbH = H * sp['cb']
    nmain = rng.randint(*sp['n_main'])
    y_top = H * min(0.93, top_f - 0.02)
    ys = sorted(rng.uniform(cbH, y_top) for _ in range(nmain))
    az = rng.uniform(0, 6.28)
    tufts = []
    for i, y in enumerate(ys):
        h = (y - cbH) / max(y_top - cbH, 1e-6)
        az += rng.uniform(math.radians(70), math.radians(170))
        env = sp.get('env', lambda hh: 1.0)(h)
        L = sp['Lmax'] * env * (1 + sp.get('ecc', 0.25) * math.cos(az - T.light_az)) * rng.uniform(0.7, 1.15)
        elev = math.radians(lerp(sp['ang'][0], sp['ang'][1], h) + rng.uniform(-10, 10))
        p0, _ = T.trunk_at(y)
        rt = T.trunk_r(y)
        d = hdir(az, elev)
        nseg = max(4, int(L / 0.4))
        q = [p0]
        for k in range(nseg):
            t = k / nseg
            if t > 0.55:
                d = turn_toward(d, UP, math.radians(sp.get('upturn', 40)) / nseg * 2.2)
            d = nrm(d + V(rng.gauss(0, 0.12), rng.gauss(0, 0.05), rng.gauss(0, 0.12)))   # 松枝曲折
            q.append(q[-1] + d * (L + (rt if k == 0 else 0)) / nseg)
        rb = clamp(rt * sp.get('br_r', 0.55) * (L / sp['Lmax']) ** 0.4, 0.02, rt * 0.8)
        br = Chain(q, [rb * (1 - 0.75 * k / nseg) for k in range(nseg + 1)], 1, T.trunk)
        T.chains.append(br)
        # 水平扇形分叉 → 枝端針葉簇
        nf = rng.randint(*sp.get('n_fork', (2, 4)))
        for f in range(nf):
            tt = rng.uniform(0.4, 0.85)
            k = int(tt * nseg)
            bd = nrm(q[k + 1] - q[k])
            fd = nrm(rot(bd, UP, rng.choice((-1, 1)) * math.radians(rng.uniform(25, 65))) + UP * rng.uniform(0.0, 0.25))
            Lf = L * rng.uniform(0.25, 0.45)
            m = max(2, int(Lf / 0.4))
            qq = [q[k]]
            for j in range(m):
                fd = turn_toward(fd, UP, math.radians(30) / m)
                fd = nrm(fd + V(rng.gauss(0, 0.1), 0, rng.gauss(0, 0.1)))
                qq.append(qq[-1] + fd * Lf / m)
            rr = br.rad[k] * 0.5
            T.chains.append(Chain(qq, [rr * (1 - 0.7 * j / m) for j in range(m + 1)], 2, br))
            tufts.append((qq[-1], fd, 1.0, h))
            if Lf > 1.2:
                tufts.append((qq[m // 2], fd, 0.75, h))
            # 赤松 B：叉枝上再補小簇（枝團連成雲層、不是一顆顆分離的球）
            for e in range(sp.get('fork_extra', 0)):
                jj = rng.randint(1, m)
                tufts.append((qq[jj], fd, rng.uniform(0.6, 0.85), h))
        tufts.append((q[-1], d, 1.25, h))
        tufts.append((q[int(nseg * 0.7)], nrm(q[int(nseg * 0.7) + 1] - q[int(nseg * 0.7)]), 0.8, h))
    # 傘頂：幹頂分出 2–3 根斜上外張的頂枝（赤松的平頂／傘頂；不是一根往上的尖頂）
    nl = sp.get('leaders', 0)
    if nl:
        p0 = T.trunk.pts[-1]
        rt0 = T.trunk.rad[-1]
        a0 = rng.uniform(0, 6.28)
        for k in range(nl):
            az2 = a0 + k * 2 * math.pi / nl + rng.uniform(-0.5, 0.5)
            d = hdir(az2, math.radians(rng.uniform(22, 40)))
            L = sp['Lmax'] * rng.uniform(0.45, 0.7)
            m = max(4, int(L / 0.4))
            q = [p0 - V(0, rt0 * 2, 0)]
            for j in range(m):
                d = turn_toward(d, hdir(az2), math.radians(18) / m)
                d = nrm(d + V(rng.gauss(0, 0.1), rng.gauss(0, 0.04), rng.gauss(0, 0.1)))
                q.append(q[-1] + d * L / m)
            rr = rt0 * 0.85
            br = Chain(q, [rr * (1 - 0.7 * j / m) for j in range(m + 1)], 1, T.trunk)
            T.chains.append(br)
            tufts.append((q[-1], d, 1.2, 1.0))
            tufts.append((q[m // 2], d, 0.85, 1.0))
    else:
        # 頂芽簇
        tufts.append((T.trunk.pts[-1], nrm(T.trunk.pts[-1] - T.trunk.pts[-2]), 1.2, 1.0))
    for p, d, sz, h in tufts:
        pine_tuft(T, p, d, sz, h)


def pine_tuft(T, p, d, sz, h):
    """松針簇：一團放射狀、偏上的針葉卡（從簇心往外上），頂面平、底面疏 → 松的「段」狀枝團。"""
    sp, rng = T.sp, T.rng
    axis = nrm(d * 0.45 + UP * 0.75)
    n = sp.get('tuft_n', 6)
    if sp.get('pad'):
        # 庭園松雲團：水平卡（頂面）＋周圍立卡（側面）
        R = sp['pad'] * sz
        for k in range(int(n * 1.6)):
            a = rng.uniform(0, 6.28)
            rr = R * math.sqrt(rng.random()) * 0.8
            q = p + V(math.cos(a) * rr, rng.uniform(0.05, 0.25) * R, math.sin(a) * rr)
            up = nrm(V(math.cos(a), 0, math.sin(a)) * rng.uniform(0.2, 0.6) + V(rng.gauss(0, 0.2), 0.0, rng.gauss(0, 0.2)))
            if np.linalg.norm(up) < 0.1:
                up = hdir(a)
            u, rt = card_axes(up, rng.uniform(-1, 1), flat=True, tilt=math.radians(25))
            T.add_card(q - u * R * 0.5, u, rt, R * 1.15 * rng.uniform(0.85, 1.1), None, None, cell=('A', 'matsu_pad'), imp=2.5)
        for k in range(n):
            a = k / n * 6.28 + rng.uniform(-0.3, 0.3)
            o = hdir(a)
            q = p + o * R * 0.55 + V(0, R * 0.1, 0)
            up = nrm(o * 0.8 + UP * 0.6)
            u, rt = card_axes(up, rng.uniform(0, 6.28), face=o)
            T.add_card(q - u * 0.2, u, rt, rng.uniform(*sp['card']) * sz, None, None, imp=2.0)
        return
    sp_lo, sp_hi = sp.get('tuft_spread', (25, 65))
    # 每簇一個葉團（lod_mode='clump' 依簇配額／合併；未開 clump 的松不受影響，不耗 rng）
    cl = new_clump(T, p, sp['card'][1] * sz * 0.5, 'pine', 1.5)
    for k in range(n):
        a = k / n * 6.28 + rng.uniform(-0.4, 0.4)
        spread = math.radians(rng.uniform(sp_lo, sp_hi))
        up = nrm(rot(axis, perp(axis), spread))
        up = nrm(rot(up, axis, a))
        u, rt = card_axes(up, rng.uniform(0, 6.28))
        T.add_card(p - u * 0.1, u, rt, rng.uniform(*sp['card']) * sz * (0.85 + 0.3 * (1 - h)), None, None, imp=1.5, cl=cl)


# ───────────── space colonization（闊葉／櫻／楓／柳／Hero） ─────────────
def gen_sc(T):
    sp, rng = T.sp, T.rng
    H, r0 = T.H, T.r0
    T.setup_flare()
    D = sp.get('D', 0.45)
    # 樹幹（可多幹）
    stems = sp.get('stems', 1)
    seed_pos, seed_par, seed_grow = [V(0, 0, 0)], [-1], [False]
    stem_tops = []
    for s in range(stems):
        if stems == 1:
            base = V(0, 0, 0)
            lean, laz = sp.get('lean', 2.0), None
        else:
            a = T.light_az + s * 2 * math.pi / stems + rng.uniform(-0.4, 0.4)
            base = hdir(a) * rng.uniform(0.08, 0.2)
            lean, laz = sp.get('lean', 8.0) * rng.uniform(0.7, 1.3), a
        hs = sp['fork'] * (1 if s == 0 else rng.uniform(0.75, 1.05))
        pts = T.trunk_path(hs, n=max(3, int(hs / D)), lean=lean, wob=sp.get('wob', 0.15), base=base, lean_az=laz,
                           s_curve=sp.get('s_curve', 0.0))
        prev = 0
        for i, p in enumerate(pts[1:] if s == 0 else pts):
            seed_pos.append(p)
            seed_par.append(prev)
            seed_grow.append(p[1] >= sp.get('branch_h', hs * 0.6))
            prev = len(seed_pos) - 1
        stem_tops.append(prev)
    # 樹冠包絡
    lobes = []
    cx = hdir(T.light_az) * sp.get('ecc', 0.15) * sp['crown'][0]
    c0 = V(cx[0], sp['crown_y'], cx[2]) + seed_pos[stem_tops[0]] * V(1, 0, 1)
    # main_scale < 1：主橢球縮小、外圍 lobe 推遠 → 多團塊樹冠（不是一顆球插在棍上）
    lobes.append((c0, V(*sp['crown']) * sp.get('main_scale', 1.0), 1.0))
    ld = sp.get('lobe_dist', (0.55, 0.9))
    a_off = rng.uniform(0, 6.28)
    nl = sp.get('n_lobes', 5)
    for k in range(nl):
        # 方位角分層抽樣（團塊繞樹冠分散，不擠在一側）
        a = a_off + (k + rng.uniform(0.15, 0.85)) * 2 * math.pi / nl
        el = rng.uniform(*sp.get('lobe_el', (-0.2, 0.8)))
        dirv = V(math.cos(a) * math.cos(el), math.sin(el), math.sin(a) * math.cos(el))
        on = c0 + dirv * V(*sp['crown']) * rng.uniform(*ld)
        rr = V(*sp['crown']) * rng.uniform(*sp.get('lobe_r', (0.3, 0.5)))
        lobes.append((on, rr, 1.0))
    for extra in sp.get('extra_lobes', []):
        lobes.append((V(*extra[0]), V(*extra[1]), extra[2] if len(extra) > 2 else 1.0))
    holes = []
    for k in range(sp.get('n_holes', 3)):
        a = rng.uniform(0, 6.28)
        el = rng.uniform(-0.4, 0.6)
        dirv = V(math.cos(a) * math.cos(el), math.sin(el), math.sin(a) * math.cos(el))
        holes.append((c0 + dirv * V(*sp['crown']) * rng.uniform(0.45, 0.85), rng.uniform(*sp.get('hole_r', (0.12, 0.25))) * max(sp['crown'])))
    A = sample_lobes(lobes, sp.get('n_attr', 1600), rng, holes)
    trop = V(0, sp.get('trop_up', 0.3), 0) + hdir(T.light_az) * sp.get('trop_light', 0.1) - UP * sp.get('trop_down', 0.0)
    P, par = sc_grow(seed_pos, seed_par, seed_grow, A, D, sp.get('di', D * 9), sp.get('dk', D * 2.0), trop, rng,
                     max_nodes=sp.get('max_nodes', 5000))
    n = len(P)
    nseed = len(seed_pos)
    # 平滑（不動種子＝樹幹）
    kids = [[] for _ in range(n)]
    for i in range(1, n):
        kids[par[i]].append(i)
    for _ in range(2):
        Q = P.copy()
        for i in range(nseed, n):
            if len(kids[i]) == 1:
                Q[i] = P[i] * 0.5 + (P[par[i]] + P[kids[i][0]]) * 0.25
        P = Q
    # 管徑（pipe model；樹幹基部對上 dbh）
    desc = np.ones(n)
    for i in range(n - 1, 0, -1):
        desc[par[i]] += desc[i]
    r_tip = sp.get('r_tip', 0.006)
    r_base = r0
    pexp = clamp(math.log(max(desc[0], 2)) / math.log(max(r_base / r_tip, 1.01)), 1.6, 3.4)
    R = r_tip * desc ** (1.0 / pexp)
    R *= r_base / R[0]
    for i in range(nseed):
        R[i] *= 1.0 + 0.12 * math.exp(-P[i][1] / 1.5)
    chains, node_chain, kids, desc = nodes_to_chains(P, par, R)
    for ch in chains:
        if ch.lvl == 0 and T.trunk is None:
            T.trunk = ch
        elif ch.lvl == 0:
            ch.lvl = 1
    # 多幹：其他主幹自 0 點出發，地下延伸
    T.chains.extend(chains)
    T.nodes = (P, par, R, kids, desc)
    # 葉卡候選：細枝節點
    r_leaf = sp.get('r_leaf', 0.025)
    ymin = sp.get('leaf_ymin', sp['fork'] * 0.8)
    cand = [i for i in range(nseed, n) if R[i] < r_leaf and P[i][1] > ymin]
    rng.shuffle(cand)
    cand.sort(key=lambda i: len(kids[i]) > 0)   # 末梢先
    T.leaf_nodes = cand
    if sp.get('hang'):
        place_hanging(T, P, par, R, kids, cand)
    if sp.get('crown_cards', True):
        for i in cand:
            d = nrm(P[i] - P[par[i]])
            o = P[i] - lobes[0][0]
            o = nrm(o)
            up = nrm(d * 0.55 + o * 0.35 + UP * sp.get('card_up', 0.15) + V(rng.gauss(0, 0.15), rng.gauss(0, 0.15), rng.gauss(0, 0.15)))
            if sp.get('roll') == 'flat' and rng.random() > sp.get('flat_mix', 0.35):
                u, rt = card_axes(up, rng.uniform(-1, 1), flat=True, tilt=math.radians(sp.get('flat_tilt', 30)))
            else:
                u, rt = card_axes(up, rng.uniform(0, 6.28), face=o)
            out = float(np.linalg.norm((P[i] - lobes[0][0]) / V(*sp['crown'])))
            T.add_card(P[i], u, rt, rng.uniform(*sp['card']), None, None, imp=0.6 + out * (1.5 if not kids[i] else 1.0))
        # 樹冠內部補叢：末梢卡只沿細枝分佈 → 樹冠像「葉子包著的骨架」。在細枝與所屬 lobe 中心之間補卡，
        #   讓每個 lobe 有實心團塊；holes 內不補（保留光洞），重要度低（LOD1/2 先拿掉內部、留外輪廓）
        nf = int(len(cand) * sp.get('fill', 0.5))
        if nf and cand:
            LC = np.asarray([l[0] for l in lobes])
            LR = np.asarray([l[1] for l in lobes])
            for k in range(nf):
                i = cand[rng.randrange(len(cand))]
                p = P[i]
                j = int(np.argmin((((LC - p) / LR) ** 2).sum(1)))
                q = p + (LC[j] - p) * rng.uniform(0.18, 0.5) + V(rng.gauss(0, 0.3), rng.gauss(0, 0.22), rng.gauss(0, 0.3))
                if any(float(np.linalg.norm(q - hc)) < hr * 0.9 for hc, hr in holes) or q[1] < ymin:
                    continue
                o = nrm(q - lobes[0][0])
                up = nrm(o * 0.55 + UP * 0.35 + V(rng.gauss(0, 0.25), rng.gauss(0, 0.15), rng.gauss(0, 0.25)))
                u, rt = card_axes(up, rng.uniform(0, 6.28), face=o)
                T.add_card(q, u, rt, rng.uniform(*sp['card']) * rng.uniform(1.0, 1.2), None, None, imp=0.3 + 0.3 * rng.random())


def place_hanging(T, P, par, R, kids, cand):
    """柳／枝垂櫻：外緣細枝垂下的長葉卡（top 錨點），下緣離地 ≥ hang_min。"""
    sp, rng = T.sp, T.rng
    c0 = np.mean(P[cand], 0) if cand else V(0, T.H * 0.6, 0)
    for i in cand:
        if rng.random() > sp['hang'].get('frac', 0.8):
            continue
        p = P[i]
        o = p - c0
        o[1] = 0
        o = nrm(o) if np.linalg.norm(o) > 1e-3 else hdir(rng.uniform(0, 6.28))
        up = nrm(UP + o * rng.uniform(0.05, 0.25) + V(rng.gauss(0, 0.08), 0, rng.gauss(0, 0.08)))
        u, rt = card_axes(up, rng.uniform(0, 6.28), face=o)
        at, r = cell_info(T.pick_cell(sp['hang']['cells']))
        s = rng.uniform(*sp['hang']['card'])
        # 卡片高度（公尺）＝ bbox 高 × 公尺/UV × s；下緣離地限制
        Suv = r['cm_per_px'] / 100.0 * ATLAS
        hgt = (r['bbox_uv'][3] - r['anchor_uv'][1]) * Suv * s
        lim = p[1] - sp['hang'].get('min_y', 0.8)
        if hgt > lim:
            s *= max(0.25, lim / max(hgt, 1e-6))
        T.cards.append(Card((at, [k for k, v in TEXJ['atlas'][at]['regions'].items() if v is r][0]), p, u, rt, s, None, None,
                            imp=1.2, kind='hang'))


def add_surface_roots(T):
    sp, rng = T.sp, T.rng
    nr = sp.get('roots', 4 if T.r0 > 0.25 else 3)
    base_r = T.trunk_r(0.3)
    for k in range(nr):
        a = T.flare_lobes[k % len(T.flare_lobes)][0] if T.flare_lobes else rng.uniform(0, 6.28)
        a += rng.uniform(-0.2, 0.2)
        L = rng.uniform(*sp.get('root_len', (T.r0 * 3.0, T.r0 * 6.0)))
        d = hdir(a)
        m = 7
        pts = []
        for j in range(m + 1):
            t = j / m
            q = d * (base_r * 0.3 + L * t) + V(0, lerp(0.45, -0.28, t ** 0.8), 0)
            q = q + rot(d, UP, 1.57) * math.sin(t * 3.0 + k) * 0.25 * t
            pts.append(q)
        rr = base_r * rng.uniform(0.22, 0.32)
        T.chains.append(Chain(pts, [rr * (1 - 0.85 * j / m) + 0.02 for j in range(m + 1)], 1, T.trunk, 'root'))


# ───────────── 枯木／倒木 ─────────────
def gen_snag(T):
    sp, rng = T.sp, T.rng
    H, r0 = T.H, T.r0
    T.setup_flare()
    pts = T.trunk_path(H, lean=sp.get('lean', 4), wob=0.3)
    rad = [max(0.05, r0 * (1 - p[1] / H * 0.6)) for p in pts]
    T.trunk = Chain(pts, rad, 0)
    T.trunk.broken = True
    T.chains.append(T.trunk)
    y = H * 0.3
    while y < H * 0.95:
        y += rng.uniform(0.6, 1.4)
        if y >= H * 0.95:
            break
        p0, _ = T.trunk_at(y)
        az = rng.uniform(0, 6.28)
        d = hdir(az, math.radians(rng.uniform(-5, 40)))
        L = rng.uniform(0.6, 2.6) * (1 - y / H * 0.5)
        m = max(2, int(L / 0.4))
        q = [p0]
        for j in range(m):
            d = nrm(d + V(rng.gauss(0, 0.15), rng.gauss(0.02, 0.1), rng.gauss(0, 0.15)))
            q.append(q[-1] + d * (L + (T.trunk_r(y) if j == 0 else 0)) / m)
        rb = clamp(T.trunk_r(y) * 0.45, 0.035, 0.12)
        ch = Chain(q, [rb * (1 - 0.6 * j / m) for j in range(m + 1)], 1, T.trunk, 'stub')
        T.chains.append(ch)
    add_splinters(T)


def add_splinters(T):
    """斷口：幹頂一圈木刺（尖、長短不一、略外翻）→ 遠看是折斷不是削平。kind='splinter'（枯木色、不擺動、LOD2 前保留）。"""
    sp, rng = T.sp, T.rng
    top = T.trunk.pts[-1]
    rt_ = T.trunk.rad[-1]
    for k in range(sp.get('splinters', 5)):
        a = rng.uniform(0, 6.28)
        o = hdir(a) * rt_ * rng.uniform(0.2, 0.6)
        Ls = rng.uniform(*sp.get('splinter_len', (0.5, 1.6)))
        d = nrm(UP + hdir(a) * rng.uniform(0.08, 0.35))
        b0 = top + o - V(0, 0.2, 0)
        T.chains.append(Chain([b0, b0 + d * Ls * 0.5, b0 + d * Ls], [rt_ * 0.45, rt_ * 0.26, 0.012], 1, T.trunk, 'stub'))


def gen_log(T):
    sp, rng = T.sp, T.rng
    L, r0 = sp['L'], T.r0
    m = 12
    pts, rad = [], []
    for j in range(m + 1):
        t = j / m
        x = -L / 2 + L * t
        r = r0 * (1 - 0.3 * t)
        pts.append(V(x, r - sp.get('sink', 0.07) + math.sin(t * 2.0) * 0.04, math.sin(t * 2.6 + 1) * 0.12))
        rad.append(r)
    ch = Chain(pts, rad, 0, None, 'log')
    ch.broken = True
    T.trunk = ch
    T.chains.append(ch)
    for k in range(sp.get('stubs', 3)):
        t = rng.uniform(0.25, 0.85)
        j = int(t * m)
        a = rng.uniform(-1.0, 1.0) + (math.pi / 2 if k % 2 else -math.pi / 2)
        d = nrm(V(rng.uniform(-0.3, 0.3), math.sin(a) * 0.8 + 0.3, math.cos(a)))
        rr = rad[j] * 0.3
        Ls = rng.uniform(0.3, 0.9)
        T.chains.append(Chain([pts[j], pts[j] + d * (rad[j] + Ls)], [rr, rr * 0.7], 1, ch, 'stub'))
    T.coll.append({'type': 'cylinder', 'a': list(pts[0]), 'b': list(pts[-1]), 'r': r0 * 0.9})


# ───────────── 灌木／蕨／笹（共享配套） ─────────────
def gen_clump(T):
    sp, rng = T.sp, T.rng
    kind = sp['clump']
    R, Hc = sp['R'], sp['Hc']
    n = sp['n']
    if kind == 'dome':
        for k in range(n):
            a = rng.uniform(0, 6.28)
            el = rng.uniform(0.0, 1.3)
            rr = rng.uniform(sp.get('shell', 0.35), 1.0)
            p = V(math.cos(a) * math.cos(el) * R * rr, Hc * 0.15 + math.sin(el) * Hc * 0.75 * rr, math.sin(a) * math.cos(el) * R * rr)
            o = nrm(p - V(0, Hc * 0.2, 0))
            up = nrm(V(rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
            u, rt = card_axes(up, rng.uniform(0, 6.28), face=o)
            T.add_card(p, u, rt, rng.uniform(*sp['card']), None, None, imp=0.5 + rr)
    else:   # radial：從基部放射（笹、蕨）
        for k in range(n):
            a = k / n * 6.28 + rng.uniform(-0.3, 0.3)
            rr = R * math.sqrt(rng.random()) * 0.6
            p = V(math.cos(a) * rr, -0.03, math.sin(a) * rr)
            tilt = math.radians(rng.uniform(*sp.get('tilt', (10, 35))))
            up = nrm(UP * math.cos(tilt) + hdir(a) * math.sin(tilt))
            u, rt = card_axes(up, rng.uniform(-0.6, 0.6) + a + 1.57)
            T.add_card(p, u, rt, rng.uniform(*sp['card']), None, None, imp=1.0)


# ───────────────────────── 風權重／色 ─────────────────────────
def assign_wind(T):
    rng = T.rng
    H = max(T.H, 1.0)
    r_ref = max(T.trunk_r(T.sp.get('fork', H * 0.4)) if T.trunk else T.r0, 0.02)
    for ch in T.chains:
        if ch is T.trunk or (ch.lvl == 0):
            ch.w = [0.10 * clamp(p[1] / H, 0, 1) ** 2 for p in ch.pts]
            ch.phase = rng.random()
            continue
        par = ch.parent
        aw = 0.0
        if par is not None and par.w is not None:
            j = min(range(len(par.pts)), key=lambda k: float(np.linalg.norm(par.pts[k] - ch.pts[0])))
            aw = par.w[j]
            ch.phase = (par.phase + rng.uniform(-0.08, 0.08)) % 1.0 if ch.lvl > 1 else rng.random()
        else:
            ch.phase = rng.random()
        if ch.kind in ('root', 'log'):
            ch.w = [0.0] * len(ch.pts)
            continue
        ws = []
        cur = aw
        for r in ch.rad:
            wr = clamp(0.045 * (r_ref / max(r, 0.004) - 1.0), 0.0, 0.6)
            cur = max(cur, wr)
            ws.append(cur)
        ch.w = ws
        ch.attach_w = aw


def card_wind(T):
    """葉卡附著點的權重＝最近枝節點權重；沒有骨架的（灌木）＝高度比例。"""
    pts, ws, ph = [], [], []
    for ch in T.chains:
        if ch.kind in ('root', 'log'):
            continue
        for i, p in enumerate(ch.pts):
            pts.append(p)
            ws.append(ch.w[i])
            ph.append(ch.phase)
    if not pts:
        for c in T.cards:
            c.w = 0.3 + 0.3 * clamp(c.p[1] / max(T.sp.get('Hc', 1.0), 0.1), 0, 1)
            c.phase = T.rng.random()
        return
    A = np.asarray(pts)
    for c in T.cards:
        if c.w is not None and c.phase is not None:
            continue
        j = int(np.argmin(((A - c.p) ** 2).sum(1)))
        c.w = max(ws[j], 0.35) if c.kind != 'twig' else ws[j]
        c.phase = ph[j]


def kmeans(X, k, rng, it=12):
    if len(X) <= k:
        return X.copy(), np.arange(len(X))
    C = X[rng.sample(range(len(X)), k)].copy()
    for _ in range(it):
        lab = ((X[:, None, :] - C[None, :, :]) ** 2).sum(2).argmin(1)
        for j in range(k):
            m = X[lab == j]
            if len(m):
                C[j] = m.mean(0)
    lab = ((X[:, None, :] - C[None, :, :]) ** 2).sum(2).argmin(1)
    return C, lab


def crown_lobes(T):
    if not T.cards:
        T.lobe_c, T.lobe_lab, T.lobe_r = np.zeros((0, 3)), np.zeros(0, int), np.zeros(0)
        return
    X = np.asarray([c.p for c in T.cards])
    span = float(np.ptp(X, 0).max())
    k = int(clamp(span / T.sp.get('lobe_size', 3.0), 3, 16))
    C, lab = kmeans(X, k, T.rng)
    R = np.array([float(np.sqrt(((X[lab == j] - C[j]) ** 2).sum(1).mean())) if (lab == j).any() else 1.0 for j in range(len(C))])
    T.lobe_c, T.lobe_lab, T.lobe_r = C, lab, np.maximum(R, 0.3)


def leaf_color(T, c, j):
    """葉卡反照率乘數：lobe 間克制色差（亮度 ±6 %、微黃／微深）＋叢內 AO＋下層略暗。"""
    sp = T.sp
    if not hasattr(T, 'lobe_tint'):
        T.lobe_tint = []
        for _ in range(len(T.lobe_c)):
            b = 1.0 + T.rng.uniform(-0.06, 0.06)
            y = T.rng.uniform(-0.04, 0.05)
            T.lobe_tint.append((b * (1 + y * 0.6), b * (1 + y * 0.25), b * (1 - y)))
        allp = np.asarray([cc.p for cc in T.cards])
        T.ylo, T.yhi = float(allp[:, 1].min()), float(allp[:, 1].max())
    lt = T.lobe_tint[j] if j < len(T.lobe_tint) else (1, 1, 1)
    d = float(np.linalg.norm(c.p - T.lobe_c[j])) / max(T.lobe_r[j], 1e-3)
    ao_in = sp.get('ao_in', 0.62)
    ao = lerp(ao_in, 1.0, sstep(0.15, 1.1, d))
    yv = (c.p[1] - T.ylo) / max(T.yhi - T.ylo, 1e-3)
    ao *= lerp(sp.get('ao_low', 0.86), 1.0, sstep(0.0, 0.6, yv))
    base = sp.get('leaf_mul', (1.0, 1.0, 1.0))
    wm = sp.get('ao_warm', 0.0)
    aoc = (ao ** (1.0 - wm), ao, ao ** (1.0 + wm)) if wm else (ao, ao, ao)
    return [base[i] * lt[i] * aoc[i] * c.tint[i] for i in range(3)]


def bark_color(T, ch, p, dirv, i):
    sp = T.sp
    y = p[1]
    ao = lerp(sp.get('bark_ao', 0.6), 1.0, sstep(-0.1, 1.0, y)) if ch.lvl <= 1 or ch.kind == 'root' else 1.0
    c = [ao, ao, ao]
    mo = sp.get('moss', 0.0)
    if mo and ch.kind not in ('stub', 'deadlimb'):
        m = mo * sstep(2.2, 0.0, y) * clamp(-dirv[2] * 0.7 + 0.5, 0, 1)
        if ch.kind in ('log',):
            m = mo * clamp(dirv[1], 0, 1)
        c = [c[0] * lerp(1, 0.72, m), c[1] * lerp(1, 0.92, m), c[2] * lerp(1, 0.52, m)]
    tt = sp.get('top_tint')
    if tt and ch.lvl <= 1 and ch.kind == 'wood':
        k = sstep(T.H * 0.35, T.H * 0.7, y)
        c = [c[q] * lerp(1.0, tt[q], k) for q in range(3)]
    if ch.kind in ('stub', 'deadlimb'):
        # 殘枝／斷口：灰褪（枯木色由頂點色做，不另開材質）
        g = sum(c) / 3.0
        c = [lerp(x, g, 0.55) * 0.82 for x in c]
    return c


# ───────────────────────── 網格化 ─────────────────────────
LOD_RATIO = (1.0, 0.40, 0.15)
LODCFG = [
    # sides 乘數, 環距乘數, 最小環距, 葉卡比例, 葉卡放大, 折卡
    dict(seg=0.055, step=2.6, step_min=0.22, card_keep=1.0, card_scale=1.0, bent=True),
    dict(seg=0.11, step=4.5, step_min=0.45, card_keep=0.42, card_scale=1.42, bent=False),
    dict(seg=0.25, step=8.0, step_min=1.0, card_keep=0.13, card_scale=2.35, bent=False),
]


def resample_chain(ch, step_fn, extra_y=()):
    pts, rad = ch.pts, ch.rad
    out_p, out_r, out_s, out_w = [pts[0]], [rad[0]], [0.0], [ch.w[0] if ch.w else 0.0]
    s_tot = 0.0
    acc = 0.0
    for i in range(1, len(pts)):
        seg = float(np.linalg.norm(pts[i] - pts[i - 1]))
        s_tot += seg
        acc += seg
        last = i == len(pts) - 1
        ey = any(pts[i - 1][1] < y <= pts[i][1] for y in extra_y)
        if acc >= step_fn(rad[i]) or last or ey:
            out_p.append(pts[i])
            out_r.append(rad[i])
            out_s.append(s_tot)
            out_w.append(ch.w[i] if ch.w else 0.0)
            acc = 0.0
    return out_p, out_r, out_s, out_w


def tube(T, mb, ch, lod, r_cut, sides_minmax=(3, 18), keep_to_y=None):
    sp = T.sp
    cfg = LODCFG[min(lod, 2)]
    pts, rad = list(ch.pts), list(ch.rad)
    # 截短：半徑低於 r_cut 的末段不建（葉卡蓋住）；keep_to_y＝至少保留到此高度（本級有畫的子枝附著點）
    k = len(rad)
    keep_all = ch is T.trunk and (getattr(ch, 'broken', False) or ch.kind == 'log')
    for i in range(len(rad)):
        if rad[i] < r_cut and i > 0 and not keep_all and (keep_to_y is None or pts[i][1] >= keep_to_y):
            k = i + 1
            break
    pts, rad = pts[:k], rad[:k]
    if len(pts) < 2:
        return 0
    w = (ch.w or [0.0] * len(ch.pts))[:k]
    is_trunk = ch is T.trunk
    embed = sp.get('embed', 0.4)
    if (is_trunk or (ch.lvl <= 1 and ch.kind == 'wood' and pts[0][1] < 0.35)) and ch.kind not in ('log',):
        pts = [pts[0] - V(0, embed, 0)] + pts
        rad = [rad[0]] + rad
        w = [0.0] + w
    tmp = Chain(pts, rad, ch.lvl, ch.parent, ch.kind)
    tmp.w = w
    extra = (-0.2, 0.05, 0.2, 0.4, 0.65, 1.0, 1.5, 2.2) if is_trunk and lod <= 1 else (0.3, 1.2) if is_trunk else ()
    step_fn = lambda r: max(cfg['step_min'] * (1.6 if is_trunk and lod >= 2 else 1.0), r * cfg['step'])
    P, R, S, W = resample_chain(tmp, step_fn, extra)
    if len(P) < 2:
        return 0
    # 枝領（branch collar）：枝基部離母枝軸 pr～2.2pr 內漸粗（×1.45→1），補一圈環讓接點平順；不像插管
    if ch.kind == 'wood' and ch.parent is not None and not is_trunk and lod <= 1 and len(P) >= 2:
        par_ = ch.parent
        jj = min(range(len(par_.pts)), key=lambda q: float(np.linalg.norm(par_.pts[q] - ch.pts[0])))
        pr = par_.rad[jj]
        if pr > R[0] * 1.05:
            s_in = pr * 1.25
            if S[1] > s_in * 1.3:
                t_ = s_in / S[1]
                P.insert(1, P[0] + (P[1] - P[0]) * t_)
                R.insert(1, R[0] + (R[1] - R[0]) * t_)
                S.insert(1, s_in)
                W.insert(1, W[0] + (W[1] - W[0]) * t_)
            for q in range(len(P)):
                if S[q] < pr * 2.2:
                    R[q] *= 1.0 + 0.45 * (1.0 - sstep(pr * 0.8, pr * 2.2, S[q]))
    rmax = max(R)
    if is_trunk:
        sides = int(clamp(round(2 * math.pi * rmax / (cfg['seg'] * (1.0 if lod == 0 else 1.0))), sp.get('trunk_sides', (8, 18))[0] if lod == 0 else 5,
                          sp.get('trunk_sides', (8, 18))[1] if lod == 0 else (10 if lod == 1 else 6)))
        if lod == 3:
            sides = 4
    else:
        sides = int(clamp(round(2 * math.pi * R[0] / cfg['seg']), sides_minmax[0], sides_minmax[1] if lod == 0 else max(3, sides_minmax[1] // 2)))
        if lod >= 2:
            sides = min(sides, 4)
    # 枯木（整棵）用枯木樹皮；活樹的殘枝／斷口用本種樹皮＋頂點色壓暗（每棵 ≤ 2 surface＝draw call）
    matn = 'VK_Bark_' + (sp.get('bark_dead', 'dead') if ch.kind == 'stub' and sp['cls'] == 'dead' else sp['bark'])
    mi = mb.mat(matn)
    tile = 1.2
    reps = max(1, round(2 * math.pi * R[0] / tile))
    # parallel transport
    Ts = []
    for i in range(len(P)):
        a = P[max(0, i - 1)]
        b = P[min(len(P) - 1, i + 1)]
        Ts.append(nrm(b - a))
    Nf = perp(Ts[0]) if not is_trunk else V(1, 0, 0)
    Nf = nrm(Nf - Ts[0] * float(np.dot(Nf, Ts[0])))
    ring_idx = []
    flare = is_trunk and ch.kind != 'log' and sp.get('flare', 0.0) > 0
    for i in range(len(P)):
        t = Ts[i]
        Nf = nrm(Nf - t * float(np.dot(Nf, t)))
        Bf = np.cross(t, Nf)
        y = P[i][1]
        dr = 0.0
        if i < len(P) - 1:
            ds = max(S[i + 1] - S[i], 1e-4)
            dr = (R[i + 1] - R[i]) / ds
        idx = []
        for kk in range(sides + 1):
            th = 2 * math.pi * kk / sides
            dv = Nf * math.cos(th) + Bf * math.sin(th)
            r = R[i]
            if flare:
                r *= T.flare_mul(y, math.atan2(dv[2], dv[0]))
            pos = P[i] + dv * r
            nn = nrm(dv - t * dr)
            col = bark_color(T, ch, pos, dv, i)
            idx.append(mb.v(pos, nn, (reps * kk / sides, S[i] / tile), (W[i], ch.phase), (col[0], col[1], col[2], 0.0)))
        ring_idx.append(idx)
    for i in range(len(P) - 1):
        a, b = ring_idx[i], ring_idx[i + 1]
        for kk in range(sides):
            mb.f([a[kk], a[kk + 1], b[kk + 1], b[kk]], mi)
    # 末端：細→收尖；斷頂（枯木／斷枝）→ 平蓋
    last = ring_idx[-1]
    t = Ts[-1]
    broken = getattr(ch, 'broken', False) or ch.kind in ('stub', 'log', 'deadlimb')
    if broken and ch is T.trunk and getattr(ch, 'broken', False) and ch.kind != 'log' and lod <= 1:
        # 斷口：鋸齒冠（每個邊頂點往上抬不同高度＝參差木刺），中心凹陷 → 遠看是折斷不是鋸平
        rng2 = random.Random(zlib.crc32(T.id.encode()))
        jag = T.sp.get('jag', 0.9) * R[-1] * 2
        ring2 = []
        for kk in range(sides + 1):
            k2 = kk % sides
            hgt = jag * (rng2.uniform(0.15, 1.0) if k2 % 2 == 0 else rng2.uniform(0.0, 0.35))
            pos = V(*mb.P[last[k2]]) + t * hgt
            col = bark_color(T, ch, pos, t, 0)
            ring2.append(mb.v(pos, V(*mb.N[last[k2]]), (reps * k2 / sides, S[-1] / tile + hgt / tile), (W[-1], ch.phase),
                              (col[0] * 1.1, col[1] * 1.05, col[2], 0.0)))
        for kk in range(sides):
            mb.f([last[kk], last[kk + 1], ring2[kk + 1], ring2[kk]], mi)
        c = P[-1] - t * R[-1] * 0.3
        col = bark_color(T, ch, c, t, 0)
        ci = mb.v(c, t, (0.5, S[-1] / tile + 0.05), (W[-1], ch.phase), (col[0] * 0.7, col[1] * 0.65, col[2] * 0.6, 0.0))
        for kk in range(sides):
            mb.f([ring2[kk], ring2[kk + 1], ci], mi)
    elif broken:
        c = P[-1] + t * R[-1] * 0.15
        col = bark_color(T, ch, c, t, 0)
        ci = mb.v(c, t, (0.5, S[-1] / tile + 0.05), (W[-1], ch.phase), (col[0] * 1.2, col[1] * 1.15, col[2] * 1.05, 0.0))
        for kk in range(sides):
            mb.f([last[kk], last[kk + 1], ci], mi)
        if ch.kind == 'log':
            first = ring_idx[0]
            c0 = P[0] - Ts[0] * R[0] * 0.15
            c0i = mb.v(c0, -Ts[0], (0.5, -0.05), (0.0, 0.0), (col[0] * 1.2, col[1] * 1.15, col[2] * 1.05, 0.0))
            for kk in range(sides):
                mb.f([first[kk + 1], first[kk], c0i], mi)
    else:
        tip = P[-1] + t * max(R[-1] * 1.5, 0.01)
        col = bark_color(T, ch, tip, t, 0)
        ti = mb.v(tip, t, (reps * 0.5, S[-1] / tile + 0.05), (W[-1], ch.phase), (col[0], col[1], col[2], 0.0))
        for kk in range(sides):
            mb.f([last[kk], last[kk + 1], ti], mi)
    return sides


def emit_card(T, mb, c, lod, scale, bent, normal_c, lobe_r, color, mat_override=None, center_mode=False, pull=True):
    at, r = cell_info(c.cell)
    mi = mb.mat(mat_override or ('VK_Leaf_' + at))
    u0, v0, u1, v1 = r['bbox_uv']
    ua, va = r['anchor_uv']
    if center_mode:
        ua, va = (u0 + u1) / 2, (v0 + v1) / 2
    S0 = r['cm_per_px'] / 100.0 * ATLAS * c.s
    S = S0 * scale
    # 地被（lod_keep_h）：LOD1/2 補面積只加寬、不加高（矮叢換檔不長高）
    Sv = S0 if (T.sp.get('lod_keep_h') and lod >= 1) else S
    up, rt = nrm(c.up), nrm(c.rt)
    n = nrm(np.cross(rt, up))
    fold = math.radians(T.sp.get('fold', 22)) if bent else 0.0
    reach = max(abs(u1 - ua), abs(ua - u0), 1e-4) * S
    tall = max(abs(va - v0), abs(v1 - va), 1e-4) * Sv
    # LOD1+ 放大補面積：以卡片「視覺中心」為準放大（不以附著點）→ 樹冠外輪廓不往外膨脹、LOD 換檔不跳體積
    #   垂枝卡（hang）維持附著點（上端掛在枝上）
    base = c.p
    if scale != 1.0 and not center_mode and c.kind != 'hang':
        uc, vc = (u0 + u1) * 0.5, (v0 + v1) * 0.5
        base = c.p + rt * ((uc - ua) * (S0 - S)) + up * ((va - vc) * (S0 - Sv))
        # LOD2+ 大幅放大：卡片中心往樹冠中心（法線中心）收 → 放大後外緣仍落在 LOD0 輪廓附近（換檔不膨脹）
        if pull and lod >= 2 and scale > 1.05 and normal_c is not None:
            dv = np.asarray(normal_c) - base
            dl = float(np.linalg.norm(dv))
            if dl > 1e-3:
                base = base + dv / dl * min((S - S0) * 0.38, dl * 0.6)

    def pos(u, v):
        q = base + rt * ((u - ua) * S) + up * ((va - v) * Sv)
        if fold:
            q = q - n * abs(u - ua) * S * math.sin(fold)
        return q

    def nor(q):
        if normal_c is None:
            return n
        cn = nrm(q - normal_c)
        nf = n if float(np.dot(n, cn)) >= 0 else -n
        return nrm(nf * (1 - T.sp.get('crown_n', 0.75)) + cn * T.sp.get('crown_n', 0.75))

    def wv(u, v):
        d = math.sqrt(((u - ua) * S) ** 2 + ((va - v) * Sv) ** 2) / max(reach, tall)
        return min(1.0, c.w + 0.45 * d), clamp(d, 0, 1)

    us = [u0, ua, u1] if bent else [u0, u1]
    ids = {}
    for u in us:
        for v in (v0, v1):
            q = pos(u, v)
            w, fl = wv(u, v)
            ids[(u, v)] = mb.v(q, nor(q), (u, v), (w, c.phase), (color[0], color[1], color[2], fl))
    for i in range(len(us) - 1):
        a, b = us[i], us[i + 1]
        mb.f([ids[(a, v1)], ids[(b, v1)], ids[(b, v0)], ids[(a, v0)]], mi)
    return 2 * (len(us) - 1)


def emit_clump_card(T, mb, i, X, k, lod, bent):
    """lod_mode='clump'：卡片視覺中心放到 X、放大 k 倍（不再往樹冠中心收：clump_select 已處理並夾回 LOD0 外包絡）。"""
    c = T.cards[i]
    X0 = card_frame(T, c)[0]
    c2 = Card(c.cell, c.p + (np.asarray(X) - X0), c.up, c.rt, c.s, c.w, c.phase, c.tint, c.imp, c.kind, c.nc, c.cl)
    j = int(T.lobe_lab[i]) if len(T.lobe_lab) else 0
    col = leaf_color(T, c, j) if len(T.lobe_c) else [1, 1, 1]
    return emit_card(T, mb, c2, max(lod, 1) if k != 1.0 else lod, k, bent, card_nc(T, c, j), None, col, pull=False)


def card_nc(T, c, j):
    """葉卡法線中心（樹冠球狀法線）：lobes＝所屬 lobe 中心偏下；axis＝同高度樹幹點；center＝灌木中心。"""
    sp = T.sp
    if c.nc is not None:
        return c.nc
    if sp.get('normal_mode', 'lobes') == 'lobes' and len(T.lobe_c):
        return T.lobe_c[j] * 0.7 + np.asarray([T.lobe_c[j][0] * 0.4, T.lobe_c[j][1] - T.lobe_r[j] * 0.4, T.lobe_c[j][2] * 0.4]) * 0.3
    if sp.get('normal_mode') == 'axis' and T.trunk is not None:
        tp, _ = T.trunk_at(clamp(c.p[1] - 0.6, 0.01, T.trunk.pts[-1][1] - 0.01))
        return tp
    if sp.get('normal_mode') == 'center':
        return V(0, sp.get('Hc', 1.0) * 0.15, 0)
    return None


def build_lods(T):
    sp = T.sp
    n_lod = sp.get('n_lod', 4)
    budget = sp['budget']
    crown_lobes(T)
    clump = sp.get('lod_mode') == 'clump'
    if clump:
        build_env(T)
    out = []
    # 葉卡重要度排序（LOD1/2 依序取前段）：外緣＋末梢＋隨機分層
    # 樹頂（最高 6 % 高度）的卡加權 → LOD1/2 保住樹高輪廓（庭園松、杉尖）
    y_top = max([c.p[1] for c in T.cards], default=0.0)
    top_band = 0.06 * max(T.H, 1.0) if sp['cls'] != 'under' else 0.25
    # 地被：最高的卡（輪廓頂）以卡片頂端高度排序，確保 LOD1/2 都留最高的幾張
    if sp['cls'] == 'under':
        tops = [c.p[1] + c.s * 0.5 for c in T.cards]
        ymax = max(tops, default=0.0)
        order = sorted(range(len(T.cards)), key=lambda i: -(T.cards[i].imp + T.rng.random() * 0.8
                                                           + (4.0 if tops[i] >= ymax - 0.15 else 0.0)))
    else:
        order = sorted(range(len(T.cards)), key=lambda i: -(T.cards[i].imp + T.rng.random() * 0.8
                                                           + (2.5 if T.cards[i].p[1] >= y_top - top_band else 0.0)))
    t0 = None  # LOD0 實際面數；LOD1／LOD2 依此取 40％／15％（規格：LOD1 ≈ 40％、LOD2 ≈ 10–20％）
    for lod in range(n_lod):
        mb = MB('%s_LOD%d' % (T.id, lod))
        if lod < 3:
            cfg = LODCFG[lod]
            # 木：依 LOD 截半徑（LOD0 自動配預算：木 ≤ wood_frac）
            r_cut = sp.get('r_cut', 0.02) * (1, 2.2, 5.0)[lod]
            r_cut0 = r_cut
            r_min = sp.get('r_min', 0.015) * (1, 2.5, 6.0)[lod]
            tgt = budget if lod == 0 else t0 * LOD_RATIO[lod]
            # 葉卡能填的最大面數（LOD1 預算夠時保留折卡＝4 面／卡）；木材上限＝固定比例與「卡填不滿的部分」取大
            #   → 卡少的樹（楓、株立、枯木）LOD1/2 不會因木材被砍太多而低於 40 %／10 %
            card_cap = len(order) * (4 if (lod == 1 and sp.get('bent', True)) else 2)
            cap = tgt * sp.get('wood_frac', 0.42) * (1.0, 1.0, 0.9)[lod]
            if lod:
                cap = max(cap, tgt - card_cap)

            def build_wood(r_cut, r_min):
                mb = MB('%s_LOD%d' % (T.id, lod))
                render = []
                for ch in T.chains:
                    near_top = T.trunk is not None and ch.parent is T.trunk and ch.pts[0][1] > T.trunk.pts[-1][1] - 0.5
                    # 枯木類（枯立木／倒木）的殘枝＝輪廓本體，保留到最後一級（倒木的翹起斷枝就是它的高度）
                    if ch.kind == 'stub' and sp['cls'] != 'dead' and lod >= (3 if near_top else 1):
                        continue
                    if ch.kind == 'root' and lod >= 2:
                        continue
                    # 結構枝保留（松的一級主枝／枯木殘枝）：LOD1/2 不因 r_min 拿掉，但仍受預算升級後 r_min 的 40 % 約束
                    keep_struct = (sp.get('keep_l1', False) and ch.lvl == 1 and ch.kind in ('wood', 'stub') and lod <= 2
                                   and ch.rad[0] >= r_min * 0.4) \
                        or (sp['cls'] == 'dead' and ch.lvl == 1 and ch.kind in ('wood', 'stub') and ch.length() > 0.5)
                    if ch is not T.trunk and ch.rad[0] < r_min and not keep_struct:
                        continue
                    render.append(ch)
                # 樹幹至少保留到本級有畫的一級枝的最高附著點（否則樹冠浮在被截短的樹幹上）
                top_y = max([c.pts[0][1] for c in render if c.parent is T.trunk and c.kind != 'root'], default=None)
                for ch in render:
                    # 樹幹截短半徑固定用該級基準值（不隨預算迴圈升級）
                    if ch is T.trunk:
                        tube(T, mb, ch, lod, r_cut0, keep_to_y=top_y)
                    else:
                        tube(T, mb, ch, lod, r_cut)
                return mb, mb.tris()

            # 往上收（木材超過上限）
            while True:
                mb, wood = build_wood(r_cut, r_min)
                if wood <= cap or r_min > 0.6:
                    break
                r_cut *= 1.25
                r_min *= 1.25
            # 往下放（卡全用上仍填不到目標 90 %）：多留細枝，直到再多就超上限
            if lod:
                r_floor = sp.get('r_min', 0.015) * (1.0, 1.0, 1.5)[lod]
                while wood + min(card_cap, tgt - wood) < tgt * 0.9 and r_min / 1.25 >= r_floor:
                    mb2, wood2 = build_wood(r_cut / 1.25, r_min / 1.25)
                    if wood2 > cap:
                        break
                    mb, wood = mb2, wood2
                    r_cut /= 1.25
                    r_min /= 1.25

            # 葉卡
            left = tgt - wood
            n_all = len(order)
            bent_ok = cfg['bent'] and sp.get('bent', True)
            if lod == 0:
                per = 4 if bent_ok else 2
                nc = min(n_all, max(0, int(left // per)))
                nbent = nc if bent_ok else 0
            else:
                # LOD1：全部卡都放得下時，用剩餘預算把最重要的 nbent 張保留折卡（與 LOD0 同體積，減少換檔跳動）
                nc = min(n_all, max(0, int(left // 2)))
                nbent = 0
                if lod == 1 and sp.get('bent', True) and nc == n_all:
                    nbent = int(min(n_all, max(0, (left - 2 * n_all) // 2)))
            if clump:
                bset = set(order[:nbent])
                for i, X, k in clump_select(T, nc, lod):
                    emit_clump_card(T, mb, i, X, k, lod, nbent >= nc or i in bset)
                if lod == 0:
                    t0 = mb.tris()
                out.append(mb)
                continue
            sel = order[:nc]
            sc = 1.0
            if lod and n_all:
                sc = clamp(math.sqrt(n_all / max(nc, 1)) * 0.92, 1.0, sp.get('lod_scale_max', 3.0))
            for k_, i in enumerate(sel):
                c = T.cards[i]
                j = int(T.lobe_lab[i]) if len(T.lobe_lab) else 0
                nc_ = card_nc(T, c, j)
                col = leaf_color(T, c, j) if len(T.lobe_c) else [1, 1, 1]
                s_here = sc if c.kind != 'hang' else min(sc, 1.25)
                emit_card(T, mb, c, lod, s_here, k_ < nbent, nc_, None, col)

        else:
            # LOD3：遠距簡化樹冠＝ lobe 十字卡＋水平卡；樹幹 4 邊
            if T.trunk is not None:
                tch = T.trunk
                k = len(tch.pts)
                top_y = sp.get('far_trunk_h', sp.get('fork', T.H * sp.get('cb', 0.4)) + 1.0)
                kk = next((i for i, p in enumerate(tch.pts) if p[1] >= top_y), k - 1)
                if T.cards:
                    # 樹幹接進樹冠：至少到葉卡下緣以上 1 m（松的高幹傘冠、葉卡從 0.6H 才開始）
                    y_leaf = float(np.percentile([c.p[1] for c in T.cards], 8)) + 1.0
                    kk = max(kk, next((i for i, p in enumerate(tch.pts) if p[1] >= y_leaf), k - 1))
                if not T.cards or getattr(tch, 'broken', False) or tch.kind == 'log':
                    kk = k - 1   # 沒樹冠遮（枯木／倒木）或斷頂：整根樹幹
                tt = Chain(tch.pts[:kk + 1], tch.rad[:kk + 1], 0, None, tch.kind)
                tt.w = tch.w[:kk + 1]
                tt.phase = tch.phase
                tt.broken = True
                T_trunk = T.trunk
                T.trunk = tt
                tube(T, mb, tt, 3, 0.0)
                T.trunk = T_trunk
            # 葉：LOD0 葉卡的分層子集（每個 lobe 依成員比例配額、取重要度最高者），以卡片中心放大補面積
            #   → 外輪廓、下層 lobe、主要缺口都沿用 LOD0；不再另做一頂「lobe 十字大卡帽」（舊版遠景只剩頂部一把大卡）
            N = len(T.cards)
            if N and clump:
                K = min(int(clamp(t0 * sp.get('far_frac', 0.05) / 2.0, 12, 140)), N)
                for i, X, k in clump_select(T, K, 3):
                    emit_clump_card(T, mb, i, X, k, 3, False)
            elif N:
                K = int(clamp(t0 * sp.get('far_frac', 0.05) / 2.0, 12, 140))
                K = min(K, N)
                lab = T.lobe_lab if len(T.lobe_lab) else np.zeros(N, int)
                quota = {}
                for j in sorted(set(int(x) for x in lab)):
                    nj = int((lab == j).sum())
                    quota[j] = max(1, int(round(K * nj / N)))
                sc3 = clamp(math.sqrt(N / max(sum(quota.values()), 1)) * sp.get('far_fill', 1.2), 1.0,
                            sp.get('lod_scale_max', 3.0) * 1.6)
                for j, qj in quota.items():
                    mem = [i for i in range(N) if int(lab[i]) == j]
                    mem.sort(key=lambda i: -T.cards[i].imp)
                    for i in mem[:qj]:
                        c = T.cards[i]
                        col = leaf_color(T, c, j) if len(T.lobe_c) else [1, 1, 1]
                        emit_card(T, mb, c, 3, sc3 if c.kind != 'hang' else min(sc3, 1.4), False, card_nc(T, c, j), None, col)
        if lod == 0:
            t0 = mb.tris()
        out.append(mb)
    return out


# ───────────────────────── 樹種表 ─────────────────────────
def env_umbrella(h):
    return 0.55 + 0.45 * math.sin(math.pi * clamp(h * 0.95 + 0.1, 0, 1))


SPECIES = {
    # ── 杉／檜系高木（神社、北丘、深林主力）
    # P9 R1b 重做（2026-10-01 審圖：杉／檜 FAIL）：gen_cedar＝葉團＋樹齡脫枝＋方位不對稱＋樹梢個體差；lod_mode='clump'
    'sugi_a': dict(group='conifer', name='杉 A（神社直幹、窄錐、團簇冠）', gen=gen_cedar, cls='forest', budget=6000, bark='sugi',
                   H=24.0, dbh=0.72, cb=0.32, Lmax=2.9, prof=lambda h: max(0.13, (1 - h) ** 0.85) * lerp(0.75, 1.0, sstep(0.0, 0.25, h)),
                   ang=(-10, 42), droop=12, upturn=30, br_step=(0.17, 0.28), step_low=1.25, low_surv=0.6, shed_h=0.26,
                   vamp=0.26, az_amp=0.2, gaps=2, gap_w=(0.4, 0.75), gap_h=(1.4, 2.6), ecc=0.22, old_p=0.25, dead_p=0.12,
                   foliage='tuft', cl_r=0.6, cl_sp=0.42, cl_skip=0.04, tuft_n=5, side_p=1.2, sec_len=0.34,
                   fol_start_low=0.35, fol_start_top=0.05, top='spire', leader_len=1.9,
                   lean=1.2, wob=0.25, cells=[('A', 'sugi_a', 3), ('A', 'sugi_b', 2)], normal_mode='axis', lod_mode='clump', nc_crown=0.5,
                   flare=0.5, flare_h=1.0, lobes=6, lobe_amp=0.22, moss=0.35, r_cut=0.03, r_min=0.025, lobe_size=3.5),
    'sugi_b': dict(group='conifer', name='杉 B（老杉・斷頂燭台、老枝再生枝）', gen=gen_cedar, cls='forest', budget=6000, bark='sugi',
                   H=21.0, dbh=0.95, cb=0.27, Lmax=3.3, prof=lambda h: max(0.25, (1 - h) ** 0.55),
                   ang=(-16, 30), droop=18, upturn=34, br_step=(0.2, 0.32), step_low=1.2, low_surv=0.6, shed_h=0.26,
                   vamp=0.28, az_amp=0.26, gaps=2, gap_w=(0.45, 0.85), gap_h=(1.5, 3.0), ecc=0.35, old_p=0.45, dead_p=0.2,
                   foliage='tuft', cl_r=0.64, cl_sp=0.46, cl_skip=0.05, tuft_n=5, side_p=1.2, sec_len=0.32,
                   fol_start_low=0.35, fol_start_top=0.05, reit=2, reit_len=(1.2, 2.4), lean=3.5, wob=0.45,
                   broken=0.82, leaders=3, leader_lead=0.9, bare_top=4.0, splinter_len=(0.5, 1.2), break_frac=0.55,
                   leader_out=(2.2, 3.0), leader_rise=(-2.0, -0.4), leader_L=0.5, bare_bands=[(0.5, 0.56, 0.35)],
                   stub_p=0.65, stub_r=(0.02, 0.05), cells=[('A', 'sugi_b', 3), ('A', 'sugi_a', 1), ('A', 'sugi_dead', 1)],
                   normal_mode='axis', lod_mode='clump', nc_crown=0.45, flare=0.65, flare_h=1.3, lobes=6, lobe_amp=0.3, moss=0.5,
                   r_cut=0.03, r_min=0.025, lobe_size=3.5),
    'sugi_c': dict(group='conifer', name='杉 C（林內細長、副梢、高枝下）', gen=gen_cedar, cls='forest', budget=4500, bark='sugi',
                   H=17.0, dbh=0.38, cb=0.36, Lmax=1.9, low_live=1, prof=lambda h: max(0.15, (1 - h) ** 0.8) * lerp(0.8, 1.0, sstep(0.0, 0.25, h)),
                   ang=(-6, 44), droop=8, upturn=26, br_step=(0.18, 0.28), step_low=1.3, low_surv=0.5, shed_h=0.3,
                   vamp=0.3, az_amp=0.24, gaps=2, gap_w=(0.4, 0.8), gap_h=(1.0, 2.2), ecc=0.3, old_p=0.1, dead_p=0.18,
                   foliage='tuft', cl_r=0.5, cl_sp=0.4, cl_skip=0.05, tuft_n=4, side_p=1.0, sec_len=0.32,
                   fol_start_low=0.35, fol_start_top=0.05, top='twin', leader_len=1.6,
                   lean=2.5, wob=0.2, stub_p=0.7, cells=[('A', 'sugi_a', 2), ('A', 'sugi_b', 1)], normal_mode='axis',
                   lod_mode='clump', nc_crown=0.5, flare=0.35, flare_h=0.8, lobes=5, lobe_amp=0.15, moss=0.25, r_cut=0.03, r_min=0.022,
                   lobe_size=3.0),
    'hinoki_a': dict(group='conifer', name='檜 A（寬錐、下垂噴枝扇團、點頭梢）', gen=gen_cedar, cls='forest', budget=6000, bark='sugi',
                     H=18.0, dbh=0.55, cb=0.2, Lmax=3.0, prof=lambda h: max(0.12, 1 - h ** 1.5) ** 0.75,
                     ang=(4, 40), elev_j=14, step_irr=True, droop=0, upturn=-34, bend_at=0.4, fan_vy=0.35, br_step=(0.15, 0.26), step_low=1.2, low_surv=0.7,
                     shed_h=0.22, vamp=0.2, az_amp=0.16, gaps=2, gap_w=(0.4, 0.75), gap_h=(1.2, 2.4), ecc=0.25,
                     old_p=0.15, dead_p=0.1, foliage='fan', cl_r=0.55, cl_sp=0.36, cl_skip=0.04, fan_n=5, fan_droop=40,
                     spr_r=0.44, spr_step=0.29, spr_side=2, wood_frac=0.26, spr_low_skip=0.3, spr_low_step=1.6, spr_low_h=0.45, bent=False,
                     fan_rollj=40, roll_min=35, roll_max=80, side_p=1.4, side_vy=0.5, sec_len=0.36, fol_start_low=0.12, fol_start_top=0.03,
                     top='nod', top_bend=26, top_bend_len=2.2, leader_len=1.6, lean=1.5, wob=0.2,
                     cells=[('A', 'hinoki_a', 3), ('A', 'hinoki_b', 2)], normal_mode='axis', lod_mode='clump', nc_crown=0.7, flare=0.4,
                     flare_h=0.9, lobes=5, lobe_amp=0.18, moss=0.3, r_cut=0.03, r_min=0.022, lobe_size=3.0),
    'hinoki_b': dict(group='conifer', name='檜 B（老檜、圓頂寬冠、偏冠）', gen=gen_cedar, cls='forest', budget=6000, bark='sugi',
                     H=20.0, dbh=0.85, cb=0.3, Lmax=3.6, prof=lambda h: max(0.3, 1 - h ** 2.6) ** 0.5,
                     ang=(-2, 36), elev_j=16, step_irr=True, droop=0, upturn=-40, bend_at=0.4, fan_vy=0.35, br_step=(0.24, 0.38), trunk_bulge=0.06, step_low=1.2, low_surv=0.65,
                     shed_h=0.25, vamp=0.24, az_amp=0.22, gaps=2, gap_w=(0.45, 0.85), gap_h=(1.4, 2.6), ecc=0.38,
                     old_p=0.4, old_r=1.6, dead_p=0.22, deadlimb_r=0.05, foliage='fan', cl_r=0.6, cl_sp=0.38, cl_skip=0.04, fan_n=5, fan_droop=42,
                     spr_r=0.46, spr_step=0.33, spr_side=2, wood_frac=0.26, spr_low_skip=0.35, spr_low_step=1.7, spr_low_h=0.5, bent=False,
                     fan_rollj=40, roll_min=35, roll_max=80, side_p=1.4, side_vy=0.5, sec_len=0.36, fol_start_low=0.12, fol_start_top=0.03,
                     top='round', leader_len=1.4, lean=3.5, wob=0.5, s_curve=0.4, stub_p=0.7, stub_r=(0.025, 0.05),
                     cells=[('A', 'hinoki_b', 3), ('A', 'hinoki_a', 2)], normal_mode='axis', lod_mode='clump', nc_crown=0.7, flare=0.5,
                     flare_h=1.0, lobes=6, lobe_amp=0.24, moss=0.4, r_cut=0.03, r_min=0.022, lobe_size=3.2),
    # ── 一般闊葉（村緣、混合林）
    'konara_a': dict(group='broad', name='小楢 A（雜木林、不規則卵形）', gen=gen_sc, cls='forest', budget=5600, bark='hackberry',
                     H=13.0, dbh=0.38, fork=2.4, branch_h=1.9, crown=(4.8, 5.4, 4.2), crown_y=7.6, ecc=0.32, n_lobes=7, lobe_r=(0.3, 0.52),
                     main_scale=0.62, lobe_dist=(0.7, 1.05), lobe_el=(-0.45, 0.75),
                     n_holes=5, hole_r=(0.12, 0.24), n_attr=1500, D=0.42, trop_up=0.25, trop_light=0.12, lean=3,
                     cells=[('B', 'konara', 4), ('B', 'broad_yellow', 1)], card=(1.3, 1.65), r_leaf=0.03,
                     flare=0.35, lobes=5, lobe_amp=0.2, moss=0.3, r_cut=0.025, r_min=0.02, lobe_size=2.6),
    'konara_b': dict(group='broad', name='小楢 B（林緣、偏光單側樹冠）', gen=gen_sc, cls='forest', budget=5200, bark='hackberry',
                     H=11.5, dbh=0.32, fork=3.0, crown=(4.0, 3.4, 3.2), crown_y=7.4, ecc=0.55, n_lobes=5, lobe_r=(0.3, 0.48),
                     main_scale=0.7, lobe_dist=(0.65, 1.0), lobe_el=(-0.4, 0.7),
                     n_holes=3, n_attr=1300, D=0.4, trop_up=0.15, trop_light=0.45, lean=9,
                     cells=[('B', 'konara', 3), ('B', 'young_broad', 1)], card=(1.25, 1.6), r_leaf=0.03,
                     flare=0.3, lobes=4, lobe_amp=0.2, moss=0.3, r_cut=0.025, r_min=0.02, lobe_size=2.5),
    'keyaki_a': dict(group='broad', name='欅 A（掃帚／扇形）', gen=gen_sc, cls='forest', budget=6000, bark='zelkova',
                     H=17.0, dbh=0.55, fork=4.0, branch_h=3.4, crown=(6.2, 5.0, 6.0), crown_y=12.0, ecc=0.15, n_lobes=6,
                     lobe_r=(0.28, 0.42), lobe_el=(0.1, 1.0), n_holes=4, n_attr=1700, D=0.5, trop_up=0.75, trop_light=0.05,
                     extra_lobes=[((0, 7.5, 0), (2.2, 2.4, 2.2), 0.35)], cells=[('B', 'keyaki', 4), ('B', 'young_broad', 1)],
                     card=(1.5, 1.9), r_leaf=0.03, flare=0.4, lobes=6, lobe_amp=0.25, moss=0.2, r_cut=0.025, r_min=0.02,
                     lobe_size=3.0),
    'enoki_a': dict(group='broad', name='榎 A（寬傘形、村界標樹）', gen=gen_sc, cls='forest', budget=6000, bark='hackberry',
                    H=12.0, dbh=0.52, fork=3.0, crown=(6.4, 3.5, 6.0), crown_y=7.8, ecc=0.2, n_lobes=6, lobe_r=(0.3, 0.45),
                    lobe_el=(-0.1, 0.5), n_holes=4, n_attr=1700, D=0.48, trop_up=0.12, trop_light=0.1,
                    cells=[('B', 'enoki', 4), ('B', 'broad_yellow', 1)], card=(1.35, 1.7), r_leaf=0.03, roll='flat',
                    flat_mix=0.55, flare=0.45, lobes=5, lobe_amp=0.3, moss=0.35, r_cut=0.025, r_min=0.02, lobe_size=3.0),
    'shii_a': dict(group='broad', name='椎 A（常綠濃密圓頂、鎮守の森）', gen=gen_sc, cls='forest', budget=6000, bark='hackberry',
                   H=13.0, dbh=0.55, fork=2.6, crown=(6.0, 5.2, 5.8), crown_y=7.6, ecc=0.15, n_lobes=7, lobe_r=(0.3, 0.42),
                   n_holes=2, hole_r=(0.1, 0.16), n_attr=1900, D=0.42, trop_up=0.2, trop_light=0.08,
                   cells=[('B', 'shii', 4), ('B', 'kusu_a', 1)], card=(1.35, 1.7), r_leaf=0.03, ao_in=0.55, fill=0.9,
                   flare=0.5, lobes=6, lobe_amp=0.3, moss=0.4, r_cut=0.025, r_min=0.02, lobe_size=2.6),
    # ── 櫻（至少 3 樹形；花色克制、不做主題樂園粉）
    'sakura_yama': dict(group='sakura', name='山櫻（高、花葉同開、紅銅嫩葉）', gen=gen_sc, cls='garden', budget=10000, bark='sakura',
                        H=12.5, dbh=0.42, fork=3.8, crown=(5.2, 4.2, 5.0), crown_y=8.8, ecc=0.25, n_lobes=5, n_holes=4,
                        n_attr=1700, D=0.42, trop_up=0.3, trop_light=0.12, lean=4,
                        cells=[('B', 'sakura_yama', 3), ('B', 'sakura_bloom', 1)], card=(1.2, 1.55), r_leaf=0.03,
                        flare=0.35, lobes=5, lobe_amp=0.2, moss=0.2, r_cut=0.02, r_min=0.016, lobe_size=2.6, ao_in=0.7,
                        ao_warm=0.9, leaf_mul=(1.07, 0.97, 0.80), fill=0.35),
    'sakura_somei': dict(group='sakura', name='里櫻（低幹寬傘、庭園／參道）', gen=gen_sc, cls='garden', budget=11000, bark='sakura',
                         H=8.0, dbh=0.5, fork=1.9, branch_h=1.5, crown=(6.8, 2.8, 6.2), crown_y=5.4, ecc=0.2, n_lobes=7,
                         lobe_r=(0.28, 0.4), lobe_el=(-0.25, 0.45), n_holes=4, n_attr=1900, D=0.42, trop_up=0.04,
                         trop_light=0.08, trop_down=0.02, s_curve=0.25, cells=[('B', 'sakura_bloom', 4), ('B', 'sakura_yama', 1)],
                         card=(1.2, 1.5), r_leaf=0.03, flare=0.45, lobes=5, lobe_amp=0.3, moss=0.25, r_cut=0.02,
                         r_min=0.016, lobe_size=2.6, ao_in=0.72, wood_frac=0.45, ao_warm=0.9, leaf_mul=(1.07, 0.97, 0.80), fill=0.35),
    'sakura_shidare': dict(group='sakura', name='枝垂櫻（垂枝簾）', gen=gen_sc, cls='garden', budget=12000, bark='sakura',
                           H=9.5, dbh=0.5, fork=3.0, crown=(3.6, 3.0, 3.6), crown_y=7.0, ecc=0.1, n_lobes=4, n_holes=2,
                           n_attr=1200, D=0.4, trop_up=0.55, trop_light=0.04, s_curve=0.3,
                           cells=[('B', 'sakura_bloom', 1)], card=(1.0, 1.25), r_leaf=0.035, crown_cards=True,
                           hang=dict(cells=[('B', 'shidare_a', 1), ('B', 'shidare_b', 1)], card=(2.6, 3.4), frac=0.9, min_y=0.9),
                           flare=0.4, lobes=5, lobe_amp=0.25, moss=0.2, r_cut=0.02, r_min=0.016, lobe_size=2.4, ao_in=0.75,
                           ao_warm=0.9, leaf_mul=(1.07, 0.97, 0.80), fill=0.3),
    # ── 楓（庭園與山林）
    'momiji_a': dict(group='momiji', name='楓 A（庭園層狀、夏綠）', gen=gen_sc, cls='garden', budget=8000, bark='maple',
                     H=6.0, dbh=0.24, fork=1.3, branch_h=1.0, stems=2, lean=10, crown=(3.2, 1.9, 3.0), crown_y=3.9, ecc=0.25,
                     n_lobes=0, main_scale=0.18, extra_lobes=[((0.7, 2.8, 0.3), (3.3, 0.55, 2.9)),
                                             ((-0.6, 4.0, -0.4), (2.7, 0.5, 2.4)), ((0.3, 5.1, 0.2), (1.7, 0.5, 1.6))],
                     n_holes=3, n_attr=1300, D=0.32, trop_up=0.05, trop_light=0.1, roll='flat', flat_mix=0.4, flat_tilt=35,
                     cells=[('B', 'momiji_g', 3), ('B', 'momiji_g2', 2)], card=(1.1, 1.35), r_leaf=0.025, s_curve=0.3,
                     flare=0.3, lobes=4, lobe_amp=0.2, moss=0.25, r_cut=0.015, r_min=0.012, lobe_size=1.8),
    'momiji_b': dict(group='momiji', name='楓 B（山林、轉色中）', gen=gen_sc, cls='garden', budget=7000, bark='maple',
                     H=9.0, dbh=0.3, fork=2.0, crown=(4.6, 2.9, 3.9), crown_y=6.0, ecc=0.38, n_lobes=7, n_holes=5,
                     main_scale=0.6, lobe_dist=(0.7, 1.05), lobe_el=(-0.55, 0.6), lobe_r=(0.3, 0.45),
                     n_attr=1400, D=0.38, trop_up=0.22, trop_light=0.15, lean=5,
                     cells=[('B', 'momiji_turn', 3), ('B', 'momiji_g', 1)], card=(1.15, 1.4), r_leaf=0.025,
                     flare=0.3, lobes=4, lobe_amp=0.2, moss=0.3, r_cut=0.016, r_min=0.013, lobe_size=2.2),
    'momiji_c': dict(group='momiji', name='楓 C（多幹株立、紅葉克制）', gen=gen_sc, cls='garden', budget=7000, bark='maple',
                     H=7.0, dbh=0.18, fork=2.2, branch_h=1.4, stems=3, lean=12, crown=(3.6, 2.5, 3.3), crown_y=4.8, ecc=0.2,
                     n_lobes=6, n_holes=4, n_attr=1300, D=0.34, trop_up=0.18, trop_light=0.1, main_scale=0.55,
                     lobe_dist=(0.7, 1.05), lobe_el=(-0.5, 0.6), lobe_r=(0.28, 0.42),
                     cells=[('B', 'momiji_red', 2), ('B', 'momiji_turn', 2), ('B', 'momiji_g2', 1)], card=(1.1, 1.35),
                     r_leaf=0.025, flare=0.25, lobes=4, lobe_amp=0.15, moss=0.2, r_cut=0.015, r_min=0.012, lobe_size=2.0),
    # ── 松（庭園型＋自然山松）
    'akamatsu_a': dict(group='matsu', name='赤松（山松、高幹傘冠）', gen=gen_pine, cls='forest', budget=6000, bark='pine',
                       H=17.0, dbh=0.42, cb=0.6, Lmax=4.8, n_main=(7, 9), ang=(-8, 14), env=env_umbrella, upturn=38,
                       lean=6, wob=0.9, s_curve=0.7, cells=[('A', 'akamatsu', 1)], card=(1.0, 1.3), tuft_n=13,
                       trunk_top=0.88, leaders=3, tuft_spread=(40, 80), br_r=0.75, n_fork=(3, 4), keep_l1=True,
                       top_tint=(1.32, 0.92, 0.78), flare=0.3, lobes=4, lobe_amp=0.15, moss=0.15, r_cut=0.03, r_min=0.025,
                       lobe_size=2.4, normal_mode='lobes'),
    'akamatsu_b': dict(group='matsu', name='赤松 B（自然山松、偏冠雲層）', gen=gen_pine, cls='forest', budget=6000, bark='pine',
                       H=16.0, dbh=0.4, cb=0.48, Lmax=4.2, n_main=(13, 16), ang=(-6, 26), env=lambda h: 0.62 + 0.38 * math.sin(math.pi * clamp(h * 0.85 + 0.12, 0, 1)),
                       upturn=34, ecc=0.45, lean=8, wob=0.8, s_curve=0.6, cells=[('A', 'akamatsu', 1)], card=(1.5, 1.9), tuft_n=5,
                       trunk_top=0.9, leaders=3, tuft_spread=(20, 70), br_r=0.7, n_fork=(5, 7), fork_extra=5, keep_l1=True,
                       top_tint=(1.32, 0.92, 0.78), flare=0.3, lobes=4, lobe_amp=0.15, moss=0.15, r_cut=0.03, r_min=0.025,
                       lobe_size=2.4, normal_mode='lobes', seed=7, lod_mode='clump', lod_scale_max=2.4),
    'kuromatsu_a': dict(group='matsu', name='黑松（粗幹、曲折、寬冠）', gen=gen_pine, cls='forest', budget=6000, bark='pine',
                        H=11.0, dbh=0.55, cb=0.32, Lmax=4.2, n_main=(10, 14), ang=(-18, 30), env=lambda h: 1.0 - 0.45 * h,
                        upturn=40, lean=10, wob=0.9, s_curve=0.8, n_fork=(3, 5), cells=[('A', 'kuromatsu', 1)],
                        card=(1.0, 1.3), tuft_n=10, trunk_top=0.92, leaders=2, tuft_spread=(40, 78), keep_l1=True, flare=0.45, lobes=5, lobe_amp=0.25, moss=0.2, r_cut=0.03, r_min=0.025,
                        lobe_size=2.4, normal_mode='lobes', br_r=0.6),
    'niwamatsu_a': dict(group='matsu', name='庭園松（S 幹、雲團仕立て）', gen=gen_pine, cls='garden', budget=9000, bark='pine',
                        H=4.6, dbh=0.3, cb=0.32, Lmax=2.0, n_main=(6, 8), ang=(-10, 12), env=lambda h: 1.0 - 0.5 * h,
                        upturn=15, lean=16, wob=0.2, s_curve=0.9, n_fork=(1, 2), cells=[('A', 'kuromatsu', 1)],
                        card=(0.6, 0.8), tuft_n=7, pad=0.75, flare=0.35, lobes=4, lobe_amp=0.2, moss=0.15, r_cut=0.02,
                        r_min=0.016, lobe_size=1.0, normal_mode='lobes', br_r=0.7),
    # ── 柳（河岸／水車周邊）
    'yanagi_a': dict(group='yanagi', name='柳 A（河岸垂柳、偏水側）', gen=gen_sc, cls='garden', budget=11000, bark='willow',
                     H=9.5, dbh=0.5, fork=2.4, crown=(4.4, 2.8, 4.2), crown_y=7.0, ecc=0.35, n_lobes=4, n_holes=2,
                     n_attr=1100, D=0.42, trop_up=0.5, trop_light=0.25, lean=10,
                     cells=[('A', 'willow_a', 1)], card=(0.9, 1.1), crown_cards=False, r_leaf=0.035,
                     hang=dict(cells=[('A', 'willow_a', 1), ('A', 'willow_b', 1)], card=(2.3, 3.0), frac=1.0, min_y=0.7),
                     flare=0.45, lobes=5, lobe_amp=0.3, moss=0.35, r_cut=0.02, r_min=0.016, lobe_size=2.2, ao_in=0.72),
    'yanagi_b': dict(group='yanagi', name='柳 B（年輕、直立）', gen=gen_sc, cls='garden', budget=8000, bark='willow',
                     H=7.0, dbh=0.26, fork=2.0, crown=(2.8, 2.4, 2.8), crown_y=5.2, ecc=0.2, n_lobes=3, n_holes=1,
                     n_attr=900, D=0.36, trop_up=0.6, trop_light=0.1, lean=4,
                     cells=[('A', 'willow_b', 1)], card=(0.9, 1.1), crown_cards=False, r_leaf=0.03,
                     hang=dict(cells=[('A', 'willow_b', 2), ('A', 'willow_a', 1)], card=(1.9, 2.5), frac=1.0, min_y=0.8),
                     flare=0.3, lobes=4, lobe_amp=0.2, moss=0.25, r_cut=0.018, r_min=0.014, lobe_size=1.8, ao_in=0.75),
    # ── 老樹／Hero（神社、地標）
    'kusu_hero': dict(group='hero', name='樟 Hero（巨木、板根、寬圓冠）', gen=gen_sc, cls='hero', budget=15000, bark='camphor',
                      H=20.0, dbh=2.4, fork=3.4, branch_h=2.6, crown=(10.5, 6.8, 9.8), crown_y=12.6, ecc=0.2, n_lobes=8,
                      lobe_r=(0.26, 0.38), n_holes=5, hole_r=(0.08, 0.15), n_attr=2600, D=0.62, trop_up=0.18,
                      trop_light=0.1, lean=3, cells=[('B', 'kusu_a', 3), ('B', 'kusu_b', 2)], card=(1.7, 2.1), r_leaf=0.04,
                      flare=0.75, flare_h=1.8, lobes=7, lobe_amp=0.35, roots=7, root_len=(2.2, 4.5), embed=0.6, moss=0.5,
                      r_cut=0.035, r_min=0.03, lobe_size=3.4, trunk_sides=(14, 24), max_nodes=6000, fill=0.85),
    # 御神木杉 R1b：不是普通杉放大——老而不對稱的冠（強方位場＋偏冠）、斷頂＋高低不齊的再生幹、斷枝／枯枝（含粗枯枝）、
    #   冠隙、中段局部裸幹帶、強 root flare（板根＋9 條地表根）、非垂直主幹（傾斜＋S 彎）
    'sugi_hero': dict(group='hero', name='杉 Hero（御神木、古樹偏冠、斷頂再生幹）', gen=gen_cedar, cls='hero', budget=15000, bark='sugi',
                      H=30.0, dbh=2.0, cb=0.30, Lmax=4.6, prof=lambda h: max(0.22, (1 - h) ** 0.5),
                      ang=(-20, 28), droop=20, upturn=34, br_step=(0.26, 0.42), step_low=1.2, low_surv=0.6, shed_h=0.3,
                      vamp=0.32, az_amp=0.36, gaps=3, gap_w=(0.6, 1.0), gap_h=(2.6, 4.2), ecc=0.55, old_p=0.55, dead_p=0.24,
                      deadlimb_r=0.06, foliage='tuft', cl_r=0.8, cl_sp=0.5, cl_skip=0.04, tuft_n=6, side_p=1.3, sec_len=0.32,
                      fol_start_low=0.35, fol_start_top=0.05, reit=2, reit_len=(1.8, 3.4),
                      old_r=1.9, trunk_bulge=0.12, elev_j=12, step_irr=True,
                      lean=6.0, wob=1.3, s_curve=1.4, broken=0.84, leaders=3, leader_lead=2.0, leader_from=(4.5, 7.0),
                      leader_out=(2.4, 3.6), leader_rise=(-2.8, 0.2), leader_r=0.5, leader_L=0.45, bare_top=4.2, break_frac=0.7,
                      bare_bands=[(0.42, 0.52, 0.12)], stub_p=0.8, stub_r=(0.04, 0.09), stub_len=1.5, low_live=2,
                      cells=[('A', 'sugi_b', 3), ('A', 'sugi_a', 2), ('A', 'sugi_dead', 1)], normal_mode='axis', lod_mode='clump', nc_crown=0.45,
                      flare=1.25, flare_h=2.6, lobes=6, lobe_amp=0.8, roots=9, root_len=(2.4, 5.0), embed=0.7, moss=0.6,
                      r_cut=0.035, r_min=0.03, lobe_size=4.0, trunk_sides=(16, 24), splinter_len=(0.8, 1.8), light_az=0.6),
    'keyaki_hero': dict(group='hero', name='欅 Hero（大扇形、地標）', gen=gen_sc, cls='hero', budget=14000, bark='zelkova',
                        H=23.0, dbh=1.6, fork=4.6, branch_h=3.8, crown=(9.5, 7.0, 9.0), crown_y=15.0, ecc=0.15, n_lobes=8,
                        lobe_r=(0.26, 0.38), lobe_el=(0.1, 1.0), n_holes=5, n_attr=2400, D=0.62, trop_up=0.7,
                        trop_light=0.05, extra_lobes=[((0, 9.5, 0), (3.2, 3.0, 3.2), 0.3)],
                        cells=[('B', 'keyaki', 4), ('B', 'young_broad', 1)], card=(1.8, 2.2), r_leaf=0.04, flare=0.65,
                        flare_h=1.6, lobes=7, lobe_amp=0.3, roots=5, root_len=(1.8, 3.6), embed=0.6, moss=0.3,
                        r_cut=0.035, r_min=0.03, lobe_size=3.6, trunk_sides=(14, 22), max_nodes=6000),
    # ── 幼樹／次生樹（forest edge）
    'young_sugi': dict(group='young', name='幼杉', gen=gen_conifer, cls='young', budget=3000, bark='sugi',
                       H=6.0, dbh=0.11, cb=0.06, Lmax=1.5, env_pow=0.95, ang=(-6, 45), upturn=26, droop=6,
                       br_step=(0.18, 0.28), gap=0.12, gaps=1, ecc=0.3, lean=3, wob=0.15, stubs=False,
                       core_fill=0.24, cells=[('A', 'sugi_young', 1)], card=(1.0, 1.3), card_step=0.28, normal_mode='axis',
                       flare=0.2, flare_h=0.4, lobes=3, lobe_amp=0.1, r_cut=0.02, r_min=0.015, lobe_size=1.6, top_cards=4,
                       embed=0.25),
    'young_broad_a': dict(group='young', name='次生闊葉 A（單幹）', gen=gen_sc, cls='young', budget=3000, bark='hackberry',
                          H=4.8, dbh=0.09, fork=1.6, crown=(1.8, 1.7, 1.7), crown_y=3.2, ecc=0.35, n_lobes=3, n_holes=2,
                          n_attr=600, D=0.3, trop_up=0.4, trop_light=0.3, lean=6,
                          cells=[('B', 'young_broad', 3), ('B', 'konara', 1)], card=(1.0, 1.25), r_leaf=0.02,
                          flare=0.2, lobes=3, lobe_amp=0.1, r_cut=0.012, r_min=0.01, lobe_size=1.4, embed=0.25),
    'young_broad_b': dict(group='young', name='次生闊葉 B（萌芽株立）', gen=gen_sc, cls='young', budget=3200, bark='hackberry',
                          H=4.2, dbh=0.07, fork=1.2, stems=4, lean=14, crown=(2.2, 1.6, 2.0), crown_y=2.8, ecc=0.25,
                          n_lobes=3, n_holes=2, n_attr=700, D=0.28, trop_up=0.3, trop_light=0.2,
                          cells=[('B', 'young_broad', 2), ('B', 'broad_yellow', 1), ('B', 'enoki', 1)], card=(1.0, 1.2),
                          r_leaf=0.02, flare=0.15, lobes=3, lobe_amp=0.1, r_cut=0.012, r_min=0.01, lobe_size=1.4, embed=0.25),
    # ── 枯木／倒木（少量）
    'snag_a': dict(group='dead', name='枯立木（斷頂）', gen=gen_snag, cls='dead', budget=2500, bark='dead', H=8.5, dbh=0.36,
                   cells=[('A', 'twigs', 1)], card=(1.2, 1.6), flare=0.4, lobes=4, lobe_amp=0.2, moss=0.3, r_cut=0.03,
                   r_min=0.025, lobe_size=2.0, stub_dead=True, bent=False, wood_frac=1.0, roots=4, keep_l1=True,
                   root_len=(0.6, 1.2), splinters=6, splinter_len=(0.5, 1.4)),
    'log_a': dict(group='dead', name='倒木（半埋、苔）', gen=gen_log, cls='dead', budget=1200, bark='dead', L=6.5, dbh=0.62,
                  sink=0.08, stubs=3, cells=[('A', 'twigs', 1)], card=(1.0, 1.0), moss=0.8, r_cut=0.03, r_min=0.025,
                  lobe_size=2.0, flare=0.0, embed=0.0, wood_frac=1.0, n_lod=3),
    # ── 灌木／蕨／地被（共享配套；R1 不鋪場景）
    'shrub_a': dict(group='under', name='灌木（雜木叢）', gen=gen_clump, cls='under', budget=900, clump='dome', R=0.9, Hc=1.3,
                    n=110, cells=[('A', 'shrub', 1)], card=(0.75, 1.0), normal_mode='center', n_lod=3, lobe_size=0.8,
                    wood_frac=0.0, lod_scale_max=1.35, lod_keep_h=True),
    'tsutsuji_a': dict(group='under', name='躑躅（修剪圓團）', gen=gen_clump, cls='under', budget=900, clump='dome', R=1.05, Hc=0.85,
                       n=150, shell=0.75, cells=[('A', 'azalea', 1)], card=(0.55, 0.72), normal_mode='center', n_lod=3, lobe_size=0.7,
                       wood_frac=0.0, lod_scale_max=1.35, lod_keep_h=True),
    'sasa_a': dict(group='under', name='隈笹叢', gen=gen_clump, cls='under', budget=700, clump='radial', R=0.8, Hc=0.9,
                   n=60, tilt=(5, 30), cells=[('A', 'sasa', 1)], card=(1.5, 1.9), normal_mode='center', n_lod=3,
                   lobe_size=0.8, wood_frac=0.0, lod_scale_max=1.25, lod_keep_h=True),
    'fern_a': dict(group='under', name='蕨叢', gen=gen_clump, cls='under', budget=500, clump='radial', R=0.35, Hc=0.6,
                   n=14, tilt=(35, 62), cells=[('A', 'fern_a', 2), ('A', 'fern_b', 1)], card=(1.7, 2.1), normal_mode='center',
                   n_lod=3, lobe_size=0.6, wood_frac=0.0, bent=True, lod_scale_max=1.2, lod_keep_h=True),
}

GROUP_NAMES = {'conifer': '杉／檜系高木', 'broad': '一般闊葉樹', 'sakura': '櫻', 'momiji': '楓', 'matsu': '松', 'yanagi': '柳',
               'hero': '老樹／Hero', 'young': '幼樹／次生樹', 'dead': '枯木／倒木', 'under': '灌木／蕨／地被（共享配套）'}
LOD_DIST = {'forest': [0, 30, 70, 160, 700], 'garden': [0, 30, 70, 150, 600], 'hero': [0, 40, 90, 200, 900],
            'young': [0, 25, 55, 120, 400], 'dead': [0, 30, 70, 150, 500], 'under': [0, 15, 35, 70]}
BUDGET_CAP = {'forest': 6000, 'garden': 12000, 'hero': 15000, 'young': 3500, 'dead': 2500, 'under': 1000}


def collision_for(T):
    sp = T.sp
    if T.coll:
        return T.coll
    if sp['group'] == 'under' or T.trunk is None:
        return []
    tr = T.trunk
    y1 = min(sp.get('fork', T.H * sp.get('cb', 0.4)), 3.2 if sp['cls'] != 'hero' else 4.0)
    y1 = max(y1, 1.8)
    p1, _ = T.trunk_at(min(y1, tr.pts[-1][1] - 0.05))
    r = T.trunk_r(1.0)
    out = [{'type': 'cylinder', 'a': [0.0, -0.2, 0.0], 'b': [float(p1[0]), float(y1), float(p1[2])], 'r': float(r * 1.02)}]
    if sp['cls'] == 'hero':
        for ch in T.chains:
            if ch.kind != 'wood' or ch is tr or ch.lvl != 1 or ch.rad[0] < 0.15 or ch.pts[0][1] > 4.5:
                continue
            q = ch.pts[min(len(ch.pts) - 1, max(1, int(len(ch.pts) * 0.35)))]
            if q[1] > 5.0:
                continue
            out.append({'type': 'cylinder', 'a': [float(x) for x in ch.pts[0]], 'b': [float(x) for x in q],
                        'r': float(ch.rad[0] * 0.85)})
            if len(out) >= 6:
                break
    return out


# R1 審圖第 1 輪：葉叢卡片 s=1 時只有 0.3–0.6 m（植物學實寸）→ 10–60 m 看樹冠只剩零星斑點（松 2–3／10、椎讀成稀疏）。
#   依群組放大卡片（三角面數不變；LOD0 預算仍由 build_lods 截）；個別樹種可用 card_gain 覆寫。
CARD_GAIN = {'conifer': 1.55, 'broad': 1.4, 'sakura': 1.15, 'momiji': 1.3, 'matsu': 2.3, 'yanagi': 1.0,
             'hero': 1.45, 'young': 1.25, 'dead': 1.0, 'under': 1.0}


def build(tid):
    sp = dict(SPECIES[tid])
    g = sp.get('card_gain', CARD_GAIN.get(sp['group'], 1.0))
    if 'card' in sp and g != 1.0:
        sp['card'] = (sp['card'][0] * g, sp['card'][1] * g)
    t0 = time.time()
    T = Tree(tid, sp)
    sp['gen'](T)
    # 根部 root flare：有主幹、夠高的樹都長地表根（未指定時依胸徑給 3–4 條短根；roots=0 可關）
    if T.trunk is not None and sp['gen'] is not gen_log and sp.get('roots', 3 if T.H >= 6 else 0):
        add_surface_roots(T)
    assign_wind(T)
    card_wind(T)
    lods = build_lods(T)
    info = {'group': sp['group'], 'group_name': GROUP_NAMES[sp['group']], 'name': sp['name'], 'cls': sp['cls'],
            'budget': sp['budget'], 'budget_cap': BUDGET_CAP[sp['cls']], 'lod_dist': LOD_DIST[sp['cls']][:len(lods) + 1],
            'lods': [], 'collision': collision_for(T), 'cards': len(T.cards),
            'chains': len(T.chains), 'light_az': T.light_az}
    lo, hi = None, None
    for mb in lods:
        a, b = mb.aabb()
        info['lods'].append({'name': mb.name, 'tris': mb.tris(), 'mats': mb.mats, 'aabb': [a.tolist(), b.tolist()]})
        if mb is lods[0]:
            lo, hi = a, b
    info['height'] = float(hi[1])
    info['crown_w'] = float(max(hi[0] - lo[0], hi[2] - lo[2]))
    info['dbh_m'] = float(T.trunk_r(1.3) * 2) if T.trunk is not None else 0.0
    info['secs'] = round(time.time() - t0, 1)
    return lods, info


def geo_hash(built):
    """每級網格的幾何雜湊（位置／面／UV／UV2／頂點色，取 5 位小數）：證明未改的樹逐位元不變。"""
    import hashlib
    out = {}
    for tid, (lods, info) in built.items():
        hs = []
        for mb in lods:
            h = hashlib.sha1()
            for arr in (mb.P, mb.UV, mb.UV2, mb.C):
                h.update(np.round(np.asarray(arr, dtype=np.float64), 5).tobytes())
            h.update(repr(mb.F).encode())
            h.update(repr(mb.FM).encode())
            h.update(repr(mb.mats).encode())
            hs.append(h.hexdigest()[:16])
        out[tid] = hs
    return out


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    only = []
    sil = '--sil' in argv
    hash_out = ''
    for a in argv:
        if a.startswith('--only='):
            only = [x for x in a[7:].split(',') if x]
        if a.startswith('--hash='):
            hash_out = a[7:]
    ids = only or list(SPECIES)
    K.clear_scene(bpy)
    mats = set()
    built = {}
    atlas = None
    sil_out = {}
    if sil:
        import veg_sil
        atlas = veg_sil.AtlasAlpha(bpy, {'A': KIT + '/tex/VL_A_albedo.png', 'B': KIT + '/tex/VL_B_albedo.png'})
    for tid in ids:
        lods, info = build(tid)
        built[tid] = (lods, info)
        for mb in lods:
            mats.update(mb.mats)
        print('[veg] %-15s %s  LOD tris %s  cards %d  H %.1f  W %.1f  dbh %.2f  (%.1fs)' % (
            tid, info['name'], [l['tris'] for l in info['lods']], info['cards'], info['height'], info['crown_w'],
            info['dbh_m'], info['secs']), flush=True)
        if sil and info['cards'] and len(lods) == 4:
            mb0 = lods[0]
            leaf_v = sorted({i for f, m in zip(mb0.F, mb0.FM) if mb0.mats[m].startswith('VK_Leaf_') for i in f})
            cy = float(np.percentile(np.asarray(mb0.P)[leaf_v, 1], 5)) if leaf_v else info['height'] * 0.4
            r = veg_sil.compare(lods, atlas, cy)
            sil_out[tid] = r
            print('[sil] %-15s ' % tid + '  '.join('%s IoU %.2f(min %.2f) W %+.0f%% C %.1fm T %+.1fm gap %s' % (
                p['pair'], p['iou'], p['iou_min'], p['width'] * 100, p['center_m'], p['top_m'],
                '-' if p['gap_iou'] is None else '%.2f' % p['gap_iou']) for p in r['pairs']), flush=True)
    bm = K.blender_mats(bpy, sorted(mats))
    objs = []
    modules = {}
    for tid, (lods, info) in built.items():
        for mb in lods:
            objs.append(mb.to_blender(bm))
            modules[mb.name] = {'tris': mb.tris()}
    os.makedirs(KIT + '/src', exist_ok=True)
    # --only＝試算（只印面數／尺寸，不寫 src/）：部分建置會讓 prefab 刪掉其他樹的 mesh／prefab，所以正式輸出一律全建
    if only:
        print('[veg] --only 試算完成（未寫 src/；完整建置約 30 s，請不帶 --only 重建）')
        if hash_out:
            K.write_json(hash_out, geo_hash(built))
        return
    if sil:
        K.write_json(KIT + '/src/lod_silhouette.json', {
            '_note': 'build_veg_kit.py --sil：逐級正交剪影比較（veg_sil.py；4 方位、0.24 m 格）。ART_REVIEW 參考，非 gate。',
            'trees': sil_out})
    K.export_glb(bpy, KIT + '/src/veg_kit.glb', objs)
    trees = {tid: info for tid, (lods, info) in built.items()}
    K.write_json(KIT + '/src/modules_blender.json', {
        '_note': 'P9 R1 植被庫。由 godot/assets/blender/village_v2/build_veg_kit.py 產生，勿手改。',
        'modules': modules, 'total_tris': sum(m['tris'] for m in modules.values()), 'trees': trees,
        'groups': GROUP_NAMES, 'only': only})
    print('[veg] %d 變體、%d 物件 → %s/src/veg_kit.glb' % (len(built), len(objs), KIT))


main()
