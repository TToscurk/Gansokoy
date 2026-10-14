extends "res://tools/p13/shot_w4.gd"
## P13 W5C diagnostic only: close-ups of the stair top (vegetation hidden for the top-down ones).
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
	await _free(pre + "_zoom_top_a", _rel(98.6, 0.0, 6.0), _rel(98.6, 0.0, 0.0), 28.0)
	await _free(pre + "_zoom_top_b", _rel(98.0, 3.5, 2.2), _rel(98.8, 0.3, 0.2), 50.0)
	await _free(pre + "_zoom_top_c", _rel(100.2, 0.5, 1.6), _rel(98.3, 0.3, 0.1), 50.0)
	if veg:
		veg.visible = true
	await _free_end()
	print("[W5C-ZOOM] DONE")
	quit(0)
