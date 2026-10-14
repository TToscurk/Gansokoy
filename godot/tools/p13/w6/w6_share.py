"""P13 Wave 6：2 つの撮影セット（baseline と変更版）の「地形 vs overlay」画素比を比較（唯読）。
  uv run --with pillow --with numpy python w6_share.py <dirA> <tagA> <idxA...> -- <dirB> <tagB> <idxB...> --nodes=Terrain/NorthHill,Vegetation/ShrineGroveP9/Ground
各ペア（A[i], B[i]）で、指定ノード群それぞれの画素数を出し、比（先頭ノード ÷ 指定ノード合計）を比べる。
"""
import json
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0] if "/" in __file__ else ".")
from w6_analyze import decode, load_table  # noqa: E402


def counts(d, tag, i, nodes):
    bits, mp = load_table(f"{d}/{tag}_idtable.json")
    ids = decode(f"{d}/{tag}_{i:03d}_id.png", bits)
    out = []
    for nd in nodes:
        us = [k for k, v in mp.items() if v == nd or v.startswith(nd + "/")]
        out.append(int(np.isin(ids, us).sum()) if us else 0)
    return out


def main():
    a = sys.argv[1:]
    sep = a.index("--")
    A, B = a[:sep], a[sep + 1:]
    nodes = []
    for x in B:
        if x.startswith("--nodes="):
            nodes = x.split("=", 1)[1].split(",")
    B = [x for x in B if not x.startswith("--nodes=")]
    dA, tA, iA = A[0], A[1], [int(x) for x in A[2:]]
    dB, tB, iB = B[0], B[1], [int(x) for x in B[2:]]
    print(f"nodes: {nodes}")
    tot = {"A": np.zeros(len(nodes), int), "B": np.zeros(len(nodes), int)}
    for ia, ib in zip(iA, iB):
        ca = counts(dA, tA, ia, nodes)
        cb = counts(dB, tB, ib, nodes)
        tot["A"] += ca
        tot["B"] += cb
        ra = ca[0] / max(sum(ca), 1)
        rb = cb[0] / max(sum(cb), 1)
        print(f"  A#{ia:03d} {ca}  share0={ra:.3f}   |   B#{ib:03d} {cb}  share0={rb:.3f}")
    ra = tot["A"][0] / max(tot["A"].sum(), 1)
    rb = tot["B"][0] / max(tot["B"].sum(), 1)
    print(f"TOTAL A {tot['A'].tolist()} share0={ra:.4f}  |  B {tot['B'].tolist()} share0={rb:.4f}")


if __name__ == "__main__":
    main()
