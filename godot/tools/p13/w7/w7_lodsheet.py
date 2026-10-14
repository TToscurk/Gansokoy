"""P13 W7 TASK 5：LOD 強制表示の 2 行×3 列（上＝BEFORE の L0／L1／L2、下＝AFTER の L0／L1／L2）。
  uv run --quiet --with pillow python w7_lodsheet.py <out.png> <before_dir> <after_dir> <prefix e.g. l_lod_mkt> [--w=520] [--crop=x0,y0,x1,y1]
"""
import sys

from PIL import Image, ImageDraw

out, bd, ad, pre = sys.argv[1:5]
w = 520
crop = None
for s in sys.argv[5:]:
    if s.startswith("--w="):
        w = int(s[4:])
    elif s.startswith("--crop="):
        crop = [int(v) for v in s[7:].split(",")]


def load(d, k):
    im = Image.open(f"{d}/{pre}_L{k}.png").convert("RGB")
    if crop:
        im = im.crop(crop)
    h = int(im.height * w / im.width)
    return im.resize((w, h), Image.LANCZOS)


rows = []
for d, name in ((bd, "BEFORE"), (ad, "AFTER")):
    ims = []
    for k in range(3):
        im = load(d, k)
        dr = ImageDraw.Draw(im)
        t = f"{name}  LOD{k} forced"
        tw = dr.textlength(t)
        dr.rectangle([0, 0, tw + 12, 20], fill=(0, 0, 0))
        dr.text((6, 4), t, fill=(255, 220, 0))
        ims.append(im)
    rows.append(ims)
h = rows[0][0].height
s = Image.new("RGB", (w * 3 + 12, h * 2 + 6), (255, 0, 255))
for r, ims in enumerate(rows):
    for c, im in enumerate(ims):
        s.paste(im, (c * (w + 6), r * (h + 6)))
s.save(out)
print("saved", out, s.size)
