"""P13 Wave 6：同一鏡位（前 c／後 f）で ID が変わった画素の「前の節点 → 後の節点」を集計（唯読）。
  uv run --with pillow --with numpy python w6_diff_ids.py <dirA> <tagA> <dirB> <tagB> <seg-substr>
"""
import json
import os
import sys
from collections import Counter

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from w6_analyze import decode, load_table  # noqa: E402

da, ta, db, tb, seg = sys.argv[1:6]
bita, ma = load_table(os.path.join(da, f"{ta}_idtable.json"))
bitb, mb = load_table(os.path.join(db, f"{tb}_idtable.json"))
ia = json.load(open(os.path.join(da, f"{ta}_index.json"), encoding="utf-8"))
for r in ia:
    if seg not in str(r.get("seg")):
        continue
    A = decode(os.path.join(da, f"{r['name']}_id.png"), bita)
    B = decode(os.path.join(db, f"{tb}_{r['name'].split('_')[1]}_id.png"), bitb)
    ch = (A != B) & (A >= 0) & (B >= 0)
    c = Counter()
    ys, xs = np.nonzero(ch)
    for y, x in zip(ys.tolist(), xs.tolist()):
        c[(ma.get(int(A[y, x]), "?"), mb.get(int(B[y, x]), "?"))] += 1
    print(f"== {r['name']} {r.get('seg')} changed px={int(ch.sum())}")
    for (a, b), n in c.most_common(6):
        print(f"    {n:7d}  {a}  ->  {b}")
