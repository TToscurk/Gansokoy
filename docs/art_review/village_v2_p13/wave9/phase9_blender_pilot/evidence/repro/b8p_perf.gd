extends "res://tools/p13/w6/w6_base.gd"
## [scratch：P13 W9 B8P 試点] DistrictB8P の ON／OFF 比較（p8_perf.gd と同じ方法・場景ファイルは書かない）。
##   godot --path godot --resolution 1600x900 --script <this> -- <out.json>
## 正式 TPS（main.tscn → ReviewStart → village_v2）、overlay は記憶の中で掛け、各鏡位で ON／OFF（visible）を交互に 3 回（暖機 40＋測定 100 幀）。
const PVIEWS := [
	["V1_lane_in", 441.0, -219.0, 456.0, -235.0],
	["V3_back_yard", 462.0, -215.4, 473.0, -221.5],
	["V5_row_lane", 469.5, -241.0, 447.0, -224.0],
]


func _measure(vp: RID, warm: int, n: int) -> Dictionary:
	for i in warm:
		await process_frame
	var ft: Array = []
	var gp: Array = []
	var cpu: Array = []
	var prim := 0.0
	var draws := 0.0
	var objs := 0.0
	for i in n:
		var t0 := Time.get_ticks_usec()
		await process_frame
		ft.append((Time.get_ticks_usec() - t0) / 1000.0)
		gp.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	ft.sort()
	gp.sort()
	cpu.sort()
	return {"frame_ms": ft[n / 2], "p95_ms": ft[int(n * 0.95)], "gpu_ms": gp[n / 2], "cpu_ms": cpu[n / 2], "prims": prim / n, "draws": draws / n, "objs": objs / n}


func _med(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func _run() -> void:
	var out_path := String(OS.get_cmdline_user_args()[0])
	await _boot()
	var dn := root.get_node_or_null("/root/DayNight")
	if dn:
		dn.flowing = false
		dn.set_hour(10.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var ov := (load("res://maps/village_v2/gen/district_b8p.scn") as PackedScene).instantiate() as Node3D
	ov.name = "DistrictB8P"
	vil.add_child(ov)
	for i in 4:
		await physics_frame
	var res := {"views": {}, "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.get_visible_rect().size), "items": int(ov.get_meta("items", 0)), "rounds": 3}
	print("[B8PP] 解像度 %s・%s・vsync off・max_fps 0・10:00；各鏡位 ON／OFF ×3（暖機 40＋測定 100 幀）" % [res["resolution"], res["renderer"]])
	for v: Array in PVIEWS:
		await _tpw(Vector2(v[1], v[2]), (Vector2(v[3], v[4]) - Vector2(v[1], v[2])).normalized())
		var st := {"ON": [], "OFF": []}
		for r in 3:
			for nm in ["ON", "OFF"]:
				ov.visible = nm == "ON"
				(st[nm] as Array).append(await _measure(vp, 40, 100))
		ov.visible = true
		var row := {}
		for key in ["frame_ms", "gpu_ms", "cpu_ms", "prims", "draws", "objs"]:
			for nm in ["ON", "OFF"]:
				row[nm.to_lower() + "_" + key] = _med([st[nm][0][key], st[nm][1][key], st[nm][2][key]])
			row["d_" + key] = float(row["on_" + key]) - float(row["off_" + key])
		res["views"][v[0]] = row
		print("[B8PP] %-12s ON−OFF：Δframe %+6.3f・Δgpu %+6.3f・Δcpu %+6.3f・Δdraws %+6.1f・Δprims %+9.0f・Δobjs %+6.1f  （ON frame %.2f／gpu %.2f／draws %.0f）" % [
			v[0], row["d_frame_ms"], row["d_gpu_ms"], row["d_cpu_ms"], row["d_draws"], row["d_prims"], row["d_objs"], row["on_frame_ms"], row["on_gpu_ms"], row["on_draws"]])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "\t") + "\n")
	f.close()
	print("[B8PP] DONE -> ", out_path)
	quit(0)
