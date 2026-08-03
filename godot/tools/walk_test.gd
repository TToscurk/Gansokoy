# 可走性測試 —— 玩家真的走得到嗎（ADR-003）
#
#   godot --headless --path godot --script tools/walk_test.gd -- village
#   godot --headless --path godot --script tools/walk_test.gd -- all
#
# 體檢（check_map.gd）驗的是「東西擺得對不對」，這支驗的是「人過不過得去」：
#   1. 出入口之間走不走得到（村南門 → 村北門、廣場 → 對岸…）
#   2. 街上有沒有被擋死的地方（房子蓋到路中間、橋頭卡樽桶）
#   3. 橋是不是真的能過（水路兩岸的連通只靠橋）
#
# 做法：用**真正的碰撞體**跑，不用產生器的 _rects —— 產生器以為擋住的
# 跟玩家實際撞到的是兩回事。地面高度也用射線打，不重算 height_at。
#   地形 trimesh 碰撞的建法跟 main.gd 一致（跨度 ≥ TRIMESH_MIN_SPAN 的 mesh）。
extends SceneTree

const CELL := 2.0              # 格點間距
const RADIUS := 0.45           # 玩家半徑（對齊 player.tscn 的膠囊）
const HEIGHT := 1.7
const STEP_UP := 0.7           # 走得上去的落差（台階、緣石、橋頭）
const TRIMESH_MIN_SPAN := 6.0  # 跟 main.gd 同一條規則

## 每張圖要驗的路線。座標是世界 XZ。
const ROUTES := {
	"village": [
		{ "name": "南口 → 北口", "a": Vector2(0, 250), "b": Vector2(0, -250) },
		{ "name": "南口 → 西口", "a": Vector2(0, 250), "b": Vector2(-250, 30) },
		{ "name": "廣場 → 東口", "a": Vector2(0, 30), "b": Vector2(250, 30) },
		{ "name": "水路南岸 → 北岸（要過橋）", "a": Vector2(40, 95), "b": Vector2(40, 75) },
		{ "name": "廣場 → 稗田邸前", "a": Vector2(0, 30), "b": Vector2(-78, 20) },
	],
	"trail": [
		{ "name": "南口 → 北口", "a": Vector2(0, 150), "b": Vector2(0, -150) },
	],
	"kourindou": [
		{ "name": "店前 → 南方林道", "a": Vector2(0, 16), "b": Vector2(0, -58) },
		{ "name": "店前 → 東側林緣", "a": Vector2(0, 16), "b": Vector2(58, 0) },
	],
}

var _sps: PhysicsDirectSpaceState3D
var _shape_rid: RID
var _cap: CapsuleShape3D
var _hf := {}                  # Vector2i -> 射線打到的地面高度
var _walk := {}                # Vector2i -> true（膠囊放得下）
var _fail := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var maps: Array = []
	if args.is_empty() or args[0] == "all":
		maps = ["village", "trail", "kourindou"]
	else:
		maps = [args[0]]
	_cap = CapsuleShape3D.new()
	_cap.radius = RADIUS
	_cap.height = HEIGHT
	_shape_rid = _cap.get_rid()
	for m in maps:
		await _check(String(m))
	print("\n══ 可走性測試完成：%d 條路線不通 ══" % _fail)
	quit(1 if _fail > 0 else 0)

func _check(map_id: String) -> void:
	var path := "res://maps/%s/%s.tscn" % [map_id, map_id]
	if not ResourceLoader.exists(path):
		print("[%s] 沒有原生場景，跳過" % map_id)
		return
	print("\n──── 可走性：%s ────" % map_id)
	_hf.clear()
	_walk.clear()

	var root: Node3D = (load(path) as PackedScene).instantiate()
	get_root().add_child(root)
	var n_col := _build_trimesh_collision(root)
	# 物理要跑一拍，剛掛上去的 StaticBody 才會進 PhysicsServer
	await physics_frame
	await physics_frame

	var terr := root.find_child("Terrain", true, false) as MeshInstance3D
	if terr == null:
		print("  ✗ 沒有 Terrain，跳過")
		_teardown(root)
		_fail += 1
		return
	_sps = root.get_world_3d().direct_space_state
	var span: AABB = terr.global_transform * terr.get_aabb()
	print("  地形範圍 %.0f × %.0f，trimesh 碰撞 %d 個" % [span.size.x, span.size.z, n_col])

	_scan(span)
	print("  可站立格點：%d / %d（掃到地面的格）" % [_walk.size(), _hf.size()])

	for r in ROUTES.get(map_id, []):
		_route(String(r.name), r.a, r.b)
	_teardown(root)

func _teardown(root: Node) -> void:
	get_root().remove_child(root)
	root.queue_free()

func _build_trimesh_collision(root: Node) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.push_back(c)
		if node is MeshInstance3D:
			var aabb: AABB = (node as MeshInstance3D).get_aabb()
			if maxf(aabb.size.x, aabb.size.z) >= TRIMESH_MIN_SPAN:
				(node as MeshInstance3D).create_trimesh_collision()
				n += 1
	return n

## 鋪格點：先射線找地面，再放膠囊看站不站得下
func _scan(span: AABB) -> void:
	var x0 := int(floor(span.position.x / CELL))
	var x1 := int(ceil((span.position.x + span.size.x) / CELL))
	var z0 := int(floor(span.position.z / CELL))
	var z1 := int(ceil((span.position.z + span.size.z) / CELL))
	var ray := PhysicsRayQueryParameters3D.new()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape_rid = _shape_rid
	q.collide_with_areas = false
	for i in range(x0, x1 + 1):
		for j in range(z0, z1 + 1):
			var x := float(i) * CELL
			var z := float(j) * CELL
			ray.from = Vector3(x, span.position.y + span.size.y + 60.0, z)
			ray.to = Vector3(x, span.position.y - 30.0, z)
			var hit := _sps.intersect_ray(ray)
			if hit.is_empty():
				continue
			var c := Vector2i(i, j)
			var gy: float = hit.position.y
			_hf[c] = gy
			# 膠囊底端離地 5cm（站著的姿勢），撞到東西就是站不下
			q.transform = Transform3D(Basis(), Vector3(x, gy + HEIGHT * 0.5 + 0.05, z))
			if _sps.intersect_shape(q, 1).is_empty():
				_walk[c] = true

## BFS：a 走不走得到 b
func _route(name: String, a: Vector2, b: Vector2) -> void:
	var start = _nearest_walkable(Vector2i(int(round(a.x / CELL)), int(round(a.y / CELL))))
	var goal = _nearest_walkable(Vector2i(int(round(b.x / CELL)), int(round(b.y / CELL))))
	if start == null or goal == null:
		print("  ✗ %s：%s 附近站不下人" % [name, "起點" if start == null else "終點"])
		_fail += 1
		return
	var seen := { start: true }
	var queue: Array[Vector2i] = [start]
	var head := 0
	var best := INF
	var best_c: Vector2i = start
	const NB := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if c == goal:
			print("  ✓ %s：通（BFS 走過 %d 格）" % [name, seen.size()])
			return
		var d := Vector2(float(c.x - goal.x), float(c.y - goal.y)).length()
		if d < best:
			best = d
			best_c = c
		for n in NB:
			var nc: Vector2i = c + n
			if seen.has(nc) or not _walk.has(nc):
				continue
			# 爬不上去的落差當牆，不然 BFS 會直接「穿過」石垣護岸與河岸
			if absf(_hf[nc] - _hf[c]) > STEP_UP:
				continue
			seen[nc] = true
			queue.append(nc)
	print("  ✗ %s：不通。最遠只到 (%.0f, %.0f)，離終點還有 %.0fm"
		% [name, float(best_c.x) * CELL, float(best_c.y) * CELL, best * CELL])
	_fail += 1

## 測試點可能剛好壓在石頭上 —— 往外找最近的可站點（6 格內）
func _nearest_walkable(c: Vector2i):
	if _walk.has(c):
		return c
	for r in range(1, 7):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var n := Vector2i(c.x + dx, c.y + dz)
				if _walk.has(n):
					return n
	return null
