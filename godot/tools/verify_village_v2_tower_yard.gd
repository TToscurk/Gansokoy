extends SceneTree
## 人間之里 V2 P9 R4-5：火見櫓周邊 規劃 gate＋烘焙＋掛載＋場景級驗證。
##   規劃＋gate（唯讀）：Godot --headless --path godot --script res://tools/verify_village_v2_tower_yard.gd
##   反向：             ... -- --neg=float|path|tree|parcel|clutter|hero；-- --negatives 一次跑完
##   烘焙 overlay：     ... -- --build
##   掛進場景：         ... -- --attach（在 Vegetation/WatersideP9 後加 TowerYardP9；先確認 Editor 無 unsaved、F5 已停）
##   場景驗證：         ... -- --scene（掛載順序、射線接地、碰撞 vs Hero／建物／其他植被、進出路＋巡回路膠囊實走）
##   封存：             ... -- --seal（data/village_v2_p9r45_seal.json 雜湊＋掛載順序＋竄改反向；P9 R4-5 ART_APPROVED 2026-10-03）
## 每項一行 [TOWER] PASS/FAIL；INFO 不計失敗；結尾 quit(失敗項數)。

const TY := preload("res://tools/village_v2_tower_yard_lib.gd")
const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const REPORT := "res://data/village_v2_p9r45_tower.json"
const SEAL := "res://data/village_v2_p9r45_seal.json"
const EYE := 1.7
const ORDER := ["ForestP9", "BambooP9", "HiedaGardenP9", "ShrineGroveP9", "SchoolYardP9", "WatersideP9", "TowerYardP9"]
## 構件上限（消防の實用品だけ、props の山にしない）
const PROP_MAX := 10
## 視線：街路・裏から塔頂（望楼床・屋根・半鐘）と梯子の足元
const SIGHT_CAMS := [Vector2(239.0, 58.0), Vector2(239.0, 66.0), Vector2(239.5, 73.0), Vector2(250.0, 47.5),
	Vector2(258.0, 47.0), Vector2(266.0, 70.0), Vector2(262.0, 76.0)]
const TOWER_TOP := [Vector3(250.0, 13.3, 66.0), Vector3(250.0, 15.0, 66.0), Vector3(250.0, 17.3, 66.0)]

var fails := 0
var neg := ""
var failed_labels: Array = []
var quiet := false


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[TOWER] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(label: String) -> void:
	if not quiet:
		print("[TOWER] INFO " + label)


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
		print("[TOWER] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var old := v.get_node_or_null("Vegetation/" + TY.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	root.add_child(v)
	await physics_frame
	await physics_frame
	var P: Dictionary = TY.plan(v, L)
	info("規劃 %d 件（%d ms）" % [(P["items"] as Array).size(), P["ms"]])
	if "--negatives" in args:
		var target := {"float": "接地", "path": "動線淨空", "tree": "開闊", "parcel": "地塊", "clutter": "構圖", "hero": "不穿"}
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
			print("[TOWER] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d）" % ["PASS" if hit else "FAIL", nm, target[nm], failed_labels.size()])
			if not hit:
				bad += 1
		print("[TOWER] 結果：%d 項失敗（negatives）" % bad)
		quit(bad)
		return
	if neg != "":
		_inject(P)
	var rep := _checks(P)
	if neg != "":
		print("[TOWER] negative=%s 失敗 %d 項" % [neg, fails])
		quit(fails)
		return
	if "--build" in args and fails == 0:
		var r := TY.bake(P)
		TY.own(r, r)
		var ps := PackedScene.new()
		check("pack overlay", ps.pack(r) == OK)
		check("save %s" % TY.OUTPUT, ResourceSaver.save(ps, TY.OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK)
		rep["overlay"] = {"path": TY.OUTPUT, "mb": FileAccess.get_file_as_bytes(TY.OUTPUT).size() / 1048576.0,
			"items": r.get_meta("items"), "shapes": r.get_meta("shapes")}
		info("overlay %.2f MB、%d 件、構件碰撞 %d" % [rep["overlay"]["mb"], rep["overlay"]["items"], rep["overlay"]["shapes"]])
		r.free()
		var f := FileAccess.open(REPORT, FileAccess.WRITE)
		f.store_string(JSON.stringify(rep, "  ", false))
		f.close()
	print("[TOWER] 結果：%d 項失敗" % fails)
	quit(fails)


func _inject(P: Dictionary) -> void:
	var items: Array = P["items"]
	var S: RLib.TriSampler = P["S"]
	match neg:
		"float":
			for it: Dictionary in items:
				if String(it["id"]) == "tk_okeyama":
					it["y"] = float(it["y"]) + 0.35
		"path":
			items.append(TY.item(S, "mesh", "sk_box", Vector2(244.0, 66.1), 0.0, 1.0, "yard"))
		"tree":
			items.append(TY.item(S, "tree", "keyaki_a", Vector2(256.8, 63.0), 0.0, 0.8, "low", {"preset": "mature"}))
		"parcel":
			items.append(TY.item(S, "mesh", "sk_box", Vector2(258.0, 64.0), 0.0, 1.0, "yard"))
		"clutter":
			for k in 4:
				items.append(TY.item(S, "mesh", "sk_box", Vector2(244.9, 64.4 + k * 0.05) + Vector2(0.0, 0.0), 0.2 * k, 1.0, "yard"))
		"hero":
			items.append(TY.item(S, "mesh", "sk_tensui", Vector2(252.4, 63.6), 0.0, 1.0, "fire"))


func _checks(P: Dictionary) -> Dictionary:
	var S: RLib.TriSampler = P["S"]
	var R: RLib.TriSampler = P["R"]
	var M: Dictionary = P["M"]
	var items: Array = P["items"]
	var rep := {"date": Time.get_datetime_string_from_system(), "items": items.size()}
	var props: Array = items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "mesh" and String(it["id"]) != "gk_amaochi")
	var plants: Array = items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) != "mesh")
	# ── 1 接地：構件 origin ≤ 環最低地面＋0.005、埋 ≤ 0.3；雜草＝地表−0.03；縁石＝地表＋0.02（半埋）
	var fl := 0
	var dp := 0
	var worst := 0.0
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		var y := float(it["y"])
		var id := String(it["id"])
		var h := S.h(p.x, p.y)
		if id in TY.PLANT_IDS:
			if absf(y - (h - 0.03)) > 0.02:
				fl += 1
			continue
		if id == "gk_amaochi":
			if absf(y - (h + 0.02)) > 0.02:
				fl += 1
			continue
		var r := 0.25
		if TY.PROP_BOX.has(id):
			r = minf(float(TY.PROP_BOX[id][0]), float(TY.PROP_BOX[id][1])) * (it["sc"] as Vector3).x
		var lo := GL.ground(S, p, r)
		if y > lo + 0.005:
			fl += 1
			worst = maxf(worst, y - lo)
		if h - y > 0.3:
			dp += 1
	check("接地：%d 件（構件環最低、雜草貼地、縁石半埋）：浮／偏 %d（最大 %.2f m）、過深 %d" % [items.size(), fl, worst, dp], fl == 0 and dp == 0)
	# ── 2 不穿：構件外框 vs 火見櫓 Hero 碰撞（柱脚・梯子）／建物；低木 vs 柱脚
	var clip: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if id in TY.PLANT_IDS or id == "gk_amaochi":
			continue
		var pts := TY.prop_corners(it) if String(it["kind"]) == "mesh" else PackedVector2Array([it["p"]])
		if String(it["kind"]) == "mesh":
			pts.append(it["p"])
		var bad := false
		for q in pts:
			for hb: Array in P["hero"]:
				bad = bad or (hb[1] as Rect2).grow(0.1).has_point(q)
			for b: Rect2 in P["bld"]:
				bad = bad or b.grow(0.1).has_point(q)
		if bad:
			clip.append("%s@(%.1f,%.1f)" % [id, (it["p"] as Vector2).x, (it["p"] as Vector2).y])
	check("不穿：構件／低木 vs 火見櫓柱脚・梯子・建物：違規 %d %s" % [clip.size(), ", ".join(clip.slice(0, 4))], clip.is_empty())
	# ── 3 動線淨空：進出路（MainStreet→梯子足元、半幅 0.9）、巡回路帶（±0.5）、梯子足元 1.2 m 內無構件／低木（雜草は進出路のみ禁止）
	var block: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if id == "gk_amaochi":
			continue
		var pts := TY.prop_corners(it) if String(it["kind"]) == "mesh" else PackedVector2Array([it["p"]])
		var rr := 0.3 if id in TY.PLANT_IDS else (0.5 if String(it["kind"]) == "tree" else 0.0)
		for q in pts:
			var on_ap := GL.line_d(TY.APPROACH, q).x < TY.APPROACH_HW + rr
			var on_ring := absf(TY.ring_d(q)) < TY.RING_W + rr and not (id in TY.PLANT_IDS)
			var on_foot := q.distance_to(TY.LADDER_FOOT) < 1.2 + rr
			if on_ap or on_ring or on_foot:
				block.append("%s@(%.1f,%.1f)" % [id, (it["p"] as Vector2).x, (it["p"] as Vector2).y])
				break
	check("動線淨空：進出路 MainStreet→梯子足元／巡回路帶／梯子足元 1.2 m 內障礙 %d %s" % [block.size(), ", ".join(block.slice(0, 4))], block.is_empty())
	# ── 4 開闊：高木 0（植生＝蕨・灌木・菅のみ、高さ ≤ 1.3 m）、塔心 8 m 內植生被覆 ≤ 6 %、塔頂視線 7 機位×3 點 被新物件擋 0
	var tall: Array = []
	var cov := 0.0
	for it: Dictionary in plants:
		var id := String(it["id"])
		var hgt := 0.4 * (it["sc"] as Vector3).x
		if String(it["kind"]) == "tree":
			hgt = float(M[id]["height"]) * (it["sc"] as Vector3).x if M.has(id) else 99.0
			if not (id in TY.UNDER_IDS):
				hgt = 99.0
			if (it["p"] as Vector2).distance_to(TY.C) < 8.0:
				var cr := float(M[id]["crown_w"]) * 0.45 * (it["sc"] as Vector3).x if M.has(id) else 3.0
				cov += PI * cr * cr
		elif (it["p"] as Vector2).distance_to(TY.C) < 8.0:
			cov += PI * 0.3 * 0.3 * (it["sc"] as Vector3).x
		if hgt > TY.LOW_MAX_H:
			tall.append("%s(%.1f m)" % [id, hgt])
	var cov_r := cov / (PI * 64.0)
	var sb := 0
	for c: Vector2 in SIGHT_CAMS:
		var cam := Vector3(c.x, S.h(c.x, c.y) + EYE, c.y)
		for t: Vector3 in TOWER_TOP:
			for it: Dictionary in plants:
				if String(it["kind"]) != "tree":
					continue
				var cyl := SG.crown_cyl(it, M)
				if SG.seg_hits(cam, t, cyl):
					sb += 1
	check("開闊：高木／超高植生 %d %s（植生 ≤ %.1f m）、塔心 8 m 內植生被覆 %.1f %%（≤ 6 %%）、塔頂視線 %d 機位×3 點被擋 %d" % [tall.size(),
		str(tall.slice(0, 3)), TY.LOW_MAX_H, cov_r * 100.0, SIGHT_CAMS.size(), sb], tall.is_empty() and cov_r <= 0.06 and sb == 0)
	rep["open"] = {"tall": tall.size(), "cover_8m": cov_r, "sight_blocked": sb}
	# ── 5 地塊：構件は塔の地塊か未區劃地のみ（町家・附屬地へ入れない）；植生は町家地塊へ入れない
	var pin: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		var kinds := ["machiya", "aux", "yard"] if String(it["kind"]) == "mesh" else ["machiya"]
		var pts := TY.prop_corners(it) if String(it["kind"]) == "mesh" else PackedVector2Array([it["p"]])
		for q in pts:
			var hit := TY.in_parcel(P["pp"], q, kinds)
			if hit != "":
				pin.append("%s→%s" % [id, hit])
				break
	check("地塊：構件／植生 侵入他地塊 %d %s" % [pin.size(), ", ".join(pin.slice(0, 4))], pin.is_empty())
	# ── 6 構圖（塔 → 基部 → 道具）：構件 ≤ %d 件、街側正面（x < 246.4、|z−66| < 2.2）に構件なし、
	#        MainStreet 正面機位 (239,66) から梯子足元への視線を構件が遮らない
	var front: Array = []
	for it: Dictionary in props:
		for q in TY.prop_corners(it):
			if q.x < 246.4 and absf(q.y - 66.0) < 2.2:
				front.append(String(it["id"]))
				break
	var cam0 := Vector2(239.0, 66.0)
	var occl := 0
	for it: Dictionary in props:
		var poly := TY.prop_corners(it)
		for t: Vector2 in [TY.LADDER_FOOT, TY.LADDER_FOOT + Vector2(0, 0.6), TY.LADDER_FOOT + Vector2(0, -0.6)]:
			if not Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([cam0, t]), poly).is_empty():
				occl += 1
	check("構圖：構件 %d 件（≤ %d）、街側正面に構件 %d %s、正面機位→梯子足元を遮る %d" % [props.size(), PROP_MAX, front.size(), str(front),
		occl], props.size() <= PROP_MAX and front.is_empty() and occl == 0)
	# ── 7 元素：用水桶積み・天水桶・手桶・道具掛け・予備梯子・木箱・縄・排水縁石・低い植生
	var have := {}
	for it: Dictionary in items:
		have[String(it["id"])] = int(have.get(String(it["id"]), 0)) + 1
	var need := {"tk_okeyama": 1, "sk_tensui": 1, "sk_teoke": 1, "tk_rack": 1, "tk_ladder": 1, "sk_box": 1, "tk_rope": 1,
		"gk_amaochi": 6, "wk_sedge": 8, "fern_a": 1}
	var miss: Array = []
	for k: String in need:
		if int(have.get(k, 0)) < int(need[k]):
			miss.append("%s %d/%d" % [k, int(have.get(k, 0)), need[k]])
	check("元素：%s" % ("齊備" if miss.is_empty() else "缺 " + ", ".join(miss)), miss.is_empty())
	rep["elements"] = have
	info("構件 %d、植生 %d（雜草 %d）、排水縁石 %d" % [props.size(), plants.size(), int(have.get("wk_sedge", 0)), int(have.get("gk_amaochi", 0))])
	return rep


# ─────────────────────────── 掛載 ───────────────────────────

func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(TY.OUTPUT):
		push_error("找不到 %s（先 --build 成功才可 attach）" % TY.OUTPUT)
		return 1
	if txt.contains("gen/tower_yard_p9.scn"):
		push_error("已經掛過 TowerYardP9")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var done := false
	var i := 0
	while i < lines.size():
		var ln := lines[i]
		out.append(ln)
		if not done and ln.begins_with("[node name=\"WatersideP9\" parent=\"Vegetation\""):
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"TowerYardP9\" parent=\"Vegetation\" instance=ExtResource(\"p9r45_tower\")]")
			out.append("")
			done = true
			continue
		i += 1
	if not done:
		push_error("找不到 Vegetation/WatersideP9")
		return 1
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p9r45_tower\"]" % TY.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[TOWER] attach：加 Vegetation/TowerYardP9 → %s" % SCENE)
	return 0


# ─────────────────────────── 場景級驗證 ───────────────────────────

func _scene(v: Node3D) -> void:
	var go := v.get_node_or_null("Vegetation/" + TY.NODE_NAME) as Node3D
	var names: Array = []
	for c in v.get_node("Vegetation").get_children():
		names.append(String(c.name))
	var ok := true
	for k in ORDER.size() - 1:
		if not (ORDER[k] in names and ORDER[k + 1] in names) or names.find(ORDER[k]) > names.find(ORDER[k + 1]):
			ok = false
	check("場景已掛 Vegetation/%s，順序 %s：%s" % [TY.NODE_NAME, " → ".join(ORDER), str(names)], go != null and ok)
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
	check("場景接地（%d／%d 件構件・低木 origin 向下射線只認地形）：浮 > 0.06 m %d（最大 %.3f）" % [n, n_all, fl, worst], fl == 0 and n == n_all)
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
	check("碰撞：構件箱 vs 火見櫓／建物／道路／其他植被 接觸 %s" % (str(hits.keys().slice(0, 5)) if hits else "0"), hits.is_empty())
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var blocked: Array = []
	var probes := 0
	var routes: Array = [TY.APPROACH, TY.YARD_PATH]
	# 巡回路（角丸正方形の帯の中心線、24 點）
	var ring: Array = []
	for k in 49:
		var a := k * TAU / 48.0
		var dir := Vector2(cos(a), sin(a))
		# 中心線＝ring_d==0 の點を二分探索
		var lo := 0.0
		var hi := 8.0
		for it in 24:
			var mid := (lo + hi) * 0.5
			if TY.ring_d(TY.C + dir * mid) < 0.0:
				lo = mid
			else:
				hi = mid
		ring.append(TY.C + dir * lo)
	routes.append(ring)
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
				if path.begins_with("Vegetation/" + TY.NODE_NAME) or path.begins_with("Landmarks/LANDMARK_TOWER"):
					blocked.append("(%.1f,%.1f) %s" % [p.x, p.y, path])
	check("實走：進出路＋巡回路＋道具置き場への踏み跡 膠囊 %d 點被本 overlay／火見櫓擋 %d %s" % [probes, blocked.size(), ", ".join(blocked.slice(0, 3))],
		blocked.is_empty())
	info("TowerYardP9：%s 件、MeshInstance %d、構件碰撞 %s" % [go.get_meta("items", "?"), go.find_children("*", "MeshInstance3D", true, false).size(), go.get_meta("shapes", "?")])


# ─────────────────────────── 封存（--seal，P9 R4-5 火見櫓周邊 ART_APPROVED 2026-10-03） ───────────────────────────

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
	check("P9 R4-5 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 總表 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var txt := FileAccess.get_file_as_string(SCENE)
	var idx: Array = []
	for nm: String in ORDER:
		idx.append(txt.find("[node name=\"%s\" parent=\"Vegetation\"" % nm))
	var ord_ok: bool = int(idx[0]) >= 0
	for k in range(1, idx.size()):
		ord_ok = ord_ok and int(idx[k]) > int(idx[k - 1])
	check("village_v2.tscn 掛載 Vegetation/%s（%s）" % [" → ".join(ORDER), TY.OUTPUT], ord_ok and txt.contains(TY.OUTPUT))
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[TOWER] 結果：%d 項失敗（seal）" % fails)
	return fails
