"""P13 Wave 6：連絡シート（N 枚を 2×2 などで並べ、ラベルを付ける）。
  uv run --with pillow python w6_sheet.py <out.png> <cols> <cellw> <label1|label2...> img1 img2 ...
ラベルは '|' 区切り（画像と同数）。
"""
import sys
from PIL import Image, ImageDraw

out = sys.argv[1]
cols = int(sys.argv[2])
cw = int(sys.argv[3])
labels = sys.argv[4].split("|")
paths = sys.argv[5:]
ims = []
for p in paths:
    im = Image.open(p).convert("RGB")
    ch = int(cw * im.height / im.width)
    ims.append(im.resize((cw, ch), Image.LANCZOS))
ch = ims[0].height
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cw + (cols - 1) * 6, rows * ch + (rows - 1) * 6), (255, 0, 255))
for i, im in enumerate(ims):
    d = ImageDraw.Draw(im)
    lab = labels[i] if i < len(labels) else str(i)
    d.rectangle((0, 0, 9 * len(lab) + 12, 22), fill=(0, 0, 0))
    d.text((6, 4), lab, fill=(255, 255, 0))
    sheet.paste(im, ((i % cols) * (cw + 6), (i // cols) * (ch + 6)))
sheet.save(out)
print(out, sheet.size)
