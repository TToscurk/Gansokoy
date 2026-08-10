extends RefCounted


static func build(
		lib,
		root: Node3D,
		out_dir: String,
		landmarks: Array,
		hieda_offset: Vector2,
		grove_seed: int,
		road_info: Callable,
		height_at: Callable,
		village_tree_mesh: Callable,
		audit: Array[String]) -> void:
	var landmark: Dictionary = {}
	for candidate in landmarks:
		if candidate.n == "稗田邸":
			landmark = candidate
	if landmark.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = grove_seed
	var half_width: float = float(landmark.w) * 0.5
	var half_depth: float = float(landmark.d) * 0.5
	var centre_x: float = float(landmark.x)
	var centre_z: float = float(landmark.z)
	var kinds := [
		"res://assets/models/tree_round_a.glb",
		"res://assets/models/tree_round_c.glb",
		"res://assets/models/tree_pine_a.glb",
	]
	var batches := {}
	var attempts := 0
	var count := 0
	while count < 46 and attempts < 3000:
		attempts += 1
		var x := rng.randf_range(
			centre_x - half_width - 9.0, centre_x + half_width + 9.0)
		var z := rng.randf_range(
			centre_z - half_depth - 9.0, centre_z + half_depth + 9.0)
		var outside_x := absf(x - centre_x) - half_width
		var outside_z := absf(z - centre_z) - half_depth
		var outside := maxf(outside_x, outside_z)
		if outside < 3.0 or outside > 9.0:
			continue
		if absf(z + 135.0) < 9.0:
			continue
		if absf(x - (centre_x + hieda_offset.x)) < 9.0 and z > centre_z:
			continue
		if float(road_info.call(x, z)) > 0.02:
			continue
		var kind: String = kinds[count % kinds.size()]
		if not batches.has(kind):
			batches[kind] = [] as Array[Transform3D]
		var scale := rng.randf_range(0.72, 1.15)
		batches[kind].append(Transform3D(
			Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				* Basis.from_scale(Vector3(scale, scale, scale)),
			Vector3(x, float(height_at.call(x, z)), z)))
		count += 1
	var group: Node3D = lib.add(root, Node3D.new(), "稗田邸緩衝林")
	var sorted_kinds: Array = batches.keys()
	sorted_kinds.sort()
	for kind in sorted_kinds:
		var instance := MultiMeshInstance3D.new()
		var mesh: Mesh = village_tree_mesh.call(String(kind))
		instance.multimesh = lib.make_multimesh(
			mesh, batches[kind], [], out_dir + "gen/mm_hieda_grove_%s.res"
				% String(kind).get_file().get_basename())
		lib.add(group, instance, "MM_%s" % String(kind).get_file().get_basename())
	audit.append("稗田邸緩衝疏林：%d 株 / %d 種（保留區外緣 3~9m 環帶，門面動線讓開）"
		% [count, sorted_kinds.size()])
