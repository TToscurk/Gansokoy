"""P13 Wave 6：指定 landmark（部分一致）が各 TPS 撮影で占める画素数（ID パス・唯読）。
  uv run --with pillow --with numpy python w6_lm_vis.py <substr> <dir:tag> [<dir:tag> ...]
"""
import glob
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from w6_analyze import decode, load_table  # noqa: E402

sub = sys.argv[1]
tot = 0
best = []
for dt in sys.argv[2:]:
    d, tag = dt.rsplit(":", 1)
    bits, mp = load_table(os.path.join(d, f"{tag}_idtable.json"))
    ks = [k for k, v in mp.items() if sub in v]
    if not ks:
        print(f"{d}: no node matching {sub!r}")
        continue
    idx = json.load(open(os.path.join(d, f"{tag}_index.json"), encoding="utf-8"))
    for r in idx:
        idp = os.path.join(d, f"{r['name']}_id.png")
        if not os.path.exists(idp):
            continue
        ids = decode(idp, bits)
        n = int(np.isin(ids, ks).sum())
        if n > 0:
            best.append((n, os.path.basename(d.rstrip('/')) + "/" + r["name"] + ":" + str(r.get("seg"))))
        tot += 1
best.sort(reverse=True)
print(f"shots scanned={tot}  shots with >0 px={len(best)}  ≥500px={sum(1 for n,_ in best if n>=500)}  ≥3000px={sum(1 for n,_ in best if n>=3000)}  of {100*0+len(best)}")
for n, nm in best[:8]:
    print(f"  {n:7d} px  {nm}")
