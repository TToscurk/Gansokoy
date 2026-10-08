extends SceneTree
## P10 R5–R6 施工：效能量測（非 headless、Forward+、10:00、VSync 關）。只讀，不存場景。
##   Godot --path . --script res://tools/perf_village_v2_rehab.gd -- <views.json> <out.json> [toggle=<NodePath>[,<NodePath>…]] [pairs=2]
## views 與 shot_village_v2_rehab_audit.gd 同格式。每個機位：暖機 90 幀 → 量 120 幀（root viewport GPU 時間、CPU 渲染時間、
## draw calls、primitives 的中位數）。toggle 指定時同機位 ON／OFF 交替量 pairs 對（ABAB），取各自中位數 → 差＝該節點成本。
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	for n in v.get_node("Districts").find_children("*ParcelLines*", "", true, false):
		n.visible = false
	await process_frame
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.set_hour(10.0)
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var out: String = a[1]
	var toggle := ""
	var pairs := 2
	for s: String in a:
		if s.begins_with("toggle="):
			toggle = s.trim_prefix("toggle=")
		elif s.begins_with("pairs="):
			pairs = s.trim_prefix("pairs=").to_int()
	# toggle 可用逗號列多個節點（P10 R5–R6 全部 pilot 一起 ON／OFF）；有 enabled 屬性的材質覆寫類 → 切 enabled
	var gs: Array = []
	for t in toggle.split(",", false):
		var nd := v.get_node_or_null(t)
		if nd:
			gs.append(nd)
	var g: Node3D = gs[0] if not gs.is_empty() else null
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 1200.0
	root.add_child(cam)
	cam.make_current()
	var sp := v.get_world_3d().direct_space_state
	for i in 60:
		await process_frame
	var res := {"renderer": RenderingServer.get_current_rendering_method(), "toggle": toggle, "pairs": pairs, "views": {}}
	for vw in views:
		_place(cam, sp, vw)
		var rec := {}
		var states := ["on", "off"] if g else ["on"]
		var acc := {"on": [], "off": []}
		for p in (pairs if g else 1):
			for stt in states:
				if g:
					for gg in gs:
						if "enabled" in gg:
							gg.set("enabled", stt == "on")
						else:
							(gg as Node3D).visible = (stt == "on")
				for i in 90:
					await process_frame
				var gpu := []
				var cpu := []
				var dc := []
				var pr := []
				for i in 120:
					await process_frame
					gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
					cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
					dc.append(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
					pr.append(RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
				acc[stt].append({"gpu_ms": _med(gpu), "cpu_ms": _med(cpu), "draw_calls": _med(dc), "primitives": _med(pr)})
		for stt in states:
			var arr: Array = acc[stt]
			rec[stt] = {"gpu_ms": snappedf(_med(arr.map(func(x): return x["gpu_ms"])), 0.001), "cpu_ms": snappedf(_med(arr.map(func(x): return x["cpu_ms"])), 0.001),
				"draw_calls": int(_med(arr.map(func(x): return x["draw_calls"]))), "primitives": int(_med(arr.map(func(x): return x["primitives"]))), "runs": arr}
		if g:
			rec["delta_gpu_ms"] = snappedf(rec["on"]["gpu_ms"] - rec["off"]["gpu_ms"], 0.001)
			rec["delta_draw_calls"] = rec["on"]["draw_calls"] - rec["off"]["draw_calls"]
			rec["delta_primitives"] = rec["on"]["primitives"] - rec["off"]["primitives"]
		res["views"][str(vw[0])] = rec
		print("[PERF] %s %s" % [vw[0], JSON.stringify(rec).left(300)])
	if g:
		for gg in gs:
			if "enabled" in gg:
				gg.set("enabled", true)
			else:
				(gg as Node3D).visible = true
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "\t"))
	f.close()
	quit()

func _med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])

func _place(cam: Camera3D, sp: PhysicsDirectSpaceState3D, vw: Array) -> void:
	if typeof(vw[1]) == TYPE_STRING and str(vw[1]) == "free":
		cam.fov = float(vw[8])
		var cp := Vector3(float(vw[2]), float(vw[3]), float(vw[4]))
		cam.global_transform = Transform3D(Basis(), cp).looking_at(Vector3(float(vw[5]), float(vw[6]), float(vw[7])), Vector3.UP)
		return
	cam.fov = 70.0
	var pp := Vector2(float(vw[1]), float(vw[2]))
	var tt := Vector2(float(vw[3]), float(vw[4]))
	var q := PhysicsRayQueryParameters3D.create(Vector3(pp.x, 120.0, pp.y), Vector3(pp.x, -40.0, pp.y))
	var gy := 0.0
	var ex: Array[RID] = []
	for k in 16:
		q.exclude = ex
		var hit := sp.intersect_ray(q)
		if hit.is_empty():
			break
		if String((hit.collider as Node).name).begins_with("TerrainCollision"):
			gy = hit.position.y
			break
		ex.append(hit.rid)
	var f := (tt - pp).normalized()
	var side := Vector2(-f.y, f.x)
	var pitch := float(vw[5])
	var piv := Vector3(pp.x, gy + 1.6, pp.y) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
	var look := Vector3(f.x * cos(pitch), sin(pitch), f.y * cos(pitch))
	var cp2 := piv - look * float(vw[6]) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
	cam.global_transform = Transform3D(Basis(), cp2).looking_at(cp2 + look, Vector3.UP)
