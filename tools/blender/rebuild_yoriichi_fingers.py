"""重建緣一手指幾何（v2：自建環，不依賴 extrude 配對）。

v1 用 bmesh.ops.extrude_edge_only，新環頂點順序與原環不對應，接面錯亂，
邊界邊由 31 暴增到 374（破管）。v2 改為：
  1. 把掌上的邊界環依繞行順序排好
  2. 沿骨路徑自行生成等數量的新環頂點（用平行傳輸框架，避免扭轉）
  3. 手工 quad 接環，最後用 fan 封頂
全程不呼叫 extrude，面的拓撲由自己決定，必為封閉流形。
"""
import json
import math
from collections import defaultdict, deque

import bmesh
import bpy
import numpy as np
from mathutils import Vector

RIGGED = r"D:/神社/shrine/work/緣一_rigged.blend"
BODY = "身體2"
FINGERS = ("Thumb", "Index", "Middle", "Ring", "Pinky")
SPLIT_FOUR = 0.638
SPLIT_THUMB = 0.615
RINGS = 12                 # 每指截面環數（三關節 × 4）
# 指根→指尖半徑比例，取代原先的單一 taper 指數
RADIUS_CURVE = [1.00, 0.97, 0.93, 0.90, 0.88, 0.86,
                0.84, 0.81, 0.78, 0.73, 0.64, 0.45]
# 掌口形狀影響在前幾圈內衰減為 0，之後為純正圓
BLEND_RINGS = 3


def log(*a):
    print("BUILD", *a)


def finger_components(me, co, sg):
    edges = [(e.vertices[0], e.vertices[1]) for e in me.edges]

    def comps(idx, min_n):
        S = set(int(i) for i in idx)
        adj = defaultdict(list)
        for a, b in edges:
            if a in S and b in S:
                adj[a].append(b)
                adj[b].append(a)
        seen, out = set(), []
        for v in S:
            if v in seen:
                continue
            q, c = deque([v]), []
            seen.add(v)
            while q:
                x = q.popleft()
                c.append(x)
                for y in adj[x]:
                    if y not in seen:
                        seen.add(y)
                        q.append(y)
            if len(c) >= min_n:
                out.append(c)
        return sorted(out, key=len, reverse=True)

    four = comps(np.where(co[:, 0] * sg > SPLIT_FOUR)[0], 12)
    four = sorted(four, key=lambda c: co[c][:, 1].mean())
    out = {}
    for nm, c in zip(("Index", "Middle", "Ring", "Pinky"), four):
        out[nm] = set(c)
    for c in comps(np.where(co[:, 0] * sg > SPLIT_THUMB)[0], 12):
        P = co[c]
        if P[:, 2].mean() < 1.435 and P[:, 1].mean() < 0.035:
            out["Thumb"] = set(c)
            break
    return out


def ordered_boundary_loops(bm):
    """回傳依繞行順序排好的邊界環（list of list[BMVert]）。"""
    bedges = [e for e in bm.edges if len(e.link_faces) == 1]
    adj = defaultdict(list)
    for e in bedges:
        a, b = e.verts
        adj[a].append(b)
        adj[b].append(a)
    seen, loops = set(), []
    for start in list(adj):
        if start in seen or len(adj[start]) != 2:
            continue
        cyc = [start]
        seen.add(start)
        prev, cur = start, adj[start][0]
        ok = True
        while cur is not start:
            if cur in seen or len(adj[cur]) != 2:
                ok = False
                break
            seen.add(cur)
            cyc.append(cur)
            a, b = adj[cur]
            prev, cur = cur, (b if a is prev else a)
        if ok and len(cyc) >= 4:
            loops.append(cyc)
    return loops


def bone_path(arm, side, finger):
    pts = []
    for i in (1, 2, 3):
        b = arm.data.bones.get(f"{side}Hand{finger}{i}")
        if not b:
            return None
        if not pts:
            pts.append(np.array(b.head_local))
        pts.append(np.array(b.tail_local))
    return pts


def resample(path, n):
    """回傳 n 個等距點及各點的切線方向。"""
    P = np.array(path)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    total = cum[-1]
    pts, tans = [], []
    for i in range(1, n + 1):
        d = total * i / n
        j = int(np.clip(np.searchsorted(cum, d, side="right") - 1, 0, len(seg) - 1))
        t = (d - cum[j]) / max(seg[j], 1e-9)
        pts.append(P[j] + (P[j + 1] - P[j]) * t)
        tan = P[j + 1] - P[j]
        tans.append(tan / max(np.linalg.norm(tan), 1e-9))
    return pts, tans


def frame(normal, ref):
    """由法線與固定參考向量建立正交框架。

    不做逐段累積旋轉，因此不會沿骨軸引入自旋 —— v2 用 rotation_difference
    逐段傳輸，在 MCP 急轉處量到最大 80 度扭轉。
    """
    nv = normal / max(np.linalg.norm(normal), 1e-9)
    r = np.array(ref, dtype=float)
    if abs(float(nv @ r)) > 0.95:
        r = np.array([0.0, 0.0, 1.0])
        if abs(float(nv @ r)) > 0.95:
            r = np.array([0.0, 1.0, 0.0])
    u = r - nv * float(nv @ r)
    u = u / max(np.linalg.norm(u), 1e-9)
    return u, np.cross(nv, u)


def build_finger(bm, loop, path, uv_layer, ref=(0.0, 0.0, 1.0)):
    """每圈以骨方向為法線重建正圓截面，半徑沿指身漸縮。

    v2 直接沿用掌口邊界環形狀，該環是斜切橢圓（扁平度低到 0.22），使截面
    主軸沿指身亂跳；v3 只在前 BLEND_RINGS 圈保留掌口起伏做接合過渡。
    """
    n = len(loop)
    base = np.array([[v.co.x, v.co.y, v.co.z] for v in loop])
    center = base.mean(axis=0)
    radius = float(np.linalg.norm(base - center, axis=1).mean())

    pts, tans = resample([center] + list(path), RINGS)

    n0 = tans[0]
    u0, v0 = frame(n0, ref)
    rel = base - center
    ang0 = np.arctan2(rel @ v0, rel @ u0)
    rad0 = np.linalg.norm(rel - np.outer(rel @ n0, n0), axis=1)

    # 保持邊界環原繞行順序（重排會讓相鄰面接不上，v3 初版因此產生 42 條邊界邊）。
    # 僅確保環的繞向與 ang 遞增一致，使後續正圓的角度序不會反向。
    d_ang = np.diff(np.unwrap(ang0))
    if float(np.sum(d_ang)) < 0:
        loop_sorted = list(reversed(loop))
        ang_sorted = ang0[::-1].copy()
        rad_sorted = rad0[::-1].copy()
    else:
        loop_sorted = list(loop)
        ang_sorted = ang0.copy()
        rad_sorted = rad0.copy()

    uv_ref = {}
    for v in loop_sorted:
        for lp in v.link_loops:
            uv_ref[v] = Vector(lp[uv_layer].uv)
            break

    prev_ring = loop_sorted
    new_faces = []

    for k in range(RINGS):
        c, nvec = pts[k], tans[k]
        u, v = frame(nvec, ref)
        scale = RADIUS_CURVE[k] * radius
        w = max(0.0, 1.0 - (k + 1) / BLEND_RINGS)

        ring = []
        for i in range(n):
            a = ang_sorted[i]
            # 只混「半徑大小」，不混「截面形狀」。
            # 保留掌口的橢圓輪廓會讓指根截面扁平（實測 flat 0.24-0.64），
            # 使主軸在段間亂跳，量到 70-82 度假扭轉；純正圓則全段 0 度。
            r_ring = scale
            r_mouth = float(rad_sorted.mean()) * RADIUS_CURVE[k]
            r = r_ring * (1.0 - w) + r_mouth * w
            p = c + u * (math.cos(a) * r) + v * (math.sin(a) * r)
            ring.append(bm.verts.new(Vector(p)))
        bm.verts.ensure_lookup_table()

        for i in range(n):
            try:
                new_faces.append(bm.faces.new((
                    prev_ring[i], prev_ring[(i + 1) % n],
                    ring[(i + 1) % n], ring[i])))
            except ValueError:
                pass
        for i, vv in enumerate(ring):
            uv_ref[vv] = uv_ref.get(prev_ring[i], Vector((0.5, 0.5)))
        prev_ring = ring

    tip = bm.verts.new(Vector(pts[-1] + tans[-1] * radius * 0.35))
    bm.verts.ensure_lookup_table()
    uv_ref[tip] = uv_ref.get(prev_ring[0], Vector((0.5, 0.5)))
    for i in range(n):
        try:
            new_faces.append(bm.faces.new(
                (prev_ring[i], prev_ring[(i + 1) % n], tip)))
        except ValueError:
            pass

    bm.faces.ensure_lookup_table()
    for f in new_faces:
        for lp in f.loops:
            lp[uv_layer].uv = uv_ref.get(lp.vert, Vector((0.5, 0.5)))
    return len(new_faces)


def main():
    bpy.ops.wm.open_mainfile(filepath=RIGGED)
    arm = bpy.data.objects["Armature"]
    body = bpy.data.objects[BODY]
    me = body.data
    M = body.matrix_world
    co = np.array([[(M @ v.co).x, (M @ v.co).y, (M @ v.co).z] for v in me.vertices])

    to_del, plan = set(), {}
    for side, sg in (("Left", 1), ("Right", -1)):
        comps = finger_components(me, co, sg)
        plan[side] = {k: len(v) for k, v in comps.items()}
        for s in comps.values():
            to_del |= s
    log("old_finger_verts", json.dumps(plan))

    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    uv_layer = bm.loops.layers.uv.active

    before_bound = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in sorted(to_del)], context="VERTS")
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()

    loops = ordered_boundary_loops(bm)
    log("boundary_loops", sorted(len(l) for l in loops))

    targets = []
    for side in ("Left", "Right"):
        for f in FINGERS:
            p = bone_path(arm, side, f)
            if p:
                targets.append((side, f, p))

    used, built = set(), {}
    # 先配對距離最近的，避免小指被搶走
    pairs = []
    for si, (side, f, path) in enumerate(targets):
        for li, l in enumerate(loops):
            c = np.array([sum(v.co[k] for v in l) / len(l) for k in range(3)])
            pairs.append((float(np.linalg.norm(c - path[0])), si, li))
    pairs.sort()
    assign = {}
    for d, si, li in pairs:
        if si in assign or li in used or d > 0.06:
            continue
        assign[si] = li
        used.add(li)

    for si, li in sorted(assign.items()):
        side, f, path = targets[si]
        nf = build_finger(bm, loops[li], path[1:], uv_layer)
        built[f"{side}{f}"] = {"ring": len(loops[li]), "faces": nf}
    missing = [f"{targets[i][0]}{targets[i][1]}" for i in range(len(targets))
               if i not in assign]
    log("built", json.dumps(built))
    log("missing", missing)

    after_bound = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    nonman = sum(1 for e in bm.edges if len(e.link_faces) > 2)
    log("boundary_edges before/after", before_bound, after_bound, "nonmanifold", nonman)

    bm.to_mesh(me)
    bm.free()
    me.update()
    bpy.ops.wm.save_as_mainfile(filepath=RIGGED)
    print("BUILDDONE" + json.dumps({
        "built": built, "missing": missing,
        "boundary_before": before_bound, "boundary_after": after_bound,
        "nonmanifold": nonman}) + "BUILDEND")


if __name__ == "__main__":
    main()
