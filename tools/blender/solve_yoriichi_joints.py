"""從 身體2 網格幾何反解緣一骨位。

Meshy auto-rig 是對「合併+含羽織長袖+袴」的網格算骨，袖子與袴把肘/腕/膝
的骨位拉出身體外（實測肘偏 11-15 cm、膝偏 10 cm）。本求解器只讀 身體2
本體，用切片中心線 + 半徑極值定位關節，另用網格連通分量抓五指。

輸出 JSON：每根骨的 head/tail/parent（世界座標，公尺）。
"""
import json
import numpy as np
from collections import defaultdict, deque

# 角色面向 -Y，背面 +Y，+X 為角色左手側
BODY = "身體2"


def _mesh_world(obj):
    M = obj.matrix_world
    co = np.array([[(M @ v.co).x, (M @ v.co).y, (M @ v.co).z] for v in obj.data.vertices])
    edges = [(e.vertices[0], e.vertices[1]) for e in obj.data.edges]
    return co, edges


def _components(edges, idx, min_n=8):
    """回傳頂點索引集合內的連通分量（由大到小）。"""
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
        q, comp = deque([v]), []
        seen.add(v)
        while q:
            x = q.popleft()
            comp.append(x)
            for y in adj[x]:
                if y not in seen:
                    seen.add(y)
                    q.append(y)
        if len(comp) >= min_n:
            out.append(comp)
    return sorted(out, key=len, reverse=True)


def _slice_axis(co, axis, lo, hi, step, half, mask=None):
    """沿 axis 切片，回傳 [(座標, n, 中心, 平均半徑)]。"""
    other = [i for i in range(3) if i != axis]
    rows = []
    c = lo
    while c <= hi + 1e-9:
        m = (co[:, axis] > c - half) & (co[:, axis] < c + half)
        if mask is not None:
            m &= mask
        Q = co[m]
        if len(Q) >= 6:
            ctr = Q.mean(axis=0)
            r = float(np.hypot(Q[:, other[0]] - ctr[other[0]],
                               Q[:, other[1]] - ctr[other[1]]).mean())
            rows.append((round(c, 4), int(len(Q)), ctr, r))
        c += step
    return rows


def _at(rows, coord, axis):
    """在切片表上線性內插出中心點。"""
    xs = np.array([r[0] for r in rows])
    C = np.array([r[2] for r in rows])
    out = C[0].copy()
    for i in range(3):
        out[i] = float(np.interp(coord, xs, C[:, i]))
    out[axis] = coord
    return out


def _argmin_radius(rows, lo, hi):
    cand = [r for r in rows if lo <= r[0] <= hi]
    return min(cand, key=lambda r: r[3])


def solve(obj):
    co, edges = _mesh_world(obj)
    J = {}
    meta = {}

    # ---------- 手臂 ----------
    # 限制在手臂高度帶，排除軀幹與衣物；身體2 本體無衣物，但仍排除頭頸
    for side, sg in (("Left", 1), ("Right", -1)):
        band = ((co[:, 2] > 1.38) & (co[:, 2] < 1.56)
                & (co[:, 1] > -0.02) & (co[:, 1] < 0.15)
                & (co[:, 0] * sg > 0.0))
        # 以 |x| 掃描，避免右側負座標讓步進方向反轉
        aco = co.copy()
        aco[:, 0] = np.abs(aco[:, 0])
        rows = _slice_axis(aco, 0, 0.13, 0.66, 0.01, 0.005, band)
        meta[f"arm{side}"] = [(r[0], r[1], round(r[3], 4)) for r in rows]

        # 腕：半徑全域極小（0.45~0.56）
        wrist_x = _argmin_radius(rows, 0.45, 0.56)[0]
        # 肘：上臂與前臂之間的半徑局部極小（0.28~0.42）
        elbow_x = _argmin_radius(rows, 0.28, 0.42)[0]
        # 肩：手臂截面併入軀幹處，取切片頂點數急增前的最後一點
        sh_x = None
        for i in range(len(rows) - 1, 0, -1):
            if rows[i][0] < 0.30 and rows[i][1] > 2.0 * rows[i + 1][1]:
                sh_x = rows[i + 1][0]
                break
        if sh_x is None:
            sh_x = 0.175

        shoulder = _at(rows, sh_x, 0)
        elbow = _at(rows, elbow_x, 0)
        wrist = _at(rows, wrist_x, 0)
        for p in (shoulder, elbow, wrist):
            p[0] *= sg

        # 鎖骨起點：脊椎頂附近、往外 3.5 cm
        clav = np.array([0.035 * sg, shoulder[1], shoulder[2]])

        J[f"{side}Shoulder"] = (clav, shoulder)
        J[f"{side}Arm"] = (shoulder, elbow)
        J[f"{side}ForeArm"] = (elbow, wrist)
        meta[f"joint{side}"] = {"shoulder_x": sh_x, "elbow_x": elbow_x, "wrist_x": wrist_x}

        # ---------- 手掌與五指 ----------
        # 指根分離處：x>0.638 出現 4 段（食中無小）；x>0.615 另可分出拇指
        four = _components(edges, np.where(co[:, 0] * sg > 0.638)[0], min_n=15)
        four = sorted(four, key=lambda c: co[c][:, 1].mean())
        thumb = None
        for c in _components(edges, np.where(co[:, 0] * sg > 0.615)[0], min_n=15):
            P = co[c]
            if P[:, 2].mean() < 1.435 and P[:, 1].mean() < 0.035:
                thumb = c
                break

        names = ["Index", "Middle", "Ring", "Pinky"]
        knuckle_x = 0.615          # 掌指關節（指仍與掌相連處）
        for nm, comp in zip(names, four):
            P = co[comp]
            d = P[:, 0] * sg
            tip = P[d.argmax()]
            base = P[d.argmin()]
            axis = tip - base
            n = np.linalg.norm(axis)
            if n < 1e-6:
                continue
            axis = axis / n
            # 由分離處往回外推到掌指關節
            back = (abs(base[0]) - knuckle_x) / max(abs(axis[0]), 1e-6)
            mcp = base - axis * back
            total = float(np.linalg.norm(tip - mcp))
            p1 = mcp + axis * total * 0.45
            p2 = mcp + axis * total * 0.75
            J[f"{side}Hand{nm}1"] = (mcp, p1)
            J[f"{side}Hand{nm}2"] = (p1, p2)
            J[f"{side}Hand{nm}3"] = (p2, tip)

        if thumb is not None:
            P = co[thumb]
            d = P[:, 0] * sg
            tip = P[d.argmax()]
            base = P[d.argmin()]
            axis = tip - base
            axis = axis / max(np.linalg.norm(axis), 1e-6)
            cmc = base - axis * 0.022          # 拇指腕掌關節再往回
            total = float(np.linalg.norm(tip - cmc))
            p1 = cmc + axis * total * 0.40
            p2 = cmc + axis * total * 0.72
            J[f"{side}HandThumb1"] = (cmc, p1)
            J[f"{side}HandThumb2"] = (p1, p2)
            J[f"{side}HandThumb3"] = (p2, tip)
            meta[f"thumb{side}"] = {"n": len(thumb), "len": round(total, 4)}

        # 手腕骨指向中指掌指關節
        mid_mcp = J.get(f"{side}HandMiddle1")
        J[f"{side}Hand"] = (wrist, mid_mcp[0] if mid_mcp else wrist + np.array([0.09 * sg, 0, 0]))

    # ---------- 腿 ----------
    for side, sg in (("Left", 1), ("Right", -1)):
        m = co[:, 0] * sg > 0.012
        rows = _slice_axis(co, 2, 0.02, 1.00, 0.02, 0.01, m)
        meta[f"leg{side}"] = [(r[0], r[1], round(r[3], 4)) for r in rows]

        ankle_z = _argmin_radius(rows, 0.12, 0.30)[0]
        # 膝：小腿段 y 幾乎水平、大腿段 y 明顯後收，取 y 斜率轉折
        zs = np.array([r[0] for r in rows])
        ys = np.array([r[2][1] for r in rows])
        best, knee_z = None, 0.53
        for zc in np.arange(0.42, 0.68, 0.01):
            a = zs <= zc
            b = zs >= zc
            if a.sum() < 4 or b.sum() < 4:
                continue
            err = 0.0
            for mk in (a, b):
                p = np.polyfit(zs[mk], ys[mk], 1)
                err += float(np.sum((ys[mk] - np.polyval(p, zs[mk])) ** 2))
            if best is None or err < best:
                best, knee_z = err, float(zc)
        hip_z = 0.945

        ankle = _at(rows, ankle_z, 2)
        knee = _at(rows, knee_z, 2)
        hip = _at(rows, hip_z, 2)
        meta[f"legjoint{side}"] = {"ankle_z": ankle_z, "knee_z": round(knee_z, 3), "hip_z": hip_z}

        # 腳掌：角色面向 -Y，取足部前端
        foot_m = m & (co[:, 2] < ankle_z)
        F = co[foot_m]
        toe_tip = F[F[:, 1].argmin()]
        ball = np.array([ankle[0], (ankle[1] + toe_tip[1]) * 0.5, 0.030])
        toe_end = np.array([ankle[0], toe_tip[1], 0.025])

        J[f"{side}UpLeg"] = (hip, knee)
        J[f"{side}Leg"] = (knee, ankle)
        J[f"{side}Foot"] = (ankle, ball)
        J[f"{side}ToeBase"] = (ball, toe_end)

    # ---------- 軀幹 ----------
    trunk = np.abs(co[:, 0]) < 0.14
    rows = _slice_axis(co, 2, 0.95, 1.75, 0.03, 0.015, trunk)
    meta["spine"] = [(r[0], r[1], round(r[3], 4)) for r in rows]

    def spine_pt(z, back=0.18):
        """脊椎在軀幹後段，非形心：往背面(+Y)偏移深度的 back 比例。"""
        p = _at(rows, z, 2)
        m = trunk & (co[:, 2] > z - 0.02) & (co[:, 2] < z + 0.02)
        Q = co[m]
        depth = float(Q[:, 1].max() - Q[:, 1].min()) if len(Q) else 0.15
        p[1] += depth * back
        p[0] = 0.0
        return p

    pelvis = spine_pt(0.99, 0.05)
    s02 = spine_pt(1.18)
    s01 = spine_pt(1.32)
    s00 = spine_pt(1.45)
    neck = spine_pt(1.54, 0.10)
    head = spine_pt(1.63, 0.0)

    head_m = trunk & (co[:, 2] > 1.60)
    H = co[head_m]
    head_top = np.array([0.0, float(H[:, 1].mean()), float(H[:, 2].max())])

    J["Hips"] = (pelvis, s02)
    J["Spine02"] = (s02, s01)
    J["Spine01"] = (s01, s00)
    J["Spine"] = (s00, neck)
    J["neck"] = (neck, head)
    J["Head"] = (head, head_top)
    J["root"] = (np.array([0.0, 0.0, 0.0]), np.array([0.0, 0.0, 0.20]))

    return J, meta


PARENTS = {
    "root": None, "Hips": "root",
    "Spine02": "Hips", "Spine01": "Spine02", "Spine": "Spine01",
    "neck": "Spine", "Head": "neck",
}
for _s in ("Left", "Right"):
    PARENTS[f"{_s}Shoulder"] = "Spine"
    PARENTS[f"{_s}Arm"] = f"{_s}Shoulder"
    PARENTS[f"{_s}ForeArm"] = f"{_s}Arm"
    PARENTS[f"{_s}Hand"] = f"{_s}ForeArm"
    PARENTS[f"{_s}UpLeg"] = "Hips"
    PARENTS[f"{_s}Leg"] = f"{_s}UpLeg"
    PARENTS[f"{_s}Foot"] = f"{_s}Leg"
    PARENTS[f"{_s}ToeBase"] = f"{_s}Foot"
    for _f in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
        PARENTS[f"{_s}Hand{_f}1"] = f"{_s}Hand"
        PARENTS[f"{_s}Hand{_f}2"] = f"{_s}Hand{_f}1"
        PARENTS[f"{_s}Hand{_f}3"] = f"{_s}Hand{_f}2"


if __name__ == "__main__":
    import bpy
    obj = bpy.data.objects[BODY]
    J, meta = solve(obj)
    out = {k: {"head": [round(float(x), 5) for x in v[0]],
               "tail": [round(float(x), 5) for x in v[1]],
               "parent": PARENTS.get(k)} for k, v in J.items()}
    print("SOLVESTART" + json.dumps({"joints": out, "meta": meta}) + "SOLVEEND")
