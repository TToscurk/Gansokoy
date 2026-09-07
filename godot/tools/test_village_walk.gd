extends SceneTree
## 人間之里實走：用真實輸入從南口走到北口，沿途截圖。不算地標、不做花俏事。

const OUT := "D:/神社/shrine/_review/village_test/"
var main: Node = null
var player: Node = null
var yaw: Node3D = null
var failures := 0

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[VT] %s %s" % ["PASS" if ok else "FAIL", label])
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

func _ground_y(x: float, z: float) -> float:
	var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -80, z))
	q.collide_with_areas = false
	var h: Dictionary = space.intersect_ray(q)
	return float(h.position.y) if h.has("position") else 0.0

func _blocked(dir: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state
	var from: Vector3 = player.global_position + Vector3(0, 0.9, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.6)
	q.collide_with_areas = false
	q.exclude = [player.get_rid()]
	var h: Dictionary = space.intersect_ray(q)
	return h.has("normal") and absf(Vector3(h.normal).y) < 0.55

func _snap(file: String) -> void:
	for i in 4:
		await process_frame
	main.get_viewport().get_texture().get_image().save_png(OUT + file)
	print("[VT] shot %s @ %s" % [file, str(player.global_position.round())])

## 走向目標；每 40 m 拍一張玩家視角
func _walk(target: Vector3, limit: float, tag: String) -> Dictionary:
	var t := 0.0
	var detour := 0.0
	var side := 1.0
	var last: Vector3 = player.global_position
	var last_t := 0.0
	var next_shot := 0.0
	var walked := 0.0
	var prev: Vector3 = player.global_position
	var n_shot := 0
	_hold("sprint", true)
	_hold("move_forward", true)
	while t < limit:
		var d: Vector3 = target - player.global_position
		d.y = 0.0
		var dist := d.length()
		if dist < 2.0:
			break
		d = d.normalized()
		if detour > 0.0:
			detour -= 1.0 / 60.0
			d = d.rotated(Vector3.UP, deg_to_rad(70.0) * side)
		elif _blocked(d):
			side = 1.0 if not _blocked(d.rotated(Vector3.UP, deg_to_rad(70.0))) else -1.0
			detour = 0.9
		yaw.rotation.y = atan2(-d.x, -d.z)
		await physics_frame
		await process_frame
		t += 1.0 / 60.0
		walked += prev.distance_to(player.global_position)
		prev = player.global_position
		if walked >= next_shot:
			n_shot += 1
			await _snap("%s_%02d.png" % [tag, n_shot])
			next_shot += 40.0
		if player.global_position.y < -50.0:
			_hold("move_forward", false); _hold("sprint", false)
			return {"ok": false, "why": "fell out of world at %s" % str(player.global_position.round())}
		if t - last_t >= 4.0:
			if last.distance_to(player.global_position) < 1.0:
				_hold("move_forward", false); _hold("sprint", false)
				return {"ok": false, "why": "stuck at %s" % str(player.global_position.round())}
			last = player.global_position
			last_t = t
	_hold("move_forward", false)
	_hold("sprint", false)
	return {"ok": true, "why": "reached in %.0fs, %.0f m" % [t, walked]}

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "")
	await _wait(60)
	player = main.get_node("Player")
	check("載入人間之里", main.current_id == "slice")
	check("出生站得住", player.is_on_floor())

	yaw = Node3D.new()
	main.add_child(yaw)
	player.input_yaw_node = yaw
	# 玩家鏡頭跟著 yaw 節點轉，截圖才是玩家看到的
	var piv: Node3D = player.get_node("Pivot")
	var adapter: Node = player.get_node("CameraAdapter")

	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/slice.meta.json"))
	var south := Vector3.INF
	var north := Vector3.INF
	var east := Vector3.INF
	for p in meta.get("portals", []):
		match str(p.get("target", "")):
			"trail": south = Vector3(float(p.x), 0, float(p.z))
			"hieda1f": north = Vector3(float(p.x), 0, float(p.z))
			"kourindou": east = Vector3(float(p.x), 0, float(p.z))

	# 從南口內側 4 m 出發（避開傳送區）
	var s := Vector3(south.x, 0, south.z - 4.0)
	player.global_position = Vector3(s.x, _ground_y(s.x, s.z) + 0.3, s.z)
	await _wait(10)

	# 讓鏡頭跟 yaw 節點：每幀把 adapter 的 yaw 設成走向
	var sync := func():
		adapter.set("_target_yaw", yaw.rotation.y)
		adapter.set("_current_yaw", yaw.rotation.y)
	var timer := Timer.new()
	main.add_child(timer)
	timer.wait_time = 1.0 / 60.0
	timer.timeout.connect(sync)
	timer.start()

	print("[VT] === 段1 南口 → 北口（稗田邸）約 %.0f m ===" % s.distance_to(north))
	var r1: Dictionary = await _walk(Vector3(north.x, 0, north.z - 6.0), 240.0, "S2N")
	print("[VT] %s" % r1.why)
	check("南口走到北口：%s" % r1.why, r1.ok)

	print("[VT] === 段2 北口 → 東口（龍石像橋・香霖堂）約 %.0f m ===" % north.distance_to(east))
	var r2: Dictionary = await _walk(Vector3(east.x - 6.0, 0, east.z), 240.0, "N2E")
	print("[VT] %s" % r2.why)
	check("北口走到東口：%s" % r2.why, r2.ok)

	timer.stop()
	print("[VT] failures=%d" % failures)
	quit(failures)
