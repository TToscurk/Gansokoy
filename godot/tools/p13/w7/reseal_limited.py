"""P13 Wave 7 limited reseal（R5a／R6a 封存の限定再封存）。

  python reseal_limited.py r5a    # P10 R5a Road Base 416 m Pilot 封存：verify_village_v2_road_base.gd の雜湊 1 件
  python reseal_limited.py r6a    # P10 R6a Kit Material 24 Buildings Pilot 封存：3 verifier の雜湊＋第一批名簿 1 件を追加
  python reseal_limited.py <kind> --check   # 変更せず、現状の一致／不一致だけ表示

修正範囲は各 CONFIG に明示した frozen のキーだけ。それ以外の frozen は雜湊が封存時と一致していることを確認した上で何も変えない。
一致しない物が 1 件でもあれば中止（exit 2）。reseal_history に理由・範囲・前後の雜湊を追記する。
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]          # D:/神社/shrine
DATE = "2026-10-14"

CONFIG = {
    "r5a": {
        "seal": "godot/data/village_v2_p10r5a_seal.json",
        "update": ["godot/tools/verify_village_v2_road_base.gd"],
        "add": [],
        "entry": {
            "kind": "W7_RDB_SCENE_GATE_ACCEPT_JUNCTION_FIX_MESH",
            "approved_by": "user（P13 WAVE 7 TASK 2：『若修改涉及封存，執行限定範圍 R5a limited reseal』）",
            "reason": "P13 W7 TASK 2 の FarmJunctionFixP13 は、RoadBaseP10 が差し替えた FarmlandTerrain.mesh から COLOR.r／UV2.y を 5 頂点だけ変えた派生 mesh"
                      "（resource_name＝FarmJunctionFix_FarmlandTerrain）に runtime で置き換える。RDB 場景 gate は地形 mesh の名前が RoadBase_FarmlandTerrain であることを要求していたため、"
                      "後続 overlay の正当な変更で FAIL する（跨層）。",
            "scope": {
                "changed_file": "godot/tools/verify_village_v2_road_base.gd",
                "change": "_scene() の地形 mesh 名検査だけ。RoadBase_FarmlandTerrain に加えて、root に FarmJunctionFixP13 があり applied > 0 のときの FarmJunctionFix_FarmlandTerrain も合法。"
                          "FarmJunctionFixP13 が無いのにその名前なら従来どおり FAIL。派生の厳密検証（変更頂点＝記録の 5 点だけ・位置／法線／UV 不変・RoadBase の他頂点不変）は"
                          "tools/p13/w7/verify_w7_cleanup.gd が持つ。",
                "not_changed": "road_base lib／road_base.gd／gen/road_base_p10.scn／元の road_*.res／terrain_farmlandterrain.res／R5a の plan gate・反向・封存範囲・判定基準・容差。",
            },
            "verification": "RDB plan＋反向 5/5・--scene 0 失敗・--seal 0 失敗；W7 gate（junction 検査 18 項＋反向）",
        },
    },
    "r6a": {
        "seal": "godot/data/village_v2_p10r6a_seal.json",
        "update": [
            "godot/tools/verify_village_v2_machiya_kit_gate.gd",
            "godot/tools/verify_village_v2_albedo_pilot.gd",
            "godot/tools/verify_village_v2_kit_material.gd",
        ],
        "add": ["godot/data/village_v2_p13w7_batch1.json"],
        "also_update": ["godot/data/village_v2_p13w7_batch1.json"],   # 同じ W7 の中で名簿の rule 文言を直した（割当は不変）ときに許す
        "entry": {
            "kind": "W7_BATCH1_SCOPE_AWARE",
            "approved_by": "user（P13 WAVE 7 TASK 5：批准第一批 50 棟正式材質整合）",
            "reason": "R6a の合法範囲は『Pilot 24 棟だけ』だった。使用者が第一批 50 棟の正式材質整合を承認したため、Kit Gate『4 材質』・ALB 場景 gate『Pilot 外に覆寫なし』・"
                      "KITM K5『Pilot 外 0 棟』が正当な後続 overlay（AlbedoBatch1P13）で FAIL する（跨層）。",
            "scope": {
                "changed_files": ["godot/tools/verify_village_v2_machiya_kit_gate.gd", "godot/tools/verify_village_v2_albedo_pilot.gd", "godot/tools/verify_village_v2_kit_material.gd"],
                "added_frozen": "godot/data/village_v2_p13w7_batch1.json（第一批 50 棟の名簿）",
                "change": "3 verifier とも、名簿ファイルの sha256 が本封存の frozen 値と一致するときだけ、名簿の建物にも『登記変体の override』を許可する（Pilot 外検査から除外）。"
                          "合法な変体は R6a の登記 18 変体だけ（sha・基底一致・飽和・明度帯の検査は不変）。名簿の sha が違う／封存が無い＝従来どおり全て FAIL。",
                "not_changed": "登記表 kit_material_variants.json／18 変体の .tres／kit_cal.gdshader／albedo_pilot.gd／albedo_pilot_p10.scn／R6a lib 2 本／Pilot 24 棟の割り当て／判定基準・容差・永久反向。",
            },
            "verification": "Kit Gate --regress（187 棟）・反向 4／ALB plan＋場景＋反向／KITM 場景・反向；W7 gate（名簿 50・LOD0／1／2 全面・範囲外 0・反向 7/7）",
        },
    },
}


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    kind = sys.argv[1]
    check = "--check" in sys.argv
    cfg = CONFIG[kind]
    seal = ROOT / cfg["seal"]
    raw = seal.read_bytes()
    crlf = b"\r\n" in raw
    d = json.loads(raw.decode("utf-8"))
    fr = d["frozen"]
    mism = {k: (v, sha(ROOT / k)) for k, v in fr.items() if sha(ROOT / k) != v}
    others = [k for k in mism if k not in cfg["update"] and k not in cfg.get("also_update", [])]
    print(f"[{kind}] frozen {len(fr)} 件・不一致 {len(mism)} 件：{[k.rsplit('/', 1)[-1] for k in mism]}")
    if others:
        print("ABORT：更新対象以外の frozen が封存時と一致しない：", others)
        sys.exit(2)
    missing = [k for k in cfg["add"] if not (ROOT / k).exists()]
    if missing:
        print("ABORT：追加する檔案が無い：", missing)
        sys.exit(2)
    if check:
        return
    if not mism and all(k in fr and fr[k] == sha(ROOT / k) for k in cfg["add"]):
        print("変更なし")
        return
    before = {}
    for k, (old, new) in mism.items():
        before[k] = [old, new]
        fr[k] = new
    added = {}
    for k in cfg["add"]:
        if k not in fr:
            fr[k] = sha(ROOT / k)
            added[k] = fr[k]
    seal_before = hashlib.sha256(raw).hexdigest()
    hist = d.setdefault("reseal_history", [])
    if hist and hist[-1].get("kind") == cfg["entry"]["kind"] and hist[-1].get("at") == DATE:
        # 同じ限定 reseal の修正（verifier を直した）：新しい履歴を増やさず、同じ項目の『後』の雜湊だけ更新する
        last = hist[-1]
        for k, (old, new) in before.items():
            if k in last["frozen"]:
                last["frozen"][k][1] = new
            else:
                last["frozen"][k] = [old, new]
        last["added_frozen"].update(added)
        last.setdefault("amended", []).append({k: v[1] for k, v in before.items()})
    else:
        entry = dict(cfg["entry"])
        entry["at"] = DATE
        entry["frozen"] = before
        entry["added_frozen"] = added
        entry["seal_file_before"] = seal_before
        hist.append(entry)
    out = json.dumps(d, ensure_ascii=False, indent=1)
    if crlf:
        out = out.replace("\n", "\r\n")
    seal.write_bytes((out + ("\r\n" if crlf else "\n")).encode("utf-8"))
    print(f"resealed [{kind}]：更新 {len(before)}・追加 {len(added)}・history {len(hist)} 件")


if __name__ == "__main__":
    main()
