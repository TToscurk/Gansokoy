extends SceneTree
## Measure every B1_Street building's lowest vertex against the ground under
## it, so floating (or sunken) buildings are found by number, not by eye.
##
## Why: the user spotted a kura floating in the editor. Guessing which of the
## 8 kura it is from a screenshot is unreliable; measuring all 40 buildings is
## cheap and also catches ones outside the current camera framing.
##
## Ground height comes from a raycast against gen/ground_collision.scn (layer
## 32) — the same surface the grass brush and Asset Placer snap to, so it is the
## surface the buildings are supposed to sit on.

const LAYER_GROUND := 1 << 31  # collision layer 32


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
	var scene := packed.instantiate()
	var use_lod := "--lod" in OS.get_cmdline_user_args()
	var cull := scene.get_node_or_null("場景效能裁剪")
	if cull != null:
		cull.set("使用減面建築", use_lod)
	print("減面建築: %s" % ("開" if use_lod else "關"))
	root.add_child(scene)
	# Two physics frames so the collision bodies are registered.
	await physics_frame
	await physics_frame

	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	var street := scene.get_node("B1_Street")

	print("%-22s %9s %9s %8s  %s" % ["建築", "模型底Y", "地面Y", "差(m)", "判定"])
	var problems := 0
	for b in street.get_children():
		if not b is Node3D:
			continue
		var meshes := _meshes(b)
		if meshes.is_empty():
			continue
		# Lowest point of the building in world space.
		var lowest := INF
		var foot := Vector3.ZERO
		for mi in meshes:
			var aabb := mi.get_aabb()
			# Check all 8 corners; the transform can rotate the box.
			for i in 8:
				var corner := mi.global_transform * aabb.get_endpoint(i)
				if corner.y < lowest:
					lowest = corner.y
					foot = corner
		# Sample ground at the building's XZ centre, not the corner, because a
		# corner may hang over a bank.
		var centre: Vector3 = (b as Node3D).global_position
		var ground := _ground_y(space, Vector3(centre.x, 80.0, centre.z))
		if is_nan(ground):
			print("%-22s %9.3f %9s %8s  地面碰撞未命中" % [b.name, lowest, "-", "-"])
			continue
		var gap := lowest - ground
		var verdict := ""
		if gap > 0.25:
			verdict = "浮空"
			problems += 1
		elif gap < -0.6:
			verdict = "陷入"
			problems += 1
		print("%-22s %9.3f %9.3f %+8.3f  %s" % [b.name, lowest, ground, gap, verdict])

	print("問題建築 %d 棟" % problems)
	print("done")
	quit(0)


func _ground_y(space: PhysicsDirectSpaceState3D, from: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -200, 0), LAYER_GROUND)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return hit["position"].y


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
