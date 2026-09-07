extends SceneTree

func _init() -> void:
	_test.call_deferred()

func _test() -> void:
	print("[DEBUG] Loading main.tscn")
	var packed = ResourceLoader.load("res://scenes/main.tscn")
	var main = packed.instantiate()
	root.add_child(main)
	print("[DEBUG] Main instantiated and added to root")
	for i in 5:
		await process_frame
	print("[DEBUG] Calling load_map('slice', '')")
	main.load_map("slice", "")
	print("[DEBUG] load_map finished calling")
	for i in 100:
		await process_frame
		await physics_frame
	var p = main.get_node("Player")
	print("[DEBUG] Player global_position: ", p.global_position)
	print("[DEBUG] Player input_yaw_node: ", p.input_yaw_node)
	if p.input_yaw_node:
		print("[DEBUG] input_yaw_node global_rotation: ", p.input_yaw_node.global_rotation)
	print("[DEBUG] Finished test")
	quit(0)
