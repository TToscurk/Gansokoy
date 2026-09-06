extends SceneTree
## Find a landing spot in slice for the incoming trail portal:
## walkable ground near the north end of the main street (x 225-422).

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
	main.load_map("slice", "")
	await _wait(60)
	var player = main.get_node_or_null("Player")
	print("[SPOT] spawn=%s on_floor=%s" % [str(player.global_position), str(player.is_on_floor())])

	var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state

	# Where does the street run, and where does it end to the north (-z)?
	print("[SPOT] --- ground along the main street, x=235 ---")
	for z in [-120.0, -100.0, -80.0, -60.0, -40.0, -20.0, 0.0, 16.0, 40.0, 60.0, 80.0]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(235.0, 120.0, z), Vector3(235.0, -60.0, z))
		q.collide_with_areas = false
		var hit: Dictionary = space.intersect_ray(q)
		var nm := "-"
		if hit.has("collider"):
			nm = String(hit.collider.name)
			var par: Node = hit.collider.get_parent()
			if par != null:
				nm = String(par.name) + "/" + nm
		var y: float = hit.position.y if hit.has("position") else 999.0
		print("[SPOT] z=%7.1f y=%7.3f  %s" % [z, y, nm])

	# Cross-section to confirm the street's width at the chosen z.
	print("[SPOT] --- cross-section at z=-60 ---")
	for x in [200.0, 215.0, 225.0, 235.0, 245.0, 260.0, 280.0]:
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(x, 120.0, -60.0), Vector3(x, -60.0, -60.0))
		q2.collide_with_areas = false
		var h2: Dictionary = space.intersect_ray(q2)
		var nm2 := "-"
		if h2.has("collider"):
			nm2 = String(h2.collider.name)
		var y2: float = h2.position.y if h2.has("position") else 999.0
		print("[SPOT] x=%6.1f y=%7.3f  %s" % [x, y2, nm2])

	# Can the player actually stand at the candidate spots?
	print("[SPOT] --- standability test ---")
	for cand in [Vector3(235.0, 0.0, -60.0), Vector3(235.0, 0.0, -80.0), Vector3(235.0, 0.0, -40.0)]:
		player.global_position = cand + Vector3(0, 3.0, 0)
		player.velocity = Vector3.ZERO
		await _wait(50)
		print("[SPOT] candidate %s → settled at %s on_floor=%s"
			% [str(cand), str(player.global_position), str(player.is_on_floor())])

	quit(0)
