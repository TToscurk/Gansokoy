#!/usr/bin/env python3
"""人間之里 V2 P10 R2：主街 Street Life Kit atlas（street_kit）。

  python tools/build_village_v2_street_atlas.py      （Python310：PIL／numpy）

全新 atlas（既存 Hero／P9／market_kit の atlas は只讀・不改）。tools/build_village_v2_textures.py の 布／紙／字 工具を import、
木地は _matlib/V2_Wood_albedo.jpg をローカルで切り出す（build_village_v2_market_atlas.py と同じ作法）。
輸出 godot/assets/village_v2/street_kit/{street_kit_atlas.png, atlas.json, ST_Street.tres}。
區域（UV 左上原點）：
  nobori_*   幟 0.45 × 1.80 m：酒／米／御食事（市集の 野菜・御茶・瀬戸物・反物・市 とは別の字）
  kanban_*   衝立看板 0.44 × 1.20 m（木地に墨・朱の縦書き）：酒／御米／くすり／油
  andon_*    置行灯の和紙面 0.30 × 0.62 m：めし／御休処／薬
  fuda_*     巷口の道標 0.22 × 0.80 m（木地に墨、下に指し矢）：市 此方／田畑／水車 川／御社
  ichi_big   市の入口の大看板 0.80 × 1.20 m（朱縁・「市」大字・「この奥」）
  chochin_*  提灯（赤・白）
  straw／paper／wood_light／wood_dark／zaru／shiba／ine  稲藁・和紙・木地・竹笊・柴・稲束
  sw         色票 16 × 16 px の格子
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402

G = T.G
AID = 'street_kit'
NAME = 'ST_Street'
SIZE = 1024
INK = (26, 22, 20)
SHU = (168, 40, 30)
WHITE = (236, 230, 216)
WOOD_SRC = G + '/assets/village_v2/_matlib/V2_Wood_albedo.jpg'

REGIONS = {}
x = 0
for k in ['nobori_sake', 'nobori_kome', 'nobori_meshi']:
    REGIONS[k] = (x, 0, x + 96, 384)
    x += 100
for i, k in enumerate(['kanban_sake', 'kanban_kome', 'kanban_kusuri', 'kanban_abura']):
    REGIONS[k] = (300 + i * 92, 0, 388 + i * 92, 240)
for i, k in enumerate(['andon_meshi', 'andon_yasumi', 'andon_kusuri']):
    REGIONS[k] = (668 + i * 84, 0, 748 + i * 84, 164)
for i, k in enumerate(['fuda_ichi', 'fuda_ta', 'fuda_kawa', 'fuda_yashiro']):
    REGIONS[k] = (300 + i * 60, 248, 356 + i * 60, 452)
REGIONS['ichi_big'] = (548, 248, 708, 488)
REGIONS['chochin_aka'] = (716, 248, 844, 376)
REGIONS['chochin_shiro'] = (852, 248, 980, 376)
REGIONS['straw'] = (0, 568, 128, 696)
REGIONS['paper'] = (136, 568, 264, 696)
REGIONS['wood_light'] = (272, 568, 400, 696)
REGIONS['wood_dark'] = (408, 568, 536, 696)
REGIONS['zaru'] = (544, 568, 672, 696)
REGIONS['shiba'] = (680, 568, 808, 696)
REGIONS['ine'] = (816, 568, 944, 696)
REGIONS['komo'] = (716, 384, 844, 512)
REGIONS['onobori_ichi'] = (0, 744, 64, 1016)
SW0 = (0, 704)          # 色票格子の原點、16 px 角、1 行 32 個
SWATCHES = {
    # 農産物・食べ物
    'daikon': '#EEEBE0', 'daikon_leaf': '#5E8A3A', 'ninjin': '#D8742A', 'nasu': '#3E2A4A', 'kabocha': '#3F5A34',
    'kyabetsu': '#A9C27A', 'kaki': '#E0782A', 'kyuri': '#3F6E2E', 'togarashi': '#B3261E', 'satoimo': '#7A5E44',
    'negi': '#D9E3C2', 'kome': '#E8E2CF', 'mame': '#A88A52', 'ringo': '#A8322A', 'mikan': '#E39A2A',
    'senbei': '#B98A4A', 'ame_y': '#E3B23A', 'ame_r': '#C8503A', 'ame_w': '#EDE6D2', 'konpeito': '#E8B4B8',
    # 器・道具
    'hakuji': '#E6E3DA', 'sometsuke': '#3B5B8C', 'ameyu': '#7A4A22', 'kokuyu': '#2A2522', 'haiyu': '#9A9A8A',
    'shuurushi': '#8E2A20', 'tetsu': '#3C3A38', 'tsuchi': '#9A6E48', 'hagane': '#6E6E6A', 'takebe': '#C8B88A',
    # 布・その他
    'mousen': '#B32D26', 'ai': '#2E4566', 'kon': '#22304A', 'kinari': '#DCD3BE', 'kakishibu': '#8A5A34',
    'take': '#B5A36A', 'take_ao': '#7E9A52', 'nawa': '#9A8256', 'komo': '#B8A27A', 'sumi': '#1E1B18',
    'wara': '#C9B07A', 'kuri': '#6A4A30', 'kanna': '#E3CFA4', 'shiba_d': '#5A4A36', 'ine_ho': '#C8A84A',
    'mino': '#8A7650', 'akachochin': '#C8392C',
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


def vtext(img, txt, fs, col, top=None, cx=None, stroke=2, blur=0.6):
    w, h = img.size
    n = len(txt)
    if top is None:
        top = h / 2 - (n - 1) * fs * 0.52
    ink_text(img, (w // 2 if cx is None else cx, int(top)), txt, fs, col, vertical=True, stroke=stroke, blur=blur)


def arrow(d, cx, y, w, col, down=True):
    """指し矢（下向き＝「此方」）：三角＋軸。"""
    d.rectangle((cx - w * 0.12, y - w * 0.9, cx + w * 0.12, y), fill=col)
    d.polygon([(cx - w * 0.5, y), (cx + w * 0.5, y), (cx, y + w * 0.7)], fill=col)


def build():
    atlas = Image.new('RGB', (SIZE, SIZE), (150, 132, 104))
    rng = np.random.default_rng(2020)
    # ── 幟：地色の布＋縦書き＋上の縁取り＋竿側の乳
    nob = {'nobori_sake': ('#22304A', '酒', WHITE), 'nobori_kome': ('#E4DCC8', '米', INK),
           'nobori_meshi': ('#8A5A34', '御食事', WHITE)}
    for i, (k, (base, txt, col)) in enumerate(nob.items()):
        w, h = sz(k)
        cl = T._cloth(w, h, base, 2100 + i)
        d = ImageDraw.Draw(cl)
        d.rectangle((0, 0, w - 1, 14), fill=tuple(int(c * 0.75) for c in T.hexrgb(base) * 255))
        for j in range(5):
            d.rectangle((w - 14, 24 + j * 72, w - 1, 36 + j * 72), fill=(200, 192, 176) if base != '#E4DCC8' else (120, 108, 92))
        n = len(txt)
        fs = 84 if n == 1 else (64 if n == 2 else 52)
        top = (h - 14) / 2 - (n - 1) * fs * 0.52 + 8
        ink_text(cl, (w // 2 - 4, int(top)), txt, fs, col, vertical=True, stroke=2 if n <= 2 else 1, blur=0.6)
        atlas.paste(cl, REGIONS[k][:2])
    # ── 大幟「市」（0.8 × 4.2 m、遠目用）：生成り地に朱の大字、上に紺の帯と白の丸
    w, h = sz('onobori_ichi')
    cl = T._cloth(w, h, '#ECE4D0', 2150)
    d = ImageDraw.Draw(cl)
    d.rectangle((0, 0, w - 1, 34), fill=(34, 48, 74))
    d.ellipse((w // 2 - 11, 6, w // 2 + 11, 28), outline=(236, 228, 210), width=4)
    d.rectangle((0, h - 10, w - 1, h - 1), fill=(150, 30, 24))
    ink_text(cl, (w // 2, 70), '市', 56, (168, 34, 26), vertical=True, stroke=3, blur=0.5)
    ink_text(cl, (w // 2, 150), '此', 34, (40, 32, 26), vertical=True, stroke=1, blur=0.4)
    ink_text(cl, (w // 2, 190), '方', 34, (40, 32, 26), vertical=True, stroke=1, blur=0.4)
    atlas.paste(cl, REGIONS['onobori_ichi'][:2])
    # ── 衝立看板：木地＋墨（酒は朱）＋枠＋上の黒い笠
    kb = {'kanban_sake': ('#B49470', '酒', SHU), 'kanban_kome': ('#C2A47A', '御米', INK),
          'kanban_kusuri': ('#B79A72', 'くすり', INK), 'kanban_abura': ('#A88A62', '油', INK)}
    for i, (k, (tone, txt, col)) in enumerate(kb.items()):
        w, h = sz(k)
        bd = wood(w, h, tone, 2200 + i, vertical=True)
        d = ImageDraw.Draw(bd)
        d.rectangle((0, 0, w - 1, h - 1), outline=(70, 52, 36), width=6)
        n = len(txt)
        fs = 66 if n == 1 else (52 if n == 2 else 44)
        vtext(bd, txt, fs, col, stroke=2)
        atlas.paste(bd, REGIONS[k][:2])
    # ── 置行灯：和紙＋墨の字、四隅の木枠は幾何で作る
    ad = {'andon_meshi': 'めし', 'andon_yasumi': '御休処', 'andon_kusuri': '薬'}
    for i, (k, txt) in enumerate(ad.items()):
        w, h = sz(k)
        pp = T._paper(w, h, 2300 + i, tone='#F1EADA')
        d = ImageDraw.Draw(pp)
        d.rectangle((0, 0, w - 1, h - 1), outline=(120, 100, 76), width=3)
        n = len(txt)
        fs = 56 if n == 1 else (40 if n == 2 else 32)
        vtext(pp, txt, fs, INK, stroke=1, blur=0.5)
        atlas.paste(pp, REGIONS[k][:2])
    # ── 道標：木地＋縦書き＋下に指し矢
    fd = {'fuda_ichi': '市此方', 'fuda_ta': '田畑', 'fuda_kawa': '水車', 'fuda_yashiro': '御社'}
    for i, (k, txt) in enumerate(fd.items()):
        w, h = sz(k)
        bd = wood(w, h, '#B89A70', 2400 + i, vertical=True)
        d = ImageDraw.Draw(bd)
        d.rectangle((0, 0, w - 1, h - 1), outline=(80, 60, 42), width=3)
        n = len(txt)
        fs = 34 if n <= 2 else 30
        vtext(bd, txt, fs, SHU if k == 'fuda_ichi' else INK, top=24, stroke=1, blur=0.4)
        arrow(d, w // 2, h - 40, 26, SHU if k == 'fuda_ichi' else INK)
        atlas.paste(bd, REGIONS[k][:2])
    # ── 市の大看板：朱の縁取り、「市」大字（朱）＋「この奥」（墨）
    w, h = sz('ichi_big')
    bd = wood(w, h, '#C9AE84', 2500, vertical=True)
    d = ImageDraw.Draw(bd)
    d.rectangle((0, 0, w - 1, h - 1), outline=SHU, width=12)
    d.rectangle((14, 14, w - 15, h - 15), outline=(80, 60, 42), width=3)
    ink_text(bd, (w // 2, 70), '市', 104, SHU, vertical=False, stroke=3, blur=0.6)
    ink_text(bd, (w // 2, 152), 'この奥', 36, INK, vertical=False, stroke=1, blur=0.5)
    arrow(d, w // 2, 196, 30, INK)
    atlas.paste(bd, REGIONS['ichi_big'][:2])
    # ── 提灯：赤（字なし・骨の陰影）／白（墨の丸紋）
    for k, tone, line in (('chochin_aka', '#C8392C', (150, 36, 28)), ('chochin_shiro', '#EFE6D0', (190, 176, 150))):
        w2, h2 = sz(k)
        ch = T._paper(w2, h2, 2600 if k == 'chochin_aka' else 2601, tone=tone)
        d = ImageDraw.Draw(ch)
        for j in range(0, h2, 9):
            d.line((0, j, w2, j), fill=line, width=2)
        d.rectangle((0, 0, w2, 12), fill=(30, 26, 24))
        d.rectangle((0, h2 - 12, w2, h2), fill=(30, 26, 24))
        if k == 'chochin_shiro':
            d.ellipse((w2 // 2 - 26, h2 // 2 - 26, w2 // 2 + 26, h2 // 2 + 26), outline=INK, width=6)
            d.line((w2 // 2 - 14, h2 // 2, w2 // 2 + 14, h2 // 2), fill=INK, width=6)
        else:
            ink_text(ch, (w2 // 2, h2 // 2), '御', 60, (24, 20, 18), vertical=False, blur=0.5)
        atlas.paste(ch, REGIONS[k][:2])
    # ── 稲藁・和紙・木地・竹笊・柴・稲束・菰
    w, h = sz('straw')
    fib = rng.normal(0, 1, (h, 1)).astype(np.float32)
    sv = np.clip(T.hexrgb('#C9B07A')[None, None, :] * (0.86 + 0.09 * fib[..., None] + 0.05 * np.sin(np.arange(w) * 0.9)[None, :, None]), 0, 1)
    atlas.paste(Image.fromarray((sv * 255).astype(np.uint8)), REGIONS['straw'][:2])
    atlas.paste(T._paper(*sz('paper'), 2701, tone='#EFEBE2'), REGIONS['paper'][:2])
    atlas.paste(wood(*sz('wood_light'), '#A9875E', 2702), REGIONS['wood_light'][:2])
    atlas.paste(wood(*sz('wood_dark'), '#6E5638', 2703), REGIONS['wood_dark'][:2])
    w, h = sz('zaru')
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    weave = 0.5 + 0.5 * np.sign(np.sin(xx * 0.55) * np.sin(yy * 0.55))
    zc = np.clip(T.hexrgb('#B5A36A')[None, None, :] * (0.78 + 0.22 * weave[..., None]), 0, 1)
    atlas.paste(Image.fromarray((zc * 255).astype(np.uint8)), REGIONS['zaru'][:2])
    # 柴：暗い小枝の束（斜めの線を重ねる）
    w, h = sz('shiba')
    sb = Image.new('RGB', (w, h), (74, 60, 44))
    d = ImageDraw.Draw(sb)
    r2 = np.random.default_rng(2704)
    for _ in range(260):
        x0 = int(r2.integers(0, w))
        y0 = int(r2.integers(-10, h))
        L = int(r2.integers(20, 60))
        c = int(r2.integers(60, 130))
        d.line((x0, y0, x0 + int(r2.integers(-6, 7)), y0 + L), fill=(c, int(c * 0.82), int(c * 0.6)), width=int(r2.integers(1, 3)))
    atlas.paste(sb.filter(ImageFilter.GaussianBlur(0.4)), REGIONS['shiba'][:2])
    # 稲束：上 30 % が穂（黄金）、下が藁（縦の繊維）
    w, h = sz('ine')
    fib2 = rng.normal(0, 1, (1, w)).astype(np.float32)
    v = np.linspace(0, 1, h)[:, None]
    base = np.where(v < 0.3, 1.0, 0.0)
    ho = T.hexrgb('#C8A84A')[None, None, :] * (0.8 + 0.12 * fib2[..., None] + 0.1 * np.sin(np.arange(h) * 1.7)[:, None, None])
    wa = T.hexrgb('#B89A62')[None, None, :] * (0.86 + 0.1 * fib2[..., None])
    iv = np.clip(base[..., None] * ho + (1 - base[..., None]) * wa, 0, 1)
    atlas.paste(Image.fromarray((iv * 255).astype(np.uint8)), REGIONS['ine'][:2])
    # 菰（酒樽の菰巻き）：生成りの藁地＋朱・墨の銘
    w, h = sz('komo')
    km = Image.fromarray((np.clip(T.hexrgb('#CDBB8E')[None, None, :] * (0.88 + 0.08 * rng.normal(0, 1, (h, 1, 1))), 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(km)
    d.rectangle((w // 2 - 30, 18, w // 2 + 30, h - 18), fill=(236, 228, 210))
    ink_text(km, (w // 2, h // 2 - 22), '銘酒', 30, SHU, vertical=True, stroke=1, blur=0.4)
    atlas.paste(km, REGIONS['komo'][:2])
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
        json.dump({'_note': f'{AID} atlas（UV 左上原點；Blender 端 v 要 1−v）。由 tools/build_village_v2_street_atlas.py 產生。'
                   ' 文字：幟「酒 米 御食事」、衝立看板「酒 御米 くすり 油」、置行灯「めし 御休処 薬」、道標「市此方 田畑 水車 御社」、大看板「市 この奥」。',
                   'size': SIZE, 'regions': uv, 'swatches': sw_uv, 'font': 'kaiu.ttf（標楷體，Windows 內建）'}, f, ensure_ascii=False, indent=1)
        f.write('\n')
    T.write_import(f'res://assets/village_v2/{AID}/{AID}_atlas.png', False)
    T.write_tres(f'{out}/{NAME}.tres', NAME, {'albedo': f'res://assets/village_v2/{AID}/{AID}_atlas.png'},
                 ['roughness = 0.9'], k=0.8)
    print('atlas →', f'{out}/{AID}_atlas.png', len(SWATCHES), 'swatches')


if __name__ == '__main__':
    build()
