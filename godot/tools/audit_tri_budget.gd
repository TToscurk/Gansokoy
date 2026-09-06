extends SceneTree
## 面數帳：每個資產檔在場上用了幾個實例、單件多重、合計多少面。
## 用來決定 LOD 該從哪一件下手（改一件影響幾百個實例）。
##
##   Godot --headless --path godot --script tools/audit_tri_budget.gd

const SCENE := "res://maps/shrine/shrine.tscn"


func _init() -> void:
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	# mesh RID → [面數, 實例數, 代表節點名]
	var per_mesh := {}
	var total := 0
	for m in _meshes(root):
		var mi := m as MeshInstance3D
		var mesh := mi.mesh
		var key := mesh.resource_path if mesh.resource_path != "" else str(mesh)
		if not per_mesh.has(key):
			var t := 0
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				t += (idx.size() if idx.size() > 0
					else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			per_mesh[key] = [t, 0, String(mi.name)]
		per_mesh[key][1] += 1
		total += per_mesh[key][0]
	var rows := []
	for k in per_mesh:
		var e: Array = per_mesh[k]
		rows.append([int(e[0]) * int(e[1]), e[0], e[1], k, e[2]])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("[BUDGET] %-11s %8s %6s  %s" % ["合計面", "單件", "實例", "資產"])
	var shown := 0
	for r in rows:
		if shown >= 22:
			break
		var name: String = String(r[3])
		if name.begins_with("res://"):
			name = name.replace("res://assets/", "")
		else:
			name = "(內嵌) " + String(r[4])
		print("[BUDGET] %11d %8d %6d  %s  (%.1f%%)"
			% [r[0], r[1], r[2], name.substr(0, 52),
				100.0 * float(r[0]) / maxf(float(total), 1.0)])
		shown += 1
	print("[BUDGET] ── 場景總計 %d 面、%d 個 MeshInstance3D ──" % [total, _count_mi(root)])
	root.free()
	quit(0)


func _count_mi(n: Node) -> int:
	return _meshes(n).size()


func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_meshes(c))
	return o
