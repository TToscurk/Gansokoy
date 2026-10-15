#!/bin/bash
# Phase 3 パイプライン（堅牢版）：Blender 失敗（Errno 22 など）は再試行し、成功しない限り後段へ進まない
cd D:/神社/shrine/godot
GD=D:/Godot/Godot_v4.7.2-stable_win64_console.exe
GLB=assets/village_v2/w9r2_arch/src/w9r2_arch.glb
ok=0
for try in 1 2 3 4 5 6; do
  rm -f "$GLB" 2>/dev/null
  (cd assets/blender/village_v2 && D:/Blender/blender-5.2.1-windows-x64/blender.exe -b --factory-startup --python-exit-code 1 --python build_w9r2_arch.py > $TMPDIR/p2_blender.log 2>&1)
  rc=$?
  if [ $rc -eq 0 ] && ! grep -aq "Traceback\|Errno" $TMPDIR/p2_blender.log && [ -f "$GLB" ]; then ok=1; echo "BLENDER=0 (try $try)"; break; fi
  echo "BLENDER FAIL rc=$rc try=$try"; grep -a "Errno\|Error" $TMPDIR/p2_blender.log | head -3 | cut -c1-200
  sleep 6
done
if [ $ok -ne 1 ]; then echo "BLENDER GAVE UP"; exit 3; fi
timeout 250 $GD --headless --path . --import > $TMPDIR/p2_import.log 2>&1; echo IMPORT=$?
timeout 200 $GD --headless --path . --script res://tools/p13/w9/w9r2_prefab.gd > $TMPDIR/p2_prefab.log 2>&1; echo PREFAB=$?; grep -a "w9r2-prefab\] \|FAIL" $TMPDIR/p2_prefab.log | tail -3
timeout 280 $GD --headless --path . --script res://tools/p13/w9/build_w9r2.gd > $TMPDIR/p2_build.log 2>&1; echo BUILD=$?; grep -a "W9R2B\] 保存\|FAIL\|SCRIPT ERROR" $TMPDIR/p2_build.log | head -5
echo DONE
