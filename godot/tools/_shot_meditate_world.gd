extends SceneTree
## 打坐姿勢在**遊戲世界**裡的驗收截圖（亮場、正面、貼地相機）。
##   <godot_console.exe> --path godot --script res://tools/_shot_meditate_world.gd
##
## ⚠ 角色（緣一）在骨架空間面朝 +Z（不是 Godot 慣例的 -Z），相機要擺 +Z 側才是正面。
## ⚠ 貼地相機（y≈0.02）是用來量「有沒有陷進地面」的：地面線切過身體就是穿地。
const OUT := "D:/神社/shrine/work/shots/meditate_world/"

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
	print("[W] 拍 " + name)


func _drain() -> void:
	var g := 0
	while bool(_dm.call("is_active")) and g < 30:
		_dm.call("advance", -1)
		await _settle(1)
		g += 1


func _look(offset: Vector3, target_h: float, tag: String) -> void:
	var o := _player.global_position
	_cam.global_position = o + offset
	_cam.look_at(o + Vector3(0, target_h, 0), Vector3.UP)
	print("[W] %s 相機=%s 看向 y=%.2f" % [tag, str((o + offset).snappedf(0.01)), target_h])
	await _shot(tag)


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

	# 站立參考（確認相機/地面基準沒問題）
	await _look(Vector3(0, 1.0, 3.0), 0.9, "w0_standing")
	_player.call("start_meditation_pose")
	await _settle(12)
	await _look(Vector3(0, 0.75, 2.6), 0.35, "w1_front")
	await _look(Vector3(1.9, 0.85, 1.9), 0.35, "w2_quarter")
	await _look(Vector3(2.6, 0.6, 0.2), 0.35, "w3_side")
	await _look(Vector3(0.0, 0.02, 2.2), 0.30, "w4_ground_level")
	await _look(Vector3(1.3, 1.6, 1.3), 0.30, "w5_high")
	quit(0)
