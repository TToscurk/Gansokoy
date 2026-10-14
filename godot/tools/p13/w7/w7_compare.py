"""P13 W7：BEFORE|AFTER 並べ画像（ラベル付き・任意クロップ・縮小）。
  uv run --quiet --with pillow python w7_compare.py <out.png> <before.png> <after.png> "<label_before>" "<label_after>" [x0,y0,x1,y1] [--w=800]
  複数ペアを縦に積む：--pair を繰り返す形式は使わず、1 ペア 1 枚。縦積みは w7_stack.py。
"""
import sys

from PIL import Image, ImageDraw


def label(im, text):
    d = ImageDraw.Draw(im)
    w = d.textlength(text)
    d.rectangle([0, 0, w + 12, 20], fill=(0, 0, 0))
    d.text((6, 4), text, fill=(255, 220, 0))


def main():
    out, b, a, lb, la = sys.argv[1:6]
    box = None
    wmax = 800
    for s in sys.argv[6:]:
        if s.startswith("--w="):
            wmax = int(s.split("=")[1])
        elif "," in s:
            box = [int(v) for v in s.split(",")]
    ib = Image.open(b).convert("RGB")
    ia = Image.open(a).convert("RGB")
    if box:
        ib = ib.crop(box)
        ia = ia.crop(box)
    if ib.width != wmax:
        h = int(ib.height * wmax / ib.width)
        ib = ib.resize((wmax, h), Image.LANCZOS)
        ia = ia.resize((wmax, h), Image.LANCZOS)
    label(ib, lb)
    label(ia, la)
    sheet = Image.new("RGB", (ib.width * 2 + 6, ib.height), (255, 0, 255))
    sheet.paste(ib, (0, 0))
    sheet.paste(ia, (ib.width + 6, 0))
    sheet.save(out)
    print("saved", out, sheet.size)


main()
