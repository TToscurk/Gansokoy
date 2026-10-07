#!/usr/bin/env python3
"""人間之里 V2 P9 R4-3：寺子屋周邊小物 atlas（school_kit）。

  python tools/build_village_v2_school_atlas.py      （Python310：PIL／numpy）

全新 atlas，不改寺子屋 Hero atlas（P5 R3 ART_APPROVED）。沿用 tools/build_village_v2_textures.py 的
木紋／紙／字工具（只 import，不改）。輸出 godot/assets/village_v2/school_kit/{school_kit_atlas.png, atlas.json, SK_School.tres}。
區域（UV 左上原點）：
  hanshi0..4  學童の清書（半紙 0.24×0.33 m、毛筆一字＋名）—— 屋簷下晾乾的習字
  fuda        手習所の木札（0.30×0.48 m、直書「手習所」「辰の刻より」）
  toban       掃除当番板（0.62×0.40 m、横書き見出し＋名札 4）
  temari      手毬の柄（u＝周、v＝上下）
  straw       草履の稲藁
  paper       白紙
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402

G = T.G
AID = 'school_kit'
NAME = 'SK_School'
SIZE = 1024
INK = (24, 20, 18)

REGIONS = {
    'hanshi0': (0, 0, 160, 220), 'hanshi1': (160, 0, 320, 220), 'hanshi2': (320, 0, 480, 220),
    'hanshi3': (480, 0, 640, 220), 'hanshi4': (640, 0, 800, 220),
    'fuda': (812, 0, 1012, 320),
    'toban': (0, 240, 372, 488),
    'temari': (392, 240, 648, 368),
    'straw': (668, 240, 796, 368),
    'paper': (392, 384, 520, 512),
    'wood_light': (540, 384, 668, 512),
}
HANSHI = [('山', 'たろう'), ('川', 'はな'), ('花', 'きち'), ('月', 'おみつ'), ('木', 'しん')]


def sz(k):
    x0, y0, x1, y1 = REGIONS[k]
    return x1 - x0, y1 - y0


def brush_char(w, h, ch, size, seed, rot=0.0):
    """毛筆一字：標楷体を少し太らせ・傾け・にじませる（子供の字）。回傳 L 遮罩。"""
    gl = Image.new('L', (w, h), 0)
    T._text(gl, (w // 2, h // 2), ch, size, 255, stroke=max(2, size // 18))
    gl = gl.rotate(rot, resample=Image.BICUBIC, center=(w // 2, h // 2))
    gl = gl.filter(ImageFilter.GaussianBlur(1.2))
    a = np.asarray(gl, np.float32) / 255.0
    rng = np.random.default_rng(seed)
    a = np.clip(a * (0.85 + 0.25 * rng.random(a.shape)) * 1.15, 0, 1)
    return Image.fromarray((a * 255).astype(np.uint8))


def build():
    atlas = Image.new('RGB', (SIZE, SIZE), (200, 188, 160))
    rng = np.random.default_rng(431)
    # 半紙：白紙＋墨一字（傾き・大きさ不揃い）＋左下に小さく名
    for i, (ch, nm) in enumerate(HANSHI):
        k = 'hanshi%d' % i
        w, h = sz(k)
        pg = T._paper(w, h, 440 + i, tone='#EEE9DD')
        big = brush_char(w, h, ch, int(104 + rng.integers(-10, 10)), 450 + i, rot=float(rng.uniform(-7, 7)))
        pg.paste(Image.new('RGB', (w, h), INK), (int(rng.integers(-14, -4)), int(rng.integers(-26, -14))), big)
        small = Image.new('L', (w, h), 0)
        T._text(small, (w - 18, h - 58), nm, 16, 255, vertical=True)
        pg.paste(Image.new('RGB', (w, h), (40, 34, 30)), (0, 0), small)
        ImageDraw.Draw(pg).rectangle((0, 0, w - 1, h - 1), outline=(200, 194, 180), width=3)
        atlas.paste(pg, REGIONS[k][:2])
    # 手習所の木札：明るい木地＋直書
    w, h = sz('fuda')
    fd = T._wood_patch(h, w, '#B79A72', 461).rotate(90, expand=True).resize((w, h))
    d = ImageDraw.Draw(fd)
    d.rectangle((0, 0, w - 1, h - 1), outline=(92, 70, 48), width=6)
    ml = Image.new('L', (w, h), 0)
    T._text(ml, (w // 2 + 26, 62), '手習所', 66, 255, vertical=True)
    T._text(ml, (w // 2 - 46, 96), '辰の刻より', 30, 255, vertical=True)
    fd.paste(Image.new('RGB', (w, h), INK), (0, 0), ml.filter(ImageFilter.GaussianBlur(0.6)))
    atlas.paste(fd, REGIONS['fuda'][:2])
    # 掃除当番：木板＋見出し＋名札 4（掛札）
    w, h = sz('toban')
    tb = T._wood_patch(w, h, '#A88A62', 462)
    d = ImageDraw.Draw(tb)
    d.rectangle((0, 0, w - 1, h - 1), outline=(80, 60, 42), width=7)
    ml = Image.new('L', (w, h), 0)
    T._text(ml, (w // 2, 44), '掃除当番', 44, 255)
    tb.paste(Image.new('RGB', (w, h), INK), (0, 0), ml)
    for j, nm in enumerate(['たろう', 'はな', 'きち', 'おみつ']):
        x = 34 + j * 84
        tag = T._wood_patch(64, 150, '#D8C49C', 470 + j)
        tm = Image.new('L', (64, 150), 0)
        T._text(tm, (32, 26), nm, 26, 255, vertical=True)
        tag.paste(Image.new('RGB', (64, 150), INK), (0, 0), tm)
        ImageDraw.Draw(tag).rectangle((0, 0, 63, 149), outline=(96, 76, 52), width=3)
        tb.paste(tag, (x, 82))
        d.ellipse((x + 27, 76, x + 37, 86), fill=(40, 34, 30))
    atlas.paste(tb, REGIONS['toban'][:2])
    # 手毬：生成り地＋赤／黄／緑／藍の菱帯（u 周、v 上下）
    w, h = sz('temari')
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xx / w
    v = yy / h
    base = np.ones((h, w, 3), np.float32) * np.array([0.93, 0.88, 0.78], np.float32)
    zig = np.abs(((u * 8.0) % 1.0) - 0.5) * 2.0
    cols = [(0.78, 0.12, 0.10), (0.92, 0.72, 0.16), (0.20, 0.50, 0.28), (0.15, 0.22, 0.50)]
    for b, c in enumerate(cols):
        c0 = 0.18 + b * 0.18
        band = np.abs(v - (c0 + 0.08 * zig)) < 0.045
        base[band] = c
    atlas.paste(Image.fromarray((base * 255).astype(np.uint8)), REGIONS['temari'][:2])
    # 稲藁（草履）
    w, h = sz('straw')
    fib = rng.normal(0, 1, (h, 1)).astype(np.float32)
    sv = np.clip(T.hexrgb('#C9B07A')[None, None, :] * (0.86 + 0.09 * fib[..., None] + 0.05 * np.sin(np.arange(w) * 0.9)[None, :, None]), 0, 1)
    atlas.paste(Image.fromarray((sv * 255).astype(np.uint8)), REGIONS['straw'][:2])
    atlas.paste(T._paper(*sz('paper'), 463, tone='#EFEBE2'), REGIONS['paper'][:2])
    atlas.paste(T._wood_patch(*sz('wood_light'), '#A9875E', 464), REGIONS['wood_light'][:2])
    out = f'{G}/assets/village_v2/{AID}'
    os.makedirs(out, exist_ok=True)
    atlas.save(f'{out}/{AID}_atlas.png', optimize=True)
    uv = {k: [x0 / SIZE, y0 / SIZE, x1 / SIZE, y1 / SIZE] for k, (x0, y0, x1, y1) in REGIONS.items()}
    with open(f'{out}/atlas.json', 'w', encoding='utf-8', newline='\n') as f:
        json.dump({'_note': f'{AID} atlas（UV 左上原點；Blender 端 v 要 1−v）。由 tools/build_village_v2_school_atlas.py 產生。'
                   ' 文字：半紙「山 川 花 月 木」＋名、木札「手習所／辰の刻より」、「掃除当番」＋名札 4。',
                   'size': SIZE, 'regions': uv, 'font': 'kaiu.ttf（標楷體，Windows 內建）'}, f, ensure_ascii=False, indent=1)
        f.write('\n')
    T.write_import(f'res://assets/village_v2/{AID}/{AID}_atlas.png', False)
    # albedo 1.0（紙・木地は atlas 自身の明度で；Hero atlas の 0.42 規約は町家壁用）
    T.write_tres(f'{out}/{NAME}.tres', NAME, {'albedo': f'res://assets/village_v2/{AID}/{AID}_atlas.png'},
                 ['roughness = 0.9'], k=0.8)
    print('atlas →', f'{out}/{AID}_atlas.png')


if __name__ == '__main__':
    build()
