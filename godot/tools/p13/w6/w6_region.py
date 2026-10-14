"""P13 Wave 6：画像の矩形領域に対し、ID パスで「どの節点が描いているか」と通常画像の色統計を出す（唯読）。
  uv run --with pillow --with numpy python w6_region.py <normal.png> <id.png> <idtable.json> x0,y0,x1,y1 [x0,y0,x1,y1 ...] [--top=8]
"""
import json
import sys
from collections import Counter

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0] if "/" in __file__ else ".")
from w6_analyze import decode, load_table  # noqa: E402


def main():
    img, idp, tab = sys.argv[1:4]
    boxes = [a for a in sys.argv[4:] if not a.startswith("--")]
    top = 8
    for a in sys.argv[4:]:
        if a.startswith("--top="):
            top = int(a.split("=")[1])
    bits, mp = load_table(tab)
    ids = decode(idp, bits)
    rgb = np.asarray(Image.open(img).convert("RGB")).astype(np.float64)
    for b in boxes:
        x0, y0, x1, y1 = [int(v) for v in b.split(",")]
        sub = ids[y0:y1, x0:x1]
        c = Counter(sub[sub >= 0].ravel().tolist())
        tot = sub.size
        col = rgb[y0:y1, x0:x1].reshape(-1, 3)
        print(f"== box {b}  px={tot}  mean RGB=({col[:,0].mean():.0f},{col[:,1].mean():.0f},{col[:,2].mean():.0f})")
        for k, n in c.most_common(top):
            m = (sub == k)
            cc = rgb[y0:y1, x0:x1][m]
            print(f"   {100*n/tot:5.1f}%  RGB=({cc[:,0].mean():.0f},{cc[:,1].mean():.0f},{cc[:,2].mean():.0f})  {mp.get(int(k), '?')}")


if __name__ == "__main__":
    main()
