"""博麗神社 v3 場地構件（依 maps/shrine_v3/gen/layout.json ＋ h_near.f32 生成，世界座標；原點＝地圖原點）。
  "D:/Blender/blender-5.2.1-windows-x64/blender.exe" -b --factory-startup --python godot/assets/shrine_v3/src/make_site.py
輸出 godot/assets/shrine_v3/models/site/：
  stairs.glb      石段（每階兩塊切石、平台鋪石、兩側耳石）
  sando.glb       參道切石（鳥居→拜殿；缺石、沉陷、色差）＋拜殿前小廣場＋飛石
  fence_w.glb     西崖木柵（柱 1.8 m 一支、兩道橫木，隨地形）
  rock_*.glb      岩石 8 種（原點＝底面中心；Godot 端三向投影石材）
  site.json       碰撞（石段坡道／平台、木柵）與每個構件的資訊
"""
import json
import math
import os
import random
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import s3b  # noqa: E402
from s3b import T, Rx, Ry, Rz, Builder  # noqa: E402

GODOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
GEN = os.path.join(GODOT, 'maps', 'shrine_v3', 'gen')
OUT = os.path.join(GODOT, 'assets', 'shrine_v3', 'models', 'site')
os.makedirs(OUT, exist_ok=True)
L = json.load(open(os.path.join(GEN, 'layout.json'), encoding='utf-8'))
NR = L['near']
NX, NZ = L['near_n']
H = np.fromfile(os.path.join(GEN, 'h_near.f32'), dtype=np.float32).reshape(NZ, NX)


def gy(x, z):
    """與 s3lib.gd height_at 相同的三角剖分。"""
    fx = (x - NR['x0']) / NR['step']
    fz = (z - NR['z0']) / NR['step']
    i = min(max(int(math.floor(fx)), 0), NX - 2)
    j = min(max(int(math.floor(fz)), 0), NZ - 2)
    u = min(max(fx - i, 0.0), 1.0)
    v = min(max(fz - j, 0.0), 1.0)
    ha, hb, hc, hd = float(H[j, i]), float(H[j, i + 1]), float(H[j + 1, i]), float(H[j + 1, i + 1])
    if (i + j) % 2 == 0:
        if u >= v:
            return ha + (hb - ha) * u + (hd - hb) * v
        return ha + (hd - hc) * u + (hc - ha) * v
    if u + v <= 1.0:
        return ha + (hb - ha) * u + (hc - ha) * v
    return hd + (hc - hd) * (1.0 - u) + (hb - hd) * (1.0 - v)


def foot_max(cx, cz, hw, hd, yaw=0.0):
    c, s = math.cos(yaw), math.sin(yaw)
    best = -1e9
    for ox in (-1, 0, 1):
        for oz in (-1, 0, 1):
            x = cx + c * ox * hw + s * oz * hd
            z = cz - s * ox * hw + c * oz * hd
            best = max(best, gy(x, z))
    return best


def sloped_block(b, x0, x1, z0, z1, yt0, yt1, depth, mat, col=None):
    """側視圖為梯形的長石（頂面由 (z0,yt0) 斜到 (z1,yt1)），厚 depth 往下。"""
    q = [(z0, yt0 - depth), (z1, yt1 - depth), (z1, yt1), (z0, yt0)]
    col = b.tint() if col is None else col
    for (xa, xb, sgn) in ((x0, x0, -1), (x1, x1, 1)):
        pts = [(xa, y, z) for (z, y) in q]
        if sgn < 0:
            pts = pts[::-1]
        b.poly(pts, [(z, y) for (_, y, z) in pts], mat, False, col)
    for k in range(4):
        (za, ya), (zb, yb) = q[k], q[(k + 1) % 4]
        pts = [(x0, ya, za), (x0, yb, zb), (x1, yb, zb), (x1, ya, za)]
        P = np.array(pts)
        n = np.cross(P[1] - P[0], P[2] - P[0])
        mid = P.mean(0)
        cen = np.array([(x0 + x1) / 2, (yt0 + yt1) / 2 - depth / 2, (z0 + z1) / 2])
        if np.dot(n, mid - cen) < 0:
            pts = pts[::-1]
        b.poly(pts, [(p[0], p[2] + p[1]) for p in pts], mat, False, col)


# ───────────────────────── 石段 ─────────────────────────
def build_stairs(cols):
    b = Builder('stairs', seed=201)
    st = L['stair']
    W = st['width']
    segs = L['stair_segs']
    P = L['P']
    rng = b.rng
    # 階頂收邊石（平台高）
    b.box(T(0, P - 0.12, st['z_top'] - 0.30), W + 0.4, 0.24, 0.64, 's3_stone', bevel=0.02)
    prev_y = P
    for (za, zb, ytop, kind, fl) in segs:
        if kind == 'tread':
            split = rng.uniform(-0.25, 0.25)
            parts = [(-W / 2, split - 0.006), (split + 0.006, W / 2)]
            for (xa, xb) in parts:
                jy = rng.uniform(-0.006, 0.004)
                rot = rng.uniform(-0.006, 0.006)
                M = T((xa + xb) / 2, ytop - 0.12 + jy, (za + zb) / 2 - 0.01) @ Ry(rot)
                b.box(M, xb - xa, 0.24, (zb - za) + 0.07, 's3_stone', bevel=0.022)
        else:
            # 踊り場：兩列鋪石
            n_rows = 3
            dz = (zb - za) / n_rows
            for r in range(n_rows):
                cuts = sorted([-W / 2, W / 2] + [rng.uniform(-0.5, 0.5)] + ([rng.uniform(-1.2, -0.7)] if r % 2 else [rng.uniform(0.7, 1.2)]))
                for k in range(len(cuts) - 1):
                    xa, xb = cuts[k] + 0.006, cuts[k + 1] - 0.006
                    M = T((xa + xb) / 2, ytop - 0.11 + rng.uniform(-0.008, 0.004), za + dz * (r + 0.5))
                    b.box(M, xb - xa, 0.22, dz - 0.012, 's3_stone', bevel=0.018)
        prev_y = ytop
    # 兩側耳石：沿踏面前緣線 +0.10，每 ~1.3 m 一塊
    def nose_y(z):
        zs = [st['z_top']] + [s[1] for s in segs] + [L['z_foot']]
        ys = [P] + [s[2] for s in segs] + [L['y_foot']]
        return float(np.interp(z, zs, ys))
    z = st['z_top'] - 0.2
    zend = L['z_foot'] + 0.3
    while z < zend - 0.05:
        z1 = min(z + rng.uniform(1.1, 1.5), zend)
        for sx in (-1, 1):
            xa = sx * (W / 2 + 0.02)
            xb = sx * (W / 2 + 0.30)
            yt0 = nose_y(z) + 0.12
            yt1 = nose_y(z1) + 0.12
            sloped_block(b, min(xa, xb), max(xa, xb), z, z1 - 0.01, yt0, yt1, 0.55, 's3_stone')
        z = z1
    # 碰撞：每段一個坡道（過各階踏面中點）＋踊り場平台
    flights = {}
    for (za, zb, ytop, kind, fl) in segs:
        flights.setdefault(fl, []).append((za, zb, ytop, kind))
    for fl, lst in sorted(flights.items()):
        treads = [s for s in lst if s[3] == 'tread']
        lands = [s for s in lst if s[3] == 'landing']
        if treads:
            za = treads[0][0]
            zb = treads[-1][1]
            ya = treads[0][2] + st['rise'] * 0.5
            yb = treads[-1][2] - st['rise'] * 0.5
            if fl == 0:
                za = st['z_top'] - 0.6
                ya = P
            if not lands:   # 最後一段：落到石段腳
                zb = L['z_foot'] + 0.5
                yb = L['y_foot']
            cols.append({'type': 'ramp', 'z0': za, 'y0': ya, 'z1': zb, 'y1': yb, 'w': W + 0.2, 'note': '石段坡道%d' % fl})
        for (za, zb, ytop, kind) in lands:
            cols.append({'type': 'flat', 'z0': za - 0.1, 'z1': zb + 0.1, 'y': ytop, 'w': W + 0.2, 'note': '踊り場%d' % fl})
    return b


# ───────────────────────── 參道 ─────────────────────────
def build_sando():
    b = Builder('sando', seed=211)
    rng = b.rng
    sd = L['sando']
    z = sd['z0']
    W = 1.3      # 中央石帶寬（參道整平寬 1.9，兩側留泥土）
    row = 0
    while z > sd['z1'] + 0.2:
        dz = rng.uniform(0.42, 0.62)
        z1 = z - dz
        nc = rng.choice([2, 2, 3])
        cuts = sorted([-W / 2, W / 2] + [rng.uniform(-W / 2 + 0.3, W / 2 - 0.3) for _ in range(nc - 1)])
        for k in range(len(cuts) - 1):
            xa, xb = cuts[k] + 0.012, cuts[k + 1] - 0.012
            cx, cz = (xa + xb) / 2, (z + z1) / 2
            hw, hd = (xb - xa) / 2, (dz - 0.024) / 2
            g = foot_max(cx, cz, hw, hd)
            sink = rng.uniform(-0.012, 0.0) if rng.random() < 0.3 else 0.0
            M = T(cx, g + 0.03 + sink - 0.07, cz) @ Ry(rng.uniform(-0.008, 0.008)) @ Rx(rng.uniform(-0.004, 0.004))
            b.box(M, xb - xa, 0.14, dz - 0.024, 's3_stone', bevel=0.014)
        z = z1
        row += 1
    # 拜殿前小廣場（木階前）
    for r in range(4):
        zc = -17.0 - r * 0.55
        cuts = sorted([-1.8, 1.8] + [rng.uniform(-1.4, -0.5), rng.uniform(-0.3, 0.3), rng.uniform(0.5, 1.4)])
        for k in range(len(cuts) - 1):
            xa, xb = cuts[k] + 0.012, cuts[k + 1] - 0.012
            cx = (xa + xb) / 2
            g = foot_max(cx, zc, (xb - xa) / 2, 0.26)
            b.box(T(cx, g + 0.03 - 0.07, zc), xb - xa, 0.14, 0.53, 's3_stone', bevel=0.014)
    # 飛石：前庭→倉庫、參道→手水舍、後方林徑起點
    paths = [L['paths']['to_store'], [(-1.2, 0.6), (-4.0, 0.7), (-6.6, 0.6)]]
    for pts in paths:
        pts = [np.array(p, float) for p in pts]
        acc = 0.0
        for i in range(len(pts) - 1):
            a, c = pts[i], pts[i + 1]
            seg = float(np.linalg.norm(c - a))
            t = 0.35 - acc if acc < 0.35 else 0.0
            while t < seg:
                p = a + (c - a) * (t / seg)
                p = p + np.array([rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08)])
                r = rng.uniform(0.24, 0.32)
                poly = [(math.cos(k * 2 * math.pi / 9) * r * rng.uniform(0.85, 1.1), math.sin(k * 2 * math.pi / 9) * r * rng.uniform(0.8, 1.05)) for k in range(9)]
                g = foot_max(p[0], p[1], r, r)
                b.prism(T(p[0], 0, p[1]) @ Ry(rng.uniform(0, 3)), poly, g - 0.12, g + 0.02, 's3_stone')
                t += rng.uniform(0.62, 0.75)
            acc = 0.0
    return b


# ───────────────────────── 西崖木柵 ─────────────────────────
def build_fence(cols):
    b = Builder('fence_w', seed=221)
    rng = b.rng
    pts = [np.array(p, float) for p in L['fence_w']]
    posts = []
    for i in range(len(pts) - 1):
        a, c = pts[i], pts[i + 1]
        seg = float(np.linalg.norm(c - a))
        n = max(1, int(round(seg / 1.8)))
        for k in range(n):
            posts.append(a + (c - a) * (k / n))
    posts.append(pts[-1])
    tops = []
    for i, p in enumerate(posts):
        g = gy(p[0], p[1])
        h = 1.05 + rng.uniform(-0.04, 0.03)
        tilt = (rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03))
        M = T(p[0], g - 0.30 + (h + 0.30) / 2, p[1]) @ Rx(tilt[0]) @ Rz(tilt[1])
        b.box(M, 0.10, h + 0.30, 0.10, 's3_wood_old', bevel=0.012, grain='y')
        b.box(T(p[0], g + h + 0.015, p[1]), 0.13, 0.03, 0.13, 's3_wood_dark', bevel=0.008)
        tops.append((p, g))
    for i in range(len(tops) - 1):
        (pa, ga), (pc, gc) = tops[i], tops[i + 1]
        for hy in (0.42, 0.88):
            b.beam((pa[0], ga + hy, pa[1]), (pc[0], gc + hy, pc[1]), 0.06, 0.08, 's3_wood_old', ext=0.05)
        d = pc - pa
        Lh = float(np.linalg.norm(d))
        ang = math.atan2(d[0], d[1])
        mid = (pa + pc) / 2
        cols.append({'type': 'box', 'size': [0.14, 1.3, Lh + 0.1], 'pos': [float(mid[0]), (ga + gc) / 2 + 0.55, float(mid[1])], 'yaw': ang, 'note': '木柵'})
    return b


# ───────────────────────── 岩石 ─────────────────────────
def build_rock(name, seed, size, flat=1.0, sub=3):
    """icosphere ＋ 多尺度雜訊位移 ＋ 底面壓平；原點＝底面中心（略埋：底 −0.15·高）。"""
    rng = np.random.default_rng(seed)
    # icosphere
    t = (1 + 5 ** 0.5) / 2
    V = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    F = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
         (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    V = [np.array(v, float) / np.linalg.norm(v) for v in V]
    for _ in range(sub):
        cache = {}
        nf = []

        def mid(a, c):
            k = (min(a, c), max(a, c))
            if k not in cache:
                m = V[a] + V[c]
                V.append(m / np.linalg.norm(m))
                cache[k] = len(V) - 1
            return cache[k]
        for (a, c, d) in F:
            ab, cd, da = mid(a, c), mid(c, d), mid(d, a)
            nf += [(a, ab, da), (c, cd, ab), (d, da, cd), (ab, cd, da)]
        F = nf
    P = np.array(V)
    # 位移：幾個大切面（平面裁切）＋雜訊
    disp = np.ones(len(P))
    for k in range(7):
        n = rng.normal(size=3)
        n /= np.linalg.norm(n)
        d0 = rng.uniform(0.55, 0.85)
        proj = P @ n
        disp = np.minimum(disp, np.where(proj > d0, d0 / np.maximum(proj, 1e-6), 1.0))
    freqs = [(2.0, 0.10), (5.0, 0.045), (11.0, 0.02)]
    ph = rng.uniform(0, 10, size=(3, 3))
    for (f, a), p in zip(freqs, ph):
        disp = disp + a * np.sin(P[:, 0] * f + p[0]) * np.sin(P[:, 1] * f * 1.3 + p[1]) * np.sin(P[:, 2] * f * 0.9 + p[2])
    P = P * disp[:, None]
    P = P * np.array([size[0] / 2, size[1] / 2 * flat, size[2] / 2])
    ymin = P[:, 1].min()
    hgt = P[:, 1].max() - ymin
    P[:, 1] -= ymin + 0.15 * hgt
    # 底面壓平（埋在地下的部分）
    P[:, 1] = np.maximum(P[:, 1], -0.15 * hgt)
    b = Builder(name, seed=seed)
    for (a, c, d) in F:
        b.poly([P[a], P[c], P[d]], [(P[a][0], P[a][2]), (P[c][0], P[c][2]), (P[d][0], P[d][2])], 's3_stone_tri', True, 1.0)
    return b, {'size': [float(v) for v in (P.max(0) - P.min(0))], 'bury': float(0.15 * hgt)}


# ───────────────────────── Blender ─────────────────────────
def main():
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = {}
    for k, c in (('s3_stone', (0.5, 0.49, 0.46)), ('s3_stone_tri', (0.5, 0.49, 0.46)), ('s3_wood_old', (0.3, 0.23, 0.17)), ('s3_wood_dark', (0.17, 0.13, 0.1))):
        m = bpy.data.materials.new(k)
        m.diffuse_color = (c[0], c[1], c[2], 1.0)
        mats[k] = m
    cols = []
    info = {}
    builders = [build_stairs(cols), build_sando(), build_fence(cols)]
    rocks = [('rock_boulder_a', 301, (2.4, 1.6, 1.9), 1.0), ('rock_boulder_b', 302, (1.8, 1.3, 1.5), 1.0),
             ('rock_mid_a', 303, (1.1, 0.7, 0.9), 1.0), ('rock_mid_b', 304, (0.9, 0.6, 0.8), 1.0), ('rock_mid_c', 305, (1.2, 0.55, 0.8), 0.85),
             ('rock_small_a', 306, (0.5, 0.32, 0.42), 1.0), ('rock_small_b', 307, (0.42, 0.22, 0.38), 0.9), ('rock_flat_a', 308, (0.8, 0.25, 0.6), 0.8)]
    for (nm, sd, sz, fl) in rocks:
        rb, ri = build_rock(nm, sd, sz, fl)
        builders.append(rb)
        info[nm] = ri
    for b in builders:
        ob = s3b.to_blender(b, mats, ground_grime=False)
        if b.name.startswith('rock_'):
            for p in ob.data.polygons:
                p.use_smooth = True
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, b.name + '.glb'), export_format='GLB', use_selection=True,
                                  export_apply=True, export_image_format='NONE', export_vertex_color='ACTIVE', export_yup=True)
        lo, hi = b.bounds()
        info.setdefault(b.name, {})
        info[b.name].update({'tris': b.tri_count(), 'min': [float(v) for v in lo], 'max': [float(v) for v in hi]})
        print('[SITE] %-15s tris %6d  min %s  max %s' % (b.name, b.tri_count(), np.round(lo, 2), np.round(hi, 2)))
    json.dump({'collision': cols, 'info': info}, open(os.path.join(OUT, 'site.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, 'shrine_v3_site.blend'))
    print('[SITE] collision', len(cols))


if __name__ == '__main__':
    main()
