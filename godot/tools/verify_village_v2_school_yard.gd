extends SceneTree
## 人間之里 V2 P9 R4-3：寺子屋周邊 規劃 gate＋烘焙＋掛載＋場景級驗證＋審圖鏡位。
##   規劃＋gate（唯讀）：Godot --headless --path godot --script res://tools/verify_village_v2_school_yard.gd
##   反向：             ... -- --neg=float|door|facade|conifer|clip|clutter（各自瞄準一項，必須讓那一項 FAIL）；-- --negatives 一次跑完
##   烘焙 overlay：     Godot --path godot --resolution 640x360 --script ... -- --build
##   掛進場景：         ... --headless ... -- --attach（village_v2.tscn 文字層級在 Vegetation/ShrineGroveP9 後加 SchoolYardP9；
##                       先確認沒有 Godot 編輯器開著；**不重生** village_v2.tscn——若有流程重生它，重生後須依序重新 attach
##                       ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9 → SchoolYardP9）
##   場景驗證：         ... --headless ... -- --scene（掛載順序、射線接地、碰撞 vs 寺子屋／建物／其他、入口＋前庭＋側院膠囊實走〔P11 R1：靜的障害＋NPC 動的規則〕、視線射線）
##   場景級反向：       ... --headless ... -- --scene-negatives（P11 R1：靜的箱／NPC 待機点／巡回端／沿って歩く → 各案 FAIL）
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
	if "--scene-negatives" in args:
		root.add_child(v)
		quit(await _scene_negatives(v))
		return
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


# ─────────────────────── 實走（P11 R1 limited verifier correction 2026-10-10） ───────────────────────
## 旧版：ルート上の膠囊が地形以外の何かに当たれば被擋。P10 R3d で寺子屋に巡回 NPC（C20、AnimatableBody3D）が入り、
##   読み込み直後の巡回位置（start_u 0.69）が入口ルート（西巷 → 踏石前）の横切り点 (205.2, 24.2) にあったため 2 点が被擋になった
##   （docs/art_review/village_v2_p11/r1/diag/known3.json：NPC を除くと被擋 0、C20 の巡回両端はルートから 1.35 m、横切り 1 箇所）。
## 修正：Population の NPC（動く体）は静的被擋の対象から外し、代わりに NPC の動的規則を追加（旧版になかった検査）：
##   ① 待機点（idle の位置、巡回の両端＝wait する所）とルートの距離 ≥ 膠囊 0.3＋NPC 半径＋0.3
##   ② 巡回がルートの帯（0.3＋NPC 半径）の中を歩く長さ ≤ ALONG_MAX（横切りは可、ルートに沿って歩き続けるのは不可）
##   ③ 横切り点の静的な通行幅（ルートの法線方向、NPC を除く）≥ 2×(0.3＋NPC 半径)＋0.3（NPC が立ち止まっても横を抜けられる）
##   静的障害（構件・建物・樹幹など）は旧版どおり 1 点でも当たれば FAIL。
const ALONG_MAX := 1.5
const ROUTES := [[Vector2(208.4, 24.3), Vector2(196.0, 24.0)], [Vector2(197.0, 18.0), Vector2(202.0, 24.0), Vector2(197.6, 31.0)],
	[Vector2(197.2, 33.2), Vector2(195.6, 35.0), Vector2(192.6, 37.6), Vector2(186.0, 38.0), Vector2(180.0, 36.4), Vector2(179.0, 30.0)],
	[Vector2(197.0, 12.5), Vector2(188.0, 11.2), Vector2(180.0, 12.0)]]

func _npc_actors(v: Node3D) -> Array:
	var out: Array = []
	var pop := v.get_node_or_null("Population")
	if pop == null:
		return out
	for n in pop.find_children("*", "AnimatableBody3D", true, false):
		if n.get("mode") == null:
			continue
		var r := 0.3
		for c in n.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is CapsuleShape3D:
				r = ((c as CollisionShape3D).shape as CapsuleShape3D).radius
		out.append({"node": n, "r": r})
	return out

func _route_dist(q: Vector2) -> Array:
	var best := INF
	var dir := Vector2.RIGHT
	for route: Array in ROUTES:
		for i in route.size() - 1:
			var a: Vector2 = route[i]
			var b: Vector2 = route[i + 1]
			var cp := Geometry2D.get_closest_point_to_segment(q, a, b)
			if cp.distance_to(q) < best:
				best = cp.distance_to(q)
				dir = (b - a).normalized()
	return [best, dir]

func _walk_check(v: Node3D, S: Object, space: PhysicsDirectSpaceState3D, terrain: StaticBody3D) -> Dictionary:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var actors := _npc_actors(v)
	var ex: Array[RID] = [terrain.get_rid()]
	for a: Dictionary in actors:
		ex.append((a["node"] as CollisionObject3D).get_rid())
	var blocked: Array = []
	var probes := 0
	for route: Array in ROUTES:
		for e: Array in GL.resample(route, 0.5):
			var p: Vector2 = e[0]
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cap
			qp.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, S.h(p.x, p.y) + 0.3 + 0.85 + 0.12, p.y))
			qp.exclude = ex
			probes += 1
			var r := space.intersect_shape(qp, 1)
			if not r.is_empty():
				blocked.append("(%.1f,%.1f) %s" % [p.x, p.y, String(v.get_path_to(r[0]["collider"] as Node))])
	var dwell_bad: Array = []
	var along_bad: Array = []
	var width_bad: Array = []
	var crossings: Array = []
	var dwell_min := 0.0
	var width_min := 0.0
	for a: Dictionary in actors:
		var n := a["node"] as Node3D
		var rr: float = a["r"]
		var band := 0.3 + rr
		dwell_min = 0.3 + rr + 0.3
		width_min = 2.0 * (0.3 + rr) + 0.3
		var path: PackedVector2Array = n.get("path_xz")
		var dwell: Array = []
		if String(n.get("mode")) == "patrol" and path.size() >= 2:
			dwell = [path[0], path[path.size() - 1]]
		else:
			dwell = [Vector2(n.global_position.x, n.global_position.z)]
		for q: Vector2 in dwell:
			var d: float = _route_dist(q)[0]
			if d < dwell_min:
				dwell_bad.append("%s (%.1f,%.1f) %.2f m" % [n.name, q.x, q.y, d])
		if String(n.get("mode")) != "patrol" or path.size() < 2:
			continue
		var along := 0.0
		var inside := false
		var cross_at := Vector2.INF
		var L := 0.0
		for i in path.size() - 1:
			L += path[i].distance_to(path[i + 1])
		var steps := maxi(2, int(L / 0.05))
		for k in steps + 1:
			var u := L * k / steps
			var q := _path_at(path, u)
			var rd: Array = _route_dist(q)
			var now := float(rd[0]) < band
			if now:
				along += L / steps
				if not inside:
					cross_at = q
			elif inside:
				if along > ALONG_MAX:
					along_bad.append("%s %.2f m" % [n.name, along])
				crossings.append([n.name, cross_at, rd[1]])
				along = 0.0
			inside = now
		if inside:
			if along > ALONG_MAX:
				along_bad.append("%s %.2f m" % [n.name, along])
			crossings.append([n.name, cross_at, _route_dist(cross_at)[1]])
	# ③ 横切り点の静的通行幅（ルート法線方向、NPC 除外）
	for c: Array in crossings:
		var q: Vector2 = c[1]
		var dir: Vector2 = c[2]
		var nrm := Vector2(-dir.y, dir.x)
		var free_lo := 0.0
		var free_hi := 0.0
		for sgn in [-1.0, 1.0]:
			var t := 0.0
			while t < 3.0:
				var pp: Vector2 = q + nrm * (t + 0.05) * sgn
				var qp := PhysicsShapeQueryParameters3D.new()
				qp.shape = cap
				qp.transform = Transform3D(Basis.IDENTITY, Vector3(pp.x, S.h(pp.x, pp.y) + 0.3 + 0.85 + 0.12, pp.y))
				qp.exclude = ex
				if not space.intersect_shape(qp, 1).is_empty():
					break
				t += 0.05
			if sgn < 0:
				free_lo = t
			else:
				free_hi = t
		var width := free_lo + free_hi + 0.6
		if width < width_min:
			width_bad.append("%s (%.1f,%.1f) %.2f m" % [c[0], q.x, q.y, width])
		else:
			info("NPC 横切り %s (%.1f,%.1f)：静的通行幅 %.2f m（≥ %.2f）" % [c[0], q.x, q.y, width, width_min])
	return {"probes": probes, "blocked": blocked, "npc_n": actors.size(), "dwell_bad": dwell_bad, "dwell_min": dwell_min, "along_bad": along_bad,
		"crossings": crossings, "width_bad": width_bad, "width_min": width_min}

func _path_at(path: PackedVector2Array, u: float) -> Vector2:
	var acc := 0.0
	for i in path.size() - 1:
		var l := path[i].distance_to(path[i + 1])
		if acc + l >= u:
			return path[i].lerp(path[i + 1], clampf((u - acc) / maxf(l, 1e-6), 0.0, 1.0))
		acc += l
	return path[path.size() - 1]

## 永久反向（場景級・記憶體のみ）：各案で _walk_check が FAIL になること。
##   N1 ルート上に静的な箱 → 被擋（旧版どおり）
##   N2 C20 を idle にして入口ルートの横切り点に立たせる → 待機点
##   N3 C20 の巡回の片端を入口ルート上へ → 待機点
##   N4 C20 の巡回を入口ルートに沿わせる（4 m）→ 沿って歩く
func _scene_negatives(v: Node3D) -> int:
	for i in 4:
		await physics_frame
	var space := v.get_world_3d().direct_space_state
	var terrain := v.get_node("Collision/TerrainCollision") as StaticBody3D
	var S := RLib.terrain_sampler(v)
	quiet = true
	var W0 := _walk_check(v, S, space, terrain)
	var clean := (W0["blocked"] as Array).is_empty() and (W0["dwell_bad"] as Array).is_empty() and (W0["along_bad"] as Array).is_empty() and (W0["width_bad"] as Array).is_empty()
	print("[SCHOOL] NEG 対照（無改変）：%s" % ("PASS" if clean else "FAIL"))
	var miss := 0 if clean else 1
	var c20: Node3D = null
	for a: Dictionary in _npc_actors(v):
		if String((a["node"] as Node).name).begins_with("C20"):
			c20 = a["node"]
	var X := Vector2(205.2, 24.2)
	var names := ["N1 ルート上に静的な箱", "N2 C20 を idle にして横切り点に立たせる", "N3 C20 の巡回の片端を入口ルート上へ", "N4 C20 の巡回を入口ルートに沿わせる 4 m"]
	for n in 4:
		var box: StaticBody3D = null
		var keep_mode: String = c20.get("mode")
		var keep_path: PackedVector2Array = c20.get("path_xz")
		var keep_xf := c20.global_transform
		match n:
			0:
				box = StaticBody3D.new()
				var cs := CollisionShape3D.new()
				var bx := BoxShape3D.new()
				bx.size = Vector3(0.6, 1.0, 0.6)
				cs.shape = bx
				box.add_child(cs)
				v.add_child(box)
				box.global_position = Vector3(200.0, S.h(200.0, 24.1) + 0.5, 24.1)
			1:
				c20.set("mode", "idle")
				c20.global_position = Vector3(X.x, S.h(X.x, X.y), X.y)
			2:
				var pp := PackedVector2Array(keep_path)
				pp[pp.size() - 1] = Vector2(204.0, 24.2)
				c20.set("path_xz", pp)
			3:
				c20.set("path_xz", PackedVector2Array([Vector2(206.0, 22.0), Vector2(206.0, 24.25), Vector2(201.0, 24.15), Vector2(201.0, 22.0)]))
		for i in 3:
			await physics_frame
		var W := _walk_check(v, S, space, terrain)
		var tripped := not ((W["blocked"] as Array).is_empty() and (W["dwell_bad"] as Array).is_empty() and (W["along_bad"] as Array).is_empty() and (W["width_bad"] as Array).is_empty())
		print("[SCHOOL] NEG %s：被擋 %d 待機点 %d 沿い %d 幅 %d → %s" % [names[n], (W["blocked"] as Array).size(), (W["dwell_bad"] as Array).size(), (W["along_bad"] as Array).size(), (W["width_bad"] as Array).size(), "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			miss += 1
		if box:
			v.remove_child(box)
			box.free()
		c20.set("mode", keep_mode)
		c20.set("path_xz", keep_path)
		c20.global_transform = keep_xf
		for i in 3:
			await physics_frame
	quiet = false
	print("[SCHOOL] 結果：%d 項失敗（scene negatives）" % miss)
	return miss

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
	var W := _walk_check(v, S, space, terrain)
	check("實走：入口＋前庭＋南側院＋北側通路 膠囊 %d 點被擋 %d %s（靜的障害；NPC は下の動的規則）" % [W["probes"], (W["blocked"] as Array).size(), ", ".join((W["blocked"] as Array).slice(0, 3))],
		(W["blocked"] as Array).is_empty())
	check("實走（NPC 動的規則）：NPC %d 体の待機点（idle 位置・巡回の両端）がルートから < %.2f m %d %s；巡回がルートに沿って歩く区間 > %.1f m %d %s；横切り %d 箇所の静的通行幅 < %.2f m %d %s" % [
		W["npc_n"], W["dwell_min"], (W["dwell_bad"] as Array).size(), ", ".join((W["dwell_bad"] as Array).slice(0, 3)), ALONG_MAX, (W["along_bad"] as Array).size(), ", ".join((W["along_bad"] as Array).slice(0, 3)),
		(W["crossings"] as Array).size(), W["width_min"], (W["width_bad"] as Array).size(), ", ".join((W["width_bad"] as Array).slice(0, 3))],
		(W["dwell_bad"] as Array).is_empty() and (W["along_bad"] as Array).is_empty() and (W["width_bad"] as Array).is_empty())
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
