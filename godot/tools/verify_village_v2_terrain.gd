extends SceneTree
## 人間之里 V2 地形驗證（P1 Terrain 驗收閘門，headless，不寫任何檔）。
##
##   Godot --headless --path godot --script res://tools/verify_village_v2_terrain.gd
##
## 每項印一行 [TERRAIN] PASS/FAIL；結尾 quit(失敗項數)。量的是場景裡真正的碰撞面（射線），不是產生器內部數值。
## 門檻出處：docs/plans/2026-09-23-人間之里V2重製規劃.md §9（P1 Terrain）。改門檻要先回報使用者。
##
## 檢查項（《人間之里 V2 全面重製計畫》§6 大地形：建築平台、道路坡度、世界邊界；Natural／Built／Transition 三分）：
##   凍結     Macro Layout 雜湊不變、北丘各峰地面高與 P0 凍結基準相同
##   平台     建成區（分區 closing 聯集）內地面＝基準面 ±FLAT_TOL（Built Terrain 相對平整）
##   過渡     平台外 0–EDGE_SPAN m 最大坡度 ≤ EDGE_CLIFF_DEG（低於玩家 floor_max_angle 52°，不留隱形牆或滑坡）
##   道路     10 m 視窗縱坡上限（主街 8 %、建成區 12 %、區外 15 %、田間路 5 %）
##   參道     HillApproach 接到山頂社殿 pad 外緣，2 m 視窗 ≤ APPROACH_MAX_DEG（可走；石段 P4／P5 再放）
##   面       地形碰撞面最陡 ≤ FACE_MAX_DEG（P0 基準：北丘 63°，無 > 65° 的面）
##   邊界     四邊腰高射線都打到 Collision/Boundary
##   預算     可見三角面 ≤ 600 萬；場景 load＋instantiate ≤ 3 秒（headless 參考值）
##   鋸齒     平台外框、河岸的等高線沿邊走不得鋸齒（網格走樣回歸：a056297 龍神橋東岸、平台斜邊）
##   接坡     Natural edge 站（gen/terrain_edges.json）往外 0–20 m 坡度 ≤ NATURAL_MAX_DEG
##   梯田     各田面＝farm_level ±FLAT_TOL、至少 3 階；灌溉揚程、排水出水高（terrain.farm_terraces）
##   橋長     Bridge_* 長度在 terrain.bridge_spans 容許範圍內

const Freeze := preload("res://tools/village_v2_freeze.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const SCENE := "res://maps/village_v2/village_v2.tscn"

const FLAT_TOL := 0.05            # 建成區平台與基準面高差上限（m）
const EDGE_CLIFF_DEG := 50.0      # 平台外框往外 0–12 m 的最大坡度（水道、路面整地帶、地塊除外）
const EDGE_SPAN := 12.0
const APPROACH_MAX_DEG := 35.0    # 參道＋接坡 2 m 視窗最大坡度（玩家 floor_max_angle 52°）
const FACE_MAX_DEG := 65.0
const STAIR_ROADS := ["HillApproach"]
const GRADE_MAIN_BUILT := 0.08    # 10 m 視窗縱坡上限
const GRADE_BUILT := 0.12
const GRADE_OUTSIDE := 0.15
const GRADE_FARM := 0.05
const BUDGET_TRIS := 6000000
const BUDGET_LOAD_MS := 3000.0
## P0 凍結基準（v2-layout-0.3，2026-09-24 量測）：北丘各峰地面高。P1 不得改變北丘 Macro 輪廓。
const HILL_BASE := {"主丘": 34.166, "西肩": 29.028, "東次峰": 27.990, "東長肩": 9.184}
const HILL_TOL := 0.05
## 鋸齒回歸：沿邊每 0.5 m 一站，往外量「地面離開平台／到達河岸等高線」的距離 t；
## t 減去前後 ±3 m 的中位數＝走樣造成的來回擺動（直邊上應 ≈ 0）。取 95 百分位。
const WOBBLE_STATION := 0.5
const WOBBLE_WIN := 6            # ±6 站＝±3 m
const WOBBLE_P95_MAX := 0.25     # m
const EDGE_DEPART := 0.3         # 地面離開平台基準面多少算「坡開始」
const BANK_LEVEL := 0.6          # 河岸等高線＝主河水位 + 0.6 m
const DRAGON_EAST := Rect2(400, -215, 70, 90)   # a056297 審圖指出的龍神橋東岸（x 400–470）
const EDGES := "res://maps/village_v2/gen/terrain_edges.json"
const NATURAL_MAX_DEG := 40.0   # 產生器把接坡 > blend_deg 35° 的站標成 Retaining；實測（網格內插、轉角）留 5° 餘裕

var L: Dictionary
var fails := 0
var v: Node3D
var space: PhysicsDirectSpaceState3D
var terrain_rid: RID
var outlines: Array
var road_lines: Array = []     # [PackedVector2Array, half_w]
var water_lines: Array = []    # [PackedVector2Array, 排除距離]
var pad_list: Array = []


func check(label: String, ok: bool) -> void:
	print("[TERRAIN] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	L = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var ferr: String = Freeze.check(L)
	check("凍結：layout 有 approval.freeze", not L.get("approval", {}).get("freeze", {}).is_empty())
	check("凍結：Macro Layout 與核可值一致 %s" % ferr, ferr == "")
	outlines = TLib.built_outlines(L)
	for r in L["roads"]:
		road_lines.append([TLib.pts(r["pts"]), float(r["half_w"])])
	water_lines.append([TLib.pts(L["water"]["MainRiver"]["pts"]), 28.0])
	water_lines.append([TLib.pts(L["water"]["Canal"]["pts"]), 9.0])
	for s in L["water"]["Streams"]:
		water_lines.append([TLib.pts(s["pts"]), 7.0])
	pad_list = TLib.pads(L)
	var t0 := Time.get_ticks_msec()
	v = (load(SCENE) as PackedScene).instantiate()
	var load_ms := float(Time.get_ticks_msec() - t0)
	root.add_child(v)
	for i in 3:
		await physics_frame
	space = v.get_world_3d().direct_space_state
	var tc := v.get_node_or_null("Collision/TerrainCollision") as StaticBody3D
	check("場景有 Collision/TerrainCollision", tc != null)
	if tc == null:
		quit(fails)
		return
	terrain_rid = tc.get_rid()
	_check_hill()
	_check_built_flat()
	_check_edges()
	_check_roads()
	_check_approach()
	_check_faces(tc)
	_check_boundary()
	_check_budget(load_ms)
	_check_wobble()
	_check_natural_edges()
	_check_farm()
	_check_bridges()
	print("[TERRAIN] 結果：%d 項失敗" % fails)
	quit(fails)


## 地形（可選含橋面）射線高度；打不到回 NAN。
func _ground(x: float, z: float, bridges := false) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -80.0, z))
	var ex: Array[RID] = []
	for i in 8:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return NAN
		var col := hit["collider"] as CollisionObject3D
		if col.get_rid() == terrain_rid or (bridges and String(col.name).begins_with("Bridge_")):
			return float(hit["position"].y)
		ex.append(col.get_rid())
	return NAN


func _near_road(p: Vector2, extra: float) -> bool:
	for r in road_lines:
		if TLib.polyline_d(r[0], p) < float(r[1]) + extra:
			return true
	return false


func _near_water(p: Vector2) -> bool:
	for w in water_lines:
		if TLib.polyline_d(w[0], p) < float(w[1]):
			return true
	return false


func _near_pad(p: Vector2, extra: float) -> bool:
	for pd in pad_list:
		if p.distance_to(pd[0]) < float(pd[1]) + extra:
			return true
	return false


func _check_hill() -> void:
	var hill: Dictionary = L["hill"]
	var peaks := {"主丘": hill["center"]}
	for lb in hill.get("lobes", []):
		peaks[String(lb["label"])] = lb["center"]
	for k in peaks:
		var c: Array = peaks[k]
		var y := _ground(float(c[0]), float(c[1]))
		print("[TERRAIN]   北丘 %s (%.0f, %.0f) 地面 %.3f m" % [k, float(c[0]), float(c[1]), y])
		if HILL_BASE.has(k):
			check("北丘 %s 地面 %.2f m（凍結基準 %.2f ±%.2f）" % [k, y, float(HILL_BASE[k]), HILL_TOL],
				absf(y - float(HILL_BASE[k])) <= HILL_TOL)


func _outline_bbox() -> Rect2:
	var bb := Rect2(outlines[0][0], Vector2.ZERO)
	for poly in outlines:
		for q in poly:
			bb = bb.expand(q)
	return bb


func _check_built_flat() -> void:
	var bb := _outline_bbox()
	var n := 0
	var bad := 0
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var x := floorf(bb.position.x)
	while x <= bb.end.x:
		var z := floorf(bb.position.y)
		while z <= bb.end.y:
			var p := Vector2(x, z)
			z += 2.0
			if TLib.outline_sd(outlines, p) < 0.0:
				continue
			if _near_road(p, 5.0) or _near_water(p) or _near_pad(p, 5.0):
				continue
			var y := _ground(p.x, p.y)
			if is_nan(y):
				continue
			n += 1
			var dv := absf(y - TLib.plane(L, p.y))
			if dv > FLAT_TOL:
				bad += 1
			if dv > worst:
				worst = dv
				worst_at = p
		x += 2.0
	check("建成區平台：%d 點中 %d 點偏離基準面 > %.2f m（最大 %.2f m @ (%.0f, %.0f)）" % [
		n, bad, FLAT_TOL, worst, worst_at.x, worst_at.y], n > 0 and bad == 0)


func _check_edges() -> void:
	var F: Dictionary = L["frame"]
	var frame := Rect2(float(F["x0"]), float(F["z0"]), float(F["x1"]) - float(F["x0"]), float(F["z1"]) - float(F["z0"]))
	var n := 0
	var worst := 0.0
	var worst_at := Vector2.ZERO
	for poly in outlines:
		for e in poly.size():
			var a: Vector2 = poly[e]
			var b: Vector2 = poly[(e + 1) % poly.size()]
			var seg := a.distance_to(b)
			var t := (b - a) / seg
			var nrm := Vector2(-t.y, t.x)
			if TLib.outline_sd(outlines, (a + b) * 0.5 + nrm * 0.5) > 0.0:
				nrm = -nrm
			var s := 2.0
			while s < seg - 1.0:
				var q := a + t * s
				s += 4.0
				var prev := NAN
				for d in int(EDGE_SPAN) + 1:
					var o := q + nrm * float(d)
					if not frame.has_point(o) or _near_road(o, 5.0) or _near_water(o) or _near_pad(o, 5.0):
						prev = NAN
						continue
					var y := _ground(o.x, o.y)
					if not is_nan(prev) and not is_nan(y):
						n += 1
						var deg := rad_to_deg(atan(absf(y - prev)))
						if deg > worst:
							worst = deg
							worst_at = o
					prev = y
	check("平台外框往外 0–%.0f m：%d 段中最大坡度 %.1f°（≤ %.0f° @ (%.0f, %.0f)）" % [
		EDGE_SPAN, n, worst, EDGE_CLIFF_DEG, worst_at.x, worst_at.y], n > 0 and worst <= EDGE_CLIFF_DEG)


func _check_roads() -> void:
	for r in L["roads"]:
		var name := String(r["name"])
		if name in STAIR_ROADS:
			continue
		var cls := String(r["class"])
		var pts: PackedVector2Array = TLib.resample(TLib.pts(r["pts"]), 1.0)
		var h := PackedFloat32Array()
		for q in pts:
			h.append(_ground(q.x, q.y, true))
		var worst := 0.0
		var worst_g := 0.0
		var worst_lim := 0.0
		var worst_at := Vector2.ZERO
		for i in pts.size() - 10:
			if is_nan(h[i]) or is_nan(h[i + 10]):
				continue
			var g := absf(h[i + 10] - h[i]) / 10.0
			var mid: Vector2 = pts[i + 5]
			var lim := GRADE_OUTSIDE
			if cls == "farm":
				lim = GRADE_FARM
			elif TLib.outline_sd(outlines, mid) >= 0.0:
				lim = GRADE_MAIN_BUILT if cls == "main" else GRADE_BUILT
			if g / lim > worst:
				worst = g / lim
				worst_g = g
				worst_lim = lim
				worst_at = mid
		check("道路 %-16s 縱坡 10 m 視窗最大 %.1f%%（上限 %.0f%% @ (%.0f, %.0f)）" % [
			name, worst_g * 100.0, worst_lim * 100.0, worst_at.x, worst_at.y], worst <= 1.0)


func _check_approach() -> void:
	var line := PackedVector2Array()
	var pad: Array = []
	for r in L["roads"]:
		if String(r["name"]) == "HillApproach":
			line = TLib.pts(r["pts"])
	for pd in pad_list:
		if String(pd[2]) == "LANDMARK_NORTH_HILL":
			pad = pd
	check("參道 HillApproach 與山頂社殿 pad 都存在", not line.is_empty() and not pad.is_empty())
	if line.is_empty() or pad.is_empty():
		return
	var end := line[line.size() - 1]
	var c: Vector2 = pad[0]
	line.append(c + (end - c).normalized() * float(pad[1]))
	var pts: PackedVector2Array = TLib.resample(line, 0.5)
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var h := PackedFloat32Array()
	for q in pts:
		h.append(_ground(q.x, q.y))
	for i in pts.size() - 4:
		if is_nan(h[i]) or is_nan(h[i + 4]):
			continue
		var deg := rad_to_deg(atan(absf(h[i + 4] - h[i]) / 2.0))
		if deg > worst:
			worst = deg
			worst_at = pts[i + 2]
	check("參道＋接坡到社殿 pad：2 m 視窗最大坡度 %.1f°（≤ %.0f° @ (%.0f, %.0f)）" % [
		worst, APPROACH_MAX_DEG, worst_at.x, worst_at.y], worst <= APPROACH_MAX_DEG)


func _check_boundary() -> void:
	var b := v.get_node_or_null("Collision/Boundary") as StaticBody3D
	check("場景有 Collision/Boundary", b != null)
	if b == null:
		return
	var F: Dictionary = L["frame"]
	var x0 := float(F["x0"])
	var x1 := float(F["x1"])
	var z0 := float(F["z0"])
	var z1 := float(F["z1"])
	var sides := [
		["北", Vector2(0, -1)], ["南", Vector2(0, 1)], ["西", Vector2(-1, 0)], ["東", Vector2(1, 0)]]
	for sd in sides:
		var dir: Vector2 = sd[1]
		var n := 0
		var miss := 0
		var miss_at := Vector2.ZERO
		var s := 2.0
		var length := (x1 - x0) if dir.y != 0.0 else (z1 - z0)
		while s < length - 2.0:
			var p: Vector2
			if dir == Vector2(0, -1):
				p = Vector2(x0 + s, z0 + 1.0)
			elif dir == Vector2(0, 1):
				p = Vector2(x0 + s, z1 - 1.0)
			elif dir == Vector2(-1, 0):
				p = Vector2(x0 + 1.0, z0 + s)
			else:
				p = Vector2(x1 - 1.0, z0 + s)
			s += 4.0
			var y := _ground(p.x, p.y)
			if is_nan(y):
				continue
			n += 1
			var from := Vector3(p.x, y + 1.0, p.y)
			var to := from + Vector3(dir.x, 0.0, dir.y) * 3.0
			var q := PhysicsRayQueryParameters3D.create(from, to)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or hit["collider"] != b:
				miss += 1
				miss_at = p
		check("邊界牆 %s 緣：%d 點中 %d 點腰高擋不住（例 (%.0f, %.0f)）" % [
			sd[0], n, miss, miss_at.x, miss_at.y], n > 0 and miss == 0)


func _check_budget(load_ms: float) -> void:
	var tris := 0
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null or not (mi as MeshInstance3D).is_visible_in_tree():
			continue
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				tris += (idx as PackedInt32Array).size() / 3
			else:
				tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	check("可見三角面 %d（≤ %d）" % [tris, BUDGET_TRIS], tris <= BUDGET_TRIS)
	check("village_v2.tscn load()+instantiate() %.0f ms（≤ %.0f ms，headless 參考值）" % [load_ms, BUDGET_LOAD_MS],
		load_ms <= BUDGET_LOAD_MS)


func _check_faces(tc: StaticBody3D) -> void:
	var shape := (tc.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D
	var f := shape.get_faces()
	var worst := 0.0
	var worst_at := Vector3.ZERO
	var steep := 0
	for i in range(0, f.size(), 3):
		var n := (f[i + 1] - f[i]).cross(f[i + 2] - f[i]).normalized()
		var deg := rad_to_deg(acos(clampf(absf(n.y), 0.0, 1.0)))
		if deg > FACE_MAX_DEG:
			steep += 1
		if deg > worst:
			worst = deg
			worst_at = (f[i] + f[i + 1] + f[i + 2]) / 3.0
	check("地形碰撞面 %d 面，最陡 %.1f°、> %.0f° 的面 %d（@ (%.0f, %.0f)）" % [
		f.size() / 3, worst, FACE_MAX_DEG, steep, worst_at.x, worst_at.z], steep == 0)


# ─────────────── 鋸齒回歸 ───────────────

## 沿 dir 往外走，回傳第一個 f(地面) 過零的距離（線性內插）；沒過零回 NAN。
func _first_cross(o: Vector2, dir: Vector2, max_t: float, level: float, above: bool) -> float:
	var prev := NAN
	var t := 0.0
	while t <= max_t:
		var q := o + dir * t
		var y := _ground(q.x, q.y)
		if is_nan(y):
			return NAN
		var f := (y - level) if above else (level - y)
		if f >= 0.0:
			if is_nan(prev) or t == 0.0:
				return t
			return t - 0.25 * f / (f - prev)
		prev = f
		t += 0.25
	return NAN


## ts：沿邊依序的 t（NAN＝該站排除）。回傳 [p95, max, max 所在索引]；只算前後窗都有值的站。
func _wobble(ts: PackedFloat32Array) -> Array:
	var dev := PackedFloat32Array()
	var idx := PackedInt32Array()
	for i in range(WOBBLE_WIN, ts.size() - WOBBLE_WIN):
		var win: Array = []
		for j in range(i - WOBBLE_WIN, i + WOBBLE_WIN + 1):
			if not is_nan(ts[j]):
				win.append(ts[j])
		if is_nan(ts[i]) or win.size() < 2 * WOBBLE_WIN + 1:
			continue
		win.sort()
		dev.append(absf(ts[i] - float(win[WOBBLE_WIN])))
		idx.append(i)
	if dev.is_empty():
		return [0.0, 0.0, -1, 0]
	var s := dev.duplicate()
	s.sort()
	var mi := 0
	for k in dev.size():
		if dev[k] > dev[mi]:
			mi = k
	return [s[int(0.95 * (s.size() - 1))], dev[mi], idx[mi], dev.size()]


func _excluded(p: Vector2, water_ok: bool) -> bool:
	if _near_road(p, 6.0) or _near_pad(p, 6.0):
		return true
	return (not water_ok) and _near_water(p)


func _check_wobble() -> void:
	var F: Dictionary = L["frame"]
	var frame := Rect2(float(F["x0"]), float(F["z0"]), float(F["x1"]) - float(F["x0"]), float(F["z1"]) - float(F["z0"])).grow(-2.0)
	# 平台外框：每條直邊獨立算（轉角處 t 本來就會變）
	var all_t := PackedFloat32Array()
	var worst := [0.0, 0.0, -1, 0]
	var worst_at := Vector2.ZERO
	for poly in outlines:
		for e in poly.size():
			var a: Vector2 = poly[e]
			var b: Vector2 = poly[(e + 1) % poly.size()]
			var seg := a.distance_to(b)
			if seg < 2.0 * WOBBLE_WIN * WOBBLE_STATION + 6.0:
				continue
			var tg := (b - a) / seg
			var nrm := Vector2(-tg.y, tg.x)
			if TLib.outline_sd(outlines, (a + b) * 0.5 + nrm * 0.5) > 0.0:
				nrm = -nrm
			var ts := PackedFloat32Array()
			var pos: Array = []
			var s := 3.0
			while s < seg - 3.0:
				var o := a + tg * s
				s += WOBBLE_STATION
				pos.append(o)
				var bad := not frame.has_point(o + nrm * 15.0)
				for d in [0.0, 5.0, 10.0, 15.0]:
					bad = bad or _excluded(o + nrm * d, false)
				if bad:
					ts.append(NAN)
					continue
				var y0 := TLib.plane(L, o.y)
				var up := _first_cross(o, nrm, 15.0, y0 + EDGE_DEPART, true)
				var dn := _first_cross(o, nrm, 15.0, y0 - EDGE_DEPART, false)
				ts.append(minf(up if not is_nan(up) else INF, dn if not is_nan(dn) else INF))
				if is_inf(ts[ts.size() - 1]):
					ts[ts.size() - 1] = NAN
			var w := _wobble(ts)
			all_t.append(w[0])
			if float(w[0]) > float(worst[0]):
				worst = w
				worst_at = pos[int(w[2])] if int(w[2]) >= 0 else Vector2.ZERO
	var edge_p95 := 0.0
	for x in all_t:
		edge_p95 = maxf(edge_p95, x)
	check("鋸齒：平台外框坡腳線擺動 p95 最差邊 %.2f m（≤ %.2f，該邊最大 %.2f m @ (%.0f, %.0f)）" % [
		edge_p95, WOBBLE_P95_MAX, float(worst[1]), worst_at.x, worst_at.y], edge_p95 <= WOBBLE_P95_MAX)
	# 主河兩岸：沿中心線，每側量到「水位＋BANK_LEVEL」等高線的距離
	var rl := TLib.resample(TLib.pts(L["water"]["MainRiver"]["pts"]), WOBBLE_STATION)
	var lvl := float(L["heights"]["river_water"]) + BANK_LEVEL
	for side in [1.0, -1.0]:
		var ts := PackedFloat32Array()
		var ts_de := PackedFloat32Array()
		for i in rl.size():
			var tg := (rl[mini(i + 1, rl.size() - 1)] - rl[maxi(i - 1, 0)]).normalized()
			var nrm: Vector2 = Vector2(-tg.y, tg.x) * float(side)
			var o: Vector2 = rl[i]
			var t := _first_cross(o, nrm, 45.0, lvl, true)
			var q: Vector2 = o + nrm * (t if not is_nan(t) else 0.0)
			if is_nan(t) or not frame.has_point(q) or _near_road(q, 8.0) or _near_pad(q, 8.0) \
					or TLib.polyline_d(water_lines[1][0], q) < 12.0:
				ts.append(NAN)
			else:
				ts.append(t)
			ts_de.append(ts[i] if DRAGON_EAST.has_point(o) else NAN)
		var w := _wobble(ts)
		var wd := _wobble(ts_de)
		var at: Vector2 = rl[int(w[2])] if int(w[2]) >= 0 else Vector2.ZERO
		check("鋸齒：主河%s岸等高線（水位+%.1f m）擺動 p95 %.2f m（≤ %.2f，最大 %.2f m @ (%.0f, %.0f)，%d 站）" % [
			"左" if side > 0.0 else "右", BANK_LEVEL, float(w[0]), WOBBLE_P95_MAX, float(w[1]), at.x, at.y, int(w[3])],
			float(w[0]) <= WOBBLE_P95_MAX)
		check("鋸齒：龍神橋東岸段（%s側）擺動 p95 %.2f m、最大 %.2f m（≤ %.2f，%d 站）" % [
			"左" if side > 0.0 else "右", float(wd[0]), float(wd[1]), WOBBLE_P95_MAX, int(wd[3])],
			int(wd[3]) == 0 or float(wd[0]) <= WOBBLE_P95_MAX)


func _check_natural_edges() -> void:
	var E = JSON.parse_string(FileAccess.get_file_as_string(EDGES))
	check("平台邊分類檔 %s 存在" % EDGES, typeof(E) == TYPE_DICTIONARY)
	if typeof(E) != TYPE_DICTIONARY:
		return
	var apron := float(E["apron"])
	var n := 0
	var worst := 0.0
	var worst_at := Vector2.ZERO
	for st in E["stations"]:
		if String(st[4]) != "natural":
			continue
		var o := Vector2(float(st[0]), float(st[1]))
		var nrm := Vector2(float(st[2]), float(st[3]))
		var prev := NAN
		# 只量平台接坡帶（blend_max 內）；再往外是原本的 Natural Terrain（北丘自身最陡 63°，另有面坡度檢查）
		for d in range(0, int(TLib.param(L, "platform_blend_max")) + 1):
			var q := o + nrm * (apron + float(d))
			if _near_road(q, 5.0) or _near_water(q) or _near_pad(q, 5.0):
				prev = NAN
				continue
			var y := _ground(q.x, q.y)
			if not is_nan(prev) and not is_nan(y):
				n += 1
				var deg := rad_to_deg(atan(absf(y - prev)))
				if deg > worst:
					worst = deg
					worst_at = q
			prev = y
	check("Natural edge %.0f m／Retaining edge %.0f m；Natural 站接坡帶：%d 段最大坡度 %.1f°（≤ %.0f° @ (%.0f, %.0f)）" % [
		float(E["natural_m"]), float(E["retaining_m"]), n, worst, NATURAL_MAX_DEG, worst_at.x, worst_at.y],
		n > 0 and worst <= NATURAL_MAX_DEG)


func _check_farm() -> void:
	var T: Dictionary = L.get("terrain", {}).get("farm_terraces", {})
	check("layout 有 terrain.farm_terraces", not T.is_empty())
	if T.is_empty():
		return
	var farm := TLib.pts(L["districts"]["Farmland"]["poly"])
	var levels := {}
	var n := 0
	var bad := 0
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var w := float(T["riser_w"])
	var xb: Array = T["x_breaks"]
	var zb: Array = T["z_breaks"]
	var x := 330.0
	while x <= 558.0:
		var z := -150.0
		while z <= 150.0:
			var p := Vector2(x, z)
			z += 2.0
			if not Geometry2D.is_point_in_polygon(p, farm) or Geometry2D.is_point_in_polygon(p, farm) == false:
				continue
			var inner := true
			for poly in [farm]:
				for k in poly.size():
					if p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[k], poly[(k + 1) % poly.size()])) < 14.0:
						inner = false
			for b in xb:
				if absf(p.x - float(b)) < w:
					inner = false
			for b in zb:
				if absf(p.y - float(b)) < w:
					inner = false
			if not inner or _near_road(p, 5.0) or _near_water(p) or _near_pad(p, 5.0) or TLib.outline_sd(outlines, p) > -30.0:
				continue
			var y := _ground(p.x, p.y)
			if is_nan(y):
				continue
			var want := TLib.farm_level(L, p)
			n += 1
			levels[snappedf(want, 0.01)] = true
			var dv := absf(y - want)
			if dv > FLAT_TOL:
				bad += 1
			if dv > worst:
				worst = dv
				worst_at = p
		x += 2.0
	var lv: Array = levels.keys()
	lv.sort()
	check("梯田田面：%d 點中 %d 點偏離田面高 > %.2f m（最大 %.2f m @ (%.0f, %.0f)）；田面 %d 階 %s" % [
		n, bad, FLAT_TOL, worst, worst_at.x, worst_at.y, lv.size(), str(lv)], n > 0 and bad == 0 and lv.size() >= 3)
	# 灌溉／排水：水渠最低水位 → 最高田面的揚程；最低田面 − 主河水位
	var canal := v.get_node_or_null("Water/Canal")
	var canal_min := NAN
	if canal != null and canal.has_meta("water_y_range"):
		canal_min = float(canal.get_meta("water_y_range")[0])
	var top := float(lv[lv.size() - 1]) if not lv.is_empty() else NAN
	var low := float(lv[0]) if not lv.is_empty() else NAN
	var lift := top - canal_min
	check("灌溉：最高田面 %.2f − 水渠最低水位 %.2f ＝ 揚程 %.2f m（≤ %.1f，水車）" % [
		top, canal_min, lift, float(T["irrigation_lift_max"])], not is_nan(lift) and lift <= float(T["irrigation_lift_max"]))
	var fb := low - float(L["heights"]["river_water"])
	check("排水：最低田面 %.2f − 主河水位 %.2f ＝ %.2f m（≥ %.1f）" % [
		low, float(L["heights"]["river_water"]), fb, float(T["freeboard_min"])], fb >= float(T["freeboard_min"]) - 0.001)


func _check_bridges() -> void:
	var bs := v.get_node("Roads/Bridges").get_children()
	check("橋 %d 座（P0 凍結 5 座）" % bs.size(), bs.size() == 5)
	for b in bs:
		var span := TLib.bridge_span(L, String(b.name))
		var len_m := float(b.get_meta("length_m", -1.0))
		if span.is_empty():
			check("%s 有 terrain.bridge_spans.preferred" % b.name, false)
			continue
		check("%s 長 %.1f m（preferred %.1f，容許 %.1f–%.1f）" % [b.name, len_m, float(span[0]), float(span[1]), float(span[2])],
			len_m >= float(span[1]) and len_m <= float(span[2]))
