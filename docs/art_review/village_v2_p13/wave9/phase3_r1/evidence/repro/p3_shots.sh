#!/bin/bash
# usage: p3_shots.sh <tag> <at-file> [free-file|-] [extra args...]  → scratch/p3raw/<tag>_<name>.png
cd D:/神社/shrine/godot
GD=D:/Godot/Godot_v4.7.2-stable_win64_console.exe
OUT=C:/Users/B365/AppData/Local/hermes/cache/scratch/p3raw/
SC=C:/Users/B365/AppData/Local/hermes/cache/scratch
TAG=$1; ATF=$2; FRF=$3; shift 3
AT=$(cat $SC/$ATF)
if [ "$FRF" != "-" ] && [ -f "$SC/$FRF" ]; then FREE=$(cat $SC/$FRF); else FREE=""; fi
if [ -n "$FREE" ]; then
  timeout 1200 $GD --path . --script res://tools/p13/w7/w7_shots.gd -- $OUT $TAG --at="$AT" --free="$FREE" "$@" > $TMPDIR/p3_shot_$TAG.log 2>&1
else
  timeout 1200 $GD --path . --script res://tools/p13/w7/w7_shots.gd -- $OUT $TAG --at="$AT" "$@" > $TMPDIR/p3_shot_$TAG.log 2>&1
fi
echo SHOT_$TAG=$?
