extends SceneTree
## 博麗神社 v2 候選 × 導航網格（NPC／AI 路徑能力）驗收：
##   godot --headless --path godot --script res://tools/verify_shrine_v2_nav.gd
## 載入候選圖（含 NavigationRegion3D「導航」），用 NavigationServer3D.map_get_path 查關鍵路線，並用物理實測：
##   N0 導航地圖載入後可查詢（大網格要等非同步同步完成，等待毫秒數一併回報）
##   N1 每條路線都找得到路，終點離目標 ≤ 1.0 m
##   N2 路徑長 ≤ 直線距離 × 1.5（無不合理繞路）
##   N3 沿路徑每 0.25 m 取樣：不在建築內核、不在池水內
##   N4 石階段：路徑總升高貼近實際（±0.5 m）
##   N5 路徑淨空：沿路徑每 0.25 m 放一個玩家同尺寸膠囊（r0.3 h1.7），不得與任何障礙（樹幹、岩石、燈籠、建築、
##      邊界牆…）重疊——地形與石階當作地板排除
##   N6 走路代理：與玩家同尺寸的 CharacterBody3D 真的沿路徑走到終點（無階梯的路線；石階由真玩家控制器的
##      verify_shrine_v2_walk／stairs 測試負責，因為玩家有 step_height 0.35 的上階邏輯，單純膠囊跨不過 0.16 m 立面）
##   N7 全網格站立性：每個導航多邊形頂點與重心都能站一個膠囊而不與障礙重疊
##   反向案例：目標在拜殿內／池中央／界外 → 路徑終點必須離目標 ≥ 2.0 m（走不進去）
## 樹幹是否擋路由 N5／N6／N7 的實體碰撞判定（veg_kit 的幼樹幹碰撞只有 3 cm 半徑且偏離樹根原點，用原點距離判斷會誤報）。

const S2 := preload("res://tools/shrine_v2/s2lib.gd")

## [標籤, 起點, 終點, 是否無階梯（可用單純膠囊代理走）]
const ROUTES := [
	["入口→石階腳", Vector2(-4.0, 76.0), Vector2(0.0, 35.5), true],
	["石階腳→石階頂", Vector2(0.0, 35.5), Vector2(0.0, 5.5), false],
	["鳥居前→拜訪區", Vector2(0.0, 2.5), Vector2(0.0, -21.0), true],
	["拜訪區→倉庫前", Vector2(0.0, -21.0), Vector2(14.5, -19.0), true],
	["倉庫前→池畔西岸", Vector2(14.5, -19.0), Vector2(6.5, -34.0), true],
	["池畔→手水舍前", Vector2(6.5, -34.0), Vector2(-8.6, -3.0), true],
	["手水舍前→林徑入口", Vector2(-8.6, -3.0), Vector2(-22.8, -11.2), true],
	["林徑入口→林徑北東端", Vector2(-22.8, -11.2), Vector2(5.5, -52.0), true],
	["入口→林徑北東端（全程）", Vector2(-4.0, 76.0), Vector2(5.5, -52.0), false],
]
const NEGATIVE := [
	["拜殿正中央", Vector2(0.0, -28.0)],
	["池塘中心", Vector2(12.5, -39.5)],
	["界外", Vector2(95.0, 0.0)],
]
## 建築腳印（layout.py FOOTPRINT；鳥居是要穿過的門，不列入）。腳印含屋簷，這裡用縮小 0.8 m 的內核判斷是否走進建築內部。
const FOOT := {"拜殿": [0.0, -28.0, 5.0, 4.4], "倉庫": [16.0, -21.4, 2.5, 2.7], "手水舍": [-11.5, -3.0, 1.9, 1.9]}
const AGENT_SPEED := 2.2
const AGENT_R := 0.3
const AGENT_H := 1.7

var fails := 0
var L: Dictionary
var map: RID
var world: Node3D
var floor_rids: Array[RID] = []
var cap_shape: CapsuleShape3D


func _init() -> void:
	# 保險絲：腳本若中途出錯（協程中止），行程不會永遠卡住
	create_timer(280.0).timeout.connect(func():
		print("[NAV2] FAIL watchdog 逾時（腳本中止或卡住）")
		quit(9))
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[NAV2] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _y(p: Vector2) -> float:
	return S2.height_at(p.x, p.y)


func _path(a: Vector2, b: Vector2) -> PackedVector3Array:
	var pa := NavigationServer3D.map_get_closest_point(map, Vector3(a.x, _y(a), a.y))
	var pb := NavigationServer3D.map_get_closest_point(map, Vector3(b.x, _y(b), b.y))
	return NavigationServer3D.map_get_path(map, pa, pb, true)


func _len(path: PackedVector3Array) -> float:
	var s := 0.0
	for i in range(path.size() - 1):
		s += path[i].distance_to(path[i + 1])
	return s


func _in_fp(x: float, z: float) -> String:
	for k in FOOT.keys():
		var fp: Array = FOOT[k]
		if absf(x - float(fp[0])) < float(fp[2]) - 0.8 and absf(z - float(fp[1])) < float(fp[3]) - 0.8:
			return String(k)
	return ""


## 站在導航點上的膠囊是否與「非地板」障礙重疊；回傳第一個碰到的碰撞體名稱（無則空字串）
func _blocked_at(p: Vector3) -> String:
	var space := root.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.5, 0), p - Vector3(0, 2.5, 0))
	var hit := space.intersect_ray(rq)
	var gy := p.y if hit.is_empty() else float((hit["position"] as Vector3).y)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap_shape
	q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, gy + 0.12 + AGENT_H * 0.5, p.z))
	q.collision_mask = 1
	q.exclude = floor_rids
	q.margin = 0.0
	var res := space.intersect_shape(q, 4)
	if res.is_empty():
		return ""
	var col := res[0]["collider"] as Node
	return "%s/%s" % [col.get_parent().name if col.get_parent() else "?", col.name]


## 走路代理：沿路徑一個個航點走。回傳 {ok, reason, end, t}
func _walk_agent(path: PackedVector3Array) -> Dictionary:
	var body := CharacterBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.floor_max_angle = 0.907571
	body.floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = AGENT_R
	cap.height = AGENT_H
	cs.shape = cap
	cs.position = Vector3(0.0, AGENT_H * 0.5, 0.0)
	body.add_child(cs)
	world.add_child(body)
	body.global_position = path[0] + Vector3(0.0, 0.3, 0.0)
	var idx := 1
	var t := 0.0
	var plen := _len(path)
	var t_max := plen / (AGENT_SPEED * 0.6) + 10.0
	var last_prog_t := 0.0
	var best_remain := 1.0e9
	var res := {"ok": false, "reason": "", "end": Vector3.ZERO, "t": 0.0}
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	while t < t_max:
		await physics_frame
		t += dt
		while idx < path.size():
			var wp := path[idx]
			var d2 := Vector2(wp.x - body.global_position.x, wp.z - body.global_position.z).length()
			if d2 < 0.45:
				idx += 1
			else:
				break
		if idx >= path.size():
			res["ok"] = true
			break
		var tgt := path[idx]
		var dir := Vector3(tgt.x - body.global_position.x, 0.0, tgt.z - body.global_position.z).normalized()
		body.velocity.x = dir.x * AGENT_SPEED
		body.velocity.z = dir.z * AGENT_SPEED
		body.velocity.y = body.velocity.y - 9.8 * dt if not body.is_on_floor() else -0.5
		body.move_and_slide()
		if body.global_position.y < -20.0:
			res["reason"] = "掉出地圖"
			break
		var remain := Vector2(path[idx].x - body.global_position.x, path[idx].z - body.global_position.z).length()
		for j in range(idx, path.size() - 1):
			remain += Vector2(path[j + 1].x - path[j].x, path[j + 1].z - path[j].z).length()
		if remain < best_remain - 0.3:
			best_remain = remain
			last_prog_t = t
		elif t - last_prog_t > 5.0:
			var cols := []
			for i in body.get_slide_collision_count():
				var col := body.get_slide_collision(i).get_collider() as Node
				cols.append("%s/%s" % [col.get_parent().name if col.get_parent() else "?", col.name])
			res["reason"] = "卡住（在航點 %d/%d，剩 %.1f m，接觸 %s）" % [idx, path.size(), remain, str(cols)]
			break
	if res["reason"] == "" and not res["ok"]:
		res["reason"] = "逾時 %.0f s" % t_max
	res["end"] = body.global_position
	res["t"] = t
	body.queue_free()
	return res


func _run() -> void:
	L = S2.load_layout()
	S2.load_height()
	world = Node3D.new()
	root.add_child(world)
	var scene := (load("res://maps/shrine_v2/shrine_v2.tscn") as PackedScene).instantiate()
	world.add_child(scene)
	# 與 main.gd 一致：地形網格在載入時才生成 trimesh 碰撞（_build_trimesh_collision 只處理名為 Terrain 的節點）
	var terr := scene.get_node("Terrain") as MeshInstance3D
	terr.create_trimesh_collision()
	cap_shape = CapsuleShape3D.new()
	cap_shape.radius = AGENT_R
	cap_shape.height = AGENT_H
	var reg := scene.get_node_or_null("導航") as NavigationRegion3D
	check("場景含 NavigationRegion3D「導航」且有網格", reg != null and reg.navigation_mesh != null and reg.navigation_mesh.get_polygon_count() > 1000)
	map = root.get_world_3d().navigation_map
	# 導航地圖預設是非同步同步（navigation/world/map_use_async_iterations）：大網格要等背景執行緒建好才查得到。
	var t0 := Time.get_ticks_msec()
	var ready_ms := -1
	while Time.get_ticks_msec() - t0 < 60000:
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point(map, Vector3(0, 3.5, 20)) != Vector3.ZERO:
			ready_ms = Time.get_ticks_msec() - t0
			break
	check("N0 導航地圖在載入後可查詢（等待 %d ms）" % ready_ms, ready_ms >= 0)
	for i in 10:
		await physics_frame
	# 地板碰撞體：地形、石階
	for c in terr.get_children():
		if c is StaticBody3D:
			floor_rids.append((c as StaticBody3D).get_rid())
	var stair_body := scene.get_node_or_null("參道石階/石階碰撞") as StaticBody3D
	if stair_body != null:
		floor_rids.append(stair_body.get_rid())
	check("地板碰撞體齊全（地形 trimesh ＋ 石階，共 %d 個）" % floor_rids.size(), floor_rids.size() >= 2)
	var nm := reg.navigation_mesh
	print("[NAV2]   導航網格：%d 多邊形、%d 頂點" % [nm.get_polygon_count(), nm.get_vertices().size()])
	var ponds: Dictionary = L["pond"]
	var th := deg_to_rad(float(ponds["rot_deg"]))
	var total_len := 0.0
	for r in ROUTES:
		var a: Vector2 = r[1]
		var b: Vector2 = r[2]
		var path := _path(a, b)
		var ok_path := path.size() >= 2
		var end_d := 999.0
		if ok_path:
			end_d = Vector2(path[path.size() - 1].x, path[path.size() - 1].z).distance_to(b)
		var plen := _len(path)
		var straight := a.distance_to(b)
		check("N1 %s：有路、終點離目標 %.2f m" % [r[0], end_d], ok_path and end_d <= 1.0)
		check("N2 %s：路徑長 %.1f m ≤ 直線 %.1f m × 1.5" % [r[0], plen, straight], ok_path and plen <= straight * 1.5 + 1.0)
		if not ok_path:
			continue
		var bad_bld := 0
		var bad_pond := 0
		var bad_clear := 0
		var samples := 0
		var first_block := ""
		for i in range(path.size() - 1):
			var seg := path[i].distance_to(path[i + 1])
			var steps := maxi(int(seg / 0.25), 1)
			for k in steps:
				var q := path[i].lerp(path[i + 1], float(k) / float(steps))
				samples += 1
				if _in_fp(q.x, q.z) != "":
					bad_bld += 1
				var dx := q.x - float(ponds["cx"])
				var dz := q.z - float(ponds["cz"])
				var u := (dx * cos(th) + dz * sin(th)) / float(ponds["rx"])
				var v := (-dx * sin(th) + dz * cos(th)) / float(ponds["rz"])
				if sqrt(u * u + v * v) < 0.9:
					bad_pond += 1
				var blk := _blocked_at(q)
				if blk != "":
					bad_clear += 1
					if first_block == "":
						first_block = "%s @(%.2f,%.2f)" % [blk, q.x, q.z]
		check("N3 %s：%d 取樣點，進建築 %d／入池 %d" % [r[0], samples, bad_bld, bad_pond], bad_bld == 0 and bad_pond == 0)
		check("N5 %s：膠囊淨空，重疊障礙 %d/%d %s" % [r[0], bad_clear, samples, first_block], bad_clear == 0)
		if r[0] == "石階腳→石階頂":
			var gain := path[path.size() - 1].y - path[0].y
			var y_c := float(L["y_c"])
			check("N4 石階：路徑總升高 %.2f m（期望約 %.2f，容許 ±0.5）" % [gain, y_c - _y(a)], absf(gain - (y_c - _y(a))) <= 0.5)
		if bool(r[3]):
			var wr: Dictionary = await _walk_agent(path)
			var endp: Vector3 = wr["end"]
			var d_end := Vector2(endp.x - b.x, endp.z - b.y).length()
			check("N6 %s：代理走到終點（離 %.2f m、耗時 %.1f s）%s" % [r[0], d_end, float(wr["t"]), str(wr["reason"])], bool(wr["ok"]) and d_end <= 1.2)
		if r[0].begins_with("入口→林徑北東端"):
			total_len = plen
	print("[NAV2]   全程（入口→林徑北東端）路徑長 %.1f m" % total_len)
	# N7：全網格站立性
	var vs := nm.get_vertices()
	var bad_v := 0
	var bad_names := {}
	for v in vs:
		var blk := _blocked_at(v)
		if blk != "":
			bad_v += 1
			bad_names[blk] = int(bad_names.get(blk, 0)) + 1
	var bad_c := 0
	for i in nm.get_polygon_count():
		var p := nm.get_polygon(i)
		var c := Vector3.ZERO
		for idx in p:
			c += vs[idx]
		c /= float(p.size())
		if _blocked_at(c) != "":
			bad_c += 1
	check("N7 全網格站立性：頂點 %d/%d、多邊形重心 %d/%d 與障礙重疊 %s" % [bad_v, vs.size(), bad_c, nm.get_polygon_count(), str(bad_names)], bad_v == 0 and bad_c == 0)
	for ng in NEGATIVE:
		var tgt: Vector2 = ng[1]
		var path := _path(Vector2(0.0, 5.5), tgt)
		var end_d := 999.0
		if path.size() >= 1:
			end_d = Vector2(path[path.size() - 1].x, path[path.size() - 1].z).distance_to(tgt)
		check("反向 %s：走不進去（終點離目標 %.1f m ≥ 2）" % [ng[0], end_d], end_d >= 2.0)
	print("[NAV2] failures=%d" % fails)
	quit(fails)
