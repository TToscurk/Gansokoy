#!/bin/bash
SC=C:/Users/B365/AppData/Local/hermes/cache/scratch
cd D:/神社/shrine/godot
GD=D:/Godot/Godot_v4.7.2-stable_win64_console.exe
mkdir -p $SC/final
# 0) enrich を最終の lib から再生成して、保存済みと同一か
timeout 280 $GD --headless --path . --script res://tools/p13/w9/build_w9p3.gd -- --meadow-cache=$SC/w9_meadow.json --dump=$SC/final/p3_plan_final.json > $SC/final/build_enrich.log 2>&1; echo ENRICH_BUILD=$?
sha256sum maps/village_v2/gen/enrich_w9p3.scn | cut -c1-16 > $SC/final/enrich_hash_after.txt
# 1) 374 gate・posts・reach
bash $TMPDIR/p2_gate.sh > $SC/final/p2_gate.out 2>&1; echo P2GATE_DONE
cp $TMPDIR/p2_gate.log $SC/final/gate_r2_main.log; cp $TMPDIR/p2_posts.log $SC/final/gate_r2_posts.log; cp $TMPDIR/p2_walk.log $SC/final/gate_w9_reach.log
# 2) Phase 3 環境 gate・蔵・近景遮蔽
timeout 280 $GD --headless --path . --script res://tools/p13/w9/verify_w9p3.gd > $SC/final/gate_p3_environment.log 2>&1; echo P3ENV=$?
timeout 120 $GD --headless --path . --script res://tools/p13/w9/verify_w9p3_kura.gd > $SC/final/gate_p3_kura.log 2>&1; echo KURA=$?
timeout 120 $GD --headless --path . --script res://tools/p13/w9/verify_w9p3_view.gd > $SC/final/gate_p3_view.log 2>&1; echo VIEW=$?
# 3) SpringArm sweep gate
timeout 600 $GD --path . --script res://tools/p13/w9/arm_sweep_w9p3.gd -- $SC/final/arm_sweep_R2.json --gate > $SC/final/gate_arm_sweep.log 2>&1; echo ARMSWEEP=$?
# 4) 真玩家：SpringArm 歩行 OFF／ON／NEG
mkdir -p $SC/final/armwalk
timeout 500 $GD --path . --script res://tools/p13/w9/walk_w9p3_arm.gd -- $SC/final/armwalk/ off --disable=EnrichW9P3,ArchW9R2P13 > $SC/final/walk_arm_off.log 2>&1; echo ARM_OFF=$?
timeout 500 $GD --path . --script res://tools/p13/w9/walk_w9p3_arm.gd -- $SC/final/armwalk/ on --baseline=$SC/final/armwalk/off_arm.json > $SC/final/walk_arm_on.log 2>&1; echo ARM_ON=$?
timeout 500 $GD --path . --script res://tools/p13/w9/walk_w9p3_arm.gd -- $SC/final/armwalk/ neg --inject-r1-posts --baseline=$SC/final/armwalk/off_arm.json > $SC/final/walk_arm_neg.log 2>&1; echo ARM_NEG=$?
# 5) 真玩家：23 脚
mkdir -p $SC/final/walk
timeout 600 $GD --path . --script res://tools/p13/w9/walk_w9p3_real.gd -- $SC/final/walk/ on --baseline=$SC/p3walk/off_walk.json > $SC/final/walk_on_R2.log 2>&1; echo WALK_ON=$?
echo FINAL_ALLDONE
