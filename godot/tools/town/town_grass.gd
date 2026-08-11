extends RefCounted


## Remove grass under deterministic post-grass features without consuming RNG.
## get_instance_transform returns identity under the headless dummy renderer,
## so read and rewrite the MultiMesh buffer directly with stride 12.
static func cut_footprints(root: Node3D, footprints: Array) -> int:
	const GRASS_NODES := ["Shrubs", "Ferns", "GrassTall", "GrassFlower", "Reeds"]
	var cut := 0
	for child in root.get_children():
		if not (child is MultiMeshInstance3D) \
				or not (String(child.name) in GRASS_NODES):
			continue
		var multimesh: MultiMesh = (child as MultiMeshInstance3D).multimesh
		var buffer: PackedFloat32Array = multimesh.buffer
		var stride := 12
		var keep := PackedFloat32Array()
		var kept := 0
		for index in multimesh.instance_count:
			var offset := index * stride
			var position := Vector2(buffer[offset + 3], buffer[offset + 11])
			var hit := false
			for footprint in footprints:
				var delta: Vector2 = position - (footprint[0] as Vector2)
				if absf(delta.x) < float(footprint[1]) \
						and absf(delta.y) < float(footprint[2]):
					hit = true
					break
			if hit:
				cut += 1
			else:
				keep.append_array(buffer.slice(offset, offset + stride))
				kept += 1
		if kept != multimesh.instance_count:
			var replacement := MultiMesh.new()
			replacement.transform_format = MultiMesh.TRANSFORM_3D
			replacement.mesh = multimesh.mesh
			replacement.instance_count = kept
			replacement.buffer = keep
			(child as MultiMeshInstance3D).multimesh = replacement
	return cut


static func build(
		lib,
		root: Node3D,
		out_dir: String,
		half: float,
		river: PackedVector2Array,
		river_half: float,
		bridges: Array,
		riverside_diner_position: Vector2,
		dump: Array,
		reserved: Array,
		rng: RandomNumberGenerator,
		patch_noise: FastNoiseLite,
		mask_at: Callable,
		obb_of: Callable,
		road_dist: Callable,
		commerce: Callable,
		height_at: Callable,
		audit: Array[String]) -> void:
	var house_grid := _build_house_grid(dump, obb_of)
	var tall: Mesh = lib.tuft_mesh(
		7, 0.40, 0.20, Color(0.11, 0.21, 0.08), Color(0.29, 0.48, 0.18))
	tall.surface_set_material(0, lib.grass_wind_mat(0.10))
	var flower: Mesh = lib.tuft_mesh(
		5, 0.34, 0.16, Color(0.12, 0.22, 0.09),
		Color(0.28, 0.46, 0.18), true)
	flower.surface_set_material(0, lib.grass_wind_mat(0.08))
	var reed: Mesh = lib.tuft_mesh(
		6, 0.62, 0.14, Color(0.18, 0.28, 0.12), Color(0.52, 0.56, 0.28))
	reed.surface_set_material(0, lib.grass_wind_mat(0.13))
	var shrub: Mesh = lib.tuft_mesh(
		9, 1.05, 0.55, Color(0.10, 0.20, 0.08), Color(0.26, 0.42, 0.16))
	shrub.surface_set_material(0, lib.grass_wind_mat(0.05))
	var fern: Mesh = lib.tuft_mesh(
		7, 0.55, 0.40, Color(0.13, 0.24, 0.10), Color(0.32, 0.50, 0.20))
	fern.surface_set_material(0, lib.grass_wind_mat(0.06))
	var groups := [
		{"mesh": shrub, "n": 2400, "file": "shrubs", "node": "Shrubs",
			"mode": "wild", "need": 2.6, "patch": 0.48, "edge": 0.78},
		{"mesh": fern, "n": 5000, "file": "ferns", "node": "Ferns",
			"mode": "wild", "need": 1.6, "patch": 0.42, "edge": 0.66},
		{"mesh": tall, "n": 14000, "file": "grass_tall", "node": "GrassTall",
			"mode": "wild", "need": 1.6, "patch": 0.38, "edge": 0.58},
		{"mesh": flower, "n": 1000, "file": "grass_flower", "node": "GrassFlower",
			"mode": "wild", "need": 1.6, "patch": 0.58, "edge": 0.72},
		{"mesh": reed, "n": 1800, "file": "reeds", "node": "Reeds",
			"mode": "shore", "need": 0.0},
	]
	var total := 0
	var parts: Array[String] = []
	for group_index in range(groups.size()):
		var grass_group: Dictionary = groups[group_index]
		var transforms: Array[Transform3D] = []
		var target: int = int(grass_group.n)
		if String(grass_group.mode) == "shore":
			transforms = _reeds_along_river(
				rng, target, river, river_half, half, bridges,
				riverside_diner_position, height_at)
		else:
			var attempts := 0
			while transforms.size() < target and attempts < target * 30:
				attempts += 1
				var x := rng.randf_range(-half + 4.0, half - 4.0)
				var z := rng.randf_range(-half + 4.0, half - 4.0)
				if not _grass_free(
						lib, x, z, float(grass_group.need), house_grid,
						mask_at, river, river_half, reserved):
					continue
				var distance_to_road: float = road_dist.call(x, z)
				var position := Vector2(x, z)
				var activity := maxf(
					float(commerce.call(position)),
					1.0 - smoothstep(2.5, 14.0, distance_to_road))
				activity = maxf(
					activity,
					1.0 - smoothstep(
						28.0, 48.0, position.distance_to(Vector2(-26, 57))))
				activity = maxf(
					activity * 0.82,
					1.0 - smoothstep(
						22.0, 38.0, position.distance_to(Vector2(-26, 2))))
				var edge_distance := maxf(absf(x), absf(z))
				var edge_factor := smoothstep(105.0, 225.0, edge_distance)
				var zone := lerpf(1.0 - float(grass_group.edge), 1.0, edge_factor)
				var noise_value := patch_noise.get_noise_2d(
					x + float(group_index) * 137.0,
					z - float(group_index) * 83.0) * 0.5 + 0.5
				var colony := smoothstep(float(grass_group.patch), 0.82, noise_value)
				var probability := colony * zone * lerpf(0.10, 1.0, 1.0 - activity)
				if rng.randf() > probability:
					continue
				var scale := rng.randf_range(0.7, 1.4)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(
					Vector3(scale, scale, scale))
				transforms.append(Transform3D(
					basis, Vector3(x, float(height_at.call(x, z)), z)))
		total += transforms.size()
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = lib.make_multimesh(
			grass_group.mesh, transforms, [],
			out_dir + "gen/%s.res" % String(grass_group.file))
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(root, instance, String(grass_group.node))
		parts.append("%s %d" % [String(grass_group.node), transforms.size()])
	audit.append("草層：%s —— 共 %d 叢 / %d draw call（稻田不搬：農田是延後項目）"
		% [", ".join(parts), total, groups.size()])


static func _build_house_grid(dump: Array, obb_of: Callable) -> Dictionary:
	var grid := {}
	for entry in dump:
		var bounds: Array = obb_of.call(entry)
		var centre: Vector2 = bounds[0]
		var radius: float = maxf(bounds[3], bounds[4]) + 3.0
		var min_x := int(floor((centre.x - radius) / 24.0))
		var max_x := int(floor((centre.x + radius) / 24.0))
		var min_z := int(floor((centre.y - radius) / 24.0))
		var max_z := int(floor((centre.y + radius) / 24.0))
		for x_index in range(min_x, max_x + 1):
			for z_index in range(min_z, max_z + 1):
				var key := Vector2i(x_index, z_index)
				if not grid.has(key):
					grid[key] = []
				grid[key].append(bounds)
	return grid


static func _grass_free(
		lib,
		x: float,
		z: float,
		need: float,
		house_grid: Dictionary,
		mask_at: Callable,
		river: PackedVector2Array,
		river_half: float,
		reserved: Array) -> bool:
	var mask: Color = mask_at.call(x, z)
	if mask.r + mask.a > 0.30:
		return false
	if lib.poly_dist(river, x, z) < river_half + 1.6:
		return false
	var position := Vector2(x, z)
	for bounds in reserved:
		var delta: Vector2 = position - bounds[0]
		if absf(delta.dot(bounds[1])) < bounds[3] + need \
				and absf(delta.dot(bounds[2])) < bounds[4] + need:
			return false
	var key := Vector2i(int(floor(x / 24.0)), int(floor(z / 24.0)))
	for x_offset in [-1, 0, 1]:
		for z_offset in [-1, 0, 1]:
			var nearby_key := Vector2i(key.x + x_offset, key.y + z_offset)
			if not house_grid.has(nearby_key):
				continue
			for bounds in house_grid[nearby_key]:
				var delta: Vector2 = position - bounds[0]
				if absf(delta.dot(bounds[1])) < bounds[3] + need \
						and absf(delta.dot(bounds[2])) < bounds[4] + need:
					return false
	return true


static func _reeds_along_river(
		rng: RandomNumberGenerator,
		target: int,
		river: PackedVector2Array,
		river_half: float,
		half: float,
		bridges: Array,
		riverside_diner_position: Vector2,
		height_at: Callable) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var total_length := 0.0
	for index in range(river.size() - 1):
		total_length += river[index].distance_to(river[index + 1])
	if total_length <= 0.0:
		return transforms
	var plants_per_metre := float(target) / total_length
	for index in range(river.size() - 1):
		var start: Vector2 = river[index]
		var finish: Vector2 = river[index + 1]
		var segment := finish - start
		var length := segment.length()
		if length <= 0.0001:
			continue
		var normal := Vector2(segment.y, -segment.x) / length
		var count := int(round(length * plants_per_metre))
		for plant_index in count:
			var on_segment: Vector2 = start + segment * rng.randf()
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var offset := rng.randf_range(river_half * 0.82, river_half * 1.52)
			var position: Vector2 = on_segment + normal * side * offset
			if absf(position.x) > half - 4.0 or absf(position.y) > half - 4.0:
				continue
			var skip := false
			for bridge in bridges:
				if position.distance_to(Vector2(float(bridge.x), float(bridge.z))) < 16.0:
					skip = true
					break
			if skip or position.distance_to(riverside_diner_position) < 20.0:
				continue
			var scale := rng.randf_range(0.7, 1.4)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(
				Vector3(scale, scale, scale))
			transforms.append(Transform3D(
				basis,
				Vector3(
					position.x,
					float(height_at.call(position.x, position.y)),
					position.y)))
	return transforms
