#!/usr/bin/env bash
# R6.1 Godot capture runner: ONE clean Godot process per test (no residual character state between tests).
#   run_caps.sh <scene res path> <tag prefix> test1 test2 ...
# output: %APPDATA%/Godot/app_userdata/Gansokoy/r61_moves/<prefix>_<test>/{<test>/f*.png, poses.json, log.json}
set -u
SCENE=$1; PFX=$2; shift 2
GD=D:/Godot/Godot_v4.7.2-stable_win64_console.exe
LOGD=C:/Users/B365/AppData/Local/hermes/cache/scratch/r61caps
mkdir -p "$LOGD"
cd D:/神社/shrine/godot
for t in "$@"; do
  timeout 900 "$GD" --path . --resolution 1280x720 --fixed-fps 30 -s tools/yoriichi_r61/capture_r61.gd -- "$t" "$SCENE" "${PFX}_$t" > "$LOGD/${PFX}_$t.log" 2>&1
  echo "$t rc=$? $(grep -c 'ERROR' "$LOGD/${PFX}_$t.log") errors; $(grep -o 'OUT .*' "$LOGD/${PFX}_$t.log" | tail -1)"
done
