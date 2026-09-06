extends SceneTree
## Record the shrine → trail → village walk so the route can be judged on screen.
## Not a test — verification lives in verify_walk_shrine_to_village.gd.

var main: Node = null
var player: Node = null
var yaw: Node3D = null
var cam: Camera3D = null
var _detour := 0.0
var _detour_side := 1.0
var _frames := 0


func _init() -> void:
	_run.call_deferred()


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


func _steer(target: Vector3, delta: float) -> void:
	var d: Vector3 = target - player.global_position
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return
	d = d.normalized()
	if _detour > 0.0:
		_detour -= delta
		d = d.rotated(Vector3.UP, deg_to_rad(70.0) * _detour_side)
	elif _blocked(d):
		_detour_side = 1.0 if not _blocked(d.rotated(Vector3.UP, deg_to_rad(70.0))) else -1.0
		_detour = 0.9
	yaw.rotation.y = atan2(-d.x, -d.z)


## Third-person chase camera so the footage reads like gameplay.
func _follow_cam() -> void:
	var back := Vector3(sin(yaw.rotation.y), 0, cos(yaw.rotation.y)) * 6.5
	var want: Vector3 = player.global_position + back + Vector3(0, 3.0, 0)
	cam.global_position = cam.global_position.lerp(want, 0.12)
	cam.look_at(player.global_position + Vector3(0, 1.2, 0), Vector3.UP)


func _walk_to(target: Vector3, expect: String, limit: float) -> bool:
	var t := 0.0
	_hold("sprint", true)
	_hold("move_forward", true)
	while t < limit:
		var delta := get_root().get_process_delta_time()
		_steer(target, delta)
		_follow_cam()
		await physics_frame
		await process_frame
		_frames += 1
		t += delta
		if main.current_id == expect:
			_hold("move_forward", false)
			_hold("sprint", false)
			return true
	_hold("move_forward", false)
	_hold("sprint", false)
	return false


func _portal_xyz(target: String) -> Vector3:
	var f := FileAccess.open("res://data/%s.meta.json" % main.current_id, FileAccess.READ)
	var j: Variant = JSON.parse_string(f.get_as_text())
	for p in j.get("portals", []):
		if String(p.get("target", "")) == target:
			return Vector3(float(p.x), float(p.y), float(p.z))
	return Vector3.INF


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	main.load_map("shrine", "")
	for i in 40:
		await physics_frame
		await process_frame
	player = main.get_node_or_null("Player")
	player.visible = true

	yaw = Node3D.new()
	main.add_child(yaw)
	player.input_yaw_node = yaw
	cam = Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.global_position = player.global_position + Vector3(0, 3, 7)
	for i in 60:
		_follow_cam()
		await physics_frame
		await process_frame
		_frames += 1

	var ok1: bool = await _walk_to(_portal_xyz("trail"), "trail", 30.0)
	for i in 60:
		_follow_cam()
		await physics_frame
		await process_frame
		_frames += 1

	# 30 fps 錄影下的模擬時間比無頭慢，給足上限免得半路收工。
	var ok2: bool = await _walk_to(_portal_xyz("slice"), "slice", 400.0)
	for i in 120:
		_follow_cam()
		await physics_frame
		await process_frame
		_frames += 1

	print("[ROUTE] %s" % JSON.stringify({
		"reached_trail": ok1,
		"reached_village": ok2,
		"final_map": main.current_id,
		"frames": _frames,
		"status": "ART_REVIEW",
	}))
	quit(0)
