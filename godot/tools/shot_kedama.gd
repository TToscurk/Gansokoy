extends SceneTree
## 毛玉實拍：受傷姿態 + 逃跑群，與緣一比例。
##   Godot --path godot --resolution 1280x720 --script tools/shot_kedama.gd
const OUT := "D:/神社/shrine/work/shots/kedama/"
var main: Node


func _init() -> void:
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _skip_dialogue() -> void:
	var dm: Node = root.get_node("/root/DialogueManager")
	while dm.is_active():
		var e := InputEventAction.new()
		e.action = "ui_accept"; e.pressed = true
		Input.parse_input_event(e)
		await physics_frame
		e = InputEventAction.new()
		e.action = "ui_accept"; e.pressed = false
		Input.parse_input_event(e)
		await physics_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	await _skip_dialogue()
	await _settle(30)
	var dn: Node = root.get_node_or_null("/root/DayNight")
	if dn != null:
		dn.set("flowing", false)
		dn.call("set_hour", 11.0)
	# 站在逃跑群旁但在 notice_range 外（8 m），拍它們縮著的樣子
	main.player.global_position = Vector3(4.2, 9.0, -86.0)
	main.player.velocity = Vector3.ZERO
	await _settle(30)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.far = 600.0
	# 逃跑群
	cam.global_position = Vector3(6.5, 9.5, -90.0)
	cam.look_at(Vector3(4.2, 8.3, -95.0))
	await _settle(30)
	main.get_viewport().get_texture().get_image().save_png(OUT + "1_fleeing_group.png")
	print("[KD] shot 1_fleeing_group")
	# 受傷毛玉（在 (3.7+2.4, -101-2) = (6.1, -103)）
	cam.global_position = Vector3(8.5, 9.2, -100.5)
	cam.look_at(Vector3(6.1, 8.2, -103.0))
	await _settle(30)
	main.get_viewport().get_texture().get_image().save_png(OUT + "2_wounded.png")
	print("[KD] shot 2_wounded")
	quit(0)
