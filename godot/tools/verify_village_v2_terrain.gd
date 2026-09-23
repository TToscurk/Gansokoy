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
