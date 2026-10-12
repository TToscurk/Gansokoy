# P13 W3B：2 枚（または 3 枚）の同鏡位画像を横に並べる（ラベル付き、各 800 px 幅に縮小）。
#   uv run --no-project --with pillow python tools/p13/stitch_w3b.py <out.png> <imgA> <imgB> [<imgC>] [--crop x0,y0,x1,y1]
import sys
from PIL import Image, ImageDraw

args = sys.argv[1:]
crop = None
if "--crop" in args:
    i = args.index("--crop")
    crop = tuple(int(v) for v in args[i + 1].split(","))
    del args[i:i + 2]
out, imgs = args[0], args[1:]
ims = []
for p in imgs:
    im = Image.open(p).convert("RGB")
    if crop:
        im = im.crop(crop)
    w = 800 if len(imgs) <= 2 else 640
    h = int(im.height * w / im.width)
    ims.append(im.resize((w, h), Image.LANCZOS))
W = sum(i.width for i in ims) + 8 * (len(ims) - 1)
H = max(i.height for i in ims)
canvas = Image.new("RGB", (W, H), (255, 0, 255))
x = 0
for im, p in zip(ims, imgs):
    canvas.paste(im, (x, 0))
    d = ImageDraw.Draw(canvas)
    d.rectangle([x, 0, x + 170, 16], fill=(0, 0, 0))
    d.text((x + 3, 2), p.replace("\\", "/").split("/")[-2][:24], fill=(255, 255, 0))
    x += im.width + 8
canvas.save(out)
print(out, canvas.size)
