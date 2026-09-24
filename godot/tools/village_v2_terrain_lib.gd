extends RefCounted
## 人間之里 V2 地形共用幾何（P1 Terrain）。產生器 gen_village_v2.gd 與驗證 verify_village_v2_terrain.gd
## 共用同一份算法，兩邊不各寫一套。
##
##   const TLib := preload("res://tools/village_v2_terrain_lib.gd")
##
## Built Terrain：各 built 分區做 closing（外擴 g → 聯集 → 內縮 g）得到平台外框；
##   外框內＋外框外 apron 公尺＝平台，高度＝基準面 plane(z)（沿 z 的 0.6 % 緩坡，排水用）。
## Transition Terrain：apron 以外 platform_blend 公尺內，地面由平台高 smoothstep 接回原地面（Natural edge）；
##   接不回來（高差太大）的地方被夾在 plane − d·tan(填方角) … plane + d·tan(挖方角) 之間（Retaining edge，
##   P4 可放擋土）。夾限用 polynomial soft min/max（寬 bank_soft_k）倒圓角，不留 2 m 網格會走樣的折線。
## Farmland：梯田面高＝farm_level（依 terrain.farm_terraces 的 x／z 斷線逐段降，斷線與 2 m 網格對齊）。
## 參數在 layout_v2.json 的 terrain（不在凍結範圍），缺省值見 DEFAULTS。

const DEFAULTS := {
	"platform_close_gap": 6.0,   # 分區間 < 2g 的縫補成同一塊平台
	"platform_apron": 3.0,       # 平台在分區外框外多留的平地（≥ 1.5 格網格，避免坡腳三角形斜進平台）
	"bank_fill_deg": 33.7,       # 填方坡 1:1.5
	"bank_cut_deg": 45.0,        # 挖方坡 1:1（西肩離平台 29.8 m、高出 26.45 m，需 ≥ 41.6° 才不削到峰頂）
	"platform_blend": 12.0,      # Natural edge：平台高接回原地面的距離（最短）
	"platform_blend_max": 20.0,  # 高差大時接坡距離放寬到此（smoothstep 坡度 ≈ 1.5·Δ/W ≤ tan blend_deg）
	"blend_deg": 35.0,
	"bank_soft_k": 3.0,          # 填挖坡夾限的圓角寬
	"retaining_min_h": 0.3,      # 夾限比自然接坡低／高 ≥ 此值的站＝Retaining edge
}


static func param(L: Dictionary, key: String) -> float:
	return float(L.get("terrain", {}).get(key, DEFAULTS[key]))


## Built Terrain 基準面：heights.built 在 z = built_z_ref，往北（−z）每公尺升 built_slope。
static func plane(L: Dictionary, z: float) -> float:
	var H: Dictionary = L["heights"]
	return float(H["built"]) + (float(H["built_z_ref"]) - z) * float(H["built_slope"])


## 平台外自然接坡（未夾限）：d＝離坡腳（apron 外緣）的水平距離（≤ 0 ＝在平台上）。
static func blend(L: Dictionary, base: float, plane_h: float, d: float) -> float:
	if d <= 0.0:
		return plane_h
	var w := clampf(1.5 * absf(base - plane_h) / tan(deg_to_rad(param(L, "blend_deg"))),
		param(L, "platform_blend"), param(L, "platform_blend_max"))
	return lerpf(plane_h, base, smoothstep(0.0, w, d))


## 填挖坡＝自然接坡再夾進填挖限（soft，倒圓角）。base＝平台不存在時的地面。
static func bank(L: Dictionary, base: float, plane_h: float, d: float) -> float:
	if d <= 0.0:
		return plane_h
	var k := minf(param(L, "bank_soft_k"), 0.5 * d)
	var h := blend(L, base, plane_h, d)
	h = smin(h, plane_h + d * tan(deg_to_rad(param(L, "bank_cut_deg"))), k)
	return smax(h, plane_h - d * tan(deg_to_rad(param(L, "bank_fill_deg"))), k)


static func smin(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return minf(a, b)
	var hh := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - hh * hh * k * 0.25


static func smax(a: float, b: float, k: float) -> float:
	return -smin(-a, -b, k)


## 梯田面高（terrain.farm_terraces）：由 top 起，往東每過一條 x 斷線降 riser_x、往北每過一條 z 斷線降 riser_z；
## 斷線處是 riser_w 寬的直坡（田埂位置）。沒設定就回 heights.farm（r3 的平田）。
static func farm_level(L: Dictionary, p: Vector2) -> float:
	var T: Dictionary = L.get("terrain", {}).get("farm_terraces", {})
	if T.is_empty():
		return float(L["heights"]["farm"])
	var h := float(T["top"])
	var w := float(T["riser_w"])
	for b in T["x_breaks"]:
		h -= float(T["riser_x"]) * clampf((p.x - (float(b) - w * 0.5)) / w, 0.0, 1.0)
	for b in T["z_breaks"]:
		h -= float(T["riser_z"]) * clampf(((float(b) + w * 0.5) - p.y) / w, 0.0, 1.0)
	return h


## 橋長容許範圍 [min, max]（terrain.bridge_spans；preferred ×(1 ∓ tolerance)）。沒設定回 []。
static func bridge_span(L: Dictionary, bridge_name: String) -> Array:
	var S: Dictionary = L.get("terrain", {}).get("bridge_spans", {})
	var pref: Dictionary = S.get("preferred", {})
	if not pref.has(bridge_name):
		return []
	var pv := float(pref[bridge_name])
	var tol := float(S["tolerance"])
	return [pv, pv * (1.0 - tol), pv * (1.0 + tol)]


static func pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in a:
		out.append(Vector2(float(v[0]), float(v[1])))
	return out


## offset_polygon／merge_polygons 會同時回傳外框與洞（洞是順時針）；只留外框。
static func _outers(polys: Array) -> Array:
	var out: Array = []
	for p in polys:
		if not Geometry2D.is_polygon_clockwise(p):
			out.append(p)
	return out


## 建成區聯集外框（closing）。回傳 Array[PackedVector2Array]（逆時針）。
static func built_outlines(L: Dictionary) -> Array:
	var g := param(L, "platform_close_gap")
	var grown: Array = []
	var D: Dictionary = L["districts"]
	for k in D:
		if String(D[k]["kind"]) == "built":
			# layout 的多邊形有順有逆（Market、MixedCommercial 是順時針）；offset_polygon 保留輸入方向，
			# 不先統一成逆時針，_outers 會把它們當成洞丟掉。
			var poly := pts(D[k]["poly"])
			if Geometry2D.is_polygon_clockwise(poly):
				poly.reverse()
			grown.append_array(_outers(Geometry2D.offset_polygon(poly, g)))
	var merged: Array = []
	for p in grown:
		var cur: PackedVector2Array = p
		var again := true
		while again:
			again = false
			for i in merged.size():
				var m := _outers(Geometry2D.merge_polygons(cur, merged[i]))
				if m.size() == 1:
					cur = m[0]
					merged.remove_at(i)
					again = true
					break
		merged.append(cur)
	var out: Array = []
	for p in merged:
		out.append_array(_outers(Geometry2D.offset_polygon(p, -g)))
	return out


## 帶號距離：> 0 在外框內（值＝到外框邊的距離）；< 0 在外框外（−距離）。多個外框取最大值。
static func outline_sd(outlines: Array, p: Vector2) -> float:
	var best := -INF
	for poly in outlines:
		var d := INF
		for k in poly.size():
			d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[k], poly[(k + 1) % poly.size()])))
		best = maxf(best, d if Geometry2D.is_point_in_polygon(p, poly) else -d)
	return best


## 點到折線的最短距離。
static func polyline_d(line: PackedVector2Array, p: Vector2) -> float:
	var d := INF
	for k in line.size() - 1:
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1])))
	return d


## 有 pad 的地標（地塊整平）：[中心, 半徑, id]。半徑＝max(寬, 深)/2 + 1.5 m（與產生器同一式）。
static func pads(L: Dictionary) -> Array:
	var out: Array = []
	for lm in L["landmarks"]:
		if lm.get("pad", false):
			var s3: Array = lm["size"]
			out.append([Vector2(float(lm["at"][0]), float(lm["at"][1])),
				maxf(float(s3[0]), float(s3[2])) * 0.5 + 1.5, String(lm["id"])])
	return out


## 參道接坡：道路折線最後一點往 pad 中心方向，接到 pad 外緣。回傳延長後的折線（找不到設定就原樣）。
static func approach_line(L: Dictionary, road_pts: PackedVector2Array, road_name: String) -> PackedVector2Array:
	var A: Dictionary = L.get("terrain", {}).get("approach", {})
	if String(A.get("road", "")) != road_name:
		return road_pts
	for pd in pads(L):
		if String(pd[2]) == String(A["pad"]):
			var end := road_pts[road_pts.size() - 1]
			var c: Vector2 = pd[0]
			var out := road_pts.duplicate()
			out.append(c + (end - c).normalized() * float(pd[1]))
			return out
	return road_pts


## 沿折線每 step 公尺取一點（依弧長，含終點）。
static func resample(line: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([line[0]])
	var carry := 0.0
	for k in line.size() - 1:
		var a := line[k]
		var b := line[k + 1]
		var seg := a.distance_to(b)
		var s := step - carry
		while s <= seg:
			out.append(a.lerp(b, s / seg))
			s += step
		carry = seg - (s - step)
	if out[out.size() - 1].distance_to(line[line.size() - 1]) > 0.01:
		out.append(line[line.size() - 1])
	return out
