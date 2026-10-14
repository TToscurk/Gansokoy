extends "res://tools/p13/shot_w4.gd"
## P13 W5C diagnostic only (not deliverable): top-down & low views with vegetation overlays optionally hidden.
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var pre := args[1] if args.size() > 1 else "d"
	DirAccess.make_dir_recursive_absolute(out)
	cl = SA.centerline()
	await _boot()
	await _free_begin()
	await _free(pre + "_top_all", _rel(94.5, 0.0, 22.0), _rel(94.5, 0.0, 0.0), 40.0)
	var hid: Array = []
	var veg := vil.get_node_or_null("Vegetation")
	if veg:
		veg.visible = false
		hid.append(veg)
	await _free(pre + "_top_novegetation", _rel(94.5, 0.0, 22.0), _rel(94.5, 0.0, 0.0), 40.0)
	await _free(pre + "_top_novegetation_close_97_100", _rel(98.5, 0.0, 9.0), _rel(98.5, 0.0, 0.0), 40.0)
	await _free(pre + "_side_novegetation_97_100", _rel(96.0, 4.0, 1.4), _rel(98.8, 0.0, 0.1), 45.0)
	for n in hid:
		n.visible = true
	await _free_end()
	print("[W5C-DIAG] DONE")
	quit(0)
