extends SceneTree
## 拍一張「靈夢對話蓋在 3D 神社上」的實機圖（ART_REVIEW 用）。
func _init() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame; await process_frame
	main.load_map("shrine", "trail")
	for i in 30: await physics_frame; await process_frame
	root.get_node("/root/DayNight").set("flowing", false)
	root.get_node("/root/DayNight").call("set_hour", 11.0)
	var player: CharacterBody3D = main.player
	player.global_position = Vector3(0.6, 4.5, -19.5)
	player.rotation.y = 0.0
	for i in 40: await physics_frame; await process_frame
	var e := InputEventAction.new(); e.action = "interact"; e.pressed = true
	Input.parse_input_event(e)
	for i in 90: await physics_frame; await process_frame
	root.get_viewport().get_texture().get_image().save_png("D:/神社/shrine/work/shots/story_slice_reimu.png")
	print("[SHOT] saved")
	quit(0)
