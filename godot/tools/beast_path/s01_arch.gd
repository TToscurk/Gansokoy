extends RefCounted
## 獸道 S01 R6：入口建築與農村道具（Blender 資產 assets/beast_path/s01_kit/src/build_s01_shrine.py → glb）在 Godot 的組裝。
## 由 prop_builder.gd 的 _torii／_lantern／_farm_patch 在 POI 有 "model" 欄位時呼叫（只有 S01 的 POI 設了 model；S02–S04 的同類 POI 照舊走原本的盒子／圓柱）。
##   torii(pb, poi)    明神鳥居：朱漆木部（s01k_paint）＋石台座（s01k_rock，苔／腳邊泥土依地形算）；碰撞＝兩柱圓柱＋台座方塊
##   lantern(pb, poi)  春日型石燈籠（s01k_rock；火袋內面壓暗）；碰撞＝一根圓柱
##   field(pb, poi)    畝と溝の耕地：順地形的土網格（s01k_soil）＋作物（大根／蔥／小松菜，Blender 資產，合併成一個網格／種）＋田緣雜草
## 腳印（森林避讓）與錨點維持原本的半徑與鍵：S01 森林規劃與 R5 林床不受影響。
const Dress := preload("res://tools/beast_path/s01_dress.gd")
const BPLib := preload("res://tools/beast_path/bp_lib.gd")
const PAINT_SH := "res://assets/beast_path/s01_kit/mat/s01k_paint.gdshader"
const SOIL_SH := "res://assets/beast_path/s01_kit/mat/s01k_soil.gdshader"
const STONE_SH := "res://assets/beast_path/s01_kit/mat/s01k_stone.gdshader"
const V2G := "res://assets/village_v2/_matlib/ground/"

## 鳥居資產尺寸（build_s01_shrine.py：SPAN 5.0、柱半徑 0.23、根卷 0.258、台座 0.92 見方、柱腳 0.30、笠木頂 5.04）
const T_SPAN := 5.0
const T_TOP := 4.6


static func _arr_mesh(name: String, mat: Material, colors: PackedColorArray = PackedColorArray()) -> ArrayMesh:
	var a := Dress.glb(name)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = a["V"]
	arr[Mesh.ARRAY_NORMAL] = a["N"]
	arr[Mesh.ARRAY_COLOR] = colors if not colors.is_empty() else a["C"]
	arr[Mesh.ARRAY_TEX_UV] = a["UV"]
	if a["UV2"] != null:
		arr[Mesh.ARRAY_TEX_UV2] = a["UV2"]
	arr[Mesh.ARRAY_INDEX] = a["I"]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m


static func paint_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(PAINT_SH)
	m.set_shader_parameter("noise_tex", load(V2G + "V2G_noise.png"))
	return m


static func _stone(pb, name: String, xf: Transform3D, moss: float, sd: int, interior: Callable = Callable(), tone: float = 1.06) -> MeshInstance3D:
	var a := Dress.glb(name)
	var C: PackedColorArray = Dress.rock_colors(pb.lib, a["V"], a["N"], xf, moss, sd, 0.92)
	for k0 in C.size():
		C[k0].g = lerpf(C[k0].g, 1.0, 0.45)            # 加工石面平整：雜訊凹陷減半（不是整顆斑駁的天然岩）
	if interior.is_valid():
		var V: PackedVector3Array = a["V"]
		for k in V.size():
			if interior.call(V[k]):
				C[k].g *= 0.32
				C[k].r *= 0.3
	var mi := MeshInstance3D.new()
	mi.name = "Stone"
	var rm := ShaderMaterial.new()                 # 加工石（燈籠、台座）：s01k_stone（比天然岩的 s01k_rock 平整、淺）
	rm.shader = load(STONE_SH)
	rm.set_shader_parameter("noise_tex", load(V2G + "V2G_noise.png"))
	rm.set_shader_parameter("tone", tone)
	mi.mesh = _arr_mesh(name, rm, C)
	return mi


# ================================================================= 鳥居
static func torii(pb, poi: Dictionary) -> Node3D:
	var py: Dictionary = pb._pos_yaw(poi)
	var r: Node3D = pb._root(poi, py["p"], py["yaw"])
	var span := float(poi.get("span", T_SPAN))
	if absf(span - T_SPAN) > 0.01:
		push_warning("[s01_arch] %s span %.2f ≠ 資產 %.2f" % [poi["id"], span, T_SPAN])
	# 兩柱腳下的地面：根節點高度取兩柱地面的較低者（台座埋 0.32 m，另一側最多再埋一點）
	var rv: Vector3 = r.transform.basis.x
	var p: Vector2 = py["p"]
	var gl: float = pb._g(p - Vector2(rv.x, rv.z) * span * 0.5)
	var gr: float = pb._g(p + Vector2(rv.x, rv.z) * span * 0.5)
	r.position.y = minf(gl, gr) + 0.02
	var wood := MeshInstance3D.new()
	wood.name = "Torii"
	var pm := paint_mat()
	pm.set_shader_parameter("tone", float(poi.get("paint_tone", 1.0)))     # 2026-10-18 荒野化：朱漆褪暗（< 1＝暗、髒）
	wood.mesh = _arr_mesh(String(poi.get("model", "s01_torii_a")), pm)         # 2026-10-18 荒野化 R2：model＝wild_torii_ruin（柱位／柱徑相同，碰撞不變）
	wood.set_instance_shader_parameter("ground_y", r.position.y)
	r.add_child(wood)
	var st := _stone(pb, "s01_torii_a_base", r.transform, float(poi.get("moss", 0.35)), absi(String(poi["id"]).hash()) % 100000, Callable(), 0.95)
	st.name = "Base"
	r.add_child(st)
	var sb: StaticBody3D = pb.body(r)
	for sx in [-1.0, 1.0]:
		pb.col_cyl(sb, 0.26, 4.45, Vector3(sx * (span * 0.5 - 0.05), 0.30 + 2.225, 0))
		pb.col_box(sb, Vector3(0.92, 0.62, 0.92), Vector3(sx * span * 0.5, -0.01, 0))
	r.set_meta("s01_model", String(poi.get("model", "s01_torii_a")))
	r.set_meta("ground_lr", [snappedf(gl, 0.01), snappedf(gr, 0.01)])
	pb._fp(String(poi["id"]), p, span * 0.5 + 2.2)
	pb.anchors[String(poi["id"])] = {"p": r.position, "h": float(poi.get("h", T_TOP))}
	return r


# ================================================================= 石燈籠
static func lantern(pb, poi: Dictionary) -> Node3D:
	var py: Dictionary = pb._pos_yaw(poi)
	var r: Node3D = pb._root(poi, py["p"], py["yaw"])
	var inside := func(v: Vector3) -> bool:
		return Vector2(v.x, v.z).length() < 0.21 and v.y > 1.24 and v.y < 1.60
	var st := _stone(pb, "s01_lantern_a", r.transform, float(poi.get("moss", 0.35)), absi(String(poi["id"]).hash()) % 100000, inside, 1.0)
	st.name = "Lantern"
	r.add_child(st)
	var sb: StaticBody3D = pb.body(r)
	pb.col_cyl(sb, 0.38, 2.2, Vector3(0, 1.1 - 0.05, 0))
	r.set_meta("s01_model", "s01_lantern_a")
	pb._fp(String(poi["id"]), py["p"], 1.1)
	return r


# ================================================================= 耕地
const F_LX := 9.4          # 畝長的一半（沿 right 方向）
const F_LZ := 6.9          # 田寬的一半（跨畝方向）
const F_PITCH := 1.15      # 畝距
const F_RIDGE_H := 0.24


static func _ridge_y(b: float) -> float:
	## 跨畝方向的剖面：頂部微圓的畝（約 55 %）、斜的畝肩、平底的溝（0＝溝底，1＝畝頂）
	var ph := fposmod((b + F_LZ) / F_PITCH, 1.0)
	var d := absf(ph - 0.5) * 2.0
	return (1.0 - smoothstep(0.42, 0.86, d)) * (1.0 - 0.08 * d * d)


static func field(pb, poi: Dictionary) -> Node3D:
	var py: Dictionary = pb._pos_yaw(poi)
	var holder: Node3D = pb._world_root(poi)
	var t: Vector2 = ((py["at"] as Dictionary)["tan"] as Vector2).normalized()
	var rv := BPLib.right_of(t)
	var F: Vector2 = py["p"]
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(String(poi["id"]).hash())
	var nz := FastNoiseLite.new()
	nz.seed = rng.seed % 100000
	nz.frequency = 0.35
	var soil := _field_soil(pb, F, rv, t, nz)
	holder.add_child(soil)
	# ---- 作物：每條畝一種（同一條畝上同種、偶有缺株）；最後一條是收成後的空畝
	var n_r := int(floor(2.0 * F_LZ / F_PITCH))
	var plan := ["s01_crop_daikon", "s01_crop_daikon", "s01_crop_daikon", "", "s01_crop_negi", "s01_crop_negi", "s01_crop_negi",
		"", "s01_crop_greens", "s01_crop_greens", "s01_crop_daikon", "s01_crop_daikon", "s01_crop_negi"]
	var spacing := {"s01_crop_daikon": 0.42, "s01_crop_negi": 0.22, "s01_crop_greens": 0.27}
	var inst := {}
	for i in n_r:
		var crop: String = plan[i % plan.size()]
		if crop == "":
			continue
		var b := -F_LZ + F_PITCH * (float(i) + 0.5)
		var end_a := F_LX - 0.7 + 0.5 * nz.get_noise_1d(b * 3.0)
		var a := -end_a + 0.3
		while a < end_a - 0.3:
			var sp: float = spacing[crop]
			var aa := a + rng.randf_range(-0.25, 0.25) * sp
			a += sp * rng.randf_range(0.9, 1.15)
			if rng.randf() < 0.07:
				continue                              # 缺株
			var bb := b + rng.randf_range(-0.05, 0.05)
			var w := F + rv * aa + t * bb
			var y := _soil_y(pb, F, rv, t, nz, aa, bb)
			var sc := rng.randf_range(0.8, 1.15)
			if crop == "s01_crop_daikon" and (i == 10 or i == 11):
				sc *= 0.7                              # 後から播いた列：小さい
			var tilt := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
			var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_euler(tilt) * Basis.from_scale(Vector3(sc, sc * rng.randf_range(0.9, 1.1), sc))
			if not inst.has(crop):
				inst[crop] = []
			(inst[crop] as Array).append(Transform3D(basis, Vector3(w.x, y - 0.01, w.y)))
	# ---- 田緣雜草（畦）：外周 0.2–1.4 m 的帶，與畝端
	var weeds := ["s01_grass_short_a", "s01_grass_short_b", "s01_forb_a"]
	var per := 2.0 * (2.0 * F_LX + 2.0 * F_LZ)
	var s := 0.0
	while s < per:
		s += rng.randf_range(0.35, 0.8)
		var q := _perimeter(s)
		var outward: Vector2 = q[1]
		var d := rng.randf_range(0.15, 1.3)
		var la: float = (q[0] as Vector2).x + outward.x * d
		var lb: float = (q[0] as Vector2).y + outward.y * d
		if nz.get_noise_2d(la * 0.6, lb * 0.6) < -0.35:
			continue
		var w2 := F + rv * la + t * lb
		var wn: String = weeds[rng.randi() % weeds.size()]
		if not inst.has(wn):
			inst[wn] = []
		var sc2 := rng.randf_range(0.8, 1.3)
		(inst[wn] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * sc2), Vector3(w2.x, pb._g(w2) - 0.02, w2.y)))
	var n_items := 0
	for nm: String in inst:
		var xs: Array = inst[nm]
		var mi := MeshInstance3D.new()
		mi.name = nm.trim_prefix("s01_")
		var tint := Color(0.78, 0.82, 0.80) if nm.begins_with("s01_crop") else Color(0.68, 0.74, 0.72)
		mi.mesh = _merge(nm, xs, Dress.veg_mat("forb" if nm.begins_with("s01_crop") else "short", [70.0, 90.0]), tint)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 110.0
		holder.add_child(mi)
		n_items += xs.size()
	holder.set_meta("s01_model", "s01_field")
	holder.set_meta("field_items", n_items)
	holder.set_meta("field_rows", n_r)
	pb._fp(String(poi["id"]), F, maxf(float(poi.get("hx", 10.0)), float(poi.get("hz", 7.0))) + 3.0)
	return holder


## 田的外周（本地 a,b），回傳 [點, 往外的法線]
static func _perimeter(s: float) -> Array:
	var L := 2.0 * F_LX
	var W := 2.0 * F_LZ
	s = fposmod(s, 2.0 * (L + W))
	if s < L:
		return [Vector2(-F_LX + s, -F_LZ - 0.1), Vector2(0, -1)]
	s -= L
	if s < W:
		return [Vector2(F_LX + 0.2, -F_LZ + s), Vector2(1, 0)]
	s -= W
	if s < L:
		return [Vector2(F_LX - s, F_LZ + 0.1), Vector2(0, 1)]
	s -= L
	return [Vector2(-F_LX - 0.2, F_LZ - s), Vector2(-1, 0)]


static func _soil_y(pb, F: Vector2, rv: Vector2, t: Vector2, nz: FastNoiseLite, a: float, b: float) -> float:
	var w := F + rv * a + t * b
	var g: float = pb._g(w)
	var end_a := F_LX + 0.5 * nz.get_noise_1d(b * 3.0)
	var fa := 1.0 - smoothstep(end_a - 0.8, end_a, absf(a))
	var edge_b := F_LZ + 0.35 * nz.get_noise_1d(a * 1.7 + 40.0)
	var inside := (1.0 - smoothstep(edge_b - 0.2, edge_b + 0.9, absf(b))) * (1.0 - smoothstep(end_a, end_a + 1.0, absf(a)))
	var clod := 0.02 * nz.get_noise_2d(a * 2.7, b * 2.7) + 0.01 * nz.get_noise_2d(a * 9.0, b * 9.0)
	var ridge := _ridge_y(b) * F_RIDGE_H * fa * (1.0 - smoothstep(F_LZ - 0.3, F_LZ, absf(b)))
	return g + lerpf(-0.05, 0.02 + ridge + clod * fa, inside)


static func _field_soil(pb, F: Vector2, rv: Vector2, t: Vector2, nz: FastNoiseLite) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var da := 0.4
	var db := F_PITCH / 10.0
	var A0 := -F_LX - 1.2
	var B0 := -F_LZ - 1.0
	var na := int(ceil(2.0 * (F_LX + 1.2) / da)) + 1
	var nb := int(ceil(2.0 * (F_LZ + 1.0) / db)) + 1
	for j in nb:
		for i in na:
			var a := A0 + da * i
			var b := B0 + db * j
			var w := F + rv * a + t * b
			var y := _soil_y(pb, F, rv, t, nz, a, b)
			var end_a := F_LX + 0.5 * nz.get_noise_1d(b * 3.0)
			var fa := 1.0 - smoothstep(end_a - 0.8, end_a, absf(a))
			var rid := _ridge_y(b) * fa * (1.0 - smoothstep(F_LZ - 0.3, F_LZ, absf(b)))
			var outer := smoothstep(F_LZ - 0.4, F_LZ + 0.6, absf(b)) + smoothstep(end_a - 0.2, end_a + 0.6, absf(a))
			st.set_color(Color(clampf(1.0 - rid * 1.25, 0.0, 1.0) * (1.0 - clampf(outer, 0.0, 1.0)), rid, clampf(outer, 0.0, 1.0), 0.5 + 0.5 * nz.get_noise_2d(a * 4.0, b * 4.0)))
			st.set_uv(Vector2(w.x, w.y))
			st.add_vertex(Vector3(w.x, y, w.y))
	for j in nb - 1:
		for i in na - 1:
			var k := j * na + i
			st.add_index(k)
			st.add_index(k + na)
			st.add_index(k + 1)
			st.add_index(k + 1)
			st.add_index(k + na)
			st.add_index(k + na + 1)
	st.generate_normals()
	st.generate_tangents()
	var m := st.commit()
	# 繞向：生成後檢查法線朝上（rv×t 的手性不同時翻轉索引）
	var arr := m.surface_get_arrays(0)
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var up := 0.0
	for q in nrm:
		up += q.y
	if up < 0.0:
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for k2 in range(0, idx.size(), 3):
			var tmp := idx[k2 + 1]
			idx[k2 + 1] = idx[k2 + 2]
			idx[k2 + 2] = tmp
		var st2 := SurfaceTool.new()
		st2.create_from_arrays(_with(arr, Mesh.ARRAY_INDEX, idx))
		st2.generate_normals()
		st2.generate_tangents()
		m = st2.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load(SOIL_SH)
	mat.set_shader_parameter("albedo_arr", load(V2G + "V2G_albedo.jpg"))
	mat.set_shader_parameter("nrh_arr", load(V2G + "V2G_nrh.jpg"))
	mat.set_shader_parameter("noise_tex", load(V2G + "V2G_noise.png"))
	m.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Soil"
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _with(arr: Array, slot: int, v) -> Array:
	var a2 := arr.duplicate()
	a2[slot] = v
	a2[Mesh.ARRAY_NORMAL] = null
	a2[Mesh.ARRAY_TANGENT] = null
	return a2


## 同一個 GLB 的多個實例合併成一個網格（生成器是 headless：不用 MultiMesh，避免 instance 矩陣存成 0）
static func _merge(name: String, xs: Array, mat: Material, tint: Color) -> ArrayMesh:
	var a := Dress.glb(name)
	var V: PackedVector3Array = a["V"]
	var N: PackedVector3Array = a["N"]
	var C: PackedColorArray = a["C"]
	var U: PackedVector2Array = a["UV"]
	var U2: PackedVector2Array = a["UV2"]
	var I: PackedInt32Array = a["I"]
	var oV := PackedVector3Array()
	var oN := PackedVector3Array()
	var oC := PackedColorArray()
	var oU := PackedVector2Array()
	var oU2 := PackedVector2Array()
	var oI := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = name.hash()
	for xf: Transform3D in xs:
		var base := oV.size()
		var k := rng.randf_range(0.9, 1.08)
		var tc := Color(tint.r * k, tint.g * k, tint.b * k)
		for i in V.size():
			oV.append(xf * V[i])
			oN.append((xf.basis * N[i]).normalized())
			var c := C[i]
			oC.append(Color(c.r * tc.r, c.g * tc.g, c.b * tc.b, 1.0))
		oU.append_array(U)
		oU2.append_array(U2)
		for i2 in I:
			oI.append(base + i2)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = oV
	arr[Mesh.ARRAY_NORMAL] = oN
	arr[Mesh.ARRAY_COLOR] = oC
	arr[Mesh.ARRAY_TEX_UV] = oU
	arr[Mesh.ARRAY_TEX_UV2] = oU2
	arr[Mesh.ARRAY_INDEX] = oI
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m
