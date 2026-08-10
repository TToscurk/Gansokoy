extends RefCounted

## Deterministic street-edge fixtures for the Human Village generator.

static func build_fence(lib, root: Node3D, group: Node3D, fixed_x: float,
		start_z: float, end_z: float, gaps: Array, dark: Material,
		boards: Material, height_fn: Callable, height := 1.7,
		collide := true) -> void:
	var cursor := start_z
	var post_index := 0
	while cursor < end_z - 0.1:
		var segment_end := minf(cursor + 1.9, end_z)
		var in_gap := false
		for gap in gaps:
			if cursor < float(gap[1]) and segment_end > float(gap[0]):
				in_gap = true
				break
		var ground_y: float = height_fn.call(
			fixed_x, (cursor + segment_end) * 0.5)
		if not in_gap:
			lib.box(group, "塀板_%d_%d" % [int(fixed_x * 10.0), post_index],
				Vector3(0.08, height - 0.26, segment_end - cursor - 0.13), boards,
				Vector3(fixed_x, ground_y + 0.18 + (height - 0.26) * 0.5,
					(cursor + segment_end) * 0.5))
			lib.box(group, "塀笠_%d_%d" % [int(fixed_x * 10.0), post_index],
				Vector3(0.16, 0.09, segment_end - cursor + 0.05), dark,
				Vector3(fixed_x, ground_y + height - 0.02,
					(cursor + segment_end) * 0.5))
		lib.box(group, "塀柱_%d_%d" % [int(fixed_x * 10.0), post_index],
			Vector3(0.14, height + 0.08, 0.14), dark,
			Vector3(fixed_x,
				float(height_fn.call(fixed_x, cursor)) + (height + 0.08) * 0.5,
				cursor))
		cursor = segment_end
		post_index += 1
	lib.box(group, "塀柱_%d_end" % int(fixed_x * 10.0),
		Vector3(0.14, height + 0.08, 0.14), dark,
		Vector3(fixed_x,
			float(height_fn.call(fixed_x, end_z)) + (height + 0.08) * 0.5,
			end_z))
	if not collide:
		return
	for span in [
			[start_z, gaps[0][0] if gaps.size() > 0 else end_z],
			[gaps[0][1] if gaps.size() > 0 else end_z, end_z],
		]:
		var span_start := float(span[0])
		var span_end := float(span[1])
		if span_end - span_start < 0.5:
			continue
		var body := StaticBody3D.new()
		group.add_child(body)
		body.owner = root
		var collision_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.25, height, span_end - span_start)
		collision_shape.shape = box
		collision_shape.position = Vector3(
			fixed_x,
			float(height_fn.call(fixed_x, (span_start + span_end) * 0.5))
				+ height * 0.5,
			(span_start + span_end) * 0.5)
		body.add_child(collision_shape)
		collision_shape.owner = root


static func build_mune_gate(lib, group: Node3D, fixed_x: float,
		fixed_z: float, width: float, dark: Material, roof: Material,
		stone: Material, height_fn: Callable) -> void:
	var ground_y: float = height_fn.call(fixed_x, fixed_z)
	var gate: Node3D = lib.add(
		group, Node3D.new(), "門_%d" % int(fixed_z))
	gate.position = Vector3(fixed_x, ground_y, fixed_z)
	for side in [-1.0, 1.0]:
		lib.box(gate, "門柱_%d" % int(side + 1.0),
			Vector3(0.19, 2.30, 0.19), dark,
			Vector3(0, 1.15, side * width * 0.5))
	lib.box(gate, "冠木", Vector3(0.17, 0.20, width + 0.55), dark,
		Vector3(0, 2.22, 0))
	lib.gable_roof(gate, 2.42, 1.30, width + 0.95, 0.42, 0.11,
		roof, dark)
	for index in 3:
		lib.box(group, "門敷石_%d_%d" % [int(fixed_z), index],
			Vector3(0.95, 0.07, 0.75), stone,
			Vector3(
				fixed_x + (0.55 + float(index) * 0.85)
					* (1.0 if fixed_x < 0.0 else -1.0) * -1.0,
				float(height_fn.call(fixed_x, fixed_z)) + 0.02,
				fixed_z))

static func build_gutters(lib, root: Node3D, out_dir: String,
		main_ew_z: float, main_ew_w: float, gutter_segment: float,
		gutter_commerce: float, river_half: float, roads: Array,
		commerce_fn: Callable, in_pilot_fn: Callable,
		river_dist_fn: Callable, height_fn: Callable,
		audit: Array[String]) -> void:
	var walls: Array[Transform3D] = []
	var floors: Array[Transform3D] = []
	var lids: Array[Transform3D] = []
	var runs := [
		{"ri": 0, "along_x": false, "fix": 0.0,
			"a": -170.0, "b": 220.0, "hw": 4.0},
		{"ri": 1, "along_x": true, "fix": main_ew_z,
			"a": -80.0, "b": 130.0, "hw": main_ew_w * 0.5},
	]
	var segment_count := 0
	var covered_count := 0
	for run in runs:
		var along_x: bool = bool(run.along_x)
		var offset: float = float(run.hw) + 0.6
		for side in [-1.0, 1.0]:
			var distance: float = float(run.a)
			var run_segment_index := 0
			while distance < float(run.b):
				var middle := distance + gutter_segment * 0.5
				var position := Vector2(
					middle, float(run.fix) + side * offset) if along_x \
					else Vector2(float(run.fix) + side * offset, middle)
				distance += gutter_segment
				run_segment_index += 1
				if float(commerce_fn.call(position)) < gutter_commerce \
						and not bool(in_pilot_fn.call(position.x, position.y)):
					continue
				if float(river_dist_fn.call(position.x, position.y)) < river_half + 2.0:
					continue
				var covered := false
				for road_index in roads.size():
					if road_index == int(run.ri):
						continue
					var road: Dictionary = roads[road_index]
					if lib.poly_dist(road.pts, position.x, position.y) \
							< float(road.w) * 0.5 + 1.2:
						covered = true
						break
				var ground_y: float = height_fn.call(position.x, position.y)
				var basis := Basis(Vector3.UP, PI * 0.5) if along_x else Basis()
				segment_count += 1
				if covered:
					covered_count += 1
					lids.append(Transform3D(
						basis.scaled(Vector3(1, 1, gutter_segment / 1.6)),
						Vector3(position.x, ground_y + 0.02, position.y)))
					continue
				for wall_side in [-1.0, 1.0]:
					var wall_offset := Vector2(0.0, wall_side * 0.42) if along_x \
						else Vector2(wall_side * 0.42, 0.0)
					walls.append(Transform3D(basis,
						Vector3(position.x + wall_offset.x, ground_y - 0.24,
							position.y + wall_offset.y)))
				floors.append(Transform3D(
					basis, Vector3(position.x, ground_y - 0.46, position.y)))
				if run_segment_index % 6 == 1:
					lids.append(Transform3D(
						basis, Vector3(position.x, ground_y + 0.02, position.y)))
	if segment_count == 0:
		return
	var stone: StandardMaterial3D = lib.pbr(
		"溝石", "stone_wall", 0.55, Color(0.60, 0.61, 0.59))
	var slab: StandardMaterial3D = lib.pbr(
		"溝蓋石", "stone_flag", 1.9, Color(0.42, 0.43, 0.42))
	var group: Node3D = lib.add(root, Node3D.new(), "石溝")
	var parts := [
		{"size": Vector3(0.22, 0.5, gutter_segment),
			"list": walls, "mat": stone, "n": "溝壁"},
		{"size": Vector3(0.7, 0.12, gutter_segment),
			"list": floors, "mat": stone, "n": "溝底"},
		{"size": Vector3(1.05, 0.10, 1.6),
			"list": lids, "mat": slab, "n": "溝蓋"},
	]
	for part in parts:
		var mesh := BoxMesh.new()
		mesh.size = part.size
		mesh.material = part.mat
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = lib.make_multimesh(
			mesh, part.list, [],
			out_dir + "gen/gutter_%s.res" % String(part.n))
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(group, instance, String(part.n))
	audit.append("石溝 %d 節（其中 %d 節是橫街的覆蓋段）→ 3 個 MultiMesh"
		% [segment_count, covered_count])

static func build_lamps(lib, root: Node3D, anchors: Array,
		reserved_fn: Callable, height_fn: Callable, audit: Array[String]) -> void:
	var group: Node3D = lib.add(root, Node3D.new(), "街燈")
	var wood: StandardMaterial3D = lib.pbr(
		"行灯柱", "dark_wood", 2.4, Color(0.42, 0.40, 0.37))
	var stone: StandardMaterial3D = lib.pbr(
		"行灯台石", "stone_flag", 1.8, Color(0.50, 0.51, 0.49))
	var paper: StandardMaterial3D = lib.flat_mat(
		"行灯紙", Color(0.93, 0.87, 0.72), 0.6,
		Color(0.34, 0.245, 0.115))
	var count := 0
	for anchor in anchors:
		var position := Vector2(float(anchor[0]), float(anchor[1]))
		if bool(reserved_fn.call(position, 0.8)):
			continue
		var lamp := Node3D.new()
		lamp.position = Vector3(
			position.x,
			float(height_fn.call(position.x, position.y)),
			position.y)
		lamp.rotation.y = 0.35 * float((count * 7) % 5 - 2) * 0.25
		lib.add(group, lamp, "街燈_%d" % count)
		lib.box(lamp, "台石", Vector3(0.50, 0.22, 0.50), stone,
			Vector3(0, 0.11, 0))
		lib.box(lamp, "柱", Vector3(0.13, 1.85, 0.13), wood,
			Vector3(0, 0.22 + 0.925, 0))
		lib.box(lamp, "火袋", Vector3(0.36, 0.44, 0.36), paper,
			Vector3(0, 2.32, 0))
		for corner in 4:
			lib.box(lamp, "框_%d" % corner, Vector3(0.05, 0.50, 0.05), wood,
				Vector3((-1.0 if corner % 2 == 0 else 1.0) * 0.165, 2.32,
					(-1.0 if corner < 2 else 1.0) * 0.165))
		lib.box(lamp, "笠", Vector3(0.56, 0.06, 0.56), wood,
			Vector3(0, 2.60, 0))
		lib.box(lamp, "笠上", Vector3(0.34, 0.05, 0.34), wood,
			Vector3(0, 2.65, 0))
		var light := OmniLight3D.new()
		light.position = Vector3(0, 2.32, 0)
		light.light_color = Color(1.0, 0.76, 0.46)
		light.light_energy = 1.1
		light.omni_range = 8.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 55.0
		light.distance_fade_length = 15.0
		lib.add(lamp, light, "光")
		count += 1
	audit.append(
		"街燈 %d 盞（辻行灯：門・辻・社前・市の口・橋詰だけ。等間隔配置は廃止）" % count)
