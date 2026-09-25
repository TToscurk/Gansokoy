#!/usr/bin/env bash
# 人間之里 V2 回歸總表（P1 Terrain ART_APPROVED 2026-09-24 起，任何 gen_village_v2.gd／terrain lib／water lib／layout 修改後都要全跑）。
# P2 起加：P1 Approved Terrain Protection（水線以上 |Δh| ≤ 0.03 m、岸線縫 ≤ 0.30 m）與 P2 water gate。
# P3 起加：roads / parcels gate（巷道層、單棟地塊 §11 紀錄、覆蓋率）。
# P5 Asset Reset 起加：asset reset gate（V2 只能引用白名單／已過 Asset Gate 的新資產；Protected 資產雜湊不變；封存不等於刪除）。
# P5 R1 起加：Hero Asset Gate 回歸（v2_assets 已登記的 Hero／地標在場景裡重驗尺寸～效能 9 項；截圖與 F5/F6 另跑 --render，見規劃 §15）。
# P5 R5 後加：場景擺放／碰撞稽核 audit_village_v2_placement.gd（skill godot-asset-placement-validation；AABB 只當 broad phase；--selftest 含 5 個永久反向／對照案例）。
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
run "P4 greybox gate"                       GB      --headless --path . --script res://tools/verify_village_v2_greybox.gd
run "P5 asset reset gate（白名單／Protected／封存）" ASSET --headless --path . --script res://tools/verify_village_v2_asset_reset.gd
run "P5 Hero Asset Gate 回歸（已登記資產 1–9 項重驗＋gate.json 雜湊）" HERO --headless --path . --script res://tools/verify_village_v2_hero_gate.gd -- --all
run "P6 町家 Kit Asset Gate 回歸（1–9 項重驗＋gate.json 雜湊）" KIT --headless --path . --script res://tools/verify_village_v2_machiya_kit_gate.gd -- --regress
run "場景擺放／碰撞稽核＋永久反向案例（clean 全 PASS；float／sink／clash→FAIL、aabbfp→PASS、noproxy→REVIEW）" PLACE --headless --path . --script res://tools/audit_village_v2_placement.gd -- --selftest
run "19-point walk"                        WALK    --rendering-method gl_compatibility --path . --script res://tools/walk_village_v2.gd
echo "回歸失敗項目：$fail"
exit $fail
