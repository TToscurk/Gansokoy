extends SceneTree
## P10 R6a 材質亮度基準 Pilot gate（回歸 tag ALB）。使用者 2026-10-09 D8：DO NOW, PILOT FIRST。
##   plan＋反向（headless）：Godot --headless --path . --script res://tools/verify_village_v2_albedo_pilot.gd
##   build（headless 可，無 MultiMesh）：… -- --build
##   attach：… -- --attach        （village_v2.tscn 加 root/AlbedoPilotP10，EdgeClosureP10 之後；只加 2 行＋空行）
##   scene：… -- --scene          （實際載入 village_v2：掛載、覆寫只落在 Pilot 建物、enabled 開關可還原、來源檔雜湊不變）
## Gate 內容（plan）：
##   1 來源材質現值＝0.42 灰（Pilot 前提；來源若已被改 → FAIL，不在改過的基準上疊加）
##   2 校正材質只改 albedo_color 且為純灰（不改色相／飽和度／其他屬性）；町家 Kit atlas＝等價 shader（貼圖／粗糙度／發光＝原材質）
##   3 每個校正值的色卡實測 luma 落在目標帶（讀 docs/…/r6a_albedo/albedo_cal.json，線性內插）；Kit 分類：暗＝木帶、亮＝漆喰帶、中＝0.42 不變
##   4 Pilot 建物：≥ 10 棟、兩區都有、全是 machiya_kit 町家（不含 Hero／aux）
##   5 Pilot 建物全在兩區矩形內
##   6 範圍：≤ 25 %（187 棟中），不是全村
const LIB := preload("res://tools/village_v2_albedo_pilot_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const EXT_ID := "p10r6a_albedo_pilot"
const AFTER_NODE := "[node name=\"EdgeClosureP10\" parent=\".\" instance=ExtResource(\"p10r5c_edge_closure\")]"
const SRC_K := 0.42
const MAX_SHARE := 0.25
const RS := preload("res://tools/village_v2_rehab_seal.gd")
const SEAL := "res://data/village_v2_p10r6a_seal.json"   # 使用者 2026-10-09 ROUND 3 FINAL：R6a Kit Material 24 Buildings Pilot＝ART_APPROVED
var fails := 0
var quiet := false


func _ok(c: bool, msg: String) -> bool:
	if not quiet:
		print("[ALB] ", "PASS " if c else "FAIL ", msg)
	if not c:
		fails += 1
	return c


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if RS.refuse_write(args, SEAL, "ALB_ALLOW_REBAKE", "ALB"):
		quit(1)
		return
	if "--seal" in args:
		quit(await RS.new().run(self, SEAL, "ALB", LIB.NODE_NAME, _seal_extra))
		return
	if "--attach" in args:
		quit(_attach())
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	await process_frame   # global_position 需要節點已在樹內
	if "--scene" in args:
		await _scene(v)
		print("[ALB] 結果：%d 項失敗" % fails)
		quit(fails)
		return
	LIB.write_kit_shader()
	var tg := LIB.targets(v)
	var cm := LIB.cal_materials()
	var all_b := v.get_node("Districts").find_children("B_*", "", true, false).size()
	var card := _cards()
	print("[ALB] plan targets=%d／%d 棟、校正材質 %d" % [tg.size(), all_b, (cm[1] as Array).size()])
	_gates(v, tg, cm, all_b, card, LIB.CAL, LIB.KIT_CLASS)
	var asg := LIB.assign(v, tg)
	_palette_gate(v, LIB.PALETTE, asg, card)
	if "--build" in args:
		_build(v, tg)
	else:
		_negatives(v, tg, cm, all_b, card)
		_palette_negatives(v, asg, card)
	print("[ALB] 結果：%d 項失敗" % fails)
	quit(fails)


static func _luma_at(card: Dictionary, mat: String, k: float) -> float:
	var ks: Array = card["ks"]
	var cards: Dictionary = card["cards"]
	for i in ks.size() - 1:
		var k0 := float(ks[i])
		var k1 := float(ks[i + 1])
		if k >= k0 - 1e-6 and k <= k1 + 1e-6:
			var l0 := float(cards["%s@%.2f" % [mat, k0]]["luma"])
			var l1 := float(cards["%s@%.2f" % [mat, k1]]["luma"])
			return lerpf(l0, l1, (k - k0) / maxf(k1 - k0, 1e-6))
	return NAN


func _cards() -> Dictionary:
	var p := ProjectSettings.globalize_path("res://").path_join("../docs/art_review/village_v2_p10_rehab_impl/r6a_albedo/albedo_cal.json").simplify_path()
	if not FileAccess.file_exists(p):
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(p))


func _gates(v: Node3D, tg: Array, cm: Array, all_b: int, card: Dictionary, cal: Dictionary, kc: Dictionary) -> void:
	# 1 來源材質現值
	var bad1 := []
	for p in cal.keys() + [LIB.KIT_SRC]:
		var m := load(p) as StandardMaterial3D
		if m == null or not m.albedo_color.is_equal_approx(Color(SRC_K, SRC_K, SRC_K, 1.0)):
			bad1.append(String(p).get_file())
	_ok(bad1.is_empty(), "來源材質 albedo 現值＝%.2f 灰（Pilot 前提）%s" % [SRC_K, "" if bad1.is_empty() else str(bad1)])
	# 2 只改 albedo、純灰
	var bad2 := []
	var src: PackedStringArray = cm[0]
	var mats: Array = cm[1]
	for i in src.size():
		var a := load(src[i]) as StandardMaterial3D
		if mats[i] is ShaderMaterial:
			# 町家 Kit atlas：等價 shader＋色階分類；貼圖／粗糙度／發光必須＝原材質，shader 原始碼＝lib 常數
			var sm := mats[i] as ShaderMaterial
			var disk := FileAccess.get_file_as_string(LIB.KIT_SHADER)
			if sm.shader == null or sm.shader.resource_path != LIB.KIT_SHADER or disk != LIB.KIT_SHADER_CODE:
				bad2.append("%s shader 不是 lib 產生的 kit_cal" % src[i].get_file())
			if sm.get_shader_parameter("albedo_tex") != a.albedo_texture or sm.get_shader_parameter("emit_tex") != a.emission_texture:
				bad2.append("%s 貼圖不同" % src[i].get_file())
			if not is_equal_approx(float(sm.get_shader_parameter("roughness_v")), a.roughness) or not is_equal_approx(float(sm.get_shader_parameter("emission_energy")), a.emission_energy_multiplier):
				bad2.append("%s 粗糙度／發光不同" % src[i].get_file())
			if a.cull_mode != BaseMaterial3D.CULL_BACK or not disk.contains("cull_back") or not a.vertex_color_use_as_albedo or a.emission_operator != BaseMaterial3D.EMISSION_OP_MULTIPLY:
				bad2.append("%s 原材質旗標與等價 shader 假設不符" % src[i].get_file())
			continue
		var b := mats[i] as StandardMaterial3D
		var c := b.albedo_color
		if not (is_equal_approx(c.r, c.g) and is_equal_approx(c.g, c.b) and is_equal_approx(c.a, 1.0)):
			bad2.append("%s 非純灰 %s" % [src[i].get_file(), c])
		for pr in a.get_property_list():
			var n := String(pr["name"])
			if n in ["albedo_color", "resource_name", "resource_path", "resource_local_to_scene", "resource_scene_unique_id", "script"]:
				continue
			if not (int(pr["usage"]) & PROPERTY_USAGE_STORAGE):
				continue
			if a.get(n) != b.get(n):
				bad2.append("%s.%s" % [src[i].get_file(), n])
	_ok(bad2.is_empty(), "校正材質只改 albedo_color 且純灰（色相／飽和度／其他屬性不動）%s" % ("" if bad2.is_empty() else str(bad2.slice(0, 6))))
	# 3 色卡目標帶
	if card.is_empty():
		_ok(false, "色卡實測 albedo_cal.json 不存在（先跑 probe_village_v2_rehab_albedo_cal.gd）")
	else:
		var bad3 := []
		var rep := []
		for p in cal:
			var mn := String(p).get_file().get_basename()
			var k := float(cal[p])
			var band: Array = LIB.TARGET_LUMA[mn]
			var l := _luma_at(card, mn, k)
			var lr := _luma_at(card, mn + "_roof24", k) if card["cards"].has(mn + "_roof24@0.42") else NAN
			rep.append("%s k=%.2f→%.3f%s" % [mn, k, l, "" if is_nan(lr) else "（屋面 %.3f）" % lr])
			if is_nan(l) or l < float(band[0]) or l > float(band[1]):
				bad3.append("%s %.3f∉%s" % [mn, l, band])
		# 町家 Kit atlas 分類：暗＝木、亮＝漆喰 的色卡帶；中（屋根灰）＝不變 0.42
		for kk in LIB.KIT_CLASS_CARD:
			var mn2: String = LIB.KIT_CLASS_CARD[kk]
			var k2 := float(kc[kk])
			var l2 := _luma_at(card, mn2, k2)
			var band2: Array = LIB.TARGET_LUMA[mn2]
			rep.append("Kit.%s k=%.2f→%.3f" % [kk, k2, l2])
			if is_nan(l2) or l2 < float(band2[0]) or l2 > float(band2[1]):
				bad3.append("Kit.%s %.3f∉%s" % [kk, l2, band2])
		if not is_equal_approx(float(kc["k_mid"]), SRC_K):
			bad3.append("Kit.k_mid %.2f ≠ %.2f（屋根灰不得變）" % [float(kc["k_mid"]), SRC_K])
		_ok(bad3.is_empty(), "色卡實測 luma 在目標帶：%s%s" % [", ".join(rep), "" if bad3.is_empty() else " ✗ " + str(bad3)])
	# 4 建物種類＋兩區
	var bad4 := []
	var per := {}
	for it in tg:
		var b := v.get_node(NodePath(String(it["path"])))
		per[it["area"]] = int(per.get(it["area"], 0)) + 1
		if String(b.get_meta("kit_asset", "")) != "machiya_kit" or String(b.get_meta("kind", "")) != "machiya" or b.get_node_or_null("Kit") == null:
			bad4.append(String(it["path"]).get_file())
	_ok(tg.size() >= 10 and per.size() == LIB.AREAS.size() and bad4.is_empty(), "Pilot 建物 %d 棟（各區 %s）全為 machiya_kit 町家%s" % [tg.size(), per, "" if bad4.is_empty() else " ✗ " + str(bad4)])
	# 5 在區內
	var bad5 := []
	for it in tg:
		var b := v.get_node(NodePath(String(it["path"]))) as Node3D
		var r: Rect2 = LIB.AREAS[it["area"]]
		if not r.has_point(Vector2(b.global_position.x, b.global_position.z)):
			bad5.append(String(it["path"]).get_file())
	_ok(bad5.is_empty(), "Pilot 建物全在兩區矩形內%s" % ("" if bad5.is_empty() else " ✗ " + str(bad5)))
	# 6 範圍
	var share := float(tg.size()) / float(maxi(all_b, 1))
	_ok(share <= MAX_SHARE, "範圍 %.1f %%（≤ %.0f %%，Pilot 不是全村）" % [share * 100.0, MAX_SHARE * 100.0])


## 7 街區調色盤：飽和度 ≤ 0.22、色卡 luma 在材質目標帶、14 m 內鄰棟不同組、每區 ≥ 3 種組合
func _palette_gate(v: Node3D, pal: Dictionary, asg: Array, card: Dictionary) -> void:
	var bad := []
	var rep := []
	for a in pal:
		for mn in ["V2_Plaster", "V2_Wood"]:
			var band: Array = LIB.TARGET_LUMA[mn]
			for c: Color in pal[a][mn]:
				var keq := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				var l := _luma_at(card, mn, keq)
				if c.s > LIB.PALETTE_MAX_SAT:
					bad.append("%s %s 飽和 %.2f" % [a, mn, c.s])
				if is_nan(l) or l < float(band[0]) or l > float(band[1]):
					bad.append("%s %s luma %.3f∉%s" % [a, mn, l, band])
	var clash := 0
	var combos := {}
	for i in asg.size():
		var ai: Dictionary = asg[i]
		var bi := v.get_node(NodePath(String(ai["path"]))) as Node3D
		combos[ai["area"]] = combos.get(ai["area"], {})
		combos[ai["area"]]["%d_%d" % [ai["plaster"], ai["wood"]]] = true
		for j in range(i + 1, asg.size()):
			var aj: Dictionary = asg[j]
			if aj["area"] != ai["area"]:
				continue
			var bj := v.get_node(NodePath(String(aj["path"]))) as Node3D
			if Vector2(bi.global_position.x, bi.global_position.z).distance_to(Vector2(bj.global_position.x, bj.global_position.z)) < LIB.NEIGHBOR_M and ai["plaster"] == aj["plaster"] and ai["wood"] == aj["wood"]:
				clash += 1
	for a in combos:
		rep.append("%s %d 組" % [String(a).substr(0, 1), (combos[a] as Dictionary).size()])
		if (combos[a] as Dictionary).size() < 3:
			bad.append("%s 只有 %d 組" % [a, (combos[a] as Dictionary).size()])
	_ok(bad.is_empty() and clash == 0, "街區調色盤：飽和 ≤ %.2f、亮度在色卡帶、14 m 內鄰棟同組 %d、使用組合 %s%s" % [LIB.PALETTE_MAX_SAT, clash, ", ".join(rep), "" if bad.is_empty() else " ✗ " + str(bad.slice(0, 4))])


func _palette_negatives(v: Node3D, asg: Array, card: Dictionary) -> void:
	var cases := []
	var p1 := LIB.PALETTE.duplicate(true)
	p1["A_gate_main_south"]["V2_Wood"][1] = Color(0.85, 0.45, 0.30)
	cases.append(["N8 調色盤過飽和（朱紅木）", p1, asg])
	var a2 := asg.duplicate(true)
	for x: Dictionary in a2:
		x["plaster"] = 0
		x["wood"] = 0
	cases.append(["N9 全部同一組（複製感）", LIB.PALETTE, a2])
	var neg_fail := 0
	for c in cases:
		var f0 := fails
		quiet = true
		_palette_gate(v, c[1], c[2], card)
		quiet = false
		var tripped := fails > f0
		fails = f0
		print("[ALB]   %s：%s" % [c[0], "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			neg_fail += 1
	_ok(neg_fail == 0, "調色盤反向 %d/%d" % [cases.size() - neg_fail, cases.size()])


func _negatives(v: Node3D, tg: Array, cm: Array, all_b: int, card: Dictionary) -> void:
	print("[ALB] 永久反向（每案必須讓 gate 失敗）")
	var cases := []
	# N1 帶色（飽和度／色相改變）
	var cm1 := [cm[0], (cm[1] as Array).map(func(m): return (m as Material).duplicate())]
	(cm1[1][0] as StandardMaterial3D).albedo_color = Color(0.85, 0.7, 0.55)
	cases.append(["N1 校正材質帶色（等於加飽和度）", tg, cm1, all_b, LIB.CAL])
	# N2 校正值超出目標帶（等幅大提亮）
	var cal2 := LIB.CAL.duplicate()
	for p in cal2:
		cal2[p] = 1.0
	cases.append(["N2 全部材質 k=1.0（等幅提亮）", tg, cm, all_b, cal2])
	# N3 區外建物混入
	var tg3 := tg.duplicate(true)
	for n in v.get_node("Districts").find_children("B_*", "", true, false):
		var p := (n as Node3D).global_position
		if not LIB.AREAS["A_gate_main_south"].has_point(Vector2(p.x, p.z)) and not LIB.AREAS["B_west_alley"].has_point(Vector2(p.x, p.z)):
			tg3.append({"path": String(v.get_path_to(n)), "area": "A_gate_main_south"})
			break
	cases.append(["N3 區外建物混入", tg3, cm, all_b, LIB.CAL])
	# N4 全村套用
	var tg4 := []
	for n in v.get_node("Districts").find_children("B_*", "", true, false):
		tg4.append({"path": String(v.get_path_to(n)), "area": "A_gate_main_south"})
	cases.append(["N4 全村 187 棟（非 Pilot）", tg4, cm, all_b, LIB.CAL])
	# N5 其他屬性被改（粗糙度）
	var cm5 := [cm[0], (cm[1] as Array).map(func(m): return (m as Material).duplicate())]
	(cm5[1][1] as StandardMaterial3D).roughness = 0.3
	cases.append(["N5 校正材質改了粗糙度", tg, cm5, all_b, LIB.CAL])
	# N6 Hero／非 machiya 混入
	var tg6 := tg.duplicate(true)
	var hero := v.get_node_or_null("Landmarks/LANDMARK_SUZUNAAN")
	if hero != null:
		tg6.append({"path": String(v.get_path_to(hero)), "area": "A_gate_main_south"})
	cases.append(["N6 Hero／非町家混入", tg6, cm, all_b, LIB.CAL])
	# N7 町家 Kit 中間帯（屋根灰）也被提亮（r1–r3 的遠景屋根變淺）
	var kc7 := LIB.KIT_CLASS.duplicate(true)
	kc7["k_mid"] = 0.80
	cases.append(["N7 Kit atlas 屋根灰也提亮（遠景 LOD 屋根變淺）", tg, cm, all_b, LIB.CAL, kc7])
	var neg_fail := 0
	for c in cases:
		var f0 := fails
		quiet = true
		_gates(v, c[1], c[2], c[3], card, c[4], c[5] if c.size() > 5 else LIB.KIT_CLASS)
		quiet = false
		var tripped := fails > f0
		fails = f0
		print("[ALB]   %s：%s" % [c[0], "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			neg_fail += 1
	_ok(neg_fail == 0, "反向 %d/%d" % [cases.size() - neg_fail, cases.size()])


func _src_hashes() -> Dictionary:
	var h := {}
	var keys := LIB.CAL.keys()
	keys.sort()
	for p in keys:
		h[p] = FileAccess.get_sha256(p)
	h[LIB.KIT_SRC] = FileAccess.get_sha256(LIB.KIT_SRC)
	h[LIB.KIT_SHADER] = FileAccess.get_sha256(LIB.KIT_SHADER)
	h["res://assets/village_v2/_matlib/matlib.json"] = FileAccess.get_sha256("res://assets/village_v2/_matlib/matlib.json")
	return h


func _build(v: Node3D, tg: Array) -> void:
	if fails > 0:
		_ok(false, "plan gate 未過，不 build")
		return
	var n := LIB.build(v)
	n.set_meta("src_sha256", JSON.stringify(_src_hashes()))
	var ps := PackedScene.new()
	_ok(ps.pack(n) == OK, "pack")
	_ok(ResourceSaver.save(ps, LIB.OUTPUT) == OK, "save %s" % LIB.OUTPUT)
	var rb := (ResourceLoader.load(LIB.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	_ok((rb.get("targets") as PackedStringArray).size() == tg.size() and (rb.get("cal_mats") as Array).size() == LIB.CAL.size() + 1, "回讀：targets %d、校正材質 %d" % [(rb.get("targets") as PackedStringArray).size(), (rb.get("cal_mats") as Array).size()])
	rb.free()
	print("[ALB] build {\"targets\":%d,\"output_sha256\":\"%s\"}" % [tg.size(), FileAccess.get_sha256(LIB.OUTPUT)])


func _scene(v: Node3D) -> void:
	var nodes := v.find_children(LIB.NODE_NAME, "", false, false)
	_ok(nodes.size() == 1, "root/%s 掛載 1 個（實得 %d）" % [LIB.NODE_NAME, nodes.size()])
	if nodes.is_empty():
		return
	var n := nodes[0] as Node3D
	var ix := n.get_index()
	var ec := v.get_node_or_null("EdgeClosureP10")
	_ok(ec != null and ec.get_index() == ix - 1, "順序：EdgeClosureP10 之後（index %d）" % ix)
	for i in 6:
		await process_frame
	var tset := {}
	for p in n.get("targets"):
		tset[String(p)] = true
	var cal_set := {}
	for m in n.get("cal_mats"):
		cal_set[m] = true
	for m in n.get("variant_mats"):
		cal_set[m] = true
	var src_set := {}
	for p in n.get("src_paths"):
		src_set[String(p)] = true
	# 覆寫只落在 Pilot 建物、且 Pilot 建物內所有來源材質表面都已覆寫
	var in_ok := 0
	var in_miss := 0
	var out_bad := 0
	var w7 := _w7_batch_paths()
	for b in v.get_node("Districts").find_children("B_*", "", true, false):
		var bp := String(v.get_path_to(b))
		var is_t := tset.has(bp)
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for si in m.mesh.get_surface_count():
				var sm := m.mesh.surface_get_material(si)
				var ov := m.get_surface_override_material(si)
				var has_cal := ov != null and cal_set.has(ov)
				if is_t and sm != null and src_set.has(sm.resource_path):
					if has_cal:
						in_ok += 1
					else:
						in_miss += 1
				elif not is_t and has_cal and not w7.has(bp):
					out_bad += 1
	_ok(in_ok > 0 and in_miss == 0, "Pilot 建物的來源材質表面全部覆寫（%d 面、漏 %d）" % [in_ok, in_miss])
	_ok(out_bad == 0, "Pilot 外建物沒有覆寫（%d）" % out_bad)
	_ok(int(n.get("applied_surfaces")) == in_ok, "applied_surfaces＝%d" % int(n.get("applied_surfaces")))
	# 開關還原
	n.set("enabled", false)
	var left := 0
	for b in v.get_node("Districts").find_children("B_*", "", true, false):
		if w7.has(String(v.get_path_to(b))):
			continue   # P13 W7 第一批は別 overlay（AlbedoBatch1P13）の責任範囲：Pilot の開閉では還原されない（W7 gate が独立に開閉を検査）
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for si in m.mesh.get_surface_count():
				var ov := m.get_surface_override_material(si)
				if ov != null and cal_set.has(ov):
					left += 1
	_ok(left == 0, "enabled=false → 覆寫全部還原（殘留 %d%s）" % [left, "" if w7.is_empty() else "・P13 W7 第一批 %d 棟は別 overlay のため除外" % w7.size()])
	n.set("enabled", true)
	_ok(int(n.get("applied_surfaces")) == in_ok, "enabled=true → 重新套用 %d 面" % int(n.get("applied_surfaces")))
	# 來源檔不變
	var rec: Dictionary = JSON.parse_string(String(n.get_meta("src_sha256", "{}")))
	var now := _src_hashes()
	var bad := []
	for p in now:
		if String(rec.get(p, "")) != String(now[p]):
			bad.append(String(p).get_file())
	_ok(not rec.is_empty() and bad.is_empty(), "_matlib／machiya_kit 來源材質與 matlib.json 雜湊＝build 時（%d 檔）%s" % [now.size(), "" if bad.is_empty() else " ✗ " + str(bad)])


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(LIB.OUTPUT):
		push_error("找不到 %s（先 --build）" % LIB.OUTPUT)
		return 1
	var line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [LIB.NODE_NAME, EXT_ID]
	if txt.contains(line):
		print("[ALB] attach：已掛（不重複、不寫場景）")
		return 0
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray(Array(lines))
	var at := out.find(AFTER_NODE)
	if at < 0:
		push_error("找不到 root/EdgeClosureP10（先掛 R5c）")
		return 1
	if at + 1 < out.size() and out[at + 1].strip_edges() != "":
		push_error("EdgeClosureP10 節點後面不是空行，拒絕文字插入")
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
	print("[ALB] attach：加 root/%s（EdgeClosureP10 之後）→ %s（+%d 行）" % [LIB.NODE_NAME, SCENE, out.size() - lines.size()])
	return 0


## --seal 固有：AlbedoPilotP10 の材質はすべて登記変体（machiya_kit/cal/kit_material_variants.json）、Pilot 24 棟、適用面 > 0
func _seal_extra(v: Node3D) -> Array:
	var n := v.get_node(LIB.NODE_NAME)
	var reg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/kit_cal_p10/kit_material_variants.json"))
	var files := {}
	for e in reg["variants"]:
		files[String(e["file"])] = true
	var bad := []
	for m: Material in (n.get("cal_mats") as Array) + (n.get("variant_mats") as Array):
		if not files.has(m.resource_path):
			bad.append(m.resource_name)
	var tg: PackedStringArray = n.get("targets")
	return [[bad.is_empty(), "AlbedoPilotP10 の材質 %d 個すべて登記変体（未登記 %s）" % [(n.get("cal_mats") as Array).size() + (n.get("variant_mats") as Array).size(), str(bad.slice(0, 3))]],
		[tg.size() == 24 and int(n.get("applied_surfaces")) > 0, "Pilot %d 棟・適用面 %d" % [tg.size(), int(n.get("applied_surfaces"))]]]


## P13 W7 TASK 5（使用者 2026-10-14・R6a limited reseal）：第一批 50 棟の名簿（data/village_v2_p13w7_batch1.json）。ファイルの sha256 が封存 frozen の値と
## 一致するときだけ合法（一致しない／封存が無い＝空）。合法な変体は R6a の登記 18 変体だけで、この名簿は「どの建物が持ってよいか」を足すだけ。
func _w7_batch_paths() -> Dictionary:
	var out := {}
	var man := "res://data/village_v2_p13w7_batch1.json"
	if not FileAccess.file_exists(man) or not FileAccess.file_exists(SEAL):
		return out
	var sj: Variant = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	if not (sj is Dictionary) or String((sj as Dictionary).get("status", "")) != "ART_APPROVED":
		return out
	if String(((sj as Dictionary).get("frozen", {}) as Dictionary).get("godot/data/village_v2_p13w7_batch1.json", "")) != FileAccess.get_sha256(man):
		return out
	var mj: Variant = JSON.parse_string(FileAccess.get_file_as_string(man))
	if mj is Dictionary:
		for wb: Dictionary in (mj as Dictionary).get("buildings", []):
			out[String(wb["path"])] = true
	return out
