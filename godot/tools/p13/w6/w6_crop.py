"""P13 Wave 6：同一画像ペア（前／後）の同一矩形を切り出して左右に並べる（唯読）。
  uv run --with pillow python w6_crop.py <before.png> <after.png> x0,y0,x1,y1 <out.png> [scale=1.0]
"""
import sys

from PIL import Image, ImageDraw

b, a, box, out = sys.argv[1:5]
sc = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0
x0, y0, x1, y1 = [int(v) for v in box.split(",")]
ib = Image.open(b).convert("RGB").crop((x0, y0, x1, y1))
ia = Image.open(a).convert("RGB").crop((x0, y0, x1, y1))
if sc != 1.0:
    ib = ib.resize((int(ib.width * sc), int(ib.height * sc)), Image.LANCZOS)
    ia = ia.resize((int(ia.width * sc), int(ia.height * sc)), Image.LANCZOS)
W = ib.width + ia.width + 8
im = Image.new("RGB", (W, ib.height), (255, 0, 255))
im.paste(ib, (0, 0))
im.paste(ia, (ib.width + 8, 0))
d = ImageDraw.Draw(im)
d.rectangle((0, 0, 70, 18), fill=(0, 0, 0))
d.text((4, 3), "BEFORE", fill=(255, 255, 0))
d.rectangle((ib.width + 8, 0, ib.width + 8 + 60, 18), fill=(0, 0, 0))
d.text((ib.width + 12, 3), "AFTER", fill=(255, 255, 0))
im.save(out)
print(out, im.size)
