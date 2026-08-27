extends SceneTree
## Basin hill ring for maps/slice (vista redo step 1, see docs/vista-basin-plan.md).
## Annulus heightfield r 500..1250: flat tuck-in band, staggered smooth mounds
## in 650..950, asymmetric (north valley gap for the river exit, south highest),
## aerial-perspective baked as vertex colour. NO trees (user supplies via Meshy).
## River clearance enforced numerically against the actual RiverWater vertices.
## Output: res://maps/slice/gen/slice_basin_hills.res
## Run: godot --headless --path godot --script tools/gen_basin_hills.gd

const CELL := 12.0
const R_IN := 380.0
const R_OUT := 1250.0
const SEED := 20260826
const RIVER_CLEAR := 80.0      # inside this distance to water: zero hill
const RIVER_RAMP := 220.0      # full height beyond this distance
const GAP_HALF_IN := 28.0      # north valley gap inner half-angle (deg)
const GAP_HALF_OUT := 58.0

var water_bins: Dictionary = {}
const WBIN := 50.0

func _wkey(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / WBIN)), int(floor(z / WBIN)))

func _river_dist(x: float, z: float) -> float:
	var k := _wkey(x, z)
	var best: float = 1e9
	for bx in range(k.x - 5, k.x + 6):
		for bz in range(k.y - 5, k.y + 6):
			var key := Vector2i(bx, bz)
			if not water_bins.has(key):
				continue
			for v in (water_bins[key] as Array):
				var d: float = Vector2(x - (v as Vector2).x, z - (v as Vector2).y).length()
				best = min(best, d)
	return best

func _init() -> void:
	var ps: PackedScene = load("res://maps/slice/slice.tscn")
	var root: Node = ps.instantiate()
	var wm: MeshInstance3D = root.get_node("RiverV3_Candidate/RiverWater") as MeshInstance3D
	var warr: Array = (wm.mesh as ArrayMesh).surface_get_arrays(0)
	var wvs: PackedVector3Array = warr[Mesh.ARRAY_VERTEX]
	for v in wvs:
		var k := _wkey(v.x, v.z)
		if not water_bins.has(k):
			water_bins[k] = []
		(water_bins[k] as Array).append(Vector2(v.x, v.z))
	print("water verts: ", wvs.size())

	# deterministic mound field: 3 staggered rows
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var mounds: Array = []   # [cx, cz, radius, height]
	for row in range(3):
		var rr: float = [710.0, 800.0, 890.0][row]
		var count: int = 16
		for i in range(count):
			var ang: float = TAU * (float(i) + (0.5 if row % 2 == 1 else 0.0)) / float(count) \
				+ rng.randf_range(-0.06, 0.06)
			var rad: float = rr + rng.randf_range(-35.0, 35.0)
			var cx: float = sin(ang) * rad
			var cz: float = -cos(ang) * rad          # ang 0 = north (-z)
			var mr: float = rng.randf_range(75.0, 150.0)
			var mh: float = [rng.randf_range(16.0, 30.0), rng.randf_range(24.0, 42.0), rng.randf_range(34.0, 58.0)][row]
			mounds.append([cx, cz, mr, mh])
	print("mounds: ", mounds.size())

	var n: int = int((R_OUT * 2.0) / CELL) + 1
	var x0: float = -R_OUT
	var hs := PackedFloat32Array(); hs.resize(n * n)
	var mask := PackedByteArray(); mask.resize(n * n)
	var cut := PackedByteArray(); cut.resize(n * n)
	var cols := PackedColorArray(); cols.resize(n * n)
	var near_col := Color(0.40, 0.50, 0.30)
	var far_col := Color(0.52, 0.58, 0.52)
	var eaten: float = 0.0     # max hill height inside RIVER_CLEAR (must stay ~0)
	for iz in range(n):
		for ix in range(n):
			var x: float = x0 + ix * CELL
			var z: float = x0 + iz * CELL
			var r: float = Vector2(x, z).length()
			var i: int = iz * n + ix
			if r < R_IN:
				mask[i] = 0
				continue
			mask[i] = 1
			# tuck-in base: starts under the existing ground, rises to field level
			var base: float = lerpf(-1.6, -0.2, smoothstep(R_IN, 560.0, r))
			var window: float = smoothstep(615.0, 690.0, r) * (1.0 - smoothstep(910.0, 990.0, r))
			var m: float = 0.0
			for md in mounds:
				var d: float = Vector2(x - (md as Array)[0], z - (md as Array)[1]).length()
				var mr: float = (md as Array)[2]
				if d < mr:
					var t: float = cos(d / mr * PI * 0.5)
					m += (md as Array)[3] * t * t
			m = min(m, 62.0)
			# asymmetry: north gap + south boost
			var theta_deg: float = abs(rad_to_deg(atan2(x, -z)))   # 0 = north, 180 = south
			var gap: float = 0.05 + 0.95 * smoothstep(GAP_HALF_IN, GAP_HALF_OUT, theta_deg)
			var south: float = 1.0 + 0.30 * smoothstep(120.0, 170.0, theta_deg)
			# river clearance: sheet is CUT OUT over the channel itself,
			# and hills ramp in gently far from the water
			var rd: float = _river_dist(x, z)
			if rd < 8.0:
				cut[i] = 1
			var rf: float = smoothstep(RIVER_CLEAR, RIVER_RAMP, rd)
			var hill: float = m * window * gap * south * rf
			if rd < 26.0:
				# over the channel: dive below the river bed, hidden by the walls
				base = -9.8
			elif rd < 45.0:
				# climb back inside the revetment wall thickness
				base = lerpf(-9.8, -0.05, smoothstep(26.0, 40.0, rd))
			if rd < 60.0 and rd >= 45.0:
				base = lerpf(-0.05, base, smoothstep(45.0, 60.0, rd))
			if rd < RIVER_CLEAR:
				eaten = max(eaten, m * window * gap * south)  # what WOULD have been there
			hs[i] = base + hill
			var tcol: float = smoothstep(660.0, 990.0, r)
			cols[i] = near_col.lerp(far_col, tcol)
	print("river-adjacent suppressed hill max (m): %.2f (forced to 0 within %.0fm of water)" % [eaten, RIVER_CLEAR])

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(n - 1):
		for ix in range(n - 1):
			var i00: int = iz * n + ix
			var i10: int = iz * n + ix + 1
			var i01: int = (iz + 1) * n + ix
			var i11: int = (iz + 1) * n + ix + 1
			if mask[i00] == 0 or mask[i10] == 0 or mask[i01] == 0 or mask[i11] == 0:
				continue
			var va := Vector3(x0 + ix * CELL, hs[i00], x0 + iz * CELL)
			var vb := Vector3(x0 + (ix + 1) * CELL, hs[i10], x0 + iz * CELL)
			var vc := Vector3(x0 + ix * CELL, hs[i01], x0 + (iz + 1) * CELL)
			var vd := Vector3(x0 + (ix + 1) * CELL, hs[i11], x0 + (iz + 1) * CELL)
			st.set_color(cols[i00]); st.add_vertex(va)
			st.set_color(cols[i10]); st.add_vertex(vb)
			st.set_color(cols[i01]); st.add_vertex(vc)
			st.set_color(cols[i10]); st.add_vertex(vb)
			st.set_color(cols[i11]); st.add_vertex(vd)
			st.set_color(cols[i01]); st.add_vertex(vc)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var nrm: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	if nrm.size() > 0 and nrm[0].y < 0.0:
		print("ERROR: winding came out downward — aborting instead of shipping a broken sheet")
		quit()
		return
	var err: int = ResourceSaver.save(mesh, "res://maps/slice/gen/slice_basin_hills.res")
	print("saved err=", err, " tris=", mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3)
	quit()
