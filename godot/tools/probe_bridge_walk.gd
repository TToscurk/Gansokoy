extends SceneTree
## What stops the real player at each bridge end? Walk it and dump every
## collision from the last move_and_slide: collider, normal, and position.

const SPEED := 6.0

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
	var player: CharacterBody3D = _main.player
	player.set_physics_process(false)

	var legs := [
		{"n": "西→東", "a": Vector3(394.4, 0.5, -134.9), "d": Vector3(1.0, 0, -0.31)},
		{"n": "東→西", "a": Vector3(452.1, 0.5, -152.9), "d": Vector3(-1.0, 0, 0.31)},
		{"n": "東河 430→", "a": Vector3(430, 1.0, 20), "d": Vector3(1, 0, 0)},
	]
	for leg in legs:
		print("── %s ──" % leg["n"])
		player.global_position = leg["a"]
		player.velocity = Vector3.ZERO
		for i in 3:
			await physics_frame
		var dir: Vector3 = (leg["d"] as Vector3).normalized()
		var last_pos := player.global_position
		var stuck_frames := 0
		for i in 240:
			player.velocity = dir * SPEED + Vector3(0, minf(player.velocity.y - 22.0 / 60.0, 0.0), 0)
			player.move_and_slide()
			await physics_frame
			var p := player.global_position
			if (p - last_pos).length() < 0.01:
				stuck_frames += 1
			else:
				stuck_frames = 0
			if i % 20 == 0 or stuck_frames == 3:
				print("  f%3d pos(%.1f, %.2f, %.1f) floor=%s wall=%s" % [
					i, p.x, p.y, p.z, player.is_on_floor(), player.is_on_wall()])
			if stuck_frames == 3:
				for k in player.get_slide_collision_count():
					var c := player.get_slide_collision(k)
					var n := c.get_normal()
					print("    撞到 %s  法線(%.2f, %.2f, %.2f) 坡 %.0f°  點(%.1f, %.2f, %.1f)" % [
						(c.get_collider() as Node).name, n.x, n.y, n.z,
						rad_to_deg(acos(clampf(n.y, -1, 1))),
						c.get_position().x, c.get_position().y, c.get_position().z])
				# What's directly ahead at foot / knee / chest height?
				for h in [0.1, 0.5, 1.0, 1.5]:
					var from := p + Vector3(0, h, 0)
					var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.0, player.collision_mask)
					q.exclude = [player.get_rid()]
					var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
					print("    前方 %.1f m 高：%s" % [h, ("%.2f m 處 %s" % [(hit["position"] - from).length(), (hit["collider"] as Node).name]) if not hit.is_empty() else "空"])
				break
			last_pos = p
	print("done")
	quit(0)
