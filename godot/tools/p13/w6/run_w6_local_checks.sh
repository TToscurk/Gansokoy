#!/usr/bin/env bash
# P13 Wave 6：受影響の局部 gate だけを走らせる（全村回歸ではない）。
#   bash tools/p13/w6/run_w6_local_checks.sh <group> [logdir]
# group: seals | scenes | roads | p13 | wide | all
GODOT="D:/Godot/Godot_v4.7.2-stable_win64_console.exe"
GROUP="${1:-all}"
LOGDIR="${2:-$TMPDIR/w6_checks}"
mkdir -p "$LOGDIR"
cd "$(dirname "$0")/../../.." || exit 2
fails=0
run() {
  local tag="$1"; shift
  local log="$LOGDIR/${tag}.log"
  timeout 560 "$GODOT" "$@" > "$log" 2>&1
  local rc=$?
  local tail1
  tail1=$(grep -aE "失敗|fails|FAIL|PASS|passes|結果|====" "$log" | tail -2 | tr '\n' ' ' | cut -c1-200)
  if [ $rc -eq 0 ]; then echo "[PASS] $tag  rc=0  $tail1"; else echo "[FAIL] $tag  rc=$rc  $tail1"; fails=$((fails+1)); fi
}
case "$GROUP" in
  seals|all)
    run SHRINE_seal   --headless --path . --script res://tools/verify_village_v2_shrine_grove.gd -- --seal
    run SHRINE_plan   --headless --path . --script res://tools/verify_village_v2_shrine_grove.gd
    run WATER_seal    --headless --path . --script res://tools/verify_village_v2_waterside.gd -- --seal
    run WATER_plan    --headless --path . --script res://tools/verify_village_v2_waterside.gd
    run GC_seal       --headless --path . --script res://tools/verify_village_v2_groundcover.gd -- --seal
    run P9F           --headless --path . --script res://tools/verify_village_v2_p9_final.gd
    run FOREST_seal   --headless --path . --script res://tools/verify_village_v2_forest.gd -- --seal
    ;;
esac
case "$GROUP" in
  scenes|all)
    run SHRINE_scene  --headless --path . --script res://tools/verify_village_v2_shrine_grove.gd -- --scene
    run SHRINE_sneg   --headless --path . --script res://tools/verify_village_v2_shrine_grove.gd -- --scene-negatives
    run WATER_scene   --headless --path . --script res://tools/verify_village_v2_waterside.gd -- --scene
    run GC_scene      --path . --script res://tools/verify_village_v2_groundcover.gd -- --scene
    ;;
esac
case "$GROUP" in
  roads|all)
    run GRD_plan      --headless --path . --script res://tools/verify_village_v2_ground_pilot.gd
    run GRD_scene     --path . --script res://tools/verify_village_v2_ground_pilot.gd -- --scene
    run RDB_plan      --headless --path . --script res://tools/verify_village_v2_road_base.gd
    run RDB_scene     --path . --script res://tools/verify_village_v2_road_base.gd -- --scene
    run RDB_seal      --headless --path . --script res://tools/verify_village_v2_road_base.gd -- --seal
    run EDGE_plan     --headless --path . --script res://tools/verify_village_v2_edge_closure.gd
    run EDGE_seal     --headless --path . --script res://tools/verify_village_v2_edge_closure.gd -- --seal
    run ALB_seal      --headless --path . --script res://tools/verify_village_v2_albedo_pilot.gd -- --seal
    run R4C_seal      --headless --path . --script res://tools/verify_village_v2_prop_fix.gd -- --seal
    run SAN_plan      --headless --path . --script res://tools/verify_village_v2_shrine_approach.gd
    run SAN_scene     --path . --script res://tools/verify_village_v2_shrine_approach.gd -- --scene
    run SWALK         --headless --path . --script res://tools/verify_village_v2_sando_walkable.gd
    run PARCEL        --headless --path . --script res://tools/verify_village_v2_parcels.gd
    run PROTECT       --headless --path . --script res://tools/verify_village_v2_p1_protect.gd
    run W6_CLEAN      --headless --path . --script res://tools/p13/w6/verify_w6_cleanup.gd -- --negatives
    ;;
esac
case "$GROUP" in
  p13|all)
    run W4_PILOT      --headless --path . --script res://tools/p13/verify_w4_pilot.gd
    run W5B           --headless --path . --script res://tools/p13/verify_w5b_integration.gd
    run W5C           --headless --path . --script res://tools/p13/verify_w5c_transition.gd
    ;;
esac
case "$GROUP" in
  wide|all)
    run P2_WATER      --headless --path . --script res://tools/verify_village_v2_water.gd
    run BRIDGE        --headless --path . --script res://tools/verify_village_v2_bridges.gd
    run FREEZE        --headless --path . --script res://tools/verify_village_v2_freeze.gd
    run GREYBOX       --headless --path . --script res://tools/verify_village_v2_greybox.gd
    run SIGHTLINE     --headless --path . --script res://tools/verify_village_v2_sightlines.gd
    run TERRAIN       --headless --path . --script res://tools/verify_village_v2_terrain.gd
    run ASSET_RESET   --headless --path . --script res://tools/verify_village_v2_asset_reset.gd
    run FARM_seal     --headless --path . --script res://tools/verify_village_v2_farmland.gd -- --seal
    run CANAL         --headless --path . --script res://tools/verify_village_v2_canal_art.gd
    run P7_BRIDGE_RBG --headless --path . --script res://tools/verify_village_v2_riverbank_gate.gd -- --regress
    ;;
esac
echo "== local checks done: fails=$fails =="
exit $fails
