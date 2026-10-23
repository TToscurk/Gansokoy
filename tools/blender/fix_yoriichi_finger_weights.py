"""手指權重重建：以幾何距離指派，取代 heat map。

heat map 在手指這種細長、彼此貼近的幾何上會讓相鄰指共享權重，渲染出來像
連指手套（實測指尖權重頂點僅 36-57 個）。本模組改用線段距離場：

  1. 用連通分量把每根手指的頂點抓出來（指根處與掌相連，故在分離面切）
  2. 掌區頂點沿最近指骨線段指派
  3. 每個頂點只取最近的 1-2 段骨，權重依距離倒數，且**不跨指混合**
  4. 指根一圈與掌做線性過渡，避免硬邊

被本模組接管的頂點，其原 heat map 權重（含 Hand/ForeArm）全部清掉重寫。
"""
import json
import math
from collections import defaultdict, deque

import bpy
import numpy as np

RIGGED = r"D:/神社/shrine/work/緣一_rigged.blend"
BODY = "身體2"
FINGERS = ("Thumb", "Index", "Middle", "Ring", "Pinky")
# 指根分離掃描面（|x|），實測 0.638 可分出四指、0.615 可再分出拇指
SPLIT_FOUR = 0.638
SPLIT_THUMB = 0.615
# 掌區起點：腕骨之後
PALM_X = 0.545


def log(*a):
    print("FIX", *a)


def _world(obj):
    M = obj.matrix_world
    return np.array([[(M @ v.co).x, (M @ v.co).y, (M @ v.co).z] for v in obj.data.vertices])


def _components(edges, idx, min_n=8):
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


def _seg_dist(P, a, b):
    """點集到線段 ab 的距離與投影比例 t。"""
    ab = b - a
    L2 = float(ab @ ab)
    if L2 < 1e-12:
        return np.linalg.norm(P - a, axis=1), np.zeros(len(P))
    t = np.clip(((P - a) @ ab) / L2, 0.0, 1.0)
    proj = a + np.outer(t, ab)
    return np.linalg.norm(P - proj, axis=1), t


def rebuild_finger_weights(arm, body):
    co = _world(body)
    edges = [(e.vertices[0], e.vertices[1]) for e in body.data.edges]
    bones = {b.name: (np.array(b.head_local), np.array(b.tail_local))
             for b in arm.data.bones}

    vg = {g.name: g for g in body.vertex_groups}

    def group(name):
        if name not in vg:
            vg[name] = body.vertex_groups.new(name=name)
        return vg[name]

    stats = {}
    for side, sg in (("Left", 1), ("Right", -1)):
        # --- 取得每根手指的頂點集合 ---
        four = _components(edges, np.where(co[:, 0] * sg > SPLIT_FOUR)[0], min_n=15)
        four = sorted(four, key=lambda c: co[c][:, 1].mean())   # y 小→大 = 食中無小
        thumb = None
        for c in _components(edges, np.where(co[:, 0] * sg > SPLIT_THUMB)[0], min_n=15):
            P = co[c]
            if P[:, 2].mean() < 1.435 and P[:, 1].mean() < 0.035:
                thumb = c
                break

        named = {}
        for nm, comp in zip(("Index", "Middle", "Ring", "Pinky"), four):
            named[nm] = set(comp)
        if thumb is not None:
            named["Thumb"] = set(thumb)

        # --- 掌區頂點：腕之後、未被指分離段包含者 ---
        claimed = set().union(*named.values()) if named else set()
        palm = [int(i) for i in np.where(co[:, 0] * sg > PALM_X)[0] if int(i) not in claimed]

        # --- 掌區頂點依最近指骨線段歸入對應指 ---
        if palm:
            Pp = co[palm]
            best_f, best_d = [None] * len(palm), np.full(len(palm), 1e9)
            for f in FINGERS:
                seg = f"{side}Hand{f}1"
                if seg not in bones:
                    continue
                a, b = bones[seg]
                d, _ = _seg_dist(Pp, a, b)
                m = d < best_d
                best_d = np.where(m, d, best_d)
                for k in np.where(m)[0]:
                    best_f[k] = f
            for k, vi in enumerate(palm):
                # 僅在極靠近指根（3 cm 內）才歸指，其餘留給 Hand
                if best_f[k] is not None and best_d[k] < 0.030:
                    named.setdefault(best_f[k], set()).add(vi)

        # --- 逐指以線段距離場寫權重 ---
        touched = 0
        for f, verts in named.items():
            segs = []
            for i in (1, 2, 3):
                nm = f"{side}Hand{f}{i}"
                if nm in bones:
                    segs.append((nm, bones[nm][0], bones[nm][1]))
            if not segs:
                continue
            vl = sorted(verts)
            P = co[vl]

            D = np.zeros((len(vl), len(segs)))
            T = np.zeros((len(vl), len(segs)))
            for j, (_, a, b) in enumerate(segs):
                D[:, j], T[:, j] = _seg_dist(P, a, b)

            # 清掉這些頂點的所有既有權重，避免 heat map 殘留把指黏在一起
            for g in body.vertex_groups:
                g.remove(vl)

            root_a = segs[0][1]
            axis = segs[-1][2] - root_a
            axis = axis / max(np.linalg.norm(axis), 1e-9)
            along = (P - root_a) @ axis

            for k, vi in enumerate(vl):
                order = np.argsort(D[k])
                j0 = int(order[0])
                w = {}
                # 只與「相鄰指節」混合，不跨指
                if len(segs) > 1:
                    j1 = int(order[1])
                    if abs(j1 - j0) == 1:
                        d0, d1 = D[k, j0] + 1e-6, D[k, j1] + 1e-6
                        w0 = (1.0 / d0) ** 2
                        w1 = (1.0 / d1) ** 2
                        s = w0 + w1
                        w[segs[j0][0]] = w0 / s
                        w[segs[j1][0]] = w1 / s
                    else:
                        w[segs[j0][0]] = 1.0
                else:
                    w[segs[j0][0]] = 1.0

                # 指根過渡：沿指軸 0~12 mm 與 Hand 混合，避免硬邊
                blend = float(np.clip(along[k] / 0.012, 0.0, 1.0))
                if blend < 1.0:
                    hand_w = 1.0 - blend
                    for kk in list(w):
                        w[kk] *= blend
                    w[f"{side}Hand"] = w.get(f"{side}Hand", 0.0) + hand_w

                for bn, wt in w.items():
                    if wt > 1e-4:
                        group(bn).add([vi], float(wt), "REPLACE")
                touched += 1
        stats[side] = {"fingers": {k: len(v) for k, v in named.items()}, "verts": touched}

    log("rebuilt", json.dumps(stats, ensure_ascii=False))
    return stats


def normalize(body):
    fixed = 0
    for v in body.data.vertices:
        gs = [g for g in v.groups if g.weight > 1e-6]
        s = sum(g.weight for g in gs)
        if not gs or abs(s - 1.0) < 1e-4:
            continue
        for g in gs:
            body.vertex_groups[g.group].add([v.index], g.weight / s, "REPLACE")
        fixed += 1
    log("normalized", fixed)


def audit(arm, body):
    counts = {}
    for v in body.data.vertices:
        for g in v.groups:
            if g.weight > 0.01:
                nm = body.vertex_groups[g.group].name
                counts[nm] = counts.get(nm, 0) + 1
    no_w = sum(1 for v in body.data.vertices
               if not v.groups or sum(g.weight for g in v.groups) < 1e-4)
    off = sum(1 for v in body.data.vertices
              if v.groups and abs(sum(g.weight for g in v.groups) - 1.0) > 0.05)
    fing = {k: v for k, v in sorted(counts.items())
            if any(f in k for f in FINGERS)}
    return {"unweighted": no_w, "weightsum_off": off,
            "finger_counts": fing,
            "zero_bones": [b.name for b in arm.data.bones
                           if b.use_deform and counts.get(b.name, 0) == 0]}


def main():
    bpy.ops.wm.open_mainfile(filepath=RIGGED)
    arm = bpy.data.objects["Armature"]
    body = bpy.data.objects[BODY]
    rebuild_finger_weights(arm, body)
    normalize(body)
    rep = audit(arm, body)
    print("AUDITSTART" + json.dumps(rep, ensure_ascii=False) + "AUDITEND")
    bpy.ops.wm.save_as_mainfile(filepath=RIGGED)
    log("saved", RIGGED)


if __name__ == "__main__":
    main()
