extends SceneTree
## Raycast probe: does the paint-target collision actually cover the river bank?
##
## Why this exists: the user still cannot place assets on the revetment after it
## was added to the collision bake. "It doesn't work" has several possible
## causes (shape not in the physics space, wrong layer, ray excluded, geometry
## offset) and guessing between them wastes rounds. This replays what Asset
## Placer does — SurfaceAssetPlacementStrategy fires
## space_state.intersect_ray() with default mask — against the real saved scene
## in a real physics space, and reports per-sample which body was hit.
##
## Headless keeps a working PhysicsServer3D (only rendering is stubbed), so the
## result is trustworthy even though the viewport is not.
##
## Run: godot --headless --path godot --script tools/probe_bank_collision.gd

const SCENE := "res://maps/slice/slice.tscn"
const TARGET_MESH := "EastRiverRevetment"


func _init() -> void:
	root.call_deferred("add_child", load(SCENE).instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await physics_frame
	await physics_frame

	var scene := root.get_child(root.get_child_count() - 1)

	# Where is the revetment, in world space?
	var mi := scene.find_child(TARGET_MESH, true, false) as MeshInstance3D
	if mi == null:
		print("[fail] %s not found" % TARGET_MESH)
		quit(1)
		return
	var aabb := mi.global_transform * mi.mesh.get_aabb()
	print("%s 世界範圍: X %.1f~%.1f  Y %.2f~%.2f  Z %.1f~%.1f" % [
		TARGET_MESH,
		aabb.position.x, aabb.end.x,
		aabb.position.y, aabb.end.y,
		aabb.position.z, aabb.end.z])

	# What collision bodies exist, and on which layers?
	print("\n碰撞體:")
	for b in _bodies(scene):
		var shape_count := 0
		for c in b.get_children():
			if c is CollisionShape3D and c.shape != null:
				shape_count += 1
		print("  %-28s layer=%d  shapes=%d" % [b.name, b.collision_layer, shape_count])

	# Sample a grid over the revetment footprint, casting straight down from
	# above — the same query Asset Placer runs, default mask, no exclusions.
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	var hits := {}
	var miss := 0
	var samples := 0
	var top := aabb.end.y + 50.0

	for ix in 12:
		for iz in 24:
			var x: float = lerpf(aabb.position.x, aabb.end.x, (ix + 0.5) / 12.0)
			var z: float = lerpf(aabb.position.z, aabb.end.z, (iz + 0.5) / 24.0)
			var q := PhysicsRayQueryParameters3D.new()
			q.from = Vector3(x, top, z)
			q.to = Vector3(x, aabb.position.y - 50.0, z)
			var r: Dictionary = space.intersect_ray(q)
			samples += 1
			if r.is_empty():
				miss += 1
			else:
				var n: String = r["collider"].name
				hits[n] = hits.get(n, 0) + 1

	print("\n護岸範圍內垂直射線 %d 發:" % samples)
	if hits.is_empty():
		print("  全部落空 — 碰撞完全沒生效")
	else:
		var keys := hits.keys()
		keys.sort()
		for k in keys:
			print("  打中 %-28s %d 發" % [k, hits[k]])
	print("  落空 %d 發" % miss)

	if hits.has("%s_碰撞" % TARGET_MESH):
		print("\n[PASS] 護岸碰撞有效，Asset Placer 應該放得上去")
	else:
		print("\n[FAIL] 護岸碰撞沒被打中 — 不是缺碰撞面，是別的原因")
	quit(0)


func _bodies(node: Node) -> Array:
	var out: Array = []
	if node is StaticBody3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_bodies(c))
	return out
