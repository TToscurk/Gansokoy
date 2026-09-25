"""人間之里 V2：入母屋・寄棟系屋根（梯形瓦面）與唐破風建構件（P5 R3 寺子屋起）。

v2_kit.tile_roof 只做矩形瓦面（切妻平入）；入母屋的下半、裳階（mokoshi）轉角是梯形。
這裡用同一套瓦貼圖對齊規則（matlib V2_Kawara：tile_u_m／columns／courses／crest_u）做「寬度隨坡長變化」的瓦面：
  - 欄（瓦筋）用全域固定格線，貼圖波峰對齊，不因梯形而扇形變形；
  - 每一段（瓦唇到瓦唇）左右各自裁到隅棟線；完整欄共用頂點（smooth），兩端裁切的小塊另外以平面多邊形補滿；
  - 隅棟蓋在裁切線上。
座標、UV、繞序慣例同 v2_kit.py（Godot 座標、glTF UV 左上原點、從外面看逆時針）。
"""
import math

import v2_kit as K
from v2_kit import X, Y, Z, add, mul, norm, sub, cross, dot


def _clip(poly, f, keep_ge):
    """Sutherland–Hodgman：(x, s) 多邊形對半平面 f(x, s) ≥ 0（keep_ge）或 ≤ 0 裁切。"""
    out = []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        fa, fb = f(*a), f(*b)
        ina = fa >= -1e-9 if keep_ge else fa <= 1e-9
        inb = fb >= -1e-9 if keep_ge else fb <= 1e-9
        if ina:
            out.append(a)
        if ina != inb:
            t = fa / (fa - fb)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def _clean(poly):
    """去掉重複點與共線點（避免 Blender 三角化出退化面）。"""
    p = []
    for q in poly:
        if not p or abs(q[0] - p[-1][0]) > 1e-5 or abs(q[1] - p[-1][1]) > 1e-5:
            p.append(q)
    if len(p) > 1 and abs(p[0][0] - p[-1][0]) < 1e-5 and abs(p[0][1] - p[-1][1]) < 1e-5:
        p.pop()
    changed = True
    while changed and len(p) >= 3:
        changed = False
        for i in range(len(p)):
            a, b, c = p[i - 1], p[i], p[(i + 1) % len(p)]
            cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
            if abs(cr) < 1e-7:
                p.pop(i)
                changed = True
                break
    return p


def _area(p):
    return 0.5 * abs(sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p))))


def oface(m, ps, want_n, mat, uvs, col=1.0, smooth=False):
    n = cross(sub(ps[1], ps[0]), sub(ps[2], ps[0]))
    if dot(n, want_n) < 0:
        ps, uvs = ps[::-1], uvs[::-1]
    m.face(m.verts(ps), mat, uvs, col, smooth)


def tile_band(m, origin, ax, dsl, n, xl, xr, S, kw, lod, mat='V2_Kawara', col=1.0, u_sign=1.0,
              amp=0.022, step=0.028, seg_per_col=2, ends=True, breaks=(), s_range=None):
    """梯形（或任意凸的左右邊界）桟瓦屋面。
    origin＝上緣 x＝0 的點；ax＝沿簷方向單位向量（從外面看向右）；dsl＝下坡單位向量；n＝外法線；
    xl(s)／xr(s)＝坡長 s 處沿 ax 的左右界（分段線性；轉折點列在 breaks）；S＝坡長。
    u＝u_sign·x／tile_u_m；v＝s／tile_m＋v0（v0 同 tile_roof：簷口落在最後一段的瓦唇前）。
    s_range＝(s0, s1)：只做這段坡長（左右界在 s0／s1 不連續時分兩次呼叫；v0 仍依全坡長 S，瓦列對齊）。"""
    tu, tv = kw['tile_u_m'], kw['tile_m']
    cols, cour = kw['columns'], kw['courses']
    crest = kw['crest_u']
    phi = 0.57
    v0 = ((0.98 + phi - S / tv * cour) % 1.0) / cour

    def P3(x, s, off):
        return add(add(origin, add(mul(ax, x), mul(dsl, s))), mul(n, off))

    def U(x):
        return u_sign * x / tu

    def V(s):
        return s / tv + v0

    def cor(x):
        return amp * math.cos(2 * math.pi * (U(x) - crest) * cols) if lod <= 1 else 0.0

    def q(s):
        return V(s) * cour - phi

    def frac(s):
        return q(s) - math.floor(q(s))

    s0, s1 = s_range if s_range else (0.0, S)
    brk = sorted(set([s0, s1] + [b for b in breaks if s0 < b < s1]))
    if lod >= 2:
        for a, b in zip(brk, brk[1:]):
            poly = _clean([(xl(a), a), (xr(a), a), (xr(b), b), (xl(b), b)])
            if len(poly) >= 3 and _area(poly) > 1e-6:
                ps = [P3(x, s, step * 0.5) for (x, s) in poly]
                oface(m, ps, n, mat, [(U(x), V(s)) for (x, s) in poly], col)
        return {'v0': v0}
    w = tu / cols / (seg_per_col if lod == 0 else 2)
    if lod == 1:
        edges = brk
        bounds = []
    else:
        k0 = math.ceil(q(s0) + 1e-6)
        bounds = []
        k = k0
        while True:
            s = ((k + phi) / cour - v0) * tv
            if s >= s1 - 1e-4:
                break
            if s > s0 + 1e-4:
                bounds.append(s)
            k += 1
        edges = sorted(set(brk + bounds))
    bset = set(bounds)
    nfaces = 0
    for a, b in zip(edges, edges[1:]):
        if b - a < 1e-4:
            continue
        if lod == 1:
            da = db = step * 0.5
        else:
            da = step * frac(a) if a not in bset else 0.0
            db = step if b in bset else (step * min(1.0, frac(b) + 0.02) if b == S else step * frac(b))

        def off(s, x):
            return da + (db - da) * (s - a) / (b - a) + cor(x)
        la, lb, ra, rb = xl(a), xl(b), xr(a), xr(b)
        # 內部完整欄（上下兩緣都在界內）：共用頂點網格
        i0 = math.ceil(max(la, lb) / w - 1e-9)
        i1 = math.floor(min(ra, rb) / w + 1e-9)
        if i1 > i0:
            ni = i1 - i0
            m.grid(lambda i, j: P3((i0 + i) * w, a if j == 0 else b, off(a if j == 0 else b, (i0 + i) * w)),
                   lambda i, j: (U((i0 + i) * w), V(a if j == 0 else b)), ni, 1, mat, col, n)
            nfaces += ni
            xin0, xin1 = i0 * w, i1 * w
        else:
            xin0 = xin1 = None
        # 兩端：界線到內部網格之間，逐欄裁切（平面多邊形）
        segs = []
        lo_all, hi_all = min(la, lb), max(ra, rb)
        if xin0 is None:
            segs.append((lo_all, hi_all))
        else:
            if xin0 > lo_all + 1e-6:
                segs.append((lo_all, xin0))
            if hi_all > xin1 + 1e-6:
                segs.append((xin1, hi_all))
        for (x0, x1) in segs:
            k = math.floor(x0 / w + 1e-9)
            while k * w < x1 - 1e-6:
                c0, c1 = max(k * w, x0), min((k + 1) * w, x1)
                k += 1
                if c1 - c0 < 1e-5:
                    continue
                poly = [(c0, a), (c1, a), (c1, b), (c0, b)]
                poly = _clip(poly, lambda x, s: x - (la + (lb - la) * (s - a) / (b - a)), True)
                if len(poly) >= 3:
                    poly = _clip(poly, lambda x, s: x - (ra + (rb - ra) * (s - a) / (b - a)), False)
                poly = _clean(poly) if len(poly) >= 3 else []
                if len(poly) < 3 or _area(poly) < 2e-5:
                    continue
                ps = [P3(x, s, off(s, x)) for (x, s) in poly]
                oface(m, ps, n, mat, [(U(x), V(s)) for (x, s) in poly], col)
                nfaces += 1
    # 瓦唇（段差面，朝下坡）
    if lod == 0:
        for s in bounds:
            l, r = xl(s), xr(s)
            i0 = math.ceil(l / w + 1e-9)
            i1 = math.floor(r / w - 1e-9)
            xs = [l] + [i * w for i in range(i0, i1 + 1)] + [r]
            xs = [x for i, x in enumerate(xs) if i == 0 or x - xs[i - 1] > 1e-4]
            if len(xs) < 2:
                continue
            m.grid(lambda i, j: P3(xs[i], s, cor(xs[i]) + (step if j == 0 else 0.0)),
                   lambda i, j: (U(xs[i]), V(s) - (0.004 if j == 0 else 0.0)), len(xs) - 1, 1, mat, col * 0.85, dsl)
        if ends and abs(s1 - S) < 1e-6:
            l, r = xl(S), xr(S)
            kmin = math.ceil((min(U(l), U(r)) - crest) * cols)
            kmax = math.floor((max(U(l), U(r)) - crest) * cols)
            for kk in range(kmin, kmax + 1):
                x = (crest + kk / cols) * tu / u_sign
                if x < l + 0.14 or x > r - 0.14:
                    continue
                c = P3(x, S, amp + step * 0.55)
                m.cyl(add(c, mul(dsl, -0.03)), add(c, mul(dsl, 0.02)), 0.068, 0.068, 10, mat, col * 0.9,
                      caps=(False, True))
    return {'v0': v0, 'courses': len(edges) - 1}


def under(m, origin, ax, dsl, n, xl, xr, S, breaks=(), depth=0.15, col=0.19, tile_w=1.2):
    """野地裏（屋面下的暗色木板，朝下）。"""
    brk = sorted(set([0.0, S] + [b for b in breaks if 0.0 < b < S]))
    for a, b in zip(brk, brk[1:]):
        poly = _clean([(xl(a), a), (xr(a), a), (xr(b), b), (xl(b), b)])
        if len(poly) < 3 or _area(poly) < 1e-6:
            continue
        ps = [add(add(origin, add(mul(ax, x), mul(dsl, s))), mul(n, -depth)) for (x, s) in poly]
        oface(m, ps, mul(n, -1.0), 'V2_Wood', [(x / tile_w, s / tile_w) for (x, s) in poly], col)


def hip_ridge(m, a, b, lod, w=0.30, h=0.20, col=0.6):
    """隅棟／降棟：瓦製角材＋頂部圓筒（a→b，a、b 為屋面上的點，自動往上墊高 h/2）。"""
    up = (0.0, 1.0, 0.0)
    a2, b2 = add(a, mul(up, h * 0.5)), add(b, mul(up, h * 0.5))
    m.beam(a2, b2, w, h, 'V2_Kawara', col, up=up)
    if lod == 0:
        m.cyl(add(a2, mul(up, h * 0.5)), add(b2, mul(up, h * 0.5)), 0.085, 0.085, 8, 'V2_Kawara', col * 0.92,
              caps=(True, True))


def karahafu(m, lod, cx, B, y_e, H, z0, z1, board_region, amat, carve=None, beam_y=None, post_x=None):
    """唐破風（棟與正面垂直）：斷面 y(x)＝y_e＋H·½(1＋cos(π·|x−cx|／B))（中央凸、兩端反翹）。
    z0＝後端（插入牆內）、z1＝前緣。回傳 yroof(x)。"""
    nseg = 28 if lod == 0 else (14 if lod == 1 else 6)
    TK = 2.4

    def yr(x):
        u = min(1.0, abs(x - cx) / B)
        return y_e + H * 0.5 * (1 + math.cos(math.pi * u))
    xs = [cx - B + 2 * B * i / nseg for i in range(nseg + 1)]
    arc = [0.0]
    for i in range(1, len(xs)):
        arc.append(arc[-1] + math.hypot(xs[i] - xs[i - 1], yr(xs[i]) - yr(xs[i - 1])))
    amid = arc[nseg // 2]
    lift = 0.06
    # 瓦面（u 沿 z＝簷方向；v 沿斷面弧長，中央為 0）
    m.grid(lambda i, j: (xs[i], yr(xs[i]) + lift, z0 if j == 0 else z1),
           lambda i, j: ((z0 if j == 0 else z1) / 4.24, abs(arc[i] - amid) / TK), nseg, 1, 'V2_Kawara', 0.9,
           (0.0, 1.0, 0.0), smooth=True)
    # 野地裏
    m.grid(lambda i, j: (xs[i], yr(xs[i]) - 0.14, z0 if j == 0 else z1),
           lambda i, j: (xs[i] / 1.2, (z0 if j == 0 else z1) / 1.2), nseg, 1, 'V2_Wood', 0.2,
           (0.0, -1.0, 0.0), smooth=False)
    # 棟（頂部沿 z 的圓筒）
    if lod <= 1:
        m.cyl((cx, yr(cx) + lift + 0.05, z0), (cx, yr(cx) + lift + 0.05, z1 + 0.02), 0.09, 0.09, 10 if lod == 0 else 6,
              'V2_Kawara', 0.55, caps=(False, True))
    # 唐破風板（前緣，朝 +z）：沿曲線的帶子，下緣 −0.30、上緣 +0.04
    u0, v0, u1, v1 = board_region
    m.grid(lambda i, j: (xs[i], yr(xs[i]) + (-0.30 if j == 0 else lift + 0.02), z1 + 0.012),
           lambda i, j: (u0 + (u1 - u0) * i / nseg, v1 if j == 0 else v0), nseg, 1, amat, 1.0, (0.0, 0.0, 1.0),
           smooth=False)
    # 兩側簷端（朝 ±x；內側也封，從跨內斜看不露背面）
    for s in (-1, 1):
        x = cx + s * B
        y = yr(x)
        q = [(x, y - 0.30, z0), (x, y - 0.30, z1 + 0.012), (x, y + lift + 0.02, z1 + 0.012), (x, y + lift + 0.02, z0)]
        uvq = [(0, 0), (1, 0), (1, 0.1), (0, 0.1)]
        oface(m, q, (float(s), 0.0, 0.0), 'V2_Wood', uvq, 0.3)
        oface(m, [(p[0] - s * 0.004, p[1], p[2]) for p in q], (-float(s), 0.0, 0.0), 'V2_Wood', uvq, 0.25)
    # 前緣板下的彫刻板（蟇股／兎の毛通し區）：虹梁頂 → 破風板下緣
    if carve is not None and beam_y is not None and lod <= 1:
        cu0, cv0, cu1, cv1 = carve
        px = post_x
        k = 16 if lod == 0 else 8
        cxs = [cx - px + 2 * px * i / k for i in range(k + 1)]
        m.grid(lambda i, j: (cxs[i], beam_y if j == 0 else yr(cxs[i]) - 0.30, z1 - 0.05),
               lambda i, j: (cu0 + (cu1 - cu0) * i / k, cv1 if j == 0 else cv0 + (cv1 - cv0) *
                             (1 - (yr(cxs[i]) - 0.30 - beam_y) / max(1e-3, yr(cx) - 0.30 - beam_y))),
               k, 1, amat, 1.0, (0.0, 0.0, 1.0), smooth=False)
    return yr
