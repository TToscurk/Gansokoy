extends RefCounted
## P8 Farmland pilot r4：水田可見層（確定性）。碰撞與量測在 village_v2_farmland_lib.gd。
## r4 成本架構（可擴全區）：秧苗與埂草改 MultiMesh 叢（每田 2 種叢網格 × 9 m 分塊 × 近／遠兩級 LOD，
##   visibility range 淡入淡出；PLANT_RANGE 外由水面 shader 行紋接手）；田埂、泥底、水面、灌排構件仍是可單獨選取的網格。
## 層次：遠＝田形與水面天空反射／秧苗行（水面 shader 行紋）；中＝圓鈍土草埂、岸邊濕泥、水口；
##       近＝秧苗株（行植但不等距、缺株、歪苗）、雜草、泥塊、腳印、小石、木板跨渠、堰板。
## 材質：地面＝P7 ground shader（_matlib，經 registry／matlib.json 取路徑，不寫 res:// 字串）；
##       木／石＝_matlib V2_Wood／V2_Stone（triplanar 副本）；水／植物＝maps/village_v2/shaders/。
const HLib := preload("res://tools/village_v2_hero_lib.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const WATER_SH := preload("res://maps/village_v2/shaders/p8_paddy_water.gdshader")
const PLANT_SH := preload("res://maps/village_v2/shaders/p8_paddy_plant.gdshader")
const PLANT_CHUNK := 9.0
const PLANT_VARIANTS := 2      # 每田叢網格種類（葉數 leaves−1／leaves+0）
const PLANT_NEAR := 24.0       # 全細節秧苗叢距離；之外換 3 三角形 LOD
const PLANT_RANGE := 110.0     # 秧苗網格可見距離（涵蓋正俯視 78 m；之外由水面 shader 行紋接手）
const FL := preload("res://tools/village_v2_farmland_lib.gd")
const WEED_NEAR := 35.0        # 旱田作物全細節距離（埂草改用 GRASS_*）
const WEED_RANGE := 120.0      # 旱田作物遠 LOD 可見距離
# 埂草／休耕草地（r6 hotspot）：全農田同一草叢網格＋材質，按 24 m 空間分塊 × 叢型合併成 MultiMesh
# （原為每 9 m × 叢型 × pilot／全區／每塊草地各自分組，1292 個節點）。
# 可見距離以分塊 AABB 中心起算（Godot 4.7 renderer_scene_cull：visibility range 與 fade 都用 transformed_aabb 中心），
# 分塊半對角約 17 m。近級＝全葉叢、全部 instance；遠級＝3 葉低面叢、保留 GRASS_FAR_KEEP 份（寬度補償）；
# GRASS_FAR 外不畫，由埂土／草地 ground shader 的草層接手。全部不投影；MultiMesh 設緊 custom_aabb。
const GRASS_CHUNK := 24.0
const GRASS_NEAR := 32.0
const GRASS_FAR := 65.0
const GRASS_FAR_KEEP := 0.45

# 各田狀態：stage＝株高 m、leaves＝每株葉數、row＝行距、hill＝株距、dir＝行向（度，0＝沿 +z）、
# miss＝缺株率、holes＝成片空洞強度、lean＝歪苗、col＝葉色(sRGB)、tip＝葉尖色、water＝水面參數、mud＝泥色層權重
const FIELD_STYLE := {
	"W1": {"stage": 0.17, "leaves": 4, "row": 0.30, "hill": 0.19, "dir": 4.0, "miss": 0.07, "holes": 0.35, "lean": 0.45,
		"col": Color(0.36, 0.49, 0.20), "tip": Color(0.52, 0.56, 0.28), "wobble": 0.06,
		"water": {"tint": Color(0.30, 0.28, 0.20), "clarity": 0.65, "rough": 0.05, "ripple": 0.7, "algae": 0.0},
		"mud": {"trodden": 0.18, "forest": 0.0}},
	"W2": {"stage": 0.30, "leaves": 6, "row": 0.30, "hill": 0.17, "dir": 94.0, "miss": 0.03, "holes": 0.15, "lean": 0.25,
		"col": Color(0.24, 0.40, 0.14), "tip": Color(0.34, 0.47, 0.19), "wobble": 0.04,
		"water": {"tint": Color(0.24, 0.25, 0.17), "clarity": 0.85, "rough": 0.04, "ripple": 0.5, "algae": 0.35},
		"mud": {"trodden": 0.0, "forest": 0.25}},
	"W3": {"stage": 0.24, "leaves": 5, "row": 0.31, "hill": 0.20, "dir": -8.0, "miss": 0.05, "holes": 0.55, "lean": 0.35,
		"col": Color(0.30, 0.45, 0.17), "tip": Color(0.44, 0.51, 0.23), "wobble": 0.07,
		"water": {"tint": Color(0.27, 0.27, 0.19), "clarity": 0.80, "rough": 0.06, "ripple": 0.9, "algae": 0.6},
		"mud": {"trodden": 0.05, "forest": 0.15}},
	"E1": {"stage": 0.38, "leaves": 7, "row": 0.30, "hill": 0.16, "dir": 91.0, "miss": 0.02, "holes": 0.1, "lean": 0.2,
		"col": Color(0.21, 0.37, 0.13), "tip": Color(0.30, 0.43, 0.16), "wobble": 0.03,
		"water": {"tint": Color(0.22, 0.23, 0.16), "clarity": 0.90, "rough": 0.03, "ripple": 0.4, "algae": 0.2},
		"mud": {"trodden": 0.0, "forest": 0.3}},
	"E2": {"stage": 0.19, "leaves": 4, "row": 0.29, "hill": 0.18, "dir": 12.0, "miss": 0.09, "holes": 0.6, "lean": 0.55,
		"col": Color(0.38, 0.50, 0.21), "tip": Color(0.56, 0.57, 0.30), "wobble": 0.08,
		"water": {"tint": Color(0.31, 0.28, 0.20), "clarity": 0.55, "rough": 0.06, "ripple": 0.8, "algae": 0.0},
		"mud": {"trodden": 0.25, "forest": 0.0}},
	"E3": {"stage": 0.27, "leaves": 5, "row": 0.30, "hill": 0.18, "dir": 82.0, "miss": 0.04, "holes": 0.3, "lean": 0.3,
		"col": Color(0.28, 0.43, 0.16), "tip": Color(0.39, 0.49, 0.21), "wobble": 0.05,
		"water": {"tint": Color(0.25, 0.26, 0.18), "clarity": 0.80, "rough": 0.05, "ripple": 0.6, "algae": 0.45},
		"mud": {"trodden": 0.05, "forest": 0.2}},
	# E4：田植え作業中——南半已植、北半剛代掻き（混濁、無苗），植付前線有苗束與腳印
	"E4": {"stage": 0.15, "leaves": 4, "row": 0.30, "hill": 0.19, "dir": 101.0, "miss": 0.05, "holes": 0.2, "lean": 0.5,
		"col": Color(0.40, 0.52, 0.22), "tip": Color(0.54, 0.57, 0.29), "wobble": 0.06, "front_z": 51.6,
		"water": {"tint": Color(0.36, 0.32, 0.23), "clarity": 0.42, "rough": 0.07, "ripple": 0.6, "algae": 0.0},
		"mud": {"trodden": 0.3, "forest": 0.0}},
}

static var _noise: FastNoiseLite
static var _ground_sh: Shader
static var _ground_tex := {}
static var _mats := {}
static var _weed_acc := {}

static func apply(root: Node3D, layout: Dictionary, P: Dictionary) -> void:
	_load_materials()
	_noise = FastNoiseLite.new()
	_noise.seed = 8108
	_noise.frequency = 0.35
	var banks := _group(root, "EarthBanks")
	var details := _group(root, "FieldDetails")
	var irrigation: Node3D = root.get_node("Irrigation")
	for fd: Dictionary in P["fields"]:
		var plot: Node3D = root.get_node("Plots/Plot_%s" % fd["name"])
		_field_art(plot, fd, layout)
	_weed_acc = {}
	for name: String in P["bunds"]:
		_bund_art(banks, details, name, P["bunds"][name], layout)
	_irrigation_art(irrigation, details, P, layout)
	_footprints(details, P, layout)
	if P.has("zone"):
		load(FL.ZONE_SCRIPT).art(root, P, layout)     # 全區擴張（r6）：支渠、水口、逐階水路、取水、排水、旱田／休耕、農具
	_emit_weeds(details)     # 埂草＋休耕草地（全區 art 也往 _weed_acc 加草）一起分塊
	root.set_meta("art_revision", "P8 pilot r4: segmented outer bunds following farm paths, bent lateral, premultiplied shallow water (sky Fresnel over visible mud), wet-mud bank transition, MultiMesh rice/weed clumps with LOD; lateral not yet connected to approved canal")

# ───────────────────────────── 田：泥底、水面、秧苗 ─────────────────────────────

static func _field_art(plot: Node3D, fd: Dictionary, layout: Dictionary) -> void:
	var n: String = fd["name"]
	var st: Dictionary = fd["style"] if fd.has("style") else FIELD_STYLE[n]     # 全區田（zone）自帶樣式
	var art := _group(plot, "FieldArt")
	var y: float = plot.get_meta("terrace_y")
	var lift: float = fd["lift"]
	var poly: PackedVector2Array = fd["water"]
	var tri := _tri_poly(poly, float(fd.get("tri_step", 0.55)))
	var pts: PackedVector2Array = tri[0]
	var idx: PackedInt32Array = tri[1]
	var edge := _edge_dist(pts, poly)
	var salt := float(n.hash() % 97)
	var front := float(st.get("front_z", 1e9))
	# 泥底：代掻き後の平滑面＋岸際の堆積＋少數露出泥塊；E4 北半剛代掻き（稍濕亮、耙痕）
	var mud_y := PackedFloat32Array()
	var st_mud: Dictionary = st["mud"]
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	for i in pts.size():
		var p := pts[i]
		var e: float = edge[i]
		var h := 0.013 + 0.006 * _n(p * 0.6 + Vector2(salt, 0)) + 0.004 * _n(p * 2.7)
		h += 0.012 * (1.0 - smoothstep(0.0, 1.2, e))                  # 岸際淤高
		# 岸際淺灘：沿岸斷續的泥灘露出水面 0.5–1.5 cm（濕泥帶，不是整圈）
		h += 0.026 * smoothstep(0.5, 0.78, _n(p * 0.33 + Vector2(salt * 2.0, 1.0))) * (1.0 - smoothstep(0.0, 0.7, e))
		var clod := smoothstep(0.62, 0.9, _n(p * 1.9 + Vector2(0, salt)))
		h += clod * 0.045 * (1.0 - smoothstep(0.5, 3.0, e))            # 岸際泥塊露頭
		if p.y > front:
			h += 0.005 * sin(p.x * 9.0 + _n(p) * 2.0)                 # 代掻き耙痕
		mud_y.append(y + h)
		var silt := smoothstep(0.45, 0.8, _n(p * 0.45 + Vector2(salt, 3.0)))
		var tr: float = clampf(st_mud["trodden"] * (0.6 + 0.4 * _n(p * 0.3)) + silt * 0.35 + clod * 0.4, 0.0, 1.0)
		var grav := 0.25 * (1.0 - smoothstep(0.0, 0.5, e)) * smoothstep(0.4, 0.7, _n(p * 2.2))
		cols.append(Color(tr, grav, 1.0, 0.0))
		uv.append(Vector2(st_mud["forest"] * (0.5 + 0.5 * _n(p * 0.25 + Vector2(salt, salt))), 0.0))
		uv2.append(Vector2(0.25 + 0.2 * _n(p * 0.8) + 0.5 * (1.0 - smoothstep(0.0, 0.9, e)), 0.0))   # 岸際更濕亮
	_mesh(art, "WetMudBottom", _build_mesh(pts, idx, mud_y, cols, uv, uv2, true), _mud_mat())
	# 水面：同一三角網、高＝本田水位；UV.x＝離岸距離（m）
	var wy := PackedFloat32Array()
	var wuv := PackedVector2Array()
	for i in pts.size():
		wy.append(y + lift)
		wuv.append(Vector2(edge[i], 0.0))
	var wm := _water_mat(n, st, fd)
	_mesh(art, "ShallowWater", _build_mesh(pts, idx, wy, PackedColorArray(), wuv, PackedVector2Array(), false), wm)
	# 淺水面與水下泥底不投影（水面不該有陰影；泥底在水下 2–4 cm，陰影讀不到）——全區擴張後陰影 pass 成本
	for nm: String in ["WetMudBottom", "ShallowWater"]:
		(art.get_node(nm) as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 秧苗：MultiMesh 叢（visibility range）；水口位置給冷水害（水口旁矮、黃）
	if not fd.has("inlet_xz"):
		var side := -1 if n.begins_with("W") else 1
		var iz: float = FL.INLET_Z[n]
		fd["inlet_xz"] = Vector2(FL.x_at(FL._lip(side), iz), iz)
	_seedlings(art, fd, st, y, layout)

static func _water_mat(n: String, st: Dictionary, fd: Dictionary) -> ShaderMaterial:
	var w: Dictionary = st["water"]
	var m := ShaderMaterial.new()
	m.shader = WATER_SH
	m.set_shader_parameter("water_tint", w["tint"])
	m.set_shader_parameter("clarity", w["clarity"])
	m.set_shader_parameter("rough_base", w["rough"])
	m.set_shader_parameter("ripple", w["ripple"])
	m.set_shader_parameter("algae", w["algae"])
	m.set_shader_parameter("seed", float(n.hash() % 50) * 0.37)
	# 遠景秧苗行紋（與網格同一行定義）
	var o: Vector2 = _plant_origin(fd)
	var ang := deg_to_rad(float(st["dir"]))
	m.set_shader_parameter("row_origin", o)
	m.set_shader_parameter("row_dir", Vector2(sin(ang), cos(ang)))
	m.set_shader_parameter("row_sp", st["row"])
	m.set_shader_parameter("hill_sp", st["hill"])
	m.set_shader_parameter("rice_color", st["col"])
	m.set_shader_parameter("rice_cov", clampf(float(st["stage"]) * 1.25 + float(st["leaves"]) * 0.03, 0.15, 0.75))
	m.set_shader_parameter("front_z", float(st.get("front_z", 1e9)))
	m.set_shader_parameter("lod_start", PLANT_RANGE - 18.0)
	m.set_shader_parameter("lod_end", PLANT_RANGE - 4.0)
	return m

static func _plant_origin(fd: Dictionary) -> Vector2:
	var bb := _bbox(fd["plant"])
	return bb.position

static func _seedlings(art: Node3D, fd: Dictionary, st: Dictionary, y: float, layout: Dictionary) -> void:
	var poly: PackedVector2Array = fd["plant"]
	var n: String = fd["name"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5501 + n.hash() % 1000
	var ang := deg_to_rad(float(st["dir"]))
	var d := Vector2(sin(ang), cos(ang))          # 沿行
	var nn := Vector2(-d.y, d.x)                  # 跨行
	var o := _plant_origin(fd)
	var bb := _bbox(poly)
	var rs: float = st["row"]
	var hs: float = st["hill"]
	var front := float(st.get("front_z", 1e9))
	var salt := float(n.hash() % 31)
	var inlet: Vector2 = fd.get("inlet_xz", Vector2(1e6, 1e6))
	var csz := float(fd.get("chunk", PLANT_CHUNK))
	# 投影範圍
	var amin := INF
	var amax := -INF
	var cmin := INF
	var cmax := -INF
	for p in poly:
		amin = minf(amin, (p - o).dot(d))
		amax = maxf(amax, (p - o).dot(d))
		cmin = minf(cmin, (p - o).dot(nn))
		cmax = maxf(cmax, (p - o).dot(nn))
	var meshes: Array = []
	for v in PLANT_VARIANTS:
		meshes.append(_clump_meshes(st, 900 + v * 17 + n.hash() % 97, int(st["leaves"]) - 1 + v))
	var chunks := {}
	var r0 := floori(cmin / rs)
	var r1 := ceili(cmax / rs)
	var hills := 0
	var skip := 0
	for ri in range(r0, r1 + 1):
		# 人工行列：每行起線偏差、微斜、手植的慢漂移（插秧繩拉不直）
		var row_c := ri * rs + rng.randf_range(-0.025, 0.025)
		var row_skew := rng.randf_range(-0.012, 0.012)
		var drift_ph := rng.randf() * TAU
		var drift_k := rng.randf_range(0.12, 0.3)
		var j0 := floori(amin / hs)
		var j1 := ceili(amax / hs)
		var start_jit := rng.randf_range(0.0, hs)
		# 行別活力：同一趟插秧的行長勢接近，少數行晚插／苗弱（矮、偏黃）
		var row_vig := rng.randf_range(0.9, 1.08) if rng.randf() > 0.12 else rng.randf_range(0.72, 0.85)
		for j in range(j0, j1 + 1):
			var a := j * hs + start_jit + rng.randf_range(-0.035, 0.035)
			var wob := float(st["wobble"]) * sin(a * 0.21 + ri * 0.77) + 0.03 * sin(a * drift_k + drift_ph) + rng.randf_range(-0.04, 0.04)
			var c := row_c + wob + a * row_skew
			var p := o + d * a + nn * c
			if not Geometry2D.is_point_in_polygon(p, poly):
				continue
			if p.y > front:
				continue
			if skip > 0:
				skip -= 1
				continue
			if rng.randf() < float(st["miss"]):
				if rng.randf() < 0.3:
					skip = rng.randi_range(1, 3)     # 連續缺株
				continue
			# 成片空洞（缺苗區）：低頻雜訊
			if _n(p * 0.22 + Vector2(0.0, n.hash() % 31)) > 1.0 - 0.28 * float(st["holes"]):
				continue
			var fert := _n(p * 0.16 + Vector2(salt, 7.0))                   # 地力斑
			var cold := 1.0 - smoothstep(0.0, 3.5, p.distance_to(inlet))    # 水口冷水
			var hsc := rng.randf_range(0.74, 1.2) * lerpf(0.8, 1.15, fert) * (1.0 - 0.3 * cold) * row_vig
			if front < 1e8 and p.y > front - 1.2:
				hsc *= 0.8
			var wsc := rng.randf_range(0.85, 1.15) * lerpf(0.9, 1.1, fert)
			var tilt := rng.randf_range(0.0, float(st["lean"]) * 0.9) if rng.randf() < 0.22 else rng.randf_range(0.0, 0.08)
			var tdir := rng.randf() * TAU
			var basis := Basis(Vector3(cos(tdir), 0.0, sin(tdir)), tilt) * Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(wsc, hsc, wsc))
			var k := rng.randf_range(-0.1, 0.07)
			# 色澤：肥處偏藍綠（深）、瘦處／弱行偏黃；個株 ±
			var ic := Color(0.87 + k - 0.05 * fert, 0.87 + k, 0.87 + k + 0.04 * fert)
			var yellow := clampf((1.0 - fert) * 0.55 + cold * 0.8 + (1.0 - row_vig) * 1.5 - 0.15, 0.0, 1.0) * rng.randf_range(0.5, 1.0)
			ic = ic.lerp(Color(1.0, 0.94, 0.62), yellow * 0.6)
			ic = (ic * lerpf(1.04, 0.9, fert)).clamp(Color(0, 0, 0, 1), Color(1, 1, 1, 1))
			var v := rng.randi() % PLANT_VARIANTS
			_add_inst(chunks, p, v, Transform3D(basis, Vector3(p.x, y + 0.012, p.y)), ic, csz)
			hills += 1
			if rng.randf() < 0.018:
				# 補植：旁邊一株較小的苗
				var q := p + d * rng.randf_range(0.05, 0.08) * (1.0 if rng.randf() < 0.5 else -1.0)
				var b2 := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(wsc * 0.8, hsc * 0.6, wsc * 0.8))
				_add_inst(chunks, q, (v + 1) % PLANT_VARIANTS, Transform3D(b2, Vector3(q.x, y + 0.012, q.y)), ic * 1.0, csz)
				hills += 1
	var mat := _plant_mat()
	var ci := 0
	for key: Vector3i in chunks:
		var inst: Array = chunks[key]
		for lod in 2:
			var nm := "RiceSeedlings_%02d_v%d_%s" % [ci, key.z, "near" if lod == 0 else "far"]
			if lod == 0:
				_mm_node(art, nm, meshes[key.z][0], inst[0], inst[1], mat, 0.0, 0.0, PLANT_NEAR, 4.0)
			else:
				_mm_node(art, nm, meshes[key.z][1], inst[0], inst[1], mat, PLANT_NEAR, 4.0, PLANT_RANGE, 8.0)
		ci += 1
	art.set_meta("rice_hills", hills)
	# E4：植付前線的苗束（束ねた苗）
	if front < 1e8:
		var trng := RandomNumberGenerator.new()
		trng.seed = 77
		var st2: SurfaceTool = SurfaceTool.new()
		st2.begin(Mesh.PRIMITIVE_TRIANGLES)
		var placed := 0
		for i in 40:
			var p := Vector2(trng.randf_range(bb.position.x + 1.0, bb.end.x - 1.0), trng.randf_range(front + 0.8, bb.end.y - 0.8))
			if not Geometry2D.is_point_in_polygon(p, poly):
				continue
			for b in 16:
				var q := p + Vector2(trng.randf_range(-0.05, 0.05), trng.randf_range(-0.05, 0.05))
				_blade(st2, Vector3(q.x, y + 0.02, q.y), trng.randf() * TAU, trng.randf_range(0.2, 0.55), 0.14 + trng.randf() * 0.06, 0.009, st["col"], st["tip"])
			placed += 1
			if placed >= 7:
				break
		var bundles := MeshInstance3D.new()
		bundles.name = "SeedlingBundles"
		bundles.mesh = st2.commit()
		bundles.material_override = _plant_mat()
		art.add_child(bundles)

static func _add_inst(chunks: Dictionary, p: Vector2, v: int, xf: Transform3D, col: Color, csz := PLANT_CHUNK) -> void:
	var key := Vector3i(floori(p.x / csz), floori(p.y / csz), v)
	if not chunks.has(key):
		chunks[key] = [[], []]
	chunks[key][0].append(xf)
	chunks[key][1].append(col)

## 秧苗叢網格（本田株高、葉色；原點＝株基）：近＝leaves 片 × 3 三角形，遠＝3 片 × 1 三角形。
## 頂點色＝葉色 × 1.15（instance color 基準 0.87 → 乘回原色；instance 可往暗／黃變化）
static func _clump_meshes(st: Dictionary, seed: int, leaves: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hi := SurfaceTool.new()
	hi.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := SurfaceTool.new()
	lo.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h: float = st["stage"]
	var col := _vc(st["col"])
	var tip := col.lerp(_vc(st["tip"]), 0.45)
	leaves = maxi(leaves, 3)
	var yaw0 := rng.randf() * TAU
	for i in leaves:
		var az := yaw0 + TAU * i / leaves + rng.randf_range(-0.35, 0.35)
		var spread := rng.randf_range(0.12, 0.42)
		var jit := Vector3(rng.randf_range(-0.012, 0.012), 0, rng.randf_range(-0.012, 0.012))
		var bh := h * rng.randf_range(0.8, 1.05)
		_blade(hi, jit, az, spread, bh, 0.0075, col, tip)
		if i < 3:
			_blade_lo(lo, jit, az, spread, bh, 0.012, col, tip)
	return [hi.commit(), lo.commit()]

static func _vc(c: Color) -> Color:
	return Color(minf(c.r * 1.15, 1.0), minf(c.g * 1.15, 1.0), minf(c.b * 1.15, 1.0))

## MultiMesh 分塊節點（秧苗／埂草共用）：不投影（小葉片陰影在 1.7 m 讀不到、成本高），visibility range 自身淡入淡出
static func _mm_node(parent: Node3D, name: String, mesh: Mesh, xfs: Array, cols: Array, mat: Material, vr_begin: float, vr_begin_margin: float, vr_end: float, vr_end_margin: float, tight_aabb := false) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	var mab := mesh.get_aabb()
	var ab := AABB()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
		if tight_aabb:
			var ib: AABB = (xfs[i] as Transform3D) * mab
			ab = ib if i == 0 else ab.merge(ib)
	# 草分塊：緊 AABB（instance 變換後網格框的聯集＋葉尖擺動 4 cm）；剔除與 visibility range 的分塊中心都以此為準，載入不需重算
	if tight_aabb:
		mm.custom_aabb = ab.grow(0.04)
	var node := MultiMeshInstance3D.new()
	node.name = name
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_begin = vr_begin
	node.visibility_range_begin_margin = vr_begin_margin
	node.visibility_range_end = vr_end
	node.visibility_range_end_margin = vr_end_margin
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(node)

## 一片葉：基部 → 中段 → 葉尖（外彎下垂），3 三角形；UV.y＝高度比例
static func _blade(t: SurfaceTool, base: Vector3, az: float, lean: float, h: float, w: float, col: Color, tip: Color) -> void:
	var dir := Vector3(cos(az), 0, sin(az))
	var side := Vector3(-dir.z, 0, dir.x)
	var p0 := base
	var p1 := base + dir * (lean * h * 0.35) + Vector3.UP * h * 0.6
	var p3 := base + dir * (lean * h * 1.3 + h * 0.18) + Vector3.UP * h * (1.0 - lean * 0.5)
	var up_n := (Vector3.UP * 0.8 + dir * 0.4).normalized()
	var pts := [p0 - side * w, p0 + side * w, p1 - side * w * 0.8, p1 + side * w * 0.8, p3]
	var vs := [0.0, 0.0, 0.6, 0.6, 1.0]
	var tris := [[0, 1, 2], [1, 3, 2], [2, 3, 4]]
	for tr: Array in tris:
		for k: int in tr:
			var v: float = vs[k]
			t.set_color(col.lerp(tip, smoothstep(0.55, 1.0, v)))
			t.set_uv(Vector2(0.0, v))
			t.set_normal(up_n)
			t.add_vertex(pts[k])

## 遠 LOD 葉：單一三角形
static func _blade_lo(t: SurfaceTool, base: Vector3, az: float, lean: float, h: float, w: float, col: Color, tip: Color) -> void:
	var dir := Vector3(cos(az), 0, sin(az))
	var side := Vector3(-dir.z, 0, dir.x)
	var p3 := base + dir * (lean * h * 1.1 + h * 0.1) + Vector3.UP * h * (1.0 - lean * 0.4)
	var up_n := (Vector3.UP * 0.8 + dir * 0.4).normalized()
	for k in 3:
		var v := 1.0 if k == 2 else 0.0
		t.set_color(col.lerp(tip, v * 0.6))
		t.set_uv(Vector2(0.0, v * 0.8 + 0.2))
		t.set_normal(up_n)
		t.add_vertex([base - side * w, base + side * w, p3][k])

# ───────────────────────────── 田埂：圓鈍土草埂 ─────────────────────────────

const PROF_U := [-1.25, -1.0, -0.82, -0.6, -0.35, -0.12, 0.12, 0.35, 0.6, 0.82, 1.0, 1.25]

static func _bund_art(banks: Node3D, details: Node3D, name: String, d: Dictionary, layout: Dictionary) -> void:
	var cls: Dictionary = FL.BUND_CLASS[d["cls"]]
	var L: float = d["length"]
	var pts: PackedVector2Array = d["pts"]
	var steps := maxi(4, ceili(L / float(d.get("step", 0.22))))
	var nu := PROF_U.size()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var walked: bool = d["walked"]
	var salt := float(d["salt"])
	var water := 0.05
	# 外埂外側＝寬緩草坡（畦畔法面）、寬度沿埂變化 1.4–2.8 倍：外緣不再是一圈等寬的框線
	var outer := String(d["cls"]).begins_with("outer")
	var ctr: Vector2 = d.get("ctr", Vector2(404.0, 34.0))     # 外坡朝外判定用的田區中心（全區田埂＝所在平台塊中心）
	for i in steps + 1:
		var s := L * float(i) / steps
		var at: Array = FL.at_s(pts, s)
		var c: Vector2 = at[0]
		var tan: Vector2 = at[1]
		var nrm := Vector2(-tan.y, tan.x)
		var ev := FL.bund_eval(d, s)
		var bh := float(cls["base_half"]) * float(ev["ws"])
		var base_y := TLib.farm_level(layout, c)
		for u: float in PROF_U:
			var ua := u - float(ev["asym"]) * (1.0 - absf(u))
			var pr := FL.profile(ua, walked and float(ev["notch"]) < 0.3)
			var lump := 0.012 * _n(c * 3.1 + Vector2(u * 2.0, salt)) + 0.006 * _n(c * 9.0 + Vector2(u * 5.0, 0))
			var hgt: float
			if pr < 0.0:
				hgt = pr + 0.004
			else:
				hgt = float(ev["h"]) * pr + lump * pr
			var lat := u * bh
			if outer and signf(u) == signf(nrm.dot(c - ctr)) and absf(u) > 0.35:
				var fk := 1.4 + 1.4 * _n(c * 0.33 + Vector2(salt, 3.0))
				lat = signf(u) * (0.35 * bh + (absf(u) - 0.35) * bh * fk)
				hgt *= lerpf(1.0, 0.8, smoothstep(0.6, 1.0, absf(u)))
			var p := c + nrm * (float(ev["off"]) + lat)
			verts.append(Vector3(p.x, base_y + hgt, p.y))
			# 地面層權重：COLOR＝trodden,gravel,mud,rock；UV＝forest,farm；UV2＝wet,street（grass＝其餘）
			var au := absf(ua)
			var top := 1.0 - smoothstep(0.18, 0.55, au)
			var foot := smoothstep(0.62, 0.95, au)
			var nz := _n(c * 0.9 + Vector2(salt, u))
			var trod := top * (0.85 if walked else 0.12 + 0.2 * smoothstep(0.3, 0.8, nz))
			trod = maxf(trod, float(ev["tread"]) * top)
			var toe := smoothstep(0.86, 1.08, au)
			# 濕泥過渡：水線下＝泥；水線上 0–5 cm 泥→濕土漸層（上緣隨毛細水不規則）
			var above := hgt - water
			var mud := toe * 0.9
			mud = maxf(mud, (1.0 - smoothstep(0.0, 0.04 + 0.03 * _n(c * 1.3 + Vector2(u, salt)), above)) * smoothstep(0.5, 0.9, au) * 0.85)
			mud = maxf(mud, float(ev["notch"]) * 0.9)
			# 側坡：土露出斑塊（畦塗り剝落）＋草；頂：常走＝踏み固め、少走＝草
			var grav := 0.35 * smoothstep(0.55, 0.85, _n(c * 2.3 + Vector2(u, salt * 0.5))) * (1.0 - foot)
			var wet := clampf(1.0 - above / (0.06 + 0.05 * _n(c * 2.1 + Vector2(salt, u))), 0.0, 1.0) * 0.85
			trod = maxf(trod, foot * (1.0 - toe) * 0.55 * smoothstep(0.35, 0.7, _n(c * 1.6 + Vector2(u * 3.0, salt))))
			wet = maxf(wet, float(ev["notch"]) * 0.7)
			cols.append(Color(clampf(trod, 0.0, 1.0), grav, clampf(mud, 0.0, 1.0), 0.0))
			uvs.append(Vector2(0.12 * (1.0 - top) * (1.0 - foot) * smoothstep(0.2, 0.8, nz), 0.0))
			uv2s.append(Vector2(wet, 0.0))
	var idx := PackedInt32Array()
	for i in steps:
		for k in nu - 1:
			var a := i * nu + k
			var b := a + nu
			idx.append_array([a, a + 1, b, a + 1, b + 1, b])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	_mesh(banks, "Earth_%s" % name, _commit_up(arr), _bank_mat())
	_bund_weeds(details, name, d, layout)

## 埂草：肩部較密、常走的埂頂稀疏；少數高莖（稗、狗尾草）；小石與掉落泥塊。
## 草叢收進 _weed_acc（全農田 GRASS_CHUNK 分塊 × 叢型），最後由 _emit_weeds 產生 MultiMesh。
static func _bund_weeds(details: Node3D, name: String, d: Dictionary, layout: Dictionary) -> void:
	var cls: Dictionary = FL.BUND_CLASS[d["cls"]]
	var L: float = d["length"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + int(d["salt"]) * 13
	var walked: bool = d["walked"]
	var detail := float(d.get("detail", 1.0))            # 全區田埂：草／小石密度係數（成本）
	var tufts := int(L * (22.0 if walked else 34.0) * detail)   # 畦畔草：肩坡幾乎連續覆蓋
	for i in tufts:
		var s := rng.randf() * L
		var ev := FL.bund_eval(d, s)
		if float(ev["notch"]) > 0.2:
			continue
		var u := rng.randf_range(-1.02, 1.02)
		if absf(u) < 0.45 and rng.randf() < (0.9 if walked else 0.5):
			u = signf(u + 1e-3) * rng.randf_range(0.45, 1.0)   # 埂頂常走 → 草推到肩坡
		var at: Array = FL.at_s(d["pts"], s)
		var c: Vector2 = at[0]
		var tan: Vector2 = at[1]
		var nrm := Vector2(-tan.y, tan.x)
		var bh := float(cls["base_half"]) * float(ev["ws"])
		var p := c + nrm * (float(ev["off"]) + u * bh)
		var ua := u - float(ev["asym"]) * (1.0 - absf(u))
		var hy := TLib.farm_level(layout, c) + maxf(FL.profile(ua, walked), 0.0) * float(ev["h"]) - 0.006
		var patch := _n(c * 0.7 + Vector2(d["salt"], 0))
		var kind := 0 if rng.randf() < 0.55 else 1
		var hgt := rng.randf_range(0.06, 0.2) * (1.0 + patch * 0.6)
		if rng.randf() < 0.08:
			kind = 2
			hgt = rng.randf_range(0.3, 0.55)
		var g := Color(0.34, 0.45, 0.18).lerp(Color(0.52, 0.53, 0.26), rng.randf() * 0.7 + patch * 0.3)
		if rng.randf() < 0.12:
			g = Color(0.58, 0.52, 0.30)   # 枯葉
		var sx := hgt * rng.randf_range(0.8, 1.2)
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(sx, hgt, hgt * rng.randf_range(0.8, 1.2)))
		grass_add(p, kind, Transform3D(basis, Vector3(p.x, hy, p.y)), (g * 1.1).clamp(Color(0, 0, 0, 1), Color(1, 1, 1, 1)))
	# 小石：常走的埂頂與埂腳
	var rocks := SurfaceTool.new()
	rocks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nrock := int(L * (0.9 if walked else 0.4) * detail)
	for i in nrock:
		var s := rng.randf() * L
		var ev := FL.bund_eval(d, s)
		var u := rng.randf_range(-1.0, 1.0)
		var at: Array = FL.at_s(d["pts"], s)
		var c: Vector2 = at[0]
		var nrm := Vector2(-(at[1] as Vector2).y, (at[1] as Vector2).x)
		var bh := float(cls["base_half"]) * float(ev["ws"])
		var p := c + nrm * (float(ev["off"]) + u * bh)
		var ua := u - float(ev["asym"]) * (1.0 - absf(u))
		var hy := TLib.farm_level(layout, c) + maxf(FL.profile(ua, walked), 0.0) * float(ev["h"])
		_rock(rocks, Vector3(p.x, hy - 0.01, p.y), rng.randf_range(0.03, 0.09), rng)
	if nrock > 0:
		_mesh(details, "Pebbles_%s" % name, _finish(rocks), _stone_mat())
		_detail_range(details.get_node("Pebbles_%s" % name), d)
	# 掉落泥塊（畦塗りの名残）：埂腳水邊
	var clods := SurfaceTool.new()
	clods.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in int(L * 0.35 * detail):
		var s := rng.randf() * L
		var ev := FL.bund_eval(d, s)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var at: Array = FL.at_s(d["pts"], s)
		var c: Vector2 = at[0]
		var nrm := Vector2(-(at[1] as Vector2).y, (at[1] as Vector2).x)
		var bh := float(cls["base_half"]) * float(ev["ws"])
		var p := c + nrm * (float(ev["off"]) + side * bh * rng.randf_range(1.0, 1.35))
		_rock(clods, Vector3(p.x, TLib.farm_level(layout, c) + 0.012, p.y), rng.randf_range(0.05, 0.12), rng, 0.45, Color(0.26, 0.22, 0.16))
	if int(L * 0.35 * detail) > 0:
		_mesh(details, "MudClods_%s" % name, _finish(clods), _clod_mat())
		_detail_range(details.get_node("MudClods_%s" % name), d)

## 草叢加入空間分塊（埂草與休耕草地共用）：instance 變換＝位置／方位／草高與寬，instance color＝每叢色差（含枯葉）
static func grass_add(p: Vector2, kind: int, xf: Transform3D, col: Color) -> void:
	var key := Vector3i(floori(p.x / GRASS_CHUNK), floori(p.y / GRASS_CHUNK), kind)
	if not _weed_acc.has(key):
		_weed_acc[key] = [[], []]
	_weed_acc[key][0].append(xf)
	_weed_acc[key][1].append(col)

## 草 MultiMesh：叢型 0＝短草 6 葉、1＝細密 8 葉、2＝高莖 3 葉（稗、狗尾草）；網格高度正規化為 1（instance 縮放＝草高）。
## 每分塊 × 叢型兩個節點：近級（全葉、全部）＋遠級（低面、確定性抽 GRASS_FAR_KEEP 份、寬 ×1.3 補覆蓋）
static func _emit_weeds(details: Node3D) -> void:
	var meshes: Array = []
	for kind in 3:
		meshes.append(_tuft_meshes(kind))
	var mat := _plant_mat()
	var g := _group(details, "GrassChunks")
	var keys := _weed_acc.keys()
	keys.sort()
	for key: Vector3i in keys:
		var inst: Array = _weed_acc[key]
		var nm := "Grass_%d_%d_k%d" % [key.x, key.y, key.z]
		_mm_node(g, nm + "_near", meshes[key.z][0], inst[0], inst[1], mat, 0.0, 0.0, GRASS_NEAR, 4.0, true)
		var fx: Array = []
		var fc: Array = []
		var widen := Basis.from_scale(Vector3(1.3, 1.0, 1.3))
		for i in inst[0].size():
			var xf: Transform3D = inst[0][i]
			if _n(Vector2(xf.origin.x, xf.origin.z) * 3.7) * 0.5 + fposmod(float(i) * 0.618034, 1.0) * 0.5 < GRASS_FAR_KEEP:
				fx.append(Transform3D(xf.basis * widen, xf.origin))
				fc.append(inst[1][i])
		if not fx.is_empty():
			_mm_node(g, nm + "_far", meshes[key.z][1], fx, fc, mat, GRASS_NEAR, 4.0, GRASS_FAR, 6.0, true)
	_weed_acc = {}

static func _tuft_meshes(kind: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 313 + kind * 71
	var hi := SurfaceTool.new()
	hi.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := SurfaceTool.new()
	lo.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades: int = [6, 8, 3][kind]
	var w: float = [0.045, 0.035, 0.014][kind]
	var jit: float = [0.3, 0.35, 0.1][kind]
	var lean_lo: float = [0.2, 0.3, 0.05][kind]
	var lean_hi: float = [0.7, 0.8, 0.3][kind]
	for b in blades:
		var base := Vector3(rng.randf_range(-jit, jit), 0.0, rng.randf_range(-jit, jit))
		var az := rng.randf() * TAU
		var lean := rng.randf_range(lean_lo, lean_hi)
		var bh := rng.randf_range(0.6, 1.0)
		_blade(hi, base, az, lean, bh, w, Color(0.82, 0.82, 0.82), Color(1, 1, 1))
		if b < 3:
			_blade_lo(lo, base, az, lean, bh, w * 1.6, Color(0.82, 0.82, 0.82), Color(1, 1, 1))
	return [hi.commit(), lo.commit()]

# ───────────────────────────── 灌排：內渠、水口、落水口、分水堰、排水溝、木板橋 ─────────────────────────────

static func _irrigation_art(irr: Node3D, details: Node3D, P: Dictionary, layout: Dictionary) -> void:
	var ch: PackedVector2Array = FL._round(P["channel"], FL.CORNER_R)
	var y0 := TLib.farm_level(layout, ch[0])
	# 渠底（泥）＋渠水（兩段水位，分水堰隔開）
	_ribbon(irr, "LateralBed", ch, FL.LIP_OFF + 0.05, func(p: Vector2, u: float) -> float: return TLib.farm_level(layout, p) + 0.012 + 0.006 * _n(p * 3.0 + Vector2(u, 0)), _ground_mat(), Color(0.1, 0.25, 1.0, 0.0), Vector2(1.0, 0.0), 0.0, 1e9)
	var wmat := _flow_mat(0.9, Color(0.30, 0.29, 0.21), 0.55)
	_ribbon(irr, "LateralWater_S", ch, FL.CH_WATER_HALF, func(p: Vector2, u: float) -> float: return TLib.farm_level(layout, p) + FL.CH_WATER_S, wmat, Color(), Vector2(), 0.0, FL.CHECK_WEIR_Z, true)
	_ribbon(irr, "LateralWater_N", ch, FL.CH_WATER_HALF, func(p: Vector2, u: float) -> float: return TLib.farm_level(layout, p) + FL.CH_WATER_N, wmat, Color(), Vector2(), FL.CHECK_WEIR_Z, FL.N_JOIN + 0.2, true)
	# 排水溝
	var dr: PackedVector2Array = P["drain"]
	_ribbon(irr, "DrainBed", dr, FL.DRAIN_HALF + 0.05, func(p: Vector2, u: float) -> float: return TLib.farm_level(layout, p) + 0.008 + 0.005 * _n(p * 3.0), _ground_mat(), Color(0.05, 0.2, 1.0, 0.0), Vector2(1.0, 0.0), -1e9, 1e9)
	# 排水溝水：混濁、較粗（落水帶泥；正俯視的日光鏡面不成白帶）
	var dmat := _flow_mat(0.4, Color(0.30, 0.27, 0.19), 0.3)
	dmat.set_shader_parameter("rough_base", 0.32)
	dmat.set_shader_parameter("algae", 0.5)
	_ribbon(irr, "DrainWater", dr, FL.DRAIN_HALF, func(p: Vector2, u: float) -> float: return TLib.farm_level(layout, p) + FL.DRAIN_WATER_LIFT, dmat, Color(), Vector2(), -1e9, 1e9, true)
	var wood := _wood_mat()
	var stone := _stone_mat()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# 分水堰（板堰）：兩根木樁＋三片疊板
	var cz := FL.CHECK_WEIR_Z
	var cx := FL.x_at(P["channel"], cz)
	var weir := _group(details, "CheckWeir")
	for side in [-1, 1]:
		_box(weir, "Post_%d" % side, Vector3(cx + side * 0.34, y0 + 0.2, cz), Vector3(0.09, 0.42, 0.09), wood, rng.randf_range(-0.05, 0.05))
	for k in 3:
		_box(weir, "Board_%d" % k, Vector3(cx, y0 + 0.018 + k * 0.024, cz + 0.02), Vector3(0.62, 0.024, 0.035), wood, rng.randf_range(-0.03, 0.03))
	# 取水（r5）：水渠 → 水車 2 → 短落とし樋 → 上段土渠 → 伏越し（FarmPath_1 路下）→ 地面木槽 → 內渠南端
	# （幾何常數在 lib；碰撞在 lib._supply_body）
	var head := _group(details, "WaterSupply")
	_supply_art(head, irr, P, layout, wood, stone, rng)
	var hp: Vector2 = P["channel"][0]
	for k in 6:
		var a := float(k) / 5.0 * PI
		_rock_node(head, "SplashStone_%d" % k, Vector3(hp.x + cos(a) * 0.5, TLib.farm_level(layout, hp) + 0.03, hp.y + 0.35 + sin(a) * 0.25), rng.randf_range(0.07, 0.12), rng, stone)
	# 排水溝東端：石組みの小桝
	var de := dr[dr.size() - 1]
	var box := _group(details, "DrainOutletBox")
	for k in 4:
		var a := k * PI * 0.5
		_box(box, "Stone_%d" % k, Vector3(de.x + cos(a) * 0.38, 0.06, de.y + sin(a) * 0.38), Vector3(0.28 if k % 2 == 0 else 0.62, 0.16, 0.62 if k % 2 == 0 else 0.28), stone, rng.randf_range(-0.1, 0.1))
	# 水口與落水口（pilot 田；全區田埂的水口由 zone.art 產生）
	for bn: String in P["bunds"]:
		var d: Dictionary = P["bunds"][bn]
		if d.has("zone"):
			continue
		for no: Dictionary in d["notches"]:
			if no["kind"] == "tread" or no["kind"] == "tap":     # tap＝P11 R2D 支線の分水切欠き（art は zone.branch_art）
				continue
			var at: Array = FL.at_s(d["pts"], float(no["s"]))
			var c: Vector2 = at[0]
			var tan: Vector2 = at[1]
			var nrm := Vector2(-tan.y, tan.x)
			var y := TLib.farm_level(layout, c)
			var g := _group(details, "%s_%s" % ["Inlet" if no["kind"] == "inlet" else "Outlet", no["field"]])
			var yaw := atan2(tan.x, tan.y)
			if no["kind"] == "outlet":
				# 堰板：插在缺口，頂＝上游田水位
				var fl: float = FL.FIELD_LIFT[no["field"]]
				_box(g, "WeirBoard", Vector3(c.x, y + fl * 0.5 + 0.01, c.y), Vector3(0.04, fl + 0.05, float(no["w"]) + 0.12), wood, yaw + PI * 0.5 + rng.randf_range(-0.08, 0.08))
				for k in 2:
					var sd := -1.0 if k == 0 else 1.0
					_rock_node(g, "Stone_%d" % k, Vector3(c.x + tan.x * sd * 0.34, y + 0.03, c.y + tan.y * sd * 0.34), rng.randf_range(0.07, 0.11), rng, stone)
			else:
				# 水口：開口，石塊夾兩側；渠水經缺口斜落田面（小水流面）
				var fl2: float = FL.FIELD_LIFT[no["field"]]
				var out_dir := nrm if (c + nrm).x < FL.x_at(P["channel"], c.y) == (c.x < FL.x_at(P["channel"], c.y)) else -nrm
				out_dir = (c - Vector2(FL.x_at(P["channel"], c.y), c.y)).normalized()
				var spill := PackedVector2Array([c - out_dir * 0.45, c + out_dir * 0.55])
				var fl_ch := FL.CH_WATER_S if c.y < FL.CHECK_WEIR_Z else FL.CH_WATER_N
				_ribbon(g, "Spill", spill, 0.2, func(p: Vector2, u: float) -> float:
					var tt := clampf((p - spill[0]).dot(out_dir) / 1.0, 0.0, 1.0)
					return y + lerpf(fl_ch, fl2, tt) + 0.004, _flow_mat(1.4, Color(0.34, 0.32, 0.24), 0.5), Color(), Vector2(), -1e9, 1e9, true)
				for k in 3:
					var sd := -1.0 if k % 2 == 0 else 1.0
					_rock_node(g, "Stone_%d" % k, Vector3(c.x + tan.x * sd * rng.randf_range(0.3, 0.38) + out_dir.x * (k - 1) * 0.2, y + 0.04, c.y + tan.y * sd * 0.34 + out_dir.y * (k - 1) * 0.2), rng.randf_range(0.07, 0.12), rng, stone)
				if no["field"] in ["W2", "E3"]:
					# 閉じた水口：板で止めて泥を盛る
					_box(g, "ShutBoard", Vector3(c.x, y + 0.06, c.y), Vector3(0.035, 0.12, 0.5), wood, yaw + PI * 0.5)
	# 木板跨渠（2 處）＋跨排水溝（1 處）
	for spec: Array in [[28.8, 3], [47.2, 2]]:
		var z: float = spec[0]
		var x := FL.x_at(P["channel"], z)
		var pb := _group(details, "PlankCrossing_%d" % int(z))
		for k: int in spec[1]:
			_box(pb, "Plank_%d" % k, Vector3(x + rng.randf_range(-0.03, 0.03), 0.28 + k * 0.004, z + (k - (spec[1] - 1) * 0.5) * 0.2), Vector3(1.55 + rng.randf_range(-0.1, 0.1), 0.045, 0.18), wood, PI * 0.5 + rng.randf_range(-0.07, 0.07))
	var dz := FL.project_s(dr, Vector2(396.0, 61.2))
	var dat: Array = FL.at_s(dr, dz)
	var dp: Vector2 = dat[0]
	var dpb := _group(details, "PlankCrossing_Drain")
	for k in 2:
		_box(dpb, "Plank_%d" % k, Vector3(dp.x + k * 0.21 - 0.1, 0.17, dp.y), Vector3(0.19, 0.045, 1.9), wood, atan2((dat[1] as Vector2).x, (dat[1] as Vector2).y) + PI * 0.5 + rng.randf_range(-0.05, 0.05))

# ───────────────────────────── 腳印 ─────────────────────────────

## 木樋段（底板＋兩側板＋內水面＋箍）：a→b 為樋底中心線（世界座標）
static func _trough_seg(seg: Node3D, a: Vector3, b: Vector3, W: float, wall: float, depth: float, wood: Material, fmat: Material) -> void:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var L := d.length()
	var yaw := atan2(d.x, d.y)
	var pitch := atan2(a.y - b.y, L)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var mid := (a + b) * 0.5
	var parts := [["Bottom", Vector3(0, -0.02, 0), Vector3(W, 0.04, L + 0.04)],
		["SideL", Vector3(-W * 0.5 + 0.018, wall * 0.5 - 0.04, 0), Vector3(0.036, wall + 0.04, L + 0.04)],
		["SideR", Vector3(W * 0.5 - 0.018, wall * 0.5 - 0.04, 0), Vector3(0.036, wall + 0.04, L + 0.04)]]
	for pt: Array in parts:
		var m := BoxMesh.new()
		m.size = pt[2]
		var node := MeshInstance3D.new()
		node.name = pt[0]
		node.mesh = m
		node.material_override = wood
		node.transform = Transform3D(basis, mid + basis * (pt[1] as Vector3))
		seg.add_child(node)
	var wm := BoxMesh.new()
	wm.size = Vector3(W - 0.08, 0.01, L)
	var wn := MeshInstance3D.new()
	wn.name = "Water"
	wn.mesh = wm
	wn.material_override = fmat
	wn.transform = Transform3D(basis, mid + basis * Vector3(0, depth, 0))
	seg.add_child(wn)
	for k in floori(L / 1.6):
		var t := (k + 0.5) * 1.6 / L - 0.5
		_box(seg, "Tie_%d" % k, mid + basis * Vector3(0, wall - 0.02, t * L), Vector3(W + 0.05, 0.035, 0.045), wood, yaw)

## 石組みの桝：四周石塊＋水面（頂 top_y、水面 water_y）；open_k 各邊（0＝+x、2＝−x）改為低於水面的越流石＝進出水口
static func _stone_box(g: Node3D, c: Vector2, ground: float, top_y: float, water_y: float, stone: Material, fmat: Material, rng: RandomNumberGenerator, cover := false, open_k: Array = []) -> void:
	var h := top_y - ground + 0.08
	for k in 4:
		var a := k * PI * 0.5
		var hk := h
		if k in open_k:
			hk = maxf(0.04, water_y - 0.025 - (ground - 0.08))
		_box(g, "Stone_%d" % k, Vector3(c.x + cos(a) * 0.34, ground - 0.08 + hk * 0.5, c.y + sin(a) * 0.34), Vector3(0.18 if k % 2 == 0 else 0.86, hk, 0.86 if k % 2 == 0 else 0.18), stone, rng.randf_range(-0.05, 0.05))
	_box(g, "Water", Vector3(c.x, water_y, c.y), Vector3(0.5, 0.01, 0.5), fmat)
	if cover:
		_box(g, "CoverStone", Vector3(c.x + 0.12, top_y + 0.03, c.y - 0.05), Vector3(0.5, 0.06, 0.62), stone, rng.randf_range(-0.12, 0.12))

## 取水水路可見網格：竜骨車（R5b.1）、落とし桝、上段土渠、伏越し兩桝、地面木槽、跨渠板
static func _supply_art(g: Node3D, irr: Node3D, P: Dictionary, layout: Dictionary, wood: Material, stone: Material, rng: RandomNumberGenerator) -> void:
	var fmat := _flow_mat(0.8, Color(0.36, 0.36, 0.3), 0.7)
	# 1) R5b.1 竜骨車（水車 2 下流の東岸。r5 の高架落とし樋・接頭箱・受け樋枕木・支柱は撤去）
	_ryukotsu_art(_group(g, "Ryukotsu"), P, wood, fmat)
	# 2) 落とし桝（竜骨車の送り樋が落水 → 上段土渠）
	var y0 := TLib.farm_level(layout, FL.DROP_BOX)
	_stone_box(_group(g, "DropBox"), FL.DROP_BOX, y0, y0 + 0.24, y0 + FL.UPPER_LIFT + 0.01, stone, fmat, rng, false, [0])
	# 3) 上段土渠（兩唇為田埂管線的 LipSupA／LipSupB；此處只鋪渠底與水面）
	var up: PackedVector2Array = P["upper"]
	_ribbon(irr, "UpperBed", up, FL.UPPER_LIP + 0.05, func(p: Vector2, u: float) -> float: return TLib.farm_level(layout, p) + 0.012 + 0.006 * _n(p * 3.0 + Vector2(u, 0)), _ground_mat(), Color(0.1, 0.25, 1.0, 0.0), Vector2(1.0, 0.0), -1e9, 1e9)
	_ribbon(irr, "UpperWater", up, FL.UPPER_HALF, func(p: Vector2, u: float) -> float: return TLib.farm_level(layout, p) + FL.UPPER_LIFT, _flow_mat(0.9, Color(0.30, 0.29, 0.21), 0.55), Color(), Vector2(), -1e9, 1e9, true)
	# 4) 伏越し：入口桝（上段土渠末端）／出口桝（FarmPath_1 東側）；路面下暗渠不可見、地上無構件
	#    水理：路面 0.148 m < 出口水位 0.19 < 入口水位 0.27 → 路下管段必滿管、出口端上湧＝封閉壓力段（伏越し，非暗渠／涵洞）。
	#    兩桝是通到路下管底的豎井：水面用混濁深色，不透出 0.12 m 下的地表（否則讀成淺盆）。
	var deep := _flow_mat(0.6, Color(0.16, 0.16, 0.13), 0.12)
	for i in 2:
		var q: Vector2 = FL.SIPHON[i]
		var gy := 0.15    # 兩桝都在 0.20→0.00 階差坡上（實測地形 0.15–0.17）；桝底再埋 0.04
		_stone_box(_group(g, "SiphonBox_%d" % i), q, gy - 0.04, float(FL.SIPHON_WATER[i]) + 0.07, float(FL.SIPHON_WATER[i]), stone, deep, rng, i == 0, [2] if i == 0 else [0])
	# 5) 地面木槽：枕木上、頂 ≈ 0.24 m，沿 W1 南埂外側東流，樋口落進內渠南端
	var tl := FL._pa(FL.TROUGH)
	var L := FL._length(tl)
	var acc := 0.0
	var tg := _group(g, "GroundTrough")
	for i in tl.size() - 1:
		var p0 := tl[i]
		var p1 := tl[i + 1]
		var seg := p0.distance_to(p1)
		var ya := FL.trough_bottom(acc, L)
		var yb := FL.trough_bottom(acc + seg, L)
		_trough_seg(_group(tg, "Seg_%d" % i), Vector3(p0.x, ya, p0.y), Vector3(p1.x, yb, p1.y), FL.TROUGH_W, FL.TROUGH_WALL, FL.TROUGH_DEPTH, wood, fmat)
		# 枕木（每 ≈1.5 m）：地面 → 底板下
		var n := maxi(1, floori(seg / 1.5))
		for j in n:
			var t := (j + 0.5) / n
			var c := p0.lerp(p1, t)
			var d := (p1 - p0).normalized()
			var gy := TLib.farm_level(layout, c)
			var top := lerpf(ya, yb, t) - 0.04
			if top - gy < 0.03:
				continue    # 木槽半埋段不需枕木
			_box(tg, "Sleeper_%d_%d" % [i, j], Vector3(c.x, (gy - 0.03 + top) * 0.5, c.y), Vector3(FL.TROUGH_W + 0.22, top - gy + 0.03, 0.12), wood, atan2(d.x, d.y) + rng.randf_range(-0.06, 0.06))
		acc += seg
	# 6) 跨渠板（木槽上 2 處、上段土渠上 1 處）：與碰撞同源（lib.crossing）
	for cr_spec: Array in FL.CROSSINGS:
		var cr := FL.crossing(cr_spec, layout)
		var cg := _group(g, "Crossing_%s_%d" % [cr_spec[0], int(cr_spec[1])])
		var at: Vector2 = cr["at"]
		for j in 3:
			_box(cg, "Plank_%d" % j, Vector3(at.x + (j - 1) * 0.25 + rng.randf_range(-0.02, 0.02), float(cr["top"]) - 0.022, at.y), Vector3(0.23, 0.045, float(cr["span"]) + rng.randf_range(-0.08, 0.08)), wood, rng.randf_range(-0.05, 0.05))

## R5b.1 竜骨車（翻車、人力の踏み軸）：傾斜樋＋羽根板の鎖（樋内の汲み上げ側／上の戻り側）＋上下の車＋踏み軸と拐木＋門形架と手摺
##   ＋渠中の杭（下車）＋送り樋（落とし桝の上へ張り出し、落水）。寸法は lib 定数（碰撞と同源）。
##   描画数を抑えるため、向きの同じ部材は 1 網格にまとめる（Trough/Body・Drive・Feed/Body、水は Trough/Water・Feed/Water）。
##   柱（Post_*）・手摺・方杖は個別（FEEDER の柱碰撞・相機淨空の OBB を緊く保つ）。
static func _ryukotsu_art(r: Node3D, P: Dictionary, wood: Material, fmat: Material) -> void:
	var bs := FL.ryu_basis()
	var lo: Vector3 = FL.RYU_LOW
	var hi: Vector3 = FL.RYU_HIGH
	var L := (hi - lo).length()
	var mid := (lo + hi) * 0.5
	var W: float = FL.RYU_W
	var wall: float = FL.RYU_WALL
	var to_local := Transform3D(bs, mid).affine_inverse()
	var xrot := Basis(Vector3.BACK, PI * 0.5)       # 円柱の軸 y → 樋局部 x（＝世界 z 方向）
	# 傾斜樋（樋の局部座標）：底板・側板・貫＋羽根板の鎖（汲み上げ側 0.02–0.14／戻り側 0.27–0.39）＋下車＋下の軸＋杭の貫
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_into(st, Transform3D(Basis(), Vector3(0, -0.02, 0)), Vector3(W, 0.04, L + 0.04))
	_box_into(st, Transform3D(Basis(), Vector3(-W * 0.5 + 0.018, wall * 0.5 - 0.04, 0)), Vector3(0.036, wall + 0.04, L + 0.04))
	_box_into(st, Transform3D(Basis(), Vector3(W * 0.5 - 0.018, wall * 0.5 - 0.04, 0)), Vector3(0.036, wall + 0.04, L + 0.04))
	for k in floori(L / 1.6):
		var t := (k + 0.5) * 1.6 / L - 0.5
		_box_into(st, Transform3D(Basis(), Vector3(0, wall - 0.02, t * L)), Vector3(W + 0.05, 0.035, 0.045))
	var n := floori((L - 0.30) / 0.22)
	for i in n + 1:
		var z := -L * 0.5 + 0.15 + i * (L - 0.30) / n
		_box_into(st, Transform3D(Basis(), Vector3(0, 0.08, z)), Vector3(W - 0.09, 0.12, 0.022))
		_box_into(st, Transform3D(Basis(), Vector3(0, 0.33, z)), Vector3(W - 0.09, 0.12, 0.022))
	_box_into(st, Transform3D(Basis(), Vector3(0, 0.08, 0)), Vector3(0.04, 0.035, L - 0.2))
	_box_into(st, Transform3D(Basis(), Vector3(0, 0.33, 0)), Vector3(0.04, 0.035, L - 0.2))
	var lax_l := Vector3(0, FL.RYU_DRUM_UP, -L * 0.5)
	_cyl_into(st, Transform3D(xrot, lax_l), 0.13, W - 0.06)
	_cyl_into(st, Transform3D(xrot, lax_l), 0.04, 0.62)
	_box_into(st, Transform3D(bs.inverse(), to_local * Vector3(lo.x - 0.10, -1.30, lo.z)), Vector3(0.07, 0.07, 0.62))
	var tg := _group(r, "Trough")
	_mesh_node(tg, "Body", st, wood, Transform3D(bs, mid))
	var ws := SurfaceTool.new()
	ws.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_into(ws, Transform3D(Basis(), Vector3(0, 0.09, 0)), Vector3(W - 0.08, 0.01, L))
	_mesh_node(tg, "Water", ws, fmat, Transform3D(bs, mid))
	# 踏み軸（世界 z 方向）＋上車＋拐木（片側 2 輪 × 2 人、各輪 4 本、隣の輪は 45° ずらす）
	var ax := FL.ryu_axle()
	var z0: float = FL.RYU_FRAME_Z[0]
	var z1: float = FL.RYU_FRAME_Z[1]
	var zrot := Basis(Vector3.RIGHT, PI * 0.5)
	var ds := SurfaceTool.new()
	ds.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cyl_into(ds, Transform3D(zrot, Vector3(0, 0, (z0 + z1) * 0.5 - lo.z)), 0.055, z1 - z0 + 0.16)
	_cyl_into(ds, Transform3D(zrot, Vector3.ZERO), 0.15, W - 0.06)
	var ring := 0
	for sd in [-1.0, 1.0]:
		for dz: float in [0.42, 0.66]:
			for k in 4:
				var a := (ring * 0.25 + k * 0.5) * PI
				var rb := Basis(Vector3.BACK, a)
				_box_into(ds, Transform3D(rb, rb * Vector3(0.17, 0, 0) + Vector3(0, 0, sd * dz)), Vector3(0.30, 0.05, 0.05))
				_box_into(ds, Transform3D(rb, rb * Vector3(0.33, 0, 0) + Vector3(0, 0, sd * dz)), Vector3(0.05, 0.11, 0.15))
			ring += 1
	_mesh_node(r, "Drive", ds, wood, Transform3D(Basis(), Vector3(ax.x, ax.y, lo.z)))
	# 柱（門形架・杭・送り樋の脚）＋手摺＋方杖（岸坡は P7 の石積みなので中間架台は立てない：樋は下車の杭と門形架で両端支持）
	for po: Dictionary in P["supply_posts"]:
		var p: Vector2 = po["p"]
		var h: float = float(po["y_top"]) - float(po["y_bot"])
		var s: float = po["s"]
		_box(r, "Post_" + String(po["name"]), Vector3(p.x, float(po["y_bot"]) + h * 0.5, p.y), Vector3(s, h, s), wood, 0.0)
	_box(r, "Rail", Vector3(ax.x, ax.y + FL.RYU_RAIL_LIFT, (z0 + z1) * 0.5), Vector3(0.08, 0.08, z1 - z0 + 0.22), wood, 0.0)
	for i in 2:
		var zf: float = FL.RYU_FRAME_Z[i]
		var top := Vector3(ax.x, ax.y + 0.55, zf)
		var foot := Vector3(ax.x + 0.62, 0.05, zf)
		var dv := top - foot
		_box(r, "Brace_%d" % i, (top + foot) * 0.5, Vector3(0.07, dv.length(), 0.07), wood, 0.0)
		(r.get_node("Brace_%d" % i) as Node3D).basis = Basis(Vector3.BACK, atan2(-dv.x, dv.y))
	# 送り樋（送り樋の局部座標）：底板・側板・貫・西端の妻板・脚の貫／水面＋落水
	var fa: Vector3 = FL.FEED[0]
	var fb: Vector3 = FL.FEED[1]
	var fd := Vector2(fb.x - fa.x, fb.z - fa.z)
	var FL_ := fd.length()
	var fbs := Basis(Vector3.UP, atan2(fd.x, fd.y)) * Basis(Vector3.RIGHT, atan2(fa.y - fb.y, FL_))
	var fmid := (fa + fb) * 0.5
	var f_local := Transform3D(fbs, fmid).affine_inverse()
	var FW: float = FL.FEED_W
	var fwall: float = FL.FEED_WALL
	var fs := SurfaceTool.new()
	fs.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_into(fs, Transform3D(Basis(), Vector3(0, -0.02, 0)), Vector3(FW, 0.04, FL_ + 0.04))
	# P11 R2D-Fix：T0 分水口＝南側（局部 −x）側板を木槽の外法幅で実際に切り欠く（底板の高さまで、底板は残す）。
	#   局部 z は f_local で分水点から求める（送り樋は yaw／pitch 付き、世界の南＝局部 −x を前提にしない）。
	var tap_w: Vector2 = load(FL.ZONE_SCRIPT).BRANCHES["T0"]["tap"]
	var tap_z := (f_local * Vector3(tap_w.x, fa.y, tap_w.y)).z
	var tap_half := FL.TROUGH_W * 0.5
	var side_z0 := -FL_ * 0.5 - 0.02
	var side_z1 := FL_ * 0.5 + 0.02
	for seg: Vector2 in [Vector2(side_z0, tap_z - tap_half), Vector2(tap_z + tap_half, side_z1)]:
		_box_into(fs, Transform3D(Basis(), Vector3(-FW * 0.5 + 0.018, fwall * 0.5 - 0.04, (seg.x + seg.y) * 0.5)), Vector3(0.036, fwall + 0.04, seg.y - seg.x))
	_box_into(fs, Transform3D(Basis(), Vector3(-FW * 0.5 + 0.018, -0.03, tap_z)), Vector3(0.036, 0.06, FL.TROUGH_W))   # 切り欠きの下＝底板と同高の敷居
	_box_into(fs, Transform3D(Basis(), Vector3(FW * 0.5 - 0.018, fwall * 0.5 - 0.04, 0)), Vector3(0.036, fwall + 0.04, FL_ + 0.04))
	for k in floori(FL_ / 1.6):
		var t := (k + 0.5) * 1.6 / FL_ - 0.5
		_box_into(fs, Transform3D(Basis(), Vector3(0, fwall - 0.02, t * FL_)), Vector3(FW + 0.05, 0.035, 0.045))
	_box_into(fs, Transform3D(Basis(), Vector3(0, fwall * 0.5 - 0.05, -FL_ * 0.5 - 0.02)), Vector3(FW, fwall + 0.06, 0.035))
	for i in FL.FEED_LEG_X.size():
		var x: float = FL.FEED_LEG_X[i]
		var y := lerpf(fa.y, fb.y, (x - fa.x) / (fb.x - fa.x))
		_box_into(fs, Transform3D(fbs.inverse(), f_local * Vector3(x, y - 0.075, fa.z)), Vector3(0.07, 0.05, FW + 0.12))
	var fg := _group(r, "Feed")
	_mesh_node(fg, "Body", fs, wood, Transform3D(fbs, fmid))
	var y_box := FL.UPPER_LIFT + 0.21     # 落とし桝水面（0.20 階面＋上段水位＋0.01）
	var fws := SurfaceTool.new()
	fws.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_into(fws, Transform3D(Basis(), Vector3(0, 0.06, 0)), Vector3(FW - 0.08, 0.01, FL_))
	_box_into(fws, Transform3D(Basis(), Vector3(-FW * 0.5 + 0.01, 0.057, tap_z)), Vector3(0.1, 0.01, FL.TROUGH_W - 0.08))   # 開口を越えて木槽へ流れ出る水
	_box_into(fws, Transform3D(fbs.inverse(), f_local * Vector3(fb.x + 0.02, (fb.y + 0.05 + y_box) * 0.5, fb.z)), Vector3(0.02, fb.y + 0.05 - y_box, 0.22))
	_mesh_node(fg, "Water", fws, fmat, Transform3D(fbs, fmid))

static func _mesh_node(parent: Node3D, name: String, st: SurfaceTool, mat: Material, xf: Transform3D) -> void:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = st.commit()
	node.material_override = mat
	node.transform = xf
	parent.add_child(node)

static func _cyl_into(st: SurfaceTool, xf: Transform3D, r: float, h: float) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	st.append_from(m, 0, xf)

static func _cyl(parent: Node3D, name: String, at: Vector3, r: float, h: float, b: Basis, mat: Material) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = m
	node.material_override = mat
	node.transform = Transform3D(b, at)
	parent.add_child(node)

static func _box_into(st: SurfaceTool, xf: Transform3D, size: Vector3) -> void:
	var m := BoxMesh.new()
	m.size = size
	st.append_from(m, 0, xf)

static func _footprints(details: Node3D, P: Dictionary, layout: Dictionary) -> void:
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	# E4 植付前線：在泥中來回的腳印（水下可見）
	var e4: Dictionary = FIELD_STYLE["E4"]
	var fz: float = e4["front_z"]
	for k in 26:
		var x := 408.0 + k * 0.52
		var side := -1.0 if k % 2 == 0 else 1.0
		var p := Vector2(x + rng.randf_range(-0.05, 0.05), fz + 0.45 + side * 0.13 + 0.25 * sin(k * 0.4))
		_oval(t, Vector3(p.x, TLib.farm_level(layout, p) + 0.021, p.y), 0.13, 0.055, rng.randf_range(-0.2, 0.2), Color(0.12, 0.10, 0.07))
	# 常走的外埂頂：草鞋の踏み跡
	for bn: String in ["OuterW1", "OuterW3", "LipE"]:
		var d: Dictionary = P["bunds"][bn]
		var L: float = d["length"]
		var s := 3.0
		var k := 0
		while s < L - 3.0:
			var ev := FL.bund_eval(d, s)
			var at: Array = FL.at_s(d["pts"], s)
			var c: Vector2 = at[0]
			var tan: Vector2 = at[1]
			var nrm := Vector2(-tan.y, tan.x)
			var side := -1.0 if k % 2 == 0 else 1.0
			var p := c + nrm * (float(ev["off"]) + side * 0.07)
			if float(ev["notch"]) < 0.1 and _n(c * 0.2) > 0.1:
				_oval(t, Vector3(p.x, TLib.farm_level(layout, c) + float(ev["h"]) + 0.003, p.y), 0.12, 0.05, atan2(tan.x, tan.y), Color(0.24, 0.20, 0.15))
			s += 0.36 + rng.randf_range(-0.04, 0.04)
			k += 1
	_mesh(details, "Footprints", _finish(t), _clod_mat())

# ───────────────────────────── 網格工具 ─────────────────────────────

## 多邊形三角化：邊界每 step 取點＋內部錯列格點 → Delaunay → 留形心在內者
static func _tri_poly(poly: PackedVector2Array, step: float) -> Array:
	var pts := PackedVector2Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := maxi(1, ceili(a.distance_to(b) / step))
		for k in n:
			pts.append(a.lerp(b, float(k) / n))
	var bb := _bbox(poly)
	var row := 0
	var y := bb.position.y + step * 0.5
	while y < bb.end.y:
		var x := bb.position.x + step * (0.25 if row % 2 == 0 else 0.75)
		while x < bb.end.x:
			var p := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(p, poly) and _dist_poly(p, poly) > step * 0.45:
				pts.append(p)
			x += step
		y += step * 0.87
		row += 1
	var tri := Geometry2D.triangulate_delaunay(pts)
	var idx := PackedInt32Array()
	for i in range(0, tri.size(), 3):
		var c := (pts[tri[i]] + pts[tri[i + 1]] + pts[tri[i + 2]]) / 3.0
		if Geometry2D.is_point_in_polygon(c, poly):
			# 統一為 +y 朝上（XZ 平面上逆時針 → 從上看）
			var a := pts[tri[i]]
			var b := pts[tri[i + 1]]
			var d := pts[tri[i + 2]]
			if (b - a).cross(d - a) > 0.0:
				idx.append_array([tri[i], tri[i + 2], tri[i + 1]])
			else:
				idx.append_array([tri[i], tri[i + 1], tri[i + 2]])
	return [pts, idx]

static func _edge_dist(pts: PackedVector2Array, poly: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in pts:
		out.append(_dist_poly(p, poly))
	return out

static func _dist_poly(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, q.distance_to(p))
	return best

static func _build_mesh(pts: PackedVector2Array, idx: PackedInt32Array, ys: PackedFloat32Array, cols: PackedColorArray, uv: PackedVector2Array, uv2: PackedVector2Array, smooth: bool) -> ArrayMesh:
	var verts := PackedVector3Array()
	for i in pts.size():
		verts.append(Vector3(pts[i].x, ys[i], pts[i].y))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	if cols.size() > 0:
		arr[Mesh.ARRAY_COLOR] = cols
	if uv.size() > 0:
		arr[Mesh.ARRAY_TEX_UV] = uv
	if uv2.size() > 0:
		arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	return _commit_up(arr)

## SurfaceTool（無法線的石塊／泥塊）→ 索引化、算法線、確保朝外朝上
static func _finish(t: SurfaceTool) -> ArrayMesh:
	t.index()
	var arr := t.commit_to_arrays()
	arr[Mesh.ARRAY_NORMAL] = null
	return _commit_up(arr)

## 由陣列建網格並確保法線朝上（Godot 以順時針為正面；平均法線 y<0 就翻轉索引）
static func _commit_up(arr: Array) -> ArrayMesh:
	var t := SurfaceTool.new()
	t.create_from_arrays(arr)
	t.generate_normals()
	var m := t.commit()
	var ns: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var sy := 0.0
	for n in ns:
		sy += n.y
	if sy >= 0.0:
		return m
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var flipped := PackedInt32Array()
	for i in range(0, idx.size(), 3):
		flipped.append_array([idx[i], idx[i + 2], idx[i + 1]])
	arr[Mesh.ARRAY_INDEX] = flipped
	t = SurfaceTool.new()
	t.create_from_arrays(arr)
	t.generate_normals()
	return t.commit()

## 沿中心線的帶狀網格（渠底／渠水／排水）。z_from／z_to：只取中心線 z 在此區間的部分。
static func _ribbon(parent: Node3D, name: String, line: PackedVector2Array, half: float, yfn: Callable, mat: Material, col: Color, uv2v: Vector2, z_from: float, z_to: float, is_water := false) -> void:
	var L := 0.0
	for i in line.size() - 1:
		L += line[i].distance_to(line[i + 1])
	var steps := maxi(2, ceili(L / 0.3))
	var nu := 7
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var rows := 0
	for i in steps + 1:
		var s := L * float(i) / steps
		var at: Array = FL.at_s(line, s)
		var c: Vector2 = at[0]
		if c.y < z_from or c.y > z_to:
			continue
		var tan: Vector2 = at[1]
		var nrm := Vector2(-tan.y, tan.x)
		for k in nu:
			var u := lerpf(-1.0, 1.0, float(k) / (nu - 1))
			var p := c + nrm * u * half
			verts.append(Vector3(p.x, yfn.call(p, u), p.y))
			if is_water:
				uvs.append(Vector2((1.0 - absf(u)) * half, s))
			else:
				cols.append(col)
				uvs.append(Vector2(0.0, 0.0))
				uv2s.append(uv2v)
		rows += 1
	if rows < 2:
		return
	var idx := PackedInt32Array()
	for i in rows - 1:
		for k in nu - 1:
			var a := i * nu + k
			var b := a + nu
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	if cols.size() > 0:
		arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	if uv2s.size() > 0:
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	_mesh(parent, name, _commit_up(arr), mat)

static func _rock(t: SurfaceTool, at: Vector3, r: float, rng: RandomNumberGenerator, squash := 0.6, col := Color(0.62, 0.60, 0.55)) -> void:
	var ring := 6
	var top := at + Vector3(0, r * squash, 0)
	var ps: Array = []
	var yaw := rng.randf() * TAU
	for k in ring:
		var a := yaw + TAU * k / ring
		var rr := r * rng.randf_range(0.75, 1.15)
		ps.append(at + Vector3(cos(a) * rr, r * squash * rng.randf_range(0.2, 0.45), sin(a) * rr))
	var c := col * rng.randf_range(0.8, 1.1)
	for k in ring:
		var a: Vector3 = ps[k]
		var b: Vector3 = ps[(k + 1) % ring]
		var low_a := Vector3(a.x, at.y - r * 0.2, a.z)
		var low_b := Vector3(b.x, at.y - r * 0.2, b.z)
		for v in [top, b, a, a, b, low_b, a, low_b, low_a]:
			t.set_color(c)
			t.add_vertex(v)

static func _oval(t: SurfaceTool, at: Vector3, len: float, wid: float, yaw: float, col: Color) -> void:
	var seg := 8
	var f := Vector3(sin(yaw), 0, cos(yaw))
	var s := Vector3(-f.z, 0, f.x)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0 := at + f * cos(a0) * len * 0.5 + s * sin(a0) * wid * 0.5
		var p1 := at + f * cos(a1) * len * 0.5 + s * sin(a1) * wid * 0.5
		for v in [at - Vector3(0, 0.004, 0), p1, p0]:
			t.set_color(col)
			t.set_normal(Vector3.UP)
			t.add_vertex(v)

static func _box(parent: Node3D, name: String, at: Vector3, size: Vector3, mat: Material, yaw := 0.0, pitch := 0.0) -> void:
	var m := BoxMesh.new()
	m.size = size
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = m
	node.material_override = mat
	node.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), at)
	parent.add_child(node)

static func _rock_node(parent: Node3D, name: String, at: Vector3, r: float, rng: RandomNumberGenerator, mat: Material) -> void:
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	_rock(t, Vector3.ZERO, r, rng)
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = _finish(t)
	node.material_override = mat
	node.position = at
	parent.add_child(node)

# ───────────────────────────── 材質 ─────────────────────────────

static func _load_materials() -> void:
	if _ground_sh != null:
		return
	var ML := {}
	for a: Dictionary in HLib.registry().get("v2_assets", []):
		if String(a.get("kind", "")) == "material_library":
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(a["entry"])))
			if parsed is Dictionary:
				ML = parsed
	assert(ML.has("ground"), "P8 pilot 需要 P7 _matlib ground（registry material_library）")
	var G: Dictionary = ML["ground"]
	_ground_sh = load(String(G["shader"]))
	_ground_tex = {"albedo": load(String(G["arrays"]["albedo"])), "nrh": load(String(G["arrays"]["nrh"])), "noise": load(String(G["noise"]["path"]))}
	_mats["wood_src"] = load(String(ML["materials"]["V2_Wood"]["tres"]))
	_mats["stone_src"] = load(String(ML["materials"]["V2_Stone"]["tres"]))
	_mats["ground_k"] = float(G["albedo_k"])

static func _ground_mat() -> ShaderMaterial:
	if _mats.has("ground"):
		return _mats["ground"]
	var m := ShaderMaterial.new()
	m.shader = _ground_sh
	m.set_shader_parameter("albedo_arr", _ground_tex["albedo"])
	m.set_shader_parameter("nrh_arr", _ground_tex["nrh"])
	m.set_shader_parameter("noise_tex", _ground_tex["noise"])
	m.set_shader_parameter("ground_k", _mats["ground_k"])
	m.set_shader_parameter("mode", 0)
	m.set_shader_parameter("use_vertex_weights", true)
	_mats["ground"] = m
	return m

## 田埂土：同一 P7 ground shader，只把本材質的 ground_k 提高約 30%——埂坡多在背光側，
## 以地形係數會近乎全黑（實測 RGB≈5,11,13；同網格換灰材質則 33,52,100）；乾的踏み固め埂土本來就比田土亮。
static func _bank_mat() -> ShaderMaterial:
	if _mats.has("bank"):
		return _mats["bank"]
	var m: ShaderMaterial = _ground_mat().duplicate()
	m.set_shader_parameter("ground_k", float(_mats["ground_k"]) * 1.6)
	_mats["bank"] = m
	return m

## 田底泥：水下泥底只受天空環境光＋少量直射，以地形係數實測近黑（RGB≈10,15,30，藏掉水面時）；
## 提高 ground_k 讓淺水下的泥色、泥斑讀得出來（水面仍負責反射與混濁）。
static func _mud_mat() -> ShaderMaterial:
	if _mats.has("mud"):
		return _mats["mud"]
	var m: ShaderMaterial = _ground_mat().duplicate()
	m.set_shader_parameter("ground_k", float(_mats["ground_k"]) * 1.9)
	_mats["mud"] = m
	return m

static func _tri_mat(key: String, src_key: String, tile: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D = (_mats[src_key] as StandardMaterial3D).duplicate()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	m.vertex_color_use_as_albedo = true
	_mats[key] = m
	return m

static func _wood_mat() -> StandardMaterial3D:
	return _tri_mat("wood", "wood_src", 1.2)

static func _stone_mat() -> StandardMaterial3D:
	return _tri_mat("stone", "stone_src", 0.8)

static func _clod_mat() -> StandardMaterial3D:
	if _mats.has("clod"):
		return _mats["clod"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.55
	_mats["clod"] = m
	return m

static func _plant_mat() -> ShaderMaterial:
	if _mats.has("plant"):
		return _mats["plant"]
	var m := ShaderMaterial.new()
	m.shader = PLANT_SH
	_mats["plant"] = m
	return m

static func _flow_mat(flow: float, tint: Color, clarity: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SH
	m.set_shader_parameter("flow", flow)
	m.set_shader_parameter("water_tint", tint)
	m.set_shader_parameter("clarity", clarity)
	m.set_shader_parameter("rough_base", 0.2)
	m.set_shader_parameter("ripple", 1.0)
	m.set_shader_parameter("rice_cov", 0.0)
	m.set_shader_parameter("scum_color", tint * 0.85)
	return m

# ───────────────────────────── 小工具 ─────────────────────────────

static func _n(p: Vector2) -> float:
	return _noise.get_noise_2d(p.x * 10.0, p.y * 10.0) * 0.5 + 0.5

static func _bbox(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r

## 全區田埂的小石／泥塊：只在近景可見（1.7 m 視角 45 m 外讀不到）、不投影
static func _detail_range(n: Node, d: Dictionary) -> void:
	if not d.has("chunk"):
		return
	var g := n as GeometryInstance3D
	g.visibility_range_end = 45.0
	g.visibility_range_end_margin = 5.0
	g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _mesh(parent: Node3D, name: String, mesh: Mesh, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)

static func _group(parent: Node3D, name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	parent.add_child(node)
	return node
