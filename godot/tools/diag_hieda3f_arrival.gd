extends SceneTree
## hieda3f: the arrival faces a bookshelf less than a metre away.
## Find how much open space surrounds the landing point.

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("hieda3f", "hieda2f")
	await _wait(70)
	var player = main.get_node_or_null("Player")
	var p: Vector3 = player.global_position
	print("[H3] arrival=(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z])

	var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state

	print("[H3] --- 落點四周淨空距離（眼高 1.5 m）---")
	for i in 12:
		var ang := deg_to_rad(float(i) * 30.0)
		var dir := Vector3(sin(ang), 0, cos(ang))
		var from: Vector3 = p + Vector3(0, 1.5, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 12.0)
		q.collide_with_areas = false
		q.exclude = [player.get_rid()]
		var h: Dictionary = space.intersect_ray(q)
		var d: float = from.distance_to(h.position) if h.has("position") else 12.0
		var nm: String = String(h.collider.name) if h.has("collider") else "淨空"
		print("[H3] %3d° %5.2f m  %s" % [i * 30, d, nm])

	# Scan the floor for the most open spot to move the arrival to.
	print("[H3] --- 掃描開闊點（取四周最小淨空最大的位置）---")
	var best := Vector3.ZERO
	var best_clear := -1.0
	for gx in range(-10, 11, 2):
		for gz in range(-10, 11, 2):
			var c := Vector3(float(gx), p.y, float(gz))
			# Must be standable.
			var dq := PhysicsRayQueryParameters3D.create(c + Vector3(0, 4, 0), c - Vector3(0, 4, 0))
			dq.collide_with_areas = false
			dq.exclude = [player.get_rid()]
			var dh: Dictionary = space.intersect_ray(dq)
			if not dh.has("position"):
				continue
			var floor_y: float = dh.position.y
			if absf(floor_y - p.y) > 1.0:
				continue
			var min_clear := 99.0
			for i in 8:
				var a2 := deg_to_rad(float(i) * 45.0)
				var d2 := Vector3(sin(a2), 0, cos(a2))
				var f2: Vector3 = Vector3(c.x, floor_y + 1.5, c.z)
				var q2 := PhysicsRayQueryParameters3D.create(f2, f2 + d2 * 10.0)
				q2.collide_with_areas = false
				q2.exclude = [player.get_rid()]
				var h2: Dictionary = space.intersect_ray(q2)
				var dd: float = f2.distance_to(h2.position) if h2.has("position") else 10.0
				min_clear = minf(min_clear, dd)
			if min_clear > best_clear:
				best_clear = min_clear
				best = Vector3(c.x, floor_y, c.z)
	print("[H3] 最開闊點 (%.1f, %.2f, %.1f)，四周最小淨空 %.2f m" % [best.x, best.y, best.z, best_clear])

	# Confirm the player can stand there.
	player.global_position = best + Vector3(0, 2.0, 0)
	player.velocity = Vector3.ZERO
	await _wait(60)
	print("[H3] 站上最開闊點 → (%.2f, %.3f, %.2f) on_floor=%s"
		% [player.global_position.x, player.global_position.y,
			player.global_position.z, str(player.is_on_floor())])
	quit(0)
