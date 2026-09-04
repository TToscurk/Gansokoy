extends SceneTree
## Print the world AABB of the two probe targets that still "fail", so the
## probe coordinates are measured, not guessed. Also list what colliders
## exist inside each subtree in the RUNNING game.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	for i in 4:
		await physics_frame
	var map: Node = main.map_root

	for path in ["B1_Street/大鳥居", "B1_Street/ToriGate", "MachiCanal/VillageStoneBank", "MachiCanal/VillageStoneBank/牆_01"]:
		var n := map.get_node_or_null(path)
		if n == null:
			print("%-36s 不存在" % path)
			continue
		var box := _aabb(n)
		var cols := _find(n, "CollisionShape3D").size()
		print("%-36s AABB pos(%.1f, %.1f, %.1f) size(%.1f, %.1f, %.1f)  子碰撞 %d" % [
			path, box.position.x, box.position.y, box.position.z,
			box.size.x, box.size.y, box.size.z, cols])

	# And the hull bodies named after them
	var bc := map.get_node_or_null("建物碰撞")
	if bc:
		for c in bc.get_children():
			if String(c.name).findn("鳥居") != -1 or String(c.name).findn("Tori") != -1:
				var cs: CollisionShape3D = c.get_child(0)
				var b := cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
				print("hull %-30s pos(%.1f, %.1f, %.1f) size(%.1f, %.1f, %.1f)" % [
					c.name, b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z])
	var gc := map.get_node_or_null("地面碰撞_刷筆用/VillageStoneBank_碰撞")
	if gc:
		var cs: CollisionShape3D = gc.get_child(0)
		var b := cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
		print("ground VillageStoneBank_碰撞  pos(%.1f, %.1f, %.1f) size(%.1f, %.1f, %.1f) layer=%d" % [
			b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z, gc.collision_layer])
	print("done")
	quit(0)


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _find(n, "MeshInstance3D"):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _find(n: Node, cls: String) -> Array:
	var out := []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find(c, cls))
	return out
