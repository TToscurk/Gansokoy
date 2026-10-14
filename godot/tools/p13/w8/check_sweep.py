"""P13 W8 TASK A：w8_lod_sweep.gd の出力（守衛 OFF／ON）を検査する。
  python check_sweep.py <off.json> <on.json>
合格条件：
  ON ：全目標×全シナリオ（near／mid／far／cold／turn_fast／turn_slow）で gap 区間 0。
  OFF：探針が不具合を検出できること（OFF の南大門に cold で gap が出る）＝『守衛が無いと壊れる』ことの永久反向。
double（2 級が各 50 % 以上同時＝大きな建物の『部品ごとの AABB 中心距離差による遷移帯』）は ON/OFF どちらにも現れる Kit 固有の性質で参考値。
『同じ部位が 2 級同時に見える』ことの有無は w8_probe_double.gd（margin 0・共通名の同時可視）で別に判定する（run_w8_local_checks.sh sweep）。
"""
import json
import sys

off = json.load(open(sys.argv[1], encoding="utf-8"))
on = json.load(open(sys.argv[2], encoding="utf-8"))
SC = ["near", "mid", "far", "cold", "turn_fast", "turn_slow"]
bad = 0
print(f"{'目標':8s} {'シナリオ':10s} {'OFF gap':28s} {'ON gap':14s} {'OFF double':22s} {'ON double':22s}")
for name in on["targets"]:
    for sc in SC:
        a = off["targets"][name]["scen"][sc]
        b = on["targets"][name]["scen"][sc]
        print(f"{name:8s} {sc:10s} {str(a['gap_runs']):28s} {str(b['gap_runs']):14s} {str(a['double_runs']):22s} {str(b['double_runs']):22s}")
        if b["gap_runs"]:
            bad += 1
            print("   ✗ ON なのに gap")
gate_cold = off["targets"]["gate"]["scen"]["cold"]["gap_runs"]
if not gate_cold:
    bad += 1
    print("✗ OFF の南大門 cold に gap が出ない＝探針が不具合を検出できていない")
print("RESULT", "FAIL" if bad else "PASS", "（ON の gap 区間 0・OFF で南大門 cold に gap あり）" if not bad else "")
sys.exit(1 if bad else 0)
