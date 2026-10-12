extends RefCounted
## 人間之里 V2 P13 W2 — 農家 A1（茅葺の主屋）＋A2（板葺の農具納屋）正式版（使用者 2026-10-12 承認の選址 (318,82)／(323,71)）。
## overlay `FarmsteadP13`（root 直下）→ gen/farmstead_p13.scn。生成器：tools/p13/build_farmstead.gd。
## 茅葺：Godot Image で生成した繊維方向（流れ方向に長い筋・葺き段・色むら）の albedo＋normal（maps/village_v2/farmstead_p13/）。
##   幾何：屋根厚 0.55 m、軒先の切り口（小口）帯、棟は押さえ＋竹の烏おどし。
## 碰撞：壁体の箱（簷高まで、他の町家と同じ方針）＋縁＋農具掛け・薪棚。籠・踏石は碰撞なし。
## 動線：A2 前 → 踏石 → T0 支線の上に渡し板（水路・堤は不変）→ FarmPath_5 西端。
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const NODE_NAME := "FarmsteadP13"
const OUTPUT := "res://maps/village_v2/gen/farmstead_p13.scn"
const TEX := "res://maps/village_v2/farmstead_p13/"
const MAT := "res://assets/village_v2/_matlib/"
const DIRS := {"st_": "res://assets/village_v2/street_kit/mesh/", "sk_": "res://assets/village_v2/school_kit/mesh/",
	"hu_": "res://assets/village_v2/humanuse_kit/mesh/", "rb_": "res://assets/village_v2/riverbank_kit/mesh/"}
## [名, 中心 x, z, 本体 x 幅, z 奥]：棟は z 沿い、正面＝+x
const HOUSES := [["A1_noka", 318.0, 82.0, 6.4, 9.1], ["A2_naya", 323.0, 71.0, 3.6, 5.5]]
## 渡し板：T0 支線（x≈329、z 67–73 で FarmPath_5 西端と並走）を横切る
const PLANK := [Vector2(327.2, 70.4), Vector2(330.9, 70.4)]
## 踏石（世界 xz）：渡し板西端 → A2 前 → A1 の戸口（x 321.2、z 84.3）
const STONES := [Vector2(326.4, 70.9), Vector2(325.9, 72.2), Vector2(325.6, 73.6), Vector2(325.1, 75.0), Vector2(324.5, 76.4),
	Vector2(323.9, 77.8), Vector2(323.3, 79.2), Vector2(322.8, 80.6), Vector2(322.4, 82.0), Vector2(322.1, 83.4)]
## 道具：[id, x, z, yaw°, 碰撞]
const PROPS := [["st_kuwa", 323.0, 67.0, 180.0, true], ["sk_woodpile", 318.0, 87.25, 0.0, true], ["hu_seoikago", 322.3, 86.2, 30.0, false]]


static func _mat(path: String, tint := Color(1, 1, 1)) -> StandardMaterial3D:
	var m := (load(path) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = m.albedo_color * tint
	return m


## 茅葺の貼図（512²、v＝流れ方向）。一度作って .res に保存（import 不要）。
static func thatch_textures() -> Array:
	var ap := TEX + "thatch_albedo.res"
	var np := TEX + "thatch_normal.res"
	if ResourceLoader.exists(ap) and ResourceLoader.exists(np):
		return [load(ap), load(np)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEX))
	var N := 512
	var fib := FastNoiseLite.new()
	fib.seed = 1301
	fib.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	fib.frequency = 1.0
	var big := FastNoiseLite.new()
	big.seed = 77
	big.frequency = 0.012
	var alb := Image.create(N, N, false, Image.FORMAT_RGB8)
	var hgt := Image.create(N, N, false, Image.FORMAT_RGB8)
	var straw := Color(0.66, 0.55, 0.34)
	var grey := Color(0.47, 0.43, 0.36)
	var dark := Color(0.30, 0.25, 0.17)
	for y in N:
		var v := float(y) / N
		var course := fposmod(v * 6.0, 1.0)            # 葺き段 6 段／タイル
		for x in N:
			var u := float(x) / N
			# 繊維：u 方向に細かく、v 方向に長く（seamless のため周期座標）
			var f := fib.get_noise_2d(u * 260.0, v * 9.0 + floor(v * 6.0) * 3.1) * 0.5 + 0.5
			var g := big.get_noise_2d(x, y) * 0.5 + 0.5
			var shade := lerpf(0.72, 1.12, f)
			if course > 0.86:                              # 段の下端＝影
				shade *= lerpf(0.65, 0.95, (1.0 - course) / 0.14)
			var c := straw.lerp(grey, clampf(g * 1.2 - 0.1, 0.0, 1.0))
			c = (c * shade).lerp(dark, clampf(0.35 - f, 0.0, 0.35))
			alb.set_pixel(x, y, c)
			var hv := clampf(f * 0.8 + (0.0 if course < 0.86 else -0.3 * (course - 0.86) / 0.14) + 0.1, 0.0, 1.0)
			hgt.set_pixel(x, y, Color(hv, hv, hv))
	hgt.bump_map_to_normal_map(6.0)
	alb.generate_mipmaps()
	hgt.generate_mipmaps()
	var at := ImageTexture.create_from_image(alb)
	var nt := ImageTexture.create_from_image(hgt)
	ResourceSaver.save(at, ap, ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(nt, np, ResourceSaver.FLAG_COMPRESS)
	return [load(ap), load(np)]


static func _thatch_mat(tx: Array) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "P13_Thatch"
	m.albedo_texture = tx[0]
	m.normal_enabled = true
	m.normal_texture = tx[1]
	m.normal_scale = 1.4
	m.roughness = 0.97
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3(0.55, 0.55, 0.55)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _box(p: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Basis.IDENTITY, nm := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if nm != "":
		mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.transform = Transform3D(rot, pos)
	p.add_child(mi)
	return mi


static func _gable(p: Node3D, x: float, y0: float, half: float, rise: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(x, y0, -half)
	var b := Vector3(x, y0 + rise, 0)
	var c := Vector3(x, y0, half)
	for v3 in [a, b, c, c, b, a]:      # 両面
		st.set_uv(Vector2(v3.z, v3.y))
		st.add_vertex(v3)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "gable"
	mi.mesh = st.commit()
	mi.material_override = mat
	p.add_child(mi)


## 切妻：棟は局所 x、±z へ下る。屋根板の外縁（軒先）が y_eave。
static func _roof(p: Node3D, len_x: float, half: float, rise: float, y_eave: float, th: float, mat: Material, cut: Material) -> void:
	var ang := atan2(rise, half)
	var sl := sqrt(half * half + rise * rise)
	for sg in [1.0, -1.0]:
		var b := Basis(Vector3.RIGHT, sg * ang)       # sg＝+1：+z 端が下がる
		_box(p, Vector3(len_x, th, sl), Vector3(0, y_eave + rise * 0.5 + th * 0.5 / cos(ang), sg * half * 0.5), mat, b, "roof_%s" % ("f" if sg > 0 else "b"))
		if cut != null:
			# 軒先の小口（切り揃えた茅の断面）：屋根板の外端に沿う帯
			_box(p, Vector3(len_x + 0.02, th * 0.95, 0.06), Vector3(0, y_eave + th * 0.5, sg * (half + 0.02)), cut, Basis.IDENTITY, "eave_cut")


static func _ground(S: RLib.TriSampler, c: Vector2, w: float, d: float) -> Array:
	var hs: Array = []
	for ix in 7:
		for iz in 7:
			var h := S.h(c.x + lerpf(-w, w, ix / 6.0) * 0.5, c.y + lerpf(-d, d, iz / 6.0) * 0.5)
			if not is_nan(h):
				hs.append(h)
	return [hs.min(), hs.max()]


static func _coll(col: StaticBody3D, nm: String, size: Vector3, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.name = nm
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.transform = xf
	col.add_child(cs)


static func _mesh_node(p: Node3D, id: String, pos: Vector3, yaw: float) -> Node3D:
	var n := Node3D.new()
	n.name = id
	n.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	var d := String(DIRS[id.substr(0, 3)])
	for lod in 2:
		var path := d + id + ("_l1" if lod == 1 else "") + ".res"
		if not ResourceLoader.exists(path):
			continue
		var mi := MeshInstance3D.new()
		mi.name = "LOD%d" % lod
		mi.mesh = load(path)
		mi.visibility_range_begin = 0.0 if lod == 0 else 34.0
		mi.visibility_range_end = 34.0 if lod == 0 else 200.0
		n.add_child(mi)
	p.add_child(n)
	return n


## v：village_v2 インスタンス（物理を使うので tree 内であること）
static func bake(v: Node3D) -> Node3D:
	var S := RLib.terrain_sampler(v)
	var sp := v.get_world_3d().direct_space_state
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_meta("phase", "P13W2")
	root.set_meta("note", "農家 A1 主屋（茅葺）＋A2 農具納屋（板葺）。使用者 2026-10-12 承認の選址。稗田邸圍牆外・田塊外・N0／T0 不変。")
	var col := StaticBody3D.new()
	col.name = "Collision"
	root.add_child(col)
	var tx := thatch_textures()
	var thatch := _thatch_mat(tx)
	var cut := _mat(MAT + "V2_Wood.tres", Color(0.62, 0.50, 0.30))
	cut.albedo_texture = tx[0]
	cut.uv1_scale = Vector3(3.0, 0.4, 1.0)
	var plaster := _mat(MAT + "V2_Plaster.tres", Color(0.80, 0.68, 0.52))
	var wood: Material = load(MAT + "V2_Wood.tres")
	var dark := _mat(MAT + "V2_Wood.tres", Color(0.45, 0.42, 0.40))
	var board := _mat(MAT + "V2_Wood.tres", Color(0.62, 0.55, 0.48))
	var stone: Material = load(MAT + "V2_Stone.tres")
	var ridge := _mat(MAT + "V2_Wood.tres", Color(0.36, 0.33, 0.30))
	var rep := []
	for s: Array in HOUSES:
		var c := Vector2(s[1], s[2])
		var w: float = s[3]
		var d: float = s[4]
		var g := _ground(S, c, w + 1.0, d + 1.0)
		var lo: float = g[0]
		var hi: float = g[1]
		var n := Node3D.new()
		n.name = String(s[0])
		n.position = Vector3(c.x, hi, c.y)
		n.set_meta("ground", [snappedf(lo, 0.01), snappedf(hi, 0.01)])
		root.add_child(n)
		var body := Node3D.new()
		body.name = "Body"
		body.rotation.y = PI * 0.5          # 局所 x（棟）＝世界 −z…+z、局所 +z（正面）＝世界 +x
		n.add_child(body)
		var Lx := d
		var D := w
		var fnd := 0.3
		var drop := hi - lo + 0.25
		_box(body, Vector3(Lx + 0.3, fnd + drop, D + 0.3), Vector3(0, (fnd - drop) * 0.5, 0), stone, Basis.IDENTITY, "kidan")
		var ba := Basis(Vector3.UP, PI * 0.5)
		if String(s[0]).ends_with("noka"):
			var e := 2.35
			_box(body, Vector3(Lx, e, D), Vector3(0, fnd + e * 0.5, 0), plaster, Basis.IDENTITY, "wall")
			_box(body, Vector3(Lx + 0.04, 0.85, D + 0.04), Vector3(0, fnd + 0.425, 0), board, Basis.IDENTITY, "koshiita")   # 腰板
			var nb := int(round(Lx / 1.82))
			for i in nb + 1:
				var x := -Lx * 0.5 + i * Lx / nb
				for zz in [-D * 0.5, D * 0.5]:
					_box(body, Vector3(0.16, e, 0.16), Vector3(x, fnd + e * 0.5, zz), wood, Basis.IDENTITY, "hashira")
			for zz in [-D * 0.5, D * 0.5]:
				_box(body, Vector3(Lx + 0.1, 0.22, 0.2), Vector3(0, fnd + e - 0.11, zz), wood, Basis.IDENTITY, "keta")
				_box(body, Vector3(Lx + 0.06, 0.12, 0.18), Vector3(0, fnd + 1.55, zz), wood, Basis.IDENTITY, "nuki")
			# 正面：土間の大戸（閉）、障子窓の格子、縁
			_box(body, Vector3(1.8, 1.95, 0.1), Vector3(-Lx * 0.25, fnd + 0.98, D * 0.5 + 0.05), dark, Basis.IDENTITY, "oodo")
			_box(body, Vector3(0.06, 1.95, 0.12), Vector3(-Lx * 0.25, fnd + 0.98, D * 0.5 + 0.09), wood, Basis.IDENTITY, "oodo_join")
			_box(body, Vector3(2.7, 1.1, 0.06), Vector3(Lx * 0.2, fnd + 1.35, D * 0.5 + 0.04), _mat(MAT + "V2_Plaster.tres", Color(0.95, 0.93, 0.86)), Basis.IDENTITY, "shoji")
			for k in 10:
				_box(body, Vector3(0.04, 1.1, 0.05), Vector3(Lx * 0.2 - 1.3 + k * 0.29, fnd + 1.35, D * 0.5 + 0.08), wood, Basis.IDENTITY, "koshi")
			_box(body, Vector3(Lx * 0.55, 0.1, 0.9), Vector3(Lx * 0.2, fnd + 0.42, D * 0.5 + 0.45), wood, Basis.IDENTITY, "engawa")
			for x in [Lx * 0.2 - Lx * 0.27, Lx * 0.2 + Lx * 0.27]:
				_box(body, Vector3(0.1, 0.42 + drop * 0.5, 0.1), Vector3(x, fnd + 0.21 - drop * 0.25, D * 0.5 + 0.85), wood, Basis.IDENTITY, "engawa_tsuka")
			# 側面（妻側）：小窓
			for x in [-Lx * 0.5 - 0.03, Lx * 0.5 + 0.03]:
				_box(body, Vector3(0.06, 0.7, 0.9), Vector3(x, fnd + 1.5, 0.6), dark, Basis.IDENTITY, "mado_side")
			var half := D * 0.5 + 0.95
			var rise := half * 1.0                # 45°
			var ye := fnd + e - 0.95              # 軒先は壁頂より下（茅は深く下がる）
			_gable(body, -Lx * 0.5, fnd + e, D * 0.5, D * 0.5, plaster)
			_gable(body, Lx * 0.5, fnd + e, D * 0.5, D * 0.5, plaster)
			_roof(body, Lx + 1.3, half, rise, ye, 0.55, thatch, cut)
			var top := ye + rise + 0.55 / cos(PI * 0.25)
			_box(body, Vector3(Lx + 1.5, 0.42, 0.62), Vector3(0, top - 0.12, 0), ridge, Basis.IDENTITY, "munaosae")
			var nx := int((Lx + 1.2) / 0.9)
			for i in nx + 1:
				var x := -(Lx + 1.2) * 0.5 + i * (Lx + 1.2) / nx
				for sg in [1.0, -1.0]:
					_box(body, Vector3(0.07, 0.07, 0.95), Vector3(x, top + 0.05, sg * 0.18), _mat(MAT + "V2_Wood.tres", Color(0.7, 0.66, 0.5)),
						Basis(Vector3.RIGHT, sg * 0.55), "karasu")
			_coll(col, "A1_wall", Vector3(w, e + fnd, d), Transform3D(Basis.IDENTITY, n.position + Vector3(0, (e + fnd) * 0.5, 0)))
			_coll(col, "A1_engawa", Vector3(0.9, fnd + 0.47, Lx * 0.55), Transform3D(Basis.IDENTITY, n.position + Vector3(w * 0.5 + 0.45, (fnd + 0.47) * 0.5, -Lx * 0.2)))
			n.set_meta("dims", "主屋 %.1f×%.1f m、壁頂 %.2f、棟 %.2f（地面から）、茅葺 45°・厚 0.55" % [w, d, fnd + e, top + 0.1])
			rep.append({"id": s[0], "top": top + 0.1, "ground": [lo, hi]})
		else:
			var e2 := 2.15
			_box(body, Vector3(Lx, e2, D), Vector3(0, fnd + e2 * 0.5, 0), board, Basis.IDENTITY, "wall")
			for k in int(Lx / 0.3):
				_box(body, Vector3(0.03, e2, D + 0.04), Vector3(-Lx * 0.5 + 0.15 + k * 0.3, fnd + e2 * 0.5, 0), dark, Basis.IDENTITY, "oshibuchi")
			for x in [-Lx * 0.5, -Lx * 0.17, Lx * 0.17, Lx * 0.5]:
				_box(body, Vector3(0.14, e2, 0.14), Vector3(x, fnd + e2 * 0.5, D * 0.5), wood, Basis.IDENTITY, "hashira")
			_box(body, Vector3(Lx * 0.33 - 0.14, e2 - 0.2, 0.08), Vector3(0, fnd + (e2 - 0.2) * 0.5, D * 0.5 + 0.03), _mat(MAT + "V2_Wood.tres", Color(0.18, 0.16, 0.14)), Basis.IDENTITY, "kuchi")
			var half2 := D * 0.5 + 0.5
			var rise2 := half2 * 0.4
			_gable(body, -Lx * 0.5, fnd + e2, D * 0.5, D * 0.5 * 0.4, board)
			_gable(body, Lx * 0.5, fnd + e2, D * 0.5, D * 0.5 * 0.4, board)
			_roof(body, Lx + 0.7, half2, rise2, fnd + e2 - 0.2, 0.08, _mat(MAT + "V2_Wood.tres", Color(0.58, 0.52, 0.46)), null)
			for k in 4:
				_box(body, Vector3(Lx + 0.7, 0.06, 0.06), Vector3(0, fnd + e2 - 0.2 + rise2 * (0.2 + k * 0.22) + 0.07, half2 * (0.8 - k * 0.22)), wood, Basis(Vector3.RIGHT, atan2(rise2, half2)), "ishioki")
				_box(body, Vector3(Lx + 0.7, 0.06, 0.06), Vector3(0, fnd + e2 - 0.2 + rise2 * (0.2 + k * 0.22) + 0.07, -half2 * (0.8 - k * 0.22)), wood, Basis(Vector3.RIGHT, -atan2(rise2, half2)), "ishioki")
			_coll(col, "A2_wall", Vector3(w, e2 + fnd, d), Transform3D(Basis.IDENTITY, n.position + Vector3(0, (e2 + fnd) * 0.5, 0)))
			n.set_meta("dims", "納屋 %.1f×%.1f m、壁頂 %.2f、板葺 4 寸勾配" % [w, d, fnd + e2])
			rep.append({"id": s[0], "top": fnd + e2 - 0.2 + rise2, "ground": [lo, hi]})
	# 渡し板：両端と中央の下を射線（最上の固体＝堤・地面）、板上面＝最高＋0.05
	var path := Node3D.new()
	path.name = "Path"
	root.add_child(path)
	var tops: Array = []
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var p: Vector2 = PLANK[0].lerp(PLANK[1], t)
		var hit := sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 40, p.y), Vector3(p.x, -20, p.y)))
		tops.append(float(hit.position.y) if not hit.is_empty() else S.h(p.x, p.y))
	# T0 の水面 0.39（ZL.BRANCHES）＋堤の見た目より上へ：板の上面 ≥ 水面＋0.15（自動跨步 0.35 以内の段差）
	var py: float = maxf(tops.max() + 0.05, 0.39 + 0.15)
	var mid: Vector2 = (PLANK[0] + PLANK[1]) * 0.5
	var ln := PLANK[0].distance_to(PLANK[1])
	for k in 3:
		_box(path, Vector3(ln, 0.06, 0.3), Vector3(mid.x, py, mid.y - 0.31 + k * 0.31), _mat(MAT + "V2_Wood.tres", Color(0.75, 0.68, 0.58)), Basis.IDENTITY, "watashi_%d" % k)
	for x in [PLANK[0].x + 0.15, PLANK[1].x - 0.15]:
		_box(path, Vector3(0.12, 0.08, 1.0), Vector3(x, py - 0.07, mid.y), wood, Basis.IDENTITY, "watashi_sannui")
	_coll(col, "watashi", Vector3(ln, 0.1, 0.95), Transform3D(Basis.IDENTITY, Vector3(mid.x, py - 0.02, mid.y)))
	root.set_meta("plank", {"y": snappedf(py, 0.01), "under": tops.map(func(f: float) -> float: return snappedf(f, 0.01))})
	var sn := 0
	for p: Vector2 in STONES:
		var h := S.h(p.x, p.y)
		var flag := _mesh_node(path, ["rb_flag_a", "rb_flag_b", "rb_flag_c", "rb_flag_d"][sn % 4], Vector3(p.x, h - 0.03, p.y), deg_to_rad(17.0 * sn))
		flag.scale = Vector3(0.75, 1.0, 0.75)
		sn += 1
	var pr := Node3D.new()
	pr.name = "Props"
	root.add_child(pr)
	for a: Array in PROPS:
		var p := Vector2(a[1], a[2])
		var h := S.h(p.x, p.y)
		var nd := _mesh_node(pr, String(a[0]), Vector3(p.x, h, p.y), deg_to_rad(float(a[3])))
		if bool(a[4]):
			var ab: AABB = (nd.get_node("LOD0") as MeshInstance3D).mesh.get_aabb()
			_coll(col, String(a[0]) + "_c", ab.size, nd.transform * Transform3D(Basis.IDENTITY, ab.get_center()))
	root.set_meta("report", rep)
	_own(root, root)
	return root


static func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_own(c, owner)
