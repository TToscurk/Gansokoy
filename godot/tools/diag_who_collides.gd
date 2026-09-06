extends SceneTree
## What is the collision actually hitting on the east river band? Name the
## collider, and drop the player there to see whether he stands on something
## visible or floats on a stale baked shape.

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _path(n: Node, mr: Node) -> String:
	var out := ""
	var cur := n
	while cur != null and cur != mr:
		out = "/" + String(cur.name) + out
		cur = cur.get_parent()
	return out

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "")
	await _wait(80)
	var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state
	var mr: Node3D = main.map_root
	var player = main.get_node_or_null("Player")

	for pt in [Vector3(445, 0, -160), Vector3(400, 0, -140), Vector3(460, 0, -120), Vector3(415, 0, -100), Vector3(430, 0, -140), Vector3(415, 0, -140), Vector3(445, 0, -120),
			Vector3(430, 0, -100), Vector3(445, 0, -60), Vector3(460, 0, -20), Vector3(250, 0, -40)]:
		var q := PhysicsRayQueryParameters3D.create(pt + Vector3(0, 200, 0), pt + Vector3(0, -80, 0))
		q.collide_with_areas = false
		var h: Dictionary = space.intersect_ray(q)
		var who := _path(h.collider, mr) if h.has("collider") else "-"
		var y: float = h.position.y if h.has("position") else NAN
		# Is there a visible mesh near that hit point?
		var near := "無"
		var best := 999.0
		for n in mr.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.visible:
				continue
			var box: AABB = mi.global_transform * mi.mesh.get_aabb()
			if box.size.x > 200.0:
				continue
			var hp := Vector3(pt.x, y, pt.z)
			if box.grow(0.5).has_point(hp):
				var d: float = absf(box.get_center().y - y)
				if d < best:
					best = d
					near = String(mi.name)
		print("[WHO] (%4.0f, %5.0f) 碰撞 y=%6.2f  碰撞體=%s  該高度附近可見物=%s"
			% [pt.x, pt.z, y, who, near])

	quit(0)
