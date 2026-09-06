extends SceneTree
## Is the east-river gap a stale collider, or two visible meshes overlapping?
## Read the VISIBLE geometry of every ground-like mesh under the sample points.

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _top_hit(mi: MeshInstance3D, x: float, z: float) -> float:
	var faces := mi.mesh.get_faces()
	var xf := mi.global_transform
	var best := NAN
	var i := 0
	while i + 2 < faces.size():
		var a: Vector3 = xf * faces[i]
		var b: Vector3 = xf * faces[i + 1]
		var c: Vector3 = xf * faces[i + 2]
		i += 3
		if x < minf(a.x, minf(b.x, c.x)) or x > maxf(a.x, maxf(b.x, c.x)):
			continue
		if z < minf(a.z, minf(b.z, c.z)) or z > maxf(a.z, maxf(b.z, c.z)):
			continue
		var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, 200, z), Vector3.DOWN, a, b, c)
		if hit != null:
			var y: float = (hit as Vector3).y
			if is_nan(best) or y > best:
				best = y
	return best

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "")
	await _wait(80)
	var mr: Node3D = main.map_root

	var meshes: Array = []
	for nm in ["UnifiedGround", "BasinHills", "EastRiverRevetment", "CanalBed", "BayBed"]:
		for n in mr.find_children(nm, "MeshInstance3D", true, false):
			meshes.append(n)
	print("[VIS] 比對的可見 mesh：%s" % str(meshes.map(func(m): return String(m.name))))
	for m in meshes:
		print("[VIS]   %-20s visible=%s" % [m.name, str((m as MeshInstance3D).visible)])

	for pt in [Vector2(445, -60), Vector2(460, -20), Vector2(430, -100), Vector2(445, -120)]:
		var line := "[VIS] (%4.0f, %5.0f)" % [pt.x, pt.y]
		for m in meshes:
			var y := _top_hit(m, pt.x, pt.y)
			line += "  %s=%s" % [m.name, ("%.2f" % y) if not is_nan(y) else "—"]
		print(line)
	quit(0)
