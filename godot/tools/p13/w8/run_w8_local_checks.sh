#!/usr/bin/env bash
# P13 W8：受影響 gate の局部実行（R6a 材質／Kit・W8・W7・LOD 掃引）。出力は $1（log）に追記。各行：結果 label (exit)
G="D:/Godot/Godot_v4.7.2-stable_win64_console.exe"
LOG="$1"
cd D:/神社/shrine/godot
E="D:/神社/shrine/docs/art_review/village_v2_p13/wave8/evidence"
: > "$LOG"
run() {   # label, expect-fail-text(空=exit 0 必須), args...
	local label="$1" want="$2"; shift 2
	local out rc t0=$(date +%s)
	out="$(timeout 580 "$G" "$@" 2>&1)"; rc=$?
	local dt=$(( $(date +%s) - t0 ))
	if [ -z "$want" ]; then
		if [ $rc -eq 0 ]; then echo "PASS $label (exit 0, ${dt}s)" >> "$LOG"; else echo "FAIL $label (exit $rc, ${dt}s)" >> "$LOG"; printf '%s\n' "$out" | grep -aE "FAIL|失敗|ERROR: [^1]" | head -6 | cut -c1-240 >> "$LOG"; fi
	else
		if [ $rc -ne 0 ] && printf '%s\n' "$out" | grep -qF "$want"; then echo "PASS(neg) $label (${dt}s)" >> "$LOG"; else echo "FAIL(neg) $label (exit $rc, ${dt}s)" >> "$LOG"; fi
	fi
}
case "$2" in
	r6a)
		run "ALB plan" "" --headless --path . --script res://tools/verify_village_v2_albedo_pilot.gd
		run "ALB --scene" "" --path . --script res://tools/verify_village_v2_albedo_pilot.gd -- --scene
		run "ALB --seal" "" --headless --path . --script res://tools/verify_village_v2_albedo_pilot.gd -- --seal
		run "KITM" "" --headless --path . --script res://tools/verify_village_v2_kit_material.gd
		run "KIT --regress (187)" "" --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress
		run "KIT neg material" "FAIL machiya_kit materials" --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress --neg=material
		run "KIT neg offpilot" "FAIL machiya_kit materials" --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress --neg=material_offpilot
		run "KIT neg wrongbase" "FAIL machiya_kit materials" --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress --neg=material_wrongbase
		run "KIT neg badsha" "FAIL machiya_kit materials" --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress --neg=material_badsha
		run "KIT neg w8_badsha" "FAIL machiya_kit materials" --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress --neg=material_w8_badsha
		run "KIT neg w8_unfrozen" "FAIL machiya_kit materials" --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress --neg=material_w8_unfrozen
		;;
	w8)
		run "W8 gate +反向" "" --headless --path . --script res://tools/p13/w8/verify_w8_lod.gd -- --negatives
		run "W7 gate +反向" "" --headless --path . --script res://tools/p13/w7/verify_w7_cleanup.gd -- --negatives
		run "W6 gate +反向" "" --headless --path . --script res://tools/p13/w6/verify_w6_cleanup.gd -- --negatives
		;;
	sweep)
		run "LOD 掃引 OFF" "" --path . --resolution 320x180 --script res://tools/p13/w8/w8_lod_sweep.gd -- $E/lod_sweep_guard_off.json --guard=off --quick --interval0
		run "LOD 掃引 ON" "" --path . --resolution 320x180 --script res://tools/p13/w8/w8_lod_sweep.gd -- $E/lod_sweep_guard_on.json --guard=on --quick --interval0
		pout="$("$G" --headless --path . --script res://tools/p13/w8/w8_probe_double.gd -- B_P_SGT_002 B_P_MKT_032 B_P_RSW_071 B_P_MXC_013 2>&1)"
		n_all=$(printf '%s
' "$pout" | grep -ac "共通名"); n_bad=$(printf '%s
' "$pout" | grep -a "共通名" | grep -avc "共通名 \[\]")
		if [ "$n_all" -ge 20 ] && [ "$n_bad" -eq 0 ]; then echo "PASS 同じ部位の 2 級同時表示 0（probe $n_all 距離・margin 0）" >> "$LOG"; else echo "FAIL 同じ部位の 2 級同時表示（probe $n_all 距離・違反 $n_bad）" >> "$LOG"; fi
		if python tools/p13/w8/check_sweep.py $E/lod_sweep_guard_off.json $E/lod_sweep_guard_on.json > $E/lod_sweep_check.txt 2>&1; then echo "PASS LOD 掃引 判定（ON gap 0・OFF で検出）" >> "$LOG"; else echo "FAIL LOD 掃引 判定" >> "$LOG"; tail -5 $E/lod_sweep_check.txt >> "$LOG"; fi
		;;
esac
echo "DONE $2" >> "$LOG"
