"""人間之里 V2 P9 R4：稗田邸庭園 Kit（garden_kit）— 新資產（石燈籠、蹲踞、延段、飛石、景石、竹垣、石橋、雨落ち縁石）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_garden_kit.py

設計（ART-FIRST，參考 docs/reference/重點地標/裨田邸正面*.PNG（前庭：切石延段、苔目地、門前燈籠、松）、
裨田後.PNG（後庭：池、石組、春日／雪見系石燈籠、雲團松、苔）、§31.2 稗田邸庭園規格）：
  - 只用共享材質：石＝machiya_kit/V2_KitStoneTri（V2_Stone 貼圖、world triplanar，石紋跨構件連續）、木＝V2_Wood、
    竹＝bamboo_kit BK_Culm_dead（P9 R3 已核准的晒し竹貼圖）、水＝garden_kit/GK_Water（新：蹲踞水面）。不新增貼圖。
  - 構件只存一次（assets/village_v2/garden_kit/mesh/<名>.res）；擺放＝tools/village_v2_hieda_garden_lib.gd。
座標：Godot（x 右、y 上、+z 前＝使用者／參道側）；原點＝接地點（y 0＝設計地面），基礎往下埋；單位 m。
  gk_toro_kasuga  春日燈籠 高 1.96（基礎埋 0.12）     gk_toro_yukimi 雪見燈籠 高 1.00、笠徑 1.1（三脚）
  gk_toro_oribe   織部燈籠 高 1.32（竿直接埋 0.35）  gk_tsukubai    蹲踞（手水鉢＋前石＋手燭石＋湯桶石＋海＋筧）
  gk_nobe_a..c    延段 1.4（x 沿路）× 1.2（z 路寬），頂 +0.035、厚 0.18（切石＋自然石混用）
  gk_tobi_a..d    飛石 徑 0.45–0.70，頂 +0.06        gk_kei_tall／mid／low／flat 景石（立石／中石／低石／伏石）
  gk_yotsume      四つ目垣 1.8 m（親柱 ±0.9、胴縁 4 段、立子 0.3 m）  gk_sodegaki 袖垣 1.0 × 1.7
  gk_bridge       石橋（切石一枚）1.8 × 0.55 × 0.2    gk_amaochi      雨落ち縁石 0.9 × 0.1
  *_l1            LOD1
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/garden_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
ST = 'V2_KitStoneTri'
WD = 'V2_Wood'
BC = 'BK_Culm_dead'
WT = 'GK_Water'
FL = 'GK_Falls'
MATS = [ST, WD, BC, WT, FL]
TILE = {ST: ML['V2_Stone']['tile_m'], WD: ML['V2_Wood']['tile_m'], BC: 1.0, WT: 1.0, FL: 1.0}

GRANITE = [(0.98, 0.97, 0.94), (1.04, 1.02, 0.97), (0.92, 0.93, 0.94), (0.88, 0.86, 0.82), (1.0, 0.97, 0.90)]
LANTERN = (1.22, 1.19, 1.12)      # 花崗岩燈籠：比護岸石亮（逆光下仍讀得出輪廓）
MOSSY = (0.80, 0.90, 0.70)
DARK = 0.22          # 火口・手水鉢內壁
ROPE = (0.10, 0.09, 0.08)
INTERNODE = 0.3      # 竹 UV：一個節間（v 方向重複）

MODS = {}
INFO = {}


def new(name, note=''):
    m = K.Mesh(name, MATS, TILE)
    MODS[name] = m
    INFO[name] = note
    return m


def tint(rng, base=None):
    t = base or rng.choice(GRANITE)
    k = rng.uniform(0.93, 1.05)
    return (t[0] * k, t[1] * k, t[2] * k)


# ─────────────────────────── 基本形 ───────────────────────────

def ring(n, r, y, phase=0.0, rx=None, rz=None):
    """俯視逆時針（Godot x 右、z 前 → 角度往 −z 轉）：側面外法線朝外、上蓋朝上（與 v2_kit 繞序慣例一致）。"""
    return [(math.cos(phase + 2 * math.pi * i / n) * (rx or r), y, -math.sin(phase + 2 * math.pi * i / n) * (rz or r))
            for i in range(n)]


def poly_w(m, ps, mat, col, want):
    """依期望法線 want 自動決定繞序（內凹面、火口、手水鉢內壁用）。"""
    n = K.cross(K.sub(ps[1], ps[0]), K.sub(ps[2], ps[0]))
    if K.dot(n, want) < 0:
        ps = list(reversed(ps))
    m.poly(ps, mat, col)


def loft(m, rings, mat, col, cap_bot=True, cap_top=True, cols=None):
    """同頂點數的環列（由下而上）→ 側面＋上下蓋。cols：每段顏色（可選）。"""
    n = len(rings[0])
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        c = cols[k] if cols else col
        for i in range(n):
            j = (i + 1) % n
            m.poly([a[i], a[j], b[j], b[i]], mat, c)
    if cap_bot:
        m.poly(list(reversed(rings[0])), mat, col)
    if cap_top:
        m.poly(list(rings[-1]), mat, col)


def prism(m, n, r0, r1, y0, y1, mat, col, phase=0.0, caps=(True, True)):
    loft(m, [ring(n, r0, y0, phase), ring(n, r1, y1, phase)], mat, col, caps[0], caps[1])


def culm(m, p0, p1, r, lod, seg=None):
    """竹材（BK_Culm_dead）：u＝周、v＝節間（每 INTERNODE m 重複）。"""
    L = math.dist(p0, p1)
    m.cyl(p0, p1, r, r, seg or (4 if lod else 6), BC, (0.78, 0.74, 0.66), caps=(False, True),
          uv_atlas=(0.0, 0.0, 1.0, L / INTERNODE))


def outline(rng, w, h, n=8, p=3.2, jit=0.08):
    pts = []
    for i in range(n):
        a = 2 * math.pi * (i + rng.uniform(-0.16, 0.16)) / n + math.pi / n
        c, s = math.cos(a), math.sin(a)
        u = math.copysign(abs(c) ** (2 / p), c) * w / 2 * (1 + rng.uniform(-jit, jit))
        v = math.copysign(abs(s) ** (2 / p), s) * h / 2 * (1 + rng.uniform(-jit, jit))
        pts.append((u, v))
    return pts


def slab(m, cx, cz, top, w, d, th, bulge, rng, col, lod, n=7, p=3.0, jit=0.07, chamf=0.03, yaw=0.0):
    """平石（x-z 面、+y 外露）：頂 top、厚 th（往下）。"""
    if lod >= 1:
        n = 5
    O = outline(rng, w, d, n, p, jit)
    cy, sy = math.cos(yaw), math.sin(yaw)

    def P(u, v, y, k=1.0):
        uu, vv = u * k, v * k
        return (cx + uu * cy - vv * sy, y, cz - (uu * sy + vv * cy))
    if lod >= 1:
        m.poly([P(u, v, top) for u, v in O], ST, col)
        for i in range(n):
            j = (i + 1) % n
            m.poly([P(*O[i], top), P(*O[i], top - th), P(*O[j], top - th), P(*O[j], top)], ST, col)
        return
    c = P(rng.uniform(-0.03, 0.03) * w, rng.uniform(-0.03, 0.03) * d, top + bulge)
    ri = [P(u, v, top + bulge * 0.6 + rng.uniform(-0.004, 0.004), 0.8) for u, v in O]
    ro = [P(u, v, top - chamf) for u, v in O]
    bt = [P(u, v, top - th, 0.97) for u, v in O]
    for i in range(n):
        j = (i + 1) % n
        m.poly([c, ri[i], ri[j]], ST, col)
        m.poly([ri[i], ro[i], ro[j], ri[j]], ST, col)
        m.poly([ro[i], bt[i], bt[j], ro[j]], ST, col)


OCTA_V = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
OCTA_F = [(0, 2, 4), (4, 2, 1), (1, 2, 5), (5, 2, 0), (4, 3, 0), (1, 3, 4), (5, 3, 1), (0, 3, 5)]


def sphere(level):
    V = [tuple(v) for v in OCTA_V]
    F = list(OCTA_F)
    for _ in range(level):
        cache = {}
        nf = []

        def mid(a, b):
            k = (min(a, b), max(a, b))
            if k not in cache:
                V.append(K.norm(K.mul(K.add(V[a], V[b]), 0.5)))
                cache[k] = len(V) - 1
            return cache[k]
        for a, b, c in F:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)]
        F = nf
    return V, F


def rock(m, center, size, rng, col, level, amp=0.14, facet=0.0, bury=0.3, top_col=None):
    """景石：size＝(半寬, 露出高, 半深)。bury＝埋入比例（總高）。facet＞0 → 頂面削平（伏石、天端）。
    top_col：上半部頂點色（苔）。原點＝接地線（y 0），頂＝露出高。"""
    V, F = sphere(level)
    dirs = [K.norm((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) for _ in range(4)]
    fq = [rng.uniform(1.4, 3.4) for _ in range(4)]
    ph = [rng.uniform(0, 6.28) for _ in range(4)]
    am = [amp, amp * 0.6, amp * 0.35, amp * 0.5]
    total = size[1] / (1.0 - bury)
    P = []
    for v in V:
        r = 1.0 + sum(am[k] * math.sin(fq[k] * K.dot(v, dirs[k]) * 3.0 + ph[k]) for k in range(4))
        # 稜角：方向量化（割石感）
        x, y, z = v[0] * r * size[0], v[1] * r * total * 0.5, v[2] * r * size[2]
        if facet > 0 and y > total * 0.5 * (1 - facet):
            y = total * 0.5 * (1 - facet) + (y - total * 0.5 * (1 - facet)) * 0.15
        P.append((x, y, z))
    lo = min(p[1] for p in P)
    hi = max(p[1] for p in P)
    dy = -bury * (hi - lo) - lo
    P = [(center[0] + p[0], center[1] + p[1] + dy, center[2] + p[2]) for p in P]
    idx = m.verts(P)
    t = m.tile[ST]
    mid_y = center[1] + (hi - lo) * (1 - bury) * 0.55
    for a, b, c in F:
        cc = col
        if top_col and min(P[a][1], P[b][1], P[c][1]) > mid_y:
            cc = top_col
        m.face([idx[a], idx[b], idx[c]], ST, [(P[q][0] / t, -P[q][2] / t) for q in (a, b, c)], cc, smooth=True)


# ─────────────────────────── 石燈籠 ───────────────────────────

def hex_roof(m, y0, r_eave, y_apex, r_top, lod, col, warabi=0.05, th=0.05, n=6, phase=0.0):
    """六角（n 角）笠：下面平、軒口厚 th、屋面二段（軒→中段→頂）、軒端蕨手上翹。"""
    eave = ring(n, r_eave, y0 + th, phase)
    eave = [(p[0], p[1] + warabi, p[2]) for p in eave]               # 角端上翹（蕨手）
    eave_b = [(p[0], p[1] - th, p[2]) for p in eave]
    under = ring(n, r_eave * 0.92, y0, phase)
    loft(m, [under, eave_b, eave], ST, col, cap_bot=True, cap_top=False)
    if lod:
        top = ring(n, r_top, y_apex, phase)
        loft(m, [eave, top], ST, col, cap_bot=False, cap_top=True)
        return
    # 屋面：角稜線往上凹（照り）→ 中段環
    mid = ring(n, r_eave * 0.55, y0 + th + (y_apex - y0 - th) * 0.62, phase)
    top = ring(n, r_top, y_apex, phase)
    # 角間中點下垂（屋面凹曲）
    eave2 = []
    mid2 = []
    for i in range(n):
        j = (i + 1) % n
        eave2.append(eave[i])
        e = K.lerp(eave[i], eave[j], 0.5)
        eave2.append((e[0] * 0.97, e[1] - warabi * 0.9, e[2] * 0.97))
        mid2.append(mid[i])
        mm = K.lerp(mid[i], mid[j], 0.5)
        mid2.append((mm[0], mm[1] - 0.008, mm[2]))
    top2 = []
    for i in range(n):
        top2.append(top[i])
        top2.append(K.lerp(top[i], top[(i + 1) % n], 0.5))
    # 軒口：中點版本的外緣
    loft(m, [eave2, mid2, top2], ST, col, cap_bot=False, cap_top=True)


def hibukuro(m, n, r, y0, y1, lod, col, window_faces, phase=0.0):
    """火袋：n 角柱，指定面開火口（暗色內凹）。"""
    a = ring(n, r, y0, phase)
    b = ring(n, r, y1, phase)
    for i in range(n):
        j = (i + 1) % n
        if lod or i not in window_faces:
            m.poly([a[i], a[j], b[j], b[i]], ST, col)
            continue
        # 框 0.22 寬比、上下 0.15；中央內凹 0.03（暗色）
        def L(p, q, t):
            return K.lerp(p, q, t)
        f = 0.22
        h0, h1 = 0.15, 0.85
        a0, a1 = L(a[i], a[j], f), L(a[i], a[j], 1 - f)
        b0, b1 = L(b[i], b[j], f), L(b[i], b[j], 1 - f)
        c00, c01 = L(a0, b0, h0), L(a1, b1, h0)
        c10, c11 = L(a0, b0, h1), L(a1, b1, h1)
        o00, o01, o10, o11 = L(a[i], b[i], h0), L(a[j], b[j], h0), L(a[i], b[i], h1), L(a[j], b[j], h1)
        m.poly([a[i], a[j], o01, o00], ST, col)
        m.poly([o10, o11, b[j], b[i]], ST, col)
        m.poly([o00, c00, c10, o10], ST, col)
        m.poly([c01, o01, o11, c11], ST, col)
        nrm = K.norm(K.sub(K.lerp(a[i], a[j], 0.5), (0.0, a[i][1], 0.0)))
        inset = K.mul(nrm, -0.035)
        d00, d01, d10, d11 = [K.add(p, inset) for p in (c00, c01, c10, c11)]
        along = K.norm(K.sub(a[j], a[i]))
        poly_w(m, [c00, c01, d01, d00], ST, DARK, (0, 1, 0))
        poly_w(m, [c10, d10, d11, c11], ST, DARK, (0, -1, 0))
        poly_w(m, [c00, d00, d10, c10], ST, DARK, along)
        poly_w(m, [d01, c01, c11, d11], ST, DARK, K.mul(along, -1))
        poly_w(m, [d00, d01, d11, d10], ST, DARK * 0.6, nrm)


def hoju(m, y, r, lod, col):
    """宝珠＋請花。"""
    n = 6 if lod else 10
    prism(m, n, r * 1.25, r * 0.9, y, y + r * 0.6, ST, col)
    y2 = y + r * 0.6
    rings = []
    for k, (rr, hh) in enumerate([(0.85, 0.0), (1.0, 0.45), (0.85, 0.95), (0.45, 1.35), (0.0, 1.75)]):
        rings.append(ring(n, max(rr * r, 0.002), y2 + hh * r))
    loft(m, rings, ST, col, cap_bot=False, cap_top=False)


def toro_kasuga(name, lod):
    rng = random.Random(311)
    m = new(name + ('_l1' if lod else ''), '春日燈籠 高 1.96：基礎（六角＋反花）、竿（節）、中台、火袋（火口 2 面）、六角笠（蕨手）、請花＋宝珠')
    n = 6
    ph = math.pi / 6
    # 基礎（埋 0.12）
    prism(m, n, 0.38, 0.38, -0.12, 0.10, ST, MOSSY, ph, caps=(True, False))
    loft(m, [ring(n, 0.38, 0.10, ph), ring(n, 0.30, 0.20, ph), ring(n, 0.17, 0.24, ph)], ST, MOSSY, cap_bot=False,
         cap_top=True)
    # 竿（節帶）
    sn = 6 if lod else 12
    prism(m, sn, 0.115, 0.105, 0.24, 0.58, ST, LANTERN, caps=(False, False))
    if not lod:
        prism(m, sn, 0.13, 0.13, 0.58, 0.63, ST, LANTERN, caps=(True, True))
    prism(m, sn, 0.105, 0.10, 0.63, 0.98, ST, LANTERN, caps=(False, False))
    # 中台
    loft(m, [ring(n, 0.17, 0.98, ph), ring(n, 0.30, 1.13, ph), ring(n, 0.30, 1.18, ph)], ST, LANTERN)
    # 火袋
    hibukuro(m, n, 0.21, 1.18, 1.52, lod, LANTERN, {0, 3}, ph)
    # 笠
    hex_roof(m, 1.52, 0.44, 1.76, 0.07, lod, LANTERN, warabi=0.06, th=0.045, n=n, phase=ph)
    hoju(m, 1.76, 0.075, lod, LANTERN)
    return m


def toro_yukimi(name, lod):
    rng = random.Random(313)
    m = new(name + ('_l1' if lod else ''), '雪見燈籠 高 1.00、笠徑 1.10：三脚（外撇）、圓中台、六角火袋、寬笠、宝珠')
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.3
        foot = (math.cos(a) * 0.46, -0.08, math.sin(a) * 0.46)
        knee = (math.cos(a) * 0.36, 0.26, math.sin(a) * 0.36)
        top = (math.cos(a) * 0.17, 0.44, math.sin(a) * 0.17)
        m.cyl(foot, knee, 0.055, 0.05, 5 if lod else 8, ST, LANTERN, caps=(True, False))
        m.cyl(knee, top, 0.05, 0.045, 5 if lod else 8, ST, LANTERN, caps=(False, False))
    sn = 8 if lod else 16
    loft(m, [ring(sn, 0.20, 0.42), ring(sn, 0.24, 0.47), ring(sn, 0.22, 0.51)], ST, LANTERN)
    hibukuro(m, 6, 0.17, 0.51, 0.75, lod, LANTERN, {1, 4}, math.pi / 6)
    hex_roof(m, 0.75, 0.56, 0.96, 0.06, lod, LANTERN, warabi=0.04, th=0.06, n=6 if lod else 8, phase=0.0)
    hoju(m, 0.96, 0.05, lod, LANTERN)
    return m


def toro_oribe(name, lod):
    m = new(name + ('_l1' if lod else ''), '織部燈籠 高 1.32：竿直接埋 0.35（生込み）、竿頭十字膨らみ、四角中台／火袋／笠、宝珠')
    col = (0.94, 0.94, 0.90)
    prism(m, 4, 0.11, 0.11, -0.35, 0.56, ST, MOSSY, math.pi / 4, caps=(True, False))
    loft(m, [ring(4, 0.11, 0.56, math.pi / 4), ring(4, 0.17, 0.66, math.pi / 4), ring(4, 0.15, 0.75, math.pi / 4)],
         ST, col, cap_bot=False, cap_top=False)
    loft(m, [ring(4, 0.15, 0.75, math.pi / 4), ring(4, 0.25, 0.80, math.pi / 4), ring(4, 0.25, 0.84, math.pi / 4)],
         ST, col)
    hibukuro(m, 4, 0.20, 0.84, 1.08, lod, col, {0, 2}, math.pi / 4)
    hex_roof(m, 1.08, 0.40, 1.25, 0.05, lod, col, warabi=0.03, th=0.04, n=4, phase=math.pi / 4)
    hoju(m, 1.25, 0.05, lod, col)
    return m


# ─────────────────────────── 蹲踞 ───────────────────────────

def smoothstep_(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def basin(m, lod, rng, col):
    """手水鉢（自然石）：迴轉剖面＋角度／高度低頻擾動、共用頂點平滑著色（不是多角柱）。
    外壁 → 圓弧肩 → 天端 → 內緣 → 鉢底（碗形）。原點＝接地線，埋 0.12。"""
    n = 14 if lod else 30
    # 下ぶくれ（重心低い）・天端は広く平ら・口縁は不整（鑿跡）
    prof = [(0.40, -0.12, 1), (0.42, 0.02, 1), (0.41, 0.15, 1), (0.385, 0.28, 1), (0.37, 0.38, 1), (0.355, 0.44, 0.9),
            (0.31, 0.475, 0.7), (0.24, 0.482, 0.45), (0.19, 0.476, 0.4), (0.168, 0.445, 0.25), (0.15, 0.405, 0.12),
            (0.10, 0.375, 0.0), (0.045, 0.364, 0.0), (0.004, 0.36, 0.0)]
    if lod:
        prof = [prof[i] for i in (0, 2, 4, 5, 7, 9, 11, 13)]
    ph = [rng.uniform(0, 6.28) for _ in range(4)]

    def R(i, j):
        r, y, wob = prof[j]
        t = 2 * math.pi * (i % n) / n
        f = 1.0 + wob * (0.11 * math.sin(t + ph[0]) + 0.07 * math.sin(2 * t + ph[1] + y * 1.5)
                         + 0.035 * math.sin(3 * t + ph[2] + y * 4.0) + 0.018 * math.sin(7 * t + ph[3] + y * 9.0))
        # 天端の傾き＋口縁の欠け（自然石）
        dy = (0.045 * math.sin(t + ph[3]) + 0.01 * math.sin(5 * t + ph[0])) * smoothstep_(0.15, 0.45, y)
        # 平面形も楕円＋片寄り（轆轤の対称を崩す）、鉢口は中心から少しずらす
        off = (0.025, -0.02) if wob < 0.3 else (0.0, 0.0)
        # 全体を片側へ傾ける（上ほど −x 側へ寄る）＋片側だけ膨らむ（下ぶくれの偏り）
        lean = -0.06 * max(y, 0.0) / 0.48
        bulge = 1.0 + 0.12 * max(0.0, math.cos(t - 0.6)) * (1.0 - abs(y - 0.12) / 0.4) * wob
        return (math.cos(t) * r * f * bulge * 1.1 + off[0] + lean, y + dy, -math.sin(t) * r * f * bulge * 0.92 + off[1])
    t_ = m.tile[ST]
    m.grid(R, lambda i, j: (i / n * 2.2 / t_, -prof[j][1] / t_), n, len(prof) - 1, ST, col, (1.0, 0.0, -0.1))
    # 水面（鉢內 +0.42，圓、略小於內壁）
    wn = 12 if lod else 24
    ring_w = [(math.cos(2 * math.pi * i / wn) * 0.158, 0.42, -math.sin(2 * math.pi * i / wn) * 0.158) for i in range(wn)]
    poly_w(m, ring_w, WT, 1.0, (0, 1, 0))


def tsukubai(name, lod):
    rng = random.Random(331)
    m = new(name + ('_l1' if lod else ''), '蹲踞：自然石手水鉢（迴轉剖面＋擾動、平滑；徑 0.77、高 0.48、水面 +0.42）＋前石／手燭石／湯桶石（自然石、天端削平）＋海（玉石）＋筧（竹、−z 側）')
    basin(m, lod, rng, tint(rng, (0.84, 0.84, 0.80)))
    lv = 1 if lod else 4
    # 前石（+z、蹲む石：大きく平ら）・手燭石（−x、高め）・湯桶石（+x、やや低い）
    rock(m, (0.0, 0.0, 0.82), (0.36, 0.11, 0.24), rng, tint(rng, (0.92, 0.91, 0.87)), lv, amp=0.07, facet=0.62, bury=0.48,
         top_col=(0.95, 0.94, 0.9))
    rock(m, (-0.72, 0.0, 0.30), (0.19, 0.24, 0.16), rng, tint(rng, (0.78, 0.78, 0.76)), lv, amp=0.16, facet=0.25, bury=0.35,
         top_col=(0.7, 0.8, 0.6))
    rock(m, (0.70, 0.0, 0.36), (0.21, 0.15, 0.17), rng, tint(rng, (0.86, 0.83, 0.77)), lv, amp=0.08, facet=0.35, bury=0.38,
         top_col=(0.75, 0.82, 0.66))
    # 海：玉石（黑）
    if not lod:
        for k in range(19):
            # 海：前石と鉢の間（+z）に寄せて群れさせる
            a = math.pi / 2 + rng.gauss(0.0, 0.9)
            r = rng.uniform(0.44, 0.62)
            s = rng.uniform(0.025, 0.085)
            rock(m, (math.cos(a) * r, 0.0, math.sin(a) * r), (s, s * 0.7, s * 0.85), rng, (0.42, 0.42, 0.44), 2,
                 amp=0.06, bury=0.35)
    # 筧（竹樋）：−z 側，支柱＋斜樋
    sg = 4 if lod else 8
    culm(m, (0.0, -0.3, -0.95), (0.0, 0.74, -0.95), 0.03, lod, seg=sg)
    culm(m, (-0.08, -0.3, -0.85), (0.06, 0.62, -0.92), 0.022, lod, seg=sg)
    culm(m, (0.0, 0.72, -1.05), (0.0, 0.62, -0.06), 0.03, lod, seg=sg)
    if not lod:
        # 筧から手水鉢への細い落水
        m.poly([(-0.012, 0.61, -0.04), (0.012, 0.61, -0.04), (0.016, 0.43, 0.0), (-0.016, 0.43, 0.0)], FL, 1.0)
        m.poly([(0.012, 0.61, -0.04), (-0.012, 0.61, -0.04), (-0.016, 0.43, 0.0), (0.016, 0.43, 0.0)], FL, 1.0)
    return m


# ─────────────────────────── 延段・飛石 ───────────────────────────

def split_rect(rng, x0, z0, x1, z1, depth, out, smin=0.2, smax=0.62):
    w, d = x1 - x0, z1 - z0
    if (w < smax and d < smax and (depth > 1 or rng.random() < 0.35)) or depth > 5 or (w < smin * 2 and d < smin * 2):
        out.append((x0, z0, x1, z1))
        return
    if (w >= d and w >= smin * 2) or d < smin * 2:
        t = rng.uniform(0.32, 0.68)
        xm = x0 + w * t
        split_rect(rng, x0, z0, xm, z1, depth + 1, out, smin, smax)
        split_rect(rng, xm, z0, x1, z1, depth + 1, out, smin, smax)
    else:
        t = rng.uniform(0.32, 0.68)
        zm = z0 + d * t
        split_rect(rng, x0, z0, x1, zm, depth + 1, out, smin, smax)
        split_rect(rng, x0, zm, x1, z1, depth + 1, out, smin, smax)


def nobedan(name, seed, lod):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), '延段 1.4 × 1.2：切石＋自然石混用、目地 2–3 cm（苔／土由地面材質負責）、頂 +0.035')
    W, D, GAP = 1.4, 1.2, 0.026
    rects = []
    split_rect(rng, -W / 2, -D / 2, W / 2, D / 2, 0, rects)
    for (x0, z0, x1, z1) in rects:
        w, d = x1 - x0 - GAP, z1 - z0 - GAP
        natural = rng.random() < 0.28
        slab(m, (x0 + x1) / 2, (z0 + z1) / 2, 0.035 + rng.uniform(-0.006, 0.006), w * (0.93 if natural else 1.0),
             d * (0.93 if natural else 1.0), 0.18, 0.008 if not natural else 0.02, rng, tint(rng), lod,
             n=6 if natural else 8, p=2.6 if natural else 7.0, jit=0.08 if natural else 0.015, chamf=0.015)
    return m


def tobi(name, seed, w, d, lod):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), '飛石 %.2f × %.2f、頂 +0.06（天端平、自然輪廓）' % (w, d))
    slab(m, 0.0, 0.0, 0.06, w, d, 0.22, 0.014, rng, tint(rng), lod, n=13, p=2.1, jit=0.16, chamf=0.035)
    return m


def keiseki(name, seed, size, lod, facet=0.0, amp=0.14, bury=0.28):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), '景石 寬 %.1f × 露出高 %.2f × 深 %.1f（埋 %.0f %%）' % (size[0] * 2, size[1], size[2] * 2,
                                                                                    bury * 100))
    rock(m, (0, 0, 0), size, rng, tint(rng, (0.86, 0.85, 0.80)), 1 if lod else 3, amp=amp, facet=facet, bury=bury,
         top_col=(0.70, 0.80, 0.62))
    return m


# ─────────────────────────── 竹垣・石橋・縁石 ───────────────────────────

def yotsume(name, lod):
    m = new(name + ('_l1' if lod else ''), '四つ目垣 1.8 m：親柱 Ø0.07（±0.9、頂 0.95、埋 0.35）、胴縁 4 段（表裏交互）、立子 0.3 m 間、棕櫚縄結び')
    for x in (-0.9, 0.9):
        culm(m, (x, -0.35, 0), (x, 0.95, 0), 0.035, lod)
    for k, y in enumerate((0.24, 0.46, 0.68, 0.88)):
        z = 0.032 if k % 2 == 0 else -0.032
        culm(m, (-0.93, y, z), (0.93, y, z), 0.014, lod)
    xs = [-0.6, -0.3, 0.0, 0.3, 0.6]
    for x in xs:
        culm(m, (x, -0.15, 0), (x, 0.98, 0), 0.0125, lod)
    if not lod:
        for x in xs:
            for k, y in enumerate((0.24, 0.46, 0.68, 0.88)):
                z = 0.032 if k % 2 == 0 else -0.032
                m.box((x - 0.018, y - 0.02, z - 0.022 if z < 0 else z - 0.012),
                      (x + 0.018, y + 0.02, z + 0.012 if z < 0 else z + 0.022), WD, ROPE)
    return m


def sodegaki(name, lod):
    rng = random.Random(337)
    m = new(name + ('_l1' if lod else ''), '袖垣 1.0 × 1.7：親柱 2、黒穂（細竹密植）面、押縁 2 段、玉縁')
    for x in (-0.5, 0.5):
        culm(m, (x, -0.3, 0), (x, 1.72, 0), 0.032, lod)
    if lod:
        m.box((-0.48, 0.02, -0.025), (0.48, 1.62, 0.025), WD, (0.30, 0.24, 0.18))
    else:
        x = -0.47
        while x < 0.47:
            top = 1.60 + rng.uniform(-0.02, 0.02)
            m.cyl((x, 0.02, rng.uniform(-0.012, 0.012)), (x + rng.uniform(-0.01, 0.01), top, rng.uniform(-0.012, 0.012)),
                  0.009, 0.008, 4, WD, (0.30, 0.24, 0.18), caps=(False, False))
            x += rng.uniform(0.018, 0.026)
    for y in (0.45, 1.15):
        for z in (0.03, -0.03):
            culm(m, (-0.5, y, z), (0.5, y, z), 0.014, lod)
    culm(m, (-0.52, 1.64, 0), (0.52, 1.64, 0), 0.045, lod)
    return m


def bridge(name, lod):
    rng = random.Random(341)
    m = new(name + ('_l1' if lod else ''), '石橋 1.8（x 跨）× 0.55 × 厚 0.20：切石一枚、微反り、頂 +0.06')
    slab(m, 0.0, 0.0, 0.06, 1.8, 0.55, 0.20, 0.02, rng, tint(rng, (0.92, 0.91, 0.88)), lod, n=10, p=8.0, jit=0.01,
         chamf=0.02)
    return m


def amaochi(name, lod):
    rng = random.Random(347)
    m = new(name + ('_l1' if lod else ''), '雨落ち縁石 0.9 × 0.1、頂 +0.04、厚 0.18')
    slab(m, 0.0, 0.0, 0.04, 0.9, 0.10, 0.18, 0.004, rng, tint(rng), lod, n=8, p=8.0, jit=0.01, chamf=0.01)
    return m


# ─────────────────────────── 全部 ───────────────────────────

def build_all():
    for lod in (0, 1):
        toro_kasuga('gk_toro_kasuga', lod)
        toro_yukimi('gk_toro_yukimi', lod)
        toro_oribe('gk_toro_oribe', lod)
        tsukubai('gk_tsukubai', lod)
        for i, s in enumerate((401, 409, 419)):
            nobedan('gk_nobe_%s' % 'abc'[i], s, lod)
        for i, (s, w, d) in enumerate(((421, 0.62, 0.50), (431, 0.52, 0.46), (433, 0.70, 0.56), (439, 0.46, 0.40))):
            tobi('gk_tobi_%s' % 'abcd'[i], s, w, d, lod)
        keiseki('gk_kei_tall', 443, (0.36, 1.35, 0.30), lod, amp=0.12, bury=0.25)
        keiseki('gk_kei_mid', 449, (0.42, 0.80, 0.36), lod, amp=0.13, bury=0.28)
        keiseki('gk_kei_low', 457, (0.55, 0.45, 0.40), lod, amp=0.14, bury=0.32, facet=0.2)
        keiseki('gk_kei_flat', 461, (0.70, 0.26, 0.48), lod, amp=0.10, bury=0.38, facet=0.45)
        yotsume('gk_yotsume', lod)
        sodegaki('gk_sodegaki', lod)
        bridge('gk_bridge', lod)
        amaochi('gk_amaochi', lod)


def dims(m):
    xs = [p[0] for p in m.v]
    ys = [p[1] for p in m.v]
    zs = [p[2] for p in m.v]
    return [round(min(xs), 4), round(min(ys), 4), round(min(zs), 4), round(max(xs), 4), round(max(ys), 4), round(max(zs), 4)]


def main():
    K.clear_scene(bpy)
    build_all()
    bm = K.blender_mats(bpy, MATS)
    objs = []
    manifest = {}
    for name, m in MODS.items():
        ob = m.to_blender(bpy, bmats=bm)
        objs.append(ob)
        tri = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        manifest[name] = {'tris': tri, 'dims': dims(m), 'mats': sorted({m.mats[f[1]] for f in m.f}), 'note': INFO[name]}
    K.export_glb(bpy, OUT + '/src/garden_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_garden_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=garden_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[GKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/garden_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[GKIT]   %-15s %5d 面  LOD1 %4d  dims %s  %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims'], v['mats']))


main()
