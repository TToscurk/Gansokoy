extends SceneTree
## Compare the world-space AABB of every LOD-swapped MeshInstance3D against
## its original, in all three axes. The footing audit only checks Y at the
## building's XZ centre; a baked transform could also shift X/Z or scale.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var boxes := {}
	for use_lod in [false, true]:
		var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
		var scene := packed.instantiate()
		scene.get_node("場景效能裁剪").set("使用減面建築", use_lod)
		root.add_child(scene)
		await process_frame
		await process_frame
		for mi in _meshes(scene):
			if mi.mesh == null or _tris(mi.mesh) < 40000:
				continue
			var key := String(scene.get_path_to(mi))
			boxes[key] = boxes.get(key, {})
			boxes[key][use_lod] = mi.global_transform * mi.get_aabb()
		scene.free()

	var bad := 0
	var checked := 0
	for key in boxes:
		if not boxes[key].has(true) or not boxes[key].has(false):
			continue
		checked += 1
		var a: AABB = boxes[key][false]
		var b: AABB = boxes[key][true]
		var d_pos := (b.position - a.position).abs()
		var d_size := (b.size - a.size).abs()
		var worst := maxf(maxf(d_pos.x, d_pos.y), maxf(d_pos.z, maxf(d_size.x, maxf(d_size.y, d_size.z))))
		if worst > 0.10:
			bad += 1
			# Report relative error too: 0.87 m on a 500 m mountain is noise;
			# 0.87 m on a 6 m house is a bug.
			var rel := worst / maxf(a.size.length(), 0.001)
			print("偏移 %5.2f m (%.3f%% of size %.0f m)  %s" % [worst, rel * 100.0, a.size.length(), key])
	print("檢查 %d 個，偏移超過 10cm 的 %d 個" % [checked, bad])
	print("done")
	quit(0)


func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		t += (idx.size() / 3) if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX].size() / 3)
	return t


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
