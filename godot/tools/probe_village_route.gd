extends SceneTree
## 人間之里（slice）局部可走性探針 —— 回答「村門走不走得到寺子屋」。
##   Godot --headless --path godot --script tools/probe_village_route.gd
##
## 為什麼不直接跑 walk_test.gd：那支會把整張 slice（1800 萬面）鋪成 2m 全圖格點，
##   光是 trimesh 碰撞就吃掉數十分鐘。這裡只做**局部**：
##   - 碰撞規則與 walk_test.gd / main.gd 完全相同（同一條 TRIMESH_MIN_SPAN），
##     但只對「世界外框與關注區域重疊」的 mesh 建 trimesh；
##   - 格點只鋪在關注區域內。
##   驗的是真的碰撞體，不是產生器的 _rects。
##
## ⚠ 這支只用來判「互動區放哪裡走得到」，不是全圖體檢。全圖體檢仍走 walk_test.gd。

const CELL := 2.0
const RADIUS := 0.45
const HEIGHT := 1.7
const TRIMESH_MIN_SPAN := 15.0
const SCENE := "res://maps/slice/slice.tscn"

## 關注區域（世界 XZ）—— B 批擴大到整條村軸（稗田邸在最北 z≈-150）
const REGION := Rect2(190.0, -170.0, 160.0, 285.0)   # x 190..350、z -170..115

## 起點：村門（MQ07 終點、MQ08 開場）
const START := Vector2(234.0, 96.0)

## 終點候選
const GOALS := {
	"寺子屋_南側": Vector2(315.0, 46.0),
	"鈴奈庵_南":   Vector2(227.0, -58.0),
	"鈴奈庵_北":   Vector2(227.0, -78.0),
	"鈴奈庵_東":   Vector2(236.0, -68.0),
	"稗田邸_門前": Vector2(233.0, -133.0),
	"稗田邸_南":   Vector2(233.0, -122.0),
	"稗田邸_東":   Vector2(252.0, -139.0),
	"火見櫓_南":   Vector2(243.0, -62.0),
	"火見櫓_東":   Vector2(251.0, -69.0),
	"鯢吞亭_南":   Vector2(213.0, -82.0),
	"鯢吞亭_東":   Vector2(226.0, -94.0),
	"霧雨店_南":   Vector2(244.0, -18.0),
}

var _sps: PhysicsDirectSpaceState3D
var _shape_rid: RID
var _walk := {}          # Vector2i -> 地面 y
var _root: Node3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_root = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_root)
	var n_col := _build_collision(_root)
	await physics_frame
	await physics_frame
	_sps = _root.get_world_3d().direct_space_state
	print("[ROUTE] 區域 %s，建了 %d 個 trimesh 碰撞" % [REGION, n_col])

	_scan()
	print("[ROUTE] 可站立格點：%d" % _walk.size())

	var start: Variant = _nearest_walkable(_cell(START))
	if start == null:
		print("[ROUTE]  起點 %s 附近站不下人" % START)
		quit(1)
		return
	print("[ROUTE] 起點 %s 可站（地面 y=%.3f）" % [START, float(_walk[start])])

	var dist := _bfs(start)
	for k in GOALS:
		var g: Vector2 = GOALS[k]
		var c: Variant = _nearest_walkable(_cell(g))
		if c == null:
			print("[ROUTE] %-12s ✗ 該點附近 3 格內站不下人" % k)
			continue
		var d: float = dist.get(c, INF)
		var dy := float(_walk[c])
		if d == INF:
			print("[ROUTE] %-12s  走不到（站得住但與村門不連通） 地面 y=%.3f" % [k, dy])
		else:
			print("[ROUTE] %-12s ✓ 走得到，路徑 %.0f m，地面 y=%.3f" % [k, d, dy])
	quit(0)


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(int(round(p.x / CELL)), int(round(p.y / CELL)))


## main.gd／walk_test.gd 的同一條規則；差別只在「世界外框要碰到關注區域」才建。
func _build_collision(root: Node) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.push_back(c)
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if String(mi.name) != "Terrain":
			var w: AABB = _world_aabb(mi)
			if not REGION.intersects(Rect2(w.position.x, w.position.z, w.size.x, w.size.z)):
				continue
		var aabb: AABB = mi.get_aabb()
		if maxf(aabb.size.x, aabb.size.z) >= TRIMESH_MIN_SPAN:
			mi.create_trimesh_collision()
			n += 1
	return n


func _world_aabb(mi: MeshInstance3D) -> AABB:
	var local: AABB = mi.mesh.get_aabb()
	var xf: Transform3D = mi.global_transform
	var out := AABB(xf * local.get_endpoint(0), Vector3.ZERO)
	for i in range(1, 8):
		out = out.expand(xf * local.get_endpoint(i))
	return out


func _scan() -> void:
	var x0 := int(floor(REGION.position.x / CELL))
	var x1 := int(ceil((REGION.position.x + REGION.size.x) / CELL))
	var z0 := int(floor(REGION.position.y / CELL))
	var z1 := int(ceil((REGION.position.y + REGION.size.y) / CELL))
	var ray := PhysicsRayQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	_shape_rid = cap.get_rid()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape_rid = _shape_rid
	q.collide_with_areas = false
	for i in range(x0, x1 + 1):
		for j in range(z0, z1 + 1):
			var x := float(i) * CELL
			var z := float(j) * CELL
			# 地面 = 由下而上收集命中，取最高的那層（地形帶內）
			var cands: Array[float] = []
			var from_y := 120.0
			while cands.size() < 6:
				ray.from = Vector3(x, from_y, z)
				ray.to = Vector3(x, -40.0, z)
				var hit := _sps.intersect_ray(ray)
				if hit.is_empty():
					break
				cands.append(hit.position.y)
				from_y = hit.position.y - 0.05
				if from_y < -39.0:
					break
			for gy in cands:
				if gy > 40.0:
					continue
				q.transform = Transform3D(Basis(), Vector3(x, gy + HEIGHT * 0.5 + 0.05, z))
				if _sps.intersect_shape(q, 1).is_empty():
					_walk[Vector2i(i, j)] = gy
					break


## 起點附近找最近的可站格（3 格內）
func _nearest_walkable(c: Vector2i) -> Variant:
	for r in range(0, 4):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var k := Vector2i(c.x + dx, c.y + dz)
				if _walk.has(k):
					return k
	return null


## BFS 回傳 Vector2i -> 距起點的實際步距（公尺）
func _bfs(start: Vector2i) -> Dictionary:
	var dist := { start: 0.0 }
	var queue: Array[Vector2i] = [start]
	var head := 0
	const NB := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: float = dist[cur]
		for o in NB:
			var k: Vector2i = cur + o
			if dist.has(k) or not _walk.has(k):
				continue
			# 落差太大 = 爬不上去
			if absf(float(_walk[k]) - float(_walk[cur])) > 0.7:
				continue
			dist[k] = d + (CELL if o.x == 0 or o.y == 0 else CELL * 1.4142)
			queue.append(k)
	return dist