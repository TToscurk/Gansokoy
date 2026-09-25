#!/usr/bin/env python3
"""人間之里 V2 P5 R6：稗田邸 本屋 Hero atlas 產生器（大宅門只用共享材質庫，不需 atlas）。

  python tools/build_village_v2_r6_atlas.py

沿用 tools/build_village_v2_r5_atlas.py 的結構與 build_village_v2_r2_atlases.py（_write／_swatches／_emit_box）、
build_village_v2_textures.py（取色、紙／木、.import、.tres 規約）；不重建共享材質庫與 R1–R5 atlas。
輸出：godot/assets/village_v2/hieda_house/{hieda_house_atlas.png, hieda_house_emit.png, atlas.json, V2_HiedaHouse.tres}。
參考：docs/reference/重點地標/裨田邸正面.PNG、裨田後.PNG（vision brief：風化深褐木構、米白灰泥、密排木格子〔淺色紙背〕、
二樓木格子窗、妻面露木構架＋灰泥、灰瓦；無招牌、無可讀文字、不做紅色）。
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402
import build_village_v2_r2_atlases as A  # noqa: E402

SIZE = A.SIZE

REGIONS = {
    'koshi': (0, 0, 512, 512),              # 一樓正面：密排千本格子（淺紙背、下 18 % 腰板）
    'window_2f': (512, 0, 1024, 512),       # 二樓：木格子窗（外框、淺色紙、方格）
    'shoji': (1024, 0, 1536, 512),          # 側／背：障子（紙＋細格）
    'door': (1536, 0, 2048, 512),           # 玄關：雙扉格子戶（上格子、下板）
    'tsuma': (0, 512, 512, 768),            # 妻面：灰泥＋露明木構（束、貫）
    'amado': (512, 512, 1024, 768),         # 雨戶（縱板＋橫桟，背面、側面用）
    'interior': (1024, 512, 1536, 1024),    # 玄關內：暗土間＋遠處行燈
    'swatch': (1536, 512, 2048, 768),
}
SW = ['#2E2119', '#4A3526', '#E8E0CF', '#6B6F70', '#8C7A5A', '#3B3F40']
SW_NOTE = ['深褐（木構暗部）', '褐（格子）', '米白（灰泥）', '瓦邊灰', '古銅（金具）', '暗灰（瓦影）']


def build():
    atlas = Image.new('RGB', (SIZE, SIZE), (36, 30, 26))
    emit = Image.new('RGB', (SIZE // 4, SIZE // 4), (0, 0, 0))
    R = REGIONS
    frame, bar = A._hex255('#2E2119'), A._hex255('#4A3526')

    def sz(k):
        x0, y0, x1, y1 = R[k]
        return x1 - x0, y1 - y0

    # 千本格子：縱格子密排（淺紙背），下 18 % 腰板
    w, h = sz('koshi')
    kc = T._paper(w, h, 601, tone='#CFC4AE')
    d = ImageDraw.Draw(kc)
    for x in range(6, w, 22):
        d.rectangle((x, 0, x + 11, int(h * 0.82)), fill=bar)
    for y in (int(h * 0.30), int(h * 0.58)):
        d.rectangle((0, y, w, y + 8), fill=frame)
    kb = T._wood_patch(w, h - int(h * 0.82), '#4E3A2A', 602)
    kc.paste(kb, (0, int(h * 0.82)))
    d.rectangle((0, int(h * 0.82) - 8, w, int(h * 0.82)), fill=frame)
    d.rectangle((0, 0, w - 1, h - 1), outline=frame, width=14)
    atlas.paste(kc, R['koshi'][:2])
    # 二樓格子窗：外框＋方格（紙背微暖）
    w, h = sz('window_2f')
    wn = T._paper(w, h, 603, tone='#D9CFB8')
    d = ImageDraw.Draw(wn)
    for x in range(0, w, 42):
        d.rectangle((x, 0, x + 9, h), fill=bar)
    for y in range(0, h, 42):
        d.rectangle((0, y, w, y + 9), fill=bar)
    d.rectangle((0, 0, w - 1, h - 1), outline=frame, width=22)
    d.line((w // 2, 0, w // 2, h), fill=frame, width=12)
    atlas.paste(wn, R['window_2f'][:2])
    # 障子：白紙＋細格
    w, h = sz('shoji')
    sj = T._paper(w, h, 604, tone='#E3DCCB')
    d = ImageDraw.Draw(sj)
    for x in range(0, w, 64):
        d.rectangle((x, 0, x + 5, h), fill=A._hex255('#5A4432'))
    for y in range(0, h, 96):
        d.rectangle((0, y, w, y + 5), fill=A._hex255('#5A4432'))
    d.rectangle((0, int(h * 0.80), w, h), fill=A._hex255('#5A4432'))
    d.rectangle((0, 0, w - 1, h - 1), outline=frame, width=16)
    atlas.paste(sj, R['shoji'][:2])
    # 玄關雙扉：上 62 % 格子（暗紙背）、下板
    w, h = sz('door')
    dr = T._wood_patch(w, h, '#4E3A2A', 605)
    d = ImageDraw.Draw(dr)
    d.rectangle((20, 20, w - 21, int(h * 0.62)), fill=A._hex255('#9C927E'))
    for x in range(20, w - 20, 26):
        d.rectangle((x, 20, x + 9, int(h * 0.62)), fill=bar)
    for y in range(20, int(h * 0.62), 52):
        d.rectangle((20, y, w - 21, y + 7), fill=bar)
    d.rectangle((0, int(h * 0.62), w, int(h * 0.66)), fill=frame)
    for x in range(0, w, 64):
        d.line((x, int(h * 0.66), x, h), fill=A._hex255('#3A2A1E'), width=3)
    d.rectangle((0, 0, w - 1, h - 1), outline=frame, width=20)
    d.line((w // 2, 0, w // 2, h), fill=frame, width=14)
    atlas.paste(dr, R['door'][:2])
    # 妻面：灰泥＋露明木構（中央束、兩道貫、斜向屋面下緣留給幾何）
    w, h = sz('tsuma')
    ts = T._paper(w, h, 606, tone='#DDD4C1')
    d = ImageDraw.Draw(ts)
    for x in (w // 2 - 10, w // 4 - 8, 3 * w // 4 - 8):
        d.rectangle((x, 0, x + 18, h), fill=frame)
    for y in (int(h * 0.38), int(h * 0.74)):
        d.rectangle((0, y, w, y + 16), fill=frame)
    d.rectangle((0, h - 14, w, h), fill=frame)
    a = np.asarray(ts, dtype=np.float32)
    a[:int(h * 0.15)] *= 0.86
    atlas.paste(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), R['tsuma'][:2])
    # 雨戶：縱板＋三道橫桟
    w, h = sz('amado')
    am = T._wood_patch(w, h, '#5A4432', 607)
    d = ImageDraw.Draw(am)
    for x in range(0, w, 48):
        d.line((x, 0, x, h), fill=A._hex255('#3A2A1E'), width=3)
    for y in (int(h * 0.12), int(h * 0.5), int(h * 0.88)):
        d.rectangle((0, y - 6, w, y + 6), fill=frame)
    atlas.paste(am, R['amado'][:2])
    # 玄關內：暗土間、遠處行燈微光
    w, h = sz('interior')
    it = Image.new('RGB', (w, h), (24, 19, 15))
    glow = Image.new('L', (w, h), 0)
    ImageDraw.Draw(glow).ellipse((w * 0.36, h * 0.40, w * 0.64, h * 0.66), fill=80)
    glow = glow.filter(ImageFilter.GaussianBlur(50))
    it = Image.composite(Image.new('RGB', (w, h), (150, 104, 56)), it, glow)
    atlas.paste(it, R['interior'][:2])
    A._emit_box(emit, R['interior'], (36, 24, 12))
    sws = A._swatches(atlas, R['swatch'], SW, SW_NOTE)
    A._write('hieda_house', 'V2_HiedaHouse', atlas, emit, R, sws,
             ' R6 稗田邸本屋（tools/build_village_v2_r6_atlas.py）：千本格子、二樓格子窗、障子、玄關雙扉、'
             '妻面露明木構、雨戶、玄關內；無文字。')


if __name__ == '__main__':
    build()
