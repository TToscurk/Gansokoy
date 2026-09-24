extends SceneTree
## 人間之里 V2：P3 Roads / Parcels gate（headless）。
##   Godot --headless --path godot --script res://tools/verify_village_v2_parcels.gd
##
## 巷道（layout lanes，P3 新增；凍結 roads 由 freeze gate 管）
##   寬 2.0–3.0 m 且比主街窄；至少一個轉折 ≥ 10°；起點接既有道路或巷道；整條在建成區平台內；
##   離水岸 ≥ LANE_WATER_MIN；不跨任何水道；縱坡 ≤ LANE_GRADE_MAX；
##   路面網格貼 P1 地形（頂點高 − 地面 ∈ LANE_LIFT ± LANE_FIT_TOL；不整地——P1 protection 另有 gate）。
## 地塊（maps/village_v2/gen/parcels.json＋場景 Districts/*/Parcels）
##   §11 欄位齊全；檔案與目前 layout 同步（重算結果一致）；場景 Marker 與檔案一一對應；
##   互不重疊；不壓道路／巷道路幅；在平台外框內；離水道、keep_clear（水車、龍神像、傳送點、任務錨點、橋頭）；
##   町家臨路面 5–9 m、縱深在規則範圍；地塊內高低差 ≤ max_relief、坡度 ≤ SLOPE_MAX；
##   入口與路面高差 ≤ ENTRY_ROAD_MAX；記錄的地面高與目前地形一致（≤ GROUND_TOL）。
##   地標固定地塊 9 塊：各含其地標中心；地標本體壓到路幅的面積另列 INFO（P0 凍結位置，交 P4）。
## 覆蓋：住宅／市集各區建成地離最近路緣 > 30 m 的比例 ≤ FAR_MAX；主街兩側臨路面地塊覆蓋率 ≥ MAIN_FILL_MIN。

const SCENE := "res://maps/village_v2/village_v2.tscn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const PARCELS := "res://maps/village_v2/gen/parcels.json"
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const PLib := preload("res://tools/village_v2_parcel_lib.gd")

const LANE_W := [2.0, 3.0]
const LANE_TURN_MIN := 10.0
const LANE_WATER_MIN := 5.0
const LANE_GRADE_MAX := 0.08
const LANE_LIFT := 0.06
const LANE_FIT_TOL := 0.06
const FRONTAGE := [5.0, 9.0]
const SLOPE_MAX := 5.0          # %
const ENTRY_ROAD_MAX := 0.5     # m
const GROUND_TOL := 0.05
const OV_SHRINK := 0.03
const FAR_DIST := 30.0
const FAR_MAX := 0.10
const MAIN_FILL_MIN := 0.70
const FIXED_COUNT := 9
const FIELDS := ["id", "ground_h", "footprint", "entrance_h", "road_h", "slope_pct", "clearance", "area_m2", "relief_m"]
const MACHIYA_FIELDS := ["frontage_m", "depth_m", "road", "entrance", "front_dir"]

var L: Dictionary
var R: Dictionary
var v: Node3D
var space: PhysicsDirectSpaceState3D
var terrain_rid: RID
var fails := 0
var net: Array
var outlines: Array
var ws: Array


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[PARCEL] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _run() -> void:
	L = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	R = L["parcel_rules"]
	v = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	await physics_frame
	await physics_frame
	space = v.get_world_3d().direct_space_state
	terrain_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	net = PLib.network(L)
	outlines = TLib.built_outlines(L)
	ws = PLib.waters(L)
	_check_lanes()
	_check_parcels()
	_check_coverage()
	print("[PARCEL] 結果：%d 項失敗" % fails)
	quit(fails)


func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -80.0, z))
	var ex: Array[RID] = []
	for i in 8:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return NAN
		var col := hit["collider"] as CollisionObject3D
		if col.get_rid() == terrain_rid:
			return float(hit["position"].y)
		ex.append(col.get_rid())
	return NAN


func _hv(p: Vector2) -> float:
	return _ground(p.x, p.y)


# ─────────────────────────── 巷道 ───────────────────────────

func _check_lanes() -> void:
	var lanes := PLib.lanes(L)
	var grp := v.get_node_or_null("Roads/Alleys/Lanes")
	check("巷道 %d 條，場景 Roads/Alleys/Lanes 有 %d 個" % [lanes.size(), 0 if grp == null else grp.get_child_count()],
		lanes.size() > 0 and grp != null and grp.get_child_count() == lanes.size())
	var main_w := INF
	for r in net:
		if r["cls"] == "main":
			main_w = minf(main_w, 2.0 * float(r["hw"]))
	for r in lanes:
		var nm: String = r["name"]
		var pts: PackedVector2Array = r["pts"]
		var w := 2.0 * float(r["hw"])
		var bad: Array = []
		if w < LANE_W[0] - 0.01 or w > LANE_W[1] + 0.01 or w >= main_w:
			bad.append("寬 %.1f m" % w)
		var tmax := 0.0
		for i in range(1, pts.size() - 1):
			tmax = maxf(tmax, rad_to_deg(absf((pts[i] - pts[i - 1]).angle_to(pts[i + 1] - pts[i]))))
		if tmax < LANE_TURN_MIN:
			bad.append("最大轉折 %.0f°" % tmax)
		var joined := false
		for o in net:
			if o["name"] == nm:
				continue
			var op: PackedVector2Array = o["pts"]
			for k in op.size() - 1:
				if pts[0].distance_to(Geometry2D.get_closest_point_to_segment(pts[0], op[k], op[k + 1])) <= float(o["hw"]) + 0.5:
					joined = true
		if not joined:
			bad.append("起點未接路")
		var smp := _along(pts, 1.0)
		var omin := INF
		var wmin := INF
		for p in smp:
			if not _near_other(p, nm):   # 路口段屬於相接的道路，平台判定跳過
				omin = minf(omin, TLib.outline_sd(outlines, p))
			for wb in ws:
				wmin = minf(wmin, PLib.water_edge_d(wb, p))
		if omin < float(r["hw"]) - 0.01:
			bad.append("出平台（路緣離外框 %.1f m）" % (omin - float(r["hw"])))
		if wmin < LANE_WATER_MIN:
			bad.append("離水岸 %.1f m" % wmin)
		for wb in ws:
			var wp: PackedVector2Array = wb["pts"]
			for a in pts.size() - 1:
				for b in wp.size() - 1:
					if Geometry2D.segment_intersects_segment(pts[a], pts[a + 1], wp[b], wp[b + 1]) != null:
						bad.append("跨 %s" % wb["name"])
		var gmax := 0.0
		for i in range(1, smp.size()):
			gmax = maxf(gmax, absf(_hv(smp[i]) - _hv(smp[i - 1])) / maxf(smp[i].distance_to(smp[i - 1]), 0.01))
		if gmax > LANE_GRADE_MAX:
			bad.append("縱坡 %.1f%%" % (gmax * 100.0))
		# 路面貼地
		var fit := 0.0
		var mi := grp.get_node_or_null(nm) as MeshInstance3D if grp != null else null
		if mi == null:
			bad.append("場景缺節點")
		else:
			var arr: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for vt in arr:
				var g := mi.global_transform * vt
				var gy := _ground(g.x, g.z)
				if not is_nan(gy):
					fit = maxf(fit, absf(g.y - gy - LANE_LIFT))
			if fit > LANE_FIT_TOL:
				bad.append("路面離地偏差 %.2f m" % fit)
		check("巷道 %s（%s）寬 %.1f m、長 %.0f m、最大轉折 %.0f°、縱坡 %.1f%%、離水 %.1f m、路面貼地偏差 %.2f m%s" % [
			nm, r["label"], w, _len(pts), tmax, gmax * 100.0, wmin, fit, "" if bad.is_empty() else "：" + "、".join(bad)],
			bad.is_empty())


func _along(pts: PackedVector2Array, st: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in pts.size() - 1:
		var n := maxi(1, int(ceil(pts[k].distance_to(pts[k + 1]) / st)))
		for i in n:
			out.append(pts[k].lerp(pts[k + 1], float(i) / n))
	out.append(pts[pts.size() - 1])
	return out


func _len(pts: PackedVector2Array) -> float:
	var s := 0.0
	for k in pts.size() - 1:
		s += pts[k].distance_to(pts[k + 1])
	return s


# ─────────────────────────── 地塊 ───────────────────────────

func _check_parcels() -> void:
	if not FileAccess.file_exists(PARCELS):
		check("parcels.json 存在", false)
		return
	var PJ: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PARCELS))
	var recs: Array = PJ["parcels"]
	check("parcels.json 版本 %s ＝ layout %s" % [PJ["layout_version"], L["version"]], PJ["layout_version"] == L["version"])
	# 與目前 layout 同步：用同一算法重算（地面高取 Terrain 碰撞）
	var re: Dictionary = PLib.parcels(L, net, _hv)
	var want := {}
	for p in re["parcels"]:
		want[p["id"]] = p["poly"]
	for p in re["fixed"]:
		want[p["id"]] = p["poly"]
	var diff := 0
	for r in recs:
		if not want.has(r["id"]) or _maxd(TLib.pts(r["footprint"]), want[r["id"]]) > 0.02:
			diff += 1
	check("parcels.json 與目前 layout 重算一致（%d 塊 vs 重算 %d 塊，不一致 %d）" % [recs.size(), want.size(), diff],
		diff == 0 and want.size() == recs.size())
	# 場景 Marker
	var markers := {}
	for d in v.get_node("Districts").get_children():
		var pg := d.get_node_or_null("Parcels")
		if pg != null:
			for m in pg.get_children():
				markers[String(m.name)] = m
	var miss := 0
	for r in recs:
		if not markers.has(r["id"]):
			miss += 1
	check("場景地塊 Marker %d 個 ＝ 檔案 %d 塊（缺 %d）" % [markers.size(), recs.size(), miss], miss == 0 and markers.size() == recs.size())
	# §11 欄位
	var nf := 0
	for r in recs:
		for f in FIELDS:
			if not r.has(f):
				nf += 1
		if r["kind"] == "machiya":
			for f in MACHIYA_FIELDS:
				if not r.has(f):
					nf += 1
		elif not (r["clearance"] as Dictionary).has("front_gap_m"):
			nf += 1
	check("§11 欄位（Parcel ID／Ground Height／Footprint／Entrance Height／Road Height／Slope／Frontage／Clearance）缺 %d 項" % nf, nf == 0)
	# 幾何
	var polys: Array = []
	var bbs: Array = []
	var inner: Array = []   # 內縮 OV_SHRINK：相鄰無間距的地塊共用邊，檔案座標取到 0.01 m 會產生假重疊
	for r in recs:
		var pp := TLib.pts(r["footprint"])
		polys.append(pp)
		bbs.append(_bbox(pp))
		var sh := Geometry2D.offset_polygon(pp, -OV_SHRINK, Geometry2D.JOIN_MITER)
		inner.append(sh[0] if not sh.is_empty() else pp)
	var ov := 0
	var ov_ex := ""
	for i in polys.size():
		for j in range(i + 1, polys.size()):
			if (bbs[i] as Rect2).intersects(bbs[j]) and PLib.overlap_area(inner[i], inner[j]) > 0.0:
				ov += 1
				ov_ex = "%s×%s" % [recs[i]["id"], recs[j]["id"]]
	check("地塊互不重疊（各內縮 %.2f m 後，%d 對%s）" % [OV_SHRINK, ov, "，例 " + ov_ex if ov > 0 else ""], ov == 0)
	var keep := PLib.keep_clear(L, net, ws)
	var wm: Dictionary = R["water_margin"]
	var cnt := {"road": 0, "outline": 0, "water": 0, "keep": 0, "size": 0, "relief": 0, "slope": 0, "entry": 0, "ground": 0}
	var ex := {}
	var nmach := 0
	var ground_max := 0.0
	var entry_max := 0.0
	var slope_max := 0.0
	for i in recs.size():
		var r: Dictionary = recs[i]
		var poly: PackedVector2Array = polys[i]
		var id: String = r["id"]
		var c := Vector2(float(r["center"][0]), float(r["center"][1]))
		var gdel := absf(float(r["ground_h"]) - _ground(c.x, c.y))
		if r["kind"] != "machiya":
			continue
		nmach += 1
		ground_max = maxf(ground_max, gdel)
		if gdel > GROUND_TOL + float(r["relief_m"]):
			_bump(cnt, ex, "ground", id)
		for rd in net:
			if not (rd["bb"] as Rect2).grow(1.0).intersects(bbs[i]):
				continue
			if PLib.poly_line_d(poly, rd["pts"]) < float(rd["hw"]) + float(R["road_gap"]) - 0.02:
				_bump(cnt, ex, "road", id + "/" + String(rd["name"]))
		var smp := PLib.edge_samples(poly, 1.0)
		for p in smp:
			if TLib.outline_sd(outlines, p) < float(R["outline_margin"]) - 0.02:
				_bump(cnt, ex, "outline", id)
				break
		for wb in ws:
			var m := float(wm.get(wb["name"], wm["default"]))
			for p in smp:
				if PLib.water_edge_d(wb, p) < m - 0.02:
					_bump(cnt, ex, "water", id + "/" + String(wb["name"]))
					break
		for kc in keep:
			if PLib.poly_point_d(poly, kc["at"]) < float(kc["r"]) - 0.02:
				_bump(cnt, ex, "keep", id + "/" + String(kc["why"]))
		var dr: Array = R["infill_depth"] if bool(r.get("infill", false)) else R["depth"].get(r["district"], R["depth"]["default"])
		var fw := float(r["frontage_m"])
		var dp := float(r["depth_m"])
		if fw < FRONTAGE[0] - 0.01 or fw > FRONTAGE[1] + 0.01 or dp < float(dr[0]) - 0.02 or dp > float(dr[1]) + 0.02:
			_bump(cnt, ex, "size", "%s %.1f×%.1f" % [id, fw, dp])
		if float(r["relief_m"]) > float(R["max_relief"]):
			_bump(cnt, ex, "relief", id)
		slope_max = maxf(slope_max, float(r["slope_pct"]))
		if float(r["slope_pct"]) > SLOPE_MAX:
			_bump(cnt, ex, "slope", id)
		var ed := absf(float(r["entrance_h"]) - float(r["road_h"]))
		entry_max = maxf(entry_max, ed)
		if ed > ENTRY_ROAD_MAX:
			_bump(cnt, ex, "entry", id)
	check("町家地塊 %d 塊不壓道路／巷道路幅（留 %.1f m）：%d 違規%s" % [nmach, float(R["road_gap"]), cnt["road"], _ex(ex, "road")], cnt["road"] == 0)
	check("町家地塊在建成區平台內（外框內縮 %.1f m）：%d 違規%s" % [float(R["outline_margin"]), cnt["outline"], _ex(ex, "outline")], cnt["outline"] == 0)
	check("町家地塊離水道（主河 %.0f m／渠、溪 %.0f m）：%d 違規%s" % [float(wm["MainRiver"]), float(wm["default"]), cnt["water"], _ex(ex, "water")], cnt["water"] == 0)
	check("町家地塊避開 keep_clear（水車、龍神像、大鳥居、參道鳥居、傳送點、任務錨點、橋頭，共 %d 處）：%d 違規%s" % [keep.size(), cnt["keep"], _ex(ex, "keep")], cnt["keep"] == 0)
	check("町家臨路面 %.0f–%.0f m、縱深在分區範圍：%d 違規%s" % [FRONTAGE[0], FRONTAGE[1], cnt["size"], _ex(ex, "size")], cnt["size"] == 0)
	check("地塊內高低差 ≤ %.1f m、坡度 ≤ %.0f%%（最大 %.1f%%）：%d／%d 違規" % [float(R["max_relief"]), SLOPE_MAX, slope_max, cnt["relief"], cnt["slope"]],
		cnt["relief"] == 0 and cnt["slope"] == 0)
	check("入口與路面高差 ≤ %.1f m（最大 %.2f m）：%d 違規%s" % [ENTRY_ROAD_MAX, entry_max, cnt["entry"], _ex(ex, "entry")], cnt["entry"] == 0)
	check("記錄地面高與目前地形一致（中心點最大差 %.3f m）：%d 違規%s" % [ground_max, cnt["ground"], _ex(ex, "ground")], cnt["ground"] == 0)
	# 地標固定地塊
	var lms := {}
	for lm in L["landmarks"]:
		lms[String(lm["id"])] = lm
	var nfix := 0
	var fix_bad: Array = []
	for i in recs.size():
		var r: Dictionary = recs[i]
		if r["kind"] != "landmark":
			continue
		nfix += 1
		var lm: Dictionary = lms.get(String(r["landmark"]), {})
		var at := Vector2(float(lm["at"][0]), float(lm["at"][1])) if not lm.is_empty() else Vector2.INF
		if lm.is_empty() or not Geometry2D.is_point_in_polygon(at, polys[i]):
			fix_bad.append(String(r["id"]))
		if float(r["footprint_road_overlap_m"]) > 0.0:
			print("[PARCEL]   INFO %s（%s）地標本體壓到路幅 %.2f m²（P0 凍結位置；P4 灰盒退縮或縮 footprint）" % [
				r["id"], r["label"], float(r["footprint_road_overlap_m"])])
	check("地標固定地塊 %d 塊（應 %d）、各含其地標中心%s" % [nfix, FIXED_COUNT, "" if fix_bad.is_empty() else "：" + ", ".join(fix_bad)],
		nfix == FIXED_COUNT and fix_bad.is_empty())


func _bump(cnt: Dictionary, ex: Dictionary, k: String, id: String) -> void:
	cnt[k] += 1
	if not ex.has(k):
		ex[k] = id


func _ex(ex: Dictionary, k: String) -> String:
	return "（例 %s）" % ex[k] if ex.has(k) else ""


func _maxd(a: PackedVector2Array, b: PackedVector2Array) -> float:
	if a.size() != b.size():
		return INF
	var m := 0.0
	for i in a.size():
		m = maxf(m, a[i].distance_to(b[i]))
	return m


func _bbox(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


# ─────────────────────────── 覆蓋 ───────────────────────────

func _check_coverage() -> void:
	var D: Dictionary = L["districts"]
	for k in D:
		if String(D[k]["kind"]) != "built":
			continue
		var poly := TLib.pts(D[k]["poly"])
		var bb := _bbox(poly)
		var tot := 0
		var far := 0
		var x := bb.position.x + 1.0
		while x < bb.end.x:
			var z := bb.position.y + 1.0
			while z < bb.end.y:
				var p := Vector2(x, z)
				if Geometry2D.is_point_in_polygon(p, poly) and TLib.outline_sd(outlines, p) >= 0.0:
					tot += 1
					var dmin := INF
					for rd in net:
						var rp: PackedVector2Array = rd["pts"]
						for s in rp.size() - 1:
							dmin = minf(dmin, p.distance_to(Geometry2D.get_closest_point_to_segment(p, rp[s], rp[s + 1])) - float(rd["hw"]))
					if dmin > FAR_DIST:
						far += 1
				z += 2.0
			x += 2.0
		var fr := float(far) / maxf(tot, 1)
		check("%s 建成地 %.2f ha，離最近路緣 > %.0f m 佔 %.1f%%（≤ %.0f%%）" % [k, tot * 4.0 / 10000.0, FAR_DIST, fr * 100.0, FAR_MAX * 100.0],
			fr <= FAR_MAX)
	# 主街臨路面：兩側每 1 m 取樣路緣外 1.5 m，建成區內（扣路口、keep_clear）有多少落在地塊內
	var recs: Array = (JSON.parse_string(FileAccess.get_file_as_string(PARCELS)) as Dictionary)["parcels"]
	var polys: Array = []
	for r in recs:
		polys.append(TLib.pts(r["footprint"]))
	var keep := PLib.keep_clear(L, net, ws)
	for rd in net:
		if rd["cls"] != "main":
			continue
		var pts: PackedVector2Array = rd["pts"]
		var hit := 0
		var gap := 0
		for side: float in [1.0, -1.0]:
			for k in pts.size() - 1:
				var t := (pts[k + 1] - pts[k]).normalized()
				var n := Vector2(-t.y, t.x) * side
				var s := 0.5
				while s < pts[k].distance_to(pts[k + 1]):
					var p := pts[k] + t * s + n * (float(rd["hw"]) + float(R["front_gap"]) + 1.0)
					s += 1.0
					if TLib.outline_sd(outlines, p) < 0.0 or _near_other(p, rd["name"]) or _in_keep(p, keep):
						continue
					var inside := false
					for pp in polys:
						if Geometry2D.is_point_in_polygon(p, pp):
							inside = true
							break
					if inside:
						hit += 1
					else:
						gap += 1
		var fr := float(hit) / maxf(hit + gap, 1)
		check("%s（%s）兩側臨路面地塊覆蓋 %.0f%%（≥ %.0f%%；扣路口、keep_clear、平台外）" % [rd["name"], rd["label"], fr * 100.0, MAIN_FILL_MIN * 100.0],
			fr >= MAIN_FILL_MIN)


func _near_other(p: Vector2, name: String) -> bool:
	for o in net:
		if o["name"] == name:
			continue
		var op: PackedVector2Array = o["pts"]
		for k in op.size() - 1:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, op[k], op[k + 1])) < float(o["hw"]) + 0.6:
				return true
	return false


func _in_keep(p: Vector2, keep: Array) -> bool:
	for kc in keep:
		if p.distance_to(kc["at"]) < float(kc["r"]) + 1.0:
			return true
	return false
