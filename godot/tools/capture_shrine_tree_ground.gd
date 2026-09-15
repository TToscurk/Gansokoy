extends SceneTree
## 神社樹木落地驗收：載入 shrine.tscn 直拍，境內 + 外圍林 + 天際線。

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
	var d := "D:/神社/shrine/_review/shrine_tree_ground/"
	DirAccess.make_dir_recursive_absolute(d)
	var scn = load("res://maps/shrine/shrine.tscn").instantiate()
	root.add_child(scn)
	await _wait(30)
	var cam := Camera3D.new()
	cam.far = 800.0
	scn.add_child(cam)
	cam.current = true

	# 1 參道正面（南入口往北看本殿）
	await _shoot(cam, Vector3(0, 6, 62), Vector3(0, 4, -20), d + "01_sando.png")
	# 2 境內邊緣林（東側，貼近地面看樹根）
	await _shoot(cam, Vector3(6, 6.0, -18), Vector3(34, 2.0, -22), d + "02_edge_east.png")
	# 3 境內邊緣林（西側樹根）
	await _shoot(cam, Vector3(-6, 6.0, -14), Vector3(-34, 2.0, -18), d + "03_edge_west.png")
	# 4 外圍森林 北（地形外那批）
	await _shoot(cam, Vector3(0, 45, -60), Vector3(0, 2, -125), d + "04_outer_north.png")
	# 5 外圍森林 東
	await _shoot(cam, Vector3(75, 45, 0), Vector3(125, 2, 0), d + "05_outer_east.png")
	# 6 高空鳥瞰整區
	await _shoot(cam, Vector3(0, 120, 150), Vector3(0, 0, -20), d + "06_aerial.png")
	# 7 低角天際線：天上不該有懸空樹
	await _shoot(cam, Vector3(-150, 40, 150), Vector3(0, 15, -30), d + "07_skyline.png")
	quit(0)
