extends SceneTree
## After the merge: where does slice still have ground collision?

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
	await _wait(80)
	var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state

	print("[GC] === 沿主街 x=235 由北到南 ===")
	for z in [-130.0, -100.0, -60.0, -20.0, 0.0, 16.0, 40.0, 60.0, 80.0, 96.0, 110.0, 130.0]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(235.0, 200.0, z), Vector3(235.0, -80.0, z))
		q.collide_with_areas = false
		var h: Dictionary = space.intersect_ray(q)
		var nm := "-"
		if h.has("collider"):
			nm = String(h.collider.name)
			var par: Node = h.collider.get_parent()
			if par != null:
				nm = String(par.name) + "/" + nm
		var y: float = h.position.y if h.has("position") else 999.0
		print("[GC] z=%7.1f y=%8.3f  %s" % [z, y, nm])

	print("[GC] === 場上的碰撞體節點 ===")
	var mr: Node3D = main.map_root
	var n_static := 0
	for c in mr.find_children("*", "StaticBody3D", true, false):
		n_static += 1
		if String(c.name).contains("Ground") or String(c.name).contains("地面") or String(c.name).contains("Unified"):
			var shapes := c.find_children("*", "CollisionShape3D", true, false)
			print("[GC]   %s  shapes=%d  pos=%s" % [c.get_path(), shapes.size(), str((c as Node3D).global_position.round())])
	print("[GC] StaticBody3D 總數：%d" % n_static)

	# Is there a ground collision .scn on disk, and does the scene reference it?
	for f in ["res://maps/slice/gen/ground_collision.scn", "res://maps/slice/gen/slice_unified_ground.res"]:
		print("[GC] %s 存在=%s" % [f, str(ResourceLoader.exists(f))])
	quit(0)
