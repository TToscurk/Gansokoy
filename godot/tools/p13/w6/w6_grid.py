"""P13 Wave 6：画像に座標グリッドを描く（目視で座標を拾うため）。
  uv run --with pillow python w6_grid.py <src.png> <dst.png> [step=200] [x0,y0,x1,y1 crop]
"""
import sys

from PIL import Image, ImageDraw

src, dst = sys.argv[1], sys.argv[2]
step = int(sys.argv[3]) if len(sys.argv) > 3 else 200
im = Image.open(src).convert("RGB")
off = (0, 0)
if len(sys.argv) > 4:
    x0, y0, x1, y1 = [int(v) for v in sys.argv[4].split(",")]
    im = im.crop((x0, y0, x1, y1))
    off = (x0, y0)
    im = im.resize((im.width * 2, im.height * 2), Image.LANCZOS)
    sc = 2
else:
    sc = 1
d = ImageDraw.Draw(im)
W, H = im.size
gx0 = (off[0] // step) * step
for x in range(gx0, off[0] + W // sc + step, step):
    px = (x - off[0]) * sc
    if 0 <= px < W:
        d.line([(px, 0), (px, H)], fill=(255, 255, 0), width=1)
        d.text((px + 3, 3), str(x), fill=(255, 255, 0))
gy0 = (off[1] // step) * step
for y in range(gy0, off[1] + H // sc + step, step):
    py = (y - off[1]) * sc
    if 0 <= py < H:
        d.line([(0, py), (W, py)], fill=(0, 255, 255), width=1)
        d.text((3, py + 3), str(y), fill=(0, 255, 255))
im.save(dst)
print(dst, im.size)
