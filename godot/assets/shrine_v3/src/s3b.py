"""s3b — 博麗神社 v3 的幾何建構小工具（Blender 端；幾何計算不依賴 bpy，可在一般 Python 測試）。

座標一律用 **Godot 空間**撰寫：x 右、y 上、z 前（資產正面＝+z）；單位公尺；原點＝結構底部中心。
寫進 Blender 時換成 Blender 座標 (x, −z, y)，glTF 匯出（+Y up）後在 Godot 還原成 (x, y, z)。

UV 一律「公尺」：材質在 Godot 端用 uv1_scale 決定一張貼圖代表幾公尺。
長條構件（梁、柱、板）木紋沿構件的長軸（local x，或圓柱的 local y）。
頂點色＝每塊構件的色差（±7%）× 近地面汙損；Godot 材質開 vertex_color_use_as_albedo。
"""
import math
import random

import numpy as np


# ───────────────────────── 矩陣 ─────────────────────────
def T(x, y, z):
    m = np.eye(4)
    m[:3, 3] = (x, y, z)
    return m


def Rx(a):
    c, s = math.cos(a), math.sin(a)
    m = np.eye(4)
    m[1, 1], m[1, 2], m[2, 1], m[2, 2] = c, -s, s, c
    return m


def Ry(a):
    c, s = math.cos(a), math.sin(a)
    m = np.eye(4)
    m[0, 0], m[0, 2], m[2, 0], m[2, 2] = c, s, -s, c
    return m


def Rz(a):
    c, s = math.cos(a), math.sin(a)
    m = np.eye(4)
    m[0, 0], m[0, 1], m[1, 0], m[1, 1] = c, -s, s, c
    return m


def S(x, y=None, z=None):
    m = np.eye(4)
    m[0, 0] = x
    m[1, 1] = x if y is None else y
    m[2, 2] = x if z is None else z
    return m


def frame(p0, p1, up=(0.0, 1.0, 0.0)):
    """local x＝p0→p1 方向、local y 盡量接近 up；原點在中點。回傳 (4x4, 長度)。"""
    p0 = np.asarray(p0, float)
    p1 = np.asarray(p1, float)
    d = p1 - p0
    L = float(np.linalg.norm(d))
    ex = d / max(L, 1e-9)
    upv = np.asarray(up, float)
    if abs(float(np.dot(ex, upv))) > 0.98:
        upv = np.array([0.0, 0.0, 1.0]) if abs(ex[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    ez = np.cross(ex, upv)
    ez /= np.linalg.norm(ez)
    ey = np.cross(ez, ex)
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2] = ex, ey, ez
    m[:3, 3] = (p0 + p1) * 0.5
    return m, L


def _xf(M, P):
    P = np.asarray(P, float)
    return P @ M[:3, :3].T + M[:3, 3]


# ───────────────────────── 建構器 ─────────────────────────
class Builder:
    """累積多邊形：每個多邊形＝(頂點 list[np3], uv list[(u,v)], 材質名, 平滑旗標, 色)。"""

    def __init__(self, name, seed=1):
        self.name = name
        self.polys = []
        self.rng = random.Random(seed)
        self.cols = []          # 碰撞規格（Godot 空間）
        self.markers = {}

    # 色差：每個構件一個係數
    def tint(self, amp=0.07):
        return 1.0 + self.rng.uniform(-amp, amp)

    def poly(self, pts, uvs, mat, smooth=False, col=1.0):
        self.polys.append(([np.asarray(p, float) for p in pts], [tuple(u) for u in uvs], mat, smooth, col))

    # ---- 原始體（local 空間建好再乘 M） ----
    def box(self, M, sx, sy, sz, mat, bevel=0.0, col=None, grain='x', uv_off=None):
        """中心在 local 原點的長方體（可倒角）。grain：木紋所在的 local 軸。"""
        col = self.tint() if col is None else col
        hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
        b = min(bevel, hx * 0.45, hy * 0.45, hz * 0.45)
        uo = uv_off if uv_off is not None else (self.rng.uniform(0, 7), self.rng.uniform(0, 7))
        faces = []
        # 六個主面（倒角後內縮）
        for ax in range(3):
            for sg in (-1.0, 1.0):
                o = [(ax + 1) % 3, (ax + 2) % 3]
                hs = [hx, hy, hz]
                c = [0.0, 0.0, 0.0]
                c[ax] = sg * hs[ax]
                a0, a1 = o
                r0 = hs[a0] - b
                r1 = hs[a1] - b
                q = []
                for (s0, s1) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    p = list(c)
                    p[a0] = s0 * r0
                    p[a1] = s1 * r1
                    q.append(p)
                # 法線方向一致（CCW 從外側看）
                n = [0.0, 0.0, 0.0]
                n[ax] = sg
                if np.dot(np.cross(np.subtract(q[1], q[0]), np.subtract(q[2], q[0])), n) < 0:
                    q = q[::-1]
                faces.append((q, ax))
        if b > 1e-6:
            # 12 條稜的倒角面＋8 個角三角形
            for ax in range(3):
                a0, a1 = (ax + 1) % 3, (ax + 2) % 3
                hs = [hx, hy, hz]
                for s0 in (-1.0, 1.0):
                    for s1 in (-1.0, 1.0):
                        q = []
                        for t in (-1.0, 1.0):
                            p1 = [0.0, 0.0, 0.0]
                            p1[ax] = t * (hs[ax] - b)
                            p1[a0] = s0 * hs[a0]
                            p1[a1] = s1 * (hs[a1] - b)
                            p2 = list(p1)
                            p2[a0] = s0 * (hs[a0] - b)
                            p2[a1] = s1 * hs[a1]
                            q.append((p1, p2))
                        quad = [q[0][0], q[1][0], q[1][1], q[0][1]]
                        n = [0.0, 0.0, 0.0]
                        n[a0] = s0
                        n[a1] = s1
                        if np.dot(np.cross(np.subtract(quad[1], quad[0]), np.subtract(quad[2], quad[0])), n) < 0:
                            quad = quad[::-1]
                        faces.append((quad, -1))
            for sx_ in (-1.0, 1.0):
                for sy_ in (-1.0, 1.0):
                    for sz_ in (-1.0, 1.0):
                        tri = [[sx_ * hx, sy_ * (hy - b), sz_ * (hz - b)],
                               [sx_ * (hx - b), sy_ * hy, sz_ * (hz - b)],
                               [sx_ * (hx - b), sy_ * (hy - b), sz_ * hz]]
                        n = [sx_, sy_, sz_]
                        if np.dot(np.cross(np.subtract(tri[1], tri[0]), np.subtract(tri[2], tri[0])), n) < 0:
                            tri = tri[::-1]
                        faces.append((tri, -2))
        gi = {'x': 0, 'y': 1, 'z': 2}[grain]
        for q, ax in faces:
            Q = np.array(q, float)
            nrm = np.cross(Q[1] - Q[0], Q[2] - Q[0])
            nn = np.abs(nrm)
            dom = int(np.argmax(nn))
            if dom == gi:
                # 端面：另外兩軸
                o = [k for k in range(3) if k != gi]
                uv = [(p[o[0]] + uo[0], p[o[1]] + uo[1]) for p in Q]
            else:
                other = [k for k in range(3) if k != gi and k != dom][0]
                uv = [(p[gi] + uo[0], p[other] + uo[1]) for p in Q]
            self.poly(_xf(M, Q), uv, mat, False, col)

    def beam(self, p0, p1, w, h, mat, up=(0, 1, 0), bevel=0.012, ext=0.0, col=None):
        """兩點間的方材（local x 沿長、y 高 h、z 寬 w）。ext：兩端各延伸。"""
        M, L = frame(p0, p1, up)
        self.box(M, L + 2 * ext, h, w, mat, bevel, col, 'x')

    def cyl(self, M, r, h, mat, n=12, cap_top=True, cap_bot=False, r_top=None, smooth=True, col=None, grain_y=True):
        """local y 軸圓柱（底在 y=0）。r_top 給定則為圓台。"""
        col = self.tint() if col is None else col
        rt = r if r_top is None else r_top
        uo = self.rng.uniform(0, 7)
        for i in range(n):
            a0 = 2 * math.pi * i / n
            a1 = 2 * math.pi * (i + 1) / n
            p = [[r * math.sin(a0), 0, r * math.cos(a0)], [r * math.sin(a1), 0, r * math.cos(a1)],
                 [rt * math.sin(a1), h, rt * math.cos(a1)], [rt * math.sin(a0), h, rt * math.cos(a0)]]
            u0 = a0 * r + uo
            u1 = a1 * r + uo
            uv = [(0, u0), (0, u1), (h, u1), (h, u0)] if grain_y else [(u0, 0), (u1, 0), (u1, h), (u0, h)]
            self.poly(_xf(M, p), uv, mat, smooth, col)
        if cap_top:
            pts = [[rt * math.sin(2 * math.pi * i / n), h, rt * math.cos(2 * math.pi * i / n)] for i in range(n)]
            self.poly(_xf(M, pts), [(p[0], p[2]) for p in pts], mat, False, col)
        if cap_bot:
            pts = [[r * math.sin(2 * math.pi * i / n), 0, r * math.cos(2 * math.pi * i / n)] for i in range(n)][::-1]
            self.poly(_xf(M, pts), [(p[0], p[2]) for p in pts], mat, False, col)

    def lathe(self, M, prof, mat, n=16, smooth=True, col=None, close_top=True, close_bot=False):
        """prof：[(r, y)] 由下而上；繞 local y 旋轉。"""
        col = self.tint() if col is None else col
        s = 0.0
        acc = [0.0]
        for i in range(1, len(prof)):
            s += math.hypot(prof[i][0] - prof[i - 1][0], prof[i][1] - prof[i - 1][1])
            acc.append(s)
        for j in range(len(prof) - 1):
            (r0, y0), (r1, y1) = prof[j], prof[j + 1]
            for i in range(n):
                a0 = 2 * math.pi * i / n
                a1 = 2 * math.pi * (i + 1) / n
                p = [[r0 * math.sin(a0), y0, r0 * math.cos(a0)], [r0 * math.sin(a1), y0, r0 * math.cos(a1)],
                     [r1 * math.sin(a1), y1, r1 * math.cos(a1)], [r1 * math.sin(a0), y1, r1 * math.cos(a0)]]
                rr = max(r0, r1, 0.05)
                uv = [(a0 * rr, acc[j]), (a1 * rr, acc[j]), (a1 * rr, acc[j + 1]), (a0 * rr, acc[j + 1])]
                if r0 < 1e-6:
                    self.poly(_xf(M, [p[0], p[2], p[3]]), [uv[0], uv[2], uv[3]], mat, smooth, col)
                elif r1 < 1e-6:
                    self.poly(_xf(M, [p[0], p[1], p[2]]), [uv[0], uv[1], uv[2]], mat, smooth, col)
                else:
                    self.poly(_xf(M, p), uv, mat, smooth, col)
        if close_top and prof[-1][0] > 1e-6:
            r, y = prof[-1]
            pts = [[r * math.sin(2 * math.pi * i / n), y, r * math.cos(2 * math.pi * i / n)] for i in range(n)]
            self.poly(_xf(M, pts), [(p[0], p[2]) for p in pts], mat, False, col)
        if close_bot and prof[0][0] > 1e-6:
            r, y = prof[0]
            pts = [[r * math.sin(2 * math.pi * i / n), y, r * math.cos(2 * math.pi * i / n)] for i in range(n)][::-1]
            self.poly(_xf(M, pts), [(p[0], p[2]) for p in pts], mat, False, col)

    def prism(self, M, poly2, y0, y1, mat, col=None, cap_top=True, cap_bot=False, uv_scale=1.0):
        """local xz 平面多邊形（CCW 從上看）擠出 y0→y1。"""
        col = self.tint() if col is None else col
        n = len(poly2)
        s = 0.0
        for i in range(n):
            a = poly2[i]
            b = poly2[(i + 1) % n]
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            p = [[a[0], y0, a[1]], [b[0], y0, b[1]], [b[0], y1, b[1]], [a[0], y1, a[1]]]
            # 外側法線：CCW（從 +y 看）多邊形的外向
            uv = [(s, y0), (s + L, y0), (s + L, y1), (s, y1)]
            P = np.array(p)
            nrm = np.cross(P[1] - P[0], P[2] - P[0])
            mid = (P[0] + P[1]) * 0.5
            cen = np.array([np.mean([q[0] for q in poly2]), mid[1], np.mean([q[1] for q in poly2])])
            if np.dot(nrm, mid - cen) < 0:
                p = p[::-1]
                uv = uv[::-1]
            self.poly(_xf(M, p), [(u * uv_scale, v * uv_scale) for u, v in uv], mat, False, col)
            s += L
        top = [[q[0], y1, q[1]] for q in poly2]
        if cap_top:
            P = np.array(top)
            if np.cross(P[1] - P[0], P[2] - P[0])[1] < 0:
                top = top[::-1]
            self.poly(_xf(M, top), [(p[0] * uv_scale, p[2] * uv_scale) for p in top], mat, False, col)
        if cap_bot:
            bot = [[q[0], y0, q[1]] for q in poly2]
            P = np.array(bot)
            if np.cross(P[1] - P[0], P[2] - P[0])[1] > 0:
                bot = bot[::-1]
            self.poly(_xf(M, bot), [(p[0] * uv_scale, p[2] * uv_scale) for p in bot], mat, False, col)

    def quad(self, pts, uvs, mat, col=None, smooth=False, double=False):
        col = self.tint(0.03) if col is None else col
        self.poly(pts, uvs, mat, smooth, col)
        if double:
            self.poly(pts[::-1], uvs[::-1], mat, smooth, col)

    def tube(self, pts, radii, mat, n=8, smooth=True, col=None, caps=True, twist=0.0, uv_v_scale=1.0):
        """沿折線的圓管（平行移動框架）。radii：每點半徑。twist：每公尺 UV 扭轉（繩紋）。"""
        col = self.tint() if col is None else col
        P = [np.asarray(p, float) for p in pts]
        m = len(P)
        tans = []
        for i in range(m):
            a = P[max(i - 1, 0)]
            b = P[min(i + 1, m - 1)]
            t = b - a
            tans.append(t / max(np.linalg.norm(t), 1e-9))
        ref = np.array([0.0, 1.0, 0.0]) if abs(tans[0][1]) < 0.9 else np.array([1.0, 0.0, 0.0])
        nrm = np.cross(tans[0], ref)
        nrm /= np.linalg.norm(nrm)
        rings = []
        s = 0.0
        acc = []
        for i in range(m):
            if i > 0:
                s += float(np.linalg.norm(P[i] - P[i - 1]))
                # 平行移動
                v = np.cross(tans[i - 1], tans[i])
                if np.linalg.norm(v) > 1e-9:
                    ang = math.acos(max(-1.0, min(1.0, float(np.dot(tans[i - 1], tans[i])))))
                    vv = v / np.linalg.norm(v)
                    nrm = nrm * math.cos(ang) + np.cross(vv, nrm) * math.sin(ang) + vv * np.dot(vv, nrm) * (1 - math.cos(ang))
            acc.append(s)
            bn = np.cross(tans[i], nrm)
            ring = []
            for k in range(n):
                a = 2 * math.pi * k / n
                ring.append(P[i] + radii[i] * (nrm * math.cos(a) + bn * math.sin(a)))
            rings.append(ring)
        for i in range(m - 1):
            rr = max(radii[i], radii[i + 1])
            for k in range(n):
                k2 = (k + 1) % n
                u0 = 2 * math.pi * k / n * rr + acc[i] * twist
                u1 = 2 * math.pi * (k + 1) / n * rr + acc[i] * twist
                u2 = 2 * math.pi * (k + 1) / n * rr + acc[i + 1] * twist
                u3 = 2 * math.pi * k / n * rr + acc[i + 1] * twist
                q = [rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k2]]
                uv = [(acc[i] * uv_v_scale, u0), (acc[i + 1] * uv_v_scale, u3), (acc[i + 1] * uv_v_scale, u2), (acc[i] * uv_v_scale, u1)]
                self.poly(q, uv, mat, smooth, col)
        if caps:
            for i, rev in ((0, True), (m - 1, False)):
                ring = rings[i][::-1] if rev else rings[i]
                self.poly(ring, [(0, 0)] * n, mat, False, col)

    def strip(self, rows, uvs, mat, col=None, smooth=False):
        """格狀曲面：rows[i][j]＝點、uvs[i][j]＝uv；相鄰兩列兩行組四邊形（點的順序決定正面）。"""
        col = self.tint(0.03) if col is None else col
        for i in range(len(rows) - 1):
            for j in range(len(rows[i]) - 1):
                q = [rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]]
                u = [uvs[i][j], uvs[i][j + 1], uvs[i + 1][j + 1], uvs[i + 1][j]]
                self.poly(q, u, mat, smooth, col)

    # ---- 碰撞／標記（Godot 空間） ----
    def col_box(self, M, size, note=''):
        self.cols.append({'type': 'box', 'size': [float(s) for s in size], 'xf': _mat_list(M), 'note': note})

    def col_cyl(self, M, r, h, note=''):
        self.cols.append({'type': 'cyl', 'r': float(r), 'h': float(h), 'xf': _mat_list(M), 'note': note})

    def mark(self, name, p):
        self.markers[name] = [float(v) for v in p]

    # ---- 統計 ----
    def bounds(self, mats=None):
        P = [p for pts, _, m, _, _ in self.polys if mats is None or m in mats for p in pts]
        A = np.array(P)
        return A.min(0), A.max(0)

    def tri_count(self):
        return sum(len(p[0]) - 2 for p in self.polys)


def _mat_list(M):
    return [float(v) for v in np.asarray(M)[:3, :4].T.reshape(-1)]   # Godot Transform3D：basis 三欄＋origin


def grime(y, y0=0.0, h=0.7, k=0.28):
    """近地面變暗（雨濺／泥）：y0 以上 h 公尺內由 (1−k) 漸回 1。"""
    t = min(max((y - y0) / h, 0.0), 1.0)
    return 1.0 - k * (1.0 - t * t * (3 - 2 * t))


# ───────────────────────── 寫進 Blender ─────────────────────────
def to_blender(b, mats, ground_grime=True, grime_mats=('s3_wood_old', 's3_wood_dark', 's3_stone', 's3_stone_moss', 's3_paint_red', 's3_plaster')):
    """Builder → 單一 Blender 物件（多材質）。mats：材質名 → bpy 材質。回傳物件。"""
    import bpy
    import bmesh
    me = bpy.data.meshes.new(b.name)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    cl = bm.loops.layers.color.new('Col')
    mat_names = []
    for pts, uvs, m, smooth, col in b.polys:
        if m not in mat_names:
            mat_names.append(m)
    for pts, uvs, m, smooth, col in b.polys:
        vs = [bm.verts.new((float(p[0]), float(-p[2]), float(p[1]))) for p in pts]
        try:
            f = bm.faces.new(vs)
        except ValueError:
            continue
        f.material_index = mat_names.index(m)
        f.smooth = smooth
        for lp, uv, p in zip(f.loops, uvs, pts):
            lp[uvl].uv = (float(uv[0]), float(uv[1]))
            g = grime(float(p[1])) if (ground_grime and m in grime_mats) else 1.0
            c = max(0.0, min(1.0, col * g))
            lp[cl] = (c, c, c, 1.0)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(b.name, me)
    for m in mat_names:
        me.materials.append(mats[m])
    bpy.context.scene.collection.objects.link(ob)
    return ob
