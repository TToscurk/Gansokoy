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
