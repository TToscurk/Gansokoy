extends RefCounted
## P8 全區農田生成器（r6，2026-10-01）：凍結階面平台塊（res://data/village_v2_p8_blocks.json，probe 實測，
## 不是手寫座標）→ 每塊自動切田、主渠／支渠、每田水口／落水口（田越し）、落水溝、跨路暗渠／涵洞或伏越し
## （依水理自動判定並寫入節點名與 meta）、跨階落差工（小堰）、北側逐階排水接主河、水車 1／3 取水
## （沿用 r5 短落とし樋＋落とし桝＋地面木槽語彙，高架只在水車岸坡）、旱田／休耕、跨渠板、少量農具。
## pilot（S1 塊：r4 田格＋r5 取水，使用者鎖定）不重生；全區只在其外擴張。田埂可見網格與碰撞沿用
## lib.bund_eval／_bund_body／visual._bund_art 同一套函式；田面沿用 visual._field_art（泥底＋預乘淺水＋MultiMesh 秧苗）。
## 田埂只落在平台塊（階面平坦處）；跨階／跨路構件的地面高取 data/village_v2_p8_ground.json（地形碰撞實測）。
const FL := preload("res://tools/village_v2_farmland_lib.gd")
const Visual := preload("res://tools/village_v2_farmland_visual.gd")
const BLOCKS := "res://data/village_v2_p8_blocks.json"
const GROUND := "res://data/village_v2_p8_ground.json"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const RIVER_WATER := -0.8          # layout heights.river_water
const MAIN_WATER := 0.078          # 主渠／支渠上游水位（相對階面；與 pilot 內渠同值）
const DRAIN_W := 0.03              # 落水溝水位（相對階面；= FL.DRAIN_WATER_LIFT）
const PIPE_COVER := 0.10           # 路下管頂覆土
const TRI_STEP := 0.8              # 全區田面三角網步距（pilot 0.55）
const CHUNK := 18.0                # 全區 MultiMesh 分塊（pilot 9 m）
## 塊規格：pick＝落在該 probe 塊內的一點；axis＝支渠走向（z／x）；near＝進水端（lo＝座標小端）；
## lat＝支渠位置（mid＝塊中、兩側有田／edge＝貼 lo 側、只一側有田）；in／out＝進水口／出水口在跨向哪一側（lo／hi／lat）
const SPEC := [
	{"id": "T0", "pick": [350, 110], "use": "paddy", "axis": "z", "near": "lo", "lat": "mid", "in": "lo", "out": "hi"},
	{"id": "T1", "pick": [405, 110], "use": "paddy", "axis": "z", "near": "hi", "lat": "mid", "in": "lo", "out": "hi"},
	{"id": "T2", "pick": [470, 110], "use": "paddy", "axis": "z", "near": "lo", "lat": "mid", "in": "lo", "out": "hi"},
	{"id": "T3", "pick": [527, 110], "use": "paddy", "axis": "z", "near": "hi", "lat": "mid", "in": "lo", "out": "hi"},
	{"id": "S2", "pick": [470, 35], "use": "paddy", "axis": "z", "near": "hi", "lat": "mid", "in": "lo", "out": "lo"},
	{"id": "S3", "pick": [528, 35], "use": "paddy", "axis": "z", "near": "hi", "lat": "mid", "in": "hi", "out": "hi"},
	{"id": "N0", "pick": [360, -80], "use": "paddy", "axis": "z", "near": "hi", "lat": "edge", "in": "lat", "out": "hi"},
	{"id": "N1", "pick": [405, -100], "use": "paddy", "axis": "x", "near": "lo", "lat": "mid", "in": "lat", "out": "lat"},
	{"id": "N2", "pick": [470, -50], "use": "paddy", "axis": "z", "near": "hi", "lat": "mid", "in": "lo", "out": "lo"},
	{"id": "N3", "pick": [528, -45], "use": "paddy", "axis": "z", "near": "hi", "lat": "mid", "in": "hi", "out": "lo"},
	{"id": "S0a", "pick": [350, 55], "use": "dry"},
	{"id": "S0b", "pick": [352, 22], "use": "dry"},
	{"id": "N0a", "pick": [357, -17], "use": "fallow"},
]
## 逐階水路（上游塊出水口 → 下游塊進水口）：串成 T0→T1→T2→T3→S3→N3→主河、pilot→S2→N2→主河、N0→N1→N2
const LINKS := [["T0", "T1"], ["T1", "T2"], ["T2", "T3"], ["T3", "S3"], ["S3", "N3"],
	["PILOT", "S2"], ["S2", "N2"], ["N0", "N1"], ["N1", "N2@O"]]
const FEEDERS := [["LANDMARK_WATERWHEEL_3", "T0"], ["LANDMARK_WATERWHEEL_1", "N0"]]
const OUTFALLS := ["N2", "N3"]
## r5 水車 2 受け樋頭相對水車 Hero 原點（水車局部座標：x 軸＝朝水渠中心；由 lib.CHUTE[0] 與水車 2 transform 反算）
const HEAD_LOCAL := Vector3(3.252, 4.821, -0.368)
const WHEEL_DY := {"LANDMARK_WATERWHEEL_1": 0.094, "LANDMARK_WATERWHEEL_2": 0.5596, "LANDMARK_WATERWHEEL_3": 0.8507}
const WHEEL_YAW := {"LANDMARK_WATERWHEEL_1": -4.574, "LANDMARK_WATERWHEEL_2": -13.496, "LANDMARK_WATERWHEEL_3": -26.565}

static var _cache := {}
static var _G := {}
static var _L := {}

## plan() 呼叫：把全區田、田埂、水利併入 pilot plan（同一 dict 格式；全區田埂名以 Z 開頭）
static func extend(P: Dictionary) -> void:
	if _cache.is_empty():
		_cache = _generate(P)
	for k: String in _cache["bunds"]:
		P["bunds"][k] = _cache["bunds"][k]
	for fd: Dictionary in _cache["fields"]:
		P["fields"].append(fd)
	P["zone"] = _cache["zone"]

# ───────────────────────────── 生成 ─────────────────────────────

static func _generate(P: Dictionary) -> Dictionary:
	_load()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BLOCKS))
	var bunds := {}
	var fields: Array = []
	var zone := {"blocks": {}, "fallow": [], "dry": [], "meadow": [], "links": [], "feeders": [], "outfalls": [], "props": []}
	for spec: Dictionary in SPEC:
		var pick := Vector2(spec["pick"][0], spec["pick"][1])
		var blk := {}
		for b: Dictionary in data["blocks"]:
			if Geometry2D.is_point_in_polygon(pick, _block_poly(b)):
				blk = b
				break
		assert(not blk.is_empty(), "P8 zone: block %s not found" % spec["id"])
		match String(spec["use"]):
			"paddy":
				zone["blocks"][spec["id"]] = _paddy(spec, blk, bunds, fields, zone)
			"dry":
				_dry(spec, blk, zone)
			"fallow":
				zone["meadow"].append({"name": spec["id"], "poly": _shrink(_block_poly(blk), 1.2), "lv": float(blk["level"])})
	var pilot_o: Vector2 = (P["drain"] as PackedVector2Array)[(P["drain"] as PackedVector2Array).size() - 1]
	for ln: Array in LINKS:
		zone["links"].append(_link(ln[0], ln[1], zone, data, pilot_o))
	for fdr: Array in FEEDERS:
		zone["feeders"].append(_feeder(fdr[0], zone["blocks"][fdr[1]]))
	for bid: String in OUTFALLS:
		zone["outfalls"].append(_outfall(zone["blocks"][bid]))
	for bn: String in bunds:
		var d: Dictionary = bunds[bn]
		d["length"] = FL._length(d["pts"])
	# 田面：水面內緣＝回圈扣掉本田田埂腳；插秧區再內縮（同 pilot 0.55／1.35）
	for fd: Dictionary in fields:
		fd["water"] = minus_own(fd, bunds, 0.55)
		fd["plant"] = minus_own(fd, bunds, 1.35)
	return {"bunds": bunds, "fields": fields, "zone": zone}

static func _load() -> void:
	if _G.is_empty():
		_G = JSON.parse_string(FileAccess.get_file_as_string(GROUND))
		_L = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))

## 地形碰撞高（1 m 格雙線性；probe 實測，含階差坡與岸坡）
static func ground_h(p: Vector2) -> float:
	_load()
	var nx := int(_G["nx"])
	var nz := int(_G["nz"])
	var fx := clampf(p.x - float(_G["x0"]), 0.0, nx - 1.001)
	var fz := clampf(p.y - float(_G["z0"]), 0.0, nz - 1.001)
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h: Array = _G["h"]
	var a := float(h[iz * nx + ix])
	var b := float(h[iz * nx + ix + 1])
	var c := float(h[(iz + 1) * nx + ix])
	var d := float(h[(iz + 1) * nx + ix + 1])
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

static func _block_poly(b: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in b["L"]:
		out.append(Vector2(p[0], p[1]))
	var r: Array = b["R"].duplicate()
	r.reverse()
	for p: Array in r:
		out.append(Vector2(p[0], p[1]))
	return out

## 一塊水田：local 座標 x＝跨向 v、y＝沿支渠（由進水端往遠端遞增）；world(p) 換回世界 xz
static func _paddy(spec: Dictionary, blk: Dictionary, bunds: Dictionary, fields: Array, zone: Dictionary) -> Dictionary:
	var id: String = spec["id"]
	var axis: String = spec["axis"]
	var sgn := 1.0 if spec["near"] == "lo" else -1.0
	var lv := float(blk["level"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001 + absi(id.hash()) % 997
	var wpoly := _block_poly(blk)
	var ctr := FL._centroid(wpoly)
	var edge_mode: bool = spec["lat"] == "edge"
	var wmin := 12.0 if edge_mode else 24.0
	var world := func(p: Vector2) -> Vector2:
		return Vector2(p.x, sgn * p.y) if axis == "z" else Vector2(sgn * p.y, p.x)
	# 沿 y 每 1 m 取跨向範圍，取最長一段寬度 ≥ wmin 的連續區間
	var bb := FL._bbox(wpoly)
	var u0 := bb.position.y if axis == "z" else bb.position.x
	var u1 := bb.end.y if axis == "z" else bb.end.x
	var ya := minf(sgn * u0, sgn * u1)
	var yb := maxf(sgn * u0, sgn * u1)
	var span := {}
	var best := [0, -1]
	var run_s := 0
	var in_run := false          # 旗標（local y 可為負，不能用 −1 當哨兵）
	var yi := ceili(ya)
	while yi <= floori(yb) + 1:
		var sp := _span(wpoly, axis, sgn * yi)
		var ok := yi <= floori(yb) and sp.y - sp.x >= wmin
		if ok:
			span[yi] = sp
			if not in_run:
				run_s = yi
				in_run = true
		else:
			if in_run and yi - 1 - run_s > best[1] - best[0]:
				best = [run_s, yi - 1]
			in_run = false
		yi += 1
	var y0 := float(best[0])
	var y1 := float(best[1])
	var vlo := func(y: float) -> float: return _span_lerp(span, y, 0)
	var vhi := func(y: float) -> float: return _span_lerp(span, y, 1)
	# 支渠中心線（兩次以內輕微偏折，最大 15°）
	var has_main: bool = spec["in"] in ["lo", "hi"]
	var y_head := y0 + (1.0 if has_main else 0.2)
	var cn := y1 - 1.83                      # 遠端外埂（其外為落水溝）
	var lat := PackedVector2Array()
	if edge_mode:
		var y := y0 + 0.2
		while y <= cn + 0.4:
			var m := -INF
			for k in range(-5, 6):
				m = maxf(m, vlo.call(clampf(y + k, y0, y1)))
			lat.append(Vector2(minf(m + 1.35, vhi.call(y) - 10.0), y))
			y += 1.0
	else:
		var base := 0.0
		var n := 0
		for k: int in span:
			base += (span[k].x + span[k].y) * 0.5
			n += 1
		base /= n
		var st := [y0 + 0.2, lerpf(y0, cn, 0.36), lerpf(y0, cn, 0.7), cn + 0.4]
		var vs: Array = []
		for s: float in st:
			vs.append(clampf(base + rng.randf_range(-0.9, 0.9), vlo.call(s) + 8.5, vhi.call(s) - 8.5))
		var y := y0 + 0.2
		while y <= cn + 0.4 + 1e-3:
			var k := 0
			while k < 2 and y > st[k + 1]:
				k += 1
			var v := lerpf(vs[k], vs[k + 1], clampf((y - st[k]) / (st[k + 1] - st[k]), 0.0, 1.0))
			lat.append(Vector2(clampf(v, vlo.call(y) + 8.0, vhi.call(y) - 8.0), y))
			y += 1.0
	lat = _dp(lat, 0.25)
	var lipA := FL._offset_line(FL._round(lat, FL.CORNER_R), FL.LIP_OFF)     # v 小側
	var lipB := FL._offset_line(FL._round(lat, FL.CORNER_R), -FL.LIP_OFF)    # v 大側
	var latv := func(y: float) -> float: return FL.x_at(lat, y)
	# 進水口／主渠
	var main_y := y0 + 1.0
	var I := Vector2.ZERO
	var main_line := PackedVector2Array()
	var in_side: String = spec["in"]
	if has_main:
		var vi: float = vlo.call(main_y) + 0.6 if in_side == "lo" else vhi.call(main_y) - 0.6
		I = Vector2(vi, main_y)
		main_line = PackedVector2Array([I, Vector2(latv.call(main_y), main_y)])
	else:
		I = Vector2(latv.call(y0 + 0.2), y0 + 0.2)
	# 切線（田界）：每側 11–17 m 一條；兩側錯開 ≥ 3.5 m（沒有十字路口）
	var sides := ["B"] if edge_mode else ["A", "B"]
	var cuts := {}
	for S: String in sides:
		var c0 := y0 + 0.9
		if has_main and ((S == "A") == (in_side == "lo")):
			c0 = y0 + 1.62
		var arr := [c0]
		var y := c0
		while true:
			y += rng.randf_range(11.0, 17.0)
			if y > cn - 9.0:
				break
			arr.append(y)
		arr.append(cn)
		cuts[S] = arr
	if not edge_mode:
		var fixed := [cuts["B"][0]]
		for i in range(1, cuts["B"].size() - 1):
			var y: float = cuts["B"][i]
			for it in 8:
				var clash := false
				for ya2: float in cuts["A"]:
					if absf(ya2 - y) < 3.5:
						clash = true
				if not clash:
					break
				y += 1.0
			if y - float(fixed[fixed.size() - 1]) >= 8.0 and cn - y >= 8.0:
				fixed.append(y)
		fixed.append(cn)
		cuts["B"] = fixed
	var blk_out := {"id": id, "lv": lv, "axis": axis, "sgn": sgn, "ctr": ctr, "lat": _to_w(lat, world),
		"lipA": "Z%s_LipA" % id, "lipB": "Z%s_LipB" % id, "cuts": {}, "I": world.call(I), "fields": []}
	# 支渠兩唇（進水側主渠內唇當 A／B 的第一道田界）
	var lip_a0 := y_head - 0.62 if not (has_main and in_side == "lo") else y0 + 1.62
	var lip_b0 := y_head - 0.62 if not (has_main and in_side == "hi") else y0 + 1.62
	if has_main:
		if in_side == "lo":
			lip_b0 = y0 + 0.38
		else:
			lip_a0 = y0 + 0.38
	var lipA_raw := FL._slice(lipA, lip_a0, cn + 0.35)
	var lipB_raw := FL._slice(lipB, lip_b0, cn + 0.35)
	_add_bund(bunds, "Z%s_LipA" % id, _to_w(lipA_raw, world), "lip", ["cap", "cap"], id, ctr)
	_add_bund(bunds, "Z%s_LipB" % id, _to_w(lipB_raw, world), "lip", ["cap", "cap"], id, ctr)
	if has_main:
		# 主渠外唇：沿進水端塊緣，由進水口接到支渠另一側唇
		var ym := y0 + 0.38
		var far_lip := lipB if in_side == "lo" else lipA
		var vi0: float = vlo.call(ym) + 0.3 if in_side == "lo" else vhi.call(ym) - 0.3
		_add_bund(bunds, "Z%s_MainLip" % id, _to_w(PackedVector2Array([Vector2(vi0, ym), Vector2(FL.x_at(far_lip, ym), ym)]), world), "lip", ["cap", "t"], id, ctr)
		blk_out["main"] = _to_w(main_line, world)
	# 田
	var fcount := 0
	var fallow_done := false
	var walked_cut := rng.randi_range(1, 2)
	for S: String in sides:
		var cs: Array = cuts[S]
		blk_out["cuts"][S] = []
		var lip := lipA if S == "A" else lipB
		var lip_name := "Z%s_Lip%s" % [id, S]
		var sd := -1.0 if S == "A" else 1.0
		var nf := cs.size() - 1
		# 每田外緣：沿塊緣內縮 0.6 m ＋每田 0–1.6 m 錯位（不規則外緣、錯位台階）
		var edges: Array = []
		for k in nf:
			var dl := 0.0 if rng.randf() < 0.45 else rng.randf_range(0.4, 1.6)
			var e := PackedVector2Array()
			var y := maxf(float(cs[k]) - 2.5, y0)
			var y_end := minf(float(cs[k + 1]) + 2.5, y1)
			while true:
				var v: float = vlo.call(y) + 0.6 + dl if S == "A" else vhi.call(y) - 0.6 - dl
				e.append(Vector2(v, y))
				if y >= y_end:
					break
				y = minf(y + 2.0, y_end)
			edges.append(_dp(e, 0.3))
		# 切線折線（邊緣 → 中段輕微偏折 → 唇）
		var cutl: Array = []
		for k in cs.size():
			var c: float = cs[k]
			var ve: float = vlo.call(c) - 0.5 if S == "A" else vhi.call(c) + 0.5
			var vl: float = latv.call(c) + (0.3 if S == "A" else -0.3)
			var j := 0.45 if (k > 0 and k < cs.size() - 1) else 0.12
			cutl.append(PackedVector2Array([Vector2(ve, c + rng.randf_range(-j, j)), Vector2(lerpf(ve, vl, rng.randf_range(0.35, 0.65)), c + rng.randf_range(-j, j)), Vector2(vl, c + rng.randf_range(-j * 0.5, j * 0.5))]))
			blk_out["cuts"][S].append(c)
		# 田界田埂（切線段：唇 → 較外一側的田緣）
		var cut_names: Array = []
		for k in cs.size():
			var pl := _isect(cutl[k], lip)
			var outs: Array = []
			if k > 0:
				outs.append(_isect(cutl[k], edges[k - 1]))
			if k < nf:
				outs.append(_isect(cutl[k], edges[k]))
			var po: Vector2 = outs[0]
			for q: Vector2 in outs:
				if absf(q.x - pl.x) > absf(po.x - pl.x):
					po = q
			var nm := "Z%s_Cut%s%d" % [id, S, k]
			var cls := "inner"
			if k == 0:
				cls = "lip" if (has_main and ((S == "A") == (in_side == "lo"))) else "outer"
			elif k == cs.size() - 1:
				cls = "outer"
			_add_bund(bunds, nm, _to_w(_sub(cutl[k], pl, po), world), cls, ["t", "t"], id, ctr)
			if k == walked_cut:
				bunds[nm]["walked"] = true
				blk_out["walk_cut"] = nm
			cut_names.append(nm)
		for k in nf:
			var ek: PackedVector2Array = edges[k]
			var p1 := _isect(cutl[k], ek)
			var p2 := _isect(cutl[k], lip)
			var p3 := _isect(cutl[k + 1], lip)
			var p4 := _isect(cutl[k + 1], ek)
			var en := "Z%s_Edge%s%d" % [id, S, k]
			_add_bund(bunds, en, _to_w(_sub(ek, p1, p4), world), "outer" if (k + fcount) % 3 != 1 else "outer_grass", ["t", "t"], id, ctr)
			var loop := PackedVector2Array()
			for part: PackedVector2Array in [_sub(cutl[k], p1, p2), _sub(lip, p2, p3), _sub(cutl[k + 1], p3, p4), _sub(ek, p4, p1)]:
				for q in part:
					FL._push(loop, world.call(q))
			if loop[0].distance_to(loop[loop.size() - 1]) < 0.05:
				loop.remove_at(loop.size() - 1)
			var name := "%s%s%d" % [id, S, k + 1]
			var bnames := [cut_names[k], lip_name, cut_names[k + 1], en]
			if has_main and k == 0 and not ((S == "A") == (in_side == "lo")):
				bnames.append("Z%s_MainLip" % id)
			var is_fallow := k == 0 and not fallow_done and nf >= 3 and rng.randf() < 0.55
			if is_fallow:
				fallow_done = true
				zone["fallow"].append({"name": name, "loop": loop, "bnames": bnames, "lv": lv, "block": id})
				fcount += 1
				continue
			# 水口（支渠唇）
			var yin := lerpf(float(cs[k]), float(cs[k + 1]), rng.randf_range(0.3, 0.7))
			var lp := Vector2(FL.x_at(lip, yin), yin)
			var lpw: Vector2 = world.call(lp)
			var into: Vector2 = (world.call(lp + Vector2(sd, 0)) - lpw).normalized()
			var lb: Dictionary = bunds[lip_name]
			var w_ch := MAIN_WATER if yin < (y_head + cn) * 0.5 else FL.CH_WATER_N
			lb["notches"].append({"s": FL.project_s(lb["pts"], lpw), "w": 0.55, "crest": FL.INLET_CREST, "kind": "inlet", "field": name, "dir": into, "ch": w_ch})
			# 落水口：田越し到下一塊田；最後一塊落到遠端落水溝
			var last := k == nf - 1
			var ob: Dictionary = bunds[cut_names[k + 1]]
			var oq: Vector2 = world.call(p3.lerp(p4, rng.randf_range(0.3, 0.7)))
			var down: Vector2 = (world.call(Vector2(p3.x, p3.y + 1.0)) - world.call(p3)).normalized()
			ob["notches"].append({"s": FL.project_s(ob["pts"], oq), "w": 0.45, "crest": FL.OUTLET_CREST, "kind": "outlet", "field": name, "dir": down})
			var st := _style(rng, 0.0 if axis == "z" else 90.0)
			var fd := {"name": name, "loop": loop, "lift": FL.WATER_LIFT, "flow": ["lateral", "drain" if last else "%s%s%d" % [id, S, k + 2]],
				"style": st, "inlet_xz": lpw, "tri_step": TRI_STEP, "chunk": CHUNK, "block": id, "ch_water": w_ch, "zone": true, "bnames": bnames}
			fields.append(fd)
			blk_out["fields"].append(name)
			fcount += 1
	# 踩踏凹口（常走的外緣埂）
	for i in 3:
		var names: Array = []
		for bn: String in bunds:
			if bn.begins_with("Z%s_Edge" % id):
				names.append(bn)
		if names.is_empty():
			break
		var bd: Dictionary = bunds[names[rng.randi() % names.size()]]
		var L := FL._length(bd["pts"])
		if L > 4.0:
			bd["notches"].append({"s": rng.randf_range(1.5, L - 1.5), "w": 0.8, "crest": 0.0, "kind": "tread", "field": ""})
	# 落水溝（遠端外埂外側，流向出水口）＋溝唇
	var yd := y1 - 1.0
	var dv0: float = vlo.call(yd) + 0.6
	var dv1: float = vhi.call(yd) - 0.6
	var dline := PackedVector2Array([Vector2(dv0, yd), Vector2(dv1, yd)])
	var out_side: String = spec["out"]
	var O := Vector2(dv0, yd)
	if out_side == "hi":
		dline = PackedVector2Array([Vector2(dv0, yd), Vector2(dv1, yd)])
		O = Vector2(dv1, yd)
	elif out_side == "lo":
		dline = PackedVector2Array([Vector2(dv1, yd), Vector2(dv0, yd)])
	else:
		O = Vector2(latv.call(yd), yd)
	_add_bund(bunds, "Z%s_DrainLip" % id, _to_w(PackedVector2Array([Vector2(vlo.call(y1 - 0.33) + 0.3, y1 - 0.33), Vector2(vhi.call(y1 - 0.33) - 0.3, y1 - 0.33)]), world), "ditch", ["cap", "cap"], id, ctr)
	blk_out["drain"] = _to_w(dline, world)
	blk_out["O"] = world.call(O)
	blk_out["lat_line"] = _to_w(FL._slice(FL._round(lat, FL.CORNER_R), y_head, cn + 0.2), world)
	blk_out["weir"] = world.call(Vector2(latv.call((y_head + cn) * 0.5), (y_head + cn) * 0.5))
	blk_out["lat_end"] = world.call(Vector2(latv.call(cn), cn))
	blk_out["plank_lat"] = blk_out.get("walk_cut", "")
	blk_out["span_y"] = [y0, y1]
	# 各田埂常走／畦塗り
	for bn: String in bunds:
		var d: Dictionary = bunds[bn]
		if d.get("zone", "") != id:
			continue
		d["plaster"] = rng.randf_range(0.0, 0.9)
		if not d.has("walked"):
			d["walked"] = bn.ends_with("MainLip") or rng.randf() < 0.18
	return blk_out

static func _add_bund(bunds: Dictionary, name: String, pts: PackedVector2Array, cls: String, ends: Array, bid: String, ctr: Vector2) -> void:
	var d := FL._bd(pts, cls, ends, 101 + absi(name.hash()) % 89)
	d["zone"] = bid
	d["ctr"] = ctr
	d["step"] = 0.3
	d["lod"] = true
	d["detail"] = 0.3
	d["chunk"] = CHUNK
	bunds[name] = d

## 田的秧苗／水面樣式：由 pilot 七田的範圍內取值（株高決定葉數、色、水色；行向沿支渠或垂直 ±12°）
static func _style(rng: RandomNumberGenerator, lat_deg: float) -> Dictionary:
	var stage := rng.randf_range(0.15, 0.38)
	var t := inverse_lerp(0.15, 0.38, stage)
	var young := Color(0.40, 0.52, 0.22)
	var old := Color(0.21, 0.37, 0.13)
	return {"stage": stage, "leaves": int(round(lerpf(4.0, 7.0, t))), "row": rng.randf_range(0.29, 0.31),
		"hill": lerpf(0.19, 0.16, t) + rng.randf_range(-0.008, 0.008),
		"dir": lat_deg + (0.0 if rng.randf() < 0.5 else 90.0) + rng.randf_range(-12.0, 12.0),
		"miss": lerpf(0.09, 0.02, t) + rng.randf_range(0.0, 0.02), "holes": rng.randf_range(0.1, 0.6), "lean": lerpf(0.55, 0.2, t),
		"col": young.lerp(old, t), "tip": Color(0.56, 0.57, 0.30).lerp(Color(0.30, 0.43, 0.16), t), "wobble": lerpf(0.08, 0.03, t),
		"water": {"tint": Color(0.31, 0.28, 0.20).lerp(Color(0.22, 0.23, 0.16), t), "clarity": clampf(lerpf(0.55, 0.9, t) + rng.randf_range(-0.08, 0.08), 0.4, 0.92),
			"rough": rng.randf_range(0.03, 0.07), "ripple": rng.randf_range(0.4, 0.9), "algae": rng.randf_range(0.0, 0.6) if rng.randf() < 0.6 else 0.0},
		"mud": {"trodden": lerpf(0.25, 0.0, t), "forest": lerpf(0.0, 0.3, t)}}

## 旱田（畑）：塊內縮後沿長邊切 2–3 區，各區畝向／作物不同
static func _dry(spec: Dictionary, blk: Dictionary, zone: Dictionary) -> void:
	var poly := _shrink(_block_poly(blk), 1.2)
	var bb := FL._bbox(poly)
	var rng := RandomNumberGenerator.new()
	rng.seed = 919 + absi(String(spec["id"]).hash()) % 97
	var long_z := bb.size.y >= bb.size.x
	var L := bb.size.y if long_z else bb.size.x
	var n := 2 if L < 22.0 else 3
	var a := bb.position.y if long_z else bb.position.x
	var cuts := [a - 1.0]
	for i in range(1, n):
		cuts.append(a + L * i / n + rng.randf_range(-2.0, 2.0))
	cuts.append(a + L + 1.0)
	for i in n:
		var c0: float = cuts[i] + (0.7 if i > 0 else 0.0)
		var c1: float = cuts[i + 1] - (0.7 if i < n - 1 else 0.0)
		var rect := PackedVector2Array()
		if long_z:
			rect = PackedVector2Array([Vector2(bb.position.x - 5, c0), Vector2(bb.end.x + 5, c0), Vector2(bb.end.x + 5, c1), Vector2(bb.position.x - 5, c1)])
		else:
			rect = PackedVector2Array([Vector2(c0, bb.position.y - 5), Vector2(c1, bb.position.y - 5), Vector2(c1, bb.end.y + 5), Vector2(c0, bb.end.y + 5)])
		var part := FL._largest(Geometry2D.intersect_polygons(poly, rect), PackedVector2Array())
		if part.size() < 3 or absf(FL._area(part)) < 40.0:
			continue
		zone["dry"].append({"name": "%s_%d" % [spec["id"], i + 1], "poly": part, "lv": float(blk["level"]),
			"dir": (0.0 if (i % 2 == 0) == long_z else 90.0) + rng.randf_range(-6.0, 6.0), "crop": ["leafy", "wheat", "bean"][(i + absi(String(spec["id"]).hash())) % 3]})

static func _shrink(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	return FL._largest(Geometry2D.offset_polygon(poly, -d), poly)

## 逐階連接：出水口 O → 下游進水口 I。跨凍結農路＝路兩側成對石桝＋路下管（依水理定名）；跨階差坡無路＝落差工（小堰）
static func _link(src: String, dst: String, zone: Dictionary, data: Dictionary, pilot_o: Vector2) -> Dictionary:
	var up_w: float
	var O: Vector2
	if src == "PILOT":
		O = pilot_o
		up_w = FL.DRAIN_WATER_LIFT
	else:
		var b: Dictionary = zone["blocks"][src]
		O = b["O"]
		up_w = float(b["lv"]) + DRAIN_W
	var to_drain := dst.ends_with("@O")
	var db: Dictionary = zone["blocks"][dst.trim_suffix("@O")]
	var I: Vector2 = db["O"] if to_drain else db["I"]
	var dn_w := float(db["lv"]) + (DRAIN_W if to_drain else MAIN_WATER)
	var out := {"from": src, "to": dst, "O": O, "I": I, "up_w": up_w, "dn_w": dn_w}
	var hit := _road_cross(O, I)
	if hit.is_empty():
		out["kind"] = "drop"
		out["name"] = "DropWeir_%s_%s" % [src, dst.trim_suffix("@O")]
		out["hyd"] = "落差工（小堰）"
		out["path"] = PackedVector2Array([O, I])
		return out
	var road: Dictionary = hit["road"]
	var c: Vector2 = hit["at"]
	var dir: Vector2 = hit["dir"]           # 路走向
	var n := Vector2(-dir.y, dir.x)
	if n.dot(I - O) < 0.0:
		n = -n
	var off := float(road["half_w"]) + 1.8
	var A := c - n * off
	var B := c + n * off
	var road_y := _road_y(data, String(road["name"]), c)
	var pipe_top := road_y - PIPE_COVER
	var siphon := dn_w > pipe_top
	out["kind"] = "road"
	out["road"] = road["name"]
	out["A"] = A
	out["B"] = B
	out["road_y"] = road_y
	out["pipe_top"] = pipe_top
	out["hyd"] = "伏越し" if siphon else "暗渠／涵洞"
	out["name"] = "%s_%s_%s" % ["Siphon" if siphon else "Culvert", src, dst.trim_suffix("@O")]
	# O → A（開渠，先沿出水方向再轉進桝）、B → I
	var mid := O + (A - O).project(n) if absf((A - O).dot(n)) > 2.0 else O
	out["path_a"] = FL._dedupe(PackedVector2Array([O, O.lerp(A, 0.5) if mid == O else mid, A]), 0.3)
	out["path_b"] = FL._dedupe(PackedVector2Array([B, I]), 0.3)
	return out

## O→I 是否跨凍結農路：回傳 {road, at, dir}（沿路分段；含路寬＋0.3 m）
static func _road_cross(a: Vector2, b: Vector2) -> Dictionary:
	for road: Dictionary in _L["roads"]:
		var pts: Array = road["pts"]
		for i in pts.size() - 1:
			var p := Vector2(pts[i][0], pts[i][1])
			var q := Vector2(pts[i + 1][0], pts[i + 1][1])
			var d := (q - p).normalized()
			var ext := float(road["half_w"]) + 0.3
			var x: Variant = Geometry2D.segment_intersects_segment(a, b, p - d * ext, q + d * ext)
			if x != null:
				return {"road": road, "at": x, "dir": d}
			# 平行貼近也算（兩端點離路中心都 < 半寬）
	return {}

static func _road_y(data: Dictionary, name: String, c: Vector2) -> float:
	var best := INF
	var y := 0.0
	for s: Array in data["road_surface"].get(name, []):
		var d := Vector2(s[0], s[1]).distance_to(c)
		if d < best:
			best = d
			y = float(s[2])
	return y

## 取水：水車（1／3）→ 短落とし樋（只跨岸坡）→ 落とし桝 → 地面木槽 → 塊進水口
static func _feeder(lm_id: String, blk: Dictionary) -> Dictionary:
	var at := Vector2.ZERO
	for lm: Dictionary in _L["landmarks"]:
		if lm["id"] == lm_id:
			at = Vector2(lm["at"][0], lm["at"][1])
	# 水車 Hero 原點＝Landmark（地形高）＋dy；水車 2 實測：landmark y＋0.5596＝−1.521（水渠水面）
	var origin_y := -1.521 if lm_id != "LANDMARK_WATERWHEEL_1" else -1.397
	var yaw := deg_to_rad(float(WHEEL_YAW[lm_id]))
	var xcol := Vector2(cos(yaw), -sin(yaw))
	var zcol := Vector2(sin(yaw), cos(yaw))
	var head2 := at + xcol * HEAD_LOCAL.x + zcol * HEAD_LOCAL.z
	var head := Vector3(head2.x, origin_y + HEAD_LOCAL.y, head2.y)
	var I: Vector2 = blk["I"]
	var dn_w := float(blk["lv"]) + MAIN_WATER
	var box_w := dn_w + 0.04
	# 落とし桝：沿水車 x 軸往岸上，找岸頂（地面 > −0.2 且往內 1.5 m 起伏 < 0.08 m）再往內 1.0 m 的點；
	# 岸頂不一定等於平台塊階面（水車 3 岸頂 0.13、T0 階面 0.30），木槽由此沿地面緩升接塊進水口
	var box := head2 + xcol * 6.0
	for k in 60:
		var q := head2 + xcol * (2.0 + k * 0.25)
		if ground_h(q) > -0.2 and absf(ground_h(q + xcol * 1.5) - ground_h(q)) < 0.08:
			box = q + xcol * 1.0
			break
	var end := Vector3(box.x, box_w + 0.18, box.y) + Vector3(-xcol.x, 0, -xcol.y) * 0.2
	var hd := Vector2(end.x - head.x, end.z - head.z)
	var mid := Vector3(head.x + hd.x * 0.55, head.y - (head.y - end.y) * 0.6, head.z + hd.y * 0.55)
	var trough := FL._dedupe(PackedVector2Array([box + xcol * 0.45, box.lerp(I, 0.5), I]), 0.3)
	return {"wheel": lm_id, "chute": [head, mid, end], "box": box, "box_w": box_w, "trough": trough,
		"bot": [box_w - 0.02 - FL.TROUGH_DEPTH, dn_w + 0.01 - FL.TROUGH_DEPTH], "block": blk["id"], "lv": float(blk["lv"])}

## 排水口：塊出水口 O → 沿塊外（北）往主河；途中地面高於溝水 0.15 m 以上的段落改暗渠（石桝＋管），岸坡上石積み落水路
static func _outfall(blk: Dictionary) -> Dictionary:
	var O: Vector2 = blk["O"]
	var w := float(blk["lv"]) + DRAIN_W
	# 往主河方向（北＝−z，稍偏東）逐 0.5 m 走到地面低於河水位
	var dir := Vector2(0.12, -1.0).normalized()
	var pts := PackedVector2Array([O])
	var hump: Array = []
	var p := O
	for k in 120:
		p += dir * 0.5
		var g := ground_h(p)
		if g > w + 0.15:
			hump.append(p)
		pts.append(p)
		if g < RIVER_WATER - 0.05:
			break
	var out := {"block": blk["id"], "O": O, "line": _dp(pts, 0.05), "w": w, "end": p}
	# 跨路（RiversidePath 等）：路兩側各 1.2 m 外設桝，路下管；與土堤隆起段合併成一段暗渠
	var rc := _road_cross(O, p)
	if not rc.is_empty():
		var c: Vector2 = rc["at"]
		var hw := float(rc["road"]["half_w"])
		hump.append(c - dir * (hw + 0.3))
		hump.append(c + dir * (hw + 0.3))
		out["road"] = rc["road"]["name"]
	if hump.size() > 1:
		var s0 := INF
		var s1 := -INF
		for q: Vector2 in hump:
			s0 = minf(s0, (q - O).dot(dir))
			s1 = maxf(s1, (q - O).dot(dir))
		out["culvert"] = [O + dir * (s0 - 1.2), O + dir * (s1 + 1.2)]
		# 下游為主河（水位 −0.80）、管內自由流、出口不上湧 → 暗渠／涵洞（樋管）
		out["hyd"] = "暗渠／涵洞"
	return out

# ───────────────────────────── 幾何小工具 ─────────────────────────────

## 世界多邊形與 u＝常數直線的交集範圍（axis z：z＝u 橫線、回傳 x 範圍；axis x：x＝u 縱線、回傳 z 範圍）
static func _span(poly: PackedVector2Array, axis: String, u: float) -> Vector2:
	var vs: Array = []
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var au := a.y if axis == "z" else a.x
		var bu := b.y if axis == "z" else b.x
		if (au - u) * (bu - u) <= 0.0 and absf(bu - au) > 1e-6:
			var t := (u - au) / (bu - au)
			vs.append(lerpf(a.x, b.x, t) if axis == "z" else lerpf(a.y, b.y, t))
	if vs.size() < 2:
		return Vector2(0, -1)
	vs.sort()
	return Vector2(vs[0], vs[vs.size() - 1])

static func _span_lerp(span: Dictionary, y: float, k: int) -> float:
	var a := floori(y)
	var keys := [a, a + 1]
	var va := 0.0
	var vb := 0.0
	var ha: bool = span.has(a)
	var hb: bool = span.has(a + 1)
	if ha:
		va = span[a][k]
	if hb:
		vb = span[a + 1][k]
	if ha and hb:
		return lerpf(va, vb, y - a)
	if ha:
		return va
	if hb:
		return vb
	# 範圍外：找最近
	var best := INF
	var v := 0.0
	for key: int in span:
		if absf(key - y) < best:
			best = absf(key - y)
			v = span[key][k]
	return v

static func _to_w(pts: PackedVector2Array, world: Callable) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(world.call(p))
	return out

## 兩折線第一個交點（無交點時回傳 a 上離 b 最近的點）
static func _isect(a: PackedVector2Array, b: PackedVector2Array) -> Vector2:
	for i in a.size() - 1:
		for j in b.size() - 1:
			var x: Variant = Geometry2D.segment_intersects_segment(a[i], a[i + 1], b[j], b[j + 1])
			if x != null:
				return x
	var best := INF
	var bp := a[0]
	for i in a.size() - 1:
		for j in b.size():
			var q := Geometry2D.get_closest_point_to_segment(b[j], a[i], a[i + 1])
			if q.distance_to(b[j]) < best:
				best = q.distance_to(b[j])
				bp = q
	return bp

## 折線上 p→q 之間的子折線（依弧長；含兩端點）
static func _sub(poly: PackedVector2Array, p: Vector2, q: Vector2) -> PackedVector2Array:
	var sp := FL.project_s(poly, p)
	var sq := FL.project_s(poly, q)
	var rev := sp > sq
	var s0 := minf(sp, sq)
	var s1 := maxf(sp, sq)
	var mid := PackedVector2Array()
	var acc := 0.0
	for i in poly.size():
		if i > 0:
			acc += poly[i - 1].distance_to(poly[i])
		if acc > s0 + 0.05 and acc < s1 - 0.05:
			mid.append(poly[i])
	if rev:
		mid.reverse()
	var out := PackedVector2Array([p])
	out.append_array(mid)
	out.append(q)
	return FL._dedupe(out, 0.02)

static func _dp(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var best := -1.0
	var bi := 0
	for i in range(1, pts.size() - 1):
		var d := Geometry2D.get_closest_point_to_segment(pts[i], a, b).distance_to(pts[i])
		if d > best:
			best = d
			bi = i
	if best > eps:
		var l := _dp(pts.slice(0, bi + 1), eps)
		var r := _dp(pts.slice(bi), eps)
		l.remove_at(l.size() - 1)
		l.append_array(r)
		return l
	return PackedVector2Array([a, b])

## 田面水／插秧多邊形：只扣本田邊界田埂（全區田多，逐田扣全部田埂太慢）
static func minus_own(fd: Dictionary, bunds: Dictionary, k: float) -> PackedVector2Array:
	var poly: PackedVector2Array = fd["loop"]
	for bn: String in fd["bnames"]:
		if not bunds.has(bn):
			continue
		var cls: Dictionary = FL.BUND_CLASS[bunds[bn]["cls"]]
		for bp: PackedVector2Array in Geometry2D.offset_polyline(bunds[bn]["pts"], float(cls["base_half"]) * k, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
			poly = FL._largest(Geometry2D.clip_polygons(poly, bp), poly)
	return poly

# ───────────────────────────── 碰撞（Irrigation/ZoneWater） ─────────────────────────────

## 構件碰撞：取水落とし樋（岸坡外段）＋支柱、落とし桝、地面木槽、跨路石桝、排水暗渠入口桝。
## 同 r5 _supply_body：樋外擴 CHUTE_CAM_PAD、低構件外擴 LOW_CAM_PAD；岸坡上（P7 範圍）不給碰撞。
static func collision(irr: Node3D, P: Dictionary) -> void:
	var Z: Dictionary = P["zone"]
	var body := StaticBody3D.new()
	body.name = "ZoneWater"
	irr.add_child(body)
	for f: Dictionary in Z["feeders"]:
		var tag: String = f["block"]
		var ch: Array = f["chute"]
		var a: Vector3 = ch[1]
		var b: Vector3 = ch[2]
		# 只給「岸坡外」那段碰撞（地面 ≥ 階面 − 0.12 起算）；岸外不足 1 m ＝樋尾直接擱桝，不給（P7 岸頂帶不占）
		var t0 := 1.0
		for k in 41:
			var tk := k / 40.0
			var qk := a.lerp(b, tk)
			if ground_h(Vector2(qk.x, qk.z)) >= float(f["lv"]) - 0.12:
				t0 = tk
				break
		a = a.lerp(b, t0)
		if Vector2(b.x - a.x, b.z - a.z).length() >= 1.0:
			var d := Vector2(b.x - a.x, b.z - a.z)
			var bs := Basis(Vector3.UP, atan2(d.x, d.y)) * Basis(Vector3.RIGHT, atan2(a.y - b.y, d.length()))
			var sh := CollisionShape3D.new()
			sh.name = "Chute_%s" % tag
			var bx := BoxShape3D.new()
			bx.size = Vector3(FL.CHUTE_W + 2.0 * FL.CHUTE_CAM_PAD, 0.24 + FL.CHUTE_CAM_PAD, d.length())
			sh.shape = bx
			sh.transform = Transform3D(bs, (a + b) * 0.5 + bs * Vector3(0, (0.24 + FL.CHUTE_CAM_PAD) * 0.5, 0))
			body.add_child(sh)
		for i in feeder_posts(f).size():
			var po: Dictionary = feeder_posts(f)[i]
			var h: float = float(po["y_top"]) - float(po["y_bot"])
			var p: Vector2 = po["p"]
			FL._coll_box(body, "Post_%s_%d" % [tag, i], Vector3(p.x, float(po["y_bot"]) + h * 0.5, p.y), Vector3(0.09 + 2.0 * FL.CHUTE_CAM_PAD, h, FL.CHUTE_W + 0.04 + 2.0 * FL.CHUTE_CAM_PAD), 0.0, 0.0)
		var bxp: Vector2 = f["box"]
		var g0 := ground_h(bxp)
		var top := float(f["box_w"]) + 0.07 + FL.LOW_CAM_PAD
		FL._coll_box(body, "DropBox_%s" % tag, Vector3(bxp.x, (g0 + top) * 0.5, bxp.y), Vector3(0.86 + 2.0 * FL.LOW_CAM_PAD, top - g0, 0.86 + 2.0 * FL.LOW_CAM_PAD), 0.0, 0.0)
		var tl: PackedVector2Array = f["trough"]
		var L := FL._length(tl)
		var acc := 0.0
		for i in tl.size() - 1:
			var p0 := tl[i]
			var p1 := tl[i + 1]
			var seg := p0.distance_to(p1)
			var n := maxi(1, ceili(seg / 2.0))
			for j in n:
				var q0 := p0.lerp(p1, float(j) / n)
				var q1 := p0.lerp(p1, float(j + 1) / n)
				var sm := acc + seg * (j + 0.5) / n
				var tt := lerpf(float(f["bot"][0]), float(f["bot"][1]), sm / L) + FL.TROUGH_WALL + FL.LOW_CAM_PAD
				var g := minf(ground_h(q0), ground_h(q1))
				var dd := q1 - q0
				FL._coll_box(body, "Trough_%s_%d_%d" % [tag, i, j], Vector3((q0.x + q1.x) * 0.5, (g + tt) * 0.5, (q0.y + q1.y) * 0.5), Vector3(FL.TROUGH_W + 0.05 + 2.0 * FL.LOW_CAM_PAD, maxf(tt - g, 0.05), q0.distance_to(q1) + 0.02), atan2(dd.x, dd.y), 0.0)
			acc += seg
	for ln: Dictionary in Z["links"]:
		if ln["kind"] != "road":
			continue
		for k in 2:
			var c: Vector2 = ln["A"] if k == 0 else ln["B"]
			var w: float = float(ln["up_w"]) if k == 0 else float(ln["dn_w"]) + 0.01
			var g := ground_h(c)
			var top := maxf(w, g + 0.1) + 0.07 + FL.LOW_CAM_PAD + (0.06 if k == 0 else 0.0)
			FL._coll_box(body, "%s_Box%d" % [ln["name"], k], Vector3(c.x, (g - 0.1 + top) * 0.5, c.y), Vector3(0.86 + 2.0 * FL.LOW_CAM_PAD, top - g + 0.1, 0.86 + 2.0 * FL.LOW_CAM_PAD), 0.0, 0.0)
	for of: Dictionary in Z["outfalls"]:
		if of.has("culvert"):
			var c: Vector2 = of["culvert"][0]
			var g := ground_h(c)
			var top := maxf(float(of["w"]), g) + 0.07 + FL.LOW_CAM_PAD
			FL._coll_box(body, "Outfall_%s_Box" % of["block"], Vector3(c.x, (g - 0.1 + top) * 0.5, c.y), Vector3(0.86 + 2.0 * FL.LOW_CAM_PAD, top - g + 0.1, 0.86 + 2.0 * FL.LOW_CAM_PAD), 0.0, 0.0)
	# 跨渠板：可踩的板面（板頂 lv+0.2925；只給板厚，渠底照舊可通水）——玩家走板過渠、不從板下穿過
	for pk: Dictionary in plank_specs(P):
		var c: Vector2 = pk["c"]
		var d: Vector2 = pk["d"]
		var n := Vector2(-d.y, d.x)
		FL._coll_box(body, "Plank_%s_%s" % [pk["block"], pk["kind"]], Vector3(c.x, float(pk["lv"]) + 0.27, c.y), Vector3(0.44, 0.045, float(pk["span"]) + 0.1), atan2(n.x, n.y), 0.0)
	# 板堰：兩木樁＋疊板一個實心框（玩家不穿過木樁）
	for wr: Dictionary in weir_specs(P):
		var c: Vector2 = wr["c"]
		var d: Vector2 = wr["d"]
		FL._coll_box(body, wr["name"], Vector3(c.x, float(wr["y"]) + 0.2, c.y), Vector3(0.8, 0.42, 0.14), atan2(d.x, d.y), 0.0)

## 跨渠板與板堰的位置規格（可見網格與碰撞共用同一份，避免兩邊各算一次而錯位）
## plank: {c, d（渠向）, lv, span}；weir: {c, d（流向）, y（堰底）}
static func plank_specs(P: Dictionary) -> Array:
	var Z: Dictionary = P["zone"]
	var out: Array = []
	for bid: String in Z["blocks"]:
		var b: Dictionary = Z["blocks"][bid]
		var lv := float(b["lv"])
		var lat: PackedVector2Array = b["lat_line"]
		if b.get("walk_cut", "") != "" and P["bunds"].has(b["walk_cut"]):
			var wc: PackedVector2Array = P["bunds"][b["walk_cut"]]["pts"]
			var pe: Vector2 = wc[wc.size() - 1]
			out.append({"block": bid, "kind": "Lateral", "c": Geometry2D.get_closest_point_to_segment(pe, lat[0], lat[lat.size() - 1]), "d": (lat[lat.size() - 1] - lat[0]).normalized(), "lv": lv, "span": 2.0 * FL.LIP_OFF + 0.6})
		var dr: PackedVector2Array = b["drain"]
		out.append({"block": bid, "kind": "Drain", "c": dr[0].lerp(dr[dr.size() - 1], 0.3), "d": (dr[dr.size() - 1] - dr[0]).normalized(), "lv": lv - 0.1, "span": 1.9})
	return out

static func weir_specs(P: Dictionary) -> Array:
	var Z: Dictionary = P["zone"]
	var out: Array = []
	for bid: String in Z["blocks"]:
		var b: Dictionary = Z["blocks"][bid]
		var lat: PackedVector2Array = b["lat_line"]
		out.append({"name": "CheckWeir_%s" % bid, "c": b["weir"], "d": (lat[1] - lat[0]).normalized(), "y": float(b["lv"])})
		out.append({"name": "EndWeir_%s" % bid, "c": b["lat_end"], "d": (lat[lat.size() - 1] - lat[lat.size() - 2]).normalized(), "y": float(b["lv"])})
	for ln: Dictionary in Z["links"]:
		if ln["kind"] == "drop":
			var path: PackedVector2Array = ln["path"]
			var mid := path[0].lerp(path[path.size() - 1], 0.5)
			out.append({"name": "DropWeir_%s" % ln["name"], "c": mid, "d": (path[path.size() - 1] - path[0]).normalized(), "y": ground_h(mid) - 0.02})
	return out

## 落とし樋第 2 段支柱（岸坡外才立；與 r5 CHUTE_POST_T 同位置比例）
static func feeder_posts(f: Dictionary) -> Array:
	var out: Array = []
	var a: Vector3 = f["chute"][1]
	var b: Vector3 = f["chute"][2]
	for t: float in FL.CHUTE_POST_T:
		var q := a.lerp(b, t)
		if ground_h(Vector2(q.x, q.z)) < float(f["lv"]) - 0.3:
			continue
		# 樋尾擱在落とし桝上＝桝即支點；桝旁 1.6 m 內的柱會落在岸頂（P7 石積み笠石帶），不立
		if Vector2(q.x, q.z).distance_to(f["box"]) < 1.6:
			continue
		out.append({"p": Vector2(q.x, q.z), "y_top": q.y, "y_bot": ground_h(Vector2(q.x, q.z)) - 0.35})
	return out

# ───────────────────────────── 可見網格 ─────────────────────────────

static func art(root: Node3D, P: Dictionary, layout: Dictionary) -> void:
	var Z: Dictionary = P["zone"]
	var zroot := Visual._group(root, "ZoneWorks")
	var irr := Visual._group(zroot, "ZoneIrrigation")
	var details := Visual._group(zroot, "ZoneDetails")
	var wood := Visual._wood_mat()
	var stone := Visual._stone_mat()
	var rng := RandomNumberGenerator.new()
	rng.seed = 60601
	var chmat := Visual._flow_mat(0.9, Color(0.30, 0.29, 0.21), 0.55)
	var dmat := Visual._flow_mat(0.4, Color(0.30, 0.27, 0.19), 0.3)
	dmat.set_shader_parameter("rough_base", 0.32)
	dmat.set_shader_parameter("algae", 0.5)
	var fmat := Visual._flow_mat(0.8, Color(0.36, 0.36, 0.3), 0.7)
	var deep := Visual._flow_mat(0.6, Color(0.16, 0.16, 0.13), 0.12)
	var gm := Visual._ground_mat()
	for bid: String in Z["blocks"]:
		var b: Dictionary = Z["blocks"][bid]
		var lv := float(b["lv"])
		var g := Visual._group(irr, "Block_%s" % bid)
		g.set_meta("terrace_y", lv)
		# 支渠（上游／下游兩段水位，中段板堰）
		var lat: PackedVector2Array = b["lat_line"]
		var weir: Vector2 = b["weir"]
		var sw := FL.project_s(lat, weir)
		Visual._ribbon(g, "LateralBed", lat, FL.LIP_OFF + 0.05, func(p: Vector2, u: float) -> float: return lv + 0.012 + 0.006 * Visual._n(p * 3.0 + Vector2(u, 0)), gm, Color(0.1, 0.25, 1.0, 0.0), Vector2(1.0, 0.0), -1e9, 1e9)
		Visual._ribbon(g, "LateralWater", lat, FL.CH_WATER_HALF, func(p: Vector2, u: float) -> float: return lv + (MAIN_WATER if FL.project_s(lat, p) < sw else FL.CH_WATER_N), chmat, Color(), Vector2(), -1e9, 1e9, true)
		_board_weir(Visual._group(g, "CheckWeir"), weir, (lat[1] - lat[0]).normalized(), lv, wood, rng)
		var le: Vector2 = b["lat_end"]
		_board_weir(Visual._group(g, "EndWeir"), le, (lat[lat.size() - 1] - lat[lat.size() - 2]).normalized(), lv, wood, rng)
		if b.has("main"):
			var ml: PackedVector2Array = b["main"]
			Visual._ribbon(g, "MainBed", ml, FL.LIP_OFF + 0.05, func(p: Vector2, u: float) -> float: return lv + 0.012 + 0.006 * Visual._n(p * 3.0), gm, Color(0.1, 0.25, 1.0, 0.0), Vector2(1.0, 0.0), -1e9, 1e9)
			Visual._ribbon(g, "MainWater", ml, FL.CH_WATER_HALF, func(p: Vector2, u: float) -> float: return lv + MAIN_WATER, chmat, Color(), Vector2(), -1e9, 1e9, true)
		var dr: PackedVector2Array = b["drain"]
		Visual._ribbon(g, "DrainBed", dr, FL.DRAIN_HALF + 0.05, func(p: Vector2, u: float) -> float: return lv + 0.008 + 0.005 * Visual._n(p * 3.0), gm, Color(0.05, 0.2, 1.0, 0.0), Vector2(1.0, 0.0), -1e9, 1e9)
		Visual._ribbon(g, "DrainWater", dr, FL.DRAIN_HALF, func(p: Vector2, u: float) -> float: return lv + DRAIN_W, dmat, Color(), Vector2(), -1e9, 1e9, true)
		# 跨渠板：畦道與支渠交會處、支渠尾（跨落水溝）——位置與碰撞共用 plank_specs()
		for pk: Dictionary in plank_specs(P):
			if pk["block"] == bid:
				_planks(Visual._group(g, "PlankCrossing_%s" % pk["kind"]), pk["c"], pk["d"], float(pk["lv"]), float(pk["span"]), wood, rng)
	# 每田水口／落水口
	for bn: String in P["bunds"]:
		var d: Dictionary = P["bunds"][bn]
		if not d.has("zone"):
			continue
		for no: Dictionary in d["notches"]:
			if no["kind"] == "tread":
				continue
			var at: Array = FL.at_s(d["pts"], float(no["s"]))
			var c: Vector2 = at[0]
			var tan: Vector2 = at[1]
			var y := TLib_level(layout, c)
			var gg := Visual._group(details, "%s_%s" % ["Inlet" if no["kind"] == "inlet" else "Outlet", no["field"]])
			var yaw := atan2(tan.x, tan.y)
			if no["kind"] == "outlet":
				Visual._box(gg, "WeirBoard", Vector3(c.x, y + FL.WATER_LIFT * 0.5 + 0.01, c.y), Vector3(0.04, FL.WATER_LIFT + 0.05, float(no["w"]) + 0.12), wood, yaw + PI * 0.5 + rng.randf_range(-0.08, 0.08))
				for k in 2:
					var sd := -1.0 if k == 0 else 1.0
					Visual._rock_node(gg, "Stone_%d" % k, Vector3(c.x + tan.x * sd * 0.34, y + 0.03, c.y + tan.y * sd * 0.34), rng.randf_range(0.07, 0.11), rng, stone)
			else:
				var od: Vector2 = no["dir"]
				var spill := PackedVector2Array([c - od * 0.45, c + od * 0.55])
				var chw: float = no["ch"]
				Visual._ribbon(gg, "Spill", spill, 0.2, func(p: Vector2, u: float) -> float:
					var tt := clampf((p - spill[0]).dot(od), 0.0, 1.0)
					return y + lerpf(chw, FL.WATER_LIFT, tt) + 0.004, Visual._flow_mat(1.4, Color(0.34, 0.32, 0.24), 0.5), Color(), Vector2(), -1e9, 1e9, true)
				for k in 3:
					var sd := -1.0 if k % 2 == 0 else 1.0
					Visual._rock_node(gg, "Stone_%d" % k, Vector3(c.x + tan.x * sd * rng.randf_range(0.3, 0.38) + od.x * (k - 1) * 0.2, y + 0.04, c.y + tan.y * sd * 0.34 + od.y * (k - 1) * 0.2), rng.randf_range(0.07, 0.12), rng, stone)
	# 休耕田（埂圍、無水、長草）／休耕草地／旱田
	for fa: Dictionary in Z["fallow"]:
		var poly := minus_own(fa, P["bunds"], 0.55)
		_meadow(details, "Fallow_%s" % fa["name"], poly, float(fa["lv"]), 5.0, rng)
	for m: Dictionary in Z["meadow"]:
		_meadow(details, "Meadow_%s" % m["name"], m["poly"], float(m["lv"]), 2.5, rng)
	for dfd: Dictionary in Z["dry"]:
		_dry_art(details, dfd, rng)
	# 逐階水路
	var works := Visual._group(irr, "Links")
	for ln: Dictionary in Z["links"]:
		var g := Visual._group(works, ln["name"])
		g.set_meta("hydraulics", ln["hyd"])
		g.set_meta("up_water", ln["up_w"])
		g.set_meta("down_water", ln["dn_w"])
		if ln["kind"] == "drop":
			var path: PackedVector2Array = ln["path"]
			_ground_ditch(g, "Ditch", path, float(ln["up_w"]), float(ln["dn_w"]), gm, fmat)
			var mid := path[0].lerp(path[path.size() - 1], 0.5)
			_board_weir(Visual._group(g, "DropWeir"), mid, (path[path.size() - 1] - path[0]).normalized(), ground_h(mid) - 0.02, wood, rng)
			for k in 4:
				var a := k * PI * 0.5 + 0.4
				Visual._rock_node(g, "Stone_%d" % k, Vector3(mid.x + cos(a) * 0.62, ground_h(mid) + 0.02, mid.y + sin(a) * 0.62), rng.randf_range(0.09, 0.15), rng, stone)
		else:
			g.set_meta("road", ln["road"])
			g.set_meta("road_y", ln["road_y"])
			g.set_meta("pipe_top", ln["pipe_top"])
			_ground_ditch(g, "DitchUp", ln["path_a"], float(ln["up_w"]), float(ln["up_w"]), gm, fmat)
			_ground_ditch(g, "DitchDown", ln["path_b"], float(ln["dn_w"]), float(ln["dn_w"]), gm, fmat)
			var siphon: bool = ln["hyd"] == "伏越し"
			for k in 2:
				var c: Vector2 = ln["A"] if k == 0 else ln["B"]
				var w: float = float(ln["up_w"]) if k == 0 else float(ln["dn_w"]) + 0.01
				var gy := ground_h(c)
				var ww := maxf(w, gy + 0.04)
				var other: Vector2 = ln["B"] if k == 0 else ln["A"]
				var face := (c - other).normalized()
				var open_k := [0] if absf(face.x) > absf(face.y) and face.x > 0 else ([2] if absf(face.x) > absf(face.y) else ([1] if face.y > 0 else [3]))
				Visual._stone_box(Visual._group(g, "Box_%d" % k), c, gy - 0.04, ww + 0.07, ww, stone, deep if siphon else fmat, rng, k == 0, open_k)
	# 取水（水車 1／3）
	var feeds := Visual._group(irr, "Feeders")
	for f: Dictionary in Z["feeders"]:
		_feeder_art(Visual._group(feeds, "Feeder_%s" % f["block"]), f, wood, stone, fmat, rng)
	# 排水口（接主河）
	var outs := Visual._group(irr, "Outfalls")
	for of: Dictionary in Z["outfalls"]:
		var g := Visual._group(outs, "Outfall_%s" % of["block"])
		g.set_meta("hydraulics", "落水 → 主河（水位 %.2f → %.2f）" % [of["w"], RIVER_WATER])
		var line: PackedVector2Array = of["line"]
		if of.has("culvert"):
			# 暗渠段（土堤／路下）不畫明渠：上游明渠到入口桝、出口桝以下明渠落主河
			var sa := FL.project_s(line, of["culvert"][0])
			var sb := FL.project_s(line, of["culvert"][1])
			_ground_ditch(g, "Ditch", _cut(line, 0.0, sa), float(of["w"]), float(of["w"]) - 0.01, gm, dmat)
			_ground_ditch(g, "DitchLow", _cut(line, sb, FL._length(line)), float(of["w"]) - 0.03, RIVER_WATER, gm, dmat)
		else:
			_ground_ditch(g, "Ditch", line, float(of["w"]), RIVER_WATER, gm, dmat)
		# 岸坡段：兩側石積み
		var L := FL._length(line)
		var s := 0.0
		var k := 0
		var cs0 := FL.project_s(line, of["culvert"][0]) if of.has("culvert") else INF
		var cs1 := FL.project_s(line, of["culvert"][1]) if of.has("culvert") else -INF
		while s < L:
			var at: Array = FL.at_s(line, s)
			var c: Vector2 = at[0]
			var tan: Vector2 = at[1]
			var gy := ground_h(c)
			if gy < float(of["w"]) - 0.12 and (s < cs0 or s > cs1):
				for sd in [-1.0, 1.0]:
					var q: Vector2 = c + Vector2(-tan.y, tan.x) * sd * 0.62
					Visual._rock_node(g, "BankStone_%d_%d" % [k, int(sd)], Vector3(q.x, ground_h(q) + 0.04, q.y), rng.randf_range(0.12, 0.2), rng, stone)
				k += 1
			s += 0.8
		if of.has("culvert"):
			g.set_meta("culvert", "暗渠／涵洞（土堤下自由流）")
			for j in 2:
				var c: Vector2 = of["culvert"][j]
				var gy := ground_h(c)
				Visual._stone_box(Visual._group(g, "CulvertBox_%d" % j), c, gy - 0.04, maxf(float(of["w"]), gy) + 0.07, maxf(float(of["w"]) - 0.02, gy + 0.03), stone, fmat, rng, j == 0, [3])
	# 少量農具
	_props(details, Z, wood, rng)
	# 成本：每個構件（水口、落水口、堰、跨渠板、桝、取水、排水口、農具組）把自身零件依材質合併成少數網格
	# （仍是一個構件一個可選節點），小構件 70 m 外、水路 180 m 外不繪；小零件不投影
	for gg: Node in details.get_children():
		if gg.name.begins_with("Inlet_") or gg.name.begins_with("Outlet_"):
			_merge(gg as Node3D, 70.0, false)
		elif gg.name == "FarmTools":
			for t: Node in gg.get_children():
				_merge(t as Node3D, 70.0, false)
	for bg: Node in irr.get_children():
		if bg.name.begins_with("Block_"):
			for sub: Node in bg.get_children():
				if sub.get_child_count() > 0:
					_merge(sub as Node3D, 70.0, false)
				else:
					_range(sub as GeometryInstance3D, 180.0, true)
		elif bg.name in ["Links", "Feeders", "Outfalls"]:
			for sub: Node in bg.get_children():
				_merge(sub as Node3D, 180.0, true)

## 構件內所有 MeshInstance3D 依材質合併（座標轉到構件本地）；水面帶（透明）與實體分開，實體可投影
static func _merge(g: Node3D, vr_end: float, shadow: bool) -> void:
	var by_mat := {}
	var olds: Array = []
	for n: Node in g.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var mat: Material = mi.material_override
		if mi.mesh == null:
			continue
		if not by_mat.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_mat[mat] = st
		var xf := g.global_transform.affine_inverse() * mi.global_transform if g.is_inside_tree() else _rel_xf(g, mi)
		for s in mi.mesh.get_surface_count():
			(by_mat[mat] as SurfaceTool).append_from(mi.mesh, s, xf)
		olds.append(mi)
	if olds.size() <= 1:
		for mi: MeshInstance3D in olds:
			_range(mi, vr_end, shadow)
		return
	for mi: MeshInstance3D in olds:
		mi.get_parent().remove_child(mi)
		mi.free()
	for sub: Node in g.find_children("*", "Node3D", true, false):
		if sub.get_child_count() == 0 and not (sub is MeshInstance3D):
			sub.get_parent().remove_child(sub)
			sub.free()
	var k := 0
	for mat: Material in by_mat:
		var node := MeshInstance3D.new()
		node.name = "Merged_%d" % k
		k += 1
		node.mesh = (by_mat[mat] as SurfaceTool).commit()
		node.material_override = mat
		var water := mat is ShaderMaterial and (mat as ShaderMaterial).shader == Visual.WATER_SH
		_range(node, vr_end, shadow and not water and not (mat is ShaderMaterial))
		g.add_child(node)

static func _rel_xf(g: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != g and cur != null:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

static func _range(n: GeometryInstance3D, vr_end: float, shadow: bool) -> void:
	if n == null:
		return
	n.visibility_range_end = vr_end
	n.visibility_range_end_margin = vr_end * 0.1
	n.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not shadow:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## 折線 s0–s1 段（弧長）
static func _cut(line: PackedVector2Array, s0: float, s1: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if s1 - s0 < 0.2:
		return out
	var n := maxi(2, ceili((s1 - s0) / 0.5) + 1)
	for i in n:
		out.append(FL.at_s(line, lerpf(s0, s1, float(i) / (n - 1)))[0])
	return out

static func TLib_level(layout: Dictionary, p: Vector2) -> float:
	return preload("res://tools/village_v2_terrain_lib.gd").farm_level(layout, p)

## 地面水路（跨階／跨路兩端／排水口）：渠底貼地、水面＝沿線線性水位但不低於地面 + 3 cm（岸坡上成落水）
static func _ground_ditch(g: Node3D, name: String, line: PackedVector2Array, w0: float, w1: float, gm: Material, wm: Material) -> void:
	if line.size() < 2 or FL._length(line) < 0.3:
		return
	var L := FL._length(line)
	Visual._ribbon(g, name + "Bed", line, 0.6, func(p: Vector2, u: float) -> float: return ground_h(p) + 0.01 + 0.004 * absf(u), gm, Color(0.1, 0.3, 1.0, 0.0), Vector2(1.0, 0.0), -1e9, 1e9)
	Visual._ribbon(g, name + "Water", line, 0.34, func(p: Vector2, u: float) -> float:
		var t := FL.project_s(line, p) / L
		return maxf(lerpf(w0, w1, t), ground_h(p) + 0.03), wm, Color(), Vector2(), -1e9, 1e9, true)

## 板堰：兩木樁＋三片疊板（小堰／止め堰）
static func _board_weir(g: Node3D, c: Vector2, d: Vector2, y: float, wood: Material, rng: RandomNumberGenerator) -> void:
	var yaw := atan2(d.x, d.y)
	var n := Vector2(-d.y, d.x)
	for sd in [-1.0, 1.0]:
		Visual._box(g, "Post_%d" % int(sd), Vector3(c.x + n.x * sd * 0.34, y + 0.2, c.y + n.y * sd * 0.34), Vector3(0.09, 0.42, 0.09), wood, rng.randf_range(-0.05, 0.05))
	for k in 3:
		Visual._box(g, "Board_%d" % k, Vector3(c.x, y + 0.018 + k * 0.024, c.y), Vector3(0.62, 0.024, 0.035), wood, yaw + PI * 0.5 + rng.randf_range(-0.03, 0.03))

## 跨渠板：沿 d 方向橫跨（span＝板長）
static func _planks(g: Node3D, c: Vector2, d: Vector2, lv: float, span: float, wood: Material, rng: RandomNumberGenerator) -> void:
	var n := Vector2(-d.y, d.x)
	for k in 2:
		var q := c + d * (k - 0.5) * 0.21
		Visual._box(g, "Plank_%d" % k, Vector3(q.x, lv + 0.27, q.y), Vector3(0.19, 0.045, span + rng.randf_range(-0.1, 0.1)), wood, atan2(n.x, n.y) + rng.randf_range(-0.05, 0.05))

static func _feeder_art(g: Node3D, f: Dictionary, wood: Material, stone: Material, fmat: Material, rng: RandomNumberGenerator) -> void:
	var ch: Array = f["chute"]
	for i in ch.size() - 1:
		Visual._trough_seg(Visual._group(g, "Chute_%d" % i), ch[i], ch[i + 1], FL.CHUTE_W, 0.2, 0.08, wood, fmat)
	var jp: Vector3 = ch[1]
	var jd := Vector2(ch[2].x - ch[0].x, ch[2].z - ch[0].z).normalized()
	Visual._box(g, "ChuteJoint", Vector3(jp.x, jp.y + 0.06, jp.z), Vector3(FL.CHUTE_W + 0.08, 0.24, 0.5), wood, atan2(jd.x, jd.y))
	var h0: Vector3 = ch[0]
	Visual._box(g, "HeadBearer", Vector3(h0.x - jd.x * 0.45, h0.y - 0.07, h0.z - jd.y * 0.45), Vector3(0.3, 0.14, 1.2), wood, atan2(jd.x, jd.y) + PI * 0.5)
	var a1: Vector3 = ch[1]
	var b1: Vector3 = ch[2]
	var dir := Vector2(b1.x - a1.x, b1.z - a1.z).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var yaw := atan2(dir.x, dir.y)
	var k := 0
	for po: Dictionary in feeder_posts(f):
		var p: Vector2 = po["p"]
		var yt: float = po["y_top"]
		var yb: float = po["y_bot"]
		var pg := Visual._group(g, "Support_%02d" % k)
		k += 1
		for sd in [-1.0, 1.0]:
			var q: Vector2 = p + perp * sd * (FL.CHUTE_W * 0.5 + 0.02)
			Visual._box(pg, "Post_%d" % int(sd), Vector3(q.x, (yb + yt) * 0.5, q.y), Vector3(0.09, yt - yb, 0.09), wood, yaw)
		Visual._box(pg, "Cap", Vector3(p.x, yt - 0.075, p.y), Vector3(FL.CHUTE_W + 0.2, 0.07, 0.1), wood, yaw)
	var bx: Vector2 = f["box"]
	var gy := ground_h(bx)
	Visual._stone_box(Visual._group(g, "DropBox"), bx, gy, float(f["box_w"]) + 0.07, float(f["box_w"]), stone, fmat, rng, false, [0])
	# 地面木槽（枕木上；半埋段不放枕木）
	# closure：槽內水面用較暗、較濁的水色——1.7 m 掠射時原 fmat（0.36 灰、clarity 0.7）反射天空成一條淺色長帶，
	# 在草地上比水車還搶眼；木槽幾何、高程、路線不變
	var tmat := Visual._flow_mat(0.8, Color(0.21, 0.20, 0.16), 0.4)
	var tl: PackedVector2Array = f["trough"]
	var L := FL._length(tl)
	var acc := 0.0
	var tg := Visual._group(g, "GroundTrough")
	for i in tl.size() - 1:
		var p0 := tl[i]
		var p1 := tl[i + 1]
		var seg := p0.distance_to(p1)
		var ya := lerpf(float(f["bot"][0]), float(f["bot"][1]), acc / L)
		var yb := lerpf(float(f["bot"][0]), float(f["bot"][1]), (acc + seg) / L)
		Visual._trough_seg(Visual._group(tg, "Seg_%d" % i), Vector3(p0.x, ya, p0.y), Vector3(p1.x, yb, p1.y), FL.TROUGH_W, FL.TROUGH_WALL, FL.TROUGH_DEPTH, wood, tmat)
		var n := maxi(1, floori(seg / 1.5))
		for j in n:
			var t := (j + 0.5) / n
			var c := p0.lerp(p1, t)
			var d := (p1 - p0).normalized()
			var gh := ground_h(c)
			var top := lerpf(ya, yb, t) - 0.04
			if top - gh < 0.03:
				continue
			Visual._box(tg, "Sleeper_%d_%d" % [i, j], Vector3(c.x, (gh - 0.03 + top) * 0.5, c.y), Vector3(FL.TROUGH_W + 0.22, top - gh + 0.03, 0.12), wood, atan2(d.x, d.y) + rng.randf_range(-0.06, 0.06))
		acc += seg

## 草地（休耕）：貼地網格＋密草 MultiMesh
static func _meadow(parent: Node3D, name: String, poly: PackedVector2Array, lv: float, density: float, rng: RandomNumberGenerator) -> void:
	if poly.size() < 3:
		return
	var g := Visual._group(parent, name)
	var tri := Visual._tri_poly(poly, 1.0)
	var pts: PackedVector2Array = tri[0]
	var ys := PackedFloat32Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	for p in pts:
		ys.append(lv + 0.01 + 0.012 * Visual._n(p * 0.7))
		cols.append(Color(0.1 * Visual._n(p * 0.4), 0.0, 0.12 * Visual._n(p * 0.9 + Vector2(3, 0)), 0.0))
		uv.append(Vector2(0.15 * Visual._n(p * 0.3), 0.0))
		uv2.append(Vector2(0.1, 0.0))
	Visual._mesh(g, "Ground", Visual._build_mesh(pts, tri[1], ys, cols, uv, uv2, true), Visual._ground_mat())
	# 草叢交給全農田空間分塊（Visual.grass_add → _emit_weeds），不再每塊草地各自一組 MultiMesh
	var bb := FL._bbox(poly)
	var n := int(absf(FL._area(poly)) * density)
	for i in n:
		var p := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y))
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		var kind := 0 if rng.randf() < 0.5 else (1 if rng.randf() < 0.85 else 2)
		var hgt := rng.randf_range(0.12, 0.32) if kind != 2 else rng.randf_range(0.35, 0.7)
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(hgt * rng.randf_range(0.8, 1.3), hgt, hgt * rng.randf_range(0.8, 1.3)))
		var col := Color(0.34, 0.45, 0.18).lerp(Color(0.55, 0.52, 0.28), rng.randf() * 0.6 + 0.3 * Visual._n(p * 0.2))
		Visual.grass_add(p, kind, Transform3D(basis, Vector3(p.x, lv + 0.01, p.y)), (col * 1.1).clamp(Color(0, 0, 0, 1), Color(1, 1, 1, 1)))

## 旱田（畑）：畝（高 0.1 m、間 0.9 m）＋沿畝作物 MultiMesh
static func _dry_art(parent: Node3D, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var g := Visual._group(parent, "DryField_%s" % d["name"])
	var poly: PackedVector2Array = d["poly"]
	var lv: float = d["lv"]
	var ang := deg_to_rad(float(d["dir"]))
	var along := Vector2(sin(ang), cos(ang))
	var across := Vector2(-along.y, along.x)
	var tri := Visual._tri_poly(poly, 0.3)
	var pts: PackedVector2Array = tri[0]
	var ys := PackedFloat32Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var edge := Visual._edge_dist(pts, poly)
	for i in pts.size():
		var p := pts[i]
		var ph := p.dot(across) / 0.9 * TAU
		var r := (0.5 + 0.5 * cos(ph)) * smoothstep(0.2, 1.2, edge[i])
		ys.append(lv + 0.012 + 0.1 * r + 0.006 * Visual._n(p * 2.0))
		cols.append(Color(0.35 + 0.3 * r, 0.05, 0.55 - 0.25 * r, 0.0))
		uv.append(Vector2(0.0, 0.6))
		uv2.append(Vector2(0.25 * (1.0 - r), 0.0))
	Visual._mesh(g, "Ridges", Visual._build_mesh(pts, tri[1], ys, cols, uv, uv2, true), Visual._ground_mat())
	var crop: String = d["crop"]
	var kind := 2 if crop == "wheat" else 0
	var meshes := Visual._tuft_meshes(kind)
	var xs: Array = []
	var cs: Array = []
	var bb := FL._bbox(poly)
	var o := bb.position
	var diag := bb.size.length()
	var r0 := -ceili(diag / 0.9)
	for ri in range(r0, -r0 + 1):
		var off := ri * 0.9
		var s := -diag
		while s < diag:
			var p := bb.get_center() + across * off + along * s
			s += 0.28 if crop != "wheat" else 0.12
			if not Geometry2D.is_point_in_polygon(p, poly) or Visual._dist_poly(p, poly) < 0.5:
				continue
			if rng.randf() < 0.06:
				continue
			var hgt := rng.randf_range(0.14, 0.24) if crop != "wheat" else rng.randf_range(0.4, 0.62)
			var wide := 1.6 if crop == "leafy" else (1.0 if crop == "bean" else 0.5)
			var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(hgt * wide, hgt, hgt * wide))
			var col := Color(0.30, 0.46, 0.17) if crop == "leafy" else (Color(0.62, 0.60, 0.30) if crop == "wheat" else Color(0.33, 0.44, 0.19))
			xs.append(Transform3D(basis, Vector3(p.x, lv + 0.1, p.y)))
			cs.append((col.lerp(Color(0.5, 0.5, 0.25), rng.randf() * 0.25) * 1.1).clamp(Color(0, 0, 0, 1), Color(1, 1, 1, 1)))
	if not xs.is_empty():
		Visual._mm_node(g, "Crop_near", meshes[0], xs, cs, Visual._plant_mat(), 0.0, 0.0, Visual.WEED_NEAR, 5.0)
		Visual._mm_node(g, "Crop_far", meshes[1], xs, cs, Visual._plant_mat(), Visual.WEED_NEAR, 5.0, Visual.WEED_RANGE, 10.0)
	g.set_meta("crop", crop)

## 少量農具：水桶、鍬、苗箱、稻草束——放在各塊進水口旁的埂邊（每兩塊一組）
static func _props(parent: Node3D, Z: Dictionary, wood: Material, rng: RandomNumberGenerator) -> void:
	var g := Visual._group(parent, "FarmTools")
	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.62, 0.53, 0.30)
	straw.roughness = 0.9
	var seed := StandardMaterial3D.new()
	seed.albedo_color = Color(0.36, 0.50, 0.20)
	seed.roughness = 0.8
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.32, 0.31, 0.30)
	metal.metallic = 0.6
	metal.roughness = 0.5
	var i := 0
	for bid: String in Z["blocks"]:
		i += 1
		if i % 2 == 0:
			continue
		var b: Dictionary = Z["blocks"][bid]
		var lv := float(b["lv"])
		var I: Vector2 = b["I"]
		var lat: PackedVector2Array = b["lat_line"]
		var d := (lat[lat.size() - 1] - lat[0]).normalized()
		var n := Vector2(-d.y, d.x)
		# closure：每組農具位置／組成各異（原為同一組件、同一偏移，每隔一塊重複）
		var c := I + d * rng.randf_range(1.4, 4.5) + n * rng.randf_range(1.3, 2.2)
		var has_bucket := rng.randf() < 0.75
		var has_hoe := rng.randf() < 0.6
		var trays := rng.randi_range(0, 2)
		var has_straw := rng.randf() < 0.7 or not (has_bucket or has_hoe or trays > 0)
		var gy := ground_h(c)     # closure：農具貼實際地面（原用階面 lv，渠唇／路肩處會浮或埋）
		lv = gy
		var pg := Visual._group(g, "Tools_%s" % bid)
		var bucket := MeshInstance3D.new()
		bucket.name = "Bucket"
		var cm := CylinderMesh.new()
		cm.top_radius = 0.17
		cm.bottom_radius = 0.14
		cm.height = 0.26
		cm.radial_segments = 10
		bucket.mesh = cm
		bucket.material_override = wood
		bucket.position = Vector3(c.x, lv + 0.13, c.y)
		if has_bucket:
			pg.add_child(bucket)
		else:
			bucket.free()
		# 鍬：平放地上（原斜靠無支點、柄頂懸空 0.6 m 且鍬頭落在柄頂正下方）；鍬頭接柄端
		if has_hoe:
			var hd := d.rotated(rng.randf_range(-0.6, 0.6))
			var hc := c + n * 0.6
			var hy := ground_h(hc)
			Visual._box(pg, "HoeHandle", Vector3(hc.x, hy + 0.018, hc.y), Vector3(0.035, 1.15, 0.035), wood, atan2(hd.x, hd.y), PI * 0.5)
			var bc := hc + hd * 0.6
			Visual._box(pg, "HoeBlade", Vector3(bc.x, ground_h(bc) + 0.012, bc.y), Vector3(0.22, 0.02, 0.18), metal, atan2(hd.x, hd.y))
		# 苗箱 2 段
		for k in trays:
			Visual._box(pg, "SeedTray_%d" % k, Vector3(c.x - d.x * 0.7, lv + 0.04 + k * 0.07, c.y - d.y * 0.7), Vector3(0.58, 0.06, 0.28), wood, atan2(d.x, d.y) + rng.randf_range(-0.2, 0.2))
			Visual._box(pg, "Seedlings_%d" % k, Vector3(c.x - d.x * 0.7, lv + 0.085 + k * 0.07, c.y - d.y * 0.7), Vector3(0.54, 0.04, 0.24), seed, atan2(d.x, d.y))
		# 稻草束
		var sb := MeshInstance3D.new()
		sb.name = "StrawBundle"
		var sm := CylinderMesh.new()
		sm.top_radius = 0.09
		sm.bottom_radius = 0.13
		sm.height = 0.55
		sm.radial_segments = 8
		sb.mesh = sm
		sb.material_override = straw
		sb.position = Vector3(c.x + d.x * 0.9, lv + 0.12, c.y + d.y * 0.9)
		sb.rotation = Vector3(PI * 0.5, rng.randf() * TAU, 0.0)
		if has_straw:
			pg.add_child(sb)
		else:
			sb.free()
