extends SceneTree
## 村內補樹驗收：直載 slice.tscn（無 HUD/對話框），拍新樹所在的實際位置。

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
	var scn = load("res://maps/slice/slice.tscn").instantiate()
	root.add_child(scn)
	await _wait(40)
	var cam := Camera3D.new()
	cam.far = 900.0
	scn.add_child(cam)
	cam.current = true

	# 補樹節點的實際位置，逐一取來拍
	var infill: Node = scn.get_node_or_null("VillageInfillTrees")
	if infill == null:
		print("找不到 VillageInfillTrees")
		quit(1)
		return
	print("補樹 %d 棵" % infill.get_child_count())

	# 街廓俯瞰（無 HUD）
	await _shoot(cam, Vector3(238, 130, 20), Vector3(238, 0, 19), d + "10_top.png")
	# 東側屋後帶（櫻花/普通樹多在 x 260..272）
	await _shoot(cam, Vector3(266, 30, -95), Vector3(266, 2, -20), d + "11_east_row.png")
	await _shoot(cam, Vector3(266, 30, 55), Vector3(266, 2, 115), d + "12_east_north.png")

	# 挑前 6 棵樹做人視角近拍
	var kids: Array = infill.get_children()
	kids.reverse()   # 盆樹在後半段，反過來先拍小株
	var i := 0
	for c in kids:
		if i >= 6:
			break
		var p: Vector3 = (c as Node3D).global_position
		await _shoot(cam, p + Vector3(13, 9.0, 13), p + Vector3(0, 1.5, 0),
			d + "20_tree_%02d_%s.png" % [i, c.name.left(3)])
		i += 1
	quit(0)
