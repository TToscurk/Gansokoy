extends RefCounted

## Human Village density dressing. The caller owns and seeds both RNG streams;
## this module only consumes the supplied instances in their established order.

var _lib
var _root: Node3D
var _mods: Dictionary
var _dump: Array
var _ghost: Array
var _ghost_run2: int
var _dbatch: Dictionary
var _ddump: Array
var _drng: RandomNumberGenerator
var _prng: RandomNumberGenerator
var _audit: Array
var _half: float
var _bank_path: float
var _main_ew_z: float
var _sakura_sites: Array
var _green_sites: Array
var _out_dir: String
var _commerce_fn: Callable
var _is_pilot_fn: Callable
var _is_house_kind_fn: Callable
var _obb_of_fn: Callable
var _pt_reserved_fn: Callable
var _pt_on_road_core_fn: Callable
var _nearest_river_pt_fn: Callable
var _height_at_fn: Callable
var _sakura_mesh_fn: Callable
var _village_tree_mesh_fn: Callable
var _dxf_mute := false


func _setup(context: Dictionary) -> void:
	_lib = context.lib
	_root = context.root
	_mods = context.mods
	_dump = context.dump
	_ghost = context.ghost
	_ghost_run2 = context.ghost_run2
	_dbatch = context.dbatch
	_ddump = context.ddump
	_drng = context.density_rng
	_prng = context.pilot_rng
	_audit = context.audit
	_half = context.half
	_bank_path = context.bank_path
	_main_ew_z = context.main_ew_z
	_sakura_sites = context.sakura_sites
	_green_sites = context.green_sites
	_out_dir = context.out_dir
	_commerce_fn = context.commerce
	_is_pilot_fn = context.is_pilot
	_is_house_kind_fn = context.is_house_kind
	_obb_of_fn = context.obb_of
	_pt_reserved_fn = context.pt_reserved
	_pt_on_road_core_fn = context.pt_on_road_core
	_nearest_river_pt_fn = context.nearest_river_pt
	_height_at_fn = context.height_at
	_sakura_mesh_fn = context.sakura_mesh
	_village_tree_mesh_fn = context.village_tree_mesh


func _commerce(p: Vector2) -> float:
	return float(_commerce_fn.call(p))


func _is_pilot(entry: Array) -> bool:
	return bool(_is_pilot_fn.call(entry))


func _is_house_kind(kind: String) -> bool:
	return bool(_is_house_kind_fn.call(kind))


func _obb_of(entry: Array) -> Array:
	return _obb_of_fn.call(entry)


func _pt_reserved(p: Vector2, margin: float) -> bool:
	return bool(_pt_reserved_fn.call(p, margin))


func _pt_on_road_core(p: Vector2, spill: float) -> bool:
	return bool(_pt_on_road_core_fn.call(p, spill))


func _nearest_river_pt(p: Vector2) -> Vector2:
	return _nearest_river_pt_fn.call(p)


func height_at(x: float, z: float) -> float:
	return float(_height_at_fn.call(x, z))


func _sakura_mesh(path: String) -> Mesh:
	return _sakura_mesh_fn.call(path)


func _village_tree_mesh(path: String) -> Mesh:
	return _village_tree_mesh_fn.call(path)


func _dxf(kind: String, p: Vector2, y: float, yaw: float, s: float = 1.0) -> void:
	if _dxf_mute:
		return
	var b := Basis(Vector3.UP, yaw)
	if s != 1.0:
		b = b * Basis.from_scale(Vector3(s, s, s))
	if not _dbatch.has(kind):
		_dbatch[kind] = []
	_dbatch[kind].append(Transform3D(b, Vector3(p.x, y, p.y)))
	_ddump.append([kind, p.x, y, p.y, yaw])


func _identity_role(kind: String, p: Vector2) -> String:
	## Stable business identity from the existing household and lot coordinate.
	## This consumes no shared RNG, so vegetation and unrelated dressing do not drift.
	var trade: float = _commerce(p)
	if trade < 0.34:
		return ""
	var hx: int = int(round(p.x * 10.0)) * 73856093
	var hz: int = int(round(p.y * 10.0)) * 19349663
	var h: int = absi(hx ^ hz)
	if kind == "machiya_w_a":
		return "workshop"
	if kind == "machiya_f_o" or (kind == "machiya_n_o" and trade > 0.62):
		return "inn"
	if kind == "machiya_f_m" and h % 3 == 0:
		return "rice"
	if h % 100 >= 68:
		return ""
	var roles: Array[String] = ["sake", "rice", "dye", "goods", "closed", "inn", "workshop"]
	return roles[h % roles.size()]


func _roofline_role(kind: String, p: Vector2) -> String:
	## Large-form identity is reserved for civic streets and market context.
	## Coordinate hashing is independent of shared dressing/vegetation RNG.
	var on_ns: bool = absf(p.x) < 18.0 and p.y > -166.0 and p.y < 176.0
	var on_ew: bool = absf(p.y - _main_ew_z) < 18.0 and p.x > -76.0 and p.x < 112.0
	var market_context: bool = p.distance_to(Vector2(-26.0, 57.0)) < 58.0
	if not (on_ns or on_ew or market_context):
		return ""
	var hx: int = int(round(p.x * 10.0)) * 83492791
	var hz: int = int(round(p.y * 10.0)) * 2971215073
	var h: int = absi(hx ^ hz)
	if h % 100 >= 62:
		return ""
	var roles: Array[String] = ["gable", "udatsu", "balcony", "store"]
	if kind == "machiya_w_a":
		return "store"
	if kind == "machiya_f_o" or kind == "machiya_n_o":
		return "udatsu"
	return roles[h % roles.size()]

func _river_dist(p: Vector2) -> float:
	return (_nearest_river_pt(p) - p).length()

func build(context: Dictionary) -> void:
	_setup(context)
	var n_noren := 0
	var n_cho := 0
	var n_kan := 0
	var n_clut := 0
	# ── PHASE 3 pilot：RNG 整列ストリーム ──
	# pilot の位置には legacy の ghost を差し込む。ghost は `_dxf_mute` で
	# 出力を捨てつつ _drng を **legacy と同じだけ**消費するので、
	# pilot より後ろの全戸の抽選が一切ずれない（実測 drift 103 → 0）。
	var stream: Array = []
	var pilots: Array = []
	var run := 0
	var i := 0
	while i < _dump.size():
		if _is_pilot(_dump[i]):
			while i < _dump.size() and _is_pilot(_dump[i]):
				pilots.append(_dump[i])
				i += 1
			var lo := 0 if run == 0 else _ghost_run2
			var hi := _ghost_run2 if run == 0 else _ghost.size()
			for k in range(lo, hi):
				stream.append(_ghost[k])
			run += 1
		else:
			stream.append(_dump[i])
			i += 1

	# ── 逐棟：吊掛 + 門前雜物（位置全部從立面錨點推，錨點是從 glb 量的）──
	for e in stream:
		_dxf_mute = _is_pilot(e)
		var kind := String(e[0])
		if not kind.begins_with("machiya"):
			continue
		var m: Dictionary = _mods[kind]
		var fac: Dictionary = m.get("facade", {})
		if fac.is_empty():
			continue
		var pos := Vector2(e[1], e[3])
		var hy: float = e[2]
		var yaw: float = e[4]
		var fwd := Vector2(sin(yaw), cos(yaw))       # 局部 +z（正面朝外）
		var ax := Vector2(cos(yaw), -sin(yaw))       # 局部 +x
		var wgt := _commerce(pos)
		var door_x: float = fac["door_x"]
		var door_w: float = fac["door_w"]
		var beam_y: float = hy + float(fac["beam_z"])
		var half_w: float = float(m["w"]) * 0.5
		# 村緣小屋是住家：吊掛機率砍半，招牌不掛
		var shop := 1.0 if kind != "machiya_e_a" else 0.45
		var identity: String = _identity_role(kind, pos)
		if identity != "":
			_dxf("facade_%s" % identity, pos + ax * door_x + fwd * 0.45, hy, yaw)
			continue
		# 暖簾：門楣下。寬的門掛五巾藍染，窄的掛四巾柿渋
		if _drng.randf() < (0.06 + 0.85 * wgt) * shop:
			var nk := "prop_noren_a" if (door_w > 1.9 and _drng.randf() < 0.7) \
				else "prop_noren_b"
			_dxf(nk, pos + ax * door_x + fwd * 0.14, beam_y, yaw)
			n_noren += 1
		# 提灯：門兩側成對（食堂／酒屋的訊號，跟商業權重走）
		if _drng.randf() < (0.04 + 0.62 * wgt) * shop:
			for sx in [-1.0, 1.0]:
				var cx: float = door_x + sx * (door_w * 0.5 + 0.28)
				if absf(cx) > half_w - 0.35:
					continue
				_dxf("prop_chochin", pos + ax * cx + fwd * 0.24, beam_y - 0.02, yaw)
				n_cho += 1
		# 招牌：掛在離門遠的那半邊；只有商業帶掛
		if wgt > 0.28 and _drng.randf() < 0.72 * wgt * shop:
			var ks: float = 1.0 if door_x < 0.0 else -1.0
			_dxf("prop_kanban", pos + ax * (ks * (half_w - 0.6)) + fwd * 0.18,
				beam_y, yaw)
			n_kan += 1
		# 門前雜物：樽／籃堆／木箱溢到門面前 0.45~1.25m，避開門口帶。
		# 縁台靠牆擺（跟牆平行），住宅帶也會有 —— 老人家坐門口那種。
		var picks: Array[String] = []
		if _drng.randf() < 0.12 + 0.72 * wgt:
			picks.append(["prop_barrel", "prop_basket", "prop_crate"][_drng.randi() % 3])
		if _drng.randf() < 0.45 * wgt:
			picks.append(["prop_barrel", "prop_basket"][_drng.randi() % 2])
		if _drng.randf() < 0.16:
			picks.append("prop_bench")
		for pk in picks:
			var placed := false
			for _try in 6:
				var sx2: float = _drng.randf_range(-(half_w - 0.8), half_w - 0.8)
				if absf(sx2 - door_x) < door_w * 0.5 + 0.45:
					continue
				var lz: float = 0.55 if pk == "prop_bench" else _drng.randf_range(0.45, 1.25)
				var wp: Vector2 = pos + ax * sx2 + fwd * lz
				if _pt_on_road_core(wp, 1.3) or _pt_reserved(wp, 0.4) \
						or _river_dist(wp) < _bank_path + 0.8:
					continue
				var pyaw: float = yaw if pk == "prop_bench" \
					else _drng.randf_range(0.0, TAU)
				_dxf(pk, wp, height_at(wp.x, wp.y), pyaw)
				n_clut += 1
				placed = true
				break
			if not placed:
				continue
	# ── 花樹群聚：同種大群聚做色塊（散點單株是稗田邸點名過的反面教材）──
	_dxf_mute = false
	# ⚠ 花樹の排除判定も **legacy の家**（stream）で行う。新しい pilot の家で
	# 判定すると、採否が変わった瞬間にその後ろの木が全部ずれる。
	# 新しい家と当たる木は、抽選のあとで**フィルタ**して落とす（乱数を
	# 消費しないので後続に影響しない）。
	var house_obbs: Array = []
	for e2 in stream:
		if _is_house_kind(String(e2[0])):
			house_obbs.append(_obb_of(e2))
	var n_tree := 0
	for grp in [{"sites": _sakura_sites, "kinds": ["tree_sakura_a", "tree_sakura_b"]},
			{"sites": _green_sites, "kinds": ["tree_round_a", "tree_round_a"]}]:
		for site in grp.sites:
			var got: Array[Vector2] = []
			var tries := 0
			while got.size() < int(site.n) and tries < int(site.n) * 10:
				tries += 1
				var ang := _drng.randf_range(0.0, TAU)
				var rad: float = sqrt(_drng.randf()) * float(site.r)
				var p: Vector2 = site.c + Vector2(cos(ang), sin(ang)) * rad
				if absf(p.x) > _half - 6.0 or absf(p.y) > _half - 6.0:
					continue
				if _pt_reserved(p, 1.2) or _pt_on_road_core(p, -1.6) \
						or _river_dist(p) < _bank_path + 1.8:
					continue
				var near_house := false
				for hb in house_obbs:
					var d: Vector2 = p - hb[0]
					if absf(d.dot(hb[1])) < hb[3] + 2.6 and absf(d.dot(hb[2])) < hb[4] + 2.6:
						near_house = true
						break
				if near_house:
					continue
				var too_close := false
				for q in got:
					if (q - p).length() < 3.4:
						too_close = true
						break
				if too_close:
					continue
				got.append(p)
				var tk: String = grp.kinds[0] if _drng.randf() < 0.65 else grp.kinds[1]
				_dxf(tk, p, height_at(p.x, p.y), _drng.randf_range(0.0, TAU),
					_drng.randf_range(0.85, 1.2))
				n_tree += 1
			if got.size() < int(site.n):
				_audit.append("⚠ 花樹群聚 (%d,%d) 只放進 %d/%d 棵（空間不夠）"
					% [int(site.c.x), int(site.c.y), got.size(), int(site.n)])
	# ── PHASE 3：新しい pilot の家に当たる木を落とす（乱数は使わない）──
	var new_obbs: Array = []
	for e3 in pilots:
		new_obbs.append(_obb_of(e3))
	var culled := 0
	for kk in _dbatch.keys():
		if not String(kk).begins_with("tree"):
			continue
		var keep: Array = []
		for t3 in _dbatch[kk]:
			var q := Vector2(t3.origin.x, t3.origin.z)
			var hit := false
			for hb2 in new_obbs:
				var dd: Vector2 = q - hb2[0]
				if absf(dd.dot(hb2[1])) < hb2[3] + 2.6 \
						and absf(dd.dot(hb2[2])) < hb2[4] + 2.6:
					hit = true
					break
			if hit:
				culled += 1
			else:
				keep.append(t3)
		_dbatch[kk] = keep
	if culled > 0:
		_audit.append("PHASE 3：pilot の新しい家と当たる花樹 %d 本を除去" % culled)
	# ══════════════════════════════════════════════════════════════
	# PHASE 3 pilot：店先の設え（Phase 2.5/2.6b の規則を村へ移す）
	# ══════════════════════════════════════════════════════════════
	# slice は一区画ずつ手で座標を書いたが、ここは**規則**：
	#   ・役割はモジュール自身＋商業勾配から決まる（新しい手動表は作らない）
	#   ・吊り高さは manifest の facade.hisashi から**計算**する
	#     （Phase 2.6b の承認済み規則。絶対高さを手で書かない）
	#   ・階層を守る：主役 1・脇役 1~2・それ以上は置かない
	var n_dress := 0
	for e4 in pilots:
		var k4 := String(e4[0])
		var m4: Dictionary = _mods[k4]
		var f4: Dictionary = m4.get("facade", {})
		var hs: Dictionary = f4.get("hisashi", {})
		if hs.is_empty() and not f4.has("door_x"):
			continue                      # legacy（machiya_e_a）は対象外
		var p4 := Vector2(float(e4[1]), float(e4[3]))
		var y4: float = float(e4[2])
		var yw: float = float(e4[4])
		var fw4 := Vector2(sin(yw), cos(yw))
		var ax4 := Vector2(cos(yw), -sin(yw))
		var hw4: float = float(m4["w"]) * 0.5
		var dx4: float = float(f4["door_x"])
		var w4 := _commerce(p4)
		var identity4: String = _identity_role(k4, p4)
		if identity4 != "":
			_dxf("facade_%s" % identity4, p4 + ax4 * dx4 + fw4 * 0.45,
				y4, yw)
			n_dress += 1
			continue
		# 庇の下端＝吊り物の天井。前桁より内側に寄せる
		if hs.is_empty():
			continue
		var hz: float = minf(0.84, float(hs["proj"]) - float(hs["beam_back"]))
		var ceil_y: float = y4 + float(hs["z"]) \
			- hz * tan(deg_to_rad(float(hs["slope"]))) - float(hs["thick"]) - 0.035
		# 役割：モジュールが語る（工房は板戸、大店は 5 開間）＋商業勾配
		# ⚠ 役割の閾値を**発明しない**。村の密度層は昔から
		# `0.06 + 0.85*wgt` で暖簾を掛けるか決めている。同じ式を使う ——
		# ここで独自の閾値を切ると、pilot だけ商業の濃さが村とずれる。
		var role := "house"
		if k4 == "machiya_w_a":
			role = "work"
		elif k4 == "machiya_f_o" or _prng.randf() < 0.06 + 0.85 * w4:
			role = "shop"
		# ── 吊り物（主役の一段）──
		if role != "house":
			var nk4 := "prop_noren_ai" if float(f4["door_w"]) > 1.7 else "prop_noren_kaki"
			_dxf(nk4, p4 + ax4 * dx4 + fw4 * hz, ceil_y, yw)
			n_dress += 1
		if role == "shop" and _prng.randf() < 0.55 + 0.4 * w4:
			for sx4 in [-1.0, 1.0]:
				var cx4: float = dx4 + sx4 * 1.55
				if absf(cx4) < hw4 - 0.35:
					_dxf("prop_chochin", p4 + ax4 * cx4 + fw4 * 0.62,
						ceil_y - 0.16 - 0.035, yw)
					n_dress += 1
		# ── 地面（脇役）：役割ごとに一種類だけ。散らかさない ──
		var ground: Array[String] = []
		if role == "shop":
			ground.append_array(["prop_misedai", "prop_zaru", "prop_taru"])
		elif role == "work":
			ground.append_array(["prop_aigame", "prop_aigame", "prop_takigi"])
		elif _prng.randf() < 0.45:
			ground.append("prop_taru")
		var gi4 := 0
		for gk in ground:
			var lat4: float = (float(gi4) - float(ground.size() - 1) * 0.5) * 1.05
			var sx5: float = dx4 + (2.05 + lat4) * (1.0 if dx4 < 0.0 else -1.0)
			if absf(sx5) > hw4 - 0.45:
				gi4 += 1
				continue
			var lz4: float = 1.05 if gk == "prop_misedai" else 0.72
			var wp4: Vector2 = p4 + ax4 * sx5 + fw4 * lz4
			if _pt_on_road_core(wp4, 1.3) or _pt_reserved(wp4, 0.4):
				gi4 += 1
				continue
			var dy4: float = 0.44 if gk == "prop_zaru" else 0.0
			_dxf(gk, wp4, height_at(wp4.x, wp4.y) + dy4,
				yw + _prng.randf_range(-0.14, 0.14))
			n_dress += 1
			gi4 += 1
	if n_dress > 0:
		_audit.append("PHASE 3 pilot：店先の設え %d 件（%d 棟）" % [n_dress, pilots.size()])

	# 集計は _ddump から数え直す（ghost は _dxf で捨てているので入らない）
	n_noren = 0; n_cho = 0; n_kan = 0; n_clut = 0
	var n_tree2 := 0
	for d3 in _ddump:
		var dk := String(d3[0])
		if dk.begins_with("prop_noren"): n_noren += 1
		elif dk == "prop_chochin": n_cho += 1
		elif dk == "prop_kanban": n_kan += 1
		elif dk.begins_with("tree"): n_tree2 += 1
		else: n_clut += 1
	n_tree = n_tree2
	# Roof/upper-front overlays are architectural batches, not scattered props.
	# They sit on existing origins and therefore preserve every lot OBB/setback.
	for e5 in _dump:
		var k5 := String(e5[0])
		if not k5.begins_with("machiya"):
			continue
		var p5 := Vector2(float(e5[1]), float(e5[3]))
		var roofline: String = _roofline_role(k5, p5)
		if roofline == "":
			continue
		_dxf("roofline_%s" % roofline, p5, float(e5[2]), float(e5[4]))
	_emit_density()
	_audit.append("密度層：暖簾 %d、提灯 %d、招牌 %d、地面雜物 %d、花樹 %d（%d draw call）"
		% [n_noren, n_cho, n_kan, n_clut, n_tree, _dbatch.size()])

## 花樹的樹冠材質：**不能**走 lib.tree_mesh 的 canopy_mat —— 那個會拿
## terrain_forest_diff 貼圖乘頂點色，粉色 × 綠貼圖 = 濁褐色。
## 花冠用無貼圖的雙面頂點色材質，樹幹照用 bark PBR。

func _emit_density() -> void:
	var g: Node3D = _lib.add(_root, Node3D.new(), "密度層")
	var names := _dbatch.keys()
	names.sort()
	for kind in names:
		var k := String(kind)
		var mesh: Mesh
		if k.begins_with("tree_sakura"):
			mesh = _sakura_mesh("res://assets/models/%s.glb" % k)
		elif k.begins_with("tree_"):
			mesh = _village_tree_mesh("res://assets/models/%s.glb" % k)
		else:
			mesh = _lib.prop_mesh("res://assets/models/%s.glb" % k, _lib.vc_mat())
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = _lib.make_multimesh(mesh, _dbatch[kind], [],
			_out_dir + "gen/mm_%s.res" % k)
		if not k.begins_with("tree_"):
			# ⚠ 這裡原本設了 visibility_range_end = 110 —— 跟草層那個是**同一個
			# bug**（見 _build_grass）：距離是拿整個 MMI 的 AABB 算的，而道具
			# 鋪滿整個鎮，所以玩家走到村緣時整層道具會一次消失。
			# 之前沒發現是因為截圖機位都在鎮中心，離 AABB 中心夠近。
			# 拿掉；吊掛物不投影仍然保留（那是真的省）。
			if k in ["prop_noren_a", "prop_noren_b", "prop_chochin", "prop_kanban"]:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lib.add(g, mmi, "MM_%s" % k)
