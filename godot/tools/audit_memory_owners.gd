extends SceneTree
## Where do 2.4 GB of static memory go? Walk every Mesh and Texture reachable
## from slice.tscn and sum their in-RAM sizes (mesh: surface arrays + index
## buffers; texture: decoded image bytes). Headless has no GPU, so this IS the
## RAM side; on a real run the same bytes also sit in VRAM.

var _meshes := {}
var _tex := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	_walk(scene)

	var mesh_rows: Array = _meshes.values()
	mesh_rows.sort_custom(func(a, b): return a["bytes"] > b["bytes"])
	var mesh_total := 0
	for r in mesh_rows:
		mesh_total += r["bytes"]
	var tex_total := 0
	for r in _tex.values():
		tex_total += r["bytes"]
	print("=== 記憶體歸屬 ===")
	print("  網格資源 %d 個，共 %.0f MB（頂點+索引，含所有屬性）" % [mesh_rows.size(), mesh_total / 1048576.0])
	print("  貼圖資源 %d 個，共 %.0f MB（解碼後）" % [_tex.size(), tex_total / 1048576.0])
	print("  Performance.MEMORY_STATIC = %.0f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
	print("\n%-58s %9s %9s %6s %s" % ["網格", "MB", "面數", "份數", "頂點屬性"])
	for i in min(30, mesh_rows.size()):
		var r = mesh_rows[i]
		print("%-58s %9.1f %9s %6d %s" % [_short(r["path"]), r["bytes"] / 1048576.0, _fmt(r["tris"]), r["users"], r["attrs"]])
	print("done")
	quit(0)


func _walk(n: Node) -> void:
	var mesh: Mesh = null
	if n is MeshInstance3D:
		mesh = (n as MeshInstance3D).mesh
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		mesh = (n as MultiMeshInstance3D).multimesh.mesh
	if mesh != null:
		_add_mesh(mesh)
	for c in n.get_children():
		_walk(c)


func _add_mesh(m: Mesh) -> void:
	var key := m.resource_path if not m.resource_path.is_empty() else str(m.get_instance_id())
	if _meshes.has(key):
		_meshes[key]["users"] += 1
		return
	var bytes := 0
	var tris := 0
	var attrs := {}
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr.is_empty():
			continue
		for ai in arr.size():
			var a = arr[ai]
			if a == null:
				continue
			var sz := 0
			if a is PackedVector3Array:
				sz = a.size() * 12
			elif a is PackedVector2Array:
				sz = a.size() * 8
			elif a is PackedFloat32Array:
				sz = a.size() * 4
			elif a is PackedInt32Array:
				sz = a.size() * 4
			elif a is PackedColorArray:
				sz = a.size() * 16
			elif a is PackedByteArray:
				sz = a.size()
			elif a is Array:
				continue
			if sz > 0:
				attrs[ai] = true
			bytes += sz
		var idx = arr[Mesh.ARRAY_INDEX]
		tris += (idx.size() / 3) if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX].size() / 3)
		# Materials → textures
		var mat := m.surface_get_material(s)
		if mat is BaseMaterial3D:
			for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_ORM, BaseMaterial3D.TEXTURE_EMISSION]:
				var t := (mat as BaseMaterial3D).get_texture(slot)
				if t != null:
					_add_tex(t)
	var names := []
	for k in attrs.keys():
		names.append(["V","N","T","C","UV","UV2","c0","c1","c2","c3","B","W","I"][k] if k < 13 else str(k))
	_meshes[key] = {"path": key, "bytes": bytes, "tris": tris, "users": 1, "attrs": ",".join(names)}


func _add_tex(t: Texture2D) -> void:
	var key := t.resource_path if not t.resource_path.is_empty() else str(t.get_instance_id())
	if _tex.has(key):
		return
	var img := t.get_image()
	_tex[key] = {"bytes": img.get_data_size() if img != null else 0}


func _short(p: String) -> String:
	var s := p.get_file()
	if s.is_empty():
		s = p
	return s.substr(0, 58)


func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
