"""人間之里 V2 P9 R4-4：水車／龍神像周邊 水邊 Kit（waterside_kit）— 新資產。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_waterside_kit.py

材質：WK_Plant（新；無貼圖、頂點色＝sRGB 反照率、雙面、薄透光）、V2_Wood（_matlib）、V2_KitStoneTri（machiya_kit 三面投影石）、
     SK_School（R4-3 已核准 atlas 的稲藁 region，只讀）。水車／龍神像 Hero 本體（P5）不動。
座標：Godot（x 右、y 上、+z 前）；原點＝接地點（y 0）；單位 m。
  wk_reed      蘆叢 Ø≈1.4、高 1.6–2.3（新芽綠葉＋去年枯稈＋穗）     wk_reed_s   小蘆叢 Ø≈0.9、高 1.1–1.5
  wk_iris      花菖蒲葉叢 Ø≈0.7、高 0.55–0.8（劍葉扇形＋花 3）      wk_sedge    菅草叢 Ø≈0.6、高 0.35–0.5（細葉垂弧）
  wk_tawara    米俵 Ø0.46 × 0.74（稲藁＋縄 3 道）                   wk_tawara3  米俵 3 俵積み（2＋1）
  wk_usu       石臼（下臼平置き＋上臼立てかけ）                     wk_sonae    龍神像前の供物台（石台＋三方＋瓶子 2＋榊）
  *_l1         LOD1
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/waterside_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(G + '/assets/village_v2/school_kit/atlas.json')['regions']
PL = 'WK_Plant'
WD = 'V2_Wood'
ST = 'V2_KitStoneTri'
SK = 'SK_School'
MATS = [PL, WD, ST, SK]
TILE = {PL: 1.0, WD: ML['V2_Wood']['tile_m'], ST: 1.0, SK: 1.0}

C_NEW = (0.36, 0.46, 0.19)      # 新芽（sRGB）
C_NEW2 = (0.44, 0.52, 0.22)
C_DRY = (0.66, 0.58, 0.40)      # 去年の枯れ稈
C_DRY2 = (0.58, 0.49, 0.33)
C_PLUME = (0.52, 0.43, 0.33)
C_IRIS = (0.30, 0.43, 0.20)
C_SEDGE = (0.42, 0.48, 0.24)
C_SEDGE2 = (0.55, 0.53, 0.30)
C_FLOWER = (0.38, 0.30, 0.62)
WOODC = (0.86, 0.80, 0.70)
WHITE = (0.86, 0.85, 0.80)
SAKAKI = (0.18, 0.30, 0.12)

MODS = {}
INFO = {}


def new(name, note=''):
    m = K.Mesh(name, MATS, TILE)
    MODS[name] = m
    INFO[name] = note
    return m


def blade(m, base, yaw, h, w, lean, bend, col, segs=4):
    """草葉一枚：base 起、yaw 方向に lean（線形）＋ bend（二次）で傾く。幅は先細り。"""
    d = (math.sin(yaw), 0.0, math.cos(yaw))
    side = (math.cos(yaw), 0.0, -math.sin(yaw))
    pts = []
    for i in range(segs + 1):
        t = i / segs
        off = lean * h * t + bend * h * t * t
        y = h * t * (1.0 - 0.35 * bend * t)
        pts.append((base[0] + d[0] * off, base[1] + y, base[2] + d[2] * off))
    for i in range(segs):
        t0, t1 = i / segs, (i + 1) / segs
        w0 = w * (1.0 - t0) ** 0.7
        w1 = w * (1.0 - t1) ** 0.7
        p0, p1 = pts[i], pts[i + 1]
        a = (p0[0] - side[0] * w0 / 2, p0[1], p0[2] - side[2] * w0 / 2)
        b = (p0[0] + side[0] * w0 / 2, p0[1], p0[2] + side[2] * w0 / 2)
        if i == segs - 1:
            m.poly([a, b, p1], PL, col, uvs=[(0, 0), (1, 0), (0.5, 1)])
        else:
            c = (p1[0] + side[0] * w1 / 2, p1[1], p1[2] + side[2] * w1 / 2)
            dd = (p1[0] - side[0] * w1 / 2, p1[1], p1[2] - side[2] * w1 / 2)
            m.poly([a, b, c, dd], PL, col, uvs=[(0, 0), (1, 0), (1, 1), (0, 1)])
    return pts[-1]


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def reed_clump(name, lod, R, Hmin, Hmax, n_new, n_dry, seed):
    m = new(name + ('_l1' if lod else ''), '蘆叢 Ø%.1f、高 %.1f–%.1f（新芽＋去年枯稈＋穗）' % (R * 2, Hmin, Hmax))
    rnd = random.Random(seed)
    k = 0.45 if lod else 1.0
    for _ in range(int(n_dry * k)):
        a = rnd.uniform(0, math.tau)
        r = R * math.sqrt(rnd.random()) * 0.85
        b = (math.cos(a) * r, -0.04, math.sin(a) * r)
        h = rnd.uniform(Hmin, Hmax)
        yaw = a + rnd.uniform(-0.6, 0.6)
        lean = rnd.uniform(0.02, 0.10)
        col = mix(C_DRY, C_DRY2, rnd.random())
        # 稈（細い板 2 枚十字）
        top = blade(m, b, yaw, h, 0.018, lean, 0.03, col, 2 if lod else 3)
        if not lod:
            blade(m, b, yaw + math.pi / 2, h * 0.98, 0.016, lean, 0.03, col, 3)
        # 穂：垂れる羽毛状 2 枚
        for s in ((0.0, 1.0),) if lod else ((0.0, 1.0), (math.pi / 2, 0.9)):
            blade(m, (top[0], top[1] - 0.03, top[2]), yaw + s[0] + 0.3, 0.30 * s[1], 0.075, 0.55, 0.45,
                  mix(C_PLUME, C_DRY, rnd.random() * 0.4), 2)
        # 枯れ葉 1–2 枚（稈から斜めに）
        for j in range(1 if lod else 2):
            y0 = h * rnd.uniform(0.25, 0.6)
            blade(m, (b[0], b[1] + y0, b[2]), yaw + rnd.uniform(-2.5, 2.5), h * 0.35, 0.03, 0.8, 0.5, col, 2)
    for _ in range(int(n_new * k)):
        a = rnd.uniform(0, math.tau)
        r = R * math.sqrt(rnd.random())
        b = (math.cos(a) * r, -0.04, math.sin(a) * r)
        h = rnd.uniform(Hmin * 0.45, Hmin * 0.85)
        col = mix(C_NEW, C_NEW2, rnd.random())
        blade(m, b, a + rnd.uniform(-1.0, 1.0), h, rnd.uniform(0.035, 0.05), rnd.uniform(0.15, 0.45), rnd.uniform(0.2, 0.55),
              col, 2 if lod else 4)
    return m


def iris(name, lod):
    m = new(name + ('_l1' if lod else ''), '花菖蒲葉叢（劍葉扇形 3 株＋花 3）')
    rnd = random.Random(31)
    for fan in range(3):
        a = fan * 2.1 + 0.4
        c = (math.cos(a) * 0.17, -0.03, math.sin(a) * 0.17)
        fy = rnd.uniform(0, math.pi)
        for i in range(4 if lod else 7):
            yaw = fy + (i - 3) * 0.16
            blade(m, c, yaw, rnd.uniform(0.55, 0.8), 0.045, (i - 3) * 0.05, rnd.uniform(0.0, 0.15),
                  mix(C_IRIS, C_NEW2, rnd.random() * 0.4), 2 if lod else 4)
        if not lod:
            # 花：茎＋花弁 3（紫）
            top = blade(m, c, fy + 1.5, 0.72, 0.012, 0.02, 0.0, C_IRIS, 2)
            for p in range(3):
                blade(m, top, p * 2.09 + fy, 0.09, 0.06, 0.9, 0.8, C_FLOWER, 2)
    return m


def sedge(name, lod):
    m = new(name + ('_l1' if lod else ''), '菅草叢（細葉垂弧）')
    rnd = random.Random(53)
    for i in range(14 if lod else 34):
        a = rnd.uniform(0, math.tau)
        r = 0.08 * rnd.random()
        blade(m, (math.cos(a) * r, -0.02, math.sin(a) * r), a, rnd.uniform(0.35, 0.5), 0.022,
              rnd.uniform(0.25, 0.6), rnd.uniform(0.4, 0.9), mix(C_SEDGE, C_SEDGE2, rnd.random()), 2 if lod else 3)
    return m


def straw_prism(m, c, axis, r, L, seg, lod):
    """稲藁の俵：axis＝'x' 方向に横たわる多角柱（SK_School straw region）＋縄 3 道＋桟俵（両端）。"""
    s = AT['straw']
    rings = []
    for e in (-1, 1):
        ring = []
        for k in range(seg):
            a = k / seg * math.tau
            ring.append((c[0] + e * L / 2, c[1] + math.sin(a) * r, c[2] + math.cos(a) * r))
        rings.append(ring)
    for k in range(seg):
        a0, a1 = rings[0][k], rings[0][(k + 1) % seg]
        b0, b1 = rings[1][k], rings[1][(k + 1) % seg]
        m.rect_uv(a1, b1, b0, a0, SK, s, 1.0)
    for e, ring in ((-1, rings[0]), (1, rings[1])):
        cen = (c[0] + e * (L / 2 + 0.01), c[1], c[2])
        for k in range(seg):
            p0, p1 = ring[k], ring[(k + 1) % seg]
            tri = [cen, p0, p1] if e > 0 else [cen, p1, p0]
            m.poly(tri, SK, 0.85, uvs=[((s[0] + s[2]) / 2, (s[1] + s[3]) / 2), (s[0], s[1]), (s[2], s[3])])
    if not lod:
        for t in (-0.32, 0.0, 0.32):
            x = c[0] + t * L
            m.cyl((x - 0.012, c[1], c[2]), (x + 0.012, c[1], c[2]), r + 0.012, r + 0.012, seg, PL, (0.45, 0.36, 0.22),
                  caps=(False, False))


def tawara(name, lod):
    m = new(name + ('_l1' if lod else ''), '米俵 Ø0.46 × 0.74')
    straw_prism(m, (0.0, 0.215, 0.0), 'x', 0.23, 0.74, 7 if lod else 10, lod)
    return m


def tawara3(name, lod):
    m = new(name + ('_l1' if lod else ''), '米俵 3 俵積み（2＋1）')
    sg = 7 if lod else 10
    straw_prism(m, (0.0, 0.215, -0.23), 'x', 0.23, 0.74, sg, lod)
    straw_prism(m, (0.03, 0.215, 0.23), 'x', 0.23, 0.74, sg, lod)
    straw_prism(m, (0.015, 0.60, 0.0), 'x', 0.23, 0.74, sg, lod)
    return m


def usu(name, lod):
    m = new(name + ('_l1' if lod else ''), '石臼：下臼 Ø0.56 平置き＋上臼 Ø0.52 立てかけ＋木柄')
    sg = 10 if lod else 18
    m.cyl((0.0, -0.04, 0.0), (0.0, 0.20, 0.0), 0.28, 0.27, sg, ST, 0.82)
    # 上臼：立てかけ（x 軸回りに傾く円盤、下臼の横）
    tilt = math.radians(68)
    c = (0.44, 0.0, 0.05)
    up = (0.0, math.sin(tilt), math.cos(tilt))
    p0 = (c[0], 0.24 * math.cos(tilt) * 0 + 0.02, c[2] - 0.09)
    p0 = (0.44, 0.255, 0.0)
    p1 = (0.44 + 0.0, 0.255 + up[2] * 0.0, 0.0)
    m.cyl((0.30, 0.255, 0.04), (0.50, 0.25, 0.10), 0.26, 0.26, sg, ST, 0.78)
    if not lod:
        m.cyl((0.50, 0.40, 0.12), (0.62, 0.43, 0.16), 0.025, 0.025, 6, WD, WOODC)
    return m


def sonae(name, lod):
    m = new(name + ('_l1' if lod else ''), '供物台：石台 0.90 × 0.50 × 0.42＋三方＋瓶子 2＋榊')
    m.box((-0.45, -0.05, -0.25), (0.45, 0.42, 0.25), ST, 0.86)
    # 三方
    m.box((-0.14, 0.42, -0.14), (0.14, 0.54, 0.14), WD, WOODC)
    m.box((-0.17, 0.54, -0.17), (0.17, 0.57, 0.17), WD, WOODC)
    if not lod:
        for k in range(5):  # 供物（白い丸餅）
            a = k / 5 * math.tau
            m.cyl((math.cos(a) * 0.06, 0.57, math.sin(a) * 0.06), (math.cos(a) * 0.06, 0.60, math.sin(a) * 0.06), 0.035, 0.03, 6,
                  PL, WHITE)
    for sx in (-0.32, 0.32):
        sg = 6 if lod else 10
        m.cyl((sx, 0.42, 0.0), (sx, 0.50, 0.0), 0.05, 0.065, sg, PL, WHITE)
        m.cyl((sx, 0.50, 0.0), (sx, 0.62, 0.0), 0.065, 0.025, sg, PL, WHITE)
        # 榊
        rnd = random.Random(int(sx * 100))
        for i in range(3 if lod else 8):
            blade(m, (sx, 0.60, 0.0), rnd.uniform(0, math.tau), rnd.uniform(0.18, 0.26), 0.05, rnd.uniform(0.2, 0.5),
                  rnd.uniform(0.1, 0.4), SAKAKI, 2)
    return m


def build_all():
    for lod in (0, 1):
        reed_clump('wk_reed', lod, 0.70, 1.6, 2.3, 26, 34, 11)
        reed_clump('wk_reed_s', lod, 0.45, 1.1, 1.5, 16, 16, 23)
        iris('wk_iris', lod)
        sedge('wk_sedge', lod)
        tawara('wk_tawara', lod)
        tawara3('wk_tawara3', lod)
        usu('wk_usu', lod)
        sonae('wk_sonae', lod)


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
    os.makedirs(OUT + '/src', exist_ok=True)
    K.export_glb(bpy, OUT + '/src/waterside_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_waterside_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=waterside_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[WKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/waterside_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[WKIT]   %-11s %5d 面  LOD1 %4d  dims %s  %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims'], v['mats']))


main()
