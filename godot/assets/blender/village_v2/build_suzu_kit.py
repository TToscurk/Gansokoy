"""人間之里 V2 P9 R4-6：鈴奈庵周邊 書店・貸本の生活 Kit（suzu_kit）— 新資產（借りに来た人が立ち止まる痕跡）。

  blender -b --factory-startup --python godot/assets/blender/village_v2/build_suzu_kit.py

材質：V2_Wood（_matlib、world 尺度 UV）、V2_Suzunaan（鈴奈庵 Hero atlas：書背・表紙・貸本板・和紙・風呂敷・色票，只讀重用）、
SK_School（R4-3 已核准 atlas 的稲藁 region＝縄，只讀）。鈴奈庵 Hero 本體（P5 R1）不動。
座標：Godot（x 右、y 上、+z 前）；原點＝接地點（y 0）；單位 m。
  sz_kanban   置き看板「貸本」：足 2＋柱 2（1.80）＋板 0.44 × 1.32（両面）＋笠木（全高 1.84）
  sz_keiji    掲示板（壁際に立てる）：柱 2（1.85、埋 0.30）＋板 1.30 × 0.70＋小屋根、貼紙 5（新刊の表紙 3・和紙 2）
  sz_hako     本箱（蓋なし）0.62 × 0.40 × 0.34、書背を上にして詰めた本
  sz_hako2    本箱 2 段（下＝蓋なし、上＝蓋＋縄十字、少し振る）
  sz_bundle   書冊束（和本 5 冊＋縄十字、上の 1 冊は表紙が見える）
  sz_stool    腰掛け 0.42 × 0.26、座面 0.40
  sz_dai      縁台 1.40 × 0.60、座面 0.40 ＋ 茣蓙＋虫干しの和本（開いた本 3・積み 3・紙束＋文鎮石）
  sz_seoi     貸本屋の背負い本箱（箱 3 段＋風呂敷包み＋負い紐、−z の壁へ少し寄り掛かる）
  sz_hachi    鉢植え（Ø0.30 陶鉢＋葉カード 3）
  *_l1        LOD1
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v2_kit as K  # noqa: E402

G = K.repo_paths(__file__)
OUT = G + '/assets/village_v2/suzu_kit'
ML = K.load_json(G + '/assets/village_v2/_matlib/matlib.json')['materials']
SZA = K.load_json(G + '/assets/village_v2/suzunaan/atlas.json')
RG = SZA['regions']
SWATCH = {k: v['uv'] for k, v in SZA['swatches'].items()}
AT = K.load_json(G + '/assets/village_v2/school_kit/atlas.json')['regions']
WD = 'V2_Wood'
SZ = 'V2_Suzunaan'
SK = 'SK_School'
MATS = [WD, SZ, SK]
TILE = {WD: ML['V2_Wood']['tile_m'], SZ: 1.0, SK: 1.0}

WOODC = (0.84, 0.78, 0.68)
AGED = (0.66, 0.62, 0.56)
DARK = (0.30, 0.26, 0.22)
ROPE = (0.46, 0.39, 0.28)       # 縄（明るいと棒に見える → 落ち着いた藁色・細め）

MODS = {}
INFO = {}


def new(name, note=''):
    m = K.Mesh(name, MATS, TILE)
    MODS[name] = m
    INFO[name] = note
    return m


def rsub(r, fx0, fy0, fx1, fy1):
    u0, v0, u1, v1 = r
    return [u0 + (u1 - u0) * fx0, v0 + (v1 - v0) * fy0, u0 + (u1 - u0) * fx1, v0 + (v1 - v0) * fy1]


def sw(hexcol):
    u, v = SWATCH[hexcol]
    return [u - 0.003, v - 0.003, u + 0.003, v + 0.003]


def cover(i):
    """表紙 i（0 百鬼夜行・1 妖魔本・2 竹取物語・3 今昔物語）"""
    return rsub(RG['covers'], i / 4, 0, (i + 1) / 4, 1)


def board(m, lo, hi, col=WOODC):
    m.box(lo, hi, WD, col)


def book(m, c, w, d, t, yaw, top, lod):
    """和本 1 冊（平置き）：c＝底中心、w×d、厚さ t；上面＝表紙 top（region）、側面＝書口の米白、背側は濃い色票。"""
    ca, sa = math.cos(yaw), math.sin(yaw)
    ax = (ca, 0.0, -sa)
    az = (sa, 0.0, ca)
    m.abox((c[0], c[1] + t / 2, c[2]), (w / 2, t / 2, d / 2), SZ,
           {'+y': top, '-x': sw('#3A2E22'), '*': sw('#B8AE96')}, 1.0, ax=ax, az=az, skip=('-y',) if lod else ())


def cord_cross(m, c, w, d, h, lod, yaw=0.0, y0=0.005):
    """縄十字（上面を十字に渡り 4 側面を下りる細い縄）：c＝底中心、w×d×h の包み（yaw 回転）に掛ける。"""
    s = AT['straw']
    r = 0.005
    ca, sa = math.cos(yaw), math.sin(yaw)

    def P(dx, dy, dz):
        return (c[0] + dx * ca + dz * sa, c[1] + dy, c[2] - dx * sa + dz * ca)
    top = h + r
    pts = [[P(-w / 2 - r, y0, 0), P(-w / 2 - r, top, 0), P(w / 2 + r, top, 0), P(w / 2 + r, y0, 0)],
           [P(0, y0, -d / 2 - r), P(0, top, -d / 2 - r), P(0, top, d / 2 + r), P(0, y0, d / 2 + r)]]
    for pl in pts:
        seq = pl if not lod else pl[1:3]
        for a, b in zip(seq, seq[1:]):
            m.cyl(a, b, r, r, 4, SK, ROPE, caps=(False, False), uv_atlas=s)


# ─────────────────────────── 構件 ───────────────────────────

def kanban(name, lod):
    m = new(name + ('_l1' if lod else ''), '置き看板「貸本」：足 2（0.50）＋柱 2（1.80）＋板 0.44 × 1.32（両面）＋笠木（全高 1.84）')
    # 實物の置き看板（行灯看板の寸法帯 1.5–1.9 m）：TPS 3–8 m で「貸本」が読める板幅
    for x in (-0.27, 0.27):
        board(m, (x - 0.035, 0.0, -0.25), (x + 0.035, 0.07, 0.25), AGED)
        board(m, (x - 0.03, 0.06, -0.03), (x + 0.03, 1.80, 0.03), AGED)
    # 板（表裏とも「貸本」）：atlas kashihon 1:3
    m.abox((0.0, 1.10, 0.0), (0.22, 0.66, 0.022), SZ, {'+z': RG['kashihon'], '-z': RG['kashihon'], '*': RG['sign_wood']}, 1.0)
    board(m, (-0.24, 0.40, -0.03), (0.24, 0.43, 0.03), AGED)
    # 笠木（小さな板屋根）
    board(m, (-0.33, 1.80, -0.12), (0.33, 1.84, 0.12), (0.46, 0.42, 0.36))
    return m


def keiji(name, lod):
    m = new(name + ('_l1' if lod else ''), '掲示板：柱 2（1.85、埋 0.30）＋板 1.30 × 0.70＋小屋根、貼紙 5（表紙 3・和紙 2）')
    for x in (-0.60, 0.60):
        board(m, (x - 0.04, -0.30, -0.04), (x + 0.04, 1.85, 0.04), AGED)
    # 板は白っぽい晒し板（壁の焼杉と分ける）、枠は濃い
    board(m, (-0.66, 0.95, 0.04), (0.66, 1.66, 0.07), (1.25, 1.18, 1.05))
    board(m, (-0.69, 1.64, 0.04), (0.69, 1.70, 0.095), DARK)
    board(m, (-0.69, 0.91, 0.04), (0.69, 0.97, 0.095), DARK)
    for x in (-0.66, 0.66):
        board(m, (x - 0.03, 0.95, 0.04), (x + 0.03, 1.66, 0.095), DARK)
    # 小屋根（前へ傾ける片流れ）
    sl = math.atan2(0.09, 0.36)
    m.obox((0.0, 1.775, 0.12), (0.78, 0.016, 0.186), WD, (0.42, 0.38, 0.32), ay=(0.0, math.cos(sl), math.sin(sl)),
           az=(0.0, -math.sin(sl), math.cos(sl)))
    # 貼紙：表紙 3（新刊案内）＋和紙 2；少し傾けて貼る
    rng = random.Random(4612)
    sheets = [(-0.45, 1.31, 0.25, 0.36, cover(1)), (-0.16, 1.33, 0.25, 0.36, cover(2)), (0.44, 1.29, 0.25, 0.36, cover(0)),
              (0.15, 1.13, 0.22, 0.26, RG['paper']), (0.15, 1.47, 0.20, 0.17, RG['paper']), (-0.30, 1.04, 0.30, 0.12, RG['paper'])]
    zf = 0.075
    for i, (cx, cy, w, h, r) in enumerate(sheets):
        a = rng.uniform(-0.05, 0.05)
        ca, sa = math.cos(a), math.sin(a)

        def P(dx, dy):
            return (cx + dx * ca - dy * sa, cy + dx * sa + dy * ca, zf + 0.001 * i)
        if r is RG['paper']:
            m.rect_uv(P(-w / 2, -h / 2), P(w / 2, -h / 2), P(w / 2, h / 2), P(-w / 2, h / 2), SK, AT['paper'], 1.0)
        else:
            m.rect_uv(P(-w / 2, -h / 2), P(w / 2, -h / 2), P(w / 2, h / 2), P(-w / 2, h / 2), SZ, r, 1.0)
        if not lod:
            # 留め釘（上 2 点）
            for dx in (-w / 2 + 0.02, w / 2 - 0.02):
                p = P(dx, h / 2 - 0.02)
                m.box((p[0] - 0.006, p[1] - 0.006, zf), (p[0] + 0.006, p[1] + 0.006, zf + 0.012), WD, DARK)
    return m


def crate(m, c, W, D, H, lod, books=True, lid=False, yaw=0.0, col=WOODC):
    """本箱：c＝底中心。側板 4＋底；books＝書背を上に詰めた本、lid＝蓋＋縄十字。"""
    ca, sa = math.cos(yaw), math.sin(yaw)
    ax = (ca, 0.0, -sa)
    az = (sa, 0.0, ca)

    def off(dx, dy, dz):
        return (c[0] + ax[0] * dx + az[0] * dz, c[1] + dy, c[2] + ax[2] * dx + az[2] * dz)
    t = 0.022
    for sz in (-1, 1):
        m.obox(off(0, H / 2, sz * (D / 2 - t / 2)), (W / 2, H / 2, t / 2), WD, col, ax=ax, az=az)
    for sx in (-1, 1):
        m.obox(off(sx * (W / 2 - t / 2), H / 2, 0), (t / 2, H / 2, D / 2 - t), WD, col, ax=ax, az=az)
    m.obox(off(0, 0.012, 0), (W / 2 - t, 0.012, D / 2 - t), WD, DARK, ax=ax, az=az)
    if not lod:
        # 手掛け（両妻の切り欠き代わりの濃い帯）＋角金具代わりの縁
        for sx in (-1, 1):
            m.obox(off(sx * (W / 2 + 0.002), H - 0.07, 0), (0.002, 0.018, 0.06), WD, DARK, ax=ax, az=az)
    if books:
        hb = H - 0.035
        m.abox(off(0, hb / 2 + 0.024, 0), (W / 2 - t, hb / 2, D / 2 - t), SZ,
               {'+y': rsub(RG['spines'], 0.1, 0.25, 0.1 + (W - 2 * t) / 2.5, 0.5), '*': sw('#3A2E22')}, 1.0, ax=ax, az=az,
               skip=('-y',))
    if lid:
        m.obox(off(0, H + 0.012, 0), (W / 2 + 0.01, 0.012, D / 2 + 0.01), WD, AGED, ax=ax, az=az)
        cord_cross(m, c, W + 0.02, D + 0.02, H + 0.024, lod, yaw=yaw, y0=H * 0.25)


def hako(name, lod):
    m = new(name + ('_l1' if lod else ''), '本箱（蓋なし）0.62 × 0.40 × 0.34、書背を上にして詰めた本')
    crate(m, (0.0, 0.0, 0.0), 0.62, 0.40, 0.34, lod)
    return m


def hako2(name, lod):
    m = new(name + ('_l1' if lod else ''), '本箱 2 段：下 0.62 × 0.40 × 0.34（蓋なし）＋上 0.56 × 0.36 × 0.30（蓋＋縄十字、+8°）')
    crate(m, (0.0, 0.0, 0.0), 0.62, 0.40, 0.34, lod, books=True)
    # 上の箱：下の箱の縁に載る（本の上ではなく縁の上：y 0.34）
    y0 = 0.34
    a = math.radians(8)
    crate(m, (0.01, y0, -0.01), 0.56, 0.36, 0.30, lod, books=False, lid=True, yaw=a, col=AGED)
    return m


def bundle(name, lod):
    m = new(name + ('_l1' if lod else ''), '書冊束：和本 5 冊（0.18 × 0.26 前後）＋縄十字、上の 1 冊は表紙')
    rng = random.Random(4613)
    y = 0.0
    covers = [sw('#B8AE96'), cover(3), sw('#B8AE96'), cover(2), cover(1)]
    for i in range(5):
        t = rng.uniform(0.018, 0.026)
        book(m, (rng.uniform(-0.01, 0.01), y, rng.uniform(-0.01, 0.01)), 0.18 + rng.uniform(-0.01, 0.01),
             0.26 + rng.uniform(-0.01, 0.01), t, rng.uniform(-0.06, 0.06), covers[i], lod)
        y += t
    cord_cross(m, (0.0, 0.0, 0.0), 0.18, 0.26, y, lod)
    return m


def stool(name, lod):
    m = new(name + ('_l1' if lod else ''), '腰掛け 0.42 × 0.26、座面 0.40')
    board(m, (-0.21, 0.37, -0.13), (0.21, 0.40, 0.13), WOODC)
    for x in (-0.16, 0.16):
        for z in (-0.09, 0.09):
            m.beam((x * 1.12, 0.0, z * 1.15), (x, 0.37, z), 0.034, 0.034, WD, AGED)
    if not lod:
        for z in (-0.09, 0.09):
            m.beam((-0.17, 0.14, z * 1.08), (0.17, 0.14, z * 1.08), 0.022, 0.022, WD, AGED)
    return m


def open_book(m, c, yaw, w, d, lod):
    """開いた和本（虫干し）：左右の頁が浅い V。c＝底中心、見開き w×d。"""
    ca, sa = math.cos(yaw), math.sin(yaw)

    def P(dx, dy, dz):
        return (c[0] + dx * ca + dz * sa, c[1] + dy, c[2] - dx * sa + dz * ca)
    lift = 0.018
    # 頁＝SK_School の和紙（albedo 0.8）：V2_Suzunaan（0.42）の紙は日向でも灰色に沈む（頂點色は 1.0 で頭打ち）
    pg = rsub(AT['paper'], 0.05, 0.05, 0.95, 0.95)
    for s in (-1, 1):
        a = P(0.0, 0.004, -d / 2)
        b = P(s * w / 2, lift, -d / 2)
        cc = P(s * w / 2, lift, d / 2)
        dd = P(0.0, 0.004, d / 2)
        if s < 0:
            m.rect_uv(a, b, cc, dd, SK, pg, 1.0)
        else:
            m.rect_uv(b, a, dd, cc, SK, pg, 1.0)
        if not lod:
            # 頁の束の厚み（外側の小口）
            o0 = P(s * w / 2, lift, -d / 2)
            o1 = P(s * w / 2, lift, d / 2)
            o2 = P(s * w / 2, -0.002, d / 2)
            o3 = P(s * w / 2, -0.002, -d / 2)
            if s > 0:
                m.quad(o3, o2, o1, o0, SZ, 1.0, uvs=[(sw('#B8AE96')[0], sw('#B8AE96')[1])] * 4)
            else:
                m.quad(o0, o1, o2, o3, SZ, 1.0, uvs=[(sw('#B8AE96')[0], sw('#B8AE96')[1])] * 4)
        # 表紙の縁（頁の下から少しはみ出す）
        e0 = P(s * (w / 2 + 0.006), lift - 0.006, -d / 2 - 0.004)
        e1 = P(s * (w / 2 + 0.006), lift - 0.006, d / 2 + 0.004)
        e2 = P(0.0, -0.002, d / 2 + 0.004)
        e3 = P(0.0, -0.002, -d / 2 - 0.004)
        if s < 0:
            m.quad(e3, e0, e1, e2, SZ, 1.0, uvs=[(sw('#5B4A36')[0], sw('#5B4A36')[1])] * 4)
        else:
            m.quad(e0, e3, e2, e1, SZ, 1.0, uvs=[(sw('#5B4A36')[0], sw('#5B4A36')[1])] * 4)


def dai(name, lod):
    m = new(name + ('_l1' if lod else ''), '縁台 1.40 × 0.60、座面 0.40＋茣蓙＋虫干しの和本（開いた本 3・積み 3・紙束＋文鎮石）')
    L, Dp, H = 1.40, 0.60, 0.40
    board(m, (-L / 2, H - 0.035, -Dp / 2), (L / 2, H, Dp / 2), WOODC)
    for x in (-L / 2 + 0.07, L / 2 - 0.07):
        for z in (-Dp / 2 + 0.06, Dp / 2 - 0.06):
            board(m, (x - 0.03, 0.0, z - 0.03), (x + 0.03, H - 0.035, z + 0.03), AGED)
    if not lod:
        for z in (-Dp / 2 + 0.06, Dp / 2 - 0.06):
            board(m, (-L / 2 + 0.07, 0.10, z - 0.015), (L / 2 - 0.07, 0.13, z + 0.015), AGED)
    # 茣蓙（稲藁 atlas、縁は少し垂らす）
    s = AT['straw']
    y = H + 0.004
    m.rect_uv((-0.62, y, 0.26), (0.62, y, 0.26), (0.62, y, -0.26), (-0.62, y, -0.26), SK, s, 0.95)
    m.rect_uv((-0.62, y - 0.035, 0.29), (0.62, y - 0.035, 0.29), (0.62, y, 0.26), (-0.62, y, 0.26), SK, s, 0.8)
    # 開いた本 3（頁を日に当てる）
    open_book(m, (-0.40, y + 0.002, 0.02), 0.08, 0.34, 0.24, lod)
    open_book(m, (0.02, y + 0.002, -0.05), -0.12, 0.34, 0.24, lod)
    open_book(m, (0.36, y + 0.002, 0.10), 0.20, 0.30, 0.22, lod)
    # 積んだ本 3＋紙束と文鎮石
    rng = random.Random(4614)
    yy = y
    for i, top in enumerate([sw('#B8AE96'), sw('#B8AE96'), cover(3)]):
        t = 0.022
        book(m, (0.47 + rng.uniform(-0.01, 0.01), yy, -0.14), 0.17, 0.25, t, rng.uniform(-0.08, 0.08), top, lod)
        yy += t
    m.abox((-0.12, y + 0.012, 0.17), (0.12, 0.012, 0.075), SK, {'+y': AT['paper'], '*': AT['paper']}, 1.0, skip=('-y',))
    m.cyl((-0.10, y + 0.024, 0.17), (-0.10, y + 0.06, 0.17), 0.04, 0.032, 6 if lod else 9, SZ, 1.0, uv_atlas=sw('#8A7F6A'))
    return m


def seoi(name, lod):
    m = new(name + ('_l1' if lod else ''), '貸本屋の背負い本箱：箱 3 段 0.50 × 0.32（計 0.85）＋風呂敷包み＋負い紐（−z の壁へ 9° 寄り掛かる）')
    lean = math.radians(9)
    cl, sl = math.cos(lean), math.sin(lean)

    def R(p):
        # x 軸回りに −z 側へ傾ける（底の前縁 z=+0.16 を支点）
        x, y, z = p
        z0 = z - 0.16
        return (x, y * cl + z0 * sl, 0.16 + z0 * cl - y * sl)
    hs = [0.30, 0.30, 0.25]
    y = 0.0
    for i, h in enumerate(hs):
        c = (0.0, y + h / 2, 0.0)
        hh = (0.25, h / 2 - 0.004, 0.16)
        ax = (1.0, 0.0, 0.0)
        ay = (0.0, cl, -sl)
        az = (0.0, sl, cl)
        cc = R(c)
        m.obox(cc, hh, WD, AGED if i % 2 else WOODC, ax=ax, ay=ay, az=az)
        if not lod:
            # 引き出しの前板＋札（和紙）
            fp = R((0.0, y + h / 2, 0.162))
            m.obox(fp, (0.22, h / 2 - 0.03, 0.004), WD, DARK, ax=ax, ay=ay, az=az)
            lp = R((0.0, y + h / 2 + 0.02, 0.168))
            m.abox(lp, (0.05, 0.035, 0.002), SZ, {'*': sw('#B8AE96')}, 1.0, ax=ax, ay=ay, az=az)
        y += h
    # 風呂敷包み（鈴奈庵の藍：noren_back）
    # 風呂敷包み（鈴奈庵の藍）：横に寝かせた丸い包み＋上の結び目
    nb = RG['noren_back']
    m.cyl(R((-0.24, y + 0.105, 0.0)), R((0.24, y + 0.105, 0.0)), 0.115, 0.115, 8 if lod else 12, SZ, 1.0, uv_atlas=nb)
    if not lod:
        for sx in (-1, 1):
            m.cyl(R((sx * 0.05, y + 0.20, 0.0)), R((sx * 0.11, y + 0.27, 0.03 * sx)), 0.028, 0.012, 6, SZ, 1.0, uv_atlas=nb)
    # 負い紐（濃い布帯、+z 正面の左右）
    st = sw('#3A2E22')
    for x in (-0.15, 0.15):
        a = R((x, 0.10, 0.168))
        b = R((x, 0.50, 0.205))
        cc = R((x, 0.84, 0.168))
        for p0, p1 in ((a, b), (b, cc)):
            dv = (p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2])
            L = math.sqrt(sum(t * t for t in dv))
            ay2 = (dv[0] / L, dv[1] / L, dv[2] / L)
            az2 = (0.0, -ay2[2], ay2[1])
            nz = math.sqrt(az2[1] ** 2 + az2[2] ** 2)
            az2 = (0.0, az2[1] / nz, az2[2] / nz)
            m.abox(((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2), (0.02, L / 2, 0.006), SZ, {'*': st}, 1.0,
                   ax=(1.0, 0.0, 0.0), ay=ay2, az=az2)
    return m


def hachi(name, lod):
    m = new(name + ('_l1' if lod else ''), '鉢植え：陶鉢 Ø0.30 × 0.24＋土＋葉カード 3（atlas foliage）')
    seg = 8 if lod else 12
    pot = sw('#8A7F6A')
    m.cyl((0, 0, 0), (0, 0.24, 0), 0.12, 0.15, seg, SZ, 1.0, caps=(True, False), uv_atlas=pot)
    m.cyl((0, 0.24, 0), (0, 0.25, 0), 0.15, 0.155, seg, SZ, 0.9, caps=(False, False), uv_atlas=pot)
    m.cyl((0, 0.22, 0), (0, 0.225, 0), 0.14, 0.14, seg, SZ, 1.0, caps=(False, True), uv_atlas=sw('#3A2E22'))
    fol = RG['foliage']
    for k in range(3):
        a = k * math.pi / 3 + 0.3
        dx, dz = math.cos(a) * 0.22, math.sin(a) * 0.22
        p0 = (-dx, 0.20, -dz)
        p1 = (dx, 0.20, dz)
        p2 = (dx * 1.15, 0.62, dz * 1.15)
        p3 = (-dx * 1.15, 0.62, -dz * 1.15)
        m.rect_uv(p0, p1, p2, p3, SZ, fol, 1.0)
        m.rect_uv(p1, p0, p3, p2, SZ, fol, 0.85)
    return m


def build_all():
    for lod in (0, 1):
        kanban('sz_kanban', lod)
        keiji('sz_keiji', lod)
        hako('sz_hako', lod)
        hako2('sz_hako2', lod)
        bundle('sz_bundle', lod)
        stool('sz_stool', lod)
        dai('sz_dai', lod)
        seoi('sz_seoi', lod)
        hachi('sz_hachi', lod)


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
    K.export_glb(bpy, OUT + '/src/suzu_kit.glb', objs)
    total = sum(v['tris'] for v in manifest.values())
    K.write_json(OUT + '/src/modules_blender.json', {
        '_note': 'build_suzu_kit.py 產生；Godot prefab（tools/village_v2_machiya_kit_prefab.gd -- --kit=suzu_kit）讀此表逐一轉成 mesh/<名>.res。',
        'materials': MATS, 'modules': manifest, 'total_tris': total})
    print('[SZKIT] %d 構件、合計 %d 三角面 → %s' % (len(manifest), total, OUT + '/src/suzu_kit.glb'))
    for n, v in manifest.items():
        if not n.endswith('_l1'):
            print('[SZKIT]   %-10s %5d 面  LOD1 %4d  dims %s  %s' % (n, v['tris'], manifest[n + '_l1']['tris'], v['dims'], v['mats']))


main()
