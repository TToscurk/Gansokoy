#!/usr/bin/env python3
"""人間之里 V2 P5 R5：山頂社殿 Hero atlas 產生器（火見櫓只用共享材質庫，不需 atlas）。

  python tools/build_village_v2_r5_atlas.py

沿用 tools/build_village_v2_r2_atlases.py（_write／_swatches／_emit_box）與 build_village_v2_textures.py
（取色、紙／布／木、.import、.tres 規約）；不重建共享材質庫與 R1–R4 atlas。
輸出：godot/assets/village_v2/hilltop_shrine/{hilltop_shrine_atlas.png, hilltop_shrine_emit.png, atlas.json,
V2_HilltopShrine.tres}。
參考：docs/reference/神社/拜殿.png（vision brief：素木風化褐柱〔非朱〕、深色方格子戶、上段米白灰泥帶＋紅色花紋、
粗稻草注連繩＋房 3＋紙垂 2、賽錢箱〔古金角金具＋巴紋〕、褪朱高欄＋暗銅擬寶珠、古金金具、無鈴、無額）。
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402
import build_village_v2_r2_atlases as A  # noqa: E402

SIZE = A.SIZE

REGIONS = {
    'door_center': (0, 0, 512, 512),          # 中央戶：深色方格子（下 22 % 小格子）
    'door_side': (512, 0, 1024, 512),         # 側戶：上 60 % 方格子、下 40 % 板
    'panel': (1024, 0, 2048, 256),            # 上段小壁：米白灰泥＋紅花紋（4:1）
    'tsuma': (1024, 256, 1280, 512),          # 入母屋妻面：灰泥＋木連格子
    'bracket': (1280, 256, 2048, 448),        # 組物帶：斗栱暗木塊、金色木口（4:1）
    'karahafu_board': (0, 512, 1024, 576),    # 唐破風板：暗褐、金色飾邊
    'carve': (0, 576, 512, 832),              # 虹梁上彫刻板：雲＋唐草
    'rope': (512, 576, 1024, 832),            # 注連繩（u 沿繩長、v 繞一圈）
    'shide': (1024, 512, 1280, 768),          # 紙垂
    'tassel': (1280, 512, 1536, 768),         # 房（稻草直紋）
    'saisen': (1536, 512, 2048, 768),         # 賽錢箱正面：頂部格柵＋木身＋古金角金具＋巴紋
    'interior': (0, 832, 512, 1344),          # 格子戶後：暗室＋遠處燭光
    'swatch': (1024, 1024, 1536, 1280),
}
SW = ['#AE8B48', '#5E5B40', '#C6A56B', '#F1F0EB', '#30251F', '#45494A', '#687052', '#994A3D']
SW_NOTE = ['古金（金具、垂木木口、飾金具）', '暗銅（擬寶珠）', '稻草', '紙垂白', '深褐（暗部）', '瓦邊暗灰',
           '苔綠', '褪朱（高欄）']


def build():
    atlas = Image.new('RGB', (SIZE, SIZE), (36, 30, 26))
    emit = Image.new('RGB', (SIZE // 4, SIZE // 4), (0, 0, 0))
    R = REGIONS
    dark = A._hex255('#241A14')

    def sz(k):
        x0, y0, x1, y1 = R[k]
        return x1 - x0, y1 - y0

    def lattice(img, box, pitch, bar, backing):
        d = ImageDraw.Draw(img)
        x0, y0, x1, y1 = box
        d.rectangle(box, fill=A._hex255(backing))
        for x in range(x0, x1 + 1, pitch):
            d.rectangle((x - bar // 2, y0, x + bar // 2, y1), fill=A._hex255('#6A4C36'))
        for y in range(y0, y1 + 1, pitch):
            d.rectangle((x0, y - bar // 2, x1, y + bar // 2), fill=A._hex255('#6A4C36'))

    # 格子戶（中央）：外框木、深色方格子；下 22 % 小格子＋腰板
    w, h = sz('door_center')
    dc = T._wood_patch(w, h, '#5E4432', 501)
    d = ImageDraw.Draw(dc)
    lattice(dc, (18, 18, w - 19, int(h * 0.74)), 30, 7, '#1A1411')
    d.rectangle((0, int(h * 0.74), w, int(h * 0.78)), fill=A._hex255('#4A3526'))
    lattice(dc, (18, int(h * 0.78), w - 19, h - 19), 18, 5, '#221A15')
    d.rectangle((0, 0, w - 1, h - 1), outline=A._hex255('#3A2A1E'), width=18)
    d.line((w // 2, 0, w // 2, h), fill=A._hex255('#3A2A1E'), width=10)
    atlas.paste(dc, R['door_center'][:2])
    # 側戶：上格子、下板
    w, h = sz('door_side')
    ds = T._wood_patch(w, h, '#6A4E3A', 502)
    lattice(ds, (18, 18, w - 19, int(h * 0.58)), 30, 7, '#1A1411')
    d = ImageDraw.Draw(ds)
    d.rectangle((0, int(h * 0.58), w, int(h * 0.62)), fill=A._hex255('#3A2A1E'))
    for x in range(0, w, 64):
        d.line((x, int(h * 0.62), x, h), fill=A._hex255('#4A3526'), width=3)
    d.rectangle((0, 0, w - 1, h - 1), outline=A._hex255('#3A2A1E'), width=18)
    atlas.paste(ds, R['door_side'][:2])
    # 小壁：米白灰泥＋紅花紋（每 1/4 一朵：八瓣＋中心），邊緣髒污
    w, h = sz('panel')
    pn = T._paper(w, h, 503, tone='#B6A593')
    d = ImageDraw.Draw(pn)
    red, red2 = A._hex255('#8E3B2C'), A._hex255('#B45A40')
    for k in range(4):
        cx, cy, r = w * (k + 0.5) / 4, h * 0.5, h * 0.30
        for i in range(8):
            a = i * math.pi / 4
            px, py = cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.55
            d.ellipse((px - r * 0.36, py - r * 0.36, px + r * 0.36, py + r * 0.36), fill=red2)
        d.ellipse((cx - r * 0.42, cy - r * 0.42, cx + r * 0.42, cy + r * 0.42), fill=red)
        d.ellipse((cx - r * 0.16, cy - r * 0.16, cx + r * 0.16, cy + r * 0.16), fill=A._hex255('#AE8B48'))
        for s in (-1, 1):   # 唐草
            d.arc((cx + s * r * 1.1 - r * 0.6, cy - r * 0.5, cx + s * r * 1.1 + r * 0.6, cy + r * 0.5), 200, 340,
                  fill=red, width=6)
    a = np.asarray(pn, dtype=np.float32)
    a[:int(h * 0.12)] *= 0.82
    a[int(h * 0.88):] *= 0.78
    atlas.paste(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), R['panel'][:2])
    # 妻面：灰泥＋木連格子（上 70 %）
    w, h = sz('tsuma')
    ts = T._paper(w, h, 504, tone='#C9BFAE')
    d = ImageDraw.Draw(ts)
    for k in range(0, w, 18):
        d.rectangle((k, 0, k + 5, int(h * 0.7)), fill=A._hex255('#3A2A1E'))
    for k in range(0, int(h * 0.7), 18):
        d.rectangle((0, k, w, k + 5), fill=A._hex255('#3A2A1E'))
    d.rectangle((0, int(h * 0.7), w, int(h * 0.7) + 10), fill=A._hex255('#2A1E16'))
    atlas.paste(ts, R['tsuma'][:2])
    # 組物帶：暗底、斗（方塊）＋肘木（橫條），木口古金點；每 1/4 一組
    w, h = sz('bracket')
    br = Image.new('RGB', (w, h), dark)
    d = ImageDraw.Draw(br)
    wood = T._wood_patch(w, h, '#6A4E3A', 505)
    for k in range(8):
        cx = w * (k + 0.5) / 8
        box = (int(cx - w * 0.028), int(h * 0.58), int(cx + w * 0.028), h - 6)
        br.paste(wood.crop(box), box[:2])                          # 斗
        box = (int(cx - w * 0.055), int(h * 0.36), int(cx + w * 0.055), int(h * 0.58))
        br.paste(wood.crop(box), box[:2])                          # 肘木
        box = (int(cx - w * 0.020), int(h * 0.08), int(cx + w * 0.020), int(h * 0.36))
        br.paste(wood.crop(box), box[:2])                          # 上斗
        for s in (-1, 1):
            x = cx + s * w * 0.045
            d.ellipse((x - 7, h * 0.47 - 7, x + 7, h * 0.47 + 7), fill=A._hex255('#AE8B48'))
    d.rectangle((0, 0, w, 6), fill=A._hex255('#3A2A1E'))
    atlas.paste(br, R['bracket'][:2])
    # 唐破風板：暗褐、上下古金細邊＋金具點
    w, h = sz('karahafu_board')
    kb = T._wood_patch(w, h, '#3A2A1E', 506)
    d = ImageDraw.Draw(kb)
    d.rectangle((0, 0, w, 7), fill=A._hex255('#AE8B48'))
    d.rectangle((0, h - 8, w, h), fill=A._hex255('#8A6A2A'))
    for k in range(8, w, 128):
        d.ellipse((k + 54, h // 2 - 10, k + 74, h // 2 + 10), fill=A._hex255('#AE8B48'))
    atlas.paste(kb, R['karahafu_board'][:2])
    # 彫刻板：雲＋唐草（亮暗兩層）、中央古金圓
    w, h = sz('carve')
    cv = T._wood_patch(w, h, '#6A4E36', 507)
    d = ImageDraw.Draw(cv)
    hi_c, lo_c = A._hex255('#9A7650'), A._hex255('#34261A')
    for k in range(7):
        cx = w * (k + 0.5) / 7
        cy = h * (0.62 + 0.12 * math.sin(k * 1.3))
        for rr, col in ((46, lo_c), (40, hi_c), (22, lo_c), (16, hi_c)):
            d.ellipse((cx - rr, cy - rr * 0.7, cx + rr, cy + rr * 0.7), fill=col)
    for s in (-1, 1):
        for k in range(4):
            x = w / 2 + s * (60 + k * 50)
            d.arc((x - 30, h * 0.20, x + 30, h * 0.20 + 60), 180 if s < 0 else 0, 360 if s < 0 else 180,
                  fill=hi_c, width=8)
    d.ellipse((w / 2 - 34, h * 0.14, w / 2 + 34, h * 0.14 + 68), fill=A._hex255('#AE8B48'))
    atlas.paste(cv.filter(ImageFilter.GaussianBlur(0.8)), R['carve'][:2])
    # 注連繩：稻草＋螺旋撚紋（u 沿繩長 12 撚、v 繞一圈 3 股）
    w, h = sz('rope')
    base = T.hexrgb('#C6A56B')
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    stripe = 0.5 + 0.5 * np.sin((xx / w * 12.0 + yy / h * 3.0) * 2 * np.pi)
    rng = np.random.default_rng(508)
    fib = rng.normal(0, 0.05, (h, w)).astype(np.float32)
    rp = np.clip(base[None, None, :] * (0.70 + 0.32 * stripe + fib)[..., None], 0, 1)
    atlas.paste(Image.fromarray((rp * 255).astype(np.uint8)), R['rope'][:2])
    atlas.paste(T._paper(*sz('shide'), 509, tone='#F1F0EB'), R['shide'][:2])
    w, h = sz('tassel')
    fb = rng.normal(0, 1, (1, w)).astype(np.float32)
    tv = np.clip(T.hexrgb('#C4A468')[None, None, :] * (0.86 + 0.10 * fb[..., None]) *
                 np.linspace(1.0, 0.82, h, dtype=np.float32)[:, None, None], 0, 1)
    atlas.paste(Image.fromarray((np.broadcast_to(tv, (h, w, 3)) * 255).astype(np.uint8)), R['tassel'][:2])
    # 賽錢箱正面（0.9 × 0.55 m → 2:1 → 上 30 % 格柵）：木身、古金角金具、中央巴紋
    w, h = sz('saisen')
    sb = T._wood_patch(w, h, '#6A4A34', 510)
    d = ImageDraw.Draw(sb)
    d.rectangle((0, 0, w, int(h * 0.28)), fill=dark)
    for x in range(10, w, 36):
        d.rectangle((x, 4, x + 16, int(h * 0.28) - 4), fill=A._hex255('#7A5A40'))
    gold = A._hex255('#AE8B48')
    for (x, y) in ((0, int(h * 0.28)), (w - 60, int(h * 0.28)), (0, h - 60), (w - 60, h - 60)):
        d.rectangle((x, y, x + 60, y + 60), fill=gold)
        d.ellipse((x + 22, y + 22, x + 38, y + 38), fill=A._hex255('#5E5B40'))
    cx, cy, r = w // 2, int(h * 0.64), int(h * 0.26)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=gold)
    for i in range(3):   # 三つ巴
        a0 = i * 2 * math.pi / 3
        px, py = cx + math.cos(a0) * r * 0.38, cy + math.sin(a0) * r * 0.38
        d.ellipse((px - r * 0.34, py - r * 0.34, px + r * 0.34, py + r * 0.34), fill=A._hex255('#3A2A1E'))
        d.pieslice((px - r * 0.62, py - r * 0.62, px + r * 0.62, py + r * 0.62), math.degrees(a0) + 60,
                   math.degrees(a0) + 150, fill=A._hex255('#3A2A1E'))
    T._text(sb, (cx, int(h * 0.14)), '奉納', int(h * 0.16), A._hex255('#D9C08A'), stroke=1)
    atlas.paste(sb, R['saisen'][:2])
    # 格子後：暗室、深處燭光（微發光）
    w, h = sz('interior')
    it = Image.new('RGB', (w, h), (22, 17, 13))
    glow = Image.new('L', (w, h), 0)
    ImageDraw.Draw(glow).ellipse((w * 0.30, h * 0.30, w * 0.70, h * 0.70), fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(60))
    it = Image.composite(Image.new('RGB', (w, h), (140, 96, 50)), it, glow)
    atlas.paste(it, R['interior'][:2])
    A._emit_box(emit, R['interior'], (40, 26, 12))
    sws = A._swatches(atlas, R['swatch'], SW, SW_NOTE)
    A._write('hilltop_shrine', 'V2_HilltopShrine', atlas, emit, R, sws,
             ' R5 山頂社殿（tools/build_village_v2_r5_atlas.py）：格子戶、小壁花紋、組物帶、唐破風板、彫刻、注連繩、'
             '紙垂、房、賽錢箱（「奉納」）。')


if __name__ == '__main__':
    build()
