extends SceneTree
## 專門拍先前浮空那兩棵的位置（村西北角 189.9,-191.7 / 206.7,-210.6），
## 以及被種到長屋屋頂的兩棵盆樹，確認已貼地。

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _shoot(main: Node, cam: Camera3D, pos: Vector3, look: Vector3, path: String) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	await _wait(8)
	main.get_viewport().get_texture().get_image().save_png(path)
	print("[V] %s" % path)

func _run() -> void:
	var d := "D:/神社/shrine/_review/float_fix/"
	DirAccess.make_dir_recursive_absolute(d)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "trail")
	await _wait(90)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true

	# 1. 大衫 #7 舊位置 (189.9, -191.7)：地平線要乾淨，天上不能有樹
	await _shoot(main, cam, Vector3(189.9, 6.0, -170.0), Vector3(189.9, 3.0, -200.0),
		d + "01_nw_corner.png")
	# 2. 同一區拉高看天空，先前那兩棵飄在 y=55
	await _shoot(main, cam, Vector3(210.0, 12.0, -160.0), Vector3(195.0, 30.0, -205.0),
		d + "02_nw_skyline.png")
	# 3. 普通樹 #5 舊位置 (206.7, -210.6)
	await _shoot(main, cam, Vector3(206.7, 5.0, -185.0), Vector3(206.7, 3.0, -215.0),
		d + "03_north_edge.png")
	# 4. 盆樹 #4 (212.7, 1.6)：先前站在長屋屋頂
	await _shoot(main, cam, Vector3(206.0, 4.0, 1.6), Vector3(214.0, 1.5, 1.6),
		d + "04_bonsai_lane.png")
	# 5. 盆樹 #10 (213.8, 66.2)
	await _shoot(main, cam, Vector3(207.0, 4.0, 66.2), Vector3(215.0, 1.5, 66.2),
		d + "05_bonsai_lane2.png")
	quit(0)
