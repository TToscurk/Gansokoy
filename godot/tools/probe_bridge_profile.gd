extends SceneTree
## Ground profile along the bridge approach, 0.25 m steps, from 3 m before the
## stuck point to 6 m past it. What is the revetment actually shaped like here?

var _main: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	_main.load_map("slice", "")
	for i in 6:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = _main.map_root.get_world_3d().direct_space_state
	var mask: int = _main.player.collision_mask
	for spot in [
		{"n": "西橋頭", "pos": Vector3(399.4, 0, -136.4), "dir": Vector3(1.0, 0, -0.31)},
		{"n": "東橋頭", "pos": Vector3(450.6, 0, -152.4), "dir": Vector3(-1.0, 0, 0.31)},
	]:
		print("── %s ──" % spot["n"])
		var dir: Vector3 = (spot["dir"] as Vector3).normalized()
		var prev_y := NAN
		var s := -3.0
		while s <= 8.0:
			var p: Vector3 = spot["pos"] + dir * s
			var from := Vector3(p.x, 12.0, p.z)
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -30, 0), mask)
			q.exclude = [_main.player.get_rid()]
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty():
				print("  s=%5.2f 無")
			else:
				var y: float = hit["position"].y
				var n: Vector3 = hit["normal"]
				var slope := "" if is_nan(prev_y) else "Δ%+.2f %4.0f°" % [y - prev_y, rad_to_deg(atan2(absf(y - prev_y), 0.25))]
				print("  s=%5.2f y=%6.2f %-28s 面坡 %3.0f°  %s" % [s, y, (hit["collider"] as Node).name, rad_to_deg(n.angle_to(Vector3.UP)), slope])
				prev_y = y
			s += 0.25
	print("done")
	quit(0)
