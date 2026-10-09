extends SceneTree
## P10 R6a ROUND 3 — 町家 Kit 專用校正材質の「合法変体機制」gate（tag KITM）。
##   Godot --headless --path godot --script res://tools/verify_village_v2_kit_material.gd [-- --write]
## --write：Kit 專用校正材質＋shader＋登記表 kit_material_variants.json を書く（値＝village_v2_albedo_pilot_lib.gd の承認済み定数）。
## 検査：
##   K1 登記表 ↔ 檔案：変体 18（cal 3＋Kit atlas 1＋調色盤 14）、id 一意、各檔 sha256 一致、shader sha256 一致
##   K2 基底との差：StandardMaterial3D は基底（_matlib／Kit）と albedo_color 以外の全プロパティ一致；Kit atlas は貼圖・粗さ・発光が基底と同じ、
##      shader＝登記 shader、band は承認値（＝任意の見た目変更を変体名で持ち込めない）
##   K3 色の範囲：飽和度 ≤ 0.22、albedo 明度が類別の帯（登記）内、色卡 luma 帯を登記
##   K4 承認済み Pilot と同値：各変体の値＝village_v2_albedo_pilot_lib.gd の CAL／KIT_CLASS／PALETTE（第一輪核准 24 棟）
##   K5 場景：町家 Kit 建物（Districts の B_*／Kit の子木）の override は「登記表の変体」だけ・「登記の Pilot 建物」だけ；Pilot 24 棟以外の 163 棟は override 0
##   K6 保護：_matlib・P6 Kit 原檔・Kit gate.json／manifest の sha256＝登記時と同じ、かつ git HEAD から未変更
## 永久反向：N1 登記外の override（albedo 0.9）／N2 登記変体を Pilot 外の建物に／N3 変体の粗さを変える／N4 飽和 0.30／N5 登記 sha 改竄／N6 明度が帯外
const KM := preload("res://tools/village_v2_kit_material_lib.gd")
const AP := preload("res://tools/village_v2_albedo_pilot_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"

var fails := 0
var quiet := false
var V: Node3D


func _ok(c: bool, msg: String) -> bool:
	if not quiet:
		print("[KITM] ", "PASS " if c else "FAIL ", msg)
	if not c:
		fails += 1
	return c


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	V = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(V)
	for i in 6:
		await process_frame
	if "--write" in args:
		var reg := KM.write_all()
		var paths := []
		for it in AP.targets(V):
			paths.append(String(it["path"]))
		reg["pilot_buildings"] = paths
		KM.write_registry(reg)
		print("[KITM] write：変体 %d、Pilot 建物 %d → %s" % [(reg["variants"] as Array).size(), paths.size(), KM.REGISTRY])
		quit(0)
		return
	var reg := KM.registry()
	var mats := _load_mats(reg)
	var ov := _overrides()
	_checks(reg, mats, ov)
	print("[KITM] 永久反向（每案必須讓 gate 失敗）")
	var neg_fail := 0
	var first_target: String = (reg["pilot_buildings"] as Array)[0]
	var non_target := ""
	for b in ov.keys():
		if not (b in reg["pilot_buildings"]):
			non_target = b
			break
	var cases := ["N1 登記外の override（albedo 0.9）", "N2 登記変体を Pilot 外の建物に", "N3 変体の粗さを変える", "N4 飽和 0.30", "N5 登記 sha 改竄", "N6 明度が帯外（0.95）"]
	for ci in cases.size():
		var r2: Dictionary = reg.duplicate(true)
		var m2 := mats.duplicate()
		var o2 := {}
		for b in ov:
			o2[b] = (ov[b] as Array).duplicate()
		match ci:
			0:
				var bad := (load("res://assets/village_v2/_matlib/V2_Plaster.tres") as StandardMaterial3D).duplicate() as StandardMaterial3D
				bad.albedo_color = Color(0.9, 0.9, 0.9)
				o2[first_target].append(bad)
			1:
				o2[non_target] = [m2.values()[0]]
			2:
				var vid := "V2_Plaster_K_A0"
				var x := (m2[vid] as StandardMaterial3D).duplicate() as StandardMaterial3D
				x.roughness = 0.3
				m2[vid] = x
			3:
				var vid2 := "V2_Wood_K_B1"
				var y := (m2[vid2] as StandardMaterial3D).duplicate() as StandardMaterial3D
				y.albedo_color = Color(0.80, 0.62, 0.56)
				m2[vid2] = y
			4:
				r2["variants"][3]["sha256"] = "0".repeat(64)
			5:
				var vid3 := "V2_Plaster_K_B2"
				var z := (m2[vid3] as StandardMaterial3D).duplicate() as StandardMaterial3D
				z.albedo_color = Color(0.95, 0.95, 0.95)
				m2[vid3] = z
		var f0 := fails
		quiet = true
		_checks(r2, m2, o2)
		quiet = false
		var tripped := fails > f0
		fails = f0
		print("[KITM]   %s：%s" % [cases[ci], "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			neg_fail += 1
	_ok(neg_fail == 0, "反向 %d/%d" % [cases.size() - neg_fail, cases.size()])
	print("[KITM] 結果：%d 項失敗" % fails)
	quit(fails)


func _load_mats(reg: Dictionary) -> Dictionary:
	var out := {}
	for e in reg.get("variants", []):
		out[String(e["id"])] = load(String(e["file"]))
	return out


## 町家 Kit 建物ごとの override 一覧（AlbedoPilotP10 の適用後）
func _overrides() -> Dictionary:
	var out := {}
	for n in V.get_node("Districts").find_children("B_*", "", true, false):
		if not (n is Node3D) or (n as Node).get_node_or_null("Kit") == null:
			continue
		var lst := []
		# 範囲＝Kit の子木（Kit Gate の対象と同じ）。B_* 直下の P4 灰盒（Foundation／Building_Main／Roof…、village_v2.tscn 埋め込みの
		# 既存 material_override）は町家 Kit ではないので対象外
		for mi in (n as Node).get_node("Kit").find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.material_override != null:
				lst.append(m.material_override)
			if m.mesh != null:
				for si in m.mesh.get_surface_count():
					var so := m.get_surface_override_material(si)
					if so != null:
						lst.append(so)
		out[String(V.get_path_to(n))] = lst
	return out


func _props(m: Material) -> Dictionary:
	var d := {}
	for p in m.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_STORAGE and not String(p["name"]) in ["resource_name", "resource_path", "resource_local_to_scene", "script", "albedo_color", "next_pass"]:
			d[String(p["name"])] = m.get(String(p["name"]))
	return d


func _checks(reg: Dictionary, mats: Dictionary, ov: Dictionary) -> void:
	var vs: Array = reg.get("variants", [])
	# K1
	var bad1 := []
	var ids := {}
	for e in vs:
		if ids.has(e["id"]):
			bad1.append("id 重複 %s" % e["id"])
		ids[e["id"]] = true
		if FileAccess.get_sha256(String(e["file"])) != String(e["sha256"]):
			bad1.append("%s sha 不一致" % e["id"])
		if mats.get(e["id"]) == null:
			bad1.append("%s 讀不到" % e["id"])
	if FileAccess.get_sha256(String(reg["shader"]["file"])) != String(reg["shader"]["sha256"]):
		bad1.append("shader sha 不一致")
	var n_cal := vs.filter(func(e): return e["kind"] == "cal").size()
	var n_kit := vs.filter(func(e): return e["kind"] == "kit_atlas_cal").size()
	var n_pal := vs.filter(func(e): return e["kind"] == "palette").size()
	_ok(bad1.is_empty() and n_cal == 3 and n_kit == 1 and n_pal == 14, "K1 登記表 ↔ 檔案：変体 %d（cal %d・Kit atlas %d・調色盤 %d）、id 一意、sha256 一致、shader 一致%s" % [vs.size(), n_cal, n_kit, n_pal, "" if bad1.is_empty() else " ✗ " + str(bad1.slice(0, 3))])
	# K2
	var bad2 := []
	for e in vs:
		var m: Material = mats.get(e["id"])
		if m == null:
			continue
		if e["kind"] == "kit_atlas_cal":
			var src := load(String(e["base"])) as StandardMaterial3D
			var sm := m as ShaderMaterial
			if sm == null or sm.shader == null or sm.shader.resource_path != String(reg["shader"]["file"]):
				bad2.append("%s shader" % e["id"])
				continue
			if sm.get_shader_parameter("albedo_tex") != src.albedo_texture or sm.get_shader_parameter("emit_tex") != src.emission_texture \
					or not is_equal_approx(float(sm.get_shader_parameter("roughness_v")), src.roughness) or not is_equal_approx(float(sm.get_shader_parameter("emission_energy")), src.emission_energy_multiplier):
				bad2.append("%s 貼圖／粗さ／発光が基底と違う" % e["id"])
			if Vector2(sm.get_shader_parameter("band_dark")) != Vector2(AP.KIT_CLASS["band_dark"][0], AP.KIT_CLASS["band_dark"][1]) or Vector2(sm.get_shader_parameter("band_light")) != Vector2(AP.KIT_CLASS["band_light"][0], AP.KIT_CLASS["band_light"][1]):
				bad2.append("%s band" % e["id"])
			continue
		var base := load(String(e["base"])) as Material
		var pa := _props(base)
		var pb := _props(m)
		for k in pa:
			if not pb.has(k) or typeof(pa[k]) != typeof(pb[k]) or (pa[k] != pb[k] and not (typeof(pa[k]) == TYPE_FLOAT and is_equal_approx(pa[k], pb[k]))):
				bad2.append("%s.%s" % [e["id"], k])
	_ok(bad2.is_empty(), "K2 基底との差＝albedo_color だけ（Kit atlas＝k 係数だけ；貼圖・粗さ・発光・band は基底／承認値と同じ）%s" % ("" if bad2.is_empty() else " ✗ " + str(bad2.slice(0, 4))))
	# K3
	var bad3 := []
	for e in vs:
		var m3 = mats.get(e["id"])
		if not (m3 is StandardMaterial3D):
			continue
		var c: Color = (m3 as StandardMaterial3D).albedo_color
		var bn := KM.base_name(String(e["base"]))
		var band: Array = reg["albedo_band"][bn]
		var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		if KM._sat(c) > float(reg["sat_max"]) + 1e-4:
			bad3.append("%s 飽和 %.2f" % [e["id"], KM._sat(c)])
		if lum < float(band[0]) - 1e-4 or lum > float(band[1]) + 1e-4:
			bad3.append("%s 明度 %.3f 帯外 %s" % [e["id"], lum, str(band)])
	_ok(bad3.is_empty(), "K3 飽和度 ≤ %.2f・albedo 明度が類別の帯（漆喰 %s・木 %s・基石 %s）%s" % [float(reg["sat_max"]), str(reg["albedo_band"]["V2_Plaster"]), str(reg["albedo_band"]["V2_Wood"]), str(reg["albedo_band"]["V2_KitStoneTri"]), "" if bad3.is_empty() else " ✗ " + str(bad3.slice(0, 3))])
	# K4
	var bad4 := []
	var pl := KM.plan()
	var by := {}
	for e in pl:
		by[String(e["id"])] = e
	for e in vs:
		var m4 = mats.get(e["id"])
		var want: Dictionary = by.get(String(e["id"]), {})
		if want.is_empty():
			bad4.append("%s 承認値に無い" % e["id"])
			continue
		if m4 is StandardMaterial3D and not (m4 as StandardMaterial3D).albedo_color.is_equal_approx(want["color"]):
			bad4.append("%s albedo" % e["id"])
		if m4 is ShaderMaterial:
			for k in ["k_dark", "k_mid", "k_light"]:
				if not is_equal_approx(float((m4 as ShaderMaterial).get_shader_parameter(k)), float(want["k"][k])):
					bad4.append("%s %s" % [e["id"], k])
	_ok(bad4.is_empty() and pl.size() == vs.size(), "K4 承認済み 24 棟 Pilot と同値（village_v2_albedo_pilot_lib.gd CAL／KIT_CLASS／PALETTE）：%d／%d%s" % [vs.size() - bad4.size(), pl.size(), "" if bad4.is_empty() else " ✗ " + str(bad4.slice(0, 3))])
	# K5
	var reg_paths := {}
	for e in vs:
		reg_paths[String(e["file"])] = true
	var pilots: Array = reg.get("pilot_buildings", [])
	var bad5 := []
	var n_pilot_ov := 0
	var n_other_ov := 0
	for b in ov:
		for m5: Material in ov[b]:
			if not reg_paths.has(m5.resource_path):
				bad5.append("%s 登記外 %s" % [String(b).get_file(), m5.resource_name])
			elif not (b in pilots):
				bad5.append("%s は Pilot 外" % String(b).get_file())
		if not (ov[b] as Array).is_empty():
			if b in pilots:
				n_pilot_ov += 1
			else:
				n_other_ov += 1
	_ok(bad5.is_empty() and n_pilot_ov == pilots.size() and pilots.size() == 24 and n_other_ov == 0, "K5 場景：町家 Kit 建物 %d 棟、override のある建物＝Pilot %d／%d 棟（すべて登記変体）・Pilot 外 %d 棟%s" % [ov.size(), n_pilot_ov, pilots.size(), n_other_ov, "" if bad5.is_empty() else " ✗ " + str(bad5.slice(0, 3))])
	# K6
	var bad6 := []
	for p in reg["protected"]:
		if FileAccess.get_sha256(p) != String(reg["protected"][p]):
			bad6.append("%s sha" % String(p).get_file())
	var out := []
	var gp := []
	for p in reg["protected"]:
		gp.append(ProjectSettings.globalize_path(p))
	var rc := OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "diff", "--quiet", "HEAD", "--"] + gp, out)
	if rc != 0:
		bad6.append("git HEAD から変更あり（rc %d）" % rc)
	_ok(bad6.is_empty(), "K6 保護：_matlib・P6 Kit 原檔・Kit gate.json／manifest %d 檔の sha256＝登記時、git HEAD から未変更%s" % [(reg["protected"] as Dictionary).size(), "" if bad6.is_empty() else " ✗ " + str(bad6)])
