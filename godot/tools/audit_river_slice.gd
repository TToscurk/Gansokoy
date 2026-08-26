extends SceneTree
## One-shot audit of slice.tscn river geometry.
## Prints per-mesh stats and, for a set of probe XZ points (in the pale
## "white field" zones), which meshes cover that column and at what Y.
## Run: godot --headless --path godot --script tools/audit_river_slice.gd

const PROBES: Array = [
	Vector2(-150, 500),   # SW outside the channel (pale field, south bridge cam left)
	Vector2(-60, 430),    # inside village side near south bridge
	Vector2(120, 530),    # SE outside channel
	Vector2(-300, 260),   # west outside
	Vector2(60, 300),     # village platform interior
	Vector2(0, 476),      # mid-channel (should be water/bed)
	Vector2(220, -260),   # northeast detail-camera target
	Vector2(260, -300),
	Vector2(300, -340),
	Vector2(340, -380),
	Vector2(380, -420),
	Vector2(420, -460),
	Vector2(170, -310),   # unified northeast dry-land closure
	Vector2(290, -206),
	Vector2(573, -381),
	Vector2(303, -615),
	Vector2(80, -350),
	Vector2(330, -150),
]

func _init() -> void:
	var ps: PackedScene = load("res://maps/slice/slice.tscn")
	var root: Node = ps.instantiate()
	var targets: Array = []
	_collect(root, targets)

	for mi_any in targets:
		var mi: MeshInstance3D = mi_any
		var mesh: ArrayMesh = mi.mesh as ArrayMesh
		if mesh == null:
			print("%s: (no ArrayMesh: %s)" % [mi.name, str(mi.mesh)])
			continue
		var aabb: AABB = mesh.get_aabb()
		var total_v: int = 0
		var total_f: int = 0
		var all_y := PackedFloat32Array()
		for s in range(mesh.get_surface_count()):
			var arr: Array = mesh.surface_get_arrays(s)
			var surface_vertices: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			total_v += surface_vertices.size()
			for vertex in surface_vertices:
				all_y.append(vertex.y)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			total_f += (idx.size() / 3) if idx.size() > 0 else ((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
		print("%s: surfaces=%d verts=%d faces=%d aabb_pos=%s aabb_size=%s xform_origin=%s" % [
			mi.name, mesh.get_surface_count(), total_v, total_f,
			str(aabb.position), str(aabb.size), str(mi.transform.origin)])
		all_y.sort()
		if not all_y.is_empty():
			print("  y percentiles: min=%.2f p50=%.2f p90=%.2f p95=%.2f p99=%.2f max=%.2f >20m=%d" % [
				all_y[0], _percentile(all_y, 0.50), _percentile(all_y, 0.90),
				_percentile(all_y, 0.95), _percentile(all_y, 0.99), all_y[-1],
				_count_above(all_y, 20.0)])

		# probe coverage (skip absurdly big meshes per-face; note it)
		if total_f > 400000:
			print("  (skipped probe test: too many faces)")
			continue
		for p_i in range(PROBES.size()):
			var p: Vector2 = PROBES[p_i]
			var lp: Vector3 = Vector3(p.x, 0.0, p.y) - mi.transform.origin
			if not _aabb_covers_xz(aabb, lp):
				continue
			var hit_y: float = -1e9
			var hit: bool = false
			for s in range(mesh.get_surface_count()):
				var arr: Array = mesh.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				var n: int = idx.size() if idx.size() > 0 else vs.size()
				for f in range(0, n, 3):
					var a: Vector3
					var b: Vector3
					var c3: Vector3
					if idx.size() > 0:
						a = vs[idx[f]]; b = vs[idx[f + 1]]; c3 = vs[idx[f + 2]]
					else:
						a = vs[f]; b = vs[f + 1]; c3 = vs[f + 2]
					var y: float = _tri_y_at(a, b, c3, Vector2(lp.x, lp.z))
					if y > -1e8:
						hit = true
						hit_y = max(hit_y, y)
			if hit:
				print("  probe %d %s -> covered, top_y=%.2f" % [p_i, str(p), hit_y + mi.transform.origin.y])
	targets.clear()
	root.free()
	ps = null
	quit()

func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		var m: Mesh = mi.mesh
		if m != null:
			var ab: AABB = m.get_aabb()
			# only meshes big enough to be a "field" (>80m on a ground axis)
			if ab.size.x > 80.0 or ab.size.z > 80.0:
				out.append(mi)
	for c in n.get_children():
		_collect(c, out)

func _aabb_covers_xz(aabb: AABB, lp: Vector3) -> bool:
	return lp.x >= aabb.position.x and lp.x <= aabb.position.x + aabb.size.x \
		and lp.z >= aabb.position.z and lp.z <= aabb.position.z + aabb.size.z

func _tri_y_at(a: Vector3, b: Vector3, c: Vector3, p: Vector2) -> float:
	var p0 := Vector2(a.x, a.z)
	var p1 := Vector2(b.x, b.z)
	var p2 := Vector2(c.x, c.z)
	var d: float = (p1.y - p2.y) * (p0.x - p2.x) + (p2.x - p1.x) * (p0.y - p2.y)
	if abs(d) < 0.000001:
		return -1e9
	var w0: float = ((p1.y - p2.y) * (p.x - p2.x) + (p2.x - p1.x) * (p.y - p2.y)) / d
	var w1: float = ((p2.y - p0.y) * (p.x - p2.x) + (p0.x - p2.x) * (p.y - p2.y)) / d
	var w2: float = 1.0 - w0 - w1
	if w0 < -0.001 or w1 < -0.001 or w2 < -0.001:
		return -1e9
	return a.y * w0 + b.y * w1 + c.y * w2

func _percentile(values: PackedFloat32Array, ratio: float) -> float:
	var index: int = clampi(roundi(float(values.size() - 1) * ratio), 0, values.size() - 1)
	return values[index]

func _count_above(values: PackedFloat32Array, threshold: float) -> int:
	var count: int = 0
	for value in values:
		if value > threshold:
			count += 1
	return count
