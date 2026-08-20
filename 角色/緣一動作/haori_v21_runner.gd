extends Node3D
## Haori v2.1 Stage 6 stress test（真實按鍵注入）＋ Stage 7 效能記錄。

const SHOT_DIR := "D:/神社/shrine-yoriichi/角色/haori_work/v21_shots/"
var char_scene: PackedScene = preload("res://haori_v21_character.tscn")
var _char: CharacterBody3D
var _cam: Camera3D
var _perf: Array = []

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
	box.size = Vector3(80, 0.2, 80)
	cs.shape = box
	fb.add_child(cs)
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(80, 0.2, 80)
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

func _shot(fname: String, yaw_off := 0.0, dist := 2.7, height := 1.5, focus := 0.95) -> void:
	var yaw := _yaw() + yaw_off
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	_cam.global_position = _char.global_position + fwd * dist + Vector3(0, height, 0)
	_cam.look_at(_char.global_position + Vector3(0, focus, 0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + fname)
	var fps := Engine.get_frames_per_second()
	var pm := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_perf.append([fname, fps, snapped(pm, 0.01)])
	print("SHOT %s fps=%.0f phys=%.2f" % [fname, fps, pm])

func _fsb(prefix: String) -> void:
	await _shot(prefix + "_front.png", 0.0)
	await _shot(prefix + "_side.png", PI * 0.5)
	await _shot(prefix + "_back.png", PI)

func _run() -> void:
	# 1. Idle 10 秒
	for i in [3.0, 3.0, 3.0]:
		await get_tree().create_timer(i).timeout
		await _shot("01_idle_%02d.png" % _perf.size())
	await _fsb("01_idle")
	# 2. Walk
	_key(KEY_W, true)
	await get_tree().create_timer(1.2).timeout
	await _fsb("02_walk")
	await _shot("02_walk_hem_close.png", 0.0, 1.5, 0.7, 0.62)
	# 3. Run
	_key(KEY_SHIFT, true)
	await get_tree().create_timer(1.2).timeout
	await _fsb("03_run")
	await _shot("03_run_hem_close.png", 0.0, 1.5, 0.7, 0.65)
	# 4. W→D 90° 急轉
	_key(KEY_W, false); _key(KEY_D, true)
	await get_tree().create_timer(0.25).timeout
	await _shot("04_turn90_a.png")
	await get_tree().create_timer(0.4).timeout
	await _shot("04_turn90_b.png")
	# 5. D→A 180° 急轉
	_key(KEY_D, false); _key(KEY_A, true)
	await get_tree().create_timer(0.25).timeout
	await _shot("05_turn180_a.png")
	await get_tree().create_timer(0.45).timeout
	await _shot("05_turn180_b.png")
	# 6. Run → instant stop
	_key(KEY_A, false); _key(KEY_W, true)
	await get_tree().create_timer(1.0).timeout
	_key(KEY_W, false); _key(KEY_SHIFT, false)
	for i in 4:
		await get_tree().create_timer(0.18).timeout
		await _shot("06_stop_%d.png" % i)
	await get_tree().create_timer(0.6).timeout
	await _shot("06_stop_settled.png")
	# 7. Draw_Sword
	_key(KEY_Q, true)
	await get_tree().process_frame
	_key(KEY_Q, false)
	for i in 3:
		await get_tree().create_timer(0.3).timeout
		await _shot("07_draw_%d.png" % i)
	# 10. Draw 右袖 close-up
	await _shot("07_draw_sleeve_close.png", -PI * 0.3, 1.4, 1.5, 1.25)
	var waited := 0.0
	while _char.sword_state != 2 and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	# 8. DRAWN idle
	await get_tree().create_timer(0.6).timeout
	await _fsb("08_drawn_idle")
	# 9. DRAWN walking
	_key(KEY_W, true)
	await get_tree().create_timer(1.2).timeout
	await _fsb("09_drawnwalk")
	# 11. 大跨步 hem close-up（run）
	_key(KEY_SHIFT, true)
	await get_tree().create_timer(0.8).timeout
	await _shot("10_stride_hem_close.png", 0.0, 1.5, 0.7, 0.6)
	await _shot("10_stride_hem_side.png", PI * 0.5, 1.5, 0.7, 0.6)
	_key(KEY_W, false); _key(KEY_SHIFT, false)
	# perf 統計
	var fps_sum := 0.0; var pm_sum := 0.0
	for p in _perf:
		fps_sum += p[1]; pm_sum += p[2]
	print("PERF avg fps=%.1f avg phys=%.2fms n=%d" % [fps_sum / _perf.size(), pm_sum / _perf.size(), _perf.size()])
	print("PERFLOG ", JSON.stringify(_perf))
	print("V21 RUN DONE")
	get_tree().quit()
