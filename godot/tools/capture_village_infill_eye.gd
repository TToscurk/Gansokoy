extends SceneTree
## 村內補樹 人視角驗收。

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
	var scn = load("res://maps/slice/slice.tscn").instantiate()
	root.add_child(scn)
	await _wait(40)
	var cam := Camera3D.new()
	cam.far = 900.0
	scn.add_child(cam)
	cam.current = true

	# Repeatable south-entry review; no scene mutation or extra pipeline.
	if "--entrance" in OS.get_cmdline_user_args():
		var stage := "before" if "--before" in OS.get_cmdline_user_args() else "after"
		var pending: Array = [scn]
		while not pending.is_empty():
			var n: Node = pending.pop_back()
			pending.append_array(n.get_children())
			if n is MeshInstance3D and n.mesh != null and n.is_visible_in_tree():
				var bb: AABB = n.global_transform * n.mesh.get_aabb()
				if bb.position.x < 235.5 and bb.end.x > 235.5 and bb.position.z < 116 and bb.end.z > 116:
					print("ENTRY_SURFACE ", n.get_path(), " ", bb, " material ", n.material_override)
					if n.name == "UnifiedGround":
						var a: Array = n.mesh.surface_get_arrays(0)
						var nearest := 0
						var distance := INF
						for k in a[Mesh.ARRAY_VERTEX].size():
							var v: Vector3 = a[Mesh.ARRAY_VERTEX][k]
							var dist_sq := Vector2(v.x - 235.5, v.z - 116).length_squared()
							if dist_sq < distance:
								distance = dist_sq
								nearest = k
						print("ENTRY_NORMAL ", a[Mesh.ARRAY_NORMAL][nearest], " strength ", n.material_override.get_shader_parameter("entry_strength"))
			if n is MultiMeshInstance3D and n.multimesh != null and n.is_visible_in_tree():
				var mm: MultiMesh = n.multimesh
				var hits := 0
				for j in mm.instance_count:
					var p: Vector3 = n.global_transform * mm.get_instance_transform(j).origin
					if p.x > 231 and p.x < 240 and p.z > 98 and p.z < 128:
						hits += 1
				if hits > 0:
					print("ENTRY_REMAIN ", n.get_path(), " ", hits)

		await _shoot(cam, Vector3(235.3, 4.5, 126), Vector3(235.3, 2, 97.5), d + "entry_" + stage + ".png")
		await _shoot(cam, Vector3(252, 7, 116), Vector3(248, 0.5, 97.5), d + "wall_" + stage + ".png")
		quit(0)
		return

	# Wall-end review (stage 3).
	if "--wall" in OS.get_cmdline_user_args():
		var stage := "before" if "--before" in OS.get_cmdline_user_args() else "after"
		await _shoot(cam, Vector3(203, 2.4, 106), Vector3(210, 1.3, 97.5), d + "wallend_sw_" + stage + ".png")
		await _shoot(cam, Vector3(270, 2.4, 107), Vector3(265, 1.3, 97.5), d + "wallend_se_" + stage + ".png")
		await _shoot(cam, Vector3(204, 2.4, -86), Vector3(210, 1.3, -77), d + "wallend_nw_" + stage + ".png")
		await _shoot(cam, Vector3(268, 2.4, -86), Vector3(264, 1.3, -77), d + "wallend_ne_" + stage + ".png")
		await _shoot(cam, Vector3(268, 2.0, 93), Vector3(262, 1.4, 97.8), d + "wallend_se_inside_" + stage + ".png")
		await _shoot(cam, Vector3(236, 40, 150), Vector3(236, 0, 90), d + "wallend_top_s_" + stage + ".png")
		quit(0)
		return

	# Repeatable main-street review (stage 2 ground zoning).
	if "--street" in OS.get_cmdline_user_args():
		var stage := "before" if "--before" in OS.get_cmdline_user_args() else "after"
		await _shoot(cam, Vector3(235.0, 1.7, 80), Vector3(235.0, 1.2, -40), d + "street_s_" + stage + ".png")
		await _shoot(cam, Vector3(233.5, 1.6, -20), Vector3(240.5, 0.3, -32), d + "street_eave_" + stage + ".png")
		await _shoot(cam, Vector3(235.0, 28, 30), Vector3(235.0, 0, -10), d + "street_top_" + stage + ".png")
		await _shoot(cam, Vector3(234.0, 2.0, 50), Vector3(222, 0.8, 24), d + "street_plaza_" + stage + ".png")
		quit(0)
		return

	# 30 東側運河邊櫻花帶（人視角，沿帶往北看）
	await _shoot(cam, Vector3(266, 2.2, -60), Vector3(266, 3.0, 30), d + "30_canal_row_n.png")
	# 31 同帶往南看
	await _shoot(cam, Vector3(266, 2.2, 70), Vector3(266, 3.0, -20), d + "31_canal_row_s.png")
	# 32 從主街東側巷口望出去（樹是否從街上看得到）
	await _shoot(cam, Vector3(245, 2.0, 20), Vector3(272, 4.0, 20), d + "32_from_street_e.png")
	# 33 西側屋後帶
	await _shoot(cam, Vector3(203, 2.2, -60), Vector3(203, 3.0, 30), d + "33_west_row.png")
	# 34 主街往北（確認主街沒被樹擋）
	await _shoot(cam, Vector3(237, 2.2, 70), Vector3(237, 2.2, -60), d + "34_mainst.png")
	# 35 斜俯瞰東側帶
	await _shoot(cam, Vector3(290, 35, -70), Vector3(258, 2, 30), d + "35_east_obl.png")
	quit(0)
