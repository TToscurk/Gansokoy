extends RefCounted
## 獸道 共用幾何庫（V0.1 白模）。產生器 / 驗證器 / 走訪 / 審圖共用同一份，不各寫一套。
##
##   const BP := preload("res://tools/beast_path/bp_lib.gd")
##   var lib := BP.new(); lib.setup()          # 讀 layout → 建路徑場 → 烘焙 1 m 高度晶格
##
## 座標：x 東、z 南、+y 上；主路由南往北（−z）。off＞0＝行進方向右側。
## 地形 = 主路山谷基底 + 雜訊 + 丘陵 + 玩區外牆 + 崖 + 台地 + 主路路廊 + 支線路廊 + 溪谷切割。
## 高度唯一來源是烘焙晶格：網格頂點、樹/道具落地、驗證器取高度都走 h_at()（與網格同一三角剖分），
## 不再各自重算 → 接縫（共用頂點）與落地位置必然一致。

const LAYOUT_PATH := "res://tools/beast_path/layout_beast_path.json"

# ---------------------------------------------------------------- 資料
var L: Dictionary = {}
var main: Poly
var branches: Dictionary = {}
var streams: Dictionary = {}
var rects: Array = []                 # [{id, rect: Rect2, tile: Rect2, corner}]
var _mounds: Array = []
var _terraces: Array = []
var _cliffs: Array = []
var _cm_last := 0.0        # 最近一次 _h_base() 的崖遮罩（0~1）；河岸錐形上限用它淡出
var _noise1 := FastNoiseLite.new()
var _noise2 := FastNoiseLite.new()
var _wander_n := FastNoiseLite.new()
var _wobble_n := FastNoiseLite.new()
var _leaf_n := FastNoiseLite.new()
var _gn1 := FastNoiseLite.new()     # S04 地表（V1.1）：約 28 m 尺度
var _gn2 := FastNoiseLite.new()     # 約 9 m
var _gn3 := FastNoiseLite.new()     # 約 2.4 m
var _gn4 := FastNoiseLite.new()     # 落葉堆／碎石斑（約 6 m）
var _gn5 := FastNoiseLite.new()     # 沿方位的起伏（頻率 1，取單位圓座標）

# 烘焙晶格（含 2 格外圈，供法線）
var cell := 1.0
var lx0 := 0.0
var lz0 := 0.0
var nx := 0
var nz := 0
var H := PackedFloat32Array()
var DM := PackedFloat32Array()        # 到主路中心線的距離
var WM := PackedFloat32Array()        # 主路半寬
var DB := PackedFloat32Array()        # 支線：離路緣距離（d − 半寬）最小值
var DS := PackedFloat32Array()        # 溪：離水緣距離（d − 半寬）最小值
var PV := PackedFloat32Array()        # 鋪石權重
var baked := false

# 臨界值（layout.limits 的快取）
var lim: Dictionary = {}


# ================================================================= Poly
class Poly:
	var id := ""
	var kind := ""
	var ctrl_id: Array = []
	var ctrl_s := PackedFloat32Array()
	var pts := PackedVector2Array()
	var s := PackedFloat32Array()
	var w := PackedFloat32Array()      # 全寬
	var y := PackedFloat32Array()      # 中心線高度
	var bed := PackedFloat32Array()    # 溪床高度
	var curve := Curve2D.new()
	var length := 0.0
	var bbox := Rect2()

	func finalize() -> void:
		curve.clear_points()
		curve.bake_interval = 0.5
		for p in pts:
			curve.add_point(p)
		var mn := pts[0]
		var mx := pts[0]
		for p in pts:
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
		bbox = Rect2(mn, mx - mn)

	func fidx(s_: float) -> float:
		return clampf(s_, 0.0, length)

	func _lerp_arr(a: PackedFloat32Array, s_: float) -> float:
		if a.size() == 0:
			return 0.0
		# s[] は累積弦長（≈1 m 間隔）。二分探索で区間を引く
		var v := fidx(s_)
		var lo := 0
		var hi := a.size() - 1
		while hi - lo > 1:
			var mid := (lo + hi) >> 1
			if s[mid] <= v:
				lo = mid
			else:
				hi = mid
		var den := s[hi] - s[lo]
		var t := 0.0 if den < 1e-6 else (v - s[lo]) / den
		return lerpf(a[lo], a[hi], t)

	func pos_at(s_: float) -> Vector2:
		var v := fidx(s_)
		var lo := 0
		var hi := pts.size() - 1
		while hi - lo > 1:
			var mid := (lo + hi) >> 1
			if s[mid] <= v:
				lo = mid
			else:
				hi = mid
		var den := s[hi] - s[lo]
		var t := 0.0 if den < 1e-6 else (v - s[lo]) / den
		return pts[lo].lerp(pts[hi], t)

	func tan_at(s_: float) -> Vector2:
		var a := pos_at(maxf(s_ - 1.5, 0.0))
		var b := pos_at(minf(s_ + 1.5, length))
		var d := b - a
		if d.length() < 1e-6:
			return Vector2(0, -1)
		return d.normalized()

	func w_at(s_: float) -> float:
		return _lerp_arr(w, s_)

	func y_at(s_: float) -> float:
		return _lerp_arr(y, s_)

	func bed_at(s_: float) -> float:
		return _lerp_arr(bed, s_)

	func q(p: Vector2) -> Dictionary:
		var off := curve.get_closest_offset(p)
		var cp := curve.sample_baked(off)
		var t := tan_at(off)
		var dv := p - cp
		return {"s": off, "d": dv.length(), "off": dv.dot(Vector2(-t.y, t.x)), "pos": cp, "tan": t}


# ================================================================= 小工具
static func smin(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return minf(a, b)
	var hh := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - hh * hh * k * 0.25


static func right_of(t: Vector2) -> Vector2:
	return Vector2(-t.y, t.x)


static func yaw_of(t: Vector2) -> float:
	## 物件本地 −Z 指向行進方向 t 時的 Y 旋轉（與玩家 yaw 慣例相同）
	return atan2(-t.x, -t.y)


static func cr_dense(P: Array, per_seg: int = 24) -> Dictionary:
	var n := P.size()
	var ext: Array = []
	ext.append((P[0] as Vector2) * 2.0 - (P[1] as Vector2))
	for p in P:
		ext.append(p)
	ext.append((P[n - 1] as Vector2) * 2.0 - (P[n - 2] as Vector2))
	var out := PackedVector2Array()
	var cidx := PackedInt32Array()
	for i in range(1, n):
		var p0: Vector2 = ext[i - 1]
		var p1: Vector2 = ext[i]
		var p2: Vector2 = ext[i + 1]
		var p3: Vector2 = ext[i + 2]
		cidx.append(out.size())
		for k in per_seg:
			var t := float(k) / float(per_seg)
			var t2 := t * t
			var t3 := t2 * t
			out.append(((p1 * 2.0) + (p2 - p0) * t + (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2 + (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3) * 0.5)
	cidx.append(out.size())
	out.append(P[n - 1])
	return {"pts": out, "cidx": cidx}


static func cum_len(pts: PackedVector2Array) -> PackedFloat32Array:
	var c := PackedFloat32Array()
	c.resize(pts.size())
	var acc := 0.0
	c[0] = 0.0
	for i in range(1, pts.size()):
		acc += pts[i - 1].distance_to(pts[i])
		c[i] = acc
	return c


static func resample(pts: PackedVector2Array, cum: PackedFloat32Array, step: float) -> PackedVector2Array:
	var L_ := cum[cum.size() - 1]
	var out := PackedVector2Array()
	var j := 0
	var t := 0.0
	while t < L_:
		while j < cum.size() - 2 and cum[j + 1] < t:
			j += 1
		var seg := cum[j + 1] - cum[j]
		var u := 0.0 if seg < 1e-9 else (t - cum[j]) / seg
		out.append(pts[j].lerp(pts[j + 1], u))
		t += step
	out.append(pts[pts.size() - 1])
	return out


## PCHIP（Fritsch–Carlson）：高程剖面用，不過衝、斜率連續
static func pchip_eval(xs: PackedFloat32Array, ys: PackedFloat32Array, x: float) -> float:
	var n := xs.size()
	if x <= xs[0]:
		return ys[0]
	if x >= xs[n - 1]:
		return ys[n - 1]
	var dk := PackedFloat32Array()
	dk.resize(n - 1)
	for i in n - 1:
		dk[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i])
	var m := PackedFloat32Array()
	m.resize(n)
	m[0] = dk[0]
	m[n - 1] = dk[n - 2]
	for i in range(1, n - 1):
		if dk[i - 1] * dk[i] <= 0.0:
			m[i] = 0.0
		else:
			var h0 := xs[i] - xs[i - 1]
			var h1 := xs[i + 1] - xs[i]
			var w1 := 2.0 * h1 + h0
			var w2 := h1 + 2.0 * h0
			m[i] = (w1 + w2) / (w1 / dk[i - 1] + w2 / dk[i])
	var k := 0
	while k < n - 2 and xs[k + 1] < x:
		k += 1
	var h := xs[k + 1] - xs[k]
	var t := (x - xs[k]) / h
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * ys[k] + (t3 - 2.0 * t2 + t) * h * m[k] + (-2.0 * t3 + 3.0 * t2) * ys[k + 1] + (t3 - t2) * h * m[k + 1]


# ================================================================= 載入 / 建場
func setup(do_bake: bool = true, use_cache: bool = true) -> void:
	load_layout()
	_build_ground_features()
	build_fields()
	if _bake_branch_y_pending:
		bake_branch_y()
	if not do_bake:
		return
	if use_cache and load_cache():
		return
	bake()
	if use_cache:
		save_cache()


const CACHE_PATH := "user://beast_path_lattice.bin"


func _cache_key() -> String:
	return (FileAccess.get_file_as_string(LAYOUT_PATH) + FileAccess.get_file_as_string("res://tools/beast_path/bp_lib.gd")).sha256_text()


func save_cache() -> void:
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_pascal_string(_cache_key())
	f.store_32(nx)
	f.store_32(nz)
	for arr: PackedFloat32Array in [H, DM, WM, DB, DS, PV]:
		f.store_buffer(arr.to_byte_array())
	f.close()


func load_cache() -> bool:
	if not FileAccess.file_exists(CACHE_PATH):
		return false
	var f := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if f == null or f.get_pascal_string() != _cache_key():
		return false
	setup_lattice()
	if f.get_32() != nx or f.get_32() != nz:
		return false
	var sz := nx * nz * 4
	var arrs: Array = []
	for k in 6:
		arrs.append(f.get_buffer(sz).to_float32_array())
	H = arrs[0]
	DM = arrs[1]
	WM = arrs[2]
	DB = arrs[3]
	DS = arrs[4]
	PV = arrs[5]
	baked = true
	print("[bake] 讀快取 %d x %d" % [nx, nz])
	return true


func load_layout(path: String = LAYOUT_PATH) -> void:
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	assert(parsed is Dictionary, "layout JSON 讀不到或不是 Dictionary：%s" % path)
	L = parsed
	lim = L.get("limits", {})
	var seed_ := int(L["frame"]["seed"])
	var tn: Dictionary = L["terrain"]["noise"]
	_noise1.seed = seed_
	_noise1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise1.frequency = float(tn["freq"])
	_noise2.seed = seed_ + 17
	_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise2.frequency = float(tn["freq2"])
	var mp: Dictionary = L["main_path"]
	_wander_n.seed = int(mp["wander"]["seed"])
	_wander_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_wander_n.frequency = 1.0
	_wobble_n.seed = seed_ + 3
	_wobble_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_wobble_n.frequency = 1.0
	_leaf_n.seed = seed_ + 29
	_leaf_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_leaf_n.frequency = 0.05
	var gns: Array = [_gn1, _gn2, _gn3, _gn4, _gn5]
	var gfq: Array = [0.035, 0.11, 0.42, 0.16, 1.0]
	for k in 5:
		var gn: FastNoiseLite = gns[k]
		gn.seed = seed_ + 101 + 13 * k
		gn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		gn.frequency = float(gfq[k])
	rects.clear()
	for sc: Dictionary in L["scenes"]:
		var r: Array = sc["play_rect"]
		var t: Array = sc["tile"]
		rects.append({"id": sc["id"], "rect": Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1])),
			"tile": Rect2(float(t[0]), float(t[1]), float(t[2]) - float(t[0]), float(t[3]) - float(t[1]))})


func build_fields() -> void:
	main = _build_main()
	_build_macro()
	branches.clear()
	for b: Dictionary in L["branches"]:
		branches[b["id"]] = _build_branch(b)
	_resolve_features()
	bake_branch_y()                    # 支線高度只依賴主路與地形特徵（stage 2）
	streams.clear()
	for sd: Dictionary in L["streams"]:
		streams[sd["id"]] = _build_stream(sd)


var _bake_branch_y_pending := false


func _station_ctrl_index(name: String) -> int:
	var pts: Array = L["main_path"]["points"]
	for i in pts.size():
		if String(pts[i]["id"]) == name:
			return i
	push_error("找不到站點 %s" % name)
	return 0


func st_s(name: String) -> float:
	return main.ctrl_s[_station_ctrl_index(name)]


## 山谷基底場（遠場高度）。
## 以「最近路徑點的 y」會在兩段路的中垂線上跳變（實測：遠場出現橫向折痕）；沿 z 單值化則在東西向的 S 彎處陡變。
## 改成：對路徑樣本做高斯加權平均 v_i = y_i + rise(d_i)，權重 exp(−((d_i − d_min)/σ)²)。連續、平滑，
## 不依賴「路在 z 上單值」。預算在 3 m 粗格，之後雙線性取樣（場本身是低頻，粗格不引入可見折痕）。
const MG_CELL := 3.0
const MG_SIGMA := 12.0
var _mg := PackedFloat32Array()
var _mg_x0 := 0.0
var _mg_z0 := 0.0
var _mg_nx := 0
var _mg_nz := 0


func _build_macro() -> void:
	var step := 4.0
	var P := PackedVector2Array()
	var Y := PackedFloat32Array()
	var s := 0.0
	while s < main.length:
		P.append(main.pos_at(s))
		Y.append(main.y_at(s))
		s += step
	P.append(main.pos_at(main.length))
	Y.append(main.y_at(main.length))
	var xr: Array = L["terrain"]["x_range"]
	var zr: Array = L["terrain"]["z_range"]
	_mg_x0 = float(xr[0]) - 6.0
	_mg_z0 = float(zr[0]) - 6.0
	_mg_nx = int(ceil((float(xr[1]) - float(xr[0]) + 12.0) / MG_CELL)) + 1
	_mg_nz = int(ceil((float(zr[1]) - float(zr[0]) + 12.0) / MG_CELL)) + 1
	_mg.resize(_mg_nx * _mg_nz)
	var n := P.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	for iz in _mg_nz:
		for ix in _mg_nx:
			var px := _mg_x0 + float(ix) * MG_CELL
			var pz := _mg_z0 + float(iz) * MG_CELL
			var dmin := 1e9
			for i in n:
				var dx := px - P[i].x
				var dz := pz - P[i].y
				var d := sqrt(dx * dx + dz * dz)
				dist[i] = d
				if d < dmin:
					dmin = d
			var acc := 0.0
			var wsum := 0.0
			for i in n:
				var e := (dist[i] - dmin) / MG_SIGMA
				if e > 3.0:
					continue
				var w := exp(-e * e)
				acc += w * (Y[i] + _valley_rise(dist[i]))
				wsum += w
			_mg[iz * _mg_nx + ix] = acc / wsum


func _macro_h(p: Vector2) -> float:
	var fx := clampf((p.x - _mg_x0) / MG_CELL, 0.0, float(_mg_nx - 1) - 0.001)
	var fz := clampf((p.y - _mg_z0) / MG_CELL, 0.0, float(_mg_nz - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var u := fx - float(ix)
	var v := fz - float(iz)
	var a := _mg[iz * _mg_nx + ix]
	var b := _mg[iz * _mg_nx + ix + 1]
	var c := _mg[(iz + 1) * _mg_nx + ix]
	var d := _mg[(iz + 1) * _mg_nx + ix + 1]
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


func _build_main() -> Poly:
	var mp: Dictionary = L["main_path"]
	var pts_def: Array = mp["points"]
	var P: Array = []
	for d: Dictionary in pts_def:
		P.append(Vector2(float(d["x"]), float(d["z"])))
	var dense := cr_dense(P, 24)
	var dp: PackedVector2Array = dense["pts"]
	var cidx: PackedInt32Array = dense["cidx"]
	var cum0 := cum_len(dp)
	var total0 := cum0[cum0.size() - 1]
	# 站點 s（蛇行前），用來定義 no_wander 區間
	var cs0 := PackedFloat32Array()
	for ci in cidx:
		cs0.append(cum0[ci])
	var ids: Array = []
	for d: Dictionary in pts_def:
		ids.append(String(d["id"]))
	var zones: Array = []
	for z: Array in mp.get("no_wander", []):
		var a := cs0[ids.find(String(z[0]))]
		var b := cs0[ids.find(String(z[1]))]
		zones.append(Vector2(minf(a, b) - float(z[2]), maxf(a, b) + float(z[2])))
	var wd: Dictionary = mp["wander"]
	var amp := float(wd["amp"])
	var wl := float(wd["wavelength"])
	var disp := PackedVector2Array()
	disp.resize(dp.size())
	for i in dp.size():
		var c := cum0[i]
		var t := (dp[mini(i + 1, dp.size() - 1)] - dp[maxi(i - 1, 0)])
		t = t.normalized() if t.length() > 1e-6 else Vector2(0, -1)
		var f := 1.0
		for zr: Vector2 in zones:
			var dd := maxf(maxf(zr.x - c, c - zr.y), 0.0)
			f = minf(f, smoothstep(0.0, 8.0, dd))
		var taper := smoothstep(0.0, 12.0, c) * smoothstep(0.0, 12.0, total0 - c)
		disp[i] = right_of(t) * (amp * _wander_n.get_noise_1d(c / wl) * f * taper)
	var dp2 := PackedVector2Array()
	dp2.resize(dp.size())
	for i in dp.size():
		dp2[i] = dp[i] + disp[i]
	var cum := cum_len(dp2)
	var rs := resample(dp2, cum, 1.0)
	var poly := Poly.new()
	poly.id = "main"
	poly.kind = "main"
	poly.pts = rs
	poly.s = cum_len(rs)
	poly.length = poly.s[poly.s.size() - 1]
	# 站點 s：以蛇行後的稠密點弧長，再按最終弦長比例校正
	var ratio := poly.length / cum[cum.size() - 1]
	for ci in cidx:
		poly.ctrl_s.append(cum[ci] * ratio)
	poly.ctrl_id = ids
	# 寬度：站點間 smoothstep，再乘微幅起伏，夾進規格 [3.5, 5.0]
	var wob := float(wd.get("width_wobble", 0.0))
	poly.w.resize(rs.size())
	var wmin := float(lim["main_width"][0])
	var wmax := float(lim["main_width"][1])
	for i in rs.size():
		var sv := poly.s[i]
		var k := 0
		while k < poly.ctrl_s.size() - 2 and poly.ctrl_s[k + 1] < sv:
			k += 1
		var a := poly.ctrl_s[k]
		var b := poly.ctrl_s[k + 1]
		var u := clampf((sv - a) / maxf(b - a, 1e-6), 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		var wv := lerpf(float((pts_def[k] as Dictionary)["w"]), float((pts_def[k + 1] as Dictionary)["w"]), u)
		wv *= 1.0 + wob * _wobble_n.get_noise_1d(sv / 17.0)
		poly.w[i] = clampf(wv, wmin, wmax)
	# 高程：PCHIP 穿過站點 y，再套平段（橋面）
	var ys := PackedFloat32Array()
	for d: Dictionary in pts_def:
		ys.append(float(d["y"]))
	poly.y.resize(rs.size())
	for i in rs.size():
		poly.y[i] = pchip_eval(poly.ctrl_s, ys, poly.s[i])
	for fl: Dictionary in mp.get("flats", []):
		var a := poly.ctrl_s[ids.find(String(fl["from"]))] + float(fl["ds0"])
		var b := poly.ctrl_s[ids.find(String(fl["to"]))] + float(fl["ds1"])
		var ramp := float(fl["ramp"])
		var yv := float(fl["y"])
		for i in rs.size():
			var sv := poly.s[i]
			var wgt := smoothstep(a - ramp, a, sv) * (1.0 - smoothstep(b, b + ramp, sv))
			poly.y[i] = lerpf(poly.y[i], yv, wgt)
	poly.finalize()
	return poly


## from/to：{"st":..,"ds":..} 取主路中心線；否則用顯式點
func _anchor(spec: Dictionary) -> Vector2:
	return main.pos_at(st_s(String(spec["st"])) + float(spec.get("ds", 0.0)))


func _build_branch(b: Dictionary) -> Poly:
	var P: Array = []
	var W: Array = []
	var inner: Array = b["points"]
	if b.has("from"):
		P.append(_anchor(b["from"]))
		W.append(float((inner[0] as Dictionary)["w"]))
	for d: Dictionary in inner:
		P.append(Vector2(float(d["x"]), float(d["z"])))
		W.append(float(d["w"]))
	if b.has("to"):
		P.append(_anchor(b["to"]))
		W.append(float((inner[inner.size() - 1] as Dictionary)["w"]))
	var dense := cr_dense(P, 24)
	var dp: PackedVector2Array = dense["pts"]
	var cidx: PackedInt32Array = dense["cidx"]
	var cum := cum_len(dp)
	var rs := resample(dp, cum, 1.0)
	var poly := Poly.new()
	poly.id = String(b["id"])
	poly.kind = String(b["kind"])
	poly.pts = rs
	poly.s = cum_len(rs)
	poly.length = poly.s[poly.s.size() - 1]
	var ratio := poly.length / cum[cum.size() - 1]
	for ci in cidx:
		poly.ctrl_s.append(cum[ci] * ratio)
	poly.w.resize(rs.size())
	for i in rs.size():
		var sv := poly.s[i]
		var k := 0
		while k < poly.ctrl_s.size() - 2 and poly.ctrl_s[k + 1] < sv:
			k += 1
		var u := clampf((sv - poly.ctrl_s[k]) / maxf(poly.ctrl_s[k + 1] - poly.ctrl_s[k], 1e-6), 0.0, 1.0)
		poly.w[i] = lerpf(float(W[k]), float(W[k + 1]), u * u * (3.0 - 2.0 * u))
	poly.y.resize(rs.size())     # bake_branch_y() で埋める
	poly.finalize()
	return poly


func _build_stream(sd: Dictionary) -> Poly:
	var pts_def: Array = sd["points"]
	var P: Array = []
	for d: Dictionary in pts_def:
		P.append(Vector2(float(d["x"]), float(d["z"])))
	# 控制點的溪床：bed＝絕對；drop＝比上一點低 drop（瀑/跌水）；其餘＝該點地形（未切溪）− depth。
	# 一律嚴格單調下降（水往下游流），所以兩岸深度由地形決定、不是手抄數字。
	var bed_c := PackedFloat32Array()
	for i in pts_def.size():
		var d: Dictionary = pts_def[i]
		var v := 0.0
		if d.has("bed"):
			v = float(d["bed"])
		elif d.has("drop"):
			v = bed_c[i - 1] - float(d["drop"])
		else:
			v = _h_stage(Vector2(float(d["x"]), float(d["z"])), 3) - float(d.get("depth", sd.get("depth_default", 2.4)))
		if i > 0:
			var seg := Vector2(float(d["x"]) - float((pts_def[i - 1] as Dictionary)["x"]), float(d["z"]) - float((pts_def[i - 1] as Dictionary)["z"])).length()
			v = minf(v, bed_c[i - 1] - 0.04 - 0.012 * seg)       # 最小坡降 1.2 %，不做平底溝
		bed_c.append(v)
	var dense := cr_dense(P, 24)
	var dp: PackedVector2Array = dense["pts"]
	var cidx: PackedInt32Array = dense["cidx"]
	var cum := cum_len(dp)
	var rs := resample(dp, cum, 1.0)
	var poly := Poly.new()
	poly.id = String(sd["id"])
	poly.kind = "stream"
	poly.pts = rs
	poly.s = cum_len(rs)
	poly.length = poly.s[poly.s.size() - 1]
	var ratio := poly.length / cum[cum.size() - 1]
	for ci in cidx:
		poly.ctrl_s.append(cum[ci] * ratio)
	poly.w.resize(rs.size())
	poly.bed.resize(rs.size())
	for i in rs.size():
		var sv := poly.s[i]
		var k := 0
		while k < poly.ctrl_s.size() - 2 and poly.ctrl_s[k + 1] < sv:
			k += 1
		var u := clampf((sv - poly.ctrl_s[k]) / maxf(poly.ctrl_s[k + 1] - poly.ctrl_s[k], 1e-6), 0.0, 1.0)
		poly.w[i] = lerpf(float((pts_def[k] as Dictionary)["w"]), float((pts_def[k + 1] as Dictionary)["w"]), u * u * (3.0 - 2.0 * u))
		poly.bed[i] = lerpf(bed_c[k], bed_c[k + 1], u)
	poly.y.resize(rs.size())
	poly.finalize()
	return poly


# ================================================================= 解析 at
func scene_id_of_z(z: float) -> String:
	for r: Dictionary in rects:
		var t: Rect2 = r["tile"]
		if z >= t.position.y and z < t.end.y:
			return String(r["id"])
	if z >= (rects[0]["tile"] as Rect2).end.y:
		return String(rects[0]["id"])
	return String(rects[rects.size() - 1]["id"])


func _on_poly(poly: Poly, s: float, off: float) -> Dictionary:
	var sv := clampf(s, 0.0, poly.length)
	var t := poly.tan_at(sv)
	var p := poly.pos_at(sv) + right_of(t) * off
	return {"p": p, "yaw": yaw_of(t), "s": sv, "poly": poly.id, "tan": t}


## 兩條 Poly 的第一個交點；回傳 {p, s_a, s_b, ang_deg} 或 {}
func intersect_polys(a: Poly, b: Poly) -> Dictionary:
	for i in a.pts.size() - 1:
		var a0 := a.pts[i]
		var a1 := a.pts[i + 1]
		var seg_box := Rect2(Vector2(minf(a0.x, a1.x), minf(a0.y, a1.y)), Vector2(absf(a1.x - a0.x), absf(a1.y - a0.y))).grow(1.0)
		if not seg_box.intersects(b.bbox.grow(1.0)):
			continue
		for j in b.pts.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(a0, a1, b.pts[j], b.pts[j + 1])
			if hit != null:
				var ta := (a1 - a0).normalized()
				var tb := (b.pts[j + 1] - b.pts[j]).normalized()
				return {"p": hit, "s_a": a.s[i], "s_b": b.s[j], "ang_deg": rad_to_deg(acos(clampf(absf(ta.dot(tb)), 0.0, 1.0)))}
	return {}


func resolve(at: Dictionary) -> Dictionary:
	if at.has("st"):
		return _on_poly(main, st_s(String(at["st"])) + float(at.get("ds", 0.0)), float(at.get("off", 0.0)))
	if at.has("cross"):
		var st: Poly = streams[String(at["cross"])]
		var hit := intersect_polys(main, st)
		if hit.is_empty():
			push_error("主路與 %s 沒有交點" % at["cross"])
			return {"p": Vector2.ZERO, "yaw": 0.0, "s": 0.0, "poly": "main", "tan": Vector2(0, -1)}
		var r := _on_poly(main, float(hit["s_a"]), float(at.get("off", 0.0)))
		r["cross_ang_deg"] = hit["ang_deg"]
		r["stream_s"] = hit["s_b"]
		return r
	if at.has("cross_branch"):
		var br: Poly = branches[String(at["cross_branch"])]
		var st2: Poly = streams[String(at["with"])]
		var hit2 := intersect_polys(br, st2)
		if hit2.is_empty():
			push_error("支線 %s 與 %s 沒有交點" % [at["cross_branch"], at["with"]])
			return {"p": Vector2.ZERO, "yaw": 0.0, "s": 0.0, "poly": "", "tan": Vector2(0, -1)}
		var r2 := _on_poly(br, float(hit2["s_a"]), float(at.get("off", 0.0)))
		r2["cross_ang_deg"] = hit2["ang_deg"]
		return r2
	if at.has("stream"):
		var sp: Poly = streams[String(at["stream"])]
		return _on_poly(sp, float(at["u"]) * sp.length, float(at.get("off", 0.0)))
	if at.has("br"):
		var bp: Poly = branches[String(at["br"])]
		return _on_poly(bp, float(at["u"]) * bp.length, float(at.get("off", 0.0)))
	if at.has("x"):
		return {"p": Vector2(float(at["x"]), float(at["z"])), "yaw": 0.0, "s": -1.0, "poly": "", "tan": Vector2(0, -1)}
	push_error("不認得的 at：%s" % str(at))
	return {"p": Vector2.ZERO, "yaw": 0.0, "s": -1.0, "poly": "", "tan": Vector2(0, -1)}


func arena_c() -> Vector2:
	var c: Array = L["boss_arena"]["c"]
	return Vector2(float(c[0]), float(c[1]))


## deg 0＝北（−z）、90＝東、180＝南
func arena_pos(deg: float, r: float) -> Vector2:
	var a := deg_to_rad(deg)
	return arena_c() + Vector2(sin(a), -cos(a)) * r


# ================================================================= 地形特徵
func _resolve_features() -> void:
	_mounds.clear()
	_terraces.clear()
	_cliffs.clear()
	for f: Dictionary in L["terrain"]["features"]:
		var typ := String(f["type"])
		if typ == "mound":
			_mounds.append({"c": Vector2(float(f["c"][0]), float(f["c"][1])), "r": float(f["r"]), "h": float(f["h"])})
		elif typ == "terrace_disc" or typ == "arena" or typ == "terrace_rect":
			var c: Vector2
			if f["c"] is Array:
				c = Vector2(float(f["c"][0]), float(f["c"][1]))
			else:
				c = resolve(f["c"])["p"]
			var yv := 0.0
			var yaw_t := Vector2(0, -1)
			var qm := main.q(c)
			if typeof(f["y"]) == TYPE_STRING and String(f["y"]) == "path":
				yv = main.y_at(qm.s)
			elif typeof(f["y"]) == TYPE_STRING and String(f["y"]) == "macro":
				yv = _macro_h(c)          # 跟著當地山谷基底（農田台地不要硬切進丘陵）
			else:
				yv = float(f["y"])
			if typ == "terrace_rect" and String(f.get("yaw", "")) == "path":
				yaw_t = qm.tan
			var r_in := float(f["r"]) if f.has("r") else float(f.get("r_flat", 0.0))
			_terraces.append({"id": f["id"], "type": typ, "c": c, "r": r_in, "hx": float(f.get("hx", 0.0)), "hz": float(f.get("hz", 0.0)),
				"t": yaw_t, "y": yv, "blend": float(f["blend"]), "paving": bool(f.get("paving", false)), "und": float(f.get("undulate", 0.0))})
		elif typ == "cliff":
			var cv := Curve2D.new()
			cv.bake_interval = 0.5
			var arr: Array = f["pts"]
			for p: Array in arr:
				cv.add_point(Vector2(float(p[0]), float(p[1])))
			_cliffs.append({"id": f["id"], "curve": cv, "h": float(f["height"]), "deg": float(f["deg"]), "len": cv.get_baked_length()})


# ================================================================= 高度函式
func mask_sdf(p: Vector2) -> float:
	var k := float(L["terrain"]["wall"]["union_k"])
	var cr := float(L["terrain"]["wall"]["corner_r"])
	var best := 1e9
	var first := true
	for r: Dictionary in rects:
		var rc: Rect2 = r["rect"]
		var ctr := rc.position + rc.size * 0.5
		var hs := rc.size * 0.5 - Vector2(cr, cr)
		var q := (p - ctr).abs() - hs
		var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - cr
		if first:
			best = d
			first = false
		else:
			best = smin(best, d, k)
	return best


## 牆緣加雜訊：路附近（d_main < 10 m）不擾動，離路 > 30 m 全量。只影響外牆起點，不影響玩區邏輯尺寸
func _mask_noisy(p: Vector2, dmain: float) -> float:
	var e := mask_sdf(p)
	var amp := float(L["terrain"]["wall"].get("noise_amp", 0.0))
	if amp <= 0.0 or e < -40.0:
		return e
	var nzv := _noise1.get_noise_2d(p.x * 1.7 + 311.0, p.y * 1.7 - 127.0) + 0.45 * _noise2.get_noise_2d(p.x * 1.3 - 77.0, p.y * 1.3 + 203.0)
	return e + amp * nzv * smoothstep(10.0, 30.0, dmain)


func wall_rise(e: float) -> float:
	if e <= 0.0:
		return 0.0
	var W: Dictionary = L["terrain"]["wall"]
	var t0 := tan(deg_to_rad(float(W["a0_deg"])))
	var t1 := tan(deg_to_rad(float(W["a1_deg"])))
	var R := float(W["ramp_m"])
	var cap := float(W["cap"])
	var rise := 0.0
	if e <= R:
		rise = t0 * e + 0.5 * (t1 - t0) / R * e * e
	else:
		rise = t0 * R + 0.5 * (t1 - t0) * R + t1 * (e - R)
	return cap * tanh(rise / cap)


func _valley_rise(d: float) -> float:
	var V: Dictionary = L["terrain"]["valley_rise"]
	return minf(float(V["lin"]) * d + float(V["quad"]) * d * d, float(V["cap"]))


func _shoulder_w(dh: float) -> float:
	var S: Dictionary = L["terrain"]["shoulder"]
	var w := 1.5 * absf(dh) / tan(deg_to_rad(float(S["design_deg"])))
	return clampf(w, float(S["min"]), float(S["max"]))


func _h_base(p: Vector2, qm: Dictionary) -> float:
	var h := _macro_h(p)
	var tn: Dictionary = L["terrain"]["noise"]
	var fade := smoothstep(float(tn["fade_d"][0]), float(tn["fade_d"][1]), float(qm["d"]))
	h += fade * (float(tn["amp"]) * _noise1.get_noise_2d(p.x, p.y) + float(tn["amp2"]) * _noise2.get_noise_2d(p.x, p.y))
	for m: Dictionary in _mounds:
		var dd := p.distance_to(m["c"]) / float(m["r"])
		if dd < 1.4:
			h += float(m["h"]) * exp(-4.0 * dd * dd)
	var wr := wall_rise(_mask_noisy(p, float(qm["d"])))
	h += wr
	var cl_mask := 0.0
	for c: Dictionary in _cliffs:
		var cv: Curve2D = c["curve"]
		var off := cv.get_closest_offset(p)
		var cp := cv.sample_baked(off)
		var a := cv.sample_baked(maxf(off - 1.0, 0.0))
		var b := cv.sample_baked(minf(off + 1.0, float(c["len"])))
		var t := (b - a).normalized()
		var left := Vector2(t.y, -t.x)
		var sd := (p - cp).dot(left) + 3.0 * _noise2.get_noise_2d(off * 0.09, 41.0)    # 崖腳線沿線起伏 ±3 m
		if sd > 0.0:
			var wd := 1.5 * float(c["h"]) / tan(deg_to_rad(float(c["deg"])))
			# 端部淡出：用「沿曲線方向超出端點」的距離（不是到端點的直線距離——後者在端點垂線上會不連續）
			var clen := float(c["len"])
			var t0 := (cv.sample_baked(1.0) - cv.sample_baked(0.0)).normalized()
			var t1 := (cv.sample_baked(clen) - cv.sample_baked(maxf(clen - 1.0, 0.0))).normalized()
			var beyond := maxf((cv.sample_baked(0.0) - p).dot(t0), (p - cv.sample_baked(clen)).dot(t1))
			var hv := float(c["h"]) * (1.0 + 0.22 * _noise1.get_noise_2d(off * 0.05 + 60.0, 9.0))
			var cm := smoothstep(0.0, wd, sd) * (1.0 - smoothstep(0.0, 12.0, maxf(beyond, 0.0)))
			h += hv * cm
			cl_mask = maxf(cl_mask, cm)
	_cm_last = cl_mask
	# 崖／外牆的岩質粗糙度（白模也要像岩壁，不是光滑土坡）；玩區內（wr≈0）不受影響
	var rw := maxf(smoothstep(2.0, 12.0, wr), cl_mask)
	if rw > 0.0:
		h += rw * (1.25 * _noise1.get_noise_2d(p.x * 0.38 + 17.0, p.y * 0.38 - 9.0) + 0.6 * _noise2.get_noise_2d(p.x * 0.85 - 31.0, p.y * 0.85 + 12.0))
	return h


func _apply_terraces(p: Vector2, h: float) -> float:
	for t: Dictionary in _terraces:
		var w := 0.0
		if String(t["type"]) == "terrace_rect":
			var tv: Vector2 = t["t"]
			var rv := right_of(tv)
			var dv: Vector2 = p - (t["c"] as Vector2)
			var u := absf(dv.dot(rv)) - float(t["hx"])
			var v := absf(dv.dot(tv)) - float(t["hz"])
			var dout := Vector2(maxf(u, 0.0), maxf(v, 0.0)).length()
			w = 1.0 - smoothstep(0.0, float(t["blend"]), dout)
		else:
			var dist := p.distance_to(t["c"])
			w = 1.0 - smoothstep(float(t["r"]), float(t["r"]) + float(t["blend"]), dist)
		if w > 0.0:
			var yy := float(t["y"])
			if float(t["und"]) > 0.0:       # 場地微起伏（<6°）：太平的圓盤讀起來像競技場
				yy += float(t["und"]) * (0.75 * _noise1.get_noise_2d(p.x * 0.08 + 5.0, p.y * 0.08 - 3.0) + 0.45 * _noise2.get_noise_2d(p.x * 0.19, p.y * 0.19 + 9.0))
			h = lerpf(h, yy, w)
	return h


func _paving_w(p: Vector2) -> float:
	var best := 0.0
	for t: Dictionary in _terraces:
		if not bool(t["paving"]):
			continue
		var w := 0.0
		if String(t["type"]) == "terrace_rect":
			var tv: Vector2 = t["t"]
			var rv := right_of(tv)
			var dv: Vector2 = p - (t["c"] as Vector2)
			var u := absf(dv.dot(rv)) - float(t["hx"])
			var v := absf(dv.dot(tv)) - float(t["hz"])
			w = 1.0 - smoothstep(0.0, 1.5, Vector2(maxf(u, 0.0), maxf(v, 0.0)).length())
		else:
			w = 1.0 - smoothstep(float(t["r"]) - 1.5, float(t["r"]) + 1.0, p.distance_to(t["c"]))
		best = maxf(best, w)
	return best


## stage: 2＝到主路路廊為止（支線 y 烘焙用）、4＝完整
func _h_stage(p: Vector2, stage: int, out: Dictionary = {}) -> float:
	var qm := main.q(p)
	var h := _h_base(p, qm)
	h = _apply_terraces(p, h)
	var hw := main.w_at(qm["s"]) * 0.5
	var yc := main.y_at(qm["s"])
	var sw := _shoulder_w(h - yc)
	if qm["d"] < hw + sw:
		var w := 1.0 - smoothstep(hw, hw + sw, float(qm["d"]))
		h = lerpf(h, yc, w)
	if not out.is_empty():
		out["dm"] = qm["d"]
		out["wm"] = hw
	if stage < 3:
		return h
	var dbr := 1e9
	for id: String in branches:
		var br: Poly = branches[id]
		if not br.bbox.grow(30.0).has_point(p):
			continue
		var qb := br.q(p)
		var hwb := br.w_at(qb["s"]) * 0.5
		dbr = minf(dbr, float(qb["d"]) - hwb)
		var swb := _shoulder_w(h - br.y_at(qb["s"]))
		swb = minf(swb, 6.0)
		if qb["d"] < hwb + swb:
			var wb := 1.0 - smoothstep(hwb, hwb + swb, float(qb["d"]))
			h = lerpf(h, br.y_at(qb["s"]), wb)
	if stage < 4:
		return h
	var dst := 1e9
	for id: String in streams:
		var st: Poly = streams[id]
		var qs := st.q(p)
		var hws := st.w_at(qs["s"]) * 0.5
		dst = minf(dst, float(qs["d"]) - hws)
		var sd := _stream_def(id)
		var slope := float(sd["bank_slope"])
		# 支線渡溪處放緩河岸（淺灘）
		var near_ford := 1e9
		for bid: String in branches:
			var bb: Poly = branches[bid]
			if String(bb.kind) != "branch" or not bb.bbox.grow(12.0).has_point(p):
				continue
			near_ford = minf(near_ford, bb.q(p)["d"])
		if near_ford < 9.0:
			slope = lerpf(0.2, slope, smoothstep(2.0, 9.0, near_ford))
		var bed := st.bed_at(qs["s"])
		var dd: float = qs["d"]
		var u := minf(dd / hws, 1.0)
		var carve := bed + 0.35 * u * u + maxf(dd - hws, 0.0) * slope
		var k_smin := 1.4
		if bool(sd.get("plateau", false)):
			# V1.2 D：崖頂平台上的溪（stream_head）。平台整片都在崖遮罩內（崖把崖北整片抬高），原本的淡出會把雕刻整個關掉。
			# 改成限制河岸錐的外擴：河岸 2 m 內照 bank_slope，之外陡升（6 倍），所以河道挖得出來、也不會把上壁或崖面削成錐。
			var ex := maxf(dd - hws, 0.0)
			# V1.3：岸要比水面高。V1.2 的斷面在水邊只比水面高 0.15 m，再被 smin（半徑 1.4 m、最多削 0.35 m）磨掉，
			#       岸頂落到水面以下 → 水像一張平鋪的膜（實測水面高出帶緣最多 0.29 m）。
			#       改成平底＋陡岸（bed + rise·u^pow）、smin 半徑改由 layout（smin_k）給；未指定時與 V1.2 相同。
			var rise := float(sd.get("bank_rise", 0.35))
			var bpow := float(sd.get("bank_pow", 2.0))
			carve = bed + rise * pow(u, bpow) + minf(ex, 2.0) * slope + maxf(ex - 2.0, 0.0) * 6.0
			k_smin = float(sd.get("smin_k", 1.4))
		else:
			# 崖面區：河岸錐（bank_slope 0.75）要隨崖遮罩淡出。否則源頭瀑布潭的岸坡會把北崖削成 37° 的錐，
			# 17 m 的崖永遠長不出來（實測 z=-448 的 23.0 m 正好等於 13.66 + 0.75×(17−5)）。
			carve += 60.0 * smoothstep(0.0, 0.3, _cm_last)
		h = smin(h, carve, k_smin)
	if not out.is_empty():
		out["db"] = dbr
		out["ds"] = dst
	return h


var _stream_defs: Dictionary = {}


func _stream_def(id: String) -> Dictionary:
	if _stream_defs.is_empty():
		for sd: Dictionary in L["streams"]:
			_stream_defs[sd["id"]] = sd
	return _stream_defs[id]


# ================================================================= 烘焙
func bake_branch_y() -> void:
	## 支線中心線高度＝主路路廊後的地形，沿線平滑；起點接主路高度，exit 接台地高度
	for id: String in branches:
		var br: Poly = branches[id]
		var n := br.pts.size()
		var raw := PackedFloat32Array()
		raw.resize(n)
		for i in n:
			raw[i] = _h_stage(br.pts[i], 2)
		var sm := raw
		for pass_i in 2:
			var nxt := PackedFloat32Array()
			nxt.resize(n)
			for i in n:
				var acc := 0.0
				var cnt := 0
				for k in range(-7, 8):
					var j := clampi(i + k, 0, n - 1)
					acc += sm[j]
					cnt += 1
				nxt[i] = acc / float(cnt)
			sm = nxt
		br.y = sm
		# 端點對齊：起點＝原始路廊高度（接主路時即主路 y），逐步過渡 10 m
		for i in n:
			var wgt := 1.0 - smoothstep(0.0, 10.0, br.s[i])
			br.y[i] = lerpf(br.y[i], raw[0], wgt)
			if br.s[i] > br.length - 10.0 and (String(id) == "hollow_loop"):
				var w2 := smoothstep(br.length - 10.0, br.length, br.s[i])
				br.y[i] = lerpf(br.y[i], raw[n - 1], w2)
	_bake_branch_y_pending = false


func setup_lattice() -> void:
	cell = float(L["terrain"]["cell"])
	var xr: Array = L["terrain"]["x_range"]
	var zr: Array = L["terrain"]["z_range"]
	lx0 = float(xr[0]) - 2.0 * cell
	lz0 = float(zr[0]) - 2.0 * cell
	nx = int(round((float(xr[1]) - float(xr[0])) / cell)) + 1 + 4
	nz = int(round((float(zr[1]) - float(zr[0])) / cell)) + 1 + 4
	H.resize(nx * nz)
	DM.resize(nx * nz)
	WM.resize(nx * nz)
	DB.resize(nx * nz)
	DS.resize(nx * nz)
	PV.resize(nx * nz)


func bake(progress: bool = false) -> void:
	if _bake_branch_y_pending:
		bake_branch_y()
	setup_lattice()
	var t0 := Time.get_ticks_msec()
	var o := {}
	for iz in nz:
		for ix in nx:
			var p := Vector2(lx0 + ix * cell, lz0 + iz * cell)
			o.clear()
			o["dm"] = 0.0
			var h := _h_stage(p, 4, o)
			var i := iz * nx + ix
			H[i] = h
			DM[i] = o["dm"]
			WM[i] = o["wm"]
			DB[i] = o.get("db", 1e9)
			DS[i] = o.get("ds", 1e9)
			PV[i] = _paving_w(p)
		if progress and iz % 100 == 0:
			print("[bake] row %d/%d  %.1f s" % [iz, nz, (Time.get_ticks_msec() - t0) / 1000.0])
	baked = true
	print("[bake] %d x %d 晶格 %.1f s" % [nx, nz, (Time.get_ticks_msec() - t0) / 1000.0])


# ================================================================= 取樣
func _ix(x: float) -> float:
	return (x - lx0) / cell


func _iz(z: float) -> float:
	return (z - lz0) / cell


func hl(ix: int, iz: int) -> float:
	return H[clampi(iz, 0, nz - 1) * nx + clampi(ix, 0, nx - 1)]


## 與網格相同的三角剖分（對角線 b–c）內插
func h_at(x: float, z: float) -> float:
	var fx := _ix(x)
	var fz := _iz(z)
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var u := fx - float(ix)
	var v := fz - float(iz)
	var a := hl(ix, iz)
	var b := hl(ix + 1, iz)
	var c := hl(ix, iz + 1)
	var d := hl(ix + 1, iz + 1)
	if u + v <= 1.0:
		return a + (b - a) * u + (c - a) * v
	return d + (c - d) * (1.0 - u) + (b - d) * (1.0 - v)


func n_at(x: float, z: float) -> Vector3:
	var e := cell
	var hx := h_at(x + e, z) - h_at(x - e, z)
	var hz := h_at(x, z + e) - h_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func slope_deg_at(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(n_at(x, z).y, -1.0, 1.0)))


func sample_arr(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf(_ix(x), 0.0, float(nx - 1) - 0.001)
	var fz := clampf(_iz(z), 0.0, float(nz - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var u := fx - float(ix)
	var v := fz - float(iz)
	var a := arr[iz * nx + ix]
	var b := arr[iz * nx + ix + 1]
	var c := arr[(iz + 1) * nx + ix]
	var d := arr[(iz + 1) * nx + ix + 1]
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


func inside_play(p: Vector2) -> bool:
	return mask_sdf(p) <= 0.0


func water_y_at_stream(id: String, s: float) -> float:
	var st: Poly = streams[id]
	return st.bed_at(s) + float(_stream_def(id)["water_depth"])


## 世界點 → 距任一溪的 {id, s, d, hw, bed}（最近者）
func stream_q(p: Vector2) -> Dictionary:
	var best := {"id": "", "d": 1e9}
	for id: String in streams:
		var st: Poly = streams[id]
		var qs := st.q(p)
		if qs["d"] < best["d"]:
			best = {"id": id, "d": qs["d"], "s": qs["s"], "hw": st.w_at(qs["s"]) * 0.5, "bed": st.bed_at(qs["s"])}
	return best


# ================================================================= 頂點色（白模地表分類）
const C_GRASS := Color(0.27, 0.35, 0.16)
const C_GRASS_DRY := Color(0.43, 0.41, 0.22)
const C_FOREST := Color(0.15, 0.23, 0.11)
const C_LEAF := Color(0.40, 0.26, 0.11)
const C_DIRT := Color(0.43, 0.35, 0.24)
const C_PACKED := Color(0.33, 0.27, 0.18)
const C_STONE := Color(0.52, 0.50, 0.46)
const C_GRAVEL := Color(0.44, 0.42, 0.39)
const C_MOSS := Color(0.14, 0.27, 0.12)
const C_ROCK := Color(0.34, 0.35, 0.37)          # 冷灰藍：和崖岩片（prop_builder SLAB_A/B）同一套岩色，才不會讀成兩套地形
const C_WALL_FLOOR := Color(0.20, 0.25, 0.13)


## 沿 z 的森林地表比例（S01 開闊 → S02 最暗 → S04 偏暗）
func forest_amt(z: float) -> float:
	var kz: Array = [[16.0, 0.12], [-60.0, 0.2], [-115.0, 0.72], [-205.0, 0.92], [-262.0, 0.58], [-340.0, 0.7], [-390.0, 0.86], [-480.0, 0.9]]
	if z >= float(kz[0][0]):
		return float(kz[0][1])
	for i in range(1, kz.size()):
		if z >= float(kz[i][0]):
			var u: float = (z - float(kz[i][0])) / (float(kz[i - 1][0]) - float(kz[i][0]))
			return lerpf(float(kz[i][1]), float(kz[i - 1][1]), u)
	return float(kz[kz.size() - 1][1])


func vertex_color(ix: int, iz: int) -> Color:
	var i := clampi(iz, 0, nz - 1) * nx + clampi(ix, 0, nx - 1)
	var x := lx0 + float(ix) * cell
	var z := lz0 + float(iz) * cell
	var h := H[i]
	var sx := (hl(ix + 1, iz) - hl(ix - 1, iz)) / (2.0 * cell)
	var sz := (hl(ix, iz + 1) - hl(ix, iz - 1)) / (2.0 * cell)
	var slope := rad_to_deg(atan(sqrt(sx * sx + sz * sz)))
	var fa := forest_amt(z)
	var n_big := _leaf_n.get_noise_2d(x * 0.9, z * 0.9)
	var n_mid := _leaf_n.get_noise_2d(x * 2.3 + 40.0, z * 2.3 - 17.0)
	var n_fine := _leaf_n.get_noise_2d(x * 5.1 - 80.0, z * 5.1 + 33.0)
	# --- 基底：草（偏黃綠、帶乾草斑）→ 林床（暗綠＋落葉）
	var grass := C_GRASS.lerp(C_GRASS_DRY, clampf(0.45 + 0.9 * n_big, 0.0, 1.0) * 0.55)
	var floor_c := C_FOREST.lerp(C_LEAF, clampf(0.35 + 0.8 * n_mid, 0.0, 1.0) * 0.6)
	var wall_k := smoothstep(34.0, 46.0, slope)
	var col := grass.lerp(floor_c, clampf(fa + 0.18 * n_big, 0.0, 1.0))
	# --- 裸土斑／落葉斑塊（深林更多）
	col = col.lerp(C_DIRT.darkened(0.18), clampf((n_mid - 0.30) * 2.4, 0.0, 0.6) * (0.25 + 0.6 * fa))
	col = col.lerp(C_LEAF, clampf((n_big - 0.12) * 2.2, 0.0, 0.7) * smoothstep(0.45, 0.9, fa))
	# --- 溪岸苔
	var ds := DS[i]
	col = col.lerp(C_MOSS, (1.0 - smoothstep(0.0, 4.5, ds)) * 0.6)
	# --- 坡面：46° 以下維持森林地表（暗化），之後才轉裸岩＋層理
	col = col.lerp(C_WALL_FLOOR, smoothstep(24.0, 40.0, slope) * 0.5)
	var strata := 0.5 + 0.5 * sin(h * 2.7 + 3.0 * n_mid)
	var rock := C_ROCK.lerp(C_ROCK.darkened(0.34), strata * 0.85).lerp(C_MOSS, clampf(0.25 + 0.5 * n_big, 0.0, 0.6) * 0.5)
	col = col.lerp(rock, smoothstep(44.0, 60.0, slope))
	# --- 瀑布濕岩帶：水幕兩側 ±5 m 的崖面壓暗＋苔（水幕貼壁、崖面像被水沖過）
	var wfx := float(L["boss_arena"]["waterfall"]["x"])
	var wet := (1.0 - smoothstep(1.5, 5.5, absf(x - wfx + 1.2 * n_mid))) * smoothstep(50.0, 70.0, slope)
	col = col.lerp(C_ROCK.darkened(0.55).lerp(C_MOSS, 0.3), wet * 0.8)
	# --- 主路：不規則邊緣、肩部踩踏草、中心壓實
	var dm := DM[i] + (0.55 * n_mid + 0.35 * n_fine) * 0.9
	var wm := WM[i]
	col = col.lerp(C_PACKED, 0.5 * (1.0 - smoothstep(wm + 0.2, wm + 1.2, dm)))
	var road_col := C_DIRT.lerp(C_PACKED, clampf(0.4 + 0.5 * n_mid, 0.0, 1.0) * 0.55)
	col = col.lerp(road_col, 1.0 - smoothstep(wm - 0.35, wm + 0.45, dm))
	# --- 支線：更窄更不規則（獸道感）
	var db := DB[i] + (0.5 * n_mid + 0.4 * n_fine) * 0.7
	col = col.lerp(C_PACKED, 0.5 * (1.0 - smoothstep(0.0, 0.9, db)))
	col = col.lerp(C_DIRT.darkened(0.1), 1.0 - smoothstep(-0.25, 0.4, db))
	# --- 鋪石／壓實地：邊界用雜訊打散，不要圓盤感；石板只成斑塊
	var pv := PV[i] + 0.30 * n_mid + 0.16 * n_fine
	var earth := smoothstep(0.12, 0.55, pv)
	col = col.lerp(C_PACKED.lerp(C_DIRT, clampf(0.5 + 0.7 * n_big, 0.0, 1.0)), 0.62 * earth)
	var patch := smoothstep(0.48, 0.74, pv + 0.22 * n_big)
	var stone := C_STONE.lerp(C_DIRT, clampf(0.35 + 0.6 * n_fine, 0.0, 0.8))
	col = col.lerp(stone, patch * 0.85)
	# --- 溪床礫石
	col = col.lerp(C_GRAVEL, 1.0 - smoothstep(-0.8, 0.3, ds))
	# --- 林內整體壓暗（樹冠遮蔽的感覺），再加輕微亮度噪聲
	var shade := lerpf(1.0, 0.8, fa * (1.0 - wall_k * 0.0))
	var jit := 1.0 + 0.08 * _leaf_n.get_noise_2d(x * 0.9 + 91.0, z * 0.9 - 40.0)
	return Color(col.r * jit * shade, col.g * jit * shade, col.b * jit * shade, 1.0)


# ================================================================= S04 天然地表權重（V1.1）
## 通道（PackedFloat32Array，GC_N 個）：0 trodden 踏み固め土、1 gravel 礫、2 mud 濕泥、3 rock 岩、
##   4 forest 林床落葉、5 wet 濕度、6 moss 苔、7 保留。其餘＝草（shader 以 1 − Σ 補齊）。
## 分布的「原因」（V1.1：所有資產分布需要自然形成的原因，不是純隨機）：
##   · 壓實土＝場心的戰鬥踩踏，半徑隨方位抖動，向外讓給草與落葉；
##   · 落葉＝樹冠遮蔭下（canopy）與林緣，並在場內成小堆；
##   · 礫＝岩腳（rock_d）；苔＝岩腳、水邊、林蔭潮濕處；
##   · 濕泥＝潭／溪岸與崖腳滲水；岩＝陡坡（shader 再用法線細修）。
## 優先序填充：岩 → 濕泥 → 礫 → 落葉 → 壓實土 → 草（剩餘），所以 Σ ≤ 1。
## ctx：{"canopy": PackedFloat32Array（與晶格同尺寸）, "rock_d": PackedFloat32Array（離岩腳緣 m；≥6.5 填 99）}
const GC_N := 8

## V1.2 C：layout.boss_arena.ground_features 的手放斑塊（落葉條帶／濕泥窪／草簇／碎礫）
var _gfeat: Array = []


func _build_ground_features() -> void:
	_gfeat.clear()
	var A: Dictionary = L["boss_arena"]
	for f: Dictionary in A.get("ground_features", []):
		if not f.has("kind"):
			continue
		var yaw := deg_to_rad(float(f["yaw"]))
		var ax := Vector2(sin(yaw), -cos(yaw))
		_gfeat.append({"k": String(f["kind"]), "c": arena_pos(float(f["deg"]), float(f["r"])), "a": float(f["a"]), "b": float(f["b"]),
			"ax": ax, "az": Vector2(-ax.y, ax.x), "st": float(f["k"])})


## 手放斑塊在 (x,z) 的強度（0~1），分四類取最大。邊界用噪聲扭曲（不是正橢圓）。
func ground_feature_w(x: float, z: float) -> Dictionary:
	var out := {"leaf": 0.0, "mud": 0.0, "grass": 0.0, "gravel": 0.0}
	var p := Vector2(x, z)
	for g: Dictionary in _gfeat:
		var d: Vector2 = p - (g["c"] as Vector2)
		if d.length_squared() > pow(maxf(float(g["a"]), float(g["b"])) * 1.9, 2.0):
			continue
		var wu := _gn3.get_noise_2d(x * 1.3 + 17.0, z * 1.3 - 5.0)
		var wv := _gn3.get_noise_2d(x * 1.3 - 31.0, z * 1.3 + 44.0)
		var u := d.dot(g["ax"]) / float(g["a"]) + 0.34 * wu
		var v := d.dot(g["az"]) / float(g["b"]) + 0.34 * wv
		var dn := sqrt(u * u + v * v)
		var f := (1.0 - smoothstep(0.42, 1.0, dn)) * float(g["st"])
		if f > float(out[g["k"]]):
			out[g["k"]] = f
	return out


func ground_channels(ix: int, iz: int, ctx: Dictionary) -> PackedFloat32Array:
	var i := clampi(iz, 0, nz - 1) * nx + clampi(ix, 0, nx - 1)
	var x := lx0 + float(ix) * cell
	var z := lz0 + float(iz) * cell
	var sx := (hl(ix + 1, iz) - hl(ix - 1, iz)) / (2.0 * cell)
	var sz := (hl(ix, iz + 1) - hl(ix, iz - 1)) / (2.0 * cell)
	var slope := rad_to_deg(atan(sqrt(sx * sx + sz * sz)))
	var n_big := _gn1.get_noise_2d(x, z)
	var n_mid := _gn2.get_noise_2d(x, z)
	var n_fine := _gn3.get_noise_2d(x, z)
	var n_pile := _gn4.get_noise_2d(x + 311.0, z - 97.0)
	var can: float = (ctx["canopy"] as PackedFloat32Array)[i]
	var rd: float = (ctx["rock_d"] as PackedFloat32Array)[i]
	var ds := DS[i]
	var rel := Vector2(x, z) - arena_c()
	var r := rel.length()
	var th := atan2(rel.x, -rel.y)                      # 羅盤方位（0=北、π/2=東、π=南）
	var cs := cos(th)
	var sn := sin(th)
	# ---- 壓實土的邊界半徑 R(θ)：不是圓。大瓣＋小瓣；南口收窄（草灣夾著進場路）、東北朝出口延伸
	var lobe1 := _gn5.get_noise_2d(cs * 1.7 + 7.0, sn * 1.7 - 3.0)
	var lobe2 := _gn5.get_noise_2d(cs * 3.6 - 11.0, sn * 3.6 + 19.0)
	var d_s := absf(wrapf(th - PI, -PI, PI))
	var d_ne := absf(wrapf(th - deg_to_rad(50.0), -PI, PI))
	# V1.2：基準半徑 15→16 m。V1.2 手放的落葉條帶／草簇／碎礫（ground_features）把戰鬥圓的泥土吃到 47.8 %，低於規格參考（約 6 成）的驗證下限 48 %；
	#   外推 1 m 並把草斑對核心的切除從 0.8 降到 0.6 之後是 52.6 %（草 22／葉 14／石 11 %）。形狀與方位仍完全由同一組噪聲決定。
	var big_r := 16.0 + 8.0 * lobe1 + 3.0 * lobe2 - 4.8 * exp(-pow(d_s / 0.5, 2.0)) + 4.0 * exp(-pow(d_ne / 0.42, 2.0))
	var rw := r + 2.4 * n_mid
	var dirt_core := maxf(1.0 - smoothstep(big_r - 4.5, big_r + 4.5, rw), 1.0 - smoothstep(7.5, 10.5, r))
	var outside := 1.0 - dirt_core
	# ---- 路：主路與支線本身就是踩實土
	var wm := WM[i]
	var trail := maxf(1.0 - smoothstep(wm - 0.1, wm + 1.5, DM[i] + 0.7 * n_fine), 1.0 - smoothstep(-0.2, 1.0, DB[i] + 0.5 * n_fine))
	# ---- 岩／濕
	var w_rock := smoothstep(30.0, 46.0, slope)
	var wet := 1.0 - smoothstep(0.3, 5.0, ds + 1.5 * n_mid)
	var seep := smoothstep(12.0, 24.0, slope) * (1.0 - smoothstep(28.0, 44.0, slope))
	wet = maxf(wet, seep * (0.45 + 0.4 * n_big))
	# 瀑布濕岩帶：水幕兩側 ±5 m 的陡崖面（水沖過的崖面變暗、長苔）
	var wfx := float(L["boss_arena"]["waterfall"]["x"])
	# V1.2 D：濕岩帶加寬（±8 m、緩坡 30° 起就算）——水幕兩側的崖面整片被水氣打濕，水幕才不像貼在乾岩上
	wet = clampf(maxf(wet, (1.0 - smoothstep(2.0, 8.0, absf(x - wfx + 1.4 * n_mid))) * smoothstep(30.0, 55.0, slope) * 0.95), 0.0, 1.0)
	# 泥：水邊濕泥＋遮蔭凹處的深色濕土斑（不在路上）
	var damp_patch := smoothstep(0.20, 0.58, 0.6 * n_mid + 0.4 * n_big + 0.22 * can)
	# ---- V1.2 C：核心區（壓實土）內不是一整片同一種土。
	#   落葉條帶：風向 NW→SE，長軸 ~9 m、短軸 ~2.5 m 的條帶，環帶（r 7~26 m）較多、中心少；
	#   濕泥斑：3~6 m 的低窪暗土；碎礫斑：1~3 m 的小礫散落；草斑：核心外圈探進來的草。
	var wphi := deg_to_rad(135.0)
	var wu := rel.x * cos(wphi) + rel.y * sin(wphi)
	var wv := -rel.x * sin(wphi) + rel.y * cos(wphi)
	# V1.2 C 修正：噪聲各向異性 3.6:1 / 2.9:1 → 1.6:1 / 1.5:1（原本讀成同向刷痕，不像落葉堆）
	var n_drift := _gn2.get_noise_2d(wu * 0.8 + 91.0, wv * 1.3 - 40.0)
	var n_drift2 := _gn3.get_noise_2d(wu * 1.1 - 13.0, wv * 1.7 + 8.0)
	var rim_k := smoothstep(6.0, 13.0, r) * (1.0 - smoothstep(24.0, 34.0, r))
	var drift := smoothstep(0.22, 0.50, n_drift + 0.35 * n_drift2) * (0.18 + 0.82 * rim_k)
	var core_damp := smoothstep(0.34, 0.60, 0.5 * _gn2.get_noise_2d(x * 1.0 + 55.0, z * 1.0 - 21.0) + 0.5 * n_big) * dirt_core
	var peb_patch := smoothstep(0.52, 0.78, 0.55 * n_fine + 0.65 * _gn4.get_noise_2d(x * 2.2 - 17.0, z * 2.2 + 63.0)) * dirt_core
	# 瀑布濕地過渡：潭／溪外 4~12 m 是濕草——暗一點、帶苔，慢慢退成乾草（不是潭緣一條線就結束）
	var wet_grass := smoothstep(1.0, 3.5, ds) * (1.0 - smoothstep(4.0, 12.0, ds + 3.0 * n_big))
	var gf := ground_feature_w(x, z)
	var mud_p := clampf(wet * 0.95 + damp_patch * 0.34 + core_damp * 0.55, 0.0, 1.0) * (1.0 - 0.6 * trail)
	mud_p = maxf(mud_p, float(gf["mud"]) * (1.0 - 0.7 * trail))
	# 礫：只來自岩腳（崩落）＋極少數場內小礫
	var gravel_p := clampf((1.0 - smoothstep(0.0, 2.5, rd + 0.9 * n_mid)) * 0.75 + smoothstep(0.66, 0.84, 0.6 * n_fine + 0.5 * n_pile) * 0.06 + peb_patch * 0.42, 0.0, 1.0) * (1.0 - 0.6 * trail)
	gravel_p = maxf(gravel_p, float(gf["gravel"]) * (1.0 - 0.7 * trail))
	# 落葉：樹冠下；以及「踩不到的地方才積葉」——堆在壓實區邊緣外，成團（不是均勻撒點）
	var pile := smoothstep(-0.06, 0.38, n_pile + 0.35 * n_mid)
	var leaf_p := clampf(smoothstep(0.10, 0.6, can) * 0.95 + outside * pile * 0.90 + smoothstep(26.0, 40.0, r) * 0.5 + drift * 0.55, 0.0, 1.0) * (1.0 - trail)
	leaf_p = maxf(leaf_p, float(gf["leaf"]) * (1.0 - 0.85 * trail))
	# 壓實土：核心＋路；草斑切走一部分
	var grass_patch := smoothstep(0.02, 0.36, 0.75 * n_mid + 0.30 * n_fine + 0.30 * smoothstep(4.0, 20.0, rw) - 0.22)
	var dirt_p := clampf(maxf(dirt_core * (1.0 - 0.6 * grass_patch) + outside * 0.08, trail), 0.0, 1.0)
	dirt_p *= 1.0 - float(gf["grass"]) * (1.0 - trail)
	# 苔：岩腳、濕處、林蔭潮處
	var moss := (1.0 - smoothstep(0.0, 2.8, rd)) * (0.5 + 0.5 * n_mid) * 0.9
	moss += wet * 0.55 * (0.4 + 0.6 * n_big) * (1.0 - w_rock)
	moss += wet_grass * 0.30 * (0.5 + 0.5 * n_mid)
	moss += smoothstep(0.4, 0.85, can) * smoothstep(0.0, 0.45, n_big + 0.12) * 0.32
	moss = clampf(moss * (1.0 - trail), 0.0, 1.0)
	wet = clampf(maxf(wet, wet_grass * 0.42), 0.0, 1.0)
	var free := 1.0 - w_rock
	var w_mud := free * mud_p
	free -= w_mud
	var w_grv := free * gravel_p
	free -= w_grv
	var w_leaf := free * leaf_p
	free -= w_leaf
	var w_dirt := free * dirt_p
	var out := PackedFloat32Array()
	out.resize(GC_N)
	out[0] = w_dirt
	out[1] = w_grv
	out[2] = w_mud
	out[3] = w_rock
	out[4] = w_leaf
	out[5] = wet
	out[6] = moss
	out[7] = 0.0
	return out


## 樹冠遮蔭場（與晶格同尺寸）。trees＝[{x, z, reach, w}]：reach＝樹冠影響半徑（m）、w＝權重。
func build_canopy_field(trees: Array) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(nx * nz)
	for t: Dictionary in trees:
		var reach := float(t["reach"])
		var tx := float(t["x"])
		var tz := float(t["z"])
		var ix0 := maxi(int(floor(_ix(tx - reach))), 0)
		var ix1 := mini(int(ceil(_ix(tx + reach))), nx - 1)
		var iz0 := maxi(int(floor(_iz(tz - reach))), 0)
		var iz1 := mini(int(ceil(_iz(tz + reach))), nz - 1)
		var tw := float(t.get("w", 1.0))
		for jz in range(iz0, iz1 + 1):
			for jx in range(ix0, ix1 + 1):
				var d := Vector2(lx0 + float(jx) * cell - tx, lz0 + float(jz) * cell - tz).length()
				if d < reach:
					var k := 1.0 - d / reach
					f[jz * nx + jx] += k * k * tw
	return f


## 離岩腳緣的距離場（m；岩內為負；≥ 6.5 m 填 99）。rocks＝[{p: Vector2, r: float}]
func build_rockprox_field(rocks: Array) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(nx * nz)
	f.fill(99.0)
	for rk: Dictionary in rocks:
		var rp: Vector2 = rk["p"]
		var rr := float(rk["r"])
		var reach := rr + 6.5
		var ix0 := maxi(int(floor(_ix(rp.x - reach))), 0)
		var ix1 := mini(int(ceil(_ix(rp.x + reach))), nx - 1)
		var iz0 := maxi(int(floor(_iz(rp.y - reach))), 0)
		var iz1 := mini(int(ceil(_iz(rp.y + reach))), nz - 1)
		for jz in range(iz0, iz1 + 1):
			for jx in range(ix0, ix1 + 1):
				var d := Vector2(lx0 + float(jx) * cell, lz0 + float(jz) * cell).distance_to(rp) - rr
				if d < f[jz * nx + jx]:
					f[jz * nx + jx] = d
	return f
