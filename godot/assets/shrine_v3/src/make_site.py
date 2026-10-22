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
    b.box(T(0, P - 0.12, st['z_top'] - 0.30), W + 0.4, 0.24, 0.64, 's3_paving', bevel=0.02, col=stone_col(rng, 0.25))
    prev_y = P
    # 規格 §24：中央踩踏區苔 0–8%、邊緣 10–30%（苔量放在頂點色 a：踏面低、耳石高）
    for (za, zb, ytop, kind, fl) in segs:
        if kind == 'tread':
            split = rng.uniform(-0.25, 0.25)
            parts = [(-W / 2, split - 0.006), (split + 0.006, W / 2)]
            for (xa, xb) in parts:
                jy = rng.uniform(-0.006, 0.004)
                rot = rng.uniform(-0.006, 0.006)
                M = T((xa + xb) / 2, ytop - 0.12 + jy, (za + zb) / 2 - 0.01) @ Ry(rot)
                mo = rng.uniform(0.04, 0.2) if rng.random() > 0.07 else rng.uniform(0.5, 0.7)
                b.box(M, xb - xa, 0.24, (zb - za) + 0.07, 's3_paving', bevel=0.022, col=stone_col(rng, mo, (0.9, 1.04), 0.08))
        else:
            # 踊り場：兩列鋪石
            n_rows = 3
            dz = (zb - za) / n_rows
            for r in range(n_rows):
                cuts = sorted([-W / 2, W / 2] + [rng.uniform(-0.5, 0.5)] + ([rng.uniform(-1.2, -0.7)] if r % 2 else [rng.uniform(0.7, 1.2)]))
                for k in range(len(cuts) - 1):
                    xa, xb = cuts[k] + 0.006, cuts[k + 1] - 0.006
                    M = T((xa + xb) / 2, ytop - 0.11 + rng.uniform(-0.008, 0.004), za + dz * (r + 0.5))
                    e = abs((xa + xb) / 2) / (W / 2)
                    b.box(M, xb - xa, 0.22, dz - 0.012, 's3_paving', bevel=0.018, col=stone_col(rng, 0.1 + 0.45 * e * e, (0.9, 1.04), 0.08))
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
            sloped_block(b, min(xa, xb), max(xa, xb), z, z1 - 0.01, yt0, yt1, 0.55, 's3_paving', stone_col(rng, rng.uniform(0.55, 0.9), (0.85, 1.0), 0.15))
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


# ───────────────────────── 參道（美術深化 2026-10-22） ─────────────────────────
# 規格 HAKUREI_SHRINE_AREA_SPEC §21–22：主石 寬 0.35–0.70 × 長 0.45–0.90、厚 0.08–0.16；縫 2–8 cm；旋轉 ±3–8°（不規則石）；
# 高低 ±1–3.5 cm；苔 5–18%、濕暗 5–15%、缺角／破石 5–12%、下沉 3–10%；不得同尺寸、等距、棋盤格。
# 鳥居端＝自然不規則石（Voronoi 切塊）→ 中段＝切石成排錯縫 → 拜殿前台＝較規整的成排切石。
TOOLS = os.path.join(GODOT, 'tools', 'shrine_v3')
sys.path.insert(0, TOOLS)
import layout as LY  # noqa: E402


def stone_col(rng, moss, base=(0.92, 1.05), damp_p=0.10):
    """每塊石頭的 (r, g, b, 苔量)。濕暗 10%：整塊壓暗。"""
    t = rng.uniform(*base)
    if rng.random() < damp_p:
        t *= rng.uniform(0.74, 0.84)
    return (t * rng.uniform(0.97, 1.03), t * rng.uniform(0.97, 1.02), t * rng.uniform(0.96, 1.03), max(0.0, min(1.0, moss)))


def _shrink(poly, d):
    cx = sum(p[0] for p in poly) / len(poly)
    cz = sum(p[1] for p in poly) / len(poly)
    out = []
    for (x, z) in poly:
        L_ = math.hypot(x - cx, z - cz)
        k = max(0.0, 1.0 - d / max(L_, 1e-6))
        out.append((cx + (x - cx) * k, cz + (z - cz) * k))
    return out


def _ccw(poly):
    a = 0.0
    for i in range(len(poly)):
        x0, z0 = poly[i]
        x1, z1 = poly[(i + 1) % len(poly)]
        a += x0 * z1 - x1 * z0
    return poly if a < 0 else poly[::-1]     # 由 +y 往下看逆時針（xz 平面 z 朝下）＝ 有號面積 < 0


def slab(b, poly, cx, cz, ytop, thick, col, yaw=0.0, tilt=(0.0, 0.0), ch=0.016, mat='s3_paving'):
    """局部 xz 多邊形（以 (0,0) 為中心）→ 頂面倒角的石塊；頂面在 ytop，往下 thick。每塊 UV 隨機偏移。"""
    M = T(cx, ytop, cz) @ Ry(yaw) @ Rx(tilt[0]) @ Rz(tilt[1])
    rng = b.rng
    uo = (rng.uniform(0, 9), rng.uniform(0, 9))
    poly = _ccw(list(poly))
    inner = _shrink(poly, ch)
    y0, ysh, y1 = -thick, -ch, 0.0
    n = len(poly)
    s = 0.0
    cen_mid = np.array([sum(p[0] for p in poly) / n, (y0 + ysh) / 2, sum(p[1] for p in poly) / n])
    for i in range(n):
        a = poly[i]
        c = poly[(i + 1) % n]
        Lw = math.hypot(c[0] - a[0], c[1] - a[1])
        wall = [[a[0], y0, a[1]], [c[0], y0, c[1]], [c[0], ysh, c[1]], [a[0], ysh, a[1]]]
        uv = [(s + uo[0], y0 + uo[1]), (s + Lw + uo[0], y0 + uo[1]), (s + Lw + uo[0], ysh + uo[1]), (s + uo[0], ysh + uo[1])]
        P_ = np.array(wall)
        if np.dot(np.cross(P_[1] - P_[0], P_[2] - P_[0]), (P_[0] + P_[1]) * 0.5 - cen_mid) < 0:
            wall, uv = wall[::-1], uv[::-1]
        b.poly(s3b._xf(M, wall), uv, mat, False, col)
        ia, ic = inner[i], inner[(i + 1) % n]
        chq = [[a[0], ysh, a[1]], [c[0], ysh, c[1]], [ic[0], y1, ic[1]], [ia[0], y1, ia[1]]]
        P_ = np.array(chq)
        nn = np.cross(P_[1] - P_[0], P_[2] - P_[0])
        if np.dot(nn, np.array([(a[0] + c[0]) / 2 - cen_mid[0], 0.6, (a[1] + c[1]) / 2 - cen_mid[2]])) < 0:
            chq = chq[::-1]
        b.poly(s3b._xf(M, chq), [(p[0] + uo[0], p[2] + uo[1]) for p in chq], mat, False, col)
        s += Lw
    top = [[p[0], y1, p[1]] for p in inner]
    P_ = np.array(top)
    if np.cross(P_[1] - P_[0], P_[2] - P_[0])[1] < 0:
        top = top[::-1]
    b.poly(s3b._xf(M, top), [(p[0] + uo[0], p[2] + uo[1]) for p in top], mat, False, col)


def _chip(rng, poly):
    """缺角：把一個角切掉成兩點。"""
    i = rng.randrange(len(poly))
    a = poly[i - 1]
    p = poly[i]
    c = poly[(i + 1) % len(poly)]
    k1 = rng.uniform(0.12, 0.3)
    k2 = rng.uniform(0.12, 0.3)
    q1 = (p[0] + (a[0] - p[0]) * k1, p[1] + (a[1] - p[1]) * k1)
    q2 = (p[0] + (c[0] - p[0]) * k2, p[1] + (c[1] - p[1]) * k2)
    return poly[:i] + [q1, q2] + poly[i + 1:]


def _clip_half(poly, nx, nz, d):
    """保留 nx·x + nz·z <= d 的部分（Sutherland–Hodgman）。"""
    out = []
    n = len(poly)
    for i in range(n):
        p = poly[i]
        q = poly[(i + 1) % n]
        fp = nx * p[0] + nz * p[1] - d
        fq = nx * q[0] + nz * q[1] - d
        if fp <= 0:
            out.append(p)
        if (fp <= 0) != (fq <= 0):
            t = fp / (fp - fq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def put_stone(b, poly_w, kind, moss, rng, stats, ch=0.008, thick=None, sink_p=0.06, broken_p=0.08, chip_p=0.06, rot=(1.0, 2.5), base=(0.92, 1.05)):
    """世界座標多邊形 → 石塊（隨機：旋轉、高低、下沉、缺角、破成兩塊）。"""
    cx = sum(p[0] for p in poly_w) / len(poly_w)
    cz = sum(p[1] for p in poly_w) / len(poly_w)
    loc = [(p[0] - cx, p[1] - cz) for p in poly_w]
    hw = max(max(abs(p[0]) for p in loc), 0.05)
    hd = max(max(abs(p[1]) for p in loc), 0.05)
    g = foot_max(cx, cz, hw, hd)
    # 審圖 r1：頂面高出地面 3 cm＋倒角陰影 → 每塊都像「擺在地上」。改成只高出 ~1.4 cm、下沉的與地面齊平
    dy = rng.uniform(-0.006, 0.006)
    if rng.random() < sink_p:
        dy = -rng.uniform(0.006, 0.01)        # 審圖 r3：沉到 −1.2～−2 cm 會被地形蓋住（讀成「缺一塊石頭」）→ 只比鄰石低 0.6–1 cm
        stats['sunk'] += 1
    yaw = math.radians(rng.uniform(-rot[1], rot[1]) if rng.random() < 0.5 else rng.uniform(-rot[0], rot[0]))
    tilt = (math.radians(rng.uniform(-0.4, 0.4)), math.radians(rng.uniform(-0.4, 0.4)))
    th = thick if thick is not None else rng.uniform(0.10, 0.14)
    col = stone_col(rng, moss, base)
    if col[0] < 0.85 * base[0]:
        stats['damp'] += 1
    if rng.random() < chip_p and len(loc) >= 4:
        loc = _chip(rng, loc)
        stats['chipped'] += 1
    if rng.random() < broken_p and len(loc) >= 4:
        # 破成兩塊：隨機斜線切開，縫 1.5 cm，兩半各自微沉
        ang = rng.uniform(0, math.pi)
        nx, nz = math.cos(ang), math.sin(ang)
        for sgn in (1, -1):
            half = _clip_half(loc, sgn * nx, sgn * nz, -0.0075)
            if len(half) >= 3:
                slab(b, half, cx, cz, g + 0.014 + dy - rng.uniform(0.0, 0.008), th, col, yaw, tilt, ch)
        stats['broken'] += 1
    else:
        slab(b, loc, cx, cz, g + 0.014 + dy, th, col, yaw, tilt, ch)
    stats['n'] += 1
    stats['area'] += abs(sum(loc[i][0] * loc[(i + 1) % len(loc)][1] - loc[(i + 1) % len(loc)][0] * loc[i][1] for i in range(len(loc)))) * 0.5


def voronoi_cells(sites, box):
    """sites：[(x,z)]；box：(x0,x1,z0,z1)。回傳每個 site 的凸多邊形（半平面裁切）。"""
    x0, x1, z0, z1 = box
    cells = []
    for i, (sx, sz) in enumerate(sites):
        poly = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
        for j, (tx, tz) in enumerate(sites):
            if i == j or abs(tx - sx) > 1.6 or abs(tz - sz) > 1.6:
                continue
            nx, nz = tx - sx, tz - sz
            d = (tx * tx + tz * tz - sx * sx - sz * sz) * 0.5
            poly = _clip_half(poly, nx, nz, d)
            if len(poly) < 3:
                break
        cells.append(poly)
    return cells


def rows_band(rng, z_top, z_bot, hw_fn, dz_rng, w_rng, edge_jit, prev_cuts_tol=0.11, stagger=False):
    """成排切石：回傳 [世界多邊形]。z 由 z_top 往 z_bot（遞減）；每排依 hw_fn(z 中) 決定寬；接縫錯開。"""
    out = []
    z = z_top
    prev = []
    row = 0
    while z > z_bot + 0.05:
        dz = min(rng.uniform(*dz_rng), z - z_bot)
        if z - dz - z_bot < 0.25:
            dz = z - z_bot
        zc = z - dz / 2
        hw = hw_fn(zc)
        if hw <= 0.05:
            z -= dz
            continue
        xl = -hw - rng.uniform(-edge_jit, edge_jit)
        xr = hw + rng.uniform(-edge_jit, edge_jit)
        cuts = [xl]
        x = xl
        if stagger and row % 2 == 1:
            x += rng.uniform(*w_rng) * 0.5
            if x < xr - 0.3:
                cuts.append(x)
        while True:
            for _ in range(8):
                w = rng.uniform(*w_rng)
                nxt = x + w
                if all(abs(nxt - c) > prev_cuts_tol for c in prev):
                    break
            if nxt >= xr - w_rng[0] * 0.6:
                break
            cuts.append(nxt)
            x = nxt
        cuts.append(xr)
        for k in range(len(cuts) - 1):
            ga = rng.uniform(0.008, 0.018)
            gz = rng.uniform(0.008, 0.018)
            xa, xb = cuts[k] + ga, cuts[k + 1] - ga
            za, zb = z - gz, z - dz + gz
            out.append([(xa, za), (xb, za), (xb, zb), (xa, zb)])
        prev = cuts[1:-1]
        z -= dz
        row += 1
    return out


def build_sando():
    b = Builder('sando', seed=211)
    rng = b.rng
    sd = L['sando']
    st = {'n': 0, 'area': 0.0, 'sunk': 0, 'damp': 0, 'chipped': 0, 'broken': 0, 'edge_small': 0, 'aux': 0}

    def moss_for(x, hw, base_lo, base_hi):
        e = min(abs(x) / max(hw, 0.3), 1.0)             # 0 中央 → 1 外緣
        m = base_lo + (base_hi - base_lo) * e * e
        if rng.random() < 0.10:
            m = rng.uniform(0.75, 0.95)                 # 長滿苔的石（多在邊上）
        return m

    # 1) 鳥居端：自然不規則石（Voronoi）
    z_a, z_b = sd['nat_z'], sd['z0']
    sites = []
    zz = z_b - 0.25
    while zz > z_a + 0.15:
        xx = -1.45 + rng.uniform(0.0, 0.3)
        while xx < 1.45:
            sites.append((xx + rng.uniform(-0.12, 0.12), zz + rng.uniform(-0.12, 0.12)))
            xx += rng.uniform(0.48, 0.62)
        zz -= rng.uniform(0.46, 0.6)
    for poly in voronoi_cells(sites, (-1.6, 1.6, z_a, z_b)):
        if len(poly) < 3:
            continue
        cz = sum(p[1] for p in poly) / len(poly)
        hw = LY.sando_hw(min(max(cz, z_a), z_b)) + rng.uniform(-0.05, 0.06)
        poly = _clip_half(poly, 1.0, 0.0, hw)
        poly = _clip_half(poly, -1.0, 0.0, hw)
        if len(poly) < 3:
            continue
        poly = _shrink(poly, rng.uniform(0.012, 0.026))
        cx = sum(p[0] for p in poly) / len(poly)
        area = abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))) * 0.5
        if area < 0.035:
            continue
        # 審圖 r3：主要的「浮起」感來自倒角＋側面在陰影裡的深色邊帶 → 倒角 1.8 → 0.9 cm
        put_stone(b, poly, 'nat', moss_for(cx, hw, 0.12, 0.6), rng, st, ch=0.009, rot=(3.0, 8.0), base=(0.86, 1.0))
    # 2) 中段：切石成排、錯縫
    for poly in rows_band(rng, sd['nat_z'], sd['fan_z0'], LY.sando_hw, (0.48, 0.85), (0.38, 0.70), 0.07):
        cx = sum(p[0] for p in poly) / 4
        put_stone(b, poly, 'mid', moss_for(cx, sd['mid_hw'], 0.06, 0.55), rng, st)
    # 3) 漸寬＋拜殿前台：較規整（成排錯縫，石較大、旋轉小）
    for poly in rows_band(rng, sd['fan_z0'], sd['z1'], LY.sando_hw, (0.5, 0.7), (0.45, 0.75), 0.03, stagger=True):
        cx = sum(p[0] for p in poly) / 4
        put_stone(b, poly, 'apron', moss_for(cx, LY.sando_hw((poly[0][1] + poly[2][1]) / 2), 0.08, 0.45), rng, st,
                  sink_p=0.03, broken_p=0.04, chip_p=0.04, rot=(0.3, 0.8), base=(0.95, 1.07))
    # 4) 邊緣：碎石／輔石帶（主石帶外 0.04–0.35 m；稀疏，打斷直線邊）。避開鳥居石台、階頂收邊石、燈籠／狛犬台座。
    keep_out = [(float(v[0]), float(v[1]), 0.8) for k, v in L['place'].items() if k.startswith('lantern') or k.startswith('komainu')]
    keep_out += [(-1.7, 7.4, 0.75), (1.7, 7.4, 0.75)]
    z = sd['z0'] - 0.45
    while z > sd['z1'] + 0.3:
        hw = LY.sando_hw(z)
        for sgn in (-1, 1):
            if hw >= sd['apron_hw'] - 0.01 and rng.random() < 0.5:
                continue
            if rng.random() < 0.55:
                r = rng.uniform(0.06, 0.16)
                x = sgn * (hw + rng.uniform(0.06, sd['edge_w']))
                if any(math.hypot(x - kx, z - kz) < kr for (kx, kz, kr) in keep_out):
                    continue
                nv = rng.randint(6, 8)
                poly = [(x + math.cos(k * 2 * math.pi / nv) * r * rng.uniform(0.75, 1.1),
                         z + math.sin(k * 2 * math.pi / nv) * r * rng.uniform(0.7, 1.05)) for k in range(nv)]
                put_stone(b, poly, 'edge', rng.uniform(0.35, 0.8), rng, st, ch=0.012, thick=0.07, sink_p=0.1, broken_p=0.0, chip_p=0.0, rot=(5, 20), base=(0.8, 0.98))
                st['edge_small'] += 1
            if rng.random() < 0.12:
                # 輔石：半壓在主石帶邊、半在外（打斷筆直邊線）
                r = rng.uniform(0.2, 0.3)
                x = sgn * (hw + rng.uniform(0.1, 0.22))
                if any(math.hypot(x - kx, z - kz) < kr + 0.2 for (kx, kz, kr) in keep_out):
                    continue
                nv = rng.randint(6, 8)
                poly = [(x + math.cos(k * 2 * math.pi / nv) * r * rng.uniform(0.8, 1.08),
                         z + math.sin(k * 2 * math.pi / nv) * r * rng.uniform(0.7, 1.0)) for k in range(nv)]
                put_stone(b, poly, 'aux', rng.uniform(0.4, 0.85), rng, st, ch=0.02, rot=(4, 12), base=(0.84, 1.0))
                st['aux'] += 1
        z -= rng.uniform(0.32, 0.5)
    # 5) 手水舍石台（較小的切石，成排）
    tx0, tx1, tz0, tz1 = L['temizuya_pad']
    pad_cx = (tx0 + tx1) / 2

    def pad_hw(zc):
        return (tx1 - tx0) / 2 if tz0 <= zc <= tz1 else 0.0
    for poly in rows_band(rng, tz1, tz0, pad_hw, (0.36, 0.55), (0.32, 0.55), 0.04):
        poly = [(p[0] + pad_cx, p[1]) for p in poly]
        put_stone(b, poly, 'pad', rng.uniform(0.25, 0.7), rng, st, sink_p=0.05, broken_p=0.05, chip_p=0.05, base=(0.85, 1.0))
    # 6) 飛石：參道→手水舍、拜殿前台→倉庫
    for key in ('to_temizuya', 'to_store'):
        pts = [np.array(p, float) for p in L['paths'][key]]
        for i in range(len(pts) - 1):
            a, c = pts[i], pts[i + 1]
            seg = float(np.linalg.norm(c - a))
            t = 0.0 if i == 0 else rng.uniform(0.1, 0.25)
            while t < seg:
                p = a + (c - a) * (t / seg) + np.array([rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08)])
                r = rng.uniform(0.24, 0.32)
                poly = [(p[0] + math.cos(k * 2 * math.pi / 9) * r * rng.uniform(0.85, 1.1), p[1] + math.sin(k * 2 * math.pi / 9) * r * rng.uniform(0.8, 1.05)) for k in range(9)]
                put_stone(b, poly, 'tobi', rng.uniform(0.3, 0.75), rng, st, ch=0.025, thick=0.14, broken_p=0.0, rot=(0, 30), base=(0.86, 1.0))
                t += rng.uniform(0.62, 0.75)
    print('[SITE] sando stones %(n)d area %(area).1f m2 sunk %(sunk)d damp %(damp)d chipped %(chipped)d broken %(broken)d edge %(edge_small)d aux %(aux)d' % st)
    b.stats = st
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
    for k, c in (('s3_stone', (0.5, 0.49, 0.46)), ('s3_stone_tri', (0.5, 0.49, 0.46)), ('s3_paving', (0.55, 0.54, 0.51)), ('s3_wood_old', (0.3, 0.23, 0.17)), ('s3_wood_dark', (0.17, 0.13, 0.1))):
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
        s3b.export_glb(os.path.join(OUT, b.name + '.glb'), export_format='GLB', use_selection=True,
                       export_apply=True, export_image_format='NONE', export_vertex_color='ACTIVE', export_yup=True)
        lo, hi = b.bounds()
        info.setdefault(b.name, {})
        info[b.name].update({'tris': b.tri_count(), 'min': [float(v) for v in lo], 'max': [float(v) for v in hi]})
        print('[SITE] %-15s tris %6d  min %s  max %s' % (b.name, b.tri_count(), np.round(lo, 2), np.round(hi, 2)))
    s3b.dump_json({'collision': cols, 'info': info}, os.path.join(OUT, 'site.json'), ensure_ascii=False, indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, 'shrine_v3_site.blend'))
    print('[SITE] collision', len(cols))


if __name__ == '__main__':
    main()
