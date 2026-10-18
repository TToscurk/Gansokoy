extends Node3D
## Wind V1.1 混合物件 pilot。
##
## 這是一個「測試場」，不是村莊內容：地面、牆、木架是程式生成的灰盒；
## 樹／暖簾／燈籠／竹籃／石燈籠用村裡真實的 mesh（材質內嵌），
## 落葉因為專案沒有單片落葉資產，用明確標記的 proxy（PILOT_leaf_*，菱形薄片）。
##
## 五類響應都在同一場景、同一個 Wind 場：
##   A 暖簾（shader，Wind 自動接線）
##   B 吊燈籠 ×3（wind_suspended.gd，擺錘＋慣性）
##   C 落葉 ×14（wind_loose.gd LEAF，靜摩擦→抖動→滑行→短暫離地）
##   D 竹籃 ×1（wind_loose.gd BASKET，一般風不動、強陣風才慢慢滑）
##   E 石燈籠 ×1（完全靜止，對照組）
##
## 除錯：F9 風面板（Wind 提供）、V 風向量視覺化、1–4 preset、G 陣風、0 開關、H 位移熱圖。
##
## V1.2 附錄（高度加權植被動態）：
##   高木 keyaki_a 18.8 m、小樹 momiji_a 6.8 m、中木 konara_a 14.9 m（真實 mesh）
##   草叢：地面散佈 ＋ 土丘頂（高 5 m，示範海拔差）＋ 牆後避風口袋（示範遮蔽，植被 shader 也吃）
##   焦點鎖在場中央 → 陣風從上風 20 m 生成、依序掃過；probe_points() 給取證工具投影量測。

const TREE_MESHES := [
	"res://assets/village_v2/veg_kit/mesh/konara_a_LOD0.res",
	"res://assets/village_v2/veg_kit/mesh/momiji_a_LOD0.res",
	"res://assets/village_v2/veg_kit/mesh/keyaki_a_LOD0.res",
]
const NOREN_MESH := "res://assets/village_v2/machiya_kit/mesh/nr_noren_a_182.res"
const LANTERN_MESH := "res://assets/village_v2/mise_kit/mesh/ms_noki_chochin_aka.res"
const BASKET_MESH := "res://assets/village_v2/kiri_kit/mesh/kr_kago.res"
const STONE_LANTERN_MESH := "res://assets/village_v2/garden_kit/mesh/gk_toro_kasuga.res"
const WOOD_MAT := "res://assets/village_v2/_matlib/V2_Wood.tres"
const STONE_MAT := "res://assets/village_v2/_matlib/V2_Stone.tres"
const GEN_LIB := preload("res://tools/gen_lib.gd")
const SUSPENDED := preload("res://scripts/wind/wind_suspended.gd")
const LOOSE := preload("res://scripts/wind/wind_loose.gd")
## 土丘（海拔示範）：中心、底半徑、頂半徑、高
const MOUND_C := Vector3(-1.5, 0.0, -9.5)
const MOUND_R_BOT := 3.8
const MOUND_R_TOP := 2.6
const MOUND_H := 5.0

var _hud: Label
var _vectors: MultiMeshInstance3D
var _vector_t := 0.0
var _vectors_on := false
var _env: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_shelter()
	_build_trees()
	_build_mound()
	_build_grass()
	_build_noren()
	_build_lanterns()
	_build_loose()
	_build_heavy()
	_build_camera()
	_build_hud()
	_build_vectors()
	# 預設不顯示風向量：它每 0.2 s 重畫，會污染截圖的像素差。
	# 按 V 或啟動時加 --pilot-vectors 才開（示範用）。
	_vectors.visible = false
	if "--pilot-vectors" in OS.get_cmdline_user_args():
		_vectors_on = true
		_vectors.visible = true
	# 遮蔽：牆後方（+X 側）是避風口袋；和場取樣共用（只有 CPU 物件吃得到）。
	apply_wind_setup()
	print("[Pilot] ready：lanterns=3 leaves=14 basket=1 heavy=1 noren=1")


# ───────────────────────── 環境 ─────────────────────────

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.44, 0.62, 0.82)
	sm.sky_horizon_color = Color(0.82, 0.86, 0.86)
	sm.ground_bottom_color = Color(0.26, 0.28, 0.2)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	_env = env
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, 38, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	_sun = sun


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "PILOT_ground"
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(44, 0.4, 44)
	shape.shape = box
	shape.position = Vector3(0, -0.2, 0)
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(44, 44)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.35, 0.21)
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)


func _build_shelter() -> void:
	# 一道石牆，後面是避風口袋（讓「巷內風比較小」有具體對照）。
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 2.4, 9.0)
	wall.mesh = bm
	wall.position = Vector3(5.6, 1.2, 0)
	var smat := load(STONE_MAT)
	if smat is StandardMaterial3D:
		wall.material_override = smat
	add_child(wall)
	var body := StaticBody3D.new()
	body.name = "PILOT_wall"
	body.position = wall.position
	add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	body.add_child(cs)


func _build_trees() -> void:
	var spots := [Vector3(-7.5, 0, -5.5), Vector3(-6.0, 0, 5.0), Vector3(7.5, 0, -4.5)]
	for i in spots.size():
		var mi := MeshInstance3D.new()
		mi.name = "PILOT_tree_%d" % i
		mi.mesh = load(TREE_MESHES[i])
		mi.position = spots[i]
		add_child(mi)


func _build_grass() -> void:
	var lib = GEN_LIB.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = lib.tuft_mesh(7, 0.42, 0.34, Color(0.16, 0.22, 0.10), Color(0.46, 0.55, 0.24))
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var pts: Array[Vector3] = []
	for i in 240:
		var p := Vector3(rng.randf_range(-13, 13), 0, rng.randf_range(-12, 12))
		# 空地中央留給落葉／籃子（不要長在道具正下方）
		if Vector2(p.x, p.z).length() < 1.2:
			continue
		# 土丘底面內不長（會埋進土丘）
		if Vector2(p.x - MOUND_C.x, p.z - MOUND_C.z).length() < MOUND_R_BOT + 0.2:
			continue
		pts.append(p)
	mm.instance_count = pts.size()
	for i in pts.size():
		var s := rng.randf_range(0.8, 1.35)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(b, pts[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PILOT_grass"
	mmi.multimesh = mm
	mmi.material_override = lib.grass_wind_mat(0.10)
	mmi.custom_aabb = AABB(Vector3(-14, 0, -13), Vector3(28, 2, 26))
	add_child(mmi)
	# 土丘頂的草叢（同一個 mesh／材質；唯一差別是根部海拔 +5 m）
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = mm.mesh
	var tops: Array[Transform3D] = []
	for i in 46:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (MOUND_R_TOP - 0.25)
		var s := rng.randf_range(0.8, 1.35)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
		tops.append(Transform3D(b, MOUND_C + Vector3(cos(a) * r, MOUND_H, sin(a) * r)))
	mm2.instance_count = tops.size()
	for i in tops.size():
		mm2.set_instance_transform(i, tops[i])
	var mmi2 := MultiMeshInstance3D.new()
	mmi2.name = "PILOT_grass_mound"
	mmi2.multimesh = mm2
	mmi2.material_override = mmi.material_override
	mmi2.custom_aabb = AABB(MOUND_C + Vector3(-3, MOUND_H, -3), Vector3(6, 2, 6))
	add_child(mmi2)


## 土丘：截頭圓錐（灰盒）＋碰撞。頂面＝MOUND_H。
func _build_mound() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = MOUND_R_TOP
	cm.bottom_radius = MOUND_R_BOT
	cm.height = MOUND_H
	cm.radial_segments = 24
	var mi := MeshInstance3D.new()
	mi.name = "PILOT_mound"
	mi.mesh = cm
	mi.position = MOUND_C + Vector3(0, MOUND_H * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.33, 0.30, 0.21)
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "PILOT_mound_body"
	body.position = mi.position
	add_child(body)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = (MOUND_R_TOP + MOUND_R_BOT) * 0.5
	shape.height = MOUND_H
	cs.shape = shape
	body.add_child(cs)


func _build_noren() -> void:
	# 木架：兩柱一橫樑；暖簾掛在橫樑下。節點名 nr_noren_pilot → Wind 自動接線。
	var wood := load(WOOD_MAT)
	for x in [-1.15, 1.15]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 2.35, 0.12)
		post.mesh = bm
		post.position = Vector3(-1.2 + x, 1.175, 1.4)
		if wood is StandardMaterial3D:
			post.material_override = wood
		add_child(post)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(2.7, 0.12, 0.14)
	beam.mesh = bb
	beam.position = Vector3(-1.2, 2.32, 1.4)
	if wood is StandardMaterial3D:
		beam.material_override = wood
	add_child(beam)
	var noren := MeshInstance3D.new()
	noren.name = "nr_noren_pilot"
	noren.mesh = load(NOREN_MESH)
	noren.position = Vector3(-1.2, 0.0, 1.4)
	add_child(noren)


func _build_lanterns() -> void:
	var wood := load(WOOD_MAT)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(4.4, 0.12, 0.12)
	beam.mesh = bb
	beam.position = Vector3(1.8, 2.55, -2.2)
	if wood is StandardMaterial3D:
		beam.material_override = wood
	add_child(beam)
	var mesh: Mesh = load(LANTERN_MESH)
	for i in 3:
		var pivot := Node3D.new()
		pivot.name = "PILOT_lantern_%d" % i
		pivot.position = Vector3(0.2 + i * 1.6, 2.5, -2.2)
		pivot.set_script(SUSPENDED)
		pivot.set("mass_kg", 0.55)
		pivot.set("area_m2", 0.11)
		pivot.set("length_m", 0.5)
		pivot.set("max_angle_deg", 32.0)
		pivot.set("damping", 2.0)
		add_child(pivot)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(0, -0.02, 0)
		pivot.add_child(mi)


func _build_loose() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99117
	var leaf_mesh := _leaf_mesh()
	for i in 14:
		var leaf := Node3D.new()
		leaf.name = "PILOT_leaf_%d" % i
		leaf.position = Vector3(0.6 + rng.randf_range(-1.6, 1.6), 0.01, 3.0 + rng.randf_range(-1.3, 1.3))
		leaf.set_script(LOOSE)
		leaf.set("kind", 0)
		leaf.set("mass_kg", 0.0035)
		leaf.set("area_m2", 0.002)
		leaf.set("mu_static", 0.85)
		leaf.set("mu_kinetic", 0.45)
		leaf.set("drag", 12.0)
		leaf.set("max_radius", 1.0)
		leaf.set("lift_max", 0.35)
		# mesh 必須在 add_child 之前掛好：wind_loose._ready() 會抓第一個 Node3D 子節點當抖動用的視覺節點
		var mi := MeshInstance3D.new()
		mi.mesh = leaf_mesh
		mi.rotation_degrees = Vector3(0, rng.randf() * 360.0, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.46, 0.38, 0.16).lerp(Color(0.30, 0.25, 0.12), rng.randf())
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.9
		mi.material_override = mat
		leaf.add_child(mi)
		add_child(leaf)

	# D：竹籃（2 kg 級）。一般微風不動，強陣風才慢慢滑。
	var basket := Node3D.new()
	basket.name = "PILOT_basket"
	basket.position = Vector3(3.4, 0.01, 2.6)
	basket.set_script(LOOSE)
	basket.set("kind", 1)
	basket.set("mass_kg", 1.6)
	basket.set("area_m2", 0.26)
	basket.set("mu_static", 0.62)
	basket.set("mu_kinetic", 0.45)
	basket.set("drag", 5.0)
	basket.set("max_radius", 0.7)
	basket.set("lift_max", 0.0)
	basket.set("tumble", false)
	var bmi := MeshInstance3D.new()
	bmi.mesh = load(BASKET_MESH)
	basket.add_child(bmi)
	add_child(basket)


func _build_heavy() -> void:
	# E：石燈籠（對照組）。沒有任何風元件；位置在整個測試中不得改變。
	var heavy := MeshInstance3D.new()
	heavy.name = "PILOT_heavy"
	heavy.mesh = load(STONE_LANTERN_MESH)
	heavy.position = Vector3(-4.6, 0.0, 2.9)
	add_child(heavy)


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "PILOT_camera"
	cam.fov = 62.0
	cam.position = Vector3(0.2, 1.75, 9.4)
	cam.look_at_from_position(cam.position, Vector3(-0.4, 1.25, 1.4))
	cam.current = true
	add_child(cam)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PILOT_hud"
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(18, 16)
	_hud.add_theme_color_override("font_color", Color(0.95, 1.0, 0.85))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud.add_theme_constant_override("outline_size", 6)
	_hud.add_theme_font_size_override("font_size", 15)
	layer.add_child(_hud)


func _build_vectors() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.02, 0.55)
	mm.mesh = bm
	var n := 13 * 13
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.name = "PILOT_wind_vectors"
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.95, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.55
	mi.material_override = mat
	mi.custom_aabb = AABB(Vector3(-13, 0, -13), Vector3(26, 1, 26))
	add_child(mi)
	_vectors = mi


func _process(delta: float) -> void:
	if _hud != null:
		var f: Dictionary = Wind.sample_field(Vector3(0, 1.2, 0))
		_hud.text = "WIND PILOT   preset=%s  base_dir=%.0f°\nlocal  %.0f°  strength %.2f  (%.1f m/s)\n[1-4] preset  [G] gust  [0] on/off  [V] vectors" % [
			String(Wind.get_wind()["preset"]),
			float(Wind.get_wind()["direction_deg"]),
			rad_to_deg(float(f["angle"])), float(f["strength"]), float(f["speed"])]
	if _vectors_on and _vectors != null and _vectors.visible:
		_vector_t += delta
		if _vector_t >= 0.2:
			_vector_t = 0.0
			_update_vectors()


func _update_vectors() -> void:
	var mm := _vectors.multimesh
	for iz in 13:
		for ix in 13:
			var p := Vector3(-12.0 + ix * 2.0, 0.06, -12.0 + iz * 2.0)
			var f: Dictionary = Wind.sample_field(p)
			var s := float(f["strength"])
			var ang := float(f["angle"])
			var yaw := PI * 0.5 - ang
			var b := Basis(Vector3.UP, yaw).scaled(Vector3(1.0, 1.0, 0.35 + s * 2.6))
			mm.set_instance_transform(iz * 13 + ix, Transform3D(b, p))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_V:
			_vectors_on = not _vectors_on
			if _vectors != null:
				_vectors.visible = _vectors_on
			get_viewport().set_input_as_handled()


# ───────────────────────── 測試用 ─────────────────────────

## 給取證／測試用：把所有動態物件歸零（燈籠回正、落葉／籃子回原點）。
## 每個 preset 開始時呼叫 → 從靜止開始累積，才能拍到「陣風慢慢把它們推起來」。
func reset_dynamic() -> void:
	for l in objects("PILOT_lantern"):
		(l as Node).call("settle")
	for o in objects("PILOT_leaf") + objects("PILOT_basket"):
		(o as Node).call("reset_to_origin")


func objects(prefix: String) -> Array:
	var out: Array = []
	for c in get_children():
		if String(c.name).begins_with(prefix):
			out.append(c)
	return out


func _leaf_mesh() -> ArrayMesh:
	# 菱形薄片（4 頂點、2 三角），雙面材質 → 遠看就是一片落葉。明示為 proxy。
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(0, 0, 0.07)
	var b := Vector3(0.035, 0, 0)
	var c := Vector3(0, 0, -0.07)
	var d := Vector3(-0.035, 0, 0)
	for tri in [[a, b, c], [a, c, d]]:
		for v in tri:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


# ───────────────────────── V1.2 取證用 ─────────────────────────

## 本場景的風設定（遮蔽＋焦點）。Wind.debug_reset() 會清掉遮蔽，取證工具重設後再呼叫一次。
func apply_wind_setup() -> void:
	Wind.clear_shelters()
	# 牆後（+X 側）是避風口袋；牆高 2.4 m → 高過牆的部分恢復開闊。CPU 道具與植被 shader 都吃。
	Wind.add_shelter(Vector3(8.0, 1.2, 0.0), 4.0, 0.30, 2.4)
	# 焦點鎖在場中央：陣風固定從上風 20 m 生成，掃過整個 pilot（不跟著相機跑）
	Wind.set_focus(Vector3.ZERO, true)

## 世界座標探針（取證工具投影到螢幕量熱圖）。tree_*：沿樹軸的 0–1 高度；grass_*：草叢。
func probe_points() -> Dictionary:
	var out := {}
	for i in 3:
		var t := get_node_or_null("PILOT_tree_%d" % i) as MeshInstance3D
		if t == null:
			continue
		var top := t.mesh.get_aabb().end.y
		out["tree%d_base" % i] = t.global_position
		out["tree%d_top" % i] = t.global_position + Vector3(0, top, 0)
		out["tree%d_h" % i] = Vector3(top, 0, 0)
	out["grass_mound"] = MOUND_C + Vector3(0, MOUND_H + 0.25, 0)
	out["grass_ground"] = Vector3(MOUND_C.x + 6.0, 0.25, MOUND_C.z + 1.0)
	out["grass_shelter"] = Vector3(8.0, 0.25, 0.4)
	out["grass_open"] = Vector3(8.0, 0.25, 7.5)
	for k in 5:
		out["grass_x%d" % k] = Vector3(-11.0 + k * 5.5, 0.25, 8.5)
	return out


## 熱圖檢視：關天光／太陽／天空，只剩植被位移 emission（0.6 m＝白）＋背景黑。
func heat_view(on: bool) -> void:
	if _env == null:
		return
	_env.background_mode = Environment.BG_COLOR if on else Environment.BG_SKY
	_env.background_color = Color.BLACK
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED if on else Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR if on else Environment.TONE_MAPPER_FILMIC
	_sun.visible = not on
	if _hud != null:
		_hud.visible = not on
	Wind.set_debug_view(1 if on else 0)


## 取證用圖層隔離：all＝全部、trees＝只留樹（量高度剖面不被前景草污染）、
## grass＝只留草叢（量海拔／遮蔽／陣風傳播不被背後樹冠污染）。只切 visible，不影響風場本身。
func view_mode(mode: String) -> void:
	for c in get_children():
		var nm := String(c.name)
		if nm.begins_with("PILOT_tree_"):
			(c as Node3D).visible = mode != "grass"
		elif nm.begins_with("PILOT_grass"):
			(c as Node3D).visible = mode != "trees"
