"""P13 W7：ID パスの画像から「節点別の疑似カラー地図」を作る（唯読）。
  uv run --quiet --with pillow --with numpy python w7_idmap.py <normal.png> <id.png> <idtable.json> <out.png> [x0,y0,x1,y1] [--scale=2]
  色：FarmlandTerrain＝青、MainTerrain＝薄青、道路 ribbon＝赤系（道ごとに色）、建物＝灰、植被・地被＝緑系、その他＝黄。
  左＝通常、右＝疑似カラー（通常画像を 35 % 重ねる）。凡例は画像下に文字で。
"""
import sys
from collections import Counter

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, __file__.replace("\\", "/").rsplit("/", 2)[0] + "/w6")
from w6_analyze import decode, load_table  # noqa: E402

PALETTE = [
    ("Terrain/FarmlandTerrain", (40, 90, 255)),
    ("Terrain/MainTerrain", (120, 170, 255)),
    ("Terrain/RiverTerrain", (0, 200, 220)),
    ("Terrain/NorthHill", (150, 120, 255)),
    ("Roads/SecondaryRoads/CrossStreetMid", (255, 40, 40)),
    ("Roads/FarmPaths/FarmPath_1", (40, 220, 40)),
    ("Roads/FarmPaths", (255, 150, 0)),
    ("Roads/MainStreet", (255, 90, 160)),
    ("Roads/SecondaryRoads", (255, 120, 60)),
    ("Roads", (255, 200, 120)),
    ("Districts/FarmlandEast/FarmlandP8/EarthBanks", (190, 120, 40)),
    ("Districts/FarmlandEast", (160, 200, 80)),
    ("Districts", (170, 170, 170)),
    ("Landmarks", (200, 200, 200)),
    ("Vegetation", (30, 140, 30)),
    ("Props", (230, 230, 90)),
]


def colour_for(path: str):
    for pre, c in PALETTE:
        if path.startswith(pre):
            return c
    return (255, 255, 0)


def main():
    img, idp, tab, out = sys.argv[1:5]
    box = None
    scale = 1
    for a in sys.argv[5:]:
        if a.startswith("--scale="):
            scale = int(a.split("=")[1])
        elif "," in a:
            box = [int(v) for v in a.split(",")]
    bits, mp = load_table(tab)
    ids = decode(idp, bits)
    rgb = np.asarray(Image.open(img).convert("RGB")).astype(np.float64)
    h, w = ids.shape
    if box is None:
        box = [0, 0, w, h]
    x0, y0, x1, y1 = box
    sub = ids[y0:y1, x0:x1]
    nrm = rgb[y0:y1, x0:x1]
    col = np.zeros(sub.shape + (3,), dtype=np.float64)
    cache = {}
    for k in np.unique(sub):
        if k < 0:
            cache[int(k)] = (0, 0, 0)
        else:
            cache[int(k)] = colour_for(mp.get(int(k), ""))
    for k, c in cache.items():
        col[sub == k] = c
    mix = (col * 0.65 + nrm * 0.35).clip(0, 255).astype(np.uint8)
    L = Image.fromarray(nrm.astype(np.uint8))
    R = Image.fromarray(mix)
    if scale != 1:
        L = L.resize((L.width * scale, L.height * scale), Image.NEAREST)
        R = R.resize((R.width * scale, R.height * scale), Image.NEAREST)
    sheet = Image.new("RGB", (L.width * 2 + 6, L.height + 60), (255, 0, 255))
    sheet.paste(L, (0, 0))
    sheet.paste(R, (L.width + 6, 0))
    d = ImageDraw.Draw(sheet)
    cnt = Counter(sub[sub >= 0].ravel().tolist())
    tot = sub.size
    y = L.height + 4
    items = []
    seen = set()
    for k, n in cnt.most_common(8):
        nm = mp.get(int(k), "?")
        c = colour_for(nm)
        key = (nm.rsplit("/", 1)[0] if nm.count("/") > 3 else nm, c)
        if key in seen:
            continue
        seen.add(key)
        items.append((c, f"{100*n/tot:4.1f}% {nm[-48:]}"))
    x = 4
    for c, t in items[:6]:
        d.rectangle([x, y, x + 12, y + 12], fill=c)
        d.text((x + 16, y), t, fill=(255, 255, 255))
        y += 16 if x > 800 else 0
        x = x if x > 800 else x
        y += 0
        if (y - (L.height + 4)) > 48:
            break
        y += 16 if x <= 800 else 0
    sheet.save(out)
    print("saved", out, sheet.size)


main()
