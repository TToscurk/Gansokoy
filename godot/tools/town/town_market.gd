extends RefCounted


static func build_market(
		lib,
		group: Node3D,
		lm_rng: RandomNumberGenerator,
		ground_under: Callable,
		height_at: Callable,
		material_fn: Callable,
		collide: Callable,
		build_dragon: Callable) -> void:
	var content: Node3D = lib.add(group, Node3D.new(), "本體")
	content.position = Vector3(1.25, 0.0, 3.95)
	# Readability correction for the roofed pilot only.  This deliberately does
	# not cast shadows or alter the world environment; it merely keeps stall
	# work surfaces from collapsing to black under overlapping canopies.
	var market_fill := OmniLight3D.new()
	market_fill.light_color = Color(1.0, 0.88, 0.72)
	market_fill.light_energy = 0.80
	market_fill.omni_range = 26.0
	market_fill.shadow_enabled = false
	market_fill.position = Vector3(-1.0, 3.2, 0.5)
	lib.add(content, market_fill, "市場陰影補光")
	var world_centre := Vector2(group.position.x, group.position.z)
	var base_y := group.position.y
	var wood: Material = material_fn.call("wood")
	var stone: Material = material_fn.call("stone")
	build_dragon.call(content, -12.0, -10.0)
	build_stalls(
		lib, content, world_centre, base_y, wood, lm_rng,
		ground_under, material_fn, collide)
	build_civic_fixtures(
		lib, content, world_centre, base_y, wood, stone,
		height_at, material_fn, collide)

## Deterministic Human Village market builders. Callers retain ownership of
## the shared landmark RNG so extraction cannot silently reset its sequence.

static func build_stalls(lib, group: Node3D, world_centre: Vector2,
		origin_y: float, wood: Material, rng: RandomNumberGenerator,
		ground_under_fn: Callable, material_fn: Callable,
		collision_fn: Callable) -> void:
	var cloths := [
		Color(0.52, 0.30, 0.27), Color(0.30, 0.35, 0.45),
		Color(0.58, 0.50, 0.32), Color(0.34, 0.42, 0.33),
		Color(0.46, 0.40, 0.50),
	]
	var goods := [
		Color(0.78, 0.62, 0.34), Color(0.52, 0.30, 0.24),
		Color(0.40, 0.52, 0.30), Color(0.86, 0.80, 0.62),
		Color(0.30, 0.34, 0.40),
	]
	var earth: StandardMaterial3D = lib.pbr(
		"市場土間", "terrain_path", 0.20, Color(0.70, 0.66, 0.58), true, 0.28)
	var stall_woods: Array[StandardMaterial3D] = [
		lib.pbr("市場屋台木_農", "planks", 0.62,
			Color(0.92, 0.78, 0.60), true, 0.42),
		lib.pbr("市場屋台木_乾", "planks", 0.62,
			Color(0.82, 0.70, 0.56), true, 0.42),
		lib.pbr("市場屋台木_食", "planks", 0.62,
			Color(0.88, 0.72, 0.58), true, 0.42),
	]
	# Two facing rows form an aisle. Island offsets keep the aerial silhouette
	# from reading as a mechanically spaced parking grid.
	const AISLE_Z := 2.0
	const AISLE_HALF := 4.6
	const STALL_ISLAND_DX := [0.0, 0.0, 2.10, 2.10, 4.60, 4.60]
	const STALL_ISLAND_DZ := [0.0, 0.35, -0.45]
	for i in 12:
		# Stable family assignment.  Deliberately uses no RNG: changing stall art
		# must not move the shared landmark stream or anything generated after it.
		var family := i % 3 # 0 produce, 1 dry goods, 2 prepared food
		var stall_wood: StandardMaterial3D = stall_woods[family]
		var row := i % 2
		var k0: int = i / 2
		var ox: float = -13.0 + float(k0) * 4.55 \
			+ float(STALL_ISLAND_DX[k0]) + rng.randf_range(-0.9, 0.9)
		var oz: float = AISLE_Z + (AISLE_HALF if row == 1 else -AISLE_HALF) \
			+ float(STALL_ISLAND_DZ[k0 / 2]) * (1.0 if row == 1 else -1.0) \
			+ rng.randf_range(-0.4, 0.4)
		var ground_under: Array = ground_under_fn.call(
			world_centre.x + ox, world_centre.y + oz, 3.6, 3.0)
		var stall := Node3D.new()
		stall.position = Vector3(ox, float(ground_under[0]) - origin_y, oz)
		stall.rotation.y = (PI if row == 1 else 0.0) \
			+ rng.randf_range(-0.18, 0.18)
		lib.add(group, stall, "屋台_%d" % i)
		lib.box(stall, "土間", Vector3(4.4, 0.10, 3.6), earth,
			Vector3(0, 0.03, 0.2))
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				lib.strut(stall, "腳_%d%d" % [int(sx + 1), int(sz + 1)],
					Vector3(sx * 1.3, 0.06, sz * 0.85),
					Vector3(sx * 1.3, 0.95, sz * 0.85), 0.055, stall_wood, 5)
			lib.strut(stall, "貫_%d" % int(sx + 1),
				Vector3(sx * 1.3, 0.34, -0.85),
				Vector3(sx * 1.3, 0.34, 0.85), 0.04, stall_wood, 4)
		var counter_size: Vector3 = [
			Vector3(3.25, 0.10, 1.95),
			Vector3(2.85, 0.10, 1.72),
			Vector3(3.05, 0.12, 2.10),
		][family]
		lib.box(stall, "檯面", counter_size,
			stall_wood, Vector3(0, 1.0, 0))
		var back_h: float = [2.18, 2.78, 2.55][family]
		var front_h: float = [1.82, 2.34, 1.92][family]
		for sx in [-1.0, 1.0]:
			lib.strut(stall, "篷柱後_%d" % int(sx + 1),
				Vector3(sx * 1.35, 0.95, -0.95),
				Vector3(sx * 1.4, back_h, -1.05), 0.05, stall_wood, 5)
			lib.strut(stall, "篷柱前_%d" % int(sx + 1),
				Vector3(sx * 1.35, 0.95, 0.95),
				Vector3(sx * 1.4, front_h, 1.15), 0.05, stall_wood, 5)
		var base_colour: Color = cloths[i % cloths.size()]
		var cloth: StandardMaterial3D = lib.pbr(
			"屋台布_%d" % (i % 5), "plaster", 1.25,
			base_colour.lightened(0.22), true, 0.22)
		cloth.roughness = 0.92
		var striped_cloth: StandardMaterial3D = lib.pbr(
			"屋台布縞_%d" % (i % 5), "plaster", 1.25,
			Color(base_colour.r * 0.62 + 0.30,
				base_colour.g * 0.62 + 0.30,
				base_colour.b * 0.62 + 0.30).lightened(0.12), true, 0.22)
		striped_cloth.roughness = 0.92
		var strip_count := 6
		var canopy_width: float = [3.55, 3.20, 3.45][family]
		var canopy_depth: float = [1.12, 1.18, 1.42][family]
		for row_index in 2:
			var row_t := float(row_index)
			var sag: float = (-0.14 if family == 0 else -0.08) \
				if row_index == 0 else 0.0
			for strip_index in strip_count:
				var strip_width := canopy_width / float(strip_count)
				var canopy: MeshInstance3D = lib.box(
					stall, "篷_%d_%d" % [row_index, strip_index],
					Vector3(strip_width * 0.99, 0.055, canopy_depth),
					cloth if strip_index % 2 == 0 else striped_cloth,
					Vector3(-canopy_width * 0.5 \
							+ (float(strip_index) + 0.5) * strip_width,
						lerpf(back_h, front_h, 0.25 + row_t * 0.5) + sag,
						-canopy_depth * 0.44 + row_t * canopy_depth * 0.88))
				canopy.rotation.x = (0.16 if family == 1 else 0.22) + row_t * 0.06
		var skirt: MeshInstance3D = lib.box(
			stall, "篷垂", Vector3(canopy_width,
				[0.28, 0.52, 0.40][family], 0.04), striped_cloth,
			Vector3(0, front_h - 0.12, 1.18))
		skirt.rotation.x = 0.1
		for goods_index in 3:
			var goods_material: StandardMaterial3D = lib.flat_mat(
				"貨_%d" % ((i + goods_index) % 5),
				goods[(i + goods_index) % goods.size()], 0.9)
			var goods_x := -0.95 + float(goods_index) * 0.95
			if rng.randf() < 0.5:
				for stack_index in 3:
					lib.cyl(stall, "貨_%d_%d" % [goods_index, stack_index],
						0.16, 0.18, 0.12, goods_material,
						Vector3(goods_x + rng.randf_range(-0.05, 0.05),
							1.11 + float(stack_index) * 0.12,
							rng.randf_range(-0.3, 0.3)), 8)
			else:
				lib.box(stall, "貨箱_%d" % goods_index,
					Vector3(0.6, 0.26, 0.5), goods_material,
					Vector3(goods_x, 1.18, rng.randf_range(-0.25, 0.25)))
		if rng.randf() < 0.6:
			var curtain_x := 1.42 * (1.0 if rng.randf() < 0.5 else -1.0)
			for curtain_index in 3:
				lib.box(stall, "暖簾_%d" % curtain_index,
					Vector3(0.04, 0.6, 0.42),
					cloth if curtain_index % 2 == 0 else striped_cloth,
					Vector3(curtain_x, 1.72,
						-0.5 + float(curtain_index) * 0.5))
		lib.box(stall, "木箱", Vector3(0.75, 0.48, 0.58),
			stall_wood,
			Vector3(rng.randf_range(-1.1, 1.1), 0.29, 1.45))
		if rng.randf() < 0.5:
			lib.box(stall, "莚", Vector3(1.5, 0.05, 1.0),
				lib.pbr("莚", "terrain_grass", 1.5, Color(0.80, 0.70, 0.46)),
				Vector3(rng.randf_range(-0.6, 0.6), 0.09, 1.7))
		_build_stall_family_details(
			lib, stall, family, i, stall_wood, cloth, striped_cloth, material_fn)
		collision_fn.call(stall, Vector3(3.0, 1.1, 2.2), Vector3.ZERO)


static func _stall_prop(lib, stall: Node3D, kind: String, suffix: String,
		position: Vector3, yaw: float = 0.0,
		scale: Vector3 = Vector3.ONE, material: Material = null) -> void:
	var item := MeshInstance3D.new()
	item.mesh = lib.prop_mesh("res://assets/models/%s.glb" % kind, material)
	item.position = position
	item.rotation.y = yaw
	item.scale = scale
	lib.add(stall, item, "%s_%s" % [kind, suffix])


static func _build_stall_family_details(lib, stall: Node3D, family: int,
		index: int, wood: Material, cloth: Material, striped_cloth: Material,
		material_fn: Callable) -> void:
	var wicker: StandardMaterial3D = lib.pbr(
		"市場籠", "planks", 0.76, Color(1.02, 0.84, 0.58), true, 0.32)
	var container_wood: StandardMaterial3D = lib.pbr(
		"市場箱桶", "planks", 0.68, Color(0.86, 0.68, 0.48), true, 0.38)
	if family == 0:
		# Produce: low horizontal abundance, baskets and a ground mat.  The
		# container silhouette carries the meaning, not three differently coloured boxes.
		lib.box(stall, "農產莚", Vector3(2.35, 0.045, 1.15),
			lib.pbr("農產莚", "terrain_grass", 1.5, Color(0.72, 0.61, 0.38)),
			Vector3(-0.25, 0.085, 1.48))
		_stall_prop(lib, stall, "prop_kago", "左_%d" % index,
			Vector3(-0.92, 1.08, 0.18), -0.18,
			Vector3(0.72, 0.72, 0.72), wicker)
		_stall_prop(lib, stall, "prop_zaru", "右_%d" % index,
			Vector3(0.82, 1.10, -0.10), 0.22,
			Vector3(0.86, 0.86, 0.86), wicker)
		_stall_prop(lib, stall, "prop_basket", "地_%d" % index,
			Vector3(1.18, 0.04, 1.30), 0.35,
			Vector3(0.70, 0.70, 0.70), wicker)
		# Rolled cloth at each front post gives the canopy a tied, soft edge.
		for side in [-1.0, 1.0]:
			lib.box(stall, "農產布束_%d" % int(side + 1.0),
				Vector3(0.15, 0.46, 0.18), cloth,
				Vector3(side * 1.38, 1.58, 1.10))
	elif family == 1:
		# Dry goods: a tall side rack, hanging packets and stacked containers.
		for shelf in 3:
			lib.box(stall, "乾貨棚_%d" % shelf, Vector3(1.05, 0.08, 0.42), wood,
				Vector3(0.98, 0.72 + float(shelf) * 0.50, 0.62))
		for side in [-1.0, 1.0]:
			lib.strut(stall, "乾貨立柱_%d" % int(side + 1.0),
				Vector3(0.98 + side * 0.48, 0.48, 0.62),
				Vector3(0.98 + side * 0.48, 2.18, 0.62), 0.045, wood, 4)
		for packet in 4:
			lib.box(stall, "掛貨_%d" % packet, Vector3(0.22, 0.34, 0.12),
				striped_cloth, Vector3(-0.72 + float(packet) * 0.46, 1.78, 0.92))
		_stall_prop(lib, stall, "prop_crate", "乾_%d" % index,
			Vector3(-1.02, 0.05, 1.30), -0.12,
			Vector3(0.78, 0.78, 0.78), container_wood)
		_stall_prop(lib, stall, "prop_kago", "棚_%d" % index,
			Vector3(0.98, 1.72, 0.60), 0.20,
			Vector3(0.55, 0.55, 0.55), wicker)
	else:
		# Prepared food: a projecting service ledge and vessel cluster create a
		# working face instead of another pure display table.
		lib.box(stall, "熟食前台", Vector3(3.22, 0.14, 0.56),
			material_fn.call("wood", (index + 2) % 4), Vector3(0, 1.05, 1.22))
		for side in [-1.0, 1.0]:
			lib.box(stall, "熟食台腳_%d" % int(side + 1.0),
				Vector3(0.13, 0.88, 0.48), wood,
				Vector3(side * 1.38, 0.52, 1.22))
		var vessel_mat: StandardMaterial3D = lib.flat_mat(
			"熟食器", Color(0.52, 0.55, 0.52), 0.82)
		lib.cyl(stall, "鍋", 0.36, 0.42, 0.28, vessel_mat,
			Vector3(-0.62, 1.26, 1.18), 12)
		lib.cyl(stall, "器", 0.22, 0.25, 0.34, vessel_mat,
			Vector3(0.08, 1.29, 1.18), 10)
		_stall_prop(lib, stall, "prop_taru", "熟_%d" % index,
			Vector3(1.02, 0.04, -0.35), 0.18,
			Vector3(0.62, 0.62, 0.62), container_wood)
		_stall_prop(lib, stall, "prop_zaru", "器_%d" % index,
			Vector3(0.74, 1.20, 0.72), -0.20,
			Vector3(0.62, 0.62, 0.62), wicker)
		# Short side flap protects the work surface without hiding the shops beyond.
		lib.box(stall, "熟食側簾", Vector3(0.04, 0.64, 0.72), cloth,
			Vector3(-1.48, 1.62, 0.58))


static func build_civic_fixtures(lib, group: Node3D,
		world_centre: Vector2, origin_y: float, wood: Material, stone: Material,
		height_fn: Callable, material_fn: Callable,
		collision_fn: Callable) -> void:
	var well_offset := Vector2(13.0, 8.0)
	var well := Node3D.new()
	well.position = Vector3(
		well_offset.x,
		float(height_fn.call(
			world_centre.x + well_offset.x,
			world_centre.y + well_offset.y)) - origin_y,
		well_offset.y)
	lib.add(group, well, "水井")
	lib.cyl(well, "井筒", 1.15, 1.25, 1.0, stone,
		Vector3(0, 0.5, 0), 12)
	lib.cyl(well, "井口", 0.95, 0.95, 0.05,
		lib.flat_mat("water_dark", Color(0.07, 0.12, 0.15), 0.1),
		Vector3(0, 1.0, 0), 12)
	for side in [-1, 1]:
		lib.cyl(well, "支柱_%d" % (side + 1), 0.09, 0.09, 2.6,
			material_fn.call("dark", -1),
			Vector3(float(side) * 1.0, 1.3, 0), 6)
	lib.box(well, "橫木", Vector3(2.4, 0.14, 0.14),
		material_fn.call("dark", -1), Vector3(0, 2.55, 0))
	lib.box(well, "桶", Vector3(0.4, 0.4, 0.4), wood,
		Vector3(0, 1.9, 0))
	lib.gable_roof(well, 2.62, 3.0, 2.6, 0.5, 0.16,
		material_fn.call("kawara", -1), wood)
	lib.cyl(well, "滑車", 0.16, 0.16, 0.12,
		material_fn.call("dark", -1), Vector3(0, 2.42, 0), 8)
	collision_fn.call(well, Vector3(2.5, 1.2, 2.5), Vector3.ZERO)

	var notice_offset := Vector2(14.0, -12.0)
	var notice := Node3D.new()
	notice.position = Vector3(
		notice_offset.x,
		float(height_fn.call(
			world_centre.x + notice_offset.x,
			world_centre.y + notice_offset.y)) - origin_y,
		notice_offset.y)
	notice.rotation.y = -0.5
	lib.add(group, notice, "高札場")
	for side in [-1, 1]:
		lib.box(notice, "柱_%d" % (side + 1), Vector3(0.18, 2.6, 0.18),
			material_fn.call("dark", -1),
			Vector3(float(side) * 1.2, 1.3, 0))
	lib.box(notice, "板", Vector3(2.7, 1.5, 0.1), wood,
		Vector3(0, 2.0, 0))
	lib.box(notice, "屋根", Vector3(3.1, 0.12, 0.6),
		material_fn.call("kawara", -1), Vector3(0, 2.85, 0))
	collision_fn.call(notice, Vector3(2.8, 2.8, 0.6), Vector3.ZERO)
