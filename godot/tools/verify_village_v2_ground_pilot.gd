extends SceneTree
## P10 R5a Ground Pilot gate（回歸 tag GRD）。使用者 2026-10-09 D3（道路 base 有條件）／D4（田格 limited fix）。
##   shader 產生＋plan＋反向（headless）：Godot --headless --path . --script res://tools/verify_village_v2_ground_pilot.gd
##   build（headless 可，無 MultiMesh）：… -- --build
##   attach：… -- --attach        （village_v2.tscn 加 root/GroundPilotP10，AlbedoPilotP10 之後）
##   scene（非 headless：shader 參數清單需要真的 RenderingServer）：… -- --scene
## plan：
##   1 來源 ground.gdshader 雜湊＝_matlib matlib.json ground.files_sha256（封存值；來源變了就不打補丁）
##   2 6 段補丁各恰好命中 1 次
##   3 磁碟上的 pilot shader＝補丁結果逐字（可重現、沒被手改）
##   4 田格已移除（無 `mod(p - paddy.xy`）；discard 只在外緣侵蝕段
##   5 新參數預設值＝舊行為（edge_w／edge_irreg／center_patch 預設 0）——沒被 Pilot 指名的道路不受影響
##   6 Pilot 道路參數在核准範圍：edge_w ∈ [0.25,1.20]、edge_irreg ∈ [0.08,0.45]、核心保留 edge_core ≤ 0.35
##   7 外緣實測（CPU 以同一張 V2G_noise.png 雙線性重算 shader 的侵蝕式）：每條 Pilot 道路兩側外緣位置沿路
##     標準差 ∈ [0.08,0.45] m、最大侵蝕 ≤ 半寬×edge_core、侵蝕 > 0 的外緣比例 ≥ 30 %（不是一條直線）
const LIB := preload("res://tools/village_v2_ground_pilot_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const MATLIB := "res://assets/village_v2/_matlib/matlib.json"
const NOISE_PNG := "res://assets/village_v2/_matlib/ground/V2G_noise.png"
const EXT_ID := "p10r5a_ground_pilot"
const AFTER_NODE := "[node name=\"AlbedoPilotP10\" parent=\".\" instance=ExtResource(\"p10r6a_albedo_pilot\")]"
var fails := 0
var quiet := false
var noise: Image


func _ok(c: bool, msg: String) -> bool:
	if not quiet:
		print("[GRD] ", "PASS " if c else "FAIL ", msg)
	if not c:
		fails += 1
	return c


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if "--attach" in args:
		quit(_attach())
		return
	if "--scene" in args:
		var v: Node3D = (load(SCENE) as PackedScene).instantiate()
		root.add_child(v)
		await process_frame
		await _scene(v)
		print("[GRD] 結果：%d 項失敗" % fails)
		quit(fails)
		return
	noise = Image.load_from_file(ProjectSettings.globalize_path(NOISE_PNG))
	var src := FileAccess.get_file_as_string(LIB.SRC_SHADER)
	var w := LIB.write_shader()
	print("[GRD] shader 產生：", JSON.stringify(w))
	var disk := FileAccess.get_file_as_string(LIB.OUT_SHADER)
	var roads := _road_edges()
	_gates(src, disk, LIB.ROADS, LIB.PATCHES, roads)
	if "--build" in args:
		_build()
	else:
		_negatives(src, disk, roads)
	print("[GRD] 結果：%d 項失敗" % fails)
	quit(fails)


## 讀 Pilot 道路 mesh（gen/road_*.res）→ 兩側外緣點列（每 2 m 一對，_ribbon 的頂點順序）＋半寬
func _road_edges() -> Dictionary:
	var out := {}
	var txt := FileAccess.get_file_as_string(SCENE)
	for path in LIB.ROADS:
		var nm := String(path).get_file()
		var mesh_path := "res://maps/village_v2/gen/road_%s.res" % nm.to_lower()
		var m := load(mesh_path) as ArrayMesh
		if m == null:
			out[path] = {}
			continue
		var arr := m.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		var left := {}
		var right := {}
		var hw := 0.0
		for i in vs.size():
			var key := snappedf(uv[i].y, 0.01)
			if uv[i].x > 0.0:
				left[key] = vs[i]
			else:
				right[key] = vs[i]
			hw = maxf(hw, uv2[i].x)
		out[path] = {"left": left, "right": right, "hw": hw, "mesh": mesh_path}
	return out


func _tex(uv: Vector2, ch: int) -> float:
	var W := noise.get_width()
	var H := noise.get_height()
	var x := uv.x * W - 0.5
	var y := uv.y * H - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var c00 := noise.get_pixel(posmod(x0, W), posmod(y0, H))
	var c10 := noise.get_pixel(posmod(x0 + 1, W), posmod(y0, H))
	var c01 := noise.get_pixel(posmod(x0, W), posmod(y0 + 1, H))
	var c11 := noise.get_pixel(posmod(x0 + 1, W), posmod(y0 + 1, H))
	var c := c00.lerp(c10, fx).lerp(c01.lerp(c11, fx), fy)
	return [c.r, c.g, c.b, c.a][ch]


## shader 侵蝕式的 CPU 重算（同 V2G_noise.png、同取樣座標）：s＝沿路 m（UV.y）、sgn＝左 +1／右 −1；
## 草舌取樣依賴離緣距離 → 切口位置＝不動點，迭代 3 次
func _bite(p: Vector2, s: float, sgn: float, hw: float, prm: Dictionary) -> float:
	var nf := _tex(p / 3.7 + Vector2(0.53, 0.11), 2)
	var n_lo := _tex(p / 11.0 + Vector2(0.13, 0.57), 0)
	var cut := 0.0
	for it in 3:
		var n_mid := _tex(Vector2(s / 4.3, cut / 1.3) + Vector2(0.71, 0.29 + sgn * 0.37), 1)
		var bite := float(prm["edge_irreg"]) * smoothstep(0.30, 0.75, n_lo) + float(prm["edge_w"]) * (smoothstep(0.35, 0.80, n_mid) * 0.7 + (nf - 0.5) * 0.6)
		cut = minf(maxf(bite, 0.0), hw * float(prm.get("edge_core", LIB.CORE_KEEP)))
	return cut


func _gates(src: String, disk: String, roads_cfg: Dictionary, patches: Array, edges: Dictionary) -> void:
	# 1 來源雜湊＝封存值
	var mj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MATLIB))
	var sealed := String(mj["ground"]["files_sha256"].get(LIB.SRC_SHADER, ""))
	var now := src.sha256_text()
	var now_file := FileAccess.get_sha256(LIB.SRC_SHADER)
	_ok(sealed != "" and now_file == sealed and now == now_file, "來源 ground.gdshader 雜湊＝matlib.json 封存值（%s…）" % sealed.substr(0, 12))
	# 2 補丁命中
	var miss := []
	for pt in patches:
		if src.count(pt[0]) != 1:
			miss.append(String(pt[0]).strip_edges().substr(0, 30))
	_ok(miss.is_empty(), "補丁 %d 段各命中 1 次%s" % [patches.size(), "" if miss.is_empty() else " ✗ " + str(miss)])
	# 3 可重現
	var code := src
	for pt in patches:
		code = code.replace(pt[0], pt[1])
	_ok(disk == code, "磁碟 pilot shader＝補丁結果逐字（%s）" % LIB.OUT_SHADER)
	# 4 田格移除、discard 位置
	var ndis := disk.count("discard;")
	_ok(not disk.contains("mod(p - paddy.xy") and ndis == 2 and disk.contains("if (from_edge < cut) {") and disk.contains("if (cut_s.y > cut_s.x && UV.y > cut_s.x && UV.y < cut_s.y && xm < cut_hw) {"), "田格段已移除、discard 只在外緣侵蝕段＋參道石段挖洞段（%d）" % ndis)
	# 5 預設值＝舊行為
	var defaults_ok := disk.contains("uniform float edge_w = 0.0;") and disk.contains("uniform float edge_irreg = 0.0;") and disk.contains("uniform float center_patch = 0.0;") and disk.contains("uniform vec2 cut_s = vec2(0.0);") and disk.contains("uniform float cut_hw = 0.0;")
	_ok(defaults_ok, "新參數預設 edge_w／edge_irreg／center_patch／cut_s／cut_hw＝0（未指名道路不變）")
	# 6 參數範圍
	var bad6 := []
	for k in roads_cfg:
		var d: Dictionary = roads_cfg[k]
		if float(d["edge_w"]) < LIB.EDGE_W_RANGE[0] or float(d["edge_w"]) > LIB.EDGE_W_RANGE[1]:
			bad6.append("%s edge_w %.2f" % [String(k).get_file(), d["edge_w"]])
		if float(d["edge_irreg"]) < LIB.EDGE_IRREG_RANGE[0] or float(d["edge_irreg"]) > LIB.EDGE_IRREG_RANGE[1]:
			bad6.append("%s edge_irreg %.2f" % [String(k).get_file(), d["edge_irreg"]])
		if float(d.get("edge_core", LIB.CORE_KEEP)) > 0.35:
			bad6.append("%s edge_core %.2f" % [String(k).get_file(), d.get("edge_core", 0.0)])
	_ok(bad6.is_empty(), "Pilot 道路 %d 條參數在核准範圍%s" % [roads_cfg.size(), "" if bad6.is_empty() else " ✗ " + str(bad6)])
	# 7 外緣實測
	var rep := []
	var bad7 := []
	for k in roads_cfg:
		var e: Dictionary = edges.get(k, {})
		if e.is_empty():
			bad7.append("%s 無 mesh" % String(k).get_file())
			continue
		var prm: Dictionary = roads_cfg[k].duplicate()
		prm["edge_core"] = float(roads_cfg[k].get("edge_core", LIB.CORE_KEEP))
		var hw := float(e["hw"])
		for side in ["left", "right"]:
			var pts: Dictionary = e[side]
			var keys := pts.keys()
			keys.sort()
			var vals := PackedFloat32Array()
			var bitten := 0
			var mx := 0.0
			# 每 2 m 一個外緣頂點；兩頂點之間再細分 4 段（0.5 m）
			var sgn := 1.0 if side == "left" else -1.0
			for i in keys.size() - 1:
				var a: Vector3 = pts[keys[i]]
				var b: Vector3 = pts[keys[i + 1]]
				for q in 4:
					var pp := Vector2(a.x, a.z).lerp(Vector2(b.x, b.z), q / 4.0)
					var ss := lerpf(float(keys[i]), float(keys[i + 1]), q / 4.0)
					var bt := _bite(pp, ss, sgn, hw, prm)
					vals.append(bt)
					mx = maxf(mx, bt)
					if bt > 0.02:
						bitten += 1
			var mean := 0.0
			for x in vals:
				mean += x
			mean /= maxf(vals.size(), 1)
			var var_ := 0.0
			for x in vals:
				var_ += (x - mean) * (x - mean)
			var sd := sqrt(var_ / maxf(vals.size(), 1))
			var frac := float(bitten) / maxf(vals.size(), 1)
			rep.append("%s/%s sd %.2f max %.2f 侵蝕 %d%%" % [String(k).get_file(), side.substr(0, 1), sd, mx, int(frac * 100.0)])
			if sd < LIB.EDGE_IRREG_RANGE[0] or sd > LIB.EDGE_IRREG_RANGE[1] or mx > hw * float(prm["edge_core"]) + 1e-4 or frac < 0.30:
				bad7.append(rep[rep.size() - 1])
	_ok(bad7.is_empty(), "外緣實測（CPU 同雜訊重算）：%s%s" % [", ".join(rep), "" if bad7.is_empty() else " ✗ " + str(bad7)])


func _negatives(src: String, disk: String, edges: Dictionary) -> void:
	print("[GRD] 永久反向（每案必須讓 gate 失敗）")
	var cases := []
	cases.append(["N1 來源 shader 已變（補丁段找不到）", src.replace("float bh = bund_w * 0.5 + 0.3;", "float bh = bund_w * 0.5 + 0.31;"), disk, LIB.ROADS, LIB.PATCHES])
	cases.append(["N2 pilot shader 被手改", src, disk.replace("farm_soil = 0.32", "farm_soil = 0.9"), LIB.ROADS, LIB.PATCHES])
	var r3 := LIB.ROADS.duplicate(true)
	r3[r3.keys()[0]]["edge_w"] = 2.0
	cases.append(["N3 edge_w 超出 1.20 m", src, disk, r3, LIB.PATCHES])
	var r4 := LIB.ROADS.duplicate(true)
	r4[r4.keys()[1]]["edge_core"] = 0.8
	cases.append(["N4 侵蝕吃進路面核心（edge_core 0.8）", src, disk, r4, LIB.PATCHES])
	var p5 := []
	for pt in LIB.PATCHES:
		p5.append([pt[0], pt[0]] if pt[0] == LIB.OLD_GRID else pt)
	var code5 := src
	for pt in p5:
		code5 = code5.replace(pt[0], pt[1])
	cases.append(["N5 田格沒移除", src, code5, LIB.ROADS, p5])
	cases.append(["N6 edge_w 預設非 0（全部道路都被侵蝕）", src, disk.replace("uniform float edge_w = 0.0;", "uniform float edge_w = 0.5;"), LIB.ROADS, LIB.PATCHES])
	cases.append(["N7 外緣等寬（雜訊無起伏 → 侵蝕成一條平行直線）", src, disk, LIB.ROADS, LIB.PATCHES, "flat"])
	var neg_fail := 0
	var real_noise := noise
	for c in cases:
		var f0 := fails
		quiet = true
		if c.size() > 5 and c[5] == "flat":
			noise = Image.create(8, 8, false, Image.FORMAT_RGBA8)
			noise.fill(Color(0.6, 0.6, 0.6, 0.6))
		_gates(c[1], c[2], c[3], c[4], edges)
		noise = real_noise
		quiet = false
		var tripped := fails > f0
		fails = f0
		print("[GRD]   %s：%s" % [c[0], "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			neg_fail += 1
	_ok(neg_fail == 0, "反向 %d/%d" % [cases.size() - neg_fail, cases.size()])


func _build() -> void:
	if fails > 0:
		_ok(false, "plan gate 未過，不 build")
		return
	var n := LIB.build()
	n.set_meta("src_sha256", FileAccess.get_sha256(LIB.SRC_SHADER))
	n.set_meta("pilot_sha256", FileAccess.get_sha256(LIB.OUT_SHADER))
	var ps := PackedScene.new()
	_ok(ps.pack(n) == OK, "pack")
	_ok(ResourceSaver.save(ps, LIB.OUTPUT) == OK, "save %s" % LIB.OUTPUT)
	var rb := (ResourceLoader.load(LIB.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	_ok((rb.get("road_paths") as PackedStringArray).size() == LIB.ROADS.size() and rb.get("pilot_shader") != null, "回讀：道路 %d、shader %s" % [(rb.get("road_paths") as PackedStringArray).size(), rb.get("pilot_shader")])
	rb.free()
	print("[GRD] build {\"roads\":%d,\"output_sha256\":\"%s\"}" % [LIB.ROADS.size(), FileAccess.get_sha256(LIB.OUTPUT)])


## 非 Pilot 道路の材質不変検査。戻り値＝[検査数, 不一致の配列]。w6_roads（RoadEdgeBlendP13 引き受け）は pilot shader であることだけ要求。
func _non_pilot_bad(v: Node3D, fresh: Node3D, targets: PackedStringArray, w6_roads: PackedStringArray, sh: Shader) -> Array:
	var others := 0
	var other_bad := []
	for mi in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
		var p := String(v.get_path_to(mi))
		if p in targets or not (p.begins_with("Roads/MainStreet") or p.begins_with("Roads/SecondaryRoads") or p.begins_with("Roads/Alleys") or p.begins_with("Roads/FarmPaths")):
			continue
		# 參道 ribbon 由 R6b ShrineApproachP10 接管（石段挖洞），不屬本 Pilot 的「不變」檢查
		var sap := v.get_node_or_null("ShrineApproachP10")
		if sap and String(sap.get("ribbon_path")) == p:
			continue
		if p in w6_roads:
			var mw := (mi as MeshInstance3D).material_override as ShaderMaterial
			if mw == null or mw.shader != sh:
				other_bad.append(p + "（W6 引き受けだが pilot shader でない）")
			continue
		var f := fresh.get_node_or_null(NodePath(p)) as MeshInstance3D
		others += 1
		if f == null or (mi as MeshInstance3D).material_override != f.material_override:
			other_bad.append(p)
	return [others, other_bad]


func _scene(v: Node3D) -> void:
	var nodes := v.find_children(LIB.NODE_NAME, "", false, false)
	_ok(nodes.size() == 1, "root/%s 掛載 1 個（實得 %d）" % [LIB.NODE_NAME, nodes.size()])
	if nodes.is_empty():
		return
	var n := nodes[0] as Node3D
	var ap := v.get_node_or_null("AlbedoPilotP10")
	_ok(ap != null and ap.get_index() == n.get_index() - 1, "順序：AlbedoPilotP10 之後（index %d）" % n.get_index())
	# 原材質（套用前）：從封存場景重讀
	var fresh: Node3D = (ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene).instantiate()
	for i in 6:
		await process_frame
	var sh: Shader = n.get("pilot_shader")
	var targets := PackedStringArray(n.get("terrain_paths")) + PackedStringArray(n.get("road_paths"))
	var ok_cnt := 0
	var bad := []
	for p in targets:
		var mi := v.get_node_or_null(NodePath(p)) as MeshInstance3D
		var f := fresh.get_node_or_null(NodePath(p)) as MeshInstance3D
		if mi == null or f == null:
			bad.append("%s 不存在" % p)
			continue
		var m := mi.material_override as ShaderMaterial
		var o := f.material_override as ShaderMaterial
		if m == null or m.shader != sh:
			bad.append("%s 未覆寫" % p)
			continue
		var diff := []
		for u in o.shader.get_shader_uniform_list():
			var nm := String(u["name"])
			if nm in ["farm_soil", "edge_w", "edge_irreg", "edge_core", "center_patch", "cut_s", "cut_hw"]:
				continue
			if o.get_shader_parameter(nm) != m.get_shader_parameter(nm):
				diff.append(nm)
		if not diff.is_empty():
			bad.append("%s 參數不同 %s" % [p, diff])
			continue
		ok_cnt += 1
	_ok(bad.is_empty() and ok_cnt == targets.size(), "Pilot 對象 %d 個（地形 %d＋道路 %d）全部換 pilot shader、原參數逐一保留%s" % [ok_cnt, (n.get("terrain_paths") as PackedStringArray).size(), (n.get("road_paths") as PackedStringArray).size(), "" if bad.is_empty() else " ✗ " + str(bad)])
	# 非 Pilot 道路不變
	# P13 W6 limited verifier correction（範圍＝RoadEdgeBlendP13.road_paths 列的道路、僅此）：這些道路由後續 overlay 套同一個
	# pilot shader（外緣侵蝕），所以不再要求「材質不變」，改要求「已換成本 Pilot 的 shader」；其餘道路仍逐一要求材質不變（反向見下）。
	var w6n := v.get_node_or_null("RoadEdgeBlendP13")
	var w6_roads := PackedStringArray(w6n.get("road_paths")) if w6n != null else PackedStringArray()
	var res := _non_pilot_bad(v, fresh, targets, w6_roads, sh)
	var others: int = res[0]
	var other_bad: Array = res[1]
	_ok(other_bad.is_empty(), "非 Pilot 道路 %d 條材質不變（另 %d 條由 RoadEdgeBlendP13 套同一 pilot shader）%s" % [others, w6_roads.size(), "" if other_bad.is_empty() else " ✗ " + str(other_bad)])
	# 反向（W6）：W6 引き受けでない道路〔MainStreet〕の材質を差し替えると、この検査が必ず 1 件検出する
	var mst := v.get_node_or_null("Roads/MainStreet/MainStreet") as MeshInstance3D
	if mst != null:
		var keep := mst.material_override
		mst.material_override = ShaderMaterial.new()
		var neg: Array = _non_pilot_bad(v, fresh, targets, w6_roads, sh)[1]
		mst.material_override = keep
		_ok(neg.size() == 1, "反向：W6 引き受け外の道路（MainStreet）の材質を差し替えると非 Pilot 検査が 1 件検出（%d）" % neg.size())
	# 開關還原
	n.set("enabled", false)
	var left := 0
	for p in targets:
		var mi := v.get_node_or_null(NodePath(p)) as MeshInstance3D
		if mi and mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).shader == sh:
			left += 1
	_ok(left == 0, "enabled=false → 原材質還原（殘留 %d）" % left)
	n.set("enabled", true)
	_ok(int(n.get("applied")) == targets.size(), "enabled=true → 重新套用 %d" % int(n.get("applied")))
	# 來源檔不變
	_ok(String(n.get_meta("src_sha256", "")) == FileAccess.get_sha256(LIB.SRC_SHADER) and String(n.get_meta("pilot_sha256", "")) == FileAccess.get_sha256(LIB.OUT_SHADER), "ground.gdshader／pilot shader 雜湊＝build 時")
	# 實際渲染（觸發 shader 編譯；SHADER ERROR 由外層 log 檢查）
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	for p in [Vector3(392.0, 8.0, 0.0), Vector3(300.0, 8.0, 52.0)]:
		cam.global_transform = Transform3D(Basis(), p).looking_at(p + Vector3(6.0, -5.0, 0.0), Vector3.UP)
		for i in 4:
			await process_frame
	print("[GRD] INFO 渲染 2 個 Pilot 機位完成（外層 log 檢 SHADER ERROR）")
	fresh.free()


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(LIB.OUTPUT):
		push_error("找不到 %s（先 --build）" % LIB.OUTPUT)
		return 1
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [LIB.NODE_NAME, EXT_ID]
	if txt.contains(line):
		print("[GRD] attach：已掛（不重複、不寫場景）")
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray(Array(lines))
	var at := out.find(AFTER_NODE)
	if at < 0:
		push_error("找不到 root/AlbedoPilotP10（先掛 R6a albedo pilot）")
		return 1
	if at + 1 < out.size() and out[at + 1].strip_edges() != "":
		push_error("AlbedoPilotP10 節點後面不是空行，拒絕文字插入")
		return 1
	out.insert(at + 1, "")
	out.insert(at + 2, line)
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [LIB.OUTPUT, EXT_ID])
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[GRD] attach：加 root/%s（AlbedoPilotP10 之後）→ %s（+%d 行）" % [LIB.NODE_NAME, SCENE, out.size() - lines.size()])
	return 0
