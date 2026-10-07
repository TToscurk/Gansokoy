extends SceneTree
## 人間之里 V2 P9 R4-6：鈴奈庵周邊 規劃 gate＋烘焙＋掛載＋場景級驗證。
##   規劃＋gate（唯讀）：Godot --headless --path godot --script res://tools/verify_village_v2_suzunaan_yard.gd
##   反向：             ... -- --neg=float|path|facade|parcel|clutter|hero；-- --negatives 一次跑完
##   烘焙 overlay：     ... -- --build
##   掛進場景：         ... -- --attach（在 Vegetation/TowerYardP9 後加 SuzunaanP9；先確認 Editor 無 unsaved、F5 已停）
##   場景驗證：         ... -- --scene（掛載順序、射線接地、碰撞 vs Hero／建物／其他植被、入口・庇下・北の踏み跡 膠囊實走）
##   封存：             ... -- --seal（data/village_v2_p9r46_seal.json 雜湊＋掛載順序＋竄改反向；P9 R4-6 ART_APPROVED 2026-10-03）
## 每項一行 [SUZU] PASS/FAIL；INFO 不計失敗；結尾 quit(失敗項數)。

const SZ := preload("res://tools/village_v2_suzunaan_yard_lib.gd")
const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const REPORT := "res://data/village_v2_p9r46_suzunaan.json"
const SEAL := "res://data/village_v2_p9r46_seal.json"
const EYE := 1.7
const ORDER := ["ForestP9", "BambooP9", "HiedaGardenP9", "ShrineGroveP9", "SchoolYardP9", "WatersideP9", "TowerYardP9", "SuzunaanP9"]
## 構件上限（生活の痕跡だけ、props の山にしない）；門前（庇の前・台基の間口）に置く構件 ≤ 1、南の路地 0
const PROP_MAX := 12
const FRONT_MAX := 1
## 門面視線：主街の正面・斜め・南北の遠景（局部）→ 二階の看板「鈴奈庵」・暖簾・入口
const SIGHT_CAMS := [Vector2(0.0, 9.0), Vector2(-6.0, 9.5), Vector2(7.0, 9.0), Vector2(-12.0, 8.5), Vector2(12.5, 8.0)]
const FACADE_PTS := [Vector3(0.0, 3.2, 4.3), Vector3(-2.0, 3.2, 4.3), Vector3(2.0, 3.2, 4.3), Vector3(0.0, 2.2, 4.4),
	Vector3(0.0, 1.3, 4.2), Vector3(-0.7, 1.0, 4.2), Vector3(0.7, 1.0, 4.2)]

var fails := 0
var neg := ""
var failed_labels: Array = []
var quiet := false


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[SUZU] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(label: String) -> void:
	if not quiet:
		print("[SUZU] INFO " + label)


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
		print("[SUZU] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var old := v.get_node_or_null("Vegetation/" + SZ.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	root.add_child(v)
	await physics_frame
	await physics_frame
	var P: Dictionary = SZ.plan(v, L)
	info("規劃 %d 件（%d ms）" % [(P["items"] as Array).size(), P["ms"]])
	if "--negatives" in args:
		var target := {"float": "接地", "path": "動線淨空", "facade": "門面", "parcel": "地塊", "clutter": "構圖", "hero": "不穿"}
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
			print("[SUZU] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d）" % ["PASS" if hit else "FAIL", nm, target[nm], failed_labels.size()])
			if not hit:
				bad += 1
		print("[SUZU] 結果：%d 項失敗（negatives）" % bad)
		quit(bad)
		return
	if neg != "":
		_inject(P)
	var rep := _checks(P)
	if neg != "":
		print("[SUZU] negative=%s 失敗 %d 項" % [neg, fails])
		quit(fails)
		return
	if "--build" in args and fails == 0:
		var r := SZ.bake(P)
		SZ.own(r, r)
		var ps := PackedScene.new()
		check("pack overlay", ps.pack(r) == OK)
		check("save %s" % SZ.OUTPUT, ResourceSaver.save(ps, SZ.OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK)
		rep["overlay"] = {"path": SZ.OUTPUT, "mb": FileAccess.get_file_as_bytes(SZ.OUTPUT).size() / 1048576.0,
			"items": r.get_meta("items"), "shapes": r.get_meta("shapes")}
		info("overlay %.2f MB、%d 件、構件碰撞 %d" % [rep["overlay"]["mb"], rep["overlay"]["items"], rep["overlay"]["shapes"]])
		r.free()
		var f := FileAccess.open(REPORT, FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, "  ", false))
		f.close()
	print("[SUZU] 結果：%d 項失敗" % fails)
	quit(fails)


func _inject(P: Dictionary) -> void:
	var items: Array = P["items"]
	var S: RLib.TriSampler = P["S"]
	match neg:
		"float":
			for it: Dictionary in items:
				if String(it["id"]) == "sz_kanban":
					it["y"] = float(it["y"]) + 0.35
		"path":
			items.append(SZ.item(S, "mesh", "sz_hako", SZ.W(0.3, 5.9), 0.0, 1.0, "front"))
		"facade":
			items.append(SZ.item(S, "mesh", "sz_keiji", SZ.W(-2.2, 6.0), SZ.yaw_l(Vector2(0.0, 1.0)), 1.0, "front"))
		"parcel":
			items.append(SZ.item(S, "mesh", "sz_hako", Vector2(244.0, 3.6), 0.0, 1.0, "side"))
		"clutter":
			for k in 6:
				items.append(SZ.item(S, "mesh", "sz_hako", SZ.W(7.6 + (k % 2) * 0.8, -2.0 + k * 0.7), 0.0, 1.0, "side"))
		"hero":
			items.append(SZ.item(S, "mesh", "sz_hako", SZ.W(3.2, 4.25), SZ.yaw_l(Vector2(0.0, 1.0)), 1.0, "front"))


func _checks(P: Dictionary) -> Dictionary:
	var S: RLib.TriSampler = P["S"]
	var R: RLib.TriSampler = P["R"]
	var M: Dictionary = P["M"]
	var items: Array = P["items"]
	var rep := {"date": Time.get_datetime_string_from_system(), "items": items.size()}
	var props: Array = items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "mesh" and not (String(it["id"]) in SZ.GROUND_IDS))
	var plants: Array = items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) != "mesh")
	# ── 0 Hero 座標系：lib の局部軸 == 場景の Hero transform（≤ 1 cm）
	var hx: Transform3D = P["hero_xf"]
	var e0 := Vector2(hx.origin.x, hx.origin.z).distance_to(SZ.HO)
	var e1 := Vector2(hx.basis.z.x, hx.basis.z.z).normalized().distance_to(SZ.BZ)
	check("Hero 座標系：原點差 %.3f m、正面軸差 %.4f（≤ 0.01）" % [e0, e1], e0 <= 0.01 and e1 <= 0.01)
	# ── 1 接地：構件 origin ≤ 環最低地面＋0.005、埋 ≤ 0.3；雜草／雨受け石＝地表−0.03；載せ物＝支え面
	var fl := 0
	var dp := 0
	var worst := 0.0
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		var y := float(it["y"])
		var id := String(it["id"])
		var h := S.h(p.x, p.y)
		if id == "gk_amaochi":
			if absf(y - (h + 0.02)) > 0.02:
				fl += 1
			continue
		if id in SZ.PLANT_IDS or id in SZ.GROUND_IDS:
			if absf(y - (h - 0.03)) > 0.02:
				fl += 1
			continue
		if it.has("on"):
			var sup: Array = items.filter(func(o: Dictionary) -> bool: return String(o["id"]) == String(it["on"]) and (o["p"] as Vector2).distance_to(p) < 0.3)
			if sup.is_empty() or absf(y - (float(sup[0]["y"]) + float(it["on_h"]))) > 0.01:
				fl += 1
			continue
		var r := 0.25
		if SZ.PROP_BOX.has(id):
			r = minf(float(SZ.PROP_BOX[id][0]), float(SZ.PROP_BOX[id][1])) * (it["sc"] as Vector3).x
		var lo := GL.ground(S, p, r)
		if y > lo + 0.005:
			fl += 1
			worst = maxf(worst, y - lo)
		if h - y > 0.3:
			dp += 1
	check("接地：%d 件（構件環最低、雜草・雨受け石貼地、縁石半埋、書冊束は腰掛けの座面）：浮／偏 %d（最大 %.2f m）、過深 %d" % [items.size(), fl, worst, dp],
		fl == 0 and dp == 0)
	# ── 2 不穿：構件／低木 vs 鈴奈庵 Hero（Collision OBB＋asset.json 地面部品：竪樋・花盆・縁台…）／鄰家建物
	var clip: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if id in SZ.PLANT_IDS:
			continue
		var pts := SZ.prop_corners(it) if String(it["kind"]) == "mesh" else PackedVector2Array([it["p"]])
		pts.append(it["p"])
		var why := ""
		for q in pts:
			var lq := SZ.Lc(q)
			for o: Array in P["obb"]:
				if SZ.in_obb(q, o, 0.02):
					why = String(o[0])
			for g: Array in P["parts"]:
				if (g[1] as Rect2).grow(0.03).has_point(lq):
					why = String(g[0])
			for b: Rect2 in P["bld"]:
				if b.grow(0.05).has_point(q):
					why = "鄰家"
		if why != "":
			clip.append("%s@(%.1f,%.1f)→%s" % [id, SZ.Lc(it["p"]).x, SZ.Lc(it["p"]).y, why])
	# 構件どうし（外框が重ならない；載せ物は支えと重なってよい）
	for a in props.size():
		for b in range(a + 1, props.size()):
			var ia: Dictionary = props[a]
			var ib: Dictionary = props[b]
			if String(ia.get("on", "")) == String(ib["id"]) or String(ib.get("on", "")) == String(ia["id"]):
				continue
			if not Geometry2D.intersect_polygons(SZ.prop_corners(ia), SZ.prop_corners(ib)).is_empty():
				clip.append("%s×%s" % [ia["id"], ib["id"]])
	check("不穿：構件／低木 vs 鈴奈庵 Hero（台基・踏石・縁台・花盆・木箱・竪樋・勝手口）／鄰家／構件どうし：違規 %d %s" % [clip.size(), ", ".join(clip.slice(0, 4))],
		clip.is_empty())
	# ── 3 動線淨空：入口の軸（局部 |lx| < 1.0、道→踏石）、庇の下の通路、北の踏み跡・横丁からの踏み跡（半幅 0.45）、勝手口前
	var block: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if id in SZ.GROUND_IDS:
			continue
		var pts := SZ.prop_corners(it) if String(it["kind"]) == "mesh" else PackedVector2Array([it["p"]])
		var rr := 0.25 if id in SZ.PLANT_IDS else (0.45 if String(it["kind"]) == "tree" else 0.0)
		for q in pts:
			var lq := SZ.Lc(q)
			var on_e := absf(lq.x) < SZ.ENTRY_HW + rr and lq.y > SZ.HALF.y and lq.y < 6.6
			var on_w := SZ.WALK.grow(rr).has_point(lq)
			var on_p := minf(GL.line_d(SZ.PATH_N, lq).x, GL.line_d(SZ.PATH_X, lq).x) < SZ.PATH_HW + rr
			var on_b := SZ.BACKDOOR.grow(rr).has_point(lq)
			if on_e or on_w or on_p or on_b:
				block.append("%s@(%.1f,%.1f)" % [id, SZ.Lc(it["p"]).x, SZ.Lc(it["p"]).y])
				break
	check("動線淨空：入口軸／庇下通路／北・横丁の踏み跡／勝手口前 障礙 %d %s" % [block.size(), ", ".join(block.slice(0, 4))], block.is_empty())
	# ── 4 門面：主街 5 機位（目高 1.7）→ 二階看板・暖簾・入口 7 點，被構件（外框×高）／植生樹冠擋 0；植生 ≤ 1.3 m
	var occl: Array = []
	for c: Vector2 in SIGHT_CAMS:
		var cw := SZ.W(c.x, c.y)
		var cam := Vector3(cw.x, S.h(cw.x, cw.y) + EYE, cw.y)
		for t: Vector3 in FACADE_PTS:
			var tw := SZ.W(t.x, t.z)
			var tgt := Vector3(tw.x, hx.origin.y + t.y, tw.y)
			for it: Dictionary in props:
				var poly := SZ.prop_corners(it)
				var hit := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(cam.x, cam.z), Vector2(tgt.x, tgt.z)]), poly)
				if hit.is_empty():
					continue
				# 交差區間で視線の高さ < 構件の頂 → 擋
				var top := float(it["y"]) + float(SZ.PROP_BOX[String(it["id"])][2])
				var blocked := false
				for seg: PackedVector2Array in hit:
					for q in seg:
						var tt := Vector2(cam.x, cam.z).distance_to(q) / Vector2(cam.x, cam.z).distance_to(Vector2(tgt.x, tgt.z))
						if lerpf(cam.y, tgt.y, tt) < top:
							blocked = true
				if blocked:
					occl.append("%s cam(%.0f,%.1f)→(%.1f,%.1f)" % [String(it["id"]), c.x, c.y, t.x, t.y])
			for it: Dictionary in plants:
				if String(it["kind"]) != "tree":
					continue
				if SG.seg_hits(cam, tgt, SG.crown_cyl(it, M)):
					occl.append("%s cam(%.0f,%.1f)" % [String(it["id"]), c.x, c.y])
	var tall: Array = []
	for it: Dictionary in plants:
		var id := String(it["id"])
		var hgt := 0.4 * (it["sc"] as Vector3).x
		if String(it["kind"]) == "tree":
			hgt = float(M[id]["height"]) * (it["sc"] as Vector3).x if M.has(id) and id in SZ.UNDER_IDS else 99.0
		if hgt > SZ.LOW_MAX_H:
			tall.append("%s(%.1f m)" % [id, hgt])
	check("門面：主街 %d 機位→看板・暖簾・入口 %d 點 被擋 %d %s；植生超高 %d %s" % [SIGHT_CAMS.size(), FACADE_PTS.size(), occl.size(),
		", ".join(occl.slice(0, 3)), tall.size(), str(tall.slice(0, 3))], occl.is_empty() and tall.is_empty())
	rep["facade"] = {"blocked": occl.size(), "tall": tall.size()}
	# ── 5 地塊：構件は鈴奈庵の地塊か未區劃地のみ（町家・附屬地へ入れない）、道路上に置かない；植生は町家地塊・道路へ入れない
	var pin: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		var kinds := ["machiya", "aux", "yard"] if String(it["kind"]) == "mesh" else ["machiya"]
		var pts := SZ.prop_corners(it) if String(it["kind"]) == "mesh" else PackedVector2Array([it["p"]])
		for q in pts:
			var hit := SZ.in_parcel(P["pp"], q, kinds)
			if hit == "" and not is_nan(R.h(q.x, q.y)):
				hit = "道路"
			if hit != "":
				pin.append("%s→%s" % [id, hit])
				break
	check("地塊：構件／植生 侵入他地塊・道路 %d %s" % [pin.size(), ", ".join(pin.slice(0, 4))], pin.is_empty())
	# ── 6 構圖・留白：構件 ≤ %d、門前 ≤ %d、南の路地 0、構件の 80 % 以上が門前＋北側、北側ゾーン占有 ≤ 25 %
	var n_front := 0
	var n_south := 0
	var n_fs := 0
	for it: Dictionary in props:
		var lq := SZ.Lc(it["p"])
		if lq.y > SZ.HALF.y - 0.2 and absf(lq.x) < SZ.HALF.x + 1.4:
			n_front += 1
		if lq.x < -SZ.HALF.x:
			n_south += 1
		if lq.y > SZ.HALF.y - 0.2 or lq.x > SZ.HALF.x:
			n_fs += 1
	var occ := 0
	var tot := 0
	var yd: Rect2 = SZ.NORTH_YARD
	var gx := yd.position.x + 0.125
	while gx < yd.end.x:
		var gz := yd.position.y + 0.125
		while gz < yd.end.y:
			tot += 1
			var w := SZ.W(gx, gz)
			var taken := false
			for it: Dictionary in items:
				var id := String(it["id"])
				if String(it["kind"]) == "mesh":
					if Geometry2D.is_point_in_polygon(w, SZ.prop_corners(it)):
						taken = true
						break
				else:
					var cr := 0.3 * (it["sc"] as Vector3).x
					if String(it["kind"]) == "tree" and M.has(id):
						cr = float(M[id]["crown_w"]) * 0.45 * (it["sc"] as Vector3).x
					if w.distance_to(it["p"]) < cr:
						taken = true
						break
			if taken:
				occ += 1
			gz += 0.25
		gx += 0.25
	var occ_r := float(occ) / maxf(1.0, tot)
	var conc := float(n_fs) / maxf(1.0, props.size())
	check("構圖：構件 %d（≤ %d）、門前 %d（≤ %d）、南の路地 %d（= 0）、門前＋北側 %.0f %%（≥ 80 %%）、北側ゾーン占有 %.1f %%（≤ 25 %%）" % [props.size(),
		PROP_MAX, n_front, FRONT_MAX, n_south, conc * 100.0, occ_r * 100.0],
		props.size() <= PROP_MAX and n_front <= FRONT_MAX and n_south == 0 and conc >= 0.8 and occ_r <= 0.25)
	rep["composition"] = {"props": props.size(), "front": n_front, "south": n_south, "concentration": conc, "north_occupancy": occ_r}
	# ── 7 元素：置き看板・掲示板・本箱・書冊束・腰掛け・縁台・鉢植え・背負い本箱・雨受け石・牆腳草・低木
	var have := {}
	for it: Dictionary in items:
		have[String(it["id"])] = int(have.get(String(it["id"]), 0)) + 1
	have["本箱"] = int(have.get("sz_hako", 0)) + int(have.get("sz_hako2", 0))
	have["低木"] = int(have.get("fern_a", 0)) + int(have.get("shrub_a", 0))
	var need := {"sz_kanban": 1, "sz_keiji": 1, "本箱": 2, "sz_bundle": 1, "sz_stool": 1, "sz_dai": 1, "sz_hachi": 1, "sz_seoi": 1,
		"gk_tobi_d": 2, "gk_amaochi": 6, "wk_sedge": 8, "低木": 2}
	var miss: Array = []
	for k: String in need:
		if int(have.get(k, 0)) < int(need[k]):
			miss.append("%s %d/%d" % [k, int(have.get(k, 0)), need[k]])
	check("元素：%s" % ("齊備" if miss.is_empty() else "缺 " + ", ".join(miss)), miss.is_empty())
	rep["elements"] = have
	info("構件 %d、植生 %d（雜草 %d）、雨受け石 %d" % [props.size(), plants.size(), int(have.get("wk_sedge", 0)), int(have.get("gk_tobi_d", 0))])
	return rep


# ─────────────────────────── 掛載 ───────────────────────────

func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(SZ.OUTPUT):
		push_error("找不到 %s（先 --build 成功才可 attach）" % SZ.OUTPUT)
		return 1
	if txt.contains("gen/suzunaan_p9.scn"):
		push_error("已經掛過 SuzunaanP9")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var done := false
	var i := 0
	while i < lines.size():
		var ln := lines[i]
		out.append(ln)
		if not done and ln.begins_with("[node name=\"TowerYardP9\" parent=\"Vegetation\""):
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"SuzunaanP9\" parent=\"Vegetation\" instance=ExtResource(\"p9r46_suzu\")]")
			out.append("")
			done = true
			continue
		i += 1
	if not done:
		push_error("找不到 Vegetation/TowerYardP9")
		return 1
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p9r46_suzu\"]" % SZ.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[SUZU] attach：加 Vegetation/SuzunaanP9 → %s" % SCENE)
	return 0


# ─────────────────────────── 場景級驗證 ───────────────────────────

func _scene(v: Node3D) -> void:
	var go := v.get_node_or_null("Vegetation/" + SZ.NODE_NAME) as Node3D
	var names: Array = []
	for c in v.get_node("Vegetation").get_children():
		names.append(String(c.name))
	var ok := true
	for k in ORDER.size() - 1:
		if not (ORDER[k] in names and ORDER[k + 1] in names) or names.find(ORDER[k]) > names.find(ORDER[k + 1]):
			ok = false
	check("場景已掛 Vegetation/%s，順序 %s：%s" % [SZ.NODE_NAME, " → ".join(ORDER), str(names)], go != null and ok)
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
	for grp: String in ["Low", "Props"]:
		for node in go.get_node(grp).get_children():
			if String(node.get_meta("sz_id", "")) == "sz_bundle":
				continue
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
	check("場景接地（%d／%d 件構件・低木 origin 向下射線只認地形；書冊束は腰掛けの上）：浮 > 0.06 m %d（最大 %.3f）" % [n, n_all, fl, worst],
		fl == 0 and n == n_all)
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
	check("碰撞：構件箱 vs 鈴奈庵 Hero／建物／道路／其他植被 接觸 %s" % (str(hits.keys().slice(0, 5)) if hits else "0"), hits.is_empty())
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var blocked: Array = []
	var probes := 0
	var routes: Array = [[Vector2(0.0, 6.6), Vector2(0.0, 5.0)], [Vector2(-3.9, 5.05), Vector2(3.9, 5.05)], SZ.PATH_N, SZ.PATH_X]
	for route: Array in routes:
		var wr: Array = []
		for q: Vector2 in route:
			wr.append(SZ.W(q.x, q.y))
		for e: Array in GL.resample(wr, 0.5):
			var p: Vector2 = e[0]
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cap
			qp.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, S.h(p.x, p.y) + 0.3 + 0.85 + 0.12, p.y))
			qp.exclude = [terrain.get_rid()]
			probes += 1
			for r: Dictionary in space.intersect_shape(qp, 4):
				var path := String(v.get_path_to(r["collider"] as Node))
				if path.begins_with("Vegetation/" + SZ.NODE_NAME) or path.begins_with("Landmarks/LANDMARK_SUZUNAAN"):
					blocked.append("(%.1f,%.1f) %s" % [SZ.Lc(p).x, SZ.Lc(p).y, path])
	check("實走：入口軸＋庇下通路＋北の踏み跡＋横丁からの踏み跡 膠囊 %d 點被本 overlay／鈴奈庵擋 %d %s" % [probes, blocked.size(),
		", ".join(blocked.slice(0, 3))], blocked.is_empty())
	info("SuzunaanP9：%s 件、MeshInstance %d、構件碰撞 %s" % [go.get_meta("items", "?"), go.find_children("*", "MeshInstance3D", true, false).size(), go.get_meta("shapes", "?")])


# ─────────────────────────── 封存（--seal，P9 R4-6 鈴奈庵周邊 ART_APPROVED 2026-10-03） ───────────────────────────

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
	check("P9 R4-6 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 總表 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var txt := FileAccess.get_file_as_string(SCENE)
	var idx: Array = []
	for nm: String in ORDER:
		idx.append(txt.find("[node name=\"%s\" parent=\"Vegetation\"" % nm))
	var ord_ok: bool = int(idx[0]) >= 0
	for k in range(1, idx.size()):
		ord_ok = ord_ok and int(idx[k]) > int(idx[k - 1])
	check("village_v2.tscn 掛載 Vegetation/%s（%s）" % [" → ".join(ORDER), SZ.OUTPUT], ord_ok and txt.contains(SZ.OUTPUT))
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[SUZU] 結果：%d 項失敗（seal）" % fails)
	return fails
