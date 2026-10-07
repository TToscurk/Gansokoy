"""人間之里 V2 P9 R4-5：火見櫓周邊 消防・瞭望 Kit（tower_kit）— 新資產（村の防火設備の実用品）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_tower_kit.py

材質：V2_Wood（_matlib、world 尺度 UV）、V2_Metal（_matlib：鳶口・刺股の鉄、箍）、SK_School（R4-3 已核准 atlas 的稲藁 region，只讀）。
火見櫓 Hero 本體（P5 R5）不動。座標：Godot（x 右、y 上、+z 前）；原點＝接地點（y 0）；單位 m。
  tk_okeyama   用水桶積み：台 1.05 × 0.55 × 0.30 ＋ 手桶 6（3-2-1、柿渋の赤茶、黒箍）
  tk_ladder    予備梯子 3.6 m（幅 0.46、桟 11）を枕木 2 本の上に寝かせる
  tk_rack      道具掛け：柱 2（2.1）＋横木 2（屋根なし）、鳶口 2・刺股 1・掛矢 1（頭は横木の上、正面＝+z）
  tk_rope      縄の束（地面、Ø0.52、4 巻＋垂れ端）
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
OUT = G + '/assets/village_v2/tower_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
AT = K.load_json(G + '/assets/village_v2/school_kit/atlas.json')['regions']
WD = 'V2_Wood'
MT = 'V2_Metal'
SK = 'SK_School'
MATS = [WD, MT, SK]
TILE = {WD: ML['V2_Wood']['tile_m'], MT: ML['V2_Metal']['tile_m'], SK: 1.0}

WOODC = (0.84, 0.78, 0.68)
AGED = (0.66, 0.62, 0.56)
DARK = (0.28, 0.25, 0.22)
KAKI = (0.62, 0.30, 0.20)       # 柿渋塗りの用水桶（赤茶）
KAKI2 = (0.55, 0.27, 0.18)
IRON = (0.62, 0.62, 0.64)       # 鉄（明るめ：暗い木の前でも鉤の形が読める）
ROPE = (0.80, 0.72, 0.56)

MODS = {}
INFO = {}


def new(name, note=''):
    m = K.Mesh(name, MATS, TILE)
    MODS[name] = m
    INFO[name] = note
    return m


def board(m, lo, hi, col=WOODC):
    m.box(lo, hi, WD, col)


def bucket(m, c, r0, r1, h, seg, col, lod):
    """手桶：c＝底中心。側板（外）＋内側（暗）＋黒箍 2＋取っ手板。"""
    x, y, z = c
    m.cyl((x, y, z), (x, y + h, z), r0, r1, seg, WD, col, caps=(True, False))
    m.cyl((x, y + h, z), (x, y + 0.03, z), r1 - 0.012, r0 - 0.012, seg, WD, DARK, caps=(False, True))
    if not lod:
        for t in (0.2, 0.8):
            yy = y + h * t
            rr = r0 + (r1 - r0) * t + 0.006
            m.cyl((x, yy - 0.012, z), (x, yy + 0.012, z), rr, rr, seg, MT, DARK, caps=(False, False))
        # 取っ手（両側の耳板＋渡し）
        board(m, (x - 0.018, y + h - 0.02, z - r1 - 0.012), (x + 0.018, y + h + 0.09, z - r1 + 0.012), col)
        board(m, (x - 0.018, y + h - 0.02, z + r1 - 0.012), (x + 0.018, y + h + 0.09, z + r1 + 0.012), col)
        board(m, (x - 0.022, y + h + 0.07, z - r1), (x + 0.022, y + h + 0.10, z + r1), AGED)


def okeyama(name, lod):
    m = new(name + ('_l1' if lod else ''), '用水桶積み：台 1.05 × 0.55 × 0.30＋手桶 6（3-2-1、柿渋）')
    W, D, H = 1.05, 0.55, 0.30
    board(m, (-W / 2, H - 0.04, -D / 2), (W / 2, H, D / 2), AGED)
    for x in (-W / 2 + 0.06, W / 2 - 0.06):
        for z in (-D / 2 + 0.06, D / 2 - 0.06):
            board(m, (x - 0.035, -0.03, z - 0.035), (x + 0.035, H - 0.04, z + 0.035), AGED)
    board(m, (-W / 2 + 0.06, 0.08, -0.02), (W / 2 - 0.06, 0.12, 0.02), AGED)
    seg = 8 if lod else 14
    r0, r1, h = 0.13, 0.15, 0.27
    rng = random.Random(4521)
    rows = [(-0.33, 0.0, 0.33), (-0.165, 0.165), (0.0,)]
    y = H
    for j, row in enumerate(rows):
        for x in row:
            col = KAKI if rng.random() > 0.4 else KAKI2
            bucket(m, (x + rng.uniform(-0.01, 0.01), y, rng.uniform(-0.01, 0.01)), r0, r1, h, seg, col, lod)
        y += h
    return m


def ladder(name, lod):
    m = new(name + ('_l1' if lod else ''), '予備梯子 3.6 × 0.46（桟 11）＋枕木 2（0.70 × 0.12 × 0.12）')
    L, Wd = 3.6, 0.46
    for x in (-1.2, 1.2):
        board(m, (x - 0.06, 0.0, -0.35), (x + 0.06, 0.12, 0.35), (0.50, 0.46, 0.40))
    y0 = 0.12
    for z in (-Wd / 2, Wd / 2):
        m.beam((-L / 2, y0 + 0.035, z), (L / 2, y0 + 0.035, z), 0.055, 0.07, WD, AGED)
    n = 11
    for i in range(n):
        x = -L / 2 + 0.18 + i * (L - 0.36) / (n - 1)
        m.cyl((x, y0 + 0.04, -Wd / 2), (x, y0 + 0.04, Wd / 2), 0.02, 0.02, 4 if lod else 6, WD, WOODC, caps=(False, False))
    return m


def tobiguchi(m, base, h, lod, lean=0.0):
    """鳶口：樫の柄 Ø0.036＋先端の鉄鳶（鉤）。base＝柄の下端。"""
    x, y, z = base
    top = (x, y + h, z + lean)
    m.cyl((x, y, z), top, 0.024, 0.022, 4 if lod else 6, WD, (0.74, 0.62, 0.46), caps=(True, True))
    # 鉄の鳶：柄の先から横に突き出して下へ曲がる
    a = (top[0], top[1] - 0.03, top[2])
    b = (top[0], top[1] + 0.03, top[2] + 0.22)
    c = (top[0], top[1] - 0.11, top[2] + 0.31)
    m.beam(a, b, 0.04, 0.045, MT, IRON)
    m.beam(b, c, 0.034, 0.04, MT, IRON)
    m.cyl((top[0], top[1] - 0.13, top[2]), (top[0], top[1] + 0.04, top[2]), 0.032, 0.032, 6, MT, IRON, caps=(True, True))


def sasumata(m, base, h, lod):
    x, y, z = base
    top = (x, y + h, z)
    m.cyl((x, y, z), top, 0.024, 0.022, 4 if lod else 6, WD, (0.74, 0.62, 0.46), caps=(True, True))
    # U 字の鉄叉（横木と平行な面に開く＝正面から U が読める）
    m.beam((x - 0.22, top[1] - 0.02, z), (x + 0.22, top[1] - 0.02, z), 0.04, 0.04, MT, IRON)
    for s in (-1, 1):
        m.beam((x + s * 0.22, top[1] - 0.02, z), (x + s * 0.25, top[1] + 0.26, z), 0.034, 0.034, MT, IRON)


def kakeya(m, base, lod):
    """掛矢（大槌）：柄を斜めに立てかけ、頭は地面。"""
    x, y, z = base
    head = (x, y + 0.11, z)
    m.cyl((x - 0.16, head[1], z), (x + 0.16, head[1], z), 0.10, 0.10, 6 if lod else 10, WD, AGED, caps=(True, True))
    m.cyl((x, head[1] + 0.05, z), (x + 0.05, head[1] + 0.92, z - 0.30), 0.022, 0.02, 5, WD, (0.70, 0.60, 0.46), caps=(False, True))


def coil(m, c, R, r, turns, lod, col=ROPE, flat=True):
    """縄の巻き束（稲藁 atlas）。flat＝地面に寝かせて上へ巻き重ね、False＝縦に掛ける（x 軸回り）。"""
    s = AT['straw']
    n = 10 if lod else 18
    for t in range(turns):
        rr = R - t * 0.012
        for k in range(n):
            a0 = 2 * math.pi * k / n
            a1 = 2 * math.pi * (k + 1) / n
            if flat:
                p0 = (c[0] + math.cos(a0) * rr, c[1] + r + t * r * 1.7, c[2] + math.sin(a0) * rr)
                p1 = (c[0] + math.cos(a1) * rr, c[1] + r + t * r * 1.7, c[2] + math.sin(a1) * rr)
            else:
                p0 = (c[0] + t * r * 1.7, c[1] + math.cos(a0) * rr, c[2] + math.sin(a0) * rr)
                p1 = (c[0] + t * r * 1.7, c[1] + math.cos(a1) * rr, c[2] + math.sin(a1) * rr)
            m.cyl(p0, p1, r, r, 4 if lod else 5, SK, col, caps=(False, False), uv_atlas=(s[0], s[1], s[2], s[3]))


def rack(name, lod):
    m = new(name + ('_l1' if lod else ''), '道具掛け 2.0 m：柱 2（2.10、埋 0.30）＋横木 2（屋根なし）、鳶口 2・刺股 1・掛矢 1（頭は横木の上へ）')
    for x in (-0.95, 0.95):
        board(m, (x - 0.045, -0.30, -0.045), (x + 0.045, 2.10, 0.045), AGED)
    m.beam((-1.05, 1.92, 0.0), (1.05, 1.92, 0.0), 0.07, 0.08, WD, AGED)
    m.beam((-1.0, 0.42, 0.0), (1.0, 0.42, 0.0), 0.06, 0.06, WD, AGED)
    if not lod:
        # 掛け釘（横木の前）
        for x in (-0.62, -0.22, 0.22, 0.62):
            m.cyl((x, 1.86, 0.04), (x, 1.88, 0.12), 0.012, 0.012, 4, WD, DARK, caps=(False, True))
        # 柱頭の小さな笠木（屋根は付けない：道具の頭を空に抜く）
        for x in (-0.95, 0.95):
            board(m, (x - 0.07, 2.10, -0.07), (x + 0.07, 2.13, 0.07), (0.50, 0.46, 0.40))
    # 道具：横木の前に立て掛け（下端は地面から 0.04）
    # 道具の頭は横木（1.92）より上へ 0.3–0.5 m 出す＝空を背景に鉤・叉の形が読める
    tobiguchi(m, (-0.62, 0.04, 0.10), 2.42, lod, lean=-0.04)
    tobiguchi(m, (-0.22, 0.04, 0.10), 2.28, lod, lean=-0.04)
    sasumata(m, (0.30, 0.04, 0.10), 2.36, lod)
    kakeya(m, (0.70, 0.0, 0.32), lod)
    return m


def rope(name, lod):
    m = new(name + ('_l1' if lod else ''), '縄の束（地面）Ø0.52、4 巻＋垂れ端')
    coil(m, (0.0, 0.0, 0.0), 0.26, 0.024, 4, lod)
    if not lod:
        s = AT['straw']
        pts = [(0.26, 0.03, 0.0), (0.38, 0.025, 0.10), (0.50, 0.025, 0.06), (0.62, 0.025, 0.14)]
        for a, b in zip(pts, pts[1:]):
            m.cyl(a, b, 0.022, 0.022, 5, SK, ROPE, caps=(False, False), uv_atlas=(s[0], s[1], s[2], s[3]))
    return m


def build_all():
    for lod in (0, 1):
        okeyama('tk_okeyama', lod)
        ladder('tk_ladder', lod)
        rack('tk_rack', lod)
        rope('tk_rope', lod)


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
    K.export_glb(bpy, OUT + '/src/tower_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_tower_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=tower_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[TKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/tower_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[TKIT]   %-11s %5d 面  LOD1 %4d  dims %s  %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims'], v['mats']))


main()
