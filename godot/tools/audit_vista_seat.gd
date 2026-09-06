extends SceneTree
## 遠景山診斷：地標山的世界 AABB vs 底下 vista 網格高度。
## 「山浮在空中」是可量的：山底邊 y − 正下方網格 y > 0 就是浮空。
##
##   Godot --headless --path godot --script tools/audit_vista_seat.gd

const SCENE := "res://maps/shrine/shrine.tscn"
const EYE := Vector3(0.0, 4.9, -20.5)      # 境內中央、眼高


func _init() -> void:
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	var vista := root.find_child("Vista", false, false) as MeshInstance3D
	var vs: PackedVector3Array = vista.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] \
		if vista != null else PackedVector3Array()
	var g := root.find_child("遠景地標", true, false)
	if g == null:
		print("[VISTA] 找不到 遠景地標")
		quit(1)
		return
	for c in g.get_children():
		var n := c as Node3D
		var box: Variant = null
		for m in _meshes(n):
			var mi := m as MeshInstance3D
			var b := _rel(mi, root) * mi.get_aabb()
			box = b if box == null else (box as AABB).merge(b)
		if box == null:
			continue
		var bb: AABB = box
		var ctr := bb.position + bb.size * 0.5
		# 山正下方的 vista 網格高度（最近頂點）
		var gy := _nearest_y(vs, ctr.x, ctr.z)
		var gap := bb.position.y - gy
		# 從境內看的仰角
		var dist := Vector2(ctr.x - EYE.x, ctr.z - EYE.z).length()
		var deg_base := rad_to_deg(atan2(bb.position.y - EYE.y, dist))
		var deg_top := rad_to_deg(atan2(bb.position.y + bb.size.y - EYE.y, dist))
		print("[VISTA] %-10s 寬 %6.0f 高 %6.0f 深 %6.0f  底 y %7.1f  網格 y %7.1f  落差 %+7.1f %s"
			% [n.name, bb.size.x, bb.size.y, bb.size.z, bb.position.y, gy, gap,
				"← 浮空" if gap > 20.0 else ("← 埋沒" if gap < -60.0 else "OK")])
		print("[VISTA]   距境內 %.0f m，山底仰角 %.1f°、山頂仰角 %.1f°%s"
			% [dist, deg_base, deg_top,
				"  ← 山底高於地平線，會像飄在天上" if deg_base > 3.0 else ""])
	root.free()
	quit(0)


func _nearest_y(vs: PackedVector3Array, x: float, z: float) -> float:
	var best := 1e18
	var by := 0.0
	for v in vs:
		var d: float = (v.x - x) * (v.x - x) + (v.z - z) * (v.z - z)
		if d < best:
			best = d
			by = v.y
	return by


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
