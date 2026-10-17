"""BEFORE｜AFTER 並排圖（同一鏡位）。
   uv run --with pillow --with numpy python make_compare.py <shots_dir_before> <shots_dir_after> <out_dir> [width]
   檔名規則：BEFORE_<view>.png／AFTER_<view>.png。輸出 <out_dir>/cmp_<view>.jpg（左 BEFORE・右 AFTER）＋ contact_sheet.jpg。
   另輸出每個鏡位的『變化像素比例』（|ΔRGB| > 12/255 的畫素占比），僅供參考，不當美術證據。"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

b_dir, a_dir, out_dir = sys.argv[1:4]
W = int(sys.argv[4]) if len(sys.argv) > 4 else 800
os.makedirs(out_dir, exist_ok=True)
names = sorted(f[len("BEFORE_"):-4] for f in os.listdir(b_dir) if f.startswith("BEFORE_") and f.endswith(".png"))
rows = []
for n in names:
    pa = os.path.join(a_dir, "AFTER_%s.png" % n)
    if not os.path.exists(pa):
        continue
    b = Image.open(os.path.join(b_dir, "BEFORE_%s.png" % n)).convert("RGB")
    a = Image.open(pa).convert("RGB")
    h = int(W * b.height / b.width)
    bs, as_ = b.resize((W, h), Image.LANCZOS), a.resize((W, h), Image.LANCZOS)
    diff = np.abs(np.asarray(b).astype(int) - np.asarray(a).astype(int)).max(axis=2)
    share = float((diff > 12).mean())
    sheet = Image.new("RGB", (W * 2 + 6, h + 22), (24, 24, 24))
    sheet.paste(bs, (0, 22))
    sheet.paste(as_, (W + 6, 22))
    d = ImageDraw.Draw(sheet)
    d.text((6, 4), "BEFORE  %s" % n, fill=(255, 255, 255))
    d.text((W + 12, 4), "AFTER  %s   (changed px %.1f%%)" % (n, share * 100), fill=(255, 255, 255))
    sheet.save(os.path.join(out_dir, "cmp_%s.jpg" % n), quality=88)
    rows.append((n, sheet, share))
    print("%-26s changed=%.1f%%" % (n, share * 100))
print("n=%d" % len(rows))
