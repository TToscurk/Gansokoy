#!/usr/bin/env python3
"""人間之里 V2 P5 R3：寺子屋 Hero atlas 產生器。

  python tools/build_village_v2_r3_atlas.py

沿用 tools/build_village_v2_r2_atlases.py 的工具（提燈式字面縮放、_write／_swatches／_emit_box），
再往上是 build_village_v2_textures.py（取色、紙／布／木、.import、.tres 規約）。不重建共享材質庫與 R1／R2 atlas。
輸出：godot/assets/village_v2/terakoya/{terakoya_atlas.png, terakoya_emit.png, atlas.json, V2_Terakoya.tres}。
參考：docs/reference/重點地標/{寺子屋2,寺子屋告示牌,上白澤旗桿}.PNG。
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402
import build_village_v2_r2_atlases as A  # noqa: E402

SIZE = A.SIZE

REGIONS = {
    'noren': (0, 0, 768, 256),              # 藍暖簾 3 片（白色圓紋）
    'noren_back': (768, 0, 1024, 64),
    'plaque': (1024, 0, 1536, 192),         # 玄關額「寺子屋」（黑漆木額、金框、白字）
    'banner': (1536, 0, 1792, 1024),        # 幟：藍底白字「上白沢寺子屋」＋圓形花紋（0.55 × 2.10 m）
    'board_keine': (1792, 0, 2048, 768),    # 立看板「上白沢慧音」（0.40 × 1.20 m）
    'board_recruit': (0, 256, 768, 768),    # 告示板「生徒募集」（1.50 × 1.00 m）
    'board_today': (768, 256, 1536, 768),   # 瓦屋根告示板：4 張紙（今日の学問 身を助くる／時間割／お知らせ）
    'lattice_paper': (0, 768, 256, 1024),   # 一樓格子後暖紙（微發光）
    'window_2f': (256, 768, 768, 1024),     # 二樓連子窗（2 格一組：暗格子＋紙）
    'interior': (768, 768, 1280, 1152),     # 玄關內：式台、下駄箱、衝立、奧的障子
    'tsuma': (1280, 768, 1536, 1024),       # 入母屋妻面：白漆喰＋木連格子（上半）
    'karahafu_board': (0, 1024, 1024, 1088),  # 唐破風板：黑褐漆、金色飾邊
    'carve': (0, 1088, 512, 1344),          # 虹梁上的彫刻板（兎の毛通し區）：雲＋若葉浮雕
    'koshi': (512, 1088, 768, 1344),        # 腰板（縦羽目、下緣風化）
    'flowers': (768, 1152, 1280, 1408),     # 盆栽／花壇：綠葉＋黃花
    'toro_window': (1280, 1024, 1408, 1152),  # 石燈籠火袋
    'swatch': (1536, 1024, 2048, 1280),
}
SW = ['#D9A441', '#1E1B18', '#2F3F66', '#E8E2D2', '#6B4A2E', '#8C8C86', '#3E5A34', '#A9774A', '#C9B79A', '#4A2E1E',
      '#8E3B2C', '#2A2622']
SW_NOTE = ['古金（金具、額框、鬼瓦飾）', '近黑（鐵件）', '藍（暖簾邊、幟布）', '胡粉白', '褐木（竹竿節）', '石灰',
           '深綠（盆栽葉）', '竹竿', '素木（看板柱）', '深褐（室內）', '赤陶（花盆）', '黑瓦邊']


def build():
    atlas = Image.new('RGB', (SIZE, SIZE), (36, 30, 26))
    emit = Image.new('RGB', (SIZE // 4, SIZE // 4), (0, 0, 0))
    R = REGIONS
    rnd = random.Random(20260925)

    def sz(k):
        x0, y0, x1, y1 = R[k]
        return x1 - x0, y1 - y0

    # 暖簾：深藍 3 片，中片「寺子屋」白字、兩側白色圓紋
    w, h = sz('noren')
    nr = T._cloth(w, h, '#26375C', 71)
    d = ImageDraw.Draw(nr)
    d.rectangle((0, 0, w, int(h * 0.10)), fill=A._hex255('#1B2744'))
    white = (232, 228, 214)
    for i in range(3):
        cx, cy, r = w * (i + 0.5) / 3, h * 0.58, h * 0.24
        if i == 1:
            T._text(nr, (int(cx), int(h * 0.56)), '寺', int(h * 0.50), white, stroke=2)
        else:
            d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=white, width=9)
            for k in range(6):
                a = k * math.pi / 3
                px, py = cx + math.cos(a) * r * 0.48, cy + math.sin(a) * r * 0.48
                d.ellipse((px - r * 0.22, py - r * 0.22, px + r * 0.22, py + r * 0.22), fill=white)
    for i in range(1, 3):
        d.line((w * i // 3, 0, w * i // 3, h), fill=A._hex255('#141D33'), width=4)
    atlas.paste(nr, R['noren'][:2])
    atlas.paste(T._cloth(*sz('noren_back'), '#1F2E4E', 72), R['noren_back'][:2])
    # 額「寺子屋」：黑漆底、金框、胡粉白字（×albedo_k 後仍要讀得出來 → 白字不用灰）
    w, h = sz('plaque')
    pq = T._wood_patch(w, h, '#2A1E16', 73)
    d = ImageDraw.Draw(pq)
    d.rectangle((0, 0, w - 1, h - 1), outline=A._hex255('#D9A441'), width=14)
    d.rectangle((20, 20, w - 21, h - 21), outline=A._hex255('#8A6A2A'), width=4)
    T._text(pq, (w // 2, h // 2 + 4), '寺子屋', int(h * 0.62), (244, 238, 222), stroke=2)
    atlas.paste(pq, R['plaque'][:2])
    # 幟：藍底、上方白色圓花紋、白字直書「上白沢寺子屋」（0.55 × 2.10 m：字 0.26 m 見方）
    w, h = sz('banner')
    bn = T._cloth(w, h, '#2B4C9A', 74)
    d = ImageDraw.Draw(bn)
    d.rectangle((0, 0, w - 1, h - 1), outline=(236, 236, 230), width=6)
    cx, cy, r = w // 2, int(h * 0.09), int(w * 0.30)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=white, width=8)
    for k in range(5):
        a = -math.pi / 2 + k * 2 * math.pi / 5
        px, py = cx + math.cos(a) * r * 0.5, cy + math.sin(a) * r * 0.5
        d.ellipse((px - r * 0.26, py - r * 0.26, px + r * 0.26, py + r * 0.26), fill=white)
    txt = '上白沢寺子屋'
    ch = int(h * 0.80 / len(txt))
    for i, c in enumerate(txt):
        gl = Image.new('L', (256, 256), 0)
        T._text(gl, (128, 134), c, 220, 255, stroke=3)
        gl = gl.resize((int(w * 0.78), ch), Image.LANCZOS)
        bn.paste(Image.new('RGB', gl.size, white), (int(w * 0.11), int(h * 0.19) + i * ch), gl)
    atlas.paste(bn, R['banner'][:2])
    # 立看板「上白沢慧音」：素木、墨字直書（0.40 × 1.20 m）
    w, h = sz('board_keine')
    bk = T._wood_patch(w, h, '#C8A878', 75).rotate(90, expand=True).resize((w, h))
    d = ImageDraw.Draw(bk)
    d.rectangle((0, 0, w - 1, h - 1), outline=A._hex255('#5A3F22'), width=10)
    txt = '上白沢慧音'
    ch = int(h * 0.84 / len(txt))
    for i, c in enumerate(txt):
        gl = Image.new('L', (256, 256), 0)
        T._text(gl, (128, 134), c, 220, 255, stroke=3)
        gl = gl.resize((int(w * 0.80), ch), Image.LANCZOS)
        bk.paste(Image.new('RGB', gl.size, (20, 15, 10)), (int(w * 0.10), int(h * 0.08) + i * ch), gl)
    atlas.paste(bk, R['board_keine'][:2])
    # 告示板「生徒募集」：舊紙、墨字大書＋右側四科
    w, h = sz('board_recruit')
    br = T._paper(w, h, 76, tone='#E4D8BC')
    d = ImageDraw.Draw(br)
    d.rectangle((0, 0, w - 1, h - 1), outline=A._hex255('#4A3524'), width=18)
    ink = (22, 17, 12)
    for i, c in enumerate('生徒募集'):
        T._text(br, (int(w * 0.30), int(h * 0.16) + i * int(h * 0.20)), c, int(h * 0.19), ink, stroke=2)
    for j, s in enumerate(['読み書き', '算術', '歴史', '書道']):
        T._text(br, (int(w * 0.62) + j * 0, int(h * 0.20) + j * int(h * 0.19)), s, int(h * 0.11), ink, stroke=1)
    T._text(br, (int(w * 0.62), int(h * 0.90)), '寺子屋', int(h * 0.07), (150, 40, 30), stroke=1)
    atlas.paste(br, R['board_recruit'][:2])
    # 告示板（瓦屋根）：板壁上 4 張紙
    w, h = sz('board_today')
    bt = T._wood_patch(w, h, '#5E4430', 77)
    d = ImageDraw.Draw(bt)
    sheets = [((30, 30, 330, 480), ['今日の学問', '身を助くる'], 54),
              ((360, 30, 740, 250), ['時間割', '一 読み書き  二 算術'], 40),
              ((360, 270, 740, 480), ['お知らせ', '明日は歴史'], 40)]
    for (x0, y0, x1, y1), lines, fs in sheets:
        pap = T._paper(x1 - x0, y1 - y0, rnd.randint(0, 999), tone='#E8DEC6')
        bt.paste(pap, (x0, y0))
        d.rectangle((x0, y0, x1, y1), outline=(90, 70, 50), width=3)
        for k, s in enumerate(lines):
            T._text(bt, ((x0 + x1) // 2, y0 + 60 + k * int(fs * 1.7)), s, fs if k == 0 else int(fs * 0.72), ink,
                    stroke=1 if k == 0 else 0)
    atlas.paste(bt, R['board_today'][:2])
    # 一樓格子後暖紙、二樓連子窗
    atlas.paste(T._paper(*sz('lattice_paper'), 78, tone='#E6CFA2'), R['lattice_paper'][:2])
    A._emit_box(emit, R['lattice_paper'], (110, 84, 52))
    w, h = sz('window_2f')
    wn = T._paper(w, h, 79, tone='#D9C9A6')
    d = ImageDraw.Draw(wn)
    dark = A._hex255('#2A1E16')
    for k in range(0, w, 22):
        d.rectangle((k, 0, k + 7, h), fill=dark)
    d.rectangle((0, 0, w, 14), fill=dark)
    d.rectangle((0, h - 14, w, h), fill=dark)
    d.rectangle((w // 2 - 7, 0, w // 2 + 7, h), fill=dark)
    atlas.paste(wn, R['window_2f'][:2])
    # 玄關內：式台（木）、左右下駄箱、衝立、奧障子暖光
    w, h = sz('interior')
    it = T._wood_patch(w, h, '#4A3322', 80)
    d = ImageDraw.Draw(it)
    d.rectangle((int(w * 0.18), int(h * 0.12), int(w * 0.82), int(h * 0.62)), fill=A._hex255('#D9C39A'))
    for k in range(1, 6):
        x = int(w * 0.18 + (w * 0.64) * k / 6)
        d.line((x, int(h * 0.12), x, int(h * 0.62)), fill=A._hex255('#5A4028'), width=5)
    d.line((int(w * 0.18), int(h * 0.37), int(w * 0.82), int(h * 0.37)), fill=A._hex255('#5A4028'), width=4)
    d.rectangle((int(w * 0.36), int(h * 0.30), int(w * 0.64), int(h * 0.74)), fill=A._hex255('#3A2A1C'))   # 衝立
    T._text(it, (w // 2, int(h * 0.50)), '学', int(h * 0.20), (220, 210, 186), stroke=1)
    for x0 in (0, int(w * 0.86)):
        d.rectangle((x0, int(h * 0.10), x0 + int(w * 0.14), int(h * 0.80)), fill=A._hex255('#5A3C24'))
        for r in range(5):
            y = int(h * 0.14 + r * h * 0.13)
            d.rectangle((x0 + 6, y, x0 + int(w * 0.14) - 6, y + int(h * 0.09)), fill=A._hex255('#3A2618'))
    d.rectangle((0, int(h * 0.80), w, h), fill=A._hex255('#6E5236'))        # 式台
    d.rectangle((0, int(h * 0.80), w, int(h * 0.83)), fill=A._hex255('#8A6A48'))
    glow = Image.new('L', (w, h), 0)
    ImageDraw.Draw(glow).ellipse((w * 0.15, h * 0.0, w * 0.85, h * 0.7), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(50))
    it = Image.composite(Image.new('RGB', (w, h), (255, 205, 140)), it, glow)
    atlas.paste(it, R['interior'][:2])
    # 妻面：白漆喰底＋木連格子（上 70 %）
    w, h = sz('tsuma')
    ts = T._paper(w, h, 81, tone='#E4DDCC')
    d = ImageDraw.Draw(ts)
    for k in range(0, w, 18):
        d.rectangle((k, 0, k + 5, int(h * 0.7)), fill=A._hex255('#3A2A1E'))
    for k in range(0, int(h * 0.7), 18):
        d.rectangle((0, k, w, k + 5), fill=A._hex255('#3A2A1E'))
    d.rectangle((0, int(h * 0.7), w, int(h * 0.7) + 10), fill=A._hex255('#2A1E16'))
    atlas.paste(ts, R['tsuma'][:2])
    # 唐破風板：黑褐漆、上下金色細邊
    w, h = sz('karahafu_board')
    kb = T._wood_patch(w, h, '#2E221A', 82)
    d = ImageDraw.Draw(kb)
    d.rectangle((0, 0, w, 7), fill=A._hex255('#D9A441'))
    d.rectangle((0, h - 8, w, h), fill=A._hex255('#B08432'))
    for k in range(8, w, 128):
        d.ellipse((k + 54, h // 2 - 10, k + 74, h // 2 + 10), fill=A._hex255('#D9A441'))
    atlas.paste(kb, R['karahafu_board'][:2])
    # 彫刻板：雲＋若葉浮雕（亮暗兩層）
    w, h = sz('carve')
    cv = T._wood_patch(w, h, '#6E4E32', 83)
    d = ImageDraw.Draw(cv)
    hi_c, lo_c = A._hex255('#9A7248'), A._hex255('#3A2818')
    for k in range(7):
        cx = w * (k + 0.5) / 7
        cy = h * (0.62 + 0.12 * math.sin(k * 1.3))
        for rr, col in ((46, lo_c), (40, hi_c), (22, lo_c), (16, hi_c)):
            d.ellipse((cx - rr, cy - rr * 0.7, cx + rr, cy + rr * 0.7), fill=col)
    for k in range(9):
        a = -math.pi / 2 + (k - 4) * 0.32
        px, py = w / 2 + math.cos(a) * h * 0.45, h * 0.95 + math.sin(a) * h * 0.72
        d.ellipse((px - 20, py - 34, px + 20, py + 34), fill=A._hex255('#4E6B3A'))
    d.ellipse((w / 2 - 34, h * 0.18, w / 2 + 34, h * 0.18 + 68), fill=A._hex255('#D9A441'))
    atlas.paste(cv.filter(ImageFilter.GaussianBlur(0.8)), R['carve'][:2])
    # 腰板：縦羽目、下緣風化
    w, h = sz('koshi')
    ko = T._wood_patch(w, h, '#6A4E36', 84).rotate(90, expand=True).resize((w, h))
    d = ImageDraw.Draw(ko)
    for k in range(0, w, 32):
        d.line((k, 0, k, h), fill=A._hex255('#3A2A1E'), width=3)
    a = np.asarray(ko, dtype=np.float32)
    a[int(h * 0.8):] *= np.linspace(1.0, 0.72, h - int(h * 0.8))[:, None, None]
    atlas.paste(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), R['koshi'][:2])
    # 花壇
    w, h = sz('flowers')
    fo = Image.new('RGB', (w, h), (46, 64, 36))
    d = ImageDraw.Draw(fo)
    for _ in range(900):
        x, y = rnd.randint(0, w), rnd.randint(0, h)
        c = tuple(int(v) for v in T.hexrgb('#4E7A34') * 255 * rnd.uniform(0.6, 1.3))
        d.ellipse((x - 8, y - 3, x + 8, y + 3), fill=c)
    for _ in range(180):
        x, y = rnd.randint(0, w), rnd.randint(0, h)
        d.ellipse((x - 5, y - 5, x + 5, y + 5), fill=A._hex255(rnd.choice(['#E8C84A', '#F2EEE0', '#E8B83A'])))
    atlas.paste(fo, R['flowers'][:2])
    atlas.paste(T._paper(*sz('toro_window'), 85, tone='#F0D8A0'), R['toro_window'][:2])
    A._emit_box(emit, R['toro_window'], (255, 200, 120))
    sws = A._swatches(atlas, R['swatch'], SW, SW_NOTE)
    A._write('terakoya', 'V2_Terakoya', atlas, emit, R, sws, ' 文字：額「寺子屋」、幟「上白沢寺子屋」、立看板「上白沢慧音」、'
             '告示「生徒募集／読み書き・算術・歴史・書道」「今日の学問 身を助くる」。')


if __name__ == '__main__':
    build()
