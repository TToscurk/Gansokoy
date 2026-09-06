extends SceneTree
## 博麗神社委製 GLB 進場前體檢：原始 AABB、原點偏移、三角面數、材質數。
##
##   Godot --headless --path godot --script tools/probe_shrine_kit.gd

const DIR := "res://assets/_lod/"


func _init() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		print("[KIT] 找不到 ", DIR)
		quit(1)
		return
	var names := []
	for f in d.get_files():
		if f.get_extension().to_lower() == "glb":
			names.append(f)
	names.sort()
	for f in names:
		_one(DIR + f)
	quit(0)


func _one(path: String) -> void:
	var label := path.get_file().get_basename()
	if not ResourceLoader.exists(path):
		print("[KIT] %s 未匯入（.import 尚未產生）" % label)
		return
	var ps := load(path) as PackedScene
	if ps == null:
		print("[KIT] %s 載入失敗" % label)
		return
	var inst := ps.instantiate() as Node3D
	var box: Variant = null
	var tris := 0
	var mats := {}
	var mesh_count := 0
	for m in _meshes(inst):
		var mi := m as MeshInstance3D
		mesh_count += 1
		var b := _rel(mi, inst) * mi.get_aabb()
		box = b if box == null else (box as AABB).merge(b)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx.size() > 0
				else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var mat := mi.mesh.surface_get_material(s)
			if mat != null:
				mats[mat.resource_name if mat.resource_name != "" else str(mat)] = true
	inst.free()
	if box == null:
		print("[KIT] %s 無網格" % label)
		return
	var bb := box as AABB
	var ctr := bb.position + bb.size * 0.5
	var origin_kind := "BASE" if absf(bb.position.y) < 0.02 * maxf(bb.size.y, 0.001) else "CENTRE/OFFSET"
	print("[KIT] %-12s  size %6.2f x %6.2f x %6.2f  min.y %7.3f  ctr(%6.2f,%6.2f,%6.2f)  %s  tris %7d  mesh %3d  mat %2d"
		% [label, bb.size.x, bb.size.y, bb.size.z, bb.position.y,
			ctr.x, ctr.y, ctr.z, origin_kind, tris, mesh_count, mats.size()])


func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_meshes(c))
	return o


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
