extends Node3D
## Body v2 驗證 runner：實際注入鍵盤事件（Input.parse_input_event）走完
## Idle / W / Shift 跑 / 四方向快速轉向 / Q 拔刀 / DRAWN Idle / DRAWN Walk，
## 每階段截圖並檢查 root 位置、地板碰撞、socket 與動畫狀態。

const SHOT_DIR := "D:/神社/shrine-yoriichi/角色/haori_work/v2_body_shots/"
var char_scene: PackedScene = preload("res://yoriichi_character_v2.tscn")
var _char: CharacterBody3D
var _cam: Camera3D
var _log: Array = []

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
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0, -0.1, 0)
	add_child(floor_body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.2, 40)
	cs.shape = box
	floor_body.add_child(cs)
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 0.2, 40)
	fm.mesh = bm
	floor_body.add_child(fm)
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

func _visual_yaw() -> float:
	var vis := _char.find_children("*", "AnimationPlayer", true, false)[0].get_parent() as Node3D
	return vis.rotation.y

func _shot(fname: String) -> void:
	var yaw := _visual_yaw()
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	_cam.global_position = _char.global_position + fwd * 2.8 + Vector3(0, 1.5, 0)
	_cam.look_at(_char.global_position + Vector3(0, 0.95, 0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + fname)
	var p := _char.global_position
	var entry := [fname, snapped(p.x, 0.01), snapped(p.y, 0.001), snapped(p.z, 0.01),
		_char.is_on_floor(), _char.sword_state, Engine.get_frames_per_second()]
	_log.append(entry)
	print("SHOT ", entry)

func _run() -> void:
	var skel: Skeleton3D = _char.find_children("*", "Skeleton3D", true, false)[0]
	print("BONE_COUNT ", skel.get_bone_count())
	var hs: BoneAttachment3D = _char.find_children("HandSocket", "", true, false)[0]
	var ss: BoneAttachment3D = _char.find_children("SheathSocket", "", true, false)[0]
	print("SOCKETS hand=", hs.bone_name, "/", hs.bone_idx, " sheath=", ss.bone_name, "/", ss.bone_idx)
	await get_tree().create_timer(1.0).timeout
	var ap: AnimationPlayer = _char.find_children("*", "AnimationPlayer", true, false)[0]
	print("ANIMS ", ap.get_animation_list())
	await _shot("01_idle_a.png")
	await get_tree().create_timer(0.8).timeout
	await _shot("02_idle_b.png")
	# W 走路
	_key(KEY_W, true)
	for i in 3:
		await get_tree().create_timer(0.45).timeout
		await _shot("03_walk_%d.png" % i)
	# Shift 跑步
	_key(KEY_SHIFT, true)
	for i in 3:
		await get_tree().create_timer(0.35).timeout
		await _shot("04_run_%d.png" % i)
	_key(KEY_SHIFT, false)
	# 四方向快速轉向 W -> D -> S -> A
	_key(KEY_W, false); _key(KEY_D, true)
	await get_tree().create_timer(0.35).timeout
	await _shot("05_turn_D.png")
	_key(KEY_D, false); _key(KEY_S, true)
	await get_tree().create_timer(0.35).timeout
	await _shot("05_turn_S.png")
	_key(KEY_S, false); _key(KEY_A, true)
	await get_tree().create_timer(0.35).timeout
	await _shot("05_turn_A.png")
	_key(KEY_A, false)
	await get_tree().create_timer(0.6).timeout
	# Q 拔刀
	_key(KEY_Q, true)
	await get_tree().process_frame
	_key(KEY_Q, false)
	for i in 3:
		await get_tree().create_timer(0.3).timeout
		await _shot("06_draw_%d.png" % i)
	# 等 DRAWN
	var waited := 0.0
	while _char.sword_state != 2 and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	var sw_h: Node3D = _char.find_children("Sword_Hand", "", true, false)[0]
	var sw_s: Node3D = _char.find_children("Sword_Sheathed", "", true, false)[0]
	print("DRAWN state=", _char.sword_state, " hand_visible=", sw_h.visible, " sheath_visible=", sw_s.visible)
	await get_tree().create_timer(0.5).timeout
	await _shot("07_drawn_idle.png")
	# DRAWN 走路
	_key(KEY_W, true)
	for i in 3:
		await get_tree().create_timer(0.45).timeout
		await _shot("08_drawnwalk_%d.png" % i)
	_key(KEY_W, false)
	print("VLOG ", JSON.stringify(_log))
	print("VALIDATION DONE")
	get_tree().quit()
