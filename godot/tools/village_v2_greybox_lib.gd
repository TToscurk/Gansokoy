extends RefCounted
## 人間之里 V2 — P4 Greybox：建築量體。產生器 gen_village_v2.gd 與 P4 gate verify_village_v2_greybox.gd 共用。
##
## 參數：layout_v2.json 的 greybox（不在 Macro 凍結範圍）；輸入是 P3 已核准的 parcels.json 紀錄（不重算地塊）。
## 使用者裁示（2026-09-24，P3 ART_APPROVED 時）：
##   - 正式町家地塊（kind "machiya"）一塊放一棟主屋。
##   - 附屬用地（kind "aux"）不強制放建築：use「倉／小屋」才放一棟小附屬棟；「庭院」「後院」只有院子地面；「空地」什麼都不放。
##   - 鈴奈庵／鯢吞亭壓主街在 P4 以量體解：P0 凍結的位置／尺寸不動，灰盒改成正面平行主街、從路緣退縮，
##     完整落在 P3 固定地塊 P_LM_* 內（固定地塊已扣掉路幅＋road_gap，所以不會壓路）。
##
## 量體（全部公尺；京間半間 module＝0.91 m）：
##   主屋正面平行臨路面、退縮 setback、兩側內縮 side_inset；縱深 main_depth 內取 module 整數倍，背面至少留 rear_min 當院子。
##   類型 types：hiraya 平屋／zushi 厨子二階／nikai 總二階，各有簷高 eave 與 1F 庇高 hisashi（0＝無庇）。
##   屋頂切妻：平入（屋脊平行街道）或妻入（屋脊垂直街道，tsuma_seq）；
##   屋脊高＝簷高＋(跨距/2＋出簷)×pitch（由量體推算，不另外指定）。出簷一律不超出地塊線（臨街面例外：庇可伸出正面 hisashi_depth）。
##   台基：base＝footprint 內地面最高點；地板＝base＋plinth；基礎從地面最低點下 embed 起算（不浮空、不整棟埋進地裡）。
##   類型依序列（main_seq 給主街／入口道路、seq 給其他路），沒有亂數。

const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const PLib := preload("res://tools/village_v2_parcel_lib.gd")


## 回傳 {"buildings": Array, "yards": Array, "notes": Array}
## recs＝parcels.json 的 parcels；h_fn(Vector2) → 地面高
static func plan(L: Dictionary, recs: Array, net: Array, h_fn: Callable) -> Dictionary:
	var G: Dictionary = L["greybox"]
	var out: Array = []
	var yards: Array = []
	var notes: Array = []
	var counters := {}
	var fg := float(L["parcel_rules"]["front_gap"])   # 地塊臨路線離路緣（犬走り＋側溝）：簷與庇可以伸到這裡，不伸進路幅
	var main_roads: Array = G["main_roads"]
	var fixed := {}
	for r in recs:
		if r["kind"] == "landmark":
			fixed[String(r["landmark"])] = r
	for r in recs:
		var kind := String(r["kind"])
		if kind == "machiya":
			var D: Dictionary = G["districts"].get(r["district"], G["districts"]["default"])
			var main := main_roads.has(String(r["road"]))
			var ck := "%s_%s" % [r["district"], "main" if main else "other"]
			var i := int(counters.get(ck, 0))
			counters[ck] = i + 1
			var seq: Array = D["main_seq"] if main and D.has("main_seq") else D["seq"]
			var typ := String(seq[i % seq.size()])
			var tseq: Array = [] if main else D.get("tsuma_seq", [])
			var tsuma := not tseq.is_empty() and int(tseq[i % tseq.size()]) == 1
			var fe := front_edge(r)
			var pd := float(r["depth_m"])
			var setback := float(D["setback"])
			var inset := float(D["side_inset"])
			var md: Array = G["main_depth"]
			var mod := float(G["module"])
			var dep := minf(pd - setback - float(G["rear_min"]), float(md[1]))
			dep = maxf(floorf(dep / mod + 1e-6) * mod, float(md[0]))
			var b := _make(G, "B_" + String(r["id"]), "machiya", r, fe, setback, inset, dep, typ, tsuma,
				bool(D["shopfront"]) and typ != "hiraya", h_fn, i, setback + fg)
			out.append(b)
			var dirv: Vector2 = fe[2]
			var back := setback + dep
			if pd - back > 0.3:
				yards.append({"id": "Y_" + String(r["id"]), "district": r["district"], "kind": "machiya_yard",
					"poly": PackedVector2Array([fe[0] - dirv * back, fe[1] - dirv * back, fe[1] - dirv * pd, fe[0] - dirv * pd])})
		elif kind == "aux":
			var use := String(r.get("use", ""))
			var A: Dictionary = G["aux"]
			if (A["yard_uses"] as Array).has(use):
				yards.append({"id": "Y_" + String(r["id"]), "district": r["district"], "kind": "aux_yard",
					"poly": TLib.pts(r["footprint"])})
			elif use == String(A["use_build"]):
				var s := _shed(G, r, h_fn)
				if s.is_empty():
					notes.append("%s（%s）放不下附屬棟，保留空地" % [r["id"], use])
				else:
					out.append(s)
	for lid in G["landmarks"]:
		if String(lid).begins_with("_"):
			continue
		var cfg: Dictionary = G["landmarks"][lid]
		if not fixed.has(lid):
			notes.append("%s 沒有固定地塊" % lid)
			continue
		var lb := _landmark(L, G, String(lid), cfg, fixed[lid], net, h_fn)
		if lb.is_empty():
			notes.append("%s 灰盒放不進固定地塊" % lid)
		else:
			out.append(lb)
	return {"buildings": out, "yards": yards, "notes": notes}


## 地塊臨路面：[左角, 右角, 朝路方向]（左→右 沿 t＝(-dir.y, dir.x)）。
## parcels.json 的 front_dir 只存到 0.01（約 0.6° 誤差）→ 只用來挑出臨路兩角，朝向改由臨路邊本身算（與地塊邊精確垂直）。
static func front_edge(r: Dictionary) -> Array:
	var poly := TLib.pts(r["footprint"])
	var dirv := Vector2(float(r["front_dir"][0]), float(r["front_dir"][1])).normalized()
	var idx := [0, 1, 2, 3]
	idx.sort_custom(func(a, b): return poly[a].dot(dirv) > poly[b].dot(dirv))
	var p: Vector2 = poly[idx[0]]
	var q: Vector2 = poly[idx[1]]
	var t := Vector2(-dirv.y, dirv.x)
	if p.dot(t) > q.dot(t):
		var tmp := p
		p = q
		q = tmp
	var te := (q - p).normalized()
	return [p, q, Vector2(te.y, -te.x)]


## 一棟：臨路面 fe＝[a, b, dir]，正面離 fe 退 setback、兩側內縮 inset、縱深 dep
static func _make(G: Dictionary, id: String, kind: String, r: Dictionary, fe: Array, setback: float, inset: float,
		dep: float, typ: String, tsuma: bool, shopfront: bool, h_fn: Callable, seq_i: int, front_room: float) -> Dictionary:
	var a: Vector2 = fe[0]
	var b: Vector2 = fe[1]
	var dirv: Vector2 = fe[2]
	var t := (b - a).normalized()
	var fa := a + t * inset - dirv * setback
	var fb := b - t * inset - dirv * setback
	var w := fa.distance_to(fb)
	var poly := PackedVector2Array([fa, fb, fb - dirv * dep, fa - dirv * dep])
	var T: Dictionary = G["types"][typ]
	var dseq: Array = G["door_pos_seq"]
	var rec := _heights(G, poly, h_fn)
	rec.merge({"id": id, "kind": kind, "parcel": String(r["id"]), "district": String(r.get("district", "")),
		"road": String(r.get("road", "")), "type": typ, "type_label": String(T["label"]), "roof": "tsuma" if tsuma else "hira",
		"poly": poly, "center": (fa + fb) * 0.5 - dirv * dep * 0.5, "dir": dirv, "width": w, "depth": dep,
		"setback": setback, "side_inset": inset, "eave": float(T["eave"]),
		"hisashi": float(T["hisashi"]) if shopfront else 0.0,
		"door_u": float(dseq[seq_i % dseq.size()]) if w >= 5.4 else 0.5})
	_roof(G, rec, inset, front_room)
	return rec


## 出簷＋屋脊高。簷高＝牆線處高度；屋脊＝簷高＋半個牆跨距×pitch；簷口（出簷端）＝簷高−出簷×pitch。
## 出簷前後對稱；front_room＝正面到路緣的空間、side_room＝兩側到地塊線的空間，出簷不超過（留 5 cm）。
static func _roof(G: Dictionary, rec: Dictionary, side_room: float, front_room: float) -> void:
	var eo := float(G["eave_overhang"])
	var go := float(G["gable_overhang"])
	var pitch := float(G["types"].get(String(rec["type"]), {}).get("pitch", G["pitch"]))
	var w := float(rec["width"])
	var dep := float(rec["depth"])
	var half: float
	if rec["roof"] == "hira":   # 平入：屋脊平行正面；前後是簷、兩側是山牆
		rec["ov_eave"] = minf(eo, maxf(front_room - 0.05, 0.0))
		rec["ov_gable"] = minf(go, maxf(side_room - 0.05, 0.0))
		half = dep * 0.5
	else:                         # 妻入：屋脊垂直正面；兩側是簷、前後是山牆
		rec["ov_eave"] = minf(eo, maxf(side_room - 0.05, 0.0))
		rec["ov_gable"] = minf(go, maxf(front_room - 0.05, 0.0))
		half = w * 0.5
	rec["pitch"] = pitch
	rec["ridge"] = float(rec["eave"]) + half * pitch
	rec["eave_edge"] = float(rec["eave"]) - float(rec["ov_eave"]) * pitch


## footprint 內地面高（1 m 格＋邊）→ base（最高點）、lo（最低點）
static func _heights(G: Dictionary, poly: PackedVector2Array, h_fn: Callable) -> Dictionary:
	var lo := INF
	var hi := -INF
	var u := poly[1] - poly[0]
	var v := poly[3] - poly[0]
	var nu := maxi(1, int(ceil(u.length())))
	var nv := maxi(1, int(ceil(v.length())))
	for i in nu + 1:
		for j in nv + 1:
			var p := poly[0] + u * (float(i) / nu) + v * (float(j) / nv)
			var h: float = h_fn.call(p)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return {"base": hi, "ground_lo": lo, "plinth": float(G["plinth"]), "embed": float(G["embed"])}


## 附屬棟（aux use＝倉／小屋）：商業區土藏、其他小屋；放在背面角落（離地塊線 margin）。放不下回傳 {}
static func _shed(G: Dictionary, r: Dictionary, h_fn: Callable) -> Dictionary:
	var A: Dictionary = G["aux"]
	var fe := front_edge(r)
	var fr := (fe[0] as Vector2).distance_to(fe[1])
	var pd := float(r["depth_m"])
	var m := float(A["margin"])
	var order: Array = ["kura", "koya"] if (A["kura"]["districts"] as Array).has(String(r["district"])) else ["koya"]
	for k in order:
		var S: Dictionary = A[k]
		var w := float(S["w"])
		var d := float(S["d"])
		if w + 2.0 * m > fr or d + 2.0 * m > pd:
			continue
		var a: Vector2 = fe[0]
		var dirv: Vector2 = fe[2]
		var t := ((fe[1] as Vector2) - a).normalized()
		var fa := a + t * m - dirv * (pd - m - d)
		var fb := fa + t * w
		var poly := PackedVector2Array([fa, fb, fb - dirv * d, fa - dirv * d])
		var rec := _heights(G, poly, h_fn)
		rec.merge({"id": "S_" + String(r["id"]), "kind": "aux_" + String(k), "parcel": String(r["id"]),
			"district": String(r["district"]), "road": String(r["road"]), "type": String(k), "type_label": String(S["label"]),
			"roof": "tsuma" if d > w else "hira", "poly": poly, "center": (fa + fb) * 0.5 - dirv * d * 0.5, "dir": dirv,
			"width": w, "depth": d, "setback": pd - m - d, "side_inset": m, "eave": float(S["eave"]), "hisashi": 0.0,
			"door_u": 0.5})
		_roof(G, rec, m, pd - m - d)
		return rec
	return {}


## 地標灰盒：正面平行指定道路、正面離路緣 front_gap＋setback；完整落在固定地塊內。
## 先試設定的面寬／縱深、沿街平移 0、±0.5…±4 m；放不下再各縮 module。
static func _landmark(L: Dictionary, G: Dictionary, lid: String, cfg: Dictionary, fx: Dictionary, net: Array,
		h_fn: Callable) -> Dictionary:
	var lm: Dictionary = {}
	for e in L["landmarks"]:
		if String(e["id"]) == lid:
			lm = e
	var road: Dictionary = {}
	for e in net:
		if String(e["name"]) == String(cfg["road"]):
			road = e
	if lm.is_empty() or road.is_empty():
		return {}
	var P := Vector2(float(lm["at"][0]), float(lm["at"][1]))
	var pts: PackedVector2Array = road["pts"]
	var bd := INF
	var Q := Vector2.ZERO
	var t := Vector2.ZERO
	for k in pts.size() - 1:
		var c := Geometry2D.get_closest_point_to_segment(P, pts[k], pts[k + 1])
		if c.distance_to(P) < bd:
			bd = c.distance_to(P)
			Q = c
			t = (pts[k + 1] - pts[k]).normalized()
	var nn := Vector2(-t.y, t.x)
	if (P - Q).dot(nn) < 0.0:
		nn = -nn
	var dirv := -nn
	var setback := float(cfg["setback"])
	var off := float(road["hw"]) + float(L["parcel_rules"]["front_gap"]) + setback
	var parcel := TLib.pts(fx["footprint"])
	var grown := Geometry2D.offset_polygon(parcel, 0.01, Geometry2D.JOIN_MITER)
	var gp: PackedVector2Array = grown[0] if not grown.is_empty() else parcel
	var mod := float(G["module"])
	var W := float(cfg["frontage"])
	while W >= float(cfg["min_frontage"]) - 0.001:
		var D := float(cfg["depth"])
		while D >= float(cfg["min_depth"]) - 0.001:
			for si in 17:
				var sh := floorf((si + 1) * 0.5) * 0.5 * (1.0 if si % 2 == 1 else -1.0)
				var s0 := Q + t * sh + nn * off
				var fa := s0 - t * W * 0.5
				var fb := s0 + t * W * 0.5
				# 左→右 沿 (-dir.y, dir.x)
				var tt := Vector2(-dirv.y, dirv.x)
				if fa.dot(tt) > fb.dot(tt):
					var tmp := fa
					fa = fb
					fb = tmp
				var poly := PackedVector2Array([fa, fb, fb - dirv * D, fa - dirv * D])
				var ok := true
				for p in poly:
					if not Geometry2D.is_point_in_polygon(p, gp):
						ok = false
				if ok and absf(PLib.overlap_area(poly, parcel) - PLib.area(poly)) > 0.05:
					ok = false
				if ok:
					var T: Dictionary = G["types"][String(cfg["type"])]
					var rec := _heights(G, poly, h_fn)
					rec.merge({"id": "B_" + String(fx["id"]), "kind": "landmark", "landmark": lid, "label": String(lm["label"]),
						"parcel": String(fx["id"]), "district": String(fx.get("district", "")), "road": String(cfg["road"]),
						"type": String(cfg["type"]), "type_label": String(T["label"]), "roof": "hira", "poly": poly,
						"center": (fa + fb) * 0.5 - dirv * D * 0.5, "dir": dirv, "width": W, "depth": D, "setback": setback,
						"side_inset": 0.0, "eave": float(T["eave"]), "hisashi": float(T["hisashi"]), "door_u": 0.5,
						"shift_m": sh, "p0_size": lm["size"], "p0_yaw": float(lm.get("yaw", 0.0))})
					# 固定地塊內側邊還有空間：出簷可到 0.3 m
					_roof(G, rec, 0.3, setback + float(L["parcel_rules"]["front_gap"]))
					return rec
			D -= mod
		W -= mod
	return {}


## 建築局部座標（原點＝footprint 中心、地面 base；+Z＝朝路、+X＝沿正面由左到右）→ Godot yaw
static func yaw_of(dirv: Vector2) -> float:
	return atan2(dirv.x, dirv.y)
