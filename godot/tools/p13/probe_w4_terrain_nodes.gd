extends SceneTree
## P13 Wave 4：Terrain 以下の MeshInstance3D を列挙し、参道の中心付近 (280,−190) を含む AABB のものと頂点密度を表示（唯讀、headless）
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	var pt := Vector3(280.0, 10.0, -190.0)
	var n_all := 0
	for mi in v.get_node("Terrain").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		n_all += 1
		var ab: AABB = m.global_transform * m.get_aabb()
		var cov := Vector2(pt.x, pt.z)
		var inside := cov.x >= ab.position.x and cov.x <= ab.end.x and cov.y >= ab.position.z and cov.y <= ab.end.z
		var tris := 0
		var vcount := 0
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			vcount += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var mat := "-"
		if m.material_override is ShaderMaterial:
			mat = (m.material_override as ShaderMaterial).shader.resource_path.get_file()
		if inside or n_all <= 12:
			print("[W4N] %s｜頂点 %d・三角形 %d・AABB (%.0f,%.0f)–(%.0f,%.0f) y %.0f–%.0f｜%s｜%s" % [String(v.get_path_to(m)), vcount, tris, ab.position.x, ab.position.z, ab.end.x, ab.end.z, ab.position.y, ab.end.y, mat, "←参道を含む" if inside else ""])
	print("[W4N] Terrain 以下の MeshInstance3D 合計 %d" % n_all)
	var col := v.get_node_or_null("Collision/TerrainCollision")
	if col:
		for c in col.get_children():
			if c is CollisionShape3D:
				var sh := (c as CollisionShape3D).shape
				print("[W4N] TerrainCollision shape：%s" % sh.get_class())
				if sh is ConcavePolygonShape3D:
					print("[W4N]   faces %d 個の三角形" % ((sh as ConcavePolygonShape3D).get_faces().size() / 3))
				elif sh is HeightMapShape3D:
					print("[W4N]   HeightMap %d×%d" % [(sh as HeightMapShape3D).map_width, (sh as HeightMapShape3D).map_depth])
	quit(0)
