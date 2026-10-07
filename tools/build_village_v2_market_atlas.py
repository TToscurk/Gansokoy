#!/usr/bin/env python3
"""人間之里 V2 P10 R1：市集廣場 Kit atlas（market_kit）。

  python tools/build_village_v2_market_atlas.py      （Python310：PIL／numpy）

全新 atlas（既存 Hero／P9 kit の atlas は只讀・不改）。tools/build_village_v2_textures.py の 布／紙／字 工具を import
（木地は _matlib/V2_Wood_albedo.jpg をローカルで切り出す——Poly Haven へは取りに行かない）。
輸出 godot/assets/village_v2/market_kit/{market_kit_atlas.png, atlas.json, MK_Market.tres}。
區域（UV 左上原點）：
  nobori_*   幟 0.45 × 1.80 m（白抜き・墨書き、上に乳＝竿通し）：野菜／御茶／瀬戸物／反物／市
  noren_*    屋台の暖簾 1.8 × 0.5 m（3 枚割り）：藍に白の丸紋／柿渋に白「めし」／生成りに藍「だんご」
  kanban_*   置き看板 0.42 × 0.90 m（木地に墨の縦書き）：やさい／団子／瀬戸物／古着
  awn_*      日除け布（屋台・布棚の屋根）：藍白の縞／生成り／柿渋
  nuno_*     反物・掛け布の柄（64 px）：藍無地／藍格子／茜／若草／鼠／山吹／紺絣／縞
  sw         色票 16 × 16 px の格子（農産物・器・漆・毛氈・番傘 …）：swatches＝{名: [u, v]}
  straw／paper／wood_light／wood_dark／zaru  稲藁・和紙・明るい木地・古い木地・竹笊の編み目
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402

G = T.G
AID = 'market_kit'
NAME = 'MK_Market'
SIZE = 1024
INK = (26, 22, 20)
WHITE = (236, 230, 216)
WOOD_SRC = G + '/assets/village_v2/_matlib/V2_Wood_albedo.jpg'

REGIONS = {}
x = 0
for k in ['nobori_yasai', 'nobori_cha', 'nobori_seto', 'nobori_tanmono', 'nobori_ichi']:
    REGIONS[k] = (x, 0, x + 96, 384)
    x += 100
for i, k in enumerate(['kanban_yasai', 'kanban_dango', 'kanban_seto', 'kanban_furugi']):
    REGIONS[k] = (500 + i * 100, 0, 596 + i * 100, 204)
for i, k in enumerate(['noren_mon', 'noren_meshi', 'noren_dango']):
    REGIONS[k] = (500, 212 + i * 58, 864, 266 + i * 58)
for i, k in enumerate(['awn_shima', 'awn_kinari', 'awn_kaki']):
    REGIONS[k] = (i * 172, 392, i * 172 + 168, 560)
for i, k in enumerate(['nuno_ai', 'nuno_koshi', 'nuno_akane', 'nuno_wakakusa', 'nuno_nezumi', 'nuno_yamabuki', 'nuno_kasuri', 'nuno_shima']):
    REGIONS[k] = (520 + (i % 4) * 68, 392 + (i // 4) * 68, 584 + (i % 4) * 68, 456 + (i // 4) * 68)
REGIONS['straw'] = (0, 568, 128, 696)
REGIONS['paper'] = (136, 568, 264, 696)
REGIONS['wood_light'] = (272, 568, 400, 696)
REGIONS['wood_dark'] = (408, 568, 536, 696)
REGIONS['zaru'] = (544, 568, 672, 696)
REGIONS['awn_ai'] = (0, 744, 168, 912)
REGIONS['awn_beni'] = (172, 744, 340, 912)
REGIONS['chochin'] = (344, 744, 472, 872)
SW0 = (0, 704)          # 色票格子の原點、16 px 角、1 行 32 個
SWATCHES = {
    # 農産物
    'daikon': '#EEEBE0', 'daikon_leaf': '#5E8A3A', 'ninjin': '#D8742A', 'nasu': '#3E2A4A', 'kabocha': '#3F5A34',
    'kabocha_in': '#D99A2E', 'kyabetsu': '#A9C27A', 'kaki': '#E0782A', 'kyuri': '#3F6E2E', 'togarashi': '#B3261E',
    'satoimo': '#7A5E44', 'negi': '#D9E3C2', 'kome': '#E8E2CF', 'mame': '#A88A52', 'cha': '#6E5A3A', 'shiitake': '#5A3F2C',
    'dango_w': '#F0EADC', 'dango_p': '#E8B4B8', 'dango_g': '#9DBA7A', 'shoyu': '#3A2618', 'sakana': '#8C949A',
    'himono': '#9A7A52', 'tamago': '#E9DEC6', 'ringo': '#A8322A',
    # 器・道具
    'hakuji': '#E6E3DA', 'sometsuke': '#3B5B8C', 'ameyu': '#7A4A22', 'kokuyu': '#2A2522', 'haiyu': '#9A9A8A',
    'shuurushi': '#8E2A20', 'urushi': '#1E1A18', 'tetsu': '#3C3A38', 'dou': '#8A6A3A', 'tsuchi': '#9A6E48',
    # 布・その他
    'mousen': '#B32D26', 'bangasa': '#B8352A', 'bangasa_in': '#D8C9A8', 'ai': '#2E4566', 'kon': '#22304A',
    'akane': '#9E3A2E', 'wakakusa': '#8FA35A', 'nezumi': '#7E7C76', 'yamabuki': '#D9A62E', 'kinari': '#DCD3BE',
    'kakishibu': '#8A5A34', 'take': '#B5A36A', 'take_ao': '#7E9A52', 'nawa': '#9A8256', 'komo': '#B8A27A',
    'sumi': '#1E1B18', 'wara': '#C9B07A', 'kuri': '#6A4A30',
    'takuan': '#E3C04A', 'ume': '#A8302E',
}


def sz(k):
    x0, y0, x1, y1 = REGIONS[k]
    return x1 - x0, y1 - y0


def wood(w, h, tone, seed, vertical=False):
    """_matlib V2_Wood の albedo から切り出して色を合わせる（木目は縦／横）。"""
    a = np.asarray(Image.open(WOOD_SRC).convert('RGB'), dtype=np.float32) / 255.0
    if not vertical:
        a = np.rot90(a, 1)
    rng = np.random.default_rng(seed)
    hh, ww = a.shape[:2]
    cw, ch = min(ww, w * 3), min(hh, h * 3)
    y0 = int(rng.integers(0, hh - ch + 1))
    x0 = int(rng.integers(0, ww - cw + 1))
    crop = Image.fromarray((a[y0:y0 + ch, x0:x0 + cw] * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    c = np.asarray(crop, dtype=np.float32) / 255.0
    mean = c.reshape(-1, 3).mean(0)
    c = np.clip(c * (T.hexrgb(tone) / np.maximum(mean, 1e-4)), 0, 1)
    return Image.fromarray((c * 255).astype(np.uint8))


def ink_text(img, xy, s, size, color, vertical=True, blur=0.7, stroke=1):
    m = Image.new('L', img.size, 0)
    T._text(m, xy, s, size, 255, vertical=vertical, stroke=stroke)
    m = m.filter(ImageFilter.GaussianBlur(blur))
    img.paste(Image.new('RGB', img.size, color), (0, 0), m)


def build():
    atlas = Image.new('RGB', (SIZE, SIZE), (150, 132, 104))
    rng = np.random.default_rng(1010)
    # ── 幟：地色の布＋縦書き（白抜き or 墨）＋上端の乳（竿通しの輪）＋下端の房なし
    nob = {'nobori_yasai': ('#2E4566', '野菜', WHITE), 'nobori_cha': ('#3F5A34', '御茶', WHITE),
           'nobori_seto': ('#E4DCC8', '瀬戸物', INK), 'nobori_tanmono': ('#8E2A20', '反物', WHITE),
           'nobori_ichi': ('#E4DCC8', '市', (150, 30, 24))}
    for i, (k, (base, txt, col)) in enumerate(nob.items()):
        w, h = sz(k)
        cl = T._cloth(w, h, base, 1100 + i)
        d = ImageDraw.Draw(cl)
        # 縁取りの帯（上と左に別色の布）
        d.rectangle((0, 0, w - 1, 14), fill=tuple(int(c * 0.75) for c in T.hexrgb(base) * 255))
        for j in range(5):
            d.rectangle((w - 14, 24 + j * 72, w - 1, 36 + j * 72), fill=(200, 192, 176) if base != '#E4DCC8' else (120, 108, 92))
        n = len(txt)
        fs = 64 if n <= 2 else 52
        if n == 1:
            fs = 84
        top = (h - 14) / 2 - (n - 1) * fs * 0.52 + 8
        ink_text(cl, (w // 2 - 4, int(top)), txt, fs, col, vertical=True, stroke=2 if n <= 2 else 1, blur=0.7 if n <= 2 else 0.4)
        atlas.paste(cl, REGIONS[k][:2])
    # ── 置き看板：木地＋墨の縦書き＋枠
    kb = {'kanban_yasai': ('#B79A72', 'やさい'), 'kanban_dango': ('#C2A47A', '団子'),
          'kanban_seto': ('#A88A62', '瀬戸物'), 'kanban_furugi': ('#B49470', '古着')}
    for i, (k, (tone, txt)) in enumerate(kb.items()):
        w, h = sz(k)
        bd = wood(w, h, tone, 1200 + i, vertical=True)
        d = ImageDraw.Draw(bd)
        d.rectangle((0, 0, w - 1, h - 1), outline=(80, 60, 42), width=5)
        n = len(txt)
        fs = 52 if n <= 2 else 44
        top = h / 2 - (n - 1) * fs * 0.52
        ink_text(bd, (w // 2, int(top)), txt, fs, INK, vertical=True)
        atlas.paste(bd, REGIONS[k][:2])
    # ── 屋台の暖簾 3 枚割り：地色＋文字／紋、割れ目（縦の暗線）
    nr = {'noren_mon': ('#2E4566', None, WHITE), 'noren_meshi': ('#8A5A34', 'めし', WHITE), 'noren_dango': ('#DCD3BE', 'だんご', (46, 69, 102))}
    for i, (k, (base, txt, col)) in enumerate(nr.items()):
        w, h = sz(k)
        cl = T._cloth(w, h, base, 1300 + i)
        d = ImageDraw.Draw(cl)
        for j in (1, 2):
            xx = j * w // 3
            d.line((xx, 6, xx, h), fill=tuple(int(c * 0.45) for c in T.hexrgb(base) * 255), width=3)
        d.rectangle((0, 0, w - 1, 6), fill=tuple(int(c * 0.6) for c in T.hexrgb(base) * 255))
        if txt is None:
            for j in range(3):
                cx = w // 6 + j * w // 3
                d.ellipse((cx - 20, h // 2 - 18, cx + 20, h // 2 + 22), outline=col, width=5)
                d.line((cx - 10, h // 2 - 6, cx, h // 2 + 12), fill=col, width=5)
                d.line((cx + 10, h // 2 - 6, cx, h // 2 + 12), fill=col, width=5)
        else:
            for j, ch in enumerate(txt):
                cx = w // (2 * len(txt)) + j * w // len(txt)
                ink_text(cl, (cx, h // 2 + 2), ch, 38, col, vertical=False, blur=0.5)
        atlas.paste(cl, REGIONS[k][:2])
    # ── 日除け布
    w, h = sz('awn_shima')
    base = T._cloth(w, h, '#E2DACA', 1400)
    d = ImageDraw.Draw(base)
    for j in range(0, w, 28):
        d.rectangle((j, 0, j + 13, h), fill=(46, 66, 98))
    atlas.paste(base.filter(ImageFilter.GaussianBlur(0.6)), REGIONS['awn_shima'][:2])
    atlas.paste(T._cloth(w, h, '#D8CFB8', 1401), REGIONS['awn_kinari'][:2])
    atlas.paste(T._cloth(w, h, '#8A5A34', 1402), REGIONS['awn_kaki'][:2])
    atlas.paste(T._cloth(w, h, '#2E4566', 1403), REGIONS['awn_ai'][:2])
    bn = T._cloth(w, h, '#B8352A', 1404)
    d = ImageDraw.Draw(bn)
    for j in range(0, w, 42):
        d.rectangle((j, 0, j + 6, h), fill=(232, 222, 200))
    atlas.paste(bn, REGIONS['awn_beni'][:2])
    # 提灯：赤い紙＋上下の黒い枠＋横の骨の陰影＋「市」
    w2, h2 = sz('chochin')
    ch = T._paper(w2, h2, 1405, tone='#C8392C')
    d = ImageDraw.Draw(ch)
    for j in range(0, h2, 9):
        d.line((0, j, w2, j), fill=(150, 36, 28), width=2)
    d.rectangle((0, 0, w2, 12), fill=(30, 26, 24))
    d.rectangle((0, h2 - 12, w2, h2), fill=(30, 26, 24))
    ink_text(ch, (w2 // 2, h2 // 2), '市', 64, (24, 20, 18), vertical=False, blur=0.5)
    atlas.paste(ch, REGIONS['chochin'][:2])
    # ── 反物の柄
    pat = {'nuno_ai': ('#2E4566', None), 'nuno_koshi': ('#2E4566', 'koshi'), 'nuno_akane': ('#9E3A2E', None),
           'nuno_wakakusa': ('#8FA35A', None), 'nuno_nezumi': ('#7E7C76', 'shima'), 'nuno_yamabuki': ('#D9A62E', None),
           'nuno_kasuri': ('#22304A', 'kasuri'), 'nuno_shima': ('#DCD3BE', 'shima_ai')}
    for i, (k, (base, kind)) in enumerate(pat.items()):
        w, h = sz(k)
        cl = T._cloth(w, h, base, 1500 + i)
        d = ImageDraw.Draw(cl)
        if kind == 'koshi':
            for j in range(0, w, 16):
                d.line((j, 0, j, h), fill=(210, 205, 190), width=2)
                d.line((0, j, w, j), fill=(210, 205, 190), width=2)
        elif kind == 'shima':
            for j in range(0, w, 10):
                d.line((j, 0, j, h), fill=(60, 58, 54), width=3)
        elif kind == 'shima_ai':
            for j in range(0, w, 12):
                d.line((j, 0, j, h), fill=(46, 66, 98), width=4)
        elif kind == 'kasuri':
            for j in range(4, h, 16):
                for q in range(6 + (j // 16 % 2) * 8, w, 16):
                    d.line((q - 3, j, q + 3, j), fill=(205, 200, 186), width=3)
                    d.line((q, j - 3, q, j + 3), fill=(205, 200, 186), width=3)
        atlas.paste(cl, REGIONS[k][:2])
    # ── 稲藁・和紙・木地・竹笊
    w, h = sz('straw')
    fib = rng.normal(0, 1, (h, 1)).astype(np.float32)
    sv = np.clip(T.hexrgb('#C9B07A')[None, None, :] * (0.86 + 0.09 * fib[..., None] + 0.05 * np.sin(np.arange(w) * 0.9)[None, :, None]), 0, 1)
    atlas.paste(Image.fromarray((sv * 255).astype(np.uint8)), REGIONS['straw'][:2])
    atlas.paste(T._paper(*sz('paper'), 1601, tone='#EFEBE2'), REGIONS['paper'][:2])
    atlas.paste(wood(*sz('wood_light'), '#A9875E', 1602), REGIONS['wood_light'][:2])
    atlas.paste(wood(*sz('wood_dark'), '#6E5638', 1603), REGIONS['wood_dark'][:2])
    w, h = sz('zaru')
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    weave = 0.5 + 0.5 * np.sign(np.sin(xx * 0.55) * np.sin(yy * 0.55))
    zc = np.clip(T.hexrgb('#B5A36A')[None, None, :] * (0.78 + 0.22 * weave[..., None]), 0, 1)
    atlas.paste(Image.fromarray((zc * 255).astype(np.uint8)), REGIONS['zaru'][:2])
    # ── 色票格子
    sw_uv = {}
    for i, (k, hx) in enumerate(SWATCHES.items()):
        cx = SW0[0] + (i % 32) * 16
        cy = SW0[1] + (i // 32) * 16
        ImageDraw.Draw(atlas).rectangle((cx, cy, cx + 15, cy + 15), fill=tuple(int(round(c * 255)) for c in T.hexrgb(hx)))
        sw_uv[k] = [(cx + 8) / SIZE, (cy + 8) / SIZE]
    out = f'{G}/assets/village_v2/{AID}'
    os.makedirs(out, exist_ok=True)
    atlas.save(f'{out}/{AID}_atlas.png', optimize=True)
    uv = {k: [x0 / SIZE, y0 / SIZE, x1 / SIZE, y1 / SIZE] for k, (x0, y0, x1, y1) in REGIONS.items()}
    with open(f'{out}/atlas.json', 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'_note': f'{AID} atlas（UV 左上原點；Blender 端 v 要 1−v）。由 tools/build_village_v2_market_atlas.py 產生。'
                   ' 文字：幟「野菜 御茶 瀬戸物 反物 市」、置き看板「やさい 団子 瀬戸物 古着」、暖簾「めし だんご」＋丸紋。',
                   'size': SIZE, 'regions': uv, 'swatches': sw_uv, 'font': 'kaiu.ttf（標楷體，Windows 內建）'}, f, ensure_ascii=False, indent=1)
        f.write('\n')
    T.write_import(f'res://assets/village_v2/{AID}/{AID}_atlas.png', False)
    T.write_tres(f'{out}/{NAME}.tres', NAME, {'albedo': f'res://assets/village_v2/{AID}/{AID}_atlas.png'},
                 ['roughness = 0.9'], k=0.8)
    print('atlas →', f'{out}/{AID}_atlas.png', len(SWATCHES), 'swatches')


if __name__ == '__main__':
    build()
