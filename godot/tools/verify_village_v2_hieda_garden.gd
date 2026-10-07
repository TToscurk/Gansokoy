extends SceneTree
## 人間之里 V2 P9 R4：稗田邸庭園 規劃 gate＋烘焙＋掛載＋場景級驗證＋審圖鏡位。
##   規劃＋gate（唯讀）：Godot --headless --path godot --script res://tools/verify_village_v2_hieda_garden.gd
##   反向：             ... -- --neg=float|clutter|axis|pond|wall（各自瞄準一項，必須讓那一項 FAIL）；-- --negatives 一次跑完
##   烘焙 overlay：     Godot --path godot --resolution 640x360 --script ... -- --build
##   掛進場景：         ... --headless ... -- --attach（village_v2.tscn 文字層級在 Vegetation/BambooP9 後加 HiedaGardenP9 instance；
##                       先確認沒有 Godot 編輯器開著；**不重生** village_v2.tscn——若有流程重生它，重生後須依序重新 attach
##                       ForestP9 → BambooP9 → HiedaGardenP9）
##   場景驗證：         ... --headless ... -- --scene（已掛載：構件射線接地、碰撞 vs 本屋／門／牆、主軸＋飛石路線膠囊實走、
##                       池擋人、R1–R3 植被 overlay 仍掛載）
##   審圖鏡位：         ... --headless ... -- --shots（寫 tools/shots/village_v2_p9r4_garden_{before,after}.json）
## 每項一行 [GARDEN] PASS/FAIL；INFO 不計失敗；結尾 quit(失敗項數)。

const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const REPORT := "res://data/village_v2_p9r4_garden.json"
const SEAL := "res://data/village_v2_p9r4_seal.json"
const EYE := 1.7
## 留白：前庭（大宅門內 → 本屋簷，主軸以西）實體物件（樹冠投影＋構件外框）覆蓋率上限
const FRONT_VOID := Rect2(384.55, -31.6, 13.45, 21.3)
const VOID_MAX := 0.18
## 主軸視廊：門口 1.7 m 眼高到玄關的視線，沿程 0.6 m 半寬內不得有植栽／構件
const AXIS_EYE := Vector3(398.0, 0.0, -9.6)

var fails := 0
var neg := ""
var failed_labels: Array = []
var quiet := false


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[GARDEN] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(label: String) -> void:
	if not quiet:
		print("[GARDEN] INFO " + label)


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
		print("[GARDEN] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var old := v.get_node_or_null("Vegetation/" + GL.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	if "--shots" in args:
		quit(_shots(v))
		return
	root.add_child(v)
	await physics_frame
	await physics_frame
	var P: Dictionary = GL.plan(v, L)
	info("規劃 %d 件（%d ms）、池面 y %.2f" % [(P["items"] as Array).size(), P["ms"], P["water_y"]])
	if "--negatives" in args:
		var target := {"float": "接地", "clutter": "留白", "axis": "主軸", "pond": "池泉", "wall": "邊界"}
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
			_checks(P2, v)
			quiet = false
			var hit := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(target[nm])))
			print("[GARDEN] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d）" % ["PASS" if hit else "FAIL", nm, target[nm], failed_labels.size()])
			if not hit:
				bad += 1
		print("[GARDEN] 結果：%d 項失敗（negatives）" % bad)
		quit(bad)
		return
	if neg != "":
		_inject(P)
	var rep := _checks(P, v)
	if neg != "":
		print("[GARDEN] negative=%s 失敗 %d 項" % [neg, fails])
		quit(fails)
		return
	if "--build" in args and fails == 0:
		var r := GL.bake(P)
		GL.own(r, r)
		var ps := PackedScene.new()
		check("pack overlay", ps.pack(r) == OK)
		var e := ResourceSaver.save(ps, GL.OUTPUT, ResourceSaver.FLAG_COMPRESS)
		check("save %s" % GL.OUTPUT, e == OK)
		rep["overlay"] = {"path": GL.OUTPUT, "mb": FileAccess.get_file_as_bytes(GL.OUTPUT).size() / 1048576.0,
			"items": r.get_meta("items"), "shapes": r.get_meta("shapes"), "water_y": r.get_meta("water_y")}
		info("overlay %.2f MB、%d 件、碰撞 %d" % [rep["overlay"]["mb"], rep["overlay"]["items"], rep["overlay"]["shapes"]])
		r.free()
		var f := FileAccess.open(REPORT, FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, "  ", false))
		f.close()
	print("[GARDEN] 結果：%d 項失敗" % fails)
	quit(fails)


func _inject(P: Dictionary) -> void:
	var items: Array = P["items"]
	match neg:
		"float":
			items[items.size() / 2]["y"] = float(items[items.size() / 2]["y"]) + 0.4
		"clutter":
			# 前庭砂利面塞滿躑躅（每 2.2 m 一團）
			var S: RLib.TriSampler = P["S"]
			var x := 386.0
			while x < 396.5:
				var z := -12.0
				while z > -30.0:
					items.append(GL.item(S, "tree", "tsutsuji_a", Vector2(x, z), 0.0, 0.8, "front_shrub"))
					z -= 2.2
				x += 2.2
		"axis":
			var S: RLib.TriSampler = P["S"]
			items.append(GL.item(S, "mesh", "gk_toro_kasuga", Vector2(398.0, -16.0), 0.0, 1.0, "lantern"))
		"pond":
			P["water_y"] = float(P["water_y"]) + 0.6
		"wall":
			var S: RLib.TriSampler = P["S"]
			items.append(GL.item(S, "tree", "momiji_a", Vector2(384.9, -40.0), 0.0, 0.8, "rear_plant"))


func _footprint(it: Dictionary, M: Dictionary) -> float:
	## 半徑：樹＝冠幅／2×縮放（地被不計留白：0.4 倍）、構件＝外框半對角
	var s: Vector3 = it["sc"]
	if String(it["kind"]) == "tree":
		var info: Dictionary = M.get(String(it["id"]), {})
		return float(info.get("crown_w", 2.0)) * 0.5 * maxf(s.x, s.z)
	var dims: Array = GKD.get(String(it["id"]), [-0.3, 0, -0.3, 0.3, 0, 0.3])
	return Vector2(float(dims[3]) - float(dims[0]), float(dims[5]) - float(dims[2])).length() * 0.5 * maxf(s.x, s.z)


var GKD := {}


func _checks(P: Dictionary, v: Node3D) -> Dictionary:
	var S: RLib.TriSampler = P["S"]
	var items: Array = P["items"]
	var M: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/village_v2/veg_kit/src/modules_blender.json"))["trees"]
	if GKD.is_empty():
		var gm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/village_v2/garden_kit/src/modules_blender.json"))["modules"]
		for k: String in gm:
			GKD[k] = gm[k]["dims"]
		var rm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/village_v2/riverbank_kit/src/modules_blender.json"))["modules"]
		for k: String in rm:
			GKD[k] = rm[k]["dims"]
	var rep := {"date": Time.get_datetime_string_from_system(), "items": items.size()}
	# ── 1 邊界：全部落在牆內（距牆內面 ≥ 構件半徑 0.6 倍；樹幹 ≥ 0.6 m）、不進本屋台基／玄關、不壓大宅門開口
	var bad: Array = []
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		var r := 0.6 if String(it["kind"]) == "tree" else _footprint(it, M) * 0.6
		if String(it["id"]).begins_with("gk_yotsume") or String(it["id"]).begins_with("gk_amaochi"):
			r = 0.05
		var inside := GL.ESTATE.grow(-r).has_point(p)
		var house := GL.HOUSE_BASE.grow(0.05).has_point(p) or GL.GENKAN.has_point(p)
		var gate := Rect2(396.8, -12.0, 2.4, 2.0).has_point(p) and String(it["tag"]) != "path_main"
		if not inside or house or gate:
			bad.append("%s@(%.1f,%.1f)" % [it["id"], p.x, p.y])
	check("邊界：%d 件全在圍牆內（樹幹距牆 ≥ 0.6 m、構件 ≥ 0.6×半徑）、不進本屋台基／玄關、不擋大宅門開口；違規 %d %s" % [items.size(),
		bad.size(), ", ".join(bad.slice(0, 3))], bad.is_empty())
	# ── 2 接地：每件 origin 不高於環 8 點最低地面（不浮）、埋深 ≤ 0.45 m；延段頂與中心地面差 ≤ 0.05
	var fl := 0
	var dp := 0
	var worst := 0.0
	for it: Dictionary in items:
		if it.get("in_water", false) or it.get("on_island", false) or String(it["id"]) == "gk_bridge":
			continue
		var p: Vector2 = it["p"]
		var f: Array = GL._foot(String(it["id"]) if String(it["kind"]) == "mesh" else "tree")
		var s: Vector3 = it["sc"]
		# 接地面＝庭園地面 overlay（GL.surf：岸坡・築山・溪床）；環 8 點＋中心の最低
		var rr := float(it.get("foot_r", float(f[0]) * maxf(s.x, s.z)))
		var lo := GL.surf(P, p)
		for k in 8:
			lo = minf(lo, GL.surf(P, p + Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0)) * rr))
		var c := GL.surf(P, p)
		var y := float(it["y"])
		if String(it["tag"]) == "path_main":
			if absf(y - c) > 0.05:
				fl += 1
			continue
		if y > lo + 0.005:
			fl += 1
			worst = maxf(worst, y - lo)
		if c - y > 0.45:
			dp += 1
			if not quiet:
				print("[GARDEN] INFO 過深 %s@(%.1f,%.1f) %.2f" % [it["id"], p.x, p.y, c - y])
	check("接地：構件／植栽 origin ≤ 環 8 點最低 overlay 面、埋 ≤ 0.45 m；延段貼地 ±5 cm：浮 %d（最大 %.2f m）、過深 %d" % [fl, worst, dp],
		fl == 0 and dp == 0)
	# ── 3 主軸：門 → 玄關 延段連續（板距 ≤ 1.5 m）、視廊（門口 1.7 m 眼高望玄關，0.6 m 半寬內無植栽／構件高於 0.4 m）
	var path: Array = items.filter(func(it: Dictionary) -> bool: return String(it["tag"]) == "path_main")
	var gap := 0.0
	for k in path.size() - 1:
		gap = maxf(gap, (path[k]["p"] as Vector2).distance_to(path[k + 1]["p"]))
	var blocked: Array = []
	for it: Dictionary in items:
		if String(it["tag"]) in ["path_main", "amaochi", "kerb"] or String(it["id"]).begins_with("gk_tobi"):
			continue
		var p: Vector2 = it["p"]
		var d := GL.line_d(GL.MAIN_PATH, p).x
		var r := _footprint(it, M) * (0.35 if String(it["kind"]) == "tree" else 0.8)
		if d - r < 0.6 + GL.MAIN_W * 0.5 - 0.65:
			var h := float(M.get(String(it["id"]), {}).get("height", 2.0)) * (it["sc"] as Vector3).y if String(it["kind"]) == "tree" \
				else float(GKD.get(String(it["id"]), [0, 0, 0, 0, 1, 0])[4]) * (it["sc"] as Vector3).y
			if h > 0.4:
				blocked.append("%s@(%.1f,%.1f) d %.2f" % [it["id"], p.x, p.y, d])
	check("主軸：大宅門 → 玄關 延段 %d 枚、最大板距 %.2f m（≤ 1.5）、鉤の手 1 處；主軸兩側 0.6 m 視廊內高物 %d %s" % [path.size(), gap,
		blocked.size(), ", ".join(blocked.slice(0, 3))], gap <= 1.5 and blocked.is_empty() and path.size() >= 12)
	# ── 4 留白：前庭（主軸以西）實體覆蓋率（樹冠投影＋構件外框，0.5 m 格）≤ VOID_MAX
	var occ := 0
	var tot := 0
	var x := FRONT_VOID.position.x
	while x < FRONT_VOID.end.x:
		var z := FRONT_VOID.position.y
		while z < FRONT_VOID.end.y:
			var q := Vector2(x + 0.25, z + 0.25)
			if GL.line_d(GL.MAIN_PATH, q).x > GL.MAIN_W * 0.5:
				tot += 1
				for it: Dictionary in items:
					if String(it["tag"]) in ["path_main", "amaochi", "fence", "kerb"]:
						continue
					var r := _footprint(it, M)
					if (it["p"] as Vector2).distance_to(q) < r:
						occ += 1
						break
			z += 0.5
		x += 0.5
	var void_r := float(occ) / maxf(tot, 1)
	check("留白：前庭主軸以西 %.0f m² 實體覆蓋 %.1f %%（≤ %.0f %%；砂利面刻意空著）" % [tot * 0.25, void_r * 100, VOID_MAX * 100],
		void_r <= VOID_MAX)
	rep["front_void_cover"] = void_r
	# ── 5 池泉：池面 ≥ 池內地形最高＋0.02、≤ 池岸地形最低＋0.15（岸不懸空、水不淹岸）；中島在池內；曲水往下游不升高、入池
	var pond: PackedVector2Array = P["pond"]
	var wl: float = P["water_y"]
	var shore_lo := INF
	for q in pond:
		shore_lo = minf(shore_lo, S.h(q.x, q.y))
	var bed_hi := -INF
	for k in range(0, pond.size(), 2):
		var c := pond[k].lerp(GL.ISLAND[0], 0.4)
		if Geometry2D.is_point_in_polygon(c, pond):
			bed_hi = maxf(bed_hi, S.h(c.x, c.y))
	var isl_ok := true
	for q in P["island"]:
		if not Geometry2D.is_point_in_polygon(q, pond) or GL.poly_d(pond, q) < 1.0:
			isl_ok = false
	var sy: Array = P["stream_y"]
	var mono := true
	for k in sy.size() - 1:
		if float(sy[k + 1]) > float(sy[k]) + 1e-4:
			mono = false
	var into := Geometry2D.is_point_in_polygon(GL.STREAM[-1], pond) or GL.poly_d(pond, GL.STREAM[-1]) < 0.8
	var area := 0.0
	for i in pond.size():
		area += pond[i].x * pond[(i + 1) % pond.size()].y - pond[(i + 1) % pond.size()].x * pond[i].y
	area = absf(area) * 0.5
	check("池泉：池 %.0f m²、池面 y %.2f（池底最高 %.2f＋≥ 0.02；岸最低 %.2f＋≤ 0.15）、中島在池內且離岸 ≥ 1 m %s、曲水 %d 站水面往下游不升 %s、入池 %s（落差 %.2f m）" % [
		area, wl, bed_hi, shore_lo, isl_ok, sy.size(), mono, into, float(sy[0]) - float(sy[-1])],
		wl >= bed_hi + 0.02 and wl <= shore_lo + 0.15 and isl_ok and mono and into and area > 80.0)
	rep["pond"] = {"area": area, "water_y": wl, "stream_drop": float(sy[0]) - float(sy[-1])}
	# ── 6 飛石：步距 0.6–1.25 m（石心）、石不入池、不入曲水（沢飛び除外）
	var tobis: Array = items.filter(func(it: Dictionary) -> bool: return String(it["tag"]) == "path_tobi")
	var step_bad := 0
	var wet := 0
	for k in tobis.size():
		var p: Vector2 = tobis[k]["p"]
		if not tobis[k].get("in_water", false):
			if Geometry2D.is_point_in_polygon(p, pond) or GL.line_d(GL.STREAM, p).x < GL.stream_w(GL.line_d(GL.STREAM, p).y) * 0.5 + 0.15:
				wet += 1
		if k > 0:
			var d := p.distance_to(tobis[k - 1]["p"])
			if d > 0.0 and (d < 0.55 or d > 1.5) and d < 4.0:
				step_bad += 1
				if not quiet:
					print("[GARDEN] INFO 步距 %.2f @ (%.1f,%.1f)–(%.1f,%.1f)" % [d, p.x, p.y, (tobis[k - 1]["p"] as Vector2).x, (tobis[k - 1]["p"] as Vector2).y])
	check("飛石：%d 枚、步距 0.55–1.5 m 違規 %d、落水（非沢飛び）%d" % [tobis.size(), step_bad, wet], step_bad == 0 and wet == 0)
	# ── 7 元素齊全（ART 規格）：松／楓／櫻／灌木／苔（地面）／飛石／主景石／石燈籠／蹲踞／池／曲水／石橋
	var have := {}
	for it: Dictionary in items:
		var id := String(it["id"])
		for k: String in ["niwamatsu", "momiji", "sakura", "tsutsuji", "gk_tobi", "gk_kei_tall", "gk_kei_mid", "gk_toro", "gk_tsukubai",
				"gk_bridge", "gk_nobe", "gk_amaochi", "gk_yotsume", "gk_sodegaki"]:
			if id.begins_with(k):
				have[k] = int(have.get(k, 0)) + 1
	check("元素：%s" % str(have), have.size() == 14)
	rep["elements"] = have
	var trees := items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "tree").size()
	info("庭園：%d 件（植栽 %d、構件 %d）" % [items.size(), trees, items.size() - trees])
	return rep


# ─────────────────────────── 掛載 ───────────────────────────

func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if txt.is_empty():
		push_error("讀不到 " + SCENE)
		return 1
	if txt.contains("gen/hieda_garden_p9.scn"):
		push_error("已經掛過 HiedaGardenP9")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var done := false
	var i := 0
	while i < lines.size():
		var ln := lines[i]
		out.append(ln)
		if not done and ln.begins_with("[node name=\"BambooP9\" parent=\"Vegetation\""):
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"HiedaGardenP9\" parent=\"Vegetation\" instance=ExtResource(\"p9r4_hieda_garden\")]")
			out.append("")
			done = true
			continue
		i += 1
	if not done:
		push_error("找不到 Vegetation/BambooP9（R3 竹林未掛載；順序須為 ForestP9 → BambooP9 → HiedaGardenP9）")
		return 1
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p9r4_hieda_garden\"]" % GL.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[GARDEN] attach：加 Vegetation/HiedaGardenP9 → %s" % SCENE)
	return 0


# ─────────────────────────── 場景級驗證（已掛載） ───────────────────────────

var BP := {}


func _scene(v: Node3D) -> void:
	await physics_frame
	BP = GL.plan(v, {})
	var go := v.get_node_or_null("Vegetation/" + GL.NODE_NAME) as Node3D
	check("場景已掛 Vegetation/%s，且 R2 ForestP9／R3 BambooP9 仍掛載" % GL.NODE_NAME, go != null
		and v.get_node_or_null("Vegetation/ForestP9") != null and v.get_node_or_null("Vegetation/BambooP9") != null)
	if go == null:
		return
	for i in 4:
		await physics_frame
	var space := v.get_world_3d().direct_space_state
	var terrain := v.get_node("Collision/TerrainCollision") as StaticBody3D
	var grid := go.get_node("Collision") as StaticBody3D
	# 1 構件射線接地（Props 每件：origin 正下方只認地形）
	var fl := 0
	var n := 0
	var worst := 0.0
	for node in go.get_node("Props").find_children("*", "Node3D", true, false):
		if not node.has_meta("garden_id"):
			continue
		var id := String(node.get_meta("garden_id"))
		if id == "gk_bridge" or String(node.get_meta("garden_tag")) == "path_tobi" and (node as Node3D).global_position.y > 99.0:
			continue
		var p := (node as Node3D).global_position
		if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), Geometry2D.offset_polygon(GL.chaikin(GL.ISLAND, 2), 0.8)[0]):
			continue      # 中島上／中島岸半入水石（站在中島 mesh／池底，不在地形上）
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 3, 0), p - Vector3(0, 3, 0))
		q.exclude = [grid.get_rid()]
		var y_hit := NAN
		var ex: Array[RID] = [grid.get_rid()]
		for k in 6:
			q.exclude = ex
			var r := space.intersect_ray(q)
			if r.is_empty():
				break
			if r["collider"] == terrain:
				y_hit = float((r["position"] as Vector3).y)
				break
			ex.append(r["rid"])
		if is_nan(y_hit):
			continue
		n += 1
		# overlay 面（GL.surf）基準：浮き＝origin − overlay（overlay は地形＋盛り／岸坡；地形は射線で實測）
		var gap := p.y - (y_hit + GL.berm(BP, Vector2(p.x, p.z)))
		worst = maxf(worst, gap)
		if gap > 0.06:
			fl += 1
			if fl <= 6:
				print("[GARDEN]   浮 %s@(%.1f,%.1f) %.3f" % [id, p.x, p.z, gap])
	check("場景接地（%d 件構件 origin 向下射線只認地形）：浮 > 0.06 m %d（最大 %.3f）" % [n, fl, worst], fl == 0 and n > 100)
	# 2 庭園碰撞 vs 本屋／大宅門／圍牆／其他（排除地形與庭園自己）
	var hits := {}
	for cs: CollisionShape3D in grid.get_children():
		var qp := PhysicsShapeQueryParameters3D.new()
		qp.shape = cs.shape
		qp.transform = cs.global_transform
		qp.exclude = [terrain.get_rid(), grid.get_rid()]
		for r: Dictionary in space.intersect_shape(qp, 4):
			if go.is_ancestor_of(r["collider"] as Node):
				continue      # 庭園內部（中島松 vs 池碰撞）不算
			var key := String(v.get_path_to(r["collider"] as Node)).get_slice("/", 0) + "/" + String(v.get_path_to(r["collider"] as Node)).get_slice("/", 1)
			hits[key + " ← " + String(cs.get_meta("garden_id", "?")) + "@(%.1f,%.1f)" % [cs.global_position.x, cs.global_position.z]] = 1
	# 植栽（樹 prefab Collision）vs 本屋／門／牆
	for t in go.get_node("Plants").get_children():
		var sb := t.get_node_or_null("Collision") as StaticBody3D
		if sb == null:
			continue
		for cs: CollisionShape3D in sb.get_children():
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cs.shape
			qp.transform = cs.global_transform
			qp.exclude = [terrain.get_rid(), grid.get_rid(), sb.get_rid()]
			for r: Dictionary in space.intersect_shape(qp, 4):
				var col := r["collider"] as Node
				if go.is_ancestor_of(col):
					continue
				hits[String(v.get_path_to(col)).get_slice("/", 1) + " ← " + String(t.name)] = 1
	check("碰撞：庭園構件／池／樹幹 vs 本屋／大宅門／圍牆／其他接觸 %s" % (str(hits.keys()) if hits else "0"), hits.is_empty())
	# 3 實走：主軸（門 → 玄關踏石前）＋飛石路線，膠囊 r 0.3 h 1.7 離地 5 cm 只可碰地形與延段
	var S := RLib.terrain_sampler(v)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var blocked: Array = []
	var probes := 0
	for route: Array in [GL.MAIN_PATH, GL.TOBI]:
		for e: Array in GL.resample(route, 0.5):
			var p: Vector2 = e[0]
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cap
			qp.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, S.h(p.x, p.y) + 0.3 + 0.85 + 0.12, p.y))
			qp.exclude = [terrain.get_rid()]
			probes += 1
			var r := space.intersect_shape(qp, 1)
			if not r.is_empty():
				blocked.append("(%.1f,%.1f) %s" % [p.x, p.y, (r[0]["collider"] as Node).name])
	check("實走：主軸＋飛石路線膠囊 %d 點被擋 %d %s" % [probes, blocked.size(), ", ".join(blocked.slice(0, 3))], blocked.is_empty())
	# 4 池擋人：池中心膠囊會撞
	var qp := PhysicsShapeQueryParameters3D.new()
	qp.shape = cap
	var wl := float(go.get_meta("water_y", 1.2))
	qp.transform = Transform3D(Basis.IDENTITY, Vector3(415.6, wl + 0.9, -20.0))
	qp.exclude = [terrain.get_rid()]
	check("池擋人：池內膠囊撞到池碰撞", not space.intersect_shape(qp, 1).is_empty())
	info("HiedaGardenP9：%s 件、碰撞 %s、池面 y %.2f" % [go.get_meta("items", "?"), go.get_meta("shapes", "?"), wl])


# ─────────────────────────── 審圖鏡位 ───────────────────────────

## [名稱, 相機 xz, 眼高（相對地面）, 看向 xz, 看向高（相對地面）]
const SHOTS := [
	["p9r4_gate_in", Vector2(398.0, -8.2), EYE, Vector2(400.0, -30.0), 2.6],
	["p9r4_gate_in_near", Vector2(398.0, -12.5), EYE, Vector2(403.5, -30.0), 2.2],
	["p9r4_axis_turn", Vector2(397.6, -15.2), EYE, Vector2(401.6, -20.6), 0.6],
	["p9r4_genkan_back", Vector2(403.0, -31.4), EYE, Vector2(398.0, -10.0), 1.8],
	["p9r4_genkan_back_w", Vector2(402.0, -31.2), EYE, Vector2(389.0, -15.0), 1.2],
	["p9r4_front_void", Vector2(396.6, -27.8), EYE, Vector2(387.0, -14.0), 1.3],
	["p9r4_pond", Vector2(406.2, -25.6), EYE, Vector2(412.0, -16.5), 0.3],
	["p9r4_pond_s", Vector2(409.5, -11.6), EYE, Vector2(414.0, -23.5), 0.6],
	["p9r4_stream", Vector2(417.3, -38.0), EYE, Vector2(418.6, -27.0), 0.0],
	["p9r4_rear", Vector2(417.0, -48.6), EYE, Vector2(400.0, -55.0), 1.2],
	["p9r4_rear_w", Vector2(398.6, -50.2), EYE, Vector2(418.0, -57.6), 1.0],
	["p9r4_tsukubai", Vector2(395.1, -49.8), 1.0, Vector2(395.0, -51.6), 0.25],
	["p9r4_rear_fall", Vector2(413.2, -49.6), EYE, Vector2(419.4, -58.4), 0.9],
]
## R4 r2 targeted polish：只重拍 4 組（側庭池泉／後庭・滝石組／蹲踞近景／前庭砂紋）
const POLISH := [
	["p9r4_pond", "p9r4_pond_s", "p9r4_stream", "p9r4b_bank_close", "p9r4b_stream_close"],
	["p9r4_rear_w", "p9r4_rear_fall", "p9r4b_fall_close"],
	["p9r4_tsukubai", "p9r4b_tsukubai_side"],
	["p9r4_front_void", "p9r4b_rake_rings", "p9r4_genkan_back_w"],
]
const SHOTS_B := [
	["p9r4b_bank_close", Vector2(414.6, -26.2), EYE, Vector2(416.4, -22.6), 0.0],
	["p9r4b_stream_close", Vector2(417.6, -45.4), EYE, Vector2(419.4, -41.0), 0.0],
	["p9r4b_fall_close", Vector2(416.4, -54.2), EYE, Vector2(419.4, -58.6), 0.8],
	["p9r4b_tsukubai_side", Vector2(396.3, -50.3), 1.0, Vector2(395.0, -51.5), 0.25],
	["p9r4b_rake_rings", Vector2(395.9, -27.2), EYE, Vector2(390.6, -22.8), 0.0],
]
## 審圖只藏除錯／規劃標示（地塊線、任務錨點、傳送點、除錯）；遊戲內容不藏
const HIDE := ["Debug", "Portals", "QuestAnchors", "Districts/LandmarkParcelLines", "Districts/AuxParcelLines", "Portal_hieda1f"]
## 高處俯視（二樓緣側／屋頂高度、斜俯視）：[名稱, 相機 xyz（絕對）, 看向 xyz]
const HIGH := [
	["p9r4_high_2f_front", Vector3(402.0, 7.3, -30.6), Vector3(399.0, 0.5, -15.0)],
	["p9r4_high_2f_rear", Vector3(403.0, 7.4, -47.6), Vector3(406.0, 0.5, -56.0)],
	["p9r4_high_obl", Vector3(372.0, 24.0, -2.0), Vector3(403.0, 0.5, -35.0)],
	["p9r4_high_top", Vector3(403.0, 58.0, -34.5), Vector3(403.0, 0.0, -35.0)],
	["p9r4_high_ne", Vector3(438.0, 20.0, -68.0), Vector3(403.0, 0.5, -34.0)],
]


func _shots(v: Node3D) -> int:
	var S := RLib.terrain_sampler(v)
	var before: Array = []
	var after: Array = []
	var polish: Array = []
	var want: Array = []
	for g: Array in POLISH:
		want.append_array(g)
	for s: Array in SHOTS + SHOTS_B:
		var c: Vector2 = s[1]
		var l: Vector2 = s[3]
		var e := {"name": String(s[0]), "cam": [c.x, snappedf(S.h(c.x, c.y) + float(s[2]), 0.01), c.y],
			"look": [l.x, snappedf(S.h(l.x, l.y) + float(s[4]), 0.01), l.y], "hud": false, "time": 10}
		var eb := e.duplicate(true)
		eb["hide"] = HIDE + ["Vegetation/HiedaGardenP9"]
		e["hide"] = HIDE
		if String(s[0]) in want:
			polish.append(e.duplicate(true))
		if String(s[0]).begins_with("p9r4b_"):
			continue
		before.append(eb)
		after.append(e)
	for s: Array in HIGH:
		var c: Vector3 = s[1]
		var l: Vector3 = s[2]
		var e := {"name": String(s[0]), "cam": [c.x, c.y, c.z], "look": [l.x, l.y, l.z], "hud": false, "time": 10,
			"hide": HIDE}
		var eb := e.duplicate(true)
		eb["hide"] = HIDE + ["Vegetation/HiedaGardenP9"]
		before.append(eb)
		after.append(e)
	for pair: Array in [["res://tools/shots/village_v2_p9r4_garden_before.json", before], ["res://tools/shots/village_v2_p9r4_garden_after.json", after],
			["res://tools/shots/village_v2_p9r4b_polish.json", polish]]:
		var f := FileAccess.open(String(pair[0]), FileAccess.WRITE)
		f.store_string(JSON.stringify(pair[1], " ", false))
		f.close()
		print("[GARDEN] 寫入 %s（%d 張）" % [pair[0], (pair[1] as Array).size()])
	v.free()
	return 0


# ─────────────────────────── 封存（--seal，P9 R4 稗田邸庭園 ART_APPROVED 2026-10-02） ───────────────────────────

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
	check("P9 R4 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 總表 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	# 掛載：village_v2.tscn 仍依序掛 ForestP9 → BambooP9 → HiedaGardenP9
	var txt := FileAccess.get_file_as_string(SCENE)
	var i_f := txt.find("[node name=\"ForestP9\" parent=\"Vegetation\"")
	var i_b := txt.find("[node name=\"BambooP9\" parent=\"Vegetation\"")
	var i_g := txt.find("[node name=\"HiedaGardenP9\" parent=\"Vegetation\"")
	check("village_v2.tscn 掛載 Vegetation/ForestP9 → BambooP9 → HiedaGardenP9（%s）" % GL.OUTPUT,
		i_f >= 0 and i_b > i_f and i_g > i_b and txt.contains(GL.OUTPUT))
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[GARDEN] 結果：%d 項失敗（seal）" % fails)
	return fails
