"""人間之里 V2 P9 R4-3：寺子屋周邊小物 Kit（school_kit）— 新資產（生活感的小物，樸素・實用）。

  python tools/build_village_v2_school_atlas.py                      （先產 atlas）
  blender -b --factory-startup --python godot/assets/blender/village_v2/build_school_kit.py

只用：木＝_matlib V2_Wood（world 尺度 UV）、竹＝bamboo_kit BK_Culm_dead（R3 已核准晒し竹）、
紙／字／稲藁／手毬＝school_kit/SK_School（新 atlas）。寺子屋 Hero 本體（P5 R3）不動。
座標：Godot（x 右、y 上、+z 前）；原點＝接地點（y 0）；單位 m。
  sk_getabako   下駄箱 1.20 × 0.34 × 0.92（三段、草履 4 足入り、背面 −z）
  sk_zori       草履一足（0.24 × 0.20）              sk_bench     縁台 1.80 × 0.50、座面 0.42
  sk_box        木箱 0.60 × 0.40 × 0.38            sk_teoke     手桶＋柄杓（Ø0.28、柄 0.46）
  sk_tensui     天水桶 Ø0.62 × 0.72（蓋半開き）     sk_hanshi    習字の干し竿 5.6 m（竹柱 2、半紙 5 枚）
  sk_fuda       木札「手習所」（柱 1.30、札 0.30 × 0.48）  sk_toban   掃除当番板（柱 2、板 0.62 × 0.40、小屋根）
  sk_temari     手毬 Ø0.16                          sk_hoop      竹の輪回し Ø0.62（立てかけ）
  sk_woodpile   薪棚 1.60 × 0.45 × 0.85（板屋根）   sk_ishikeri  石蹴りの地面線 0.9 × 2.7
  *_l1          LOD1
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/school_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(OUT + '/atlas.json')['regions']
WD = 'V2_Wood'
BC = 'BK_Culm_dead'
SK = 'SK_School'
MATS = [WD, BC, SK]
TILE = {WD: ML['V2_Wood']['tile_m'], BC: 1.0, SK: 1.0}
INTERNODE = 0.3
DARK = (0.30, 0.25, 0.20)
WOODC = (0.86, 0.80, 0.70)
AGED = (0.70, 0.66, 0.60)

MODS = {}
INFO = {}


def new(name, note=''):
    m = K.Mesh(name, MATS, TILE)
    MODS[name] = m
    INFO[name] = note
    return m


def culm(m, p0, p1, r, lod, seg=None):
    L = math.dist(p0, p1)
    m.cyl(p0, p1, r, r, seg or (4 if lod else 6), BC, (0.80, 0.76, 0.66), caps=(False, True),
          uv_atlas=(0.0, 0.0, 1.0, L / INTERNODE))


def board(m, lo, hi, col=WOODC):
    m.box(lo, hi, WD, col)


def leg(m, x, z, h, w=0.05, col=WOODC):
    m.box((x - w / 2, -0.03, z - w / 2), (x + w / 2, h, z + w / 2), WD, col)


# ─────────────────────────── 物 ───────────────────────────

def zori_pair(m, cx, cy, cz, yaw, lod, sc=1.0):
    """草履一足：稲藁底（atlas straw）＋鼻緒（暗色）。cx／cz 中心、yaw rad。"""
    cy0 = cy
    c, s = math.cos(yaw), math.sin(yaw)

    def P(x, y, z):
        return (cx + (x * c + z * s) * sc, cy0 + y * sc, cz + (-x * s + z * c) * sc)
    for dx in (-0.055, 0.055):
        hw, hl, th = 0.042, 0.115, 0.018
        lo = (dx - hw, 0.0, -hl)
        hi = (dx + hw, th, hl)
        # 底：上面だけ straw、側面 wood
        a, b, cc, d = P(lo[0], th, hi[2]), P(hi[0], th, hi[2]), P(hi[0], th, lo[2]), P(lo[0], th, lo[2])
        m.rect_uv(a, b, cc, d, SK, AT['straw'], 1.0)
        for e0, e1 in ((P(lo[0], 0, hi[2]), P(hi[0], 0, hi[2])), (P(hi[0], 0, hi[2]), P(hi[0], 0, lo[2])),
                       (P(hi[0], 0, lo[2]), P(lo[0], 0, lo[2])), (P(lo[0], 0, lo[2]), P(lo[0], 0, hi[2]))):
            m.poly([e0, e1, (e1[0], e1[1] + th * sc, e1[2]), (e0[0], e0[1] + th * sc, e0[2])], SK, 0.8,
                   uvs=[(AT['straw'][0], AT['straw'][3]), (AT['straw'][2], AT['straw'][3]), (AT['straw'][2], AT['straw'][1]),
                        (AT['straw'][0], AT['straw'][1])])
        if not lod:
            # 鼻緒：前つぼから左右へ V 字
            tip = P(dx, th + 0.02, hl - 0.03)
            for sd in (-1, 1):
                q = P(dx + sd * hw * 0.85, th + 0.003, 0.0)
                m.cyl(tip, q, 0.006, 0.006, 4, WD, DARK, caps=(False, False))


def getabako(name, lod):
    m = new(name + ('_l1' if lod else ''), '下駄箱 1.20 × 0.34 × 0.92：側板・背板・棚三段、草履 4 足')
    W, D, H = 1.20, 0.34, 0.92
    board(m, (-W / 2, -0.02, -D / 2), (-W / 2 + 0.025, H, D / 2), AGED)
    board(m, (W / 2 - 0.025, -0.02, -D / 2), (W / 2, H, D / 2), AGED)
    board(m, (-W / 2, -0.02, -D / 2), (W / 2, H, -D / 2 + 0.015), (0.62, 0.58, 0.52))
    board(m, (-W / 2, H - 0.025, -D / 2), (W / 2, H + 0.005, D / 2 + 0.02), AGED)
    for y in (0.06, 0.34, 0.62):
        board(m, (-W / 2 + 0.025, y, -D / 2 + 0.015), (W / 2 - 0.025, y + 0.022, D / 2), WOODC)
    zori_pair(m, -0.28, 0.082, 0.0, 0.0, lod)
    zori_pair(m, 0.30, 0.082, 0.0, 0.08, lod)
    zori_pair(m, -0.05, 0.362, 0.0, -0.06, lod)
    zori_pair(m, 0.33, 0.642, 0.0, 0.0, lod)
    return m


def zori(name, lod):
    m = new(name + ('_l1' if lod else ''), '草履一足（脱ぎ揃え）')
    zori_pair(m, 0.0, 0.0, 0.0, 0.0, lod)
    return m


def bench(name, lod):
    m = new(name + ('_l1' if lod else ''), '縁台 1.80 × 0.50、座面 0.42（板 5 枚、脚 4、貫）')
    W, D, H = 1.80, 0.50, 0.42
    n = 5
    for i in range(n):
        z0 = -D / 2 + i * D / n + 0.006
        board(m, (-W / 2, H - 0.03, z0), (W / 2, H, z0 + D / n - 0.012), (0.82 + 0.03 * (i % 2), 0.76, 0.66))
    for x in (-W / 2 + 0.12, W / 2 - 0.12):
        for z in (-D / 2 + 0.06, D / 2 - 0.06):
            leg(m, x, z, H - 0.03, 0.055, AGED)
        board(m, (x - 0.025, 0.12, -D / 2 + 0.06), (x + 0.025, 0.16, D / 2 - 0.06), AGED)
    board(m, (-W / 2 + 0.12, 0.12, -0.02), (W / 2 - 0.12, 0.16, 0.02), AGED)
    return m


def box(name, lod):
    m = new(name + ('_l1' if lod else ''), '木箱 0.60 × 0.40 × 0.38（板張り、縁補強）')
    W, D, H = 0.60, 0.40, 0.38
    board(m, (-W / 2, 0.0, -D / 2), (W / 2, H, D / 2), (0.78, 0.72, 0.62))
    if not lod:
        for y in (0.12, 0.25):
            board(m, (-W / 2 - 0.004, y, -D / 2 - 0.004), (W / 2 + 0.004, y + 0.006, D / 2 + 0.004), (0.55, 0.50, 0.44))
        for x in (-W / 2 + 0.02, W / 2 - 0.02):
            board(m, (x - 0.02, 0.0, D / 2), (x + 0.02, H, D / 2 + 0.012), (0.60, 0.55, 0.48))
    return m


def staves(m, r0, r1, h, seg, col, y0=0.0, hoop=True, lod=False):
    m.cyl((0, y0, 0), (0, y0 + h, 0), r0, r1, seg, WD, col, caps=(True, False))
    # 内側（暗い）
    m.cyl((0, y0 + h, 0), (0, y0 + 0.03, 0), r1 - 0.012, r0 - 0.012, seg, WD, (0.42, 0.36, 0.30), caps=(False, True))
    if hoop and not lod:
        for t in (0.18, 0.78):
            y = y0 + h * t
            rr = r0 + (r1 - r0) * t + 0.005
            m.cyl((0, y - 0.012, 0), (0, y + 0.012, 0), rr, rr, seg, WD, (0.26, 0.24, 0.22), caps=(False, False))


def teoke(name, lod):
    m = new(name + ('_l1' if lod else ''), '手桶 Ø0.28 × 0.26＋把手板＋柄杓（地面に置き）')
    seg = 8 if lod else 14
    staves(m, 0.13, 0.145, 0.26, seg, WOODC, lod=lod)
    board(m, (-0.02, 0.0, -0.15), (0.02, 0.46, -0.125), AGED)
    board(m, (-0.02, 0.0, 0.125), (0.02, 0.46, 0.15), AGED)
    board(m, (-0.03, 0.40, -0.15), (0.03, 0.44, 0.15), AGED)
    if not lod:
        # 柄杓：桶の縁に掛ける
        m.cyl((0.08, 0.27, 0.0), (0.40, 0.08, 0.12), 0.008, 0.008, 5, BC, (0.82, 0.78, 0.68), caps=(True, True),
              uv_atlas=(0.0, 0.0, 1.0, 1.2))
        staves(m, 0.035, 0.035, 0.05, 8, WOODC, y0=0.0, hoop=False, lod=True)
    return m


def tensui(name, lod):
    m = new(name + ('_l1' if lod else ''), '天水桶 Ø0.62 × 0.72（箍 3、蓋板半開き）')
    seg = 10 if lod else 18
    staves(m, 0.29, 0.31, 0.72, seg, (0.66, 0.62, 0.56), lod=lod)
    if not lod:
        m.cyl((0, 0.40, 0), (0, 0.42, 0), 0.305, 0.305, seg, WD, (0.26, 0.24, 0.22), caps=(False, False))
    # 蓋：半分（板 2 枚）＋斜めに立てかけた 1 枚
    board(m, (-0.31, 0.72, -0.31), (0.0, 0.745, 0.31), (0.58, 0.54, 0.48))
    return m


def hanshi(name, lod):
    m = new(name + ('_l1' if lod else ''), '習字の干し竿：竹柱 2（1.62、間 5.6）＋竿 1.42＋半紙 5（0.24 × 0.33、両面）')
    L = 5.6
    for x in (-L / 2, L / 2):
        culm(m, (x, -0.30, 0.0), (x, 1.62, 0.0), 0.022, lod)
    culm(m, (-L / 2 - 0.06, 1.44, 0.0), (L / 2 + 0.06, 1.42, 0.0), 0.013, lod, seg=4 if lod else 5)
    rng = random.Random(733)
    xs = [-1.9, -1.0, -0.05, 0.95, 1.85]
    for i, x in enumerate(xs):
        x += rng.uniform(-0.12, 0.12)
        sw = rng.uniform(-0.05, 0.05)
        top, bot = 1.405, 1.405 - 0.33
        a = (x - 0.12, bot, sw)
        b = (x + 0.12, bot, -sw)
        c = (x + 0.12, top, 0.0)
        d = (x - 0.12, top, 0.0)
        r = AT['hanshi%d' % i]
        m.rect_uv(a, b, c, d, SK, r, 1.0)
        m.rect_uv(b, a, d, c, SK, AT['paper'], 0.92)
        if not lod:
            for px in (x - 0.07, x + 0.07):
                m.box((px - 0.006, top - 0.03, -0.012), (px + 0.006, top + 0.02, 0.012), WD, DARK)
    return m


def fuda(name, lod):
    m = new(name + ('_l1' if lod else ''), '木札「手習所」：柱 1.30（埋 0.35）＋札 0.30 × 0.48（表＝字、裏＝木地）')
    m.box((-0.045, -0.35, -0.045), (0.045, 1.30, 0.045), WD, AGED)
    lo, hi = (-0.15, 0.80, 0.05), (0.15, 1.28, 0.075)
    m.abox(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2), ((hi[0] - lo[0]) / 2, (hi[1] - lo[1]) / 2,
           (hi[2] - lo[2]) / 2), SK, {'+z': AT['fuda'], '*': AT['wood_light']}, 1.0)
    # 小屋根
    m.box((-0.20, 1.30, -0.02), (0.20, 1.33, 0.13), WD, (0.50, 0.46, 0.40))
    return m


def toban(name, lod):
    m = new(name + ('_l1' if lod else ''), '掃除当番板：柱 2（1.55、埋 0.35）＋板 0.62 × 0.40＋板屋根')
    for x in (-0.36, 0.36):
        m.box((x - 0.035, -0.35, -0.035), (x + 0.035, 1.55, 0.035), WD, AGED)
    m.abox((0.0, 1.20, 0.05), (0.31, 0.20, 0.014), SK, {'+z': AT['toban'], '*': AT['wood_light']}, 1.0)
    m.box((-0.46, 1.55, -0.12), (0.46, 1.58, 0.22), WD, (0.48, 0.44, 0.38))
    return m


def temari(name, lod):
    m = new(name + ('_l1' if lod else ''), '手毬 Ø0.16（u＝周、v＝上下）')
    r = 0.08
    nu, nv = (8, 5) if lod else (16, 9)
    u0, v0, u1, v1 = AT['temari']

    def P(i, j):
        th = 2 * math.pi * i / nu
        ph = math.pi * j / nv
        return (math.cos(th) * math.sin(ph) * r, r + math.cos(ph) * r * 0.95 - 0.006, -math.sin(th) * math.sin(ph) * r)
    m.grid(P, lambda i, j: (u0 + (u1 - u0) * i / nu, v0 + (v1 - v0) * j / nv), nu, nv, SK, 1.0, (0.0, -1.0, 0.0))
    return m


def hoop(name, lod):
    m = new(name + ('_l1' if lod else ''), '竹の輪回し Ø0.62（傾け 70°、接地点＝原点）')
    R, r = 0.31, 0.011
    n = 12 if lod else 24
    tilt = math.radians(70)
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        x, y = math.cos(a) * R, math.sin(a) * R + R
        pts.append((x, y * math.sin(tilt), -y * math.cos(tilt)))
    for k in range(n):
        culm(m, pts[k], pts[(k + 1) % n], r, lod, seg=4)
    return m


def woodpile(name, lod):
    m = new(name + ('_l1' if lod else ''), '薪棚 1.60 × 0.45 × 0.85：割木を井桁に積み、板屋根')
    rng = random.Random(741)
    W, D = 1.60, 0.45
    leg(m, -W / 2, 0.0, 0.95, 0.05, AGED)
    leg(m, W / 2, 0.0, 0.95, 0.05, AGED)
    board(m, (-W / 2 - 0.08, 0.95, -D / 2 - 0.05), (W / 2 + 0.08, 0.98, D / 2 + 0.08), (0.46, 0.42, 0.36))
    rows = 4 if lod else 6
    for j in range(rows):
        y = 0.02 + j * 0.13
        n = 6 if lod else 11
        for i in range(n):
            x = -W / 2 + 0.08 + (W - 0.16) * (i + 0.5) / n + rng.uniform(-0.01, 0.01)
            s = rng.uniform(0.045, 0.065)
            m.cyl((x, y + s, -D / 2 + 0.02), (x, y + s, D / 2 - 0.02), s, s * rng.uniform(0.9, 1.05), 5 if lod else 6, WD,
                  (0.74 + rng.uniform(-0.06, 0.06), 0.64, 0.50), caps=(True, True))
    return m


def ishikeri(name, lod):
    m = new(name + ('_l1' if lod else ''), '石蹴り：棒で地面に引いた線（溝の陰）1–2–1–2–1、0.9 × 2.7、y 0.008')
    rng = random.Random(751)
    s = 0.45
    rows = [1, 2, 1, 2, 1]
    w = 0.028
    y = 0.008
    col = (0.30, 0.26, 0.22)

    def seg(a, b):
        dx, dz = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dz)
        nx, nz = -dz / L * w / 2, dx / L * w / 2
        j = rng.uniform(-0.012, 0.012)
        m.poly([(a[0] - nx, y, a[1] - nz + j), (a[0] + nx, y, a[1] + nz + j), (b[0] + nx, y, b[1] + nz), (b[0] - nx, y, b[1] - nz)][::-1],
               SK, col, uvs=[(AT['wood_light'][0], AT['wood_light'][1])] * 4)
    z = -len(rows) * s / 2
    for n in rows:
        x0 = -s * n / 2
        seg((x0, z), (x0 + s * n, z))
        seg((x0, z + s), (x0 + s * n, z + s))
        for k in range(n + 1):
            seg((x0 + k * s, z), (x0 + k * s, z + s))
        z += s
    return m


def build_all():
    for lod in (0, 1):
        getabako('sk_getabako', lod)
        zori('sk_zori', lod)
        bench('sk_bench', lod)
        box('sk_box', lod)
        teoke('sk_teoke', lod)
        tensui('sk_tensui', lod)
        hanshi('sk_hanshi', lod)
        fuda('sk_fuda', lod)
        toban('sk_toban', lod)
        temari('sk_temari', lod)
        hoop('sk_hoop', lod)
        woodpile('sk_woodpile', lod)
        ishikeri('sk_ishikeri', lod)


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
    K.export_glb(bpy, OUT + '/src/school_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_school_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=school_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[SKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/school_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[SKIT]   %-13s %5d 面  LOD1 %4d  dims %s  %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims'], v['mats']))


main()
