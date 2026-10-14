"""P13 Wave 6：道路 ribbon 同士の「ID が入れ替わる画素」（同一面の重なり＝z-fight の疑い）と、その画素の見た目の差（唯読）。
  uv run --with pillow --with numpy python w6_road_zfight.py <dirA> <tagA> <dirB> <tagB>
同一機位の前後 2 回撮影で、道路ノード A→B に変わった画素（A,B とも Roads/ 系）を集計し、その画素の RGB 差の平均を出す。
"""
import json
import os
import sys
from collections import defaultdict

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from w6_analyze import decode, load_table  # noqa: E402

da, ta, db, tb = sys.argv[1:5]
bita, ma = load_table(os.path.join(da, f"{ta}_idtable.json"))
bitb, mb = load_table(os.path.join(db, f"{tb}_idtable.json"))
roads_a = {k for k, v in ma.items() if v.startswith("Roads/") and "/Bridges/" not in v}
roads_b = {k for k, v in mb.items() if v.startswith("Roads/") and "/Bridges/" not in v}
idx = json.load(open(os.path.join(da, f"{ta}_index.json"), encoding="utf-8"))
tot = defaultdict(lambda: [0, 0.0, 0])  # pair → [px, sum|dRGB|, shots]
for r in idx:
    n = r["name"].split("_")[1]
    pa = os.path.join(da, f"{ta}_{n}_id.png")
    pb = os.path.join(db, f"{tb}_{n}_id.png")
    if not (os.path.exists(pa) and os.path.exists(pb)):
        continue
    A = decode(pa, bita)
    B = decode(pb, bitb)
    ma_ = np.isin(A, list(roads_a))
    mb_ = np.isin(B, list(roads_b))
    sw = ma_ & mb_ & (A != B)
    # 別 table の ID 値を名前で比べる
    ys, xs = np.nonzero(sw)
    if len(ys) == 0:
        continue
    ia = np.asarray(Image.open(os.path.join(da, f"{ta}_{n}.png")).convert("RGB")).astype(np.int32)
    ib = np.asarray(Image.open(os.path.join(db, f"{tb}_{n}.png")).convert("RGB")).astype(np.int32)
    d = np.abs(ia - ib).sum(axis=2)
    seen = set()
    for y, x in zip(ys.tolist(), xs.tolist()):
        na, nb = ma[int(A[y, x])], mb[int(B[y, x])]
        if na == nb:
            continue
        key = tuple(sorted((na.split("/")[-1], nb.split("/")[-1])))
        e = tot[key]
        e[0] += 1
        e[1] += float(d[y, x]) / 3.0
        if key not in seen:
            e[2] += 1
            seen.add(key)
print(f"{'road pair (label swapped between two runs)':50s} {'px':>8s} {'shots':>5s} {'mean|dRGB| of those px':>24s}")
for k, (n, s, sh) in sorted(tot.items(), key=lambda kv: -kv[1][0])[:12]:
    print(f"{k[0]+' <-> '+k[1]:50s} {n:8d} {sh:5d} {s/max(n,1):24.2f}")
