extends SceneTree
## 人間之里 V2 P9 R4-2：神社周邊（鎮守之森／參道）規劃 gate＋烘焙＋掛載＋場景級驗證＋審圖鏡位。
##   規劃＋gate（唯讀）：Godot --headless --path godot --script res://tools/verify_village_v2_shrine_grove.gd
##   反向：             ... -- --neg=road|sight|void|uniform|float|rope（各自瞄準一項，必須讓那一項 FAIL）；-- --negatives 一次跑完
##   烘焙 overlay：     Godot --path godot --resolution 640x360 --script ... -- --build
##   掛進場景：         ... --headless ... -- --attach（village_v2.tscn 文字層級在 Vegetation/HiedaGardenP9 後加 ShrineGroveP9；
##                       先確認沒有 Godot 編輯器開著；**不重生** village_v2.tscn——若有流程重生它，重生後須依序重新 attach
##                       ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9）
##   場景驗證：         ... --headless ... -- --scene（射線接地、碰撞 vs 地標／建物／R2 樹幹、參道＋前庭膠囊實走〔P11 R1：歩行面基準＋段差〕、視線射線、掛載順序）
##   場景級反向：       ... --headless ... -- --scene-negatives（P11 R1：障害／継ぎ目段差／未登記の台 → 各案 FAIL）
##   審圖鏡位：         ... --headless ... -- --shots（寫 tools/shots/village_v2_p9r42_shrine_{before,after}.json）
##   封存：             ... --headless ... -- --seal（data/village_v2_p9r42_seal.json 雜湊＋掛載順序＋竄改反向；P9 R4-2 ART_APPROVED 2026-10-02）
## 每項一行 [SHRINE] PASS/FAIL；INFO 不計失敗；結尾 quit(失敗項數)。

const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const FLib := preload("res://tools/village_v2_forest_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const REPORT := "res://data/village_v2_p9r42_shrine.json"
const SEAL := "res://data/village_v2_p9r42_seal.json"
const EYE := 1.7

var fails := 0
var neg := ""
var failed_labels: Array = []
var quiet := false


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[SHRINE] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(label: String) -> void:
	if not quiet:
		print("[SHRINE] INFO " + label)


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
		quit(await _scene_negatives(v, L))
		return
	if "--scene" in args:
		root.add_child(v)
		await _scene(v, L)
		print("[SHRINE] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var old := v.get_node_or_null("Vegetation/" + SG.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	if "--shots" in args:
		quit(_shots(v))
		return
	root.add_child(v)
	await physics_frame
	await physics_frame
	var P: Dictionary = SG.plan(v, L)
	info("規劃 %d 件（%d ms）；拒絕原因 %s" % [(P["items"] as Array).size(), P["ms"], str(P["rejects"])])
	if "--negatives" in args:
		var target := {"road": "參道淨空", "sight": "視線", "void": "留白", "uniform": "非均勻", "float": "接地", "rope": "注連繩"}
		var bad := 0
		for nm: String in target:
			var cp: Array = []
			for it: Dictionary in P["items"]:
				cp.append(it.duplicate(true))
			var P2 := P.duplicate()
			P2["items"] = cp
			P2["rope"] = (P["rope"] as Dictionary).duplicate(true)
			neg = nm
			fails = 0
			failed_labels.clear()
			quiet = true
			_inject(P2)
			_checks(P2)
			quiet = false
			var hit := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(target[nm])))
			print("[SHRINE] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d）" % ["PASS" if hit else "FAIL", nm, target[nm], failed_labels.size()])
			if not hit:
				bad += 1
		print("[SHRINE] 結果：%d 項失敗（negatives）" % bad)
		quit(bad)
		return
	if neg != "":
		_inject(P)
	var rep := _checks(P)
	if neg != "":
		print("[SHRINE] negative=%s 失敗 %d 項" % [neg, fails])
		quit(fails)
		return
	if "--build" in args and fails == 0:
		var r := SG.bake(P)
		SG.own(r, r)
		var ps := PackedScene.new()
		check("pack overlay", ps.pack(r) == OK)
		var e := ResourceSaver.save(ps, SG.OUTPUT, ResourceSaver.FLAG_COMPRESS)
		check("save %s" % SG.OUTPUT, e == OK)
		rep["overlay"] = {"path": SG.OUTPUT, "mb": FileAccess.get_file_as_bytes(SG.OUTPUT).size() / 1048576.0,
			"items": r.get_meta("items"), "shapes": r.get_meta("shapes")}
		info("overlay %.2f MB、%d 件、構件碰撞 %d" % [rep["overlay"]["mb"], rep["overlay"]["items"], rep["overlay"]["shapes"]])
		r.free()
		var f := FileAccess.open(REPORT, FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, "  ", false))
		f.close()
	print("[SHRINE] 結果：%d 項失敗" % fails)
	quit(fails)


func _inject(P: Dictionary) -> void:
	var items: Array = P["items"]
	var S: RLib.TriSampler = P["S"]
	var road: Array = P["road"]
	match neg:
		"road":
			var p: Vector2 = (road[1] as Vector2).lerp(road[2], 0.5)
			items.append(SG.item(S, "tree", "sugi_a", p + Vector2(0.6, 0.0), 0.0, 1.0, "sando_row1", {"side": 1.0, "arc": 50.0}))
		"sight":
			var c: Vector3 = (P["cams"] as Array)[0]
			var tg: Vector3 = (P["targets"] as Array)[1]
			var q := c.lerp(tg, 0.55)
			items.append(SG.item(S, "tree", "shii_a", Vector2(q.x, q.z) + Vector2(4.5, 0.0), 0.0, 1.0, "sando_row2"))
		"void":
			items.append(SG.item(S, "tree", "sugi_b", Vector2(258.0, -214.0), 0.0, 1.0, "sando_row1"))
		"uniform":
			# 參道右側一列改成等距、同種
			var row: Array = items.filter(func(it: Dictionary) -> bool: return String(it["tag"]) == "sando_row1" and float(it.get("side", 0.0)) > 0.0)
			for k in row.size():
				var it: Dictionary = row[k]
				it["arc"] = 40.0 + k * 6.0
				it["id"] = "sugi_a"
		"float":
			for it: Dictionary in items:
				if String(it["tag"]) == "lantern":
					it["y"] = float(it["y"]) + 0.4
					break
		"rope":
			var pr: Array = P["rope"]["prof"]
			for k in pr.size():
				pr[k] = float(pr[k]) + 0.35


func _checks(P: Dictionary) -> Dictionary:
	var S: RLib.TriSampler = P["S"]
	var M: Dictionary = P["M"]
	var items: Array = P["items"]
	var road: Array = P["road"]
	var rep := {"date": Time.get_datetime_string_from_system(), "items": items.size()}
	var trees: Array = items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "tree")
	var canopy: Array = trees.filter(func(it: Dictionary) -> bool: return not (String(it["id"]) in SG.UNDER_IDS) and String(it["id"]) != "log_a")
	# ── 1 參道淨空：樹幹離路緣 ≥ 1.2 m＋幹徑；地被不進路面；不進鳥居／社殿／丘腳社寺／建物
	var bad: Array = []
	for it: Dictionary in trees:
		var p: Vector2 = it["p"]
		var id := String(it["id"])
		var sc: float = (it["sc"] as Vector3).x
		var e := SG.road_e(road, p)
		var lim := 0.2 if id in SG.UNDER_IDS else 1.2 + SG.trunk_r(id, sc, M)
		if id == "log_a":
			lim = 1.0
		if e < lim or SG.TORII_BOX.grow(1.5).has_point(p) or SG.SHRINE_BOX.grow(2.0).has_point(p) or SG.TEMPLE_BOX.grow(3.0).has_point(p):
			bad.append("%s@(%.1f,%.1f) e %.2f" % [id, p.x, p.y, e])
	check("參道淨空：%d 株植栽樹幹離路緣 ≥ 1.2 m＋幹徑、地被不進路面、不進鳥居／社殿／丘腳社寺；違規 %d %s" % [trees.size(), bad.size(),
		", ".join(bad.slice(0, 3))], bad.is_empty())
	# ── 2 接地：origin ≤ 環 8 點最低地面＋0.005、埋 ≤ 0.45
	var fl := 0
	var dp := 0
	var worst := 0.0
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		var sc: float = (it["sc"] as Vector3).x
		var r := SG.foot_r(String(it["kind"]), String(it["id"]), sc)
		if String(it["id"]) == "log_a":
			r = 1.2
		var lo := SG.ground(S, p, r)
		var y := float(it["y"])
		if String(it["tag"]) != "goshinboku" and y > lo + 0.005 + (0.03 if String(it["id"]) == "log_a" else 0.0):
			fl += 1
			worst = maxf(worst, y - lo)
		if String(it["tag"]) == "goshinboku":
			# 御神木：根張り底面全頂點 ≤ 地形＋0.03（谷側不浮）、中心埋 ≤ 1.4 m（山側埋入是斜面接地；北丘頂最小 1.26）
			var xf := SG.xf_of(it)
			var gmax := -INF
			for q in SG.flare_verts(String(it["id"])):
				var w := xf * q
				gmax = maxf(gmax, w.y - S.h(w.x, w.z))
			info("御神木斜面接地：根張り底面最高離地 %.3f m、中心埋 %.2f m" % [gmax, S.h(p.x, p.y) - y])
			if gmax > 0.03:
				fl += 1
			if S.h(p.x, p.y) - y > 1.4:
				dp += 1
			continue
		if S.h(p.x, p.y) - y > 0.45:
			dp += 1
			if not quiet:
				print("[SHRINE] INFO 過深 %s@(%.1f,%.1f) %.2f" % [it["id"], p.x, p.y, S.h(p.x, p.y) - y])
	check("接地：%d 件 origin ≤ 環 8 點最低地面、埋 ≤ 0.45 m：浮 %d（最大 %.2f m）、過深 %d" % [items.size(), fl, worst, dp], fl == 0 and dp == 0)
	# ── 3 視線：村側鳥居外 2 機位 1.7 m → 社殿屋頂／屋身，不被新樹冠／樹幹／燈籠擋；新樹守 R2 社殿背景天窗
	var blk: Array = []
	var cams: Array = P["cams"]
	var tgs: Array = P["targets"]
	for it: Dictionary in canopy:
		var cyl := SG.crown_cyl(it, M)
		var sc: float = (it["sc"] as Vector3).x
		var tcyl := [it["p"], SG.trunk_r(String(it["id"]), sc, M) + 0.05, float(it["y"]), float(it["y"]) + float(M[it["id"]]["height"]) * sc * 0.4]
		for c: Vector3 in cams:
			for tg: Vector3 in tgs:
				if SG.seg_hits(c, tg, cyl) or SG.seg_hits(c, tg, tcyl):
					blk.append("%s@(%.1f,%.1f)" % [it["id"], (it["p"] as Vector2).x, (it["p"] as Vector2).y])
	var cap_bad := 0
	for it: Dictionary in canopy:
		var cap := FLib.back_cap(it["p"], SG.SHRINE_ROOF)
		if cap < INF and float(it["y"]) + float(M[it["id"]]["height"]) * (it["sc"] as Vector3).y > cap + 0.05:
			cap_bad += 1
	check("視線：鳥居外 %d 機位 → 社殿屋頂／屋身被新樹擋 %d %s；R2 社殿背景天窗超高 %d" % [cams.size(), blk.size(), ", ".join(blk.slice(0, 3)),
		cap_bad], blk.is_empty() and cap_bad == 0)
	# ── 4 留白：前庭（拜殿前）不得有樹幹／灌木（燈籠除外）；樹冠投影覆蓋 ≤ VOID_MAX
	var fc := PackedVector2Array(SG.FORECOURT)
	var inside: Array = []
	for it: Dictionary in items:
		if String(it["tag"]) == "lantern":
			continue
		if Geometry2D.is_point_in_polygon(it["p"], fc):
			inside.append("%s@(%.1f,%.1f)" % [it["id"], (it["p"] as Vector2).x, (it["p"] as Vector2).y])
	var occ := 0
	var tot := 0
	var bb := Rect2(fc[0], Vector2.ZERO)
	for q in fc:
		bb = bb.expand(q)
	var x := bb.position.x
	while x < bb.end.x:
		var z := bb.position.y
		while z < bb.end.y:
			var q := Vector2(x + 0.25, z + 0.25)
			if Geometry2D.is_point_in_polygon(q, fc):
				tot += 1
				for it: Dictionary in canopy:
					var cr := float(M[it["id"]]["crown_w"]) * 0.5 * (it["sc"] as Vector3).x * 0.72
					if q.distance_to(it["p"]) < cr:
						occ += 1
						break
			z += 0.5
		x += 0.5
	var vr := float(occ) / maxf(tot, 1)
	check("留白：前庭 %.0f m² 內植栽／構件 %d %s、新樹冠投影覆蓋 %.1f %%（≤ %.0f %%）" % [tot * 0.25, inside.size(), ", ".join(inside.slice(0, 3)),
		vr * 100, SG.VOID_MAX * 100], inside.is_empty() and vr <= SG.VOID_MAX)
	rep["forecourt_cover"] = vr
	# ── 5 鎮守林：鳥居 → 參道終點每 6 m 窗兩側 9 m 內都有高木（新＋R2）；新高木針葉 ≥ 60 %、檜 ≤ 15 %
	var s_t: float = P["s_torii"]
	var L_r: float = P["L_road"]
	var all_c: Array = []
	for it: Dictionary in canopy:
		all_c.append([it["p"], float(M[it["id"]]["height"]) * (it["sc"] as Vector3).y])
	for t: Array in P["sealed"]:
		if String(t[3]) != "under" and float(t[6]) > 6.0:
			all_c.append([t[0], float(t[6])])
	var gaps: Array = []
	var s := s_t + 3.0
	var rs := GL.resample(road, 0.5)
	while s < L_r - 4.0:
		for sgn: float in [-1.0, 1.0]:
			var have := false
			for c: Array in all_c:
				var p: Vector2 = c[0]
				if float(c[1]) < 6.0:
					continue
				var a := SG.arc_of(road, p)
				if a < s or a > s + 6.0:
					continue
				var e := SG.road_e(road, p)
				if e > 9.0:
					continue
				var k := clampi(int(a / 0.5), 0, rs.size() - 1)
				var d: Vector2 = rs[k][1]
				var side := signf((p - (rs[k][0] as Vector2)).dot(Vector2(-d.y, d.x)))
				if side == sgn:
					have = true
					break
			if not have:
				gaps.append("%.0f%s" % [s - s_t, "R" if sgn > 0 else "L"])
		s += 6.0
	var n_con := canopy.filter(func(it: Dictionary) -> bool: return String(it["id"]) in SG.CONIFER).size()
	var n_hin := canopy.filter(func(it: Dictionary) -> bool: return String(it["id"]).begins_with("hinoki")).size()
	var con_r := float(n_con) / maxf(canopy.size(), 1)
	var hin_r := float(n_hin) / maxf(canopy.size(), 1)
	check("鎮守林：鳥居→參道終點每 6 m 窗兩側 9 m 內有高木（缺 %d %s）；新高木 %d 株、針葉 %.0f %%（≥ 60）、檜 %.0f %%（≤ 15）" % [
		gaps.size(), ", ".join(gaps.slice(0, 6)), canopy.size(), con_r * 100, hin_r * 100], gaps.size() <= 2 and con_r >= 0.6 and hin_r <= 0.15)
	rep["enclosure_gaps"] = gaps
	# ── 6 非均勻：近路一列每側間距 CV ≥ 0.2、同種連排 ≤ 2
	var cv_min := INF
	var run_max := 0
	for sgn: float in [-1.0, 1.0]:
		var row: Array = canopy.filter(func(it: Dictionary) -> bool: return String(it["tag"]) == "sando_row1" and float(it.get("side", 0.0)) == sgn)
		row.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["arc"]) < float(b["arc"]))
		var gs: Array = []
		var run := 1
		for k in range(1, row.size()):
			gs.append(float(row[k]["arc"]) - float(row[k - 1]["arc"]))
			run = run + 1 if String(row[k]["id"]) == String(row[k - 1]["id"]) else 1
			run_max = maxi(run_max, run)
		if gs.size() >= 3:
			var mu := 0.0
			for gv: float in gs:
				mu += gv
			mu /= gs.size()
			var va := 0.0
			for gv: float in gs:
				va += (gv - mu) * (gv - mu)
			cv_min = minf(cv_min, sqrt(va / gs.size()) / maxf(mu, 1e-3))
	check("非均勻：近路一列間距變異係數最小 %.2f（≥ 0.2）、同種連排最長 %d（≤ 2）" % [cv_min, run_max], cv_min >= 0.2 and run_max <= 2)
	# ── 7 共存：新樹幹 vs R2 樹幹淨距、樹冠不疊心
	var clash: Array = []
	for it: Dictionary in trees:
		var id := String(it["id"])
		var sc: float = (it["sc"] as Vector3).x
		var tr := SG.trunk_r(id, sc, M)
		for t: Array in P["sealed"]:
			var d := (it["p"] as Vector2).distance_to(t[0])
			if float(t[4]) > 0.0 and tr > 0.0 and d < tr + float(t[4]) + 0.5:
				clash.append("%s↔%s" % [id, t[1]])
	check("共存：新植栽樹幹 vs R2 林帶樹幹淨距 ≥ 0.5 m：違規 %d %s" % [clash.size(), ", ".join(clash.slice(0, 3))], clash.is_empty())
	# ── 8 注連繩：繩心到御神木樹皮三角面（LOD0 實際網格，獨立於截面估計）距離 − 繩半徑 ∈ [−0.03, 0.15]（不陷入、不懸空）；高 2.2–3.0
	var gos: Dictionary = {}
	for it: Dictionary in items:
		if String(it["tag"]) == "goshinboku":
			gos = it
	var path := SG.rope_path(gos, P["rope"])
	var bark := _bark_tris("sugi_hero", SG.xf_of(gos), float(P["rope"]["h"]) * (gos["sc"] as Vector3).y + float(gos["y"]))
	var gmin := INF
	var gmax := -INF
	for q: Vector3 in path:
		var dmin := INF
		for k in range(0, bark.size(), 3):
			dmin = minf(dmin, q.distance_to(_closest_tri(q, bark[k], bark[k + 1], bark[k + 2])))
		gmin = minf(gmin, dmin - SG.ROPE_R)
		gmax = maxf(gmax, dmin - SG.ROPE_R)
	var gp: Vector2 = gos["p"]
	var hh := float(P["rope"]["h"]) * (gos["sc"] as Vector3).y + float(gos["y"]) - S.h(gp.x, gp.y)
	check("注連繩：繩 %d 點到御神木樹皮面淨距 %.3f–%.3f m（−0.03–0.15）、離中心地面 %.2f m（1.4–2.0）" % [path.size(), gmin, gmax, hh],
		gmin >= -0.03 and gmax <= 0.15 and hh >= 1.4 and hh <= 2.0)
	# ── 9 元素齊全
	var have := {}
	for it: Dictionary in items:
		var id := String(it["id"])
		for k: String in ["sugi_a", "sugi_b", "sugi_c", "sugi_hero", "hinoki", "shii_a", "young_sugi", "fern_a", "sasa_a", "shrub_a",
				"log_a", "gk_toro_kasuga"]:
			if id.begins_with(k):
				have[k] = int(have.get(k, 0)) + 1
	check("元素：%s" % str(have), have.size() >= 11 and int(have.get("gk_toro_kasuga", 0)) >= 4 and int(have.get("sugi_hero", 0)) == 1)
	rep["elements"] = have
	info("植栽 %d（高木 %d、林下 %d）、構件 %d" % [trees.size(), canopy.size(), trees.size() - canopy.size(), items.size() - trees.size()])
	for it: Dictionary in items:
		if String(it["tag"]) in ["gate_sugi", "goshinboku"]:
			info("%s %s @(%.1f,%.1f) sc %.2f" % [it["tag"], it["id"], (it["p"] as Vector2).x, (it["p"] as Vector2).y, (it["sc"] as Vector3).x])
	return rep


# ─────────────────────────── 掛載 ───────────────────────────

func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if txt.is_empty():
		push_error("讀不到 " + SCENE)
		return 1
	if txt.contains("gen/shrine_grove_p9.scn"):
		push_error("已經掛過 ShrineGroveP9")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var done := false
	var i := 0
	while i < lines.size():
		var ln := lines[i]
		out.append(ln)
		if not done and ln.begins_with("[node name=\"HiedaGardenP9\" parent=\"Vegetation\""):
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"ShrineGroveP9\" parent=\"Vegetation\" instance=ExtResource(\"p9r42_shrine_grove\")]")
			out.append("")
			done = true
			continue
		i += 1
	if not done:
		push_error("找不到 Vegetation/HiedaGardenP9（順序須為 ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9）")
		return 1
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p9r42_shrine_grove\"]" % SG.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[SHRINE] attach：加 Vegetation/ShrineGroveP9 → %s" % SCENE)
	return 0


# ─────────────────────── 實走（P11 R1 limited verifier correction 2026-10-10） ───────────────────────
## 旧版：膠囊の基準高さ＝地形 S.h 固定。P10 R6b の參道（root/ShrineApproachP10、石段＋踊り場の斜坡碰撞 RampCollision）は地形より
##   0.51–0.94 m 高い歩行面で、旧版はその上を歩く膠囊を「斜坡に埋まる」として 40／179 点を被擋と判定していた
##   （docs/art_review/village_v2_p11/r1/diag/known3.json：歩行面基準では被擋 0）。
## 修正：基準高さ＝その点の「歩行面」＝下向き射線で最初に当たる地形、または登記歩行面（WALKABLE：ShrineApproachP10 の RampCollision だけ）。
##   それ以外の物体（構件・樹幹・建物・未登記の台）は従来どおり障害（射線はそれを越えて下の歩行面を探し、膠囊はその物体に当たる）。
##   追加（旧版になかった検査）：隣接標本 0.5 m の歩行面段差 ≤ STEP_MAX（斜坡の継ぎ目・踊り場の縁で段差が跳ねないこと）。
##   膠囊 r 0.3 h 1.7・底 ＝歩行面＋0.55（旧版と同じ余裕）・ルート・標本間隔・鳥居の除外は旧版と同じ。
const WALKABLE := [["ShrineApproachP10", "RampCollision"]]
const STEP_MAX := 0.45

func _walk_base(v: Node3D, space: PhysicsDirectSpaceState3D, terrain: StaticBody3D, p: Vector2, h: float) -> Array:
	var ex: Array[RID] = []
	for k in 16:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 3.0, p.y), Vector3(p.x, h - 3.0, p.y))
		q.exclude = ex
		var r := space.intersect_ray(q)
		if r.is_empty():
			break
		var col := r["collider"] as Node
		if col == terrain:
			return [float((r["position"] as Vector3).y), "terrain"]
		var path := String(v.get_path_to(col))
		for w: Array in WALKABLE:
			if path.begins_with(String(w[0]) + "/") and String(col.name) == String(w[1]):
				return [float((r["position"] as Vector3).y), "walkable"]
		ex.append(r["rid"])
	return [h, "terrain"]

func _walk_check(v: Node3D, L: Dictionary, S: Object, space: PhysicsDirectSpaceState3D, terrain: StaticBody3D) -> Dictionary:
	var road: Array = SG.road_pts(L)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var blocked: Array = []
	var steps: Array = []
	var probes := 0
	var n_t := 0
	var n_w := 0
	var routes: Array = [road.slice(1), [Vector2(266.0, -208.0), Vector2(258.0, -214.0), Vector2(258.0, -221.5)],
		[Vector2(250.5, -216.0), Vector2(266.0, -216.0)]]
	for route: Array in routes:
		var prev := NAN
		for e: Array in GL.resample(route, 0.5):
			var p: Vector2 = e[0]
			if SG.TORII_BOX.grow(0.2).has_point(p) and absf((p - SG.TORII).dot(Vector2(0.927, 0.375))) > 1.6:
				prev = NAN
				continue
			var wb := _walk_base(v, space, terrain, p, S.h(p.x, p.y))
			var base: float = wb[0]
			if String(wb[1]) == "walkable":
				n_w += 1
			else:
				n_t += 1
			if not is_nan(prev) and absf(base - prev) > STEP_MAX:
				steps.append("(%.1f,%.1f) %+.2f m" % [p.x, p.y, base - prev])
			prev = base
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cap
			qp.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, base + 0.3 + 0.85 + 0.25, p.y))
			qp.exclude = [terrain.get_rid()]
			probes += 1
			var r := space.intersect_shape(qp, 1)
			if not r.is_empty():
				blocked.append("(%.1f,%.1f) %s" % [p.x, p.y, (r[0]["collider"] as Node).name])
	return {"probes": probes, "blocked": blocked, "steps": steps, "on_terrain": n_t, "on_walkable": n_w}

## 永久反向（場景級・記憶體のみ）：各案で _walk_check が FAIL になること。
##   N1 參道の歩行面に 0.6×1.2×0.6 m の箱（障害）→ 被擋
##   N2 參道の斜坡碰撞を 0.8 m 持ち上げる（歩行面の継ぎ目に段差）→ 段差
##   N3 未登記の「台」（歩行面の 0.7–0.9 m 上の板、別の親）を参道に置く → 被擋（登記外の面は歩行面として扱わない）
func _scene_negatives(v: Node3D, L: Dictionary) -> int:
	for i in 4:
		await physics_frame
	var space := v.get_world_3d().direct_space_state
	var terrain := v.get_node("Collision/TerrainCollision") as StaticBody3D
	var S := RLib.terrain_sampler(v)
	var W0 := _walk_check(v, L, S, space, terrain)
	var clean := (W0["blocked"] as Array).is_empty() and (W0["steps"] as Array).is_empty()
	print("[SHRINE] NEG 対照（無改変）：被擋 %d 段差 %d → %s" % [(W0["blocked"] as Array).size(), (W0["steps"] as Array).size(), "PASS" if clean else "FAIL"])
	var miss := 0 if clean else 1
	var p0 := Vector2(285.7, -175.8)
	var y0: float = _walk_base(v, space, terrain, p0, S.h(p0.x, p0.y))[0]
	for n in 3:
		var tamper: Node3D = null
		var ramp := v.find_child("RampCollision", true, false) as Node3D
		var ramp_xf := ramp.global_transform if ramp else Transform3D()
		if n == 0 or n == 2:
			var sb := StaticBody3D.new()
			sb.name = "NegObstacle" if n == 0 else "NegUnregisteredDeck"
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(0.6, 1.2, 0.6) if n == 0 else Vector3(2.0, 0.2, 3.0)
			cs.shape = bx
			sb.add_child(cs)
			v.add_child(sb)
			sb.global_position = Vector3(p0.x, y0 + (0.6 if n == 0 else 0.8), p0.y)
			tamper = sb
		else:
			ramp.global_transform = ramp_xf.translated(Vector3(0, 0.8, 0))
		for i in 3:
			await physics_frame
		var W := _walk_check(v, L, S, space, terrain)
		var tripped := not (W["blocked"] as Array).is_empty() or not (W["steps"] as Array).is_empty()
		var nm: String = ["N1 參道の歩行面に箱（障害）", "N2 斜坡碰撞を 0.8 m 持ち上げ（継ぎ目の段差）", "N3 未登記の台を参道に置く"][n]
		print("[SHRINE] NEG %s：被擋 %d 段差 %d → %s" % [nm, (W["blocked"] as Array).size(), (W["steps"] as Array).size(), "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			miss += 1
		if tamper:
			tamper.get_parent().remove_child(tamper)
			tamper.free()
		else:
			ramp.global_transform = ramp_xf
		for i in 3:
			await physics_frame
	print("[SHRINE] 結果：%d 項失敗（scene negatives）" % miss)
	return miss

# ─────────────────────────── 場景級驗證（已掛載） ───────────────────────────

func _scene(v: Node3D, L: Dictionary) -> void:
	var go := v.get_node_or_null("Vegetation/" + SG.NODE_NAME) as Node3D
	var order_ok := true
	var names: Array = []
	for c in v.get_node("Vegetation").get_children():
		names.append(String(c.name))
	for pair: Array in [["ForestP9", "BambooP9"], ["BambooP9", "HiedaGardenP9"], ["HiedaGardenP9", "ShrineGroveP9"]]:
		if not (pair[0] in names and pair[1] in names) or names.find(pair[0]) > names.find(pair[1]):
			order_ok = false
	check("場景已掛 Vegetation/%s，順序 ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9：%s" % [SG.NODE_NAME, str(names)], go != null and order_ok)
	if go == null:
		return
	for i in 4:
		await physics_frame
	var space := v.get_world_3d().direct_space_state
	var terrain := v.get_node("Collision/TerrainCollision") as StaticBody3D
	var S := RLib.terrain_sampler(v)
	# 1 射線接地：樹／林下／構件 origin 正下方只認地形
	var fl := 0
	var n := 0
	var worst := 0.0
	for grp: String in ["Trees", "Under", "Props"]:
		for node in go.get_node(grp).get_children():
			var p := (node as Node3D).global_position
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 3, 0), p - Vector3(0, 3, 0))
			var ex: Array[RID] = []
			var y_hit := NAN
			for k in 8:
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
			var gap := p.y - y_hit
			worst = maxf(worst, gap)
			if gap > 0.06 and not String(node.name).contains("log_a"):
				fl += 1
	var n_all := 0
	for grp: String in ["Trees", "Under", "Props"]:
		n_all += go.get_node(grp).get_child_count()
	check("場景接地（%d／%d 件 origin 向下射線只認地形）：浮 > 0.06 m %d（最大 %.3f）" % [n, n_all, fl, worst], fl == 0 and n == n_all and n > 0)
	# 2 碰撞：新樹幹／燈籠 vs 地標／建物／R2 樹幹／其他（排除地形與本 overlay）
	var hits := {}
	var own_rids: Array[RID] = [terrain.get_rid()]
	for sb in go.find_children("*", "StaticBody3D", true, false):
		own_rids.append((sb as StaticBody3D).get_rid())
	for sb in go.find_children("*", "StaticBody3D", true, false):
		for cs in sb.get_children():
			if not (cs is CollisionShape3D):
				continue
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = (cs as CollisionShape3D).shape
			qp.transform = (cs as CollisionShape3D).global_transform
			qp.exclude = own_rids
			for r: Dictionary in space.intersect_shape(qp, 4):
				var key := String(v.get_path_to(r["collider"] as Node))
				hits[key.get_slice("/", 0) + "/" + key.get_slice("/", 1) + "/" + key.get_slice("/", 2) + " ← " + String(sb.get_parent().name)] = 1
	check("碰撞：新樹幹／燈籠 vs 地標／建物／R2–R4 植被／其他接觸 %s" % (str(hits.keys().slice(0, 5)) if hits else "0"), hits.is_empty())
	# 3 實走：參道（鳥居南 → 終點）＋前庭橫走，膠囊 r 0.3 h 1.7（只排除地形）
	var W := _walk_check(v, L, S, space, terrain)
	check("實走：參道＋前庭膠囊 %d 點被擋 %d %s；歩行面の隣接段差 > %.2f m %d %s（歩行面＝地形 %d 点・登記歩行面 %d 点）" % [W["probes"], (W["blocked"] as Array).size(),
		", ".join((W["blocked"] as Array).slice(0, 3)), STEP_MAX, (W["steps"] as Array).size(), ", ".join((W["steps"] as Array).slice(0, 3)), W["on_terrain"], W["on_walkable"]],
		(W["blocked"] as Array).is_empty() and (W["steps"] as Array).is_empty())
	var nmesh := go.find_children("*", "MeshInstance3D", true, false).size()
	info("ShrineGroveP9：%s 件、MeshInstance %d、構件碰撞 %s" % [go.get_meta("items", "?"), nmesh, go.get_meta("shapes", "?")])


# ─────────────────────────── 審圖鏡位 ───────────────────────────

const HIDE := ["Debug", "Portals", "QuestAnchors", "Districts/LandmarkParcelLines", "Districts/AuxParcelLines"]
## [名稱, 相機 xz, 眼高, 看向 xz, 看向高（相對地面）]
const SHOTS := [
	["p9r42_torii_out", Vector2(296.5, -142.0), EYE, Vector2(272.0, -200.0), 8.0],
	["p9r42_torii_near", Vector2(292.2, -156.0), EYE, Vector2(278.0, -194.0), 6.0],
	["p9r42_torii_in_back", Vector2(286.2, -176.0), EYE, Vector2(298.0, -136.0), 1.6],
	["p9r42_approach_mid", Vector2(281.6, -186.5), EYE, Vector2(266.0, -212.0), 5.0],
	["p9r42_shrine_front", Vector2(258.6, -212.0), EYE, Vector2(258.0, -228.0), 3.4],
	["p9r42_goshinboku", Vector2(262.6, -216.2), EYE, Vector2(271.0, -223.0), 1.6],
	["p9r42_forecourt_back", Vector2(258.0, -221.5), EYE, Vector2(270.0, -200.0), -1.0],
	["p9r42_side_forest", Vector2(304.5, -190.0), EYE, Vector2(290.0, -178.0), 1.2],
	["p9r42_side_forest_w", Vector2(272.0, -186.0), EYE, Vector2(262.0, -176.0), 0.8],
]
const HIGH := [
	["p9r42_high", Vector3(345.0, 75.0, -140.0), Vector3(270.0, 14.0, -195.0)],
	["p9r42_high_w", Vector3(200.0, 70.0, -150.0), Vector3(268.0, 16.0, -200.0)],
	["p9r42_top", Vector3(272.0, 140.0, -184.0), Vector3(272.0, 0.0, -185.5)],
	["p9r42_village_view", Vector3(318.0, 4.6, -112.0), Vector3(262.0, 28.0, -222.0)],
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
		eb["hide"] = HIDE + ["Vegetation/" + SG.NODE_NAME]
		before.append(eb)
		after.append(e)
	for s: Array in HIGH:
		var c: Vector3 = s[1]
		var l: Vector3 = s[2]
		var e := {"name": String(s[0]), "cam": [c.x, c.y, c.z], "look": [l.x, l.y, l.z], "hud": false, "time": 10, "hide": HIDE}
		var eb := e.duplicate(true)
		eb["hide"] = HIDE + ["Vegetation/" + SG.NODE_NAME]
		before.append(eb)
		after.append(e)
	for pair: Array in [["res://tools/shots/village_v2_p9r42_shrine_before.json", before], ["res://tools/shots/village_v2_p9r42_shrine_after.json", after]]:
		var f := FileAccess.open(String(pair[0]), FileAccess.WRITE)
		f.store_string(JSON.stringify(pair[1], " ", false))
		f.close()
		print("[SHRINE] 寫入 %s（%d 張）" % [pair[0], (pair[1] as Array).size()])
	v.free()
	return 0


func _bark_tris(id: String, xf: Transform3D, y_world: float) -> PackedVector3Array:
	var t: Node3D = (load(SG.TREES + id + ".tscn") as PackedScene).instantiate()
	var am := (t.get_node("LOD0") as MeshInstance3D).mesh as ArrayMesh
	var arr := am.surface_get_arrays(0)
	t.free()
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var out := PackedVector3Array()
	for k in range(0, I.size(), 3):
		var a := xf * V[I[k]]
		var b := xf * V[I[k + 1]]
		var c := xf * V[I[k + 2]]
		if minf(a.y, minf(b.y, c.y)) <= y_world + 0.3 and maxf(a.y, maxf(b.y, c.y)) >= y_world - 0.3:
			out.append_array([a, b, c])
	return out


func _closest_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


# ─────────────────────────── 封存（--seal，P9 R4-2 神社周邊 ART_APPROVED 2026-10-02） ───────────────────────────

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
	check("P9 R4-2 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 總表 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var txt := FileAccess.get_file_as_string(SCENE)
	var idx: Array = []
	for nm: String in ["ForestP9", "BambooP9", "HiedaGardenP9", "ShrineGroveP9"]:
		idx.append(txt.find("[node name=\"%s\" parent=\"Vegetation\"" % nm))
	var ord_ok: bool = int(idx[0]) >= 0 and int(idx[1]) > int(idx[0]) and int(idx[2]) > int(idx[1]) and int(idx[3]) > int(idx[2])
	check("village_v2.tscn 掛載 Vegetation/ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9（%s）" % SG.OUTPUT,
		ord_ok and txt.contains(SG.OUTPUT))
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[SHRINE] 結果：%d 項失敗（seal）" % fails)
	return fails
