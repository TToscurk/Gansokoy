# Portal 串接測試 —— 傳送點真的接起來了嗎
#
#   godot --headless --path godot --script tools/portal_test.gd
#
# 「target 欄位填了」不等於「串接完成」（使用者明令）。每一跳要驗四件事：
#   1. 雙向對接：A 有指向 B 的 portal，B 也要有指回 A 的 portal ——
#      main.gd::_place_player 是拿「目的圖裡 target == from_id 的 portal」
#      當落點，缺一半就會摔在 (0,40,0)。
#   2. 落點物理：照 main.gd 的落點公式（portal + 2m 高 + 朝原點推 4m）算出
#      實際落點，在目的場景裡射線找地面、放膠囊 —— 要站得下，而且地面高
#      不能離 portal.y 太遠（差太多代表 meta 的 y 是抄錯的）。
#   3. 落點連通：從落點 BFS 走到目的圖裡「附近的每一個 portal」——
#      落地之後要走得回去（往返），也要走得到下一跳（鏈）。
#   4. 地面判定用 walk_test 同款的「高度帶內取最高候選」——
#      室內圖有天花碰撞，「第一個命中」永遠是天花頂（walk_test 抓過的坑）。
extends SceneTree

const CELL := 1.0              # 室內走道窄，格點比 walk_test 密一倍
const RADIUS := 0.45
const HEIGHT := 1.7
const STEP_UP := 0.7
const TRIMESH_MIN_SPAN := 15.0
const GOAL_NEAR := 30.0        # 只 BFS 到落點 30m 內的 portal（村圖的遠門不掃）

## 要驗的跳（雙向都列 —— 每一跳獨立驗）
const HOPS := [
	["village", "hieda1f"], ["hieda1f", "village"],
	["hieda1f", "hieda2f"], ["hieda2f", "hieda1f"],
	["hieda2f", "hieda3f"], ["hieda3f", "hieda2f"],
]

var _sps: PhysicsDirectSpaceState3D
var _cap := CapsuleShape3D.new()
var _fail := 0
var _terr_ymax := 0.0


func _init() -> void:
	_cap.radius = RADIUS
	_cap.height = HEIGHT
	for hop in HOPS:
		await _check_hop(String(hop[0]), String(hop[1]))
	print("\n══ Portal 串接測試：%d 跳失敗 ══" % _fail)
	quit(1 if _fail > 0 else 0)


func _meta(id: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string("res://data/%s.meta.json" % id)
	if txt.is_empty():
		return {}
	return JSON.parse_string(txt)


func _portal_to(meta: Dictionary, target: String) -> Variant:
	for p in meta.get("portals", []):
		if p.get("target") == target:
			return p
	return null


func _check_hop(a: String, b: String) -> void:
	print("\n──── %s → %s ────" % [a, b])
	var ma := _meta(a)
	var mb := _meta(b)
	var pa: Variant = _portal_to(ma, b)
	var pb: Variant = _portal_to(mb, a)
	# 1. 雙向對接
	if pa == null:
		print("  ✗ %s 沒有指向 %s 的 portal" % [a, b])
		_fail += 1
		return
	if pb == null:
		print("  ✗ %s 沒有指回 %s 的 portal —— 玩家會摔在 (0,40,0)" % [b, a])
		_fail += 1
		return
	# 2. 落點（照 main.gd::_place_player 的公式算）
	var spawn := Vector3(pb.x, pb.y + 2.0, pb.z)
	var inward := Vector3(0.0, spawn.y, 0.0) - spawn
	inward.y = 0.0
	if inward.length() > 0.01:
		spawn += inward.normalized() * 4.0
	# 載入目的場景 + 物理
	var root: Node3D = (load("res://maps/%s/%s.tscn" % [b, b]) as PackedScene).instantiate()
	get_root().add_child(root)
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			if not (String(n.name) == "Terrain" or n.has_meta("needs_trimesh")):
				continue
			var ab: AABB = (n as MeshInstance3D).get_aabb()
			if maxf(ab.size.x, ab.size.z) >= TRIMESH_MIN_SPAN:
				(n as MeshInstance3D).create_trimesh_collision()
	await physics_frame
	await physics_frame
	_sps = root.get_world_3d().direct_space_state
	var terr := root.find_child("Terrain", true, false) as MeshInstance3D
	var tspan: AABB = terr.global_transform * terr.get_aabb()
	_terr_ymax = tspan.position.y + tspan.size.y

	var gy: Variant = _ground_at(spawn.x, spawn.z)
	if gy == null:
		print("  ✗ 落點 (%.1f, %.1f) 底下沒有地面" % [spawn.x, spawn.z])
		_fail += 1
		_teardown(root)
		return
	if absf(float(gy) - float(pb.y)) > 2.5:
		print("  ✗ 落點地面 y=%.2f 離 portal y=%.2f 太遠（meta 的 y 抄錯？）"
			% [float(gy), float(pb.y)])
		_fail += 1
		_teardown(root)
		return
	if not _capsule_fits(spawn.x, float(gy), spawn.z):
		print("  ✗ 落點 (%.1f, %.1f) 膠囊站不下" % [spawn.x, spawn.z])
		_fail += 1
		_teardown(root)
		return
	print("  ✓ 落點 (%.1f, %.2f, %.1f) 地面 y=%.2f、站得下" % [spawn.x, spawn.y, spawn.z, float(gy)])

	# 3. 落點連通：BFS 到目的圖裡落點 30m 內的每一個 portal
	var goals: Array = []
	for p in mb.get("portals", []):
		var d := Vector2(spawn.x - float(p.x), spawn.z - float(p.z)).length()
		if d <= GOAL_NEAR:
			goals.append(p)
	for gp in goals:
		var label: String = String(gp.get("target")) if gp.get("target") != null else "保留"
		if _bfs(Vector2(spawn.x, spawn.z), Vector2(float(gp.x), float(gp.z))):
			print("  ✓ 落點 → portal[%s]：走得到" % label)
		else:
			print("  ✗ 落點 → portal[%s]：走不到" % label)
			_fail += 1
	_teardown(root)


func _teardown(root: Node) -> void:
	get_root().remove_child(root)
	root.queue_free()


## 地面：往下行進收集命中，取「地形高度帶（terrain max + 2.5）內」最高的
## —— 天花/牆頂被排除（walk_test 同款；室內圖第一個命中永遠是天花頂）。
func _ground_at(x: float, z: float) -> Variant:
	var ray := PhysicsRayQueryParameters3D.new()
	var from_y := _terr_ymax + 60.0
	var tries := 0
	while tries < 8:
		tries += 1
		ray.from = Vector3(x, from_y, z)
		ray.to = Vector3(x, _terr_ymax - 40.0, z)
		var hit := _sps.intersect_ray(ray)
		if hit.is_empty():
			return null
		var gy: float = hit.position.y
		if gy <= _terr_ymax + 2.5:
			return gy
		from_y = gy - 0.05
	return null


func _capsule_fits(x: float, gy: float, z: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape_rid = _cap.get_rid()
	q.collide_with_areas = false
	q.transform = Transform3D(Basis(), Vector3(x, gy + HEIGHT * 0.5 + 0.05, z))
	return _sps.intersect_shape(q, 1).is_empty()


## 迷你 BFS：範圍只框「起點與終點的包絡 + 8m」——村圖不用掃 600×600
func _bfs(a: Vector2, b: Vector2) -> bool:
	var lo := Vector2(minf(a.x, b.x) - 8.0, minf(a.y, b.y) - 8.0)
	var hi := Vector2(maxf(a.x, b.x) + 8.0, maxf(a.y, b.y) + 8.0)
	var walk := {}
	var hf := {}
	for i in range(int(floor(lo.x / CELL)), int(ceil(hi.x / CELL)) + 1):
		for j in range(int(floor(lo.y / CELL)), int(ceil(hi.y / CELL)) + 1):
			var gy: Variant = _ground_at(float(i) * CELL, float(j) * CELL)
			if gy == null:
				continue
			var c := Vector2i(i, j)
			hf[c] = float(gy)
			if _capsule_fits(float(i) * CELL, float(gy), float(j) * CELL):
				walk[c] = true
	var start: Variant = _nearest(walk, Vector2i(int(round(a.x / CELL)), int(round(a.y / CELL))))
	if start == null:
		return false
	var seen := { start: true }
	var queue: Array[Vector2i] = [start]
	var head := 0
	const NB := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		# 終點 = 走進 portal 的觸發圓柱（main.gd 的 Area3D 半徑 1.6）——
		# 不是「站上 portal 中心那一格」。中心格常壓在欄杆/樓梯邊上，
		# 用格點吸附會把真的可觸發判成走不到（或反過來）。
		if Vector2(float(c.x) * CELL, float(c.y) * CELL).distance_to(b) <= 1.55:
			return true
		for n in NB:
			var nc: Vector2i = c + n
			if seen.has(nc) or not walk.has(nc):
				continue
			if absf(hf[nc] - hf[c]) > STEP_UP:
				continue
			seen[nc] = true
			queue.append(nc)
	return false


func _nearest(walk: Dictionary, c: Vector2i) -> Variant:
	if walk.has(c):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var nc := Vector2i(c.x + dx, c.y + dz)
				if walk.has(nc):
					return nc
	return null
