extends SceneTree
# Windowed screenshot run for the AnimationTree-layered controller.
# Key evidence: upper/lower layering (legs run while drawing), run turn,
# split jump (fast start / fall), roll from run, air attack.
# Output: 角色/gameplay_bugfix_review/tree_combat_v4/

const OUT := "D:/神社/shrine-yoriichi/角色/gameplay_bugfix_review/eight_dir_v5/"

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
		# 1. 左前側身追擊跑（RunFL sector）
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.6)
		key(KEY_A, true)
		await wait(0.12)
		await shot("01_run_fl_sector")
		key(KEY_A, false)
		await wait(0.4)
		# 2. 右前
		key(KEY_D, true)
		await wait(0.12)
		await shot("02_run_fr_sector")
		key(KEY_D, false)
		await recenter()
		# 3. BackPedal（Walking 反播）
		key(KEY_W, true)
		await wait(0.5)
		key(KEY_W, false)
		key(KEY_S, true)
		await wait(0.1)
		await shot("03_backpedal")
		key(KEY_S, false)
		await recenter()
		# 4. 居合拔刀斬：LMB from SHEATHED，離鞘瞬間接斬擊
		click(MOUSE_BUTTON_LEFT)
		await wait(0.32)
		await shot("04_iai_quick_draw")
		await wait(0.8)
		# 5. Dodge counter：翻滾中按 LMB，roll 結束反擊
		key(KEY_SHIFT, true)
		await wait(0.05)
		key(KEY_SHIFT, false)
		await wait(0.15)
		click(MOUSE_BUTTON_LEFT)
		await wait(0.35)
		await shot("05_dodge_counter")
		await wait(0.8)
		# 6. 剝離位移後的 Run_Turn（不再拖離碰撞體）
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.6)
		key(KEY_W, false)
		key(KEY_A, true)
		await wait(0.15)
		await shot("06_run_turn_stripped")
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
