extends SceneTree
## Regression: 獸道 → slice（新人間之里）必須真的走得通，且回得來。
##
## 舊基線 village.tscn 已凍結，實作在 maps/slice。傳送圖必須跟著改，
## 否則獸道走到底進的是舊圖。

var failures := 0
var main: Node = null
var player: Node = null
var yaw: Node3D = null
var _detour := 0.0
var _side := 1.0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[T2S] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _hold(a: String, down: bool) -> void:
	var e := InputEventAction.new()
	e.action = a
	e.pressed = down
	Input.parse_input_event(e)

func _blocked(dir: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state
	var from: Vector3 = player.global_position + Vector3(0, 0.9, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.6)
	q.collide_with_areas = false
	q.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	return hit.has("normal") and absf(Vector3(hit.normal).y) < 0.55

func _walk_to(target: Vector3, expect: String, limit: float) -> Dictionary:
	var t := 0.0
	var last: Vector3 = player.global_position
	var last_t := 0.0
	_hold("sprint", true)
	_hold("move_forward", true)
	while t < limit:
		var delta := get_root().get_process_delta_time()
		var d: Vector3 = target - player.global_position
		d.y = 0.0
		if d.length_squared() > 0.0001:
			d = d.normalized()
			if _detour > 0.0:
				_detour -= delta
				d = d.rotated(Vector3.UP, deg_to_rad(70.0) * _side)
			elif _blocked(d):
				_side = 1.0 if not _blocked(d.rotated(Vector3.UP, deg_to_rad(70.0))) else -1.0
				_detour = 0.9
			yaw.rotation.y = atan2(-d.x, -d.z)
		await physics_frame
		await process_frame
		t += delta
		if main.current_id == expect:
			_hold("move_forward", false)
			_hold("sprint", false)
			return {"ok": true, "seconds": t, "why": "arrived in %s" % expect}
		if player.global_position.y < -80.0:
			break
		if t - last_t >= 4.0:
			if last.distance_to(player.global_position) < 1.0:
				_hold("move_forward", false)
				_hold("sprint", false)
				return {"ok": false, "seconds": t, "why": "stuck at %s" % str(player.global_position)}
			last = player.global_position
			last_t = t
	_hold("move_forward", false)
	_hold("sprint", false)
	return {"ok": false, "seconds": t, "why": "timed out (map=%s)" % main.current_id}

func _portal_xyz(target: String) -> Vector3:
	var f := FileAccess.open("res://data/%s.meta.json" % main.current_id, FileAccess.READ)
	var j: Variant = JSON.parse_string(f.get_as_text())
	for p in j.get("portals", []):
		if str(p.get("target", "")) == target:
			return Vector3(float(p.x), float(p.y), float(p.z))
	return Vector3.INF

func _run() -> void:
	# --- 靜態：傳送圖必須連通 -----------------------------------------
	var tf := FileAccess.open("res://data/trail.meta.json", FileAccess.READ)
	var tj: Variant = JSON.parse_string(tf.get_as_text())
	var trail_targets: Array = []
	for p in tj.get("portals", []):
		trail_targets.append(str(p.get("target", "")))
	print("[T2S] 獸道的傳送目的地：%s" % str(trail_targets))
	check("獸道有一顆傳送區指向 slice", trail_targets.has("slice"))
	check("獸道不再指向凍結的 village", not trail_targets.has("village"))

	var sf := FileAccess.open("res://data/slice.meta.json", FileAccess.READ)
	var sj: Variant = JSON.parse_string(sf.get_as_text())
	var slice_targets: Array = []
	for p in sj.get("portals", []):
		slice_targets.append(str(p.get("target", "")))
	print("[T2S] slice 的傳送目的地：%s" % str(slice_targets))
	check("slice 有回獸道的傳送區", slice_targets.has("trail"))

	var rf := FileAccess.open("res://data/mapRegistry.json", FileAccess.READ)
	var rj: Variant = JSON.parse_string(rf.get_as_text())
	check("slice 已登錄進 mapRegistry", rj.has("slice"))
	if rj.has("slice"):
		check("slice 有中文圖名（HUD 才不會顯示 id）", String(rj["slice"].get("zh", "")) != "")

	# --- 實走：獸道南下 → slice ---------------------------------------
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("trail", "shrine")
	await _wait(40)
	player = main.get_node_or_null("Player")
	yaw = Node3D.new()
	main.add_child(yaw)
	player.input_yaw_node = yaw

	var target := _portal_xyz("slice")
	check("獸道場上找得到往 slice 的傳送點座標", target != Vector3.INF)
	if target != Vector3.INF:
		print("[T2S] 從 %s 走向 %s（%.0f m）"
			% [str(player.global_position), str(target), player.global_position.distance_to(target)])
		var r: Dictionary = await _walk_to(target, "slice", 400.0)
		print("[T2S] 段果：%s（%.1f s）" % [r.why, r.seconds])
		check("能從獸道走進 slice：%s" % r.why, r.ok)

		if main.current_id == "slice":
			await _wait(90)
			print("[T2S] slice 落點 %s on_floor=%s"
				% [str(player.global_position), str(player.is_on_floor())])
			check("在 slice 站得住（沒有掉出世界）", player.global_position.y > -20.0)
			check("在 slice 踩得到地面", player.is_on_floor())
			# 落在主街上，不是 235 m 外的空草地。
			check("落在主街範圍內（x 225~422）",
				player.global_position.x > 220.0 and player.global_position.x < 430.0)

			# --- 回程：slice → 獸道 -------------------------------
			var back := _portal_xyz("trail")
			check("slice 場上找得到回獸道的傳送點", back != Vector3.INF)
			if back != Vector3.INF:
				while main.portal_cooldown > 0.0:
					await physics_frame
					await process_frame
				var r2: Dictionary = await _walk_to(back, "trail", 200.0)
				print("[T2S] 回程：%s（%.1f s）" % [r2.why, r2.seconds])
				check("能從 slice 走回獸道：%s" % r2.why, r2.ok)

	print("[T2S] failures=%d" % failures)
	quit(failures)
