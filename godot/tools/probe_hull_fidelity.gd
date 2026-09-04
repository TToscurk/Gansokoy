extends SceneTree
## 凸包保真度量測：換成凸包之後，形狀會「胖」多少？
##
##   Godot --headless --path godot --script tools/probe_hull_fidelity.gd
##
## 方法：在原始三角網周圍撒點，測「在凸包內、但不在原網格內」的比例。
## 這個比例就是玩家會撞到空氣的體積佔比。石牆這種近似長方體的東西會接近 0；
## 鏤空的水車或拱門會很高（那種就不能換凸包）。
##
## 判準：<5% 可換，5~15% 需目視，>15% 不換。

const SAMPLES := 20000


func _init() -> void:
	var packed: PackedScene = load("res://maps/slice/slice.tscn")
	var src := packed.instantiate()
	seed(20260904)

	print("[HULL] %-34s %8s %8s %9s  判定" % ["網格", "三角面", "凸包點", "膨脹率"])
	for path in [
			"MachiCanal/VillageStoneBank/牆_01/mesh_node",
			"MachiCanal/Waterworks/田泵水口_南/output_unwrapped",
			"MachiCanal/Waterworks/分水堰/output_unwrapped",
			"MachiCanal/Waterworks/石造堰檻/mesh_node",
			"MachiCanal/Waterworks/水車/mesh_node",
			"MachiCanal/Waterworks/濱水平台/mesh_node",
			"MachiCanal/Waterworks/親水階梯/mesh_node",
			"MachiCanal/Waterworks/N_親水階梯_弱節點/mesh_node"]:
		var mi := src.get_node_or_null(path) as MeshInstance3D
		if mi == null:
			print("[HULL] 找不到 %s" % path)
			continue
		var m: Mesh = mi.mesh
		var faces := m.get_faces()
		var hull := m.create_convex_shape(true, false)
		var pts := hull.points

		# 用物理引擎做內含判定：凸包放進一個獨立世界，逐點查詢。
		var inflate := _inflation(faces, pts, m.get_aabb())
		var verdict := "✓ 可換"
		if inflate > 0.15:
			verdict = "✗ 不可換（鏤空）"
		elif inflate > 0.05:
			verdict = "△ 需目視"
		print("[HULL] %-34s %8d %8d %8.1f%%  %s" % [
			path.get_slice("/", 2) + "/" + path.get_file(),
			faces.size() / 3, pts.size(), inflate * 100.0, verdict])

	src.free()
	print("[HULL] done")
	quit(0)


## 膨脹率 = (凸包內 且 原網格外) / 凸包內。用射線奇偶法判斷點是否在封閉網格內。
func _inflation(faces: PackedVector3Array, hull_pts: PackedVector3Array, aabb: AABB) -> float:
	var planes := _hull_planes(hull_pts)
	var in_hull := 0
	var in_hull_out_mesh := 0
	for i in SAMPLES:
		var p := aabb.position + Vector3(
			randf() * aabb.size.x, randf() * aabb.size.y, randf() * aabb.size.z)
		if not _inside_planes(p, planes):
			continue
		in_hull += 1
		if not _inside_mesh(p, faces):
			in_hull_out_mesh += 1
	if in_hull == 0:
		return 0.0
	return float(in_hull_out_mesh) / float(in_hull)


## 凸包的外接近似：對 162 個均勻方向取支撐平面。這是凸包的**外接**體，
## 只會高估膨脹率、不會低估 —— 誤差方向對安全有利（寧可判定「不可換」）。
## Godot 沒有公開「由點雲取回凸包面」的 API（build_convex_mesh_from_points
## 不存在），所以不能拿精確的殼面。
func _hull_planes(pts: PackedVector3Array) -> Array:
	var planes: Array = []
	for dir in _directions(162):
		var best := -INF
		for p in pts:
			best = maxf(best, dir.dot(p))
		planes.append(Plane(dir, best))
	return planes


func _directions(n: int) -> Array:
	var out: Array = []
	var ga := PI * (3.0 - sqrt(5.0))
	for i in n:
		var y := 1.0 - (float(i) / float(n - 1)) * 2.0
		var r := sqrt(maxf(0.0, 1.0 - y * y))
		var th := ga * i
		out.append(Vector3(cos(th) * r, y, sin(th) * r))
	return out


func _inside_planes(p: Vector3, planes: Array) -> bool:
	for pl in planes:
		if (pl as Plane).distance_to(p) > 0.0:
			return false
	return true


## 奇偶法：從 p 往 +X 射線，數穿過幾個三角形。
func _inside_mesh(p: Vector3, faces: PackedVector3Array) -> bool:
	var hits := 0
	var dir := Vector3(1.0, 0.0037, 0.0011).normalized()  # 避開退化的軸對齊情形
	for i in range(0, faces.size(), 3):
		if Geometry3D.ray_intersects_triangle(p, dir, faces[i], faces[i + 1], faces[i + 2]) != null:
			hits += 1
	return (hits % 2) == 1
