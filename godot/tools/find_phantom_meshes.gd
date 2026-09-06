extends SceneTree
## Find visible meshes whose OWN surface the brush cannot reach.
##
## Why this differs from audit_paint_coverage.gd: that tool asked "does a ray
## fired here hit anything?" and everything passed — because UnifiedGround lies
## under the whole map and always answers. The real question is "does the ray
## hit THIS mesh's surface?". A decorative revetment wall with no collider is
## invisible to physics: the ray passes straight through it and lands on the
## ground beneath, so the brush drops the plant metres below the surface the user
## is aiming at. That reads as "it just won't paint here".
##
## Method: for each visible mesh, sample points across its top face, ray down,
## and compare the hit height with the mesh's own surface height there. If the
## ray lands well below the mesh top, that mesh is physics-invisible.
##
## Run: godot --headless --path godot --script tools/find_phantom_meshes.gd

const SCENE := "res://maps/slice/slice.tscn"
const MIN_FOOTPRINT := 20.0
const TOLERANCE := 0.6  # metres; below this the mesh is effectively collidable


func _init() -> void:
	root.call_deferred("add_child", load(SCENE).instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await physics_frame
	await physics_frame

	var scene := root.get_child(root.get_child_count() - 1)
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state

	var phantom: Array = []
	var solid: Array = []

	for mi in _meshes(scene):
		if not mi.is_visible_in_tree():
			continue
		var m: Mesh = mi.mesh
		if m == null:
			continue
		var box: AABB = mi.global_transform * m.get_aabb()
		if box.size.x * box.size.z < MIN_FOOTPRINT:
			continue
		# Skip paper-thin water planes; they are meant to have no collision.
		if box.size.y < 0.05:
			continue

		var gap_sum := 0.0
		var gap_max := 0.0
		var n := 0
		for ix in 5:
			for iz in 7:
				var x: float = lerpf(box.position.x, box.end.x, (ix + 0.5) / 5.0)
				var z: float = lerpf(box.position.z, box.end.z, (iz + 0.5) / 7.0)
				var q := PhysicsRayQueryParameters3D.new()
				q.from = Vector3(x, box.end.y + 20.0, z)
				q.to = Vector3(x, box.position.y - 40.0, z)
				var r: Dictionary = space.intersect_ray(q)
				if r.is_empty():
					continue
				# How far below this mesh's own top does the ray land?
				var gap: float = box.end.y - r["position"].y
				gap_sum += gap
				gap_max = max(gap_max, gap)
				n += 1

		if n == 0:
			continue
		var avg := gap_sum / n
		var row := {
			"path": str(scene.get_path_to(mi)),
			"foot": box.size.x * box.size.z,
			"h": box.size.y,
			"avg": avg,
			"max": gap_max,
		}
		# A mesh whose top is consistently far above whatever the ray hits is
		# either physics-invisible or a tall object (building) — height filters
		# the latter out, since buildings are meant to be unpaintable anyway.
		if avg > TOLERANCE and box.size.y < 6.0:
			phantom.append(row)
		else:
			solid.append(row)

	phantom.sort_custom(func(a, b): return a["foot"] > b["foot"])

	print("=== 射線打不到自己表面的可見網格（筆刷會穿過去）===\n")
	if phantom.is_empty():
		print("  無")
	else:
		print("%-46s %10s %7s %8s" % ["節點", "佔地m²", "厚度m", "落差m"])
		for r in phantom:
			print("%-46s %10.0f %7.2f %8.2f" % [
				r["path"].substr(0, 46), r["foot"], r["h"], r["avg"]])

	print("\n=== 有實體碰撞的大面（前 12）===")
	solid.sort_custom(func(a, b): return a["foot"] > b["foot"])
	for i in min(12, solid.size()):
		var r = solid[i]
		print("  %-44s 佔地 %8.0f  落差 %.2f" % [
			r["path"].substr(0, 44), r["foot"], r["avg"]])
	quit(0)


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
