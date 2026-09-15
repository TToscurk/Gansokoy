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
	# ⚠ 2026-09-15：山犬戰鬥已取消，這裡不再需要避開遭遇區。
	#   玩家放在逃跑群旁 8 m（notice_range 7 m 外），拍它們縮著的樣子。
	#   座標是 r3 路線重排後的實測值（逃跑群 (2.6,-78)、受傷 (-1.5,-90.7)）。
	main.player.global_position = Vector3(6.0, 9.0, -84.0)
	main.player.velocity = Vector3.ZERO
	await _settle(30)
	await _skip_dialogue()
	await _settle(10)
	main.player.visible = false
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.far = 600.0
	# 逃跑群：實際位置用 group 查，不用算的
	var grp: Vector3 = Vector3(2.6, 7.0, -78.0)
	for k in main.get_tree().get_nodes_in_group("kedama"):
		if int(k.get("mode")) == 1:
			grp = (k as Node3D).global_position
			break
	print("[KD] 逃跑毛玉實際位置 (%.1f, %.2f, %.1f)" % [grp.x, grp.y, grp.z])
	cam.global_position = grp + Vector3(2.6, 1.1, 2.8)
	cam.look_at(grp + Vector3(0, 0.55, 0))
	await _settle(30)
	main.get_viewport().get_texture().get_image().save_png(OUT + "1_fleeing_group.png")
	print("[KD] shot 1_fleeing_group")
	# 臉部特寫：確認眼睛沒被毛埋掉
	cam.global_position = grp + Vector3(0.0, 0.62, 1.15)
	cam.look_at(grp + Vector3(0, 0.58, 0))
	await _settle(20)
	main.get_viewport().get_texture().get_image().save_png(OUT + "3_face.png")
	print("[KD] shot 3_face")
	# 受傷毛玉：實際位置用 group 查，不用算的
	var wounded: Node3D = null
	for k in main.get_tree().get_nodes_in_group("kedama"):
		if int(k.get("mode")) == 2:
			wounded = k
	if wounded == null:
		print("[KD] ✗ 找不到 WOUNDED 毛玉")
		quit(1)
		return
	var wp: Vector3 = wounded.global_position
	print("[KD] 受傷毛玉實際位置 (%.1f, %.2f, %.1f)" % [wp.x, wp.y, wp.z])
	cam.global_position = wp + Vector3(2.2, 1.3, 2.4)
	cam.look_at(wp + Vector3(0, 0.35, 0))
	await _settle(30)
	main.get_viewport().get_texture().get_image().save_png(OUT + "2_wounded.png")
	print("[KD] shot 2_wounded")
	quit(0)
