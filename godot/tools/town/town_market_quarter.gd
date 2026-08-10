extends RefCounted

## Deterministic functional fixtures around the market quarter. This builder
## owns no RNG and receives terrain and grass editing through explicit hooks.

static func build(lib, root: Node3D, material_fn: Callable,
		height_fn: Callable, collision_fn: Callable,
		cut_grass_fn: Callable, audit: Array[String]) -> void:
	var group: Node3D = lib.add(root, Node3D.new(), "市場區の設え")
	var dark = material_fn.call("dark", 1)
	var wood = material_fn.call("wood", 0)
	var plank: StandardMaterial3D = lib.pbr(
		"市場板", "planks", 0.55, Color(0.66, 0.58, 0.46))
	var stone: StandardMaterial3D = lib.pbr(
		"市場踏石", "stone_wall", 2.0, Color(0.70, 0.69, 0.66))
	var made: Array[String] = []
	var footprints: Array = []

	var platform_x := -46.5
	var platform_z := 73.0
	var platform_y: float = height_fn.call(platform_x, platform_z)
	var platform: Node3D = lib.add(group, Node3D.new(), "荷揚げ台")
	platform.position = Vector3(platform_x, platform_y, platform_z)
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			lib.box(platform,
				"束石_%d%d" % [int(x_side + 1.0), int(z_side + 1.0)],
				Vector3(0.34, 0.30, 0.34), stone,
				Vector3(x_side * 1.45, 0.15, z_side * 0.78))
	lib.box(platform, "台板", Vector3(3.60, 0.16, 2.10), plank,
		Vector3(0, 0.45, 0))
	lib.box(platform, "縁桁", Vector3(3.72, 0.13, 0.13), dark,
		Vector3(0, 0.35, 1.06))
	lib.box(platform, "踏段", Vector3(1.30, 0.15, 0.42), plank,
		Vector3(-0.9, 0.22, 1.32))
	collision_fn.call(platform, Vector3(3.7, 0.55, 2.2), Vector3.ZERO)
	for spec in [
			["prop_tawara", -47.6, 72.5, 0.30, 0.53],
			["prop_tawara", -47.6, 73.4, 0.34, 0.53],
			["prop_tawara", -47.5, 72.95, 0.10, 0.86],
			["prop_crate", -45.4, 73.2, -0.4, 0.53],
		]:
		var item := MeshInstance3D.new()
		item.mesh = lib.prop_mesh(
			"res://assets/models/%s.glb" % String(spec[0]))
		item.position = Vector3(
			float(spec[1]),
			float(height_fn.call(platform_x, platform_z)) + float(spec[4]),
			float(spec[2]))
		item.rotation.y = float(spec[3])
		lib.add(group, item,
			"蔵荷_%s_%d" % [String(spec[0]), int(float(spec[4]) * 100.0)])
	made.append("荷揚げ台と俵")
	footprints.append([Vector2(platform_x, platform_z), 2.4, 1.8])

	var canopy_x := -34.0
	var canopy_z := 70.0
	var canopy_y: float = height_fn.call(canopy_x, canopy_z)
	var canopy: Node3D = lib.add(group, Node3D.new(), "仕事庇")
	canopy.position = Vector3(canopy_x, canopy_y, canopy_z)
	for x_side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			lib.strut(canopy,
				"庇柱_%d%d" % [int(x_side + 1.0), int(z_side + 1.0)],
				Vector3(x_side * 2.55, 0.0, z_side * 1.35),
				Vector3(x_side * 2.55, 2.32 + z_side * 0.13, z_side * 1.35),
				0.075, dark, 6)
	lib.box(canopy, "桁前", Vector3(5.30, 0.13, 0.12), dark,
		Vector3(0, 2.20, -1.35))
	lib.box(canopy, "桁後", Vector3(5.30, 0.13, 0.12), dark,
		Vector3(0, 2.46, 1.35))
	for index in 9:
		var rafter_x := -2.35 + float(index) * 0.59
		var rafter: MeshInstance3D = lib.box(
			canopy, "垂木_%d" % index, Vector3(0.09, 0.06, 2.86), dark,
			Vector3(rafter_x, 2.36, 0))
		rafter.rotation.x = -0.09
	var reed_screen: MeshInstance3D = lib.box(
		canopy, "葭簀", Vector3(5.30, 0.05, 2.90),
		lib.pbr("葭簀", "planks", 1.6, Color(0.74, 0.66, 0.45)),
		Vector3(0, 2.42, 0))
	reed_screen.rotation.x = -0.09
	lib.box(canopy, "作業台", Vector3(2.10, 0.10, 0.86), plank,
		Vector3(-0.8, 0.78, 0.15))
	for side in [-1.0, 1.0]:
		lib.box(canopy, "台脚_%d" % int(side + 1.0),
			Vector3(0.11, 0.73, 0.78), wood,
			Vector3(-0.8 + side * 0.92, 0.37, 0.15))
	for index in 5:
		lib.box(canopy, "材_%d" % index, Vector3(2.60, 0.11, 0.13), wood,
			Vector3(1.55, 0.09 + float(index % 3) * 0.12,
				-0.65 + float(index / 3) * 0.30))
	collision_fn.call(canopy, Vector3(5.4, 2.5, 2.9), Vector3.ZERO)
	for spec in [
			["prop_takigi", -36.9, 71.2, 0.25],
			["prop_takigi", -36.9, 70.1, 0.25],
			["prop_taru", -31.3, 71.4, -0.5],
		]:
		var item := MeshInstance3D.new()
		item.mesh = lib.prop_mesh(
			"res://assets/models/%s.glb" % String(spec[0]))
		item.position = Vector3(
			float(spec[1]),
			float(height_fn.call(float(spec[1]), float(spec[2]))),
			float(spec[2]))
		item.rotation.y = float(spec[3])
		lib.add(group, item,
			"作業荷_%s_%d" % [String(spec[0]), int(float(spec[2]))])
	made.append("仕事庇と材")
	footprints.append([Vector2(canopy_x, canopy_z), 3.4, 2.4])

	for spec in [
			["prop_misedai", -22.6, 71.4, 0.0],
			["prop_zaru", -20.2, 71.5, 0.4],
			["prop_kago", -19.4, 71.9, -0.2],
			["prop_crate", -23.9, 71.9, 0.15],
			["prop_taru", -24.6, 72.2, 0.6],
		]:
		var item := MeshInstance3D.new()
		item.mesh = lib.prop_mesh(
			"res://assets/models/%s.glb" % String(spec[0]))
		item.position = Vector3(
			float(spec[1]),
			float(height_fn.call(float(spec[1]), float(spec[2]))),
			float(spec[2]))
		item.rotation.y = float(spec[3])
		lib.add(group, item,
			"店先_%s_%d" % [String(spec[0]), int(-float(spec[1]))])
	made.append("見世台と店先の荷")
	footprints.append([Vector2(-22.0, 71.7), 3.6, 1.4])

	var rack_x := -42.2
	var rack_z := 66.6
	var rack_y: float = height_fn.call(rack_x, rack_z)
	var rack: Node3D = lib.add(group, Node3D.new(), "荷置き")
	rack.position = Vector3(rack_x, rack_y, rack_z)
	rack.rotation.y = -PI * 0.5
	lib.box(rack, "簀の子", Vector3(2.80, 0.10, 1.50), plank,
		Vector3(0, 0.10, 0))
	for side in [-1.0, 1.0]:
		lib.box(rack, "枕木_%d" % int(side + 1.0),
			Vector3(2.90, 0.12, 0.14), dark,
			Vector3(0, 0.06, side * 0.62))
	collision_fn.call(rack, Vector3(2.9, 0.3, 1.6), Vector3.ZERO)
	for spec in [
			["prop_tawara", -42.4, 65.9, 1.55, 0.16],
			["prop_tawara", -42.4, 66.8, 1.55, 0.16],
			["prop_tawara", -42.3, 66.35, 1.55, 0.49],
			["prop_crate", -41.6, 67.5, 0.2, 0.16],
			["prop_zaru", -43.0, 67.7, -0.3, 0.0],
		]:
		var item := MeshInstance3D.new()
		item.mesh = lib.prop_mesh(
			"res://assets/models/%s.glb" % String(spec[0]))
		item.position = Vector3(
			float(spec[1]), rack_y + float(spec[4]), float(spec[2]))
		item.rotation.y = float(spec[3])
		lib.add(group, item,
			"西荷_%s_%d" % [String(spec[0]), int(float(spec[4]) * 100.0)])
	made.append("西縁の荷置き")
	footprints.append([Vector2(rack_x, rack_z), 2.2, 2.2])

	for index in 7:
		var path_t := float(index) / 6.0
		var x := lerpf(-14.2, -19.4, path_t)
		var z := lerpf(66.4, 71.6, path_t)
		var stepping_stone: MeshInstance3D = lib.box(
			group, "飛石_%d" % index, Vector3(0.62, 0.09, 0.52), stone,
			Vector3(x, float(height_fn.call(x, z)) + 0.045, z))
		stepping_stone.rotation.y = 0.22 * float(index % 3 - 1)
	made.append("飛石 7")
	footprints.append([Vector2(-16.8, 69.0), 3.6, 3.6])

	var cut_count: int = cut_grass_fn.call(footprints)
	audit.append("PHASE 5A-V 市場區の設え：%s（足元の草 %d 叢を除去）"
		% [", ".join(made), cut_count])
