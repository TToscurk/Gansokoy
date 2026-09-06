extends SceneTree
## Why does _try_step_up refuse the bridge abutment? Replay its tests at the
## stuck position and print each intermediate answer.

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
	var p: CharacterBody3D = _main.player
	p.set_physics_process(false)

	for spot in [
		{"n": "西橋頭", "pos": Vector3(399.4, -0.13, -136.4), "dir": Vector3(1.0, 0, -0.31)},
		{"n": "東橋頭", "pos": Vector3(450.6, -0.34, -152.4), "dir": Vector3(-1.0, 0, 0.31)},
	]:
		print("── %s ──" % spot["n"])
		p.global_position = spot["pos"]
		p.velocity = Vector3.ZERO
		for i in 3:
			await physics_frame
		var dir: Vector3 = (spot["dir"] as Vector3).normalized()
		var motion := dir * 7.0 / 60.0
		print("  位置 (%.2f, %.2f, %.2f) on_floor=%s" % [p.global_position.x, p.global_position.y, p.global_position.z, p.is_on_floor()])
		print("  平走被擋: %s" % p.test_move(p.global_transform, motion))
		# Replay _try_step_up's exact sequence with travel distances.
		var par := PhysicsTestMotionParameters3D.new()
		var res := PhysicsTestMotionResult3D.new()
		par.from = p.global_transform
		par.motion = Vector3(0, 0.6, 0)
		var up_hit := PhysicsServer3D.body_test_motion(p.get_rid(), par, res)
		print("  抬升 0.6: hit=%s travel.y=%.3f remainder=%.3f %s" % [up_hit, res.get_travel().y, res.get_remainder().y,
			((res.get_collider() as Node).name + " 法線坡 %.0f°" % rad_to_deg(res.get_collision_normal().angle_to(Vector3.UP))) if up_hit else ""])
		var lifted_by: float = res.get_travel().y
		var lifted := p.global_transform.translated(Vector3(0, lifted_by, 0))
		par.from = lifted
		par.motion = motion
		var f_hit := PhysicsServer3D.body_test_motion(p.get_rid(), par, res)
		print("  抬高後前進 %.3f: hit=%s travel=%.3f" % [motion.length(), f_hit, res.get_travel().length()])
		var fwd: Vector3 = res.get_travel()
		par.from = lifted.translated(fwd)
		par.motion = Vector3(0, -lifted_by, 0)
		var d_hit := PhysicsServer3D.body_test_motion(p.get_rid(), par, res)
		print("  落下 %.3f: hit=%s travel=%.3f %s" % [lifted_by, d_hit, res.get_travel().length(),
			((res.get_collider() as Node).name + " 法線坡 %.0f°" % rad_to_deg(res.get_collision_normal().angle_to(Vector3.UP))) if d_hit else ""])
		for sh in [0.3, 0.6, 0.9, 1.2, 1.5]:
			var up := Vector3(0, sh, 0)
			var lifted2 := p.global_transform.translated(up)
			var up_blocked := p.test_move(p.global_transform, up)
			var fwd_blocked := p.test_move(lifted2, motion)
			var line := "  抬 %.1f m: 往上被擋=%s 抬高後前進被擋=%s" % [sh, up_blocked, fwd_blocked]
			if not up_blocked and not fwd_blocked:
				var ahead := lifted2.translated(motion)
				var par2 := PhysicsTestMotionParameters3D.new()
				par2.from = ahead
				par2.motion = -up
				var res2 := PhysicsTestMotionResult3D.new()
				var hit := PhysicsServer3D.body_test_motion(p.get_rid(), par2, res2)
				if hit:
					var n := res2.get_collision_normal()
					line += " 落地: 走了 %.2f 法線坡 %.0f° 撞 %s" % [
						res2.get_travel().length(), rad_to_deg(n.angle_to(Vector3.UP)),
						(res2.get_collider() as Node).name]
				else:
					line += " 落地: 無"
			print(line)
		# What is ahead of the feet, in 0.25 m slices?
		for h in [0.05, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0]:
			var from := p.global_position + Vector3(0, h, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * 3.0, p.collision_mask)
			q.exclude = [p.get_rid()]
			var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
			if hit.is_empty():
				print("  前方 高 %.2f: 3 m 內空" % h)
			else:
				var n: Vector3 = hit["normal"]
				print("  前方 高 %.2f: %.2f m 處 %s 法線坡 %.0f°" % [h, (hit["position"] - from).length(), (hit["collider"] as Node).name, rad_to_deg(n.angle_to(Vector3.UP))])
	print("done")
	quit(0)
