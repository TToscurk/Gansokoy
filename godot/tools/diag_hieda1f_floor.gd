extends SceneTree
## hieda1f: the spawn moves 262 m in one direction and 0 m in the other seven.
## Find out what the player is standing on and what surrounds the spawn.

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]

func _path(n: Node, root_node: Node) -> String:
	var out := ""
	var cur := n
	while cur != null and cur != root_node:
		out = "/" + String(cur.name) + out
		cur = cur.get_parent()
	return out

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("hieda1f", "slice")
	await _wait(70)
	var player = main.get_node_or_null("Player")
	var mr: Node3D = main.map_root
	var p: Vector3 = player.global_position
	print("[H1] spawn=%s on_floor=%s" % [_v(p), str(player.is_on_floor())])

	var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state

	# What is directly under the spawn?
	var dq := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2, 0), p - Vector3(0, 30, 0))
	dq.collide_with_areas = false
	dq.exclude = [player.get_rid()]
	var dh: Dictionary = space.intersect_ray(dq)
	if dh.has("collider"):
		print("[H1] 腳下=%s @ %s" % [_path(dh.collider, mr), _v(dh.position)])
	else:
		print("[H1] 腳下什麼都沒有（懸空）")

	# Ring cast: what walls the spawn in?
	print("[H1] --- 八方向 3 m 內的阻擋 ---")
	for i in 8:
		var ang := deg_to_rad(float(i) * 45.0)
		var dir := Vector3(sin(ang), 0, cos(ang))
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.9, 0), p + Vector3(0, 0.9, 0) + dir * 3.0)
		q.collide_with_areas = false
		q.exclude = [player.get_rid()]
		var h: Dictionary = space.intersect_ray(q)
		if h.has("collider"):
			print("[H1] %3d° 擋於 %.2f m: %s" % [i * 45, p.distance_to(h.position), _path(h.collider, mr)])
		else:
			print("[H1] %3d° 3 m 內無阻擋" % [i * 45])

	# Walk each direction and report where it ends up — including the 262 m one.
	print("[H1] --- 實走八方向 ---")
	for i in 8:
		var ang2 := deg_to_rad(float(i) * 45.0)
		var d2 := Vector3(sin(ang2), 0, cos(ang2))
		player.global_position = p
		player.velocity = Vector3.ZERO
		await _wait(4)
		for f in 90:
			player.velocity.x = d2.x * 4.0
			player.velocity.z = d2.z * 4.0
			player.move_and_slide()
			await physics_frame
		print("[H1] %3d° → %s on_floor=%s" % [i * 45, _v(player.global_position), str(player.is_on_floor())])

	# How big is the floor collision, really?
	print("[H1] --- 地板碰撞盤點 ---")
	for n in mr.find_children("*", "StaticBody3D", true, false):
		var sb := n as StaticBody3D
		for cs in sb.find_children("*", "CollisionShape3D", true, false):
			var c := cs as CollisionShape3D
			if c.shape == null:
				continue
			print("[H1]   %-38s %s" % [_path(sb, mr), c.shape.get_class()])
	quit(0)
