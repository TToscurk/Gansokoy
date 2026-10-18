extends Node3D
## Wind V2 主河浮物（Phase E／G 實地整合；WIND_V2_REVIEW）。
## 全部漂流物共用 Wind 的水面場（流場＋長波＋風漣漪）與風場；元件＝scripts/water/floatable.gd。
##   LEAF_PROXY_*：落葉代理（明示 proxy：專案沒有單片落葉資產）——輕、受風大、偏航快；漂遠淡出回上游。
##   Taru_*：真實資產 geidon_kit/gd_taru（酒樽）——重、慣性大；同樣是臨時漂流物（淡出回收）。
##   小舟：WaterLifeP10/BoatLanding/Boat 的 Hull 視覺節點繫留浮動（本體與碰撞不動，保留作者擺位）。
## 這些都是視覺／模擬物件：不寫存檔、不影響導航與碰撞；重載場景回到作者位置。

const FLOAT := preload("res://scripts/water/floatable.gd")
const TARU := "res://assets/village_v2/geidon_kit/mesh/gd_taru.res"
## 生成點：主河中心線 pts[6]→pts[7]（龍神橋下游）；往下游漂 60 m 後淡出、回生成點重生
const SPAWN_A := Vector2(405.0, -186.0)
const SPAWN_B := Vector2(414.0, -168.0)
const BOAT_PATH := "../WaterLifeP10/BoatLanding/Boat"

var _built := false


func _ready() -> void:
	_build.call_deferred()


func _build() -> void:
	var w := get_node_or_null("/root/Wind")
	# 等 Wind 把主河接線（流場建好）
	for i in 120:
		if w != null and w.has_water():
			break
		await get_tree().process_frame
	if w == null or not w.has_water() or _built:
		return
	_built = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7071
	var leaf_mesh := _leaf_mesh()
	for i in 8:
		var t := rng.randf()
		var p := SPAWN_A.lerp(SPAWN_B, t) + Vector2(rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5))
		var f: Node3D = FLOAT.new()
		f.name = "LEAF_PROXY_%d" % i
		f.set("preset", 0)
		f.set("recycle", true)
		var mi := MeshInstance3D.new()
		mi.mesh = leaf_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.40, 0.16).lerp(Color(0.62, 0.30, 0.10), rng.randf())
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.8
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_child(mi)
		f.position = Vector3(p.x, float(w.sample_water_height(Vector3(p.x, 0, p.y))), p.y)
		f.rotation.y = rng.randf() * TAU
		add_child(f)
	var taru: Mesh = load(TARU)
	for i in 2:
		var p := SPAWN_A.lerp(SPAWN_B, 0.3 + 0.4 * i) + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
		var f: Node3D = FLOAT.new()
		f.name = "Taru_%d" % i
		f.set("preset", 1)
		f.set("recycle", true)
		var mi := MeshInstance3D.new()
		mi.mesh = taru
		# 樽橫躺漂（軸向水平）。浮物原點＝水面−吃水（0.12 m）；空樽軸心約在水面上 7 cm
		# → mesh 中心放在原點上方 0.19 m（旋轉後 AABB 中心對齊，不假設 mesh 原點位置）
		var ab := taru.get_aabb()
		var rb := Basis(Vector3.FORWARD, PI * 0.5)
		mi.transform = Transform3D(rb, -(rb * ab.get_center()) + Vector3(0, 0.19, 0))
		f.add_child(mi)
		f.position = Vector3(p.x, float(w.sample_water_height(Vector3(p.x, 0, p.y))), p.y)
		add_child(f)
	var boat := get_node_or_null(BOAT_PATH) as Node3D
	if boat != null and boat.get_node_or_null("Hull") != null:
		var f: Node3D = FLOAT.new()
		f.name = "BoatTether"
		f.set("preset", 1)
		f.set("mass_kg", 60.0)
		f.set("waterline_area_m2", 1.2)
		f.set("water_drag_area_m2", 0.25)
		f.set("air_drag_area_m2", 0.5)
		f.set("max_tilt_deg", 4.0)
		f.set("tether_length", 0.35)
		f.set("yaw_inertia", 30.0)
		f.set("yaw_damping", 8.0)
		boat.add_child(f)
		f.set("visual_node", f.get_path_to(boat.get_node("Hull")))
		f.call("_ready")
	print("[RiverDemo] 漂流物：落葉 proxy 8、酒樽 2、小舟繫留 %s" % str(boat != null))


func floatables() -> Array:
	var out := find_children("*", "Node3D", false, false)
	var boat := get_node_or_null(BOAT_PATH + "/BoatTether")
	if boat:
		out.append(boat)
	return out


func _leaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(0, 0, 0.09)
	var b := Vector3(0.045, 0, 0)
	var c := Vector3(0, 0, -0.09)
	var d := Vector3(-0.045, 0, 0)
	for tri in [[a, b, c], [a, c, d]]:
		for v in tri:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()
