#!/usr/bin/env python3
"""人間之里 V2 P5 R2：鯢吞亭／霧雨店 Hero atlas 產生器。

  python tools/build_village_v2_r2_atlases.py [geidontei] [kirisame]

沿用 tools/build_village_v2_textures.py 的工具（貼圖取色、紙／布、.import、.tres 規約）；不重建共享材質庫與鈴奈庵
atlas。輸出（每件）：godot/assets/village_v2/<id>/<id>_atlas.png、<id>_emit.png、atlas.json、V2_<Id>.tres。
參考：docs/reference/重點地標/{鲵吞亭_正面,鲵吞亭_側面,鯢吞燈籠正面,霧雨店,霧雨燈籠,霧雨特價}.png。
"""
import json
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402

G = T.G
SIZE = 2048
FONT_GOTH = 'C:/Windows/Fonts/msgothic.ttc'   # 黑板粉筆字（假名）


def _fill(img, box, rgb):
    ImageDraw.Draw(img).rectangle(box, fill=tuple(int(v) for v in rgb))


def _hex255(h):
    return tuple(int(v * 255) for v in T.hexrgb(h))


def _mottle(w, h, base, spot, seed, spots=260, rmin=4, rmax=26, pale=None):
    """山椒魚皮：底色＋深色不規則斑＋少量淡斑＋細顆粒。"""
    rng = np.random.default_rng(seed)
    img = T._cloth(w, h, base, seed)
    d = ImageDraw.Draw(img)
    for _ in range(spots):
        x, y = rng.integers(0, w), rng.integers(0, h)
        r = rng.integers(rmin, rmax)
        pts = [(x + math.cos(t) * r * rng.uniform(0.6, 1.3), y + math.sin(t) * r * rng.uniform(0.6, 1.3))
               for t in np.linspace(0, 2 * math.pi, 9)[:-1]]
        d.polygon(pts, fill=_hex255(spot))
    if pale:
        for _ in range(spots // 3):
            x, y = rng.integers(0, w), rng.integers(0, h)
            r = rng.integers(3, 9)
            d.ellipse((x - r, y - r, x + r, y + r), fill=_hex255(pale))
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    a = np.asarray(img, dtype=np.float32) / 255.0
    a *= 1 + rng.normal(0, 0.05, (h, w, 1)).astype(np.float32)
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


def _chochin(w, h, paper, ch, ink, seed, circ_m, h_m, char_m, ring=False, vertical=False):
    """提燈紙面（展開後貼在圓柱上：u 繞一圈＝周長 circ_m、v＝燈身高 h_m；字在 u 0.25（正面）與 0.75（背面）各一次）。
    u 方向每像素的公尺數比 v 大很多 → 每個字先畫在正方形上、再依 char_m／circ_m、char_m／h_m 縮放，
    貼到燈上才是正方形字（R2 第一版直接畫 → 字被橫向拉 2.6–5 倍、讀不出來）。"""
    img = T._paper(w, h, seed, tone=paper)
    d = ImageDraw.Draw(img)
    for k in range(1, 14):            # 竹骨
        y = int(h * k / 14)
        d.line((0, y, w, y), fill=tuple(int(c * 0.72) for c in _hex255(paper)), width=2)
    gw = max(8, int(round(char_m / circ_m * w)))
    gh = max(8, int(round(char_m / h_m * h)))
    glyphs = list(ch) if vertical else [ch]
    n = len(glyphs)
    for cx in (w * 0.25, w * 0.75):
        for i, g in enumerate(glyphs):
            S = 256
            gl = Image.new('L', (S, S), 0)
            if ring:
                ImageDraw.Draw(gl).ellipse((10, 10, S - 10, S - 10), outline=255, width=22)
                T._text(gl, (S // 2, S // 2 + 4), g, int(S * 0.56), 255, stroke=2)
            else:
                T._text(gl, (S // 2, S // 2 + 6), g, int(S * 0.86), 255, stroke=3)
            gl = gl.resize((gw, gh), Image.LANCZOS)
            y = h / 2 + (i - (n - 1) / 2) * gh * 1.04
            img.paste(Image.new('RGB', (gw, gh), _hex255(ink)), (int(cx - gw / 2), int(y - gh / 2)), gl)
    return img


def _write(aid, name, atlas, emit, regions, swatches, extra_note=''):
    out = f'{G}/assets/village_v2/{aid}'
    os.makedirs(out, exist_ok=True)
    atlas.save(f'{out}/{aid}_atlas.png', optimize=True)
    emit.save(f'{out}/{aid}_emit.png', optimize=True)
    uv = {k: [x0 / SIZE, y0 / SIZE, x1 / SIZE, y1 / SIZE] for k, (x0, y0, x1, y1) in regions.items()}
    with open(f'{out}/atlas.json', 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'_note': f'{aid} Hero atlas（UV 左上原點；Blender 端 v 要 1−v）。由 tools/build_village_v2_r2_atlases.py 產生。'
                   + extra_note, 'size': SIZE, 'regions': uv, 'swatches': swatches,
                   'font': 'kaiu.ttf（標楷體）／msgothic.ttc（Windows 內建）'}, f, ensure_ascii=False, indent=1)
        f.write('\n')
    for fn in (f'{aid}_atlas.png', f'{aid}_emit.png'):
        T.write_import(f'res://assets/village_v2/{aid}/{fn}', False)
    T.write_tres(f'{out}/{name}.tres', name, {'albedo': f'res://assets/village_v2/{aid}/{aid}_atlas.png',
                                              'emit': f'res://assets/village_v2/{aid}/{aid}_emit.png'},
                 ['roughness = 0.9'])
    print('atlas →', f'{out}/{aid}_atlas.png')


def _swatches(atlas, box, cols, notes):
    x0, y0, x1, y1 = box
    n = len(cols)
    per = 4
    rows = (n + per - 1) // per
    sw, sh = (x1 - x0) // per, (y1 - y0) // rows
    out = {}
    for i, c in enumerate(cols):
        bx = (x0 + (i % per) * sw, y0 + (i // per) * sh, x0 + (i % per + 1) * sw - 1, y0 + (i // per + 1) * sh - 1)
        _fill(atlas, bx, T.hexrgb(c) * 255)
        out[c] = {'uv': [(bx[0] + bx[2] + 1) / 2 / SIZE, (bx[1] + bx[3] + 1) / 2 / SIZE], 'note': notes[i]}
    return out


def _emit_box(emit, box, rgb=(255, 205, 140)):
    x0, y0, x1, y1 = box
    ImageDraw.Draw(emit).rectangle((x0 // 4, y0 // 4, x1 // 4 - 1, y1 // 4 - 1), fill=rgb)


# ───────────────────────── 鯢吞亭 ─────────────────────────
GD_REGIONS = {
    'skin': (0, 0, 1024, 512),            # 山椒魚頭皮（藕紫灰＋深紫斑）；經緯展開
    'eye': (1024, 0, 1280, 256),          # 眼（琥珀虹膜＋黑瞳＋高光）
    'mouth': (1280, 0, 1536, 256),        # 口腔（暗紅褐）
    'noren': (0, 512, 1024, 768),         # 紫暖簾 2 片（左右各半），白色圓形植物紋
    'noren_back': (1024, 256, 1536, 320),
    'name_lantern': (1024, 1280, 2048, 1792),  # 「鯢吞亭」大提燈（展開，u 0.25／0.75 各一次；r 0.36、身高 0.80）
    'interior': (0, 768, 1024, 1280),     # 店內：櫃檯、酒瓶架、暖光
    'lattice_paper': (1024, 512, 1280, 768),  # 格子後的暖色紙（微發光）
    'lattice_dark': (1280, 512, 1536, 768),   # 二樓格子後的暗色板
    'toro_window': (1536, 512, 1664, 640),    # 石燈籠火袋窗
    'swatch': (1024, 1024, 1536, 1280),
}
GD_RED = ['酒', '肴', '菜', '鮮', '味', '膳', '壽', '樂']   # 1F 左 3、右 3；2F 兩端
for i, ch in enumerate(GD_RED):
    GD_REGIONS[f'red_{i}'] = ((i % 4) * 256, 1280 + (i // 4) * 256, (i % 4 + 1) * 256, 1280 + (i // 4 + 1) * 256)
GD_SW = ['#D9A441', '#E8DDC4', '#C98F97', '#2A1A14', '#1E1B18', '#5F4A63', '#8C8C86', '#3E2A1E', '#E7AEB5', '#E6D9BC']
GD_SW_NOTE = ['古金（破風金具、懸魚、柱頭）', '象牙（牙）', '粉紫（門柱唇帶）', '口腔深處', '近黑（鐵件）', '深紫（皮暗部）',
              '石燈籠灰', '深褐（室內）', '淺粉（上顎唇管）', '米白（眼眶）']


def build_geidontei():
    atlas = Image.new('RGB', (SIZE, SIZE), (40, 32, 30))
    emit = Image.new('RGB', (SIZE // 4, SIZE // 4), (0, 0, 0))
    R = GD_REGIONS

    def sz(k):
        x0, y0, x1, y1 = R[k]
        return x1 - x0, y1 - y0

    # 皮色要比周圍深色木作亮一階（× albedo_k 0.42 後仍要在暗立面前分得出頭形；R2 首版 #7E7089 在實機畫面裡跟屋簷糊成一片）
    atlas.paste(_mottle(*sz('skin'), '#B3A3BE', '#4E3D5C', 31, spots=340, pale='#D6CCDD'), R['skin'][:2])
    # 眼
    w, h = sz('eye')
    ey = Image.new('RGB', (w, h), _hex255('#4A3A4E'))
    d = ImageDraw.Draw(ey)
    d.ellipse((18, 18, w - 18, h - 18), fill=_hex255('#D29A2E'))
    for k in range(10):
        r = 40 + k * 7
        d.ellipse((w / 2 - r, h / 2 - r, w / 2 + r, h / 2 + r), outline=_hex255('#B07A1E'), width=2)
    d.ellipse((w / 2 - 44, h / 2 - 52, w / 2 + 44, h / 2 + 52), fill=(12, 10, 10))
    d.ellipse((w / 2 - 50, h / 2 - 70, w / 2 - 18, h / 2 - 38), fill=(250, 250, 245))
    atlas.paste(ey, R['eye'][:2])
    atlas.paste(_mottle(*sz('mouth'), '#4A1E1C', '#2A1210', 32, spots=40), R['mouth'][:2])
    # 暖簾：深紫 2 片，各一個白色圓形植物紋
    w, h = sz('noren')
    nr = T._cloth(w, h, '#4B3656', 33)
    d = ImageDraw.Draw(nr)
    d.rectangle((0, 0, w, int(h * 0.08)), fill=_hex255('#35263D'))
    for i in range(2):
        cx, cy, r = w * (i + 0.5) / 2, h * 0.56, h * 0.28
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(226, 220, 206), width=12)
        for k in range(5):     # 葉
            a = -math.pi / 2 + (k - 2) * 0.55
            px, py = cx + math.cos(a) * r * 0.45, cy + math.sin(a) * r * 0.45
            d.ellipse((px - r * 0.2, py - r * 0.34, px + r * 0.2, py + r * 0.34), fill=(226, 220, 206))
        d.line((cx, cy - r * 0.2, cx, cy + r * 0.7), fill=(226, 220, 206), width=10)
    d.line((w // 2, 0, w // 2, h), fill=_hex255('#281C2E'), width=4)
    atlas.paste(nr, R['noren'][:2])
    atlas.paste(T._cloth(*sz('noren_back'), '#3E2D47', 34), R['noren_back'][:2])
    # 大提燈「鯢吞亭」：金黃紙、黑字直書
    w, h = sz('name_lantern')
    atlas.paste(_chochin(w, h, '#E3B45C', '鯢吞亭', '#17110C', 35, 2 * math.pi * 0.36, 0.80, 0.22, vertical=True),
                R['name_lantern'][:2])
    _emit_box(emit, R['name_lantern'], (255, 196, 120))
    # 紅提燈：朱紙白字
    for i, ch in enumerate(GD_RED):
        w, h = sz(f'red_{i}')
        atlas.paste(_chochin(w, h, '#C23A22', ch, '#F2E8D4', 40 + i, 2 * math.pi * 0.16, 0.36, 0.20), R[f'red_{i}'][:2])
        _emit_box(emit, R[f'red_{i}'], (255, 120, 70))
    # 店內：暗木牆＋酒瓶架三層＋櫃檯＋暖光
    w, h = sz('interior')
    it = T._wood_patch(w, h, '#4A3322', 36)
    d = ImageDraw.Draw(it)
    rnd = random.Random(7)
    for row in range(3):
        y = int(h * (0.12 + row * 0.2))
        d.rectangle((0, y + 58, w, y + 66), fill=_hex255('#2A1C12'))
        x = 8
        while x < w - 30:
            bw = rnd.randint(18, 30)
            bh = rnd.randint(34, 56)
            c = _hex255(rnd.choice(['#4E6B3A', '#7A4A22', '#2F4A5A', '#C9B07A', '#6B2E22', '#E0D6BC']))
            d.rectangle((x, y + 58 - bh, x + bw, y + 58), fill=c)
            d.rectangle((x + bw // 3, y + 58 - bh - 12, x + bw - bw // 3, y + 58 - bh), fill=c)
            if rnd.random() < 0.6:
                d.rectangle((x + 3, y + 58 - bh // 2 - 8, x + bw - 3, y + 58 - bh // 2 + 6), fill=(230, 222, 200))
            x += bw + rnd.randint(4, 10)
    d.rectangle((0, int(h * 0.72), w, h), fill=_hex255('#5A3C24'))          # 櫃檯
    d.rectangle((0, int(h * 0.72), w, int(h * 0.75)), fill=_hex255('#7A5534'))
    glow = Image.new('L', (w, h), 0)
    ImageDraw.Draw(glow).ellipse((w * 0.2, -h * 0.3, w * 0.8, h * 0.5), fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(60))
    it = Image.composite(Image.new('RGB', (w, h), (255, 190, 110)), it, glow)
    atlas.paste(it, R['interior'][:2])
    atlas.paste(T._paper(*sz('lattice_paper'), 37, tone='#E2C79A'), R['lattice_paper'][:2])
    _emit_box(emit, R['lattice_paper'], (120, 90, 55))
    atlas.paste(T._wood_patch(*sz('lattice_dark'), '#2C2119', 38), R['lattice_dark'][:2])
    atlas.paste(T._paper(*sz('toro_window'), 39, tone='#F0D8A0'), R['toro_window'][:2])
    _emit_box(emit, R['toro_window'], (255, 200, 120))
    sws = _swatches(atlas, R['swatch'], GD_SW, GD_SW_NOTE)
    _write('geidontei', 'V2_Geidontei', atlas, emit, R, sws, ' 紅提燈字：' + '、'.join(GD_RED) + '。')


# ───────────────────────── 霧雨店 ─────────────────────────
KS_REGIONS = {
    'sign': (0, 0, 1024, 288),            # 「霧雨店」扇形邊木額（兩端綠葉＋黃白小花）
    'sign_wood': (1024, 0, 1280, 256),
    'noren': (0, 288, 1024, 544),         # 深綠暖簾：星、新月、流星（無字）
    'noren_back': (1280, 0, 1536, 64),
    'goods': (0, 544, 1024, 1056),        # 貨架：藥瓶、罐、盒、書（4 層）
    'spines': (1024, 256, 1536, 512),     # 書背
    'chalk': (1536, 0, 1792, 384),        # A 字黑板「魔法道具 特別セール！…」
    'lantern_ma': (0, 1056, 512, 1312),   # 「魔」提燈（圓框；r 0.22、身高 0.44）
    'oval_ma': (1792, 256, 2048, 448),    # 立柱吊牌（橢圓木牌、魔）
    'cloth_red': (1024, 512, 1280, 768),  # 展示桌紅布
    'hat': (1280, 512, 1536, 768),        # 魔女帽黑布
    'gable_boards': (1536, 448, 1792, 704),  # 破風內蜂蜜色木板
    'glass': (1792, 448, 2048, 704),      # 金屬燈籠暖色玻璃
    'flowers': (1024, 768, 1536, 1024),   # 木桶花台：葉＋白黃粉紅小花
    'swatch': (1536, 704, 2048, 960),
}
KS_SW = ['#1E1B18', '#B7A6C9', '#7A5A36', '#4B6B45', '#C9A24A', '#3A5F6E', '#8E3B2C', '#D8CFB8']
KS_SW_NOTE = ['近黑（鐵件、帽）', '淡紫灰（帽上蝴蝶結）', '桶木', '綠玻璃', '金（燈籠框）', '藍綠玻璃', '赤陶', '米白']


def build_kirisame():
    atlas = Image.new('RGB', (SIZE, SIZE), (38, 32, 26))
    emit = Image.new('RGB', (SIZE // 4, SIZE // 4), (0, 0, 0))
    R = KS_REGIONS
    rnd = random.Random(20260925)

    def sz(k):
        x0, y0, x1, y1 = R[k]
        return x1 - x0, y1 - y0

    # 額：暖金褐木紋＋「霧雨店」墨字＋兩端綠葉白黃花（網格決定扇形外緣）
    w, h = sz('sign')
    sg = T._wood_patch(w, h, '#D9B47A', 51)   # 淺色木：×albedo_k 0.42 之後仍與墨字有對比
    d = ImageDraw.Draw(sg)
    d.rectangle((0, 0, w - 1, h - 1), outline=_hex255('#5A3F22'), width=16)
    for side in (0, 1):
        cx = 70 if side == 0 else w - 70
        for k in range(7):
            a = k * 0.9
            px, py = cx + math.cos(a) * 34, h / 2 + math.sin(a) * 60
            d.ellipse((px - 26, py - 12, px + 26, py + 12), fill=_hex255('#4E7A3A'))
        for k in range(6):
            px, py = cx + rnd.uniform(-30, 30), h / 2 + rnd.uniform(-70, 70)
            d.ellipse((px - 9, py - 9, px + 9, py + 9), fill=_hex255(rnd.choice(['#F2E8C8', '#E8C84A'])))
    txt = Image.new('L', (w, h), 0)
    T._text(txt, (w // 2, h // 2 + 4), '霧雨店', 196, 255, stroke=3)
    wear = np.asarray(txt, dtype=np.float32)[..., None] / 255.0
    a = np.asarray(sg, dtype=np.float32) / 255.0
    a = a * (1 - wear * 0.94) + T.hexrgb('#140F0B') * wear * 0.94
    atlas.paste(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)), R['sign'][:2])
    atlas.paste(T._wood_patch(*sz('sign_wood'), '#7A5A34', 52), R['sign_wood'][:2])
    # 暖簾：深綠、米白星／新月／流星
    w, h = sz('noren')
    nr = T._cloth(w, h, '#2E5247', 53)
    d = ImageDraw.Draw(nr)
    d.rectangle((0, 0, w, int(h * 0.08)), fill=_hex255('#22403A'))
    star = (232, 224, 198)

    def draw_star(cx, cy, r, pts=5):
        P = []
        for k in range(pts * 2):
            rr = r if k % 2 == 0 else r * 0.42
            ang = -math.pi / 2 + k * math.pi / pts
            P.append((cx + math.cos(ang) * rr, cy + math.sin(ang) * rr))
        d.polygon(P, fill=star)
    for _ in range(26):
        draw_star(rnd.uniform(20, w - 20), rnd.uniform(h * 0.18, h * 0.92), rnd.uniform(6, 20))
    d.ellipse((120, 70, 230, 180), fill=star)
    d.ellipse((150, 58, 262, 168), fill=_hex255('#2E5247'))       # 新月
    d.line((600, 190, 780, 90), fill=star, width=6)                # 流星
    draw_star(790, 84, 30)
    for i in range(1, 6):
        d.line((int(w * i / 6), 0, int(w * i / 6), h), fill=_hex255('#1E3832'), width=3)
    atlas.paste(nr, R['noren'][:2])
    atlas.paste(T._cloth(*sz('noren_back'), '#284A40', 54), R['noren_back'][:2])
    # 貨架：4 層
    w, h = sz('goods')
    gd = T._wood_patch(w, h, '#3A2A1C', 55)
    d = ImageDraw.Draw(gd)
    for row in range(4):
        y1 = int(h * (row + 1) / 4) - 6
        d.rectangle((0, y1, w, y1 + 6), fill=_hex255('#5A4028'))
        x = 6
        while x < w - 40:
            kind = rnd.random()
            if kind < 0.45:      # 瓶
                bw, bh = rnd.randint(18, 30), rnd.randint(50, 92)
                c = _hex255(rnd.choice(['#4B6B45', '#3A5F6E', '#8A5A22', '#6B3F7A', '#A63A2C', '#7FA36A']))
                d.ellipse((x, y1 - bh * 0.6, x + bw, y1), fill=c)
                d.rectangle((x + bw * 0.35, y1 - bh, x + bw * 0.65, y1 - bh * 0.5), fill=c)
                d.rectangle((x + bw * 0.3, y1 - bh - 6, x + bw * 0.7, y1 - bh), fill=_hex255('#8A6A44'))
                d.rectangle((x + 4, y1 - bh * 0.4, x + bw - 4, y1 - bh * 0.2), fill=(226, 218, 196))
            elif kind < 0.7:     # 罐
                bw, bh = rnd.randint(30, 48), rnd.randint(34, 56)
                c = _hex255(rnd.choice(['#8C7B6A', '#5A4E44', '#B8A07A', '#44505A']))
                d.rectangle((x, y1 - bh, x + bw, y1), fill=c)
                d.rectangle((x - 2, y1 - bh - 6, x + bw + 2, y1 - bh), fill=tuple(int(v * 0.7) for v in c))
            elif kind < 0.85:    # 盒
                bw, bh = rnd.randint(34, 60), rnd.randint(22, 40)
                d.rectangle((x, y1 - bh, x + bw, y1), fill=_hex255(rnd.choice(['#C9B48A', '#8E3B2C', '#D8CFB8'])))
            else:                # 書
                bw = 0
                for _ in range(rnd.randint(3, 6)):
                    tw, th = rnd.randint(10, 18), rnd.randint(60, 96)
                    d.rectangle((x + bw, y1 - th, x + bw + tw - 1, y1),
                                fill=_hex255(rnd.choice(['#8E3B2C', '#C9A24A', '#2F4A5A', '#4B6B45', '#D8CFB8'])))
                    bw += tw
            x += bw + rnd.randint(4, 12)
    atlas.paste(gd, R['goods'][:2])
    # 書背（直接沿用 R1 的畫法：隨機高低、題簽）
    w, h = sz('spines')
    sp = Image.new('RGB', (w, h), (30, 24, 19))
    d = ImageDraw.Draw(sp)
    for row in range(2):
        x, y1 = 2, row * 128 + 125
        while x < w - 4:
            bw, bh = rnd.randint(14, 28), rnd.randint(80, 118)
            d.rectangle((x, y1 - bh, x + bw - 2, y1), fill=_hex255(rnd.choice(
                ['#3C4652', '#5A4632', '#8C7446', '#6E3A30', '#C9BFA6', '#4F5A45', '#6B3F7A'])))
            x += bw
    atlas.paste(sp, R['spines'][:2])
    # 黑板
    w, h = sz('chalk')
    cb = Image.new('RGB', (w, h), _hex255('#23262A'))
    ns = np.asarray(cb, dtype=np.float32) / 255.0
    ns = ns * (1 + np.random.default_rng(56).normal(0, 0.06, (h, w, 1)))
    cb = Image.fromarray((np.clip(ns, 0, 1) * 255).astype(np.uint8))
    chalk = (232, 226, 210)
    T._text(cb, (w // 2, 44), '魔法道具', 50, chalk, font=T.FONT_KAI)
    T._text(cb, (w // 2, 100), '特別セール！', 38, chalk, font=FONT_GOTH)
    ImageDraw.Draw(cb).line((24, 132, w - 24, 132), fill=_hex255('#C9A24A'), width=3)
    for i, s in enumerate(['今だけの特別価格！', '杖・ポーション・書物', '人気アイテムが', 'お得に手に入る', 'チャンス！']):
        T._text(cb, (w // 2, 162 + i * 38), s, 24, chalk, font=FONT_GOTH)
    d = ImageDraw.Draw(cb)
    d.ellipse((30, 336, 70, 376), outline=chalk, width=3)
    d.rectangle((44, 318, 56, 338), outline=chalk, width=3)
    for k in range(8):
        a = k * math.pi / 4
        d.line((w / 2, 350, w / 2 + math.cos(a) * 18, 350 + math.sin(a) * 18), fill=_hex255('#C9A24A'), width=3)
    atlas.paste(cb, R['chalk'][:2])
    # 魔 提燈
    w, h = sz('lantern_ma')
    atlas.paste(_chochin(w, h, '#E6C47A', '魔', '#15100C', 57, 2 * math.pi * 0.22, 0.44, 0.30, ring=True),
                R['lantern_ma'][:2])
    _emit_box(emit, R['lantern_ma'], (255, 200, 130))
    # 橢圓吊牌（正面）
    w, h = sz('oval_ma')
    ov = T._wood_patch(w, h, '#9A7446', 58)
    T._text(ov, (w // 2, h // 2), '魔', 120, (26, 20, 14))
    atlas.paste(ov, R['oval_ma'][:2])
    atlas.paste(T._cloth(*sz('cloth_red'), '#9A3E2A', 59), R['cloth_red'][:2])
    atlas.paste(T._cloth(*sz('hat'), '#1E1C22', 60), R['hat'][:2])
    atlas.paste(T._wood_patch(*sz('gable_boards'), '#B08850', 61).rotate(90), R['gable_boards'][:2])
    atlas.paste(T._paper(*sz('glass'), 62, tone='#F2D08A'), R['glass'][:2])
    _emit_box(emit, R['glass'], (255, 205, 130))
    w, h = sz('flowers')
    fo = Image.new('RGB', (w, h), (50, 70, 40))
    d = ImageDraw.Draw(fo)
    for _ in range(900):
        x, y = rnd.randint(0, w), rnd.randint(0, h)
        c = tuple(int(v) for v in T.hexrgb('#577A3A') * 255 * rnd.uniform(0.6, 1.3))
        d.ellipse((x - 8, y - 3, x + 8, y + 3), fill=c)
    for _ in range(220):
        x, y = rnd.randint(0, w), rnd.randint(0, h)
        c = _hex255(rnd.choice(['#F2EEE0', '#E8C84A', '#E88AA0', '#C8403A']))
        d.ellipse((x - 5, y - 5, x + 5, y + 5), fill=c)
    atlas.paste(fo, R['flowers'][:2])
    sws = _swatches(atlas, R['swatch'], KS_SW, KS_SW_NOTE)
    _write('kirisame', 'V2_Kirisame', atlas, emit, R, sws)


if __name__ == '__main__':
    which = sys.argv[1:] or ['geidontei', 'kirisame']
    if 'geidontei' in which:
        build_geidontei()
    if 'kirisame' in which:
        build_kirisame()
