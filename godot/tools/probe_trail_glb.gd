extends SceneTree
## 量 landscape/ 樹 GLB 的實高、水平冠幅、面數，供獸道換樹定尺寸用。
##   Godot --headless --path godot --script tools/probe_trail_glb.gd

const SRC := "res://assets/landscape/"
const FILES := ["大衫", "2大衫", "松樹", "針葉樹1", "針葉樹2glb", "針葉林樹3",
	"針葉林樹4", "普通樹", "楓樹", "櫻花樹", "鎮守之杜", "盆樹"]

func _mesh_nodes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_mesh_nodes(c))
	return out

func _rel(n: Node3D, r: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != r:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

func _init() -> void:
	for f in FILES:
		var path: String = SRC + f + ".glb"
		var ps := load(path) as PackedScene
		if ps == null:
			print("%-12s 載入失敗" % f)
			continue
		var inst := ps.instantiate() as Node3D
		var box: Variant = null
		var tris := 0
		for m in _mesh_nodes(inst):
			var mi := m as MeshInstance3D
			var b := _rel(mi, inst) * mi.get_aabb()
			box = b if box == null else (box as AABB).merge(b)
			for s in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				if idx.size() > 0:
					tris += idx.size() / 3
				else:
					tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var a: AABB = box
		print("%-12s h=%6.2f  w=%6.2f x %6.2f  min.y=%6.3f  tris=%6d" % [
			f, a.size.y, a.size.x, a.size.z, a.position.y, tris])
		inst.free()
	quit(0)
