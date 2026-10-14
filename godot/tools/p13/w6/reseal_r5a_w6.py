"""P13 Wave 6 limited reseal（P10 R5a Road Base 416 m Pilot 封存 data/village_v2_p10r5a_seal.json）。

修改範囲（明示）：frozen のうち godot/tools/verify_village_v2_ground_pilot.gd の雜湊 1 件だけ。
理由：GRD 場景 gate の「非 Pilot 道路材質不變」を scope-aware に補正した（RoadEdgeBlendP13.road_paths 列の 7 道路は
「同じ pilot shader に換わっている」ことだけを要求し、それ以外は従来どおり不變を要求；反向 1 案を追加）。
他の frozen 16 件は雜湊が封存時と一致していることを確認した上で何も変えない。一致しない物が 1 件でもあれば中止。
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]          # D:/神社/shrine
SEAL = ROOT / "godot" / "data" / "village_v2_p10r5a_seal.json"
TARGET = "godot/tools/verify_village_v2_ground_pilot.gd"


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    raw = SEAL.read_bytes()
    d = json.loads(raw.decode("utf-8"))
    fr = d["frozen"]
    mism = []
    for k, v in fr.items():
        cur = sha(ROOT / k)
        if cur != v:
            mism.append((k, v, cur))
    others = [m for m in mism if m[0] != TARGET]
    if others:
        print("ABORT：目標以外の frozen が封存時と一致しない：", [m[0] for m in others])
        sys.exit(2)
    if not mism:
        print("変更なし（目標の雜湊も一致）。何もしない")
        return
    k, old, new = mism[0]
    fr[k] = new
    d["reseal_history"].append({
        "at": "2026-10-14",
        "kind": "W6_GRD_SCENE_GATE_SCOPE_AWARE",
        "approved_by": "user（P13 Wave 6 指示 §6：必要な limited reseal は明確な修改範囲つきで可）",
        "reason": "P13 Wave 6 の RoadEdgeBlendP13 が外圍 7 道路（CrossStreetMid／HillFootStreet／RiverNorthPath／EntranceRoad／FarmPath_2／3／5）へ"
                  "この Pilot と同じ ground_p10_pilot.gdshader の外緣侵蝕を overlay で套用する。GRD 場景 gate『非 Pilot 道路材質不變』は封存時の"
                  "scope（Pilot 4 道路だけが変わる）を前提にしていたため、後続 overlay の正当な変更で FAIL する（跨層）。",
        "scope": {
            "changed_file": TARGET,
            "change": "非 Pilot 道路検査を関数化（_non_pilot_bad）。RoadEdgeBlendP13.road_paths に列挙された道路は『pilot shader に換わっている』ことだけを要求"
                      "（材質不變の対象外）。それ以外の道路は従来どおり材質不變を要求。反向 1 案を追加：W6 引き受け外の MainStreet の材質を差し替えると必ず 1 件検出。",
            "not_changed": "ground_p10_pilot.gdshader／ground_pilot.gd／ground_pilot_p10.scn／village_v2_ground_pilot_lib.gd／road_base 関連／R5a の plan gate（shader 雜湊・補丁・外緣統計）／Pilot 4 道路の参數",
        },
        "hash_before": old,
        "hash_after": new,
        "verification": "GRD plan 反向 7/7・--scene 0 失敗（非 Pilot 道路 12 条不變＋W6 引き受け 7 条＋反向 1）；RDB --seal 0 失敗",
    })
    out = json.dumps(d, ensure_ascii=False, indent=1)
    # 元ファイルの改行規約を保つ
    if b"\r\n" in raw:
        out = out.replace("\n", "\r\n")
    SEAL.write_bytes((out + ("\r\n" if b"\r\n" in raw else "\n")).encode("utf-8"))
    print("resealed:", k, old[:12], "→", new[:12], "history entries:", len(d["reseal_history"]))


if __name__ == "__main__":
    main()
