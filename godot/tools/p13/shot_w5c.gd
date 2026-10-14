extends "res://tools/p13/shot_w4.gd"
## P13 W5C — upper shrine stair transition (s≈84–100 m). Same cameras for BEFORE/AFTER.
##   godot --path godot --script res://tools/p13/shot_w5c.gd -- <outdir/> <prefix>
## Actual main.tscn runtime (ReviewStart), Forward+, 10:00 frozen. TPS = real player + SpringArm (camera code untouched);
## free views = read-only capture camera, trees NOT hidden.
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var pre := args[1] if args.size() > 1 else "x"
	DirAccess.make_dir_recursive_absolute(out)
	cl = SA.centerline()
	await _boot()
	await _tp(85.0, true)
	await _shot(pre + "_t1_up_s85", 30)
	await _tp(90.5, true)
	await _shot(pre + "_t2_up_s90", 30)
	await _tp(95.0, true)
	await _shot(pre + "_t3_entrance_s95", 30)
	await _tp(98.0, true)
	await _shot(pre + "_t4_entrance_s98", 30)
	await _tp(100.0, false)
	await _shot(pre + "_t5_down_s100", 30)
	await _free_begin()
	await _free(pre + "_f1_join", _rel(85.5, 3.6, 3.0), _rel(89.85, 0.0, 0.4), 55.0)
	await _free(pre + "_f2_upper_side", _rel(88.5, 5.5, 3.2), _rel(94.5, 0.0, 0.3), 55.0)
	await _free(pre + "_f3_upper_high", _rel(84.0, 5.0, 10.0), _rel(94.0, 0.0, 0.0), 60.0)
	await _free(pre + "_f4_top_looking_down", _rel(100.5, -2.0, 3.0), _rel(92.0, 0.0, 0.3), 58.0)
	await _free(pre + "_f5_close_treads", _rel(91.0, 2.6, 1.3), _rel(94.5, 0.0, 0.2), 50.0)
	await _free_end()
	print("[W5C-SHOTS] DONE ", pre)
	quit(0)
