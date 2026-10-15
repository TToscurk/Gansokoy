#!/bin/bash
SC=C:/Users/B365/AppData/Local/hermes/cache/scratch
cd D:/神社/shrine/godot
GD=D:/Godot/Godot_v4.7.2-stable_win64_console.exe
timeout 500 $GD --path . --script res://tools/p13/w9/walk_w9p3_arm.gd -- $SC/p3walk_arm/ off --disable=EnrichW9P3,ArchW9R2P13 > $TMPDIR/p3b_arm_off.log 2>&1; echo ARM_OFF=$?
timeout 500 $GD --path . --script res://tools/p13/w9/walk_w9p3_arm.gd -- $SC/p3walk_arm/ on --baseline=$SC/p3walk_arm/off_arm.json > $TMPDIR/p3b_arm_on.log 2>&1; echo ARM_ON=$?
timeout 500 $GD --path . --script res://tools/p13/w9/walk_w9p3_arm.gd -- $SC/p3walk_arm/ neg --inject-r1-posts --baseline=$SC/p3walk_arm/off_arm.json > $TMPDIR/p3b_arm_neg.log 2>&1; echo ARM_NEG=$?
echo ARMWALK_ALLDONE
