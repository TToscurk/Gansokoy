"""植被光照校正：修正前／後同角度對照表（Pillow）。
  python compare_light.py <before_dir> <after_dir> <out_prefix>
輸出 <out_prefix>_A.jpg（L1–L5）、<out_prefix>_B.jpg（L5b–L7）：每列左＝修正前、右＝修正後。
另印每張圖的平均亮度與紅色系（楓）畫素的平均飽和度。
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

NAMES = [
    ('L1_sakura_haiden', '櫻花樹與神社建築'), ('L2_grove_ground', '櫻花林與地面'), ('L3_stair_sides', '石階兩側樹林'),
    ('L4_crown_trunk_close', '樹冠與樹幹近景'), ('L5_backlit_tree', '背光樹木（同一棵櫻，面向太陽）'),
    ('L5b_backlit_grove', '背光櫻林'), ('L6_court_front', '神社前庭正面'), ('L6b_court_oblique', '神社前庭整體（斜俯瞰）'),
    ('L7_frontlit_tree', '順光樹木（同一棵櫻，背對太陽）'),
]
W, H = 800, 450


def font(sz):
    for f in ['C:/Windows/Fonts/msjh.ttc', 'C:/Windows/Fonts/msjhbd.ttc', 'C:/Windows/Fonts/mingliu.ttc']:
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def s2l(a):
    a = a / 255.0
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def stats(p):
    a = np.asarray(Image.open(p).convert('RGB')).astype(float)
    Y = s2l(a) @ np.array([0.2126, 0.7152, 0.0722])
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    red = (r > 1.6 * g) & (r > 1.4 * b) & (r > 60)
    mx = a.max(axis=2)
    sat = np.where(mx > 0, (mx - a.min(axis=2)) / np.maximum(mx, 1), 0)
    return Y.mean(), (sat[red].mean() if red.sum() > 200 else float('nan')), int(red.sum())


def sheet(bdir, adir, names, out):
    f1, f2 = font(26), font(22)
    rows = len(names)
    im = Image.new('RGB', (W * 2 + 18, rows * (H + 40) + 10), (24, 24, 24))
    d = ImageDraw.Draw(im)
    for i, (n, label) in enumerate(names):
        y = i * (H + 40) + 10
        d.text((8, y), label, font=f1, fill=(235, 235, 235))
        for j, (lab, dd, col) in enumerate((('修正前', bdir, (210, 130, 130)), ('修正後', adir, (130, 210, 150)))):
            p = os.path.join(dd, n + '.png')
            x = 6 + j * (W + 6)
            if os.path.exists(p):
                im.paste(Image.open(p).convert('RGB').resize((W, H)), (x, y + 34))
            d.rectangle([x, y + 34, x + 92, y + 66], fill=(0, 0, 0))
            d.text((x + 8, y + 36), lab, font=f2, fill=col)
    im.save(out, quality=88)
    print('[SHEET]', out, im.size)


if __name__ == '__main__':
    b, a, o = sys.argv[1:4]
    sheet(b, a, NAMES[:5], o + '_A.jpg')
    sheet(b, a, NAMES[5:], o + '_B.jpg')
    print('| 視角 | 平均亮度 前 → 後 | 紅色系飽和度 前 → 後（畫素數） |')
    print('|---|---|---|')
    for n, label in NAMES:
        pb, pa = os.path.join(b, n + '.png'), os.path.join(a, n + '.png')
        if os.path.exists(pb) and os.path.exists(pa):
            yb, sb, nb = stats(pb)
            ya, sa, na = stats(pa)
            print('| %s | %.3f → %.3f（%+.0f%%） | %.2f → %.2f（%d → %d） |' % (label, yb, ya, 100 * (ya / yb - 1), sb, sa, nb, na))
