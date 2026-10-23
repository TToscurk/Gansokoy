#!/usr/bin/env python3
"""鯢吞亭／霧雨魔法店（Hero）の暖簾に字を入れる（atlas の暖簾区画だけを描き直す・冪等）。

  python tools/patch_village_v2_noren_text_hero.py

2026-10-21 使用者指示「布簾上沒有字的／幾何圖案的改成有相應文字的」。
  geidontei：2 幅の紫の暖簾（山椒の紋 2 つ）→「鯢」「吞」（店名「鯢吞亭」の前 2 字。「亭」は大提灯）。
  kirisame ：6 幅の緑の暖簾（三日月・星・流れ星）→ 1〜5 幅に「霧」「雨」「魔」「法」「店」。6 幅目の星の絵はそのまま残す（魔理沙の星）。
暖簾の区画は 1024×256 px で、板は 1.98×0.86 m（geidontei）／1.8×0.78 m（kirisame）＝縦横比 約 2.3 → 絵は横に 1.74 倍つぶれて貼られる。
字は『正方形で描いて横へ 1.74 倍』にして、貼ったときに歪まないようにする。noren_back（裏地）は触らない。
布・字の道具は build_village_v2_textures.py（_cloth／_text）を再利用。
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_village_v2_textures as T  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, '..'))
AV = os.path.join(ROOT, 'godot', 'assets', 'village_v2')
INK = (226, 220, 204)
SQUASH = 1.74          # (板の縦 m / 区画の縦 px) ÷ (板の横 m / 区画の横 px)
TOP = 22               # 竿袋（上の暗い帯）の高さ px

JOBS = [
    # name, atlas, 区画 (x0,y0,x1,y1), 幅数, 字（左から）, 布の色, 字の高さ px（正方形で描く辺）
    ('geidontei', 'geidontei/geidontei_atlas.png', (0, 512, 1024, 768), 2, '鯢吞', '#493554', 150),
    ('kirisame', 'kirisame/kirisame_atlas.png', (0, 288, 1024, 544), 6, '霧雨魔法店', '#2D5045', 84),
]


def glyph_mask(ch, size, stroke):
    sq = Image.new('L', (size * 2, size * 2), 0)
    T._text(sq, (size, size), ch, size, 255, vertical=False, stroke=stroke)
    bb = sq.getbbox()
    sq = sq.crop(bb) if bb else sq
    return sq


def main():
    for name, rel, box, n, text, cloth, gh in JOBS:
        path = os.path.join(AV, rel)
        atlas = Image.open(path).convert('RGB')
        x0, y0, x1, y1 = box
        cell = atlas.crop(box)
        w, h = cell.size
        pw = w / n
        d = ImageDraw.Draw(cell)
        mask = Image.new('L', (w, h), 0)
        seed = 9100 + sum(ord(c) for c in name)
        # 字を入れる幅ぜんぶを 1 枚の布で塗り直し（旧い紋・切れ目の縁の残りを消す）、切れ目を引き直す。字の無い残りの幅（kirisame の 6 幅目）は触らない
        rx1 = w if len(text) == n else int(len(text) * pw) - 2
        cell.paste(T._cloth(rx1, h - TOP, cloth, seed), (0, TOP))
        for i, ch in enumerate(text):
            if i > 0:
                bx = int(i * pw)
                d.rectangle((bx - 3, TOP, bx + 3, h), fill=(20, 18, 16))                 # 幅の切れ目
        if len(text) < n:
            bx = int(len(text) * pw)
            d.rectangle((bx - 3, TOP, bx + 3, h), fill=(20, 18, 16))                     # 残す幅との境
        for i, ch in enumerate(text):
            # 字：正方形の字を横 SQUASH 倍にして中心へ
            g = glyph_mask(ch, gh, max(1, int(gh * 0.03)))
            g = g.resize((int(g.width * SQUASH), g.height), Image.BICUBIC)
            cx, cy = int(i * pw + pw / 2), TOP + int((h - TOP) * 0.52)
            mask.paste(g, (cx - g.width // 2, cy - g.height // 2), g)
        mask = mask.filter(ImageFilter.GaussianBlur(0.5))
        rng = np.random.default_rng(seed)
        wear = np.asarray(Image.fromarray(rng.normal(128, 40, (h // 16, w // 16)).clip(0, 255).astype(np.uint8))
                          .resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0
        m = np.asarray(mask, dtype=np.float32) / 255.0 * np.clip(0.88 + 0.2 * wear, 0.0, 1.0)
        m = np.clip(m, 0, 1)[..., None]
        base = np.asarray(cell, dtype=np.float32)
        out = base * (1 - m) + np.array(INK, dtype=np.float32)[None, None, :] * m
        cell = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
        atlas.paste(cell, (x0, y0))
        atlas.save(path)
        print(name, '→', text, path)


if __name__ == '__main__':
    main()
