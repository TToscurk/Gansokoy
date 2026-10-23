extends SceneTree
## 回歸測試：這支「全骨頭都寫位置鍵」的打坐 clip，出定後會不會把坐姿的位置留下來？
##   <godot_console.exe> --path godot --script res://tools/_shot_meditate_exit.gd
##
## 風險：Idle／走路那些 clip 若只寫旋轉鍵，我寫的 22 根骨頭位置鍵就會殘留 →
## 角色「站起來但整個人還是矮一截」。用髖的世界高度量化：
##   站立 ≈ 0.95 m、打坐 ≈ 0.34 m。
const OUT := "D:/神社/shrine/work/shots/meditate_exit/"

var _main: Node
var _dm: Node
var _cam: Camera3D
var _player: Node3D


func _init() -> void:
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _shot(name: String) -> void:
	await _settle(4)
	await RenderingServer.frame_post_draw
	await process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("[EXIT] 拍 " + name)


func _drain() -> void:
	var g := 0
	while bool(_dm.call("is_active")) and g < 30:
		_dm.call("advance", -1)
		await _settle(1)
		g += 1


## 髖／頭／腳的世界高度（m）
func _heights(tag: String) -> void:
	var sk := _player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var line := "[EXIT] %s：" % tag
	for b in ["Hips", "Head", "LeftFoot", "LeftToeBase"]:
		var i := sk.find_bone(b)
		if i < 0:
			continue
		var w := sk.global_transform * sk.get_bone_global_pose(i)
		line += " %s=%.3f" % [b, w.origin.y]
	print(line)


func _run() -> void:
	_dm = root.get_node("/root/DialogueManager")
	var dn := root.get_node("/root/DayNight")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(8)
	var ui := root.find_child("DialogueUI", true, false)
	if ui != null:
		ui.set_process_unhandled_input(false)
		ui.set("typewriter_cps", 0.0)
	await _drain()
	_main.player.set("input_locked", false)
	_main.load_map("slice", "trail")
	await _settle(120)
	await _drain()
	_player = _main.player as Node3D
	_player.set("input_locked", false)
	dn.set("hour", 12.0)
	dn.set("pause_reasons", [] as Array[String])
	dn.set("flowing", false)
	await _settle(20)

	_cam = root.get_viewport().get_camera_3d()
	_cam.set_process(false)
	_cam.get_parent().set_process(false)
	_cam.global_position = _player.global_position + Vector3(0, 1.6, 3.2)
	_cam.look_at(_player.global_position + Vector3(0, 0.8, 0), Vector3.UP)

	_heights("冥想前（站姿）")
	await _shot("e1_before")
	_player.call("start_meditation_pose")
	await _settle(12)
	_heights("入定")
	await _shot("e2_sitting")
	_player.call("end_meditation_pose")
	await _settle(20)
	_heights("出定後 +0.3s")
	await _shot("e3_after_exit")
	await _settle(90)
	_heights("出定後 +1.8s")
	await _shot("e4_after_settle")

	# 再走兩步，確認走路 clip 有沒有把位置拉回來
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = true
	root.push_input(ev)
	await _settle(60)
	ev.pressed = false
	root.push_input(ev)
	await _settle(30)
	_heights("走幾步後")
	await _shot("e5_after_walk")
	quit(0)
