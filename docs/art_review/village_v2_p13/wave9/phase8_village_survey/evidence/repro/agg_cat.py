"""P13 W9 Phase 8：ID パス → 畫面組成（類別％）。
uv run --quiet --with pillow --with numpy python agg_cat.py <shots_dir> <tag> <out.json>
"""
import json
import re
import sys
from collections import defaultdict

import numpy as np

sys.path.insert(0, "D:/神社/shrine/godot/tools/p13/w6")
from w6_analyze import decode, load_table  # noqa: E402

CATS = [
    ("npc", r"^Population/"),
    ("w9_bld", r"^ArchW9R2P13/"),
    ("w9_env", r"^EnrichW9"),
    ("bld", r"^Districts/[^/]+/Buildings/"),
    ("landmark", r"^(Landmarks/|FarmsteadP13/)"),
    ("farm", r"^Districts/Farmland"),
    ("props", r"^(Props/|HumanUse|ShrineApproachP10|WaterLifeP10|QuestAnchors|Districts/[^/]+/(Market|Stall|Props))"),
    ("veg", r"^(Vegetation/|EdgeClosureP10/|Districts/[^/]+/(Trees|Hedges|Garden))"),
    ("water", r"^(Water/|Riverbank/)"),
    ("road", r"^(Roads/|RoadBaseP10|RoadEdgeBlend|SandoPilot)"),
    ("terrain", r"^(Terrain/|Districts/[^/]+/(Yards|AuxYards))"),
    ("debug", r"^Debug/"),
]


def cat_of(path: str) -> str:
    for c, rx in CATS:
        if re.search(rx, path):
            return c
    return "other:" + path.split("/")[0]


def main() -> None:
    d, tag, outp = sys.argv[1], sys.argv[2], sys.argv[3]
    bits, mp = load_table(f"{d}/{tag}_idtable.json")
    idx = json.load(open(f"{d}/{tag}_index.json", encoding="utf-8"))
    key2cat = {int(k): cat_of(p) for k, p in mp.items()}
    other_paths = defaultdict(int)
    res = {}
    for rec in idx:
        nm = rec["name"]
        ids = decode(f"{d}/{nm}_id.png", bits)
        tot = ids.size
        u, c = np.unique(ids, return_counts=True)
        agg = defaultdict(float)
        bld = defaultdict(float)
        for k, n in zip(u.tolist(), c.tolist()):
            if k <= 0:
                agg["sky"] += n
                continue
            ct = key2cat.get(k, "unknown")
            agg[ct] += n
            p = mp.get(k, "")
            m = re.search(r"(B_P_[A-Z]+_\d+|S_A_[A-Z]+_\d+)", p)
            if m:
                bld[m.group(1)] += n
            if ct.startswith("other:"):
                other_paths["/".join(p.split("/")[:3])] += n
        res[nm] = {"cat": {k: round(100 * v / tot, 2) for k, v in sorted(agg.items(), key=lambda x: -x[1])},
                   "bld_top": {k: round(100 * v / tot, 2) for k, v in sorted(bld.items(), key=lambda x: -x[1])[:6]},
                   "cam": rec.get("cam"), "player": rec.get("player")}
    json.dump(res, open(outp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    if other_paths:
        print("OTHER:", dict(sorted(other_paths.items(), key=lambda x: -x[1])[:12]))
    print("shots", len(res))


main()
