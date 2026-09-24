#!/usr/bin/env bash
# 人間之里 V2 回歸總表（P1 Terrain ART_APPROVED 2026-09-24 起，任何 gen_village_v2.gd／terrain lib／water lib／layout 修改後都要全跑）。
# P2 起加：P1 Approved Terrain Protection（水線以上 |Δh| ≤ 0.03 m、岸線縫 ≤ 0.30 m）與 P2 water gate。
# P3 起加：roads / parcels gate（巷道層、單棟地塊 §11 紀錄、覆蓋率）。
# 用法（repo 根目錄，git-bash）：  bash godot/tools/run_village_v2_regression.sh [--gen]
#   --gen   先重新產生場景再驗證
# 任一項非 0 退出 → 整體退出碼 = 失敗項目數。固定鏡位擷取另見 docs/plans/2026-09-23-人間之里V2重製規劃.md §9.5。
set -u
cd "$(dirname "$0")/.." || exit 99
G="${GODOT:-D:/Godot/Godot_v4.7.2-stable_win64_console.exe}"
fail=0
run() {  # $1 標籤, $2 grep 前綴, 其餘為 Godot 參數
	local label="$1" tag="$2"; shift 2
	local out; out="$("$G" "$@" 2>&1)"; local rc=$?
	printf '%s\n' "$out" | grep -E "^\[$tag\] (FAIL|結果)|SCRIPT ERROR|Parse Error"
	if [ $rc -ne 0 ]; then echo "✗ $label（exit $rc）"; fail=$((fail + 1)); else echo "✓ $label"; fi
}
if [ "${1:-}" = "--gen" ]; then
	"$G" --headless --path . --script res://tools/gen_village_v2.gd > /dev/null 2>&1 || { echo "✗ 產生器失敗"; exit 98; }
	echo "✓ 產生器"
fi
run "freeze check"                         FREEZE  --headless --path . --script res://tools/verify_village_v2_freeze.gd
run "P1 Approved Terrain Protection"       PROTECT --headless --path . --script res://tools/verify_village_v2_p1_protect.gd
run "P2 water gate"                        WATER   --headless --path . --script res://tools/verify_village_v2_water.gd
run "terrain gate（含鋸齒坡、東岸、橋端、農田）" TERRAIN --headless --path . --script res://tools/verify_village_v2_terrain.gd
run "5 bridge checks"                      BRIDGE  --headless --path . --script res://tools/verify_village_v2_bridges.gd
run "sightline checks"                     SL      --headless --path . --script res://tools/verify_village_v2_sightlines.gd
run "P3 roads / parcels gate"               PARCEL  --headless --path . --script res://tools/verify_village_v2_parcels.gd
run "19-point walk"                        WALK    --rendering-method gl_compatibility --path . --script res://tools/walk_village_v2.gd
echo "回歸失敗項目：$fail"
exit $fail
