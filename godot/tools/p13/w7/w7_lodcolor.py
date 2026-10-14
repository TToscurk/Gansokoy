"""P13 W7 TASK 5：LOD 強制表示（L0／L1／L2）の画像を ID パスで分け、町家の『壁系』と『屋根系』の平均色を群ごとに集計する（唯読）。
  uv run --quiet --with pillow --with numpy python w7_lodcolor.py <wave7 dir> [out.json]
群：batch（第一批 50）／main（W2 主街 39）／pilot（R6a Pilot 24）／rest（未校正）。main・pilot は使用者が ART_APPROVED 済みの基準。
壁系＝屋根系以外（base_ を除く）。屋根系＝部品名の接頭辞が rf_／rg_*／udh_／dmr_p／oni_*／vg_／his_／hisx_／l_rh_*。
3 鏡位（市集・西住宅・丘腳）の画素を合算。
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, "D:/神社/shrine/godot/tools/p13/w6")
from w6_analyze import decode, load_table  # noqa: E402

W = Path(sys.argv[1])
out = None
VIEWS = ["mkt", "rsw", "mxc"]
DIRS = ["lod_before", "lod_after"]
for a in sys.argv[2:]:
    if a.startswith("--views="):
        VIEWS = a[8:].split(",")
    elif a.startswith("--dirs="):
        DIRS = a[7:].split(",")
    elif not a.startswith("--"):
        out = a
ROOT = Path("D:/神社/shrine")
batch = {r["id"] for r in json.load(open(ROOT / "godot/data/village_v2_p13w7_batch1.json", encoding="utf-8"))["buildings"]}
main_st = {b["id"] for b in json.load(open(ROOT / "godot/data/village_v2_p13_mainstreet.json", encoding="utf-8"))["buildings"]}
pilot = {Path(p).name for p in json.load(open(ROOT / "godot/maps/village_v2/kit_cal_p10/kit_material_variants.json", encoding="utf-8"))["pilot_buildings"]}
ROOF = ("rf_", "rg_", "udh_", "dmr_p", "oni_", "vg_", "his_", "hisx_", "l_rh_")
pat = re.compile(r"^Districts/[^/]+/Buildings/(B_[A-Z0-9_]+)/Kit/LOD(\d)/(.+)$")


def prefix(name):
    s = ""
    for ch in name:
        if ch.isdigit():
            break
        s += ch
    return s


def grp(bid):
    if bid in batch:
        return "batch"
    if bid in main_st:
        return "main"
    if bid in pilot:
        return "pilot"
    return "rest"


def classify(path):
    m = pat.match(path)
    if not m:
        return None
    bid, lod, rest = m.group(1), int(m.group(2)), m.group(3)
    pre = prefix(rest.split("/")[-1])
    if pre.startswith("base_"):
        return None
    return grp(bid), lod, ("roof" if pre.startswith(ROOF) else "wall")


def luma(rgb):
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


res = {}
for tag in DIRS:
    bits, mp = load_table(str(W / "diag" / tag / "l_idtable.json"))
    cls = {k: classify(v) for k, v in mp.items()}
    acc = {}
    for v in VIEWS:
        for k in range(3):
            img = np.asarray(Image.open(W / "diag" / tag / f"l_lod_{v}_L{k}.png").convert("RGB")).astype(float)
            ids = decode(str(W / "diag" / tag / f"l_lod_{v}_L{k}_id.png"), bits)
            flat = ids.ravel()
            pix = img.reshape(-1, 3)
            for idv in np.unique(flat):
                c = cls.get(int(idv)) if int(idv) >= 0 else None
                if c is None or c[1] != k:
                    continue
                sel = pix[flat == idv]
                key = (c[0], k, c[2])
                a = acc.setdefault(key, [0, np.zeros(3)])
                a[0] += len(sel)
                a[1] += sel.sum(axis=0)
    res[tag] = {f"{g}|LOD{k}|{c}": {"px": int(n), "rgb": [round(float(x), 1) for x in (s / max(n, 1))], "luma": round(float(luma(s / max(n, 1))), 1)} for (g, k, c), (n, s) in acc.items()}


def get(tag, g, k, c):
    return res[tag].get(f"{g}|LOD{k}|{c}")


print("== 壁系 平均輝度（sRGB luma 0–255）と LOD 間差")
print(f"{'group':6s} {'tag':7s}  LOD0   LOD1   LOD2   | Δ(L1−L0)  Δ(L2−L0)   px(L0/L1/L2)")
summary = {}
for g in ("batch", "main", "pilot", "rest"):
    for tag in DIRS:
        ls = [get(tag, g, k, "wall") for k in range(3)]
        if not all(ls):
            continue
        l0, l1, l2 = [x["luma"] for x in ls]
        print(f"{g:6s} {tag[4:]:7s}  {l0:5.1f}  {l1:5.1f}  {l2:5.1f}  | {l1 - l0:+6.1f}    {l2 - l0:+6.1f}      {ls[0]['px']}/{ls[1]['px']}/{ls[2]['px']}")
        summary[f"{g}|{tag}"] = {"L0": l0, "L1": l1, "L2": l2, "d10": round(l1 - l0, 1), "d20": round(l2 - l0, 1)}
print("== 屋根系 平均輝度（batch は Kawara 不校正＝BEFORE と AFTER でほぼ同じのはず）")
for g in ("batch", "main", "pilot", "rest"):
    for tag in DIRS:
        ls = [get(tag, g, k, "roof") for k in range(3)]
        if not all(ls):
            continue
        print(f"{g:6s} {tag[4:]:7s}  " + "  ".join(f"{x['luma']:5.1f}" for x in ls) + "   px " + "/".join(str(x["px"]) for x in ls))
if len(DIRS) == 2:
    print("== 壁系 平均色 (R,G,B)：batch の AFTER")
    for k in range(3):
        x = get(DIRS[1], "batch", k, "wall")
        y = get(DIRS[0], "batch", k, "wall")
        print(f"LOD{k}  BEFORE {y['rgb']}  AFTER {x['rgb']}")
if out:
    Path(out).write_text(json.dumps({"detail": res, "wall_summary": summary}, ensure_ascii=False, indent=1), encoding="utf-8")
