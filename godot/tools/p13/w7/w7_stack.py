"""P13 W7：複数の compare 画像（w7_compare.py の出力）を縦に積む。
  uv run --quiet --with pillow python w7_stack.py <out.png> <in1.png> <in2.png> ...
"""
import sys

from PIL import Image

ims = [Image.open(p).convert("RGB") for p in sys.argv[2:]]
w = max(i.width for i in ims)
h = sum(i.height for i in ims) + 6 * (len(ims) - 1)
sheet = Image.new("RGB", (w, h), (255, 0, 255))
y = 0
for i in ims:
    sheet.paste(i, (0, y))
    y += i.height + 6
sheet.save(sys.argv[1])
print("saved", sys.argv[1], sheet.size)
