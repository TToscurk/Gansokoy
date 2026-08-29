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
# 主街走廊參數（與 tools/gen_b1_street.gd 對齊）
const STREET_AXIS_X := 235.0
const STREET_MID_Z := 16.0
const STREET_HALF_LEN := 76.0
# B2 小河（用水路）樣板段：村核與農田之間的直渠（2026-08-29，使用者批准）
const CANAL_X := 340.0
const CANAL_MID := 0.0
const CANAL_HALF_LEN := 46.0
const CANAL_BED_Y := -2.45
const CANAL_BED_HALF := 2.75
const CANAL_TOP_HALF := 3.7

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



## 村內地被分區（2026-08-29，使用者選定「用地面材質分區」取代撒草）。
## 依據概念圖：草地是預設，踏み固めた土是例外——主街走廊與建物群周邊被踩實。
## 注意頂點間距 = CELL(6m)，雜訊尺度必須夠大才畫得出來。
func _village_cover(x: float, z: float) -> float:
	# 主街走廊：夯土，不長草
	var street_d: float = absf(x - STREET_AXIS_X)
	var along: float = 1.0 - smoothstep(STREET_HALF_LEN * 0.90, STREET_HALF_LEN * 1.35,
		absf(z - STREET_MID_Z))
	var street_pack: float = (1.0 - smoothstep(13.0, 30.0, street_d)) * along
	# 建物群周邊踩實，範圍收斂在村心 ~90m 內
	var core: float = 1.0 - smoothstep(16.0, 58.0, Vector2(x - 250.0, z - 10.0).length())
	# 有機斑塊，讓草地邊界不是同心圓
	var patch: float = _n.get_noise_2d(x * 0.55 + 300.0, z * 0.55 - 120.0) * 0.5 + 0.5
	var cover: float = smoothstep(0.28, 0.62, patch)
	var base: float = lerpf(0.55, 1.0, cover)   # 底線 0.55，開闊地不會整片光禿
	return clampf(base * (1.0 - street_pack) * (1.0 - 0.55 * core), 0.0, 1.0)


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
			# B2 小河：淺槽直渠，兩端漸收回地表；牆體與水面由 b2_canal 場景供給
			var canal_d: float = absf(x - CANAL_X)
			var canal_z: float = absf(z - CANAL_MID)
			if canal_d < CANAL_TOP_HALF and canal_z < CANAL_HALF_LEN + 10.0:
				var canal_end: float = 1.0 - smoothstep(CANAL_HALF_LEN - 8.0, CANAL_HALF_LEN + 10.0, canal_z)
				var canal_prof: float = 1.0 - smoothstep(CANAL_BED_HALF, CANAL_TOP_HALF, canal_d)
				var canal_cut: float = (g - CANAL_BED_Y) * canal_prof * canal_end
				if canal_cut > 0.0:
					g -= canal_cut
			hs[i] = g

			# Ground uses COLOR.r for dirt/grass and COLOR.g for aerial fade.
			var grass_weight: float = maxf(smoothstep(270.0, 455.0, pl), _village_cover(x, z))
			if g < WATER_Y - 0.2:
				grass_weight = 0.0
			# A packed ochre maintenance path sits behind the wall, like the
			# reference's continuous top access band.
			if d >= revetment_top - 0.35 and d < widths.y:
				grass_weight = 0.0
			var aerial_fade: float = smoothstep(520.0, 1150.0, r)
			# Submerged bed reads as wet stone, not bright ochre dirt — the
			# semi-transparent shallow band otherwise glows with the dirt
			# texture underneath and that IS the bright waterline stripe.
			var bed_stone: float = 1.0 - smoothstep(WATER_Y - 0.05, WATER_Y + 0.55, g)
			if canal_z < CANAL_HALF_LEN + 10.0:
				grass_weight *= smoothstep(CANAL_TOP_HALF - 1.0, CANAL_TOP_HALF + 3.0, canal_d)
				if canal_d < CANAL_TOP_HALF and g < -0.7:
					bed_stone = maxf(bed_stone, 1.0 - smoothstep(-1.6, -0.7, g) * 0.4)
			cols[i] = Color(grass_weight, aerial_fade, bed_stone, bed_stone)

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
	var e1: int = ResourceSaver.save(ground, "res://maps/slice/gen/slice_unified_ground.res", ResourceSaver.FLAG_COMPRESS)

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
				# Coping course: the face stops short of the crest and a stone
				# lip rises ~0.22 m proud of the path before dropping back, per
				# the 護岸強化 reference — the silhouette break is what stops
				# the wall reading as a texture projected on a ramp.
				rows.append([
					[Vector3(center_x + side * (widths_r.x - 0.75), BED_Y + 0.12, zr), Color(0, 0, 1, 1)],
					[Vector3(center_x + side * (widths_r.x + 0.30), WATER_Y + 0.06, zr), Color(0, 0, 1, 1)],
					[Vector3(center_x + side * (widths_r.x + REVETMENT_RUN - 0.45), bank_y - 0.06, zr), Color(0, 0, 1, 0)],
					[Vector3(center_x + side * (widths_r.x + REVETMENT_RUN + 0.05), bank_y + 0.22, zr), Color(0, 0, 1, 0)],
					[Vector3(center_x + side * (widths_r.x + REVETMENT_RUN + 0.50), bank_y + 0.22, zr), Color(0, 0, 1, 0)],
					[Vector3(center_x + side * (widths_r.x + REVETMENT_RUN + 0.72), bank_y, zr), Color(0, 0, 1, 0)],
					[Vector3(center_x + side * (widths_r.x + REVETMENT_RUN + 1.05), bank_y, zr), Color(0, 0, 0, 0)],
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
	var e3: int = ResourceSaver.save(revetment, "res://maps/slice/gen/east_river_revetment.res", ResourceSaver.FLAG_COMPRESS)

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
		# COLOR.gb carries the local downstream direction (encoded 0..1) so the
		# water shader can scroll its normals along the meander instead of a
		# fixed world axis. Flow runs north inlet -> south exit (+z).
		var f0: Vector2 = Vector2((_river_x(z0f + 2.0) - _river_x(z0f - 2.0)) / 4.0, 1.0).normalized()
		var f1: Vector2 = Vector2((_river_x(z1f + 2.0) - _river_x(z1f - 2.0)) / 4.0, 1.0).normalized()
		for q in range(3):
			var a0v: Array = row0[q]
			var a1v: Array = row0[q + 1]
			var b0v: Array = row1[q]
			var b1v: Array = row1[q + 1]
			var c0 := Color(a0v[1], f0.x * 0.5 + 0.5, f0.y * 0.5 + 0.5)
			var c1 := Color(b0v[1], f1.x * 0.5 + 0.5, f1.y * 0.5 + 0.5)
			wst.set_color(c0); wst.add_vertex(a0v[0])
			wst.set_color(Color(a1v[1], c0.g, c0.b)); wst.add_vertex(a1v[0])
			wst.set_color(Color(b0v[1], c1.g, c1.b)); wst.add_vertex(b0v[0])
			wst.set_color(Color(a1v[1], c0.g, c0.b)); wst.add_vertex(a1v[0])
			wst.set_color(Color(b1v[1], c1.g, c1.b)); wst.add_vertex(b1v[0])
			wst.set_color(Color(b0v[1], c1.g, c1.b)); wst.add_vertex(b0v[0])
	wst.generate_normals()
	var water: ArrayMesh = wst.commit()
	var water_arrays: Array = water.surface_get_arrays(0)
	if (water_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0].y < 0.0:
		push_error("water winding flipped - fix generator")
	var e2: int = ResourceSaver.save(water, "res://maps/slice/gen/east_river_water.res", ResourceSaver.FLAG_COMPRESS)

	# Stone landing steps beside the bridge abutment (west bank, z=-130), per
	# the 護岸強化 reference's 階梯與水邊設施 panel: a solid stepped block from
	# the crest path down through the wall face into the water. Sits inside the
	# vegetation belt's bridge clearing, so no reeds intersect it.
	# z chosen clear of the Meshy bridge deck (its approach ramp reaches ~z=-128)
	# yet still inside the vegetation belt's bridge clearing (ends z=-111.9).
	var sz0: float = -116.5
	var sz1: float = -113.5
	var szc: float = (sz0 + sz1) * 0.5
	var scx: float = _river_x(szc)
	var sw: Vector2 = _widths(szc)
	var s_top_y: float = _grid_height(hs, n, scx - (sw.y + 0.8), szc) + 0.06
	var s_top_d: float = sw.x + REVETMENT_RUN + 0.9
	var riser: float = 0.30
	var tread: float = 0.42
	var n_steps: int = int(ceil((s_top_y - (WATER_Y - 0.75)) / riser))
	var sst := SurfaceTool.new()
	sst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c_dry := Color(0, 0, 1, 0)
	var base_y: float = WATER_Y - 1.4
	# profile from top of stairs to bottom (x increases toward the river)
	var prof: Array = []
	for i in range(n_steps + 1):
		var y_i: float = s_top_y - float(i) * riser
		var x_i: float = scx - (s_top_d - float(i) * tread)
		prof.append(Vector2(x_i, y_i))
	for i in range(n_steps):
		var pa: Vector2 = prof[i]
		var pb: Vector2 = prof[i + 1]
		var wet_a: float = 1.0 if pa.y < WATER_Y + 0.45 else 0.0
		var wet_b: float = 1.0 if pb.y < WATER_Y + 0.45 else 0.0
		var ca := Color(0, 0, 1, wet_a)
		var cb := Color(0, 0, 1, wet_b)
		# tread (horizontal, top face) at height pa.y from pa.x to pb.x
		var t00 := Vector3(pa.x, pa.y, sz0)
		var t01 := Vector3(pb.x, pa.y, sz0)
		var t10 := Vector3(pa.x, pa.y, sz1)
		var t11 := Vector3(pb.x, pa.y, sz1)
		_add_tri(sst, t00, t01, t10, ca, ca, ca)
		_add_tri(sst, t01, t11, t10, ca, ca, ca)
		# riser (vertical, faces the river +x)
		var r00 := Vector3(pb.x, pa.y, sz0)
		var r01 := Vector3(pb.x, pb.y, sz0)
		var r10 := Vector3(pb.x, pa.y, sz1)
		var r11 := Vector3(pb.x, pb.y, sz1)
		_add_tri(sst, r00, r10, r01, ca, ca, cb)
		_add_tri(sst, r01, r10, r11, cb, ca, cb)
	# side stringers: curtain from the step profile down to base_y on both sides
	for side_i in range(2):
		var zs: float = sz0 if side_i == 0 else sz1
		for i in range(prof.size() - 1):
			var pa2: Vector2 = prof[i]
			var pb2: Vector2 = prof[i + 1]
			var a_top := Vector3(pa2.x, pa2.y, zs)
			var b_top := Vector3(pb2.x, pb2.y, zs)
			var a_bot := Vector3(pa2.x, base_y, zs)
			var b_bot := Vector3(pb2.x, base_y, zs)
			# include the tread lip on the side: quad (pa top .. pb at pa.y)
			var lip := Vector3(pb2.x, pa2.y, zs)
			if side_i == 0:
				_add_tri(sst, a_top, lip, a_bot, c_dry, c_dry, c_dry)
				_add_tri(sst, lip, b_bot, a_bot, c_dry, c_dry, c_dry)
				_add_tri(sst, lip, b_top, b_bot, c_dry, c_dry, c_dry)
			else:
				_add_tri(sst, a_top, a_bot, lip, c_dry, c_dry, c_dry)
				_add_tri(sst, lip, a_bot, b_bot, c_dry, c_dry, c_dry)
				_add_tri(sst, lip, b_bot, b_top, c_dry, c_dry, c_dry)
	# front face of the lowest submerged step down to base
	var last: Vector2 = prof[prof.size() - 1]
	var f00 := Vector3(last.x, last.y, sz0)
	var f01 := Vector3(last.x, base_y, sz0)
	var f10 := Vector3(last.x, last.y, sz1)
	var f11 := Vector3(last.x, base_y, sz1)
	var c_wet := Color(0, 0, 1, 1)
	_add_tri(sst, f00, f10, f01, c_wet, c_wet, c_wet)
	_add_tri(sst, f01, f10, f11, c_wet, c_wet, c_wet)
	sst.generate_normals()
	var steps_mesh: ArrayMesh = sst.commit()
	var e4: int = ResourceSaver.save(steps_mesh, "res://maps/slice/gen/east_river_steps.res", ResourceSaver.FLAG_COMPRESS)
	print("steps err=", e4, " steps n=", n_steps, " top=(%.1f, %.2f, %.1f)" % [scx - s_top_d, s_top_y, szc])

	print("ground err=", e1, " water err=", e2, " revetment err=", e3,
		" grid=", n, "x", n, " water_width~=", WATER_HALF * 2.0,
		" valley_top_width~=", TOP_HALF * 2.0, " depth=", DEPTH,
		" revetment_run=", REVETMENT_RUN,
		" nominal_face_angle_deg=", rad_to_deg(atan2(-BED_Y, REVETMENT_RUN)))
	quit()
