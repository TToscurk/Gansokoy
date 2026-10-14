"""P13 Wave 8 limited reseal（R6a 封存の限定再封存・LOD 材質の登記）。

  python reseal_limited.py r6a            # 3 verifier の雜湊更新＋LOD 材質（登記表・shader・変体 .tres・名簿）を frozen に追加
  python reseal_limited.py r6a --check    # 変更せず、現状の一致／不一致だけ表示

修正範囲は CONFIG に明示した frozen のキーだけ。それ以外の frozen は雜湊が封存時と一致していることを確認した上で何も変えない。
一致しない物が 1 件でもあれば中止（exit 2）。reseal_history に理由・範囲・前後の雜湊を追記する（同日・同 kind の修正は履歴を増やさず amended に積む）。
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]          # D:/神社/shrine
DATE = "2026-10-14"
LODDIR = ROOT / "godot/maps/village_v2/lod_cal_p13"
ADD = sorted(["godot/maps/village_v2/lod_cal_p13/" + p.name for p in LODDIR.iterdir() if p.suffix in (".tres", ".json", ".gdshader")]) + ["godot/data/village_v2_p13w8_lod.json"]

CONFIG = {
    "r6a": {
        "seal": "godot/data/village_v2_p10r6a_seal.json",
        "update": [
            "godot/tools/verify_village_v2_machiya_kit_gate.gd",
            "godot/tools/verify_village_v2_kit_material.gd",
        ],
        "add": ADD,
        "also_update": ADD,   # 同じ W8 の中で LOD 材質の値を調整し直した（割当・範囲は不変）ときに許す
        "entry": {
            "kind": "W8_LOD_MATERIALS_SCOPE_AWARE",
            "approved_by": "user（P13 WAVE 8 TASK B：少量按建築調色盤分類的 LOD 材質を許可）",
            "reason": "R6a の合法な override は『登記 18 変体』だけだった。W8 TASK B は第一批 50 棟の LOD1／LOD2 の atlas 表面（V2_MachiyaKit）を、"
                      "LOD0 の灰泥・木・瓦に色を合わせた調色盤別の LOD 材質（新 shader kit_cal_lod.gdshader の派生 21 材質）で覆寫する。"
                      "Kit Gate『4 材質』・KITM K5 は未登記の override として正当な後続 overlay（LodCalBatch1P13）で FAIL する（跨層）。",
            "scope": {
                "changed_files": ["godot/tools/verify_village_v2_machiya_kit_gate.gd", "godot/tools/verify_village_v2_kit_material.gd"],
                "added_frozen": "lod_cal_p13/ の登記表・shader・変体 .tres 全部と、割り当て名簿 data/village_v2_p13w8_lod.json",
                "change": "2 verifier とも、LOD 材質の登記表・shader・各変体の sha256 が本封存の frozen 値と一致するものだけ、登記変体として許可する（base＝V2_MachiyaKit.tres の表面に限る）。"
                          "適用先は W7 の第一批名簿の建物だけ（従来の Pilot 外検査がそのまま効く）。登記表の sha が違う／封存が無い＝従来どおり全て FAIL。",
                "not_changed": "R6a 登記表 kit_material_variants.json／既存 18 変体の .tres／kit_cal.gdshader／albedo_pilot.gd／albedo_pilot_p10.scn／W7 の albedo_batch.gd／Pilot 24 棟の割り当て／"
                               "判定基準・容差・永久反向。verify_village_v2_albedo_pilot.gd は変更なし（W7 の名簿範囲の例外がそのまま効く）。",
            },
            "verification": "Kit Gate --regress（187 棟）・反向 4／KITM 場景・反向／ALB 場景・封存；W8 gate（登記・名簿・LOD1／2 全面・範囲外 0・還原・反向）",
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
    # 追加済みの LOD 材質が、いまのファイルと違う（調整した）＝更新、未追加＝追加
    if check:
        print(f"  追加予定 {len([k for k in cfg['add'] if k not in fr])} 件")
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
