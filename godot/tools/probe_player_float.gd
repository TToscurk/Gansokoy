extends SceneTree
## Is the player floating? Let the real controller settle at several street /
## bank spots, then measure: capsule bottom vs. ground ray under the body vs.
## the visual mesh's lowest vertex (feet). Also report the same for the old
## capsule player for comparison, and what floor_snap / safe_margin are.

var _main: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	_main.load_map("slice", "")
	for i in 6:
		await physics_frame
	var p: CharacterBody3D = _main.player
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var cs: CollisionShape3D = null
	for c in p.get_children():
		if c is CollisionShape3D:
			cs = c
	var cap: CapsuleShape3D = cs.shape
	var cap_bottom_local: float = cs.position.y - cap.height * 0.5
	print("[float] 膠囊 r=%.2f h=%.2f  碰撞節點 y=%.2f → 膠囊底在 root 下 %.3f m  floor_snap=%.2f safe_margin=%.3f" % [
		cap.radius, cap.height, cs.position.y, cap_bottom_local, p.floor_snap_length, p.safe_margin])

	# Visual: lowest skinned vertex of the body mesh in root space (feet).
	var body := p.get_node_or_null("BodyVisual")
	var lowest := 1e9
	if body != null:
		for mi in _meshes(body):
			var a: AABB = (mi.global_transform.affine_inverse() * p.global_transform).affine_inverse() * mi.get_aabb()
			lowest = minf(lowest, a.position.y)
	print("[float] 身體 mesh AABB 最低點在 root 下 %.3f m（靜態 AABB，未計蒙皮）" % lowest)

	var spots := [
		["主街出生點", Vector3(235, 1.0, 16)],
		["主街北", Vector3(236, 1.0, 60)],
		["霧雨店前", Vector3(244, 1.0, 2)],
		["東河護岸頂", Vector3(400, 1.0, -134)],
		["河岸小徑", Vector3(405, 1.0, 20)],
		["西橋頭", Vector3(396, 1.0, -135)],
	]
	print("[float] %-12s %8s %8s %8s %8s  %s" % ["地點", "root.y", "地面y", "膠囊底", "浮空", "on_floor"])
	for s in spots:
		p.global_position = s[1]
		p.velocity = Vector3.ZERO
		for i in 40:
			await physics_frame
		var from := p.global_position + Vector3(0, 0.5, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -5, 0), p.collision_mask)
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		var gy: float = hit["position"].y if not hit.is_empty() else NAN
		var cb := p.global_position.y + cap_bottom_local
		print("[float] %-12s %8.3f %8.3f %8.3f %8.3f  %s  %s" % [
			s[0], p.global_position.y, gy, cb, cb - gy, p.is_on_floor(),
			(hit["collider"] as Node).name if not hit.is_empty() else "無地面"])
	print("done")
	quit(0)


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
