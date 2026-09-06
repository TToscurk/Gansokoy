extends SceneTree
## Shoot each floor of 稗田邸 from the player's arrival point.

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
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var d := "D:/神社/shrine/_review/route_walk/"

	for spec in [["hieda1f", "slice"], ["hieda2f", "hieda1f"], ["hieda3f", "hieda2f"]]:
		var id: String = spec[0]
		main.load_map(id, spec[1])
		await _wait(70)
		var player = main.get_node_or_null("Player")
		player.visible = false
		var p: Vector3 = player.global_position
		# Shoot the direction the player actually faces on arrival (arrival_yaw),
		# not a hardcoded -z — 3F faces +x down the aisle.
		var fwd: Vector3 = -player.global_transform.basis.z
		cam.global_position = p + Vector3(0, 1.6, 0)
		cam.look_at(p + Vector3(0, 1.3, 0) + fwd * 8.0, Vector3.UP)
		cam.fov = 80.0
		await _wait(8)
		main.get_viewport().get_texture().get_image().save_png(d + id + "_a.png")
		# Second angle: stay UNDER the ceiling (an overhead shot just films the
		# roof) and back off along +z, tilted down to read the room's layout.
		cam.global_position = p + Vector3(0, 2.6, 0) - fwd * 7.0
		cam.look_at(p + Vector3(0, 0.6, 0) + fwd * 4.0, Vector3.UP)
		await _wait(8)
		main.get_viewport().get_texture().get_image().save_png(d + id + "_b.png")
		print("[HF] %s arrival=%s → %s_a.png / %s_b.png" % [id, str(p), id, id])
	quit(0)
