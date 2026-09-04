extends SceneTree
## 碰撞是否跟著節點走：把每個建物碰撞體的世界 AABB 與它對應的視覺網格比對。
##
##   Godot --headless --path godot --script tools/verify_collision_alignment.gd
##
## 為什麼需要：gen_building_collision.gd 從磁碟讀 slice.tscn，而使用者會在
## 編輯器裡手調位置。忘記存檔就重烘，碰撞會停在舊座標——玩家撞到空氣、
## 走進建築。這支把「碰撞盒中心」對「視覺網格中心」的距離量出來。

const TARGETS := ["鯢吞亭", "水車", "霧雨店", "寺子屋", "鈴奈庵", "稗田底新版"]


func _init() -> void:
	var packed: PackedScene = load("res://maps/slice/slice.tscn")
	var src := packed.instantiate()

	# 視覺網格的世界 AABB
	var visual := {}
	for name in TARGETS:
		var node := src.find_child(name, true, false)
		if node == null:
			print("[ALIGN] 場景裡找不到 %s" % name)
			continue
		var box: Variant = _subtree_aabb(node as Node3D, src)
		if box != null:
			visual[name] = box

	# 碰撞體的世界 AABB。地面碰撞也要看：水車的代理住在那裡（獨立 body），
	# 只讀建物碰撞會誤報「水車沒有碰撞體」。
	var collision := {}
	for path in ["res://maps/slice/gen/building_collision.scn",
			"res://maps/slice/gen/ground_collision.scn"]:
		var col_scene: PackedScene = load(path)
		var col_root := col_scene.instantiate()
		for body in col_root.get_children():
			if not (body is StaticBody3D):
				continue
			var box: Variant = _body_aabb(body as StaticBody3D)
			if box == null:
				continue
			# 碰撞體命名是「<節點名>_<網格名>」或「<節點名>_旋轉代理_碰撞」
			for name in TARGETS:
				if String(body.name).begins_with(name):
					if collision.has(name):
						collision[name] = (collision[name] as AABB).merge(box)
					else:
						collision[name] = box
		col_root.free()

	print("[ALIGN] %-14s %28s %28s %9s" % ["物件", "視覺中心", "碰撞中心", "偏差m"])
	var worst := 0.0
	for name in TARGETS:
		if not visual.has(name):
			continue
		if not collision.has(name):
			print("[ALIGN] %-14s %28s %28s   ← 沒有碰撞體！" % [
				name, _v(visual[name].get_center()), "—"])
			continue
		var vc: Vector3 = (visual[name] as AABB).get_center()
		var cc: Vector3 = (collision[name] as AABB).get_center()
		var d := vc.distance_to(cc)
		worst = maxf(worst, d)
		var flag := ""
		if d > 2.0:
			flag = "   ← 嚴重錯位"
		elif d > 0.5:
			flag = "   ← 偏移"
		print("[ALIGN] %-14s %28s %28s %9.3f%s" % [name, _v(vc), _v(cc), d, flag])

	print("[ALIGN] 最大偏差 %.3f m" % worst)
	src.free()
	print("[ALIGN] done")
	quit(0)


func _v(v: Vector3) -> String:
	return "(%8.2f,%7.2f,%9.2f)" % [v.x, v.y, v.z]


func _subtree_aabb(node: Node3D, root: Node) -> Variant:
	var out: Variant = null
	for mi in _meshes(node):
		if (mi as MeshInstance3D).mesh == null:
			continue
		var xf := _global_xform(mi, root)
		var local: AABB = (mi as MeshInstance3D).mesh.get_aabb()
		var box := xf * local
		out = box if out == null else (out as AABB).merge(box)
	return out


func _body_aabb(body: StaticBody3D) -> Variant:
	var out: Variant = null
	for c in body.get_children():
		if not (c is CollisionShape3D):
			continue
		var s: Shape3D = (c as CollisionShape3D).shape
		var pts := PackedVector3Array()
		if s is ConvexPolygonShape3D:
			pts = (s as ConvexPolygonShape3D).points
		elif s is ConcavePolygonShape3D:
			pts = (s as ConcavePolygonShape3D).get_faces()
		if pts.is_empty():
			continue
		var xf: Transform3D = body.transform * (c as CollisionShape3D).transform
		var box := AABB(xf * pts[0], Vector3.ZERO)
		for p in pts:
			box = box.expand(xf * p)
		out = box if out == null else (out as AABB).merge(box)
	return out


func _global_xform(node: Node3D, scene_root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != scene_root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
