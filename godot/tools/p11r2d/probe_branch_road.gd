extends SceneTree
## P11 R2D：支線の碰撞形（Br*）と可見網格（Branches）が道路 ribbon の面に入る量（路面と重なる水平面積の目安：点数）。
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	var tris: Array = []
	for mi: MeshInstance3D in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or String(v.get_path_to(mi)).begins_with("Roads/Bridges"):
			continue
		var f := mi.mesh.get_faces()
		for t in range(0, f.size(), 3):
			var a := mi.global_transform * f[t]
			var b := mi.global_transform * f[t + 1]
			var c := mi.global_transform * f[t + 2]
			tris.append([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), String(mi.name)])
	var on_road := func(p: Vector2) -> String:
		for t in tris:
			if Geometry2D.point_is_inside_triangle(p, t[0], t[1], t[2]):
				return t[3]
		return ""
	var zw := v.get_node("Districts/FarmlandEast/FarmlandP8/Irrigation/ZoneWater")
	var hits := {}
	for cs in zw.get_children():
		if not String(cs.name).begins_with("Br"):
			continue
		var s := cs as CollisionShape3D
		var bx := (s.shape as BoxShape3D).size
		for i in 5:
			for j in 5:
				var lp := Vector3((i / 4.0 - 0.5) * bx.x, 0, (j / 4.0 - 0.5) * bx.z)
				var w := s.global_transform * lp
				var r: String = on_road.call(Vector2(w.x, w.z))
				if r != "":
					hits[String(s.name) + "→" + r] = int(hits.get(String(s.name) + "→" + r, 0)) + 1
	print("[BRD] 碰撞形 Br* の 5×5 取樣点が道路面に入る：%d 形 %s" % [hits.size(), str(hits)])
	var vh := {}
	for mi: MeshInstance3D in v.get_node("Districts/FarmlandEast/FarmlandP8/ZoneWorks/ZoneIrrigation/Branches").find_children("*", "MeshInstance3D", true, false):
		for sidx in mi.mesh.get_surface_count():
			for q: Vector3 in mi.mesh.surface_get_arrays(sidx)[Mesh.ARRAY_VERTEX]:
				var w := mi.global_transform * q
				var r: String = on_road.call(Vector2(w.x, w.z))
				if r != "":
					vh[r] = int(vh.get(r, 0)) + 1
	print("[BRD] 可見網格の頂点が道路面内：%s" % str(vh))
	quit(0)
