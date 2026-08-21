extends SceneTree
# Windowed screenshot run for the AnimationTree-layered controller.
# Key evidence: upper/lower layering (legs run while drawing), run turn,
# split jump (fast start / fall), roll from run, air attack.
# Output: 角色/gameplay_bugfix_review/tree_combat_v4/

const OUT := "D:/神社/shrine-yoriichi/角色/gameplay_bugfix_review/tree_combat_v4/"

class Driver extends Node:
	var chr: CharacterBody3D

	func _ready() -> void:
		run()

	func wait(s: float) -> void:
		await get_tree().create_timer(s).timeout

	func key(code: Key, pressed: bool) -> void:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)

	func click(btn: MouseButton) -> void:
		var ev := InputEventMouseButton.new()
		ev.button_index = btn
		ev.pressed = true
		Input.parse_input_event(ev)
		var up := InputEventMouseButton.new()
		up.button_index = btn
		up.pressed = false
		Input.parse_input_event(up)

	func shot(name: String) -> void:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(OUT + name + ".png")
		print("shot ", name)

	func recenter(z := 8.0) -> void:
		for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT]:
			key(k, false)
		chr.velocity = Vector3.ZERO
		chr.global_position = Vector3(0, 0.2, z)
		await wait(0.4)

	func run() -> void:
		await wait(0.6)
		# 1. 邊跑邊拔刀：腿 Run、上半身 Draw（分層證據）
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.5)
		key(KEY_Q, true)
		key(KEY_Q, false)
		await wait(0.18)
		await shot("01_run_draw_upper_layer")
		await wait(0.6)
		# 2. 邊跑邊斬（upper 輕攻擊 + Run legs）
		click(MOUSE_BUTTON_LEFT)
		await wait(0.15)
		await shot("02_run_attack_upper_layer")
		await wait(0.6)
		# 3. Run Turn
		key(KEY_W, false)
		key(KEY_A, true)
		await wait(0.12)
		await shot("03_run_turn")
		await recenter()
		# 4. Jump：快起跳與 Fall 段
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.5)
		key(KEY_SPACE, true)
		key(KEY_SPACE, false)
		await wait(0.42)
		await shot("04_jump_rise")
		await wait(0.35)
		await shot("05_jump_fall_state")
		await wait(0.8)
		await recenter()
		# 5. 跑步中 Roll（3.2 m）
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.5)
		key(KEY_SHIFT, false)
		await wait(0.05)
		key(KEY_SHIFT, true)
		await wait(0.05)
		key(KEY_SHIFT, false)
		await wait(0.2)
		await shot("06_roll_from_run")
		await wait(0.5)
		await recenter()
		# 6. 空中攻擊
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.5)
		key(KEY_SPACE, true)
		key(KEY_SPACE, false)
		await wait(0.35)
		click(MOUSE_BUTTON_LEFT)
		await wait(0.12)
		await shot("07_air_attack")
		await wait(1.0)
		# 7. 跑步中收刀
		click(MOUSE_BUTTON_LEFT)   # 若已 SHEATHED 則 quick-draw；確保 DRAWN
		await wait(1.2)
		key(KEY_Q, true)
		key(KEY_Q, false)
		await wait(0.3)
		await shot("08_run_sheathe_upper_layer")
		await wait(0.6)
		get_tree().quit()

func _initialize():
	DirAccess.make_dir_recursive_absolute(OUT)
	var level := Node3D.new()
	root.add_child(level)

	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 0.2, 40)
	cs.shape = bs
	floor_body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(40, 0.2, 40)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.5, 0.4)
	mi.material_override = mat
	floor_body.add_child(mi)
	floor_body.position.y = -0.1
	level.add_child(floor_body)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	level.add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment = e
	level.add_child(env)

	var chr: CharacterBody3D = (load("res://yoriichi_character_meshy_full.tscn") as PackedScene).instantiate()
	chr.position = Vector3(0, 0.5, 8)
	level.add_child(chr)

	# 固定側面相機：涵蓋 -Z 方向的跑動路徑。
	var cam := Camera3D.new()
	var cam_pos := Vector3(11.0, 3.0, 1.0)
	var cam_target := Vector3(0, 1.0, 1.0)
	cam.transform = Transform3D(Basis.looking_at(cam_target - cam_pos, Vector3.UP), cam_pos)
	level.add_child(cam)
	cam.current = true

	var d := Driver.new()
	d.chr = chr
	root.add_child(d)
