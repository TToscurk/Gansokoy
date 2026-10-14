"""P13 Wave 6：同一鏡位セット（前／後）で各道路ノードが占める画素数の比（路幅の見かけの変化・唯読）。
  uv run --with pillow --with numpy python w6_road_px.py <dirA> <tagA> <dirB> <tagB>
"""
import json
import os
import sys
from collections import defaultdict

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from w6_analyze import decode, load_table  # noqa: E402

da, ta, db, tb = sys.argv[1:5]


def collect(d, tag):
    bits, mp = load_table(os.path.join(d, f"{tag}_idtable.json"))
    roads = {k: v for k, v in mp.items() if v.startswith("Roads/")}
    idx = json.load(open(os.path.join(d, f"{tag}_index.json"), encoding="utf-8"))
    out = defaultdict(lambda: defaultdict(int))
    for r in idx:
        p = os.path.join(d, f"{r['name']}_id.png")
        if not os.path.exists(p):
            continue
        ids = decode(p, bits)
        u, c = np.unique(ids[ids >= 0], return_counts=True)
        for k, n in zip(u.tolist(), c.tolist()):
            if k in roads:
                out[roads[k]][r["i"]] += n
    return out


A = collect(da, ta)
B = collect(db, tb)
print(f"{'road':44s} {'shots':>5s} {'px_before':>10s} {'px_after':>10s} {'ratio':>6s}  (shots with >=3000px road only)")
for road in sorted(set(A) | set(B)):
    sb = sa = n = 0
    for i, v in A[road].items():
        if v >= 3000:
            sb += v
            sa += B[road].get(i, 0)
            n += 1
    if n:
        print(f"{road:44s} {n:5d} {sb:10d} {sa:10d} {sa/sb:6.3f}")
