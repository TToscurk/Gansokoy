"""P13 W8：同鏡位 LOD0／LOD1／LOD2 の比較シートを作る（唯読）。
  uv run --quiet --with pillow python w8_sheets.py <wave8 dir>
B：第一批 50 棟（W7 の状態＝BEFORE／W8＝AFTER）×3 鏡位（市集・西住宅・丘腳）→ compare/B_lod_same_view_<view>.png
C：Pilot 24（無変更・参考）3 鏡位 × L0／L1／L2 → compare/C_pilot_lod_unchanged.png
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W = Path(sys.argv[1])
S = 0.4
try:
    F = ImageFont.truetype("C:/Windows/Fonts/msjh.ttc", 30)
except Exception:
    F = ImageFont.load_default()


def tile(path, text):
    im = Image.open(path).convert("RGB")
    im = im.resize((int(im.width * S), int(im.height * S)), Image.LANCZOS)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, im.width, 40], fill=(0, 0, 0))
    d.text((8, 4), text, fill=(255, 255, 255), font=F)
    return im


def sheet(rows, out):
    h = rows[0][0].height
    w = rows[0][0].width
    sh = Image.new("RGB", (w * len(rows[0]) + 6 * (len(rows[0]) - 1), h * len(rows) + 6 * (len(rows) - 1)), (255, 255, 255))
    for r, row in enumerate(rows):
        for c, t in enumerate(row):
            sh.paste(t, (c * (w + 6), r * (h + 6)))
    sh.save(out)
    print(out, sh.size)


VN = {"mkt": "市集", "rsw": "西住宅", "mxc": "丘腳通り"}
(W / "compare").mkdir(exist_ok=True)
for v in ("mkt", "rsw", "mxc"):
    rows = []
    for tag, name in (("lod_b_before", "BEFORE（W7）"), ("lod_b_after2", "AFTER（W8）")):
        rows.append([tile(W / "diag" / tag / f"l_{v}_L{k}.png", f"{name}  {VN[v]}  LOD{k}") for k in range(3)])
    sheet(rows, W / "compare" / f"B_lod_same_view_{v}.png")
rows = []
for v, nm in (("p0", "南大門脇"), ("p1", "西住宅"), ("p2", "市集南")):
    rows.append([tile(W / "diag" / "lod_pilot" / f"l_{v}_L{k}.png", f"Pilot 24（無変更） {nm}  LOD{k}") for k in range(3)])
sheet(rows, W / "compare" / "C_pilot_lod_unchanged.png")
