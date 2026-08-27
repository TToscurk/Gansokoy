extends SceneTree
## Unified outer terrain + east main river (vista-basin-plan R1).
## ONE heightfield carries: basin hill ring, the east river valley carved
## as a trapezoid (water 16m, revetment-height 4-6m per 水護岸概念圖),
## north inlet through the valley gap, south fade-out (bed rises, narrows
## to a creek). Replaces GroundUnderlay/VillageLandExtension/tails/
## BasinHills and the old ring river. Village Terrain plate stays; a
## 15m blend band matches its edge height.
## Outputs: gen/slice_unified_ground.res, gen/east_river_water.res,
##          gen/east_river_wall_hint.res (R2 replaces with real ishigaki)
## Run: godot --headless --path godot --script tools/gen_terrain_river.gd

const CELL := 6.0
const R_EXT := 1250.0
const SEED := 20260827
const VILLAGE_R := 300.0      # Terrain plate half-size (600x600 centred)
# river centreline: north inlet -> east side -> south exit
const RIV_N_Z := -430.0
const RIV_S_Z := 560.0
const FADE_LEN := 190.0
const WATER_HALF := 8.0       # water width 16m
const TOP_HALF := 15.0        # valley top width ~30m
const DEPTH := 5.2            # bank top to bed
const WATER_DROP := 4.6       # bank top to water surface
# dragon-statue pool: river widens, statue platform stays uncarved
const STATUE := Vector2(485.0, 50.0)
const STATUE_R := 36.0
const POOL_Z0 := 0.0
const POOL_Z1 := 100.0

var _n := FastNoiseLite.new()

func _river_x(z: float) -> float:
	# gentle natural meander down the east side
	return 430.0 + 55.0 * sin(z * 0.006 + 1.3) + 30.0 * sin(z * 0.0023 - 0.7) \
		+ _n.get_noise_1d(z * 0.8) * 18.0

func _fade(z: float) -> float:
	# 0 = full river, 1 = fully faded (south end)
	return smoothstep(RIV_S_Z - FADE_LEN, RIV_S_Z, z)

func _hills(x: float, z: float, r: float, theta_deg: float) -> float:
	var wx: float = x + _n.get_noise_2d(x * 0.5, z * 0.5 + 999.0) * 220.0
	var wz: float = z + _n.get_noise_2d(x * 0.5 - 777.0, z * 0.5) * 220.0
	var ridge: float = 1.0 - abs(_n.get_noise_2d(wx * 1.1, wz * 1.1))
	var fill: float = _n.get_noise_2d(wx * 2.3 + 500.0, wz * 2.3) * 0.5 + 0.5
	var shape: float = pow(clampf(0.55 * ridge * ridge + 0.45 * fill, 0.0, 1.0), 1.15)
	var env: float = smoothstep(470.0, 640.0, r) * (1.0 - smoothstep(1120.0, 1250.0, r))
	var amp: float = lerpf(34.0, 92.0, smoothstep(560.0, 1150.0, r))
	# north valley gap for the sky window + river inlet, south highest
	var gap: float = 0.06 + 0.94 * smoothstep(24.0, 55.0, theta_deg)
	var south: float = 1.0 + 0.22 * smoothstep(120.0, 170.0, theta_deg)
	return shape * amp * env * gap * south

func _init() -> void:
	_n.seed = SEED
	_n.noise_type = FastNoiseLite.TYPE_VALUE
	_n.fractal_octaves = 4
	_n.frequency = 1.0 / 300.0

	var n: int = int((R_EXT * 2.0) / CELL) + 1
	var x0: float = -R_EXT
	var hs := PackedFloat32Array(); hs.resize(n * n)
	var wat := PackedByteArray(); wat.resize(n * n)   # 1 = inside water span
	var cols := PackedColorArray(); cols.resize(n * n)
	var near_col := Color(0.42, 0.50, 0.30)
	var far_col := Color(0.52, 0.58, 0.54)
	var earth_col := Color(0.55, 0.47, 0.33)

	for iz in range(n):
		for ix in range(n):
			var x: float = x0 + ix * CELL
			var z: float = x0 + iz * CELL
			var i: int = iz * n + ix
			var r: float = Vector2(x, z).length()
			var theta: float = abs(rad_to_deg(atan2(x, -z)))
			# base ground: field level, gentle undulation
			var g: float = -0.25 + _n.get_noise_2d(x * 1.6 + 88.0, z * 1.6) * 0.9
			g += _hills(x, z, r, theta)
			# blend band onto the village plate edge (plate ~y 0.05)
			var pl: float = maxf(absf(x), absf(z))
			if pl < VILLAGE_R + 15.0:
				var t: float = smoothstep(VILLAGE_R - 5.0, VILLAGE_R + 15.0, pl)
				g = lerpf(0.05, g, t)
			# ---- carve the east river valley ----
			if z > RIV_N_Z - 60.0 and z < RIV_S_Z + 10.0:
				var f: float = _fade(z)
				var cx: float = _river_x(z)
				var d: float = absf(x - cx)
				var pool: float = smoothstep(POOL_Z0 - 30.0, POOL_Z0 + 20.0, z) * (1.0 - smoothstep(POOL_Z1 - 20.0, POOL_Z1 + 30.0, z))
				var wh: float = lerpf(WATER_HALF, 2.2, f) + 12.0 * pool
				var th: float = lerpf(TOP_HALF, 5.0, f) + 14.0 * pool
				var dep: float = lerpf(DEPTH, 1.1, f)
				var sd: float = Vector2(x - STATUE.x, z - STATUE.y).length()
				var plat: float = 1.0 - smoothstep(STATUE_R - 10.0, STATUE_R + 6.0, sd)
				if d < th and plat < 0.999:
					var bank_top: float = g
					var carved: float
					if d <= wh:
						carved = bank_top - dep
					else:
						var s: float = (d - wh) / (th - wh)   # 0 bed wall .. 1 top
						carved = bank_top - dep + dep * smoothstep(0.0, 1.0, s)
					g = lerpf(carved, bank_top, plat)
					if d <= wh + 1.5 and f < 0.985:
						wat[i] = 1
			# statue platform: flatten to a level pad so the pedestal skirt sits in the soil
			var sd2: float = Vector2(x - STATUE.x, z - STATUE.y).length()
			var plat2: float = 1.0 - smoothstep(STATUE_R - 12.0, STATUE_R + 2.0, sd2)
			if plat2 > 0.0:
				g = lerpf(g, -0.55, plat2)
			hs[i] = g
			# vertex colour: aerial fade + earth tint low
			var fade_c: float = smoothstep(520.0, 1150.0, r)
			var c: Color = near_col.lerp(far_col, fade_c)
			if g < -1.2:
				c = earth_col            # valley walls read as earth/stone base
			cols[i] = c

	# ---- build ground mesh ----
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(n - 1):
		for ix in range(n - 1):
			var i00: int = iz * n + ix
			var i10: int = iz * n + ix + 1
			var i01: int = (iz + 1) * n + ix
			var i11: int = (iz + 1) * n + ix + 1
			var v00 := Vector3(x0 + ix * CELL, hs[i00], x0 + iz * CELL)
			var v10 := Vector3(x0 + (ix + 1) * CELL, hs[i10], x0 + iz * CELL)
			var v01 := Vector3(x0 + ix * CELL, hs[i01], x0 + (iz + 1) * CELL)
			var v11 := Vector3(x0 + (ix + 1) * CELL, hs[i11], x0 + (iz + 1) * CELL)
			st.set_color(cols[i00]); st.add_vertex(v00)
			st.set_color(cols[i10]); st.add_vertex(v10)
			st.set_color(cols[i01]); st.add_vertex(v01)
			st.set_color(cols[i10]); st.add_vertex(v10)
			st.set_color(cols[i11]); st.add_vertex(v11)
			st.set_color(cols[i01]); st.add_vertex(v01)
	st.generate_normals()
	var ground: ArrayMesh = st.commit()
	var a0: Array = ground.surface_get_arrays(0)
	if (a0[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0].y < 0.0:
		push_error("winding flipped — fix generator")
	DirAccess.make_dir_recursive_absolute("res://maps/slice/gen")
	var e1: int = ResourceSaver.save(ground, "res://maps/slice/gen/slice_unified_ground.res")

	# ---- water ribbon along the centreline ----
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps: int = int((RIV_S_Z - RIV_N_Z) / 4.0)
	for k in range(steps):
		var z0f: float = RIV_N_Z + (RIV_S_Z - RIV_N_Z) * float(k) / float(steps)
		var z1f: float = RIV_N_Z + (RIV_S_Z - RIV_N_Z) * float(k + 1) / float(steps)
		var f0: float = _fade(z0f)
		var f1: float = _fade(z1f)
		if f0 >= 0.985:
			continue
		var c0: float = _river_x(z0f)
		var c1: float = _river_x(z1f)
		var h0: float = lerpf(WATER_HALF, 2.2, f0) + 0.4
		var h1: float = lerpf(WATER_HALF, 2.2, f1) + 0.4
		var y0: float = -WATER_DROP + lerpf(0.0, 3.4, f0)
		var y1: float = -WATER_DROP + lerpf(0.0, 3.4, f1)
		# 4-vertex cross-section: edges carry vertex-colour R=1 (foam band),
		# centre R=0 (deep water) — the water shader reads COLOR.r as "bank".
		var fe0: float = minf(2.2, h0 * 0.35)
		var fe1: float = minf(2.2, h1 * 0.35)
		var row0: Array = [
			[Vector3(c0 - h0, y0, z0f), 1.0], [Vector3(c0 - h0 + fe0, y0, z0f), 0.0],
			[Vector3(c0 + h0 - fe0, y0, z0f), 0.0], [Vector3(c0 + h0, y0, z0f), 1.0]]
		var row1: Array = [
			[Vector3(c1 - h1, y1, z1f), 1.0], [Vector3(c1 - h1 + fe1, y1, z1f), 0.0],
			[Vector3(c1 + h1 - fe1, y1, z1f), 0.0], [Vector3(c1 + h1, y1, z1f), 1.0]]
		for q in range(3):
			var a0v: Array = row0[q]
			var a1v: Array = row0[q + 1]
			var b0v: Array = row1[q]
			var b1v: Array = row1[q + 1]
			wst.set_color(Color(a0v[1], 0, 0)); wst.add_vertex(a0v[0])
			wst.set_color(Color(a1v[1], 0, 0)); wst.add_vertex(a1v[0])
			wst.set_color(Color(b0v[1], 0, 0)); wst.add_vertex(b0v[0])
			wst.set_color(Color(a1v[1], 0, 0)); wst.add_vertex(a1v[0])
			wst.set_color(Color(b1v[1], 0, 0)); wst.add_vertex(b1v[0])
			wst.set_color(Color(b0v[1], 0, 0)); wst.add_vertex(b0v[0])
	wst.generate_normals()
	var water: ArrayMesh = wst.commit()
	var wa: Array = water.surface_get_arrays(0)
	if (wa[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0].y < 0.0:
		# rebuild flipped
		var w2 := SurfaceTool.new()
		w2.begin(Mesh.PRIMITIVE_TRIANGLES)
		var vs: PackedVector3Array = wa[Mesh.ARRAY_VERTEX]
		for t in range(0, vs.size(), 3):
			w2.add_vertex(vs[t]); w2.add_vertex(vs[t + 2]); w2.add_vertex(vs[t + 1])
		w2.generate_normals()
		water = w2.commit()
	var e2: int = ResourceSaver.save(water, "res://maps/slice/gen/east_river_water.res")
	print("ground err=", e1, " water err=", e2, " grid=", n, "x", n)
	quit()
