extends SceneTree
## 神社南出口驗收：截圖 + 地面高程／碰撞探測。
## Godot --path godot --script tools/capture_shrine_exit.gd

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
	var d := "D:/神社/shrine/_review/shrine_exit/"
	DirAccess.make_dir_recursive_absolute(d)
	var scn: Node3D = load("res://maps/shrine/shrine.tscn").instantiate()
	root.add_child(scn)
	await _wait(40)
	# 沿主軸射線：地面碰撞高度（用實際物理）
	var space := scn.get_world_3d().direct_space_state
	var line := ""
	var gaps := 0
	for z in range(44, 80, 2):
		var q := PhysicsRayQueryParameters3D.create(Vector3(0, 20, z), Vector3(0, -30, z))
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			line += "%d:NONE " % z
			gaps += 1
		else:
			line += "%d:%.2f(%s) " % [z, hit.position.y, (hit.collider as Node).name]
	print("RAY_AXIS " + line + " gaps=%d" % gaps)
	# 走廊邊坡上的樹：與新地形高差
	var tmesh: ArrayMesh = (scn.get_node("Terrain") as MeshInstance3D).mesh
	var tv: PackedVector3Array = tmesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var off: Array = []
	var stack: Array = scn.get_node("植被").get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if not (n is Node3D):
			continue
		var parts := String(n.name).rsplit("_", true, 1)
		if not (parts.size() == 2 and parts[1].is_valid_int() and not (n is MeshInstance3D)):
			stack.append_array(n.get_children())
			continue
		var p: Vector3 = (n as Node3D).global_position
		if p.z < 46.0 or p.z > 95.0 or absf(p.x) > 27.0:
			continue
		var best := INF; var gy := 0.0
		for v in tv:
			var dd := (v.x - p.x) * (v.x - p.x) + (v.z - p.z) * (v.z - p.z)
			if dd < best: best = dd; gy = v.y
		if absf(p.y - gy) > 0.25 and p.z < 76.0:
			off.append({"path": String(scn.get_path_to(n)), "x": p.x, "y": p.y, "z": p.z, "gy": gy})
		elif p.z >= 76.0:
			# 圖外：對 Vista 網格
			var vv: PackedVector3Array = ((scn.get_node("Vista") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var vb := INF; var vy := 0.0
			for v in vv:
				var dd := (v.x - p.x) * (v.x - p.x) + (v.z - p.z) * (v.z - p.z)
				if dd < vb: vb = dd; vy = v.y
			if absf(p.y - vy) > 0.4:
				off.append({"path": String(scn.get_path_to(n)), "x": p.x, "y": p.y, "z": p.z, "gy": vy, "vista": true})
	print("TREE_OFFGROUND " + JSON.stringify(off))
	# 出口走廊南端是否被擋
	for z in [61.0, 63.0, 70.0, 75.0, 77.0]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(0, -3.0, z - 1.5), Vector3(0, -3.0, z + 1.5))
		var hit := space.intersect_ray(q)
		print("WALK z=%.0f %s" % [z, "BLOCKED by " + String((hit.collider as Node).name) if not hit.is_empty() else "clear"])
	var cam := Camera3D.new()
	cam.far = 900.0
	scn.add_child(cam)
	cam.current = true
	# --noshadow：關掉所有方向光陰影 + 拉高環境光，用來分辨「黑面」是陰影還是幾何
	if "--noshadow" in OS.get_cmdline_user_args():
		var st2: Array = [scn]
		while not st2.is_empty():
			var n: Node = st2.pop_back()
			st2.append_array(n.get_children())
			if n is DirectionalLight3D:
				(n as DirectionalLight3D).shadow_enabled = false
			if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
				var env: Environment = (n as WorldEnvironment).environment
				env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				env.ambient_light_color = Color(0.8, 0.8, 0.8)
				env.ambient_light_energy = 1.5
		d += "noshadow_"
		print("[V] noshadow mode")
	await _shoot(cam, Vector3(0.0, 0.6, 47.0), Vector3(0.0, -2.5, 70.0), d + "01_from_torii_down.png")
	await _shoot(cam, Vector3(0.0, -2.9, 76.0), Vector3(0.0, 1.0, 50.0), d + "02_from_bottom_up.png")
	await _shoot(cam, Vector3(9.0, 1.5, 62.0), Vector3(0.0, -2.5, 65.0), d + "03_side_stairs.png")
	await _shoot(cam, Vector3(0.0, 30.0, 95.0), Vector3(0.0, -2.0, 58.0), d + "04_aerial_gap.png")
	await _shoot(cam, Vector3(-3.0, 0.0, 56.0), Vector3(2.0, -1.0, 60.5), d + "05_lantern_torii2.png")
	# ⚠ 原本 (0,2.6,-20) 在拜殿月台（y≈3.5）底下，拍到的是石板背面、畫面倒轉
	await _shoot(cam, Vector3(0.0, 0.9, 0.0), Vector3(0.0, -2.0, 70.0), d + "06_from_court_axis.png")
	quit(0)
