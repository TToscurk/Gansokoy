extends RefCounted
## 獸道 S01 入口林道（R1）候選植被規劃。
##
## 為什麼獨立成檔：S01 R1 只授權改 S01。S02／S03／S04 的植被是凍結檔原樣載入（雜湊檢查），
## 不經過本檔；本檔只往 planner.trees 裡加 scene＝S01 的條目，並登記樹距（讓之後的規劃避開），不動任何別區的資料。
##
## 模式（layout.forest.s01_candidate.mode）：
##   replay  S01 原樣重播 V0.1 凍結檔的 S01（380 筆，含 xf）。工程隔離的『零變化』對照：
##           這個模式下重生出來的 S01 必須和 V1.3 相同（只差 Godot 每次重抽的 unique_id）。
##   r1      美術候選（同 seed 可重現）。見 plan_r1()。
##
## 候選不是正式凍結基準：S01 通過 ART_APPROVED 之後，才把候選提升為新的凍結基準（寫出新凍結檔並登記）。
## 提升工具【尚未實作】（仿 freeze_s04_v12.gd）；使用者核准前不做，因為做了就等於未經核准的凍結。
##
## r1 的設計（使用者 S01 規格；第一輪不增加總量，只重新分配）：
##   · 原 380 筆＝8 釘點＋327 樹＋45 林下。其中 227 棵是谷壁上的背景林（離谷緣 ≥ 6 m），路廊內（±40 m）只有約 100 棵，
##     而且間距幾乎等距（最近鄰 4~6 m）＝均勻疏林，這就是『公園感』的來源之一；
##   · 釘點（櫻群、鳥居門樹）原樣保留；村後（路起點以北）與接縫（z＝−100 附近）的樹原樣保留；
##   · 路廊內的樹與林下全部重排：沿主路每隔一段在路的一側或兩側長出一『叢』，叢內樹距近、叢與叢之間留空隙；
##     進度 u（沿主路的相對進度，不是面積比）：0–30 % 村緣（開闊、零星小叢）→ 30–70 % 自然雜木 → 70–100 % 樹冠交錯、林蔭、較密地被；
##   · 總量守恆：新增的量由背景林裡『過度擠密、離谷緣夠遠』的地方扣掉（只剪鄰居最多的樹，稀疏處不動）；
##     稀疏後的天際線落差與覆蓋由規劃回報（skyline_max_drop_deg、sky_bins_*），verify 另行檢查；
##   · 樹種隨進度由村緣的闊葉／幼樹為主，過渡到與 S02 接縫處相同的杉＋闊葉混合；每叢有主要樹種（約 6 成）；大小有高低、微傾（生長方向）；
##   · 林下（灌木／蕨／笹）長在樹叢腳、路肩、岩腳、田邊籬，不均勻撒滿；
##   · 路必須讀得出來：樹幹表面離路緣至少 zones[].clear（村緣 2.0 m → 深處 3.2 m，樹冠可以伸過路但樹幹不站進路肩）。

##   r2      R2 修整（使用者 2026-10-16 R2 授權）：r1 的全部規則＋cfg.r2 的局部修整（谷壁點綴、拆左側群落鏈、
##           25–30 % 過渡、釘點櫻小幅位移、鳥居前／90 % 路肩受光守門）。r2 為空時與 r1 逐位元相同（R1 可由 mode＝r1 重現）。
const S01Wall := preload("res://tools/beast_path/s01_wall.gd")


static func plan(fp, cfg: Dictionary) -> Dictionary:
	var mode := String(cfg.get("mode", "replay"))
	match mode:
		"replay":
			fp._adopt_entries("S01", fp._hist_s01)
			return {"mode": mode, "round": String(cfg.get("round", "")), "n": fp._hist_s01.size()}
		"r1":
			return plan_r1(fp, cfg)
		"r2":
			var r2: Dictionary = cfg.get("r2", {})
			if r2.is_empty():
				fp.freeze_error = "S01 候選 mode＝r2 但沒有 r2 設定"
				return {}
			return plan_r1(fp, cfg, r2)
		_:
			fp.freeze_error = "S01 候選未知的 mode：%s" % mode
			return {}


# ---------------------------------------------------------------- R2 小工具
## 路的座標系：p 投影到主路 → {s, off（沿 rv 的側向距離，rv＝(−tg.y, tg.x)，向右為正）}
static func _path_frame(lib, p: Vector2) -> Dictionary:
	var q: Dictionary = lib.main.q(p)
	var s := float(q["s"])
	var c: Vector2 = lib.main.pos_at(s)
	var tg: Vector2 = lib.main.tan_at(s)
	var rv := Vector2(-tg.y, tg.x)
	return {"s": s, "off": (p - c).dot(rv)}


static func _from_frame(lib, s: float, off: float) -> Vector2:
	var tg: Vector2 = lib.main.tan_at(s)
	return lib.main.pos_at(s) + Vector2(-tg.y, tg.x) * off


## 離最近的谷壁岩（主岩／衛星岩／碎石）外緣多遠（m）
static func _rock_clear(rocks: Array, p: Vector2) -> float:
	var best := 1e9
	for r: Dictionary in rocks:
		var d := p.distance_to(Vector2(float(r["x"]), float(r["z"]))) - 0.5 * maxf(float(r["w"]), float(r["d"]))
		best = minf(best, d)
	return best


## R2 路肩受光守門（局部）：只在 cfg.r2.shade.ranges 的進度範圍、多個時刻，每 5 m 一窗分左右路肩算受光；
## 放新樹時若會讓某時刻某窗『受光較多的那一側路肩』掉到地板以下（而且比原本更暗）就拒絕。
## 目的＝使用者 R2 §9：樹影可以有（氣氛），但不能蓋住整段路的兩側路肩、讓人分不出路緣。
static func _shade_init(fp, sh: Dictionary, s0: float, L: float, bd: Array) -> Dictionary:
	var lib = fp.lib
	var hours: Array = sh.get("hours", [8, 10, 14, 16])
	var edge := float(sh.get("edge", 1.5))
	var win_len := float(sh.get("win", 5.0))
	var suns: Array = []
	for h: Variant in hours:
		var t := (float(h) - 6.0) / 12.0
		var e := deg_to_rad(sin(PI * t) * 72.0 + 6.0)
		var az := deg_to_rad(-40.0 + 80.0 * t)
		suns.append(Vector3(sin(az) * cos(e), sin(e), cos(az) * cos(e)))
	var pts: Array = []        # [pos, win, side(0=L,1=R)]
	var wins := {}
	for rg_: Array in sh.get("ranges", []):
		var sa := s0 + float(rg_[0]) * L
		var sb := s0 + float(rg_[1]) * L
		var s := sa
		while s <= sb:
			var c: Vector2 = lib.main.pos_at(s)
			var tg: Vector2 = lib.main.tan_at(s)
			var rv := Vector2(-tg.y, tg.x)
			var w := int(floor((s - s0) / win_len))
			wins[w] = true
			for side in 2:
				var q: Vector2 = c + rv * (edge if side == 1 else -edge)
				pts.append([Vector3(q.x, lib.h_at(q.x, q.y) + 0.3, q.y), w, side])
			s += 1.0
	var st := {"suns": suns, "hours": hours, "pts": pts, "lit": [], "tot": {}, "litc": [], "floor": sh.get("floor", {}), "rej": 0, "win_len": win_len}
	for hi in suns.size():
		var lit: Array = []
		lit.resize(pts.size())
		lit.fill(1)
		(st["lit"] as Array).append(lit)
		var lc := {}
		for k in pts.size():
			var key: String = "%d_%d" % [int(pts[k][1]), int(pts[k][2])]
			lc[key] = int(lc.get(key, 0)) + 1
			if hi == 0:
				st["tot"][key] = int((st["tot"] as Dictionary).get(key, 0)) + 1
		(st["litc"] as Array).append(lc)
	var crowns: Array = []
	for t: Dictionary in fp.trees:
		var kind := String(t["kind"])
		if (kind == "tree" or kind == "pin" or kind == "landmark") and float(t["z"]) > -150.0 and float(t["z"]) < 30.0:
			crowns.append(_crown(fp, String(t["id"]), float(t["s"]), float(t["x"]), float(t["y"]), float(t["z"])))
	for e: Dictionary in bd:
		crowns.append(_crown(fp, String(e["id"]), float(e["s"]), float(e["x"]), float(e["y"]), float(e["z"])))
	for cr: Array in crowns:
		_shade_commit(st, cr[0], float(cr[1]))
	st["rej"] = 0
	return st


static func _shade_hits(st: Dictionary, hi: int, center: Vector3, r: float) -> Array:
	var hits: Array = []
	var sun: Vector3 = st["suns"][hi]
	var lit: Array = st["lit"][hi]
	var pts: Array = st["pts"]
	for i in pts.size():
		if int(lit[i]) == 0:
			continue
		var o: Vector3 = pts[i][0]
		if absf(center.x - o.x) > 45.0 or absf(center.z - o.z) > 45.0:
			continue
		var oc := center - o
		var tt := oc.dot(sun)
		if tt < 0.0:
			continue
		if oc.length_squared() - tt * tt < r * r:
			hits.append(i)
	return hits


static func _shade_commit(st: Dictionary, center: Vector3, r: float) -> void:
	for hi in (st["suns"] as Array).size():
		var lit: Array = st["lit"][hi]
		var lc: Dictionary = st["litc"][hi]
		for i: int in _shade_hits(st, hi, center, r):
			lit[i] = 0
			var key: String = "%d_%d" % [int(st["pts"][i][1]), int(st["pts"][i][2])]
			lc[key] = int(lc[key]) - 1


## 每個時刻、每窗：max(左路肩受光, 右路肩受光)
static func _shade_best(st: Dictionary, hi: int, w: int, minus: Dictionary = {}) -> float:
	var lc: Dictionary = st["litc"][hi]
	var best := 0.0
	for side in 2:
		var key := "%d_%d" % [w, side]
		if not (st["tot"] as Dictionary).has(key):
			continue
		var v := float(int(lc[key]) - int(minus.get(key, 0))) / float(maxi(int(st["tot"][key]), 1))
		best = maxf(best, v)
	return best


static func _shade_ok(st: Dictionary, center: Vector3, r: float) -> bool:
	for hi in (st["suns"] as Array).size():
		var hits := _shade_hits(st, hi, center, r)
		if hits.is_empty():
			continue
		var per := {}
		var wins := {}
		for i: int in hits:
			var key: String = "%d_%d" % [int(st["pts"][i][1]), int(st["pts"][i][2])]
			per[key] = int(per.get(key, 0)) + 1
			wins[int(st["pts"][i][1])] = true
		var fl := float((st["floor"] as Dictionary).get(str(int(st["hours"][hi])), 0.4))
		for w: int in wins:
			var before := _shade_best(st, hi, w)
			var after := _shade_best(st, hi, w, per)
			if after < fl and after < before - 1e-6:
				return false
	return true


## 釘點櫻小幅位移（R2 §7）：位置＝layout 的釘點位置在『路的座標系』裡沿路 ds、離路方向 doff（＋＝離路更遠）；
## 樹種變體、縮放（樹高）不變；朝向換成 yaw_deg。回傳新的條目（kind 仍是 pin、pin 名不變）或空字典（被擋＝不動）。
static func _moved_pin(fp, e: Dictionary, mv: Dictionary) -> Dictionary:
	var lib = fp.lib
	var pins: Array = fp._fcfg["pins"]
	for idx in pins.size():
		if String((pins[idx] as Dictionary)["id"]) != String(e["pin"]):
			continue
		var info: Dictionary = fp._pin_info(pins[idx], idx)
		var p0: Vector2 = info["p"]
		var fr := _path_frame(lib, p0)
		var off0 := float(fr["off"])
		var sgn := 1.0 if off0 >= 0.0 else -1.0
		var p1 := _from_frame(lib, float(fr["s"]) + float(mv.get("ds", 0.0)), off0 + sgn * float(mv.get("doff", 0.0)))
		return {"id": String(info["id"]), "p": p1, "p0": p0, "s": float(info["s"]), "yaw": deg_to_rad(float(mv.get("yaw_deg", 0.0)))}
	return {}


# ---------------------------------------------------------------- 小工具（關鍵影格內插）
## frames＝[{u:…, key:…}…]（u 遞增）。回傳 [i0, i1, t]
static func _seg(frames: Array, u: float) -> Array:
	var n := frames.size()
	if u <= float((frames[0] as Dictionary)["u"]):
		return [0, 0, 0.0]
	for i in range(1, n):
		var u1 := float((frames[i] as Dictionary)["u"])
		if u <= u1:
			var u0 := float((frames[i - 1] as Dictionary)["u"])
			return [i - 1, i, (u - u0) / maxf(u1 - u0, 1e-6)]
	return [n - 1, n - 1, 0.0]


static func _kf(frames: Array, u: float, key: String) -> float:
	var sg := _seg(frames, u)
	return lerpf(float((frames[sg[0]] as Dictionary)[key]), float((frames[sg[1]] as Dictionary)[key]), float(sg[2]))


static func _kfv(frames: Array, u: float, key: String) -> Vector2:
	var sg := _seg(frames, u)
	var a: Array = (frames[sg[0]] as Dictionary)[key]
	var b: Array = (frames[sg[1]] as Dictionary)[key]
	var t := float(sg[2])
	return Vector2(lerpf(float(a[0]), float(b[0]), t), lerpf(float(a[1]), float(b[1]), t))


static func _pick(w: Dictionary, rng: RandomNumberGenerator) -> String:
	var tot := 0.0
	for k: String in w:
		tot += float(w[k])
	var r := rng.randf() * tot
	for k2: String in w:
		r -= float(w[k2])
		if r <= 0.0:
			return k2
	return String(w.keys()[0])


static func _rng(seed_: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_ & 0x7FFFFFFF
	return r


## 樹種權重：進度 u 的混合比 × 林帶（stands）偏好 × 林緣幼樹。和 forest_planner._species_weights 同一套規則，只是混合比隨 u 內插。
static func _weights(fp, cfg: Dictionary, p: Vector2, u: float) -> Dictionary:
	var frames: Array = cfg["mix"]
	var w := {}
	for sp: String in ["cedar", "broadleaf", "maple", "cherry", "sapling"]:
		w[sp] = _kf(frames, u, sp)
	for st: Dictionary in fp._stands:
		var d: float = p.distance_to(st["c"])
		if d < float(st["r"]):
			var t := 1.0 - (d / float(st["r"])) * (d / float(st["r"]))
			var sp2 := String(st["sp"])
			if w.has(sp2):
				w[sp2] = float(w[sp2]) * (1.0 + 3.0 * (float(st["boost"]) - 1.0) * t * t)
	var cd: float = fp._clear_dist(p)
	if cd > 0.0 and cd < 8.0:
		w["sapling"] = float(w["sapling"]) * 2.4                  # 林緣（空地邊 8 m 內）幼樹偏多
	return w


# ---------------------------------------------------------------- 路面日照守門（10:00 太陽）
## 規則：沿主路每 1 m 取 3 點（中心、左右各 1.5 m），朝太陽方向射線對『樹冠球體』求交，沒被擋＝受光。
## 每 light_win m 一窗；放新樹時若它會讓某窗的受光比例掉到地板（light_floor，隨進度）以下就拒絕——
## 樹冠可以伸過路、可以有樹影，但路必須讀得出來（使用者停止條件：森林密度使主路不易辨識）。
## 樹冠球：中心高 0.62×樹高，半徑 0.35×樹冠寬（不含半透明葉隙，所以是偏保守的陰影）。
static func _crown(fp, id: String, s: float, x: float, y: float, z: float) -> Array:
	var k: Dictionary = fp.kit[id]
	var h := float(k["h"]) * s
	return [Vector3(x, y + 0.62 * h, z), maxf(float(k["wx"]) * s * 0.5 * 0.7, 1.0)]


static func _light_init(fp, cfg: Dictionary, s0: float, L: float, bd: Array) -> Dictionary:
	var lib = fp.lib
	var sd: Array = cfg.get("sun_dir", [-0.5574, 0.7646, 0.3218])
	var sun := Vector3(float(sd[0]), float(sd[1]), float(sd[2])).normalized()
	var win_len := float(cfg.get("light_win", 10.0))
	var pts: Array = []
	var wi: Array = []
	var s := 0.0
	while s <= L:
		var c: Vector2 = lib.main.pos_at(s0 + s)
		var tg: Vector2 = lib.main.tan_at(s0 + s)
		var rv := Vector2(-tg.y, tg.x)
		for off: float in [-1.5, 0.0, 1.5]:
			var q: Vector2 = c + rv * off
			pts.append(Vector3(q.x, lib.h_at(q.x, q.y) + 0.3, q.y))
			wi.append(int(s / win_len))
		s += 1.0
	var nwin := int(L / win_len) + 1
	# 一般 Array（參照語意）：Packed 陣列放進 Dictionary 是值語意，索引寫入會落在副本上
	var lit: Array = []
	lit.resize(pts.size())
	lit.fill(1)
	var win_tot: Array = []
	win_tot.resize(nwin)
	win_tot.fill(0)
	var win_lit: Array = []
	win_lit.resize(nwin)
	win_lit.fill(0)
	for w in wi:
		win_tot[w] += 1
		win_lit[w] += 1
	var st := {"sun": sun, "pts": pts, "wi": wi, "lit": lit, "nwin": nwin, "win_len": win_len, "L": L, "win_tot": win_tot, "win_lit": win_lit, "rej": 0}
	var crowns: Array = []
	for t: Dictionary in fp.trees:
		var kind := String(t["kind"])
		if (kind == "tree" or kind == "pin" or kind == "landmark") and float(t["z"]) > -150.0 and float(t["z"]) < 30.0:
			crowns.append(_crown(fp, String(t["id"]), float(t["s"]), float(t["x"]), float(t["y"]), float(t["z"])))
	for e: Dictionary in bd:
		crowns.append(_crown(fp, String(e["id"]), float(e["s"]), float(e["x"]), float(e["y"]), float(e["z"])))
	for cr: Array in crowns:
		_light_commit(st, cr[0], float(cr[1]))
	st["rej"] = 0
	return st


## 這顆樹冠會擋到哪些目前受光的取樣點（索引）
static func _light_hits(st: Dictionary, center: Vector3, r: float) -> Array:
	var hits: Array = []
	var sun: Vector3 = st["sun"]
	var pts: Array = st["pts"]
	var lit: Array = st["lit"]
	for i in pts.size():
		if int(lit[i]) == 0:
			continue
		var o: Vector3 = pts[i]
		if absf(center.x - o.x) > 40.0 or absf(center.z - o.z) > 40.0:
			continue
		var oc := center - o
		var tt := oc.dot(sun)
		if tt < 0.0:
			continue
		if oc.length_squared() - tt * tt < r * r:
			hits.append(i)
	return hits


static func _light_commit(st: Dictionary, center: Vector3, r: float) -> void:
	var lit: Array = st["lit"]
	var win_lit: Array = st["win_lit"]
	var wi: Array = st["wi"]
	for i: int in _light_hits(st, center, r):
		lit[i] = 0
		win_lit[int(wi[i])] = int(win_lit[int(wi[i])]) - 1


## 放這顆樹會不會讓任一窗的受光比例掉到地板以下？（本來就在地板以下的窗：只要這顆樹沒有再擋到它就放行）
static func _light_ok(st: Dictionary, cfg: Dictionary, center: Vector3, r: float, L: float) -> bool:
	var hits := _light_hits(st, center, r)
	if hits.is_empty():
		return true
	var wi: Array = st["wi"]
	var per := {}
	for i: int in hits:
		per[int(wi[i])] = int(per.get(int(wi[i]), 0)) + 1
	var fr: Array = cfg["light_floor"]
	for w: int in per:
		var u_w := (float(w) + 0.5) * float(st["win_len"]) / L
		var floor_v := _kf(fr, clampf(u_w, 0.0, 1.0), "v")
		var after := float(int(st["win_lit"][w]) - int(per[w])) / float(maxi(int(st["win_tot"][w]), 1))
		if after < floor_v:
			return false
	return true


# ---------------------------------------------------------------- r1
## r2＝cfg.r2（空＝R1 原樣；所有 R2 分支都在 R2 旗標之後，R1 的亂數序列與輸出不變）。
static func plan_r1(fp, cfg: Dictionary, r2: Dictionary = {}) -> Dictionary:
	var lib = fp.lib
	var consts: Dictionary = fp.get_script().get_script_constant_map()
	var SP: Dictionary = consts["SPECIES"]
	var UN: Dictionary = consts["UNDER"]
	var zs: int = int(fp.zone_seed("S01"))
	var salt: int = int(cfg.get("salt", 1))
	var s0: float = lib.st_s("village")
	var s1: float = lib.st_s("s01_s02")
	var L: float = s1 - s0
	var bd_min: float = float(cfg.get("backdrop_min_sdf", 6.0))
	var use_r2 := not r2.is_empty()
	var info := {"mode": "r2" if use_r2 else "r1", "round": String(cfg.get("round", "")), "salt": salt}
	# ---- 1) 歷史條目分類：釘點／村後與接縫（原樣）、背景林（稀疏化候選）、路廊內的樹與林下（重排）
	var keep: Array = []
	var bd: Array = []
	var n_pin := 0
	var n_edge := 0
	var n_rep_tree := 0
	var n_rep_under := 0
	var pin_moves: Dictionary = r2.get("pin_moves", {})
	var moved: Array = []
	for e: Dictionary in fp._hist_s01:
		var kind := String(e["kind"])
		var p := Vector2(float(e["x"]), float(e["z"]))
		if kind == "pin" or kind == "landmark":
			if use_r2 and pin_moves.has(String(e["pin"])):
				moved.append(e)                             # R2 §7：只動 layout 點名的釘點櫻，其他釘點原樣
			else:
				keep.append(e)
			n_pin += 1
			continue
		var qq: Dictionary = lib.main.q(p)
		var u := (float(qq["s"]) - s0) / L
		if kind == "tree" and lib.mask_sdf(p) >= bd_min:
			bd.append(e)
			continue
		if u <= 0.02 or u >= 1.0:
			keep.append(e)                                  # 村後（路起點以北）與接縫：不動
			n_edge += 1
			continue
		if kind == "tree":
			n_rep_tree += 1
		else:
			n_rep_under += 1
	fp._adopt_entries("S01", keep)
	if String(fp.freeze_error) != "":
		return {}
	info["pins"] = n_pin
	info["kept_edge"] = n_edge
	info["backdrop"] = bd.size()
	info["replaced_trees"] = n_rep_tree
	info["replaced_under"] = n_rep_under
	# ---- 1b) R2：釘點櫻小幅位移（種類／樹高不變、仍是 pin）；被擋就原樣不動並記錄
	var pin_log: Array = []
	for e2: Dictionary in moved:
		var mv: Dictionary = pin_moves[String(e2["pin"])]
		var np := _moved_pin(fp, e2, mv)
		var ok := not np.is_empty()
		var rr := 0.0
		var why := ""
		if ok:
			rr = float((fp.kit[String(np["id"])] as Dictionary)["r"]) * float(np["s"])
			var pp: Vector2 = np["p"]
			if lib.scene_id_of_z(pp.y) != "S01":
				why = "出 S01"
			elif fp._blocked(pp, rr, true):
				why = "禁區"
			elif fp._too_close(pp, 3.0 + rr * 2.0, "t", rr):
				why = "離別的樹太近"
			ok = why == ""
		if not ok:
			fp._adopt_entries("S01", [e2])
			pin_log.append({"pin": String(e2["pin"]), "moved": false, "why": why})
			continue
		var p1: Vector2 = np["p"]
		fp._add_tree(String(np["id"]), p1, float(np["s"]), float(np["yaw"]), "pin", String(e2["pin"]))
		fp._register(p1, rr, 3.0 + rr * 2.0)
		var p0: Vector2 = np["p0"]
		pin_log.append({"pin": String(e2["pin"]), "moved": true, "id": String(np["id"]), "from": [snappedf(p0.x, 0.01), snappedf(p0.y, 0.01)],
			"to": [snappedf(p1.x, 0.01), snappedf(p1.y, 0.01)], "dist": snappedf(p0.distance_to(p1), 0.01)})
	if use_r2:
		info["pin_moves"] = pin_log
	# ---- 1c) R2：谷壁點綴規劃（岩露頭／坡腳碎石／土袋）。要避開已載入的樹＋背景林，所以在分類之後、群落之前
	var wall := {}
	var wrocks: Array = []
	if use_r2 and r2.has("wall"):
		wall = S01Wall.plan(fp, r2["wall"], zs + salt * 7, bd)
		wrocks = wall["rocks"]
		info["wall"] = wall["info"]
	# ---- 2) 沿路的群落
	var zones: Array = cfg["zones"]
	var light := _light_init(fp, cfg, s0, L, bd)
	var shade := {}
	if use_r2 and r2.has("shade"):
		shade = _shade_init(fp, r2["shade"], s0, L, bd)
	var rg := _rng(zs * 31 + salt * 7919 + 11)
	var groves: Array = []
	var gdiag := {"attempt": 0, "skip_p": 0, "skip_clear": 0, "skip_mask": 0, "skip_overlap": 0}
	var s := s0 + float(cfg.get("first_gap", 6.0))
	var guard := 0
	while s < s1 - 2.0 and guard < 400:
		guard += 1
		var u := (s - s0) / L
		var step_r := _kfv(zones, u, "step")
		var tg: Vector2 = lib.main.tan_at(s)
		var rv := Vector2(-tg.y, tg.x)
		var hw: float = lib.main.w_at(s) * 0.5
		var ctr: Vector2 = lib.main.pos_at(s)
		var pside := _kf(zones, u, "p_side")
		var er := _kfv(zones, u, "edge")
		var rr := _kfv(zones, u, "radius")
		var nr := _kfv(zones, u, "n")
		for side: float in [-1.0, 1.0]:
			var r_go := rg.randf()                          # 每個 (s, side) 固定抽 6 個亂數：接受與否不會位移後面的序列
			var r_edge := rg.randf()
			var r_R := rg.randf()
			var r_n := rg.randf()
			var r_t := rg.randf()
			var r_x := rg.randf()
			gdiag["attempt"] += 1
			if r_go > pside:
				gdiag["skip_p"] += 1
				continue
			var edge := lerpf(er.x, er.y, r_edge)
			var R := lerpf(rr.x, rr.y, r_R)
			var c: Vector2 = ctr + rv * side * (hw + edge + R * 0.35) + tg * lerpf(-3.0, 3.0, r_t)
			if fp._clear_dist(c) < 0.0:
				gdiag["skip_clear"] += 1
				continue                                    # 叢中心不在空地（草地／田）裡
			if lib.mask_sdf(c) > 0.0:
				gdiag["skip_mask"] += 1
				continue                                    # 也不在谷壁外
			var ok := true
			for g: Dictionary in groves:
				if c.distance_to(g["c"]) < (float(g["R"]) + R) * float(cfg.get("grove_overlap_k", 0.55)) + float(cfg.get("grove_gap", 1.5)):
					ok = false
					break
			if not ok:
				gdiag["skip_overlap"] += 1
				continue
			groves.append({"c": c, "R": R, "n": int(roundf(lerpf(nr.x, nr.y, r_n))), "u": u, "side": side, "x": r_x})
		s += lerpf(step_r.x, step_r.y, rg.randf())
	# R2 §5：拆左側群落鏈（drop／push）、補右側（add）。群落的索引不變（被拿掉的只標記、不刪），
	# 因為每叢的填樹亂數由索引決定——這樣沒被點名的群落維持 R1 的樣子（使用者：保留 R1 已達成的改善）。
	if use_r2:
		info["grove_edits"] = _grove_edits(fp, cfg, r2.get("groves", {}), groves, s0, L)
	# 位置固定的『孤木』（村緣的老樹…）：layout 明寫，不抽樣
	var lone_n := 0
	var rl := _rng(zs * 131 + salt * 104729 + 7)
	for ln: Dictionary in cfg.get("lone", []):
		var pp: Vector2 = lib.resolve(ln["at"])["p"]
		var id := String(ln["id"])
		var k: Dictionary = fp.kit[id]
		var sc := float(ln["h"]) / float(k["h"])
		var rt0 := float(k["r"]) * sc
		var yaw0 := rl.randf() * TAU
		var lean_r := rl.randf()
		if fp.lib.scene_id_of_z(pp.y) != "S01" or fp._blocked(pp, rt0, true) or fp._too_close(pp, 3.0, "t", rt0):
			push_warning("S01 孤木 %s 的位置被擋掉（禁區或離別的樹太近）" % String(ln.get("name", id)))
			continue
		fp._add_tree(id, pp, sc, yaw0, "tree", "")
		fp._register(pp, rt0, 3.6, "t")
		_lean(fp.trees[fp.trees.size() - 1], Vector2.ZERO, pp, lean_r, cfg, 0.7)
		lone_n += 1
	# 各群落填樹
	var n_tree := 0
	var n_rej := 0
	var third := [0, 0, 0]          # 村緣／中段／深處
	var members: Array = []         # 每叢的樹位置（林下用）
	var gcfg: Dictionary = r2.get("groves", {})
	var flower_k := float(gcfg.get("near_flower_k", 1.0))
	var flower_d := float(gcfg.get("near_flower_d", 0.0))
	var sub: Dictionary = gcfg.get("subclump", {})
	for gi in groves.size():
		var g2: Dictionary = groves[gi]
		var rt := _rng(zs * 193 + salt * 15485863 + gi * 7727)
		var u2 := float(g2["u"])
		var cg: Vector2 = g2["c"]
		var R2 := float(g2["R"])
		var placed := 0
		var tries := 0
		var age := rt.randf_range(0.92, 1.12)
		var wbase := _weights(fp, cfg, cg, u2)
		var dom := _pick(wbase, rt)
		wbase[dom] = float(wbase[dom]) * float(cfg.get("dominant_k", 3.0))
		var mem: Array = []
		if bool(g2.get("drop", false)):
			g2["placed"] = 0
			g2["dom"] = dom
			members.append(mem)
			continue
		# R2：群落內的『小叢』——樹距不再貼著最小樹距均勻排：1–2 個小叢心，叢心附近的樹可以近（雙幹、擠在一起），另有離群的
		var subs: Array = []
		if use_r2 and not sub.is_empty():
			var ns := 1 if int(g2["n"]) < 6 else 2
			for k_s in ns:
				subs.append(cg + Vector2.from_angle(rt.randf() * TAU) * R2 * rt.randf_range(0.15, 0.55))
		while placed < int(g2["n"]) and tries < int(g2["n"]) * 14:
			tries += 1
			var ang := rt.randf() * TAU
			var rad := R2 * pow(rt.randf(), 0.72)
			var p2: Vector2 = cg + Vector2(cos(ang), sin(ang)) * rad
			var gap_k := 1.0
			if not subs.is_empty():
				var r_out := rt.randf()
				var r_sub := rt.randf()
				var r_gk := rt.randf()
				if r_out >= float(sub.get("outlier_p", 0.3)):
					var sc_: Vector2 = subs[int(r_sub * float(subs.size())) % subs.size()]
					p2 = sc_ + Vector2(cos(ang), sin(ang)) * R2 * float(sub.get("r_k", 0.42)) * pow(rad / R2, 1.1)
					gap_k = lerpf(float(sub.get("gap_k", [0.5, 1.0])[0]), float(sub.get("gap_k", [0.5, 1.0])[1]), r_gk)
				else:
					p2 = cg + Vector2(cos(ang), sin(ang)) * R2 * lerpf(0.55, 1.15, r_sub)
			var dedge0: float = lib.sample_arr(lib.DM, p2.x, p2.y) - lib.sample_arr(lib.WM, p2.x, p2.y)
			var wt: Dictionary = wbase
			if dedge0 < float(cfg.get("cedar_min_edge", 6.0)):
				wt = wbase.duplicate()
				wt["cedar"] = 0.0                                   # 路緣帶（離路緣 < 6 m）：先驅闊葉、幼樹；杉（人工造林）退到 6 m 以外，路邊不會站一排杉幹
			if use_r2 and dedge0 < flower_d:
				wt = wt.duplicate()
				wt["cherry"] = float(wt["cherry"]) * flower_k       # R2：近路的櫻／楓降權（R1 的『夾道賞花』列植感）
				wt["maple"] = float(wt["maple"]) * flower_k
			var spn := _pick(wt, rt)
			var spec: Dictionary = SP[spn]
			var id2 := _pick(spec["v"], rt)
			var sc2 := lerpf(float(spec["s"][0]), float(spec["s"][1]), rt.randf()) * age * (1.0 + 0.10 * (1.0 - rad / R2))
			var r_stunt := rt.randf()
			var r_stunt_k := rt.randf()
			if spn != "sapling" and r_stunt < float(cfg.get("stunt_p", 0.3)):
				sc2 *= lerpf(0.68, 0.85, r_stunt_k)                  # 被壓著的矮樹：同一叢裡有高有矮，不是同齡林
			sc2 = minf(sc2, float(spec["s"][1]) * float(cfg.get("scale_cap_k", 1.06)))
			var yaw2 := rt.randf() * TAU
			var lean_r2 := rt.randf()
			var rt2 := float((fp.kit[id2] as Dictionary)["r"]) * sc2
			if fp.lib.scene_id_of_z(p2.y - rt2) != "S01" or lib.mask_sdf(p2) > 3.0 or fp._blocked(p2, rt2):
				n_rej += 1
				continue
			var dedge: float = lib.sample_arr(lib.DM, p2.x, p2.y) - lib.sample_arr(lib.WM, p2.x, p2.y)
			if dedge < _kf(zones, u2, "clear") + rt2:
				n_rej += 1
				continue
			var gap := maxf(float(spec["gap"]) * float(cfg.get("grove_gap_k", 0.66)), 1.7)
			if use_r2:
				gap = maxf(gap * gap_k, float(sub.get("gap_min", 1.5)))
				if _rock_clear(wrocks, p2) < rt2 + 0.6:
					n_rej += 1
					continue
			if fp._too_close(p2, gap, "t", rt2):
				n_rej += 1
				continue
			var gy: float = lib.h_at(p2.x, p2.y)
			var crw := _crown(fp, id2, sc2, p2.x, gy, p2.y)
			if not _light_ok(light, cfg, crw[0], float(crw[1]), L):
				light["rej"] = int(light["rej"]) + 1
				continue                                    # 這棵會把這段路遮得太暗：不放（這就是『叢』會有空隙的物理原因之一）
			if not shade.is_empty() and not _shade_ok(shade, crw[0], float(crw[1])):
				shade["rej"] = int(shade["rej"]) + 1
				continue                                    # R2：這棵會讓這一段兩側路肩都暗掉（多時刻）：不放
			_light_commit(light, crw[0], float(crw[1]))
			if not shade.is_empty():
				_shade_commit(shade, crw[0], float(crw[1]))
			fp._add_tree(id2, p2, sc2, yaw2, "tree", "")
			fp._register(p2, rt2, gap, "t")
			_lean(fp.trees[fp.trees.size() - 1], cg, p2, lean_r2, cfg, 1.0)
			mem.append(p2)
			placed += 1
			n_tree += 1
			third[clampi(int(u2 * 3.0), 0, 2)] += 1
		g2["placed"] = placed
		g2["dom"] = dom
		members.append(mem)
	var lit_pct: Array = []
	for w3 in int(light["nwin"]):
		lit_pct.append(int(round(100.0 * float(int(light["win_lit"][w3])) / float(maxi(int(light["win_tot"][w3]), 1)))))
	info["road_lit_pct"] = lit_pct
	info["light_rejected"] = int(light["rej"])
	info["groves"] = groves.size()
	info["grove_diag"] = gdiag
	info["grove_list"] = groves.map(func(g): return "u%.2f s%+d n%d/%d R%.1f %s" % [float(g["u"]), int(g["side"]), int(g["placed"]), int(g["n"]), float(g["R"]), String(g["dom"])])
	info["grove_empty"] = groves.filter(func(g): return int(g["placed"]) == 0).size()
	info["trees_new"] = n_tree + lone_n
	info["lone"] = lone_n
	info["trees_by_third"] = third
	info["rejected"] = n_rej
	# ---- 3) 林下：樹叢腳、路肩、岩腳、田邊籬
	var n_under := 0
	var under_third := [0, 0, 0]
	var ur: Array = cfg["under"]
	var ru := _rng(zs * 389 + salt * 32452843 + 3)
	# (a) 樹叢腳：一部分長在叢內樹旁（樹下），其餘在叢的外緣（坡腳）
	for gi2 in groves.size():
		var g3: Dictionary = groves[gi2]
		var u3 := float(g3["u"])
		var mem3: Array = members[gi2]
		var want := int(roundf(float(g3["placed"]) * _kf(ur, u3, "per_tree") * (float(r2.get("under_k", 1.0)) if use_r2 else 1.0)))
		var got := 0
		var tries2 := 0
		while got < want and tries2 < want * 10 + 8:
			tries2 += 1
			var cc: Vector2
			if not mem3.is_empty() and ru.randf() < 0.6:
				var m: Vector2 = mem3[ru.randi_range(0, mem3.size() - 1)]
				cc = m + Vector2.from_angle(ru.randf() * TAU) * ru.randf_range(1.0, 2.6)
			else:
				cc = (g3["c"] as Vector2) + Vector2.from_angle(ru.randf() * TAU) * float(g3["R"]) * ru.randf_range(0.7, 1.3)
			var made := _under_cluster(fp, cfg, UN, cc, u3, ru, 2, 4, wrocks)
			got += made
			n_under += made
			under_third[clampi(int(u3 * 3.0), 0, 2)] += made
	# (b) 路肩：沿路每隔幾 m 擲一次，成叢（村緣稀、林內多）
	var sv := s0 + 3.0
	while sv < s1 - 2.0:
		var uv := (sv - s0) / L
		var tg2: Vector2 = lib.main.tan_at(sv)
		var rv2 := Vector2(-tg2.y, tg2.x)
		var hv: float = lib.main.w_at(sv) * 0.5
		var pv := _kf(ur, uv, "verge")
		if use_r2:
			pv *= float(r2.get("verge_k", 1.0))               # R2：路肩林下少一點（量移到谷壁土袋；路邊不再每隔幾 m 一叢）
		for side2: float in [-1.0, 1.0]:
			var r_go2 := ru.randf()
			var r_off := ru.randf()
			if r_go2 < pv:
				var cv: Vector2 = lib.main.pos_at(sv) + rv2 * side2 * (hv + lerpf(float(cfg.get("verge_min", 1.7)), 4.2, r_off))
				var made2 := _under_cluster(fp, cfg, UN, cv, uv, ru, 2, 4, wrocks)
				n_under += made2
				under_third[clampi(int(uv * 3.0), 0, 2)] += made2
		sv += ru.randf_range(4.0, 7.0)
	# (c) 岩腳：每顆岩 1–2 叢蕨／灌木
	var n_rockfoot := 0
	for f: Dictionary in fp._foot:
		var fid := String(f["id"])
		var fq: Vector2 = f["p"]
		if fq.y > 20.0 or fq.y < -100.0 or not (fid.contains("rock") or fid.contains("stone_marker")):
			continue
		for t in ru.randi_range(1, 2):
			var cr: Vector2 = fq + Vector2.from_angle(ru.randf() * TAU) * (float(f["r"]) + ru.randf_range(0.4, 1.2))
			var ur_u := clampf((float(lib.main.q(cr)["s"]) - s0) / L, 0.0, 1.0)
			var made3 := _under_cluster(fp, cfg, UN, cr, ur_u, ru, 1, 2, wrocks)
			n_under += made3
			n_rockfoot += made3
	# (d) 籬：沿 layout 指定的線種一排不規則的灌木（田邊、小屋後）
	var n_hedge := 0
	var hedges: Array = (cfg.get("hedges", []) as Array).duplicate()
	if use_r2:
		hedges.append_array(r2.get("hedges", []))
	for hd: Dictionary in hedges:
		var ha: Vector2 = lib.resolve(hd["a"])["p"]
		var hb: Vector2 = lib.resolve(hd["b"])["p"]
		var cnt := int(hd["n"])
		for t2 in cnt:
			var tt := (float(t2) + ru.randf_range(0.1, 0.9)) / float(cnt)
			var hp: Vector2 = ha.lerp(hb, tt) + Vector2(ru.randf_range(-0.7, 0.7), ru.randf_range(-0.7, 0.7))
			var made4 := _under_cluster(fp, cfg, UN, hp, 0.2, ru, 1, 2, wrocks)
			n_under += made4
			n_hedge += made4
	info["under_new"] = n_under
	info["under_by_third"] = under_third
	info["under_rockfoot"] = n_rockfoot
	info["under_hedge"] = n_hedge
	# ---- 3b) R2：25–30 % 過渡的小群（layout 明寫位置＝離路稍遠的小樹＋林下；不是一道樹牆）
	if use_r2:
		info["transition"] = _transition_r2(fp, cfg, r2, SP, UN, s0, L, light, shade, wrocks)
	# ---- 3c) R2：谷壁土袋的植物（算進 380 總量；背景林的稀疏化會把多出來的量扣回去＝把擠在牆頂背景林的量移到牆面）
	var wall_u: Array = []
	if use_r2 and not wall.is_empty():
		var wp := _wall_plants(fp, cfg, r2["wall"], wall, SP, UN, light, shade, L)
		wall_u = wp["_entries"]
		wp.erase("_entries")
		info["wall_plants"] = wp
	# ---- 4) 總量守恆：背景林裡過度擠密的地方，扣到總量回到目標
	var n_s01 := 0
	for t3: Dictionary in fp.trees:
		if String(t3["scene"]) == "S01":
			n_s01 += 1
	var target := int(cfg.get("target_total", 380))
	var need := n_s01 + bd.size() - target
	var cap := int(floor(float(bd.size()) * float(r2.get("drop_max_frac", cfg.get("drop_max_frac", 0.34)))))
	info["total_before_thin"] = n_s01 + bd.size()
	info["thin_need"] = need
	info["thin_cap"] = cap
	var drop_idx := {}
	if need > 0:
		var eyes: Array = []
		var se := s0 - 10.0
		while se <= s1 + 6.0:
			var pe: Vector2 = lib.main.pos_at(clampf(se, 0.0, lib.main.length))
			eyes.append(Vector3(pe.x, lib.h_at(pe.x, pe.y) + 1.7, pe.y))
			se += float(cfg.get("eye_step", 8.0))
		var tcfg := cfg
		if use_r2 and r2.has("thin"):
			tcfg = cfg.duplicate()
			tcfg.merge(r2["thin"], true)                    # R2：背景林稀疏化可放寬『擠密』門檻（天際線守門 thin_sky_eps_deg 不放寬）
		var th := _thin_backdrop(fp, bd, mini(need, cap), eyes, tcfg)
		for i: int in th["drop"]:
			drop_idx[i] = true
		info["thin_dropped"] = (th["drop"] as Array).size()
		info["skyline_max_drop_deg"] = snappedf(float(th["skyline_drop_deg"]), 0.01)
		info["sky_bins_before"] = int(th["coverage_before"])
		info["sky_bins_after"] = int(th["coverage_after"])
	else:
		info["thin_dropped"] = 0
		info["skyline_max_drop_deg"] = 0.0
	var bd_keep: Array = []
	for i in bd.size():
		if not drop_idx.has(i):
			bd_keep.append(bd[i])
	fp._adopt_entries("S01", bd_keep)
	# R2：林下以 loose 模式種，規劃器不看道具腳印；柵欄又只以柱（r 0.9）取樣、柱距最多 4.4 m——灌木可能長在兩柱之間的橫木上、
	# 或田裡／小屋裡。這裡以「柱到柱的線段」與非岩道具的腳印清掉衝突的植物（岩腳的植物是有意的，不清）；清掉的數量由下面的總量回扣補回。
	if use_r2:
		var cut_p := _prop_conflicts(fp)
		info["prop_conflicts_removed"] = cut_p
		if cut_p.size() > 0:
			wall_u = wall_u.filter(func(pe5: Array) -> bool: return fp.trees.has(pe5[1]))
	var n_final := 0
	for t4: Dictionary in fp.trees:
		if String(t4["scene"]) == "S01":
			n_final += 1
	info["total"] = n_final
	# R2：背景林已剪到上限（天際線守門／擠密門檻）還多出來的，從谷壁土袋的植物扣回（總量守恆，不放寬背景林的守門）。
	# 輪流扣：每次從「林下最多的那個土袋」拿一株，所以每個土袋盡量都還留著植物（不會有只有土色、沒有植物的土袋）；
	# 林下都只剩一株時才扣小樹。上限＝min(target, budget_max)：就算有人把 target 拉高，R2 也不會超出植被預算（與 R1 同一性質）。
	var cap_total := mini(target, int(r2.get("budget_max", target))) if use_r2 else target
	if use_r2 and n_final > cap_total and not wall_u.is_empty():
		var cut := 0
		var cut_t := 0
		var by_pk := {}
		for pe0: Array in wall_u:
			var key := "%d_%.2f_%.2f" % [int((pe0[0] as Dictionary)["seed"]), float((pe0[0] as Dictionary)["x"]), float((pe0[0] as Dictionary)["z"])]
			if not by_pk.has(key):
				by_pk[key] = {"pk": pe0[0], "u": [], "t": []}
			(by_pk[key]["u" if String((pe0[1] as Dictionary)["kind"]) == "under" else "t"] as Array).append(pe0[1])
		var keys: Array = by_pk.keys()
		keys.sort()
		while n_final > cap_total:
			# 扣的順序：(1) 林下 ≥ 2 株的土袋拿一株（最多的先）→ (2) 有樹的土袋拿掉林下（土袋仍有樹）
			#          → (3) 只剩一株林下的土袋整個清空（這種土袋之後地表也不畫土）→ (4) 最後才扣小樹（遠看打斷坡面的主要是樹）
			var best_k: Variant = null
			var take_t := false
			var best_n := 1
			for k: Variant in keys:
				var nu := (by_pk[k]["u"] as Array).size()
				if nu > best_n:
					best_n = nu
					best_k = k
			if best_k == null:
				for k2: Variant in keys:
					if (by_pk[k2]["u"] as Array).size() == 1 and not (by_pk[k2]["t"] as Array).is_empty():
						best_k = k2
						break
			if best_k == null:
				for k3: Variant in keys:
					if (by_pk[k3]["u"] as Array).size() == 1:
						best_k = k3
						break
			if best_k == null:
				for k4: Variant in keys:
					if not (by_pk[k4]["t"] as Array).is_empty():
						best_k = k4
						take_t = true
						break
			if best_k == null:
				break
			var lst: Array = by_pk[best_k]["t" if take_t else "u"]
			var ent: Dictionary = lst.pop_back()
			fp.trees.erase(ent)
			var pkd: Dictionary = by_pk[best_k]["pk"]
			pkd["trees" if take_t else "under"] = int(pkd["trees" if take_t else "under"]) - 1
			n_final -= 1
			if take_t:
				cut_t += 1
			else:
				cut += 1
		info["wall_under_trimmed"] = cut
		info["wall_trees_trimmed"] = cut_t
		info["total"] = n_final
	# ---- 5) R2：露根（挑最後留下的、長在坡上的樹）；谷壁點綴整包交給生成器
	if use_r2 and not wall.is_empty():
		wall["roots"] = S01Wall.plan_roots(fp, r2["wall"], zs + salt * 7)
		info["wall"]["roots"] = (wall["roots"] as Array).size()
		wall = S01Wall.apply_r3_fixes(fp, wall, r2["wall"], zs + salt * 7)       # R3：指名岩組修正（植物已種完；植被不連動）
		fp.s01_wall = wall
	if not shade.is_empty():
		info["shade_rejected"] = int(shade["rej"])
		info["shade_edge_lit"] = _shade_report(shade)
	fp.set_meta("s01_groves", groves)                  # 只給審圖探針讀（分布圖的群落中心）；不進任何產物
	return info


## R2：路肩受光守門的最終狀態（每時刻、每 5 m 窗：較亮那一側路肩的受光 %）
static func _shade_report(st: Dictionary) -> Dictionary:
	var out := {}
	var wins := {}
	for k: String in (st["tot"] as Dictionary):
		wins[int(k.split("_")[0])] = true
	var wl: Array = wins.keys()
	wl.sort()
	for hi in (st["suns"] as Array).size():
		var row: Array = []
		for w: int in wl:
			row.append(int(round(100.0 * _shade_best(st, hi, w))))
		out[str(int(st["hours"][hi]))] = row
	out["windows_m"] = wl.map(func(w): return int(w) * int(st["win_len"]))
	return out


## R2 §5：群落編輯（layout r2.groves）：
##   drop＝[{u: [a, b], side}]：中心落在這個進度範圍、這一側的群落標記為不種（索引保留）；
##   push＝[{u: [a, b], side, d, R_k, n_k}]：往離路方向推 d m（讓近路的一串變成有前有後的深度層）、半徑／株數倍率；
##   add＝[{u, side, edge, R, n, why}]：在指定進度、側、離路緣 edge m 加一叢（中心不得在空地或谷壁外，不得和既有群落重疊）。
static func _grove_edits(fp, cfg: Dictionary, gc: Dictionary, groves: Array, s0: float, L: float) -> Dictionary:
	var lib = fp.lib
	var elog := {"drop": [], "push": [], "add": [], "rejected": []}
	for g: Dictionary in groves:
		var u := float(g["u"])
		var side := int(g["side"])
		for d: Dictionary in gc.get("drop", []):
			var ur: Array = d["u"]
			if u >= float(ur[0]) and u <= float(ur[1]) and side == int(d["side"]):
				g["drop"] = true
				(elog["drop"] as Array).append("u%.2f s%+d" % [u, side])
		if bool(g.get("drop", false)):
			continue
		for pu: Dictionary in gc.get("push", []):
			var ur2: Array = pu["u"]
			if u >= float(ur2[0]) and u <= float(ur2[1]) and side == int(pu["side"]):
				var s := s0 + u * L
				var tg: Vector2 = lib.main.tan_at(s)
				var rv := Vector2(-tg.y, tg.x)
				var c2: Vector2 = (g["c"] as Vector2) + rv * float(side) * float(pu.get("d", 0.0))
				var R2 := float(g["R"]) * float(pu.get("R_k", 1.0))
				if fp._clear_dist(c2) < 0.0 or lib.mask_sdf(c2) > 0.0:
					(elog["rejected"] as Array).append("push u%.2f s%+d：推出去落在空地或谷壁外" % [u, side])
					continue
				g["c"] = c2
				g["R"] = R2
				g["n"] = int(roundf(float(g["n"]) * float(pu.get("n_k", 1.0))))
				(elog["push"] as Array).append("u%.2f s%+d +%.1fm R×%.2f n→%d" % [u, side, float(pu.get("d", 0.0)), float(pu.get("R_k", 1.0)), int(g["n"])])
	for a: Dictionary in gc.get("add", []):
		var u3 := float(a["u"])
		var s3 := s0 + u3 * L
		var side3 := int(a["side"])
		var tg3: Vector2 = lib.main.tan_at(s3)
		var rv3 := Vector2(-tg3.y, tg3.x)
		var R3 := float(a["R"])
		var c3: Vector2 = lib.main.pos_at(s3) + rv3 * float(side3) * (lib.main.w_at(s3) * 0.5 + float(a["edge"]) + R3 * 0.35)
		var bad := ""
		if fp._clear_dist(c3) < 0.0:
			bad = "中心在空地"
		elif lib.mask_sdf(c3) > 0.0:
			bad = "中心在谷壁外"
		else:
			for g2: Dictionary in groves:
				if bool(g2.get("drop", false)):
					continue
				if c3.distance_to(g2["c"]) < (float(g2["R"]) + R3) * float(cfg.get("grove_overlap_k", 0.55)) + float(cfg.get("grove_gap", 1.5)):
					bad = "和 u%.2f 的群落重疊" % float(g2["u"])
					break
		if bad != "":
			(elog["rejected"] as Array).append("add u%.2f s%+d：%s" % [u3, side3, bad])
			continue
		groves.append({"c": c3, "R": R3, "n": int(a["n"]), "u": u3, "side": float(side3), "x": 0.5, "added": true})
		(elog["add"] as Array).append("u%.2f s%+d edge%.1f R%.1f n%d" % [u3, side3, float(a["edge"]), R3, int(a["n"])])
	return elog


## R2 §6：25–30 % 過渡（layout r2.transition）：每組＝離路 off m 的一個小點，種 trees 棵小樹＋under 株林下。
## 規則與群落相同（禁區、路緣淨空、樹距、路面受光守門），只是位置是明寫的（藝術指定），亂數只管細部。
static func _transition_r2(fp, cfg: Dictionary, r2: Dictionary, SP: Dictionary, UN: Dictionary, s0: float, L: float, light: Dictionary, shade: Dictionary, wrocks: Array) -> Array:
	var lib = fp.lib
	var zones: Array = cfg["zones"]
	var out: Array = []
	var k := 0
	for tr: Dictionary in r2.get("transition", []):
		var rt := _rng(int(fp.zone_seed("S01")) * 7 + 9001 + k * 131)
		k += 1
		var u := float(tr["u"])
		var c := _from_frame(lib, s0 + u * L, float(tr["side"]) * float(tr["off"]))
		var got_t := 0
		var tries := 0
		var want_t := int(tr.get("trees", 0))
		while got_t < want_t and tries < 24:
			tries += 1
			var p := c + Vector2.from_angle(rt.randf() * TAU) * rt.randf_range(0.0, float(tr.get("r", 2.0)))
			var spn := String(tr.get("sp", "sapling"))
			var spec: Dictionary = SP[spn]
			var id := _pick(spec["v"], rt)
			var sc := lerpf(float(spec["s"][0]), float(spec["s"][1]), rt.randf()) * float(tr.get("scale_k", 1.0))
			var yaw := rt.randf() * TAU
			var lean_r := rt.randf()
			var rt2 := float((fp.kit[id] as Dictionary)["r"]) * sc
			if lib.scene_id_of_z(p.y) != "S01" or fp._blocked(p, rt2, true) or _rock_clear(wrocks, p) < rt2 + 0.6:
				continue
			var dedge: float = lib.sample_arr(lib.DM, p.x, p.y) - lib.sample_arr(lib.WM, p.x, p.y)
			if dedge < _kf(zones, u, "clear") + rt2:
				continue
			var gap := maxf(float(spec["gap"]) * 0.8, 1.7)
			if fp._too_close(p, gap, "t", rt2):
				continue
			var crw := _crown(fp, id, sc, p.x, lib.h_at(p.x, p.y), p.y)
			if not _light_ok(light, cfg, crw[0], float(crw[1]), L):
				continue
			if not shade.is_empty() and not _shade_ok(shade, crw[0], float(crw[1])):
				continue
			_light_commit(light, crw[0], float(crw[1]))
			if not shade.is_empty():
				_shade_commit(shade, crw[0], float(crw[1]))
			fp._add_tree(id, p, sc, yaw, "tree", "")
			fp._register(p, rt2, gap, "t")
			_lean(fp.trees[fp.trees.size() - 1], c, p, lean_r, cfg, 0.8)
			got_t += 1
		var got_u := 0
		var tries_u := 0
		var want_u := int(tr.get("under", 0))
		while got_u < want_u and tries_u < 8:
			tries_u += 1
			var cu := c + Vector2.from_angle(rt.randf() * TAU) * rt.randf_range(0.6, float(tr.get("r", 2.0)) + 1.2)
			got_u += _under_cluster(fp, cfg, UN, cu, u, rt, 1, mini(3, want_u - got_u), wrocks)
		out.append({"why": String(tr.get("why", "")), "u": u, "side": int(tr["side"]), "trees": got_t, "under": got_u})
	return out


## R2 §4：谷壁土袋的植物。每袋 0–2 棵小樹（幼樹／小楓／小闊葉）＋2–4 株林下；長在土袋圓內、坡度 ≤ 48°、避開岩。
## 坡上的植物不完全垂直：林下隨坡面法線傾一點（坡度的 0.35 倍、上限 16°），小樹朝下坡（朝光）微傾 1–4°。
static func _wall_plants(fp, cfg: Dictionary, wc: Dictionary, wall: Dictionary, SP: Dictionary, UN: Dictionary, light: Dictionary, shade: Dictionary, L: float) -> Dictionary:
	var lib = fp.lib
	var rocks: Array = wall["rocks"]
	var ps: Dictionary = wc.get("pocket_species", {"sapling": 0.6, "maple": 0.2, "broadleaf": 0.2})
	var pu: Dictionary = wc.get("pocket_under", {"shrub_a": 0.3, "fern_a": 0.3, "sasa_a": 0.25, "tsutsuji_a": 0.15})
	var tw: Array = wc.get("pocket_trees", [0, 1, 1, 2])
	var tsc: Array = wc.get("pocket_tree_scale", [0.62, 0.9])
	var usc: Array = wc.get("pocket_under_scale", [1.0, 1.45])
	var max_sl := float(wc.get("plant_slope_max", 48.0))
	var n_t := 0
	var n_u := 0
	var rej := {"slope": 0, "blocked": 0, "rock": 0, "close": 0, "light": 0}
	var u_entries: Array = []
	for pk: Dictionary in wall["pockets"]:
		var rp := _rng(int(pk["seed"]))
		var c: Vector2 = pk["c"]
		var R := float(pk["R"])
		var ledge := bool(pk.get("ledge", false))
		var want_t := int(tw[rp.randi_range(0, tw.size() - 1)])
		var un_r: Array = wc.get("pocket_under_n", [2, 4])
		var want_u := rp.randi_range(int(un_r[0]), int(un_r[1]))
		# 岩後的土（ledge）：陡坡上岩擋住的一小塊土——只長 1–3 株林下、偶爾一棵小幼樹；坡度上限放寬到 ledge_slope_max（土是岩撐住的）
		var sl_max := max_sl
		var rock_gap := 0.25
		var tsc_k := 1.0
		# 看得到的坡面（面向主路的那一面）上的土袋：樹多一棵、正常大小——遠看（50–60 m）時能打斷大面坡的是樹冠，不是 1 m 的灌木
		if not ledge and float(pk.get("vis", 0.0)) >= float(wc.get("vis_pocket_min", 2.0)):
			want_t = mini(want_t + 1, 2)
			tsc_k = float(wc.get("vis_pocket_tree_k", 1.0))
		if ledge:
			var gully := bool(pk.get("gully", false))
			want_t = 1 if rp.randf() < float(wc.get("gully_tree_p" if gully else "ledge_tree_p", 0.0)) else 0
			want_u = rp.randi_range(1, 2) if gully else 1
			sl_max = float(wc.get("ledge_slope_max", 64.0))
			rock_gap = 0.05
		var got_t := 0
		var tries := 0
		var mem: Array = []
		while got_t < want_t and tries < want_t * 14:
			tries += 1
			var q := c + Vector2.from_angle(rp.randf() * TAU) * R * sqrt(rp.randf()) * 0.8
			var spn := _pick(ps, rp)
			var spec: Dictionary = SP[spn]
			var id := _pick(spec["v"], rp)
			var sc := lerpf(float(spec["s"][0]), float(spec["s"][1]), rp.randf()) * lerpf(float(tsc[0]), float(tsc[1]), rp.randf()) * tsc_k
			var yaw := rp.randf() * TAU
			var lr := rp.randf()
			if ledge:
				sc *= 0.8
			var rt2 := float((fp.kit[id] as Dictionary)["r"]) * sc
			if lib.slope_deg_at(q.x, q.y) > sl_max:
				rej["slope"] += 1
				continue
			if lib.scene_id_of_z(q.y) != "S01" or fp._blocked(q, rt2, true):
				rej["blocked"] += 1
				continue
			if _rock_clear(rocks, q) < rt2 + (0.15 if ledge else 0.6):
				rej["rock"] += 1
				continue
			var gap := maxf(float(spec["gap"]) * 0.7, 1.8)
			if fp._too_close(q, gap, "t", rt2):
				rej["close"] += 1
				continue
			var crw := _crown(fp, id, sc, q.x, lib.h_at(q.x, q.y), q.y)
			if not _light_ok(light, cfg, crw[0], float(crw[1]), L) or (not shade.is_empty() and not _shade_ok(shade, crw[0], float(crw[1]))):
				rej["light"] += 1
				continue
			_light_commit(light, crw[0], float(crw[1]))
			if not shade.is_empty():
				_shade_commit(shade, crw[0], float(crw[1]))
			fp._add_tree(id, q, sc, yaw, "tree", "")
			fp._register(q, rt2, gap, "t")
			u_entries.append([pk, fp.trees[fp.trees.size() - 1]])
			var g := S01Wall.grad(lib, q)
			var dd := (-g).normalized() if g.length() > 1e-4 else Vector2(0, 1)
			fp.trees[fp.trees.size() - 1]["lean"] = [dd.y, -dd.x, deg_to_rad(lerpf(4.0, 9.0, lr) if ledge else lerpf(1.0, 4.0, lr))]   # 岩縫裡的樹朝外（朝光）傾得多一點
			mem.append(q)
			got_t += 1
			n_t += 1
		var got_u := 0
		var tries_u := 0
		while got_u < want_u and tries_u < want_u * 10:
			tries_u += 1
			var q2 := c + Vector2.from_angle(rp.randf() * TAU) * R * pow(rp.randf(), 0.7)
			if not mem.is_empty() and rp.randf() < 0.5:
				q2 = (mem[rp.randi_range(0, mem.size() - 1)] as Vector2) + Vector2.from_angle(rp.randf() * TAU) * rp.randf_range(0.8, 1.8)
			var id2 := _pick(pu, rp)
			var sc2 := lerpf(float(usc[0]), float(usc[1]), rp.randf())
			var yaw2 := rp.randf() * TAU
			var sl: float = lib.slope_deg_at(q2.x, q2.y)
			if sl > sl_max + 2.0:
				rej["slope"] += 1
				continue
			if lib.scene_id_of_z(q2.y) != "S01" or fp._blocked(q2, 0.1, true) or fp._too_close(q2, 0.75, "u"):
				rej["blocked"] += 1
				continue
			if _rock_clear(rocks, q2) < rock_gap:
				rej["rock"] += 1
				continue
			fp._add_tree(id2, q2, sc2, yaw2, "under", "")
			fp._register(q2, 0.05, 0.75, "u")
			u_entries.append([pk, fp.trees[fp.trees.size() - 1]])
			var g2 := S01Wall.grad(lib, q2)
			var dd2 := (-g2).normalized() if g2.length() > 1e-4 else Vector2(0, 1)
			fp.trees[fp.trees.size() - 1]["lean"] = [dd2.y, -dd2.x, deg_to_rad(minf(sl * 0.35, 16.0))]
			got_u += 1
			n_u += 1
		pk["trees"] = got_t
		pk["under"] = got_u
	return {"trees": n_t, "under": n_u, "rejected": rej, "_entries": u_entries}


## 背景林稀疏：只剪『過度擠密』的地方，而且剪了不能讓天際線缺角。
##   · 只考慮離谷緣夠遠（thin_min_sdf）的樹——谷底上看到的牆腳林帶不動；
##   · 每棵背景樹數『平面上 thin_pack_r m 內還有幾棵背景樹』（＝樹冠互相疊住的程度）；一次剪一棵，優先剪鄰居最多的，
##     鄰居數 < thin_min_neighbors 就停（稀疏的地方一棵都不剪），剪完立刻更新鄰居數，所以不會把同一塊剪出洞；
##   · 天際線否決：從路上每個眼點（沿路每 eye_step m 一個、離地 1.7 m）看，每 1° 方位的最高樹冠頂仰角叫『天際線』。
##     候選樹若是某個 (眼點, 方位) 目前的最高樹冠、而剪掉後該處天際線相對『原版』降幅會超過 thin_sky_eps_deg，就不剪（改試下一棵）。
##     所以全部剪完之後，任何眼點任何方位的天際線降幅 ≤ thin_sky_eps_deg（累積值，不是逐棵值）——這是保證，不是事後量到的。
## 回傳 {drop: [bd 的索引…], skyline_drop_deg, coverage_before, coverage_after}
static func _thin_backdrop(fp, bd: Array, need: int, eyes: Array, cfg: Dictionary) -> Dictionary:
	var lib = fp.lib
	var n := bd.size()
	var ne := eyes.size()
	var pack_r := float(cfg.get("thin_pack_r", 6.0))
	var min_sdf := float(cfg.get("thin_min_sdf", 12.0))
	var min_nb := int(cfg.get("thin_min_neighbors", 3))
	var eps := deg_to_rad(float(cfg.get("thin_sky_eps_deg", 2.0)))
	var floor_a := -0.5
	var w_k := float(cfg.get("crown_w_k", 0.75))
	var px := PackedFloat32Array()
	var pz := PackedFloat32Array()
	var sdf := PackedFloat32Array()
	px.resize(n)
	pz.resize(n)
	sdf.resize(n)
	for i in n:
		var e: Dictionary = bd[i]
		px[i] = float(e["x"])
		pz[i] = float(e["z"])
		sdf[i] = lib.mask_sdf(Vector2(px[i], pz[i]))
	# 每棵樹在每個眼點的：樹冠頂仰角 A、方位格範圍 B0..B1；每個 (眼點, 方位格) 蓋到哪些樹
	var A := PackedFloat32Array()
	var B0 := PackedInt32Array()
	var B1 := PackedInt32Array()
	A.resize(n * ne)
	B0.resize(n * ne)
	B1.resize(n * ne)
	var bin_trees: Array = []
	bin_trees.resize(ne * 360)
	for q in ne * 360:
		bin_trees[q] = []
	var sky0 := PackedFloat32Array()
	sky0.resize(ne * 360)
	sky0.fill(-10.0)
	for i2 in n:
		var e2: Dictionary = bd[i2]
		var k: Dictionary = fp.kit[String(e2["id"])]
		var sc := float(e2["s"])
		var top := float(e2["y"]) + float(k["h"]) * sc
		var hwc := maxf(float(k["wx"]) * sc * 0.5 * w_k, 0.6)
		for j in ne:
			var ey: Vector3 = eyes[j]
			var dx := px[i2] - ey.x
			var dz := pz[i2] - ey.z
			var d := maxf(sqrt(dx * dx + dz * dz), 0.5)
			var th := atan2(dx, dz)
			var dl := atan2(hwc, d)
			var a := atan2(top - ey.y, d)
			var idx := i2 * ne + j
			A[idx] = a
			B0[idx] = int(floor(rad_to_deg(th - dl)))
			B1[idx] = int(floor(rad_to_deg(th + dl)))
			for bb in range(B0[idx], B1[idx] + 1):
				var bi := j * 360 + posmod(bb, 360)
				(bin_trees[bi] as Array).append(i2)
				sky0[bi] = maxf(sky0[bi], a)
	var nb := PackedInt32Array()
	nb.resize(n)
	for i3 in n:
		var c := 0
		for j2 in n:
			if j2 != i3 and Vector2(px[i3] - px[j2], pz[i3] - pz[j2]).length() < pack_r:
				c += 1
		nb[i3] = c
	var alive := PackedByteArray()
	alive.resize(n)
	alive.fill(1)
	var dropped: Array = []
	var vetoed := 0
	while dropped.size() < need:
		var cand: Array = []
		for i4 in n:
			if alive[i4] == 1 and sdf[i4] >= min_sdf and nb[i4] >= min_nb:
				cand.append(i4)
		if cand.is_empty():
			break
		cand.sort_custom(func(x: int, y: int) -> bool: return nb[x] > nb[y] or (nb[x] == nb[y] and x < y))
		var pick := -1
		for ci: int in cand:
			if _skyline_loss(ci, ne, A, B0, B1, bin_trees, alive, sky0, floor_a) <= eps:
				pick = ci
				break
			vetoed += 1
		if pick < 0:
			break
		alive[pick] = 0
		dropped.append(pick)
		for j3 in n:
			if alive[j3] == 1 and Vector2(px[pick] - px[j3], pz[pick] - pz[j3]).length() < pack_r:
				nb[j3] -= 1
	# 量測：剪完後的最大天際線降幅（應 ≤ eps）與有樹冠覆蓋的方位格數
	var worst := 0.0
	var cov0 := 0
	var cov1 := 0
	for bi2 in ne * 360:
		if sky0[bi2] <= -9.0:
			continue
		cov0 += 1
		var top1 := floor_a
		var any := false
		for kk: int in (bin_trees[bi2] as Array):
			if alive[kk] == 1:
				any = true
				top1 = maxf(top1, A[kk * ne + bi2 / 360])
		if any:
			cov1 += 1
		worst = maxf(worst, sky0[bi2] - top1)
	return {"drop": dropped, "skyline_drop_deg": rad_to_deg(worst), "coverage_before": cov0, "coverage_after": cov1, "vetoed": vetoed}


## 候選樹 i 若被剪掉，天際線相對『原版』的最大降幅（rad）。只有『i 是該 (眼點, 方位格) 目前的最高樹冠』的格子會變。
static func _skyline_loss(i: int, ne: int, A: PackedFloat32Array, B0: PackedInt32Array, B1: PackedInt32Array, bin_trees: Array, alive: PackedByteArray, sky0: PackedFloat32Array, floor_a: float) -> float:
	var worst := 0.0
	for j in ne:
		var idx := i * ne + j
		var a_i := A[idx]
		for bb in range(B0[idx], B1[idx] + 1):
			var bi := j * 360 + posmod(bb, 360)
			var top_alive := floor_a
			var best_other := floor_a
			for k: int in (bin_trees[bi] as Array):
				if alive[k] == 0:
					continue
				var ak := A[k * ne + j]
				top_alive = maxf(top_alive, ak)
				if k != i:
					best_other = maxf(best_other, ak)
			if a_i >= top_alive - 1e-6:
				worst = maxf(worst, sky0[bi] - best_other)
	return worst


## 在 c 附近種 lo..hi 株林下（灌木／蕨／笹／杜鵑）。避開禁區（loose：不受空地限制）與已有的東西，只收 S01。回傳實際種了幾株。
static func _under_cluster(fp, cfg: Dictionary, UN: Dictionary, c: Vector2, u: float, rng: RandomNumberGenerator, lo: int, hi: int, avoid: Array = []) -> int:
	var m := rng.randi_range(lo, hi)
	var made := 0
	# 隨進度改變偏好：村緣灌木／杜鵑，林內蕨與笹
	var w := {}
	var fern_k := smoothstep(0.25, 0.8, u)
	for k: String in UN:
		var wk := float(UN[k])
		match k:
			"fern_a": wk *= lerpf(0.5, 1.7, fern_k)
			"sasa_a": wk *= lerpf(0.3, 1.1, fern_k)
			"shrub_a": wk *= lerpf(1.5, 0.9, fern_k)
			"tsutsuji_a": wk *= lerpf(1.3, 0.8, fern_k)
		w[k] = wk
	for i in m:
		var q := c + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		var id := _pick(w, rng)
		var s := rng.randf_range(0.8, 1.3)
		var yaw := rng.randf() * TAU
		if fp.lib.scene_id_of_z(q.y) != "S01" or fp._blocked(q, 0.1, true) or fp._too_close(q, 0.75, "u"):
			continue
		if not avoid.is_empty() and _rock_clear(avoid, q) < 0.25:
			continue                                    # R2：不長進谷壁岩裡
		var dedge: float = fp.lib.sample_arr(fp.lib.DM, q.x, q.y) - fp.lib.sample_arr(fp.lib.WM, q.x, q.y)
		if dedge < float(cfg.get("verge_min", 1.7)) * 0.8:
			continue
		fp._add_tree(id, q, s, yaw, "under", "")
		fp._register(q, 0.05, 0.75, "u")
		made += 1
	return made


## 微傾（生長方向）：約 lean_frac 的樹有傾斜，最大 lean_max_deg；群落邊緣的樹往外（朝光）傾，加一點隨機。
## lean＝[軸x, 軸z, 角度 rad]（軸在水平面、世界座標；傾向＝(d.x, d.y)）。r＝這棵樹的亂數（0~1），用來決定要不要傾、傾多少、方向偏移。
static func _lean(t: Dictionary, c: Vector2, p: Vector2, r: float, cfg: Dictionary, k: float) -> void:
	var frac := float(cfg.get("lean_frac", 0.6))
	if r > frac:
		return
	var f := r / maxf(frac, 1e-6)                           # 0~1，在『有傾』的樹之間均勻
	var d := p - c
	if d.length() < 0.5:
		d = Vector2.from_angle(f * TAU)
	d = d.normalized()
	d = (d + Vector2.from_angle(fposmod(f * 977.0, 1.0) * TAU) * 0.45).normalized()
	var ang := deg_to_rad(lerpf(0.8, float(cfg.get("lean_max_deg", 4.5)), fposmod(f * 313.0, 1.0))) * k
	t["lean"] = [d.y, -d.x, ang]


## R2：與柵欄（柱到柱的線段）或非岩道具腳印衝突的 S01 植物（林下、樹；釘點／地標不動），從規劃移除。回傳被移除的摘要
static func _prop_conflicts(fp) -> Array:
	var segs: Array = []
	var discs: Array = []
	var groups := {}
	for f: Dictionary in fp._foot:
		var fid := String(f["id"])
		if fid.begins_with("fence"):
			var k := fid.rfind("_")
			var g := fid.substr(0, k)
			if not groups.has(g):
				groups[g] = []
			(groups[g] as Array).append([int(fid.substr(k + 1)), f["p"] as Vector2])
		elif not fid.contains("rock") and not fid.contains("stone"):
			discs.append([fid, f["p"] as Vector2, float(f["r"])])
	for g2: String in groups:
		var lst: Array = groups[g2]
		lst.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
		for i in range(lst.size() - 1):
			segs.append([g2, lst[i][1], lst[i + 1][1]])
	var out: Array = []
	var keep: Array = []
	for t: Dictionary in fp.trees:
		var kd := String(t["kind"])
		if String(t["scene"]) != "S01" or (kd != "under" and kd != "tree"):
			keep.append(t)
			continue
		var p := Vector2(float(t["x"]), float(t["z"]))
		var rr := float((fp.kit[String(t["id"])] as Dictionary)["r"]) * float(t["s"])
		var need := (maxf(rr, 0.6) + 0.35) if kd == "under" else (rr + 0.3)
		var why := ""
		for s: Array in segs:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, s[1], s[2])) < need:
				why = String(s[0])
				break
		if why == "":
			for d: Array in discs:
				if p.distance_to(d[1]) >= float(d[2]) + (0.0 if float(d[2]) > 5.0 else need):
					continue
				if float(d[2]) > 5.0:
					# 大範圍（田）用圓近似；植物和田心之間隔著柵欄＝在柵外（路側），不算在田裡
					var fenced := false
					for s2: Array in segs:
						if Geometry2D.segment_intersects_segment(p, d[1], s2[1], s2[2]) != null:
							fenced = true
							break
					if fenced:
						continue
				why = String(d[0])
				break
		if why != "":
			out.append("%s@%.1f,%.1f×%s" % [String(t["id"]), p.x, p.y, why])
		else:
			keep.append(t)
	if out.size() > 0:
		fp.trees.clear()
		fp.trees.append_array(keep)
	return out
