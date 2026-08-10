extends RefCounted

## Deterministic fire-watch crossroads builder. This module deliberately owns
## no RNG and receives all generator state through explicit callables.

static func build(lib, root: Node3D, out_dir: String, has_wood: bool,
		material_fn: Callable, height_fn: Callable, collision_fn: Callable,
		tree_mesh_fn: Callable, cut_grass_fn: Callable,
		audit: Array[String]) -> void:
	var tower_x := 9.5
	var tower_z := -132.0
	var group: Node3D = lib.add(root, Node3D.new(), "火の番の辻")
	var dark = material_fn.call("dark", 1)
	var roof = material_fn.call("kawara", 1)
	var wood = material_fn.call("wood", 0) if has_wood \
		else material_fn.call("dark", 0)
	var stone: StandardMaterial3D = lib.pbr(
		"辻石", "stone_wall", 0.5, Color(0.62, 0.61, 0.58))
	var placed: Array[String] = []

	var bell_y: float = height_fn.call(tower_x - 3.6, tower_z) + 3.15
	lib.box(group, "半鐘腕木", Vector3(2.1, 0.17, 0.19), dark,
		Vector3(tower_x - 2.6, bell_y + 0.46, tower_z))
	lib.box(group, "半鐘方杖", Vector3(0.9, 0.13, 0.13), dark,
		Vector3(tower_x - 2.2, bell_y + 0.02, tower_z))
	lib.cyl(group, "半鐘吊環", 0.06, 0.06, 0.16, dark,
		Vector3(tower_x - 3.6, bell_y + 0.30, tower_z), 6)
	lib.cyl(group, "半鐘笠", 0.30, 0.42, 0.18,
		lib.flat_mat("半鐘銅", Color(0.155, 0.135, 0.095), 0.38),
		Vector3(tower_x - 3.6, bell_y + 0.12, tower_z), 14)
	lib.cyl(group, "半鐘", 0.42, 0.50, 0.66,
		lib.flat_mat("半鐘銅", Color(0.155, 0.135, 0.095), 0.38),
		Vector3(tower_x - 3.6, bell_y - 0.30, tower_z), 14)
	lib.cyl(group, "半鐘縄", 0.018, 0.018, 1.55,
		lib.flat_mat("辻縄", Color(0.22, 0.18, 0.12), 0.95),
		Vector3(tower_x - 3.6, bell_y - 1.40, tower_z), 5)
	placed.append("半鐘")

	var water_barrels: Array[Transform3D] = []
	for spec in [
			[tower_x - 2.6, tower_z + 0.9],
			[tower_x - 2.6, tower_z + 2.0],
			[tower_x - 2.6, tower_z + 3.1],
			[tower_x - 1.3, tower_z + 3.9],
			[tower_x - 0.1, tower_z + 3.9],
		]:
		var x: float = float(spec[0])
		var z: float = float(spec[1])
		water_barrels.append(Transform3D(
			Basis(Vector3.UP, 0.2) * Basis.from_scale(Vector3(1.28, 1.32, 1.28)),
			Vector3(x, float(height_fn.call(x, z)), z)))
	var barrel_instance := MultiMeshInstance3D.new()
	barrel_instance.multimesh = lib.make_multimesh(
		lib.prop_mesh("res://assets/models/prop_taru.glb", lib.vc_mat()),
		water_barrels, [], out_dir + "gen/tsuji_tensuioke.res")
	lib.add(group, barrel_instance, "MM_天水桶")
	placed.append("天水桶 %d" % water_barrels.size())

	var hut_x := tower_x - 1.3
	var hut_z := tower_z + 6.6
	var hut_y: float = height_fn.call(hut_x, hut_z)
	var hut: Node3D = lib.add(group, Node3D.new(), "番小屋")
	hut.position = Vector3(hut_x, hut_y, hut_z)
	hut.rotation.y = 0.2
	lib.box(hut, "土台", Vector3(3.15, 0.18, 2.75), stone,
		Vector3(0, 0.09, 0))
	lib.box(hut, "壁", Vector3(3.0, 2.05, 2.6),
		material_fn.call("plaster", 1), Vector3(0, 1.20, 0))
	for side in [-1.0, 1.0]:
		lib.box(hut, "隅柱_%d" % int(side + 1.0),
			Vector3(0.14, 2.05, 0.14), dark,
			Vector3(side * 1.43, 1.20, 1.23))
	lib.box(hut, "腰板", Vector3(3.06, 0.62, 2.66), dark,
		Vector3(0, 0.49, 0))
	lib.box(hut, "窓", Vector3(0.06, 0.72, 1.05),
		lib.flat_mat("番小屋灯", Color(0.74, 0.67, 0.53), 0.55,
			Color(0.24, 0.17, 0.08)), Vector3(-1.52, 1.45, 0.1))
	lib.gable_roof(hut, 2.25, 3.5, 3.1, 0.30, 0.14, roof, dark)
	collision_fn.call(hut, Vector3(3.1, 2.3, 2.7), Vector3.ZERO)
	placed.append("番小屋")

	var notice_x := -6.6
	var notice_z := -133.4
	var notice_y: float = height_fn.call(notice_x, notice_z)
	var notice: Node3D = lib.add(group, Node3D.new(), "高札場")
	notice.position = Vector3(notice_x, notice_y, notice_z)
	notice.rotation.y = -PI * 0.5 + 0.18
	for side in [-1.0, 1.0]:
		lib.box(notice, "柱_%d" % int(side + 1.0),
			Vector3(0.16, 2.5, 0.16), dark,
			Vector3(side * 1.05, 1.25, 0))
	lib.box(notice, "板", Vector3(2.4, 1.35, 0.09),
		lib.pbr("高札板", "planks", 0.5, Color(0.70, 0.62, 0.50)),
		Vector3(0, 1.88, 0))
	lib.box(notice, "屋根", Vector3(2.8, 0.11, 0.55), roof,
		Vector3(0, 2.68, 0))
	collision_fn.call(notice, Vector3(2.5, 2.6, 0.55), Vector3.ZERO)
	placed.append("高札場")

	var jizo_x := -6.5
	var jizo_z := -139.6
	var jizo_y: float = height_fn.call(jizo_x, jizo_z)
	var jizo: Node3D = lib.add(group, Node3D.new(), "辻地蔵")
	jizo.position = Vector3(jizo_x, jizo_y, jizo_z)
	jizo.rotation.y = PI
	lib.box(jizo, "台座", Vector3(0.86, 0.30, 0.72), stone,
		Vector3(0, 0.15, 0))
	lib.cyl(jizo, "地蔵身", 0.19, 0.22, 0.62, stone,
		Vector3(0, 0.61, 0), 10)
	lib.cyl(jizo, "地蔵頭", 0.17, 0.17, 0.28, stone,
		Vector3(0, 1.06, 0), 10)
	lib.box(jizo, "前掛", Vector3(0.36, 0.34, 0.05),
		lib.flat_mat("辻前掛", Color(0.52, 0.13, 0.11), 0.85),
		Vector3(0, 0.70, -0.21))
	for side in [-1.0, 1.0]:
		lib.box(jizo, "祠柱_%d" % int(side + 1.0),
			Vector3(0.09, 1.42, 0.09), dark,
			Vector3(side * 0.52, 0.71, 0.16))
	lib.box(jizo, "祠屋根", Vector3(1.32, 0.10, 0.92), roof,
		Vector3(0, 1.50, 0.0))
	collision_fn.call(jizo, Vector3(1.3, 1.6, 0.95), Vector3.ZERO)
	placed.append("辻地蔵")

	var tree_x := -8.8
	var tree_z := -136.4
	var tree := MeshInstance3D.new()
	tree.mesh = tree_mesh_fn.call("res://assets/models/tree_round_a.glb")
	tree.position = Vector3(
		tree_x, float(height_fn.call(tree_x, tree_z)), tree_z)
	tree.rotation.y = 0.6
	tree.scale = Vector3(1.15, 1.2, 1.15)
	lib.add(group, tree, "辻の樹")
	placed.append("樹")

	var footprints := [
		[Vector2(hut_x, hut_z), 2.1, 1.8],
		[Vector2(notice_x, notice_z), 1.5, 0.7],
		[Vector2(jizo_x, jizo_z), 1.0, 0.8],
		[Vector2(tower_x - 2.0, tower_z + 2.4), 2.4, 2.6],
		[Vector2(tree_x, tree_z), 1.3, 1.3],
	]
	var cut_count: int = cut_grass_fn.call(footprints)
	audit.append("PHASE 3.1B 火の番の辻：%s（足元の草 %d 叢を除去）"
		% [", ".join(placed), cut_count])
