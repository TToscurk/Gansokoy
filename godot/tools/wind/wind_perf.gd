extends SceneTree
## Wind V1 效能比較：同一台機位，風開／關／再開（A/B/A）在獨立視窗（Forward+、VSync 關）。
##
##   Godot_v4.7.2-stable_win64_console.exe --path godot --disable-vsync \
##     --script res://tools/wind/wind_perf.gd -- --scene=village_v2 \
##     --views=res://tools/wind/views_village.json --out=C:/.../wind_v1/perf_village.json
##
## 量的是「幀間隔」（含 CPU＋GPU），不是純 GPU 時間；兩個模式的 draw call／primitive 必須相同，
## 因為風只改頂點著色器，沒有新增材質、沒有新增 draw call。
## A/B/A 是為了抵掉地圖升溫與背景負載漂移：off1 → on → off2，on 只跟兩次 off 的平均比。

const WARMUP := 45
const SAMPLE := 150
## A/B 交錯次數：off→on→off→on。單次量測的漂移（GPU 升溫、背景負載）可達 15 %，
## 交錯兩輪取平均後才看得出 shader 的真正成本。
const CYCLES := 2


func _init() -> void:
	_run.call_deferred()


func _arg(a: Array, key: String, dflt: String) -> String:
	for s: String in a:
		if s.begins_with(key + "="):
			return s.substr(key.length() + 1)
	return dflt


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var scene_id := _arg(a, "--scene", "village_v2")
	var views_path := _arg(a, "--views", "res://tools/wind/views_village.json")
	var out := _arg(a, "--out", "user://wind_perf.json")
	var only := PackedStringArray()
	if _arg(a, "--only", "") != "":
		only = _arg(a, "--only", "").split(",")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1280, 720)

	var wind := root.get_node_or_null("Wind")
	if wind == null:
		print("FAIL 找不到 Wind")
		quit(1)
		return
	wind.set_frozen(false)

	var map_path := "res://maps/village_v2/village_v2.tscn"
	if scene_id.begins_with("res://"):
		map_path = scene_id
	elif scene_id != "village_v2":
		map_path = "res://maps/beast_path/%s.tscn" % scene_id
	var ps := ResourceLoader.load(map_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var v: Node3D = ps.instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors", "Population"]:
		var n := v.get_node_or_null(nm)
		if n is Node3D:
			(n as Node3D).visible = false
	for n in v.find_children("*ParcelLines*", "", true, false):
		if n is Node3D:
			(n as Node3D).visible = false
	var day := root.get_node_or_null("DayNight")
	if day and day.has_method("set_hour"):
		day.set("flowing", false)
		day.set_hour(10.0)
	var weather := root.get_node_or_null("Weather")
	if weather and weather.has_method("set_weather"):
		weather.set_weather("clear")

	# --no-shadows：關掉所有 DirectionalLight 陰影（量陰影 pass 佔風成本多少；風開／關兩邊同樣關）
	if _arg(a, "--no-shadows", "0") == "1":
		for l in root.find_children("*", "DirectionalLight3D", true, false):
			(l as DirectionalLight3D).shadow_enabled = false
		print("[perf] DirectionalLight 陰影關閉")
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame

	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(views_path))
	var sp: PhysicsDirectSpaceState3D = v.get_world_3d().direct_space_state
	var rows := []
	for vw in views:
		if vw.size() > 1 and str(vw[1]) == "cloth":
			continue
		if not only.is_empty() and not (str(vw[0]) in only):
			continue
		if vw.size() > 1 and str(vw[1]) == "cam":
			cam.global_position = Vector3(float(vw[2]), float(vw[3]), float(vw[4]))
			cam.look_at(Vector3(float(vw[5]), float(vw[6]), float(vw[7])), Vector3.UP)
			cam.fov = float(vw[8]) if vw.size() > 8 else 55.0
		else:
			_aim(vw, sp, cam)
		for i in 6:
			await process_frame
		var off_ms := []
		var on_ms := []
		for cyc in int(_arg(a, "--cycles", str(CYCLES))):
			wind.set_enabled(false)
			await _settle()
			await _wait_gate_closed(wind)
			off_ms.append(await _measure("off"))
			wind.set_enabled(true)
			wind.set_preset(3)   # Strong Gust：最壞情況
			await _settle()
			on_ms.append(await _measure("gust"))
		wind.set_enabled(true)
		wind.set_preset(1)
		await _settle()
		var breeze: Dictionary = await _measure("breeze")
		var off_avg := 0.0
		for r: Dictionary in off_ms:
			off_avg += float(r["gpu_ms"])
		off_avg /= off_ms.size()
		var on_avg := 0.0
		for r: Dictionary in on_ms:
			on_avg += float(r["gpu_ms"])
		on_avg /= on_ms.size()
		for r: Dictionary in off_ms + on_ms:
			var row: Dictionary = r.duplicate()
			row["view"] = str(vw[0])
			row["scene"] = scene_id
			row["off_gpu_ms"] = off_avg
			row["delta_gpu_ms"] = float(row["gpu_ms"]) - off_avg
			row["delta_pct"] = 100.0 * float(row["delta_gpu_ms"]) / maxf(off_avg, 0.001)
			rows.append(row)
			print("%-14s %-6s gpu %6.2f ms  cpu %6.2f  frame %6.2f  phys %5.2f  proc %5.2f  draw %5d  prim %9d  Δgpu %+5.2f ms (%+5.1f %%)" % [
				str(vw[0]), str(row["wind"]), float(row["gpu_ms"]), float(row["cpu_ms"]),
				float(row["avg_ms"]), float(row["physics_ms"]), float(row["process_ms"]),
				int(row["draw_calls"]), int(row["primitives"]),
				float(row["delta_gpu_ms"]), float(row["delta_pct"])])
		var br: Dictionary = breeze.duplicate()
		br["view"] = str(vw[0])
		br["scene"] = scene_id
		br["off_gpu_ms"] = off_avg
		br["delta_gpu_ms"] = float(br["gpu_ms"]) - off_avg
		br["delta_pct"] = 100.0 * float(br["delta_gpu_ms"]) / maxf(off_avg, 0.001)
		rows.append(br)
		print("%-14s %-6s gpu %6.2f ms  cpu %6.2f  frame %6.2f  draw %5d  prim %9d  Δgpu %+5.2f ms (%+5.1f %%)" % [
			str(vw[0]), "breeze", float(br["gpu_ms"]), float(br["cpu_ms"]), float(br["avg_ms"]),
			int(br["draw_calls"]), int(br["primitives"]), float(br["delta_gpu_ms"]), float(br["delta_pct"])])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"scene": scene_id, "rows": rows}, "  "))
	f.close()
	print("perf -> ", out)
	var bad := 0
	var per_view := {}
	for r: Dictionary in rows:
		var vn: String = str(r["view"])
		if not per_view.has(vn):
			per_view[vn] = int(r["draw_calls"])
		elif int(r["draw_calls"]) != int(per_view[vn]):
			bad += 1
	if v.has_method("reset_dynamic"):
		# 有動態鬆動物的場景：物件會被剔除／進入視錐，draw call 本來就會 ±幾筆。
		print("INFO 動態場景 draw call 風開／關差 %d 個 view（葉子移動造成剔除變化，不是新材質）" % bad)
	else:
		print("%s draw call 在風開／關間不變（%d 個 view 不一致）" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(0)


func _settle() -> void:
	# 風場 tau=1.35 s：至少等 2 秒，量到的才是穩態（不是還在升的過渡）。
	for i in 120:
		await process_frame


## 「關風」量測前確認 shader 閘門真的關了：基礎風＝0 且陣風事件已清空（陣風增益 TAU_OFF 淡出約 3–4 s）。
## 只等固定幀數時，跑得快的版本（fps 高）會在事件還沒清空時就開始量 → off 基準被汙染、Δ 被低估。
func _wait_gate_closed(wind: Node) -> void:
	for i in 1200:
		if float(wind.get("_strength")) == 0.0 and (wind.get("_events") as Array).is_empty():
			break
		await process_frame
	for i in 10:
		await process_frame


func _measure(label: String) -> Dictionary:
	for i in WARMUP:
		await process_frame
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await process_frame
	var t := PackedFloat32Array()
	var g := PackedFloat32Array()
	var c := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	for i in SAMPLE:
		await process_frame
		var now := Time.get_ticks_usec()
		t.append((now - last) / 1000.0)
		last = now
		g.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		c.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	t.sort()
	g.sort()
	c.sort()
	var avg := 0.0
	for x in t:
		avg += x
	avg /= t.size()
	return {
		"wind": label,
		"avg_ms": avg,
		"p95_ms": t[int(t.size() * 0.95)],
		"fps": 1000.0 / maxf(avg, 0.001),
		"gpu_ms": g[int(g.size() * 0.5)],
		"gpu_p95_ms": g[int(g.size() * 0.95)],
		"cpu_ms": c[int(c.size() * 0.5)],
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	}


func _aim(vw: Array, sp: PhysicsDirectSpaceState3D, cam: Camera3D) -> void:
	var pp := Vector2(float(vw[1]), float(vw[2]))
	var tt := Vector2(float(vw[3]), float(vw[4]))
	var q := PhysicsRayQueryParameters3D.create(Vector3(pp.x, 60.0, pp.y), Vector3(pp.x, -40.0, pp.y))
	var gy := 0.0
	var ex: Array[RID] = []
	var first_y := 0.0
	for k in 12:
		q.exclude = ex
		var hit: Dictionary = sp.intersect_ray(q)
		if hit.is_empty():
			break
		if k == 0:
			first_y = hit.position.y
		if String((hit.collider as Node).name).begins_with("TerrainCollision"):
			gy = hit.position.y
			break
		ex.append(hit.rid)
	if gy == 0.0 and ex.size() > 0:
		gy = first_y
	var fwd := (tt - pp).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	var pitch := float(vw[5])
	var piv := Vector3(pp.x, gy + 1.6, pp.y) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
	var look := Vector3(fwd.x * cos(pitch), sin(pitch), fwd.y * cos(pitch))
	var cp := piv - look * float(vw[6]) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
	var qc := PhysicsRayQueryParameters3D.create(piv, cp)
	var hc: Dictionary = sp.intersect_ray(qc)
	if not hc.is_empty():
		cp = hc.position - (cp - piv).normalized() * 0.3
	cam.global_transform = Transform3D(Basis(), cp).looking_at(cp + look, Vector3.UP)
