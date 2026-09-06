extends SceneTree
## Find every sizeable ground-like mesh in maps/slice and report which ones the
## paint-target collision does NOT cover.
##
## Why this exists: the collision bake uses a hand-written whitelist
## (gen_ground_collision.gd TARGETS). That was fine for the flat ground, but the
## user is now trying to paint on a brown bank slope that is evidently some other
## mesh — possibly inside an instanced sub-scene, which the whitelist cannot see.
## Guessing the node name has already cost two rounds; this enumerates the actual
## scene instead.
##
## Method: walk every MeshInstance3D, take its world AABB, drop the ones too
## small or too vertical to paint on, then fire a downward ray at the centre of
## each candidate and report whether a collision body answers. Anything that
## reports "no collision" is a surface the brush silently cannot reach.
##
## Run: godot --headless --path godot --script tools/audit_paint_coverage.gd

const SCENE := "res://maps/slice/slice.tscn"
const MIN_FOOTPRINT := 25.0  # m^2; below this it is a prop, not a paint surface


func _init() -> void:
	root.call_deferred("add_child", load(SCENE).instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await physics_frame
	await physics_frame

	var scene := root.get_child(root.get_child_count() - 1)
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state

	var rows: Array = []
	for mi in _meshes(scene):
		if not mi.is_visible_in_tree():
			continue
		var m: Mesh = mi.mesh
		if m == null:
			continue
		var box: AABB = mi.global_transform * m.get_aabb()
		var foot := box.size.x * box.size.z
		if foot < MIN_FOOTPRINT:
			continue

		# Sample a few points rather than one: a bank is a strip, and its AABB
		# centre can fall in the gap beside the actual geometry.
		var covered := 0
		var probes := 0
		var hit_names := {}
		for ix in 3:
			for iz in 5:
				var x: float = lerpf(box.position.x, box.end.x, (ix + 0.5) / 3.0)
				var z: float = lerpf(box.position.z, box.end.z, (iz + 0.5) / 5.0)
				var q := PhysicsRayQueryParameters3D.new()
				q.from = Vector3(x, box.end.y + 30.0, z)
				q.to = Vector3(x, box.position.y - 30.0, z)
				var r: Dictionary = space.intersect_ray(q)
				probes += 1
				if not r.is_empty():
					covered += 1
					var nm: String = r["collider"].name
					hit_names[nm] = hit_names.get(nm, 0) + 1

		rows.append({
			"path": str(scene.get_path_to(mi)),
			"foot": foot,
			"y0": box.position.y,
			"y1": box.end.y,
			"cov": covered,
			"probes": probes,
			"hits": hit_names,
		})

	rows.sort_custom(func(a, b): return a["foot"] > b["foot"])

	print("可繪製面覆蓋稽核（佔地 >= %.0f m² 的可見網格）\n" % MIN_FOOTPRINT)
	var uncovered: Array = []
	for r in rows:
		var pct: float = 100.0 * float(r["cov"]) / float(r["probes"])
		var mark := "ok " if pct >= 60.0 else "MISS"
		print("[%s] %-46s 佔地 %9.0f m²  Y %.2f~%.2f  射線命中 %d/%d" % [
			mark, r["path"].substr(0, 46), r["foot"], r["y0"], r["y1"], r["cov"], r["probes"]])
		if pct < 60.0:
			uncovered.append(r)

	print("\n--- 沒有碰撞覆蓋的面（筆刷刷不到）---")
	if uncovered.is_empty():
		print("  無")
	else:
		for r in uncovered:
			print("  %s   (佔地 %.0f m²)" % [r["path"], r["foot"]])
	quit(0)


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
