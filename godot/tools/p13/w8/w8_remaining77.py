"""P13 W8 TASK D：剩餘 77 棟の施工名単（盤点だけ・施工しない）。
  uv run --quiet python w8_remaining77.py <wave8 evidence dir>
入力：wave7/evidence/uncorrected_buildings.json（77 id）・wave6/evidence/inventory_remaining148.json（可見度）・wave6/evidence/inventory_priority_batches.json（batch2／batch3）・
      wave7/evidence/structure_differentiation_backlog.json（構造差異化の候補）・wave8/evidence/buildings_meta_187.json（meta）
出力：wave8/evidence/remaining77_worklist.json／.md
"""
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

E8 = Path(sys.argv[1])
P13 = E8.parent.parent
W6 = P13 / "wave6/evidence"
W7 = P13 / "wave7/evidence"

unc = json.load(open(W7 / "uncorrected_buildings.json", encoding="utf-8"))["ids"]
inv = {r["name"]: r for r in json.load(open(W6 / "inventory_remaining148.json", encoding="utf-8"))}
bt = json.load(open(W6 / "inventory_priority_batches.json", encoding="utf-8"))
b_of = {}
for k in ("batch2", "batch3"):
    for x in bt[k]:
        b_of[x if isinstance(x, str) else x["id"]] = k
meta = json.load(open(E8 / "buildings_meta_187.json", encoding="utf-8"))
try:
    sd = json.load(open(W7 / "structure_differentiation_backlog.json", encoding="utf-8"))
except Exception:
    sd = {}
sd_ids = set()


def collect(o):
    if isinstance(o, dict):
        for k, v in o.items():
            collect(v)
    elif isinstance(o, list):
        for x in o:
            collect(x)
    elif isinstance(o, str) and o.startswith("B_P_"):
        sd_ids.add(o)


collect(sd)

AREA = {"Market": "A", "MixedCommercial": "A", "ResidentialWest": "B", "ResidentialNE": "B"}
USE = {"Market": "商業（市集區の町家列）", "MixedCommercial": "商業・混在（丘脚通り）", "ResidentialWest": "住宅（西区）", "ResidentialNE": "住宅（北東区）"}
rows = []
for i in unc:
    m = meta.get(i, {})
    r = inv.get(i, {})
    rows.append({
        "id": i, "path": m.get("path", ""), "district": m.get("district", ""), "use": USE.get(m.get("district", ""), ""), "palette_area": AREA.get(m.get("district", ""), "?"),
        "road": m.get("road", ""), "type": m.get("type", ""), "type_label": m.get("type_label", ""), "roof": m.get("roof", ""), "pos": m.get("pos", []),
        "tier": r.get("tier", ""), "max_px": r.get("max_px", 0), "shrine_vis": bool(r.get("shrine_vis", False)), "n3000": r.get("n3000", 0),
        "batch": b_of.get(i, ""), "structure_backlog": i in sd_ids,
    })
rows.sort(key=lambda r: (r["batch"], -int(r["n3000"]), -int(r["max_px"]), r["id"]))
for n, r in enumerate(rows):
    r["order"] = n + 1
out = {"count": len(rows), "by_batch": dict(Counter(r["batch"] for r in rows)), "by_district": dict(Counter(r["district"] for r in rows)),
       "by_tier": dict(Counter(r["tier"][:1] for r in rows)), "by_road": dict(Counter(r["road"] for r in rows)), "rows": rows}
(E8 / "remaining77_worklist.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")

L = []
L.append("# 剩餘 77 棟町家 — 下一批施工名單（盤点のみ・W8 では施工しない）\n")
L.append(f"出所：W7 の未校正 {out['count']} 棟（187 − 主街 39 − R6a Pilot 21 − W7 第一批 50）。順序＝W6 の優先度（batch2＝TPS で顕著・神社から見える／batch3＝顕著でない）の中で、TPS 3000 px 以上の鏡位数 → 最大画素数。\n")
L.append(f"- 批次：{out['by_batch']}\n- 区：{out['by_district']}\n- 可見度ティア：{out['by_tier']}\n- 道路：{out['by_road']}\n")
L.append("## 前提（W8 で整ったもの）\n")
L.append("1. LOD1／LOD2 の色は『LOD0 の材質を決めた後に』擬合する（`w8_albedo_probe.gd` → `w8_lod_fit_build.py`）。順序＝先に W7 方式で LOD0 の 18 変体を割り当て → その LOD0 を基準に LOD1／2 の調色盤を擬合。")
L.append("2. 屋根 l_rh_* は LOD 材質の roof 種別（LOD0 の瓦に合わせた乗数）。W7 の『不覆寫』は W8 で置き換わった。")
L.append("3. 新しい材質ファイルは `maps/village_v2/lod_cal_p13/` に追加（既存の登記表は封存のまま）。W9 で LOD 材質を増やすときは W8 と同じ限定 reseal（`tools/p13/w8/reseal_limited.py`）を 1 回。")
L.append("4. 本表の `structure_backlog=true` は W7 の『同じ外形枠で細部だけ違う近隣』候補。材質だけの施工では直らない（構造差異化は別工程）。\n")
L.append("## 一覧（施工順）\n")
L.append("| # | id | 区 | 用途 | 道路 | 型 | 屋根 | 可見 | n≥3000px | 最大px | 神社から | 批次 | 構造候補 |")
L.append("|---|----|----|------|------|----|------|------|----------|--------|----------|------|----------|")
for r in rows:
    L.append(f"| {r['order']} | {r['id']} | {r['district']} | {r['use']} | {r['road']} | {r['type_label'] or r['type']} | {r['roof']} | {r['tier'][:1]} | {r['n3000']} | {r['max_px']} | {'○' if r['shrine_vis'] else ''} | {r['batch']} | {'●' if r['structure_backlog'] else ''} |")
L.append("")
L.append("## 区別の小計\n")
by = defaultdict(list)
for r in rows:
    by[r["district"]].append(r["id"])
for k, ids in by.items():
    L.append(f"- **{k}**（{len(ids)}）：{', '.join(i.replace('B_P_', '') for i in ids)}")
(E8 / "remaining77_worklist.md").write_text("\n".join(L) + "\n", encoding="utf-8")
print("書き込み", out["count"], out["by_batch"], out["by_district"])
