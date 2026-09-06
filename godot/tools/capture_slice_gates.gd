extends SceneTree
## Shoot the three slice gates so their placement can be judged on screen.

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _shoot(main: Node, cam: Camera3D, pos: Vector3, look: Vector3, path: String) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	await _wait(8)
	main.get_viewport().get_texture().get_image().save_png(path)
	print("[G] %s" % path)

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	# Arrive as a player would: walking in from the trail.
	main.load_map("slice", "trail")
	await _wait(90)
	var player = main.get_node_or_null("Player")
	print("[G] 獸道落點=%s on_floor=%s" % [str(player.global_position), str(player.is_on_floor())])

	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var d := "D:/神社/shrine/_review/route_walk/"
	var p: Vector3 = player.global_position

	# 1. Arrival: behind the player, looking north up the street through the torii.
	await _shoot(main, cam, p + Vector3(0, 3.4, 12.0), p + Vector3(0, 2.0, -30.0), d + "gate_trail.png")
	# 2. The same spot seen from outside — grass and stone rows.
	await _shoot(main, cam, Vector3(236, 5, 140), Vector3(236, 3, 100), d + "gate_trail_outside.png")
	# 3. 稗田邸 gate: north end of the street.
	await _shoot(main, cam, Vector3(234, 5, -108), Vector3(233, 6, -140), d + "gate_hieda.png")
	# 4. 香霖堂 gate: the dragon bridge, seen from the east bank.
	await _shoot(main, cam, Vector3(470, 8, -128), Vector3(420, 2, -148), d + "gate_kourindou.png")
	# 5. Dragon statue + bridge together, to confirm the gate sits by them.
	await _shoot(main, cam, Vector3(430, 30, -95), Vector3(400, 0, -155), d + "gate_dragon_wide.png")
	quit(0)
