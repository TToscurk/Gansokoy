extends SceneTree
## 月台改造前的現況量測：拜殿 / 月台 / 石階 / 境內平台，各自世界 AABB。
##   Godot --headless --path godot --script tools/audit_courtyard_dims.gd

const SCENE := "res://maps/shrine/shrine.tscn"

const TARGETS := [
	["/建築/拜殿", "Haiden"],
	["/鋪石/拜殿白石磚月台/月台鋪面", "月台鋪面(白石)"],
	["/鋪石/拜殿白石磚月台/月台石垣", "月台石垣"],
	["/鋪石/拜殿白石磚月台/月台_基座", "月台基座"],
	["/參道石階/踏石", "主石階踏石"],
	["/參道石階/袖石垣", "主石階袖石垣"],
	["/鋪石/境內鋪石", "境內中軸鋪石"],
	["/建築/本殿", "Honden"],
	["/建築/社務所", "社務所"],
	["/建築/手水舍", "手水舍"],
]


func _init() -> void:
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	print("[DIM] %-18s %8s %8s %8s   %9s %9s   %9s %9s"
		% ["節點", "寬X", "高Y", "深Z", "x min", "x max", "z min", "z max"])
	for t in TARGETS:
		var n := root.get_node_or_null(NodePath(String(t[0]).substr(1))) as Node3D
		if n == null:
			print("[DIM] %-18s ✗ 找不到" % t[1])
			continue
		var box: Variant = null
		for m in _meshes(n):
			var mi := m as MeshInstance3D
			var b := _rel(mi, root) * mi.get_aabb()
			box = b if box == null else (box as AABB).merge(b)
		if box == null:
			print("[DIM] %-18s 無網格" % t[1])
			continue
		var bb: AABB = box
		print("[DIM] %-18s %8.2f %8.2f %8.2f   %9.2f %9.2f   %9.2f %9.2f"
			% [t[1], bb.size.x, bb.size.y, bb.size.z,
				bb.position.x, bb.position.x + bb.size.x,
				bb.position.z, bb.position.z + bb.size.z])
		if String(t[1]).begins_with("月台鋪面") or String(t[1]) == "Haiden":
			print("[DIM]                    台面/底 y = %.2f ~ %.2f"
				% [bb.position.y, bb.position.y + bb.size.y])
	# 境內平台高度（地形）
	var terrain := root.find_child("Terrain", false, false) as MeshInstance3D
	if terrain != null:
		var vs: PackedVector3Array = terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		print("[DIM] 地形高度取樣：")
		for p in [[0.0, -20.0, "境內中央"], [0.0, -9.0, "石階頂"], [0.0, -28.0, "拜殿位置"],
				[-13.0, -20.0, "境內西"], [13.0, -20.0, "境內東"], [0.0, -38.0, "本殿位置"]]:
			var best := 1e18
			var by := 0.0
			for v in vs:
				var d: float = (v.x - float(p[0])) * (v.x - float(p[0])) \
					+ (v.z - float(p[1])) * (v.z - float(p[1]))
				if d < best:
					best = d
					by = v.y
			print("[DIM]   %-8s (%.1f, %.1f) y=%.2f" % [p[2], p[0], p[1], by + terrain.position.y])
	root.free()
	quit(0)


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
