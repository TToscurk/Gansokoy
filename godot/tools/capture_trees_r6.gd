extends SceneTree
## 拍村緣樹群換成 Tripo 資產後的實況，供視覺驗收。

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
	print("[T] %s" % path)

func _run() -> void:
	var d := "D:/神社/shrine/_review/trees_r6/"
	DirAccess.make_dir_recursive_absolute(d)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "trail")
	await _wait(90)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true

	# 關掉 UI 與開場對話，否則俯瞰圖被對話框吃掉一半
	for ui_name in ["UI", "HUD", "CanvasLayer", "DialogueUI", "OpeningFade"]:
		var u: Node = main.find_child(ui_name, true, false)
		if u != null and u is CanvasItem:
			(u as CanvasItem).visible = false
	for c in main.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	await _wait(4)

	# 1. 玩家從獸道進村的第一眼——村緣林在左右兩側
	var player = main.get_node_or_null("Player")
	if player != null:
		var p: Vector3 = player.global_position
		await _shoot(main, cam, p + Vector3(0, 3.4, 12.0), p + Vector3(0, 2.0, -30.0),
			d + "01_arrival.png")

	# 2. 西側林緣（密度最高處），平視
	await _shoot(main, cam, Vector3(150.0, 8.0, 40.0), Vector3(190.0, 10.0, 0.0),
		d + "02_west_edge.png")
	# 3. 村北，稗田邸方向的林相
	await _shoot(main, cam, Vector3(200.0, 10.0, -170.0), Vector3(250.0, 8.0, -120.0),
		d + "03_north.png")
	# 4. 高空俯瞰整個村緣樹群分布
	await _shoot(main, cam, Vector3(210.0, 130.0, 120.0), Vector3(225.0, 0.0, 0.0),
		d + "04_overview.png")
	# 5. 主街南望借景走廊——確認樹沒有擋掉遠峰構圖
	await _shoot(main, cam, Vector3(235.0, 4.0, 60.0), Vector3(235.0, 8.0, 220.0),
		d + "05_sight_corridor.png")
	# 6. 近拍單棵，看新資產的網格與貼圖品質
	await _shoot(main, cam, Vector3(168.0, 6.0, -14.0), Vector3(178.0, 8.0, -14.0),
		d + "06_closeup.png")
	quit(0)
