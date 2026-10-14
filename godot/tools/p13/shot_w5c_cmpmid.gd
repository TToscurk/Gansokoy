extends "res://tools/p13/shot_w4.gd"
## P13 W5C diagnostic only: the approved mid section seen like the top section (vegetation hidden) — are dark wedges on the right side part of the approved style?
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var pre := args[1]
	DirAccess.make_dir_recursive_absolute(out)
	cl = SA.centerline()
	await _boot()
	await _free_begin()
	var veg := vil.get_node_or_null("Vegetation")
	if veg:
		veg.visible = false
	await _free(pre + "_mid_right_s83", _rel(82.2, 3.5, 2.2), _rel(83.0, 0.3, 0.2), 50.0)
	await _free(pre + "_mid_right_s70", _rel(69.2, 3.5, 2.2), _rel(70.0, 0.3, 0.2), 50.0)
	await _free(pre + "_top_right_s98", _rel(98.0, 3.5, 2.2), _rel(98.8, 0.3, 0.2), 50.0)
	if veg:
		veg.visible = true
	await _free_end()
	print("[W5C-MID] DONE")
	quit(0)
