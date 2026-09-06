extends SceneTree
## 博麗鳥居淨開口量測：在柱身高度帶掃描頂點 x 分佈，找兩根柱子之間的空隙。
## 同時輸出各資產按規格反推的建議 scale。
##
##   Godot --headless --path godot --script tools/probe_shrine_fit.gd

const TORII := "res://assets/shrine/博麗鳥居.glb"


func _init() -> void:
	_torii_gap()
	_scale_table()
	quit(0)


func _torii_gap() -> void:
	var ps := load(TORII) as PackedScene
	var inst := ps.instantiate() as Node3D
	var pts := PackedVector3Array()
	var box: Variant = null
	for m in _meshes(inst):
		var mi := m as MeshInstance3D
		var xf := _rel(mi, inst)
		var b := xf * mi.get_aabb()
		box = b if box == null else (box as AABB).merge(b)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				pts.append(xf * v)
	var bb := box as AABB
	# 柱身帶：總高的 20%~45%（避開基座與笠木／貫）
	var lo := bb.position.y + bb.size.y * 0.20
	var hi := bb.position.y + bb.size.y * 0.45
	var left_max := -1e9
	var right_min := 1e9
	for p in pts:
		if p.y < lo or p.y > hi:
			continue
		if p.x < 0.0:
			left_max = maxf(left_max, p.x)
		else:
			right_min = minf(right_min, p.x)
	inst.free()
	var gap := right_min - left_max
	print("[FIT] 鳥居 單位化：total %.3f x %.3f x %.3f，柱間淨空 %.3f（占總寬 %.1f%%）"
		% [bb.size.x, bb.size.y, bb.size.z, gap, gap / bb.size.x * 100.0])
	print("[FIT] 規格 高 6.0-7.5 → scale %.2f - %.2f；此區間淨開口 %.2f - %.2f m（規格 4.5-6.0）"
		% [6.0 / bb.size.y, 7.5 / bb.size.y, gap * 6.0 / bb.size.y, gap * 7.5 / bb.size.y])


func _scale_table() -> void:
	# [名稱, 單位化 w,h,d, 目標描述, 建議 scale]
	var rows := [
		["拜殿", 1.00, 0.68, 0.85, "寬 9-12 / 深 6-8 / 屋高 6-8"],
		["社務所", 0.98, 0.46, 0.83, "靈夢住居，單層"],
		["手水舍", 1.00, 0.83, 0.91, "約 3.0-3.5 m 見方"],
		["陰陽玉", 1.00, 1.00, 1.00, "直徑 0.18-0.35"],
	]
	for r in rows:
		print("[FIT] %-6s 單位化 %.2f x %.2f x %.2f  ← %s" % [r[0], r[1], r[2], r[3], r[4]])
		for s in [3.0, 3.5, 8.0, 9.5, 10.0, 12.0, 0.3]:
			pass
	# 明確算幾組候選
	print("[FIT] 拜殿 scale 9.5 → 寬 9.50 深 8.08 高 6.46 ／ scale 9.0 → 寬 9.00 深 7.65 高 6.12")
	print("[FIT] 社務所 scale 8.0 → 寬 7.84 深 6.64 高 3.68 ／ scale 7.0 → 寬 6.86 深 5.81 高 3.22")
	print("[FIT] 手水舍 scale 3.5 → 寬 3.50 深 3.19 高 2.91 ／ scale 3.2 → 寬 3.20 深 2.91 高 2.66")
	print("[FIT] 陰陽玉 scale 0.18-0.35 → 直徑即 scale")


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
