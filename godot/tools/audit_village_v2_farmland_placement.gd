extends SceneTree
## P8 overlay placement audit; runs only in memory against saved village scene.
## r3：田埂碰撞為折線多盒 → 每個 BoxShape 取 5 點地面射線；水面 proxy 每田 9 點。門檻不變。
const SCENE := "res://maps/village_v2/village_v2.tscn"
var fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		push_error("[FARM_PLACE] scene missing")
		quit(2)
		return
	var village := packed.instantiate()
	root.add_child(village)
	await physics_frame
	var farm: Node3D = village.get_node_or_null("Districts/FarmlandEast/FarmlandP8")
	if farm == null:
		push_error("[FARM_PLACE] overlay missing from saved village")
		quit(2)
		return
	var terrain := village.get_node("Collision/TerrainCollision") as CollisionObject3D
	var ground_rid := terrain.get_rid()
	var space: PhysicsDirectSpaceState3D = village.get_world_3d().direct_space_state
	var count := 0
	var expected := 0
	var max_abs_gap := 0.0
	for body: StaticBody3D in farm.get_node("Bunds").get_children():
		for shape: CollisionShape3D in body.get_children():
			var box := shape.shape as BoxShape3D
			var half := box.size * 0.5
			var xf := shape.global_transform
			for offset in [Vector2.ZERO, Vector2(-half.x * 0.9, -half.z * 0.9), Vector2(-half.x * 0.9, half.z * 0.9), Vector2(half.x * 0.9, -half.z * 0.9), Vector2(half.x * 0.9, half.z * 0.9)]:
				expected += 1
				var p := xf * Vector3(offset.x, -half.y, offset.y)
				var hit := _ground(space, p, ground_rid)
				if hit.is_empty():
					fails += 1
					print("[FARM_PLACE] FAIL no terrain under %s/%s at %s" % [body.name, shape.name, p])
					continue
				var gap: float = p.y - hit["position"].y
				max_abs_gap = maxf(max_abs_gap, absf(gap))
				if gap > 0.08 or gap < -0.12:
					fails += 1
					print("[FARM_PLACE] FAIL %s/%s gap %.3fm at %s" % [body.name, shape.name, gap, p])
				count += 1
	var water_samples := 0
	var max_intrusion := -INF
	for plot: Node3D in farm.get_node("Plots").get_children():
		var water: MeshInstance3D = plot.get_node("PaddyWater")
		var half_water: Vector3 = (water.mesh as BoxMesh).size * 0.5
		var water_top := water.global_position.y + half_water.y
		for fx in [-0.9, 0.0, 0.9]:
			for fz in [-0.9, 0.0, 0.9]:
				var p := water.global_position + Vector3(fx * half_water.x, 0, fz * half_water.z)
				var hit := _ground(space, p, ground_rid)
				if hit.is_empty():
					fails += 1
					continue
				var intrude: float = hit["position"].y - water_top
				max_intrusion = maxf(max_intrusion, intrude)
				if intrude > -0.01:
					fails += 1
					print("[FARM_PLACE] FAIL terrain pokes water %s at %s (%.3fm)" % [plot.name, p, intrude])
				water_samples += 1
	print("[FARM_PLACE] bund=%d water=%d samples, max |ground gap| %.3fm, max water intrusion %.3fm, %d failures" % [count, water_samples, max_abs_gap, max_intrusion, fails])
	village.queue_free()
	quit(0 if fails == 0 and count == expected and water_samples == farm.get_node("Plots").get_child_count() * 9 else 1)

func _ground(space: PhysicsDirectSpaceState3D, p: Vector3, ground_rid: RID) -> Dictionary:
	var exclusions: Array[RID] = []
	for retry in 30:
		var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 8, p.z), Vector3(p.x, p.y - 8, p.z))
		query.exclude = exclusions
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit["rid"] == ground_rid:
			return hit
		exclusions.append(hit["rid"])
	return {}
