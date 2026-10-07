extends SceneTree
## 人間之里 V2 P10 R1b Market West Rework（市集西通り r2）gate——構造の機械検査；美術判定は同機位 TPS BEFORE／AFTER。
##   godot --headless --path . --script res://tools/verify_village_v2_market_west.gd                 規劃 gate（21 項）
##   godot --headless --path . --script res://tools/verify_village_v2_market_west.gd -- --negatives  永久反向（19 案）
##   godot --headless --path . --script res://tools/verify_village_v2_market_west.gd -- --build      gate PASS 時のみ gen/market_west_p10.scn を書く
##   godot --headless --path . --script res://tools/verify_village_v2_market_west.gd -- --attach     Props/StreetP10 の後へ MarketWestP10 を掛ける（1 回だけ）
##   godot --headless --path . --script res://tools/verify_village_v2_market_west.gd -- --seal       封存（P10 R1b r3 ART_APPROVED）：雜湊＋掛載＋依存（P10 R1・P9 R5 限定解封）＋竄改反向
##   godot --path . --script res://tools/verify_village_v2_market_west.gd -- --scene                 場景級（掛載順・MarketP10 封存・接地射線・建物 Kit LOD・床・碰撞・anchors）
## 每項一行 [MW] PASS/FAIL；結尾 quit(失敗項數)。
const MW := preload("res://tools/village_v2_market_west_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const MK := preload("res://tools/village_v2_market_lib.gd")
const ML := preload("res://tools/village_v2_machiya_kit_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const MARKET_SEAL := "res://data/village_v2_p10r1_seal.json"
const SEAL := "res://data/village_v2_p10r1b_seal.json"
const R5_SEAL := "res://data/village_v2_p9r5_seal.json"
const PARCELS := "res://maps/village_v2/gen/parcels.json"
## mise_kit が使ってよい材質（町で使用中・承認済みのもの；新 atlas は不可）
const MISE_MATS := ["V2_Wood", "V2_Kawara", "MK_Market", "ST_Street"]
const TALL := 1.7

var fails := 0
var failed_labels: Array = []
var quiet := false
var verbose := false
var lib := {}
var parcels: Array = []


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[MW] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(s: String) -> void:
	if not quiet:
		print("[MW] INFO " + s)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	verbose = "--verbose" in args
	if "--attach" in args:
		quit(_attach())
		return
	if "--seal" in args:
		quit(_seal())
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	if "--scene" in args:
		root.add_child(v)
		await _scene(v)
		print("[MW] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var old := v.get_node_or_null(MW.PARENT + "/" + MW.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	root.add_child(v)
	await physics_frame
	var PJ: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PARCELS))
	for r: Dictionary in PJ["parcels"]:
		var pp := PackedVector2Array()
		for a in r["footprint"]:
			pp.append(Vector2(float(a[0]), float(a[1])))
		parcels.append([String(r["id"]), pp])
	lib = ML.load_lib()
	var P := MW.plan(v)
	P["street"] = SL.plan(v)["items"]
	_kits(P)
	info("規劃 店 %d、構件 %d、anchors %d（%d ms）" % [(P["shops"] as Array).size(), (P["items"] as Array).size(), (P["anchors"] as Array).size(), P["ms"]])
	if "--negatives" in args:
		var target := {"n_float": "接地", "n_building": "建物", "n_parcel": "地塊", "n_overlap": "互不重疊", "n_lane": "歩く通り", "n_door": "戸口",
			"n_market": "封存", "n_access": "到達", "n_sight": "視線", "n_compose": "構圖", "n_anchor": "NPC", "n_water": "水際", "n_retired": "Kit",
			"n_hung": "掛け物", "n_closed": "営業中", "n_naka": "店内", "n_even": "主次", "n_lure": "入口の誘い", "n_fan": "市集の北西角"}
		var bad := 0
		for nm: String in target:
			var P2 := P.duplicate()
			P2["items"] = (P["items"] as Array).duplicate(true)
			P2["anchors"] = (P["anchors"] as Array).duplicate(true)
			P2["shops"] = (P["shops"] as Array).duplicate(true)
			fails = 0
			failed_labels.clear()
			quiet = true
			_inject(P2, nm)
			_checks(P2)
			quiet = false
			var hit := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(target[nm])))
			print("[MW] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d：%s）" % ["PASS" if hit else "FAIL", nm, target[nm], failed_labels.size(),
				", ".join(failed_labels.map(func(l: String) -> String: return l.substr(0, 5)))])
			if not hit:
				bad += 1
		print("[MW] 結果：%d 項失敗（negatives）" % bad)
		quit(bad)
		return
	_checks(P)
	for a: String in args:
		if a.begins_with("--dump="):
			_dump(P, a.trim_prefix("--dump="))
	if "--build" in args and fails == 0:
		var r := MW.bake(P)
		var holder := Node3D.new()
		holder.add_child(r)
		MW.own(r, r)
		var ps := PackedScene.new()
		var e := ps.pack(r)
		var e2 := ResourceSaver.save(ps, MW.OUTPUT, ResourceSaver.FLAG_COMPRESS) if e == OK else e
		check("save %s（店 %d、構件 %d、anchors %d、碰撞 %d）" % [MW.OUTPUT, r.get_meta("shops"), r.get_meta("items"), r.get_meta("anchors"), r.get_meta("shapes")], e2 == OK)
		holder.free()
	print("[MW] 結果：%d 項失敗" % fails)
	quit(fails)


## 各店の Kit を一度組んで戸口・開間を読む（gate の戸口帯・構圖用；組んだ Node は捨てる）
func _kits(P: Dictionary) -> void:
	for s: Dictionary in P["shops"]:
		var kit := ML.build(s["rec"], lib, MW.EMBED)
		s["door_cx"] = float(kit.get_meta("door_cx"))
		s["door_w"] = float(kit.get_meta("door_w"))
		s["kinds"] = kit.get_meta("bay_kind")
		kit.free()


func _inject(P: Dictionary, nm: String) -> void:
	var items: Array = P["items"]
	var C: Dictionary = P["C"]
	var shop := func(id: String) -> Dictionary:
		for s: Dictionary in P["shops"]:
			if String(s["id"]) == id:
				return s
		return {}
	match nm:
		"n_float":
			for it: Dictionary in items:
				if String(it["tag"]) == "disp":
					it["y"] = float(it["y"]) + 0.3
					break
		"n_building":
			var s: Dictionary = shop.call("MW_S4")
			s["d"] = 6.8
		"n_parcel":
			var s: Dictionary = shop.call("MW_N2")
			s["d"] = 6.6
		"n_overlap":
			for it: Dictionary in items:
				if String(it["id"]).begins_with("ms_battari_"):
					var it2: Dictionary = it.duplicate(true)
					it2["p"] = (it["p"] as Vector2) + Vector2(0.2, 0.0)
					items.append(it2)
					break
		"n_lane":
			items.append(MW.item(C, "st_hiradai_yasai", Vector2(215.0, MW.Z_C), Vector2(0, 1), "disp"))
		"n_door":
			var s: Dictionary = shop.call("MW_N3")
			var dw := _door_world(s)
			items.append(MW.item(C, "sz_stool", MW.sp("N", dw.x, 0.6), Vector2(0, 1), "disp"))
		"n_market":
			items.append(MW.item(C, "kr_hakozumi", Vector2(238.4, -45.0), Vector2(1, 0), "back"))
		"n_access":
			items.append(MW.item(C, "kr_hakozumi", MW.ACCESS_FROM, Vector2(1, 0), "back"))
		"n_sight":
			P["shops"] = (P["shops"] as Array).filter(func(s: Dictionary) -> bool: return String(s["id"]) != "MW_N6")
		"n_compose":
			P["items"] = items.filter(func(it: Dictionary) -> bool: return String(it["id"]) != "ms_tsuna_chochin")
		"n_closed":
			P["items"] = items.filter(func(it: Dictionary) -> bool: return not String(it["id"]).begins_with("ms_battari_") or String(it.get("shop", "")).begins_with("MW_S"))
		"n_naka":
			for it: Dictionary in items:
				if String(it["tag"]) == MW.NAKA_TAG:
					it["p"] = (it["p"] as Vector2) + Vector2(0.0, 0.6 if String(it.get("shop", "")).begins_with("MW_N") else -0.6)
					break
		"n_even":
			for s: Dictionary in P["shops"]:
				s["tier"] = "mid"
		"n_lure":
			P["items"] = items.filter(func(it: Dictionary) -> bool: return not (String(it["id"]) == "ms_tsuna_chochin" and (MW.FLOOR["roji1"] as Rect2).has_point(it["p"])))
		"n_fan":
			items.append(MW.item(C, "ms_kido_26", (MW.SIGHT_MARKET[0] as Vector2).lerp(MW.SIGHT_MARKET[1], 0.35), Vector2(0.8, -0.6), "entr"))
		"n_anchor":
			P["anchors"] = (P["anchors"] as Array).filter(func(a: Dictionary) -> bool: return not String(a["activity"]).begins_with("vendor"))
		"n_water":
			var WS: RLib.TriSampler = C["WS"]
			for k in 40000:
				var q := Vector2(150.0 + (k % 400) * 1.0, -250.0 + (k / 400) * 4.0)
				var wh := WS.h(q.x, q.y)
				if not is_nan(wh) and wh > (C["S"] as RLib.TriSampler).h(q.x, q.y) + 0.05:
					for it: Dictionary in items:
						if String(it["tag"]) == "back":
							it["p"] = q
							break
					break
		"n_retired":
			items.append({"id": "ic_taru", "p": Vector2(213.0, -39.0), "yaw": 0.0, "tag": "back", "y": 1.2})
		"n_hung":
			for it: Dictionary in items:
				if String(it["id"]).begins_with("ms_noki_chochin"):
					it["p"] = (it["p"] as Vector2) + Vector2(0.0, 1.0 if (it["p"] as Vector2).y < MW.Z_C else -1.0)
					break


func _door_world(s: Dictionary) -> Vector2:
	var X: Transform3D = s["xf"]
	var w: Vector3 = X * Vector3(float(s["door_cx"]), 0.0, float(s["d"]) * 0.5)
	return Vector2(w.x, w.z)


## 戸口帯（開いた店の間の前：間口 ±0.55、牆線から 1.2 m）
func _door_poly(s: Dictionary) -> PackedVector2Array:
	var dw := _door_world(s)
	var sd := String(s["side"])
	var hw := minf(0.55, float(s["door_w"]) * 0.5)
	return PackedVector2Array([MW.sp(sd, dw.x - hw, 0.05), MW.sp(sd, dw.x + hw, 0.05), MW.sp(sd, dw.x + hw, 1.2), MW.sp(sd, dw.x - hw, 1.2)])


## 平面規劃図用の JSON（店・構件の足元・床・歩く通り・周りの P4 建物・市集の構件・anchors・視線）
func _dump(P: Dictionary, path: String) -> void:
	var C: Dictionary = P["C"]
	var pl2 := func(pl: PackedVector2Array) -> Array:
		var o: Array = []
		for q in pl:
			o.append([snappedf(q.x, 0.01), snappedf(q.y, 0.01)])
		return o
	var out := {"shops": [], "items": [], "floor": {}, "lanes": {}, "bld": [], "market": [], "anchors": [], "parcels": [],
		"sight_alley": [[MW.SIGHT_ALLEY[0].x, MW.SIGHT_ALLEY[0].y], [MW.SIGHT_ALLEY[1].x, MW.SIGHT_ALLEY[1].y]],
		"sight_market": [[MW.SIGHT_MARKET[0].x, MW.SIGHT_MARKET[0].y], [MW.SIGHT_MARKET[1].x, MW.SIGHT_MARKET[1].y]]}
	for s: Dictionary in P["shops"]:
		var r := MW.shop_rect(s)
		out["shops"].append({"id": s["id"], "type": s["type"], "trade": s["trade"], "side": s["side"], "rect": [r.position.x, r.position.y, r.size.x, r.size.y],
			"door": [_door_world(s).x, _door_world(s).y] if s.has("door_cx") else []})
	for it: Dictionary in P["items"]:
		var polys: Array = []
		for pl: PackedVector2Array in MW.polys(it):
			polys.append(pl2.call(pl))
		out["items"].append({"id": it["id"], "tag": it["tag"], "p": [(it["p"] as Vector2).x, (it["p"] as Vector2).y], "polys": polys})
	for k: String in MW.FLOOR:
		var r: Rect2 = MW.FLOOR[k]
		out["floor"][k] = [r.position.x, r.position.y, r.size.x, r.size.y]
	for k: String in MW.LANES:
		var r: Rect2 = MW.LANES[k]
		out["lanes"][k] = [r.position.x, r.position.y, r.size.x, r.size.y]
	for b: Dictionary in C["bld"]:
		var o: Vector2 = b["o"]
		if o.x > 185.0 and o.x < 250.0 and o.y > -70.0 and o.y < -5.0:
			var cs: Array = []
			for s2: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var q := o + (b["ax"] as Vector2) * s2.x * float(b["w"]) * 0.5 + (b["az"] as Vector2) * s2.y * float(b["d"]) * 0.5
				cs.append([snappedf(q.x, 0.01), snappedf(q.y, 0.01)])
			out["bld"].append({"name": b["name"], "c": cs})
	for o: Dictionary in C["market"]:
		if not (String(o["id"]) in MK.LINE):
			out["market"].append({"id": o["id"], "c": pl2.call(MK.corners(o))})
	for a: Dictionary in P["anchors"]:
		out["anchors"].append({"id": a["id"], "activity": a["activity"], "p": [(a["p"] as Vector2).x, (a["p"] as Vector2).y]})
	for pr: Array in parcels:
		var bbp := Rect2((pr[1] as PackedVector2Array)[0], Vector2.ZERO)
		for q in pr[1]:
			bbp = bbp.expand(q)
		if bbp.intersects(Rect2(195.0, -62.0, 50.0, 45.0)):
			out["parcels"].append({"id": pr[0], "c": pl2.call(pr[1])})
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	info("dump → %s" % path)


## P4 建物の屋根の外周までの距離（greybox.json の roof／ov_eave_m／ov_gable_m；平入＝棟は幅方向 ax → 妻＝±ax 端）
var _gb := {}


func _roof_d(b: Dictionary, q: Vector2) -> float:
	if _gb.is_empty():
		var G: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/gen/greybox.json"))
		for r: Dictionary in G["buildings"]:
			_gb[String(r["id"])] = r
	var r: Dictionary = _gb.get(String(b["name"]), {"roof": "hira", "ov_eave_m": 0.45, "ov_gable_m": 0.3})
	var hira := String(r.get("roof", "hira")) == "hira"
	var ovx := float(r.get("ov_gable_m", 0.3)) if hira else float(r.get("ov_eave_m", 0.45))
	var ovz := float(r.get("ov_eave_m", 0.45)) if hira else float(r.get("ov_gable_m", 0.3))
	var d := q - (b["o"] as Vector2)
	var lx := absf(d.dot(b["ax"])) - float(b["w"]) * 0.5 - ovx
	var lz := absf(d.dot(b["az"])) - float(b["d"]) * 0.5 - ovz
	if lx <= 0.0 and lz <= 0.0:
		return maxf(lx, lz)
	return Vector2(maxf(lx, 0.0), maxf(lz, 0.0)).length()


func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _in_parcel(p: Vector2) -> String:
	for pr: Array in parcels:
		if Geometry2D.is_point_in_polygon(p, pr[1]):
			return String(pr[0])
	return ""


func _known(it: Dictionary) -> bool:
	return MW.KITS.has(String(it["id"]).substr(0, 3))


func _checks(P: Dictionary) -> void:
	var items: Array = (P["items"] as Array).filter(func(it: Dictionary) -> bool: return _known(it))
	var all_items: Array = P["items"]
	var anchors: Array = P["anchors"]
	var shops: Array = P["shops"]
	var C: Dictionary = P["C"]
	C["shops"] = shops
	var R: RLib.TriSampler = C["R"]
	var F: RLib.TriSampler = C["F"]
	var srects: Array = shops.map(func(s: Dictionary) -> Rect2: return MW.shop_rect(s))
	# ── W1 Kit：構件の mesh（LOD0／LOD1）、ichi_kit 引退、mise_kit の材質＝町の既存材質のみ
	var miss: Array = []
	var retired: Array = []
	for it: Dictionary in all_items:
		var id := String(it["id"])
		if not _known(it):
			retired.append(id)
			continue
		if not ResourceLoader.exists(MW.mesh_dir(id) + id + ".res") or not ResourceLoader.exists(MW.mesh_dir(id) + id + "_l1.res"):
			miss.append(id)
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MW.kit_dir("ms_") + "src/modules_blender.json"))
	var badmat: Array = []
	for n: String in man["modules"]:
		for mt: String in man["modules"][n]["mats"]:
			if not (mt in MISE_MATS):
				badmat.append("%s:%s" % [n, mt])
	check("Kit：構件 %d の mesh（LOD0／LOD1）欠 %d %s；引退した ichi_kit・未登記の構件 %d %s；mise_kit の材質が町の既存材質以外 %d %s" % [all_items.size(), miss.size(),
		", ".join(miss.slice(0, 999 if verbose else 3)), retired.size(), ", ".join(retired.slice(0, 999 if verbose else 3)), badmat.size(), ", ".join(badmat.slice(0, 999 if verbose else 3))],
		miss.is_empty() and retired.is_empty() and badmat.is_empty() and all_items.size() >= 40)
	# ── W2 建物（町家 Kit 合成の店）：P4 建物の壁 0.3 m・軒どうし 0.2 m、路面、店どうし 0.2 m、台基の高さ
	var bb: Array = []
	for i in shops.size():
		var s: Dictionary = shops[i]
		var r: Rect2 = srects[i]
		var roof := r.grow_individual(MW.OV_GABLE, MW.OV_EAVE, MW.OV_GABLE, MW.OV_EAVE)
		var n_b := 0
		var n_roof := 0
		var n_road := 0
		var x := r.position.x
		while x <= r.end.x + 0.001:
			var z := r.position.y
			while z <= r.end.y + 0.001:
				var q := Vector2(x, z)
				for b: Dictionary in C["bld"]:
					if (b["o"] as Vector2).distance_to(q) < 14.0 and SL.obb_d(b, q) < 0.3:
						n_b += 1
				if not is_nan(R.h(q.x, q.y)):
					n_road += 1
				z += 0.25
			x += 0.25
		# 軒先（自分の屋根の外周）と P4 の屋根（OBB＋平入なら軒側 ov_eave・妻側 ov_gable、妻入は逆）の距離 ≥ 0.15
		var rx := roof.position.x
		while rx <= roof.end.x + 0.001:
			for rz: float in [roof.position.y, roof.end.y]:
				for b: Dictionary in C["bld"]:
					if (b["o"] as Vector2).distance_to(Vector2(rx, rz)) < 14.0 and _roof_d(b, Vector2(rx, rz)) < 0.15:
						n_roof += 1
			rx += 0.25
		var n_pair := 0
		for j in shops.size():
			if j != i and r.grow(0.2).intersects(srects[j]):
				n_pair += 1
		var plinth := float(s["base_h"]) - float(s["ground_lo"])
		if n_b > 0 or n_roof > 0 or n_road > 0 or n_pair > 0 or plinth > 0.45:
			bb.append("%s(壁%d 軒%d 路%d 隣%d 台%.2f)" % [s["id"], n_b, n_roof, n_road, n_pair, plinth])
	check("建物：店 %d 棟が P4 建物の壁 0.3 m・軒（屋根の外周）0.15 m・路面・隣の店 0.2 m に入らず台基 ≤ 0.45 m——違反 %d %s" % [shops.size(), bb.size(), ", ".join(bb.slice(0, 999 if verbose else 3))], bb.is_empty())
	# ── W3 地塊：店の足元（＋背面の軒先）は REAR_LOTS（中橫街の表店の敷地の後ろ半分）以外の地塊に入らない
	var pb: Array = []
	for i in shops.size():
		var r2: Rect2 = (srects[i] as Rect2).grow_individual(0.0, MW.OV_EAVE + 0.1, 0.0, MW.OV_EAVE + 0.1)
		var bad_ids := {}
		var x := r2.position.x
		while x <= r2.end.x + 0.001:
			var z := r2.position.y
			while z <= r2.end.y + 0.001:
				var pid := _in_parcel(Vector2(x, z))
				if pid != "" and not (pid in MW.REAR_LOTS):
					bad_ids[pid] = true
				z += 0.25
			x += 0.25
		if not bad_ids.is_empty():
			pb.append("%s∈%s" % [shops[i]["id"], ",".join(bad_ids.keys())])
	check("地塊：店（＋背面の軒先 0.45 m）が裏店の敷地（%s の後ろ半分）以外の地塊に入る %d %s" % [",".join(MW.REAR_LOTS), pb.size(), ", ".join(pb.slice(0, 999 if verbose else 3))], pb.is_empty())
	# ── W4 接地：浮き ≤ 0.02、沈み ≤ 0.15（掛け物は W5）
	var fl: Array = []
	var mx := 0.0
	var ground_items: Array = items.filter(func(it: Dictionary) -> bool: return not (String(it["id"]) in MW.HUNG) and String(it["tag"]) != MW.NAKA_TAG)
	var naka_items: Array = items.filter(func(it: Dictionary) -> bool: return String(it["tag"]) == MW.NAKA_TAG)
	var solid_items: Array = ground_items.filter(func(it: Dictionary) -> bool: return String(it["tag"]) != MW.PAVE_TAG)
	for it: Dictionary in ground_items:
		var y: float = it["y"]
		var sink := -1e9
		var fmin := 1e9
		var pts := PackedVector2Array([it["p"]])
		for poly: PackedVector2Array in MW.polys(it):
			pts.append_array(poly)
		for q: Vector2 in pts:
			var t := MW.ground_h(C, q)
			sink = maxf(sink, t - y)
			fmin = minf(fmin, y - t)
		mx = maxf(mx, sink)
		if fmin > 0.02 or sink > 0.15:
			fl.append("%s(浮 %.2f 沈 %.2f)" % [it["id"], fmin, sink])
	check("接地：%d 件 浮き ≤ 0.02 m・沈み ≤ 0.15 m（最大沈み %.2f）違反 %d %s" % [ground_items.size(), mx, fl.size(), ", ".join(fl.slice(0, 999 if verbose else 3))], fl.is_empty())
	# ── W5 掛け物：軒提灯・吊るし物は自分の店の正面（牆線 ±0.05、店の間口の中）、高さ＝台基＋2.0〜簷−0.1；吊り提灯は両端が壁 0.2 m 以内、提灯の下端 ≥ 1.95 m
	var hb: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if not (id in MW.HUNG):
			continue
		var p: Vector2 = it["p"]
		if id == "ms_tsuna_chochin":
			var sx := float(it.get("sx", 1.0))
			var ends: Array = [MW.local_to_world(it, Vector2(-2.2, 0.0)), MW.local_to_world(it, Vector2(2.2, 0.0))]
			var ok := true
			for e: Vector2 in ends:
				var dmin := 1e9
				for b: Dictionary in C["bld"]:
					if (b["o"] as Vector2).distance_to(e) < 14.0:
						dmin = minf(dmin, absf(SL.obb_d(b, e)))
				for r: Rect2 in srects:
					var dx := maxf(maxf(r.position.x - e.x, e.x - r.end.x), 0.0)
					var dz := maxf(maxf(r.position.y - e.y, e.y - r.end.y), 0.0)
					var din := minf(minf(e.x - r.position.x, r.end.x - e.x), minf(e.y - r.position.y, r.end.y - e.y))
					dmin = minf(dmin, Vector2(dx, dz).length() if (dx > 0.0 or dz > 0.0) else din)
				ok = ok and dmin <= 0.2
			var low := float(it["y"]) - 0.28 - 0.1 - 0.44
			var mid: Vector2 = ((ends[0] as Vector2) + (ends[1] as Vector2)) * 0.5
			var gmax := maxf(MW.ground_h(C, p), MW.ground_h(C, mid))
			if not ok or low - gmax < 1.95 or sx < 0.5 or sx > 1.5:
				hb.append("%s@(%.1f,%.1f)(端 %s 下端 %.2f)" % [id, p.x, p.y, ok, low - gmax])
			continue
		var host: Dictionary = {}
		for s: Dictionary in shops:
			if String(s["id"]) == String(it.get("shop", "")):
				host = s
		if host.is_empty():
			hb.append("%s(店なし)" % id)
			continue
		var wz := MW.Z_N if String(host["side"]) == "N" else MW.Z_S
		var rel := float(it["y"]) - float(host["base_h"])
		var eave := float(host["rec"]["eave_m"])
		if absf(p.y - wz) > 0.05 or p.x < float(host["x0"]) or p.x > float(host["x1"]) or rel < 2.0 or rel > eave - 0.1:
			hb.append("%s@%s(壁 %.2f 高 %.2f)" % [id, host["id"], absf(p.y - wz), rel])
	check("掛け物：軒提灯・吊るし物・吊り提灯が壁から外れる／高さ外 %d %s" % [hb.size(), ", ".join(hb.slice(0, 999 if verbose else 3))], hb.is_empty())
	# ── W6 路面・店先帯 ／ W7 封存 ／ W8 水際
	var bf: Array = []
	var bs: Array = []
	var bw: Array = []
	var others_mk: Array = []
	for o: Dictionary in C["market"]:
		if not (String(o["id"]) in MK.LINE):
			others_mk.append([MK.corners(o), "market:" + String(o["id"])])
	var others_st: Array = []
	for o: Dictionary in P["street"]:
		for pl: PackedVector2Array in SL.polys(o):
			others_st.append([pl, "street:" + String(o["id"])])
	for it: Dictionary in ground_items:
		var pls: Array = MW.polys(it)
		var sm := PackedVector2Array()
		for poly: PackedVector2Array in pls:
			sm.append_array(SL._poly_samples(poly, 0.15))
		var nf := 0
		var nsl := 0
		var nw := 0
		for q: Vector2 in sm:
			if not is_nan(F.h(q.x, q.y)) or not is_nan(R.h(q.x, q.y)):
				nf += 1
			if (C["block"] as Array).any(func(rr: Rect2) -> bool: return rr.has_point(q)):
				nsl += 1
			if SL.in_water(C, q):
				nw += 1
		for o: Array in others_mk:
			for pl: PackedVector2Array in pls:
				if not Geometry2D.intersect_polygons(pl, o[0]).is_empty():
					nsl += 1
		if nf > 0:
			bf.append("%s×%d" % [it["id"], nf])
		if nsl > 0:
			bs.append("%s×%d" % [it["id"], nsl])
		if nw > 0:
			bw.append("%s×%d" % [it["id"], nw])
	for i in shops.size():
		for o: Array in others_mk:
			if not Geometry2D.intersect_polygons(_rect_poly(srects[i]), o[0]).is_empty():
				bs.append("%s×%s" % [shops[i]["id"], o[1]])
		var sr: Rect2 = srects[i]
		if (C["block"] as Array).any(func(rr: Rect2) -> bool: return rr.intersects(sr)):
			bs.append("%s×封存 rect" % shops[i]["id"])
	check("路面・店先帯：足元が道路・P6 店先帯に載る件 %d %s" % [bf.size(), ", ".join(bf.slice(0, 999 if verbose else 3))], bf.is_empty())
	check("封存：足元・店が封存 overlay・市集 MarketP10 の構件／歩く通りに入る件 %d %s" % [bs.size(), ", ".join(bs.slice(0, 999 if verbose else 3))], bs.is_empty())
	check("水際：足元が水面・水際に入る件 %d %s" % [bw.size(), ", ".join(bw.slice(0, 999 if verbose else 3))], bw.is_empty())
	# ── W9 互不重疊：構件どうし・構件と店（建物）・構件と P4 建物（0.3 m）・StreetP10
	var ov: Array = []
	for i in ground_items.size():
		var pi: Array = MW.polys(ground_items[i])
		for j in range(i + 1, ground_items.size()):
			if (ground_items[i]["p"] as Vector2).distance_to(ground_items[j]["p"]) > 8.0:
				continue
			for a: PackedVector2Array in pi:
				for b2: PackedVector2Array in MW.polys(ground_items[j]):
					if not Geometry2D.intersect_polygons(a, b2).is_empty():
						ov.append("%s×%s" % [ground_items[i]["id"], ground_items[j]["id"]])
		for a: PackedVector2Array in pi:
			for k in srects.size():
				if not Geometry2D.intersect_polygons(a, _rect_poly((srects[k] as Rect2).grow(-0.02))).is_empty():
					ov.append("%s×%s" % [ground_items[i]["id"], shops[k]["id"]])
			for o: Array in others_st:
				if not Geometry2D.intersect_polygons(a, o[0]).is_empty():
					ov.append("%s×%s" % [ground_items[i]["id"], o[1]])
			for q: Vector2 in a:
				for b: Dictionary in C["bld"]:
					if (b["o"] as Vector2).distance_to(q) < 14.0 and SL.obb_d(b, q) < 0.3:
						ov.append("%s×%s" % [ground_items[i]["id"], b["name"]])
						break
	check("互不重疊：足元が重なる組 %d %s" % [ov.size(), ", ".join(ov.slice(0, 999 if verbose else 3))], ov.is_empty())
	# ── W10 歩く通り（通りの中央 2.8 m・辻から市集への連絡・主の口の路地）
	var in_lane: Array = []
	for ln: String in MW.LANES:
		var rp := _rect_poly(MW.LANES[ln])
		for it: Dictionary in solid_items:
			for a: PackedVector2Array in MW.polys(it):
				if not Geometry2D.intersect_polygons(a, rp).is_empty():
					in_lane.append("%s∈%s" % [it["id"], ln])
		for k in srects.size():
			if (MW.LANES[ln] as Rect2).intersects(srects[k]):
				in_lane.append("%s∈%s" % [shops[k]["id"], ln])
	check("歩く通り：通りの中央・クランク・市集への連絡・主の口の路地に足元が入る件 %d %s" % [in_lane.size(), ", ".join(in_lane.slice(0, 999 if verbose else 3))], in_lane.is_empty())
	# ── W11 戸口：開いた店の間（戸口）の前 1.2 m に陳列を置かない
	var dz_bad: Array = []
	for s: Dictionary in shops:
		if not s.has("door_cx"):
			continue
		var dp := _door_poly(s)
		for it: Dictionary in solid_items:
			for a: PackedVector2Array in MW.polys(it):
				if not Geometry2D.intersect_polygons(a, dp).is_empty():
					dz_bad.append("%s←%s" % [s["id"], it["id"]])
	if verbose:
		for s: Dictionary in shops:
			if s.has("door_cx"):
				info("%s door world %s w %.2f kinds %s" % [s["id"], _door_world(s), s["door_w"], s["kinds"]])
	check("戸口：店 %d 棟の戸口の前（間口 ±0.55・1.2 m）を塞ぐ件 %d %s" % [shops.size(), dz_bad.size(), ", ".join(dz_bad.slice(0, 999 if verbose else 3))], dz_bad.is_empty())
	# ── W12 到達：中橫街（主の口）→ 西小路の口・市集の西の通り・各客の立ち場（0.5 m 格子 BFS）
	var reach := _reach(P, solid_items, srects)
	var unreached: Array = []
	for a: Dictionary in anchors:
		if (String(a["activity"]).begins_with("customer") or String(a["activity"]) == "walk") and not reach.has(_cell(a["p"])):
			unreached.append(String(a["id"]))
	var to_ok: Array = []
	for q: Vector2 in MW.ACCESS_TO:
		to_ok.append(reach.has(_cell(q)))
	check("到達：中橫街の主の口 → 西小路の口 %s・市集の西の通り %s、客・行き交う人の立ち場へ届かない %d %s" % [to_ok[0], to_ok[1], unreached.size(), ", ".join(unreached.slice(0, 999 if verbose else 3))],
		not to_ok.has(false) and unreached.is_empty())
	# ── W13 視線：主の口から北 → 茶屋（主の店）の店の正面で止まる；路地 1 から北 → 呉服（主の店）の店の正面で止まる
	var sa := _sight_alley(P, srects, solid_items, MW.SIGHT_ALLEY)
	var sr := _sight_alley(P, srects, solid_items, MW.SIGHT_ROJI)
	check("視線：中橫街の主の口から北の突き当たり＝%s（要 %s）、路地 1 から北の突き当たり＝%s（要 %s）" % [sa, MW.SIGHT_ALLEY[2], sr, MW.SIGHT_ROJI[2]],
		sa == String(MW.SIGHT_ALLEY[2]) and sr == String(MW.SIGHT_ROJI[2]))
	# ── W17 市集の北西角の視野：扇 ±22°（1° 刻み）——近く（6 m 以内）を本 overlay の物・建物が塞がない（木戸なし；封存の市集の屋台は数えない）、開いた店（focal／mid）の正面に届く光線 ≥ 3 本、
	##     8 m 以上抜ける光線 ≥ 25 %、吊り提灯が 25 m 以内で扇の中に見える
	var fan := _market_fan(P, srects, solid_items)
	check("市集の北西角の視野：近くの遮り %d %s、開いた店の正面に届く光線 %d（%s）、8 m 以上抜ける %d %%、見える吊り提灯 %d" % [fan["near"], str(fan["near_what"]), fan["open_hits"],
		",".join(fan["shops"]), fan["far_pct"], fan["ropes"]], fan["near"] == 0 and fan["open_hits"] >= 3 and fan["far_pct"] >= 25 and fan["ropes"] >= 1)
	# ── W14 構圖
	var cont := {}
	for sd: String in ["N", "S"]:
		var ss: Array = shops.filter(func(s: Dictionary) -> bool: return String(s["side"]) == sd)
		var x0 := 1e9
		var x1 := -1e9
		var wsum := 0.0
		for s: Dictionary in ss:
			x0 = minf(x0, float(s["x0"]))
			x1 = maxf(x1, float(s["x1"]))
			wsum += float(s["x1"]) - float(s["x0"])
		cont[sd] = wsum / maxf(x1 - x0, 0.01) if ss.size() > 0 else 0.0
	var types := {}
	var trades := {}
	for s: Dictionary in shops:
		types[String(s["type"])] = int(types.get(String(s["type"]), 0)) + 1
		trades[String(s["trade"])] = true
	var ids: Array = items.map(func(it: Dictionary) -> String: return String(it["id"]))
	var awn_cols := {}
	for i2: String in ids:
		if i2.begins_with("ms_maku_"):
			awn_cols[i2] = true
	var cnt := func(pre: String) -> int:
		return ids.filter(func(i3: String) -> bool: return i3.begins_with(pre)).size()
	var signs := ids.filter(func(i3: String) -> bool: return i3.contains("kanban") or i3.contains("andon") or i3.contains("nobori") or i3.contains("fuda")).size()
	var back := items.filter(func(it: Dictionary) -> bool: return String(it["tag"]) == "back").size()
	var bare: Array = []
	for s: Dictionary in shops:
		var sid := String(s["id"])
		if not items.any(func(it: Dictionary) -> bool: return String(it.get("shop", "")) == sid and String(it["tag"]) in ["disp", "sign", "work"]):
			bare.append(sid)
	var covers := int(cnt.call("ms_maku_")) + int(cnt.call("ms_shitomi"))
	var compose_ok: bool = float(cont["N"]) >= 0.85 and float(cont["S"]) >= 0.6 and shops.size() >= 9 and int(types.get("nikai", 0)) >= 2 \
		and int(types.get("zushi", 0)) >= 4 and int(types.get("hiraya", 0)) >= 1 and trades.size() >= 8 and covers >= 5 and awn_cols.size() >= 2 \
		and int(cnt.call("ms_noki_chochin")) >= 8 and int(cnt.call("ms_tsuna_chochin")) >= 6 and int(cnt.call("ms_kido_")) == 2 \
		and signs >= 6 and back >= 5 and bare.is_empty()
	check("構圖：店列の連続 北 %.2f（≥ 0.85）南 %.2f（≥ 0.6）、店 %d（總二階 %d・厨子 %d・平屋 %d）、商い %d、覆い（幕＋蔀）%d（幕 %d 色）、軒提灯 %d、吊り提灯 %d、木戸 %d、看板類 %d、後場 %d、陳列なしの店 %d %s" % [
		cont["N"], cont["S"], shops.size(), int(types.get("nikai", 0)), int(types.get("zushi", 0)), int(types.get("hiraya", 0)), trades.size(), covers,
		awn_cols.size(), cnt.call("ms_noki_chochin"), cnt.call("ms_tsuna_chochin"), cnt.call("ms_kido_"), signs, back, bare.size(), ", ".join(bare)], compose_ok)
	# ── W18 店内：店内の陳列（ms_naka_*）は開いた店の間（shop_c／shop_k）の中、高さ＝建物の基準高（店台 0.72 に載る）
	var nb: Array = []
	for it: Dictionary in naka_items:
		var host: Dictionary = {}
		for s: Dictionary in shops:
			if String(s["id"]) == String(it.get("shop", "")):
				host = s
		var ok := not host.is_empty() and host.has("bays")
		if ok:
			var p: Vector2 = it["p"]
			var wz := MW.Z_N if String(host["side"]) == "N" else MW.Z_S
			var hw := 0.8 * float(it.get("sx", 1.0))
			var kinds_ok: Array = ["shop_o"] if String(it["id"]).begins_with("ms_tana_") else MW.OPEN_BAYS
			ok = absf(p.y - wz) < 0.02 and absf(float(it["y"]) - float(host["base_h"])) < 0.01 and (host["bays"] as Array).any(func(b: Dictionary) -> bool:
				return String(b["kind"]) in kinds_ok and p.x - hw >= float(b["u0"]) - 0.02 and p.x + hw <= float(b["u1"]) + 0.02)
		if not ok:
			nb.append("%s@%s" % [it["id"], it.get("shop", "")])
	# 店の灯：開いた店の間の奥（店の箱の中、壁線から 0.2–0.6 m 奥）
	var lb: Array = []
	for L: Dictionary in P.get("lights", []):
		var lp: Vector2 = L["p"]
		if L.get("geya", false):
			# 下屋の灯：下屋（ms_geya_*）の売り台の上、中心から 1 m 以内
			if not items.any(func(it: Dictionary) -> bool: return String(it["id"]).begins_with("ms_geya_") and (it["p"] as Vector2).distance_to(lp) < 1.0):
				lb.append("geya@(%.1f,%.1f)" % [lp.x, lp.y])
			continue
		var inside := false
		for r: Rect2 in srects:
			if r.has_point(lp):
				inside = true
		var dzl := absf(lp.y - MW.Z_N) if absf(lp.y - MW.Z_N) < absf(lp.y - MW.Z_S) else absf(lp.y - MW.Z_S)
		if not inside or dzl < 0.2 or dzl > 0.6:
			lb.append("%s@(%.1f,%.1f)" % [L["shop"], lp.x, lp.y])
	check("店内：店内の陳列・戸口の奥の棚 %d 件が開いた店の間の中に収まらない %d %s；店の灯 %d が店の間の奥にない %d %s" % [naka_items.size(), nb.size(),
		", ".join(nb.slice(0, 999 if verbose else 3)), (P.get("lights", []) as Array).size(), lb.size(), ", ".join(lb.slice(0, 3))],
		nb.is_empty() and naka_items.size() >= 9 and lb.is_empty() and (P.get("lights", []) as Array).size() >= 10)
	# ── W19 営業中：開いた店＝店内の陳列＋ばったり床几＋覆い（蔀か幕）＋掀げた暖簾；北 ≥ 4・南 ≥ 2。開いた店の店先（戸口の前を除く）の
	##     0–1.42 m に陳列・看板が続く割合 ≥ 0.6（連続した商業界面）
	var open_n := 0
	var open_s := 0
	var weak: Array = []
	var per := {}
	for s: Dictionary in shops:
		var sid := String(s["id"])
		var mine: Array = items.filter(func(it: Dictionary) -> bool: return String(it.get("shop", "")) == sid)
		per[sid] = mine.size()
		var has := func(pre: String) -> bool:
			return mine.any(func(it: Dictionary) -> bool: return String(it["id"]).begins_with(pre))
		if not (has.call("ms_naka_") and has.call("ms_battari_") and (has.call("ms_shitomi") or has.call("ms_maku_")) and has.call("ms_noren_age_")):
			continue
		# 店先の被覆：x の区間の和（陳列・看板・仕事の足元、v ≤ 1.45）÷（間口 − 戸口帯）
		var ivs: Array = []
		for it: Dictionary in mine:
			if not (String(it["tag"]) in ["disp", "sign", "work"]):
				continue
			for pl: PackedVector2Array in MW.polys(it):
				var lo := 1e9
				var hi := -1e9
				for q: Vector2 in pl:
					lo = minf(lo, q.x)
					hi = maxf(hi, q.x)
				ivs.append([maxf(lo, float(s["x0"])), minf(hi, float(s["x1"]))])
		ivs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var covered := 0.0
		var cur0 := -1e9
		var cur1 := -1e9
		for iv: Array in ivs:
			if float(iv[0]) > cur1:
				covered += maxf(cur1 - cur0, 0.0)
				cur0 = float(iv[0])
				cur1 = float(iv[1])
			else:
				cur1 = maxf(cur1, float(iv[1]))
		covered += maxf(cur1 - cur0, 0.0)
		var avail := float(s["x1"]) - float(s["x0"]) - minf(1.1, float(s.get("door_w", 1.1)))
		var ratio := covered / maxf(avail, 0.1)
		if ratio < 0.6:
			weak.append("%s %.2f" % [sid, ratio])
			continue
		if String(s["side"]) == "N":
			open_n += 1
		else:
			open_s += 1
	check("営業中：開いた店 北 %d（≥ 4）・南 %d（≥ 2）；店先の連続が 0.6 に届かない開いた店 %d %s" % [open_n, open_s, weak.size(), ", ".join(weak)],
		open_n >= 4 and open_s >= 2)
	# ── W20 主次：focal 2–3 店の物の数がすべて mid の最多より多い、quiet ≥ 1 店は物 ≤ 4、店ごとの物の数の變動係數 ≥ 0.35（平均に並べない）
	var tiers := {"focal": [], "mid": [], "quiet": []}
	var nums: Array = []
	for s: Dictionary in shops:
		var t := String(s.get("tier", ""))
		if tiers.has(t):
			(tiers[t] as Array).append(int(per[String(s["id"])]))
			nums.append(float(per[String(s["id"])]))
	var mean := 0.0
	for x: float in nums:
		mean += x
	mean /= maxf(nums.size(), 1.0)
	var var_ := 0.0
	for x: float in nums:
		var_ += (x - mean) * (x - mean)
	var cv := sqrt(var_ / maxf(nums.size(), 1.0)) / maxf(mean, 0.01)
	var fmin: int = (tiers["focal"] as Array).min() if not (tiers["focal"] as Array).is_empty() else 0
	var mmax: int = (tiers["mid"] as Array).max() if not (tiers["mid"] as Array).is_empty() else 0
	var quiet_ok := (tiers["quiet"] as Array).any(func(n: int) -> bool: return n <= 4)
	check("主次：focal %d 店 %s（最少 %d）＞ mid の最多 %d、quiet %s（≤ 4 の店あり %s）、物の數の變動係數 %.2f（≥ 0.35）" % [(tiers["focal"] as Array).size(),
		str(tiers["focal"]), fmin, mmax, str(tiers["quiet"]), quiet_ok, cv],
		(tiers["focal"] as Array).size() >= 2 and (tiers["focal"] as Array).size() <= 3 and fmin > mmax and quiet_ok and cv >= 0.35)
	# ── W21 入口の誘い：主の口の路地・路地 1 にそれぞれ吊り提灯 ≥ 2、主の口・路地 1 の突き当たりは focal の店（W13）、酒屋の角は路地へ回り込む
	var in_rect := func(r: Rect2) -> int:
		return items.filter(func(it: Dictionary) -> bool: return String(it["id"]) == "ms_tsuna_chochin" and r.has_point(it["p"])).size()
	var n_alley: int = in_rect.call(MW.FLOOR["alley"])
	var n_roji: int = in_rect.call(MW.FLOOR["roji1"])
	var corner := items.filter(func(it: Dictionary) -> bool: return String(it.get("shop", "")) == "MW_S4" and (it["p"] as Vector2).x > 226.5).size()
	var focal_ids: Array = shops.filter(func(s: Dictionary) -> bool: return String(s.get("tier", "")) == "focal").map(func(s: Dictionary) -> String: return String(s["id"]))
	check("入口の誘い：主の口の路地の吊り提灯 %d（≥ 2）、路地 1 の吊り提灯 %d（≥ 2）、突き当たりの店 %s／%s が focal、酒屋の路地側の外溢 %d（≥ 3）" % [n_alley, n_roji,
		MW.SIGHT_ALLEY[2], MW.SIGHT_ROJI[2], corner], n_alley >= 2 and n_roji >= 2 and String(MW.SIGHT_ALLEY[2]) in focal_ids and String(MW.SIGHT_ROJI[2]) in focal_ids and corner >= 3)
	# ── W15 NPC anchors：≥ 24、店ごとに売り手＋客（桶屋＝仕事＋客）、建物・店・足元の内に立たない、0.5 m 未満の組なし
	var by_ref := {}
	var bad: Array = []
	for a: Dictionary in anchors:
		var ref := String(a["ref"])
		if not by_ref.has(ref):
			by_ref[ref] = []
		(by_ref[ref] as Array).append(String(a["activity"]))
		var ap: Vector2 = a["p"]
		for b: Dictionary in C["bld"]:
			if (b["o"] as Vector2).distance_to(ap) < 14.0 and SL.obb_d(b, ap) < 0.15:
				bad.append(String(a["id"]))
		for r: Rect2 in srects:
			if r.has_point(ap):
				bad.append("%s∈店" % a["id"])
		for it: Dictionary in solid_items:
			for pl: PackedVector2Array in MW.polys(it):
				if Geometry2D.is_point_in_polygon(ap, pl):
					bad.append("%s∈%s" % [a["id"], it["id"]])
	var lack: Array = []
	for s: Dictionary in shops:
		var acts: Array = by_ref.get(String(s["id"]), [])
		var first := "work" if String(s["trade"]) == "okeya" else "vendor"
		if not (acts.any(func(t: String) -> bool: return t.begins_with(first)) and acts.any(func(t: String) -> bool: return t.begins_with("customer"))):
			lack.append(String(s["id"]))
	var close := 0
	for i in anchors.size():
		for j in range(i + 1, anchors.size()):
			if (anchors[i]["p"] as Vector2).distance_to(anchors[j]["p"]) < 0.5:
				close += 1
	check("NPC anchors：%d（≥ 24）、売り手（仕事）＋客の欠けた店 %d %s、建物・店・足元の内 %d %s、0.5 m 未満の組 %d" % [anchors.size(), lack.size(), ", ".join(lack),
		bad.size(), ", ".join(bad.slice(0, 999 if verbose else 3)), close], anchors.size() >= 24 and lack.is_empty() and bad.is_empty() and close == 0)
	# ── W16 床：区域ごとの床に面がある、路面・建物の上に張らない、上面 ≥ 見えている最上面＋0.03（P9 地被 ground＋0.016 の上）
	var fbad: Array = []
	var nfaces := 0
	for k: String in MW.FLOOR:
		var m := MW.floor_mesh(P, k)
		if m.get_surface_count() == 0:
			fbad.append(k + "(空)")
			continue
		var fv: PackedVector3Array = m.get_faces()
		nfaces += fv.size() / 3
		var step := maxi(1, fv.size() / 400)
		var i := 0
		while i < fv.size():
			var q := Vector2(fv[i].x, fv[i].z)
			if not is_nan(R.h(q.x, q.y)):
				fbad.append("%s 路面@(%.1f,%.1f)" % [k, q.x, q.y])
				break
			if fv[i].y < SL.top_h(C, q) + 0.03:
				fbad.append("%s 低@(%.1f,%.1f)" % [k, q.x, q.y])
				break
			var inb := false
			for b: Dictionary in C["bld"]:
				if (b["o"] as Vector2).distance_to(q) < 14.0 and SL.obb_d(b, q) < -0.05:
					inb = true
			if inb:
				fbad.append("%s 建物@(%.1f,%.1f)" % [k, q.x, q.y])
				break
			i += step
	check("床：区域 %d の床（%d 面）、空・路面の上・建物の内・地被より低い %d %s" % [MW.FLOOR.size(), nfaces, fbad.size(), ", ".join(fbad.slice(0, 999 if verbose else 3))], fbad.is_empty())


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / 0.5), floori(p.y / 0.5))


func _reach(P: Dictionary, items: Array, srects: Array) -> Dictionary:
	var C: Dictionary = P["C"]
	var bbx := Rect2(196.0, -60.0, 46.0, 40.0)
	var blocked := {}
	var x := bbx.position.x
	while x < bbx.end.x:
		var z := bbx.position.y
		while z < bbx.end.y:
			var q := Vector2(x + 0.25, z + 0.25)
			var blk := is_nan((C["S"] as RLib.TriSampler).h(q.x, q.y)) or SL.in_water(C, q)
			if not blk:
				for b: Dictionary in C["bld"]:
					if (b["o"] as Vector2).distance_to(q) < 14.0 and SL.obb_d(b, q) < 0.25:
						blk = true
						break
			if not blk:
				for r: Rect2 in srects:
					if r.grow(0.2).has_point(q):
						blk = true
						break
			if blk:
				blocked[_cell(q)] = true
			z += 0.5
		x += 0.5
	var polys: Array = []
	for it: Dictionary in items:
		polys.append_array(MW.polys(it))
	for o: Dictionary in C["market"]:
		if not (String(o["id"]) in MK.LINE):
			polys.append(MK.corners(o))
	for pl: PackedVector2Array in polys:
		var r := Rect2(pl[0], Vector2.ZERO)
		for q in pl:
			r = r.expand(q)
		r = r.grow(0.15)
		var xx := floorf(r.position.x / 0.5) * 0.5
		while xx <= r.end.x:
			var zz := floorf(r.position.y / 0.5) * 0.5
			while zz <= r.end.y:
				var q := Vector2(xx + 0.25, zz + 0.25)
				if Geometry2D.is_point_in_polygon(q, pl) or Geometry2D.get_closest_point_to_segment(q, pl[0], pl[2]).distance_to(q) < 0.12:
					blocked[_cell(q)] = true
				zz += 0.5
			xx += 0.5
	var seen := {}
	var start := _cell(MW.ACCESS_FROM)
	if blocked.has(start):
		return seen
	var queue: Array = [start]
	seen[start] = true
	var lo := _cell(bbx.position)
	var hi := _cell(bbx.end)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < lo.x or n.y < lo.y or n.x > hi.x or n.y > hi.y or seen.has(n) or blocked.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return seen


## 主の口から北へ：最初に当たる建物（本 overlay の店／P4 建物）の名前；途中に高さ ≥ 1.7 m の構件の足元があれば「構件名」
func _sight_alley(P: Dictionary, srects: Array, items: Array, line: Array) -> String:
	var C: Dictionary = P["C"]
	var a: Vector2 = line[0]
	var b: Vector2 = line[1]
	var n := int(a.distance_to(b) / 0.1)
	for i in n:
		var q := a.lerp(b, float(i) / n)
		for k in srects.size():
			if (srects[k] as Rect2).has_point(q):
				return String(P["shops"][k]["id"])
		for bl: Dictionary in C["bld"]:
			if (bl["o"] as Vector2).distance_to(q) < 14.0 and SL.obb_d(bl, q) < 0.0:
				return String(bl["name"])
		for it: Dictionary in items:
			if float(MW.box(String(it["id"]))[2]) >= TALL and MW.pole_key(String(it["id"])) == "":
				for pl: PackedVector2Array in MW.polys(it):
					if Geometry2D.is_point_in_polygon(q, pl):
						return "構件:" + String(it["id"])
	return "なし"


## 市集の北西角の視野（2D）：SIGHT_MARKET[0] から [1] の方向へ ±22° の扇、1° 刻み。各光線は 0.1 m ずつ進み、
##   P4 建物・本 overlay の店・市集 MarketP10 の構件・高さ ≥ 1.7 m の構件に当たると止まる。
func _market_fan(P: Dictionary, srects: Array, items: Array) -> Dictionary:
	var C: Dictionary = P["C"]
	var a: Vector2 = MW.SIGHT_MARKET[0]
	var d0 := ((MW.SIGHT_MARKET[1] as Vector2) - a).normalized()
	var mk: Array = []
	for o: Dictionary in C["market"]:
		if not (String(o["id"]) in MK.LINE):
			mk.append(MK.corners(o))
	var tall: Array = []
	for it: Dictionary in items:
		if float(MW.box(String(it["id"]))[2]) >= TALL and MW.pole_key(String(it["id"])) == "" and not (String(it["id"]) in MW.HUNG):
			tall.append_array(MW.polys(it))
	var kido: Array = []
	for it: Dictionary in items:
		if String(it["id"]).begins_with("ms_kido_"):
			kido.append_array(MW.polys(it))
	var near := 0
	var near_what := {}
	var far := 0
	var hits := 0
	var shops_hit := {}
	var n := 0
	for k in range(-22, 23):
		n += 1
		var dir := d0.rotated(deg_to_rad(float(k)))
		var dist := 0.0
		while dist < 30.0:
			var q := a + dir * dist
			var hit := ""
			for i in srects.size():
				if (srects[i] as Rect2).has_point(q):
					hit = "shop:%d" % i
			if hit == "":
				for bl: Dictionary in C["bld"]:
					if (bl["o"] as Vector2).distance_to(q) < 14.0 and SL.obb_d(bl, q) < 0.0:
						hit = "bld"
						break
			if hit == "":
				for pl: PackedVector2Array in mk:
					if Geometry2D.is_point_in_polygon(q, pl):
						hit = "market"
						break
			if hit == "":
				for pl: PackedVector2Array in tall:
					if Geometry2D.is_point_in_polygon(q, pl):
						hit = "tall"
						break
			if hit == "" and dist < 6.0:
				for pl: PackedVector2Array in kido:
					if Geometry2D.is_point_in_polygon(q, pl) or Geometry2D.get_closest_point_to_segment(q, pl[0], pl[2]).distance_to(q) < 0.3:
						hit = "kido"
			if hit != "":
				if dist < 6.0:
					near_what[hit] = int(near_what.get(hit, 0)) + 1
					if hit != "market":          # 封存の市集の屋台は市集そのもの（視點が市集の中）——本 overlay の物と建物だけを数える
						near += 1
				if hit.begins_with("shop:"):
					var s: Dictionary = P["shops"][int(hit.substr(5))]
					if String(s.get("tier", "")) in ["focal", "mid"]:
						hits += 1
						shops_hit[String(s["id"])] = true
				break
			dist += 0.1
		if dist >= 8.0:
			far += 1
	# 吊り提灯：中心が 25 m 以内・扇の中、そこまでの 2D 線が建物に当たらない
	var ropes := 0
	for it: Dictionary in P["items"]:
		if String(it["id"]) != "ms_tsuna_chochin":
			continue
		var c: Vector2 = it["p"]
		var v := c - a
		if v.length() > 25.0 or absf(rad_to_deg(d0.angle_to(v))) > 22.0:
			continue
		var blocked := false
		var steps := int(v.length() / 0.1)
		for j in steps:
			var q := a + v * (float(j) / steps)
			for bl: Dictionary in C["bld"]:
				if (bl["o"] as Vector2).distance_to(q) < 14.0 and SL.obb_d(bl, q) < 0.0:
					blocked = true
			for pl: PackedVector2Array in mk:
				if Geometry2D.is_point_in_polygon(q, pl):
					blocked = true
			if blocked:
				break
		if not blocked:
			ropes += 1
	return {"near": near, "near_what": near_what, "open_hits": hits, "shops": shops_hit.keys(), "far_pct": int(100.0 * far / maxf(n, 1)), "ropes": ropes}


func _seal_mismatch(seal: Dictionary) -> PackedStringArray:
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	var docs := repo + "docs/art_review/village_v2_p10_props/"
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


## 依存：P10 R1（MarketP10）封存と P9 R5（地被、路地 1 の限定解封後の再封存）の現在の雜湊が、R1b 封存時に記録した値と一致
func _dep_mismatch(seal: Dictionary) -> PackedStringArray:
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	var bad := PackedStringArray()
	var deps: Dictionary = seal["dependencies"]
	for k: String in deps["files"]:
		if not FileAccess.file_exists(repo + k):
			bad.append("%s 不存在" % k)
		elif FileAccess.get_sha256(repo + k) != String(deps["files"][k]):
			bad.append("%s 雜湊変了" % k)
	var r5: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R5_SEAL))
	var ev: Array = (r5.get("reseal_history", []) as Array).map(func(e: Dictionary) -> String: return String(e.get("event", "")))
	if not (String(deps["p9r5_reseal_event"]) in ev):
		bad.append("P9 R5 seal に %s がない" % deps["p9r5_reseal_event"])
	return bad


func _seal() -> int:
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	var bad := _seal_mismatch(seal)
	var n: int = seal["frozen"].size() + seal["art_review_images"].size() + seal["evidence"].size()
	check("P10 R1b Market West r3 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 圖 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var dbad := _dep_mismatch(seal)
	check("依存：P10 R1 MarketP10 封存・P9 R5 地被（路地 1 限定解封後の再封存）の雜湊が R1b 封存時と一致（不符 %d：%s）" % [dbad.size(), ", ".join(dbad)], dbad.is_empty())
	var txt := FileAccess.get_file_as_string(SCENE)
	var i_mk := txt.find("[node name=\"MarketP10\" parent=\"Props\"")
	var i_st := txt.find("[node name=\"StreetP10\" parent=\"Props\"")
	var i_mw := txt.find("[node name=\"MarketWestP10\" parent=\"Props\"")
	check("village_v2.tscn 掛載 Props/MarketP10 → StreetP10 → MarketWestP10（%s 恰 1 個）" % MW.OUTPUT,
		i_mk >= 0 and i_st > i_mk and i_mw > i_st and txt.count("instance=ExtResource(\"p10r1b_market_west\")") == 1 and txt.contains(MW.OUTPUT))
	var verdicts: Array = seal.get("verdicts", [])
	var lights: Dictionary = seal.get("shop_lights", {})
	check("裁定の記録：verdicts %d 項（= 10）、店の灯 %d 盞（= 18、保留・P13 は強度／色温／範囲／全域バランスのみ調整可）" % [verdicts.size(), int(lights.get("count", 0))],
		verdicts.size() == 10 and int(lights.get("count", 0)) == 18 and String(lights.get("ruling", "")) == "KEEP")
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	var neg_dep := seal.duplicate(true)
	var d0: String = neg_dep["dependencies"]["files"].keys()[0]
	neg_dep["dependencies"]["files"][d0] = "0".repeat(64)
	check("反向：依存 %s の期望雜湊を竄改 → 偵測（実際 %d）" % [d0, _dep_mismatch(neg_dep).size() - dbad.size()], _dep_mismatch(neg_dep).size() == dbad.size() + 1)
	print("[MW] 結果：%d 項失敗（seal）" % fails)
	return fails


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(MW.OUTPUT):
		push_error("找不到 %s（先 --build）" % MW.OUTPUT)
		return 1
	if txt.contains("gen/market_west_p10.scn"):
		push_error("已經掛過 MarketWestP10")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var st_line := "[node name=\"StreetP10\" parent=\"Props\" instance=ExtResource(\"p10r2_street\")]"
	if txt.count(st_line) != 1:
		push_error("StreetP10 の掛載行が見つからない")
		return 1
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var done := false
	var i := 0
	while i < lines.size():
		out.append(lines[i])
		if not done and lines[i] == st_line:
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"MarketWestP10\" parent=\"Props\" instance=ExtResource(\"p10r1b_market_west\")]")
			out.append("")
			done = true
			continue
		i += 1
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p10r1b_market_west\"]" % MW.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[MW] attach：加 Props/MarketWestP10（StreetP10 の後）→ %s" % SCENE)
	return 0


func _scene(v: Node3D) -> void:
	var txt := FileAccess.get_file_as_string(SCENE)
	var i_mk := txt.find("[node name=\"MarketP10\" parent=\"Props\"")
	var i_st := txt.find("[node name=\"StreetP10\" parent=\"Props\"")
	var i_mw := txt.find("[node name=\"MarketWestP10\" parent=\"Props\"")
	var go := v.get_node_or_null(MW.PARENT + "/" + MW.NODE_NAME)
	check("場景已掛 Props/MarketP10 → StreetP10 → MarketWestP10（各 1 個）", go != null and go.scene_file_path == MW.OUTPUT and i_mk >= 0 and i_st > i_mk and i_mw > i_st
		and txt.count("instance=ExtResource(\"p10r1b_market_west\")") == 1)
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MARKET_SEAL))
	check("MarketP10 封存：gen/market_p10.scn 雜湊＝封存時", FileAccess.get_sha256(MK.OUTPUT) == String(seal["frozen"]["godot/maps/village_v2/gen/market_p10.scn"]))
	if go == null:
		return
	for i in 4:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var terrain_y := func(o: Vector3) -> float:
		var q := PhysicsRayQueryParameters3D.create(o + Vector3(0, 30, 0), o + Vector3(0, -10, 0))
		var ex: Array[RID] = []
		for k in 20:
			q.exclude = ex
			var hit := sp.intersect_ray(q)
			if hit.is_empty():
				return NAN
			var cn := String((hit.collider as Node).name)
			if cn.begins_with("TerrainCollision") or (hit.collider as Node).get_parent().name == "Roads" or cn.contains("Road"):
				return hit.position.y
			ex.append(hit.rid)
		return NAN
	# 構件：原點と地形（衝突體）の差 ≤ 0.22（床 +0.04・店先帯 +0.10 を含む）；掛け物は除く
	var n_i := 0
	var bad: Array = []
	var nolod: Array = []
	for grp: String in ["Stalls", "Signs", "Entrances", "Back", "Paving"]:
		for n in go.get_node(grp).get_children():
			var id := String(n.get_meta("mw_id", ""))
			var l0 := n.get_node_or_null("LOD0") as MeshInstance3D
			var l1 := n.get_node_or_null("LOD1") as MeshInstance3D
			if l0 == null or l1 == null or l0.mesh == null or l1.mesh == null:
				nolod.append(String(n.name))
			if id in MW.HUNG:
				continue
			n_i += 1
			var o := (n as Node3D).global_position
			var gy: float = terrain_y.call(o)
			if is_nan(gy) or absf(gy - o.y) > 0.22:
				bad.append("%s(Δ%s)" % [n.name, "nan" if is_nan(gy) else "%.2f" % (o.y - gy)])
	check("接地射線：%d 件（陳列・看板・入口・後場・敷石）の原點と地形（衝突體）の差 ≤ 0.22 m 違反 %d %s" % [n_i, bad.size(), ", ".join(bad.slice(0, 999 if verbose else 3))], bad.is_empty() and n_i >= 60)
	check("LOD：構件の LOD0／LOD1 mesh（欠 %d %s）" % [nolod.size(), ", ".join(nolod.slice(0, 999 if verbose else 3))], nolod.is_empty())
	# 建物：町家 Kit（LOD0／1／2）・店先帯、原點＝足元の最高地形（地形の上 0–0.3 m）
	var bbad: Array = []
	var nb := 0
	for b in go.get_node("Buildings").get_children():
		nb += 1
		var kit := b.get_node_or_null("Kit")
		var fr := b.get_node_or_null("Frontage")
		var k0 := kit.get_node("LOD0").get_child_count() if kit else 0
		var k1 := kit.get_node("LOD1").get_child_count() if kit else 0
		var k2 := kit.get_node("LOD2").get_child_count() if kit else 0
		var o := (b as Node3D).global_position
		var gy: float = terrain_y.call(o)
		if kit == null or fr == null or k0 < 20 or k1 < 3 or k2 < 3 or is_nan(gy) or o.y < gy - 0.02 or o.y - gy > 0.3:
			bbad.append("%s(LOD %d/%d/%d 帯 %s Δ%.2f)" % [b.name, k0, k1, k2, fr != null, o.y - gy])
	check("建物：%d 棟に町家 Kit（LOD0／1／2）・店先帯、原點が地形の上 0–0.3 m（違反 %d %s）" % [nb, bbad.size(), ", ".join(bbad.slice(0, 999 if verbose else 3))], bbad.is_empty() and nb >= 9)
	var nf := 0
	var fbad: Array = []
	for f in go.get_node("Floor").get_children():
		var mi := f as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0 or mi.material_override == null:
			fbad.append(String(f.name))
		else:
			nf += 1
	check("床：区域ごとの床 %d（面・材質の欠 %d %s）" % [nf, fbad.size(), ", ".join(fbad)], nf == MW.FLOOR.size() and fbad.is_empty())
	var ns := go.get_node("Collision").get_child_count()
	var na := go.get_node("Anchors").get_child_count()
	var nl := go.get_node("ShopLights").get_child_count() if go.has_node("ShopLights") else 0
	var nr := 0
	for b in go.get_node("Buildings").get_children():
		if (b.get_node("Kit") as Node).get_meta("noren_lifted", false):
			var left := 0
			for lod_n in b.get_node("Kit").get_children():
				for c in lod_n.get_children():
					if String(c.name).begins_with("nr_"):
						left += 1
			nr += 1
			if left > 2:
				fbad.append("%s 暖簾 nr_ %d 残る" % [b.name, left])
	check("営業中の店：掀げた暖簾の店 %d（町家 Kit の戸口の暖簾を外した）、店の灯 %d（OmniLight・影なし）" % [nr, nl], nr >= 7 and nl >= 10 and fbad.is_empty())
	check("碰撞 %d shapes、NPC anchors %d（group＋activity meta）" % [ns, na], ns >= 40 and na >= 24 and go.get_node("Anchors").get_children().all(func(a: Node) -> bool: return a.is_in_group("npc_activity_anchor")))
	check("MultiMesh を使わない：%d" % go.find_children("*", "MultiMeshInstance3D", true, false).size(), go.find_children("*", "MultiMeshInstance3D", true, false).is_empty())
