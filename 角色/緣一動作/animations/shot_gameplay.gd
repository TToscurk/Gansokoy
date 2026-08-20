extends SceneTree
# Windowed screenshot run: fixed side camera, captures roll displacement,
# jump phases and combo. Output: 角色/gameplay_bugfix_review/roll_jump_v2/

const OUT := "D:/神社/shrine-yoriichi/角色/gameplay_bugfix_review/roll_jump_v2/"

class Driver extends Node:
	var chr: CharacterBody3D

	func _ready() -> void:
		run()

	func wait(s: float) -> void:
		await get_tree().create_timer(s).timeout

	func shot(name: String) -> void:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(OUT + name + ".png")
		print("shot ", name)

	func run() -> void:
		await wait(0.6)
		await shot("01_roll_start")
		chr.request_dodge(Vector3(0, 0, -1))
		await wait(0.45)
		await shot("02_roll_mid")
		await wait(0.9)
		await shot("03_roll_end_no_snapback")
		await wait(0.4)
		chr.request_jump()
		await wait(0.35)
		await shot("04_jump_crouch")
		await wait(0.45)
		await shot("05_jump_air")
		await wait(1.2)
		await shot("06_jump_landed")
		chr.request_draw()
		await wait(1.3)
		chr.request_primary_attack()
		await wait(0.1)
		chr.request_primary_attack()
		chr.request_primary_attack()
		await wait(0.15)
		await shot("07_combo_mid")
		await wait(0.6)
		await shot("08_combo_recovered")
		get_tree().quit()

func _initialize():
	DirAccess.make_dir_recursive_absolute(OUT)
	var level := Node3D.new()
	root.add_child(level)

	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(30, 0.2, 30)
	cs.shape = bs
	floor_body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(30, 0.2, 30)
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
	chr.position = Vector3(0, 0.5, 0)
	level.add_child(chr)

	# Fixed side camera covering the whole 6.4 m roll path (z 0 → -6.4).
	var cam := Camera3D.new()
	var cam_pos := Vector3(9.5, 2.6, -3.2)
	var cam_target := Vector3(0, 0.9, -3.2)
	cam.transform = Transform3D(Basis.looking_at(cam_target - cam_pos, Vector3.UP), cam_pos)
	level.add_child(cam)
	cam.current = true

	var d := Driver.new()
	d.chr = chr
	root.add_child(d)
