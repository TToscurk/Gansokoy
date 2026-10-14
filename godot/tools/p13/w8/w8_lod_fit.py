"""P13 W8 TASK B：albedo_probe_<group>.json から、LOD1／LOD2 の壁・木の色が LOD0 とどれだけ離れているかを群ごとに要約する（唯読）。
  uv run --quiet --with numpy python w8_lod_fit.py <evidence dir> [group …]
壁＝LOD0 plaster ↔ LODk atlas_light／木＝LOD0 wood ↔ LODk atlas_dark。比は rgb 各チャンネルの LODk／LOD0。
輝度比＝Rec.709 の線形輝度比、色味ずれ＝(r,g,b)/輝度 の正規化色の距離（0＝同じ色相彩度）。
"""
import json
import sys
from pathlib import Path

import numpy as np

E = Path(sys.argv[1])
groups = [a for a in sys.argv[2:]] or ["batch", "main", "pilot"]
LUM = np.array([0.2126, 0.7152, 0.0722])


def lum(c):
    return float(np.dot(c, LUM))


def chroma(c):
    c = np.array(c, dtype=float)
    return c / max(lum(c), 1e-9)


def pair(b, cls0, clsk, k):
    a = b["L0"].get(cls0)
    z = b["L%d" % k].get(clsk)
    if not a or not z or a["area"] < 4 or z["area"] < 2:
        return None
    return np.array(a["rgb"]), np.array(z["rgb"])


for g in groups:
    d = json.load(open(E / f"albedo_probe_{g}.json", encoding="utf-8"))["buildings"]
    print(f"== {g} ({len(d)} 棟)")
    for what, c0, ck in (("壁 plaster→atlas_light", "plaster", "atlas_light"), ("木 wood→atlas_dark", "wood", "atlas_dark")):
        for k in (1, 2):
            rat, dch, n = [], [], 0
            for bid, b in d.items():
                p = pair(b, c0, ck, k)
                if p is None:
                    continue
                n += 1
                rat.append(lum(p[1]) / lum(p[0]))
                dch.append(float(np.linalg.norm(chroma(p[1]) - chroma(p[0]))))
            if n:
                rat = np.array(rat)
                dch = np.array(dch)
                print(f"  {what:24s} LOD{k}: n={n:2d}  輝度比 中央値 {np.median(rat):.2f} 範囲 {rat.min():.2f}–{rat.max():.2f}   色味ずれ 平均 {dch.mean():.3f} 最大 {dch.max():.3f}")
            else:
                print(f"  {what:24s} LOD{k}: 比較できる建物なし")
    # 屋根（kawara ↔ atlas_dark の屋根は l_rh_ なので別扱い。ここでは LOD1／2 の kawara 類）
    for k in (1, 2):
        rat, n = [], 0
        for bid, b in d.items():
            a = b["L0"].get("kawara")
            z = b["L%d" % k].get("kawara")
            if a and z and a["area"] >= 4:
                n += 1
                rat.append(lum(np.array(z["rgb"])) / lum(np.array(a["rgb"])))
        if n:
            print(f"  屋根 kawara             LOD{k}: n={n:2d}  輝度比 中央値 {np.median(rat):.2f} 範囲 {min(rat):.2f}–{max(rat):.2f}")
