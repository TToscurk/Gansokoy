extends SceneTree
## 博麗神社 r3 場景組裝（總裝腳本）。每次從頭組出 maps/shrine_v2/shrine_v2.tscn。
##   python tools/shrine_v2/gen_terrain.py && python tools/shrine_v2/gen_placements.py
##   godot --headless --path godot --script res://tools/shrine_v2/build_terrain.gd
##   godot --headless --path godot --script res://tools/shrine_v2/build_scene.gd
## 本腳本不含 MultiMesh（headless 會存出零矩陣）；所有擺放都是獨立可選取的節點。
## 約定：x 東 / z 南(入口) / y 上；主軸 x=0；地面高一律用 S2.height_at()（＝網格實際高度）。

const S2 := preload("res://tools/shrine_v2/s2lib.gd")
const OUT := "res://maps/shrine_v2/shrine_v2.tscn"
const GEN := "res://maps/shrine_v2/gen/"
const KIT := "res://assets/shrine_v2/kit/"
const BLD := "res://assets/shrine_v2/bld/"
const PROPS := "res://assets/shrine_v2/props/"
const GK := "res://assets/village_v2/garden_kit/mesh/"
const TREES := "res://assets/village_v2/veg_kit/trees/"
const NAT := "res://assets/nature/"
const LP := "res://assets/lowpoly_scene/"

var sroot: Node3D
var L: Dictionary
var stats := {}
var _stone_mat: StandardMaterial3D


# ───────── 小工具 ─────────
func add(parent: Node, n: Node, nm := "") -> Node:
	if nm != "":
		n.name = nm
	parent.add_child(n)
	n.owner = sroot
	return n


func group(parent: Node, nm: String) -> Node3D:
	var g := Node3D.new()
	return add(parent, g, nm) as Node3D


func gy(x: float, z: float) -> float:
	return S2.height_at(x, z)


func xf_of(pos: Vector3, yaw := 0.0, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(scl), pos)


func inst(parent: Node, path: String, nm: String, xf: Transform3D) -> Node3D:
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("載入失敗 " + path)
		return null
	var n := ps.instantiate() as Node3D
	n.name = nm
	n.transform = xf
	parent.add_child(n)
	n.owner = sroot
	return n


func mesh_node(parent: Node, mesh: Mesh, nm: String, xf: Transform3D, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	if mat != null:
		mi.material_override = mat
	return add(parent, mi, nm) as MeshInstance3D


func static_box(parent: StaticBody3D, nm: String, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = pos
	add(parent, cs, nm)


func place_building(parent: Node, wrapper: String, nm: String, x: float, z: float, yaw: float, sink := 0.04) -> Node3D:
	var ps := load(wrapper) as PackedScene
	var n := ps.instantiate() as Node3D
	var bpos: Vector3 = n.get_meta("aabb_pos", Vector3.ZERO)
	var y := gy(x, z) - bpos.y - sink
	n.name = nm
	n.transform = xf_of(Vector3(x, y, z), yaw)
	parent.add_child(n)
	n.owner = sroot
	return n


func _read_json(p: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(p))


# ───────── 地形、天空、邊界 ─────────
func make_terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/shrine_terrain.gdshader")
	m.set_shader_parameter("grass_diff", load("res://assets/textures/terrain_grass_diff.jpg"))
	m.set_shader_parameter("grass_nor", load("res://assets/textures/terrain_grass_nor_gl.jpg"))
	m.set_shader_parameter("forest_diff", load("res://assets/textures/terrain_forest_diff.jpg"))
	m.set_shader_parameter("forest_nor", load("res://assets/textures/terrain_forest_nor_gl.jpg"))
	m.set_shader_parameter("path_diff", load("res://assets/textures/terrain_path_diff.jpg"))
	m.set_shader_parameter("path_nor", load("res://assets/textures/terrain_path_nor_gl.jpg"))
	m.set_shader_parameter("dirt_diff", load("res://assets/textures/street_earth_diff.png"))
	m.set_shader_parameter("dirt_nor", load("res://assets/textures/terrain_path_nor_gl.jpg"))
	m.set_shader_parameter("dirt_amount", 1.0)
	m.set_shader_parameter("dirt_cover", 0.0)
	m.set_shader_parameter("dirt_tile", 0.9)
	m.set_shader_parameter("dirt_tint", Color(0.77, 0.72, 0.63))      # 夯土：暖灰褐。實測（截圖庭院取樣）初版 (203,180,152)、二版 (189,164,135) 仍亮 → 三版再降 ≈10%、飽和度降
	m.set_shader_parameter("dirt_var", 0.28)                          # 夯土 2–5 m 尺度的明暗（−28%…+15%）與潮濕斑
	m.set_shader_parameter("path_tint", Color(1.45, 1.55, 1.59))      # 參道碎石土：貼圖原色過黑（亮度 0.22）→ 提到 ≈ 夯土略深
	m.set_shader_parameter("dirt_base_color", Color(0.451, 0.378, 0.287))   # = 貼圖平均色（線性空間算過）經去飽和與 dirt_tint 後的 sRGB
	m.set_shader_parameter("dirt_texture_strength", 0.62)             # 細紋理對比壓到 62%（審圖：細碎紋理比公尺級變化搶眼）
	m.set_shader_parameter("dirt_normal_strength", 0.35)
	m.set_shader_parameter("dirt_raw_texture", 0.0)
	m.set_shader_parameter("mask_tex", load(GEN + "ground_mask.res"))
	m.set_shader_parameter("tile", 0.12)
	m.set_shader_parameter("path_tile", 2.2)
	m.set_shader_parameter("forest_tile", 1.4)
	m.set_shader_parameter("grass_tint", Color(0.66, 0.72, 0.50))
	# 落花：細碎花瓣點，密度來自 gen_placements 的 petal_mask（櫻花樹下＋庭院零星）
	var pr: Dictionary = _read_json(GEN + "placements.json")["petal"]
	m.set_shader_parameter("petal_mask", load(GEN + "petal_mask.res"))
	m.set_shader_parameter("petal_rect", Vector4(float(pr["x0"]), float(pr["z0"]), float(pr["w"]), float(pr["d"])))
	m.set_shader_parameter("petal_amount", 1.0)
	# 玩家範圍外 → 林冠質感（與 Vista_A 同貼圖同尺度），近景邊緣與外圍山體無接縫
	var pl: Dictionary = _read_json(GEN + "layout.json")["play"]
	m.set_shader_parameter("canopy_tex", load(GEN + "canopy_far.res"))
	m.set_shader_parameter("canopy_tile", 0.0045)
	m.set_shader_parameter("canopy_play", Vector4(float(pl["x0"]), float(pl["z0"]), float(pl["x1"]), float(pl["z1"])))
	m.set_shader_parameter("canopy_fade", Vector2(2.0, 22.0))
	m.set_shader_parameter("canopy_amount", 1.0)
	return m


## 中景／遠景：林冠質感地面（shrine_vista.gdshader）＋低解析度雜訊遮罩（森林密度、明暗）。
## 近景範圍外沒有真的樹；舊版用地形 shader 的草／林床貼圖，俯視時像光禿草坡、與近景密林斷層。
func make_vista_material(mask_path: String, tile: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/shrine_vista.gdshader")
	m.set_shader_parameter("canopy", load(GEN + "canopy_far.res"))
	m.set_shader_parameter("mask_tex", load(mask_path))
	m.set_shader_parameter("tile", tile)
	return m


func add_terrain() -> void:
	var t := MeshInstance3D.new()
	t.mesh = load(GEN + "terrain.res")
	t.material_override = make_terrain_material()
	add(sroot, t, "Terrain")
	# 遠景：中景（±260 m、4 m 格）＋遠景（±1100 m、20 m 格）。近景範圍內已在 gen_terrain 壓低；
	# 邊緣高度與近景網格連續。材質＝近景同一支 shader（遮罩改雜訊）。
	var va := MeshInstance3D.new()
	va.mesh = load(GEN + "vista_a.res")
	va.material_override = make_vista_material(GEN + "vista_a_mask.res", 0.0045)
	va.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add(sroot, va, "Vista_A")
	var vb := MeshInstance3D.new()
	vb.mesh = load(GEN + "vista_b.res")
	vb.material_override = make_vista_material(GEN + "vista_b_mask.res", 0.0032)
	vb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add(sroot, vb, "Vista_B")


func add_sky() -> void:
	var n := inst(sroot, GEN + "sky_rig.tscn", "天象系統", Transform3D.IDENTITY)
	stats["sky"] = n != null


func add_boundary() -> void:
	var p: Dictionary = L["play"]
	var x0 := float(p["x0"])
	var x1 := float(p["x1"])
	var z0 := float(p["z0"])
	var z1 := float(p["z1"])
	var body := StaticBody3D.new()
	add(sroot, body, "Boundary")
	var W := x1 - x0
	var D := z1 - z0
	var th := 4.0
	var hh := 120.0
	var specs := [
		["北牆", Vector3(0, 0, z0 - th * 0.5), Vector3(W + th * 2.0, hh, th)],
		["南牆", Vector3(0, 0, z1 + th * 0.5), Vector3(W + th * 2.0, hh, th)],
		["西牆", Vector3(x0 - th * 0.5, 0, (z0 + z1) * 0.5), Vector3(th, hh, D)],
		["東牆", Vector3(x1 + th * 0.5, 0, (z0 + z1) * 0.5), Vector3(th, hh, D)],
	]
	for s in specs:
		static_box(body, s[0], s[2], Vector3(s[1].x, 40.0, s[1].z))


# ───────── 石階 ─────────
func stair_plan() -> Dictionary:
	var st: Dictionary = L["stair"]
	var rise := float(st["rise"])
	var run := float(st["run"])
	var landing := float(st["landing"])
	var z := float(st["z_foot"])
	var flights: Array = st["flights"]
	var treads: Array = []
	var landings: Array = []
	var k := 0
	for f in flights.size():
		for i in int(flights[f]):
			treads.append({"k": k, "flight": f, "zc": z - run * 0.5, "y_top": rise * (k + 1)})
			z -= run
			k += 1
		if f < flights.size() - 1:
			landings.append({"zc": z - landing * 0.5, "y": rise * k})
			z -= landing
	return {"treads": treads, "landings": landings, "z_end": z}


func add_stairs() -> void:
	var sp := stair_plan()
	var tread_m := load(KIT + "tread.res") as Mesh
	var land_m := load(KIT + "landing.res") as Mesh
	var sleeve_m := load(KIT + "sleeve.res") as Mesh
	var cap_m := load(KIT + "cap.res") as Mesh
	var fill_mat: Material = load("res://assets/shrine_v2/mat/stone_foot.tres")
	var g := group(sroot, "參道石階")
	var gt := group(g, "踏石")
	var gs := group(g, "袖石垣")
	var gf := group(g, "填塊")
	var body := StaticBody3D.new()
	add(g, body, "石階碰撞")
	var rise: float = float(L["stair"]["rise"])
	var run: float = float(L["stair"]["run"])
	var treads: Array = sp["treads"]
	for t in treads:
		var k: int = t["k"]
		var zc: float = t["zc"]
		var yt: float = t["y_top"]
		var even := k % 2 == 0
		var xl := -0.74 if even else -0.86
		var xr := 0.86 if even else 0.74
		var s := Vector3(0.845, 0.776, 1.237)
		mesh_node(gt, tread_m, "踏石_%02d_L" % k, xf_of(Vector3(xl, yt - 0.0737, zc), 0.0, s))
		mesh_node(gt, tread_m, "踏石_%02d_R" % k, xf_of(Vector3(xr, yt - 0.0737, zc), 0.0, s))
		for sx in [-1, 1]:
			var ss := Vector3(0.2367, 0.7594, 0.9068)
			mesh_node(gs, sleeve_m, "袖石_%02d_%s" % [k, "L" if sx < 0 else "R"],
				xf_of(Vector3(sx * 1.825, yt - 0.0265, zc), 0.0, ss))
		# 實心填塊：從踏石底面往下 0.7 m，免得踏石下露出空隙
		var fb := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(3.2, 0.7, run - 0.004)
		fb.mesh = bm
		fb.material_override = fill_mat
		fb.position = Vector3(0, yt - rise - 0.35, zc)
		add(gf, fb, "填塊_%02d" % k)
		static_box(body, "階_%02d" % k, Vector3(3.3, 0.86, run), Vector3(0, yt - 0.43, zc))
		static_box(body, "袖_%02d_L" % k, Vector3(0.45, 0.72, run), Vector3(-1.825, yt - 0.0265, zc))
		static_box(body, "袖_%02d_R" % k, Vector3(0.45, 0.72, run), Vector3(1.825, yt - 0.0265, zc))
	var lands: Array = sp["landings"]
	var li := 0
	for l in lands:
		var ls := Vector3(0.85, 0.6, 2.2 / 1.6123)
		var yl: float = l["y"]
		for sx in [-1, 1]:
			mesh_node(gt, land_m, "平台石_%d_%s" % [li, "L" if sx < 0 else "R"],
				xf_of(Vector3(sx * 0.80, yl - 0.0794, l["zc"]), 0.0, ls))
		var fb2 := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(3.2, 0.7, 2.2)
		fb2.mesh = bm2
		fb2.material_override = fill_mat
		fb2.position = Vector3(0, yl - rise - 0.35, l["zc"])
		add(gf, fb2, "平台填塊_%d" % li)
		static_box(body, "平台_%d" % li, Vector3(3.3, 0.86, 2.2), Vector3(0, yl - 0.43, l["zc"]))
		for sx in [-1, 1]:
			var segs := 5
			for q in segs:
				var zq: float = l["zc"] - 1.1 + 2.2 * (q + 0.5) / segs
				mesh_node(gs, sleeve_m, "平台袖_%d_%d_%s" % [li, q, "L" if sx < 0 else "R"],
					xf_of(Vector3(sx * 1.825, yl - 0.0265, zq), 0.0, Vector3(0.2367, 0.7594, 2.2 / segs / 0.419)))
			static_box(body, "平台袖_%d_%s" % [li, "L" if sx < 0 else "R"], Vector3(0.45, 0.72, 2.2), Vector3(sx * 1.825, yl - 0.0265, l["zc"]))
		li += 1
	# 收頭石：石階腳與石階頂
	var z_foot: float = float(L["stair"]["z_foot"])
	var z_end: float = sp["z_end"]
	for sx in [-1, 1]:
		var zf := z_foot + 0.30
		mesh_node(gt, cap_m, "收頭_南_%s" % ("L" if sx < 0 else "R"),
			xf_of(Vector3(sx * 0.8, gy(sx * 0.8, zf) + 0.03 - 0.0985, zf), 0.0, Vector3(0.84, 0.65, 1.025)))
		var zt := z_end - 0.27
		mesh_node(gt, cap_m, "收頭_北_%s" % ("L" if sx < 0 else "R"),
			xf_of(Vector3(sx * 0.8, float(L["y_c"]) + 0.03 - 0.0985, zt), 0.0, Vector3(0.84, 0.65, 1.025)))
	stats["tread_count"] = treads.size()


# ───────── 建築與境內物件 ─────────
func add_buildings() -> void:
	var g := group(sroot, "建築")
	var pl: Dictionary = L["place"]
	var h: Array = pl["haiden"]
	var t: Array = pl["torii"]
	var tm: Array = pl["temizuya"]
	var sh: Array = pl["storehouse"]
	place_building(g, BLD + "haiden.tscn", "拜殿", h[0], h[1], 0.0, 0.05)
	place_building(g, BLD + "torii.tscn", "博麗鳥居", t[0], t[1], 0.0, 0.06)
	place_building(g, BLD + "temizuya.tscn", "手水舍", tm[0], tm[1], PI * 0.5, 0.05)
	place_building(g, PROPS + "storehouse.tscn", "倉庫", sh[0], sh[1], 0.0, 0.03)
	var sa: Array = pl["saisen"]
	place_building(g, PROPS + "saisen_box.tscn", "賽錢箱", sa[0], sa[1], 0.0, 0.0)
	# 掃帚：靠在倉庫門東側的牆上
	var bn := place_building(g, PROPS + "broom.tscn", "掃帚", sh[0] + 1.72, sh[1] + 1.18, 0.4, 0.0)
	bn.rotation = Vector3(-0.17, 0.4, 0.0)
	bn.position.y += 0.02


func stone_material() -> StandardMaterial3D:
	if _stone_mat == null:
		_stone_mat = StandardMaterial3D.new()
		_stone_mat.albedo_color = Color(0.62, 0.60, 0.56)
		_stone_mat.albedo_texture = load("res://assets/textures/stone_wall_diff.jpg")
		_stone_mat.uv1_triplanar = true
		_stone_mat.uv1_scale = Vector3(0.9, 0.9, 0.9)
		_stone_mat.roughness = 0.95
	return _stone_mat


func _box_body(parent: Node, size: Vector3, center: Vector3) -> void:
	var sb := StaticBody3D.new()
	parent.add_child(sb)
	sb.owner = sroot
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = center
	sb.add_child(cs)
	cs.owner = sroot


func add_court_items() -> void:
	var g := group(sroot, "境內物件")
	# 石燈籠：拜殿前一對、鳥居旁（織部）、池畔（雪見）
	var kas := load(GK + "gk_toro_kasuga.res") as Mesh
	var ori := load(GK + "gk_toro_oribe.res") as Mesh
	var yuk := load(GK + "gk_toro_yukimi.res") as Mesh
	var spots := [
		["燈籠_春日_W", kas, -4.3, -19.0, 0.0, 1.0],
		["燈籠_春日_E", kas, 4.3, -19.0, 0.0, 1.0],
		["燈籠_織部", ori, -7.2, -6.2, 0.6, 1.0],
		["燈籠_雪見_池畔", yuk, 10.6, -31.2, 0.4, 1.0],
	]
	for s in spots:
		var m: Mesh = s[1]
		var bb := m.get_aabb()
		var y: float = gy(s[2], s[3]) - bb.position.y * float(s[5]) - 0.03
		var mi := mesh_node(g, m, s[0], xf_of(Vector3(s[2], y, s[3]), s[4], Vector3.ONE * float(s[5])))
		_box_body(mi, Vector3(minf(bb.size.x, 0.7), bb.size.y, minf(bb.size.z, 0.7)), bb.get_center())
	# 狛犬一對：中軸兩側（沿用 models/komainu_a 造型，風化石材質；build_props.gd 產出 komainu.tscn）
	for sx in [-1, 1]:
		var kn := place_building(g, PROPS + "komainu.tscn", "狛犬_%s" % ("吽" if sx < 0 else "阿"), float(sx) * 2.7, -12.6, 0.0, 0.04)
		kn.set_meta("pair", sx)
	# 倉庫旁的生活感：柴棚、柴堆、木箱、梯子、木桶
	var sh: Array = (L["place"] as Dictionary)["storehouse"]
	var life := [
		["柴棚", LP + "LogStorage.gltf", sh[0] - 3.4, sh[1] + 0.2, PI * 0.5, 1.0],
		["柴堆", LP + "Log_Cluster.gltf", sh[0] - 3.4, sh[1] + 0.2, PI * 0.5, 0.9],
		["木箱_1", LP + "WoodenBox.gltf", sh[0] + 2.6, sh[1] + 1.2, 0.3, 0.8],
		["木箱_2", LP + "WoodenBox.gltf", sh[0] + 3.6, sh[1] + 0.4, -0.2, 0.8],
		["梯子", LP + "Ladder.gltf", sh[0] + 2.40, sh[1] - 0.6, PI * 0.5, 1.0],
		["木桶", LP + "Barrel.gltf", sh[0] - 2.4, sh[1] + 1.55, 0.0, 0.55],
	]
	for it in life:
		var n := inst(g, it[1], it[0], xf_of(Vector3(it[2], gy(it[2], it[3]) - 0.03, it[3]), it[4], Vector3.ONE * it[5]))
		if it[0] == "梯子":
			n.rotation = Vector3(0.0, PI * 0.5, 0.0)
			n.rotate_object_local(Vector3(0, 0, 1), -0.2)
		elif n != null and it[0] != "柴堆":
			_aabb_body(n)         # 柴棚／木箱／木桶：實心障礙（柴堆與柴棚同位置，由柴棚的盒子涵蓋）
	# 陰陽玉（LEVEL 3 彩蛋，全圖僅此 1 顆）：池塘西岸的一塊扁石上
	var rock := load(GK + "gk_kei_flat.res") as Mesh
	var rb := rock.get_aabb()
	var rx := 4.6
	var rz := -37.4
	var ry := gy(rx, rz) - rb.position.y - 0.10
	var dai := mesh_node(g, rock, "陰陽玉台石", xf_of(Vector3(rx, ry, rz), 0.8))
	_convex_body(dai)
	var top := ry + rb.position.y + rb.size.y
	inst(g, BLD + "onmyoudama.tscn", "陰陽玉", xf_of(Vector3(rx + 0.05, top + 0.10, rz + 0.05), 0.0))


# ───────── 石板參道、飛石 ─────────
func add_paths() -> void:
	var pl: Dictionary = _read_json(GEN + "placements.json")
	var g := group(sroot, "鋪石")
	var meshes := {
		"nobe_a": load(GK + "gk_nobe_a.res"), "nobe_c": load(GK + "gk_nobe_c.res"),
		"tobi_a": load(GK + "gk_tobi_a.res"), "tobi_b": load(GK + "gk_tobi_b.res"),
		"tobi_c": load(GK + "gk_tobi_c.res"), "tobi_d": load(GK + "gk_tobi_d.res"),
	}
	var smats := _path_stone_materials()
	var i := 0
	for lst in [pl["path"], pl["tobi"]]:
		for it in lst:
			var m: Mesh = meshes[it["src"]]
			var bb := m.get_aabb()
			var sc := Vector3(float(it.get("sx", 1.0)), float(it.get("sy", 1.0)), float(it.get("sz", 1.0))) * float(it["s"])
			var x: float = it["x"]
			var z: float = it["z"]
			# 擺法：腳印 9 點地面 → 最小平方平面；石板順著平面微傾（≤8°），再整體抬到「9 點都不被地形蓋住 + 1.2 cm」。
			# 2026-10-22：原本只取中心點地面 +1.5 cm，地面傾斜 >1.7° 時一端被地形蓋住（PV 量到最深 13 cm）→ 參道讀成「斷口／零散石塊」；
			# 改成「頂面取最高點」又讓低側懸空 12 cm → 最終採順坡微傾。
			var hx := bb.size.x * 0.5 * sc.x * 0.9
			var hz := bb.size.z * 0.5 * sc.z * 0.9
			var yb := Basis(Vector3.UP, float(it["yaw"]))
			var hs: Array[Vector3] = []
			for ox in [-1.0, 0.0, 1.0]:
				for oz in [-1.0, 0.0, 1.0]:
					var w: Vector3 = yb * Vector3(float(ox) * hx, 0.0, float(oz) * hz)
					hs.append(Vector3(w.x, gy(x + w.x, z + w.z), w.z))
			var sxx := 0.0
			var szz := 0.0
			var sxh := 0.0
			var szh := 0.0
			var hm := 0.0
			for p in hs:
				sxx += p.x * p.x
				szz += p.z * p.z
				sxh += p.x * p.y
				szh += p.z * p.y
				hm += p.y
			hm /= float(hs.size())
			var ga := clampf(sxh / maxf(sxx, 1.0e-6), -0.14, 0.14)
			var gb := clampf(szh / maxf(szz, 1.0e-6), -0.14, 0.14)
			var res_max := -1.0e9
			for p in hs:
				res_max = maxf(res_max, p.y - (hm + ga * p.x + gb * p.z))
			var top_c := hm + maxf(res_max, 0.0) + 0.012
			var tilt := Basis(Quaternion(Vector3.UP, Vector3(-ga, 1.0, -gb).normalized()))
			var bas: Basis = tilt * yb.scaled(sc)
			var org: Vector3 = Vector3(x, top_c, z) - bas * Vector3(0.0, bb.position.y + bb.size.y, 0.0)
			mesh_node(g, m, "%s_%03d" % [it["src"], i], Transform3D(bas, org), smats[i % smats.size()])
			i += 1
	stats["path_stones"] = i


## 參道石板：沿用園藝套件的延段／飛石網格，但套件材質亮度係數 0.42（≈ 反照率 0.24，鋪在夯土上像黑色跑道）
## → 改成 1.0（≈ 0.57，灰白），三種微幅色偏避免整排同色。
func _path_stone_materials() -> Array:
	var base := load("res://assets/village_v2/machiya_kit/V2_KitStoneTri.tres") as StandardMaterial3D
	var out: Array = []
	for tint in [Color(1.00, 0.99, 0.95), Color(0.93, 1.00, 0.91), Color(1.04, 1.02, 0.97)]:
		var m := base.duplicate() as StandardMaterial3D
		m.albedo_color = tint
		out.append(m)
	return out


# ───────── 地被：落花、三葉草、野花（Quaternius CC0，無碰撞）─────────
func add_litter() -> void:
	var pl: Dictionary = _read_json(GEN + "placements.json")
	var g := group(sroot, "地被")
	var i := 0
	for it in pl["litter"]:
		var x: float = it["x"]
		var z: float = it["z"]
		inst(g, NAT + String(it["src"]) + ".gltf", "%s_%03d" % [it["src"], i],
			xf_of(Vector3(x, gy(x, z) - 0.02, z), it["yaw"], Vector3.ONE * float(it["s"])))
		i += 1
	stats["litter"] = i


# ───────── 池塘 ─────────
func add_pond() -> void:
	var p: Dictionary = L["pond"]
	var th := deg_to_rad(float(p["rot_deg"]))
	var cx := float(p["cx"])
	var cz := float(p["cz"])
	var rx := float(p["rx"])
	var rz := float(p["rz"])
	var level := float(p["level"])
	var nseg := 72
	var nring := 7
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.append(Vector3(cx, level, cz))
	cols.append(_pond_color(0.0))
	uvs.append(Vector2(0.5, 0.5))
	for r in range(1, nring + 1):
		var f := float(r) / nring
		for i in nseg:
			var a := TAU * i / nseg
			var wob := 1.0 + 0.16 * sin(a * 2.0 + 0.7) + 0.09 * sin(a * 3.0 - 1.3) + 0.05 * sin(a * 5.0 + 2.1)
			var rr := wob * 1.045 * f
			var u := rr * cos(a)
			var v := rr * sin(a)
			var dx := rx * u * cos(th) - rz * v * sin(th)
			var dz := rx * u * sin(th) + rz * v * cos(th)
			verts.append(Vector3(cx + dx, level, cz + dz))
			cols.append(_pond_color(f))
			uvs.append(Vector2(0.5 + dx * 0.05, 0.5 + dz * 0.05))
	for i in nseg:
		idx.append_array([0, 1 + i, 1 + (i + 1) % nseg])
	for r in range(1, nring):
		var b0 := 1 + (r - 1) * nseg
		var b1 := 1 + r * nseg
		for i in nseg:
			var j := (i + 1) % nseg
			idx.append_array([b0 + i, b1 + i, b0 + j, b0 + j, b1 + i, b1 + j])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/water.gdshader")
	# 「頂點色＝反照率」模式（人里主河同款）：世界座標的程序漣漪（不隨鏡頭滑動）＋風漣漪；
	# 舊的 wave_nor 模式用 view-space VERTEX.xz 取 UV，貼圖會跟著鏡頭走，而且專案裡那張 wave_nor 是草葉法線圖（細長條紋）。
	mat.set_shader_parameter("vc_albedo", 1.0)
	mat.set_shader_parameter("vc_roughness", 0.20)
	mat.set_shader_parameter("vc_specular", 0.15)     # Godot 4 的菲涅耳 f90 ∝ 0.08×specular：0.15 → 掠射角天空反射最多 ≈1/3，水色不被「天空乳白」蓋掉
	mat.set_shader_parameter("detail_slope", 0.035)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add(sroot, mi, "池塘水面")


## 池水頂點色：f＝0 池心、1 水線。深色 → 淺灰綠；水線處半透明（透出濕泥岸）。
func _pond_color(f: float) -> Color:
	var t := clampf(pow(f, 1.8), 0.0, 1.0)
	var deep := Color(0.10, 0.17, 0.15, 0.95)
	var shallow := Color(0.30, 0.38, 0.30, 0.62)
	var c := deep.lerp(shallow, t)
	# 最外 35% 漸透明到 ≈0.22（透出濕泥岸）：水線不是一刀切（審圖：水土交界乾淨、過渡窄）
	c.a = lerpf(c.a, 0.22, smoothstep(0.65, 1.0, f))
	return c


# ───────── 岩石、植被 ─────────
## n 底下所有 MeshInstance3D 在 n 本地座標的聯集 AABB
func _local_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != n:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var bb: AABB = xf * mi.mesh.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


## 以子網格聯集 AABB 為尺寸，在 n 底下加一個盒形實心碰撞（隨 n 的旋轉／縮放）
func _aabb_body(n: Node3D, shrink := 0.9) -> void:
	var bb := _local_aabb(n)
	if bb.size == Vector3.ZERO:
		return
	_box_body(n, bb.size * Vector3(shrink, 1.0, shrink), bb.get_center())


func _convex_body(mi: MeshInstance3D, parent: Node = null) -> void:
	if mi.mesh == null:
		return
	var sh := mi.mesh.create_convex_shape(true, true)
	if sh == null:
		return
	var sb := StaticBody3D.new()
	sb.name = "碰撞"
	var host: Node = parent if parent != null else mi
	host.add_child(sb)
	sb.owner = sroot
	var cs := CollisionShape3D.new()
	cs.shape = sh
	if parent != null:
		cs.transform = mi.transform
	sb.add_child(cs)
	cs.owner = sroot


func _foot_min(x: float, z: float, hx: float, hz: float, yaw: float) -> float:
	var lo := INF
	var b := Basis(Vector3.UP, yaw)
	for p in [Vector2(0, 0), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		var w := b * Vector3(p.x * hx, 0.0, p.y * hz)
		lo = minf(lo, gy(x + w.x, z + w.z))
	return lo


func add_rocks_and_veg() -> void:
	var pl: Dictionary = _read_json(GEN + "placements.json")
	var gr := group(sroot, "岩石")
	var kmap := {
		"kei_low": load(GK + "gk_kei_low.res"), "kei_flat": load(GK + "gk_kei_flat.res"),
		"kei_mid": load(GK + "gk_kei_mid.res"), "kei_tall": load(GK + "gk_kei_tall.res"),
	}
	var ri := 0
	var rock_bb := {}   # Quaternius 岩石 src → 網格區域 AABB（快取）
	for r in pl["rocks"]:
		var src: String = r["src"]
		var x: float = r["x"]
		var z: float = r["z"]
		var s: float = r["s"]
		# 接地：以腳印 9 點的「最低地面」為準（斜坡上以中心高放置，下坡側會懸空），再埋入 6–20 cm
		var bb: AABB
		if kmap.has(src):
			bb = (kmap[src] as Mesh).get_aabb()
		else:
			if not rock_bb.has(src):
				var tmp := (load(NAT + "Rock_Medium_%s.gltf" % src.substr(src.length() - 1)) as PackedScene).instantiate()
				var ks: Array = tmp.find_children("*", "MeshInstance3D", true, false)
				rock_bb[src] = (ks[0] as MeshInstance3D).mesh.get_aabb()
				tmp.free()
			bb = rock_bb[src]
		var lo := _foot_min(x, z, bb.size.x * 0.5 * s * 0.85, bb.size.z * 0.5 * s * 0.85, float(r["yaw"]))
		var y := minf(lo, gy(x, z)) - clampf(float(r["sink"]) * 0.4, 0.06, 0.2) - bb.position.y * s
		var nm := "%s_%02d" % [src, ri]
		ri += 1
		if kmap.has(src):
			var m: Mesh = kmap[src]
			var mi := mesh_node(gr, m, nm, xf_of(Vector3(x, y, z), r["yaw"], Vector3.ONE * s))
			_convex_body(mi)
		else:
			var path := NAT + "Rock_Medium_%s.gltf" % src.substr(src.length() - 1)
			var n := inst(gr, path, nm, xf_of(Vector3(x, y, z), r["yaw"], Vector3.ONE * s))
			var kids: Array = n.find_children("*", "MeshInstance3D", true, false)
			if kids.size() > 0:
				_convex_body(kids[0], n)
	stats["rocks"] = ri
	var gt := group(sroot, "樹木")
	var ti := 0
	for t in pl["trees"]:
		var id: String = t["id"]
		var x: float = t["x"]
		var z: float = t["z"]
		var n := inst(gt, TREES + id + ".tscn", "%s_%03d" % [id, ti], xf_of(Vector3(x, gy(x, z), z), t["yaw"], Vector3.ONE * float(t["s"])))
		if n != null:
			n.set_meta("zone", t["g"])
		ti += 1
	stats["trees"] = ti
	var gu := group(sroot, "下層植栽")
	var ui := 0
	for u in pl["under"]:
		inst(gu, TREES + String(u["id"]) + ".tscn", "%s_%03d" % [u["id"], ui],
			xf_of(Vector3(u["x"], gy(u["x"], u["z"]), u["z"]), u["yaw"], Vector3.ONE * float(u["s"])))
		ui += 1
	stats["under"] = ui


# ───────── 互動、標記 ─────────
func add_interactions() -> void:
	var wi := load("res://components/interaction/world_interaction.gd")
	var g := Node3D.new()
	add(sroot, g, "神社互動點")
	var a := Area3D.new()
	a.set_script(wi)
	a.collision_layer = 0
	a.collision_mask = 1
	a.set("interaction_id", "hakurei_shrine_approach")
	a.set("interaction_label", "")
	a.set("quest_event_type", "REACH")
	a.set("quest_target_id", "hakurei_shrine_approach")
	add(g, a, "參道抵達")
	a.position = Vector3(1.0, gy(1.0, 38.0) + 0.5, 38.0)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(16, 6, 6)
	cs.shape = bx
	add(a, cs, "CollisionShape3D")
	var b := Area3D.new()
	b.set_script(wi)
	b.collision_layer = 0
	b.collision_mask = 1
	b.set("interaction_id", "hakurei_shrine_visit")
	b.set("interaction_label", "拜訪")
	b.set("place_name", "博麗神社")
	b.set("dialogue_id", "reimu_hakurei_shrine")
	b.set("require_quest", "MQ04")
	add(g, b, "拜殿拜訪")
	b.position = Vector3(0, float(L["y_c"]) + 1.2, -21.0)
	var cs2 := CollisionShape3D.new()
	var bx2 := BoxShape3D.new()
	bx2.size = Vector3(10, 4, 6)
	cs2.shape = bx2
	add(b, cs2, "CollisionShape3D")


func add_markers() -> void:
	var g := group(sroot, "標記")
	var ap: Array = L["approach"]
	var a1: Array = ap[1]
	var portal_pos := Vector3(float(a1[0]), float(a1[2]), float(a1[1]))
	var m1 := Marker3D.new()
	m1.position = Vector3(portal_pos.x + 0.2, gy(portal_pos.x, portal_pos.z - 4.0), portal_pos.z - 4.0)
	m1.rotation.y = PI
	add(g, m1, "出生點_南")
	var m2 := Marker3D.new()
	m2.position = portal_pos
	m2.set_meta("portal", "trail")
	add(g, m2, "傳送點_南_獸道")


# ───────── 導航網格（NPC／AI 路徑用；專案其他圖沒有，這裡是新增能力）─────────
func _to_root(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != sroot:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _shape_aabb_local(sh: Shape3D) -> AABB:
	if sh is BoxShape3D:
		var s := (sh as BoxShape3D).size
		return AABB(-s * 0.5, s)
	if sh is CylinderShape3D:
		var c := sh as CylinderShape3D
		return AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2.0, c.height, c.radius * 2.0))
	if sh is SphereShape3D:
		var r := (sh as SphereShape3D).radius
		return AABB(Vector3(-r, -r, -r), Vector3(r * 2.0, r * 2.0, r * 2.0))
	if sh is CapsuleShape3D:
		var cp := sh as CapsuleShape3D
		return AABB(Vector3(-cp.radius, -cp.height * 0.5, -cp.radius), Vector3(cp.radius * 2.0, cp.height, cp.radius * 2.0))
	var pts := PackedVector3Array()
	if sh is ConcavePolygonShape3D:
		pts = (sh as ConcavePolygonShape3D).get_faces()
	elif sh is ConvexPolygonShape3D:
		pts = (sh as ConvexPolygonShape3D).points
	if pts.is_empty():
		return AABB()
	var lo := pts[0]
	var hi := pts[0]
	for v in pts:
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo, hi - lo)


func add_navigation() -> void:
	var geo := NavigationMeshSourceGeometryData3D.new()
	var terr := sroot.get_node("Terrain") as MeshInstance3D
	geo.add_mesh(terr.mesh, Transform3D.IDENTITY)
	var n_walk := 1
	for mi in sroot.get_node("參道石階").find_children("*", "MeshInstance3D", true, false):
		geo.add_mesh((mi as MeshInstance3D).mesh, _to_root(mi as Node3D))
		n_walk += 1
	# 障礙＝建築、境內物件、樹、岩石、下層植栽的碰撞體（取世界 AABB 的 XZ 矩形，carve 進導航網格）
	var n_obs := 0
	for grp in ["建築", "境內物件", "樹木", "岩石", "下層植栽"]:
		var gn := sroot.get_node_or_null(grp)
		if gn == null:
			continue
		for cs_n in gn.find_children("*", "CollisionShape3D", true, false):
			var cs := cs_n as CollisionShape3D
			if cs.shape == null or cs.disabled:
				continue
			var lb := _shape_aabb_local(cs.shape)
			if lb.size == Vector3.ZERO:
				continue
			var xf := _to_root(cs)
			var lo := Vector3(1.0e9, 1.0e9, 1.0e9)
			var hi := Vector3(-1.0e9, -1.0e9, -1.0e9)
			for ix in 2:
				for iy in 2:
					for iz in 2:
						var c := xf * (lb.position + lb.size * Vector3(ix, iy, iz))
						lo = lo.min(c)
						hi = hi.max(c)
			if hi.x - lo.x > 40.0 or hi.z - lo.z > 40.0:
				continue
			# 最小邊長 0.5 m（≥ 2 格）：Recast 以體素中心判斷是否在多邊形內，比 1 格還小的障礙（幼樹幹 r=5 cm）有 84% 機率一格也點不到而挖不出孔
			var cxm := (lo.x + hi.x) * 0.5
			var czm := (lo.z + hi.z) * 0.5
			var hxm := maxf((hi.x - lo.x) * 0.5, 0.25)
			var hzm := maxf((hi.z - lo.z) * 0.5, 0.25)
			var poly := PackedVector3Array([
				Vector3(cxm - hxm, lo.y, czm - hzm), Vector3(cxm + hxm, lo.y, czm - hzm), Vector3(cxm + hxm, lo.y, czm + hzm), Vector3(cxm - hxm, lo.y, czm + hzm)])
			# carve=false：孔會再外擴一個代理半徑；carve=true 只挖出障礙腳印本身，路徑會貼著燈籠／樹幹邊走而卡住
			# 柱體向下多延 1.2 m：陡坡上代理半徑範圍內的下坡地面比樹根還低，不延伸就挖不到（實測 35° 坡上幼樹旁頂點離樹幹僅 0.33 m）
			geo.add_projected_obstruction(poly, lo.y - 1.2, maxf(hi.y - lo.y, 0.5) + 1.2, false)
			n_obs += 1
	# 池塘：水線以內不可走（岸坡外的淺灘仍可走）
	var water := sroot.get_node_or_null("池塘水面") as MeshInstance3D
	if water != null:
		var arr := water.mesh.surface_get_arrays(0)
		var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ring := PackedVector3Array()
		var nseg := 72
		for k in range(vv.size() - nseg, vv.size()):
			ring.append(Vector3(vv[k].x, vv[k].y - 2.0, vv[k].z))
		geo.add_projected_obstruction(ring, vv[0].y - 2.0, 2.6, false)
		n_obs += 1
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	nm.agent_height = 1.8
	# 體素化後實際留白＝(⌈半徑/格⌉−1)×格：0.5 → 2 格 → 只剩 0.25 m（實測倉庫／賽錢箱邊頂點離碰撞盒 0.22–0.25 m）；0.8 → 4 格 → 0.75 m，扣掉輪廓簡化誤差 0.25 m 仍 ≥ 玩家膠囊半徑 0.3
	nm.agent_radius = 0.8
	nm.agent_max_climb = 0.3
	# 30°：石階兩側的山坡（約 35–45°）不納入導航，NPC／AI 會走石階與林徑；玩家本身 floor_max_angle 52°，仍可自行爬坡
	nm.agent_max_slope = 30.0
	nm.region_min_size = 4.0
	# 輪廓簡化誤差（單位＝體素）：1.0 ＝ 0.25 m。多邊形總數 4082 < 4096（NavigationAgent3D／查詢預設 path_search_max_polygons），長路線的 A* 不會被截斷；0.5 會讓總數倍增到 7400，全程路線被截成 3.6 m 缺口
	nm.edge_max_error = 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--nav-eme="):
			nm.edge_max_error = float(a.substr(10))
		elif a.begins_with("--nav-part="):
			nm.sample_partition_type = int(a.substr(11))
		elif a.begins_with("--nav-rad="):
			nm.agent_radius = float(a.substr(10))
		elif a.begins_with("--nav-vpp="):
			nm.vertices_per_polygon = float(a.substr(10))
		elif a.begins_with("--nav-merge="):
			nm.region_merge_size = float(a.substr(12))
		elif a.begins_with("--nav-minr="):
			nm.region_min_size = float(a.substr(11))
	var p: Dictionary = L["play"]
	# 範圍內縮 2 m：邊界牆外的樹不在烘焙範圍內（障礙會被忽略），網格若貼著邊緣就會靠到它們；內縮後邊緣離牆外樹 ≥ 2 m
	var inset := 2.0
	nm.filter_baking_aabb = AABB(Vector3(float(p["x0"]) + inset, -6.0, float(p["z0"]) + inset), Vector3(float(p["x1"]) - float(p["x0"]) - inset * 2.0, 80.0, float(p["z1"]) - float(p["z0"]) - inset * 2.0))
	NavigationServer3D.bake_from_source_geometry_data(nm, geo)
	var e := ResourceSaver.save(nm, GEN + "navmesh.res")
	var reg := NavigationRegion3D.new()
	reg.navigation_mesh = load(GEN + "navmesh.res")
	add(sroot, reg, "導航")
	stats["nav"] = {"save_err": e, "polys": nm.get_polygon_count(), "verts": nm.get_vertices().size(), "walk_meshes": n_walk, "obstacles": n_obs}



func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	L = S2.load_layout()
	S2.load_height()
	sroot = Node3D.new()
	sroot.name = "Shrine"
	sroot.set_meta("own_colliders", true)
	add_terrain()
	add_sky()
	add_boundary()
	add_stairs()
	add_buildings()
	add_court_items()
	add_paths()
	add_litter()
	add_pond()
	add_rocks_and_veg()
	add_interactions()
	add_markers()
	add_navigation()
	var pk := PackedScene.new()
	var e := pk.pack(sroot)
	var e2 := ResourceSaver.save(pk, OUT)
	print("[BUILD] pack=%d save=%d nodes=%d stats=%s -> %s" % [e, e2, _count(sroot), stats, OUT])
	quit()


func _count(n: Node) -> int:
	var c := 1
	for k in n.get_children():
		c += _count(k)
	return c
