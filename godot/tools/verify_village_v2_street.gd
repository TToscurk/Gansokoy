extends SceneTree
## 人間之里 V2 P10 R2 主街 Street Life gate（構造の機械検査；美術判定は同機位 TPS BEFORE／AFTER）。
##   godot --headless --path . --script res://tools/verify_village_v2_street.gd                 規劃 gate
##   godot --headless --path . --script res://tools/verify_village_v2_street.gd -- --map        規劃の内訳（店・商い・置けなかった物）
##   godot --headless --path . --script res://tools/verify_village_v2_street.gd -- --negatives  永久反向（各案が瞄準項を FAIL させる）
##   godot --headless --path . --script res://tools/verify_village_v2_street.gd -- --build      gate PASS 時のみ gen/street_p10.scn を書く
##   godot --headless --path . --script res://tools/verify_village_v2_street.gd -- --attach     village_v2.tscn の Props/MarketP10 の後へ StreetP10 を掛ける（1 回だけ）
##   godot --path . --script res://tools/verify_village_v2_street.gd -- --scene                 場景級（掛載順・接地射線・碰撞・LOD・MarketP10 封存）
## 每項一行 [STR] PASS/FAIL；結尾 quit(失敗項數)。
const SL := preload("res://tools/village_v2_street_lib.gd")
const MK := preload("res://tools/village_v2_market_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const VEG_ORDER := ["ForestP9", "BambooP9", "HiedaGardenP9", "ShrineGroveP9", "SchoolYardP9", "WatersideP9", "TowerYardP9", "SuzunaanP9", "GeidonteiP9", "KirisameP9", "GroundcoverP9"]
const MARKET_SEAL := "res://data/village_v2_p10r1_seal.json"
## 主街の視點（辻の手前・向こう）→ 市の大看板が見えること；中橫街の口の前 → 市集の色（提灯・屋台）が見えること
const MS_VIEW := [Vector2(263.6, -12.0), Vector2(263.0, -27.0), Vector2(258.0, -6.0), Vector2(266.5, -36.0)]
const MOUTH_VIEW := [Vector2(246.0, -20.6), Vector2(243.0, -20.4), Vector2(249.0, -20.8)]
const CLEAR_MAIN := 4.5
const CLEAR_CROSS := 3.5

var fails := 0
var failed_labels: Array = []
var quiet := false
var vroot: Node3D


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[STR] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(s: String) -> void:
	if not quiet:
		print("[STR] INFO " + s)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--attach" in args:
		quit(_attach())
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	if "--scene" in args:
		root.add_child(v)
		await _scene(v)
		print("[STR] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var old := v.get_node_or_null(SL.PARENT + "/" + SL.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	root.add_child(v)
	vroot = v
	await physics_frame
	var P := SL.plan(v)
	info("規劃 %d 件、anchors %d、主街の店 %d（%d ms）；置けなかった候補 %d" % [(P["items"] as Array).size(), (P["anchors"] as Array).size(),
		(P["shops"] as Array).size(), P["ms"], (P["dropped"] as Array).size()])
	if "--map" in args:
		_map(P)
	var surveyed := false
	for a: String in args:
		if a.begins_with("--survey="):
			var xy := a.trim_prefix("--survey=").split(",")
			_survey(P, Vector2(float(xy[0]), float(xy[1])), float(xy[2]) if xy.size() > 2 else 12.0)
			surveyed = true
	if surveyed:
		quit(0)
		return
	if "--lots" in args:
		_lots(P)
		quit(0)
		return
	if "--farmlots" in args:
		_farmlots(P)
		quit(0)
		return
	if "--negatives" in args:
		var target := {"n_float": "接地", "n_building": "建物", "n_frontage": "店先帯", "n_sealed": "封存", "n_overlap": "互不重疊",
			"n_door": "戸口", "n_road": "通行", "n_clone": "構圖", "n_entrance": "市の入口", "n_cross": "巷口", "n_farm": "農田", "n_anchor": "NPC", "n_life": "暮らし", "n_water": "水際"}
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
			print("[STR] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d：%s）" % ["PASS" if hit else "FAIL", nm, target[nm], failed_labels.size(),
				", ".join(failed_labels.map(func(l: String) -> String: return l.substr(0, 6)))])
			if not hit:
				bad += 1
		print("[STR] 結果：%d 項失敗（negatives）" % bad)
		quit(bad)
		return
	_checks(P)
	if "--build" in args and fails == 0:
		var r := SL.bake(P)
		var holder := Node3D.new()
		holder.add_child(r)
		SL.own(r, r)
		var ps := PackedScene.new()
		var e := ps.pack(r)
		var e2 := ResourceSaver.save(ps, SL.OUTPUT, ResourceSaver.FLAG_COMPRESS) if e == OK else e
		check("save %s（items %d、anchors %d、碰撞 %d）" % [SL.OUTPUT, r.get_meta("items"), r.get_meta("anchors"), r.get_meta("shapes")], e2 == OK)
		holder.free()
	print("[STR] 結果：%d 項失敗" % fails)
	quit(fails)


func _map(P: Dictionary) -> void:
	for sd: float in P["sides"]:
		for b: Dictionary in P["sides"][sd]:
			var n := (P["items"] as Array).filter(func(it: Dictionary) -> bool: return String(it.get("b", "")) == String(b["name"])).map(
				func(it: Dictionary) -> String: return String(it["id"]).substr(0, 14))
			print("[STR] MAP side %+d s=%5.1f %-12s %-9s w=%.1f door=%+.2f %s" % [int(sd), b["s"], String(b["name"]).trim_prefix("B_P_"), b["trade"], b["w"], b["door_cx"], ", ".join(n)])
	var tags := {}
	for it: Dictionary in P["items"]:
		var t := String(it["tag"]).split(":")[0]
		tags[t] = int(tags.get(t, 0)) + 1
	print("[STR] MAP tags ", tags)
	for it: Dictionary in P["items"]:
		var t := String(it["tag"])
		if not (t.begins_with("shop") or t == "res" or t == "fire"):
			print("[STR] MAP %-14s %-16s (%.1f, %.1f) y=%.2f" % [t, it["id"], (it["p"] as Vector2).x, (it["p"] as Vector2).y, it["y"]])
	for d: String in P["dropped"]:
		print("[STR] DROP ", d)


## 佔用の ASCII 地図（0.5 m、x 右・z 下）：B 建物（壁 0.3 m 内）f 店先帯 R 路面 S 封存 M 市集 I 本 overlay の物 D 戸口前 F 農田 ~ 地形なし . 空き
func _survey(P: Dictionary, c: Vector2, r: float) -> void:
	var C: Dictionary = P["C"]
	var FS := RLib.TriSampler.new()
	var fm := vroot.get_node_or_null("Terrain/FarmlandTerrain") as MeshInstance3D
	if fm:
		FS.add(fm.mesh.get_faces(), RLib.rel_xf(fm, vroot))
	print("[STR] SURVEY (%.1f, %.1f) ±%.0f m（列＝x %.1f→、行＝z %.1f↓）" % [c.x, c.y, r, c.x - r, c.y - r])
	var z := c.y - r
	while z <= c.y + r:
		var row := "%7.1f " % z
		var x := c.x - r
		while x <= c.x + r:
			var q := Vector2(x, z)
			var ch := "."
			if is_nan((C["S"] as RLib.TriSampler).h(q.x, q.y)):
				ch = "~"
			elif (C["bld"] as Array).any(func(b: Dictionary) -> bool: return (b["o"] as Vector2).distance_to(q) < 12.0 and SL.obb_d(b, q) < 0.3):
				ch = "B"
			elif not is_nan((C["F"] as RLib.TriSampler).h(q.x, q.y)):
				ch = "f"
			elif (P["items"] as Array).any(func(it: Dictionary) -> bool: return SL.polys(it).any(func(pl: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(q, pl))):
				ch = "I"
			elif (C["market"] as Array).any(func(o: Dictionary) -> bool: return Geometry2D.is_point_in_polygon(q, MK.corners(o))):
				ch = "M"
			elif (C["block"] as Array).any(func(rr: Rect2) -> bool: return rr.has_point(q)):
				ch = "S"
			elif (C["bld"] as Array).any(func(b: Dictionary) -> bool: return (b["o"] as Vector2).distance_to(q) < 12.0 and Geometry2D.is_point_in_polygon(q, SL.door_poly(b))):
				ch = "D"
			elif not is_nan((C["R"] as RLib.TriSampler).h(q.x, q.y)):
				ch = "R"
			elif not is_nan(FS.h(q.x, q.y)):
				ch = "F"
			if absf(x - c.x) < 0.01 and absf(z - c.y) < 0.01:
				ch = "@"
			row += ch
			x += 0.5
		print("[STR] " + row)
		z += 0.5


## 主街から見える空き地（作業場の候補）：主街の路縁から 1.0–9 m、通りに平行な 2.6 × 1.8 m の箱が全部空き（建物・店先帯・路面・封存・市集・本 overlay・戸口前・農田なし）
func _lots(P: Dictionary) -> void:
	var C: Dictionary = P["C"]
	var ms: PackedVector2Array = C["roads"]["MainStreet"]["pts"]
	var hw: float = C["roads"]["MainStreet"]["hw"]
	var L := SL.pl_len(ms)
	var s := 2.0
	var found: Array = []
	while s < L - 2.0:
		var pp: Array = SL.pl_point(ms, s)
		var c: Vector2 = pp[0]
		var tg: Vector2 = pp[1]
		for side: float in [-1.0, 1.0]:
			var nrm := Vector2(-tg.y, tg.x) * side
			var off := hw + 1.0
			while off <= hw + 9.0:
				var ctr := c + nrm * (off + 0.9)
				var ok := true
				var a := -1.3
				while a <= 1.3 and ok:
					var bb := -0.9
					while bb <= 0.9 and ok:
						var q := ctr + tg * a + nrm * bb
						if is_nan((C["S"] as RLib.TriSampler).h(q.x, q.y)) or not is_nan((C["R"] as RLib.TriSampler).h(q.x, q.y)) or not is_nan((C["F"] as RLib.TriSampler).h(q.x, q.y)):
							ok = false
						elif (C["bld"] as Array).any(func(b: Dictionary) -> bool: return (b["o"] as Vector2).distance_to(q) < 12.0 and (SL.obb_d(b, q) < 0.3 or Geometry2D.is_point_in_polygon(q, SL.door_poly(b)))):
							ok = false
						elif (C["block"] as Array).any(func(rr: Rect2) -> bool: return rr.has_point(q)):
							ok = false
						elif (C["market"] as Array).any(func(o: Dictionary) -> bool: return (o["p"] as Vector2).distance_to(q) < 4.0):
							ok = false
						elif (P["items"] as Array).any(func(it: Dictionary) -> bool: return (it["p"] as Vector2).distance_to(q) < 1.0):
							ok = false
						bb += 0.3
					a += 0.3
				if ok and _los(C, c, ctr):
					found.append("s=%5.1f side %+d off=%.1f ctr=(%.1f, %.1f) face=(%.2f, %.2f)" % [s, int(side), off - hw, ctr.x, ctr.y, -nrm.x, -nrm.y])
					break
				off += 0.5
		s += 3.0
	for f: String in found:
		print("[STR] LOT " + f)


## 農田→住宅の境の候補：田から 2–10 m、建物から 25 m 以内、4.2 × 2.0 m の箱が空きで起伏 ≤ 0.15 m（2 m 格子で走査）
func _farmlots(P: Dictionary) -> void:
	var C: Dictionary = P["C"]
	var FS: RLib.TriSampler = C["FS"]
	var x := 296.0
	while x < 380.0:
		var z := -150.0
		while z < 110.0:
			var c := Vector2(x, z)
			z += 2.0
			var dfarm := 99.0
			for k in 24:
				var a := TAU * k / 24.0
				for rr in [2.0, 4.0, 6.0, 8.0, 10.0, 13.0, 16.0, 20.0, 24.0]:
					var q: Vector2 = c + Vector2(cos(a), sin(a)) * rr
					if not is_nan(FS.h(q.x, q.y)):
						dfarm = minf(dfarm, rr)
			if dfarm > 24.0 or dfarm < 2.0:
				continue
			var dmin := 99.0
			for b: Dictionary in C["bld"]:
				dmin = minf(dmin, SL.obb_d(b, c))
			if dmin > 25.0 or dmin < 2.0:
				continue
			var ok := true
			var hmin := 1e9
			var hmax := -1e9
			var a2 := -2.1
			while a2 <= 2.1 and ok:
				var b2 := -1.0
				while b2 <= 1.0 and ok:
					var q := c + Vector2(a2, b2)
					var h := SL.top_h(C, q)
					if is_nan(h) or not is_nan(FS.h(q.x, q.y)) or not is_nan((C["R"] as RLib.TriSampler).h(q.x, q.y)) or (C["block"] as Array).any(func(rr: Rect2) -> bool: return rr.has_point(q)) or SL.in_water(C, q):
						ok = false
					else:
						hmin = minf(hmin, h)
						hmax = maxf(hmax, h)
					b2 += 0.5
				a2 += 0.5
			if ok and hmax - hmin <= 0.15:
				print("[STR] FARMLOT (%.0f, %.0f) 田 %.0f m 建物 %.1f m 起伏 %.2f h=%.2f" % [c.x, c.y, dfarm, dmin, hmax - hmin, hmin])
		x += 2.0


func _inject(P: Dictionary, nm: String) -> void:
	var items: Array = P["items"]
	var C: Dictionary = P["C"]
	var shop_items := items.filter(func(x: Dictionary) -> bool: return String(x["tag"]).begins_with("shop:"))
	match nm:
		"n_float":
			items[0]["y"] = float(items[0]["y"]) + 0.3
		"n_building":
			var it: Dictionary = shop_items[3]
			var b := _bld(C, String(it["b"]))
			it["p"] = (b["o"] as Vector2) + (b["az"] as Vector2) * (float(b["d"]) * 0.5 - 0.2)
		"n_frontage":
			var it: Dictionary = shop_items[5]
			var b := _bld(C, String(it["b"]))
			it["p"] = SL.bw(b, ((it["p"] as Vector2) - (b["o"] as Vector2)).dot(b["ax"]), float(b["d"]) * 0.5 + 0.25)
			SL.ground(C, it)
		"n_sealed":
			var it: Dictionary = shop_items[7]
			var r: Rect2 = (C["block"] as Array)[0]
			it["p"] = r.get_center()
			SL.ground(C, it)
		"n_overlap":
			var it: Dictionary = (shop_items[2] as Dictionary).duplicate(true)
			it["p"] = (it["p"] as Vector2) + Vector2(0.15, 0.1)
			items.append(it)
		"n_door":
			var it: Dictionary = shop_items[9]
			var b := _bld(C, String(it["b"]))
			it["p"] = SL.bw(b, float(b["door_cx"]), float(b["d"]) * 0.5 + 1.0)
			SL.ground(C, it)
		"n_road":
			var ms: PackedVector2Array = C["roads"]["MainStreet"]["pts"]
			var it := SL.item(C, "st_hiradai_yasai", ms[2].lerp(ms[3], 0.4), Vector2(1, 0), "shop:yaoya", {"b": shop_items[0]["b"]})
			items.append(it)
		"n_clone":
			var sh: Array = P["shops"]
			var s0: Dictionary = sh[0]
			for s1: Dictionary in sh:
				if s1 != s0 and float(s1["side"]) == float(s0["side"]):
					s1["trade"] = s0["trade"]
					break
		"n_entrance":
			P["items"] = items.filter(func(x: Dictionary) -> bool: return not (String(x["id"]) in ["st_ichi_kanban", "mk_chochin_line", "st_onobori_ichi"] and String(x["tag"]) == "market_lead"))
		"n_cross":
			P["items"] = items.filter(func(x: Dictionary) -> bool: return not String(x["tag"]).begins_with("cross"))
		"n_farm":
			P["items"] = items.filter(func(x: Dictionary) -> bool: return not String(x["tag"]).begins_with("farm"))
		"n_water":
			var WS: RLib.TriSampler = C["WS"]
			var it: Dictionary = (items.filter(func(x: Dictionary) -> bool: return String(x["tag"]).begins_with("farm"))[0] as Dictionary)
			var wp := Vector2.ZERO
			for k in 400:
				var q: Vector2 = (it["p"] as Vector2) + Vector2(cos(k * 0.7), sin(k * 0.7)) * (k * 0.1)
				var wh := WS.h(q.x, q.y)
				if not is_nan(wh) and wh > (C["S"] as RLib.TriSampler).h(q.x, q.y) + 0.05:
					wp = q
					break
			it["p"] = wp
		"n_life":
			P["items"] = items.filter(func(x: Dictionary) -> bool: return not (String(x["tag"]).begins_with("life") or String(x["tag"]) == "res_work"))
		"n_anchor":
			P["anchors"] = (P["anchors"] as Array).filter(func(a: Dictionary) -> bool: return not String(a["id"]).begins_with("st_vendor_"))


func _bld(C: Dictionary, nm: String) -> Dictionary:
	for b: Dictionary in C["bld"]:
		if String(b["name"]) == nm:
			return b
	return {}


func _samples(it: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for poly: PackedVector2Array in SL.polys(it):
		out.append_array(SL._poly_samples(poly, 0.2))
	return out


## 2D の視線：a→b が建物 OBB（0.1 m 縮め）を横切らない
func _los(C: Dictionary, a: Vector2, b: Vector2) -> bool:
	var n := int(ceil(a.distance_to(b) / 0.25))
	for i in range(1, n):
		var q := a.lerp(b, float(i) / n)
		for bd: Dictionary in C["bld"]:
			if (bd["o"] as Vector2).distance_to(q) < 10.0 and SL.obb_d(bd, q) < -0.1:
				return false
	return true


func _checks(P: Dictionary) -> void:
	var items: Array = P["items"]
	var anchors: Array = P["anchors"]
	var C: Dictionary = P["C"]
	var S: RLib.TriSampler = C["S"]
	var R: RLib.TriSampler = C["R"]
	var F: RLib.TriSampler = C["F"]
	var roads: Dictionary = C["roads"]
	# ── S1 Kit
	var miss: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if not SL.BOX.has(id) or not ResourceLoader.exists(SL.mesh_dir(id) + id + ".res") or not ResourceLoader.exists(SL.mesh_dir(id) + id + "_l1.res"):
			miss.append(id)
	check("Kit：%d 件の mesh（LOD0／LOD1）と足元定義（欠 %d %s）" % [items.size(), miss.size(), ", ".join(miss.slice(0, 3))], miss.is_empty() and items.size() >= 100)
	# ── S2 接地：中心の浮き ≤ 0.02 m、足元の隅の沈み ≤ 0.15 m（可見最上面＝地形・路面・院子）
	var fl: Array = []
	var max_sink := 0.0
	for it: Dictionary in items:
		var y: float = it["y"]
		var pts := PackedVector2Array([it["p"]])
		for poly: PackedVector2Array in SL.polys(it):
			pts.append_array(poly)
		var sink := -1e9
		var fmin := 1e9
		for q: Vector2 in pts:
			var t := SL.top_h(C, q)
			sink = maxf(sink, t - y)
			fmin = minf(fmin, y - t)
		max_sink = maxf(max_sink, sink)
		if fmin > 0.02 or sink > 0.15:
			fl.append("%s(浮 %.2f 沈 %.2f)" % [it["id"], fmin, sink])
	check("接地：%d 件 浮き ≤ 0.02 m・沈み ≤ 0.15 m（最大沈み %.2f m）違反 %d %s" % [items.size(), max_sink, fl.size(), ", ".join(fl.slice(0, 3))], fl.is_empty())
	# ── S3 建物／S4 店先帯／S5 封存（封存 overlay・市集の構件と歩く通り）／S7 戸口
	var bad_b: Array = []
	var bad_f: Array = []
	var bad_s: Array = []
	var bad_d: Array = []
	for it: Dictionary in items:
		var nb := 0
		var nf := 0
		var nsl := 0
		for q: Vector2 in _samples(it):
			for b: Dictionary in C["bld"]:
				if (b["o"] as Vector2).distance_to(q) < 12.0 and SL.obb_d(b, q) < 0.3:
					nb += 1
			if not is_nan(F.h(q.x, q.y)):
				nf += 1
			if (C["block"] as Array).any(func(r: Rect2) -> bool: return r.has_point(q)):
				nsl += 1
		for poly: PackedVector2Array in SL.polys(it):
			for o: Dictionary in C["market"]:
				if (o["p"] as Vector2).distance_to(it["p"]) < 8.0 and not Geometry2D.intersect_polygons(poly, MK.corners(o) if not (String(o["id"]) in MK.LINE) else PackedVector2Array()).is_empty():
					nsl += 1
			for b: Dictionary in C["bld"]:
				if (b["o"] as Vector2).distance_to(it["p"]) < 14.0 and not Geometry2D.intersect_polygons(poly, SL.door_poly(b)).is_empty():
					bad_d.append("%s→%s" % [it["id"], String(b["name"]).trim_prefix("B_P_")])
		if nb > 0:
			bad_b.append("%s×%d" % [it["id"], nb])
		if nf > 0:
			bad_f.append("%s×%d@(%.1f,%.1f)" % [it["id"], nf, (it["p"] as Vector2).x, (it["p"] as Vector2).y])
		if nsl > 0:
			bad_s.append("%s×%d" % [it["id"], nsl])
	check("建物：足元が建物の壁 0.3 m 以内に入る件 %d %s" % [bad_b.size(), ", ".join(bad_b.slice(0, 3))], bad_b.is_empty())
	check("店先帯：足元が P6 店先帯（犬走り・側溝）に載る件 %d %s" % [bad_f.size(), ", ".join(bad_f.slice(0, 3))], bad_f.is_empty())
	check("封存：足元が封存 overlay（R4 周邊・庭園・鎮守之森）・市集 MarketP10 の構件／歩く通りに入る件 %d %s" % [bad_s.size(), ", ".join(bad_s.slice(0, 3))], bad_s.is_empty())
	check("戸口：門口の前（±%.2f m・奥 %.1f m）を塞ぐ件 %d %s" % [SL.DOOR_HW, SL.DOOR_D, bad_d.size(), ", ".join(bad_d.slice(0, 3))], bad_d.is_empty())
	var bad_w: Array = []
	for it: Dictionary in items:
		for q: Vector2 in _samples(it):
			if SL.in_water(C, q):
				bad_w.append("%s@(%.1f,%.1f)" % [it["id"], q.x, q.y])
				break
	check("水際：足元が水面・水際 0.8 m・P7 河岸構件／橋に入る件 %d %s" % [bad_w.size(), ", ".join(bad_w.slice(0, 3))], bad_w.is_empty())
	# ── S6 互不重疊
	var ov: Array = []
	for i in items.size():
		for j in range(i + 1, items.size()):
			if (items[i]["p"] as Vector2).distance_to(items[j]["p"]) > 7.0:
				continue
			var hit := false
			for a: PackedVector2Array in SL.polys(items[i]):
				for b: PackedVector2Array in SL.polys(items[j]):
					if not Geometry2D.intersect_polygons(a, b).is_empty():
						hit = true
			if hit:
				ov.append("%s×%s" % [items[i]["id"], items[j]["id"]])
	check("互不重疊：足元が重なる組 %d %s" % [ov.size(), ", ".join(ov.slice(0, 3))], ov.is_empty())
	# ── S8 通行：主街は 1 m ごとに中央の空き ≥ 4.5 m、横街 ≥ 3.5 m；巷・路地・田埂道の路面には置かない
	var worst := {}
	for rn: String in ["MainStreet", "CrossStreetMid", "CrossStreetSouth"]:
		var pts: PackedVector2Array = roads[rn]["pts"]
		var hw: float = roads[rn]["hw"]
		var L := SL.pl_len(pts)
		var wmin := 99.0
		var wat := Vector2.ZERO
		var s := 0.5
		while s < L:
			var pp: Array = SL.pl_point(pts, s)
			var c: Vector2 = pp[0]
			var tg: Vector2 = pp[1]
			var nrm := Vector2(-tg.y, tg.x)
			if is_nan(R.h(c.x, c.y)):
				s += 1.0
				continue
			var near := items.filter(func(it: Dictionary) -> bool: return (it["p"] as Vector2).distance_to(c) < hw + 3.0)
			var run := 0.0
			var best := 0.0
			var k := -hw
			while k <= hw + 0.001:
				var q := c + nrm * k
				var cov := is_nan(R.h(q.x, q.y))
				if not cov:
					for it: Dictionary in near:
						for poly: PackedVector2Array in SL.polys(it):
							if Geometry2D.is_point_in_polygon(q, poly):
								cov = true
				run = 0.0 if cov else run + 0.1
				best = maxf(best, run)
				k += 0.1
			if best < wmin:
				wmin = best
				wat = c
			s += 1.0
		worst[rn] = [wmin, wat]
	var bad_lane: Array = []
	for it: Dictionary in items:
		for q: Vector2 in _samples(it):
			if is_nan(R.h(q.x, q.y)):
				continue
			var ok := false
			for rn: String in ["MainStreet", "CrossStreetMid", "CrossStreetSouth", "HillFootStreet", "EntranceRoad"]:
				var pr: Array = SL.pl_param(roads[rn]["pts"], q)
				if float(pr[0]) <= float(roads[rn]["hw"]) + 0.6:
					ok = true
			if not ok:
				bad_lane.append(String(it["id"]))
				break
	check("通行：主街の中央の空き 最小 %.1f m（≥ %.1f、@%s）、中橫街 %.1f m・南橫街 %.1f m（≥ %.1f）、巷・路地・田埂道の路面に載る件 %d %s" % [
		worst["MainStreet"][0], CLEAR_MAIN, str(worst["MainStreet"][1]), worst["CrossStreetMid"][0], worst["CrossStreetSouth"][0], CLEAR_CROSS,
		bad_lane.size(), ", ".join(bad_lane.slice(0, 3))],
		float(worst["MainStreet"][0]) >= CLEAR_MAIN and float(worst["CrossStreetMid"][0]) >= CLEAR_CROSS and float(worst["CrossStreetSouth"][0]) >= CLEAR_CROSS and bad_lane.is_empty())
	# ── S9 構圖：主街の店頭外溢
	var shops: Array = P["shops"]
	var with_disp := 0
	var trades := {}
	var adj := 0
	var by_side := {}
	for sh: Dictionary in shops:
		var mine := items.filter(func(it: Dictionary) -> bool: return String(it.get("b", "")) == String(sh["name"]) and String(it["id"]) in SL.DISPLAY + ["st_kanban_kusuri"])
		if not mine.is_empty():
			with_disp += 1
		trades[sh["trade"]] = true
		var sd := float(sh["side"])
		if not by_side.has(sd):
			by_side[sd] = []
		(by_side[sd] as Array).append(sh)
	for sd: float in by_side:
		var arr: Array = by_side[sd]
		arr.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return float(a["s"]) < float(c["s"]))
		for i in range(1, arr.size()):
			if String(arr[i]["trade"]) == String(arr[i - 1]["trade"]):
				adj += 1
	var nob := {}
	var kan := {}
	var andon := {}
	var lant := 0
	var tall := 0
	for it: Dictionary in items:
		var id := String(it["id"])
		if id.contains("nobori"):
			nob[id] = true
		if id.contains("kanban") and id != "st_ichi_kanban":
			kan[id] = true
		if id.begins_with("st_andon"):
			andon[id] = true
		if id in SL.LANTERN or id == "st_ichi_kanban":
			lant += 1
		if float(SL.BOX[id][2]) >= SL.TALL:
			tall += 1
	var n_shop := shops.size()
	var ratio := float(with_disp) / maxf(1.0, n_shop)
	var n_quiet := shops.filter(func(sh: Dictionary) -> bool: return String(sh.get("level", "")) == "quiet").size()
	var n_rich := shops.filter(func(sh: Dictionary) -> bool: return String(sh.get("level", "")) == "rich").size()
	check("構圖：主街の店 %d のうち店頭の陳列あり %d（%.0f %%、55–85 %%＝全部同じにしない）、静かな店 %d・賑やかな店 %d（各 ≥ 15 %%）、商い %d 種（≥ 10）、同じ側で隣と同じ商い %d、幟 %d 種・看板 %d 種・置行灯 %d 種、提灯・行灯 %d（≥ 10）、2.2 m 以上の輪郭 %d（≥ 15）" % [
		n_shop, with_disp, ratio * 100.0, n_quiet, n_rich, trades.size(), adj, nob.size(), kan.size(), andon.size(), lant, tall],
		n_shop >= 20 and ratio >= 0.55 and ratio <= 0.85 and n_quiet >= 0.15 * n_shop and n_rich >= 0.15 * n_shop and trades.size() >= 10 and adj == 0
		and nob.size() >= 4 and kan.size() >= 5 and andon.size() >= 3 and lant >= 10 and tall >= 15)
	# ── S11 巷口・路口：道標＋用途の物
	var need := ["cross:cross_mid_e", "cross:cross_south_e", "cross:hillfoot", "cross:midlane"]
	var lack: Array = []
	for t: String in need:
		if not items.any(func(it: Dictionary) -> bool: return String(it["tag"]) == t):
			lack.append(t)
	var fuda := {}
	for it: Dictionary in items:
		if String(it["id"]).begins_with("st_fuda"):
			fuda[it["id"]] = true
	check("巷口・路口：用途提示の欠けた口 %d %s、道標 %d 種（≥ 4：市此方・田畑・水車・御社）" % [lack.size(), ", ".join(lack), fuda.size()], lack.is_empty() and fuda.size() >= 4)
	# ── S12 市の入口：大看板・道標・赤提灯／吊り提灯・荷車・荷 ≥ 2、主街から大看板が見え、口の前から市の色が見える
	var lead := items.filter(func(it: Dictionary) -> bool: return String(it["tag"]) == "market_lead")
	var ids := lead.map(func(it: Dictionary) -> String: return String(it["id"]))
	var goods := ids.filter(func(i: String) -> bool: return i in ["st_kago_tsumi", "wk_tawara3", "kr_fukuro", "mk_tsumini"]).size()
	var ki: Array = lead.filter(func(it: Dictionary) -> bool: return String(it["id"]) in ["st_ichi_kanban", "st_onobori_ichi"])
	var vis_ms := 0
	for vp: Vector2 in MS_VIEW:
		if ki.any(func(k: Dictionary) -> bool: return _los(C, vp, k["p"])):
			vis_ms += 1
	var color: Array = (C["market"] as Array).filter(func(o: Dictionary) -> bool:
		return String(o["id"]) in ["mk_chochin_line", "mk_yatai_yasai", "mk_yatai_cha", "mk_nobori_ichi", "mk_tana_nuno", "mk_mushiro_yasai"])
	var vis_mouth := 0
	for vp: Vector2 in MOUTH_VIEW:
		var nvis := color.filter(func(o: Dictionary) -> bool: return _los(C, vp, o["p"])).size()
		if nvis >= 3:
			vis_mouth += 1
	var n_line := ids.filter(func(i: String) -> bool: return i == "mk_chochin_line").size()
	var ent_ok: bool = "st_ichi_kanban" in ids and "st_fuda_ichi" in ids and "st_onobori_ichi" in ids and n_line >= 3 and ("mk_kuruma_ni" in ids or "kr_kuruma" in ids) and goods >= 2
	check("市の入口：大看板・道標「市此方」・大幟「市 此方」・吊り提灯 ≥ 3 本（主街の角→中橫街→口）・荷車 %s、荷 %d（≥ 2）、主街の視點 %d/%d から「市」の大看板か幟が見える（全部）、口の前 %d/%d から市の色 ≥ 3 件が見える（= 3）" % [
		"揃う" if ent_ok else "欠け", goods, vis_ms, MS_VIEW.size(), vis_mouth, MOUTH_VIEW.size()], ent_ok and vis_ms == MS_VIEW.size() and vis_mouth == MOUTH_VIEW.size())
	# ── S13 道端の作業場：≥ 3 か所・≥ 3 種、主街の路縁から 12 m 以内で主街から見える
	var works := items.filter(func(it: Dictionary) -> bool: return String(it["tag"]) == "work")
	var wk := {}
	var wbad: Array = []
	var ms: PackedVector2Array = roads["MainStreet"]["pts"]
	for it: Dictionary in works:
		wk[it["id"]] = true
		var pr: Array = SL.pl_param(ms, it["p"])
		var cp: Vector2 = SL.pl_point(ms, float(pr[1]))[0]
		if float(pr[0]) > float(roads["MainStreet"]["hw"]) + 12.0 or not _los(C, cp, it["p"]):
			wbad.append(String(it["id"]))
	check("作業場：%d か所・%d 種（≥ 3・≥ 3）、主街から 12 m 超／見えない %d %s" % [works.size(), wk.size(), wbad.size(), ", ".join(wbad)], works.size() >= 3 and wk.size() >= 3 and wbad.is_empty())
	# ── S14 農田→住宅の境：≥ 3 か所・各 ≥ 2 件、種類 ≥ 4
	var farm := {}
	var fk := {}
	for it: Dictionary in items:
		var t := String(it["tag"])
		if t.begins_with("farm"):
			farm[t] = int(farm.get(t, 0)) + 1
			fk[it["id"]] = true
	var fsmall := farm.values().filter(func(n: int) -> bool: return n < 2).size()
	var FS: RLib.TriSampler = C["FS"]
	var fbad: Array = []
	for it: Dictionary in items:
		if not String(it["tag"]).begins_with("farm"):
			continue
		var on := false
		for q: Vector2 in _samples(it):
			if not is_nan(FS.h(q.x, q.y)):
				on = true
		var near := false
		var p0: Vector2 = it["p"]
		for k in 48:
			var a := TAU * k / 48.0
			for rr in [3.0, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0, 24.0]:
				var q: Vector2 = p0 + Vector2(cos(a), sin(a)) * rr
				if not is_nan(FS.h(q.x, q.y)):
					near = true
		if on or not near:
			fbad.append("%s(%s)" % [it["id"], "田の中" if on else "田から 24 m 超"])
	check("農田→住宅の境：%d か所（≥ 3）、2 件未満の所 %d、種類 %d（≥ 4）、田の中／田から 24 m 超（水渠の村側）%d %s" % [farm.size(), fsmall, fk.size(), fbad.size(), ", ".join(fbad.slice(0, 3))],
		farm.size() >= 3 and fsmall == 0 and fk.size() >= 4 and fbad.is_empty())
	# ── S16 暮らし：井戸端 ≥ 2・干し竿 ≥ 1（住まいの気配）、職の家の小さな仕事場 ≥ 1
	var n_ido := items.filter(func(it: Dictionary) -> bool: return String(it["id"]) == "st_ido").size()
	var n_hoshi := items.filter(func(it: Dictionary) -> bool: return String(it["id"]) == "mk_hoshimono").size()
	var n_rw := items.filter(func(it: Dictionary) -> bool: return String(it["tag"]) == "res_work").size()
	check("暮らし：井戸 %d（≥ 2）、干し竿 %d（≥ 1）、職の家の仕事場 %d（≥ 1）" % [n_ido, n_hoshi, n_rw], n_ido >= 2 and n_hoshi >= 1 and n_rw >= 1)
	# ── S15 NPC anchors：店頭陳列のある店に売り手＋客、作業場に職人、足元・建物・巷の路面の内に立たない、間隔 ≥ 0.5 m
	var by_ref := {}
	var bad_a: Array = []
	for a: Dictionary in anchors:
		var p: Vector2 = a["p"]
		var act := String(a["activity"])
		for b: Dictionary in C["bld"]:
			if (b["o"] as Vector2).distance_to(p) < 12.0 and SL.obb_d(b, p) < 0.15:
				bad_a.append(String(a["id"]))
		if act != "vendor_stand":
			for it: Dictionary in items:
				for poly: PackedVector2Array in SL.polys(it):
					if Geometry2D.is_point_in_polygon(p, poly):
						bad_a.append("%s∈%s" % [a["id"], it["id"]])
		by_ref[String(a["id"])] = act
	var vend := anchors.filter(func(a: Dictionary) -> bool: return String(a["activity"]) == "vendor_stand").size()
	var cust := anchors.filter(func(a: Dictionary) -> bool: return String(a["activity"]) == "customer_browse").size()
	var work_a := anchors.filter(func(a: Dictionary) -> bool: return String(a["activity"]) == "worker_craft").size()
	var close: Array = []
	for i in anchors.size():
		for j in range(i + 1, anchors.size()):
			if (anchors[i]["p"] as Vector2).distance_to(anchors[j]["p"]) < 0.5:
				close.append("%s×%s" % [anchors[i]["id"], anchors[j]["id"]])
	check("NPC anchors：%d（≥ 30）、売り手 %d・客 %d（≥ 店頭陳列 %d）、職人 %d（≥ 作業場 %d）、足元・建物の内 %d %s、0.5 m 未満の組 %d" % [anchors.size(), vend, cust, with_disp,
		work_a, works.size(), bad_a.size(), ", ".join(bad_a.slice(0, 3)), close.size()],
		anchors.size() >= 30 and vend >= with_disp and cust >= with_disp and work_a >= works.size() and bad_a.is_empty() and close.is_empty())


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(SL.OUTPUT):
		push_error("找不到 %s（先 --build 成功才可 attach）" % SL.OUTPUT)
		return 1
	if txt.contains("gen/street_p10.scn"):
		push_error("已經掛過 StreetP10")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var mk_line := "[node name=\"MarketP10\" parent=\"Props\" instance=ExtResource(\"p10r1_market\")]"
	if txt.count(mk_line) != 1:
		push_error("MarketP10 の掛載行が見つからない（StreetP10 は MarketP10 の後に掛ける）")
		return 1
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var done := false
	var i := 0
	while i < lines.size():
		out.append(lines[i])
		if not done and lines[i] == mk_line:
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"StreetP10\" parent=\"Props\" instance=ExtResource(\"p10r2_street\")]")
			out.append("")
			done = true
			continue
		i += 1
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p10r2_street\"]" % SL.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[STR] attach：加 Props/StreetP10（MarketP10 の後）→ %s" % SCENE)
	return 0


func _scene(v: Node3D) -> void:
	var txt := FileAccess.get_file_as_string(SCENE)
	var idx: Array = []
	for nm: String in VEG_ORDER:
		idx.append(txt.find("[node name=\"%s\" parent=\"Vegetation\"" % nm))
	var ord_ok: bool = int(idx[0]) >= 0
	for k in range(1, idx.size()):
		ord_ok = ord_ok and int(idx[k]) > int(idx[k - 1])
	var i_mk := txt.find("[node name=\"MarketP10\" parent=\"Props\"")
	var i_st := txt.find("[node name=\"StreetP10\" parent=\"Props\"")
	var go := v.get_node_or_null(SL.PARENT + "/" + SL.NODE_NAME)
	check("場景已掛 Props/MarketP10 → Props/StreetP10（%s、各 1 個）、P9 Vegetation 掛載順序不變" % SL.OUTPUT,
		go != null and go.scene_file_path == SL.OUTPUT and i_mk >= 0 and i_st > i_mk and txt.count("parent=\"Props\" instance=ExtResource(\"p10r2_street\")") == 1 and ord_ok)
	# MarketP10（P10 R1 封存）の overlay 雜湊が封存時と同じ
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MARKET_SEAL))
	var mk_sha := FileAccess.get_sha256(MK.OUTPUT)
	check("MarketP10 封存：gen/market_p10.scn 雜湊＝封存時（%s…）" % mk_sha.substr(0, 8), mk_sha == String(seal["frozen"]["godot/maps/village_v2/gen/market_p10.scn"]))
	if go == null:
		return
	for i in 4:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var n_i := 0
	var bad: Array = []
	var nolod: Array = []
	for grp in ["Shopfront", "Signs", "Residence", "Crossings", "MarketLead", "Work", "FarmEdge"]:
		for n in go.get_node(grp).get_children():
			n_i += 1
			var o := (n as Node3D).global_position
			var q := PhysicsRayQueryParameters3D.create(o + Vector3(0, 30, 0), o + Vector3(0, -10, 0))
			var ex: Array[RID] = []
			var gy := NAN
			for k in 12:
				q.exclude = ex
				var hit := sp.intersect_ray(q)
				if hit.is_empty():
					break
				var cn := String((hit.collider as Node).name)
				if cn.begins_with("TerrainCollision") or (hit.collider as Node).get_parent().name == "Roads" or cn.contains("Road"):
					gy = hit.position.y
					break
				ex.append(hit.rid)
			if is_nan(gy) or absf(gy - o.y) > 0.2:
				bad.append("%s(Δ%s)" % [n.name, "nan" if is_nan(gy) else "%.2f" % (o.y - gy)])
			var l0 := n.get_node_or_null("LOD0") as MeshInstance3D
			var l1 := n.get_node_or_null("LOD1") as MeshInstance3D
			if l0 == null or l1 == null or l0.mesh == null or l1.mesh == null:
				nolod.append(String(n.name))
	check("接地射線：%d 件の原點と地形・路面（衝突體）の差 ≤ 0.20 m 違反 %d %s" % [n_i, bad.size(), ", ".join(bad.slice(0, 3))], bad.is_empty() and n_i >= 100)
	check("LOD：%d 件に LOD0／LOD1 mesh（欠 %d）" % [n_i, nolod.size()], nolod.is_empty())
	var ns := go.get_node("Collision").get_child_count()
	var na := go.get_node("Anchors").get_child_count()
	var grp_ok := go.get_node("Anchors").get_children().all(func(a: Node) -> bool: return a.is_in_group("npc_activity_anchor") and a.has_meta("activity"))
	check("碰撞 %d shapes、NPC anchors %d（group npc_activity_anchor＋activity meta）" % [ns, na], ns >= 100 and na >= 30 and grp_ok)
	var mm := go.find_children("*", "MultiMeshInstance3D", true, false).size()
	check("MultiMesh を使わない（節點ごとに選べる；MMBAKE 対象外）：%d" % mm, mm == 0)
