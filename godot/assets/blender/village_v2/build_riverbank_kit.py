"""人間之里 V2 P7 R2：河岸 Kit（Riverbank / Bridge Transition 共用構件）— 新資產，不重用任何舊河岸資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_riverbank_kit.py

設計：
  - 構件只存一次（assets/village_v2/riverbank_kit/mesh/<名>.res）；Godot 端 tools/village_v2_riverbank_lib.gd 依
    水道中心線（layout，不改）＋最終地形（P1，不改）逐段擺放，再按 40 m 區塊合併成一個 ArrayMesh（LOD0／LOD1），
    濕石／苔在合併時依「頂點離水位高度」寫進頂點色（構件本身只帶石色差）。
  - 參考圖 docs/reference/河岸/（花崗岩疊砌牆一段、護岸收頭件、親水階梯、洗物石段、濱水平台、木樁）與
    docs/reference/橋/：野面積み（半整形割石、目地深、不規則段）、笠石一列、雁木石段、繩綁木樁。
  - 材質＝重用 machiya_kit/V2_KitStoneTri（共享材質庫 V2_Stone 貼圖、world triplanar：石紋跨構件連續）＋共享 V2_Wood；不新增貼圖。
座標：Godot（x 右、y 上、+z 外側）；單位 m。
  rb_rev_*   護岸石張り面板 2.4（x 沿岸）× 0.9（y 沿坡上）；面板平面 z＝0，石面凸出 +0.05～+0.11、石背 −0.30；目地背板 −0.03
  rb_revb_*  護岸大石面板（水際最下段用）2.4 × 0.9，一段大石
  rb_cap_*   笠石：原點＝座面中心（y 0），頂 +0.24、埋 −0.10；x 沿岸、+z 朝水
  rb_bld_*   巨石：原點＝接地線，底 −0.35H、頂 +0.65H（標稱徑 1.0 m）
  rb_cob_*   河原石群：原點＝地面（y 0）、直徑約 1.4 m 圓盤內 10–18 顆
  rb_flag_*  橋頭鋪石：原點＝頂面中心（y 0），厚 0.16
  rb_curb_*  見切り石：原點＝頂面中心，1.1 × 0.3、厚 0.34
  rb_step_*  雁木石段：原點＝踏面中心（y 0），x 1.3（垂直河岸）× z 0.44（沿岸），往下 1.4
  rb_land    親水平台（洗い場）：原點＝頂面中心，1.9 × 1.4、往下 1.1
  rb_pile_*  木樁（_r 綁繩）：原點＝地面，頂 +0.95、埋 −0.8，Ø0.20
  rb_rail    矮欄 2.0 m：原點＝地面中心，柱頂 +0.85、埋 −0.45
  rb_shig    しがらみ 2.0 m：原點＝地面中心，高 0.55
  *_l1       LOD1
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/riverbank_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
ST = 'V2_KitStoneTri'   # 重用町家 Kit 的 world-triplanar 石材（共享材質庫 V2_Stone 貼圖），不新增材質
WD = 'V2_Wood'
MATS = [ST, WD]
TILE = {ST: ML['V2_Stone']['tile_m'], WD: ML['V2_Wood']['tile_m']}

PW, PH = 2.4, 0.9            # 護岸面板
MORTAR = 0.50                # 目地（背板）色（0.30 太黑：1.7 m 視角讀成黑洞，2026-09-28 審查）
STONE_TINTS = [(0.96, 0.94, 0.90), (1.03, 0.98, 0.91), (0.88, 0.90, 0.93), (0.80, 0.78, 0.74), (0.99, 0.95, 0.86)]
WOOD_DARK = (0.66, 0.60, 0.54)
ROPE = (1.25, 1.10, 0.82)

MODS = {}
INFO = {}


def new(name, note=''):
    m = K.Mesh(name, MATS, TILE)
    MODS[name] = m
    INFO[name] = note
    return m


def tint(rng):
    t = rng.choice(STONE_TINTS)
    k = rng.uniform(0.88, 1.08)
    return (t[0] * k, t[1] * k, t[2] * k)


def outline(rng, w, h, n=8, p=3.2, jit=0.08):
    """(u, v) 平面上的不規則圓角矩形（superellipse），逆時針。"""
    pts = []
    for i in range(n):
        a = 2 * math.pi * (i + rng.uniform(-0.16, 0.16)) / n + math.pi / n
        c, s = math.cos(a), math.sin(a)
        u = math.copysign(abs(c) ** (2 / p), c) * w / 2 * (1 + rng.uniform(-jit, jit))
        v = math.copysign(abs(s) ** (2 / p), s) * h / 2 * (1 + rng.uniform(-jit, jit))
        pts.append((u, v))
    return pts


# ─────────────────────────── 石：面石（x-y 面、+z 外露）───────────────────────────

def face_stone(m, cx, cy, w, h, depth, bulge, rng, col, lod, n=8):
    O = outline(rng, w, h, n)
    n = len(O)
    if lod >= 1:
        m.quad((cx - w / 2, cy - h / 2, bulge * 0.5), (cx + w / 2, cy - h / 2, bulge * 0.5),
               (cx + w / 2, cy + h / 2, bulge * 0.5), (cx - w / 2, cy + h / 2, bulge * 0.5), ST, col)
        return
    c = (cx + rng.uniform(-0.04, 0.04) * w, cy + rng.uniform(-0.04, 0.04) * h, bulge)
    ri = [(cx + u * 0.78, cy + v * 0.78, bulge * 0.8 + rng.uniform(-0.012, 0.012)) for u, v in O]
    ro = [(cx + u, cy + v, 0.0) for u, v in O]
    bk = [(cx + u * 0.94, cy + v * 0.94, -depth) for u, v in O]
    for i in range(n):
        j = (i + 1) % n
        m.poly([c, ri[i], ri[j]], ST, col)
        m.poly([ri[i], ro[i], ro[j], ri[j]], ST, col)
        m.poly([ro[i], bk[i], bk[j], ro[j]], ST, col)


def rev_panel(name, seed, lod, big=False, three=False):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), '護岸石張り面板 %.1f×%.1f（%s）' % (PW, PH, '水際大石一段' if big else ('小石三段' if three else '野面積み二段')))
    m.quad((-PW / 2, -PH / 2, -0.03), (PW / 2, -PH / 2, -0.03), (PW / 2, PH / 2, -0.03), (-PW / 2, PH / 2, -0.03), ST, MORTAR)
    # 水際版亦做兩列中石，不做單列長板；6 邊輪廓保留低面數
    courses = ([(-PH / 2, -PH / 2 + 0.47), (-PH / 2 + 0.47, PH / 2)] if big else
               ([(-PH / 2, -PH / 2 + 0.31), (-PH / 2 + 0.31, -PH / 2 + 0.60), (-PH / 2 + 0.60, PH / 2)]
                if three else [(-PH / 2, -PH / 2 + 0.47), (-PH / 2 + 0.47, PH / 2)]))
    for ci, (y0, y1) in enumerate(courses):
        x = -PW / 2 + 0.02
        while x < PW / 2 - 0.12:
            w = rng.uniform(0.50, 0.78) if big else (rng.uniform(0.26, 0.52) if three else rng.uniform(0.40, 0.78))
            if x + w > PW / 2 - 0.02 or PW / 2 - 0.02 - (x + w) < 0.22:
                w = PW / 2 - 0.02 - x
            gap = rng.uniform(0.03, 0.05)
            hh = (y1 - y0) - gap
            dy = rng.uniform(-0.02, 0.02)
            face_stone(m, x + w / 2, (y0 + y1) / 2 + dy, w - gap, hh * rng.uniform(0.9, 1.0), 0.30,
                       rng.uniform(0.06, 0.11) if big else rng.uniform(0.05, 0.10), rng, tint(rng), lod,
                       6 if (three or big) else 8)   # 水際／小石面板：石多 → 6 邊輪廓控面數
            x += w
    return m


# ─────────────────────────── 石：平石（x-z 面、+y 外露）───────────────────────────

def slab(m, cx, cz, top, w, d, th, bulge, rng, col, lod, n=7, p=3.0, jit=0.07, chamf=0.03):
    if lod >= 1:
        n = 5                     # LOD1（75 m 外）：5 邊輪廓 → 13 三角面
    O = outline(rng, w, d, n, p, jit)

    def P(u, v, y, k=1.0):
        return (cx + u * k, y, cz - v * k)
    if lod >= 1:
        m.poly([P(u, v, top) for u, v in O], ST, col)
        for i in range(n):
            j = (i + 1) % n
            m.poly([P(*O[i], top), P(*O[i], top - th), P(*O[j], top - th), P(*O[j], top)], ST, col)
        return
    c = P(rng.uniform(-0.03, 0.03) * w, rng.uniform(-0.03, 0.03) * d, top + bulge)
    ri = [P(u, v, top + bulge * 0.6 + rng.uniform(-0.006, 0.006), 0.8) for u, v in O]
    ro = [P(u, v, top - chamf) for u, v in O]
    bt = [P(u, v, top - th, 0.97) for u, v in O]
    for i in range(n):
        j = (i + 1) % n
        m.poly([c, ri[i], ri[j]], ST, col)
        m.poly([ri[i], ro[i], ro[j], ri[j]], ST, col)
        m.poly([ro[i], bt[i], bt[j], ro[j]], ST, col)


def cap(name, seed, lod):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), '笠石（天端石）約 1.15 × 0.48、頂 +0.24、埋 0.10')
    slab(m, 0.0, 0.0, 0.24, rng.uniform(1.08, 1.22), rng.uniform(0.44, 0.52), 0.34, 0.025, rng, tint(rng), lod,
         n=8, p=4.0, jit=0.05, chamf=0.04)
    return m


def flag(name, seed, w, d, lod):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), '橋頭鋪石 %.2f × %.2f：貼地頂面（無外露側壁；路帶邊高差由既有 P3 幾何負責）' % (w, d))
    O = outline(rng, w, d, 7, 3.4, 0.08)
    c = (rng.uniform(-0.02, 0.02) * w, 0.008, rng.uniform(-0.02, 0.02) * d)
    rim = [(u, rng.uniform(-0.003, 0.003), -v) for u, v in O]
    col = tint(rng)
    for i in range(len(rim)):
        m.poly([c, rim[i], rim[(i + 1) % len(rim)]], ST, col)
    return m


def curb(name, seed, lod):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), '見切り石 1.1 × 0.3、厚 0.34')
    slab(m, 0.0, 0.0, 0.0, 1.1, 0.30, 0.34, 0.015, rng, tint(rng), lod, n=8, p=5.0, jit=0.03, chamf=0.03)
    return m


def step(name, seed, lod):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), '雁木石段 1.3（垂直河岸）× 0.44（沿岸）、往下 1.4')
    slab(m, 0.0, 0.0, 0.0, 1.3, 0.44, 1.4, 0.01, rng, tint(rng), lod, n=8, p=5.0, jit=0.03, chamf=0.03)
    return m


def landing(name, seed, lod):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), '親水平台（洗い場）1.9 × 1.4：基石＋三枚平石')
    slab(m, 0.0, 0.0, -0.10, 1.9, 1.4, 1.0, 0.0, rng, tint(rng), lod, n=8, p=6.0, jit=0.02, chamf=0.02)
    for k in range(3):
        slab(m, -0.62 + k * 0.62, 0.0, 0.0, 0.60, 1.36, 0.14, 0.01, rng, tint(rng), lod, n=6, p=5.0, jit=0.03, chamf=0.02)
    return m


# ─────────────────────────── 巨石／河原石 ───────────────────────────

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
                p = K.norm(K.mul(K.add(V[a], V[b]), 0.5))
                V.append(p)
                cache[k] = len(V) - 1
            return cache[k]
        for a, b, c in F:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)]
        F = nf
    return V, F


def rock(m, center, size, rng, col, level, flat=0.62, amp=0.14, ground=True):
    """size＝(sx, sy, sz) 半徑；ground＝True 時整顆平移到「底 −0.35H、頂 +0.65H」（原點＝接地線）。"""
    V, F = sphere(level)
    dirs = [K.norm((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) for _ in range(3)]
    fq = [rng.uniform(1.6, 3.2) for _ in range(3)]
    ph = [rng.uniform(0, 6.28) for _ in range(3)]
    am = [amp, amp * 0.6, amp * 0.35]
    P = []
    for v in V:
        r = 1.0 + sum(am[k] * math.sin(fq[k] * K.dot(v, dirs[k]) * 3.0 + ph[k]) for k in range(3))
        x, y, z = v[0] * r * size[0], v[1] * r * size[1] * flat / 0.62, v[2] * r * size[2]
        y = max(y, -size[1] * 0.55)
        P.append((x, y, z))
    lo = min(p[1] for p in P)
    hi = max(p[1] for p in P)
    dy = (-0.35 * (hi - lo) - lo) if ground else 0.0
    P = [(center[0] + p[0], center[1] + p[1] + dy, center[2] + p[2]) for p in P]
    idx = m.verts(P)
    t = m.tile[ST]
    for a, b, c in F:
        # 頂點共用（smooth）；UV 為俯視投影（Godot 端石材為 world triplanar，UV 僅供切線）
        m.face([idx[a], idx[b], idx[c]], ST, [(P[q][0] / t, -P[q][2] / t) for q in (a, b, c)], col, smooth=True)


def boulder(name, seed, lod):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), '巨石 標稱徑 1.0 m（擺放時等比 0.35–2.0）')
    rock(m, (0, 0, 0), (0.5 * rng.uniform(0.9, 1.1), 0.5, 0.5 * rng.uniform(0.75, 1.0)), rng, tint(rng), 1 if lod else 2,
         flat=rng.uniform(0.52, 0.7), amp=rng.uniform(0.10, 0.17))
    return m


def cobbles(name, seed, n, smin, smax, lod):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), '河原石群 %d 顆（徑 %.2f–%.2f）' % (n, smin * 2, smax * 2))
    placed = []
    tries = 0
    while len(placed) < n and tries < 400:
        tries += 1
        r = 0.68 * math.sqrt(rng.random())
        a = rng.uniform(0, 6.283)
        x, z = r * math.cos(a), r * math.sin(a)
        s = rng.uniform(smin, smax)
        if any(math.hypot(x - q[0], z - q[1]) < (s + q[2]) * 0.95 for q in placed):
            continue
        placed.append((x, z, s))
        rock(m, (x, s * 0.12, z), (s, s * 0.5, s * rng.uniform(0.7, 0.95)), rng, tint(rng), 0 if lod else 1,
             flat=0.62, amp=0.08, ground=False)
    return m


# ─────────────────────────── 木 ───────────────────────────

def pile(name, seed, rope, lod):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), '木樁 Ø0.20、頂 +0.95、埋 0.8' + ('、上部綁繩' if rope else ''))
    seg = 4 if lod else 10          # LOD1：四角柱（75 m 外 Ø0.2 m 約 2 px）
    r = 0.10 * rng.uniform(0.92, 1.05)
    m.cyl((0, -0.8, 0), (0, 0.95, 0), r, r * 0.95, seg, WD, WOOD_DARK, caps=(False, not lod), phase=rng.uniform(0, 1))
    if rope and not lod:
        for y in (0.66, 0.74, 0.82):
            m.cyl((0, y, 0), (0, y + 0.05, 0), r + 0.018, r + 0.018, seg, WD, ROPE, caps=(False, False))
    return m


def rail(name, lod):
    m = new(name + ('_l1' if lod else ''), '矮欄 2.0 m：柱 0.10 角、頂 +0.85、橫木二段')
    for x in (-0.95, 0.95):
        m.box((x - 0.05, -0.45, -0.05), (x + 0.05, 0.85, 0.05), WD, WOOD_DARK, grain=K.Y)
    m.box((-1.02, 0.77, -0.035), (1.02, 0.84, 0.035), WD, WOOD_DARK, grain=K.X)
    if not lod:
        m.box((-1.0, 0.40, -0.03), (1.0, 0.46, 0.03), WD, WOOD_DARK, grain=K.X)
    return m


def shigarami(name, seed, lod):
    rng = random.Random(seed)
    m = new(name + ('_l1' if lod else ''), 'しがらみ 2.0 m：杭 4 本＋粗朶 4 段、高 0.55')
    xs = [-0.95, -0.32, 0.32, 0.95]
    for x in xs:
        m.cyl((x, -0.35, 0), (x, 0.55, 0), 0.035, 0.03, 3 if lod else 6, WD, WOOD_DARK, caps=(False, not lod))
    if lod:
        # LOD1：粗朶兩段各一片薄板（75 m 外看得到橫向編條即可）
        for y in (0.14, 0.34):
            m.box((-1.0, y - 0.04, -0.03), (1.0, y + 0.04, 0.03), WD, (0.78, 0.70, 0.58), grain=K.X)
        return m
    rows = [0.08, 0.20, 0.32, 0.44]
    for k, y in enumerate(rows):
        pts = [(-1.0, y + rng.uniform(-0.015, 0.015), 0.0)]
        for i, x in enumerate(xs):
            pts.append((x, y + rng.uniform(-0.015, 0.015), (0.045 if (i + k) % 2 else -0.045)))
        pts.append((1.0, y, 0.0))
        for i in range(len(pts) - 1):
            m.cyl(pts[i], pts[i + 1], 0.022, 0.022, 3 if lod else 5, WD, (0.78, 0.70, 0.58), caps=(False, False))
    return m


# ─────────────────────────── 全部 ───────────────────────────

def build_all():
    for lod in (0, 1):
        for i, s in enumerate((11, 23, 37, 41)):
            rev_panel('rb_rev_%s' % 'abcd'[i], s, lod)
        for i, s in enumerate((257, 263)):
            rev_panel('rb_rev_%s' % 'ef'[i], s, lod, three=True)
        for i, s in enumerate((53, 67)):
            rev_panel('rb_revb_%s' % 'ab'[i], s, lod, big=True)
        for i, s in enumerate((71, 83, 97)):
            cap('rb_cap_%s' % 'abc'[i], s, lod)
        for i, s in enumerate((101, 113, 127, 131, 149)):
            boulder('rb_bld_%s' % 'abcde'[i], s, lod)
        cobbles('rb_cob_a', 151, 14, 0.07, 0.16, lod)
        cobbles('rb_cob_b', 163, 10, 0.08, 0.20, lod)
        cobbles('rb_cob_c', 173, 18, 0.05, 0.12, lod)
        for i, (s, w, d) in enumerate(((181, 0.56, 0.46), (191, 0.70, 0.50), (193, 0.84, 0.54), (197, 0.62, 0.60))):
            flag('rb_flag_%s' % 'abcd'[i], s, w, d, lod)
        for i, s in enumerate((211, 223)):
            curb('rb_curb_%s' % 'ab'[i], s, lod)
        for i, s in enumerate((227, 229)):
            step('rb_step_%s' % 'ab'[i], s, lod)
        landing('rb_land', 233, lod)
        pile('rb_pile_a', 239, False, lod)
        pile('rb_pile_r', 241, True, lod)
        rail('rb_rail', lod)
        shigarami('rb_shig', 251, lod)


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
        manifest[name] = {'tris': tri, 'dims': dims(m), 'note': INFO[name]}
    K.export_glb(bpy, OUT + '/src/riverbank_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_riverbank_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=riverbank_kit）讀此表逐一轉成 mesh/<名>.res。',
        'constants': {'panel': [PW, PH], 'mortar': MORTAR},
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[RBKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/riverbank_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[RBKIT]   %-12s %5d 面  LOD1 %4d  dims %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims']))


main()
