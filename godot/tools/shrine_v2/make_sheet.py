"""把 asset_sheet.gd 拍出的 tile_XX.png 拼成一張帶標籤的總表。
python godot/tools/shrine_v2/make_sheet.py <tile_dir> <out.jpg> [cols] [tile_px]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

d = sys.argv[1]
out = sys.argv[2]
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 4
tp = int(sys.argv[4]) if len(sys.argv) > 4 else 420

labels = []
with open(os.path.join(d, "list.txt"), encoding="utf-8") as f:
    for ln in f:
        ln = ln.strip()
        if ln:
            labels.append(ln.split("|"))

font = None
for fp in ("C:/Windows/Fonts/msjh.ttc", "C:/Windows/Fonts/mingliu.ttc", "C:/Windows/Fonts/arial.ttf"):
    if os.path.exists(fp):
        font = ImageFont.truetype(fp, 17)
        break
if font is None:
    font = ImageFont.load_default()

rows = (len(labels) + cols - 1) // cols
pad = 44
sheet = Image.new("RGB", (cols * tp, rows * (tp + pad)), (24, 24, 26))
dr = ImageDraw.Draw(sheet)
for i, (idx, name, size) in enumerate(labels):
    im = Image.open(os.path.join(d, f"tile_{int(idx):02d}.png")).convert("RGB")
    w, h = im.size
    s = min(tp / w, tp / h)
    im = im.resize((int(w * s), int(h * s)), Image.LANCZOS)
    x = (i % cols) * tp
    y = (i // cols) * (tp + pad)
    sheet.paste(im, (x, y + pad))
    dr.text((x + 6, y + 4), name, fill=(255, 235, 150), font=font)
    dr.text((x + 6, y + 24), size, fill=(190, 220, 255), font=font)
sheet.save(out, quality=88)
print("sheet", out, sheet.size)
