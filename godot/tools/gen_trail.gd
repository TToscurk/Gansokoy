# 獸道・場景產生器（Godot 原生重做第二張）
#
#   godot --headless --path godot --script tools/gen_trail.gd
#
# 定調（使用者指示 + docs/border-vistas.md）：獸道是**森林裡的獸徑**，
# 不是峽谷 —— 沒有兩側高牆，玩家被密林包著走，路以外全是樹。
# 佈局沿用 web 版 trail.js：北=神社、西南=人里、東南=竹林、東北=太陽花田，
# 分岔點 (26,40)，傳送點座標與 meta.json 一致。
# 碰撞自理（root meta own_colliders）：web 版樹的碰撞位置跟新森林對不上。
extends SceneTree

const Lib := preload("res://tools/gen_lib.gd")

const OUT_DIR := "res://maps/trail/"
const HALF := 340.0
const FORK := Vector2(26.0, 40.0)
const PATH_SEGMENTS := [
	# 北臂：神社（順 web 版控制點）
	{ "width": 6.0, "pts": [[0.0, -300.0], [-10.0, -240.0], [16.0, -180.0], [-8.0, -120.0], [4.0, -44.0], [30.0, -6.0], [26.0, 40.0]] },
	# 西南臂：人里
	{ "width": 6.0, "pts": [[26.0, 40.0], [-2.0, 74.0], [-44.0, 108.0], [-88.0, 146.0], [-118.0, 190.0], [-150.0, 250.0]] },
	# 東南臂：竹林
	{ "width": 5.2, "pts": [[26.0, 40.0], [62.0, 78.0], [96.0, 112.0], [128.0, 152.0], [162.0, 198.0], [190.0, 250.0]] },
	# 東北臂：太陽花田（環線）
	{ "width": 4.6, "pts": [[26.0, 40.0], [72.0, 22.0], [112.0, -6.0], [148.0, -42.0], [196.0, -80.0], [246.0, -122.0]] },
]

var lib: Lib
var _noise_h: FastNoiseLite
var _n2: FastNoiseLite

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _path_info(x: float, z: float) -> Array:
	var p := Vector2(x, z)
	var edge := INF
	var mask := 0.0
	for seg in PATH_SEGMENTS:
		var pts: Array = seg.pts
		var w: float = seg.width
		for k in pts.size() - 1:
			var d := _seg_dist(p, Vector2(pts[k][0], pts[k][1]), Vector2(pts[k + 1][0], pts[k + 1][1]))
			edge = minf(edge, maxf(0.0, d - w * 0.5))
			mask = maxf(mask, 1.0 - smoothstep(w * 0.5 - 0.4, w * 0.5 + 1.4, d))
	return [edge, mask]

## 森林地面：整體起伏比香霖堂大一點（獸徑的顛簸感），路面壓平，無邊界坡牆
func height_at(x: float, z: float) -> float:
	var roll := _noise_h.get_noise_2d(x, z) * 3.2 + sin(x * 0.021) * 1.1 + sin(z * 0.017 + 0.8) * 1.0
	var ed: float = _path_info(x, z)[0]
	return roll * clampf((0.35 + ed / 12.0), 0.35, 1.0) + sin(x * 0.46 + z * 0.33) * 0.06

func mask_at(x: float, z: float) -> Color:
	var info := _path_info(x, z)
	var g2 := clampf(_n2.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	# 森林圖：離路愈遠林床愈濃（樹蔭下都是腐葉土）
	var ed: float = info[0]
	var forest_w := clampf(smoothstep(2.0, 16.0, ed) * 0.85 + g2 * 0.15, 0.0, 1.0)
	var macro := clampf(_noise_h.get_noise_2d(x * 0.4, z * 0.4) * 0.5 + 0.5, 0.0, 1.0)
	return Color(info[1], forest_w, macro)

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "gen"))
	_noise_h = FastNoiseLite.new()
	_noise_h.frequency = 0.013
	_noise_h.fractal_octaves = 3
	_noise_h.seed = 240

	_n2 = FastNoiseLite.new()
	_n2.frequency = 0.021
	_n2.seed = 31

	var root := Node3D.new()
	root.name = "Trail"
	# 這張圖的碰撞自理（樹的位置是新生成的，web 版碰撞箱對不上）
	root.set_meta("own_colliders", true)
	lib = Lib.new()
	lib.setup(root, 20240817)

	lib.terrain(OUT_DIR, HALF, 171, height_at, mask_at)
	lib.boundary(HALF - 2.0)
	_build_forest()
	_build_fork_landmark()
	_build_grass()
	# 遠景（border-vistas.md）：西北 = 妖怪之山主峰、東北 = 神社東山
	lib.vista(OUT_DIR, HALF, 1000.0, height_at, [
		{ "x": -620.0, "z": -620.0, "h": 150.0, "r": 260.0 },   # 妖怪之山
		{ "x": 520.0, "z": -560.0, "h": 60.0, "r": 200.0 },     # 神社東山
	], "res://assets/models/tree_round_b.glb", 380)
	_build_env()

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT_DIR + "trail.tscn")
	print("saved trail.tscn err=", err)
	quit()

func _build_forest() -> void:
	var variants := []
	for glb in Lib.TREE_GLBS:
		variants.append({ "mesh": lib.tree_mesh(glb), "list": [] })
	var trunks: Array[Vector3] = []       # 近路樹要碰撞
	var count := 0
	var tries := 0
	while count < 9000 and tries < 260000:
		tries += 1
		var x := lib.rr(-HALF + 3.0, HALF - 3.0)
		var z := lib.rr(-HALF + 3.0, HALF - 3.0)
		var info := _path_info(x, z)
		var ed: float = info[0]
		if ed < 3.2:
			continue
		if Vector2(x, z).distance_to(FORK) < 16.0:      # 分岔點空地
			continue
		# 密度：路邊高、深處略稀（給獸徑一種「森林被路劈開」的擠壓感）
		var p := 0.95 if ed < 30.0 else 0.8
		if lib.rand() > p:
			continue
		var y := height_at(x, z)
		var s := lib.rr(1.05, 2.0)
		var basis := Basis(Vector3.UP, lib.rand() * TAU).scaled(Vector3(s, s * lib.rr(0.9, 1.25), s))
		var r := lib.rand()
		var vi := 0 if r < 0.34 else (1 if r < 0.62 else (2 if r < 0.78 else (3 if r < 0.92 else 4)))
		variants[vi].list.append(Transform3D(basis, Vector3(x, y, z)))
		if ed < 14.0:
			trunks.append(Vector3(x, y, z))
		count += 1

	var forest := lib.add(lib.root, Node3D.new(), "Forest")
	for i in variants.size():
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(variants[i].mesh, variants[i].list, [],
			OUT_DIR + "gen/trees_%d.res" % i)
		lib.add(forest, mmi, "Trees%d" % i)

	# 近路樹幹碰撞（走在路上撞得到的那些才給實體）
	var body := StaticBody3D.new()
	lib.add(lib.root, body, "TrunkColliders")
	for t in trunks:
		var shape := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = 0.42
		c.height = 6.0
		shape.shape = c
		shape.position = t + Vector3(0, 3, 0)
		body.add_child(shape)
		shape.owner = lib.root
	print("forest: ", count, " trees（", trunks.size(), " 根近路樹幹有碰撞）")

## 分岔點：一座苔石道標 + 幾顆立石 —— 全圖唯一的人工物，迷路時的錨點
func _build_fork_landmark() -> void:
	var g := Node3D.new()
	var y := height_at(FORK.x, FORK.y)
	g.position = Vector3(FORK.x, y, FORK.y)
	lib.add(lib.root, g, "ForkMarker")
	var stone := lib.pbr("stone", "stone_wall", 0.30)
	var dark := lib.pbr("dark_wood", "dark_wood", 0.45)
	lib.box(g, "道標柱", Vector3(0.5, 2.2, 0.5), stone, Vector3(0, 1.1, 0))
	lib.box(g, "道標冠", Vector3(0.7, 0.22, 0.7), stone, Vector3(0, 2.3, 0))
	for i in 4:
		var a := float(i) / 4.0 * TAU + 0.5
		lib.box(g, "臂板_%d" % i, Vector3(1.3, 0.18, 0.06), dark,
			Vector3(cos(a) * 0.8, 1.5 + 0.14 * float(i), sin(a) * 0.8)).rotation.y = -a
	for i in 5:
		var a2 := lib.rr(0.0, TAU)
		var d := lib.rr(1.4, 2.6)
		var s := lib.rr(0.25, 0.55)
		lib.box(g, "立石_%d" % i, Vector3(s, s * 1.4, s * 0.8), stone,
			Vector3(cos(a2) * d, s * 0.5, sin(a2) * d)).rotation.y = lib.rr(0.0, TAU)
	# 道標周圍擋一圈（web 版 post 的等價物）
	var body := StaticBody3D.new()
	g.add_child(body)
	body.owner = lib.root
	var shape := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = 1.0
	c.height = 3.0
	shape.shape = c
	shape.position = Vector3(0, 1.5, 0)
	body.add_child(shape)
	shape.owner = lib.root

func _build_grass() -> void:
	var tall := lib.tuft_mesh(7, 0.40, 0.20, Color(0.13, 0.22, 0.08), Color(0.38, 0.50, 0.20))
	tall.surface_set_material(0, lib.grass_wind_mat(0.10))
	var short := lib.tuft_mesh(5, 0.22, 0.28, Color(0.15, 0.24, 0.10), Color(0.33, 0.44, 0.18))
	short.surface_set_material(0, lib.grass_wind_mat(0.06))
	var flower := lib.tuft_mesh(5, 0.34, 0.16, Color(0.14, 0.23, 0.09), Color(0.36, 0.48, 0.20), true)
	flower.surface_set_material(0, lib.grass_wind_mat(0.08))
	var groups := [
		{ "mesh": tall, "n": 2200, "near": 0.85, "far": 0.1, "file": "grass_tall" },
		{ "mesh": short, "n": 1600, "near": 0.6, "far": 0.15, "file": "grass_short" },
		{ "mesh": flower, "n": 260, "near": 0.22, "far": 0.03, "file": "grass_flower" },
	]
	var total := 0
	for grp in groups:
		var list: Array[Transform3D] = []
		var tries := 0
		while list.size() < int(grp.n) and tries < int(grp.n) * 30:
			tries += 1
			var x := lib.rr(-HALF + 4.0, HALF - 4.0)
			var z := lib.rr(-HALF + 4.0, HALF - 4.0)
			var ed: float = _path_info(x, z)[0]
			if ed < 0.4:
				continue
			# 草長在路緣與分岔空地 —— 密林深處交給林床
			if lib.rand() > (float(grp.near) if ed < 5.0 else float(grp.far)):
				continue
			var s := lib.rr(0.7, 1.6)
			var basis := Basis(Vector3.UP, lib.rand() * TAU).scaled(Vector3(s, s, s))
			list.append(Transform3D(basis, Vector3(x, height_at(x, z), z)))
		total += list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(grp.mesh, list, [], OUT_DIR + "gen/" + String(grp.file) + ".res")
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(lib.root, mmi, String(grp.file).capitalize().replace(" ", ""))
	print("grass: ", total)

func _build_env() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.33, 0.5, 0.78)
	sky_mat.sky_horizon_color = Color(0.8, 0.8, 0.72)
	sky_mat.ground_horizon_color = Color(0.68, 0.68, 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.75, 0.68)
	env.fog_density = 0.0035         # 樹海要一點霧的縱深
	env.fog_sky_affect = 0.2
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.sdfgi_enabled = true
	env.ssao_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.018
	env.volumetric_fog_albedo = Color(0.8, 0.83, 0.76)
	var we := WorldEnvironment.new()
	we.environment = env
	lib.add(lib.root, we, "WorldEnvironment")
