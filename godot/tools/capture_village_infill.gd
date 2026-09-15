extends SceneTree
## 人間之里村內空地探勘：拍街廓內部俯瞰與街景，找可種樹的位置。

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _shoot(cam: Camera3D, pos: Vector3, look: Vector3, path: String) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	await _wait(8)
	root.get_viewport().get_texture().get_image().save_png(path)
	print("[V] %s" % path)

func _run() -> void:
	var d := "D:/神社/shrine/_review/village_infill/"
	DirAccess.make_dir_recursive_absolute(d)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "trail")
	await _wait(90)
	var cam := Camera3D.new()
	cam.far = 900.0
	main.add_child(cam)
	cam.current = true

	# 街廓 BLOCK = x 200..270, z -72..112
	# 1 正上方俯瞰整個街廓
	await _shoot(cam, Vector3(235, 190, 20), Vector3(235, 0, 19), d + "01_block_top.png")
	# 2 北半街廓俯瞰
	await _shoot(cam, Vector3(235, 95, -95), Vector3(235, 0, -30), d + "02_block_north.png")
	# 3 南半街廓俯瞰
	await _shoot(cam, Vector3(235, 95, 140), Vector3(235, 0, 70), d + "03_block_south.png")
	# 4 主街人視角（往北）
	await _shoot(cam, Vector3(235, 2.4, 60), Vector3(235, 2.0, -40), d + "04_mainst_north.png")
	# 5 主街人視角（往南）
	await _shoot(cam, Vector3(235, 2.4, -40), Vector3(235, 2.0, 60), d + "05_mainst_south.png")
	# 6 西側屋後（人視角）
	await _shoot(cam, Vector3(207, 2.4, 10), Vector3(230, 2.0, 10), d + "06_west_back.png")
	# 7 東側屋後（人視角）
	await _shoot(cam, Vector3(265, 2.4, 10), Vector3(240, 2.0, 10), d + "07_east_back.png")
	quit(0)
