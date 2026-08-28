extends SceneTree
## Unified Human Village ground, basin hills, and east main river (B scale).
## One continuous heightfield owns the village floor and surrounding hills.
## The river remains broad through both map boundaries so water, revetment,
## and terrain cannot terminate at different places inside the visible world.
## Outputs: unified ground, river water, and a river-aligned revetment cap.
## The ground remains continuous beneath the cap, so a missing/hidden cap can
## never expose a terrain hole; the cap provides the density an engineered
## wall needs without forcing the full 2.5 km terrain to a wasteful 3 m grid.
## Run: godot --headless --path godot --script tools/gen_terrain_river.gd

const CELL := 6.0
const R_EXT := 1250.0
const SEED := 20260827
const VILLAGE_HALF := 300.0
const VILLAGE_BLEND_END := 440.0

# B scale selected by the user: about 44 m water, 68 m valley top, 6 m drop.
const WATER_HALF := 22.0
const TOP_HALF := 34.0
const DEPTH := 6.0
const WATER_Y := -5.15
const BED_Y := WATER_Y - 0.95
const REVETMENT_RUN := 5.5
const RIVER_Z0 := -R_EXT + CELL
const RIVER_Z1 := R_EXT - CELL

var _n := FastNoiseLite.new()


func _river_x(z: float) -> float:
	# Broad, slow meander down the east side. The landmark does not affect it.
	return 430.0 + 55.0 * sin(z * 0.006 + 1.3) + 30.0 * sin(z * 0.0023 - 0.7) \
		+ _n.get_noise_1d(z * 0.8) * 18.0


func _wvar(z: float) -> float:
	# Large river with restrained organic variation; never tapers to a creek.
	return 1.0 + 0.08 * sin(z * 0.0042 + 0.9) + 0.05 * sin(z * 0.0117 - 1.7) \
		+ _n.get_noise_1d(z * 0.35 + 400.0) * 0.06


func _widths(z: float) -> Vector2:
	var water_half: float = WATER_HALF * _wvar(z)
	return Vector2(water_half, water_half + (TOP_HALF - WATER_HALF))


func _hills(x: float, z: float, r: float, theta_deg: float) -> float:
	var wx: float = x + _n.get_noise_2d(x * 0.5, z * 0.5 + 999.0) * 220.0
	var wz: float = z + _n.get_noise_2d(x * 0.5 - 777.0, z * 0.5) * 220.0
	var ridge: float = 1.0 - abs(_n.get_noise_2d(wx * 1.1, wz * 1.1))
	var fill: float = _n.get_noise_2d(wx * 2.3 + 500.0, wz * 2.3) * 0.5 + 0.5
	var shape: float = pow(clampf(0.55 * ridge * ridge + 0.45 * fill, 0.0, 1.0), 1.15)
	var env: float = smoothstep(470.0, 640.0, r) * (1.0 - smoothstep(1120.0, 1250.0, r))
	var amp: float = lerpf(34.0, 92.0, smoothstep(560.0, 1150.0, r))
	var gap: float = 0.06 + 0.94 * smoothstep(24.0, 55.0, theta_deg)
	var south: float = 1.0 + 0.22 * smoothstep(120.0, 170.0, theta_deg)
	return shape * amp * env * gap * south


func _add_tri(
		tool: SurfaceTool,
		a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	tool.set_color(ca); tool.add_vertex(a)
	tool.set_color(cb); tool.add_vertex(b)
	tool.set_color(cc); tool.add_vertex(c)


func _grid_height(hs: PackedFloat32Array, n: int, x: float, z: float) -> float:
	var fx: float = clampf((x + R_EXT) / CELL, 0.0, float(n - 1))
	var fz: float = clampf((z + R_EXT) / CELL, 0.0, float(n - 1))
	var ix: int = mini(floori(fx), n - 2)
	var iz: int = mini(floori(fz), n - 2)
	var tx: float = fx - ix
	var tz: float = fz - iz
	var h0: float = lerpf(hs[iz * n + ix], hs[iz * n + ix + 1], tx)
	var h1: float = lerpf(hs[(iz + 1) * n + ix], hs[(iz + 1) * n + ix + 1], tx)
	return lerpf(h0, h1, tz)


func _init() -> void:
	_n.seed = SEED
	_n.noise_type = FastNoiseLite.TYPE_VALUE
	_n.fractal_octaves = 4
	_n.frequency = 1.0 / 300.0

	var n: int = int((R_EXT * 2.0) / CELL) + 1
	var x0: float = -R_EXT
	var hs := PackedFloat32Array(); hs.resize(n * n)
	var cols := PackedColorArray(); cols.resize(n * n)

	for iz in range(n):
		for ix in range(n):
			var x: float = x0 + ix * CELL
			var z: float = x0 + iz * CELL
			var i: int = iz * n + ix
			var r: float = Vector2(x, z).length()
			var pl: float = maxf(absf(x), absf(z))
			var theta: float = abs(rad_to_deg(atan2(x, -z)))

			var village_blend: float = smoothstep(VILLAGE_HALF - 24.0, VILLAGE_BLEND_END, pl)
			var natural_ground: float = -0.12 + _n.get_noise_2d(x * 1.6 + 88.0, z * 1.6) * 0.55
			var g: float = lerpf(0.0, natural_ground, village_blend)

			# Open a low valley before adding hills; hills never occupy the river corridor.
			var widths: Vector2 = _widths(z)
			var d: float = absf(x - _river_x(z))
			var valley_clear: float = smoothstep(widths.y + 48.0, widths.y + 155.0, d)
			g += _hills(x, z, r, theta) * valley_clear

			# A continuous, conservative under-slope seals the terrain below the
			# river-aligned revetment cap generated later.
			var revetment_top: float = widths.x + REVETMENT_RUN
			if d < widths.y:
				var bank_top: float = g
				if d <= widths.x:
					g = BED_Y
				else:
					var bank_t: float = (d - widths.x) / (widths.y - widths.x)
					g = lerpf(BED_Y, bank_top, smoothstep(0.0, 1.0, bank_t))
			hs[i] = g

			# Ground uses COLOR.r for dirt/grass and COLOR.g for aerial fade.
			var grass_weight: float = smoothstep(270.0, 455.0, pl)
			if g < WATER_Y - 0.2:
				grass_weight = 0.0
			# A packed ochre maintenance path sits behind the wall, like the
			# reference's continuous top access band.
			if d >= revetment_top - 0.35 and d < widths.y:
				grass_weight = 0.0
			var aerial_fade: float = smoothstep(520.0, 1150.0, r)
			cols[i] = Color(grass_weight, aerial_fade, 0.0, 0.0)

	# One continuous ground mesh seals village, hills, and the river bed.
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
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

			_add_tri(gst, v00, v10, v01, cols[i00], cols[i10], cols[i01])
			_add_tri(gst, v10, v11, v01, cols[i10], cols[i11], cols[i01])

	gst.generate_normals()
	var ground: ArrayMesh = gst.commit()
	var ground_arrays: Array = ground.surface_get_arrays(0)
	if (ground_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0].y < 0.0:
		push_error("ground winding flipped - fix generator")

	DirAccess.make_dir_recursive_absolute("res://maps/slice/gen")
	var e1: int = ResourceSaver.save(ground, "res://maps/slice/gen/slice_unified_ground.res")

	# Dense river-aligned strips create a clean wall silhouette on bends.  Each
	# side is one continuous cross-section: submerged toe, wet waterline, dry
	# stone face, coping transition, then the packed-earth crest.  It overlaps
	# the sealed ground beneath and meets untouched terrain beyond the crest.
	var river_steps: int = int((RIVER_Z1 - RIVER_Z0) / 4.0)
	var rst := SurfaceTool.new()
	rst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(river_steps):
		var z0r: float = lerpf(RIVER_Z0, RIVER_Z1, float(k) / float(river_steps))
		var z1r: float = lerpf(RIVER_Z0, RIVER_Z1, float(k + 1) / float(river_steps))
		for side in [-1.0, 1.0]:
			var rows: Array = []
			for zr in [z0r, z1r]:
				var center_x: float = _river_x(zr)
				var widths_r: Vector2 = _widths(zr)
				var outer_x: float = center_x + side * (widths_r.y + 0.8)
				var bank_y: float = _grid_height(hs, n, outer_x, zr) + 0.08
				rows.append([
					[Vector3(center_x + side * (widths_r.x - 0.75), BED_Y + 0.12, zr), Color(0, 0, 1, 1)],
					[Vector3(center_x + side * (widths_r.x + 0.30), WATER_Y + 0.06, zr), Color(0, 0, 1, 1)],
					[Vector3(center_x + side * (widths_r.x + REVETMENT_RUN), bank_y, zr), Color(0, 0, 1, 0)],
					[Vector3(center_x + side * (widths_r.x + REVETMENT_RUN + 0.65), bank_y, zr), Color(0, 0, 0, 0)],
					[Vector3(outer_x, bank_y, zr), Color(0, 0, 0, 0)]])
			var row0r: Array = rows[0]
			var row1r: Array = rows[1]
			for q in range(row0r.size() - 1):
				var a0: Array = row0r[q]
				var a1: Array = row0r[q + 1]
				var b0: Array = row1r[q]
				var b1: Array = row1r[q + 1]
				if side < 0.0:
					_add_tri(rst, a0[0], b0[0], a1[0], a0[1], b0[1], a1[1])
					_add_tri(rst, a1[0], b0[0], b1[0], a1[1], b0[1], b1[1])
				else:
					_add_tri(rst, a0[0], a1[0], b0[0], a0[1], a1[1], b0[1])
					_add_tri(rst, a1[0], b1[0], b0[0], a1[1], b1[1], b0[1])
	rst.generate_normals()
	var revetment: ArrayMesh = rst.commit()
	var e3: int = ResourceSaver.save(revetment, "res://maps/slice/gen/east_river_revetment.res")

	# Water shares the carved bed's centreline and width, and reaches both map edges.
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(river_steps):
		var z0f: float = lerpf(RIVER_Z0, RIVER_Z1, float(k) / float(river_steps))
		var z1f: float = lerpf(RIVER_Z0, RIVER_Z1, float(k + 1) / float(river_steps))
		var c0x: float = _river_x(z0f)
		var c1x: float = _river_x(z1f)
		var h0: float = _widths(z0f).x + 0.45
		var h1: float = _widths(z1f).x + 0.45
		var fe0: float = minf(2.6, h0 * 0.22)
		var fe1: float = minf(2.6, h1 * 0.22)
		var row0: Array = [
			[Vector3(c0x - h0, WATER_Y, z0f), 1.0],
			[Vector3(c0x - h0 + fe0, WATER_Y, z0f), 0.0],
			[Vector3(c0x + h0 - fe0, WATER_Y, z0f), 0.0],
			[Vector3(c0x + h0, WATER_Y, z0f), 1.0]]
		var row1: Array = [
			[Vector3(c1x - h1, WATER_Y, z1f), 1.0],
			[Vector3(c1x - h1 + fe1, WATER_Y, z1f), 0.0],
			[Vector3(c1x + h1 - fe1, WATER_Y, z1f), 0.0],
			[Vector3(c1x + h1, WATER_Y, z1f), 1.0]]
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
	var water_arrays: Array = water.surface_get_arrays(0)
	if (water_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0].y < 0.0:
		push_error("water winding flipped - fix generator")
	var e2: int = ResourceSaver.save(water, "res://maps/slice/gen/east_river_water.res")

	print("ground err=", e1, " water err=", e2, " revetment err=", e3,
		" grid=", n, "x", n, " water_width~=", WATER_HALF * 2.0,
		" valley_top_width~=", TOP_HALF * 2.0, " depth=", DEPTH,
		" revetment_run=", REVETMENT_RUN,
		" nominal_face_angle_deg=", rad_to_deg(atan2(-BED_Y, REVETMENT_RUN)))
	quit()
