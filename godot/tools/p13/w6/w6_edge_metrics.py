"""P13 Wave 6：道路 ↔ 地面境界の対比（鮮鋭度）を Before／After で比較（唯読）。
  uv run --with pillow --with numpy python w6_edge_metrics.py <dirA> <tagA> <dirB> <tagB> [--hard=25]
各ショット i（A と B は同じ鏡位）の ID 画像から、道路ノードと地面系ノードが隣接する画素対を集め、
  n（対の数）、mean ΔRGB、p90、hard 率（ΔRGB > hard）を「道路ノード別」に出す。A＝修正前、B＝修正後。
"""
import json
import sys
from collections import defaultdict

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0] if "/" in __file__ else ".")
from w6_analyze import decode, load_table  # noqa: E402


def is_ground(path):
    p = path.split("/")
    if p[0] == "Terrain":
        return True
    if p[0] == "Vegetation" and len(p) > 2 and (p[2] == "Ground" or p[2].startswith("Ground") or (p[1] == "GroundcoverP9" and p[2] in ("Ground", "Chunks"))):
        return True
    if "EarthBanks" in p:
        return True
    if p[0] == "Districts" and len(p) > 2 and "Yard" in p[2]:
        return True
    return False


def collect(d, tag, idx, hard):
    bits, mp = load_table(f"{d}/{tag}_idtable.json")
    index = json.load(open(f"{d}/{tag}_index.json", encoding="utf-8"))
    name = [r["name"] for r in index if r["i"] == idx][0]
    ids = decode(f"{d}/{tag}_{idx:03d}_id.png", bits)
    rgb = np.asarray(Image.open(f"{d}/{name}.png").convert("RGB")).astype(np.float64)
    kind = {}
    for u in np.unique(ids[ids >= 0]):
        p = mp.get(int(u))
        if p is None:
            continue
        if p.startswith("Roads/") and not p.startswith("Roads/Bridges"):
            kind[int(u)] = ("R", p)
        elif is_ground(p):
            kind[int(u)] = ("G", p)
    road_ids = np.zeros(ids.max() + 2, bool)
    gr_ids = np.zeros(ids.max() + 2, bool)
    for u, (k, p) in kind.items():
        if k == "R":
            road_ids[u] = True
        else:
            gr_ids[u] = True
    isr = np.where(ids >= 0, road_ids[np.clip(ids, 0, None)], False)
    isg = np.where(ids >= 0, gr_ids[np.clip(ids, 0, None)], False)
    out = defaultdict(list)
    for axis in (0, 1):
        if axis == 1:
            ra, rb = isr[:, :-1], isr[:, 1:]
            ga, gb = isg[:, :-1], isg[:, 1:]
            ia, ib = ids[:, :-1], ids[:, 1:]
            ca, cb = rgb[:, :-1], rgb[:, 1:]
        else:
            ra, rb = isr[:-1, :], isr[1:, :]
            ga, gb = isg[:-1, :], isg[1:, :]
            ia, ib = ids[:-1, :], ids[1:, :]
            ca, cb = rgb[:-1, :], rgb[1:, :]
        for m, rid in ((ra & gb, ia), (ga & rb, ib)):
            ys, xs = np.nonzero(m)
            if ys.size == 0:
                continue
            dd = np.abs(ca[ys, xs] - cb[ys, xs]).mean(axis=1)
            rids = rid[ys, xs]
            for u in np.unique(rids):
                out[kind[int(u)][1]].append(dd[rids == u])
    return {k: np.concatenate(v) for k, v in out.items()}


def main():
    a = sys.argv[1:]
    dA, tA, dB, tB = a[0], a[1], a[2], a[3]
    hard = 25.0
    for x in a[4:]:
        if x.startswith("--hard="):
            hard = float(x.split("=")[1])
    idxA = json.load(open(f"{dA}/{tA}_index.json", encoding="utf-8"))
    agg = {"A": defaultdict(list), "B": defaultdict(list)}
    for r in idxA:
        i = r["i"]
        for tag, d, key in ((tA, dA, "A"), (tB, dB, "B")):
            for road, v in collect(d, tag, i, hard).items():
                agg[key][road].append(v)
    roads = sorted(set(agg["A"]) | set(agg["B"]))
    print(f"{'road':44s} | {'A n':>7s} {'mean':>6s} {'p90':>6s} {'hard%':>6s} | {'B n':>7s} {'mean':>6s} {'p90':>6s} {'hard%':>6s} | d_hard")
    for road in roads:
        row = []
        for key in ("A", "B"):
            if road in agg[key]:
                v = np.concatenate(agg[key][road])
                row.append((len(v), v.mean(), np.percentile(v, 90), 100.0 * (v > hard).mean()))
            else:
                row.append((0, 0, 0, 0))
        (na, ma, pa, ha), (nb, mb, pb, hb) = row
        print(f"{road:44s} | {na:7d} {ma:6.1f} {pa:6.1f} {ha:6.1f} | {nb:7d} {mb:6.1f} {pb:6.1f} {hb:6.1f} | {hb - ha:+6.1f}")


if __name__ == "__main__":
    main()
