extends SceneTree
## Physics ground vs VISIBLE ground. The player stands on whatever collider
## the ray hits first; if that is the hidden Terrain mesh's trimesh and the
## visible UnifiedGround is lower, the feet hang in the air by the difference.
## Samples a grid over the village and reports the hidden-minus-visible gap.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	for i in 6:
		await physics_frame
	var map: Node = main.map_root
	var space: PhysicsDirectSpaceState3D = map.get_world_3d().direct_space_state
	var mask: int = main.player.collision_mask

	# Which colliders exist on the player's layers, and are their visuals shown?
	print("[gap] 碰撞體 → 其視覺節點是否可見：")
	for n in _bodies(map):
		var vis := "?"
		var owner_vis: Node = n.get_parent()
		if owner_vis is Node3D:
			vis = str((owner_vis as Node3D).is_visible_in_tree())
		print("[gap]   %-40s layer=%d 父節點可見=%s" % [n.get_path().get_concatenated_names().substr(-40), n.collision_layer, vis])

	var worst := 0.0
	var worst_at := Vector3.ZERO
	var rows := []
	for x in range(220, 470, 10):
		for z in range(-160, 110, 10):
			var from := Vector3(x, 60, z)
			# First hit on player mask (what physics stands on)
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -120, 0), mask)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var phys_y: float = hit["position"].y
			var phys_name := String((hit["collider"] as Node).name)
			# Now skip hidden-visual colliders and find the first VISIBLE one
			var excl := []
			var vis_y := NAN
			var vis_name := ""
			for k in 6:
				var q2 := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -120, 0), mask)
				q2.exclude = excl
				var h2 := space.intersect_ray(q2)
				if h2.is_empty():
					break
				var c: Node = h2["collider"]
				var par: Node = c.get_parent()
				var shown: bool = not (par is Node3D) or (par as Node3D).is_visible_in_tree()
				# Terrain_col lives under the hidden Terrain mesh
				if String(c.name) == "Terrain_col":
					shown = false
				if shown:
					vis_y = h2["position"].y
					vis_name = String(c.name)
					break
				excl.append(h2["rid"])
			if is_nan(vis_y):
				continue
			var gap := phys_y - vis_y
			rows.append([gap, x, z, phys_name, vis_name, phys_y, vis_y])
			if absf(gap) > absf(worst):
				worst = gap
				worst_at = Vector3(x, phys_y, z)
	rows.sort_custom(func(a, b): return absf(a[0]) > absf(b[0]))
	var n_pos := 0
	var n_big := 0
	for r in rows:
		if r[0] > 0.02:
			n_pos += 1
		if r[0] > 0.10:
			n_big += 1
	print("[gap] 取樣 %d 點：物理面高於可見面 >2 cm 的 %d 點，>10 cm 的 %d 點；最大 %.2f m @ (%.0f, %.0f)" % [
		rows.size(), n_pos, n_big, worst, worst_at.x, worst_at.z])
	print("[gap] %6s %6s %8s %-26s %-26s %8s %8s" % ["x", "z", "落差", "物理面", "可見面", "物理y", "可見y"])
	for i in min(25, rows.size()):
		var r = rows[i]
		print("[gap] %6d %6d %8.3f %-26s %-26s %8.2f %8.2f" % [r[1], r[2], r[0], r[3], r[4], r[5], r[6]])
	print("done")
	quit(0)


func _bodies(n: Node) -> Array:
	var out := []
	if n is CollisionObject3D and (n as CollisionObject3D).collision_layer & 1:
		out.append(n)
	for c in n.get_children():
		out.append_array(_bodies(c))
	return out
