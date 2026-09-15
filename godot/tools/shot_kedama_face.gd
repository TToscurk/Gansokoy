extends SceneTree
## 毛玉造型正面照（獨立場景，不載地圖）——只驗造型，不受地形／光照干擾。
##   Godot --rendering-method gl_compatibility --path godot --resolution 1280x720 --script tools/shot_kedama_face.gd

const OUT := "D:/神社/shrine/work/shots/kedama/"

func _init() -> void:
	_run.call_deferred()

func _settle(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.20, 0.24, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.72)
	e.ambient_light_energy = 1.1
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 150, 0)
	sun.light_energy = 1.3
	world.add_child(sun)

	var k: Node3D = (load("res://characters/yokai/kedama.tscn") as PackedScene).instantiate()
	world.add_child(k)
	k.position = Vector3.ZERO
	await _settle(6)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	# 毛玉本體在 hover_height=0.55、半徑 0.32 → 中心 y≈0.55
	# 站 1.6 m 外拍正面（毛玉正面是 +z）
	cam.global_position = Vector3(0.0, 0.62, 1.6)
	cam.look_at(Vector3(0.0, 0.55, 0.0))
	await _settle(12)
	get_root().get_texture().get_image().save_png(OUT + "4_face_clean.png")
	print("[KDF] 正面照 4_face_clean")

	# 45 度側前方，看毛與臉的交界
	cam.global_position = Vector3(1.15, 0.85, 1.15)
	cam.look_at(Vector3(0.0, 0.55, 0.0))
	await _settle(8)
	get_root().get_texture().get_image().save_png(OUT + "5_face_45.png")
	print("[KDF] 斜側照 5_face_45")
	quit(0)
