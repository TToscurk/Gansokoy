extends Node3D
## 獨立羽織（純骨架跟隨，無物理）動作測試：
## Idle / Walk / Run / 左右轉身 / Draw / DRAWN Walk ＋ 穿模診斷特寫。

const SHOT_DIR := "D:/神社/shrine-yoriichi/角色/haori_work/v2_haori_shots/"
var char_scene: PackedScene = preload("res://yoriichi_character_v2_haori_test.tscn")
var _char: CharacterBody3D
var _cam: Camera3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment = e
	add_child(env)
	var fb := StaticBody3D.new()
	fb.position = Vector3(0, -0.1, 0)
	add_child(fb)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	cs.shape = box
	fb.add_child(cs)
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(60, 0.2, 60)
	fm.mesh = bm
	fb.add_child(fm)
	_char = char_scene.instantiate()
	_char.position = Vector3(0, 0.5, 0)
	add_child(_char)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_run.call_deferred()

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _yaw() -> float:
	var vis := _char.find_children("*", "AnimationPlayer", true, false)[0].get_parent() as Node3D
	return vis.rotation.y

func _shot(fname: String, dist := 2.8, height := 1.5, focus_h := 0.95, yaw_off := 0.0) -> void:
	var yaw := _yaw() + yaw_off
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	_cam.global_position = _char.global_position + fwd * dist + Vector3(0, height, 0)
	_cam.look_at(_char.global_position + Vector3(0, focus_h, 0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + fname)
	print("SHOT ", fname, " pos=", _char.global_position.snapped(Vector3(0.01,0.001,0.01)),
		" floor=", _char.is_on_floor(), " state=", _char.sword_state)

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	await _shot("10_idle.png")
	await get_tree().create_timer(0.7).timeout
	await _shot("11_idle_b.png")
	# Walk
	_key(KEY_W, true)
	for i in 3:
		await get_tree().create_timer(0.42).timeout
		await _shot("12_walk_%d.png" % i)
	# 特寫：下擺 vs 袴 / 腿
	await get_tree().create_timer(0.2).timeout
	await _shot("12_walk_hem_close.png", 1.5, 0.7, 0.65)
	# Run
	_key(KEY_SHIFT, true)
	for i in 3:
		await get_tree().create_timer(0.32).timeout
		await _shot("13_run_%d.png" % i)
	await _shot("13_run_hem_close.png", 1.5, 0.7, 0.7)
	await _shot("13_run_side.png", 2.4, 1.3, 0.95, PI * 0.5)
	_key(KEY_SHIFT, false)
	# 左右轉身
	_key(KEY_W, false); _key(KEY_A, true)
	await get_tree().create_timer(0.3).timeout
	await _shot("14_turn_A.png")
	_key(KEY_A, false); _key(KEY_D, true)
	await get_tree().create_timer(0.5).timeout
	await _shot("14_turn_D.png")
	_key(KEY_D, false); _key(KEY_S, true)
	await get_tree().create_timer(0.5).timeout
	await _shot("14_turn_S.png")
	_key(KEY_S, false)
	await get_tree().create_timer(0.6).timeout
	# Draw
	_key(KEY_Q, true)
	await get_tree().process_frame
	_key(KEY_Q, false)
	for i in 3:
		await get_tree().create_timer(0.3).timeout
		await _shot("15_draw_%d.png" % i)
	# 特寫：右袖 vs 手臂
	await _shot("15_draw_sleeve_close.png", 1.4, 1.5, 1.25, -PI * 0.25)
	var waited := 0.0
	while _char.sword_state != 2 and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	await get_tree().create_timer(0.4).timeout
	await _shot("16_drawn_idle.png")
	# DRAWN walk
	_key(KEY_W, true)
	for i in 3:
		await get_tree().create_timer(0.42).timeout
		await _shot("17_drawnwalk_%d.png" % i)
	_key(KEY_W, false)
	# 背面/側面收尾
	await get_tree().create_timer(0.5).timeout
	await _shot("18_final_front.png")
	await _shot("18_final_back.png", 2.8, 1.5, 0.95, PI)
	await _shot("18_final_side.png", 2.8, 1.5, 0.95, PI * 0.5)
	print("HAORI ANIM DONE")
	get_tree().quit()
