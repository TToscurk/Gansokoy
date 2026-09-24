extends RefCounted
## 人間之里 V2 — P3 Roads / Parcels：巷道層＋地塊。產生器 gen_village_v2.gd 與驗證 verify_village_v2_parcels.gd 共用。
##
## 參數：layout_v2.json 的 lanes（P3 巷道層）與 parcel_rules（地塊規則）。兩者都不在 Macro 凍結範圍；
## 凍結的 16 條 roads 一條都不動（2026-09-24 使用者裁示）。
##   巷道：只在建成區平台內，寬 2.0–3.0 m、有轉折，路面貼 P1 平台（不整地），一端接既有道路或巷道。
##   地塊：沿道路兩側鋪單棟地塊。臨路面寬取 frontage_seq（5–9 m）、縱深依 district（12–25 m），
##         全部由序列與道路幾何決定（沒有亂數）。依 road_order 逐條、逐段、兩側鋪；
##         每塊必須：在平台外框內、不壓任何道路／巷道路幅、離水道有餘裕、不進 keep_clear、
##         不與地標固定地塊或其他地塊重疊、地塊內高低差 ≤ max_relief。放不下先縮縱深，再往前挪 1 m。
##   三輪（2026-09-24 使用者裁示 r2：正式町家一律 machiya_depth 12–25 m，不得有淺町家）：
##     1 町家輪：分區縱深，缺口前進 1 m。
##     2 合併輪：掃描第一輪留下的空隙，優先把空隙「合併」進背面的相鄰町家——該町家縱深以
##       merge_step 加深到剛好吃掉空隙，上限 merge_depth_max（25 m）。町家仍是單棟、仍在 12–25 m。
##     3 附屬輪：合併不掉的空隙改成 auxiliary／yard 附屬用地（kind "aux"、縱深 aux_depth 4–10 m，
##       用途取 aux_use_seq：庭院／後院／倉小屋／空地）。附屬用地不是正式町家建築地塊，
##       P4 灰盒不在上面放主建築；也不為覆蓋率硬塞建築。
##   地標固定地塊：box 類地標 footprint（依 yaw 旋轉）外擴 yard，扣掉道路路幅；或直接用 layout 指定的 poly。

const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const OV_EPS := 0.03


static func lanes(L: Dictionary) -> Array:
	var out: Array = []
	for r in L.get("lanes", []):
		out.append({"name": String(r["name"]), "cls": "lane", "label": String(r["label"]),
			"hw": float(r["half_w"]), "pts": TLib.pts(r["pts"]), "lane": true})
	return out


## 全路網：凍結 roads（主街寬取 variants.main_street_width.selected）＋ P3 巷道
static func network(L: Dictionary) -> Array:
	var out: Array = []
	var VW: Dictionary = L.get("variants", {}).get("main_street_width", {})
	for r in L["roads"]:
		var hw := float(r["half_w"])
		if not VW.is_empty() and String(r["name"]) == String(VW["road"]):
			hw = float(VW["options"][String(VW["selected"])]["half_w"])
		out.append({"name": String(r["name"]), "cls": String(r["class"]), "label": String(r["label"]),
			"hw": hw, "pts": TLib.pts(r["pts"]), "lane": false})
	out.append_array(lanes(L))
	for r in out:
		r["bb"] = _bbox(r["pts"]).grow(float(r["hw"]))
	return out


## 水道：[{name, pts, hw: PackedFloat32Array（每點半寬）}]
static func waters(L: Dictionary) -> Array:
	var W: Dictionary = L["water"]
	var out: Array = []
	var mr: Dictionary = W["MainRiver"]
	var hws := PackedFloat32Array()
	for v in mr["half_w"]:
		hws.append(float(v))
	out.append({"name": "MainRiver", "pts": TLib.pts(mr["pts"]), "hw": hws})
	var cn: Dictionary = W["Canal"]
	out.append({"name": "Canal", "pts": TLib.pts(cn["pts"]), "hw": _const(float(cn["half_w"]), cn["pts"].size())})
	for s in W["Streams"]:
		out.append({"name": String(s["name"]), "pts": TLib.pts(s["pts"]), "hw": _const(float(s["half_w"]), s["pts"].size())})
	return out


static func _const(v: float, n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(v)
	return a


## 點到水道岸邊（中心線 ± 半寬）的距離；負＝在水道內
static func water_edge_d(w: Dictionary, p: Vector2) -> float:
	var pts: PackedVector2Array = w["pts"]
	var hw: PackedFloat32Array = w["hw"]
	var best := INF
	for k in pts.size() - 1:
		var seg := pts[k + 1] - pts[k]
		var t := clampf((p - pts[k]).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		best = minf(best, p.distance_to(pts[k] + seg * t) - lerpf(hw[k], hw[k + 1], t))
	return best


static func _bbox(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## 多邊形到折線的最短距離（相交或折線在多邊形內＝0）
static func poly_line_d(poly: PackedVector2Array, line: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		for k in line.size() - 1:
			var cp := Geometry2D.get_closest_points_between_segments(a, b, line[k], line[k + 1])
			best = minf(best, cp[0].distance_to(cp[1]))
	if best > 0.0 and Geometry2D.is_point_in_polygon(line[0], poly):
		return 0.0
	return best


## 多邊形到點的距離（點在內＝負的到邊距離）
static func poly_point_d(poly: PackedVector2Array, p: Vector2) -> float:
	var d := INF
	for i in poly.size():
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return -d if Geometry2D.is_point_in_polygon(p, poly) else d


static func area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		s += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(s) * 0.5


static func overlap_area(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var s := 0.0
	for p in Geometry2D.intersect_polygons(a, b):
		s += area(p)
	return s


## 沿多邊形邊每 step m 取樣（含角點）
static func edge_samples(poly: PackedVector2Array, st: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := maxi(1, int(ceil(a.distance_to(b) / st)))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	return out


## 地標 footprint（box 類；yaw 繞 +Y，局部 x → (cos, −sin)、局部 z → (sin, cos)）
static func landmark_rect(lm: Dictionary) -> PackedVector2Array:
	var c := Vector2(float(lm["at"][0]), float(lm["at"][1]))
	var s: Array = lm["size"]
	var th := deg_to_rad(float(lm.get("yaw", 0.0)))
	var ax := Vector2(cos(th), -sin(th)) * float(s[0]) * 0.5
	var az := Vector2(sin(th), cos(th)) * float(s[2]) * 0.5
	return PackedVector2Array([c - ax - az, c + ax - az, c + ax + az, c - ax + az])


## 道路 × 水道交點（橋位）
static func crossings(net: Array, ws: Array) -> Array:
	var out: Array = []
	for r in net:
		var rp: PackedVector2Array = r["pts"]
		for w in ws:
			var wp: PackedVector2Array = w["pts"]
			for a in rp.size() - 1:
				for b in wp.size() - 1:
					var hit = Geometry2D.segment_intersects_segment(rp[a], rp[a + 1], wp[b], wp[b + 1])
					if hit != null:
						out.append({"road": r["name"], "water": w["name"], "at": hit as Vector2,
							"hw": maxf(w["hw"][b], w["hw"][b + 1])})
	return out


## keep_clear：[{at, r, why}]＝layout 指定＋任務錨點＋傳送點＋橋位
static func keep_clear(L: Dictionary, net: Array, ws: Array) -> Array:
	var R: Dictionary = L["parcel_rules"]
	var out: Array = []
	for k in R["keep_clear"]:
		out.append({"at": Vector2(float(k["at"][0]), float(k["at"][1])), "r": float(k["r"]), "why": String(k["why"])})
	for q in L["quest_anchors"]:
		out.append({"at": Vector2(float(q["at"][0]), float(q["at"][1])), "r": float(R["anchor_clear"]),
			"why": "quest " + String(q.get("id", q.get("name", "")))})
	for q in L["portals"]:
		out.append({"at": Vector2(float(q["at"][0]), float(q["at"][1])), "r": float(R["portal_clear"]),
			"why": "portal " + String(q.get("id", q.get("name", "")))})
	for c in crossings(net, ws):
		out.append({"at": c["at"], "r": float(c["hw"]) + float(R["bridge_clear"]), "why": "bridge %s×%s" % [c["road"], c["water"]]})
	return out


## 地標固定地塊
static func fixed_parcels(L: Dictionary, net: Array) -> Array:
	var R: Dictionary = L["parcel_rules"]
	var lms := {}
	for lm in L["landmarks"]:
		lms[String(lm["id"])] = lm
	var out: Array = []
	for f in R["fixed"]:
		var lid := String(f["landmark"])
		var lm: Dictionary = lms[lid]
		var c := Vector2(float(lm["at"][0]), float(lm["at"][1]))
		var poly: PackedVector2Array
		var rect := PackedVector2Array()
		if lm.has("size"):
			rect = landmark_rect(lm)
			if Geometry2D.is_polygon_clockwise(rect):
				rect.reverse()
		if f.has("poly"):
			poly = TLib.pts(f["poly"])
		else:
			var g := Geometry2D.offset_polygon(rect, float(f["yard"]), Geometry2D.JOIN_MITER)
			poly = g[0]
		# 地標本體壓到道路路幅的面積（P0 凍結的位置，只記錄、不移動）
		var enc := 0.0
		for r in net:
			var road := Geometry2D.offset_polyline(r["pts"], float(r["hw"]), Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
			if not rect.is_empty():
				for hp in Geometry2D.intersect_polygons(rect, road[0]):
					enc += area(hp)
			# 院子扣掉道路路幅＋road_gap；留下含地標中心（或最大）的那塊
			var corr := Geometry2D.offset_polyline(r["pts"], float(r["hw"]) + float(R["road_gap"]),
				Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
			for cp in corr:
				var parts := Geometry2D.clip_polygons(poly, cp)
				if parts.is_empty():
					continue
				var best: PackedVector2Array = PackedVector2Array()
				var ba := -1.0
				for pp in parts:
					if Geometry2D.is_polygon_clockwise(pp) and parts.size() > 1 and _is_hole(pp, parts):
						continue
					var sc := area(pp) + (1e6 if Geometry2D.is_point_in_polygon(c, pp) else 0.0)
					if sc > ba:
						ba = sc
						best = pp
				poly = best
		out.append({"id": String(f["id"]), "kind": "landmark", "landmark": lid, "label": String(lm["label"]),
			"poly": poly, "footprint": rect, "footprint_road_overlap": enc, "at": c})
	return out


## 地塊生成。h_fn(Vector2) → 地面高；回傳 {parcels: Array, fixed: Array, stats: Dictionary}
static func parcels(L: Dictionary, net: Array, h_fn: Callable) -> Dictionary:
	var R: Dictionary = L["parcel_rules"]
	var outlines := TLib.built_outlines(L)
	var ws := waters(L)
	var keep := keep_clear(L, net, ws)
	var fixed := fixed_parcels(L, net)
	var D: Dictionary = L["districts"]
	var dpolys := {}
	for k in D:
		if String(D[k]["kind"]) == "built":
			dpolys[k] = TLib.pts(D[k]["poly"])
	var acc: Array = []   # [poly, bbox]
	for f in fixed:
		acc.append([f["poly"], _bbox(f["poly"])])
	var byname := {}
	for r in net:
		byname[r["name"]] = r
	var order: Array = []
	for n in R["road_order"]:
		order.append(String(n))
	for r in net:
		if r["lane"] and not order.has(r["name"]):
			order.append(r["name"])
	var out: Array = []
	var counts := {}
	var stats := {"tried": 0, "outline": 0, "road": 0, "water": 0, "keep": 0, "overlap": 0, "relief": 0,
		"gaps": 0, "merged": 0, "merged_m": 0.0}
	var ctx := {"R": R, "outlines": outlines, "net": net, "ws": ws, "keep": keep, "acc": acc, "h_fn": h_fn,
		"dpolys": dpolys, "out": out, "counts": counts, "stats": stats, "gaps": []}
	# 第一輪 町家：分區縱深（machiya_depth 12–25 m 內），缺口前進 1 m
	for oi in order.size():
		_pass(ctx, byname[order[oi]], oi, 0)
	# 第二輪 掃描：找出第一輪留下的空隙（不落地，只收集多邊形）
	for oi in order.size():
		_pass(ctx, byname[order[oi]], oi, 1)
	stats["gaps"] = (ctx["gaps"] as Array).size()
	# 第三輪 合併：空隙優先併進背面的相鄰町家（加深縱深，上限 merge_depth_max）
	_merge(ctx)
	# 第四輪 附屬用地：併不掉的空隙改成 auxiliary／yard（庭院、後院、倉小屋、空地），不是正式町家
	for oi in order.size():
		_pass(ctx, byname[order[oi]], oi, 2)
	for pc in out:
		pc.erase("acc_i")
	return {"parcels": out, "fixed": fixed, "stats": stats, "keep": keep}


## 空隙併進背面町家：沿背面方向以 merge_step 加深，只在「背面 dmax 內還有掃描輪標出的空隙」時才繼續，
## 空隙吃完（或碰到既有地塊／路／水／平台外／keep_clear）就停。町家縱深上限 merge_depth_max
## （＝ machiya_depth 上限 25 m），所以正式町家永遠在 12–25 m，也不會無限往空地長。
static func _merge(ctx: Dictionary) -> void:
	var R: Dictionary = ctx["R"]
	var gaps: Array = ctx["gaps"]
	if gaps.is_empty():
		return
	var step := float(R["merge_step"])
	var dmax := float(R["merge_depth_max"])
	var min_gap := float(R.get("merge_min_gap_m2", 2.0))
	var acc: Array = ctx["acc"]
	var stats: Dictionary = ctx["stats"]
	for pc in ctx["out"]:
		if pc["kind"] != "machiya":
			continue
		var f0: Vector2 = pc["front_a"]
		var f1: Vector2 = pc["front_b"]
		var n: Vector2 = -(pc["dir"] as Vector2)
		var side := 1.0 if String(pc["side"]) == "L" else -1.0
		var ai := int(pc["acc_i"])
		var d := float(pc["depth"])
		var d0 := d
		while d + step <= dmax + 0.001:
			# 背面 [d, dmax] 帶狀範圍內還有空隙才繼續（沒有＝背面是刻意留白的空地／後院）
			var band := PackedVector2Array([f0 + n * d, f1 + n * d, f1 + n * dmax, f0 + n * dmax])
			if _gap_area(gaps, band) < min_gap:
				break
			var cand := PackedVector2Array([f0, f1, f1 + n * (d + step), f0 + n * (d + step)])
			if side < 0.0:
				cand.reverse()
			var self_e: Array = acc[ai]
			acc[ai] = [PackedVector2Array(), Rect2(1e7, 1e7, 0.0, 0.0)]   # 測試時排除自己（bbox 放到遠處，不會被命中）
			var why := _reject(cand, R, ctx["outlines"], ctx["net"], ctx["ws"], ctx["keep"], acc, ctx["h_fn"])
			acc[ai] = self_e
			if why != "":
				break
			d += step
			pc["poly"] = cand
			acc[ai] = [cand, _bbox(cand)]
		if d > d0:
			pc["depth"] = d
			pc["merged_m"] = snappedf(d - d0, 0.01)
			stats["merged"] += 1
			stats["merged_m"] = snappedf(float(stats["merged_m"]) + d - d0, 0.01)


static func _gap_area(gaps: Array, band: PackedVector2Array) -> float:
	var bb := _bbox(band)
	var a := 0.0
	for g in gaps:
		if (g[1] as Rect2).intersects(bb):
			a += overlap_area(band, g[0])
	return a


## 沿一條路兩側鋪地塊。mode 0＝町家輪；1＝掃描輪（只收集空隙，不落地）；2＝附屬用地輪（aux）。
static func _pass(ctx: Dictionary, r: Dictionary, oi: int, mode: int) -> void:
	var R: Dictionary = ctx["R"]
	var fseq: Array = R["frontage_seq"]
	var dpat: Array = R["depth_pattern"]
	var front_gap := float(R["front_gap"])
	var fmin := float(R["frontage_min"])
	var stats: Dictionary = ctx["stats"]
	var pts: PackedVector2Array = r["pts"]
	var hw := float(r["hw"])
	var small := mode != 0
	for side: float in [1.0, -1.0]:
		var idx := oi * 3 + (0 if side > 0.0 else 5) + (7 if small else 0)
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var t := (b - a).normalized()
			var n := Vector2(-t.y, t.x) * side
			var seg_len := a.distance_to(b)
			var s := 0.0
			while s + fmin <= seg_len:
				var widths: Array = [minf(float(fseq[idx % fseq.size()]), seg_len - s)]
				if small and widths[0] > fmin:
					widths.append(fmin)
				var placed := false
				var w := 0.0
				var dist := ""
				for wv in widths:
					w = float(wv)
					var f0: Vector2 = a + t * s + n * (hw + front_gap)
					var f1: Vector2 = a + t * (s + w) + n * (hw + front_gap)
					dist = _district(ctx["dpolys"], (f0 + f1) * 0.5 + n * 6.0)
					var dr: Array = R["aux_depth"] if small else R["depth"].get(dist, R["depth"]["default"])
					var d: float = lerpf(float(dr[0]), float(dr[1]), float(dpat[idx % dpat.size()]))
					while d >= float(dr[0]) - 0.01:
						stats["tried"] += 1
						var poly := PackedVector2Array([f0, f1, f1 + n * d, f0 + n * d])
						if side < 0.0:
							poly.reverse()
						var why := _reject(poly, R, ctx["outlines"], ctx["net"], ctx["ws"], ctx["keep"], ctx["acc"], ctx["h_fn"])
						if why == "":
							if mode == 1:
								(ctx["gaps"] as Array).append([poly, _bbox(poly)])
							else:
								var counts: Dictionary = ctx["counts"]
								var code: String = R["district_code"].get(dist, "XXX")
								var aux := mode == 2
								var ckey: String = ("A_" if aux else "") + code
								counts[ckey] = int(counts.get(ckey, 0)) + 1
								var rec := {"id": "%s_%03d" % [("A_" + code) if aux else ("P_" + code), counts[ckey]],
									"kind": "aux" if aux else "machiya",
									"district": dist, "road": r["name"], "road_cls": r["cls"],
									"side": "L" if side > 0.0 else "R", "poly": poly,
									"frontage": w, "depth": d, "front_a": f0, "front_b": f1, "dir": -n,
									"s": float(k) + s / maxf(seg_len, 1e-6),
									"acc_i": (ctx["acc"] as Array).size()}
								if aux:
									var useq: Array = R["aux_use_seq"]
									rec["use"] = String(useq[counts[ckey] % useq.size()])
								(ctx["acc"] as Array).append([poly, _bbox(poly)])
								(ctx["out"] as Array).append(rec)
							placed = true
							break
						stats[why] += 1
						d -= 1.5
					if placed:
						break
				if placed:
					var gp: Array = R["side_gap"].get(dist, R["side_gap"]["default"])
					s += w + float(gp[idx % gp.size()])
					idx += 1
				else:
					s += 0.5 if small else 1.0


static func _is_hole(pp: PackedVector2Array, parts: Array) -> bool:
	for q in parts:
		if q != pp and Geometry2D.is_point_in_polygon(pp[0], q):
			return true
	return false


static func _district(dpolys: Dictionary, p: Vector2) -> String:
	for k in dpolys:
		if Geometry2D.is_point_in_polygon(p, dpolys[k]):
			return k
	var best := ""
	var bd := INF
	for k in dpolys:
		var d := poly_point_d(dpolys[k], p)
		if d < bd:
			bd = d
			best = k
	return best


static func _reject(poly: PackedVector2Array, R: Dictionary, outlines: Array, net: Array, ws: Array,
		keep: Array, acc: Array, h_fn: Callable) -> String:
	var bb := _bbox(poly)
	# 候選內縮 OV_EPS 後與既有地塊不得有任何交集（相鄰地塊可共用邊，不可互相吃進）
	var sh := Geometry2D.offset_polygon(poly, -OV_EPS, Geometry2D.JOIN_MITER)
	var core: PackedVector2Array = sh[0] if not sh.is_empty() else poly
	for e in acc:
		if (e[1] as Rect2).intersects(bb) and not Geometry2D.intersect_polygons(core, e[0]).is_empty():
			return "overlap"
	for kc in keep:
		if poly_point_d(poly, kc["at"]) < float(kc["r"]):
			return "keep"
	var gap := float(R["road_gap"])
	for r in net:
		if not (r["bb"] as Rect2).grow(gap + 0.5).intersects(bb):
			continue
		if poly_line_d(poly, r["pts"]) < float(r["hw"]) + gap - 0.01:
			return "road"
	var smp := edge_samples(poly, 2.0)
	var wm: Dictionary = R["water_margin"]
	for w in ws:
		var m := float(wm.get(w["name"], wm["default"]))
		for p in smp:
			if water_edge_d(w, p) < m:
				return "water"
	var om := float(R["outline_margin"])
	for p in smp:
		if TLib.outline_sd(outlines, p) < om:
			return "outline"
	var lo := INF
	var hi := -INF
	for p in smp:
		var h: float = h_fn.call(p)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	if hi - lo > float(R["max_relief"]):
		return "relief"
	return ""


## §11 地塊紀錄（高度、坡度、淨空）。road_h_fn(road_name, Vector2) → 路面高。
static func record(pc: Dictionary, all_polys: Array, net: Array, h_fn: Callable, road_h_fn: Callable) -> Dictionary:
	var poly: PackedVector2Array = pc["poly"]
	var smp := edge_samples(poly, 1.0)
	var lo := INF
	var hi := -INF
	var sum := 0.0
	for p in smp:
		var h: float = h_fn.call(p)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		sum += h
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var rec := {"id": pc["id"], "kind": pc["kind"], "district": pc.get("district", ""),
		"footprint": _arr(poly), "area_m2": snappedf(area(poly), 0.1), "center": _v(c),
		"ground_h": snappedf(sum / smp.size(), 0.01), "relief_m": snappedf(hi - lo, 0.01)}
	var nb := INF
	for q in all_polys:
		if q == poly:
			continue
		if not _bbox(q).grow(12.0).intersects(_bbox(poly)):
			continue
		nb = minf(nb, _poly_poly_d(poly, q))
	rec["clearance"] = {"nearest_parcel_m": snappedf(minf(nb, 99.0), 0.01)}
	if pc["kind"] == "machiya" or pc["kind"] == "aux":
		var fm: Vector2 = (pc["front_a"] + pc["front_b"]) * 0.5
		var dir: Vector2 = pc["dir"]   # 朝道路
		var ent: float = h_fn.call(fm - dir * 0.5)
		var rh: float = road_h_fn.call(pc["road"], fm + dir * 3.0)
		var back: float = h_fn.call(fm - dir * float(pc["depth"]))
		var fa: float = h_fn.call((pc["front_a"] as Vector2) - dir * float(pc["depth"]) * 0.5)
		var fb: float = h_fn.call((pc["front_b"] as Vector2) - dir * float(pc["depth"]) * 0.5)
		rec["road"] = pc["road"]
		rec["road_cls"] = pc["road_cls"]
		if pc.has("merged_m"):
			rec["merged_m"] = pc["merged_m"]
		if pc.has("use"):
			rec["use"] = pc["use"]
		rec["side"] = pc["side"]
		rec["frontage_m"] = snappedf(pc["frontage"], 0.01)
		rec["depth_m"] = snappedf(pc["depth"], 0.01)
		rec["front_dir"] = _v(dir)
		rec["entrance"] = _v(fm)
		rec["entrance_h"] = snappedf(ent, 0.01)
		rec["road_h"] = snappedf(rh, 0.01)
		rec["slope_pct"] = snappedf(100.0 * maxf(absf(ent - back) / float(pc["depth"]), absf(fa - fb) / float(pc["frontage"])), 0.1)
		rec["clearance"]["front_gap_m"] = snappedf(_road_gap(poly, net, pc["road"]), 0.01)
	else:
		rec["landmark"] = pc["landmark"]
		rec["label"] = pc["label"]
		rec["landmark_at"] = _v(pc["at"])
		rec["footprint_road_overlap_m"] = snappedf(pc["footprint_road_overlap"], 0.01)
		var best := ""
		var bd := INF
		for r in net:
			var dd := poly_line_d(poly, r["pts"]) - float(r["hw"])
			if dd < bd:
				bd = dd
				best = r["name"]
		rec["road"] = best
		rec["clearance"]["front_gap_m"] = snappedf(bd, 0.01)
		rec["entrance_h"] = snappedf(h_fn.call(pc["at"]), 0.01)
		rec["road_h"] = snappedf(road_h_fn.call(best, pc["at"]), 0.01)
		rec["slope_pct"] = snappedf(100.0 * (hi - lo) / maxf(sqrt(area(poly)), 1.0), 0.1)
	return rec


static func _road_gap(poly: PackedVector2Array, net: Array, road: String) -> float:
	for r in net:
		if r["name"] == road:
			return poly_line_d(poly, r["pts"]) - float(r["hw"])
	return INF


static func _poly_poly_d(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if overlap_area(a, b) > 0.05:
		return 0.0
	var best := INF
	for i in a.size():
		for j in b.size():
			var cp := Geometry2D.get_closest_points_between_segments(a[i], a[(i + 1) % a.size()], b[j], b[(j + 1) % b.size()])
			best = minf(best, cp[0].distance_to(cp[1]))
	return best


static func _v(p: Vector2) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]


static func _arr(poly: PackedVector2Array) -> Array:
	var a: Array = []
	for p in poly:
		a.append(_v(p))
	return a
