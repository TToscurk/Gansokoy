"""P13 Wave 6：P8 EarthBanks が各 TPS 撮影で占める画素割合と、隣接する地形ノードとの平均 RGB 差（唯読）。
  uv run --with pillow --with numpy python w6_bank_share.py <dir:tag> [<dir:tag> ...]
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from w6_analyze import decode, load_table  # noqa: E402

rows = []
for dt in sys.argv[1:]:
    d, tag = dt.rsplit(":", 1)
    bits, mp = load_table(os.path.join(d, f"{tag}_idtable.json"))
    eb = [k for k, v in mp.items() if "/EarthBanks/" in v]
    terr = [k for k, v in mp.items() if v.startswith("Terrain/FarmlandTerrain") or v.startswith("Terrain/MainTerrain")]
    idx = json.load(open(os.path.join(d, f"{tag}_index.json"), encoding="utf-8"))
    for r in idx:
        p = os.path.join(d, f"{r['name']}_id.png")
        if not os.path.exists(p):
            continue
        ids = decode(p, bits)
        rgb = np.asarray(Image.open(os.path.join(d, f"{r['name']}.png")).convert("RGB")).astype(np.float64)
        me = np.isin(ids, eb)
        mt = np.isin(ids, terr)
        n = int(me.sum())
        tot = ids.size
        if n > 0 and mt.sum() > 0:
            le = (0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2])[me].mean()
            lt = (0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2])[mt].mean()
            rows.append((n / tot * 100.0, le / lt, r["name"], str(r.get("seg"))))
        else:
            rows.append((0.0, float("nan"), r["name"], str(r.get("seg"))))
sh = np.array([r[0] for r in rows])
print(f"shots={len(rows)}  with EarthBanks>0.5%: {int((sh>0.5).sum())}   >2%: {int((sh>2).sum())}   >5%: {int((sh>5).sum())}   max={sh.max():.1f}%   mean(all)={sh.mean():.2f}%")
lr = np.array([r[1] for r in rows if r[0] > 0.5 and r[1] == r[1]])
if len(lr):
    print(f"luma ratio EarthBanks / adjacent-terrain-mean (shots with >0.5% banks): median={np.median(lr):.2f}  p10={np.percentile(lr,10):.2f}  p90={np.percentile(lr,90):.2f}")
for r in sorted(rows, reverse=True)[:6]:
    print(f"   {r[0]:5.1f}%  ratio={r[1]:.2f}  {r[2]}:{r[3]}")
