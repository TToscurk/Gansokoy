extends RefCounted

const StreetFixtures := preload("res://tools/town/town_street_fixtures.gd")

## Deterministic main-street frontage and civic assembly. Fence and gate
## geometry is delegated to the shared street-fixture builders.

static func build(lib, root: Node3D, material_fn: Callable,
		height_fn: Callable, reserved_fn: Callable, collision_fn: Callable,
		tree_mesh_fn: Callable, cut_grass_fn: Callable,
		audit: Array[String]) -> void:
	var group: Node3D = lib.add(root, Node3D.new(), "本通の街並")
	var dark: StandardMaterial3D = lib.pbr(
		"塀柱", "dark_wood", 2.2, Color(0.34, 0.32, 0.29))
	var boards: StandardMaterial3D = lib.pbr(
		"塀板", "planks", 3.4, Color(0.50, 0.44, 0.37))
	var stone: StandardMaterial3D = lib.pbr(
		"街石", "stone_flag", 1.6, Color(0.55, 0.56, 0.54))
	var roof = material_fn.call("kawara", 1)
	var made: Array[String] = []
	var footprints: Array = []

	var terakoya_fence: Node3D = lib.add(group, Node3D.new(), "寺子屋塀")
	StreetFixtures.build_fence(
		lib, root, terakoya_fence, -8.2, -62.0, -44.0,
		[[-55.3, -53.3]], dark, boards, height_fn)
	StreetFixtures.build_mune_gate(
		lib, terakoya_fence, -8.2, -54.3, 1.85,
		dark, roof, stone, height_fn)
	made.append("寺子屋の塀と門")
	footprints.append([Vector2(-8.2, -53.0), 1.2, 9.6])

	var inari_y: float = height_fn.call(-7.8, -30.0)
	var inari: Node3D = lib.add(group, Node3D.new(), "稲荷小祠")
	inari.position = Vector3(-7.8, inari_y, -30.0)
	inari.rotation.y = 0.5
	lib.box(inari, "基壇", Vector3(1.5, 0.28, 1.2), stone,
		Vector3(0, 0.14, 0))
	lib.box(inari, "祠身", Vector3(0.78, 0.72, 0.62),
		lib.pbr("祠木", "dark_wood", 2.6, Color(0.52, 0.46, 0.40)),
		Vector3(0, 0.64, 0))
	lib.gable_roof(inari, 1.02, 1.06, 0.92, 0.55, 0.09, roof, dark)
	var vermilion: StandardMaterial3D = lib.flat_mat(
		"鳥居朱", Color(0.435, 0.135, 0.10), 0.78)
	for index in 2:
		var torii_z := -1.05 - float(index) * 0.75
		for side in [-1.0, 1.0]:
			lib.box(inari,
				"小鳥居柱_%d_%d" % [index, int(side + 1.0)],
				Vector3(0.07, 0.95, 0.07), vermilion,
				Vector3(side * 0.36, 0.475, torii_z))
		lib.box(inari, "小鳥居笠_%d" % index,
			Vector3(0.98, 0.08, 0.10), vermilion,
			Vector3(0, 0.95, torii_z))
	collision_fn.call(inari, Vector3(1.6, 1.3, 1.3), Vector3.ZERO)
	made.append("稲荷小祠")
	footprints.append([Vector2(-7.8, -30.0), 1.4, 1.8])

	var fence_material: StandardMaterial3D = lib.pbr(
		"玉垣", "planks", 1.9, Color(0.60, 0.55, 0.47))
	for span in [[-13.0, -1.6], [5.6, 17.0]]:
		var cursor := float(span[0])
		while cursor < float(span[1]) - 0.1:
			var segment_end := minf(cursor + 1.55, float(span[1]))
			var segment_y: float = height_fn.call(
				-6.5, (cursor + segment_end) * 0.5)
			lib.box(group, "玉垣板_%d" % int(cursor * 10.0),
				Vector3(0.07, 0.66, segment_end - cursor - 0.10),
				fence_material,
				Vector3(-6.5, segment_y + 0.52, (cursor + segment_end) * 0.5))
			lib.box(group, "玉垣柱_%d" % int(cursor * 10.0),
				Vector3(0.11, 0.94, 0.11), dark,
				Vector3(-6.5,
					float(height_fn.call(-6.5, cursor)) + 0.47, cursor))
			cursor = segment_end
	var torii_y: float = height_fn.call(-6.4, 2.0)
	var torii: Node3D = lib.add(group, Node3D.new(), "鳥居")
	torii.position = Vector3(-6.4, torii_y, 2.0)
	for side in [-1.0, 1.0]:
		lib.box(torii, "柱_%d" % int(side + 1.0),
			Vector3(0.24, 3.30, 0.24), vermilion,
			Vector3(0, 1.65, side * 1.45))
		lib.box(torii, "亀腹_%d" % int(side + 1.0),
			Vector3(0.38, 0.22, 0.38), stone,
			Vector3(0, 0.11, side * 1.45))
	lib.box(torii, "貫", Vector3(0.16, 0.20, 3.85), vermilion,
		Vector3(0, 2.55, 0))
	lib.box(torii, "島木", Vector3(0.22, 0.20, 3.75), vermilion,
		Vector3(0, 3.32, 0))
	lib.box(torii, "笠木", Vector3(0.30, 0.17, 4.10), dark,
		Vector3(0, 3.50, 0))
	for index in 3:
		lib.box(group, "参道敷石_%d" % index,
			Vector3(0.95, 0.07, 0.80), stone,
			Vector3(-5.3,
				float(height_fn.call(-5.3, 2.0)) + 0.02,
				2.0 - 0.85 + float(index) * 0.85))
	made.append("鎮守之杜の玉垣と鳥居")

	var storehouse_fence: Node3D = lib.add(
		group, Node3D.new(), "蔵屋敷塀")
	StreetFixtures.build_fence(
		lib, root, storehouse_fence, 6.9, -38.0, -8.0,
		[[-23.4, -21.4]], dark, boards, height_fn)
	StreetFixtures.build_mune_gate(
		lib, storehouse_fence, 6.9, -22.4, 1.85,
		dark, roof, stone, height_fn)
	var storehouse_wall: StandardMaterial3D = lib.pbr(
		"蔵漆喰", "plaster", 1.5, Color(1.04, 1.01, 0.95))
	var storehouse_base: StandardMaterial3D = lib.pbr(
		"蔵海鼠", "namako", 2.1, Color(0.92, 0.92, 0.90))
	for z in [-30.5, -14.5]:
		var x := 11.6
		if bool(reserved_fn.call(Vector2(x, z), 2.0)):
			continue
		var y: float = height_fn.call(x, z)
		var storehouse: Node3D = lib.add(
			group, Node3D.new(), "蔵_%d" % int(z))
		storehouse.position = Vector3(x, y, z)
		storehouse.rotation.y = PI * 0.5
		lib.box(storehouse, "基壇", Vector3(5.0, 0.42, 6.4), stone,
			Vector3(0, 0.21, 0))
		lib.box(storehouse, "腰", Vector3(4.62, 0.95, 6.02), storehouse_base,
			Vector3(0, 0.90, 0))
		lib.box(storehouse, "壁", Vector3(4.58, 2.35, 5.98), storehouse_wall,
			Vector3(0, 2.53, 0))
		lib.box(storehouse, "扉", Vector3(1.15, 1.75, 0.14), dark,
			Vector3(0.6, 1.45, -3.02))
		lib.box(storehouse, "窓", Vector3(0.72, 0.55, 0.10), dark,
			Vector3(0, 3.05, -3.00))
		lib.gable_roof(
			storehouse, 3.72, 5.3, 7.0, 0.44, 0.15, roof, dark)
		collision_fn.call(
			storehouse, Vector3(5.0, 3.8, 6.4), Vector3.ZERO)
		footprints.append([Vector2(x, z), 3.4, 3.0])
	made.append("蔵屋敷（塀＋蔵二棟）")
	footprints.append([Vector2(6.9, -23.0), 1.0, 15.6])

	var banner_colours := [
		Color(0.16, 0.19, 0.31), Color(0.55, 0.30, 0.16),
		Color(0.80, 0.76, 0.66), Color(0.16, 0.19, 0.31),
		Color(0.30, 0.42, 0.28),
	]
	for index in 5:
		var z := 46.0 + float(index) * 6.0
		var y: float = height_fn.call(-6.9, z)
		var banner: Node3D = lib.add(
			group, Node3D.new(), "幟_%d" % index)
		banner.position = Vector3(-6.9, y, z)
		banner.rotation.y = 0.10 * float(index % 3 - 1)
		lib.cyl(banner, "竿", 0.045, 0.055, 4.3, dark,
			Vector3(0, 2.15, 0), 6)
		lib.box(banner, "横手", Vector3(0.05, 0.05, 0.62), dark,
			Vector3(0, 4.05, 0.26))
		lib.box(banner, "布", Vector3(0.035, 2.55, 0.55),
			lib.flat_mat("幟布_%d" % index, banner_colours[index], 0.85),
			Vector3(0, 2.72, 0.30))
	for side in [-1.0, 1.0]:
		lib.box(group, "市木戸柱_%d" % int(side + 1.0),
			Vector3(0.20, 2.45, 0.20), dark,
			Vector3(-6.9,
				float(height_fn.call(-6.9, 57.0 + side * 1.35)) + 1.22,
				57.0 + side * 1.35))
	lib.box(group, "市木戸冠木", Vector3(0.17, 0.19, 3.35), dark,
		Vector3(-6.9, float(height_fn.call(-6.9, 57.0)) + 2.42, 57.0))
	for spec in [
			["prop_tawara", -6.3, 60.4, 0.7],
			["prop_crate", -6.6, 61.4, -0.3],
			["prop_zaru", -6.1, 48.6, 0.2],
			["prop_taru", -6.5, 47.6, 1.2],
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
			"市荷_%s_%d" % [String(spec[0]), int(float(spec[2]))])
	made.append("市場の幟と木戸")

	for index in 4:
		var z := 96.5 + float(index) * 4.4
		var hedge := MeshInstance3D.new()
		hedge.mesh = lib.prop_mesh(
			"res://assets/models/hedge_a.glb", lib.vc_mat())
		hedge.position = Vector3(6.6, float(height_fn.call(6.6, z)), z)
		hedge.rotation.y = PI * 0.5
		lib.add(group, hedge, "生垣_%d" % index)
	made.append("湯屋前の生垣")

	var trees := [
		["tree_round_a", -6.3, -70.0, 1.30, 0.8],
		["tree_pine_a", 6.3, -43.0, 1.15, 2.1],
		["tree_sakura_a", -6.2, 26.0, 1.20, 4.0],
		["tree_round_c", 6.5, 61.0, 1.25, 5.3],
		["tree_sakura_b", -6.4, 120.0, 1.10, 0.4],
	]
	for spec in trees:
		var x := float(spec[1])
		var z := float(spec[2])
		if bool(reserved_fn.call(Vector2(x, z), 1.0)):
			continue
		var tree := MeshInstance3D.new()
		tree.mesh = tree_mesh_fn.call(
			"res://assets/models/%s.glb" % String(spec[0]))
		tree.position = Vector3(x, float(height_fn.call(x, z)), z)
		tree.rotation.y = float(spec[4])
		tree.scale = Vector3(
			float(spec[3]), float(spec[3]) * 1.05, float(spec[3]))
		lib.add(group, tree, "街路樹_%s" % String(spec[0]))
	made.append("街路樹 5 本")

	var cut_count: int = cut_grass_fn.call(footprints)
	audit.append(
		"本通の街並：%s（足元の草 %d 叢を除去）"
		% [", ".join(made), cut_count])
