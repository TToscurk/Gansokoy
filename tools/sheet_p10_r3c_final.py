"""R3c FINAL ART_REVIEW sheets: same-camera R3b (activity off) vs R3c (activity on), six review categories.
Inputs: activity_r1/final_population (N_before = R3b, N_after = R3c, 5_walk_through_* = R3c walk)
        activity_r1/final_baseline_walk (5_walk_through_* = R3b walk, same player route/camera).
Usage: uv run --with pillow python tools/sheet_p10_r3c_final.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

R = Path(__file__).resolve().parents[1]
A = R / 'docs/art_review/village_v2_p10_population/activity_r1'
import sys
# optional: <population dir> <out dir> <after label> (R3c.1: activity_r1c1/population activity_r1c1/review R3c.1)
P = Path(sys.argv[1]) if len(sys.argv) > 1 else A / 'final_population'
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else A / 'final_review'
TAG = sys.argv[3] if len(sys.argv) > 3 else 'R3c'
BW = A / 'final_baseline_walk'   # R3b walk-through (activity off) — R3b is sealed, same route / camera
OUT.mkdir(exist_ok=True)
try:
    F = ImageFont.truetype('C:/Windows/Fonts/msjh.ttc', 34)
except OSError:
    F = ImageFont.load_default()


def label(im, text):
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 30 + 19 * len(text), 50), fill=(0, 0, 0))
    d.text((12, 6), text, fill='white', font=F)
    return im


views = ['1_market_tps', '2_market_west_tps', '3_main_street_tps', '4_market_high']
pairs = []
for v in views:
    b = label(Image.open(P / f'{v}_before.png').convert('RGB'), f'{v}  R3b (activity off)')
    a = label(Image.open(P / f'{v}_after.png').convert('RGB'), f'{v}  {TAG} (activity on)')
    s = Image.new('RGB', (3840, 1080))
    s.paste(b, (0, 0)); s.paste(a, (1920, 0))
    s.save(OUT / (f'{v}_R3b_vs_' + TAG.replace('.', '') + '.jpg'), quality=90)
    pairs.append(s)
# 5: walk-through, R3b row over R3c row
tw, th = 640, 360
w = Image.new('RGB', (tw * 6, th * 2 + 0), '#202020')
for i in range(6):
    w.paste(label(Image.open(BW / f'5_walk_through_{i:02d}.png').convert('RGB'), f'R3b {i}').resize((tw, th)), (i * tw, 0))
    w.paste(label(Image.open(P / f'5_walk_through_{i:02d}.png').convert('RGB'), f'{TAG} {i}').resize((tw, th)), (i * tw, th))
w.save(OUT / ('5_walk_through_R3b_vs_' + TAG.replace('.', '') + '.jpg'), quality=90)
# 6: all four same-camera pairs in one sheet
s6 = Image.new('RGB', (1920, 540 * 4))
for i, p in enumerate(pairs):
    s6.paste(p.resize((1920, 540)), (0, i * 540))
s6.save(OUT / ('6_before_after_R3b_vs_' + TAG.replace('.', '') + '.jpg'), quality=88)
print('wrote', sorted(x.name for x in OUT.iterdir()))
