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

const CANAL_TRENCH_PROBES: Array[Vector2] = [
	Vector2(287.0, -40.0),
	Vector2(287.0, 16.0),
	Vector2(287.0, 72.0),
]
const CANAL_TERRAIN_MAX_Y := -3.0


func _init() -> void:
	var ps: PackedScene = load("res://maps/slice/slice.tscn")
	var root: Node = ps.instantiate()
	if not _audit_canal_trench(root):
		root.free()
		ps = null
		quit(1)
		return
	if not _audit_paddy_support(root):
		root.free()
		ps = null
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--canal-only"):
		root.free()
		ps = null
		quit()
		return
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


func _audit_canal_trench(root: Node) -> bool:
	var ground: MeshInstance3D = root.get_node_or_null("UnifiedGround") as MeshInstance3D
	if ground == null:
		push_error("CANAL_TRENCH: UnifiedGround missing")
		return false
	var ok := true
	for probe in CANAL_TRENCH_PROBES:
		var top_y: float = _mesh_top_y_at(ground, probe)
		print("CANAL_TRENCH probe=%s terrain_top=%.3f max=%.3f" % [
			str(probe), top_y, CANAL_TERRAIN_MAX_Y])
		if top_y > CANAL_TERRAIN_MAX_Y:
			push_error("CANAL_TRENCH blocked at %s: terrain %.3f is above %.3f" % [
				str(probe), top_y, CANAL_TERRAIN_MAX_Y])
			ok = false
	return ok


## 水田支撐面審計：每格水田中心下方，UnifiedGround 的地形頂必須低於
## 該格泥面底，否則地形會把田面埋掉。
## 注意：實例化但未加入 SceneTree 時，global_transform 是 IDENTITY——
## 必須手動累加 transform 鏈（本檔 _mesh_top_y_at 曾犯過同一個錯）。
func _audit_paddy_support(root: Node) -> bool:
	var ground: MeshInstance3D = root.get_node_or_null("UnifiedGround") as MeshInstance3D
	var paddy: Node = root.get_node_or_null("MachiCanal/PaddyFields/PaddyWater")
	if ground == null or paddy == null:
		push_error("PADDY_SUPPORT: UnifiedGround or PaddyWater missing")
		return false
	var ok := true
	var mesh_arrays: Array = ground.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
	for child in paddy.get_children():
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var ab: AABB = _world_xform(mi) * mi.get_aabb()
		var probe: Vector2 = Vector2(ab.position.x + ab.size.x * 0.5, ab.position.z + ab.size.z * 0.5)
		var paddy_bottom: float = ab.position.y
		var terrain_top: float = -INF
		for v in verts:
			var d: float = Vector2(v.x - probe.x, v.z - probe.y).length_squared()
			if d < 9.0 and v.y > terrain_top:  # 3m 半徑內取最高點
				terrain_top = v.y
		if terrain_top == -INF:
			push_warning("PADDY_SUPPORT %s: no terrain sample near %s" % [child.name, str(probe)])
			continue
		var clearance: float = paddy_bottom - terrain_top
		if clearance < 0.0:
			push_error("PADDY_SUPPORT buried %s probe=(%.1f,%.1f): terrain %.3f above paddy bottom %.3f (%.3f m)" % [
				child.name, probe.x, probe.y, terrain_top, paddy_bottom, -clearance])
			ok = false
		else:
			print("PADDY_SUPPORT %s probe=(%.1f,%.1f) terrain=%.3f paddy_bottom=%.3f clearance=%.3f" % [
				child.name, probe.x, probe.y, terrain_top, paddy_bottom, clearance])
	return ok


func _world_xform(n: Node3D) -> Transform3D:
	var t: Transform3D = n.transform
	var cur: Node = n.get_parent()
	while cur != null:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _mesh_top_y_at(mi: MeshInstance3D, world_xz: Vector2) -> float:
	var mesh: ArrayMesh = mi.mesh as ArrayMesh
	if mesh == null:
		return INF
	# The audit instantiates the scene without adding it to SceneTree, so use
	# the node's local transform. UnifiedGround is a direct child of slice.
	var local_probe: Vector3 = mi.transform.affine_inverse() * Vector3(world_xz.x, 0.0, world_xz.y)
	var top_y := -INF
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var raw_indices = arrays[Mesh.ARRAY_INDEX]
		var indices: PackedInt32Array = raw_indices if raw_indices != null else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for face in range(0, count, 3):
			var a: Vector3 = vertices[indices[face]] if not indices.is_empty() else vertices[face]
			var b: Vector3 = vertices[indices[face + 1]] if not indices.is_empty() else vertices[face + 1]
			var c: Vector3 = vertices[indices[face + 2]] if not indices.is_empty() else vertices[face + 2]
			var local_y: float = _tri_y_at(a, b, c, Vector2(local_probe.x, local_probe.z))
			if local_y > -1e8:
				var world_y: float = (mi.transform * Vector3(local_probe.x, local_y, local_probe.z)).y
				top_y = maxf(top_y, world_y)
	return top_y


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
