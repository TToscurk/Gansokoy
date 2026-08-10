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
