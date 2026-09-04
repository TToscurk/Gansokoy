extends SceneTree
## 路燈碰撞錯位查證：圓柱在哪、視覺網格在哪、差多少。
##
##   Godot --headless --path godot --script tools/probe_lamp_offset.gd
##
## 懷疑點：gen_lamp_collision.gd 取的是「路燈」根節點的世界原點，但
## road_lamp.tscn 的結構是
##   路燈 (scale 10)
##    └ 模型偏移 (position.x = 0.2392)
##       └ Clockwork Lantern Pole_1  ← 真正的網格在這
## 根節點原點與網格中心之間隔了一層偏移，還可能有 GLB 自己的根變換。
## 這支直接比對「碰撞體位置」與「網格世界 AABB 中心」。

func _init() -> void:
	var packed: PackedScene = load("res://maps/slice/slice.tscn")
	var src := packed.instantiate()

	var col_scene: PackedScene = load("res://maps/slice/gen/lamp_collision.scn")
	var col_root := col_scene.instantiate()
	var cyl := {}
	for b in col_root.get_children():
		if b is StaticBody3D:
			cyl[String(b.name).replace("_碰撞", "")] = (b as StaticBody3D).transform.origin

	print("[OFF] %-10s %26s %26s %8s" % ["路燈", "碰撞圓柱位置", "網格 AABB 中心", "偏差m"])
	var worst := 0.0
	for lamp in _lamps(src):
		var nm := String(lamp.name)
		# 網格的世界 AABB：走訪這根路燈底下所有 MeshInstance3D
		var box: Variant = null
		for mi in _meshes(lamp):
			if (mi as MeshInstance3D).mesh == null:
				continue
			var xf := _global_xform(mi, src)
			var b := xf * (mi as MeshInstance3D).mesh.get_aabb()
			box = b if box == null else (box as AABB).merge(b)
		if box == null:
			print("[OFF] %-10s 沒有網格" % nm)
			continue
		var mc: Vector3 = (box as AABB).get_center()
		var cc: Vector3 = cyl.get(nm, Vector3.INF)
		if cc == Vector3.INF:
			print("[OFF] %-10s 沒有對應碰撞體" % nm)
			continue
		var d := mc.distance_to(cc)
		worst = maxf(worst, d)
		print("[OFF] %-10s (%8.2f,%6.2f,%8.2f) (%8.2f,%6.2f,%8.2f) %8.3f%s" % [
			nm, cc.x, cc.y, cc.z, mc.x, mc.y, mc.z, d,
			"  ← 錯位" if d > 0.3 else ""])

	print("[OFF] 最大偏差 %.3f m" % worst)

	# 節點結構：偏移到底來自哪一層
	print("[OFF] === 單根路燈的節點鏈（路燈_00）===")
	var one := src.find_child("路燈_00", true, false) as Node3D
	if one != null:
		_dump(one, one, 0)
		var mesh_box: Variant = null
		for mi in _meshes(one):
			if (mi as MeshInstance3D).mesh == null:
				continue
			var xf := _global_xform(mi, src)
			var b := xf * (mi as MeshInstance3D).mesh.get_aabb()
			mesh_box = b if mesh_box == null else (mesh_box as AABB).merge(b)
		print("[OFF] 根節點世界原點 = %v" % _global_xform(one, src).origin)
		print("[OFF] 網格世界 AABB   = 中心 %v 尺寸 %v" % [
			(mesh_box as AABB).get_center(), (mesh_box as AABB).size])
		print("[OFF] 網格底部 y = %.3f，頂部 y = %.3f" % [
			(mesh_box as AABB).position.y, (mesh_box as AABB).end.y])

	src.free()
	col_root.free()
	print("[OFF] done")
	quit(0)


func _dump(n: Node, root_node: Node, depth: int) -> void:
	var t := ""
	if n is Node3D:
		var x := (n as Node3D).transform
		t = " pos=%v scale=%v" % [x.origin, x.basis.get_scale()]
	print("[OFF]   %s%s (%s)%s" % ["  ".repeat(depth), n.name, n.get_class(), t])
	if depth >= 3:
		return
	for c in n.get_children():
		_dump(c, root_node, depth + 1)


func _global_xform(node: Node3D, scene_root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != scene_root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _lamps(node: Node) -> Array:
	var out: Array = []
	if node is Node3D and node.is_in_group("village_lamps"):
		out.append(node)
	for c in node.get_children():
		out.append_array(_lamps(c))
	return out


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
