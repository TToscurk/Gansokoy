extends SceneTree
## P10 R5a ROUND 3 診断：再生道（RoadBaseP10）の両脇に残る「舊路寬の直線の土色帯」の出どころを切り分ける（只讀、非 headless、Forward+、10:00）。
##   Godot --path . --script res://tools/diag_village_v2_road_band.gd -- <outdir/>
## 同じ機位で次を撮って比べる（使用者 ROUND 3 §3 A–D）：
##   V0 現行（全 overlay ON）
##   A  RoadBaseP10 OFF（元の道の帯）
##   B  対象 3 本の道の Mesh を隠す（地形だけが見える）
##   C  B＋地形の道路重み（P7 地形頂点の street＝UV2.y・trodden＝COLOR.r）を 0 にした診断 shader（地形の道路塗りを隔離）
##   D  B＋地形の重みの可視化（R＝street、G＝trodden、B＝farm、unshaded）
##   E  B＋P9 地被（GroundcoverP9／MeadowP9）を隠す
## 各機位の「道の芯から ±3.5 m」の帯の画素について、B→C・B→E の平均色差を出す（どの層が帯を作っているか）。
const PILOT_SHADER := "res://maps/village_v2/shaders_p10/ground_p10_pilot.gdshader"
const TERRAIN := ["Terrain/MainTerrain", "Terrain/NorthHill", "Terrain/FarmlandTerrain", "Terrain/RiverTerrain"]
const ROADS := ["Roads/FarmPaths/FarmPath_1", "Roads/FarmPaths/FarmPath_4", "Roads/SecondaryRoads/CrossStreetSouth"]
const VIEWS := [
	["grd_farmpath4_6m", 410.0, 0.0, 425.0, 0.0, -0.16, 2.8, 0.5],
	["r5a_farmpath1_n", 372.0, 30.0, 372.0, -10.0, -0.1, 3.6, 0.8],
	["grd_cross_south_edge_8m", 362.0, 44.0, 372.0, 41.0, -0.14, 3.0, 0.6],
	["r5a_farm_road_high", "free", 395.0, 38.0, 60.0, 372.0, 0.0, 15.0, 60],
]
const VIZ := """shader_type spatial;
render_mode unshaded, cull_back;
void fragment() {
	ALBEDO = vec3(UV2.y, COLOR.r, UV.y);
}
"""

var v: Node3D
var cam: Camera3D
var orig_mat := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var outdir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	v = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	for n in v.get_node("Districts").find_children("*ParcelLines*", "", true, false):
		n.visible = false
	await process_frame
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.set_hour(10.0)
	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 1200.0
	root.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame
	# 診断 shader：pilot shader の地形（mode 0）の street／trodden 重みを 0 に
	var code := FileAccess.get_file_as_string(PILOT_SHADER)
	var n1 := code.count("\t\tw[2] = a.r;")
	var n2 := code.count("\t\tw[1] = b.a;")
	var zero_sh := Shader.new()
	zero_sh.code = code.replace("\t\tw[2] = a.r;", "\t\tw[2] = 0.0;").replace("\t\tw[1] = b.a;", "\t\tw[1] = 0.0;")
	var viz_sh := Shader.new()
	viz_sh.code = VIZ
	print("[BAND] 診断 shader：置換 trodden %d・street %d 箇所" % [n1, n2])
	var report := {}
	for vw in VIEWS:
		_place(vw)
		var nm := String(vw[0])
		var imgs := {}
		for variant in ["V0", "A", "B", "C", "D", "E"]:
			_set_variant(variant, zero_sh, viz_sh)
			for i in 14:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.save_png(outdir + "%s_%s.png" % [nm, variant])
			imgs[variant] = img
		_set_variant("V0", zero_sh, viz_sh)
		report[nm] = {"B_vs_C": _diff(imgs["B"], imgs["C"]), "B_vs_E": _diff(imgs["B"], imgs["E"]), "V0_vs_A": _diff(imgs["V0"], imgs["A"]), "A_vs_B": _diff(imgs["A"], imgs["B"])}
		print("[BAND] %s %s" % [nm, JSON.stringify(report[nm])])
	var f := FileAccess.open(outdir + "band_diag.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	quit(0)


func _place(vw: Array) -> void:
	var sp := v.get_world_3d().direct_space_state
	if typeof(vw[1]) == TYPE_STRING:
		cam.fov = float(vw[8])
		var cp := Vector3(float(vw[2]), float(vw[3]), float(vw[4]))
		cam.global_transform = Transform3D(Basis(), cp).looking_at(Vector3(float(vw[5]), float(vw[6]), float(vw[7])), Vector3.UP)
		return
	cam.fov = 70.0
	var pp := Vector2(float(vw[1]), float(vw[2]))
	var tt := Vector2(float(vw[3]), float(vw[4]))
	var q := PhysicsRayQueryParameters3D.create(Vector3(pp.x, 120.0, pp.y), Vector3(pp.x, -40.0, pp.y))
	var gy := 0.0
	var ex: Array[RID] = []
	for k in 16:
		q.exclude = ex
		var hit := sp.intersect_ray(q)
		if hit.is_empty():
			break
		if String((hit.collider as Node).name).begins_with("TerrainCollision"):
			gy = hit.position.y
			break
		ex.append(hit.rid)
	var f := (tt - pp).normalized()
	var side := Vector2(-f.y, f.x)
	var pitch := float(vw[5])
	var dist := float(vw[6])
	var piv := Vector3(pp.x, gy + 1.6, pp.y) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
	var look := Vector3(f.x * cos(pitch), sin(pitch), f.y * cos(pitch))
	var cp2 := piv - look * dist + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
	cam.global_transform = Transform3D(Basis(), cp2).looking_at(cp2 + look, Vector3.UP)


func _set_variant(vn: String, zero_sh: Shader, viz_sh: Shader) -> void:
	var rb := v.get_node_or_null("RoadBaseP10")
	if rb:
		rb.set("enabled", vn != "A")
	for p in ROADS:
		(v.get_node(p) as Node3D).visible = vn in ["V0", "A"]
	for grp in ["Vegetation/GroundcoverP9", "Vegetation/MeadowP9"]:
		var g := v.get_node_or_null(grp) as Node3D
		if g:
			g.visible = vn != "E"
	for p in TERRAIN:
		var mi := v.get_node_or_null(p) as MeshInstance3D
		if mi == null:
			continue
		if not orig_mat.has(p):
			orig_mat[p] = mi.material_override
		var om := orig_mat[p] as ShaderMaterial
		if vn == "C":
			var m := om.duplicate() as ShaderMaterial
			m.shader = zero_sh
			mi.material_override = m
		elif vn == "D":
			var m2 := ShaderMaterial.new()
			m2.shader = viz_sh
			mi.material_override = m2
		else:
			mi.material_override = om


## 2 枚の差：画面下 2/3 の平均 |ΔRGB|（0–255）と、Δ > 12 の画素の割合
func _diff(a: Image, b: Image) -> Dictionary:
	var ia := a.duplicate() as Image
	var ib := b.duplicate() as Image
	ia.resize(400, 225, Image.INTERPOLATE_BILINEAR)
	ib.resize(400, 225, Image.INTERPOLATE_BILINEAR)
	var s := 0.0
	var big := 0
	var n := 0
	for y in range(75, 225):
		for x in 400:
			var ca := ia.get_pixel(x, y)
			var cb := ib.get_pixel(x, y)
			var d := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0 * 255.0
			s += d
			if d > 12.0:
				big += 1
			n += 1
	return {"mean_abs": snappedf(s / n, 0.01), "frac_gt12": snappedf(float(big) / n, 0.001)}
