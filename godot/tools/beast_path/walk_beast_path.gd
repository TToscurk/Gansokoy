extends SceneTree
## T09 實走測試：正式 main.tscn、真正的玩家 CharacterBody3D、真輸入（move_forward／sprint）。
##   godot --headless --path godot --script res://tools/beast_path/walk_beast_path.gd -- --map=beast_path [--out=<json>] [--scale=4]
## 腿：
##   main_fwd   從 S01 出生點沿主路走到 BOSS 場入口（走）
##   main_back  衝刺原路返回出生點（sprint）
##   bamboo / hollow_loop / return_lane / exit_shrine  各支線從起點走到終點（exit_shrine 與 return_lane 盡頭刻意被封，走到封口前即算到達）
## 每腿記錄：是否到達、用時、最大上升、卡住位置與附近碰撞物。
const BP := preload("res://tools/beast_path/bp_lib.gd")

var main: Node
var player: CharacterBody3D
var adapter: Node
var lib: BP
var report := {"legs": []}


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var out := ""
	var scale := 4.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--scale="):
			scale = float(a.trim_prefix("--scale="))
	lib = BP.new()
	lib.setup(true, true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	Engine.time_scale = scale
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		if player and String(main.get("current_id")) == "beast_path" and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 120000:
			print("[WALK] ✗ 120 秒內沒進到 beast_path 並站上地面")
			quit(2)
			return
	adapter = player.get_node("CameraAdapter")
	adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	print("[WALK] 進圖 OK，玩家 step_height=%.2f floor_max_angle=%.1f° 起點 %s" % [float(player.get("step_height")), rad_to_deg(player.floor_max_angle), str(player.global_position)])
	report["start"] = [player.global_position.x, player.global_position.y, player.global_position.z]
	var fails := 0
	# --- 主線走去
	var s0: float = lib.main.q(Vector2(player.global_position.x, player.global_position.z))["s"]
	var fwd: Array = []
	var s := s0
	while s < lib.main.length:
		fwd.append(lib.main.pos_at(s))
		s += 6.0
	fwd.append(lib.main.pos_at(lib.main.length))
	var r1 := await _walk("main_fwd", fwd, false, 1.2)
	fails += 0 if r1["arrived_all"] else 1
	# --- 主線衝刺返回（直接從終點接著跑）
	var back: Array = []
	s = lib.main.length
	while s > s0:
		back.append(lib.main.pos_at(s))
		s -= 6.0
	back.append(lib.main.pos_at(s0))
	var r2 := await _walk("main_back_sprint", back, true, 1.4)
	fails += 0 if r2["arrived_all"] else 1
	# --- 支線
	var ends := {"exit_shrine": 0.30, "return_lane": 0.93}      # 盡頭被封：只走到封口前
	for id: String in ["bamboo", "hollow_loop", "return_lane", "exit_shrine"]:
		var br: BP.Poly = lib.branches[id]
		var u_end := float(ends.get(id, 1.0))
		var pts: Array = []
		var ss := 0.0
		while ss < br.length * u_end:
			pts.append(br.pos_at(ss))
			ss += 5.0
		pts.append(br.pos_at(br.length * u_end))
		await _place(br.pos_at(0.0))
		var r := await _walk("branch_" + id, pts, false, 1.2)
		fails += 0 if r["arrived_all"] else 1
	# --- BOSS 場繞圈：進場 → 中心 → r=12 繞一圈（12 點）→ 回中心 → 走向東北出口平台（封口前）
	await _place(lib.main.pos_at(lib.main.length - 14.0))
	var c0 := lib.arena_c()
	var ap: Array = [c0]
	for k in 13:
		var ang := TAU * float(k) / 12.0 + PI
		ap.append(c0 + Vector2(sin(ang), -cos(ang)) * 12.0)
	ap.append(c0)
	ap.append(lib.arena_pos(50.0, 20.0))
	var ra := await _walk("arena_circuit", ap, false, 1.3)
	fails += 0 if ra["arrived_all"] else 1
	report["fails"] = fails
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "\t") + "\n")
		f.close()
	print("[WALK] ═══ 結果：%d 腿、%d 未到達 ═══" % [(report["legs"] as Array).size(), fails])
	Engine.time_scale = 1.0
	quit(0 if fails == 0 else 1)


func _place(q: Vector2) -> void:
	var sp := player.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, 60.0, q.y), Vector3(q.x, -60.0, q.y), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := sp.intersect_ray(rq)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(q.x, (float((r["position"] as Vector3).y) if not r.is_empty() else 2.0) + 0.15, q.y)
	for i in 20:
		await physics_frame


func _near_colliders(p: Vector3) -> Array:
	var sp := player.get_world_3d().direct_space_state
	var sh := SphereShape3D.new()
	sh.radius = 1.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.9, 0))
	q.exclude = [player.get_rid()]
	var names: Array = []
	for r: Dictionary in sp.intersect_shape(q, 8):
		var c := r["collider"] as Node
		if c != null:
			names.append(String(c.get_parent().name) + "/" + String(c.name) if c.get_parent() != null else String(c.name))
	return names


func _walk(label: String, wps: Array, sprint: bool, arrive_r: float) -> Dictionary:
	var y0 := player.global_position.y
	var maxr := 0.0
	var dist := 0.0
	var stuck_at := Vector3.ZERO
	var stuck_near: Array = []
	var arrived_all := true
	var t_start := Time.get_ticks_msec()
	var last := player.global_position
	var done_wp := 0
	for w: Vector2 in wps:
		var t0 := Time.get_ticks_msec()
		var hist: Array = []
		var arrived := false
		while Time.get_ticks_msec() - t0 < 25000:
			var p := Vector2(player.global_position.x, player.global_position.z)
			if p.distance_to(w) < arrive_r:
				arrived = true
				break
			var d := w - p
			adapter.set("_target_yaw", atan2(-d.x, -d.y))
			Input.action_press("move_forward")
			if sprint:
				Input.action_press("sprint")
			await physics_frame
			maxr = maxf(maxr, player.global_position.y - y0)
			dist += player.global_position.distance_to(last)
			last = player.global_position
			hist.append(p)
			if hist.size() > 150:
				hist.pop_front()
				if (hist[-1] as Vector2).distance_to(hist[0]) < 0.15:
					break
		Input.action_release("move_forward")
		Input.action_release("sprint")
		if not arrived:
			arrived_all = false
			stuck_at = player.global_position
			stuck_near = _near_colliders(stuck_at)
			break
		done_wp += 1
	var secs := (Time.get_ticks_msec() - t_start) / 1000.0
	var e := player.global_position
	var rec := {"leg": label, "arrived_all": arrived_all, "waypoints": wps.size(), "done": done_wp, "walked_m": snappedf(dist, 0.1), "real_s": snappedf(secs, 0.1),
		"max_rise_m": snappedf(maxr, 0.01), "end": [snappedf(e.x, 0.01), snappedf(e.y, 0.01), snappedf(e.z, 0.01)]}
	if not arrived_all:
		rec["stuck_at"] = [snappedf(stuck_at.x, 0.01), snappedf(stuck_at.y, 0.01), snappedf(stuck_at.z, 0.01)]
		rec["stuck_near"] = stuck_near
		rec["stuck_wp"] = [snappedf((wps[done_wp] as Vector2).x, 0.1), snappedf((wps[done_wp] as Vector2).y, 0.1)]
	(report["legs"] as Array).append(rec)
	print("[WALK] %-18s %s  waypoint %d/%d  實走 %.0f m  最大上升 %.2f m  終點 (%.1f, %.1f, %.1f)%s" % [label, "到達" if arrived_all else "未到達", done_wp, wps.size(), dist, maxr, e.x, e.y, e.z,
		"" if arrived_all else "  卡在 %s 附近：%s" % [str(stuck_at), str(stuck_near)]])
	return rec
