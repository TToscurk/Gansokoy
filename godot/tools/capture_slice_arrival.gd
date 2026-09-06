extends SceneTree
## Shoot the slice arrival point so the entry can be judged on screen.

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _shoot(main: Node, cam: Camera3D, pos: Vector3, look: Vector3, path: String) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	await _wait(6)
	var img := main.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[SHOT] %s" % path)

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	# Arrive the way a player does: walking in from the trail.
	main.load_map("slice", "trail")
	await _wait(90)
	var player = main.get_node_or_null("Player")
	print("[SHOT] arrival=%s on_floor=%s" % [str(player.global_position), str(player.is_on_floor())])

	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	var p: Vector3 = player.global_position
	var dir := "D:/神社/shrine/_review/route_walk/"

	# 1. Over-the-shoulder from the arrival point, looking down the street.
	await _shoot(main, cam, p + Vector3(0, 3.2, -8.0), p + Vector3(0, 1.2, 40.0), dir + "slice_arrival.png")
	# 2. The north gate the player walks through.
	await _shoot(main, cam, Vector3(235, 6, -110), Vector3(235, 4, -70), dir + "slice_gate.png")
	# 3. Wide view of where the arrival sits relative to the village.
	await _shoot(main, cam, Vector3(180, 60, -160), Vector3(250, 0, 20), dir + "slice_overview.png")
	quit(0)
