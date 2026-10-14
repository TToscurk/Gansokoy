#!/usr/bin/env bash
# P13 W7：受影響 gate の局部実行（R5a／R6a／W7／W6／P8）。出力は $1（log）に追記。各行：結果 label (exit)
G="D:/Godot/Godot_v4.7.2-stable_win64_console.exe"
LOG="$1"
cd D:/神社/shrine/godot
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
	r5a)
		run "RDB plan+反向 5" "" --headless --path . --script res://tools/verify_village_v2_road_base.gd
		run "RDB --scene" "" --path . --script res://tools/verify_village_v2_road_base.gd -- --scene
		run "RDB --seal" "" --headless --path . --script res://tools/verify_village_v2_road_base.gd -- --seal
		run "GRD --seal" "" --headless --path . --script res://tools/verify_village_v2_ground_pilot.gd -- --seal
		;;
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
		;;
	p8)
		run "P1 Approved Terrain Protection" "" --headless --path . --script res://tools/verify_village_v2_p1_protect.gd
		run "P8 local gate" "" --headless --path . --script res://tools/verify_village_v2_farmland.gd
		run "P8 --seal" "" --headless --path . --script res://tools/verify_village_v2_farmland.gd -- --seal
		run "P8 永久反向 (--negative)" "" --headless --path . --script res://tools/verify_village_v2_farmland.gd -- --negative
		run "P8 田埂／水面擺放稽核" "" --headless --path . --script res://tools/audit_village_v2_farmland_placement.gd
		run "GRD plan+反向 7" "" --headless --path . --script res://tools/verify_village_v2_ground_pilot.gd
		run "GRD --scene" "" --path . --script res://tools/verify_village_v2_ground_pilot.gd -- --scene
		;;
	w7)
		run "W7 gate +反向" "" --headless --path . --script res://tools/p13/w7/verify_w7_cleanup.gd -- --negatives
		run "W6 gate +反向 (TASK1 params)" "" --headless --path . --script res://tools/p13/w6/verify_w6_cleanup.gd -- --negatives
		;;
esac
echo "DONE $2" >> "$LOG"
