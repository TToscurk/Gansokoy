extends RefCounted

## Deterministic river ecology for the Human Village generator. The caller
## owns and passes the shared street RNG so generation order remains stable.

static func river_reach(river: PackedVector2Array, fauna_z: Vector2, river_depth: float,
		bank_fn: Callable) -> Array:
	var points: Array[Vector2] = []
	var heights: Array[float] = []
	for point in river:
		if point.y < fauna_z.x or point.y > fauna_z.y:
			continue
		points.append(point)
		heights.append(
			float(bank_fn.call(point.x, point.y)) - river_depth * 0.20)
	return [points, heights]


static func build_fauna(lib, root: Node3D, river: PackedVector2Array,
		fauna_z: Vector2, river_half: float, river_depth: float,
		bridges: Array, uno_position: Vector2, plaza: Vector2,
		rng: RandomNumberGenerator, bank_fn: Callable,
		height_fn: Callable, audit: Array[String]) -> void:
	var reach := river_reach(river, fauna_z, river_depth, bank_fn)
	var points: Array = reach[0]
	var heights: Array = reach[1]
	if points.size() < 2:
		return
	var group: Node3D = lib.add(root, Node3D.new(), "Fauna")
	group.set_script(load("res://scripts/fauna.gd"))
	group.set("paths", [{"pts": points, "ys": heights}])
	var total_length := 0.0
	for index in range(points.size() - 1):
		total_length += (points[index] as Vector2).distance_to(points[index + 1])

	var segment_count := points.size() - 1
	var at_river := func(t: float, sink: float) -> Vector3:
		var segment_t: float = clampf(t, 0.0, 0.999) * float(segment_count)
		var index := int(segment_t)
		var fraction := segment_t - float(index)
		var start: Vector2 = points[index]
		var end: Vector2 = points[mini(index + 1, segment_count)]
		var position: Vector2 = start.lerp(end, fraction)
		position += (end - start).normalized().orthogonal() \
			* rng.randf_range(-2.2, 2.2)
		var water_y: float = lerpf(
			float(heights[index]),
			float(heights[mini(index + 1, segment_count)]), fraction)
		return Vector3(position.x, water_y - sink, position.y)
	var speed_fraction := func(meters_per_second: float) -> float:
		return meters_per_second / maxf(total_length, 1.0)

	var duck_mesh: Mesh = lib.prop_mesh("res://assets/models/duck.glb")
	var koi_mesh: Mesh = lib.prop_mesh("res://assets/models/koi.glb")
	for index in 9:
		var duck := MeshInstance3D.new()
		duck.mesh = duck_mesh
		duck.scale = Vector3.ONE * rng.randf_range(0.85, 1.15)
		var swim_t := rng.randf_range(0.06, 0.94)
		lib.add(group, duck, "鴨_%d" % index)
		duck.position = at_river.call(swim_t, -0.02)
		duck.rotation.y = rng.randf_range(0.0, TAU)
		duck.set_meta("swim_kind", 0)
		duck.set_meta("swim_t", swim_t)
		duck.set_meta(
			"swim_speed", speed_fraction.call(rng.randf_range(0.35, 0.9)))
	for index in 14:
		var koi := MeshInstance3D.new()
		koi.mesh = koi_mesh
		koi.scale = Vector3.ONE * rng.randf_range(0.8, 1.4)
		var swim_t := rng.randf_range(0.06, 0.94)
		lib.add(group, koi, "鯉_%d" % index)
		koi.position = at_river.call(swim_t, 0.32)
		koi.rotation.y = rng.randf_range(0.0, TAU)
		koi.set_meta("swim_kind", 1)
		koi.set_meta("swim_t", swim_t)
		koi.set_meta(
			"swim_speed", speed_fraction.call(rng.randf_range(0.6, 1.6)))

	var heron_mesh: Mesh = lib.prop_mesh("res://assets/models/heron.glb")
	var placed := 0
	var tries := 0
	var shore_offsets: Array[float] = []
	while placed < 5 and tries < 600:
		tries += 1
		var segment_index := rng.randi() % maxi(segment_count, 1)
		var start: Vector2 = points[segment_index]
		var end: Vector2 = points[mini(segment_index + 1, segment_count)]
		var segment_t := rng.randf()
		var centre: Vector2 = start.lerp(end, segment_t)
		var normal := (end - start).normalized().orthogonal()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var skip := false
		for bridge in bridges:
			if centre.distance_to(
					Vector2(float(bridge.x), float(bridge.z))) < 14.0:
				skip = true
		if skip or centre.distance_to(uno_position) < 22.0:
			continue
		if Vector2(centre.x, centre.y - plaza.y).length() < 134.0:
			continue
		var water_y: float = float(bank_fn.call(centre.x, centre.y)) \
			- river_depth * 0.20
		var found := Vector2.ZERO
		var found_y := 0.0
		var found_distance := 0.0
		var distance := river_half * 0.86
		while distance < river_half * 2.4:
			var candidate: Vector2 = centre + normal * side * distance
			var ground_y: float = height_fn.call(candidate.x, candidate.y)
			if ground_y >= water_y + 0.03:
				if ground_y <= water_y + 0.5:
					found = candidate
					found_y = ground_y
					found_distance = distance
				break
			distance += 0.2
		if found == Vector2.ZERO:
			continue
		var heron := MeshInstance3D.new()
		heron.mesh = heron_mesh
		heron.position = Vector3(found.x, found_y, found.y)
		heron.rotation.y = atan2(-normal.x * side, -normal.y * side) \
			+ rng.randf_range(-0.5, 0.5)
		heron.scale = Vector3.ONE * rng.randf_range(0.9, 1.15)
		lib.add(group, heron, "鷺鷥_%d" % placed)
		shore_offsets.append(found_distance)
		placed += 1
	if placed > 0:
		var average_offset := 0.0
		for offset in shore_offsets:
			average_offset += offset
		audit.append(
			"　鷺鷥水際線實測：離河心平均 %.2fm（河半寬 %.1f、水面半寬 %.2f）"
			% [average_offset / float(placed), river_half, river_half * 0.86])
	audit.append(
		"水邊生物：9 鴨 / 14 鯉 / %d 鷺鷥（巡游段 z %.0f~%.0f，全長 %.0fm）"
		% [placed, fauna_z.x, fauna_z.y, total_length])


static func build_water_plants(lib, root: Node3D,
		river: PackedVector2Array, out_dir: String, half: float,
		river_half: float, river_depth: float, bridges: Array,
		uno_position: Vector2, rng: RandomNumberGenerator,
		bank_fn: Callable, audit: Array[String]) -> void:
	var group: Node3D = lib.add(root, Node3D.new(), "WaterPlants")
	var lily_pad: Mesh = lib.tuft_mesh(
		6, 0.30, 0.34, Color(0.15, 0.29, 0.13), Color(0.27, 0.45, 0.19))
	var lotus: Mesh = lib.tuft_mesh(
		5, 0.46, 0.14, Color(0.20, 0.34, 0.16),
		Color(0.92, 0.72, 0.80), true)
	var plant_groups := [
		{"mesh": lily_pad, "n": 220, "band": Vector2(0.42, 0.86),
			"sink": -0.03, "file": "睡蓮"},
		{"mesh": lotus, "n": 80, "band": Vector2(0.52, 0.84),
			"sink": -0.30, "file": "荷"},
	]
	var total := 0
	var parts: Array[String] = []
	for plant_group in plant_groups:
		var transforms: Array[Transform3D] = []
		var tries := 0
		var target: int = int(plant_group.n)
		while transforms.size() < target and tries < target * 60:
			tries += 1
			var segment_index := int(rng.randf() * float(river.size() - 1))
			var start: Vector2 = river[segment_index]
			var end: Vector2 = river[segment_index + 1]
			var position: Vector2 = start.lerp(end, rng.randf())
			var band: Vector2 = plant_group.band
			var offset: float = river_half * rng.randf_range(band.x, band.y) \
				* (1.0 if rng.randf() < 0.5 else -1.0)
			position += (end - start).normalized().orthogonal() * offset
			if absf(position.x) > half - 8.0 or absf(position.y) > half - 8.0:
				continue
			var skip := false
			for bridge in bridges:
				if position.distance_to(
						Vector2(float(bridge.x), float(bridge.z))) < 12.0:
					skip = true
					break
			if skip or position.distance_to(uno_position) < 16.0:
				continue
			var river_distance: float = lib.poly_dist(
				river, position.x, position.y)
			if river_distance > river_half * 0.86 - 0.3 \
					or river_distance < river_half * 0.30:
				continue
			var water_y: float = float(bank_fn.call(position.x, position.y)) \
				- river_depth * 0.20 + float(plant_group.sink)
			var scale := rng.randf_range(0.7, 1.5)
			transforms.append(Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU).scaled(
					Vector3(scale, scale, scale)),
				Vector3(position.x, water_y, position.y)))
		total += transforms.size()
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = lib.make_multimesh(
			plant_group.mesh, transforms, [],
			out_dir + "gen/water_%s.res" % String(plant_group.file))
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(group, instance, String(plant_group.file))
		parts.append("%s %d" % [String(plant_group.file), transforms.size()])
	audit.append("水生植物：%s（共 %d 株，貼岸帶 0.42~0.86 半寬）"
		% [", ".join(parts), total])
