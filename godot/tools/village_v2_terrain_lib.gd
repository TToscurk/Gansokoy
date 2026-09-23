extends RefCounted
## 人間之里 V2 地形共用幾何（P1 Terrain）。產生器 gen_village_v2.gd 與驗證 verify_village_v2_terrain.gd
## 共用同一份算法，兩邊不各寫一套。
##
##   const TLib := preload("res://tools/village_v2_terrain_lib.gd")
##
## Built Terrain：各 built 分區做 closing（外擴 g → 聯集 → 內縮 g）得到平台外框；
##   外框內＋外框外 apron 公尺＝平台，高度＝基準面 plane(z)（沿 z 的 0.6 % 緩坡，排水用）。
## Transition Terrain：apron 以外是填挖坡，離坡腳 d 公尺處地形被夾在
##   plane − d·tan(填方角) … plane + d·tan(挖方角) 之間；夾不到的地方就是原本的 Natural Terrain。
## 參數在 layout_v2.json 的 terrain（不在凍結範圍），缺省值見 DEFAULTS。

const DEFAULTS := {
	"platform_close_gap": 6.0,   # 分區間 < 2g 的縫補成同一塊平台
	"platform_apron": 3.0,       # 平台在分區外框外多留的平地（≥ 1.5 格網格，避免坡腳三角形斜進平台）
	"bank_fill_deg": 33.7,       # 填方坡 1:1.5
	"bank_cut_deg": 45.0,        # 挖方坡 1:1（西肩離平台 29.8 m、高出 26.45 m，需 ≥ 41.6° 才不削到峰頂）
}


static func param(L: Dictionary, key: String) -> float:
	return float(L.get("terrain", {}).get(key, DEFAULTS[key]))


## Built Terrain 基準面：heights.built 在 z = built_z_ref，往北（−z）每公尺升 built_slope。
static func plane(L: Dictionary, z: float) -> float:
	var H: Dictionary = L["heights"]
	return float(H["built"]) + (float(H["built_z_ref"]) - z) * float(H["built_slope"])


## 填挖坡：base＝平台不存在時的地面；d＝離坡腳（apron 外緣）的水平距離（≤ 0 ＝在平台上）。
static func bank(L: Dictionary, base: float, plane_h: float, d: float) -> float:
	if d <= 0.0:
		return plane_h
	return clampf(base, plane_h - d * tan(deg_to_rad(param(L, "bank_fill_deg"))),
		plane_h + d * tan(deg_to_rad(param(L, "bank_cut_deg"))))


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
