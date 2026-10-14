extends "res://tools/p13/shot_w4.gd"
## P13 W5C diagnostic only: which node draws the light-grey strip / dark wedge? Same camera, one child hidden at a time.
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
	var ov := vil.get_node(OVR)
	var cam_pos := _rel(98.0, 3.5, 2.2)
	var cam_tgt := _rel(98.8, 0.3, 0.2)
	await _free(pre + "_h0_all", cam_pos, cam_tgt, 50.0)
	ov.get_node("W5C").visible = false
	await _free(pre + "_hh_noW5C", cam_pos, cam_tgt, 50.0)
	for pth in ["Roads", "Terrain/NorthHill", "Terrain/FarmlandTerrain", "Terrain/RiverTerrain", "Terrain/MainTerrain", "ShrineApproachP10", "Districts", "Vegetation/ShrineGroveP9"]:
		var n := vil.get_node_or_null(pth) as Node3D
		if n == null:
			continue
		n.visible = false
		await _free(pre + "_hh_no_" + pth.replace("/", "_"), cam_pos, cam_tgt, 50.0)
		n.visible = true
	ov.get_node("W5C").visible = true
	if veg:
		veg.visible = true
	await _free_end()
	print("[W5C-HIDE] DONE")
	quit(0)
