extends SceneTree
## 道路接地穩定度＋橫越實走（真控制器、真碰撞）：RoadCollision ⟷ TerrainCollision 的交界。需要視窗。
##   godot --path godot --resolution 960x540 --script res://tools/walk_village_v2_road_cross.gd
## A. 橫越：路外 → 路面 → 對側路外。端點自動沿路找「站得下、直線上沒有地形／路面以外碰撞」的位置（找不到報 SKIP，
##    不再把端點放進路旁建築）。
## B. 交叉口：沿 A 路方向、斜 45°、垂直 90° 各穿越一次（±7 m；路徑上有建築就 SKIP）。
## 每段記錄：抵達、on_floor 比例、最長離地連續幀、每物理幀 |Δy| 最大、Terrain↔Road 切換次數、腳下碰撞種類。
## 穩定＝抵達 且 on_floor ≥ 97% 且 最長離地 ≤ 4 幀 且 |Δy|/幀 ≤ 0.16 m。

const CROSS := [
	# [名稱, 路寬 m, 路面上一點（三角形重心，離中線 ≤ 寬/6）, 路的走向上另一點]
	["MainStreet", 7.2, Vector2(261.47, -14.62), Vector2(265.59, -27.78)],
	["EntranceRoad", 7.0, Vector2(224.43, 159.16), Vector2(226.10, 145.82)],
	["CrossStreetMid", 6.0, Vector2(286.48, -25.65), Vector2(272.85, -23.07)],
	["WestAlley", 3.0, Vector2(202.49, -13.45), Vector2(205.72, 0.01)],
	["NWLane", 2.5, Vector2(185.03, -200.50), Vector2(189.64, -187.60)],
	["MidLane", 2.5, Vector2(241.28, -85.75), Vector2(228.36, -88.98)],
	["FarmPath_2", 2.4, Vector2(439.60, 10.67), Vector2(440.40, 3.33)],
	["FarmPath_5", 2.4, Vector2(449.33, 69.60), Vector2(449.4, 59.6)],
]
const JUNC := [
	["MainStreet×CrossStreetMid", Vector2(258.95, -21.05), Vector2(261.47, -14.62)],
	["MainStreet×CrossStreetSouth", Vector2(240.34, 51.01), Vector2(238.15, 57.60)],
	["HillFootStreet×NWLane", Vector2(200.94, -147.67), Vector2(207.01, -149.28)],
	["FarmPath_1×FarmPath_4", Vector2(371.93, -1.27), Vector2(372.38, -9.33)],
	["CrossStreetSouth×FarmPath_1", Vector2(370.87, 38.04), Vector2(362.59, 39.03)],
	["WestAlley×CrossStreetMid", Vector2(197.76, -19.52), Vector2(199.26, -26.91)],
	["HillApproach×HillFootStreet", Vector2(300.19, -131.01), Vector2(297.36, -136.66)],
	["FarmPath_2×FarmPath_4", Vector2(440.94, 1.46), Vector2(439.60, -3.33)],
]
var main: Node
var p: CharacterBody3D
var ground_rids := {}


func _init() -> void:
	_run.call_deferred()


func _ground(x: float, z: float) -> float:
	var sp: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	# 只認地形／路面（屋頂、建築基礎不算地面——否則端點會落在屋頂上）
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -30, z))
	var ex: Array[RID] = [p.get_rid()]
	for i in 12:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return 0.0
		if ground_rids.is_empty() or ground_rids.has(h.rid):
			return h.position.y
		ex.append(h.rid)
	return 0.0


## 站點與直線路徑上有沒有地形／路面以外的碰撞（膠囊 r0.32，底離地 0.06；地形與路面碰撞排除，所以低矮的基礎／台階也算障礙）
func _clear(a: Vector2, b: Vector2) -> bool:
	var sp: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.4
	var steps := maxi(2, int(a.distance_to(b) / 0.5))
	for i in steps + 1:
		var q := a.lerp(b, float(i) / steps)
		var prm := PhysicsShapeQueryParameters3D.new()
		prm.shape = cap
		prm.transform = Transform3D(Basis(), Vector3(q.x, _ground(q.x, q.y) + 0.06 + 0.7, q.y))
		prm.collision_mask = p.collision_mask
		var ex: Array[RID] = [p.get_rid()]
		for r: RID in ground_rids:
			ex.append(r)
		prm.exclude = ex
		if not sp.intersect_shape(prm, 1).is_empty():
			return false
	return true


func _walk(s0: Vector2, s1: Vector2) -> Dictionary:
	p.global_position = Vector3(s0.x, _ground(s0.x, s0.y) + 0.05, s0.y)
	p.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame
	var d := s1 - s0
	p.snap_yaw(atan2(-d.x, -d.y))
	Input.action_press("move_forward")
	var r := {"ok": false, "frames": 0, "floor": 0, "air_max": 0, "dy_max": 0.0, "switch": 0, "kinds": {}, "air_at": "", "dy_at": ""}
	var air_start := Vector3.ZERO
	var air := 0
	var last_y := p.global_position.y
	var last_kind := ""
	for i in 600:
		await physics_frame
		r["frames"] += 1
		var q := Vector2(p.global_position.x, p.global_position.z)
		if p.is_on_floor():
			r["floor"] += 1
			air = 0
		else:
			if air == 0:
				air_start = p.global_position
			air += 1
			if air > int(r["air_max"]):
				r["air_max"] = air
				r["air_at"] = "離地起點 (%.2f, %.2f, %.2f) 前一個地面 %s、地面落差 %.3f m" % [air_start.x, air_start.y, air_start.z, last_kind, air_start.y - _ground(p.global_position.x, p.global_position.z)]
		if absf(p.global_position.y - last_y) > float(r["dy_max"]):
			r["dy_at"] = "(%.1f, %.1f)" % [p.global_position.x, p.global_position.z]
		r["dy_max"] = maxf(r["dy_max"], absf(p.global_position.y - last_y))
		last_y = p.global_position.y
		var kind := ""
		for k in p.get_slide_collision_count():
			var c := p.get_slide_collision(k)
			if c.get_normal().y > 0.6 and c.get_collider() is Node:
				kind = String((c.get_collider() as Node).name)
		if kind != "":
			r["kinds"][kind] = true
			if last_kind != "" and kind != last_kind:
				r["switch"] += 1
			last_kind = kind
		if q.distance_to(s1) < 0.8:
			r["ok"] = true
			break
		p.snap_yaw(atan2(-(s1 - q).x, -(s1 - q).y))
	Input.action_release("move_forward")
	r["stable"] = r["ok"] and float(r["floor"]) / r["frames"] >= 0.97 and int(r["air_max"]) <= 4 and float(r["dy_max"]) <= 0.16
	return r


func _line(tag: String, r: Dictionary) -> String:
	return "%s %-40s %s %3d 幀  on_floor %5.1f%%  最長離地 %d 幀  |Δy|/幀 %.3f m  地面切換 %d %s" % [
		"✓" if r["stable"] else "✗", tag, "抵達" if r["ok"] else "未達", r["frames"], 100.0 * r["floor"] / r["frames"],
		r["air_max"], r["dy_max"], r["switch"], (r["kinds"] as Dictionary).keys()] + ("" if r["stable"] else "
        ↳ %s；|Δy| 最大於 %s" % [r["air_at"], r["dy_at"]])


func _run() -> void:
	var sf := root.get_node("/root/StoryFlags")
	sf.set_flag("woke_in_trail", true)
	sf.set_flag("met_reimu", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 30:
		await process_frame
	main.load_map("village_v2", "")
	for i in 90:
		await process_frame
	p = main.player
	for n in ["Collision/TerrainCollision", "Collision/RoadCollision"]:
		var b := main.map_root.get_node_or_null(n) as CollisionObject3D
		if b:
			ground_rids[b.get_rid()] = true
	var bad := 0
	var n_pass := 0
	for c in CROSS:
		var a0: Vector2 = c[2]
		var t: Vector2 = (c[3] - a0).normalized()
		var nn := Vector2(-t.y, t.x)
		var hw := float(c[1]) * (0.5 + 1.0 / 6.0) + 1.5
		var picked := Vector2.INF
		var used := 0.0
		var offs: Array = [0.0]
		for k in range(1, 26):
			offs.append(4.0 * k)
			offs.append(-4.0 * k)
		for off in offs:   # 沿路 ±100 m（主街兩側多半緊貼町家，要找到有空地的那一段）
			var a := a0 + t * float(off)
			if _clear(a + nn * hw, a - nn * hw):
				picked = a
				used = off
				break
		if picked == Vector2.INF:
			print("[cross] SKIP %-14s 沿路 ±100 m 找不到兩側都空的端點" % c[0])
			continue
		for side in [1.0, -1.0]:
			var r: Dictionary = await _walk(picked + nn * hw * side, picked - nn * hw * side)
			n_pass += 1
			if not r["stable"]:
				bad += 1
			print("[cross] " + _line("橫越 %s %s @(%.1f,%.1f) 沿路移 %+.0f m" % [c[0], "→" if side > 0 else "←", picked.x, picked.y, used], r))
	for j in JUNC:
		var m: Vector2 = j[1]
		var t: Vector2 = (j[2] - m).normalized()
		for ang in [0.0, 45.0, 90.0]:
			var dv := t.rotated(deg_to_rad(ang))
			var s0 := m - dv * 7.0
			var s1 := m + dv * 7.0
			if not _clear(s0, s1):
				print("[cross] SKIP %-28s %3d° 路徑上有建築等碰撞" % [j[0], int(ang)])
				continue
			var r: Dictionary = await _walk(s0, s1)
			n_pass += 1
			if not r["stable"]:
				bad += 1
			print("[cross] " + _line("交叉 %s %d°" % [j[0], int(ang)], r))
	print("[cross] 結果：%d 段、不穩定或未達 %d" % [n_pass, bad])
	quit(bad)
