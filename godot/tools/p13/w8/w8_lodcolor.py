"""P13 W8 TASK B：LOD 強制表示（L0／L1／L2）の画像を ID パスで分け、町家の『壁系』と『屋根系』の平均色を群ごとに集計する（唯読）。
  uv run --quiet --with pillow --with numpy python w8_lodcolor.py <wave8 dir> [out.json] [--dirs=lod_b_before,lod_b_after] [--views=mkt,rsw,mxc]
群：batch（W7 第一批 50＝W8 で LOD 材質を当てた）／main（W2 主街 39）／pilot（R6a Pilot 24）／rest（未校正 77）。main・pilot は使用者が ART_APPROVED 済みの基準（W8 は触らない）。
壁系＝屋根系と base_ 以外。屋根系＝部品名の接頭辞が rf_／rg_*／udh_／dmr_p／oni_*／vg_／his_／hisx_／l_rh_*。3 鏡位（市集・西住宅・丘腳）の画素を合算。
指標：輝度（sRGB 0–255）・RGB・暖度 warmth＝(R−B)/(R+G+B)・LOD0 に対する輝度比 L1／L0、L2／L0・LOD0 との色味ずれ（正規化 RGB の距離）。
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
DIRS = ["lod_b_before", "lod_b_after"]
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


def warmth(rgb):
    s = float(np.sum(rgb))
    return float((rgb[0] - rgb[2]) / s) if s > 0 else 0.0


def chroma(rgb):
    s = float(np.sum(rgb))
    return np.array(rgb) / s if s > 0 else np.zeros(3)


res = {}
for tag in DIRS:
    bits, mp = load_table(str(W / "diag" / tag / "l_idtable.json"))
    cls = {k: classify(v) for k, v in mp.items()}
    acc = {}
    for v in VIEWS:
        for k in range(3):
            img = np.asarray(Image.open(W / "diag" / tag / f"l_{v}_L{k}.png").convert("RGB")).astype(float)
            ids = decode(str(W / "diag" / tag / f"l_{v}_L{k}_id.png"), bits)
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


summary = {}
for part in ("wall", "roof"):
    print(f"== {'壁系' if part == 'wall' else '屋根系'}：輝度（sRGB 0–255）・LOD0 に対する比・暖度・色味ずれ")
    print(f"{'group':6s} {'tag':13s}  L0     L1     L2    | L1/L0  L2/L0 | 暖度 L0/L1/L2          | 色味ずれ L1 L2  | px(L0/L1/L2)")
    for g in ("batch", "main", "pilot", "rest"):
        for tag in DIRS:
            ls = [get(tag, g, k, part) for k in range(3)]
            if not all(ls):
                continue
            l0, l1, l2 = [x["luma"] for x in ls]
            w0, w1, w2 = [warmth(np.array(x["rgb"])) for x in ls]
            c0 = chroma(np.array(ls[0]["rgb"]))
            d1 = float(np.linalg.norm(chroma(np.array(ls[1]["rgb"])) - c0))
            d2 = float(np.linalg.norm(chroma(np.array(ls[2]["rgb"])) - c0))
            print(f"{g:6s} {tag:13s} {l0:5.1f} {l1:6.1f} {l2:6.1f}  | {l1 / l0:5.2f}  {l2 / l0:5.2f} | {w0:+.3f} {w1:+.3f} {w2:+.3f}  | {d1:.3f} {d2:.3f} | {ls[0]['px']}/{ls[1]['px']}/{ls[2]['px']}")
            summary[f"{part}|{g}|{tag}"] = {"L0": l0, "L1": l1, "L2": l2, "r10": round(l1 / l0, 3), "r20": round(l2 / l0, 3), "warm": [round(w0, 4), round(w1, 4), round(w2, 4)], "dchroma": [round(d1, 4), round(d2, 4)],
                                            "rgb": [x["rgb"] for x in ls]}
if out:
    Path(out).write_text(json.dumps({"detail": res, "summary": summary}, ensure_ascii=False, indent=1), encoding="utf-8")
