extends RefCounted

## Shared deterministic infrastructure for landmark and civic builders.
## Callers retain ownership of generator state and RNG objects.

static func ground_sample(lib, river: PackedVector2Array, river_half: float,
		river_depth: float, height_fn: Callable, bank_fn: Callable,
		x: float, z: float) -> float:
	var y: float = height_fn.call(x, z)
	if lib.poly_dist(river, x, z) < river_half:
		y = maxf(y, float(bank_fn.call(x, z)) - river_depth * 0.20)
	return y


static func ground_under(sample_fn: Callable, cx: float, cz: float,
		w: float, d: float) -> Array:
	var lo := INF
	var hi := -INF
	var nx := clampi(int(ceil(w / 4.0)) + 1, 3, 9)
	var nz := clampi(int(ceil(d / 4.0)) + 1, 3, 9)
	for i in nx:
		for j in nz:
			var ox := float(i) / float(nx - 1) - 0.5
			var oz := float(j) / float(nz - 1) - 0.5
			var y: float = sample_fn.call(cx + ox * w, cz + oz * d)
			lo = minf(lo, y)
			hi = maxf(hi, y)
	return [lo, hi - lo]


static func add_collision(root: Node3D, group: Node3D, size: Vector3,
		offset := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	group.add_child(body)
	body.owner = root
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = offset + Vector3(0, size.y * 0.5, 0)
	body.add_child(shape)
	shape.owner = root


## Blockout material uses vertex colour and disables back-face culling. Blender
## rendered the source as double-sided, while Godot otherwise removed several
## reversed ground quads, including the full cut-stone approach.
static func hieda_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.88
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.resource_name = "hieda_blockout_vc"
	return material


static func build_hieda(lib, group: Node3D, offset: Vector2,
		flatten_fn: Callable, bank_fn: Callable, audit: Array[String]) -> void:
	# The yard is flattened, but keep deriving its height so future terrain
	# changes remain aligned with the baked blockout.
	var bank: float = bank_fn.call(group.position.x, group.position.z)
	var yard: float = flatten_fn.call(
		group.position.x, group.position.z, bank) - group.position.y
	var local_offset := Vector3(offset.x, yard, offset.y)
	var body := MeshInstance3D.new()
	body.mesh = lib.prop_mesh(
		"res://assets/models/hieda_blockout.glb", hieda_material())
	body.position = local_offset
	body.set_meta("needs_trimesh", true)
	lib.add(group, body, "本體")
	# Planting coordinates share the baked blockout's local coordinate system.
	var holder := lib.add(group, Node3D.new(), "植栽") as Node3D
	holder.position = local_offset
	var count: int = preload("res://tools/gen_hieda.gd").new().emit(lib, holder)
	audit.append("稗田邸（完整獨立版）：blockout 22,600 面 + 植栽 %d 實例 / 10 模組" % count)


static func build_ashiarai(lib, group: Node3D, spread: float,
		rng: RandomNumberGenerator, material_fn: Callable,
		collision_fn: Callable) -> void:
	# The legacy broken walls were asymmetric, so shift the content back to the
	# centre of its symmetric reservation.
	var body := lib.add(group, Node3D.new(), "本體") as Node3D
	body.position.z = 4.25
	var half_w := 42.0 * 0.5 - 2.0
	var half_d := 45.0 * 0.5 - 2.0
	for wall in [[0.0, -half_d, half_w * 1.4, true],
			[-half_w, -6.0, half_d * 0.9, false],
			[half_w, 4.0, half_d * 0.8, false]]:
		var height := rng.randf_range(1.2, 1.9)
		var foot := spread + 0.4
		lib.box(body, "崩れ塀_%d" % int(wall[0]),
			Vector3(wall[2] if wall[3] else 0.36,
				height + foot, 0.36 if wall[3] else wall[2]),
			material_fn.call("mud", -1),
			Vector3(wall[0], height * 0.5 - foot * 0.5, wall[1]))
	var house_foot := spread + 0.4
	lib.box(body, "母屋基壇", Vector3(16.0, 0.5 + house_foot, 12.0),
		material_fn.call("stone", -1),
		Vector3(0, 0.25 - house_foot * 0.5, -2.0))
	lib.box(body, "母屋", Vector3(14.5, 3.6, 10.5),
		material_fn.call("dark", -1), Vector3(0, 2.3, -2.0))
	lib.gable_roof(body, 4.1, 17.0, 13.0, 0.62, 0.5,
		material_fn.call("thatch", -1), material_fn.call("dark", -1),
		Vector3(0, 0, -2.0))
	collision_fn.call(body, Vector3(14.9, 5.4, 10.9), Vector3(0, 0, -2.0))


static func build_suzunaan(lib, group: Node3D, material_fn: Callable,
		collision_fn: Callable) -> void:
	group.rotation.y = -PI / 2.0
	var width := 13.0
	var depth := 9.5
	lib.box(group, "基石", Vector3(width + 0.5, 0.35, depth + 0.5),
		material_fn.call("stone", -1), Vector3(0, 0.18, 0))
	lib.box(group, "屋身", Vector3(width, 5.4, depth),
		material_fn.call("plaster", -1), Vector3(0, 3.05, 0))
	lib.box(group, "腰板", Vector3(width + 0.05, 1.0, 0.08),
		material_fn.call("dark", -1), Vector3(0, 0.85, depth * 0.5 + 0.05))
	lib.box(group, "格子戶", Vector3(width * 0.62, 2.1, 0.1),
		material_fn.call("dark", -1), Vector3(0, 1.75, depth * 0.5 + 0.06))
	lib.box(group, "二階窗", Vector3(width * 0.72, 1.3, 0.08),
		material_fn.call("dark", -1), Vector3(0, 4.3, depth * 0.5 + 0.06))
	lib.box(group, "庇", Vector3(width + 1.0, 0.16, 1.4),
		material_fn.call("kawara", -1), Vector3(0, 3.35, depth * 0.5 + 0.6))
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.28, 0.24, 0.34)
	cloth.roughness = 1.0
	for index in [-1, 0, 1]:
		lib.box(group, "暖簾_%d" % (index + 1), Vector3(2.0, 0.9, 0.05), cloth,
			Vector3(float(index) * 2.2, 2.55, depth * 0.5 + 0.66))
	lib.box(group, "看板", Vector3(0.6, 2.4, 0.14),
		material_fn.call("wood", -1),
		Vector3(width * 0.44, 3.0, depth * 0.5 + 0.5))
	lib.box(group, "書架", Vector3(4.2, 1.3, 0.9),
		material_fn.call("wood", -1), Vector3(-2.6, 1.0, depth * 0.5 + 1.1))
	lib.gable_roof(group, 5.75, width + 1.4, depth + 1.6, 0.5, 0.24,
		material_fn.call("kawara", -1), material_fn.call("plaster", -1))
	collision_fn.call(group, Vector3(width + 0.5, 7.0, depth + 0.5), Vector3.ZERO)


static func build_terakoya(lib, group: Node3D, spread: float,
		dais_fn: Callable, material_fn: Callable, collision_fn: Callable) -> void:
	const DAIS_H := 1.5
	group.position.y += DAIS_H
	# The bell, worship porch, and basin make the contents east/south-heavy, so
	# shift them back toward the centre of the reserved landmark footprint.
	var body := lib.add(group, Node3D.new(), "本體") as Node3D
	body.position = Vector3(-0.55, 0.0, -1.35)
	dais_fn.call(body, 26.0, 16.0, DAIS_H, Vector2(0, 1), spread)
	lib.box(body, "土台", Vector3(24.0, 0.5, 14.0),
		material_fn.call("stone", -1), Vector3(0, 0.25, 0))
	lib.box(body, "屋身", Vector3(22.0, 4.6, 12.0),
		material_fn.call("plaster", 0), Vector3(0, 2.9, 0))
	lib.box(body, "外廊", Vector3(23.4, 0.34, 3.0),
		material_fn.call("wood", -1), Vector3(0, 0.85, 7.2))
	lib.box(body, "高欄", Vector3(23.4, 0.14, 0.14),
		material_fn.call("dark", -1), Vector3(0, 1.62, 8.6))
	for i in 14:
		lib.box(body, "高欄束_%d" % i, Vector3(0.1, 0.62, 0.1),
			material_fn.call("dark", -1),
			Vector3(-11.2 + float(i) * 1.72, 1.32, 8.6))
	for i in 8:
		lib.cyl(body, "廊柱_%d" % i, 0.19, 0.19, 3.6,
			material_fn.call("dark", -1),
			Vector3(-10.0 + float(i) * 2.85, 2.8, 8.4), 6)
	for i in 5:
		lib.box(body, "障子_%d" % i, Vector3(3.4, 2.8, 0.08),
			lib.flat_mat("shoji", Color(0.94, 0.93, 0.88), 0.9),
			Vector3(-8.6 + float(i) * 4.3, 2.25, 6.05))
		lib.box(body, "障子框_%d" % i, Vector3(3.6, 0.14, 0.12),
			material_fn.call("dark", -1),
			Vector3(-8.6 + float(i) * 4.3, 3.72, 6.05))
	lib.gable_roof(body, 5.2, 26.0, 16.0, 0.52, 0.4,
		material_fn.call("kawara", -1), material_fn.call("plaster", 0))
	lib.box(body, "向拜屋根", Vector3(7.4, 0.3, 3.4),
		material_fn.call("kawara", -1), Vector3(0, 4.6, 8.0))
	for side in [-1.0, 1.0]:
		lib.cyl(body, "向拜柱_%d" % int(side + 1), 0.22, 0.24, 4.4,
			material_fn.call("dark", -1),
			Vector3(side * 3.2, 2.2, 9.2), 8)
	lib.box(body, "梵鐘架", Vector3(2.6, 0.3, 2.6),
		material_fn.call("dark", -1), Vector3(13.0, 3.4, 6.0))
	lib.cyl(body, "梵鐘", 0.62, 0.78, 1.5,
		lib.pbr("bonsho", "stone_wall", 0.6, Color(0.52, 0.58, 0.52)),
		Vector3(13.0, 2.4, 6.0), 12)
	lib.box(body, "立札", Vector3(1.6, 1.1, 0.1),
		material_fn.call("wood", -1), Vector3(-8.0, 1.3, 10.5))
	lib.cyl(body, "手水缽", 0.7, 0.75, 0.7,
		material_fn.call("stone", -1), Vector3(9.0, 0.35, 10.0), 10)
	collision_fn.call(body, Vector3(22.4, 7.0, 12.4), Vector3.ZERO)


static func build_grove(lib, group: Node3D, root: Node3D,
		rng: RandomNumberGenerator, height_fn: Callable,
		road_dist_fn: Callable, tree_mesh_fn: Callable,
		material_fn: Callable) -> void:
	var world_centre := Vector2(group.position.x, group.position.z)
	var origin_y: float = group.position.y
	var local_position := func(wx: float, wz: float, dy: float) -> Vector3:
		return Vector3(
			wx - world_centre.x,
			float(height_fn.call(wx, wz)) - origin_y + dy,
			wz - world_centre.y)

	var post_material = material_fn.call("stone", 1)
	lib.cyl(group, "土壇", 5.6, 6.4, 0.7, material_fn.call("stone", 2),
		local_position.call(world_centre.x, world_centre.y, 0.25), 16)
	var sacred_tree := MeshInstance3D.new()
	sacred_tree.mesh = tree_mesh_fn.call("res://assets/models/tree_round_a.glb")
	sacred_tree.position = local_position.call(world_centre.x, world_centre.y, 0.6)
	sacred_tree.scale = Vector3(3.0, 3.6, 3.0)
	lib.add(group, sacred_tree, "神木")
	var tree_body := StaticBody3D.new()
	sacred_tree.add_child(tree_body)
	tree_body.owner = root
	var tree_shape := CollisionShape3D.new()
	var tree_cylinder := CylinderShape3D.new()
	tree_cylinder.radius = 1.6 / 3.0
	tree_cylinder.height = 8.0 / 3.6
	tree_shape.shape = tree_cylinder
	tree_shape.position = Vector3(0, 1.2 / 3.6, 0)
	tree_body.add_child(tree_shape)
	tree_shape.owner = root
	var rope_material: StandardMaterial3D = lib.pbr(
		"shimenawa", "terrain_grass", 1.6, Color(0.88, 0.84, 0.66))
	var segment_count := 20
	for i in segment_count:
		var middle := (float(i) + 0.5) / float(segment_count) * TAU
		var radius := 1.75
		var link: MeshInstance3D = lib.cyl(group, "注連縄_%d" % i, 0.17, 0.17,
			radius * TAU / float(segment_count) * 1.12, rope_material,
			local_position.call(
				world_centre.x + cos(middle) * radius,
				world_centre.y + sin(middle) * radius, 3.1), 6)
		link.rotation.y = -middle
		link.rotation.z = PI * 0.5
	for i in 6:
		var angle := float(i) / 6.0 * TAU + 0.25
		lib.box(group, "紙垂_%d" % i, Vector3(0.16, 0.5, 0.03),
			lib.flat_mat("shide", Color(0.96, 0.96, 0.94), 0.9),
			local_position.call(
				world_centre.x + cos(angle) * 1.78,
				world_centre.y + sin(angle) * 1.78, 2.72))
	for i in 16:
		var post_angle := float(i) / 16.0 * TAU
		lib.box(group, "玉垣柱_%d" % i, Vector3(0.22, 1.05, 0.22),
			post_material, local_position.call(
				world_centre.x + cos(post_angle) * 5.4,
				world_centre.y + sin(post_angle) * 5.4, 0.5))
		var rail_angle := (float(i) + 0.5) / 16.0 * TAU
		var rail: MeshInstance3D = lib.box(group, "玉垣貫_%d" % i,
			Vector3(2.15, 0.13, 0.10), post_material,
			local_position.call(
				world_centre.x + cos(rail_angle) * 5.4,
				world_centre.y + sin(rail_angle) * 5.4, 0.78))
		rail.rotation.y = -rail_angle
	for side in [-1.0, 1.0]:
		var lamp_x: float = world_centre.x + 6.6
		var lamp_z: float = world_centre.y + side * 2.6
		var tag := int(side + 1)
		lib.cyl(group, "獻燈基_%d" % tag, 0.34, 0.40, 0.22,
			post_material, local_position.call(lamp_x, lamp_z, 0.11), 8)
		lib.cyl(group, "獻燈竿_%d" % tag, 0.13, 0.15, 1.15,
			post_material, local_position.call(lamp_x, lamp_z, 0.8), 8)
		lib.cyl(group, "獻燈袋_%d" % tag, 0.30, 0.28, 0.42,
			post_material, local_position.call(lamp_x, lamp_z, 1.58), 6)
		lib.cyl(group, "獻燈笠_%d" % tag, 0.08, 0.56, 0.26,
			post_material, local_position.call(lamp_x, lamp_z, 1.92), 6)
	var trees := [
		"res://assets/models/tree_round_a.glb",
		"res://assets/models/tree_round_c.glb",
		"res://assets/models/tree_pine_a.glb",
	]
	for i in 14:
		var world_angle := rng.randf_range(0.0, TAU)
		var radius_factor := sqrt(rng.randf_range(0.30, 1.0))
		var wx: float = world_centre.x + cos(world_angle) * (7.0 + radius_factor * 10.0)
		var wz: float = world_centre.y + sin(world_angle) * (7.0 + radius_factor * 7.5)
		if float(road_dist_fn.call(wx, wz)) < 1.6:
			continue
		var tree := MeshInstance3D.new()
		tree.mesh = tree_mesh_fn.call(trees[rng.randi() % trees.size()])
		tree.position = local_position.call(wx, wz, 0.0)
		tree.scale = Vector3.ONE * rng.randf_range(1.05, 1.5)
		tree.rotation.y = rng.randf_range(0.0, TAU)
		lib.add(group, tree, "杜木_%d" % i)
