extends SceneTree
## VistaTrees 只拍它自己：其他節點全隱藏，看 700 個實例到底長在哪。
##   Godot --path godot --script tools/shot_vista_trees_only.gd

const OUT := "D:/神社/shrine/_review/shrine_trees/"


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var scn: Node3D = load("res://maps/shrine/shrine.tscn").instantiate()
	root.add_child(scn)
	await _wait(20)
	var vt := scn.get_node("VistaTrees") as MultiMeshInstance3D
	print("VT aabb=%s custom=%s" % [vt.get_aabb(), vt.custom_aabb])
	# 其他所有 Node3D 子節點隱藏，只留 VistaTrees
	for c in scn.get_children():
		if c is Node3D and c != vt:
			(c as Node3D).visible = false
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.9, 0.35, 0.35)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.6
	env.environment = e
	scn.add_child(env)
	var cam := Camera3D.new()
	cam.far = 4000.0
	scn.add_child(cam)
	cam.current = true
	# 俯視全圖
	cam.global_position = Vector3(0.0, 700.0, 620.0)
	cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	await _wait(10)
	root.get_viewport().get_texture().get_image().save_png(OUT + "vista_trees_only_wide.png")
	# 近看原點
	cam.global_position = Vector3(0.0, 12.0, 45.0)
	cam.look_at(Vector3(0.0, 4.0, 0.0), Vector3.UP)
	await _wait(10)
	root.get_viewport().get_texture().get_image().save_png(OUT + "vista_trees_only_origin.png")
	print("[V] saved")
	quit(0)
