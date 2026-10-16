"""contact sheets: python sheet8.py <shots_dir> <tag> <out_prefix> <names comma> [cols] [tw]"""
import json
import sys

from PIL import Image, ImageDraw, ImageFont

d, tag, outp, names = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split(",")
cols = int(sys.argv[5]) if len(sys.argv) > 5 else 3
tw = int(sys.argv[6]) if len(sys.argv) > 6 else 533
th = tw * 9 // 16
V = {v[0]: v[5] for v in json.load(open("C:/Users/B365/AppData/Local/hermes/cache/scratch/p8/views.json", encoding="utf-8"))}
font = ImageFont.truetype("C:/Windows/Fonts/msjh.ttc", 22)
rows = (len(names) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * (th + 30)), (20, 20, 20))
dr = ImageDraw.Draw(sheet)
for i, n in enumerate(names):
    im = Image.open(f"{d}/{tag}_{n}.png").convert("RGB").resize((tw, th), Image.LANCZOS)
    x, y = (i % cols) * tw, (i // cols) * (th + 30)
    sheet.paste(im, (x, y + 30))
    dr.text((x + 6, y + 3), f"{n}  {V.get(n, '')}", fill=(255, 230, 120), font=font)
sheet.save(outp, quality=88)
print(outp, sheet.size)
