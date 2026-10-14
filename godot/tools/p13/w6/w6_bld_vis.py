"""P13 Wave 6 TASK D：ID パス画像から「建物ごとの画面占有画素」を集計（唯読）。
  uv run --with pillow --with numpy python w6_bld_vis.py <out.json> <dir1> <tag1> [<dir2> <tag2> ...]
各ショットの ID 画像で、建物ノード（Districts/*/Buildings/B_P_*／S_A_*、Landmarks/LANDMARK_*）に属する画素を数える。
出力：建物名 → {max_px, total_px, shots_ge_500, shots_ge_3000, best_shot}
"""
import json
import sys
from collections import defaultdict

import numpy as np

sys.path.insert(0, __file__.rsplit("/", 1)[0] if "/" in __file__ else ".")
from w6_analyze import decode, load_table  # noqa: E402


def bld_of(path):
    p = path.split("/")
    if p[0] == "Districts" and len(p) > 3 and p[2] == "Buildings":
        return p[3]
    if p[0] == "Landmarks" and len(p) > 1:
        return p[1]
    return None


def main():
    out = sys.argv[1]
    pairs = list(zip(sys.argv[2::2], sys.argv[3::2]))
    stat = defaultdict(lambda: {"max_px": 0, "total_px": 0, "shots_ge_500": 0, "shots_ge_3000": 0, "best_shot": ""})
    nshots = 0
    for d, tag in pairs:
        idx = json.load(open(f"{d}/{tag}_index.json", encoding="utf-8"))
        bits, mp = load_table(f"{d}/{tag}_idtable.json")
        owner = {}
        for k, pth in mp.items():
            b = bld_of(pth)
            if b:
                owner[int(k)] = b
        names = sorted(set(owner.values()))
        code_of = {n: i for i, n in enumerate(names)}
        lut_size = max(owner) + 2
        lut = np.full(lut_size, -1, np.int32)
        for k, b in owner.items():
            lut[k] = code_of[b]
        for r in idx:
            i = r["i"]
            ids = decode(f"{d}/{tag}_{i:03d}_id.png", bits)
            valid = ids >= 0
            codes = np.where(valid, lut[np.clip(ids, 0, lut_size - 1)], -1)
            cnt = np.bincount(codes[codes >= 0].ravel(), minlength=len(names))
            nshots += 1
            for n, c in zip(names, cnt):
                if c <= 0:
                    continue
                s = stat[n]
                s["total_px"] += int(c)
                if c > s["max_px"]:
                    s["max_px"] = int(c)
                    s["best_shot"] = f"{tag}_{i:03d}:{r['seg']}"
                if c >= 500:
                    s["shots_ge_500"] += 1
                if c >= 3000:
                    s["shots_ge_3000"] += 1
    json.dump({"shots": nshots, "buildings": stat}, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("shots", nshots, "buildings", len(stat))


if __name__ == "__main__":
    main()
