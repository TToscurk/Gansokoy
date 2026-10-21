extends SceneTree
## shrine_v2 資產量測：印出每個資產的合併 AABB（走完整 transform 鏈）、面數、表面/材質數。
## godot --headless --path godot --script res://tools/shrine_v2/probe_assets.gd -- --list=a.glb,b.glb

func _init() -> void:
	_run.call_deferred()

func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
			t += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		elif arr.size() > 0 and arr[Mesh.ARRAY_VERTEX] != null:
			t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t

func _walk(n: Node, xf: Transform3D, acc: Dictionary) -> void:
	var cur := xf
	if n is Node3D:
		cur = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var bb := cur * mi.mesh.get_aabb()
		if acc.has("aabb"):
			acc["aabb"] = (acc["aabb"] as AABB).merge(bb)
		else:
			acc["aabb"] = bb
		acc["tris"] = int(acc.get("tris", 0)) + _tris(mi.mesh)
		acc["meshes"] = int(acc.get("meshes", 0)) + 1
		acc["surfs"] = int(acc.get("surfs", 0)) + mi.mesh.get_surface_count()
	for c in n.get_children():
		_walk(c, cur, acc)

func _run() -> void:
	var list: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--list="):
			list = a.substr(7).split(",")
	for p in list:
		var path := p
		if not path.begins_with("res://"):
			path = "res://" + path
		var ps := ResourceLoader.load(path) as PackedScene
		if ps == null:
			print("[PROBE] FAIL ", path)
			continue
		var inst := ps.instantiate()
		var acc := {}
		_walk(inst, Transform3D.IDENTITY, acc)
		if acc.has("aabb"):
			var bb: AABB = acc["aabb"]
			print("[PROBE] %s size=(%.3f, %.3f, %.3f) min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f) tris=%d meshes=%d surfs=%d" % [
				path.get_file(), bb.size.x, bb.size.y, bb.size.z, bb.position.x, bb.position.y, bb.position.z,
				bb.end.x, bb.end.y, bb.end.z, acc["tris"], acc["meshes"], acc["surfs"]])
		else:
			print("[PROBE] ", path, " no mesh")
		inst.free()
	quit()
