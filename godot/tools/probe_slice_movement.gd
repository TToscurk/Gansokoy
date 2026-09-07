extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- Starting slice locomotion probe ---")
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main: Node = packed.instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
		await physics_frame
	
	main.load_map("slice", "")
	for i in 60:
		await process_frame
		await physics_frame
		
	var player = main.get_node("Player")
	print("Player pos: ", player.global_position)
	print("Player rotation: ", player.rotation)
	var visual = player.get("_visual")
	print("Visual: ", visual)
	if visual:
		print("Visual rotation: ", visual.rotation)
	var input_yaw_node = player.get("input_yaw_node")
	print("input_yaw_node: ", input_yaw_node)
	if input_yaw_node:
		print("input_yaw_node rotation: ", input_yaw_node.rotation)
		print("input_yaw_node global_rotation: ", input_yaw_node.global_rotation)

	var tree = player.get_node_or_null("Tree") as AnimationTree
	var pb = tree.get("parameters/loco/playback") if tree else null
	print("Initial loco node: ", pb.get_current_node() if pb else "null")

	# Test pressing W (move_forward)
	print("\n--- Pressing move_forward ---")
	Input.action_press("move_forward")
	for i in 30:
		await physics_frame
		await process_frame
		if i % 10 == 0:
			print("Frame ", i, ":")
			print("  velocity: ", player.velocity)
			print("  visual.rotation.y: ", visual.rotation.y if visual else 0.0)
			print("  loco state: ", pb.get_current_node() if pb else "null")
			var yaw: float = visual.rotation.y if visual else 0.0
			var fwd := Vector2(sin(yaw), cos(yaw))
			var left := Vector2(-cos(yaw), sin(yaw))
			var lv := Vector2(player.velocity.x, player.velocity.z)
			var nd := lv.normalized()
			var ang := rad_to_deg(atan2(nd.dot(left), nd.dot(fwd)))
			print("  ang: ", ang, " dot(left): ", nd.dot(left), " dot(fwd): ", nd.dot(fwd))

	Input.action_release("move_forward")
	print("\n--- Finished probe ---")
	quit(0)
