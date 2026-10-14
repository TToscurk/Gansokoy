extends "res://tools/p13/w6/w6_base.gd"
## P13 Wave 7 TASK 4：DrapeFixP13 の一次・有界コスト比較（唯読・場景ファイルは書かない）。
##   godot --path . --resolution 1600x900 --script res://tools/p13/w7/w7_perf.gd -- <out.json>
## 通常のゲーム経路（main.tscn → ReviewStart → village_v2・実際の玩家と TPS 相機・10:00・Forward+）で、
##   DrapeFixP13.enabled の ON／OFF を ON,OFF,ON,OFF と交互に（1 回の測定＝暖機 40 幀＋測定 100 幀）、5 鏡位で比べる。
##   vsync off・max_fps 0（P8 の COST 測定と同じ方法）。GPU／CPU／draw calls／primitives／objects を記録。
##   ついでに overlay の読み込み・生成・套用の時間（ms）も測る（P12 の 3000 ms 問題は触れない）。
## 多輪の負荷試験ではない（各鏡位 ON×2・OFF×2 の 1 周だけ）。
const PVIEWS := [
	# [name, x, z, face_x, face_z, DrapeFix メッシュが視界にあるか]
	["sando_low", 296.4, -143.5, -0.258, -0.966, true],
	["sando_high", 279.8, -188.5, -0.476, -0.879, true],
	["waterwheel", 322.0, -62.0, 0.9990, 0.0366, true],
	["main_street", 257.2, -5.5, 0.316, -0.949, false],
	["farm_path3", 500.0, -30.5, 0.0, 1.0, false],
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
	var df := vil.get_node("DrapeFixP13")
	var res := {"views": {}, "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.get_visible_rect().size), "meshes_replaced": int(df.get("applied"))}
	# overlay の読み込み・生成・套用（ms）
	var path := "res://maps/village_v2/gen/drape_fix_p13.scn"
	var tl: Array = []
	var ti: Array = []
	for k in 3:
		var t0 := Time.get_ticks_usec()
		var ps := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var t1 := Time.get_ticks_usec()
		var inst := ps.instantiate()
		var t2 := Time.get_ticks_usec()
		tl.append((t1 - t0) / 1000.0)
		ti.append((t2 - t1) / 1000.0)
		inst.free()
	var ta: Array = []
	for k in 3:
		df.set("enabled", false)
		await process_frame
		var t3 := Time.get_ticks_usec()
		df.set("enabled", true)
		ta.append((Time.get_ticks_usec() - t3) / 1000.0)
		await process_frame
	res["overlay_load_ms"] = _med(tl)
	res["overlay_instantiate_ms"] = _med(ti)
	res["overlay_apply_ms"] = _med(ta)
	res["overlay_file_bytes"] = FileAccess.get_file_as_bytes(path).size()
	print("[W7P] overlay：load %.1f ms・instantiate %.1f ms・apply（%d meshes）%.2f ms・file %.2f MB" % [res["overlay_load_ms"], res["overlay_instantiate_ms"], res["meshes_replaced"], res["overlay_apply_ms"], float(res["overlay_file_bytes"]) / 1048576.0])
	print("[W7P] 解像度 %s・%s・vsync off・max_fps 0・10:00；各鏡位 ON,OFF,ON,OFF（暖機 40＋測定 100 幀）" % [res["resolution"], res["renderer"]])
	for v: Array in PVIEWS:
		await _tpw(Vector2(v[1], v[2]), Vector2(v[3], v[4]))
		var on: Array = []
		var off: Array = []
		for r in 2:
			df.set("enabled", true)
			on.append(await _measure(vp, 40, 100))
			df.set("enabled", false)
			off.append(await _measure(vp, 40, 100))
		df.set("enabled", true)
		var row := {"near_drape_meshes": v[5]}
		for key in ["frame_ms", "gpu_ms", "cpu_ms", "prims", "draws", "objs"]:
			row["on_" + key] = _med([on[0][key], on[1][key]])
			row["off_" + key] = _med([off[0][key], off[1][key]])
			row["d_" + key] = float(row["on_" + key]) - float(row["off_" + key])
		row["raw_on"] = on
		row["raw_off"] = off
		res["views"][v[0]] = row
		print("[W7P] %-12s Δframe %+6.3f ms・Δgpu %+6.3f ms・Δcpu %+6.3f ms・Δdraws %+5.1f・Δprims %+8.0f・Δobjs %+5.1f  （ON frame %.2f／gpu %.2f／draws %.0f／prims %.0f）" % [v[0], row["d_frame_ms"], row["d_gpu_ms"], row["d_cpu_ms"], row["d_draws"], row["d_prims"], row["d_objs"], row["on_frame_ms"], row["on_gpu_ms"], row["on_draws"], row["on_prims"]])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "\t") + "\n")
	f.close()
	print("[W7P] DONE -> ", out_path)
	quit(0)
