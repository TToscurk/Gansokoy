extends "res://tools/p13/w6/w6_base.gd"
## P13 W9 Phase 3：A 主街・B 住宅巷・C 農家の一次・有界コスト比較（唯読・場景ファイルは書かない）。w9r2_p2_perf.gd と同じ方法。
##   godot --path . --resolution 1600x900 --script res://tools/p13/w9/w9p3_perf.gd -- <out.json>
## 通常のゲーム経路（main.tscn → ReviewStart → village_v2・実際の玩家と TPS 相機・10:00・Forward+）で、各鏡位を 3 状態 × 2 回（1 回＝暖機 40 幀＋測定 100 幀）：
##   ALL ：ArchW9R2P13 enabled（Phase 1–3 の建築）＋ EnrichW9P3 表示 ／ OFF：ArchW9R2P13 disabled（元の Kit）＋ EnrichW9P3 非表示 ／ P3ENV：EnrichW9P3 だけ表示（環境の単独コスト）
## vsync off・max_fps 0（P8 の COST 測定と同じ方法）。GPU／CPU／draw calls／primitives／objects の中央値。多輪の負荷試験ではない。
const PVIEWS := [
	["A_aT1", 289.7, -100.4, -0.9333, -0.3590],
	["A_aT2", 281.0, -80.1, 0.2542, -0.9672],
	["A_aT3", 294.9, -113.4, -0.4971, 0.8677],
	["B_bT1", 226.1, -90.3, 0.9657, 0.2597],
	["B_bT3", 235.8, -87.6, 0.2334, -0.9724],
	["B_bT4", 245.2, -85.3, 0.2696, -0.9630],
	["C_cT1", 344.0, 70.4, -0.9869, 0.1615],
	["C_cT3", 327.0, 90.5, -0.4614, -0.8872],
	["C_cT5", 331.5, 79.0, -0.9216, 0.3881],
	["C_cT7", 352.0, 70.6, -0.9980, 0.0635],
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


func _state(arch: Node3D, p3: Node3D, name: String) -> void:
	match name:
		"ALL":
			arch.set("enabled", true)
			p3.visible = true
		"OFF":
			arch.set("enabled", false)
			p3.visible = false
		"P3ENV":
			arch.set("enabled", false)
			p3.visible = true


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
	var arch := vil.get_node("ArchW9R2P13") as Node3D
	var p3 := vil.get_node("EnrichW9P3") as Node3D
	var res := {"views": {}, "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.get_visible_rect().size), "buildings": arch.get_child_count(), "p3_items": int(p3.get_meta("items", 0))}
	print("[W9P3P] 解像度 %s・%s・vsync off・max_fps 0・10:00；各鏡位 ALL／OFF／P3ENV ×2（暖機 40＋測定 100 幀）" % [res["resolution"], res["renderer"]])
	for v: Array in PVIEWS:
		await _tpw(Vector2(v[1], v[2]), Vector2(v[3], v[4]))
		var st := {"ALL": [], "OFF": [], "P3ENV": []}
		for r in 2:
			for nm in ["ALL", "OFF", "P3ENV"]:
				_state(arch, p3, nm)
				(st[nm] as Array).append(await _measure(vp, 40, 100))
		_state(arch, p3, "ALL")
		var row := {}
		for key in ["frame_ms", "gpu_ms", "cpu_ms", "prims", "draws", "objs"]:
			for nm in ["ALL", "OFF", "P3ENV"]:
				row[nm.to_lower() + "_" + key] = _med([st[nm][0][key], st[nm][1][key]])
			row["d_all_" + key] = float(row["all_" + key]) - float(row["off_" + key])
			row["d_p3env_" + key] = float(row["p3env_" + key]) - float(row["off_" + key])
		res["views"][v[0]] = row
		print("[W9P3P] %-10s ALL−OFF：Δframe %+6.3f・Δgpu %+6.3f・Δcpu %+6.3f・Δdraws %+6.1f・Δprims %+9.0f  ｜ P3ENV−OFF：Δgpu %+6.3f・Δdraws %+6.1f・Δprims %+8.0f  （ALL frame %.2f／gpu %.2f／draws %.0f）" % [
			v[0], row["d_all_frame_ms"], row["d_all_gpu_ms"], row["d_all_cpu_ms"], row["d_all_draws"], row["d_all_prims"], row["d_p3env_gpu_ms"], row["d_p3env_draws"], row["d_p3env_prims"], row["all_frame_ms"], row["all_gpu_ms"], row["all_draws"]])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "\t") + "\n")
	f.close()
	print("[W9P3P] DONE -> ", out_path)
	quit(0)
