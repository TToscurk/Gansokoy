extends RefCounted
## 獸道 地形／水面網格建造（V0.1 白模，T05–T08/T10 的 V0.1 版）。
##
## 四個場景各一塊 tile（寬 220 m，z 方向互相共用邊界列），頂點一律取自 bp_lib 的 1 m 烘焙晶格；
## 法線也用晶格中心差分（含 2 格外圈）。所以相鄰 tile 在接縫列的位置、法線、顏色完全相同 → 無裂縫。
## 三角剖分固定為對角線 b–c，與 bp_lib.h_at() 的內插一致（樹、道具、驗證器取到的高度＝網格表面）。

const BPLib := preload("res://tools/beast_path/bp_lib.gd")


static func tile_rect(sc: Dictionary) -> Rect2:
	var t: Array = sc["tile"]
	return Rect2(float(t[0]), float(t[1]), float(t[2]) - float(t[0]), float(t[3]) - float(t[1]))


static func terrain_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "BP_TerrainWhitebox"
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.metallic = 0.0
	m.metallic_specular = 0.15
	return m


static func water_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "BP_WaterWhitebox"
	m.albedo_color = Color(0.17, 0.36, 0.44, 0.7)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.0
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func fall_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "BP_FallWhitebox"
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, 1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = Color(0.42, 0.56, 0.64)
	m.emission_energy_multiplier = 0.22
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func foam_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "BP_FoamWhitebox"
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, 1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


const GROUND_SHADER := "res://assets/beast_path/materials/bp_ground.gdshader"
const GROUND_MAT_PATH := "res://assets/beast_path/materials/bp_ground.tres"
const GROUND_S01_SHADER := "res://assets/beast_path/materials/bp_ground_s01.gdshader"      # S01 R1：獨立的材質入口（不碰 bp_ground.*）
const GROUND_S01_MAT_PATH := "res://assets/beast_path/materials/bp_ground_s01.tres"
const R3_TEX := "res://assets/textures/"          # S01 R3：林床落葉／苔地貼圖（Poly Haven CC0，專案既有，唯讀引用）
const P7_GROUND := "res://assets/village_v2/_matlib/ground/"
const ROCK_SHADER := "res://assets/beast_path/materials/bp_rock.gdshader"
const WATER_SHADER := "res://assets/beast_path/materials/bp_water.gdshader"
const FALL_SHADER := "res://assets/beast_path/materials/bp_waterfall.gdshader"
const POOL_MAT_PATH := "res://assets/beast_path/materials/bp_water_pool.tres"
const STREAM_MAT_PATH := "res://assets/beast_path/materials/bp_water_stream.tres"
const FALL_MAT_PATH := "res://assets/beast_path/materials/bp_waterfall.tres"
const FALL_MAT_B_PATH := "res://assets/beast_path/materials/bp_waterfall_b.tres"
const ROCK_MAT_PATH := "res://assets/beast_path/materials/bp_rock.tres"
## 地表與岩共用的線性亮度係數：崖面地形（ground shader 的岩層）和岩片（rock shader）才是同一種石頭、同一個亮度
const GROUND_K := 0.26


## S04 天然地表材質：bp_ground.gdshader + 人間之里 P7 的 7 層 CC0 貼圖陣列（唯讀引用，不複製、不改 _matlib）。
## 寫成 .tres 讓網格只引用檔案——之後調 uniform 不必重生地形。
static func ground_material(lib: BPLib) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = "BP_Ground_S04"
	m.shader = load(GROUND_SHADER) as Shader
	m.set_shader_parameter("albedo_arr", load(P7_GROUND + "V2G_albedo.jpg"))
	m.set_shader_parameter("nrh_arr", load(P7_GROUND + "V2G_nrh.jpg"))
	m.set_shader_parameter("noise_tex", load(P7_GROUND + "V2G_noise.png"))
	m.set_shader_parameter("ground_k", GROUND_K)
	var lm: Dictionary = lib.L["boss_arena"]["landmark"]
	var mp := lib.arena_pos(float(lm["deg"]), float(lm["r"]))
	m.set_shader_parameter("autumn", Vector4(mp.x, mp.y, 18.0, 1.0))
	for sc: Dictionary in lib.L["scenes"]:
		if String(sc["id"]) == "S04":
			var z_top := float((sc["tile"] as Array)[3])
			m.set_shader_parameter("seam_z0", z_top)
			m.set_shader_parameter("seam_z1", z_top - 26.0)
	return m


## S04 岩材質（岩片／巨石／碎石共用）：bp_rock.gdshader + 同一組 P7 貼圖陣列；瀑布位置給濕潤帶用。
static func write_rock_material(lib: BPLib) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = "BP_Rock_S04"
	m.shader = load(ROCK_SHADER) as Shader
	m.set_shader_parameter("albedo_arr", load(P7_GROUND + "V2G_albedo.jpg"))
	m.set_shader_parameter("nrh_arr", load(P7_GROUND + "V2G_nrh.jpg"))
	m.set_shader_parameter("noise_tex", load(P7_GROUND + "V2G_noise.png"))
	m.set_shader_parameter("ground_k", GROUND_K)
	var wf: Dictionary = lib.L["boss_arena"]["waterfall"]
	m.set_shader_parameter("wet_src", Vector4(float(wf["x"]), float(wf["z"]), 10.0, 1.0))
	var e := ResourceSaver.save(m, ROCK_MAT_PATH)
	if e != OK:
		push_error("存 %s 失敗：%s" % [ROCK_MAT_PATH, error_string(e)])
	return ResourceLoader.load(ROCK_MAT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial


## S01 R1 地表材質：bp_ground_s01.gdshader + 同一組 P7 貼圖陣列（唯讀引用）。接縫在北端（和仍是白模的 S02 共用 z＝tile 北緣）。
static func ground_material_s01(lib: BPLib) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = "BP_Ground_S01"
	m.shader = load(GROUND_S01_SHADER) as Shader
	m.set_shader_parameter("albedo_arr", load(P7_GROUND + "V2G_albedo.jpg"))
	m.set_shader_parameter("nrh_arr", load(P7_GROUND + "V2G_nrh.jpg"))
	m.set_shader_parameter("noise_tex", load(P7_GROUND + "V2G_noise.png"))
	var g: Dictionary = lib.L.get("s01_ground", {})
	m.set_shader_parameter("ground_k", float(g.get("ground_k", GROUND_K)))
	for sc: Dictionary in lib.L["scenes"]:
		if String(sc["id"]) == "S01":
			var z_n := float((sc["tile"] as Array)[1])
			m.set_shader_parameter("seam_z0", z_n)
			m.set_shader_parameter("seam_z1", z_n + float(g.get("seam_fade_m", 26.0)))
	if bool(g.get("seam_off", false)):
		# 全區美術完成：S02／S03 也用同一套地表（zone_ground.gd），北端不再淡出成白模色
		m.set_shader_parameter("seam_z0", -2000.0)
		m.set_shader_parameter("seam_z1", -1999.0)
	var gn: Dictionary = g.get("gains", {})
	m.set_shader_parameter("gain_a", Vector4(float(gn.get("grass", 1.0)), float(gn.get("trodden", 1.0)), float(gn.get("gravel", 1.0)), float(gn.get("mud", 1.0))))
	m.set_shader_parameter("gain_b", Vector2(float(gn.get("rock", 1.0)), float(gn.get("forest", 1.0))))
	if String(((lib.L.get("forest", {}) as Dictionary).get("s01_candidate", {}) as Dictionary).get("mode", "")) == "r2":
		m.set_shader_parameter("far_steep_fix", 1.0)                # R2 才開（R1／replay 不設，畫面與 R1 相同）
	for k: String in (g.get("shader", {}) as Dictionary):
		var val: Variant = g["shader"][k]
		m.set_shader_parameter(k, Vector2(float(val[0]), float(val[1])) if val is Array else float(val))
	# S01 R3 地表自然化：兩層 S01 專用貼圖（專案既有、CC0；唯讀引用，不改匯入設定）＋ r3 參數。r3 未啟用＝不設（R2 畫面不變）
	var r3c: Dictionary = g.get("r3", {})
	if bool(r3c.get("enabled", false)):
		m.set_shader_parameter("r3_on", 1.0)
		m.set_shader_parameter("litter_alb", load(R3_TEX + "terrain_forest_diff.jpg"))
		m.set_shader_parameter("litter_nrm", load(R3_TEX + "terrain_forest_nor_gl.jpg"))
		m.set_shader_parameter("mossg_alb", load(R3_TEX + "terrain_grass_diff.jpg"))
		m.set_shader_parameter("mossg_nrm", load(R3_TEX + "terrain_grass_nor_gl.jpg"))
		for k3: String in (r3c.get("shader", {}) as Dictionary):
			var v3: Variant = r3c["shader"][k3]
			if v3 is Array and (v3 as Array).size() == 3:
				m.set_shader_parameter(k3, Vector3(float(v3[0]), float(v3[1]), float(v3[2])))
			elif v3 is Array:
				m.set_shader_parameter(k3, Vector2(float(v3[0]), float(v3[1])))
			else:
				m.set_shader_parameter(k3, float(v3))
	return m


## S02／S03 森林地表材質：同一個 S01 shader 與參數（林床語言一致），不淡出；layout.zone_ground.shader 可再覆寫。
static func write_ground_material_zone(lib: BPLib, path: String) -> ShaderMaterial:
	var m := ground_material_s01(lib)
	m.resource_name = "BP_Ground_Zone"
	m.set_shader_parameter("seam_z0", -2000.0)
	m.set_shader_parameter("seam_z1", -1999.0)
	m.set_shader_parameter("rut_amp", 0.0)
	var zg: Dictionary = lib.L.get("zone_ground", {})
	for k: String in (zg.get("shader", {}) as Dictionary):
		var v: Variant = zg["shader"][k]
		if v is Array and (v as Array).size() == 3:
			m.set_shader_parameter(k, Vector3(float(v[0]), float(v[1]), float(v[2])))
		elif v is Array:
			m.set_shader_parameter(k, Vector2(float(v[0]), float(v[1])))
		else:
			m.set_shader_parameter(k, float(v))
	var e := ResourceSaver.save(m, path)
	if e != OK:
		push_error("存 %s 失敗：%s" % [path, error_string(e)])
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial


static func write_ground_material_s01(lib: BPLib) -> ShaderMaterial:
	var m := ground_material_s01(lib)
	var e := ResourceSaver.save(m, GROUND_S01_MAT_PATH)
	if e != OK:
		push_error("存 %s 失敗：%s" % [GROUND_S01_MAT_PATH, error_string(e)])
	return ResourceLoader.load(GROUND_S01_MAT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial


## 寫出（或更新）材質檔，回傳磁碟上的那份（網格引用它）。
static func write_ground_material(lib: BPLib) -> ShaderMaterial:
	var m := ground_material(lib)
	var e := ResourceSaver.save(m, GROUND_MAT_PATH)
	if e != OK:
		push_error("存 %s 失敗：%s" % [GROUND_MAT_PATH, error_string(e)])
	return ResourceLoader.load(GROUND_MAT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial


## 一個場景 tile 的地形網格。回傳 {mesh, nv, ntri, x0, z0, nxv, nzv}
## ctx 為空＝白模頂點色（S01–S03）；ctx 有 "canopy"／"rock_d"＝S04 天然地表模式：
##   COLOR＝(trodden, gravel, mud, rock)、UV＝(forest, wet)、UV2＝(moss, 0)、CUSTOM0.rgb＝白模頂點色（接縫淡出用）。
static func build_tile(lib: BPLib, sc: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var g01 := ctx.has("s01")                      # S01 R1：S01 的地表情境（通道由 s01_ground.gd 算）；沒有它就維持原本的行為
	var ground := ctx.has("canopy") or g01
	var tr := tile_rect(sc)
	var cell := lib.cell
	var nxv := int(round(tr.size.x / cell)) + 1
	var nzv := int(round(tr.size.y / cell)) + 1
	var ix0 := int(round((tr.position.x - lib.lx0) / cell))
	var iz0 := int(round((tr.position.y - lib.lz0) / cell))
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var UV := PackedVector2Array()
	var UV2 := PackedVector2Array()
	var CU := PackedByteArray()
	var CU1 := PackedByteArray()                    # S01 R3：(林床落葉, 苔地, 乾, 潤)；只有 R3 的通道（13 個值）才有，R1／R2／S04 不建
	var has_c1 := false
	V.resize(nxv * nzv)
	N.resize(nxv * nzv)
	C.resize(nxv * nzv)
	UV.resize(nxv * nzv)
	if ground:
		UV2.resize(nxv * nzv)
		CU.resize(nxv * nzv * 4)
	for j in nzv:
		for i in nxv:
			var ixl := ix0 + i
			var izl := iz0 + j
			var x := lx0_of(lib, ixl)
			var z := lz0_of(lib, izl)
			var k := j * nxv + i
			V[k] = Vector3(x, lib.hl(ixl, izl), z)
			var gx := lib.hl(ixl + 1, izl) - lib.hl(ixl - 1, izl)
			var gz := lib.hl(ixl, izl + 1) - lib.hl(ixl, izl - 1)
			N[k] = Vector3(-gx, 2.0 * cell, -gz).normalized()
			if ground:
				var gw: PackedFloat32Array = (ctx["s01"].channels(ixl, izl, ctx)) if g01 else lib.ground_channels(ixl, izl, ctx)
				C[k] = Color(gw[0], gw[1], gw[2], gw[3])
				UV[k] = Vector2(gw[4], gw[5])
				UV2[k] = Vector2(gw[6], gw[7])
				var fc := lib.vertex_color(ixl, izl)
				# 與 ArrayMesh 存 COLOR 時的 8 位元量化一致（截斷），接縫比對才會是 0 差
				CU[k * 4] = clampi(int(fc.r * 255.0), 0, 255)
				CU[k * 4 + 1] = clampi(int(fc.g * 255.0), 0, 255)
				CU[k * 4 + 2] = clampi(int(fc.b * 255.0), 0, 255)
				CU[k * 4 + 3] = 255 if gw.size() < 9 else clampi(int((1.0 - gw[8]) * 255.0), 0, 255)      # S01 R2：a＝1−土袋（R1／S04 為 255＝沒有土袋）
				if gw.size() >= 13:
					if not has_c1:
						has_c1 = true
						CU1.resize(nxv * nzv * 4)
					for c4 in 4:
						CU1[k * 4 + c4] = clampi(int(roundf(clampf(gw[9 + c4], 0.0, 1.0) * 255.0)), 0, 255)
			else:
				C[k] = lib.vertex_color(ixl, izl)
				UV[k] = Vector2(x, z) * 0.25
	var I := PackedInt32Array()
	I.resize((nxv - 1) * (nzv - 1) * 6)
	var w := 0
	for j in nzv - 1:
		for i in nxv - 1:
			var a := j * nxv + i
			var b := a + 1
			var c := a + nxv
			var d := c + 1
			I[w] = a
			I[w + 1] = b
			I[w + 2] = c
			I[w + 3] = b
			I[w + 4] = d
			I[w + 5] = c
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = V
	arrays[Mesh.ARRAY_NORMAL] = N
	arrays[Mesh.ARRAY_COLOR] = C
	arrays[Mesh.ARRAY_TEX_UV] = UV
	arrays[Mesh.ARRAY_INDEX] = I
	var mesh := ArrayMesh.new()
	if ground:
		arrays[Mesh.ARRAY_TEX_UV2] = UV2
		arrays[Mesh.ARRAY_CUSTOM0] = CU
		var fmt: int = Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		if has_c1:
			arrays[Mesh.ARRAY_CUSTOM1] = CU1
			fmt |= Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
		mesh.surface_set_material(0, ResourceLoader.load(String(ctx.get("mat_path", GROUND_S01_MAT_PATH)) if g01 else GROUND_MAT_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as Material)
	else:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, terrain_material())
	mesh.resource_name = "%s_terrain" % String(sc["id"])
	return {"mesh": mesh, "nv": V.size(), "ntri": I.size() / 3, "x0": tr.position.x, "z0": tr.position.y, "nxv": nxv, "nzv": nzv}


static func lx0_of(lib: BPLib, ixl: int) -> float:
	return lib.lx0 + float(ixl) * lib.cell


static func lz0_of(lib: BPLib, izl: int) -> float:
	return lib.lz0 + float(izl) * lib.cell


## 溪流水面帶（每格 1 m 一段；段中點 z 落在此 tile 才算此 tile 的）
static func build_water(lib: BPLib, sc: Dictionary, mat: Material = null) -> ArrayMesh:
	var tr := tile_rect(sc)
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var UV := PackedVector2Array()
	var I := PackedInt32Array()
	for id: String in lib.streams:
		var st: BPLib.Poly = lib.streams[id]
		var wd := float(lib._stream_def(id)["water_depth"])
		# V1.3：崖頂上游的最後一點＝水幕頂列（寬 waterfall.w）。河道帶在這點收到同寬，否則帶的兩角（比水幕各寬 0.3 m）露在崖口外成一個方角
		var w_lip := -1.0
		if id == "stream_head":
			w_lip = float(lib.L["boss_arena"]["waterfall"]["w"])
		for i in st.pts.size() - 1:
			var mid := (st.pts[i] + st.pts[i + 1]) * 0.5
			if mid.y < tr.position.y or mid.y >= tr.end.y:
				continue
			var base := V.size()
			for k in 2:
				var idx := i + k
				var p := st.pts[idx]
				var t := st.tan_at(st.s[idx])
				var r := BPLib.right_of(t)
				var hw := st.w[idx] * 0.5 + 0.12
				if w_lip > 0.0:
					hw = lerpf(hw, w_lip * 0.5, smoothstep(st.length - 1.5, st.length, st.s[idx]))
				var y := st.bed[idx] + wd
				V.append(Vector3(p.x - r.x * hw, y, p.y - r.y * hw))
				V.append(Vector3(p.x + r.x * hw, y, p.y + r.y * hw))
				N.append(Vector3.UP)
				N.append(Vector3.UP)
				UV.append(Vector2(0.0, st.s[idx] * 0.25))
				UV.append(Vector2(1.0, st.s[idx] * 0.25))
			# 頂點序：0=l_i 1=r_i 2=l_i+1 3=r_i+1；(l_i, l_i+1, r_i) 與 (r_i, l_i+1, r_i+1) 皆為朝上的正面
			I.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	if V.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = V
	arrays[Mesh.ARRAY_NORMAL] = N
	arrays[Mesh.ARRAY_TEX_UV] = UV
	arrays[Mesh.ARRAY_INDEX] = I
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat if mat != null else water_material())
	mesh.resource_name = "%s_water" % String(sc["id"])
	return mesh


## 崖面位置不假設單調：對每個高度 y 取「由南往北第一次地形高 ≥ y」的 z。
## 崖面有雜訊起伏（岩質粗糙度 ±1.9 m），貼著地形逐列取高會讓水片穿進岩壁、再從縫裡露出來。
static func _face_z(lib: BPLib, x: float, y: float, z_from: float, z_to: float) -> float:
	var z := z_from
	while z >= z_to:
		if lib.h_at(x, z) >= y:
			return z
		z -= 0.1
	return z_to


static func _grid_idx(I: PackedInt32Array, base: int, rows: int, cols: int) -> void:
	for r in rows:
		for c in cols - 1:
			var a := base + r * cols + c
			var b := a + 1
			var cc := a + cols
			var d := cc + 1
			I.append_array(PackedInt32Array([a, cc, b, b, cc, d]))


## 瀑布幾何（水幕、潭水材質、粒子共用同一份）：崖頂 y_top／z_top、潭水面 pw、落水點 fz。
static func waterfall_geom(lib: BPLib) -> Dictionary:
	var wf: Dictionary = lib.L["boss_arena"]["waterfall"]
	var pool: Dictionary = lib.L["boss_arena"]["pool"]
	var cx := float(wf["x"])
	var w_top := float(wf["w"])
	var w_base := float(wf.get("w_base", w_top * 1.2))
	var pw := lib.water_y_at_stream("stream_trib", 0.0)
	var z_s := float(pool["z"]) - float(pool["r"]) + 0.5            # 潭北緣
	# 崖頂：先看到陡坡（≥ 60°），再連續 6 格（1.5 m）緩下來（< 38°）
	var seen := false
	var calm := 0
	var z_top := z_s - 14.0
	var z := z_s
	while z > z_s - 40.0:
		var sl := rad_to_deg(atan(absf(lib.h_at(cx, z - 0.5) - lib.h_at(cx, z + 0.5))))
		if sl >= 60.0:
			seen = true
			calm = 0
		elif seen:
			if sl < 38.0:
				calm += 1
				if calm >= 6:
					z_top = z + 1.5
					break
			else:
				calm = 0
		z -= 0.25
	var y_top := lib.h_at(cx, z_top)
	var fz := _face_z(lib, cx, pw + 0.1, z_s + 2.0, z_s - 45.0) + 1.1
	# V1.2 D：崖頂有上游河道（stream_head）→ 水幕頂端接在河道末端的水面上（比崖口地形高一個水深），水從河道漫過崖口變成水幕
	var y_wtop := y_top
	if lib.streams.has("stream_head"):
		y_wtop = lib.water_y_at_stream("stream_head", (lib.streams["stream_head"] as BPLib.Poly).length)
	return {"cx": cx, "w_top": w_top, "w_base": w_base, "pw": pw, "z_s": z_s, "z_top": z_top, "y_top": y_top, "y_wtop": y_wtop, "fz": fz}


## 全區美術完成：S02／S03 的溪水（原本是白模 StandardMaterial：藍色半透明、粗糙度 0.08 → 像一片藍板）。
## 改用與 S04 同一個水 shader（bp_water.gdshader，唯讀引用、不改）＋自己的材質檔（新檔；S04 的 bp_water_stream.tres 不動）。
const ZONE_WATER_PATH := "res://assets/beast_path/materials/bp_water_stream_zone.tres"


static func write_water_zone() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = "BP_Water_StreamZone"
	m.shader = load(WATER_SHADER) as Shader
	m.set_shader_parameter("noise_tex", load(P7_GROUND + "V2G_noise.png"))
	m.set_shader_parameter("uv_flow", 0.42)
	m.set_shader_parameter("ripple", 0.045)
	m.set_shader_parameter("fall", Vector4(0.0, 0.0, 1.0, 0.0))
	m.set_shader_parameter("lip", Vector4(0.0, 0.0, 0.0, 0.0))
	ResourceSaver.save(m, ZONE_WATER_PATH)
	return load(ZONE_WATER_PATH) as ShaderMaterial


## 水材質（潭／支流／瀑布幕）：bp_water.gdshader、bp_waterfall.gdshader + P7 的噪聲貼圖（CC0 程序噪聲，唯讀引用）。
static func write_water_materials(lib: BPLib) -> void:
	var g := waterfall_geom(lib)
	var noise := load(P7_GROUND + "V2G_noise.png")
	var pool := ShaderMaterial.new()
	pool.resource_name = "BP_Water_Pool"
	pool.shader = load(WATER_SHADER) as Shader
	pool.set_shader_parameter("noise_tex", noise)
	pool.set_shader_parameter("fall", Vector4(float(g["cx"]), float(g["fz"]), 2.9, 0.85))
	ResourceSaver.save(pool, POOL_MAT_PATH)
	var stream := ShaderMaterial.new()
	stream.resource_name = "BP_Water_Stream"
	stream.shader = load(WATER_SHADER) as Shader
	stream.set_shader_parameter("noise_tex", noise)
	stream.set_shader_parameter("uv_flow", 0.35)
	stream.set_shader_parameter("fall", Vector4(0.0, 0.0, 1.0, 0.0))
	stream.set_shader_parameter("ripple", 0.035)
	if lib.streams.has("stream_head"):
		# 崖頂上游溪的終點＝崖口；水快到這裡時碎成白水，和水幕頂端接起來（其餘溪段離這裡很遠，shader 內以位置限制，不受影響）
		var hs: BPLib.Poly = lib.streams["stream_head"]
		var le: Vector2 = hs.pts[hs.pts.size() - 1]
		stream.set_shader_parameter("lip", Vector4(le.x, le.y, 4.0, 0.75))
	ResourceSaver.save(stream, STREAM_MAT_PATH)
	var fall := ShaderMaterial.new()
	fall.resource_name = "BP_Waterfall"
	fall.shader = load(FALL_SHADER) as Shader
	fall.set_shader_parameter("noise_tex", noise)
	fall.set_shader_parameter("height_m", float(g["y_wtop"]) - float(g["pw"]))
	if lib.streams.has("stream_head"):
		# V1.3：水幕頂列接在河道末端水面上 → 頂端不再淡出 0.7 m、頂端邊緣收得窄一點（可見寬＝崖口河寬）
		fall.set_shader_parameter("top_fade", 0.006)
		fall.set_shader_parameter("edge_top", 0.12)
	ResourceSaver.save(fall, FALL_MAT_PATH)
	# 第二層水幕（V1.2 D）：同一支 shader，股左右鏡像、相位錯開、略快、較淡
	var fall_b := ShaderMaterial.new()
	fall_b.resource_name = "BP_Waterfall_B"
	fall_b.shader = load(FALL_SHADER) as Shader
	fall_b.set_shader_parameter("noise_tex", noise)
	fall_b.set_shader_parameter("height_m", float(g["y_wtop"]) - float(g["pw"]))
	fall_b.set_shader_parameter("mirror", 1.0)
	fall_b.set_shader_parameter("y_shift", 7.3)
	fall_b.set_shader_parameter("speed", 1.17)
	fall_b.set_shader_parameter("alpha_k", 0.62)
	if lib.streams.has("stream_head"):
		fall_b.set_shader_parameter("top_fade", 0.006)
		fall_b.set_shader_parameter("edge_top", 0.12)
	ResourceSaver.save(fall_b, FALL_MAT_B_PATH)


static func _mat(path: String) -> Material:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Material


## V1.3 崖口過渡：水幕最上面 BRINK_H m 從河道末端翻過崖口（拋物線），崖口水平流速 V_LIP m/s
const BRINK_H := 1.6
const V_LIP := 1.25


## 瀑布（V1.1）：surface 0＝沿崖面「立起來」的水幕（離崖面 0.3 m，13 欄、UV 給 bp_waterfall.gdshader）；
## V1.2：崖頂上游改由 stream_head（泉眼 → 蜿蜒河道 → 崖口）經 build_water 生成；surface 1＝第二層水幕（外推 0.34 m、鏡像錯相）；落水泡沫在潭面 shader 裡畫。
static func build_waterfall(lib: BPLib) -> ArrayMesh:
	var g := waterfall_geom(lib)
	var cx := float(g["cx"])
	var w_top := float(g["w_top"])
	var w_base := float(g["w_base"])
	var pw := float(g["pw"])
	var z_s := float(g["z_s"])
	var z_top := float(g["z_top"])
	var y_top := float(g["y_top"])
	var y_wtop := float(g["y_wtop"])
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var UV := PackedVector2Array()
	var I := PackedInt32Array()
	# ---- 水幕
	var rows := maxi(int(ceil((y_wtop - pw) / 0.4)), 2)
	var cols := 13
	# V1.3 崖口過渡：V1.2 的水幕頂列貼在崖面外 0.30 m、河道帶則一路平鋪到崖外 0.6 m（懸空的平水片＋直幕，接縫是一條硬線）。
	#   現在河道停在崖口；水幕最上面 BRINK m 從「河道末端那條水線」翻過崖口——頂列就在河道末端（同高、沿河道法線展開），
	#   往下依自由落體拋物線（崖口水平流速 V_LIP）往崖外走，到 BRINK 處接回貼崖面的直幕。第二層水幕的外推在頂端歸零。
	var has_head := lib.streams.has("stream_head")
	var e_c := Vector2(cx, z_top)
	var e_r := Vector2(1.0, 0.0)
	if has_head:
		var hs0: BPLib.Poly = lib.streams["stream_head"]
		e_c = hs0.pts[hs0.pts.size() - 1]
		e_r = BPLib.right_of(hs0.tan_at(hs0.length))
		if e_r.x < 0.0:
			e_r = -e_r                                     # 欄序 ux 0→1＝西→東，水線也要同向，否則三角形會扭
	var KB := PackedFloat32Array()
	for r in rows + 1:
		var tt := float(r) / float(rows)
		var y := lerpf(pw - 0.1, y_wtop, tt)
		var width := lerpf(w_base, w_top, tt) * (1.0 + 0.06 * sin(tt * 9.0))
		var dyb := y_wtop - y
		var kb := (1.0 - smoothstep(0.0, BRINK_H, dyb)) if has_head else 0.0
		for c in cols:
			var ux := float(c) / float(cols - 1)
			var x := cx + (ux - 0.5) * width + 0.25 * sin(tt * 7.0 + float(c) * 0.55)
			var zf := _face_z(lib, x, minf(y, y_top) + 0.05, z_s + 2.0, z_s - 45.0)       # 最上一列用崖口地形找面（水面高出的 0.26 m 不往上游找面）
			var zc := zf + 0.30 + 0.10 * sin(float(c) * 0.9 + tt * 5.0)
			if kb > 0.0:
				var lp := e_c + e_r * (ux - 0.5) * w_top
				var z_arc := lp.y + V_LIP * sqrt(2.0 * dyb / 9.81)
				x = lerpf(x, lp.x, kb)
				zc = lerpf(zc, z_arc, kb)
			V.append(Vector3(x, y, zc))
			# V1.3：翻落段的法線由河道的「朝上」漸變到水幕的「朝外」，水面到水幕的明暗不再一刀切
			N.append(Vector3.UP.lerp(Vector3(0.0, 0.12, 1.0).normalized(), 1.0 - kb).normalized())
			UV.append(Vector2(ux, 1.0 - tt))                  # v：崖口 0 → 潭面 1
			KB.append(kb)
	_grid_idx(I, 0, rows, cols)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = V
	arrays[Mesh.ARRAY_NORMAL] = N
	arrays[Mesh.ARRAY_TEX_UV] = UV
	arrays[Mesh.ARRAY_INDEX] = I
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _mat(FALL_MAT_PATH))
	# 第二層：同網格往外（+z，朝戰場）再推 0.34 m，用鏡像／錯相的材質（V1.3：翻過崖口那段的外推漸減到 0）
	var V2 := PackedVector3Array()
	for vi in V.size():
		V2.append(V[vi] + Vector3(0.0, 0.0, (0.34 + 0.06 * sin(float(vi) * 0.37)) * (1.0 - KB[vi])))
	var arrays2 := []
	arrays2.resize(Mesh.ARRAY_MAX)
	arrays2[Mesh.ARRAY_VERTEX] = V2
	arrays2[Mesh.ARRAY_NORMAL] = N
	arrays2[Mesh.ARRAY_TEX_UV] = UV
	arrays2[Mesh.ARRAY_INDEX] = I
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays2)
	mesh.surface_set_material(1, _mat(FALL_MAT_B_PATH))
	mesh.resource_name = "boss_waterfall"
	mesh.set_meta("bp_crest", Vector3(cx, y_top, z_top))
	mesh.set_meta("bp_impact", Vector3(cx, pw + 0.04, float(g["fz"])))
	return mesh


## 瀑布潭水面：依地形裁切（只在地形低於水位的格子生成），岸線自然貼地。
## 固定高度的圓盤會在潭緣飄在地面上——河床的 smin(h, carve, 1.4) 會把潭緣再挖低約 0.3 m，圓盤的邊就懸空了。
static func build_pool(lib: BPLib) -> ArrayMesh:
	var P: Dictionary = lib.L["boss_arena"]["pool"]
	var pc := Vector2(float(P["x"]), float(P["z"]))
	var wl := lib.water_y_at_stream("stream_trib", 0.0)
	var rmax := float(P["r"]) + 1.8
	var step := 0.5
	var n := int(ceil(2.0 * rmax / step)) + 1
	var x0 := pc.x - rmax
	var z0 := pc.y - rmax
	var wet := PackedByteArray()
	wet.resize(n * n)
	for j in n:
		for i in n:
			var x := x0 + float(i) * step
			var z := z0 + float(j) * step
			var inside := Vector2(x, z).distance_to(pc) <= rmax
			wet[j * n + i] = 1 if inside and lib.h_at(x, z) < wl - 0.01 else 0
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var I := PackedInt32Array()
	var idx := {}
	for j in n - 1:
		for i in n - 1:
			if wet[j * n + i] + wet[j * n + i + 1] + wet[(j + 1) * n + i] + wet[(j + 1) * n + i + 1] == 0:
				continue
			var q: Array = []
			for k in 4:
				var ci: int = i + (k & 1)
				var cj: int = j + (k >> 1)
				var key := cj * n + ci
				if not idx.has(key):
					idx[key] = V.size()
					V.append(Vector3(x0 + float(ci) * step, wl, z0 + float(cj) * step))
					N.append(Vector3.UP)
				q.append(idx[key])
			# 由上往下看順時針（x 向右、z 向下＝螢幕座標）：a→b→d、a→d→c
			I.append_array(PackedInt32Array([q[0], q[1], q[3], q[0], q[3], q[2]]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = V
	arrays[Mesh.ARRAY_NORMAL] = N
	arrays[Mesh.ARRAY_INDEX] = I
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _mat(POOL_MAT_PATH))
	mesh.resource_name = "boss_pool_surface"
	return mesh
