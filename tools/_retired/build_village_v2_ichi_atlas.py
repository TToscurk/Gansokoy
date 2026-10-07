#!/usr/bin/env python3
"""人間之里 V2 P10 R1b：市集西通り Kit atlas（ichi_kit）——docs/reference/市集資產 の参考図に合わせた布・器・作物の柄。

  python tools/build_village_v2_ichi_atlas.py      （Python310：PIL／numpy）

全新 atlas（market_kit／street_kit／Hero／P9 の atlas は只讀・不改）。tools/build_village_v2_textures.py の 布／紙 工具を import、
木地は _matlib/V2_Wood_albedo.jpg をローカルで切り出す。輸出 godot/assets/village_v2/ichi_kit/{ichi_kit_atlas.png, atlas.json, IC_Ichi.tres}。
參考（docs/reference/市集資產）：01 布旗と招牌（藍・弁柄・生成りの五弁花紋の暖簾、縞・赤・生成りの日除け、旗）／02 陶磁の碗皿（染付・飴釉・灰釉）／
  03 甕・酒瓶（藁巻き甕・流し釉・縄掛けの緑の瓶）／04 木の屋台と家具／05 布・提灯・雑貨（反物の積み・巾着・風呂敷包み・唐辛子・大蒜・菅笠）／
  06 野菜と籠・箱／市集攤（瓦・茅葺き・板屋根の小屋形の店）／旗桿（藍・弁柄の花紋の長旗＋波）。
區域（UV 左上原點）：
  noren_ai／noren_kinari／noren_aka   小屋の暖簾 3–4 枚割り（花紋・草花）
  hata_ai／hata_aka                    長旗 0.6 × 2.4（花紋＋波）
  nuno_*                               反物・卓布・巾着の柄（縞・花・格子・波・絣）
  sometsuke／ameyu_drip／haiyu         器の胴の帯（染付の草花・流し釉・灰釉）
  kaya（茅）・ita（板屋根）・straw・zaru・paper・wood_light・wood_dark・chochin_hana
  sw                                   色票 16 × 16 px の格子
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402

G = T.G
AID = 'ichi_kit'
NAME = 'IC_Ichi'
SIZE = 1024
INK = (26, 22, 20)
CREAM = (232, 222, 198)
AI = '#2C4260'
BENI = '#9A3A2C'
KINARI = '#E2D7BE'
WOOD_SRC = G + '/assets/village_v2/_matlib/V2_Wood_albedo.jpg'

REGIONS = {
    'noren_ai': (0, 0, 300, 120), 'noren_kinari': (0, 124, 300, 244), 'noren_aka': (0, 248, 300, 368),
    'hata_ai': (304, 0, 368, 256), 'hata_aka': (372, 0, 436, 256),
    'nuno_shima': (440, 0, 568, 128), 'nuno_hana_aka': (572, 0, 700, 128), 'nuno_hana_ai': (704, 0, 832, 128),
    'nuno_hana_kinari': (836, 0, 964, 128), 'nuno_koshi': (440, 132, 568, 260), 'nuno_nami': (572, 132, 700, 260),
    'nuno_kasuri': (704, 132, 832, 260), 'nuno_ai': (836, 132, 964, 260),
    'sometsuke': (304, 264, 560, 328), 'ameyu_drip': (564, 264, 820, 328), 'haiyu': (304, 332, 560, 396),
    'kaya': (0, 400, 256, 528), 'ita': (260, 400, 516, 528), 'straw': (520, 400, 648, 528), 'zaru': (652, 400, 780, 528),
    'paper': (784, 400, 912, 528), 'wood_light': (0, 532, 128, 660), 'wood_dark': (132, 532, 260, 660),
    'chochin_hana': (264, 532, 392, 660), 'kanban_kame': (396, 532, 460, 660), 'kanban_hana': (464, 532, 528, 660),
    'komo': (532, 532, 660, 660),
}
SW0 = (0, 704)
SWATCHES = {
    'daikon': '#EEEBE0', 'daikon_leaf': '#5E8A3A', 'ninjin': '#D8742A', 'nasu': '#3E2A4A', 'kabocha': '#3F5A34',
    'kyabetsu': '#A9C27A', 'kyabetsu_d': '#5E7E44', 'hakusai': '#E4E6C8', 'tomato': '#B8392A', 'jagaimo': '#B39A6A',
    'tamanegi': '#B97E3E', 'kaki': '#E0782A', 'yuzu': '#E3B83A', 'ringo': '#A8322A', 'satoimo': '#7A5E44',
    'negi': '#D9E3C2', 'negi_ao': '#5F8A5A', 'piman': '#3F7A32', 'kabu': '#EDEBDD', 'togarashi': '#A8281E',
    'ninniku': '#E6DCC6', 'hyoutan': '#C89A52', 'kome': '#E8E2CF',
    'hakuji': '#E6E3DA', 'sometsuke_b': '#3B5B8C', 'ameyu': '#7A4A22', 'kokuyu': '#2A2522', 'haiyu_c': '#9A9A8A',
    'midori_bin': '#4E5E2E', 'shuurushi': '#8E2A20', 'tetsu': '#3C3A38', 'tsuchi': '#9A6E48', 'seiji': '#8FA88A',
    'ai': AI, 'beni': BENI, 'kinari': KINARI, 'kon': '#22304A', 'take': '#B5A36A', 'nawa': '#9A8256', 'wara': '#C9B07A',
    'sumi': '#1E1B18', 'kuri': '#6A4A30', 'akachochin': '#B8402E', 'yamabuki': '#D9A62E', 'wakakusa': '#8FA35A',
    'shu': '#A8321E', 'ishi': '#8A857A',
}


def sz(k):
    x0, y0, x1, y1 = REGIONS[k]
    return x1 - x0, y1 - y0


def wood(w, h, tone, seed, vertical=False):
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


def rgb(hx):
    return tuple(int(round(c * 255)) for c in T.hexrgb(hx))


def flower(d, cx, cy, r, col, ring=False, center=None):
    """五弁花紋（参考図 01・旗桿の紋）。"""
    for i in range(5):
        a = -math.pi / 2 + i * 2 * math.pi / 5
        px, py = cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.55
        d.ellipse((px - r * 0.45, py - r * 0.45, px + r * 0.45, py + r * 0.45), fill=col)
    d.ellipse((cx - r * 0.22, cy - r * 0.22, cx + r * 0.22, cy + r * 0.22), fill=center or col)
    if ring:
        d.ellipse((cx - r * 1.25, cy - r * 1.25, cx + r * 1.25, cy + r * 1.25), outline=col, width=max(2, int(r * 0.14)))


def spray(d, x0, y0, x1, y1, col, rng, n=7):
    """草花の枝（暖簾の外側・反物の柄）。"""
    d.line((x0, y1, x1, y0), fill=col, width=3)
    for i in range(n):
        t = (i + 1) / (n + 1)
        px, py = x0 + (x1 - x0) * t, y1 + (y0 - y1) * t
        s = float(rng.uniform(4, 8))
        d.ellipse((px - s, py - s, px + s, py + s), fill=col)
        lx = px + float(rng.uniform(-14, 14))
        d.line((px, py, lx, py - float(rng.uniform(6, 14))), fill=col, width=2)


def waves(d, x0, y0, x1, y1, col, r=10):
    """青海波（旗・布の裾）。"""
    yy = y1
    row = 0
    while yy > y0:
        xx = x0 - (r if row % 2 else 0)
        while xx < x1 + r:
            for k in (1.0, 0.68, 0.36):
                d.arc((xx - r * k, yy - r * k, xx + r * k, yy + r * k), 180, 360, fill=col, width=2)
            xx += 2 * r
        yy -= r * 0.75
        row += 1


def noren(k, base, motif, panels, seed):
    w, h = sz(k)
    rng = np.random.default_rng(seed)
    cl = T._cloth(w, h, base, seed)
    d = ImageDraw.Draw(cl)
    dark = tuple(int(c * 0.5) for c in rgb(base))
    d.rectangle((0, 0, w - 1, 8), fill=tuple(int(c * 0.7) for c in rgb(base)))
    for j in range(1, panels):
        xx = j * w // panels
        d.line((xx, 10, xx, h), fill=dark, width=3)
    for j in range(panels):
        cx = w // (2 * panels) + j * w // panels
        if motif == 'crest' and (j == panels // 2 or panels == 4):
            flower(d, cx, h // 2 + 6, 18, CREAM, ring=(panels == 3), center=rgb(base))
        elif motif == 'crest':
            spray(d, cx - 30, 30, cx + 28, h - 14, CREAM, rng, 6)
        else:
            spray(d, cx - 30, 26, cx + 30, h - 12, rgb(BENI) if j == 0 else rgb('#6E7A44'), rng, 6)
            if j > 0:
                flower(d, cx + 8, 44, 10, rgb(BENI) if j == 2 else rgb('#6E7A44'))
    return cl.filter(ImageFilter.GaussianBlur(0.5))


def hata(k, base, seed, ring):
    w, h = sz(k)
    rng = np.random.default_rng(seed)
    cl = T._cloth(w, h, base, seed)
    d = ImageDraw.Draw(cl)
    d.rectangle((0, 0, w - 1, 10), fill=tuple(int(c * 0.7) for c in rgb(base)))
    flower(d, w // 2, 40, 9, CREAM)
    flower(d, w // 2, 104, 17, CREAM, ring=ring, center=rgb(base))
    for _ in range(9):
        px, py = float(rng.uniform(6, w - 6)), float(rng.uniform(140, 190))
        d.ellipse((px - 3, py - 3, px + 3, py + 3), fill=CREAM)
    if not ring:
        spray(d, 8, 150, w - 8, 210, CREAM, rng, 5)
    waves(d, 0, 200, w, h - 4, CREAM, r=8)
    return cl.filter(ImageFilter.GaussianBlur(0.4))


def build():
    atlas = Image.new('RGB', (SIZE, SIZE), (150, 132, 104))
    rng = np.random.default_rng(3030)
    atlas.paste(noren('noren_ai', AI, 'crest', 3, 3100), REGIONS['noren_ai'][:2])
    atlas.paste(noren('noren_kinari', KINARI, 'bot', 3, 3101), REGIONS['noren_kinari'][:2])
    atlas.paste(noren('noren_aka', BENI, 'crest', 4, 3102), REGIONS['noren_aka'][:2])
    atlas.paste(hata('hata_ai', AI, 3110, True), REGIONS['hata_ai'][:2])
    atlas.paste(hata('hata_aka', BENI, 3111, False), REGIONS['hata_aka'][:2])
    # ── 反物・卓布の柄
    pats = {'nuno_shima': (KINARI, 'shima'), 'nuno_hana_aka': (BENI, 'hana'), 'nuno_hana_ai': (AI, 'hana'),
            'nuno_hana_kinari': (KINARI, 'hana_r'), 'nuno_koshi': (AI, 'koshi'), 'nuno_nami': ('#33507A', 'nami'),
            'nuno_kasuri': ('#22304A', 'kasuri'), 'nuno_ai': (AI, None)}
    for i, (k, (base, kind)) in enumerate(pats.items()):
        w, h = sz(k)
        cl = T._cloth(w, h, base, 3200 + i)
        d = ImageDraw.Draw(cl)
        r2 = np.random.default_rng(3300 + i)
        if kind == 'shima':
            for j in range(0, w, 24):
                d.rectangle((j, 0, j + 11, h), fill=rgb('#3E5A80'))
        elif kind in ('hana', 'hana_r'):
            col = CREAM if kind == 'hana' else rgb(BENI)
            for _ in range(7):
                flower(d, float(r2.uniform(10, w - 10)), float(r2.uniform(10, h - 10)), float(r2.uniform(7, 12)), col)
        elif kind == 'koshi':
            for j in range(0, w, 16):
                d.line((j, 0, j, h), fill=(200, 196, 182), width=2)
                d.line((0, j, w, j), fill=(200, 196, 182), width=2)
        elif kind == 'nami':
            waves(d, 0, 0, w, h, CREAM, r=10)
        elif kind == 'kasuri':
            for j in range(4, h, 16):
                for q in range(6 + (j // 16 % 2) * 8, w, 16):
                    d.line((q - 3, j, q + 3, j), fill=(205, 200, 186), width=3)
                    d.line((q, j - 3, q, j + 3), fill=(205, 200, 186), width=3)
        atlas.paste(cl.filter(ImageFilter.GaussianBlur(0.4)), REGIONS[k][:2])
    # ── 器の胴の帯：染付（白地に藍の草花＋上下の線）、流し釉（飴の地に白い垂れ）、灰釉（斑）
    w, h = sz('sometsuke')
    so = Image.new('RGB', (w, h), rgb('#E8E4D8'))
    d = ImageDraw.Draw(so)
    d.rectangle((0, 2, w, 6), fill=rgb('#3B5B8C'))
    d.rectangle((0, h - 7, w, h - 3), fill=rgb('#3B5B8C'))
    r3 = np.random.default_rng(3400)
    for j in range(8):
        cx = 16 + j * 32
        flower(d, cx, h // 2, 8, rgb('#3B5B8C'))
        spray(d, cx + 4, 12, cx + 20, h - 10, rgb('#4E6E9E'), r3, 3)
    atlas.paste(so.filter(ImageFilter.GaussianBlur(0.5)), REGIONS['sometsuke'][:2])
    w, h = sz('ameyu_drip')
    am = Image.new('RGB', (w, h), rgb('#6A3E1E'))
    d = ImageDraw.Draw(am)
    d.rectangle((0, 0, w, 14), fill=rgb('#D8CDB4'))
    for j in range(0, w, 9):
        L = int(r3.integers(10, 44))
        d.rectangle((j, 10, j + 5, 10 + L), fill=rgb('#CFC2A6'))
        d.ellipse((j - 1, 8 + L, j + 6, 15 + L), fill=rgb('#CFC2A6'))
    atlas.paste(am.filter(ImageFilter.GaussianBlur(0.8)), REGIONS['ameyu_drip'][:2])
    w, h = sz('haiyu')
    hv = np.clip(T.hexrgb('#9A9A88')[None, None, :] * (0.85 + 0.12 * r3.random((h, w, 1))), 0, 1)
    atlas.paste(Image.fromarray((hv * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), REGIONS['haiyu'][:2])
    # ── 茅（金茶の縦の繊維＋段）・板屋根（縦の板＋押縁）・藁・笊・和紙・木地
    w, h = sz('kaya')
    fib = r3.normal(0, 1, (1, w)).astype(np.float32)
    v = np.arange(h)[:, None]
    band = 0.88 + 0.1 * np.sin(v * 0.35)[..., None]
    kv = np.clip(T.hexrgb('#B39056')[None, None, :] * (band + 0.1 * fib[..., None]), 0, 1)
    atlas.paste(Image.fromarray((kv * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.4)), REGIONS['kaya'][:2])
    w, h = sz('ita')
    it = wood(w, h, '#7A6248', 3500, vertical=True)
    d = ImageDraw.Draw(it)
    for j in range(0, w, 28):
        d.line((j, 0, j, h), fill=(52, 40, 30), width=2)
    for j in range(20, h, 40):
        d.rectangle((0, j, w, j + 5), fill=(70, 54, 40))
    atlas.paste(it, REGIONS['ita'][:2])
    w, h = sz('straw')
    fib2 = r3.normal(0, 1, (h, 1)).astype(np.float32)
    sv = np.clip(T.hexrgb('#C9B07A')[None, None, :] * (0.86 + 0.09 * fib2[..., None] + 0.05 * np.sin(np.arange(w) * 0.9)[None, :, None]), 0, 1)
    atlas.paste(Image.fromarray((sv * 255).astype(np.uint8)), REGIONS['straw'][:2])
    w, h = sz('zaru')
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    weave = 0.5 + 0.5 * np.sign(np.sin(xx * 0.55) * np.sin(yy * 0.55))
    zc = np.clip(T.hexrgb('#B5A36A')[None, None, :] * (0.78 + 0.22 * weave[..., None]), 0, 1)
    atlas.paste(Image.fromarray((zc * 255).astype(np.uint8)), REGIONS['zaru'][:2])
    atlas.paste(T._paper(*sz('paper'), 3501, tone='#EFEBE2'), REGIONS['paper'][:2])
    atlas.paste(wood(*sz('wood_light'), '#A9875E', 3502), REGIONS['wood_light'][:2])
    atlas.paste(wood(*sz('wood_dark'), '#6E5638', 3503), REGIONS['wood_dark'][:2])
    # 提灯（弁柄の紙に生成りの花紋）
    w, h = sz('chochin_hana')
    ch = T._paper(w, h, 3504, tone='#B8402E')
    d = ImageDraw.Draw(ch)
    for j in range(0, h, 9):
        d.line((0, j, w, j), fill=(140, 44, 32), width=2)
    d.rectangle((0, 0, w, 12), fill=(30, 26, 24))
    d.rectangle((0, h - 12, w, h), fill=(30, 26, 24))
    d.ellipse((w // 2 - 30, h // 2 - 30, w // 2 + 30, h // 2 + 30), fill=CREAM)
    flower(d, w // 2, h // 2, 18, rgb('#8A2A20'))
    atlas.paste(ch, REGIONS['chochin_hana'][:2])
    # 吊り看板（字の代わりに絵：甕・花——参考図 01 の絵看板）
    for k, kind in (('kanban_kame', 'kame'), ('kanban_hana', 'hana')):
        w, h = sz(k)
        bd = wood(w, h, '#8E7558', 3505, vertical=True)
        d = ImageDraw.Draw(bd)
        d.rectangle((5, 8, w - 6, h - 8), fill=(214, 202, 176))
        if kind == 'kame':
            d.ellipse((14, 44, w - 14, h - 22), fill=(52, 36, 26))
            d.rectangle((24, 30, w - 24, 48), fill=(52, 36, 26))
            for j in range(3):
                d.line((20, 64 + j * 14, w - 20, 64 + j * 14), fill=(214, 202, 176), width=2)
        else:
            flower(d, w // 2, h // 2, 18, (40, 46, 70))
        atlas.paste(bd, REGIONS[k][:2])
    # 菰（酒樽・甕を包む藁）
    w, h = sz('komo')
    km = np.clip(T.hexrgb('#C4AE80')[None, None, :] * (0.86 + 0.1 * r3.normal(0, 1, (h, 1, 1)) + 0.05 * np.sin(np.arange(w) * 1.3)[None, :, None]), 0, 1)
    atlas.paste(Image.fromarray((km * 255).astype(np.uint8)), REGIONS['komo'][:2])
    # ── 色票
    sw_uv = {}
    for i, (k, hx) in enumerate(SWATCHES.items()):
        cx = SW0[0] + (i % 32) * 16
        cy = SW0[1] + (i // 32) * 16
        ImageDraw.Draw(atlas).rectangle((cx, cy, cx + 15, cy + 15), fill=rgb(hx))
        sw_uv[k] = [(cx + 8) / SIZE, (cy + 8) / SIZE]
    out = f'{G}/assets/village_v2/{AID}'
    os.makedirs(out, exist_ok=True)
    atlas.save(f'{out}/{AID}_atlas.png', optimize=True)
    uv = {k: [x0 / SIZE, y0 / SIZE, x1 / SIZE, y1 / SIZE] for k, (x0, y0, x1, y1) in REGIONS.items()}
    with open(f'{out}/atlas.json', 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'_note': f'{AID} atlas（UV 左上原點；Blender 端 v 要 1−v）。由 tools/build_village_v2_ichi_atlas.py 產生；參考 docs/reference/市集資產。',
                   'size': SIZE, 'regions': uv, 'swatches': sw_uv}, f, ensure_ascii=False, indent=1)
        f.write('\n')
    T.write_import(f'res://assets/village_v2/{AID}/{AID}_atlas.png', False)
    T.write_tres(f'{out}/{NAME}.tres', NAME, {'albedo': f'res://assets/village_v2/{AID}/{AID}_atlas.png'}, ['roughness = 0.88'], k=0.8)
    print('atlas →', f'{out}/{AID}_atlas.png', len(SWATCHES), 'swatches')


if __name__ == '__main__':
    build()
