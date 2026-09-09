extends SceneTree
## 獸道山犬實拍：確認狼生在路上、比例與環境相稱。
##   Godot --path godot --resolution 1280x720 --script tools/shot_trail_wolf.gd
const OUT := "D:/神社/shrine/work/shots/trail_wolf/"
var main: Node


func _init() -> void:
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	var dm: Node = root.get_node("/root/DialogueManager")
	# 開局獨白演完，否則玩家被鎖
	while dm.is_active():
		var e := InputEventAction.new()
		e.action = "ui_accept"; e.pressed = true
		Input.parse_input_event(e)
		await physics_frame
		e = InputEventAction.new()
		e.action = "ui_accept"; e.pressed = false
		Input.parse_input_event(e)
		await physics_frame
	await _settle(30)
	var dn: Node = root.get_node_or_null("/root/DayNight")
	if dn != null:
		dn.set("flowing", false)
		dn.call("set_hour", 11.0)
	# 走進遭遇區觸發生成
	main.player.global_position = Vector3(5.3, 9.0, -78.0)
	main.player.velocity = Vector3.ZERO
	await _settle(40)
	while dm.is_active():
		var e := InputEventAction.new()
		e.action = "ui_accept"; e.pressed = true
		Input.parse_input_event(e)
		await physics_frame
		e = InputEventAction.new()
		e.action = "ui_accept"; e.pressed = false
		Input.parse_input_event(e)
		await physics_frame
	await _settle(20)
	var wolves := main.get_tree().get_nodes_in_group("enemies")
	print("[TW] 場上山犬 %d 隻" % wolves.size())
	if wolves.is_empty():
		print("[TW] ✗ 沒生成")
		quit(1)
		return
	var w: Node3D = wolves[0]
	var p: Vector3 = w.global_position
	print("[TW] 狼位置 (%.1f, %.2f, %.1f) 玩家 (%.1f, %.2f, %.1f)"
		% [p.x, p.y, p.z, main.player.global_position.x, main.player.global_position.y,
		main.player.global_position.z])
	main.player.visible = false
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.far = 600.0
	var shots := [
		["1_approach", p + Vector3(2.0, 2.4, 9.0), p + Vector3(0, 1.0, 0)],
		["2_side", p + Vector3(-7.0, 1.8, 1.0), p + Vector3(0, 0.9, 0)],
		["3_wide", p + Vector3(6.0, 9.0, 16.0), p + Vector3(0, 0, -4)],
	]
	for s in shots:
		cam.global_position = s[1]
		cam.look_at(s[2])
		await _settle(30)
		var img := main.get_viewport().get_texture().get_image()
		img.save_png("%s%s.png" % [OUT, s[0]])
		print("[TW] shot %s" % s[0])
	quit(0)
