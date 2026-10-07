extends SceneTree
## 人間之里 V2 P9 R4-3：寺子屋周邊 規劃 gate＋烘焙＋掛載＋場景級驗證＋審圖鏡位。
##   規劃＋gate（唯讀）：Godot --headless --path godot --script res://tools/verify_village_v2_school_yard.gd
##   反向：             ... -- --neg=float|door|facade|conifer|clip|clutter（各自瞄準一項，必須讓那一項 FAIL）；-- --negatives 一次跑完
##   烘焙 overlay：     Godot --path godot --resolution 640x360 --script ... -- --build
##   掛進場景：         ... --headless ... -- --attach（village_v2.tscn 文字層級在 Vegetation/ShrineGroveP9 後加 SchoolYardP9；
##                       先確認沒有 Godot 編輯器開著；**不重生** village_v2.tscn——若有流程重生它，重生後須依序重新 attach
##                       ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9 → SchoolYardP9）
##   場景驗證：         ... --headless ... -- --scene（掛載順序、射線接地、碰撞 vs 寺子屋／建物／其他、入口＋前庭＋側院膠囊實走、視線射線）
##   審圖鏡位：         ... --headless ... -- --shots（寫 tools/shots/village_v2_p9r43_school_{before,after}.json）
##   封存：             ... --headless ... -- --seal（data/village_v2_p9r43_seal.json 雜湊＋掛載順序＋竄改反向；P9 R4-3 ART_APPROVED 2026-10-02）
## 每項一行 [SCHOOL] PASS/FAIL；INFO 不計失敗；結尾 quit(失敗項數)。

const SY := preload("res://tools/village_v2_school_yard_lib.gd")
const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const REPORT := "res://data/village_v2_p9r43_school.json"
const SEAL := "res://data/village_v2_p9r43_seal.json"
const EYE := 1.7

var fails := 0
var neg := ""
var failed_labels: Array = []
var quiet := false


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[SCHOOL] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(label: String) -> void:
	if not quiet:
		print("[SCHOOL] INFO " + label)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with("--neg="):
			neg = a.trim_prefix("--neg=")
	if "--attach" in args:
		quit(_attach())
		return
	if "--seal" in args:
		quit(_seal())
		return
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	if "--scene" in args:
		root.add_child(v)
		await _scene(v)
		print("[SCHOOL] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var old := v.get_node_or_null("Vegetation/" + SY.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	if "--shots" in args:
		quit(_shots(v))
		return
	root.add_child(v)
	await physics_frame
	await physics_frame
	var P: Dictionary = SY.plan(v, L)
	info("規劃 %d 件（%d ms）" % [(P["items"] as Array).size(), P["ms"]])
	if "--negatives" in args:
		var target := {"float": "接地", "door": "主入口", "facade": "視線", "conifer": "植被語彙", "clip": "不穿建築", "clutter": "留白"}
		var bad := 0
		for nm: String in target:
			var cp: Array = []
			for it: Dictionary in P["items"]:
				cp.append(it.duplicate(true))
			var P2 := P.duplicate()
			P2["items"] = cp
			neg = nm
			fails = 0
			failed_labels.clear()
			quiet = true
			_inject(P2)
			_checks(P2)
			quiet = false
			var hit := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(target[nm])))
			print("[SCHOOL] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d）" % ["PASS" if hit else "FAIL", nm, target[nm], failed_labels.size()])
			if not hit:
				bad += 1
		print("[SCHOOL] 結果：%d 項失敗（negatives）" % bad)
		quit(bad)
		return
	if neg != "":
		_inject(P)
	var rep := _checks(P)
	if neg != "":
		print("[SCHOOL] negative=%s 失敗 %d 項" % [neg, fails])
		quit(fails)
		return
	if "--build" in args and fails == 0:
		var r := SY.bake(P)
		SY.own(r, r)
		var ps := PackedScene.new()
		check("pack overlay", ps.pack(r) == OK)
		var e := ResourceSaver.save(ps, SY.OUTPUT, ResourceSaver.FLAG_COMPRESS)
		check("save %s" % SY.OUTPUT, e == OK)
		rep["overlay"] = {"path": SY.OUTPUT, "mb": FileAccess.get_file_as_bytes(SY.OUTPUT).size() / 1048576.0,
			"items": r.get_meta("items"), "shapes": r.get_meta("shapes")}
		info("overlay %.2f MB、%d 件、構件碰撞 %d" % [rep["overlay"]["mb"], rep["overlay"]["items"], rep["overlay"]["shapes"]])
		r.free()
		var f := FileAccess.open(REPORT, FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, "  ", false))
		f.close()
	print("[SCHOOL] 結果：%d 項失敗" % fails)
	quit(fails)


func _inject(P: Dictionary) -> void:
	var items: Array = P["items"]
	var S: RLib.TriSampler = P["S"]
	match neg:
		"float":
			for it: Dictionary in items:
				if String(it["id"]) == "sk_bench":
					it["y"] = float(it["y"]) + 0.35
		"door":
			items.append(SY.item(S, "mesh", "sk_box", Vector2(199.0, 24.1), 0.0, 1.0, "rest"))
		"facade":
			items.append(SY.item(S, "tree", "keyaki_a", Vector2(203.5, 21.0), 0.0, 0.7, "shade_tree", {"preset": "mature"}))
		"conifer":
			items.append(SY.item(S, "tree", "sugi_a", Vector2(172.0, 36.0), 0.0, 0.8, "back_tree", {"preset": "mature"}))
		"clip":
			items.append(SY.item(S, "mesh", "sk_tensui", Vector2(186.0, 20.0), 0.0, 1.0, "back"))
		"clutter":
			for k in 8:
				items.append(SY.item(S, "mesh", "sk_box", Vector2(197.5 + (k % 4) * 1.4, 18.6 + (k / 4) * 11.6), 0.0, 1.0, "rest"))


func _checks(P: Dictionary) -> Dictionary:
	var S: RLib.TriSampler = P["S"]
	var M: Dictionary = P["M"]
	var items: Array = P["items"]
	var rep := {"date": Time.get_datetime_string_from_system(), "items": items.size()}
	var trees: Array = items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "tree")
	var canopy: Array = trees.filter(func(it: Dictionary) -> bool: return not (String(it["id"]) in SY.UNDER_IDS))
	var props: Array = items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "mesh")
	# ── 1 接地：origin ≤ 環最低地面＋0.005、埋 ≤ 0.45；踏石上の草履＝物理表面 ±0.02
	var fl := 0
	var dp := 0
	var worst := 0.0
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		var y := float(it["y"])
		if it.get("on_step", false):
			continue
		if String(it["id"]) == "sk_ishikeri":
			if absf(y - S.h(p.x, p.y) - 0.006) > 0.02:
				fl += 1
			continue
		var r := 0.25
		var sc: float = (it["sc"] as Vector3).x
		if String(it["kind"]) == "tree" and not (String(it["id"]) in SY.UNDER_IDS):
			r = maxf(SG.trunk_r(String(it["id"]), sc, M) * 0.7, 0.12)
		elif SY.PROP_BOX.has(String(it["id"])):
			r = minf(float(SY.PROP_BOX[it["id"]][0]), float(SY.PROP_BOX[it["id"]][1]))
		var lo := GL.ground(S, p, r)
		if y > lo + 0.005:
			fl += 1
			worst = maxf(worst, y - lo)
		if S.h(p.x, p.y) - y > 0.45:
			dp += 1
	check("接地：%d 件 origin ≤ 環 8 點最低地面、埋 ≤ 0.45 m（踏石上草履另驗）：浮 %d（最大 %.2f m）、過深 %d" % [items.size(), fl, worst, dp],
		fl == 0 and dp == 0)
	# ── 2 不穿建築：樹幹／構件外框 vs 寺子屋台基（＋0.15）、踏石（草履除外）、Hero 前庭小物 0.5 m、花壇、鄰棟
	var clip: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		var p: Vector2 = it["p"]
		var pts := PackedVector2Array([p])
		if String(it["kind"]) == "mesh":
			pts = SY.prop_corners(it)
			pts.append(p)
		var r := 0.0
		if String(it["kind"]) == "tree" and not (id in SY.UNDER_IDS):
			r = SG.trunk_r(id, (it["sc"] as Vector3).x, M) + 0.3
		for q in pts:
			var bad := SY.BODY.grow(0.15 + r).has_point(q)
			if not it.get("on_step", false):
				bad = bad or SY.STEP.grow(0.05 + r).has_point(q)
			for b: Rect2 in SY.BEDS:
				bad = bad or b.grow(0.05).has_point(q)
			for hp: Vector2 in SY.HERO_PROPS:
				bad = bad or q.distance_to(hp) < 0.5 + r
			for b: Rect2 in P["bld"]:
				bad = bad or (b as Rect2).grow(0.1 + r).has_point(q)
			if bad and id != "gk_amaochi":
				clip.append("%s@(%.1f,%.1f)" % [id, p.x, p.y])
				break
	check("不穿建築：樹幹／構件 vs 寺子屋台基・踏石・前庭 Hero 小物・花壇・鄰棟：違規 %d %s" % [clip.size(), ", ".join(clip.slice(0, 4))],
		clip.is_empty())
	# ── 3 主入口淨空：西巷 → 踏石 動線 半寬 ENTRY_HW 內無構件／植栽（地面線・草履除外）；入口前 3 m 扇形無高物
	var block: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if id in ["sk_ishikeri", "sk_zori"]:
			continue
		var pts := SY.prop_corners(it) if String(it["kind"]) == "mesh" else PackedVector2Array([it["p"]])
		var cr := 0.0
		if String(it["kind"]) == "tree":
			cr = float(M[id]["crown_w"]) * 0.5 * (it["sc"] as Vector3).x * (0.6 if id in SY.UNDER_IDS else 0.0)
		for q in pts:
			if GL.line_d(SY.ENTRY, q).x < SY.ENTRY_HW + cr or q.distance_to(SY.DOOR + Vector2(1.6, 0.0)) < 1.7 + cr:
				block.append("%s@(%.1f,%.1f)" % [id, (it["p"] as Vector2).x, (it["p"] as Vector2).y])
				break
	check("主入口：西巷→踏石 動線半寬 %.1f m＋玄關前 1.7 m 內障礙 %d %s" % [SY.ENTRY_HW, block.size(), ", ".join(block.slice(0, 3))],
		block.is_empty())
	# ── 4 視線：西巷側 4 機位（1.7 m）→ 正面 7 點（向拝・額・兩端・屋根）不被新樹冠／樹幹擋
	var blk: Array = []
	for it: Dictionary in canopy:
		var cyl := SG.crown_cyl(it, M)
		var sc: float = (it["sc"] as Vector3).x
		var tcyl := [it["p"], SG.trunk_r(String(it["id"]), sc, M) + 0.05, float(it["y"]), float(it["y"]) + float(M[it["id"]]["height"]) * sc * 0.4]
		for c2: Vector2 in SY.SIGHT_CAMS:
			var c := Vector3(c2.x, S.h(c2.x, c2.y) + EYE, c2.y)
			for tg: Vector3 in SY.FACADE:
				if SG.seg_hits(c, tg, cyl) or SG.seg_hits(c, tg, tcyl):
					blk.append("%s@(%.1f,%.1f)" % [it["id"], (it["p"] as Vector2).x, (it["p"] as Vector2).y])
	check("視線：西巷 %d 機位 → 寺子屋正面 %d 點被新樹擋 %d %s" % [SY.SIGHT_CAMS.size(), SY.FACADE.size(), blk.size(), ", ".join(blk.slice(0, 3))],
		blk.is_empty())
	# ── 5 留白：前庭活動場 YARD 內 構件外框＋林下樹冠＋樹幹 覆蓋率 ≤ YARD_MAX（地面線・草履除外）
	var yard := PackedVector2Array(SY.YARD)
	var occ := 0
	var tot := 0
	var bb := Rect2(yard[0], Vector2.ZERO)
	for q in yard:
		bb = bb.expand(q)
	var x := bb.position.x
	while x < bb.end.x:
		var z := bb.position.y
		while z < bb.end.y:
			var q := Vector2(x + 0.25, z + 0.25)
			if Geometry2D.is_point_in_polygon(q, yard):
				tot += 1
				for it: Dictionary in items:
					var id := String(it["id"])
					if id in ["sk_ishikeri", "sk_zori", "sk_temari"]:
						continue
					var hit := false
					if String(it["kind"]) == "mesh":
						hit = Geometry2D.is_point_in_polygon(q, SY.prop_corners(it))
					elif id in SY.UNDER_IDS:
						hit = q.distance_to(it["p"]) < float(M[id]["crown_w"]) * 0.45 * (it["sc"] as Vector3).x
					else:
						hit = q.distance_to(it["p"]) < SG.trunk_r(id, (it["sc"] as Vector3).x, M) + 0.2
					if hit:
						occ += 1
						break
			z += 0.5
		x += 0.5
	var yr := float(occ) / maxf(tot, 1)
	var n_props := props.filter(func(it: Dictionary) -> bool: return String(it["id"]) != "gk_amaochi").size()
	var in_yard := props.filter(func(it: Dictionary) -> bool: return String(it["id"]) != "gk_amaochi" and Geometry2D.is_point_in_polygon(it["p"], yard)).size()
	check("留白：前庭活動場 %.0f m² 覆蓋 %.1f %%（≤ %.0f %%）；生活小物 %d 件（≤ 20）、其中前庭內 %d（≤ 4，不成市集）" % [tot * 0.25, yr * 100,
		SY.YARD_MAX * 100, n_props, in_yard], yr <= SY.YARD_MAX and n_props <= 20 and in_yard <= 4)
	rep["yard_cover"] = yr
	# ── 6 植被語彙：高木全為落葉闊葉／楓／櫻／幼樹（無杉檜）、櫻 ≤ 1、楓 ≥ 1、日陰主木 ≥ 1
	var bad_ids: Array = canopy.filter(func(it: Dictionary) -> bool: return not (String(it["id"]) in SY.CANOPY_OK)).map(func(it: Dictionary) -> String: return String(it["id"]))
	var n_sak := canopy.filter(func(it: Dictionary) -> bool: return String(it["id"]).begins_with("sakura")).size()
	var n_mom := canopy.filter(func(it: Dictionary) -> bool: return String(it["id"]).begins_with("momiji")).size()
	var n_shade := canopy.filter(func(it: Dictionary) -> bool: return String(it["tag"]) == "shade_tree").size()
	check("植被語彙：高木 %d（非落葉闊葉系 %d %s）、櫻 %d（≤ 1）、楓 %d（≥ 1）、日陰主木 %d（≥ 1）" % [canopy.size(), bad_ids.size(),
		str(bad_ids), n_sak, n_mom, n_shade], bad_ids.is_empty() and n_sak <= 1 and n_mom >= 1 and n_shade >= 1)
	# ── 7 元素
	var have := {}
	for it: Dictionary in items:
		var id := String(it["id"])
		have[id] = int(have.get(id, 0)) + 1
	var need := ["sk_getabako", "sk_zori", "sk_fuda", "sk_toban", "sk_bench", "sk_box", "sk_teoke", "sk_hanshi", "sk_temari", "sk_hoop",
		"sk_ishikeri", "sk_tensui", "sk_woodpile", "gk_amaochi"]
	var miss: Array = need.filter(func(k: String) -> bool: return not have.has(k))
	check("元素：生活小物 %d 種齊備（缺 %s）、草履 %d" % [need.size() - miss.size(), str(miss), int(have.get("sk_zori", 0))],
		miss.is_empty() and int(have.get("sk_zori", 0)) >= 2)
	rep["elements"] = have
	info("植栽 %d（高木 %d、林下 %d）、構件 %d（雨落ち縁石 %d）" % [trees.size(), canopy.size(), trees.size() - canopy.size(), props.size(),
		int(have.get("gk_amaochi", 0))])
	return rep


# ─────────────────────────── 掛載 ───────────────────────────

func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if txt.is_empty():
		push_error("讀不到 " + SCENE)
		return 1
	if txt.contains("gen/school_yard_p9.scn"):
		push_error("已經掛過 SchoolYardP9")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var done := false
	var i := 0
	while i < lines.size():
		var ln := lines[i]
		out.append(ln)
		if not done and ln.begins_with("[node name=\"ShrineGroveP9\" parent=\"Vegetation\""):
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"SchoolYardP9\" parent=\"Vegetation\" instance=ExtResource(\"p9r43_school_yard\")]")
			out.append("")
			done = true
			continue
		i += 1
	if not done:
		push_error("找不到 Vegetation/ShrineGroveP9（順序須為 ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9 → SchoolYardP9）")
		return 1
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p9r43_school_yard\"]" % SY.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[SCHOOL] attach：加 Vegetation/SchoolYardP9 → %s" % SCENE)
	return 0


# ─────────────────────────── 場景級驗證（已掛載） ───────────────────────────

func _scene(v: Node3D) -> void:
	var go := v.get_node_or_null("Vegetation/" + SY.NODE_NAME) as Node3D
	var names: Array = []
	for c in v.get_node("Vegetation").get_children():
		names.append(String(c.name))
	var order := ["ForestP9", "BambooP9", "HiedaGardenP9", "ShrineGroveP9", "SchoolYardP9"]
	var ok := true
	for k in order.size() - 1:
		if not (order[k] in names and order[k + 1] in names) or names.find(order[k]) > names.find(order[k + 1]):
			ok = false
	check("場景已掛 Vegetation/%s，順序 %s：%s" % [SY.NODE_NAME, " → ".join(order), str(names)], go != null and ok)
	if go == null:
		return
	for i in 4:
		await physics_frame
	var space := v.get_world_3d().direct_space_state
	var terrain := v.get_node("Collision/TerrainCollision") as StaticBody3D
	var S := RLib.terrain_sampler(v)
	# 1 射線接地：只認地形（踏石上的草履：第一個命中＝寺子屋踏石，離 ≤ 0.03）
	var fl := 0
	var n := 0
	var n_all := 0
	var worst := 0.0
	for grp: String in ["Trees", "Under", "Props"]:
		for node in go.get_node(grp).get_children():
			n_all += 1
			var p := (node as Node3D).global_position
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 3, 0), p - Vector3(0, 3, 0))
			var on_step := bool(node.get_meta("on_step", false)) and SY.STEP.has_point(Vector2(p.x, p.z))
			var ex: Array[RID] = []
			var y_hit := NAN
			for k in 8:
				q.exclude = ex
				var r := space.intersect_ray(q)
				if r.is_empty():
					break
				var col := r["collider"] as Node
				if col == terrain or (on_step and String(v.get_path_to(col)).begins_with("Landmarks/LANDMARK_TERAKOYA")):
					y_hit = float((r["position"] as Vector3).y)
					break
				ex.append(r["rid"])
			if is_nan(y_hit):
				continue
			n += 1
			var gap := p.y - y_hit
			worst = maxf(worst, gap)
			if gap > 0.06:
				fl += 1
	check("場景接地（%d／%d 件 origin 向下射線只認地形；踏石上草履認踏石）：浮 > 0.06 m %d（最大 %.3f）" % [n, n_all, fl, worst],
		fl == 0 and n == n_all)
	# 2 碰撞：本 overlay 碰撞（構件箱、樹幹）vs 寺子屋／建物／其他植被（排除地形與本 overlay）
	var hits := {}
	var own: Array[RID] = [terrain.get_rid()]
	for sb in go.find_children("*", "StaticBody3D", true, false):
		own.append((sb as StaticBody3D).get_rid())
	for sb in go.find_children("*", "StaticBody3D", true, false):
		for cs in sb.get_children():
			if not (cs is CollisionShape3D):
				continue
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = (cs as CollisionShape3D).shape
			qp.transform = (cs as CollisionShape3D).global_transform
			qp.exclude = own
			for r: Dictionary in space.intersect_shape(qp, 4):
				var key := String(v.get_path_to(r["collider"] as Node))
				hits[key.get_slice("/", 0) + "/" + key.get_slice("/", 1) + "/" + key.get_slice("/", 2) + " ← " + String(cs.name)] = 1
	check("碰撞：構件箱／樹幹 vs 寺子屋本體・Hero 小物／鄰棟／其他植被 接觸 %s" % (str(hits.keys().slice(0, 5)) if hits else "0"), hits.is_empty())
	# 3 實走：西巷 → 踏石前、前庭橫走、南側院 → 裏、北側通路（膠囊 r 0.3 h 1.7；只排除地形）
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var blocked: Array = []
	var probes := 0
	var routes: Array = [[Vector2(208.4, 24.3), Vector2(196.0, 24.0)], [Vector2(197.0, 18.0), Vector2(202.0, 24.0), Vector2(197.6, 31.0)],
		[Vector2(197.2, 33.2), Vector2(195.6, 35.0), Vector2(192.6, 37.6), Vector2(186.0, 38.0), Vector2(180.0, 36.4), Vector2(179.0, 30.0)],
		[Vector2(197.0, 12.5), Vector2(188.0, 11.2), Vector2(180.0, 12.0)]]
	for route: Array in routes:
		for e: Array in GL.resample(route, 0.5):
			var p: Vector2 = e[0]
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cap
			qp.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, S.h(p.x, p.y) + 0.3 + 0.85 + 0.12, p.y))
			qp.exclude = [terrain.get_rid()]
			probes += 1
			var r := space.intersect_shape(qp, 1)
			if not r.is_empty():
				blocked.append("(%.1f,%.1f) %s" % [p.x, p.y, String(v.get_path_to(r[0]["collider"] as Node))])
	check("實走：入口＋前庭＋南側院＋北側通路 膠囊 %d 點被擋 %d %s" % [probes, blocked.size(), ", ".join(blocked.slice(0, 3))], blocked.is_empty())
	info("SchoolYardP9：%s 件、MeshInstance %d、構件碰撞 %s" % [go.get_meta("items", "?"),
		go.find_children("*", "MeshInstance3D", true, false).size(), go.get_meta("shapes", "?")])


# ─────────────────────────── 審圖鏡位 ───────────────────────────

const HIDE := ["Debug", "Portals", "QuestAnchors", "Districts/LandmarkParcelLines", "Districts/AuxParcelLines",
	"Districts/Market/ParcelLines", "Districts/MixedCommercial/ParcelLines", "Districts/ResidentialWest/ParcelLines",
	"Districts/ResidentialNE/ParcelLines", "Districts/SouthGate/ParcelLines"]
## [名稱, 相機 xz, 眼高, 看向 xz, 看向高（相對地面）]
const SHOTS := [
	["p9r43_front", Vector2(214.0, 24.4), EYE, Vector2(191.0, 24.0), 3.4],
	["p9r43_front_l", Vector2(208.6, 34.6), EYE, Vector2(192.0, 21.0), 2.6],
	["p9r43_entry_near", Vector2(198.2, 22.6), EYE, Vector2(194.0, 25.8), 0.7],
	["p9r43_bench", Vector2(205.4, 15.6), EYE, Vector2(201.2, 9.8), 1.2],
	["p9r43_side_s", Vector2(201.4, 41.6), EYE, Vector2(186.0, 33.0), 1.6],
	["p9r43_side_n", Vector2(206.4, 6.4), EYE, Vector2(188.0, 13.6), 1.6],
	["p9r43_back", Vector2(170.2, 38.6), EYE, Vector2(182.0, 22.0), 1.6],
	["p9r43_back_n", Vector2(175.4, 12.2), EYE, Vector2(182.2, 21.0), 1.2],
	["p9r43_hanshi", Vector2(185.6, 40.2), EYE, Vector2(188.2, 35.6), 1.05],
]
const HIGH := [
	["p9r43_high", Vector3(222.0, 22.0, 46.0), Vector3(190.0, 2.0, 22.0)],
	["p9r43_high_nw", Vector3(160.0, 26.0, -6.0), Vector3(190.0, 1.0, 26.0)],
	["p9r43_top", Vector3(189.0, 70.0, 25.0), Vector3(189.0, 0.0, 25.5)],
]


func _shots(v: Node3D) -> int:
	var S := RLib.terrain_sampler(v)
	var before: Array = []
	var after: Array = []
	for s: Array in SHOTS:
		var c: Vector2 = s[1]
		var l: Vector2 = s[3]
		var e := {"name": String(s[0]), "cam": [c.x, snappedf(S.h(c.x, c.y) + float(s[2]), 0.01), c.y],
			"look": [l.x, snappedf(S.h(l.x, l.y) + float(s[4]), 0.01), l.y], "hud": false, "time": 10, "hide": HIDE}
		var eb := e.duplicate(true)
		eb["hide"] = HIDE + ["Vegetation/" + SY.NODE_NAME]
		before.append(eb)
		after.append(e)
	for s: Array in HIGH:
		var c: Vector3 = s[1]
		var l: Vector3 = s[2]
		var e := {"name": String(s[0]), "cam": [c.x, c.y, c.z], "look": [l.x, l.y, l.z], "hud": false, "time": 10, "hide": HIDE}
		var eb := e.duplicate(true)
		eb["hide"] = HIDE + ["Vegetation/" + SY.NODE_NAME]
		before.append(eb)
		after.append(e)
	for pair: Array in [["res://tools/shots/village_v2_p9r43_school_before.json", before], ["res://tools/shots/village_v2_p9r43_school_after.json", after]]:
		var f := FileAccess.open(String(pair[0]), FileAccess.WRITE)
		f.store_string(JSON.stringify(pair[1], " ", false))
		f.close()
		print("[SCHOOL] 寫入 %s（%d 張）" % [pair[0], (pair[1] as Array).size()])
	v.free()
	return 0


# ─────────────────────────── 封存（--seal，P9 R4-3 寺子屋周邊 ART_APPROVED 2026-10-02） ───────────────────────────

func _seal_mismatch(seal: Dictionary) -> PackedStringArray:
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	var docs := repo + "docs/art_review/village_v2_p9_vegetation/"
	var bad := PackedStringArray()
	for grp: String in ["frozen", "art_review_images", "evidence"]:
		var d: Dictionary = seal[grp]
		for k: String in d:
			var path: String = (repo + k) if grp == "frozen" else (docs + k)
			if not FileAccess.file_exists(path):
				bad.append("%s 不存在" % k)
			elif FileAccess.get_sha256(path) != String(d[k]):
				bad.append("%s 雜湊變了" % k)
	return bad


func _seal() -> int:
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	var bad := _seal_mismatch(seal)
	var n: int = seal["frozen"].size() + seal["art_review_images"].size() + seal["evidence"].size()
	check("P9 R4-3 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 總表 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var txt := FileAccess.get_file_as_string(SCENE)
	var idx: Array = []
	for nm: String in ["ForestP9", "BambooP9", "HiedaGardenP9", "ShrineGroveP9", "SchoolYardP9"]:
		idx.append(txt.find("[node name=\"%s\" parent=\"Vegetation\"" % nm))
	var ord_ok: bool = int(idx[0]) >= 0
	for k in range(1, idx.size()):
		ord_ok = ord_ok and int(idx[k]) > int(idx[k - 1])
	check("village_v2.tscn 掛載 Vegetation/ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9 → SchoolYardP9（%s）" % SY.OUTPUT,
		ord_ok and txt.contains(SY.OUTPUT))
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[SCHOOL] 結果：%d 項失敗（seal）" % fails)
	return fails
