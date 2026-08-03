# 人間之里・場景產生器（Godot 原生重做第三張）
#
#   godot --headless --path godot --script tools/gen_village.gd
#
# 幻想鄉最大的人類聚落：十字街廓 + 町屋群 + 市集 + 外圍田野。
# 北門通獸道、西南門通香霖堂（傳送點座標照 meta.json：(0,-174)、(-132,100)）。
# 佈局是新設計（碰撞自理 own_colliders），精神沿用 web 版：十字大街、
# 街屋夾道、南與東南是田。
extends SceneTree

const Lib := preload("res://tools/gen_lib.gd")

const OUT_DIR := "res://maps/village/"
const HALF := 230.0
const CROSS := Vector2(0.0, 20.0)          # 十字路口
# 街道（用地形 shader 的 path 層畫在地上）
const PATH_SEGMENTS := [
	{ "width": 8.0, "pts": [[0.0, -174.0], [0.0, -100.0], [0.0, 20.0], [0.0, 120.0], [0.0, 190.0]] },   # 南北大街
	{ "width": 7.0, "pts": [[-170.0, 20.0], [-80.0, 20.0], [0.0, 20.0], [90.0, 20.0], [180.0, 20.0]] }, # 東西大街
	{ "width": 5.0, "pts": [[-132.0, 100.0], [-100.0, 72.0], [-60.0, 44.0], [0.0, 20.0]] },             # 西南門引道（香霖堂）
]

var lib: Lib
var _nh: FastNoiseLite
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
			mask = maxf(mask, 1.0 - smoothstep(w * 0.5 - 0.4, w * 0.5 + 1.6, d))
	return [edge, mask]

## 里的地勢：聚落中心整過地（近乎全平），外圍才有起伏
func height_at(x: float, z: float) -> float:
	var roll := _nh.get_noise_2d(x, z) * 2.2
	var town := smoothstep(90.0, 190.0, Vector2(x, z).distance_to(CROSS))
	return roll * (0.12 + 0.88 * town) + sin(x * 0.46 + z * 0.33) * 0.04

## 田（南＋東南外圍的矩形田塊，遮罩用 G=林床層畫成翻過的土）
func _field_w(x: float, z: float) -> float:
	var w := 0.0
	for f in [[-40.0, 120.0, 150.0, 210.0], [60.0, 130.0, 200.0, 200.0], [-190.0, -60.0, 120.0, 200.0]]:
		if x > f[0] and x < f[2] and z > f[1] and z < f[3]:
			# 田埂：每 7 公尺留一條走道
			var row := fmod(absf(z - f[1]), 7.0)
			w = maxf(w, 0.85 if row > 1.2 else 0.15)
	return w

func mask_at(x: float, z: float) -> Color:
	var info := _path_info(x, z)
	var g2 := clampf(_n2.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var soil := maxf(_field_w(x, z), g2 * 0.12)
	var macro := clampf(_nh.get_noise_2d(x * 0.4, z * 0.4) * 0.5 + 0.5, 0.0, 1.0)
	return Color(info[1], soil, macro)

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "gen"))
	_nh = FastNoiseLite.new()
	_nh.frequency = 0.011
	_nh.seed = 500
	_n2 = FastNoiseLite.new()
	_n2.frequency = 0.03
	_n2.seed = 77

	var root := Node3D.new()
	root.name = "Village"
	root.set_meta("own_colliders", true)
	lib = Lib.new()
	lib.setup(root, 20240901)

	lib.terrain(OUT_DIR, HALF, 161, height_at, mask_at)
	lib.boundary(HALF - 2.0)
	_build_houses()
	_build_market()
	_build_gates()
	_build_lamps()
	_build_trees()
	_build_grass()
	lib.vista(OUT_DIR, HALF, 800.0, height_at, [
		{ "x": -520.0, "z": -560.0, "h": 140.0, "r": 240.0 },   # 妖怪之山（西北）
		{ "x": 480.0, "z": -420.0, "h": 55.0, "r": 180.0 },     # 神社東山（東北）
	], "res://assets/models/tree_round_b.glb", 320)
	_build_env()

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT_DIR + "village.tscn")
	print("saved village.tscn err=", err)
	quit()

# ── 町屋：灰泥牆身 + 深色木樑柱 + 和瓦切妻頂；每棟自帶碰撞 ──
func _house(parent: Node, name: String, pos: Vector3, w: float, d: float, h: float, yaw: float) -> void:
	var plaster := lib.pbr("plaster", "plaster", 0.4)
	var dark := lib.pbr("dark_wood", "dark_wood", 0.45)
	var kawara := lib.pbr("kawara", "roof_kawara", 0.22, Color(0.85, 0.88, 0.95))
	var stone := lib.pbr("stone", "stone_wall", 0.30)
	var g := Node3D.new()
	g.position = pos
	g.rotation.y = yaw
	lib.add(parent, g, name)
	lib.box(g, "基石", Vector3(w + 0.6, 0.35, d + 0.6), stone, Vector3(0, 0.17, 0))
	lib.box(g, "屋身", Vector3(w, h, d), plaster, Vector3(0, 0.35 + h / 2.0, 0))
	# 木構線（柱與腰帶）
	for s in [-1, 1]:
		lib.box(g, "柱_%d" % (s + 1), Vector3(0.22, h, 0.24), dark, Vector3(s * (w / 2.0 - 0.2), 0.35 + h / 2.0, d / 2.0 + 0.02))
	lib.box(g, "腰帶", Vector3(w + 0.05, 0.18, 0.1), dark, Vector3(0, 0.35 + h * 0.55, d / 2.0 + 0.06))
	lib.box(g, "門", Vector3(1.4, 2.0, 0.12), dark, Vector3(lib.rr(-w * 0.2, w * 0.2), 1.35, d / 2.0 + 0.05))
	# 切妻瓦頂：兩片斜坡 + 屋脊
	var rw := w + 1.2
	var rd := d + 1.4
	for s in [-1, 1]:
		var slope := lib.box(g, "屋頂坡_%d" % (s + 1), Vector3(rw, 0.22, rd * 0.62), kawara,
			Vector3(0, 0.35 + h + 0.95, s * rd * 0.21))
		slope.rotation.x = s * 0.62
	lib.box(g, "屋脊", Vector3(rw + 0.3, 0.26, 0.7), kawara, Vector3(0, 0.35 + h + 1.72, 0))
	# 碰撞：一顆屋身大小的箱子
	var body := StaticBody3D.new()
	g.add_child(body)
	body.owner = lib.root
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(w + 0.6, h + 2.6, d + 0.6)
	shape.shape = bx
	shape.position = Vector3(0, (h + 2.6) / 2.0, 0)
	body.add_child(shape)
	shape.owner = lib.root

func _build_houses() -> void:
	var houses := lib.add(lib.root, Node3D.new(), "Houses")
	var idx := 0
	# 沿南北大街與東西大街的兩側排屋（跳過路口一圈）
	var slots := []
	for z in [-150.0, -120.0, -90.0, -62.0, 62.0, 92.0, 122.0, 152.0]:
		for sx in [-1, 1]:
			slots.append({ "pos": Vector2(sx * lib.rr(9.5, 12.5), z + lib.rr(-3, 3)), "yaw": PI / 2.0 * sx + PI / 2.0 })
	for x in [-150.0, -118.0, -86.0, -54.0, 54.0, 86.0, 118.0, 150.0]:
		for sz in [-1, 1]:
			slots.append({ "pos": Vector2(x + lib.rr(-3, 3), 20.0 + sz * lib.rr(9.5, 13.0)), "yaw": 0.0 if sz > 0 else PI })
	# 巷內第二排（稀一點）
	for i in 10:
		var a := lib.rr(0.0, TAU)
		var d := lib.rr(34.0, 70.0)
		var p := Vector2(CROSS.x + cos(a) * d, CROSS.y + sin(a) * d * 0.8)
		if _path_info(p.x, p.y)[0] < 6.0:
			continue
		slots.append({ "pos": p, "yaw": lib.rr(0.0, TAU) })
	for s in slots:
		idx += 1
		var p: Vector2 = s.pos
		var w := lib.rr(5.5, 8.5)
		var d := lib.rr(4.5, 6.5)
		var h := lib.rr(2.6, 3.2)
		_house(houses, "町屋_%02d" % idx, Vector3(p.x, height_at(p.x, p.y), p.y), w, d, h, s.yaw)
	print("houses: ", idx)

# ── 市集：路口東側的攤位群（棚布 + 木架 + 貨箱） ──
func _build_market() -> void:
	var market := lib.add(lib.root, Node3D.new(), "Market")
	var wood := lib.pbr("wood", "planks", 0.5, Color(0.9, 0.82, 0.72))
	var cloths := [Color(0.62, 0.3, 0.26), Color(0.28, 0.36, 0.52), Color(0.72, 0.6, 0.3), Color(0.34, 0.46, 0.32)]
	for i in 6:
		var px := 16.0 + float(i % 3) * 7.0 + lib.rr(-1, 1)
		var pz := 34.0 + float(i / 3) * 9.0 + lib.rr(-1, 1)
		var y := height_at(px, pz)
		var g := Node3D.new()
		g.position = Vector3(px, y, pz)
		g.rotation.y = lib.rr(-0.2, 0.2)
		lib.add(market, g, "攤_%d" % i)
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				lib.cyl(g, "腳_%d%d" % [sx + 1, sz + 1], 0.05, 0.05, 2.2, wood, Vector3(sx * 1.3, 1.1, sz * 0.9), 6)
		lib.box(g, "檯面", Vector3(2.8, 0.12, 1.9), wood, Vector3(0, 0.95, 0))
		var cloth_m := StandardMaterial3D.new()
		cloth_m.albedo_color = cloths[i % cloths.size()]
		cloth_m.roughness = 1.0
		var top := lib.box(g, "棚布", Vector3(3.2, 0.08, 2.4), cloth_m, Vector3(0, 2.35, -0.2))
		top.rotation.x = 0.16
		lib.box(g, "貨箱", Vector3(0.8, 0.5, 0.6), wood, Vector3(lib.rr(-1, 1), 0.25, 1.4))
		var body := StaticBody3D.new()
		g.add_child(body)
		body.owner = lib.root
		var shape := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(3.2, 2.4, 2.4)
		shape.shape = bx
		shape.position = Vector3(0, 1.2, 0)
		body.add_child(shape)
		shape.owner = lib.root

# ── 門：北門（獸道）與西南門（香霖堂）—— 兩柱一樑的木門 ──
func _build_gates() -> void:
	var dark := lib.pbr("dark_wood", "dark_wood", 0.45)
	var kawara := lib.pbr("kawara", "roof_kawara", 0.22, Color(0.85, 0.88, 0.95))
	var defs := [
		{ "name": "北門", "x": 0.0, "z": -166.0, "yaw": 0.0 },
		{ "name": "西南門", "x": -126.0, "z": 95.0, "yaw": 0.72 },
	]
	for d in defs:
		var g := Node3D.new()
		g.position = Vector3(d.x, height_at(d.x, d.z), d.z)
		g.rotation.y = d.yaw
		lib.add(lib.root, g, d.name)
		for s in [-1, 1]:
			lib.box(g, "柱_%d" % (s + 1), Vector3(0.6, 4.6, 0.6), dark, Vector3(s * 4.2, 2.3, 0))
		lib.box(g, "樑", Vector3(10.0, 0.5, 0.8), dark, Vector3(0, 4.6, 0))
		lib.box(g, "簷", Vector3(11.0, 0.2, 1.6), kawara, Vector3(0, 5.05, 0))
		for s in [-1, 1]:
			var body := StaticBody3D.new()
			g.add_child(body)
			body.owner = lib.root
			var shape := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(0.8, 5.0, 0.8)
			shape.shape = bx
			shape.position = Vector3(s * 4.2, 2.5, 0)
			body.add_child(shape)
			shape.owner = lib.root

func _build_lamps() -> void:
	var iron := lib.flat_mat("iron", Color(0.16, 0.16, 0.18), 0.6)
	var glow := lib.flat_mat("lamp_glow", Color(1.0, 0.85, 0.55), 0.3, Color(1.0, 0.75, 0.4))
	var lamps := lib.add(lib.root, Node3D.new(), "Lamps")
	var idx := 0
	for z in [-140.0, -70.0, 90.0, 160.0]:
		for sx in [-1, 1]:
			idx += 1
			var x := float(sx) * 6.5
			var lamp := Node3D.new()
			lamp.position = Vector3(x, height_at(x, z), z)
			lib.add(lamps, lamp, "街燈_%d" % idx)
			lib.cyl(lamp, "柱", 0.055, 0.075, 3.4, iron, Vector3(0, 1.7, 0), 8)
			lib.box(lamp, "燈頭", Vector3(0.42, 0.5, 0.42), glow, Vector3(0, 3.55, 0))
			lib.box(lamp, "燈帽", Vector3(0.56, 0.1, 0.56), iron, Vector3(0, 3.85, 0))
			var li := OmniLight3D.new()
			li.position = Vector3(0, 3.5, 0)
			li.light_color = Color(1.0, 0.78, 0.5)
			li.light_energy = 1.3
			li.omni_range = 9.0
			li.shadow_enabled = false
			lib.add(lamp, li, "光")
	for x in [-120.0, -60.0, 60.0, 130.0]:
		for sz in [-1, 1]:
			idx += 1
			var z2 := 20.0 + float(sz) * 6.0
			var lamp := Node3D.new()
			lamp.position = Vector3(x, height_at(x, z2), z2)
			lib.add(lamps, lamp, "街燈_%d" % idx)
			lib.cyl(lamp, "柱", 0.055, 0.075, 3.4, iron, Vector3(0, 1.7, 0), 8)
			lib.box(lamp, "燈頭", Vector3(0.42, 0.5, 0.42), glow, Vector3(0, 3.55, 0))
			lib.box(lamp, "燈帽", Vector3(0.56, 0.1, 0.56), iron, Vector3(0, 3.85, 0))
			var li := OmniLight3D.new()
			li.position = Vector3(0, 3.5, 0)
			li.light_color = Color(1.0, 0.78, 0.5)
			li.light_energy = 1.3
			li.omni_range = 9.0
			li.shadow_enabled = false
			lib.add(lamp, li, "光")

# ── 里內外的樹：聚落裡零星、外圍漸密（銜接周邊的世界） ──
func _build_trees() -> void:
	var variants := []
	for glb in Lib.TREE_GLBS:
		variants.append({ "mesh": lib.tree_mesh(glb), "list": [] })
	var count := 0
	var tries := 0
	while count < 900 and tries < 40000:
		tries += 1
		var x := lib.rr(-HALF + 3.0, HALF - 3.0)
		var z := lib.rr(-HALF + 3.0, HALF - 3.0)
		if _path_info(x, z)[0] < 4.0:
			continue
		if _field_w(x, z) > 0.2:
			continue
		var town := Vector2(x, z).distance_to(CROSS)
		var p := 0.06 if town < 90.0 else (0.25 if town < 150.0 else 0.7)
		if lib.rand() > p:
			continue
		var y := height_at(x, z)
		var s := lib.rr(0.9, 1.7)
		var basis := Basis(Vector3.UP, lib.rand() * TAU).scaled(Vector3(s, s * lib.rr(0.9, 1.2), s))
		var r := lib.rand()
		var vi := 0 if r < 0.4 else (1 if r < 0.7 else (2 if r < 0.85 else (3 if r < 0.95 else 4)))
		variants[vi].list.append(Transform3D(basis, Vector3(x, y, z)))
		count += 1
	var forest := lib.add(lib.root, Node3D.new(), "Trees")
	for i in variants.size():
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(variants[i].mesh, variants[i].list, [],
			OUT_DIR + "gen/trees_%d.res" % i)
		lib.add(forest, mmi, "Trees%d" % i)
	print("trees: ", count)

func _build_grass() -> void:
	var tall := lib.tuft_mesh(7, 0.40, 0.20, Color(0.13, 0.22, 0.08), Color(0.38, 0.50, 0.20))
	tall.surface_set_material(0, lib.grass_wind_mat(0.10))
	var flower := lib.tuft_mesh(5, 0.34, 0.16, Color(0.14, 0.23, 0.09), Color(0.36, 0.48, 0.20), true)
	flower.surface_set_material(0, lib.grass_wind_mat(0.08))
	# 稻苗：田裡整齊的行列（田的翻土遮罩上一排排綠苗）
	var rice := lib.tuft_mesh(5, 0.3, 0.1, Color(0.2, 0.34, 0.12), Color(0.45, 0.62, 0.22))
	rice.surface_set_material(0, lib.grass_wind_mat(0.07))

	var groups := [
		{ "mesh": tall, "n": 1400, "file": "grass_tall", "mode": "wild" },
		{ "mesh": flower, "n": 200, "file": "grass_flower", "mode": "wild" },
		{ "mesh": rice, "n": 2400, "file": "rice_rows", "mode": "field" },
	]
	var total := 0
	for grp in groups:
		var list: Array[Transform3D] = []
		var tries := 0
		var target: int = grp.n
		while list.size() < target and tries < target * 40:
			tries += 1
			var x := lib.rr(-HALF + 4.0, HALF - 4.0)
			var z := lib.rr(-HALF + 4.0, HALF - 4.0)
			if String(grp.mode) == "field":
				if _field_w(x, z) < 0.5:
					continue
				# 對齊行列：吸附到 1.4m 網格
				x = snappedf(x, 1.4) + lib.rr(-0.12, 0.12)
				z = snappedf(z, 1.4) + lib.rr(-0.12, 0.12)
			else:
				if _path_info(x, z)[0] < 0.5 or _field_w(x, z) > 0.2:
					continue
				var town := Vector2(x, z).distance_to(CROSS)
				if lib.rand() > (0.15 if town < 90.0 else 0.6):
					continue
			var s := lib.rr(0.7, 1.4)
			var basis := Basis(Vector3.UP, lib.rand() * TAU).scaled(Vector3(s, s, s))
			list.append(Transform3D(basis, Vector3(x, height_at(x, z), z)))
		total += list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(grp.mesh, list, [], OUT_DIR + "gen/" + String(grp.file) + ".res")
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(lib.root, mmi, String(grp.file).capitalize().replace(" ", ""))
	print("grass+rice: ", total)

func _build_env() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.54, 0.82)
	sky_mat.sky_horizon_color = Color(0.84, 0.83, 0.74)
	sky_mat.ground_horizon_color = Color(0.72, 0.7, 0.62)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.78, 0.7)
	env.fog_density = 0.0014        # 里是開闊地，霧最薄
	env.fog_sky_affect = 0.2
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.05
	env.sdfgi_enabled = true
	env.ssao_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.84, 0.85, 0.78)
	var we := WorldEnvironment.new()
	we.environment = env
	lib.add(lib.root, we, "WorldEnvironment")
