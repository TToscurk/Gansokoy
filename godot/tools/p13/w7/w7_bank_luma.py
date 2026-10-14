"""P13 W7 TASK 3：EarthBanks の亮度を、同一画面内の周辺地面（FarmlandTerrain／MainTerrain）と比べる（ID パスで画素を分離）。
  uv run --quiet --with pillow --with numpy python w7_bank_luma.py <wave7 dir> [out.json]
eb_before（EarthBankToneP13 OFF）と eb_after（ON）の同じ鏡位 30 枚。画像ごとに bank 画素と地面画素の平均輝度（sRGB の Rec.709 luma）を取り、
bank ≥ 0.3 % の画像だけ使う。比 = bank / ground。
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, "D:/神社/shrine/godot/tools/p13/w6")
from w6_analyze import decode, load_table  # noqa: E402

W = Path(sys.argv[1]) / "diag"
out = sys.argv[2] if len(sys.argv) > 2 else None


def luma(rgb):
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


res = {}
for tag in ("eb_before", "eb_after"):
    bits, mp = load_table(str(W / tag / "e_idtable.json"))
    bank_ids = [k for k, v in mp.items() if "FarmlandP8/EarthBanks" in v]
    gnd_ids = [k for k, v in mp.items() if v in ("Terrain/FarmlandTerrain", "Terrain/MainTerrain")]
    rows = {}
    for p in sorted((W / tag).glob("e_f*.png")):
        if p.name.endswith("_id.png"):
            continue
        ids = decode(str(p.with_name(p.stem + "_id.png")), bits)
        img = np.asarray(Image.open(p).convert("RGB")).astype(float)
        mb = np.isin(ids, bank_ids)
        mg = np.isin(ids, gnd_ids)
        if mb.mean() < 0.003 or mg.sum() < 5000:
            continue
        lb = luma(img[mb]).mean()
        lg = luma(img[mg]).mean()
        rows[p.stem] = {"bank_px": int(mb.sum()), "bank_pct": round(100 * float(mb.mean()), 2), "bank_luma": round(float(lb), 1), "ground_luma": round(float(lg), 1), "ratio": round(float(lb / lg), 3)}
    res[tag] = rows
common = sorted(set(res["eb_before"]) & set(res["eb_after"]))
rb = np.array([res["eb_before"][k]["ratio"] for k in common])
ra = np.array([res["eb_after"][k]["ratio"] for k in common])
lbb = np.array([res["eb_before"][k]["bank_luma"] for k in common])
lba = np.array([res["eb_after"][k]["bank_luma"] for k in common])
lgb = np.array([res["eb_before"][k]["ground_luma"] for k in common])
lga = np.array([res["eb_after"][k]["ground_luma"] for k in common])
summ = {"shots_used": len(common), "ratio_median_before": round(float(np.median(rb)), 3), "ratio_median_after": round(float(np.median(ra)), 3),
        "bank_luma_median_before": round(float(np.median(lbb)), 1), "bank_luma_median_after": round(float(np.median(lba)), 1),
        "ground_luma_median_before": round(float(np.median(lgb)), 1), "ground_luma_median_after": round(float(np.median(lga)), 1)}
print(json.dumps(summ, ensure_ascii=False, indent=1))
for k in common[:12]:
    b, a = res["eb_before"][k], res["eb_after"][k]
    print(f"{k}  bank {b['bank_pct']:4.1f}%  ratio {b['ratio']:.3f} -> {a['ratio']:.3f}   bank luma {b['bank_luma']:.1f} -> {a['bank_luma']:.1f}   ground luma {b['ground_luma']:.1f} -> {a['ground_luma']:.1f}")
if out:
    Path(out).write_text(json.dumps({"summary": summ, "per_shot": {k: {"before": res["eb_before"][k], "after": res["eb_after"][k]} for k in common}}, ensure_ascii=False, indent=1), encoding="utf-8")
