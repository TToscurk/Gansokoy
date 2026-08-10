extends RefCounted

## Deterministic main-street sight nodes. The street-lamp scene is inspected
## only to avoid visual overlap; this builder owns no RNG.

static func build(lib, root: Node3D, material_fn: Callable,
		reserved_fn: Callable, height_fn: Callable, collision_fn: Callable,
		cut_grass_fn: Callable, audit: Array[String]) -> void:
	var group: Node3D = lib.add(root, Node3D.new(), "本通の節")
	var dark = material_fn.call("dark", 1)
	var roof = material_fn.call("kawara", 1)
	var stone: StandardMaterial3D = lib.pbr(
		"節石", "stone_wall", 2.2, Color(0.74, 0.73, 0.70))
	var plank: StandardMaterial3D = lib.pbr(
		"節板", "planks", 0.5, Color(0.62, 0.55, 0.44))
	var made: Array[String] = []
	var footprints: Array = []
	var lamps: Array[Vector2] = []
	var lamp_group := root.get_node_or_null("街燈")
	if lamp_group != null:
		for child in lamp_group.get_children():
			if child is Node3D:
				lamps.append(Vector2(
					(child as Node3D).position.x,
					(child as Node3D).position.z))
	var lamp_gap := func(position: Vector2) -> float:
		var best := 1e9
		for lamp_position in lamps:
			best = minf(best, position.distance_to(lamp_position))
		return best
	var dodge_lamp := func(position: Vector2, wanted_gap: float) -> Vector2:
		for step in [0.0, 3.0, -3.0, 6.0, -6.0, 9.0, -9.0, 12.0, -12.0]:
			var candidate := Vector2(position.x, position.y + float(step))
			if lamp_gap.call(candidate) >= wanted_gap:
				return candidate
		return position

	var well_position: Vector2 = dodge_lamp.call(Vector2(-6.9, -52.0), 6.5)
	if not bool(reserved_fn.call(well_position, 1.6)):
		var well_y: float = height_fn.call(well_position.x, well_position.y)
		var well: Node3D = lib.add(group, Node3D.new(), "共同井戸")
		well.position = Vector3(well_position.x, well_y, well_position.y)
		well.rotation.y = 0.24
		for index in 8:
			var angle := TAU * float(index) / 8.0
			var block: MeshInstance3D = lib.box(
				well, "井筒_%d" % index, Vector3(0.34, 0.52, 0.24), stone,
				Vector3(cos(angle) * 0.72, 0.26, sin(angle) * 0.72))
			block.rotation.y = PI * 0.5 - angle
		lib.cyl(well, "井口", 0.62, 0.62, 0.06, dark,
			Vector3(0, 0.56, 0), 12)
		for side in [-1.0, 1.0]:
			lib.box(well, "井桁柱_%d" % int(side + 1.0),
				Vector3(0.11, 1.9, 0.11), dark,
				Vector3(side * 0.86, 0.95, 0))
		lib.box(well, "井桁梁", Vector3(1.94, 0.12, 0.12), dark,
			Vector3(0, 1.86, 0))
		lib.cyl(well, "滑車", 0.15, 0.15, 0.11, dark,
			Vector3(0, 1.72, 0), 8)
		lib.gable_roof(well, 1.98, 2.5, 2.2, 0.42, 0.13, roof, dark)
		collision_fn.call(well, Vector3(2.1, 1.9, 2.1), Vector3.ZERO)
		lib.box(group, "洗い場", Vector3(2.1, 0.14, 1.5), stone,
			Vector3(well_position.x - 1.9,
				float(height_fn.call(
					well_position.x - 1.9, well_position.y + 1.7)) + 0.07,
				well_position.y + 1.7))
		var bench_x := well_position.x - 0.4
		var bench_z := well_position.y + 3.4
		lib.box(group, "縁台_座", Vector3(1.7, 0.09, 0.52), plank,
			Vector3(bench_x, float(height_fn.call(bench_x, bench_z)) + 0.42,
				bench_z))
		for side in [-1.0, 1.0]:
			lib.box(group, "縁台_脚_%d" % int(side + 1.0),
				Vector3(0.09, 0.40, 0.42), dark,
				Vector3(bench_x + side * 0.72,
					float(height_fn.call(bench_x, bench_z)) + 0.20, bench_z))
		made.append("N1 共同井戸")
		footprints.append([well_position, 2.4, 3.0])

	var shelter_position: Vector2 = dodge_lamp.call(Vector2(8.4, 41.0), 5.5)
	if not bool(reserved_fn.call(shelter_position, 2.4)):
		var shelter_y: float = height_fn.call(
			shelter_position.x, shelter_position.y)
		var shelter: Node3D = lib.add(group, Node3D.new(), "上屋")
		shelter.position = Vector3(
			shelter_position.x, shelter_y, shelter_position.y)
		shelter.rotation.y = -0.12
		lib.box(shelter, "土間", Vector3(6.4, 0.12, 4.6),
			lib.pbr("上屋土間", "terrain_path", 0.9, Color(0.72, 0.66, 0.56)),
			Vector3(0, 0.05, 0.2))
		for z in [-2.05, 2.45]:
			lib.box(shelter, "土間縁", Vector3(6.4, 0.14, 0.22), stone,
				Vector3(0, 0.07, z))
		for index in 3:
			var x := -2.55 + float(index) * 2.55
			lib.box(shelter, "沓石_w%d" % index, Vector3(0.34, 0.26, 0.34),
				stone, Vector3(x, 0.16, -1.55))
			lib.box(shelter, "柱_w%d" % index, Vector3(0.16, 2.10, 0.16),
				dark, Vector3(x, 0.29 + 1.05, -1.55))
			lib.box(shelter, "沓石_e%d" % index, Vector3(0.34, 0.26, 0.34),
				stone, Vector3(x, 0.16, 1.75))
			lib.box(shelter, "柱_e%d" % index, Vector3(0.16, 2.70, 0.16),
				dark, Vector3(x, 0.29 + 1.35, 1.75))
		lib.box(shelter, "貫_前", Vector3(5.3, 0.10, 0.14), dark,
			Vector3(0, 0.98, -1.55))
		lib.box(shelter, "貫_後", Vector3(5.3, 0.10, 0.14), dark,
			Vector3(0, 0.98, 1.75))
		for side in [-1.0, 1.0]:
			lib.box(shelter, "貫_妻", Vector3(0.14, 0.10, 3.3), dark,
				Vector3(side * 2.55, 0.98, 0.1))
			var brace: MeshInstance3D = lib.box(
				shelter, "方杖", Vector3(0.11, 0.90, 0.11), dark,
				Vector3(side * 2.35, 2.02, -1.42))
			brace.rotation.z = side * 0.6
		lib.box(shelter, "桁_前", Vector3(5.9, 0.17, 0.17), dark,
			Vector3(0, 2.46, -1.55))
		lib.box(shelter, "桁_後", Vector3(5.9, 0.17, 0.17), dark,
			Vector3(0, 3.06, 1.75))
		for index in 8:
			var rafter_x := -2.75 + float(index) * (5.5 / 7.0)
			var rafter: MeshInstance3D = lib.box(
				shelter, "垂木_%d" % index, Vector3(0.09, 0.09, 4.9), dark,
				Vector3(rafter_x, 2.80, 0.10))
			rafter.rotation.x = -0.181
		var roof_surface: MeshInstance3D = lib.box(
			shelter, "屋根面", Vector3(6.5, 0.15, 5.3), roof,
			Vector3(0, 2.94, 0.10))
		roof_surface.rotation.x = -0.181
		lib.box(shelter, "棟押え", Vector3(6.54, 0.14, 0.30), dark,
			Vector3(0, 3.42, 2.15))
		for side in [-1.0, 1.0]:
			var fascia: MeshInstance3D = lib.box(
				shelter, "破風_%d" % int(side + 1.0),
				Vector3(0.07, 0.17, 5.35), dark,
				Vector3(side * 3.26, 2.93, 0.10))
			fascia.rotation.x = -0.181
		lib.box(shelter, "背板壁", Vector3(5.2, 1.90, 0.07),
			lib.pbr("上屋板壁", "planks", 1.6, Color(0.62, 0.55, 0.45)),
			Vector3(0, 1.90, 1.72))
		collision_fn.call(
			shelter, Vector3(5.6, 2.9, 3.6), Vector3(0, 0, 0.1))
		var bale := MeshInstance3D.new()
		bale.mesh = lib.prop_mesh("res://assets/models/prop_tawara.glb")
		bale.position = Vector3(1.5, 0.12, 0.6)
		bale.rotation.y = 0.4
		lib.add(shelter, bale, "俵")
		var crate := MeshInstance3D.new()
		crate.mesh = lib.prop_mesh("res://assets/models/prop_crate.glb")
		crate.position = Vector3(-1.6, 0.12, 0.9)
		crate.rotation.y = -0.25
		lib.add(shelter, crate, "木箱")
		made.append("N2 上屋")
		footprints.append([shelter_position, 3.6, 2.8])

	var lantern_z := 78.0
	for step in [0.0, 3.0, -3.0, 6.0, -6.0, 9.0, -9.0, 12.0, -12.0]:
		var candidate_z := 78.0 + float(step)
		if minf(
				lamp_gap.call(Vector2(-6.3, candidate_z)),
				lamp_gap.call(Vector2(6.3, candidate_z))) >= 7.0:
			lantern_z = candidate_z
			break
	var lantern_count := 0
	var west_lantern := Vector2(-6.3, lantern_z)
	for side in [-1.0, 1.0]:
		var lantern_position := Vector2(side * 6.3, lantern_z)
		if bool(reserved_fn.call(lantern_position, 1.2)) \
				or lamp_gap.call(lantern_position) < 7.0:
			continue
		var lantern_y: float = height_fn.call(
			lantern_position.x, lantern_position.y)
		var lantern: Node3D = lib.add(
			group, Node3D.new(), "常夜灯_%d" % int(side + 1.0))
		lantern.position = Vector3(
			lantern_position.x, lantern_y, lantern_position.y)
		lib.box(lantern, "基壇", Vector3(1.05, 0.34, 1.05), stone,
			Vector3(0, 0.17, 0))
		lib.box(lantern, "竿", Vector3(0.34, 1.85, 0.34), stone,
			Vector3(0, 1.26, 0))
		lib.box(lantern, "中台", Vector3(0.66, 0.16, 0.66), stone,
			Vector3(0, 2.26, 0))
		lib.box(lantern, "火袋", Vector3(0.58, 0.62, 0.58),
			lib.flat_mat("常夜灯火", Color(0.80, 0.73, 0.58), 0.55,
				Color(0.22, 0.16, 0.07)), Vector3(0, 2.65, 0))
		lib.box(lantern, "笠", Vector3(0.94, 0.20, 0.94), stone,
			Vector3(0, 3.06, 0))
		lib.box(lantern, "宝珠", Vector3(0.22, 0.26, 0.22), stone,
			Vector3(0, 3.29, 0))
		collision_fn.call(lantern, Vector3(1.0, 3.4, 1.0), Vector3.ZERO)
		footprints.append([lantern_position, 1.0, 1.0])
		if side < 0.0:
			west_lantern = lantern_position
		lantern_count += 1
	if lantern_count > 0:
		var sign_position := Vector2(west_lantern.x, west_lantern.y - 3.4)
		if not bool(reserved_fn.call(sign_position, 1.0)):
			var sign_y: float = height_fn.call(sign_position.x, sign_position.y)
			lib.box(group, "道標", Vector3(0.30, 1.42, 0.26), stone,
				Vector3(sign_position.x, sign_y + 0.71, sign_position.y))
			footprints.append([sign_position, 0.7, 0.7])
		made.append("N3 常夜灯 %d ＋道標" % lantern_count)

	var cut_count: int = cut_grass_fn.call(footprints)
	audit.append("PHASE 3.2A 本通の節：%s（足元の草 %d 叢を除去）"
		% [", ".join(made), cut_count])
