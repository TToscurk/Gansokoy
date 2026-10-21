"""arch_spatial — 建築構件空間驗證核心（Blender 端，唯讀）。

在 Blender 內執行（blender -b ... --python / Blender MCP execute_blender_code 皆可 import）。
只讀場景：不改物件、不存檔。所有幾何一律先轉成「世界座標的評估後網格」再比較
（含修改器、Parent、非均勻縮放、負縮放；負縮放會反轉三角形繞向以保持外法線）。

主要入口
  evaluate(spec, cache_path=None) -> report dict      # 依連接表／約束 JSON 驗證
  scan(objects=None, ...)          -> report dict      # 沒有連接表時：懸空零件＋未宣告穿插
  transform_info(obj) / bounds_info(obj)               # Phase 1 座標／尺寸／OBB
  blender_to_godot(v)                                  # 預設 glTF 匯出軸向 (x, z, -y)，已由測試實際匯出驗證

狀態只有 PASS / WARN / FAIL / UNKNOWN。資料不足（非封閉網格算不出穿透深度、物件不存在）
一律 UNKNOWN，不猜 PASS。容差單位為公尺（角度為度）。
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import struct
import time

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

VERSION = "arch_spatial/1.0"
UP = Vector((0.0, 0.0, 1.0))

# 預設容差（公尺／度）。硬表面木構建築；個別約束可用 tol / tol_rel 覆寫。
DEFAULT_TOL = {
    "CONTACT": 0.002,
    "SUPPORT": 0.003,
    "SNAP": 0.002,
    "OVERLAP_ALLOWED": 0.002,
    "CLEARANCE_REQUIRED": 0.0,
    "NO_INTERSECTION": 0.001,
    "SYMMETRIC": 0.01,
    "PARALLEL": 0.5,
    "PERPENDICULAR": 0.5,
    "COAXIAL": 0.01,
    "CONTINUOUS": 0.01,
    "EVEN_SPACING": 0.05,  # 相對值（間距偏差／平均間距）
}
CONSTRAINT_TYPES = tuple(DEFAULT_TOL.keys())


# ───────────────────────── 幾何資料 ─────────────────────────

class Geom:
    """一個構件的世界座標三角網格 + BVH。"""

    __slots__ = ("name", "verts", "tris", "normals", "areas", "bvh", "manifold",
                 "key", "bmin", "bmax", "area", "det", "_cent")

    def __init__(self, name, verts, tris, det=1.0):
        self.name = name
        self.det = det
        self.verts = verts
        self.tris = tris
        self.normals = []
        self.areas = []
        for a, b, c in tris:
            n = (verts[b] - verts[a]).cross(verts[c] - verts[a])
            ar = n.length * 0.5
            self.areas.append(ar)
            self.normals.append(n.normalized() if ar > 1e-14 else Vector((0.0, 0.0, 0.0)))
        self.area = sum(self.areas)
        edges = {}
        for a, b, c in tris:
            for e in ((a, b), (b, c), (c, a)):
                k = (e[0], e[1]) if e[0] < e[1] else (e[1], e[0])
                edges[k] = edges.get(k, 0) + 1
        self.manifold = bool(tris) and all(v == 2 for v in edges.values())
        self.bvh = BVHTree.FromPolygons(verts, tris, all_triangles=True) if tris else None
        if verts:
            self.bmin = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
            self.bmax = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
        else:
            self.bmin = self.bmax = Vector((0.0, 0.0, 0.0))
        h = hashlib.sha1()
        h.update(struct.pack("<I", len(verts)))
        for v in verts:
            h.update(struct.pack("<3q", round(v.x * 1e6), round(v.y * 1e6), round(v.z * 1e6)))
        for t in tris:
            h.update(struct.pack("<3I", *t))
        self.key = h.hexdigest()
        self._cent = None

    @property
    def size(self):
        return self.bmax - self.bmin

    def centroid(self):
        """面積加權表面重心（不是原點，也不是 AABB 中心）。"""
        if self._cent is None:
            acc = Vector((0.0, 0.0, 0.0))
            for (a, b, c), ar in zip(self.tris, self.areas):
                acc += (self.verts[a] + self.verts[b] + self.verts[c]) * (ar / 3.0)
            self._cent = acc / self.area if self.area > 0 else (self.bmin + self.bmax) * 0.5
        return self._cent


def geom_from_object(obj, depsgraph=None) -> Geom:
    if depsgraph is None:
        depsgraph = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(depsgraph)
    me = ev.to_mesh()
    try:
        me.calc_loop_triangles()
        mw = ev.matrix_world.copy()
        det = mw.to_3x3().determinant()
        verts = [mw @ v.co for v in me.vertices]
        tris = [tuple(lt.vertices) for lt in me.loop_triangles]
    finally:
        ev.to_mesh_clear()
    if det < 0:  # 負縮放：世界空間繞向反了，翻回來讓法線朝外
        tris = [(a, c, b) for a, b, c in tris]
    return Geom(obj.name, verts, tris, det)


def split_islands(g: Geom, min_tris=1) -> list:
    """把單一網格拆成連通島（Tripo 單網格建築用）。"""
    parent = list(range(len(g.verts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for a, b, c in g.tris:
        ra, rb, rc = find(a), find(b), find(c)
        parent[rb] = ra
        parent[find(rc)] = ra
    groups = {}
    for t in g.tris:
        groups.setdefault(find(t[0]), []).append(t)
    out = []
    for n, (root, tris) in enumerate(sorted(groups.items(), key=lambda kv: -len(kv[1]))):
        if len(tris) < min_tris:
            continue
        used = sorted({i for t in tris for i in t})
        remap = {old: new for new, old in enumerate(used)}
        out.append(Geom(f"{g.name}#island{n}", [g.verts[i] for i in used],
                        [(remap[a], remap[b], remap[c]) for a, b, c in tris], g.det))
    return out


# ───────────────────────── Phase 1：座標／Transform／Bounds ─────────────────────────

def blender_to_godot(v):
    """Blender Z-up → glTF/Godot Y-up（Blender glTF 匯出預設 +Y Up）。Blender -Y = Godot +Z。"""
    return Vector((v[0], v[2], -v[1]))


def godot_to_blender(v):
    return Vector((v[0], -v[2], v[1]))


def transform_info(obj) -> dict:
    mw = obj.matrix_world
    m3 = mw.to_3x3()
    cols = [m3.col[i].copy() for i in range(3)]
    lengths = [c.length for c in cols]
    det = m3.determinant()
    shear = 0.0
    for i, j in ((0, 1), (0, 2), (1, 2)):
        if lengths[i] > 1e-12 and lengths[j] > 1e-12:
            shear = max(shear, abs(cols[i].normalized().dot(cols[j].normalized())))
    loc, quat, sc = mw.decompose()
    return {
        "object": obj.name,
        "parent": obj.parent.name if obj.parent else None,
        "translation": list(loc),
        "quaternion_wxyz": list(quat),
        "euler_xyz_deg": [math.degrees(a) for a in quat.to_euler("XYZ")],
        "axis_lengths": lengths,
        "det": det,
        "negative_scale": det < 0,
        "uniform_scale": (max(lengths) - min(lengths)) <= 1e-6 * max(1.0, max(lengths)),
        "shear_cos": shear,  # 父層非均勻縮放＋子層旋轉會產生斜切；>1e-4 時軸向不再正交
        "world_axes": {"X": list(cols[0].normalized()), "Y": list(cols[1].normalized()), "Z": list(cols[2].normalized())},
    }


def _jacobi3(m):
    """3x3 對稱矩陣特徵分解（Jacobi）。回傳 (eigvals, eigvecs as columns list)。"""
    a = [[m[i][j] for j in range(3)] for i in range(3)]
    v = [[1.0 if i == j else 0.0 for j in range(3)] for i in range(3)]
    for _ in range(50):
        p, q = max(((0, 1), (0, 2), (1, 2)), key=lambda ij: abs(a[ij[0]][ij[1]]))
        if abs(a[p][q]) < 1e-15:
            break
        th = 0.5 * math.atan2(2 * a[p][q], a[q][q] - a[p][p])
        c, s = math.cos(th), math.sin(th)
        for k in range(3):
            akp, akq = a[k][p], a[k][q]
            a[k][p], a[k][q] = c * akp - s * akq, s * akp + c * akq
        for k in range(3):
            apk, aqk = a[p][k], a[q][k]
            a[p][k], a[q][k] = c * apk - s * aqk, s * apk + c * aqk
        for k in range(3):
            vkp, vkq = v[k][p], v[k][q]
            v[k][p], v[k][q] = c * vkp - s * vkq, s * vkp + c * vkq
    vals = [a[i][i] for i in range(3)]
    vecs = [Vector((v[0][i], v[1][i], v[2][i])).normalized() for i in range(3)]
    return vals, vecs


def _box_on_axes(points, axes):
    lo = [min(p.dot(ax) for p in points) for ax in axes]
    hi = [max(p.dot(ax) for p in points) for ax in axes]
    centre = sum((ax * ((l + h) * 0.5) for ax, l, h in zip(axes, lo, hi)), Vector((0.0, 0.0, 0.0)))
    return {"center": list(centre), "axes": [list(a) for a in axes],
            "extents": [h - l for l, h in zip(lo, hi)]}


def obb_pca(g: Geom) -> dict:
    pts = g.verts
    c = sum(pts, Vector((0.0, 0.0, 0.0))) / len(pts)
    cov = [[0.0] * 3 for _ in range(3)]
    for p in pts:
        d = p - c
        for i in range(3):
            for j in range(3):
                cov[i][j] += d[i] * d[j]
    _, vecs = _jacobi3(cov)
    out = _box_on_axes(pts, vecs)
    out["method"] = "pca"
    return out


def _hull2d(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def obb_upright(g: Geom, up=UP) -> dict:
    """直立 OBB：只繞 up 旋轉的最小面積外框（旋轉卡尺）。建築／柱子最實用的局部框。"""
    up = Vector(up).normalized()
    ref = Vector((1, 0, 0)) if abs(up.x) < 0.9 else Vector((0, 1, 0))
    e1 = (ref - up * ref.dot(up)).normalized()
    e2 = up.cross(e1)
    hull = _hull2d([(round(p.dot(e1), 7), round(p.dot(e2), 7)) for p in g.verts])
    best = None
    for i in range(len(hull)):
        x0, y0 = hull[i]
        x1, y1 = hull[(i + 1) % len(hull)]
        ang = math.atan2(y1 - y0, x1 - x0)
        ca, sa = math.cos(ang), math.sin(ang)
        us = [x * ca + y * sa for x, y in hull]
        vs = [-x * sa + y * ca for x, y in hull]
        area = (max(us) - min(us)) * (max(vs) - min(vs))
        if best is None or area < best[0] - 1e-12:
            best = (area, ang)
    ang = best[1] if best else 0.0
    a1 = e1 * math.cos(ang) + e2 * math.sin(ang)
    a2 = up.cross(a1)
    out = _box_on_axes(g.verts, [a1, a2, up])
    yaw = math.degrees(math.atan2(a1.dot(e2), a1.dot(e1))) % 90.0
    out.update({"method": "upright_min_area", "yaw_mod90_deg": yaw})
    return out


def obb_object(obj, depsgraph=None):
    """物件自身軸向的 OBB（local AABB × matrix_world）。有斜切時回 None（軸不正交）。"""
    ti = transform_info(obj)
    if ti["shear_cos"] > 1e-4:
        return None
    if depsgraph is None:
        depsgraph = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(depsgraph)
    bb = [Vector(c) for c in ev.bound_box]
    lmin = Vector((min(c.x for c in bb), min(c.y for c in bb), min(c.z for c in bb)))
    lmax = Vector((max(c.x for c in bb), max(c.y for c in bb), max(c.z for c in bb)))
    mw = ev.matrix_world
    m3 = mw.to_3x3()
    axes = [m3.col[i].normalized() for i in range(3)]
    ext = [(lmax[i] - lmin[i]) * m3.col[i].length for i in range(3)]
    return {"center": list(mw @ ((lmin + lmax) * 0.5)), "axes": [list(a) for a in axes],
            "extents": ext, "method": "object_axes"}


def bounds_info(obj, depsgraph=None) -> dict:
    """Local AABB、緊世界 AABB（頂點）、鬆世界 AABB（bound_box 角點）、OBB、原點 vs 幾何中心。"""
    if depsgraph is None:
        depsgraph = bpy.context.evaluated_depsgraph_get()
    g = geom_from_object(obj, depsgraph)
    ev = obj.evaluated_get(depsgraph)
    bb = [Vector(c) for c in ev.bound_box]
    loose = [ev.matrix_world @ c for c in bb]
    lmin = Vector((min(c.x for c in bb), min(c.y for c in bb), min(c.z for c in bb)))
    lmax = Vector((max(c.x for c in bb), max(c.y for c in bb), max(c.z for c in bb)))
    lo = Vector((min(c.x for c in loose), min(c.y for c in loose), min(c.z for c in loose)))
    hi = Vector((max(c.x for c in loose), max(c.y for c in loose), max(c.z for c in loose)))
    origin = obj.matrix_world.translation
    return {
        "object": obj.name,
        "local_aabb": {"min": list(lmin), "max": list(lmax), "size": list(lmax - lmin)},
        "world_aabb": {"min": list(g.bmin), "max": list(g.bmax), "size": list(g.size)},
        "world_aabb_loose": {"min": list(lo), "max": list(hi), "size": list(hi - lo)},
        "obb_object": obb_object(obj, depsgraph),
        "obb_upright": obb_upright(g) if g.verts else None,
        "origin": list(origin),
        "aabb_center": list((g.bmin + g.bmax) * 0.5),
        "surface_centroid": list(g.centroid()),
        "origin_to_aabb_center": list(origin - (g.bmin + g.bmax) * 0.5),
        "manifold": g.manifold,
        "tris": len(g.tris),
    }


def aabb_overlap(ga: Geom, gb: Geom, margin=0.0):
    lo = Vector((max(ga.bmin[i], gb.bmin[i]) for i in range(3)))
    hi = Vector((min(ga.bmax[i], gb.bmax[i]) for i in range(3)))
    if all(lo[i] <= hi[i] + margin for i in range(3)):
        return lo - Vector((margin,) * 3), hi + Vector((margin,) * 3)
    return None


# ───────────────────────── 建築局部座標系 ─────────────────────────

class Frame:
    """建築自身座標：right / front / up。left/right 以建築面朝 front 時的自身左右定義。"""

    def __init__(self, origin=(0, 0, 0), front=(0, -1, 0), up=(0, 0, 1)):
        self.origin = Vector(origin)
        self.up = Vector(up).normalized()
        f = Vector(front)
        f = (f - self.up * f.dot(self.up)).normalized()
        self.front = f
        self.right = f.cross(self.up)

    def to_local(self, p):
        d = Vector(p) - self.origin
        return Vector((d.dot(self.right), d.dot(self.front), d.dot(self.up)))

    def dir(self, name):
        s = -1.0 if name.startswith("-") else 1.0
        k = name.lstrip("+-").lower()
        base = {"right": self.right, "front": self.front, "up": self.up,
                "x": Vector((1, 0, 0)), "y": Vector((0, 1, 0)), "z": Vector((0, 0, 1))}[k]
        return base * s

    def as_dict(self):
        return {"origin": list(self.origin), "right": list(self.right), "front": list(self.front), "up": list(self.up)}


_AXIS = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}


def _parse_axis(s):
    s = s.strip().upper()
    sign = -1.0 if s.startswith("-") else 1.0
    return _AXIS[s.lstrip("+-")] * sign


def frame_from_spec(spec) -> Frame:
    """spec: {"origin": 物件名|[x,y,z], "front": 物件名(MARK_Front)|"-Y"|"local:-Y@物件名"}。預設 Godot +Z 正面 = Blender -Y。"""
    spec = spec or {}
    o = spec.get("origin", (0, 0, 0))
    if isinstance(o, str):
        ob = bpy.data.objects.get(o)
        if ob is None:
            raise KeyError(f"frame origin 物件不存在：{o}")
        origin = ob.matrix_world.translation.copy()
        base_rot = ob.matrix_world.to_3x3().normalized()
    else:
        origin = Vector(o)
        base_rot = Matrix.Identity(3)
    f = spec.get("front", "-Y")
    if isinstance(f, str) and f in bpy.data.objects:
        front = bpy.data.objects[f].matrix_world.translation - origin
    elif isinstance(f, str) and f.startswith("local:"):
        ax, _, owner = f[6:].partition("@")
        rot = bpy.data.objects[owner].matrix_world.to_3x3().normalized() if owner else base_rot
        front = rot @ _parse_axis(ax)
    elif isinstance(f, str):
        front = base_rot @ _parse_axis(f)
    else:
        front = Vector(f)
    return Frame(origin, front, spec.get("up", (0, 0, 1)))


# ───────────────────────── Phase 2：BVHTree 量測 ─────────────────────────

def samples(g: Geom, step, max_n=6000, tri_filter=None):
    """確定性的表面取樣：頂點、邊（每 step）、三角形內部（重心格點）。回傳 [(point, tri_index)]。"""
    idx = [i for i in range(len(g.tris)) if (tri_filter is None or tri_filter(i)) and g.areas[i] > 1e-14]
    if not idx:
        return []
    step = step or default_step(g)
    total = sum(g.areas[i] for i in idx)
    if total / (step * step) > max_n:
        step = math.sqrt(total / max_n)
    if len(idx) > max_n:  # 超大網格：均勻抽三角形
        stride = len(idx) / max_n
        idx = [idx[int(k * stride)] for k in range(max_n)]
    out = []
    for i in idx:
        a, b, c = (g.verts[k] for k in g.tris[i])
        n = g.areas[i] / (step * step)
        k = min(40, max(1, int(math.ceil(math.sqrt(2.0 * n)))))
        ab, ac = b - a, c - a
        for ii in range(k):
            for jj in range(k - ii):
                out.append((a + ab * ((ii + 1 / 3) / k) + ac * ((jj + 1 / 3) / k), i))
        for p, q in ((a, b), (b, c), (c, a)):
            m = max(1, min(200, int((q - p).length / step)))
            for t in range(m + 1):
                out.append((p.lerp(q, t / m), i))
    if len(out) > 4 * max_n:
        stride = len(out) / (4 * max_n)
        out = [out[int(k * stride)] for k in range(4 * max_n)]
    return out


def _tri_box_filter(g: Geom, lo, hi):
    def f(i):
        vs = [g.verts[k] for k in g.tris[i]]
        return all(min(v[a] for v in vs) <= hi[a] and max(v[a] for v in vs) >= lo[a] for a in range(3))
    return f


def default_step(*geoms):
    m = min(min(g.size) if min(g.size) > 1e-6 else max(g.size) for g in geoms)
    return max(0.002, min(0.05, m / 4.0))


_DIRS = (Vector((0.5773, 0.5774, 0.5776)).normalized(),
         Vector((-0.3112, 0.8291, -0.4645)).normalized(),
         Vector((0.7071, -0.2236, -0.6708)).normalized())


def inside(g: Geom, p) -> object:
    """射線奇偶判斷點是否在封閉網格內。非封閉網格回 None（不可判定）。"""
    if not g.manifold:
        return None
    if any(p[i] < g.bmin[i] - 1e-9 or p[i] > g.bmax[i] + 1e-9 for i in range(3)):
        return False
    maxd = (g.bmax - g.bmin).length * 2 + 1.0
    votes = 0
    for d in _DIRS:
        o = p.copy()
        n = 0
        for _ in range(256):
            loc, _nor, _i, _dist = g.bvh.ray_cast(o, d, maxd)
            if loc is None:
                break
            n += 1
            o = loc + d * 1e-6
        votes += n % 2
    return votes >= 2


def overlap_pairs(ga: Geom, gb: Geom):
    if ga.bvh is None or gb.bvh is None:
        return [], 0
    pairs = ga.bvh.overlap(gb.bvh)
    cop = 0
    for i, j in pairs:
        na, nb = ga.normals[i], gb.normals[j]
        if abs(na.dot(nb)) > 0.9999 and abs((ga.verts[ga.tris[i][0]] - gb.verts[gb.tris[j][0]]).dot(nb)) < 1e-5:
            cop += 1
    return pairs, cop


def penetration(ga: Geom, gb: Geom, step=None, keep_points=200) -> dict:
    """穿透量測。depth = 一方表面取樣點落在另一方封閉體內時，到其表面的最大距離（解析度 ≈ step）。

    BVH overlap 只證明三角形相交；深度需要封閉網格做內外判斷，兩邊都不封閉時 depth=None（UNKNOWN）。
    """
    step = step or default_step(ga, gb)
    pairs, cop = overlap_pairs(ga, gb)
    res = {"intersects": bool(pairs), "tri_pairs": len(pairs), "coplanar_pairs": cop,
           "depth": 0.0, "inside_points": [], "method": "bvh_overlap", "resolution": step}
    box = aabb_overlap(ga, gb, margin=step)
    contained = False
    if box is None:
        return res
    known = False
    depth = 0.0
    pts_inside = []
    for src, dst in ((ga, gb), (gb, ga)):
        if not dst.manifold:
            continue
        known = True
        lo, hi = box
        for p, _ in samples(src, step, tri_filter=_tri_box_filter(src, lo, hi)):
            if any(p[i] < lo[i] or p[i] > hi[i] for i in range(3)):
                continue
            if inside(dst, p):
                d = dst.bvh.find_nearest(p)[3]
                if d > 1e-6:
                    pts_inside.append((d, p, src.name))
                depth = max(depth, d)
    if not pairs and pts_inside:
        contained = True  # 一方完全包在另一方裡（三角形不相交）
    if not pairs and not contained:
        return res
    res["contained"] = contained
    res["intersects"] = True
    if not known:
        res["depth"] = None
        res["method"] += "+depth_unknown(non_manifold)"
        return res
    res["method"] += "+ray_parity_inside+find_nearest"
    pts_inside.sort(key=lambda t: -t[0])
    res["depth"] = depth
    res["inside_points"] = [(list(p), d, s) for d, p, s in pts_inside[:keep_points]]
    res["inside_count"] = len(pts_inside)
    return res


def min_distance(ga: Geom, gb: Geom, step=None, search=1.0) -> dict:
    """兩表面最小距離（雙向取樣 → find_nearest）。相交時為 0。"""
    step = step or default_step(ga, gb)
    pairs, _ = overlap_pairs(ga, gb)
    if pairs:
        return {"distance": 0.0, "intersects": True}
    best = (math.inf, None, None, None, None)
    for src, dst in ((ga, gb), (gb, ga)):
        lo = dst.bmin - Vector((search,) * 3)
        hi = dst.bmax + Vector((search,) * 3)
        for p, ti in samples(src, step, tri_filter=_tri_box_filter(src, lo, hi)):
            loc, nor, _j, d = dst.bvh.find_nearest(p, search)
            if loc is not None and d < best[0]:
                best = (d, p, loc, src.normals[ti], nor) if src is ga else (d, loc, p, nor, src.normals[ti])
    d, pa, pb, na, nb = best
    out = {"distance": d, "intersects": False, "resolution": step}
    if pa is not None:
        out.update({"point_a": list(pa), "point_b": list(pb),
                    "normal_angle_deg": math.degrees(na.angle(-nb)) if na.length and nb.length else None})
    return out


def gap_profile(ga: Geom, gb: Geom, band, step=None) -> dict:
    """A 表面在 B 附近（band 內）的間隙分布：用於接縫／齊平檢查。"""
    step = step or default_step(ga, gb)
    lo, hi = gb.bmin - Vector((band,) * 3), gb.bmax + Vector((band,) * 3)
    ds, angs = [], []
    for p, ti in samples(ga, step, tri_filter=_tri_box_filter(ga, lo, hi)):
        loc, nor, _j, d = gb.bvh.find_nearest(p, band)
        if loc is None:
            continue
        ds.append(d)
        if ga.normals[ti].length and nor.length:
            angs.append(math.degrees(ga.normals[ti].angle(-nor)))
    if not ds:
        return {"n": 0}
    ds.sort()
    return {"n": len(ds), "min": ds[0], "median": ds[len(ds) // 2], "p95": ds[int(len(ds) * 0.95) - 1 if len(ds) > 1 else 0],
            "max": ds[-1], "angles": angs}


def support_profile(ga: Geom, gb: Geom, up=UP, tol=0.003, embed_max=0.01, search=None, step=None) -> dict:
    """A 由 B 支撐：A 朝下面往下打到 B、B 朝上面往上打到 A，各自統計 gap。gap>0 懸空、<0 埋入。"""
    up = Vector(up).normalized()
    step = step or default_step(ga, gb)
    search = search if search is not None else max(0.5, 0.5 * ga.size.dot(Vector([abs(x) for x in up])))
    sides = {}
    for name, src, dst, dirv in (("a_bottom", ga, gb, -up), ("b_top", gb, ga, up)):
        tris = lambda i, s=src, d=dirv: s.normals[i].dot(d) > 0.5  # noqa: E731
        pts = samples(src, step, max_n=3000, tri_filter=tris)
        gaps = []
        deep = 0
        for p, _ in pts:
            # 1) 反向打：若先碰到 dst「朝向接觸方向」的面（從內往外穿出）→ p 在 dst 內，埋入深度 = 距離
            loc, nor, _i, dist = dst.bvh.ray_cast(p, -dirv, search)
            if loc is not None and nor.dot(-dirv) > 0:
                gaps.append(-dist)
                continue
            # 2) 順向打：碰到朝向 p 的面 = 懸空間隙；碰到背向的面 = p 在 dst 深處（超過 search）
            loc, nor, _i, dist = dst.bvh.ray_cast(p, dirv, search)
            if loc is None:
                continue
            if nor.dot(-dirv) > 0:
                gaps.append(dist)
            else:
                deep += 1
                gaps.append(-search)
        ok = [g for g in gaps if -embed_max <= g <= tol]
        gs = sorted(gaps)
        sides[name] = {"samples": len(pts), "hits": len(gaps), "deep_inside": deep,
                       "coverage": (len(ok) / len(gaps)) if gaps else 0.0,
                       "min_gap": gs[0] if gs else None, "median_gap": gs[len(gs) // 2] if gs else None,
                       "max_gap": gs[-1] if gs else None}
    return sides


def support_lowest(ga: Geom, gb: Geom, up=UP, band=None, search=0.5) -> dict:
    """非封閉網格用：A 最低帶（band 內）的頂點，上下各打一條射線到 B，取較近者。
    gap>0 = B 在下方（懸空），gap<0 = B 表面在上方（埋入）。不依賴面法線方向。"""
    up = Vector(up).normalized()
    hs = [v.dot(up) for v in ga.verts]
    lo = min(hs)
    band = band if band is not None else max(0.05, 0.02 * (max(hs) - lo))
    gaps = []
    ambiguous = 0
    pts = [v for v, h in zip(ga.verts, hs) if h <= lo + band]
    for v in pts:
        dn = gb.bvh.ray_cast(v, -up, search)
        upr = gb.bvh.ray_cast(v, up, search)
        if gb.manifold and upr[0] is not None and inside(gb, v):
            gaps.append(-upr[3])  # B 封閉：奇偶判斷在內 → 埋入
            continue
        if gb.manifold:
            if dn[0] is not None:
                gaps.append(dn[3])
            continue
        cands = []
        if dn[0] is not None:
            cands.append(dn[3])
        if upr[0] is not None:
            cands.append(-upr[3])
        if len(cands) == 2 and abs(abs(cands[0]) - abs(cands[1])) < 0.2 * max(abs(cands[0]), abs(cands[1])) \
                and min(abs(c) for c in cands) > 1e-4:
            ambiguous += 1  # 兩邊都不封閉、上下距離相近：分不出埋入或懸空
            continue
        if cands:
            gaps.append(min(cands, key=abs))
    gs = sorted(gaps)
    return {"band": band, "samples": len(pts), "hits": len(gaps), "ambiguous": ambiguous, "gaps_sorted": gs,
            "min_gap": gs[0] if gs else None, "median_gap": gs[len(gs) // 2] if gs else None,
            "max_gap": gs[-1] if gs else None}


# ───────────────────────── Phase 3：約束評估 ─────────────────────────

def _row(c, status, building_id, objs, expected, actual, deviation, tol, method, suggestion="", evidence=None, fix=None):
    pri = c.get("priority", "hard")
    if status == "FAIL" and pri == "soft":
        status = "WARN"
    return {
        "rule_id": c.get("id", c.get("type")), "type": c.get("type"), "building_id": building_id,
        "object_ids": objs, "status": status, "priority": pri,
        "severity": {"hard": "high", "soft": "low"}.get(pri, pri),
        "expected": expected, "actual": actual, "deviation": deviation, "tolerance": tol,
        "method": method, "suggestion": suggestion, "evidence": evidence or {}, "fix": fix,
    }


def _tol(c, *geoms):
    t = c.get("tol", DEFAULT_TOL.get(c["type"], 0.002))
    if "tol_rel" in c and geoms:
        t = max(t, c["tol_rel"] * min(min(g.size) for g in geoms))
    return t


def _axis_of(g: Geom, obj, spec, frame: Frame):
    """軸向：'local:Z'（物件矩陣欄）、'frame:up'（建築座標）、'obb:long|mid|short'（PCA）。"""
    spec = spec or "obb:long"
    kind, _, val = spec.partition(":")
    if kind == "local":
        if obj is None:
            raise ValueError("local 軸需要真實物件")
        return (obj.matrix_world.to_3x3() @ _parse_axis(val)).normalized()
    if kind == "frame":
        return frame.dir(val)
    if kind == "world":
        return _parse_axis(val)
    o = obb_pca(g)
    order = sorted(range(3), key=lambda i: -o["extents"][i])
    pick = {"long": 0, "mid": 1, "short": 2}[val or "long"]
    return Vector(o["axes"][order[pick]])


def _c_contact(c, A, B, ctx):
    tol = _tol(c, A, B)
    allow = c.get("allow_depth", tol)
    md = min_distance(A, B, ctx["step"], search=max(1.0, 10 * tol))
    if md["intersects"]:
        pen = penetration(A, B, ctx["step"])
        if pen["depth"] is None:
            return _row(c, "UNKNOWN", ctx["bid"], [A.name, B.name], f"depth<={allow}", None, None, tol,
                        pen["method"], "網格不封閉，無法量穿透深度；請檢視近照或補封閉碰撞體", {"penetration": _slim(pen)})
        ok = pen["depth"] <= allow
        return _row(c, "PASS" if ok else "FAIL", ctx["bid"], [A.name, B.name], f"gap<={tol}, depth<={allow}",
                    {"gap": 0.0, "depth": pen["depth"]}, max(0.0, pen["depth"] - allow), tol, pen["method"],
                    "" if ok else f"穿插 {pen['depth']*1000:.1f} mm，超出允許 {allow*1000:.1f} mm",
                    {"penetration": _slim(pen)})
    d = md["distance"]
    ok = d <= tol
    fix = None
    if not ok and md.get("point_a"):
        fix = {"object": A.name, "translate": list(Vector(md["point_b"]) - Vector(md["point_a"]))}
    return _row(c, "PASS" if ok else "FAIL", ctx["bid"], [A.name, B.name], f"gap<={tol}", {"gap": d},
                max(0.0, d - tol), tol, "bidirectional_samples+bvh_find_nearest",
                "" if ok else f"間隙 {d*1000:.1f} mm；最小修正＝沿最近點把 {A.name} 移 {d*1000:.1f} mm", md, fix)


def _c_no_intersection(c, A, B, ctx):
    tol = _tol(c, A, B)
    pen = penetration(A, B, ctx["step"])
    if not pen["intersects"]:
        return _row(c, "PASS", ctx["bid"], [A.name, B.name], "no penetration", {"depth": 0.0}, 0.0, tol, pen["method"])
    if pen["depth"] is None:
        if pen["coplanar_pairs"] == pen["tri_pairs"]:
            return _row(c, "PASS", ctx["bid"], [A.name, B.name], "no penetration", {"coplanar_only": True}, 0.0, tol,
                        pen["method"] + "+coplanar")
        return _row(c, "UNKNOWN", ctx["bid"], [A.name, B.name], "no penetration", None, None, tol, pen["method"],
                    "網格不封閉，三角形相交但無法判定是接觸還是穿透", {"penetration": _slim(pen)})
    ok = pen["depth"] <= tol
    return _row(c, "PASS" if ok else "FAIL", ctx["bid"], [A.name, B.name], f"depth<={tol}", {"depth": pen["depth"]},
                max(0.0, pen["depth"] - tol), tol, pen["method"],
                "" if ok else f"非預期穿插 {pen['depth']*1000:.1f} mm", {"penetration": _slim(pen)})


def _region_box(c, frame):
    r = c.get("region")
    if not r:
        return None
    if isinstance(r, str):
        ob = bpy.data.objects.get(r)
        if ob is None:
            raise KeyError(f"region 物件不存在：{r}")
        if ob.type == "MESH":
            g = geom_from_object(ob)
            return g.bmin, g.bmax
        s = ob.empty_display_size
        corners = [ob.matrix_world @ Vector((x * s, y * s, z * s)) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        return (Vector((min(p[i] for p in corners) for i in range(3))),
                Vector((max(p[i] for p in corners) for i in range(3))))
    return Vector(r["min"]), Vector(r["max"])


def _c_overlap_allowed(c, A, B, ctx):
    tol = _tol(c, A, B)
    max_depth = c.get("max_depth")
    pen = penetration(A, B, ctx["step"], keep_points=100000)
    if not pen["intersects"]:
        md = min_distance(A, B, ctx["step"], search=max(1.0, 10 * tol))
        ok = (md["distance"] <= tol) or not c.get("must_touch", True)
        return _row(c, "PASS" if ok else "FAIL", ctx["bid"], [A.name, B.name], f"overlap or gap<={tol}",
                    {"gap": md["distance"]}, max(0.0, md["distance"] - tol), tol, "bvh_find_nearest",
                    "" if ok else f"應搭接／接觸，實際分離 {md['distance']*1000:.1f} mm", md)
    if pen["depth"] is None:
        return _row(c, "UNKNOWN", ctx["bid"], [A.name, B.name], "allowed overlap", None, None, tol, pen["method"],
                    "網格不封閉，搭接深度與範圍無法量測", {"penetration": _slim(pen)})
    issues = []
    if max_depth is not None and pen["depth"] > max_depth + tol:
        issues.append(f"搭接深度 {pen['depth']*1000:.1f} mm > 上限 {max_depth*1000:.1f} mm")
    box = _region_box(c, ctx["frame"])
    outside = 0
    if box is not None:
        lo, hi = box[0] - Vector((tol,) * 3), box[1] + Vector((tol,) * 3)
        for p, d, _s in pen["inside_points"]:
            if d > tol and any(p[i] < lo[i] or p[i] > hi[i] for i in range(3)):
                outside += 1
        if outside:
            issues.append(f"{outside} 個穿插取樣點落在允許區域外（region={c.get('region')}）")
    status = "FAIL" if issues else "PASS"
    return _row(c, status, ctx["bid"], [A.name, B.name],
                {"max_depth": max_depth, "region": c.get("region")},
                {"depth": pen["depth"], "outside_points": outside, "inside_points": pen.get("inside_count", 0)},
                None, tol, pen["method"] + ("+region" if box else ""), "；".join(issues), {"penetration": _slim(pen)})


def _c_clearance(c, A, B, ctx):
    need = c.get("min", _tol(c, A, B))
    mx = c.get("max")
    md = min_distance(A, B, ctx["step"], search=max(1.0, (mx or need) * 2 + 0.1))
    d = md["distance"]
    ok = (not md["intersects"]) and d >= need and (mx is None or d <= mx)
    msg = "" if ok else ("互相穿插" if md["intersects"] else (f"淨距 {d*1000:.1f} mm < 需求 {need*1000:.1f} mm" if d < need
                                                       else f"淨距 {d*1000:.1f} mm > 上限 {mx*1000:.1f} mm"))
    return _row(c, "PASS" if ok else "FAIL", ctx["bid"], [A.name, B.name], {"min": need, "max": mx}, {"clearance": d},
                0.0 if ok else (need - d if d < need else d - (mx or d)), need, "bvh_find_nearest", msg, md)


def _c_support(c, A, B, ctx):
    tol = _tol(c, A, B)
    embed = c.get("embed_max", 0.01)
    need = c.get("min_contact", 0.7)
    up = ctx["frame"].dir(c["up"]) if "up" in c else ctx["frame"].up
    if not (A.manifold and B.manifold) or c.get("method") == "lowest":
        lp = support_lowest(A, B, up, c.get("contact_band"), c.get("search", 0.5))
        gs = lp.pop("gaps_sorted")
        if lp["ambiguous"] > 0.2 * max(1, lp["samples"]):
            return _row(c, "UNKNOWN", ctx["bid"], [A.name, B.name], f"contact>={need}", None, None, tol,
                        "lowest_vertex_vertical_nearest", f"{lp['ambiguous']}/{lp['samples']} 個最低點上下距離相近且兩者都不封閉，"
                        "分不出埋入還是懸空；請補封閉碰撞體或看近照", lp)
        if not gs:
            return _row(c, "FAIL", ctx["bid"], [A.name, B.name], f"contact>={need}", {"coverage": 0.0}, need, tol,
                        "lowest_vertex_vertical_nearest", f"{A.name} 最低帶上下 search 內找不到 {B.name}（NO_SUPPORT_BELOW）", lp)
        cov = sum(1 for g in gs if -embed <= g <= tol) / len(gs)
        med = lp["median_gap"]
        ok = cov >= need
        reason, fix = "", None
        if not ok:
            if med > tol:
                reason, fix = f"懸空：最低帶中位間隙 {med*1000:.1f} mm（FLOATING）", {"object": A.name, "translate": list(-up * med)}
            elif med < -embed:
                reason, fix = (f"埋入過深：中位 {-med*1000:.1f} mm > {embed*1000:.1f} mm（OVER_EMBEDDED）",
                               {"object": A.name, "translate": list(-up * med)})
            else:
                reason = f"最低帶接觸率 {cov:.0%} < {need:.0%}（INSUFFICIENT_SUPPORT）"
        return _row(c, "PASS" if ok else "FAIL", ctx["bid"], [A.name, B.name],
                    f"contact>={need:.0%}, gap in [-{embed},{tol}]", {"coverage": cov, "median_gap": med},
                    max(0.0, need - cov), tol, "lowest_vertex_vertical_nearest(non_manifold: 不依賴面法線)", reason,
                    dict(lp, manifold={"a": A.manifold, "b": B.manifold}), fix)
    sp = support_profile(A, B, up, tol, embed, c.get("search"), ctx["step"])
    req = c.get("require", "either")
    cov = {"a": sp["a_bottom"]["coverage"], "b": sp["b_top"]["coverage"]}
    got = max(cov.values()) if req == "either" else cov[req]
    if sp["a_bottom"]["hits"] == 0 and sp["b_top"]["hits"] == 0:
        return _row(c, "FAIL", ctx["bid"], [A.name, B.name], f"contact>={need}", {"coverage": 0.0}, need, tol,
                    "ray_cast_support", f"{A.name} 下方 search 範圍內找不到 {B.name}（NO_SUPPORT_BELOW）", sp)
    ok = got >= need
    side = sp["a_bottom"] if sp["a_bottom"]["hits"] else sp["b_top"]
    med = side["median_gap"]
    reason, fix = "", None
    if not ok:
        if med is not None and med > tol:
            reason = f"懸空：中位間隙 {med*1000:.1f} mm（FLOATING）"
            fix = {"object": A.name, "translate": list(-up * med)}
        elif med is not None and med < -embed:
            reason = f"埋入過深：中位 {-med*1000:.1f} mm > {embed*1000:.1f} mm（OVER_EMBEDDED）"
            fix = {"object": A.name, "translate": list(-up * med)}
        else:
            reason = f"支撐接觸率 {got:.0%} < {need:.0%}（INSUFFICIENT_SUPPORT）"
    return _row(c, "PASS" if ok else "FAIL", ctx["bid"], [A.name, B.name], f"contact>={need:.0%}, gap in [-{embed},{tol}]",
                {"coverage": got, "median_gap": med}, max(0.0, need - got), tol, "ray_cast_support(both_sides)", reason, sp, fix)


def _c_snap(c, A, B, ctx):
    tol = _tol(c, A, B)
    if "anchor_a" in c and "anchor_b" in c:
        oa, ob = bpy.data.objects.get(c["anchor_a"]), bpy.data.objects.get(c["anchor_b"])
        if oa is None or ob is None:
            return _row(c, "UNKNOWN", ctx["bid"], [A.name, B.name], "anchors", None, None, tol, "anchor",
                        f"錨點物件不存在：{c['anchor_a']} / {c['anchor_b']}")
        pa, pb = oa.matrix_world.translation, ob.matrix_world.translation
        d = (pa - pb).length
        ok = d <= tol
        return _row(c, "PASS" if ok else "FAIL", ctx["bid"], [A.name, B.name], f"anchor distance<={tol}",
                    {"anchor_distance": d, "delta_frame": list(ctx["frame"].to_local(pb) - ctx["frame"].to_local(pa))},
                    max(0.0, d - tol), tol, "anchor_world_distance",
                    "" if ok else f"錨點差 {d*1000:.1f} mm", {"a": list(pa), "b": list(pb)},
                    None if ok else {"object": A.name, "translate": list(pb - pa)})
    band = max(5 * tol, 0.01)
    gp = gap_profile(A, B, band, ctx["step"])
    ang_tol = c.get("angle_tol", 2.0)
    if gp["n"] == 0:
        return _row(c, "FAIL", ctx["bid"], [A.name, B.name], f"flush within {tol}", None, None, tol, "gap_profile",
                    f"{A.name} 與 {B.name} 在 {band*1000:.0f} mm 內沒有對接面", gp)
    flush = [a for a in gp["angles"] if a <= ang_tol]
    ok = gp["median"] <= tol and len(flush) >= 0.5 * len(gp["angles"])
    return _row(c, "PASS" if ok else "FAIL", ctx["bid"], [A.name, B.name], f"seam median<={tol}, faces antiparallel<={ang_tol}°",
                {"seam_median": gp["median"], "seam_max": gp["max"], "flush_ratio": len(flush) / max(1, len(gp["angles"]))},
                max(0.0, gp["median"] - tol), tol, "gap_profile(find_nearest)",
                "" if ok else f"接縫中位 {gp['median']*1000:.1f} mm", {k: v for k, v in gp.items() if k != "angles"})


def _mirror(p, point, normal):
    return p - normal * (2.0 * (p - point).dot(normal))


def _c_symmetric(c, A, B, ctx):
    tol = _tol(c, A, B)
    fr = ctx["frame"]
    if "plane" in c:
        pp = c["plane"]["point"]
        if isinstance(pp, str):  # 構件名 → 以其世界 AABB 中心為鏡面點（自身對稱）
            gp_ = ctx["geoms"][pp]
            pt = (gp_.bmin + gp_.bmax) * 0.5
        else:
            pt = Vector(pp)
        nm = (fr.dir(c["plane"]["normal"]) if isinstance(c["plane"]["normal"], str)
              else Vector(c["plane"]["normal"])).normalized()
    else:
        pt, nm = fr.origin, fr.right
    ds = []
    for p, _ in samples(A, ctx["step"], max_n=3000):
        loc, _n, _i, d = B.bvh.find_nearest(_mirror(p, pt, nm), 10.0)
        ds.append(d if loc is not None else math.inf)
    ds.sort()
    cent_dev = (_mirror(A.centroid(), pt, nm) - B.centroid()).length
    p95 = ds[int(len(ds) * 0.95) - 1] if ds else math.inf
    ok = p95 <= tol and cent_dev <= tol
    return _row(c, "PASS" if ok else "FAIL", ctx["bid"], [A.name, B.name], f"mirror deviation p95<={tol}",
                {"p95": p95, "max": ds[-1] if ds else None, "centroid_dev": cent_dev}, max(0.0, p95 - tol), tol,
                "mirror_samples+find_nearest", "" if ok else f"左右不對稱：重心差 {cent_dev*1000:.1f} mm、p95 {p95*1000:.1f} mm",
                {"plane_point": list(pt), "plane_normal": list(nm)},
                None if ok else {"object": B.name, "translate": list(_mirror(A.centroid(), pt, nm) - B.centroid())})


def _c_angle(c, A, B, ctx, mode):
    tol = _tol(c, A, B)
    aa = _axis_of(A, ctx["objs"].get(A.name), c.get("axis_a", c.get("axis")), ctx["frame"])
    ab = _axis_of(B, ctx["objs"].get(B.name), c.get("axis_b", c.get("axis")), ctx["frame"])
    ang = math.degrees(math.acos(max(-1.0, min(1.0, abs(aa.dot(ab))))))  # 軸無方向性：0..90
    dev = ang if mode == "PARALLEL" else abs(90.0 - ang)
    ok = dev <= tol
    return _row(c, "PASS" if ok else "FAIL", ctx["bid"], [A.name, B.name], f"{mode} within {tol}°", {"angle_deg": ang},
                dev, tol, "axis_vectors(acos|dot|)", "" if ok else f"夾角 {ang:.2f}°", {"axis_a": list(aa), "axis_b": list(ab)})


def _c_coaxial(c, A, B, ctx):
    tol = _tol(c, A, B)
    ang_tol = c.get("angle_tol", 0.5)
    fr = ctx["frame"]
    aa = _axis_of(A, ctx["objs"].get(A.name), c.get("axis_a", c.get("axis", "frame:up")), fr)
    ab = _axis_of(B, ctx["objs"].get(B.name), c.get("axis_b", c.get("axis", "frame:up")), fr)
    ang = math.degrees(math.acos(max(-1.0, min(1.0, abs(aa.dot(ab))))))
    ca, cb = ((A.bmin + A.bmax) * 0.5, (B.bmin + B.bmax) * 0.5) if c.get("center", "aabb") == "aabb" else (A.centroid(), B.centroid())
    d = cb - ca
    lateral = d - aa * d.dot(aa)
    off = lateral.length
    ok = off <= tol and ang <= ang_tol
    lf = fr.to_local(fr.origin + lateral)
    return _row(c, "PASS" if ok else "FAIL", ctx["bid"], [A.name, B.name], f"axis offset<={tol}, angle<={ang_tol}°",
                {"offset": off, "angle_deg": ang, "offset_frame_rfu": list(lf)}, max(0.0, off - tol), tol,
                f"{c.get('center', 'aabb')}_center_to_axis_line",
                "" if ok else f"中心線偏 {off*1000:.1f} mm（建築座標 右{lf.x*1000:+.1f}／前{lf.y*1000:+.1f} mm）", {},
                None if ok else {"object": B.name, "translate": list(-lateral)})


def _c_continuous(c, geoms, ctx):
    tol = _tol(c, *geoms)
    up = ctx["frame"].dir(c.get("up", "up"))
    gap_tol = c.get("gap_tol", DEFAULT_TOL["CONTACT"])
    tops = [max(v.dot(up) for v in g.verts) for g in geoms]
    rises = [tops[i + 1] - tops[i] for i in range(len(tops) - 1)]
    mean = sum(rises) / len(rises)
    spread = max(abs(r - mean) for r in rises)
    gaps = [min_distance(geoms[i], geoms[i + 1], ctx["step"])["distance"] for i in range(len(geoms) - 1)]
    issues = []
    if spread > tol:
        k = max(range(len(rises)), key=lambda i: abs(rises[i] - mean))
        issues.append(f"級高不連續：第 {k+1}→{k+2} 階 {rises[k]*1000:.0f} mm，平均 {mean*1000:.0f} mm")
    if "rise_max" in c and max(rises) > c["rise_max"]:
        issues.append(f"最大級高 {max(rises)*1000:.0f} mm > {c['rise_max']*1000:.0f} mm")
    bad = [i for i, g in enumerate(gaps) if g > gap_tol]
    if bad:
        issues.append(f"相鄰構件分離：{[(geoms[i].name, geoms[i+1].name, round(gaps[i]*1000, 1)) for i in bad]} mm")
    return _row(c, "FAIL" if issues else "PASS", ctx["bid"], [g.name for g in geoms],
                f"rise spread<={tol}, seam gap<={gap_tol}", {"rises": rises, "spread": spread, "gaps": gaps},
                spread, tol, "top_height_sequence+bvh_find_nearest", "；".join(issues))


def _c_even_spacing(c, geoms, ctx):
    tol = _tol(c, *geoms)
    ax = ctx["frame"].dir(c.get("axis", "right"))
    pos = sorted(((g.bmin + g.bmax) * 0.5).dot(ax) for g in geoms)
    sp = [pos[i + 1] - pos[i] for i in range(len(pos) - 1)]
    mean = sum(sp) / len(sp)
    dev = max(abs(s - mean) for s in sp) / mean if mean > 1e-9 else math.inf
    ok = dev <= tol
    c2 = dict(c)
    c2.setdefault("priority", "soft")
    return _row(c2, "PASS" if ok else "FAIL", ctx["bid"], [g.name for g in geoms], f"spacing deviation<={tol:.0%}",
                {"spacings": sp, "rel_dev": dev}, dev, tol, "center_projection",
                "" if ok else f"間距不均：{[round(s, 3) for s in sp]} m")


PAIR_FUNCS = {
    "CONTACT": _c_contact, "NO_INTERSECTION": _c_no_intersection, "OVERLAP_ALLOWED": _c_overlap_allowed,
    "CLEARANCE_REQUIRED": _c_clearance, "SUPPORT": _c_support, "SNAP": _c_snap, "SYMMETRIC": _c_symmetric,
    "PARALLEL": lambda c, A, B, x: _c_angle(c, A, B, x, "PARALLEL"),
    "PERPENDICULAR": lambda c, A, B, x: _c_angle(c, A, B, x, "PERPENDICULAR"),
    "COAXIAL": _c_coaxial,
}
LIST_FUNCS = {"CONTINUOUS": _c_continuous, "EVEN_SPACING": _c_even_spacing}


def _slim(pen):
    return {k: v for k, v in pen.items() if k != "inside_points"} | {"inside_sample": pen.get("inside_points", [])[:3]}


# ───────────────────────── 快取 ─────────────────────────

class Cache:
    """約束結果快取：鍵 = 工具版本 + 約束 JSON + 建築座標 + 所有相關構件的世界網格雜湊。

    任何頂點、修改器、Transform、Parent 變動都會改變世界網格雜湊 → 自動失效；不會用到過期 PASS。
    """

    def __init__(self, path):
        self.path = path
        self.data = {}
        if path and os.path.exists(path):
            try:
                with open(path, encoding="utf-8") as f:
                    d = json.load(f)
                if d.get("version") == VERSION:
                    self.data = d.get("entries", {})
            except (OSError, ValueError):
                self.data = {}
        self.hits = self.misses = 0

    @staticmethod
    def key(c, geoms, frame):
        h = hashlib.sha1(VERSION.encode())
        h.update(json.dumps(c, sort_keys=True, ensure_ascii=False).encode())
        h.update(json.dumps(frame.as_dict(), sort_keys=True).encode())
        for g in geoms:
            h.update(g.key.encode())
        return h.hexdigest()

    def get(self, k):
        r = self.data.get(k)
        if r is None:
            self.misses += 1
        else:
            self.hits += 1
        return r

    def put(self, k, r):
        self.data[k] = r

    def save(self):
        if self.path:
            os.makedirs(os.path.dirname(os.path.abspath(self.path)), exist_ok=True)
            with open(self.path, "w", encoding="utf-8") as f:
                json.dump({"version": VERSION, "entries": self.data}, f)


# ───────────────────────── 主流程 ─────────────────────────

def _resolve_components(spec):
    comps = spec.get("components") or {}
    objs, geoms, missing = {}, {}, []
    dg = bpy.context.evaluated_depsgraph_get()
    names = set()
    for c in spec.get("constraints", []):
        for k in ("a", "b"):
            if k in c:
                names.add(c[k])
        names.update(c.get("components", []))
    names.update(comps.keys())
    for cid in sorted(names):
        on = comps.get(cid, {}).get("object", cid) if isinstance(comps.get(cid), dict) else cid
        ob = bpy.data.objects.get(on)
        if ob is None or ob.type != "MESH":
            missing.append(cid)
            continue
        g = geom_from_object(ob, dg)
        g.name = cid
        objs[cid] = ob
        geoms[cid] = g
    return objs, geoms, missing


def evaluate(spec, cache_path=None, undeclared="warn", detached=True) -> dict:
    """依連接表／約束 spec 驗證。spec 格式見 docs/arch_spatial/README.md。"""
    t0 = time.time()
    bid = spec.get("building_id", "?")
    frame = frame_from_spec(spec.get("frame"))
    objs, geoms, missing = _resolve_components(spec)
    cache = Cache(cache_path)
    ctx = {"bid": bid, "frame": frame, "objs": objs, "geoms": geoms, "step": spec.get("sample_step")}
    rows = []
    for c in spec.get("constraints", []):
        t = c.get("type")
        if t not in PAIR_FUNCS and t not in LIST_FUNCS:
            rows.append(_row(c, "UNKNOWN", bid, [], None, None, None, None, "-", f"未知約束類型 {t}"))
            continue
        ids = c.get("components") if t in LIST_FUNCS else [c.get("a"), c.get("b")]
        miss = [i for i in ids if i not in geoms]
        if miss:
            rows.append(_row(c, "UNKNOWN", bid, ids, None, None, None, None, "-", f"構件不存在或不是網格：{miss}"))
            continue
        gs = [geoms[i] for i in ids]
        k = Cache.key(c, gs, frame)
        r = cache.get(k)
        if r is not None:
            r = dict(r, cached=True)
        else:
            r = (LIST_FUNCS[t](c, gs, ctx) if t in LIST_FUNCS else PAIR_FUNCS[t](c, gs[0], gs[1], ctx))
            r = json.loads(json.dumps(r, default=_jsonable))
            cache.put(k, r)
            r = dict(r, cached=False)
        rows.append(r)
    declared = {frozenset((c.get("a"), c.get("b"))) for c in spec.get("constraints", []) if "a" in c}
    if undeclared != "off" or detached:
        rows += _structure_scan(list(geoms.values()), bid, declared, undeclared, detached, spec.get("ground_z"), ctx["step"])
    cache.save()
    return _report(bid, rows, missing, time.time() - t0, cache, frame)


def _structure_scan(gs, bid, declared, undeclared, detached, ground_z, step):
    """未宣告穿插 + 懸空零件（接觸圖中與地面不連通的島）。AABB 只做候選，精確判定用 BVH。"""
    rows = []
    unknown_pairs = []
    tol = DEFAULT_TOL["CONTACT"]
    adj = {g.name: set() for g in gs}
    for i in range(len(gs)):
        for j in range(i + 1, len(gs)):
            A, B = gs[i], gs[j]
            if aabb_overlap(A, B, margin=tol) is None:
                continue
            md = min_distance(A, B, step, search=tol * 2)
            if md["distance"] <= tol:
                adj[A.name].add(B.name)
                adj[B.name].add(A.name)
            if md["intersects"] and undeclared != "off" and frozenset((A.name, B.name)) not in declared:
                pen = penetration(A, B, step)
                if pen["depth"] is None:
                    if pen["coplanar_pairs"] < pen["tri_pairs"]:
                        unknown_pairs.append([A.name, B.name])
                    continue
                if pen["depth"] > 0.005:
                    c = {"id": f"UNDECLARED:{A.name}|{B.name}", "type": "NO_INTERSECTION",
                         "priority": "hard" if undeclared == "fail" else "soft"}
                    rows.append(_row(c, "FAIL", bid, [A.name, B.name], "declared or no penetration", {"depth": pen["depth"]},
                                     pen["depth"], 0.005, pen["method"],
                                     "未宣告的穿插：若是榫接／搭接請在連接表宣告 OVERLAP_ALLOWED", {"penetration": _slim(pen)}))
    if unknown_pairs:  # 非封閉網格的相交：彙總成一列，不逐對洗版
        c = {"id": "UNDECLARED_UNMEASURABLE", "type": "NO_INTERSECTION", "priority": "soft"}
        rows.append(_row(c, "UNKNOWN", bid, sorted({n for p in unknown_pairs for n in p})[:50],
                         "measurable penetration", {"pairs": len(unknown_pairs)}, None, 0.005,
                         "bvh_overlap(non_manifold→depth_unknown)",
                         f"{len(unknown_pairs)} 對三角形相交，但兩邊都不是封閉網格，量不出是接觸還是穿透；"
                         "請補封閉碰撞體或改看近照", {"first_pairs": unknown_pairs[:20]}))
    if detached and gs:
        gz = ground_z if ground_z is not None else min(g.bmin.z for g in gs)
        seen, stack = set(), [g.name for g in gs if g.bmin.z <= gz + tol]
        seen.update(stack)
        while stack:
            n = stack.pop()
            for m in adj[n]:
                if m not in seen:
                    seen.add(m)
                    stack.append(m)
        floating = [g.name for g in gs if g.name not in seen]
        c = {"id": "DETACHED", "type": "SUPPORT", "priority": "hard"}
        rows.append(_row(c, "FAIL" if floating else "PASS", bid, floating, "all parts connected to ground",
                         {"floating_parts": floating, "parts": len(gs), "contact_edges": sum(len(v) for v in adj.values()) // 2},
                         len(floating), tol, "contact_graph(bvh_min_distance<=tol)+ground_flood",
                         f"{len(floating)} 個零件與地面不連通（懸空）" if floating else ""))
    return rows


def _jsonable(o):
    if isinstance(o, Vector):
        return list(o)
    if isinstance(o, float) and (math.isinf(o) or math.isnan(o)):
        return str(o)
    return str(o)


def _report(bid, rows, missing, secs, cache, frame):
    rows = json.loads(json.dumps(rows, default=_jsonable).replace("Infinity", '"inf"'))
    counts = {s: sum(1 for r in rows if r["status"] == s) for s in ("PASS", "WARN", "FAIL", "UNKNOWN")}
    return {"tool": VERSION, "building_id": bid, "summary": counts, "missing_components": missing,
            "seconds": round(secs, 3), "cache": {"hits": cache.hits, "misses": cache.misses},
            "frame": frame.as_dict(), "results": rows}


def scan(objects=None, building_id="scan", split=False, ground_z=None, undeclared="warn", step=None) -> dict:
    """無連接表模式：可見網格（或拆島）→ 懸空零件 + 未宣告穿插。"""
    t0 = time.time()
    dg = bpy.context.evaluated_depsgraph_get()
    objs = objects if objects is not None else [o for o in bpy.context.scene.objects if o.type == "MESH" and o.visible_get()]
    gs = []
    for o in objs:
        g = geom_from_object(o, dg)
        gs += split_islands(g) if split else [g]
    rows = _structure_scan(gs, building_id, set(), undeclared, True, ground_z, step)
    rep = _report(building_id, rows, [], time.time() - t0, Cache(None), Frame())
    rep["parts"] = len(gs)
    return rep


def summary_text(rep) -> str:
    s = rep["summary"]
    lines = [f"[ARCH] {rep['building_id']}  PASS {s['PASS']} / WARN {s['WARN']} / FAIL {s['FAIL']} / UNKNOWN {s['UNKNOWN']}"
             f"  ({rep['seconds']} s, cache {rep['cache']['hits']} hit)"]
    for r in rep["results"]:
        if r["status"] != "PASS":
            lines.append(f"  {r['status']:7} {r['rule_id']}: {r['suggestion'] or r['actual']}")
    return "\n".join(lines)
