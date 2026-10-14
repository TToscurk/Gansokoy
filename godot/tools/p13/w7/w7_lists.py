"""P13 W7：第一批 50 棟の表／未校正の一覧／構造差異化 backlog を証拠 JSON から生成する（唯読・場景には触れない）。
  python w7_lists.py <wave7 dir>
出力（wave7/evidence/）：
  batch1_buildings.md              50 棟の ID・区・道・用途・型・屋根・漆喰／木の変体
  uncorrected_buildings.json/.md   未校正 77 棟（187 − 主街 39 − Pilot 24〔うち主街重複 3〕− 第一批 50）
  structure_differentiation_backlog.json/.md   形状が同じ（型・屋根・寸法・LOD0 の部品／三角形数が同じ）建物が近接して並ぶ組（構造差異化候補・本輪は施工しない）
"""
import collections
import json
import math
import sys
from pathlib import Path

W = Path(sys.argv[1])
G = W.parents[0]
ROOT = Path("D:/神社/shrine")
EV = W / "evidence"
inv = json.load(open(EV / "inventory_187.json", encoding="utf-8"))["buildings"]
by = {b["name"]: b for b in inv}
man = json.load(open(ROOT / "godot/data/village_v2_p13w7_batch1.json", encoding="utf-8"))["buildings"]
w2 = {b["id"] for b in json.load(open(ROOT / "godot/data/village_v2_p13_mainstreet.json", encoding="utf-8"))["buildings"]}
reg = json.load(open(ROOT / "godot/maps/village_v2/kit_cal_p10/kit_material_variants.json", encoding="utf-8"))
pilot = {Path(p).name for p in reg["pilot_buildings"]}
batch = {r["id"] for r in man}
assert len(batch) == 50 and not (batch & w2) and not (batch & pilot)

# 1) 第一批 50 棟
rows = sorted(man, key=lambda r: (r["district"], r["id"]))
lines = ["| # | 建築 ID | 区 | 道 | 用途 | 型 | 屋根 | 漆喰の変体 | 木の変体 |", "|--:|---|---|---|---|---|---|---|---|"]
for i, r in enumerate(rows, 1):
    lines.append(f"| {i} | `{r['id']}` | {r['district']} | {r['road']} | {r['use']} | {r['type_label']} | {r['roof']} | `{r['plaster']}` | `{r['wood']}` |")
(EV / "batch1_buildings.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("batch1 table", len(rows))

# 2) 未校正
done = w2 | pilot | batch
rest = [b for b in inv if b["name"] not in done]
cnt = collections.Counter(b["meta"]["district"] for b in rest)
(EV / "uncorrected_buildings.json").write_text(json.dumps({"count": len(rest), "by_district": dict(cnt), "ids": sorted(b["name"] for b in rest)}, ensure_ascii=False, indent=1), encoding="utf-8")
l2 = [f"未校正 {len(rest)} 棟（187 − 主街 {len(w2)} − Pilot {len(pilot)}（うち主街重複 {len(pilot & w2)}）− 第一批 {len(batch)} = {187 - len(done)}）", "", "| 区 | 棟数 |", "|---|--:|"]
for k, v in sorted(cnt.items()):
    l2.append(f"| {k} | {v} |")
l2 += ["", "ID: " + ", ".join(f"`{b['name']}`" for b in sorted(rest, key=lambda b: b["name"]))]
(EV / "uncorrected_buildings.md").write_text("\n".join(l2) + "\n", encoding="utf-8")
print("uncorrected", len(rest), dict(cnt), " expected", 187 - len(done))


# 3) 構造差異化 backlog（登記のみ）：第一批 50 棟を含む、同じ外形枠の近接ペア。
#    strict ＝ 同じ道・型・屋根・幅奥行き ±0.5 m・LOD0 の部品数と三角形数が同じ（＝完全に同一形状）
#    envelope ＝ 型・屋根が同じで、幅・奥行き ±0.5 m・軒高 ±0.3 m の外形枠が重なる（LOD0 の細部は違ってよい）、25 m 以内
def dist(a, b):
    return math.hypot(a["pos"][0] - b["pos"][0], a["pos"][2] - b["pos"][2])


def same_env(a, b):
    ma, mb = a["meta"], b["meta"]
    return ma["type"] == mb["type"] and ma["roof"] == mb["roof"] and abs(ma["width_m"] - mb["width_m"]) <= 0.5 and abs(ma["depth_m"] - mb["depth_m"]) <= 0.5 and abs(ma["eave_m"] - mb["eave_m"]) <= 0.3


strict = []
env = []
for i, a in enumerate(inv):
    for b in inv[i + 1:]:
        if a["name"] not in batch and b["name"] not in batch:
            continue
        d = dist(a, b)
        if d > 25.0 or not same_env(a, b):
            continue
        la, lb = a["lods"]["LOD0"], b["lods"]["LOD0"]
        rec = {"a": a["name"], "b": b["name"], "dist_m": round(d, 1), "road_a": a["meta"]["road"], "road_b": b["meta"]["road"], "type": a["meta"]["type_label"], "roof": a["meta"]["roof"],
               "width_m": a["meta"]["width_m"], "depth_m": a["meta"]["depth_m"], "lod0_tris": [la["tris"], lb["tris"]], "lod0_meshes": [la["n_mesh"], lb["n_mesh"]]}
        env.append(rec)
        if a["meta"]["road"] == b["meta"]["road"] and la["n_mesh"] == lb["n_mesh"] and la["tris"] == lb["tris"]:
            strict.append(rec)
(EV / "structure_differentiation_backlog.json").write_text(json.dumps({"criteria": {"strict": "同じ道・型・屋根・外形枠 ±0.5 m・LOD0 の部品数と三角形数が同じ（完全に同一形状）", "envelope": "型・屋根が同じで 幅／奥行き ±0.5 m・軒高 ±0.3 m、25 m 以内（LOD0 の細部は違ってよい）"}, "strict_pairs": strict, "envelope_pairs": env}, ensure_ascii=False, indent=1), encoding="utf-8")
l3 = ["# 構造差異化 backlog（登記のみ・本輪は施工しない）", "",
      "第一批 50 棟を含む組だけ。形状の入替え（屋根型・出簷・間口など）は材質だけの本輪の範囲外のため、登記して使用者の判断を待つ。", "",
      f"- 完全に同一形状（同じ道・型・屋根・寸法・LOD0 の部品／三角形数）＝ **{len(strict)} 組**",
      f"- 同じ外形枠（型・屋根・幅奥行き ±0.5 m・軒高 ±0.3 m、25 m 以内、LOD0 の細部は異なる）＝ **{len(env)} 組**", ""]
if env:
    l3 += ["| 建物 A | 建物 B | 距離 | 道 | 型・屋根 | 外形 (m) | LOD0 面数 A/B |", "|---|---|--:|---|---|---|---|"]
    for r in env:
        l3.append(f"| `{r['a']}` | `{r['b']}` | {r['dist_m']} m | {r['road_a']}{'' if r['road_a'] == r['road_b'] else ' / ' + r['road_b']} | {r['type']}・{r['roof']} | {r['width_m']}×{r['depth_m']} | {r['lod0_tris'][0]}/{r['lod0_tris'][1]} |")
(EV / "structure_differentiation_backlog.md").write_text(chr(10).join(l3) + chr(10), encoding="utf-8")
print("backlog: strict", len(strict), " envelope", len(env))
for r in env:
    print("  ", r["a"], r["b"], r["dist_m"], r["road_a"], r["type"], r["roof"], r["lod0_tris"])
