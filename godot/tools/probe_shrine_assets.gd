extends SceneTree
## 博麗神社 P0 資產盤點：現有的東西夠不夠、尺寸對不對。
##
##   Godot --headless --path godot --script tools/probe_shrine_assets.gd
##
## 對照 HAKUREI_SHRINE_AREA_SPEC.md §2 Scale Anchors：
##   Main Torii  高 6.0-7.5 m、淨開口寬 4.5-6.0 m
##   Haiden      寬 9-12 m、深 6-8 m、可見屋高 6-8 m
##   Honden      寬 5-8 m、深 4-6 m
##   Stone Steps 級高 0.14-0.18 m、級深 0.30-0.45 m、寬 2.5-3.5 m

const CANDIDATES := [
	# [路徑, 規格用途, 目標尺寸描述]
	["res://assets/landmark/大鳥居.glb", "Main Torii", "高 6.0-7.5、開口寬 4.5-6.0"],
	["res://assets/lowpoly_scene/ToriGate.gltf", "Main Torii（備案）", "同上"],
	["res://assets/lowpoly_scene/House_4x5.gltf", "Haiden 暫代？", "寬 9-12、深 6-8"],
	["res://assets/machiya/大町家.glb", "Haiden 暫代？", "寬 9-12、深 6-8"],
	["res://assets/machiya/町家.glb", "Honden 暫代？", "寬 5-8、深 4-6"],
	["res://assets/machiya/倉庫.glb", "storage", "小型"],
	["res://assets/riverbank/降台石5段.glb", "Stone Steps", "級高 0.14-0.18"],
	["res://assets/riverbank/親水階梯一組.glb", "Stone Steps", "同上"],
	["res://assets/riverbank/洗物石段.glb", "Stone Steps", "同上"],
	["res://assets/lowpoly_scene/StoneLantern.gltf", "石燈籠", "≤ 少量"],
	["res://assets/landscape/鎮守之杜.glb", "Hero Tree", "高 12-18"],
	["res://assets/landscape/大衫.glb", "Hero Tree", "高 12-18"],
	["res://assets/landscape/2大衫.glb", "Hero Tree", "高 12-18"],
	["res://assets/landmark/火見櫓.glb", "（參考尺度）", "-"],
]


func _init() -> void:
	print("[SHRINE] %-26s %7s %7s %7s  %8s  %s" % ["asset", "w", "h", "d", "tris", "用途 / 目標"])
	for c in CANDIDATES:
		_one(c[0], c[1], c[2])
	quit(0)


func _one(path: String, role: String, target: String) -> void:
	var label := path.get_file().get_basename()
	if not ResourceLoader.exists(path):
		print("[SHRINE] %-26s 不存在 —— %s（%s）" % [label, role, target])
		return
	var ps := load(path) as PackedScene
	if ps == null:
		print("[SHRINE] %-26s 載入失敗" % label)
		return
	var inst := ps.instantiate() as Node3D
	var box: Variant = null
	var tris := 0
	for m in _meshes(inst):
		var mi := m as MeshInstance3D
		var b := _rel(mi, inst) * mi.get_aabb()
		box = b if box == null else (box as AABB).merge(b)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx.size() > 0
				else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	inst.free()
	if box == null:
		print("[SHRINE] %-26s 無網格" % label)
		return
	var bb := box as AABB
	print("[SHRINE] %-26s %7.2f %7.2f %7.2f  %8d  %s ← %s"
		% [label, bb.size.x, bb.size.y, bb.size.z, tris, role, target])


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
