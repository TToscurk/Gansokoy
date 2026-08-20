extends Node3D
const SHOT_DIR := "D:/神社/shrine-yoriichi/角色/haori_work/v2_haori_shots/"
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45,30,0); sun.light_energy = 1.2; add_child(sun)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.3,0.32,0.36)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.75,0.75,0.78); e.ambient_light_energy = 0.8
	env.environment = e; add_child(env)
	var body = (load("res://yoriichi_body_v2.fbx") as PackedScene).instantiate()
	add_child(body)
	var haori = (load("res://yoriichi_haori_v2_aligned.glb") as PackedScene).instantiate()
	add_child(haori)
	var cam := Camera3D.new(); add_child(cam); cam.current = true
	_seq.call_deferred(cam)
func _seq(cam: Camera3D) -> void:
	var views := {"front": Vector3(0,1.0,3.2), "back": Vector3(0,1.0,-3.2),
		"left": Vector3(3.2,1.0,0), "right": Vector3(-3.2,1.0,0)}
	for name in views:
		cam.global_position = views[name]
		cam.look_at(Vector3(0,0.95,0))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(SHOT_DIR + "static_" + name + ".png")
		print("SHOT ", name)
	print("STATIC DONE")
	get_tree().quit()
