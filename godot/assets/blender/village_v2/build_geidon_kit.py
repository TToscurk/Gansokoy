"""人間之里 V2 P9 R4-7：鯢吞亭周邊 居酒屋の生活 Kit（geidon_kit）— 新資產（飲みに来た人が腰を下ろす痕跡）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_geidon_kit.py

材質：V2_Wood（_matlib、world 尺度 UV）、SK_School（R4-3 已核准 atlas：稲藁＝菰・縄、和紙＝品書き・樽の札，只讀）、
V2_Geidontei（鯢吞亭 Hero atlas 的非發光色票：象牙＝徳利・猪口・盛り塩，近黑＝鉄，只讀；紅提燈 region 會發光，不用）。
鯢吞亭 Hero 本體（P5 R2）不動。座標：Godot（x 右、y 上、+z 前）；原點＝接地點（y 0）；單位 m。
  gd_taruzumi  菰樽積み：低い台 1.45 × 0.56 ＋ 菰樽 3＋2（Ø0.46 × 0.52、縄三段、和紙の札）
  gd_taru      樽卓（空き樽を卓に）Ø0.48 × 0.62、竹箍 2、蓋
  gd_shogi     床几（縁台）1.60 × 0.55、座面 0.42、緋毛氈（前へ少し垂らす）
  gd_tray      盆 0.32 × 0.22 ＋ 徳利 1 ＋ 猪口 2（縁台・樽卓に載せる）
  gd_fuda      品書き：柱 2（1.50、埋 0.30）＋板 0.90 × 0.62 ＋短冊 6（和紙）＋小屋根
  gd_morijio   盛り塩：小皿 Ø0.13 ＋ 円錐 h0.08
  gd_chochin   赤提灯の柱：柱 2.05＋腕木＋赤提灯 Ø0.34 × 0.50（紅提燈 region＝發光；外の席の目印）
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
OUT = G + '/assets/village_v2/geidon_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
GDA = K.load_json(G + '/assets/village_v2/geidontei/atlas.json')
SWATCH = {k: v['uv'] for k, v in GDA['swatches'].items()}
AT = K.load_json(G + '/assets/village_v2/school_kit/atlas.json')['regions']
WD = 'V2_Wood'
GD = 'V2_Geidontei'
SK = 'SK_School'
MATS = [WD, GD, SK]
TILE = {WD: ML['V2_Wood']['tile_m'], GD: 1.0, SK: 1.0}

WOODC = (0.84, 0.78, 0.68)
AGED = (0.66, 0.62, 0.56)
DARK = (0.30, 0.26, 0.22)
ROPE = (0.46, 0.39, 0.28)
FELT = (0.95, 0.22, 0.16)        # 緋毛氈（木地に赤の頂點色：發光する紅提燈 region は使わない）
LACQ = (0.40, 0.14, 0.10)        # 盆の朱漆（暗め）

MODS = {}
INFO = {}


def new(name, note=''):
    m = K.Mesh(name, MATS, TILE)
    MODS[name] = m
    INFO[name] = note
    return m


def sw(hexcol):
    u, v = SWATCH[hexcol]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


def board(m, lo, hi, col=WOODC):
    m.box(lo, hi, WD, col)


def komodaru(m, c, lod, rng):
    """菰樽：c＝底中心。菰（稲藁 atlas）の胴＋木蓋＋縄三段＋正面の和紙札。"""
    x, y, z = c
    r, h = 0.23, 0.52
    seg = 8 if lod else 14
    s = AT['straw']
    m.cyl((x, y, z), (x, y + h, z), r * 0.96, r, seg, SK, (0.92, 0.84, 0.66), caps=(False, False), uv_atlas=s)
    m.cyl((x, y + h, z), (x, y + h + 0.025, z), r * 0.92, r * 0.85, seg, WD, AGED, caps=(False, True))
    if not lod:
        for t in (0.12, 0.5, 0.88):
            yy = y + h * t
            m.cyl((x, yy - 0.012, z), (x, yy + 0.012, z), r + 0.008, r + 0.008, seg, SK, ROPE, caps=(False, False), uv_atlas=s)
    # 札（正面 +z、和紙）
    a = rng.uniform(-0.15, 0.15)
    ca, sa = math.cos(a), math.sin(a)
    w2, hh = 0.09, 0.15
    zc = r + 0.004

    def P(dx, dy):
        return (x + dx * ca + zc * sa, y + h * 0.5 + dy, z - dx * sa + zc * ca)
    m.rect_uv(P(-w2, -hh), P(w2, -hh), P(w2, hh), P(-w2, hh), SK, AT['paper'], 0.85)
    # 銘柄の印（墨の角印）：遠目に「札」と読ませる
    if not lod:
        zc2 = zc + 0.003
        def Q(dx, dy):
            return (x + dx * ca + zc2 * sa, y + h * 0.5 + dy, z - dx * sa + zc2 * ca)
        m.rect_uv(Q(-0.05, -0.02), Q(0.05, -0.02), Q(0.05, 0.08), Q(-0.05, 0.08), GD, sw('#1E1B18'), 1.0)


def taruzumi(name, lod):
    m = new(name + ('_l1' if lod else ''), '菰樽積み：台 1.45 × 0.56 × 0.15 ＋ 菰樽 3＋2（Ø0.46 × 0.52）')
    W, D, H = 1.45, 0.56, 0.15
    board(m, (-W / 2, H - 0.035, -D / 2), (W / 2, H, D / 2), AGED)
    for x in (-W / 2 + 0.05, W / 2 - 0.05):
        board(m, (x - 0.04, 0.0, -D / 2 + 0.03), (x + 0.04, H - 0.035, D / 2 - 0.03), DARK)
    rng = random.Random(4721)
    for x in (-0.48, 0.0, 0.48):
        komodaru(m, (x + rng.uniform(-0.01, 0.01), H, rng.uniform(-0.02, 0.02)), lod, rng)
    for x in (-0.24, 0.24):
        komodaru(m, (x + rng.uniform(-0.01, 0.01), H + 0.545, rng.uniform(-0.02, 0.0)), lod, rng)
    return m


def taru(name, lod):
    m = new(name + ('_l1' if lod else ''), '樽卓：空き樽 Ø0.48 × 0.62（竹箍 2、蓋）')
    seg = 10 if lod else 16
    m.cyl((0, 0, 0), (0, 0.31, 0), 0.22, 0.245, seg, WD, AGED, caps=(True, False))
    m.cyl((0, 0.31, 0), (0, 0.62, 0), 0.245, 0.22, seg, WD, AGED, caps=(False, False))
    m.cyl((0, 0.62, 0), (0, 0.635, 0), 0.215, 0.215, seg, WD, WOODC, caps=(False, True))
    if not lod:
        for yy, rr in ((0.1, 0.235), (0.52, 0.235)):
            m.cyl((0, yy - 0.02, 0), (0, yy + 0.02, 0), rr + 0.006, rr + 0.006, seg, WD, (0.62, 0.58, 0.40), caps=(False, False))
    return m


def shogi(name, lod):
    m = new(name + ('_l1' if lod else ''), '床几 1.60 × 0.55、座面 0.42、緋毛氈')
    L, Dp, H = 1.60, 0.55, 0.42
    board(m, (-L / 2, H - 0.04, -Dp / 2), (L / 2, H - 0.012, Dp / 2), WOODC)
    for x in (-L / 2 + 0.08, L / 2 - 0.08):
        for z in (-Dp / 2 + 0.06, Dp / 2 - 0.06):
            board(m, (x - 0.03, 0.0, z - 0.03), (x + 0.03, H - 0.04, z + 0.03), AGED)
    if not lod:
        for z in (-Dp / 2 + 0.06, Dp / 2 - 0.06):
            board(m, (-L / 2 + 0.08, 0.10, z - 0.015), (L / 2 - 0.08, 0.13, z + 0.015), AGED)
    # 緋毛氈：座面の上＋前（+z）へ 0.12 垂らす
    m.box((-L / 2 + 0.03, H - 0.012, -Dp / 2 + 0.02), (L / 2 - 0.03, H, Dp / 2 + 0.01), WD, FELT)
    m.box((-L / 2 + 0.03, H - 0.13, Dp / 2 + 0.002), (L / 2 - 0.03, H, Dp / 2 + 0.012), WD, FELT)
    return m


def tray(name, lod):
    m = new(name + ('_l1' if lod else ''), '盆 0.32 × 0.22 ＋徳利 1（h0.16）＋猪口 2')
    board(m, (-0.16, 0.0, -0.11), (0.16, 0.012, 0.11), LACQ)
    if not lod:
        for sx in (-1, 1):
            board(m, (-0.16, 0.012, sx * 0.11 - 0.006), (0.16, 0.03, sx * 0.11 + 0.006), LACQ)
            board(m, (sx * 0.16 - 0.006, 0.012, -0.11), (sx * 0.16 + 0.006, 0.03, 0.11), LACQ)
    iv = sw('#E8DDC4')
    seg = 8 if lod else 12
    x, z = -0.06, 0.0
    m.cyl((x, 0.012, z), (x, 0.09, z), 0.035, 0.045, seg, GD, 1.0, caps=(True, False), uv_atlas=iv)
    m.cyl((x, 0.09, z), (x, 0.14, z), 0.045, 0.014, seg, GD, 1.0, caps=(False, False), uv_atlas=iv)
    m.cyl((x, 0.14, z), (x, 0.172, z), 0.014, 0.02, seg, GD, 1.0, caps=(False, True), uv_atlas=iv)
    for (cx, cz) in ((0.06, -0.05), (0.09, 0.05)):
        m.cyl((cx, 0.012, cz), (cx, 0.042, cz), 0.018, 0.028, seg, GD, 1.0, caps=(True, True), uv_atlas=iv)
    return m


def fuda(name, lod):
    m = new(name + ('_l1' if lod else ''), '品書き：柱 2（1.50、埋 0.30）＋板 0.90 × 0.62 ＋短冊 6（和紙）＋小屋根')
    for x in (-0.42, 0.42):
        board(m, (x - 0.035, -0.30, -0.035), (x + 0.035, 1.50, 0.035), AGED)
    board(m, (-0.46, 0.80, 0.035), (0.46, 1.42, 0.06), DARK)
    rng = random.Random(4722)
    for i in range(6):
        cx = -0.34 + i * 0.136
        h = rng.uniform(0.40, 0.50)
        top = 1.38
        m.rect_uv((cx - 0.05, top - h, 0.062), (cx + 0.05, top - h, 0.062), (cx + 0.05, top, 0.062), (cx - 0.05, top, 0.062), SK,
                  AT['paper'], 0.78)
    sl = math.atan2(0.08, 0.32)
    m.obox((0.0, 1.535, 0.08), (0.58, 0.015, 0.17), WD, (0.42, 0.38, 0.32), ay=(0.0, math.cos(sl), math.sin(sl)),
           az=(0.0, -math.sin(sl), math.cos(sl)))
    return m


def morijio(name, lod):
    m = new(name + ('_l1' if lod else ''), '盛り塩：小皿 Ø0.13 ＋ 円錐 h0.08')
    iv = sw('#E8DDC4')
    seg = 6 if lod else 10
    m.cyl((0, 0, 0), (0, 0.018, 0), 0.05, 0.065, seg, GD, 1.0, caps=(True, True), uv_atlas=iv)
    m.cyl((0, 0.018, 0), (0, 0.10, 0), 0.04, 0.003, seg, SK, 1.0, caps=(True, False), uv_atlas=AT['paper'])
    return m


def chochin(name, lod):
    m = new(name + ('_l1' if lod else ''), '赤提灯の柱：柱 2.05（埋 0.30）＋腕木 0.40 ＋赤提灯 Ø0.34 × 0.50（鯢吞亭の紅提燈 region、夜は灯る）')
    board(m, (-0.035, -0.30, -0.035), (0.035, 2.05, 0.035), AGED)
    board(m, (-0.03, 1.98, -0.03), (0.03, 2.03, 0.42), AGED)
    # 吊り紐＋提灯（上下の黒い輪、胴は少し膨らむ）
    zc = 0.36
    seg = 8 if lod else 12
    blk = sw('#1E1B18')
    red = GDA['regions']['red_0']
    m.cyl((0.0, 1.98, zc), (0.0, 1.88, zc), 0.006, 0.006, 4, GD, 1.0, caps=(False, False), uv_atlas=blk)
    y0, y1 = 1.34, 1.84
    m.cyl((0.0, y1 + 0.02, zc), (0.0, y1 - 0.02, zc), 0.10, 0.11, seg, GD, 1.0, caps=(True, False), uv_atlas=blk)
    m.cyl((0.0, y1 - 0.02, zc), (0.0, (y0 + y1) / 2, zc), 0.12, 0.17, seg, GD, 1.0, caps=(False, False), uv_atlas=red)
    m.cyl((0.0, (y0 + y1) / 2, zc), (0.0, y0 + 0.02, zc), 0.17, 0.12, seg, GD, 1.0, caps=(False, False), uv_atlas=red)
    m.cyl((0.0, y0 + 0.02, zc), (0.0, y0 - 0.02, zc), 0.11, 0.10, seg, GD, 1.0, caps=(False, True), uv_atlas=blk)
    return m


def build_all():
    for lod in (0, 1):
        chochin('gd_chochin', lod)
        taruzumi('gd_taruzumi', lod)
        taru('gd_taru', lod)
        shogi('gd_shogi', lod)
        tray('gd_tray', lod)
        fuda('gd_fuda', lod)
        morijio('gd_morijio', lod)


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
    K.export_glb(bpy, OUT + '/src/geidon_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_geidon_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=geidon_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[GDKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/geidon_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[GDKIT]   %-12s %5d 面  LOD1 %4d  dims %s  %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims'], v['mats']))


main()
