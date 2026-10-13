extends "res://tools/p13/shot_w4.gd"
## Five production captures only, actual main.tscn, frozen 10:00, Forward+.
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	cl = SA.centerline()
	await _boot()
	var ov := vil.get_node(OVR)
	_ok_mount(ov)
	await _tp(43.2,true,4.0)
	var target := _rel(72.0,1.3,0.4)
	var face := (target-player.global_position).normalized()
	player.call("snap_yaw",atan2(-face.x,-face.z))
	await _shot("01_right_wall_tps",70)
	await _free_begin()
	await _free("02_left_wall",_rel(39.0,-6.0,3.0),_rel(66.0,-1.3,0.5),62.0)
	await _free_end()
	await _tp(53.0,true)
	await _shot("03_uphill_tps",30)
	await _free_begin()
	var mid := _rel(64.0,0.0,1.0)
	var pos := mid + Vector3(18.0,65.0,18.0)
	await _free("04_whole_approach_high",pos,mid,62.0)
	await _free("05_new_old_join_s89_85",_rel(85.5,3.6,3.0),_rel(89.85,0.0,0.4),55.0)
	await _free_end()
	print("[W5B-SHOTS] DONE 5")
	quit(0)

func _ok_mount(ov: Node) -> void:
	print("[W5B-SHOTS] integrated=%s upper=%s current=%s" % [str(ov.get_meta("integrated_range")),str(ov.get_node_or_null("W5Upper")!=null),str(vil.get_viewport().get_camera_3d().get_path())])
