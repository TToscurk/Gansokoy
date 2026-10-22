extends SceneTree
## 博麗神社 v3 植被：models/veg/*.glb → assets/shrine_v3/mesh/veg/<物種>_v3_<變體>.res（檔名前綴＝風力物種）。
## 材質：樹皮 veg_bark、葉卡 veg_leaf（專案共用的植被 shader：Wind 自動接線靠它與檔名前綴），貼圖全為本輪新做／新下載。
##   godot --headless --path godot --script res://tools/shrine_v3/build_veg.gd

const SRC := "res://assets/shrine_v3/models/veg/"
const DST := "res://assets/shrine_v3/mesh/veg/"
const MAT := "res://assets/shrine_v3/mat/veg/"
const PH := "res://assets/shrine_v3/tex/ph/"
const CARDS := "res://assets/shrine_v3/tex/veg/"
const SH_BARK := "res://assets/village_v2/veg_kit/veg_bark.gdshader"
const SH_LEAF := "res://assets/village_v2/veg_kit/veg_leaf.gdshader"

## 物種前綴 → [樹皮貼圖 id, 葉卡, 葉色乘數]
const SPEC := {
	"sakura_yama": ["sakura_bark", "sakura_card", Color(1.0, 1.0, 1.0)],
	"konara": ["japanese_zelkova_bark", "broad_card", Color(1.0, 1.0, 1.0)],
	"keyaki": ["japanese_zelkova_bark", "broad_dark_card", Color(1.0, 1.0, 1.0)],
	"momiji": ["japanese_zelkova_bark", "momiji_card", Color(1.0, 1.0, 1.0)],
	"sugi": ["japanese_cedar_bark", "sugi_card", Color(1.0, 1.0, 1.0)],
	"akamatsu": ["pine_bark", "sugi_card", Color(1.12, 1.10, 0.92)],
	"tsutsuji": ["japanese_zelkova_bark", "tsutsuji_card", Color(1.0, 1.0, 1.0)],
	"shrub": ["japanese_zelkova_bark", "broad_dark_card", Color(0.95, 1.0, 0.95)],
	"fern": ["japanese_zelkova_bark", "fern_card", Color(1.0, 1.0, 1.0)],
}


func _init() -> void:
	_run.call_deferred()


func _prefix(nm: String) -> String:
	for k in SPEC:
		if nm.begins_with(String(k)):
			return k
	return ""


func _bark(id: String) -> ShaderMaterial:
	var p := MAT + "bark_" + id + ".tres"
	var m := ShaderMaterial.new()
	m.shader = load(SH_BARK)
	m.set_shader_parameter("albedo_tex", load(PH + id + "_diff_1k.jpg"))
	m.set_shader_parameter("normal_tex", load(PH + id + "_nor_gl_1k.jpg"))
	m.set_shader_parameter("albedo_mul", 0.95)
	m.set_shader_parameter("roughness", 0.92)
	m.set_shader_parameter("specular", 0.18)
	m.resource_name = "s3_bark_" + id
	ResourceSaver.save(m, p)
	return load(p)


func _leaf(card: String, mul: Color) -> ShaderMaterial:
	var key := card + ("_t" if mul != Color(1, 1, 1) else "")
	var p := MAT + "leaf_" + key + ".tres"
	var m := ShaderMaterial.new()
	m.shader = load(SH_LEAF)
	m.set_shader_parameter("albedo_tex", load(CARDS + card + ".png"))
	m.set_shader_parameter("albedo_mul", 1.0)
	m.set_shader_parameter("roughness", 0.85)
	m.set_shader_parameter("specular", 0.25)
	m.set_shader_parameter("alpha_cut", 0.45)
	m.set_shader_parameter("translucency", 0.35)
	m.resource_name = "s3_leaf_" + key
	ResourceSaver.save(m, p)
	var mm: ShaderMaterial = load(p)
	return mm


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DST))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT))
	var bark_cache := {}
	var leaf_cache := {}
	var fails := 0
	var n := 0
	var files := DirAccess.get_files_at(SRC)
	for f in files:
		if not f.ends_with(".glb"):
			continue
		var nm := f.get_basename()
		var pre := _prefix(nm)
		if pre == "":
			push_error("未知物種 %s" % nm)
			fails += 1
			continue
		var spec: Array = SPEC[pre]
		var ps := load(SRC + f) as PackedScene
		if ps == null:
			push_error("讀不到 %s（先 --import）" % f)
			fails += 1
			continue
		var inst := ps.instantiate()
		var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
		var mesh := (mi.mesh as ArrayMesh).duplicate() as ArrayMesh
		inst.free()
		for i in mesh.get_surface_count():
			var sm := mesh.surface_get_material(i)
			var mn := sm.resource_name if sm != null else ""
			if mn.begins_with("bark"):
				if not bark_cache.has(spec[0]):
					bark_cache[spec[0]] = _bark(String(spec[0]))
				mesh.surface_set_material(i, bark_cache[spec[0]])
			else:
				var key := String(spec[1]) + str(spec[2])
				if not leaf_cache.has(key):
					leaf_cache[key] = _leaf(String(spec[1]), spec[2])
				mesh.surface_set_material(i, leaf_cache[key])
		mesh.resource_name = nm
		var e := ResourceSaver.save(mesh, DST + nm + ".res")
		n += 1
		print("[VEG] %-18s save=%d surfaces=%d aabb=%s" % [nm, e, mesh.get_surface_count(), mesh.get_aabb()])
	print("[VEG] done n=%d fails=%d" % [n, fails])
	_grass_clumps()
	quit(1 if fails > 0 else 0)


## 草叢網格（meadow_grass 的頂點約定：COLOR＝葉色、UV.y＝根→梢、UV2＝(相位, 剛性)、法線偏上）。3 種變體。
func _grass_clumps() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/village_v2/meadow/meadow_grass.gdshader")
	mat.set_shader_parameter("fade_out", Vector2(30.0, 38.0))
	mat.resource_name = "s3_grass"
	ResourceSaver.save(mat, MAT + "grass.tres")
	var gm: Material = load(MAT + "grass.tres")
	var rng := RandomNumberGenerator.new()
	for v in 3:
		rng.seed = 900 + v
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var nb := 26 + v * 6
		for b in nb:
			var ang := rng.randf() * TAU
			var r := rng.randf_range(0.0, 0.14 + 0.05 * v)
			var base := Vector3(cos(ang) * r, -0.03, sin(ang) * r)
			var h := rng.randf_range(0.12, 0.30 + 0.06 * v)
			var w := rng.randf_range(0.011, 0.02)
			var lean_dir := Vector3(cos(ang), 0, sin(ang)) if r > 0.02 else Vector3(1, 0, 0)
			var lean := rng.randf_range(0.10, 0.45)
			var face := lean_dir.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
			var side := face.cross(Vector3.UP).normalized()
			var dry := rng.randf() < 0.12
			var c0 := Color(0.13, 0.21, 0.07) if not dry else Color(0.30, 0.27, 0.12)
			var c1 := Color(0.44, 0.52, 0.20) if not dry else Color(0.62, 0.55, 0.30)
			var ph := rng.randf()
			var stiff := rng.randf_range(0.05, 0.35)
			var rows := []
			for k in 3:
				var t := float(k) / 2.0
				var p := base + Vector3.UP * h * t + face * lean * h * t * t
				var ww := w * (1.0 - t * 0.92)
				rows.append([p - side * ww, p + side * ww, t])
			var nrm := (face * -1.0).lerp(Vector3.UP, 0.6).normalized()
			for k in 2:
				var a: Array = rows[k]
				var bb: Array = rows[k + 1]
				var quad := [[a[0], 0.0, a[2]], [a[1], 1.0, a[2]], [bb[1], 1.0, bb[2]], [bb[0], 0.0, bb[2]]]
				for idx in [0, 1, 2, 0, 2, 3]:
					var q: Array = quad[idx]
					st.set_color(c0.lerp(c1, float(q[2])))
					st.set_uv(Vector2(float(q[1]), float(q[2])))
					st.set_uv2(Vector2(ph, stiff))
					st.set_normal(nrm)
					st.add_vertex(q[0])
		var mesh := st.commit()
		mesh.surface_set_material(0, gm)
		var p := DST + "grass_clump_v3_%s.res" % "abc"[v]
		var e := ResourceSaver.save(mesh, p)
		print("[VEG] grass_clump_v3_%s save=%d blades=%d aabb=%s" % ["abc"[v], e, nb, mesh.get_aabb()])
