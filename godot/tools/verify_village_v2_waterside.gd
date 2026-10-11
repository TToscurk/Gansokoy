extends SceneTree
## 人間之里 V2 P9 R4-4：水車／龍神像周邊 規劃 gate＋烘焙＋掛載＋場景級驗證＋審圖鏡位。
##   規劃＋gate（唯讀）：Godot --headless --path godot --script res://tools/verify_village_v2_waterside.gd
##   反向：             ... -- --neg=float|road|hero|sight|uniform|conifer|rope|mill；-- --negatives 一次跑完
##   烘焙 overlay：     ... --headless ... -- --build
##   掛進場景：         ... --headless ... -- --attach（在 Vegetation/SchoolYardP9 後加 WatersideP9；先確認 Editor 無 unsaved、F5 已停）
##   場景驗證：         ... --headless ... -- --scene（掛載順序、射線接地、碰撞 vs Hero／橋／建物／農地、walkway／參拜道膠囊實走）
##   封存：             ... --headless ... -- --seal（data/village_v2_p9r44_seal.json 雜湊＋掛載順序＋竄改反向；P9 R4-4 ART_APPROVED 2026-10-03）
## 每項一行 [WATER] PASS/FAIL；INFO 不計失敗；結尾 quit(失敗項數)。

const WS := preload("res://tools/village_v2_waterside_lib.gd")
const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const REPORT := "res://data/village_v2_p9r44_waterside.json"
const SEAL := "res://data/village_v2_p9r44_seal.json"
const EYE := 1.7
const ORDER := ["ForestP9", "BambooP9", "HiedaGardenP9", "ShrineGroveP9", "SchoolYardP9", "WatersideP9"]
## P12 FINAL CLOSURE（使用者 2026-10-12 授權）：P11 R2C の河岸 RB_11_-7 局部重烘で、同 seed 再計算の計画が封存実物から漂移
## （計画上の wk_reed_s が水車入口帯へ）。蘆葦は再生成しない。以下が「全部」一致する時だけ、この 1 件の計画障害を容認：
## 障害集合が登記どおり／上游 2 檔・封存 overlay の雜湊／計画全体の摘要（他の漂移は不可）／封存実物の対応ノードが同じ判定で通路外。
const P12_DRIFT := {
	"blocked": ["wk_reed_s@(329.7,-47.2)"],
	"plan_digest": "f53d2d2a1f6f2003cf6e5877a1a399fe313aba705548673a8b160a697533d3bf",
	"upstream": {"res://maps/village_v2/gen/riverbank_rb_11_m7_lod0.res": "22f4f3abf480c331bb0fd2ebac871688f409f99a60999a5fbdfc26433f713002",
		"res://maps/village_v2/gen/riverbank_rb_11_m7_lod1.res": "811d0d9d2a6463d3b057143f2a73faa4e458e2d35779b5123c80037dbb538930"},
	"baked": {"res://maps/village_v2/gen/waterside_p9.scn": "8fc80e8882383b6dfb8e3de18c641d6059b007fae9e770683d5ea991a118b21c"},
	"baked_node": "Plants/120_wk_reed_s", "baked_pos": [328.75, -45.25],
}
var _baked_cache: Node3D = null

var fails := 0
var neg := ""
var failed_labels: Array = []
var quiet := false


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[WATER] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(label: String) -> void:
	if not quiet:
		print("[WATER] INFO " + label)


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
		print("[WATER] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var old := v.get_node_or_null("Vegetation/" + WS.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	root.add_child(v)
	await physics_frame
	await physics_frame
	var P: Dictionary = WS.plan(v, L)
	info("規劃 %d 件（%d ms）" % [(P["items"] as Array).size(), P["ms"]])
	if "--negatives" in args:
		var target := {"float": "接地", "road": "動線淨空", "hero": "Hero 淨空", "sight": "視線", "uniform": "河岸植生", "conifer": "植被語彙",
			"rope": "注連繩", "mill": "作業場"}
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
			print("[WATER] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d）" % ["PASS" if hit else "FAIL", nm, target[nm], failed_labels.size()])
			if not hit:
				bad += 1
		print("[WATER] 結果：%d 項失敗（negatives）" % bad)
		quit(bad)
		return
	if neg != "":
		_inject(P)
	var rep := _checks(P)
	if neg != "":
		print("[WATER] negative=%s 失敗 %d 項" % [neg, fails])
		quit(fails)
		return
	if "--build" in args and fails == 0:
		var r := WS.bake(P)
		WS.own(r, r)
		var ps := PackedScene.new()
		check("pack overlay", ps.pack(r) == OK)
		check("save %s" % WS.OUTPUT, ResourceSaver.save(ps, WS.OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK)
		rep["overlay"] = {"path": WS.OUTPUT, "mb": FileAccess.get_file_as_bytes(WS.OUTPUT).size() / 1048576.0,
			"items": r.get_meta("items"), "shapes": r.get_meta("shapes")}
		info("overlay %.2f MB、%d 件、構件碰撞 %d" % [rep["overlay"]["mb"], rep["overlay"]["items"], rep["overlay"]["shapes"]])
		r.free()
		var f := FileAccess.open(REPORT, FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, "  ", false))
		f.close()
	print("[WATER] 結果：%d 項失敗" % fails)
	quit(fails)


func _inject(P: Dictionary) -> void:
	var items: Array = P["items"]
	var S: RLib.TriSampler = P["S"]
	match neg:
		"float":
			for it: Dictionary in items:
				if String(it["id"]) == "wk_sonae":
					it["y"] = float(it["y"]) + 0.4
		"road":
			items.append(WS.item(S, "mesh", "wk_tawara3", Vector2(378.0, -188.0), 0.0, 1.0, "dragon_offering"))
		"hero":
			items.append(WS.item(S, "tree", "yanagi_b", Vector2(326.2, 4.6), 0.0, 0.8, "ww2_willow", {"preset": "young"}))
		"sight":
			items.append(WS.item(S, "tree", "yanagi_a", Vector2(393.4, -199.2), 0.0, 1.0, "dragon_willow", {"preset": "mature"}))
		"uniform":
			var n := 0
			var x := 360.0
			while x < 378.0:
				items.append(WS.item(S, "plant", "wk_reed", Vector2(x, -214.0), 0.0, 1.0, "dragon_bank"))
				x += 1.0
				n += 1
		"conifer":
			items.append(WS.item(S, "tree", "sugi_a", Vector2(362.0, -214.0), 0.0, 0.8, "dragon_willow", {"preset": "mature"}))
		"rope":
			var pr: Array = P["rope"]["prof"]
			for k in pr.size():
				pr[k] = float(pr[k]) + 0.35
		"mill":
			# 石臼を柳の樹冠下・水際へ寄せ、1.4 倍に拡大（＝今回禁止した解決法）
			for it: Dictionary in items:
				if String(it["id"]) == "wk_usu" and String(it["tag"]) == "ww2_mill":
					it["p"] = Vector2(320.6, -8.4)
					it["sc"] = Vector3.ONE * 1.4


func _checks(P: Dictionary) -> Dictionary:
	var S: RLib.TriSampler = P["S"]
	var R: RLib.TriSampler = P["R"]
	var M: Dictionary = P["M"]
	var H: Dictionary = P["H"]
	var W: WS.WaterQ = P["W"]
	var SB: WS.PtBins = P["SB"]
	var items: Array = P["items"]
	var rep := {"date": Time.get_datetime_string_from_system(), "items": items.size()}
	var trees: Array = items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "tree" and not (String(it["id"]) in WS.UNDER_IDS))
	var plants: Array = items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "plant")
	var props: Array = items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "mesh" and not (String(it["id"]) in WS.STONE_IDS))
	# ── 1 接地：樹／構件 origin ≤ 環最低地面＋0.005、埋 ≤ 0.45（御神木＝板根 conform；濕石＝半埋 0.08–0.4；植物＝地表−0.04）
	var fl := 0
	var dp := 0
	var worst := 0.0
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		var y := float(it["y"])
		var id := String(it["id"])
		var h := S.h(p.x, p.y)
		if String(it["tag"]) == "goshinboku":
			if y > h + 0.005 or h - y > 2.2:
				fl += 1
			continue
		if id in WS.STONE_IDS:
			var e := h - y
			if e < 0.05 or e > 0.45:
				fl += 1
			continue
		if String(it["kind"]) == "plant":
			if absf(y - (h - 0.04)) > 0.02:
				fl += 1
				worst = maxf(worst, y - h)
			continue
		var r := 0.25
		if String(it["kind"]) == "tree" and not (id in WS.UNDER_IDS):
			r = maxf(SG.trunk_r(id, (it["sc"] as Vector3).x, M) * 0.7, 0.12)
		elif WS.PROP_BOX.has(id):
			r = minf(float(WS.PROP_BOX[id][0]), float(WS.PROP_BOX[id][1])) * (it["sc"] as Vector3).x
		var lo := GL.ground(S, p, r)
		if y > lo + 0.005:
			fl += 1
			worst = maxf(worst, y - lo)
		if h - y > 0.45:
			dp += 1
	check("接地：%d 件（御神木板根、濕石半埋、植物貼地、樹／構件環最低）：浮／偏 %d（最大 %.2f m）、過深 %d" % [items.size(), fl, worst, dp], fl == 0 and dp == 0)
	# ── 2 不穿：樹幹／構件 vs Hero 碰撞／橋／建物／農地／P7 石積頂點（植物除外）
	var clip: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if String(it["kind"]) == "plant" or id in WS.STONE_IDS:
			continue
		var p: Vector2 = it["p"]
		var pts := PackedVector2Array([p])
		var r := 0.0
		if String(it["kind"]) == "mesh":
			pts = WS.prop_corners(it)
			pts.append(p)
		elif not (id in WS.UNDER_IDS):
			r = SG.trunk_r(id, (it["sc"] as Vector3).x, M) + 0.25
		for q in pts:
			var bad := false
			for b: Rect2 in H["boxes"]:
				bad = bad or b.grow(0.1 + r).has_point(q)
			for b: Rect2 in P["obs"]:
				bad = bad or b.grow(0.1 + r).has_point(q)
			if String(it["kind"]) == "tree" and not (id in WS.UNDER_IDS):
				bad = bad or SB.near(q, r + 0.3, S.h(q.x, q.y) - 0.3)
			if bad:
				clip.append("%s@(%.1f,%.1f)" % [id, p.x, p.y])
				break
	check("不穿：樹幹／構件 vs Hero 碰撞・橋・建物・農地・河岸石積：違規 %d %s" % [clip.size(), ", ".join(clip.slice(0, 4))], clip.is_empty())
	# ── 3 動線淨空：道路、水車 walkway＋入口、龍神像參拜道＋walkway 內無樹／構件（地面植物以叢判，半徑 0.4）
	var block: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if String(it["tag"]) == "dragon_offering" and id == "wk_sonae":
			pass
		var pts := WS.prop_corners(it) if String(it["kind"]) == "mesh" else PackedVector2Array([it["p"]])
		var rr := 0.4 if String(it["kind"]) == "plant" else 0.0
		for q in pts:
			if WS._blocked(q, rr, R, {"boxes": [], "walkways": H["walkways"], "entries": H["entries"], "dragon_walkway": H["dragon_walkway"]}, []):
				block.append("%s@(%.1f,%.1f)" % [id, (it["p"] as Vector2).x, (it["p"] as Vector2).y])
				break
	var dr := _drift_ok(P, block, P12_DRIFT)
	check("動線淨空：道路／水車 walkway＋入口／龍神像參拜道＋walkway 內障礙 %d %s（P12 封存差異登記：%s）" % [block.size(), ", ".join(block.slice(0, 4)),
		"適用" if (not block.is_empty() and dr.is_empty()) else ("—" if block.is_empty() else "不適用 " + str(dr))], block.is_empty() or dr.is_empty())
	if not quiet and not block.is_empty() and dr.is_empty():
		var d1 := P12_DRIFT.duplicate(true)
		d1["upstream"][d1["upstream"].keys()[0]] = "0".repeat(64)
		var d2 := P12_DRIFT.duplicate(true)
		d2["baked"][d2["baked"].keys()[0]] = "0".repeat(64)
		var d3 := P12_DRIFT.duplicate(true)
		d3["plan_digest"] = "0".repeat(64)
		var d4 := P12_DRIFT.duplicate(true)
		d4["baked_pos"] = [329.695, -47.189]
		check("反向（P12 差異登記）：上游雜湊／封存 overlay 雜湊／計画摘要／実物位置の竄改、障害 1 件追加 → それぞれ不適用",
			not _drift_ok(P, block, d1).is_empty() and not _drift_ok(P, block, d2).is_empty() and not _drift_ok(P, block, d3).is_empty()
			and not _drift_ok(P, block, d4).is_empty() and not _drift_ok(P, block + ["wk_reed@(1.0,1.0)"], P12_DRIFT).is_empty())
	# ── 4 Hero 淨空（layout keep_clear）：水車 r 6.0 內無樹／構件、植物 ≥ 4.5；龍神像 r 12 內無樹
	var hc: Array = []
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		var kind := String(it["kind"])
		for wc: Vector2 in WS.WHEELS:
			var dd := p.distance_to(wc)
			if (kind != "plant" and dd < WS.WHEEL_CLEAR and not (String(it["id"]) in WS.STONE_IDS)) or (kind == "plant" and dd < 4.5):
				hc.append("%s@(%.1f,%.1f)" % [it["id"], p.x, p.y])
		if kind == "tree" and not (String(it["id"]) in WS.UNDER_IDS) and p.distance_to(WS.DRAGON) < WS.DRAGON_TREE_CLEAR:
			hc.append("%s@(%.1f,%.1f)" % [it["id"], p.x, p.y])
	check("Hero 淨空：水車 r %.0f m 內樹／構件 0、植物 ≥ 4.5 m；龍神像 r %.0f m 內樹 0：違規 %d %s" % [WS.WHEEL_CLEAR, WS.DRAGON_TREE_CLEAR,
		hc.size(), ", ".join(hc.slice(0, 4))], hc.is_empty())
	# ── 5 視線：龍神像（龍神橋／參拜道／RiverNorthPath／對岸）、水車（橋／西岸）→ 新樹冠／樹幹不擋
	var cams := [[Vector3(399.0, 3.9, -205.0), "dragon"], [Vector3(372.0, S.h(372, -176) + EYE, -176.0), "dragon"],
		[Vector3(367.0, S.h(367, -165) + EYE, -165.0), "dragon"], [Vector3(376.0, S.h(376, -188) + EYE, -188.0), "dragon"],
		[Vector3(336.0, 3.8, -34.0), "ww1"], [Vector3(323.0, S.h(323, -48) + EYE, -48.0), "ww1"],
		[Vector3(317.0, S.h(317, 1) + EYE, 1.0), "ww2"], [Vector3(338.0, S.h(338, -14) + EYE, -14.0), "ww2"],
		[Vector3(321.0, 3.8, 42.0), "ww3"], [Vector3(297.0, S.h(297, 57) + EYE, 57.0), "ww3"]]
	var tg := {"dragon": [Vector3(388.0, 4.0, -188.0), Vector3(388.0, 8.0, -188.0), Vector3(387.7, 11.4, -187.4)]}
	for k in 3:
		var hub: Vector3 = (H["hubs"] as Array)[k]
		tg["ww%d" % (k + 1)] = [hub, hub + Vector3(0, 2.6, 0), hub + Vector3(0, -1.6, 0)]
	var blk: Array = []
	for it: Dictionary in trees:
		var cyl := SG.crown_cyl(it, M)
		var sc: float = (it["sc"] as Vector3).x
		var tcyl := [it["p"], SG.trunk_r(String(it["id"]), sc, M) + 0.05, float(it["y"]), float(it["y"]) + float(M[it["id"]]["height"]) * sc * 0.45]
		for c: Array in cams:
			for t: Vector3 in tg[c[1]]:
				if SG.seg_hits(c[0], t, cyl) or SG.seg_hits(c[0], t, tcyl):
					blk.append("%s@(%.1f,%.1f)→%s" % [it["id"], (it["p"] as Vector2).x, (it["p"] as Vector2).y, c[1]])
	check("視線：%d 機位 → 龍神像／水車 3 點被新樹擋 %d %s" % [cams.size(), blk.size(), ", ".join(blk.slice(0, 3))], blk.is_empty())
	# ── 6 河岸植生：各 site 有叢（≥ 4）且不成連續壁（同列 1.2 m 內相鄰 ≥ 6 株的直線串 0）；植物不在深水（深 ≤ 0.4）
	var per := {}
	for it: Dictionary in plants:
		var k := String(it["tag"]).trim_suffix("_bank")
		per[k] = int(per.get(k, 0)) + 1
	var deep := plants.filter(func(it: Dictionary) -> bool: return W.depth(it["p"]) > 0.4).size()
	var wall := 0
	for it: Dictionary in plants:
		var chain := 0
		for o: Dictionary in plants:
			if o != it and (o["p"] as Vector2).distance_to(it["p"]) < 1.25:
				chain += 1
		if chain >= 2:
			wall += 1
	var few: Array = []
	for k: String in WS.SITES:
		if int(per.get(k, 0)) < 4:
			few.append(k)
	# 連續壁＝蘆（大）が 1.6 m 以内に 3 株以上並ぶ直線串（叢は混種なので許容）
	var reeds: Array = plants.filter(func(it: Dictionary) -> bool: return String(it["id"]) == "wk_reed")
	var wall2 := 0
	for it: Dictionary in reeds:
		var nb := reeds.filter(func(o: Dictionary) -> bool: return o != it and (o["p"] as Vector2).distance_to(it["p"]) < 1.6).size()
		if nb >= 2:
			wall2 += 1
	var wall_r := float(wall2) / maxf(reeds.size(), 1)
	check("河岸植生：各 site 株數 %s（≥ 4，不足 %s）、深水 %d、大蘆連串（1.6 m 內 ≥ 2 鄰）%d／%d＝%.0f %%（≤ 15 %%，不成連續蘆壁）" % [str(per), str(few),
		deep, wall2, reeds.size(), wall_r * 100], few.is_empty() and deep == 0 and wall_r <= 0.15)
	rep["plants"] = per
	# ── 7 植被語彙：高木＝柳／樟（御神木 ≤ 1）／幼樹；無杉檜；柳 ≥ 4
	var bad_ids: Array = trees.filter(func(it: Dictionary) -> bool: return not (String(it["id"]) in WS.TREE_OK)).map(func(it: Dictionary) -> String: return String(it["id"]))
	var n_yan := trees.filter(func(it: Dictionary) -> bool: return String(it["id"]).begins_with("yanagi")).size()
	var n_kusu := trees.filter(func(it: Dictionary) -> bool: return String(it["tag"]) == "goshinboku").size()
	check("植被語彙：高木 %d（非水邊系 %d %s）、柳 %d（≥ 4）、御神木 %d（≤ 1）" % [trees.size(), bad_ids.size(), str(bad_ids), n_yan, n_kusu],
		bad_ids.is_empty() and n_yan >= 4 and n_kusu <= 1)
	# ── 8 元素
	var have := {}
	for it: Dictionary in items:
		have[String(it["id"])] = int(have.get(String(it["id"]), 0)) + 1
	var need := {"wk_reed": 6, "wk_reed_s": 3, "wk_iris": 2, "wk_sedge": 2, "wk_tawara": 1, "wk_tawara3": 1, "wk_usu": 2, "wk_sonae": 1,
		"gk_toro_kasuga": 2, "kusu_hero": 1}
	var miss: Array = []
	for k: String in need:
		if int(have.get(k, 0)) < int(need[k]):
			miss.append("%s %d/%d" % [k, int(have.get(k, 0)), need[k]])
	check("元素：%s" % ("齊備" if miss.is_empty() else "缺 " + ", ".join(miss)), miss.is_empty())
	# ── 9 注連繩（r4）：繩徑 ≥ 0.30 m（中距 TPS 可讀）；繩心到樟樹皮三角面（LOD0 實際網格）淨距 − 繩半徑 ∈ [−0.03, 0.15]（不陷入、不浮空）
	var gos: Dictionary = {}
	for it: Dictionary in items:
		if String(it["tag"]) == "goshinboku":
			gos = it
	var path := WS.rope_path(gos, P["rope"])
	var y_rope := float(P["rope"]["h"]) * (gos["sc"] as Vector3).y + float(gos["y"])
	var bark := _bark_tris(String(gos["id"]), SG.xf_of(gos), y_rope)
	var gmin := INF
	var gmax := -INF
	for q: Vector3 in path:
		var dmin := INF
		for k in range(0, bark.size(), 3):
			dmin = minf(dmin, q.distance_to(_closest_tri(q, bark[k], bark[k + 1], bark[k + 2])))
		gmin = minf(gmin, dmin - WS.ROPE_R)
		gmax = maxf(gmax, dmin - WS.ROPE_R)
	var gp: Vector2 = gos["p"]
	var hh := y_rope - S.h(gp.x, gp.y)
	check("注連繩：繩徑 %.2f m（≥ 0.30）、繩 %d 點到樟樹皮面淨距 %.3f–%.3f m（−0.03–0.15）、離根元地面 %.2f m（1.2–2.4）" % [WS.ROPE_R * 2.0,
		path.size(), gmin, gmax, hh], WS.ROPE_R * 2.0 >= 0.30 and gmin >= -0.03 and gmax <= 0.15 and hh >= 1.2 and hh <= 2.4)
	rep["rope"] = {"diameter": WS.ROPE_R * 2.0, "gap_min": gmin, "gap_max": gmax, "h_above_ground": hh}
	# ── 10 作業場（r4）：米俵・石臼＝原寸（sc ≤ 1.05，不靠放大）、水際 ≥ 2.5 m、柳樹冠外（日向）、半徑 1.2 m 內無河岸植物（局部留白）、
	#        水車本體 ≥ 7 m（不背暗色水車／影）、組間（俵群↔石臼）中心距 ≥ 2.0 m
	var mills: Array = items.filter(func(it: Dictionary) -> bool: return String(it["tag"]).ends_with("_mill"))
	var mbad: Array = []
	for it: Dictionary in mills:
		var p: Vector2 = it["p"]
		var why := ""
		if (it["sc"] as Vector3).x > 1.05:
			why += "放大"
		if W.depth(p) > -0.3 or W.dist(p, 2.5) <= 2.5:
			why += "水際"
		for wd: Array in P["willows"]:
			if p.distance_to(wd[0]) < float(wd[1]):
				why += "柳下"
		for o: Dictionary in plants:
			if (o["p"] as Vector2).distance_to(p) < 1.2:
				why += "植物"
				break
		var kk := int(String(it["tag"]).substr(2, 1)) - 1
		if p.distance_to(WS.WHEELS[kk]) < 7.0:
			why += "近水車"
		for o: Dictionary in mills:
			if o != it and String(o["tag"]) == String(it["tag"]) and (String(o["id"]) == "wk_usu") != (String(it["id"]) == "wk_usu") 					and (o["p"] as Vector2).distance_to(p) < 2.0:
				why += "留白"
		if why != "":
			mbad.append("%s@(%.1f,%.1f)%s" % [it["id"], p.x, p.y, why])
	check("作業場：米俵・石臼 %d 件（原寸、水際 ≥ 2.5 m、柳樹冠外、1.2 m 內無植物、離水車 ≥ 7 m、俵↔臼 ≥ 2.0 m）：違規 %d %s" % [mills.size(),
		mbad.size(), ", ".join(mbad.slice(0, 4))], mbad.is_empty() and mills.size() >= 7)
	rep["mills"] = mills.map(func(it: Dictionary) -> Array: return [it["id"], it["tag"], [(it["p"] as Vector2).x, (it["p"] as Vector2).y], it["yaw"]])
	rep["elements"] = have
	info("植物 %d、高木 %d、構件 %d" % [plants.size(), trees.size(), props.size()])
	return rep


# ─────────────────────────── 掛載 ───────────────────────────

func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(WS.OUTPUT):
		push_error("找不到 %s（先 --build 成功才可 attach）" % WS.OUTPUT)
		return 1
	if txt.contains("gen/waterside_p9.scn"):
		push_error("已經掛過 WatersideP9")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var done := false
	var i := 0
	while i < lines.size():
		var ln := lines[i]
		out.append(ln)
		if not done and ln.begins_with("[node name=\"SchoolYardP9\" parent=\"Vegetation\""):
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"WatersideP9\" parent=\"Vegetation\" instance=ExtResource(\"p9r44_waterside\")]")
			out.append("")
			done = true
			continue
		i += 1
	if not done:
		push_error("找不到 Vegetation/SchoolYardP9")
		return 1
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p9r44_waterside\"]" % WS.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[WATER] attach：加 Vegetation/WatersideP9 → %s" % SCENE)
	return 0


# ─────────────────────────── 場景級驗證 ───────────────────────────

static func _plan_digest(items: Array) -> String:
	var rows := PackedStringArray()
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		rows.append("%s %.3f %.3f %.3f" % [it["id"], p.x, float(it["y"]), float(it.get("yaw", 0.0))])
	rows.sort()
	return "\n".join(rows).sha256_text()


## 空 Array＝登記どおり（容認可）。理由の列＝不適用
func _drift_ok(P: Dictionary, block: Array, D: Dictionary) -> Array:
	var why: Array = []
	if block != D["blocked"]:
		why.append("障害集合")
	for grp in ["upstream", "baked"]:
		for k: String in D[grp]:
			if FileAccess.get_sha256(k) != String(D[grp][k]):
				why.append(grp + " " + k.get_file())
	var dg := _plan_digest(P["items"])
	if dg != String(D["plan_digest"]):
		why.append("計画摘要 " + dg)
	if _baked_cache == null:
		_baked_cache = (ResourceLoader.load(WS.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var n := _baked_cache.get_node_or_null(String(D["baked_node"])) as Node3D
	if n == null:
		why.append("実物ノードなし")
	else:
		var o := (_baked_cache.transform * (n.get_parent() as Node3D).transform * n.transform).origin
		var bp := Vector2(D["baked_pos"][0], D["baked_pos"][1])
		var H: Dictionary = P["H"]
		if Vector2(o.x, o.z).distance_to(bp) > 0.01:
			why.append("実物位置 %s" % Vector2(o.x, o.z))
		elif WS._blocked(Vector2(o.x, o.z), 0.4, P["R"], {"boxes": [], "walkways": H["walkways"], "entries": H["entries"], "dragon_walkway": H["dragon_walkway"]}, []):
			why.append("実物が通路内")
	return why


func _scene(v: Node3D) -> void:
	var go := v.get_node_or_null("Vegetation/" + WS.NODE_NAME) as Node3D
	var names: Array = []
	for c in v.get_node("Vegetation").get_children():
		names.append(String(c.name))
	var ok := true
	for k in ORDER.size() - 1:
		if not (ORDER[k] in names and ORDER[k + 1] in names) or names.find(ORDER[k]) > names.find(ORDER[k + 1]):
			ok = false
	check("場景已掛 Vegetation/%s，順序 %s：%s" % [WS.NODE_NAME, " → ".join(ORDER), str(names)], go != null and ok)
	if go == null:
		return
	for i in 4:
		await physics_frame
	var space := v.get_world_3d().direct_space_state
	var terrain := v.get_node("Collision/TerrainCollision") as StaticBody3D
	var S := RLib.terrain_sampler(v)
	var fl := 0
	var n := 0
	var n_all := 0
	var worst := 0.0
	for grp: String in ["Trees", "Under", "Props"]:
		for node in go.get_node(grp).get_children():
			n_all += 1
			var p := (node as Node3D).global_position
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 3, 0), p - Vector3(0, 6, 0))
			var ex: Array[RID] = []
			var y_hit := NAN
			for k in 10:
				q.exclude = ex
				var r := space.intersect_ray(q)
				if r.is_empty():
					break
				if (r["collider"] as Node) == terrain:
					y_hit = float((r["position"] as Vector3).y)
					break
				ex.append(r["rid"])
			if is_nan(y_hit):
				continue
			n += 1
			worst = maxf(worst, p.y - y_hit)
			if p.y - y_hit > 0.06:
				fl += 1
	check("場景接地（%d／%d 件樹／構件 origin 向下射線只認地形）：浮 > 0.06 m %d（最大 %.3f）" % [n, n_all, fl, worst], fl == 0 and n == n_all)
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
	check("碰撞：構件箱／樹幹 vs Hero／橋／建物／農地／河岸／其他植被 接觸 %s" % (str(hits.keys().slice(0, 5)) if hits else "0"), hits.is_empty())
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var blocked: Array = []
	var probes := 0
	var routes: Array = [[Vector2(375.4, -188.0), Vector2(381.0, -188.0)], [Vector2(375.0, -194.0), Vector2(380.4, -186.0)]]
	var H := WS.hero_geo(v)
	for k in 3:
		var wk: Array = H["walkways"][k]
		var c: Vector2 = (wk[0] + wk[1] + wk[2] + wk[3]) / 4.0
		routes.append([H["entries"][k], c])
	for route: Array in routes:
		for e: Array in GL.resample(route, 0.5):
			var p: Vector2 = e[0]
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cap
			qp.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, S.h(p.x, p.y) + 0.3 + 0.85 + 0.12, p.y))
			qp.exclude = [terrain.get_rid()]
			probes += 1
			for r: Dictionary in space.intersect_shape(qp, 4):
				var path := String(v.get_path_to(r["collider"] as Node))
				if path.begins_with("Vegetation/" + WS.NODE_NAME):
					blocked.append("(%.1f,%.1f) %s" % [p.x, p.y, path])
	check("實走：龍神像參拜道＋水車入口→walkway 膠囊 %d 點被本 overlay 擋 %d %s" % [probes, blocked.size(), ", ".join(blocked.slice(0, 3))], blocked.is_empty())
	info("WatersideP9：%s 件、MeshInstance %d、構件碰撞 %s" % [go.get_meta("items", "?"), go.find_children("*", "MeshInstance3D", true, false).size(), go.get_meta("shapes", "?")])


## 樟 LOD0 樹皮三角面（繩高 ±0.4 m 帶）：world
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
		if minf(a.y, minf(b.y, c.y)) <= y_world + 0.4 and maxf(a.y, maxf(b.y, c.y)) >= y_world - 0.4:
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
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)


# ─────────────────────────── 封存（--seal，P9 R4-4 水車／龍神像周邊 ART_APPROVED 2026-10-03） ───────────────────────────

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
	check("P9 R4-4 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 總表 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var txt := FileAccess.get_file_as_string(SCENE)
	var idx: Array = []
	for nm: String in ORDER:
		idx.append(txt.find("[node name=\"%s\" parent=\"Vegetation\"" % nm))
	var ord_ok: bool = int(idx[0]) >= 0
	for k in range(1, idx.size()):
		ord_ok = ord_ok and int(idx[k]) > int(idx[k - 1])
	check("village_v2.tscn 掛載 Vegetation/%s（%s）" % [" → ".join(ORDER), WS.OUTPUT], ord_ok and txt.contains(WS.OUTPUT))
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[WATER] 結果：%d 項失敗（seal）" % fails)
	return fails
