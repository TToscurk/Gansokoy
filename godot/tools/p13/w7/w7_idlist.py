"""P13 W7：ID パス画像に写っている節点の画素数上位を列挙する（唯読）。
  uv run --quiet --with pillow --with numpy python w7_idlist.py <id.png> <idtable.json> [--top=14] [x0,y0,x1,y1]
"""
import sys
from collections import Counter

import numpy as np

sys.path.insert(0, __file__.replace("\\", "/").rsplit("/", 2)[0] + "/w6")
from w6_analyze import decode, load_table  # noqa: E402

args = [a for a in sys.argv[1:] if not a.startswith("--")]
top = 14
for a in sys.argv[1:]:
    if a.startswith("--top="):
        top = int(a.split("=")[1])
bits, mp = load_table(args[1])
ids = decode(args[0], bits)
if len(args) > 2:
    x0, y0, x1, y1 = [int(v) for v in args[2].split(",")]
    ids = ids[y0:y1, x0:x1]
c = Counter(ids[ids >= 0].ravel().tolist())
tot = ids.size
for k, n in c.most_common(top):
    print(f"{100*n/tot:5.1f}%  {mp.get(int(k), '?')}")
