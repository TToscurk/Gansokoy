extends SceneTree
## Does the baked ground collision still match the merged (remote) slice
## geometry? Sample the visible mesh height vs the collision height along the
## east river / quay band the remote branch reworked (B2 r18-r20).

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "")
	await _wait(80)
	var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state
	var mr: Node3D = main.map_root

	# Collision height.
	var coll := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200.0, z), Vector3(x, -80.0, z))
		q.collide_with_areas = false
		var h: Dictionary = space.intersect_ray(q)
		return float(h.position.y) if h.has("position") else NAN

	# Visible ground mesh height: find the unified ground MeshInstance3D and
	# read its triangles via a mesh-space ray on the ArrayMesh faces.
	var ground_mi: MeshInstance3D = null
	for n in mr.find_children("*", "MeshInstance3D", true, false):
		var nm := String(n.name)
		if nm.contains("UnifiedGround") and not nm.contains("碰撞"):
			ground_mi = n
			break
	print("[CHK] 可見地面 mesh：%s" % (str(ground_mi.get_path()) if ground_mi else "找不到"))

	var faces: PackedVector3Array = ground_mi.mesh.get_faces() if ground_mi else PackedVector3Array()
	var xf: Transform3D = ground_mi.global_transform if ground_mi else Transform3D()
	print("[CHK] 地面三角面數：%d" % (faces.size() / 3))

	var visual := func(x: float, z: float) -> float:
		# Highest triangle hit under (x, z).
		var best := NAN
		var i := 0
		while i + 2 < faces.size():
			var a: Vector3 = xf * faces[i]
			var b: Vector3 = xf * faces[i + 1]
			var c: Vector3 = xf * faces[i + 2]
			i += 3
			# Quick reject on XZ bounds.
			if x < minf(a.x, minf(b.x, c.x)) or x > maxf(a.x, maxf(b.x, c.x)):
				continue
			if z < minf(a.z, minf(b.z, c.z)) or z > maxf(a.z, maxf(b.z, c.z)):
				continue
			var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, 200.0, z), Vector3.DOWN, a, b, c)
			if hit != null:
				var y: float = (hit as Vector3).y
				if is_nan(best) or y > best:
					best = y
		return best

	print("[CHK] === 東河／碼頭帶（遠端 B2 r18-r20 重做區）x 408-468 ===")
	var worst := 0.0
	var samples := 0
	var bad := 0
	for z in [-160.0, -140.0, -120.0, -100.0, -60.0, -20.0, 20.0, 60.0]:
		for x in [400.0, 415.0, 430.0, 445.0, 460.0]:
			var cy: float = coll.call(x, z)
			var vy: float = visual.call(x, z)
			if is_nan(cy) or is_nan(vy):
				continue
			var d := absf(cy - vy)
			samples += 1
			worst = maxf(worst, d)
			if d > 0.35:
				bad += 1
				print("[CHK]   x=%5.0f z=%6.0f  碰撞 y=%7.2f  可見 y=%7.2f  差 %.2f m" % [x, z, cy, vy, d])
	print("[CHK] 河岸帶取樣 %d 點，超過 0.35 m 的 %d 點，最大落差 %.2f m" % [samples, bad, worst])

	print("[CHK] === 主街（未動區）x 225-300 對照 ===")
	var worst2 := 0.0
	var n2 := 0
	for z in [-100.0, -40.0, 20.0, 80.0]:
		for x in [230.0, 250.0, 270.0, 290.0]:
			var cy: float = coll.call(x, z)
			var vy: float = visual.call(x, z)
			if is_nan(cy) or is_nan(vy):
				continue
			n2 += 1
			worst2 = maxf(worst2, absf(cy - vy))
	print("[CHK] 主街取樣 %d 點，最大落差 %.2f m" % [n2, worst2])
	quit(0)
