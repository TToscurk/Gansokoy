extends SceneTree
## P9 R2 林帶 runtime 成本 A/B（Forward+ 正式 benchmark；不改 village_v2.tscn）。
## 林帶 overlay（maps/village_v2/gen/forest_p9.scn）只在本程序內臨時掛到 Vegetation 下：
##   ON  ＝ R2 林帶可見、六塊 P0 placeholder 隱藏（＝R2 掛載後的實際狀態）
##   OFF ＝ R2 林帶隱藏、六塊 placeholder 可見（＝目前正式村落）
## 量法與 P8 --cost 相同：1920×1061、vsync off、max_fps 0、10:00；同鏡位 ON／OFF 交替 N 輪（預設 3），每態暖機 60 幀、量 150 幀；
##   GPU／frame 取中位數，Δ 取各輪中位數。
## P9 效能 guardrail（規劃 §31）：一般玩家鏡位 GPU Δ ≤ 3 ms；forest 鏡位 ≤ 4.5 ms；render CPU Δ ≤ 3 ms。
## 前提：R2 overlay 有 15k+ 個 instance-uniform 節點，需 rendering/limits/global_shader_variables/buffer_size ≥ 節點 × 16；
##   benchmark 時以暫時 override.cfg 提供（不改 project.godot），本腳本開頭檢查設定值。
## 用法：Godot --rendering-method forward_plus --path . --resolution 1920x1080 --script res://tools/verify_village_v2_forest_cost.gd -- [--rounds=5]
const FLib := preload("res://tools/village_v2_forest_lib.gd")
const BUDGET_GPU_GENERAL := 3.0
const BUDGET_GPU_FOREST := 4.5
const BUDGET_CPU := 3.0
# [名稱, 類別, 站位 x, z, 看向 x, z, pitch, 相機距離]
const VIEWS := [
	["T1_eye", "general", 392.0, 100.0, 418.0, 120.0, -0.10, 5.0],
	["N2_eye", "general", 455.0, -3.0, 465.0, -40.0, -0.10, 5.0],
	["S2_road", "general", 447.6, 66.0, 465.0, 40.0, -0.10, 5.0],
	["Hieda_front", "general", 398.0, -6.0, 398.0, 20.0, -0.15, 8.5],
	["High_overlook", "general", 420.0, 150.0, 450.0, 60.0, -0.55, 16.0],
	["Main_north", "general", 241.0, 44.0, 276.0, -70.0, -0.05, 5.0],
	["West_edge", "forest", 125.0, -10.0, 40.0, -10.0, -0.05, 5.0],
	["West_edge_s", "forest", 118.0, 45.0, 40.0, 90.0, -0.05, 5.0],
	["SW_out", "forest", 200.0, 110.0, 100.0, 170.0, -0.05, 5.0],
	["Hill_approach", "forest", 289.0, -172.0, 266.0, -222.0, -0.02, 5.0],
	["North_ridge", "forest", 360.0, -150.0, 330.0, -270.0, -0.05, 5.0],
	["Forest_overlook", "forest", 280.0, 20.0, 280.0, -150.0, -0.45, 16.0],
]
var main: Node
var player: CharacterBody3D
var fails := 0
var stale := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var rounds := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.substr(9))
	var buf := int(ProjectSettings.get_setting("rendering/limits/global_shader_variables/buffer_size", 65536))
	print("[FCOST] renderer %s、instance uniform buffer_size %d" % [ProjectSettings.get_setting("rendering/renderer/rendering_method"), buf])
	var flags := root.get_node("/root/StoryFlags")
	flags.set_flag("woke_in_trail", true)
	flags.set_flag("met_reimu", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 60:
		await process_frame
	main.load_map("village_v2", "trail")
	for i in 90:
		await process_frame
	player = main.player
	var veg := main.map_root.get_node_or_null("Vegetation") as Node3D
	if player == null or veg == null:
		push_error("[FCOST] map/player/Vegetation missing")
		quit(2)
		return
	var debug: Node = main.map_root.get_node_or_null("Debug")
	if debug:
		debug.visible = false
	var ph: Array = []
	for c in veg.get_children():
		if String(c.name).begins_with("Forest_"):
			ph.append(c)
	# 鏡位地面高先量（林帶樹幹碰撞掛上前），避免射線打到樹幹
	var ys := {}
	for v: Array in VIEWS:
		ys[v[0]] = _ground(v[2], v[3])
	var forest := (load(FLib.OUTPUT) as PackedScene).instantiate() as Node3D
	var nodes := forest.find_children("*", "GeometryInstance3D", true, false).size()
	if nodes * 16 > buf:
		push_error("[FCOST] instance uniform 節點 %d × 16 > buffer_size %d（Forward+ 會溢位、葉子發白）→ 不量" % [nodes, buf])
		quit(2)
		return
	veg.add_child(forest)
	print("[FCOST] R2 overlay：GeometryInstance %d、placeholder %d 塊" % [nodes, ph.size()])
	await _cost(forest, ph, ys, rounds)
	if stale > 0:
		print("[FCOST] 結果：INVALID（%d 次量測視窗未繪製），本次數字不得採用" % stale)
		quit(3)
		return
	print("[FCOST] 結果：%d 項失敗（P9 runtime guardrail）" % fails)
	quit(1 if fails > 0 else 0)

func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60.0, z), Vector3(x, -30.0, z))
	q.exclude = [player.get_rid()]
	var r := player.get_world_3d().direct_space_state.intersect_ray(q)
	return NAN if r.is_empty() else (r["position"] as Vector3).y

func _state(forest: Node3D, ph: Array, on: bool) -> void:
	forest.visible = on
	for p in ph:
		(p as Node3D).visible = not on

func _measure(vp: RID, warm: int, n: int) -> Dictionary:
	for i in warm:
		await process_frame
	var ft: Array = []
	var gp: Array = []
	var cpu := 0.0
	var prim := 0.0
	var draws := 0.0
	for i in n:
		var t0 := Time.get_ticks_usec()
		await process_frame
		ft.append((Time.get_ticks_usec() - t0) / 1000.0)
		gp.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	ft.sort()
	gp.sort()
	# 視窗被最小化／遮蔽時引擎停畫：GPU 計時整段不變 → 本次量測無效（整支 exit 3，不得採用數字）
	if is_equal_approx(gp[0], gp[n - 1]):
		stale += 1
		push_error("[FCOST] STALE：%d 幀 GPU 計時完全相同（%.3f ms）→ 視窗未繪製，量測無效" % [n, gp[0]])
	return {"frame": ft[n / 2], "p95": ft[int(n * 0.95)], "gpu": gp[n / 2], "cpu": cpu / n, "prims": prim / n, "draws": draws / n}

func _med(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]

## 診斷變體（--variants=a,b）：與 normal 同輪交替量，回報各自對 OFF 的 Δ 與相對 normal 的差。量完一律還原。
## noshadow：林帶全部 GeometryInstance cast_shadow＝OFF（只量 shadow pass 佔比，不是正式方案）
func _apply_variant(forest: Node3D, name: String) -> Array:
	var undo: Array = []
	match name:
		"normal":
			pass
		"noshadow":
			for g in forest.find_children("*", "GeometryInstance3D", true, false):
				var gi := g as GeometryInstance3D
				undo.append([gi, "cast_shadow", gi.cast_shadow])
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"far3off", "shpolicy":
			# far3off：遠級 LOD3（MultiMesh）不投影
			# shpolicy：＋遠級 LOD2 的幼樹／枯木不投影＋近級 LOD1 的下層（layer under）不投影；近級 LOD0 全保留
			var small := FLib.YOUNG_IDS + ["snag_a", "log_a"]
			for g in forest.find_children("*", "GeometryInstance3D", true, false):
				var gi := g as GeometryInstance3D
				if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					continue
				var path := String(forest.get_path_to(gi))
				var off := false
				if path.begins_with("Far/LOD3/"):
					off = true
				elif name == "shpolicy" and path.begins_with("Far/LOD2/") and String(gi.get_meta("veg_id", "")) in small:
					off = true
				elif name == "shpolicy" and path.begins_with("Near/") and String(gi.name) == "LOD1" \
						and String(gi.get_parent().get_meta("layer", "")) == "under":
					off = true
				if off:
					undo.append([gi, "cast_shadow", gi.cast_shadow])
					gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			print("[FCOST]   變體 %s：關閉投影 %d 個節點" % [name, undo.size()])
		"sh_n0", "sh_n1", "sh_f2", "sh_f3":
			# 單級投影關閉（拆 shadow pass 成本歸屬）：近級 LOD0／LOD1、遠級 LOD2／LOD3
			for g in forest.find_children("*", "GeometryInstance3D", true, false):
				var gi := g as GeometryInstance3D
				if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					continue
				var path := String(forest.get_path_to(gi))
				var hit := false
				match name:
					"sh_n0": hit = path.begins_with("Near/") and String(gi.name) == "LOD0"
					"sh_n1": hit = path.begins_with("Near/") and String(gi.name) == "LOD1"
					"sh_f2": hit = path.begins_with("Far/LOD2/")
					"sh_f3": hit = path.begins_with("Far/LOD3/")
				if hit:
					undo.append([gi, "cast_shadow", gi.cast_shadow])
					gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_:
			push_error("[FCOST] 未知變體 " + name)
	return undo

func _undo(undo: Array) -> void:
	for u: Array in undo:
		(u[0] as Object).set(u[1], u[2])

func _cost(forest: Node3D, ph: Array, ys: Dictionary, rounds: int) -> void:
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var dn := root.get_node_or_null("/root/DayNight")
	if dn:
		dn.flowing = false
		dn.set_hour(10.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var adapter := player.get_node("CameraAdapter")
	var only: Array = []
	var variants: Array = ["normal"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--views="):
			only = Array(a.substr(8).split(","))
		elif a.begins_with("--variants="):
			variants += Array(a.substr(11).split(","))
	print("[FCOST] 解析度 %s、vsync off、max_fps 0、10:00；%s／OFF 交替 %d 輪，每態暖機 60 幀、量 150 幀；GPU／frame 取中位數，Δ 取 %d 輪中位數" % [str(root.get_visible_rect().size), "／".join(variants), rounds, rounds])
	for v: Array in VIEWS:
		if not only.is_empty() and not (v[0] in only):
			continue
		var at := Vector2(v[2], v[3])
		var d := Vector2(v[4], v[5]) - at
		var yaw := atan2(-d.x, -d.y)
		player.global_position = Vector3(at.x, float(ys[v[0]]) + 0.05, at.y)
		player.velocity = Vector3.ZERO
		player.snap_yaw(yaw)
		for i in 20:
			await physics_frame
		adapter._target_yaw = yaw
		adapter._current_yaw = yaw
		adapter._target_pitch = v[6]
		adapter._current_pitch = v[6]
		adapter._target_distance = v[7]
		adapter._current_distance = v[7]
		var on := {}
		for vn in variants:
			on[vn] = []
		var off: Array = []
		for r in rounds:
			for vn: String in variants:
				_state(forest, ph, true)
				var undo := _apply_variant(forest, vn)
				(on[vn] as Array).append(await _measure(vp, 60, 150))
				_undo(undo)
			_state(forest, ph, false)
			off.append(await _measure(vp, 60, 150))
		_state(forest, ph, false)
		var keys := ["gpu", "cpu", "frame", "prims", "draws"]
		var moff := {}
		for k in keys:
			moff[k] = _med(off.map(func(x: Dictionary) -> float: return x[k]))
		print("[FCOST] %-15s %-7s OFF        median frame %.2f  renderCPU %.2f  GPU %.2f  prims %.0fk  draws %d" % [v[0], v[1], moff["frame"], moff["cpu"], moff["gpu"], moff["prims"] / 1000.0, int(moff["draws"])])
		var dg_normal := 0.0
		for vn: String in variants:
			var arr: Array = on[vn]
			var mon := {}
			for k in keys:
				mon[k] = _med(arr.map(func(x: Dictionary) -> float: return x[k]))
			var dg: Array = []
			var dc: Array = []
			for r in rounds:
				dg.append(arr[r]["gpu"] - off[r]["gpu"])
				dc.append(arr[r]["cpu"] - off[r]["cpu"])
			var dgm := _med(dg)
			var dcm := _med(dc)
			dg.sort()
			print("[FCOST] %-15s %-7s ON %-8s median frame %.2f  renderCPU %.2f  GPU %.2f  prims %.0fk  draws %d" % [v[0], v[1], vn, mon["frame"], mon["cpu"], mon["gpu"], mon["prims"] / 1000.0, int(mon["draws"])])
			if vn == "normal":
				dg_normal = dgm
				var lim := BUDGET_GPU_FOREST if v[1] == "forest" else BUDGET_GPU_GENERAL
				var ok := dgm <= lim and dcm <= BUDGET_CPU
				if not ok:
					fails += 1
				print("[FCOST] %s %-15s Δ GPU %+.2f（上限 %.1f；各輪 %s）  renderCPU %+.2f（上限 %.0f）  prims %+.0fk  draws %+d" % ["PASS" if ok else "FAIL",
					v[0], dgm, lim, " / ".join(dg.map(func(x: float) -> String: return "%+.2f" % x)), dcm, BUDGET_CPU,
					(mon["prims"] - moff["prims"]) / 1000.0, int(mon["draws"] - moff["draws"])])
			else:
				print("[FCOST] DIAG %-15s %-8s Δ GPU %+.2f（各輪 %s；相對 normal %+.2f）  renderCPU %+.2f  prims %+.0fk  draws %+d" % [v[0], vn, dgm,
					" / ".join(dg.map(func(x: float) -> String: return "%+.2f" % x)), dgm - dg_normal, dcm,
					(mon["prims"] - moff["prims"]) / 1000.0, int(mon["draws"] - moff["draws"])])
