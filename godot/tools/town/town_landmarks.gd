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
