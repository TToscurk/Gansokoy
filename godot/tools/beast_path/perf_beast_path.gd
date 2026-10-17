extends SceneTree
## 效能基準（非 headless、真渲染）：正式 main.tscn 載 beast_path，把玩家放到幾個代表位置，量 FPS／draw call／面數／物件數。
##   godot --path godot --script res://tools/beast_path/perf_beast_path.gd -- --map=beast_path [--out=<json>] [--only=S04_arena_center,...] [--hide=<組1>|<組2>]
## --hide：隔離量測（找瓶頸）。每組是逗號分隔的名稱子字串或 meta:<鍵>；每個位置先量全開，再逐組隱藏後量，量完還原。
## --exp=a,b：執行期實驗（量完還原）：rock_shadow_off（岩石不投影）／cheap_ground（S04 地面換簡單材質）／forest_shadow_off（森林不投影）／rock_vis150（岩石可視距離 150 m）。
## 　S01 拆解用（R1 起）：cheap_ground_s01（S01 地面換簡單材質）／forest_off_s01（隱藏 S01 森林）；（R2 加）s01_forest_shadow_off（只 S01 森林不投影）／s01_forest_hide（＝forest_off_s01）。
## 只量，不最佳化（最佳化＝T27）。FPS 關垂直同步後量，所以是這台機器上的上限值。
const BP := preload("res://tools/beast_path/bp_lib.gd")

var vp_rid: RID
var main: Node
var player: CharacterBody3D
var adapter: Node
var lib: BP


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var out := ""
	var only: PackedStringArray = []
	var hide_sets: Array = []
	var exps: PackedStringArray = []
	var reps := 1
	var warm := 150
	var hour := 10.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
		elif a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
		elif a.begins_with("--rep="):
			reps = maxi(int(a.trim_prefix("--rep=")), 1)
		elif a.begins_with("--warm="):
			warm = maxi(int(a.trim_prefix("--warm=")), 30)
		elif a.begins_with("--exp="):
			exps = a.trim_prefix("--exp=").split(",")
		elif a.begins_with("--hide="):
			for g in a.trim_prefix("--hide=").split("|"):
				hide_sets.append(g.split(","))
	lib = BP.new()
	lib.setup(true, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	vp_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)       # V1.2 G：GPU／CPU 渲染毫秒（每幀實測）
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		if player and String(main.get("current_id")) == "beast_path" and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 120000:
			quit(2)
			return
	adapter = player.get_node("CameraAdapter")
	# 凍結遊戲內時鐘（與 tps_shots.gd 相同）。時鐘在走時太陽角度一直變 → 陰影 cascade 內的投影物集合隨時間變 →
	# 同一個畫面 draw call／FPS 會漂移 10 % 以上（V1.2 實測 82.8→90.2 FPS，相機完全不動）；V1.1 以前的 A/B 沒凍結，量測值含時鐘位置的變因。
	var dn := root.get_node_or_null("DayNight")
	if dn != null:
		dn.set("flowing", false)
		dn.call("set_hour", hour)
	print("[PERF] 時鐘凍結：DayNight=%s hour=%.1f" % [str(dn != null), hour])
	for _i in 3:
		await process_frame
	for lt in root.find_children("*", "DirectionalLight3D", true, false):
		var dl := lt as DirectionalLight3D
		print("[PERF] 光源 %s：仰角 %.1f°、能量 %.2f、陰影 %s、可見 %s、shadow_max_distance %.0f m、mode %d" % [String(dl.get_path()), rad_to_deg(asin(clampf(dl.global_transform.basis.z.y, -1.0, 1.0))), dl.light_energy, str(dl.shadow_enabled), str(dl.is_visible_in_tree()), dl.directional_shadow_max_distance, dl.directional_shadow_mode])
	var spots := [
		["S01_spawn", "village", 20.0],
		["S01_torii", "torii", -6.0],
		["S02_forest_gate", "forest_gate", 0.0],
		["S02_corridor", "corridor", 6.0],
		["S02_bridge", "bridge_s", 2.0],
		["S03_fork", "fork", -4.0],
		["S03_north", "north_a", 4.0],
		["S04_threshold", "buffer_s", 2.0],
		["S04_arena_center", "arena_s", -12.0],
	]
	var res: Array = []
	for sp: Array in spots:
		if not only.is_empty() and not only.has(String(sp[0])):
			continue
		var s := lib.st_s(String(sp[1])) + float(sp[2])
		var p := lib.main.pos_at(s)
		var t := lib.main.tan_at(s)
		await _put(p, atan2(-t.x, -t.y))
		for i in warm:
			await process_frame
		var m: Dictionary = await _measure(300)
		if reps > 1:
			# 重複量測：管線在背景逐步編譯特化版本，剛進場的幾秒偏慢。印出每一次，記錄用中位數
			var fl: Array = [m["fps"]]
			var line := "%.1f" % float(m["fps"])
			var cam0 := get_root().get_camera_3d()
			print("[PERF]   相機 #0 pos %s  fwd %s  fov %.1f" % [str(cam0.global_position.snapped(Vector3.ONE * 0.01)), str((-cam0.global_basis.z).snapped(Vector3.ONE * 0.001)), cam0.fov])
			for r in reps - 1:
				var m2: Dictionary = await _measure(300)
				fl.append(m2["fps"])
				line += " %.1f" % float(m2["fps"])
				m = m2
				var camr := get_root().get_camera_3d()
				print("[PERF]   相機 #%d pos %s  fwd %s  fov %.1f  draw %d  面 %.0fk" % [r + 1, str(camr.global_position.snapped(Vector3.ONE * 0.01)), str((-camr.global_basis.z).snapped(Vector3.ONE * 0.001)), camr.fov, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000.0])
			print("[PERF]   重複 %s：%s" % [sp[0], line])
			fl.sort()
			m["fps"] = fl[fl.size() / 2]
		var rec := {
			"spot": sp[0],
			"fps_avg": m["fps"],
			"ms_avg": m["ms"],
			"ms_p95": m["p95"],
			"gpu_ms": m["gpu"],
			"cpu_ms": m["cpu"],
			"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"primitives_k": snappedf(float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000.0, 1),
			"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"vram_mb": snappedf(float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0, 1),
		}
		res.append(rec)
		print("[PERF] %-18s fps %6.1f  幀 %5.2f ms（p95 %5.2f）GPU %5.2f CPU %5.2f  draw %5d  面 %7.1fk  物件 %5d  節點 %6d  VRAM %.0f MB" % [sp[0], rec["fps_avg"], rec["ms_avg"], rec["ms_p95"], rec["gpu_ms"], rec["cpu_ms"], rec["draw_calls"], rec["primitives_k"], rec["objects"], rec["nodes"], rec["vram_mb"]])
		var hi := 0
		for hs: PackedStringArray in hide_sets:
			hi += 1
			var hidden := _hide_matching(hs)
			for i in 60:
				await process_frame
			var mh: Dictionary = await _measure(240)
			var fh: float = mh["fps"]
			print("[PERF]   └ 隔離 h%d [%s] 隱藏 %d 節點：fps %6.1f（%+.1f%%）  draw %5d  面 %7.1fk" % [hi, ",".join(hs), hidden.size(), fh, (fh - float(rec["fps_avg"])) / float(rec["fps_avg"]) * 100.0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000.0])
			rec["hide_%d" % hi] = {"set": ",".join(hs), "n": hidden.size(), "fps": fh, "gpu_ms": mh["gpu"], "ms": mh["ms"]}
			for n3: Node3D in hidden:
				n3.visible = true
		for ex in exps:
			var undo := _apply_exp(ex)
			for i in 60:
				await process_frame
			var me: Dictionary = await _measure(240)
			var fe: float = me["fps"]
			print("[PERF]   └ 實驗 %-18s：fps %6.1f（%+.1f%%）  draw %5d  面 %7.1fk" % [ex, fe, (fe - float(rec["fps_avg"])) / float(rec["fps_avg"]) * 100.0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000.0])
			rec["exp_" + ex] = fe
			rec["exp_" + ex + "_gpu_ms"] = me["gpu"]
			rec["exp_" + ex + "_ms"] = me["ms"]
			undo.call()
	var gpu := RenderingServer.get_video_adapter_name()
	print("[PERF] GPU：%s  renderer：%s" % [gpu, ProjectSettings.get_setting("rendering/renderer/rendering_method")])
	if out != "":
		var f2 := FileAccess.open(out, FileAccess.WRITE)
		f2.store_string(JSON.stringify({"gpu": gpu, "spots": res}, "\t") + "\n")
		f2.close()
	quit(0)


## 每幀實測時間（process_frame 之間的 µs）。Performance.TIME_FPS 每秒才更新一次，120 幀只取得 1~2 個樣本，同一版本重跑差 ±5 %，不能拿來做 A/B。
func _measure(frames: int) -> Dictionary:
	var dts := PackedFloat64Array()
	var gpu := 0.0
	var cpu := 0.0
	var t_prev := Time.get_ticks_usec()
	for i in frames:
		await process_frame
		var t_now := Time.get_ticks_usec()
		dts.append(float(t_now - t_prev) / 1000.0)
		t_prev = t_now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
	var tot := 0.0
	for d in dts:
		tot += d
	var srt := dts.duplicate()
	srt.sort()
	var mean := tot / float(frames)
	return {"fps": snappedf(1000.0 / mean, 0.1), "ms": snappedf(mean, 0.01), "p95": snappedf(srt[int(float(frames) * 0.95)], 0.01), "gpu": snappedf(gpu / float(frames), 0.01), "cpu": snappedf(cpu / float(frames), 0.01)}


func _rock_meshes() -> Array[MeshInstance3D]:
	var r: Array[MeshInstance3D] = []
	for n in main.find_children("*", "MeshInstance3D", true, false):
		var par := n.get_parent()
		if par != null and (par.has_meta("bp_slab") or par.has_meta("bp_rock_r")):
			r.append(n as MeshInstance3D)
	return r


func _apply_exp(name: String) -> Callable:
	match name:
		"rock_shadow_off":
			var ms := _rock_meshes()
			var old_r: Array = []
			for m in ms:
				old_r.append(m.cast_shadow)                      # 還原成「原本的值」（V1.1 起小石頭本來就不投影，不能一律還原成 ON）
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return func() -> void:
				for i in ms.size():
					ms[i].cast_shadow = old_r[i]
		"meadow_shadow_off":
			var mm: Array = []
			var old_m: Array = []
			for g in main.find_children("*", "MultiMeshInstance3D", true, false):
				if g.get_parent() != null and g.get_parent().get_parent() != null and String(g.get_parent().get_parent().name) == "MeadowS04":
					mm.append(g)
					old_m.append((g as GeometryInstance3D).cast_shadow)
					(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			print("[PERF]     （meadow_shadow_off 影響 %d 個 MultiMesh）" % mm.size())
			return func() -> void:
				for i in mm.size():
					(mm[i] as GeometryInstance3D).cast_shadow = old_m[i]
		"rock_vis150":
			var ms2 := _rock_meshes()
			for m in ms2:
				m.visibility_range_end = 150.0
			return func() -> void:
				for m in ms2:
					m.visibility_range_end = 0.0
		"forest_shadow_off":
			var gs: Array = []
			var old: Array = []
			for fnode in main.find_children("Forest", "Node3D", true, false):
				for g in fnode.find_children("*", "GeometryInstance3D", true, false):
					gs.append(g)
					old.append((g as GeometryInstance3D).cast_shadow)
					(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return func() -> void:
				for i in gs.size():
					(gs[i] as GeometryInstance3D).cast_shadow = old[i]
		"forest_shadow_off_s04", "forest_shadow_off_other", "forest_shadow_far60", "forest_shadow_far45", "forest_shadow_far80":
			# 森林陰影細分：S04 自己的樹／其他區（S01–S03）的樹／S04 離場中心超過 R m 的樹
			var c0 := lib.arena_c()
			var far_r := 60.0
			if name == "forest_shadow_far45":
				far_r = 45.0
			elif name == "forest_shadow_far80":
				far_r = 80.0
			var gs2: Array = []
			var old2: Array = []
			for fnode in main.find_children("Forest", "Node3D", true, false):
				var is_s04 := String(fnode.get_parent().name).begins_with("S04")
				if name == "forest_shadow_off_s04" and not is_s04:
					continue
				if name == "forest_shadow_off_other" and is_s04:
					continue
				for ch in fnode.get_children():
					var c3 := ch as Node3D
					if c3 == null:
						continue
					if name.begins_with("forest_shadow_far"):
						if not is_s04:
							continue
						if Vector2(c3.global_position.x, c3.global_position.z).distance_to(c0) < far_r:
							continue
					for g in c3.find_children("*", "GeometryInstance3D", true, false):
						gs2.append(g)
						old2.append((g as GeometryInstance3D).cast_shadow)
						(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			print("[PERF]     （%s 影響 %d 個幾何體）" % [name, gs2.size()])
			return func() -> void:
				for i in gs2.size():
					(gs2[i] as GeometryInstance3D).cast_shadow = old2[i]
		"shadow_kind_under", "shadow_kind_tree", "shadow_kind_under_far25":
			# S04 的森林實例依 bp_kind 分類關閉陰影：under＝下層植被（灌木／羊歯）、tree＝喬木（含 pin／landmark）
			var c1 := lib.arena_c()
			var want_under := name.begins_with("shadow_kind_under")
			var gs3: Array = []
			var old3: Array = []
			for fnode in main.find_children("Forest", "Node3D", true, false):
				if not String(fnode.get_parent().name).begins_with("S04"):
					continue
				for ch in fnode.get_children():
					var c3 := ch as Node3D
					if c3 == null:
						continue
					var kd := String(c3.get_meta("bp_kind", ""))
					var is_under := kd == "under"
					var is_tree := kd == "tree" or kd == "pin" or kd == "landmark"
					if want_under != is_under or (not want_under and not is_tree):
						continue
					if name == "shadow_kind_under_far25" and Vector2(c3.global_position.x, c3.global_position.z).distance_to(c1) < 25.0:
						continue
					for g in c3.find_children("*", "GeometryInstance3D", true, false):
						gs3.append(g)
						old3.append((g as GeometryInstance3D).cast_shadow)
						(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			print("[PERF]     （%s 影響 %d 個幾何體）" % [name, gs3.size()])
			return func() -> void:
				for i in gs3.size():
					(gs3[i] as GeometryInstance3D).cast_shadow = old3[i]
		"ring_hide":
			# 場中心 20–32 m 環帶內的森林實例（量「林緣貼近空地」的成本）
			var c0 := lib.arena_c()
			var hid: Array[Node3D] = []
			for fnode in main.find_children("Forest", "Node3D", true, false):
				if not String(fnode.get_parent().name).begins_with("S04"):
					continue
				for ch in fnode.get_children():
					var c3 := ch as Node3D
					var d := Vector2(c3.global_position.x, c3.global_position.z).distance_to(c0)
					if d >= 20.0 and d < 32.0 and c3.visible:
						c3.visible = false
						hid.append(c3)
			print("[PERF]     （ring_hide 隱藏 %d 棵）" % hid.size())
			return func() -> void:
				for c3: Node3D in hid:
					c3.visible = true
		"cheap_ground_s01":
			# S01 R1 實驗：S01 地面換成最簡單的材質，量專用地表 shader 的成本
			var tm1: MeshInstance3D = null
			for n1 in main.find_children("TerrainMesh", "MeshInstance3D", true, false):
				var par1 := n1.get_parent()
				if par1 != null and (String(par1.name).begins_with("S01") or String(par1.get_meta("bp_scene", "")) == "S01"):
					tm1 = n1 as MeshInstance3D
			var om1 := tm1.mesh.surface_get_material(0)
			var cm1 := StandardMaterial3D.new()
			cm1.albedo_color = Color(0.30, 0.34, 0.18)
			cm1.roughness = 0.95
			tm1.mesh.surface_set_material(0, cm1)
			return func() -> void:
				tm1.mesh.surface_set_material(0, om1)
		"forest_off_s01":
			# S01 R1 實驗：隱藏 S01 的整個森林（樹＋林下），量植被的成本
			var hid1: Array = []
			for fnode1 in main.find_children("Forest", "Node3D", true, false):
				var fp1 := fnode1.get_parent()
				if fp1 != null and (String(fp1.name).begins_with("S01") or String(fp1.get_meta("bp_scene", "")) == "S01") and (fnode1 as Node3D).visible:
					(fnode1 as Node3D).visible = false
					hid1.append(fnode1)
			print("[PERF]     （forest_off_s01 隱藏 %d 個 Forest 節點）" % hid1.size())
			return func() -> void:
				for f1: Node3D in hid1:
					f1.visible = true
		"s01_forest_shadow_off", "s01_forest_hide":
			# S01 R2 成本拆解：只動 S01 場景的 Forest（陰影關／整個隱藏），S02–S04 的森林不動。s01_forest_hide 與 R1 的 forest_off_s01 等價（R2 量測用過這個名字，保留以便重現）
			var fs: Array = []
			var olds: Array = []
			for fnode in main.find_children("Forest", "Node3D", true, false):
				if not String(fnode.get_parent().name).begins_with("S01"):
					continue
				if name == "s01_forest_hide":
					fs.append(fnode)
					olds.append((fnode as Node3D).visible)
					(fnode as Node3D).visible = false
				else:
					for g in fnode.find_children("*", "GeometryInstance3D", true, false):
						fs.append(g)
						olds.append((g as GeometryInstance3D).cast_shadow)
						(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			print("[PERF]     （%s 影響 %d 個節點）" % [name, fs.size()])
			return func() -> void:
				for i in fs.size():
					if name == "s01_forest_hide":
						(fs[i] as Node3D).visible = olds[i]
					else:
						(fs[i] as GeometryInstance3D).cast_shadow = olds[i]
		"cheap_ground":
			var tm: MeshInstance3D = null
			for n in main.find_children("TerrainMesh", "MeshInstance3D", true, false):
				if n.get_parent() != null and String(n.get_parent().name).begins_with("S04"):
					tm = n as MeshInstance3D
			var om := tm.mesh.surface_get_material(0)
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color(0.30, 0.24, 0.16)
			cm.roughness = 0.95
			tm.mesh.surface_set_material(0, cm)
			return func() -> void:
				tm.mesh.surface_set_material(0, om)
	return func() -> void:
		pass


func _hide_matching(tokens: PackedStringArray) -> Array[Node3D]:
	var res: Array[Node3D] = []
	for n in main.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if not n3.visible:
			continue
		var hit := false
		for t in tokens:
			if t.begins_with("meta:"):
				hit = hit or n3.has_meta(t.trim_prefix("meta:"))
			elif String(n3.name).to_lower().contains(t.to_lower()):
				hit = true
		if hit:
			n3.visible = false
			res.append(n3)
	return res


func _put(q: Vector2, yaw: float) -> void:
	var sp := player.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, 80.0, q.y), Vector3(q.x, -60.0, q.y), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := sp.intersect_ray(rq)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(q.x, (float((r["position"] as Vector3).y) if not r.is_empty() else 2.0) + 0.2, q.y)
	adapter.set("_target_yaw", yaw)
	if player.has_method("snap_yaw"):
		player.snap_yaw(yaw)
	for i in 20:
		await physics_frame
