"""P13 W7：BEFORE｜AFTER｜DIFF×k の 3 連画像（ラベル付き）。
  uv run --quiet --with pillow --with numpy python w7_triple.py <out.png> <before.png> <after.png> "<label_b>" "<label_a>" [--w=520] [--gain=5] [--crop=x0,y0,x1,y1]
"""
import sys

import numpy as np
from PIL import Image, ImageDraw


def lab(im, t):
    d = ImageDraw.Draw(im)
    w = d.textlength(t)
    d.rectangle([0, 0, w + 12, 20], fill=(0, 0, 0))
    d.text((6, 4), t, fill=(255, 220, 0))


out, b, a, lb, la = sys.argv[1:6]
w = 520
gain = 5.0
crop = None
for s in sys.argv[6:]:
    if s.startswith("--w="):
        w = int(s[4:])
    elif s.startswith("--gain="):
        gain = float(s[7:])
    elif s.startswith("--crop="):
        crop = [int(v) for v in s[7:].split(",")]
ib = Image.open(b).convert("RGB")
ia = Image.open(a).convert("RGB")
if crop:
    ib = ib.crop(crop)
    ia = ia.crop(crop)
d = np.abs(np.asarray(ib).astype(int) - np.asarray(ia).astype(int)).sum(axis=2)
dd = Image.fromarray(np.clip(d * gain, 0, 255).astype(np.uint8)).convert("RGB")
h = int(ib.height * w / ib.width)
ims = [im.resize((w, h), Image.LANCZOS) for im in (ib, ia, dd)]
lab(ims[0], lb)
lab(ims[1], la)
lab(ims[2], "DIFF x%g" % gain)
s = Image.new("RGB", (w * 3 + 12, h), (255, 0, 255))
for i, im in enumerate(ims):
    s.paste(im, (i * (w + 6), 0))
s.save(out)
print("saved", out, s.size)
