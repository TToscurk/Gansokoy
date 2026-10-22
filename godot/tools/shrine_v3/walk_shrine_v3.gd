extends SceneTree
## 博麗神社 v3 實走測試：正式 main.tscn（--map=shrine_v3）、真正的玩家 CharacterBody3D、真輸入（move_forward）。
##   godot --headless --path godot --script res://tools/shrine_v3/walk_shrine_v3.gd -- --map=shrine_v3 [--out=<json>] [--scale=3]
## 路線（使用者規格 17-C）：獸道入口 → 石段 → 鳥居 → 前庭 → 拜殿前 → 倉庫側 → 櫻林邊緣 → 池塘周邊。
## 每腿記錄：到達與否、實走距離、最大上升、穿地次數（腳下射線地面高於玩家 0.3 m 以上）、鏡頭在碰撞體內的幀數。
## 另測：導航網格路徑（NavigationServer3D.map_get_path）在各關鍵點之間是否連續；互動區是否涵蓋玩家站位。
## 錄影（原速、第三人稱）：godot --path godot --resolution 1280x720 --write-movie <out.avi> --fixed-fps 60 --script res://tools/shrine_v3/walk_shrine_v3.gd -- --map=shrine_v3 --record

const S3 := preload("res://tools/shrine_v3/s3lib.gd")

var main: Node
var player: CharacterBody3D
var adapter: Node
var report := {"legs": [], "nav": [], "interactions": []}
var L: Dictionary


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var out := ""
	var scale := 3.0
	var record := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--scale="):
			scale = float(a.trim_prefix("--scale="))
		elif a == "--record":
			record = true
	L = S3.load_layout()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	Engine.time_scale = 1.0 if record else scale
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		if player and String(main.get("current_id")) == "shrine_v3" and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 120000:
			print("[WALK] ✗ 120 秒內沒進到 shrine_v3 並站上地面（current_id=%s）" % str(main.get("current_id")))
			quit(2)
			return
	adapter = player.get_node("CameraAdapter")
	adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	var sp := player.global_position
	print("[WALK] 進圖 OK，出生 %s  step_height=%.2f floor_max_angle=%.1f°" % [str(sp), float(player.get("step_height")), rad_to_deg(player.floor_max_angle)])
	report["spawn"] = [sp.x, sp.y, sp.z]
	var fails := 0
	# 1) 獸道入口 → 石段腳（beast 折線由石段腳往南；反向走）
	var beast: Array = []
	for p in L["beast"]:
		beast.push_front(Vector2(float(p[0]), float(p[1])))
	var leg1 := _resample(beast, 5.0)
	fails += 0 if (await _walk("1_獸道→石段腳", leg1, 1.2))["arrived_all"] else 1
	_check_interactions("石段腳")
	# 2) 石段 → 鳥居 → 前庭
	var zf := float(L["z_foot"])
	fails += 0 if (await _walk("2_石段→鳥居", _resample([Vector2(0, zf - 0.5), Vector2(0.15, 9.0), Vector2(0.0, 4.5)], 3.0), 1.0))["arrived_all"] else 1
	# 3) 前庭 → 拜殿前（賽錢箱前 1.4 m）
	fails += 0 if (await _walk("3_前庭→拜殿前", _resample([Vector2(0.0, 4.5), Vector2(0.0, -15.8)], 4.0), 1.0))["arrived_all"] else 1
	_check_interactions("拜殿前")
	# 4) 拜殿前 → 倉庫側（倉庫正面）
	var store: Array = []
	for p in L["paths"]["to_store"]:
		store.append(Vector2(float(p[0]), float(p[1])))
	fails += 0 if (await _walk("4_拜殿前→倉庫側", [Vector2(1.2, -13.5)] + store, 1.0))["arrived_all"] else 1
	# 4b) 倉庫正面 → 繞北側 → 陰陽玉彩蛋旁（美術深化：確認走得到、互動區涵蓋站位），再走回倉庫正面
	fails += 0 if (await _walk("4b_倉庫→陰陽玉", _resample([store[-1], Vector2(12.7, -20.4), Vector2(15.2, -20.75), Vector2(16.25, -20.95)], 2.0), 0.6))["arrived_all"] else 1
	_check_interactions("陰陽玉旁")
	fails += 0 if (await _walk("4c_陰陽玉→倉庫前", _resample([Vector2(16.25, -20.95), Vector2(15.2, -20.75), Vector2(12.7, -20.4), Vector2(11.6, -16.3)], 2.0), 0.8))["arrived_all"] else 1
	# 5) 倉庫 → 繞拜殿西側 → 林徑起點 → 櫻林邊緣
	#    美術深化：拜殿前燈籠移到 (±3.7, −12.6)，舊直線 (6,−12)→(−5.6,−12.6) 正好穿過左燈籠 → 改從燈籠前 1.1 m 走過
	var grove: Array = []
	for p in L["paths"]["grove"]:
		grove.append(Vector2(float(p[0]), float(p[1])))
	var leg5: Array = [Vector2(6.0, -11.0), Vector2(-5.6, -11.0), Vector2(-6.6, -20.0), Vector2(-6.6, -27.0), grove[0], grove[1], grove[2]]
	fails += 0 if (await _walk("5_倉庫→櫻林邊緣", _resample(leg5, 4.0), 1.1))["arrived_all"] else 1
	# 6) 櫻林林徑 → 池塘北岸（林徑沿池北繞到東北岸）
	var leg6 := _resample(grove.slice(2), 4.0)
	fails += 0 if (await _walk("6_櫻林→池塘北岸", leg6, 1.1))["arrived_all"] else 1
	if record:
		# 錄影版（原速）：只走去程 1–6 段（不瞬移），停 1.5 秒收尾
		for i in 90:
			await physics_frame
		print("[REC] done fails=%d" % fails)
		quit(0 if fails == 0 else 1)
		return
	# 6b) 池畔西徑：平台東北角 → 池塘西岸
	var pond_w: Array = []
	for p in L["paths"]["pond_w"]:
		pond_w.append(Vector2(float(p[0]), float(p[1])))
	await _place(Vector2(6.0, -26.0))
	fails += 0 if (await _walk("6b_平台→池塘西岸", _resample([Vector2(6.0, -26.0)] + pond_w, 3.0), 1.1))["arrived_all"] else 1
	# 7) 回程：池塘 → 前庭 → 石段下（確認下行）
	var back: Array = [Vector2(-6.6, -27.0), Vector2(-6.6, -20.0), Vector2(-5.6, -12.6), Vector2(-5.0, -6.0), Vector2(-1.0, -3.0), Vector2(0.0, 4.0), Vector2(0.0, 9.5), Vector2(0.0, 30.0), Vector2(0.0, zf + 1.0)]
	await _place(Vector2(-6.0, -30.5))
	fails += 0 if (await _walk("7_林徑口→石段下(下行)", _resample(back, 4.0), 1.1))["arrived_all"] else 1
	# 導航連續性
	_check_nav()
	report["fails"] = fails
	var nav_bad := 0
	for n: Dictionary in report["nav"]:
		if not bool(n["ok"]):
			nav_bad += 1
	report["nav_fails"] = nav_bad
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "\t") + "\n")
		f.close()
	print("[WALK] ═══ 結果：%d 腿、%d 未到達；導航 %d 段、%d 段不通 ═══" % [(report["legs"] as Array).size(), fails, (report["nav"] as Array).size(), nav_bad])
	Engine.time_scale = 1.0
	quit(0 if fails == 0 and nav_bad == 0 else 1)


func _resample(pts: Array, step: float) -> Array:
	var out: Array = []
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / step)))
		for k in n:
			out.append(a.lerp(b, float(k) / float(n)))
	out.append(pts[-1])
	return out


func _ground(q: Vector2) -> float:
	var sp := player.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, 80.0, q.y), Vector3(q.x, -40.0, q.y), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := sp.intersect_ray(rq)
	return float((r["position"] as Vector3).y) if not r.is_empty() else -INF


func _place(q: Vector2) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(q.x, _ground(q) + 0.15, q.y)
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


func _cam_inside() -> bool:
	var cam := player.get_viewport().get_camera_3d()
	if cam == null:
		return false
	var sp := player.get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.position = cam.global_position
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	return sp.intersect_point(q, 1).size() > 0


func _walk(label: String, wps: Array, arrive_r: float) -> Dictionary:
	var y0 := player.global_position.y
	var maxr := 0.0
	var dist := 0.0
	var stuck_at := Vector3.ZERO
	var stuck_near: Array = []
	var arrived_all := true
	var t_start := Time.get_ticks_msec()
	var last := player.global_position
	var done_wp := 0
	var sink := 0
	var cam_in := 0
	var frames := 0
	var ymin := INF
	var ymax := -INF
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
			await physics_frame
			frames += 1
			var gp := player.global_position
			maxr = maxf(maxr, gp.y - y0)
			ymin = minf(ymin, gp.y)
			ymax = maxf(ymax, gp.y)
			dist += gp.distance_to(last)
			last = gp
			if frames % 6 == 0:
				var g := _ground(Vector2(gp.x, gp.z))
				if g != -INF and g - gp.y > 0.3:
					sink += 1
				if _cam_inside():
					cam_in += 1
			hist.append(p)
			if hist.size() > 150:
				hist.pop_front()
				if (hist[-1] as Vector2).distance_to(hist[0]) < 0.15:
					break
		Input.action_release("move_forward")
		if not arrived:
			arrived_all = false
			stuck_at = player.global_position
			stuck_near = _near_colliders(stuck_at)
			break
		done_wp += 1
	var secs := (Time.get_ticks_msec() - t_start) / 1000.0
	var e := player.global_position
	var rec := {"leg": label, "arrived_all": arrived_all, "waypoints": wps.size(), "done": done_wp, "walked_m": snappedf(dist, 0.1), "real_s": snappedf(secs, 0.1),
		"max_rise_m": snappedf(maxr, 0.01), "y_range": [snappedf(ymin, 0.01), snappedf(ymax, 0.01)], "sink_samples": sink, "cam_inside_samples": cam_in, "samples": frames / 6,
		"end": [snappedf(e.x, 0.01), snappedf(e.y, 0.01), snappedf(e.z, 0.01)]}
	if not arrived_all:
		rec["stuck_at"] = [snappedf(stuck_at.x, 0.01), snappedf(stuck_at.y, 0.01), snappedf(stuck_at.z, 0.01)]
		rec["stuck_near"] = stuck_near
		rec["stuck_wp"] = [snappedf((wps[done_wp] as Vector2).x, 0.1), snappedf((wps[done_wp] as Vector2).y, 0.1)]
	(report["legs"] as Array).append(rec)
	print("[WALK] %-22s %s  waypoint %d/%d  實走 %.0f m  高程 %.1f→%.1f  穿地 %d/%d  鏡頭在碰撞體內 %d/%d  終點 (%.1f, %.1f, %.1f)%s" % [label, "到達" if arrived_all else "未到達", done_wp, wps.size(), dist,
		ymin, ymax, sink, frames / 6, cam_in, frames / 6, e.x, e.y, e.z, "" if arrived_all else "  卡在 %s 附近：%s" % [str(stuck_at), str(stuck_near)]])
	return rec


func _check_interactions(where: String) -> void:
	for wi in get_nodes_in_group("world_interaction"):
		if not (wi is Area3D):
			continue
		var a := wi as Area3D
		var inside := a.overlaps_body(player)
		var rec := {"at": where, "id": String(a.get("interaction_id")), "overlaps_player": inside, "enabled": bool(a.get("enabled")), "require_quest": String(a.get("require_quest"))}
		(report["interactions"] as Array).append(rec)
		print("[WALK] 互動區 %-26s 玩家在區內=%s enabled=%s require_quest=%s" % [rec["id"], str(inside), str(rec["enabled"]), rec["require_quest"]])


func _check_nav() -> void:
	var map_rid := player.get_world_3d().navigation_map
	var pts := {
		"獸道口": Vector2(-16.5, 89.0), "石段腳": Vector2(0.0, float(L["z_foot"]) + 1.5), "鳥居內": Vector2(0.0, 4.0),
		"拜殿前": Vector2(0.0, -15.6), "倉庫前": Vector2(12.0, -16.5), "陰陽玉旁": Vector2(16.25, -20.95), "櫻林": Vector2(-8.0, -44.0), "池畔": Vector2(float(L["paths"]["pond_w"][1][0]), float(L["paths"]["pond_w"][1][1])),
	}
	var order := ["獸道口", "石段腳", "鳥居內", "拜殿前", "倉庫前", "陰陽玉旁", "櫻林", "池畔"]
	for i in order.size() - 1:
		var a: Vector2 = pts[order[i]]
		var b: Vector2 = pts[order[i + 1]]
		var pa := Vector3(a.x, _ground(a) + 0.1, a.y)
		var pb := Vector3(b.x, _ground(b) + 0.1, b.y)
		var path := NavigationServer3D.map_get_path(map_rid, pa, pb, true)
		var ok := path.size() >= 2 and path[path.size() - 1].distance_to(pb) < 1.5 and path[0].distance_to(pa) < 1.5
		var ln := 0.0
		for k in path.size() - 1:
			ln += path[k].distance_to(path[k + 1])
		var rec := {"from": order[i], "to": order[i + 1], "ok": ok, "points": path.size(), "len_m": snappedf(ln, 0.1),
			"end_gap_m": snappedf(path[path.size() - 1].distance_to(pb), 0.01) if path.size() > 0 else -1.0}
		(report["nav"] as Array).append(rec)
		print("[WALK] 導航 %s → %s  %s  點數 %d  長 %.1f m  終點差 %.2f m" % [order[i], order[i + 1], "通" if ok else "不通", path.size(), ln, float(rec["end_gap_m"])])
