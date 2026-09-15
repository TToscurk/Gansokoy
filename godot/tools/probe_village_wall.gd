extends SceneTree
## 量人里圍牆現況：每片牆的世界 AABB、走向、端點，以及附近的碰撞體。
## Godot --headless --path godot --script tools/probe_village_wall.gd

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var scn: Node3D = load("res://maps/slice/slice.tscn").instantiate()
	root.add_child(scn)
	await process_frame
	var wall: Node = scn.get_node_or_null("圍牆")
	if wall == null:
		push_error("圍牆 not found")
		quit(1)
		return
	var stack: Array = [wall]
	var i := 0
	var all := AABB()
	var has := false
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh != null:
			var bb: AABB = n.global_transform * n.mesh.get_aabb()
			all = all.merge(bb) if has else bb
			has = true
			print("WALL_MESH %d %s  min=(%.2f, %.2f, %.2f) max=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f) faces=%d" % [
				i, n.get_path(), bb.position.x, bb.position.y, bb.position.z, bb.end.x, bb.end.y, bb.end.z,
				bb.size.x, bb.size.y, bb.size.z, n.mesh.get_faces().size() / 3])
			i += 1
	print("WALL_ALL min=(%.2f, %.2f, %.2f) max=(%.2f, %.2f, %.2f)" % [all.position.x, all.position.y, all.position.z, all.end.x, all.end.y, all.end.z])
	# 牆附近的碰撞體
	for grp in ["手動碰撞", "建物碰撞", "地面碰撞_刷筆用"]:
		var g: Node = scn.get_node_or_null(grp)
		if g == null:
			continue
		var st: Array = [g]
		while not st.is_empty():
			var n: Node = st.pop_back()
			st.append_array(n.get_children())
			if n is CollisionShape3D and n.shape != null:
				var p: Vector3 = n.global_position
				if p.x > all.position.x - 8 and p.x < all.end.x + 8 and p.z > all.position.z - 8 and p.z < all.end.z + 8:
					var sz := ""
					if n.shape is BoxShape3D:
						sz = str((n.shape as BoxShape3D).size * n.global_transform.basis.get_scale())
					print("COLL %s pos=(%.2f, %.2f, %.2f) %s %s" % [n.get_path(), p.x, p.y, p.z, n.shape.get_class(), sz])
	# 牆腳地面高度
	var ground: MeshInstance3D = scn.get_node_or_null("UnifiedGround")
	if ground != null:
		var a: Array = ground.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for x in [all.position.x, (all.position.x + all.end.x) * 0.5, all.end.x]:
			var best := INF
			var y := 0.0
			for v in verts:
				var d := Vector2(v.x - x, v.z - all.end.z).length_squared()
				if d < best:
					best = d
					y = v.y
			print("GROUND_Y x=%.1f z=%.1f y=%.2f" % [x, all.end.z, y])
	quit(0)
