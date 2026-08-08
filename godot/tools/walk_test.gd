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
# ⚠ 這個值以前是 6.0，註解還寫著「跟 main.gd 同一條規則」—— main.gd 是
# 15.0。對 own_colliders 的圖看不出差別（名字過濾先生效），非 own 的圖
# 會讓 6~15m 的 mesh 在測試裡是實心、在遊戲裡卻穿得過 —— 測試比現實嚴，
# 「不通」可能是假的。對齊成 15.0，跟 main.gd 的 TRIMESH_MIN_SPAN 同值。
const TRIMESH_MIN_SPAN := 15.0

## 每張圖要驗的路線。座標是世界 XZ。
const ROUTES := {
	# ⚠ 整合 Stage 2 起 village **就是**街區重設計版的佈局，所以路線表
	# 直接沿用原本為它寫的那份（舊格線的路線已經對不上任何東西）。
	"village": [
		# 幹道連通（南北向縱貫 + 兩座門）
		{ "name": "北門 → 南口", "a": Vector2(0, -190), "b": Vector2(0, 245) },
		{ "name": "北門 → 西南門", "a": Vector2(0, -174), "b": Vector2(-172, 92) },
		# 三座橋 —— 河東岸的連通**只靠它們**
		{ "name": "廣場 → 東岸（過 12m 主橋）", "a": Vector2(0, 30), "b": Vector2(110, 30) },
		{ "name": "小橋北（z=-80）", "a": Vector2(40, -80), "b": Vector2(100, -80) },
		{ "name": "小橋南（z=140）", "a": Vector2(30, 140), "b": Vector2(90, 140) },
		# 西岸河畔道（x=52 街被河截斷後，南段通行靠它）
		{ "name": "河畔道 北 → 南", "a": Vector2(52, -40), "b": Vector2(54, 110) },
		# ⚠ 稗田邸換成完整獨立版之後，舊的三條終點（−52,−164）／（−72,−150）
		# 全部落在新院子**裡面**（保留區 x −129..−32、z −255..−136），名字跟
		# 實際位置對不上，測了也讀不出意義。改成三段真正要驗的動線：
		#   1. 主入口走得到門前（門前 = z=−135 那條橫街的北緣，庭院自己的
		#      外參道就接在街上，沒有另拉引道）
		#   2. 穿過棟門、沿 6m 切石參道走到唐破風玄関腳下（＝室內 portal 的位置）
		#   3. 繞過主屋進得了後院（枯山水／水池那一區）—— blockout 是一份
		#      trimesh，走不進去的話玩家只能隔著牆看
		{ "name": "北門 → 稗田邸門前", "a": Vector2(0, -174), "b": Vector2(-78, -140) },
		{ "name": "廣場 → 稗田邸門前", "a": Vector2(0, 30), "b": Vector2(-78, -140) },
		{ "name": "門前 → 唐破風玄関", "a": Vector2(-78, -140), "b": Vector2(-78, -164.6) },
		{ "name": "玄関 → 後院（枯山水側）", "a": Vector2(-78, -164.6), "b": Vector2(-62, -215) },
	],
	"trail": [
		{ "name": "南口 → 北口", "a": Vector2(0, 150), "b": Vector2(0, -150) },
	],
	"kourindou": [
		{ "name": "店前 → 南方林道", "a": Vector2(0, 16), "b": Vector2(0, -58) },
		{ "name": "店前 → 東側林緣", "a": Vector2(0, 16), "b": Vector2(58, 0) },
	],
	# 稗田邸一樓（傳送場景）：土間 → 客間各角落。式台 0.15+0.15 的落差
	# 要走得上去；家具（矮桌／屏風／箱階段）不能把哪個角落堵死。
	"hieda1f": [
		{ "name": "玄関 → 床の間前", "a": Vector2(0, 5.2), "b": Vector2(-4.3, -5.0) },
		# ⚠ 終點不能塞在屏風跟西襖牆之間那條 1.9m 的縫 —— 膠囊擠得過去，
		# 但 CELL=2 的格點兩側各壓在牆與屏風的碰撞箱上，BFS 根本沒有格點
		# 可走（格點解析度的假陰性，不是真的堵死）。驗「西區沒被家具封死」
		# 用屏風北緣外側的格點就夠了。
		{ "name": "玄関 → 屏風北側（西區）", "a": Vector2(0, 5.2), "b": Vector2(-8.5, 2.0) },
		{ "name": "玄関 → 東の間", "a": Vector2(0, 5.2), "b": Vector2(7.0, -5.0) },
	],
	# 稗田邸二樓（傳送場景）：階段口 → 書房各區。家具（文机/火鉢/書塔/
	# 行灯）不能把哪一區堵死；卷軸牆的碰撞不能吃進走道。
	"hieda2f": [
		# ⚠ 起點在圍欄旁 1m 內的話，那一格被欄杆碰撞箱壓住，
		# _nearest_walkable 會吸附到隔壁格 —— 挑一格保證乾淨的
		# 文机放大 2 倍後碰撞箱到 x −2.0 —— 終點擺桌東北側的乾淨格
		{ "name": "階段口 → 文机", "a": Vector2(-6.4, -2.0), "b": Vector2(0.3, -0.6) },
		{ "name": "階段口 → 東端衣桁", "a": Vector2(-6.4, -2.0), "b": Vector2(7.6, -2.2) },
		{ "name": "階段口 → 押入前", "a": Vector2(-6.4, -2.0), "b": Vector2(-9.6, 2.2) },
	],
	# 稗田邸三樓（傳送場景）：中軸廊是唯一的通道 —— 兩排 3.55m 高的中央
	# 書架不能把哪一段夾死；腰側走道（書架與腰壁之間）也要通。
	"hieda3f": [
		{ "name": "階段口 → 核心典籍", "a": Vector2(-6.5, 0.0), "b": Vector2(6.6, 0.0) },
		{ "name": "階段口 → 南腰側走道", "a": Vector2(-6.5, 0.0), "b": Vector2(5.0, -2.4) },
		{ "name": "階段口 → 北腰側走道", "a": Vector2(-6.5, 0.0), "b": Vector2(5.0, 2.4) },
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
		maps = ["village", "trail", "kourindou", "hieda1f", "hieda2f", "hieda3f"]
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
	var n_col := _build_trimesh_collision(root, root.get_meta("own_colliders", false))
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

## 規則必須跟 main.gd 一模一樣，否則測到的不是玩家實際會撞到的東西：
## own_colliders 的原生圖只有地形做 trimesh，建物靠場景自帶的碰撞箱。
func _build_trimesh_collision(root: Node, own_colliders: bool) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.push_back(c)
		if node is MeshInstance3D:
			if own_colliders and not (String(node.name) == "Terrain" or node.has_meta("needs_trimesh")):
				continue
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
	# ⚠ 地面不是「由上而下第一個命中」。室內圖有天花碰撞之後，第一個
	# 命中永遠是**天花的頂面** —— 二樓那輪的「69/77 可站」其實整片站在
	# 天花板上（平面上路線全通 = 假綠燈），三樓的斜屋面連膠囊都放不下
	# 才把這件事逼出來。正解：往下行進收集命中，只取「地形高度帶內
	# （terrain max + 2.5）」最高的那個 —— 天花/牆頂/架頂全部被帶外
	# 排除，橋面（在帶內）仍然是第一候選，村圖行為不變。
	var ymax := span.position.y + span.size.y + 2.5
	for i in range(x0, x1 + 1):
		for j in range(z0, z1 + 1):
			var x := float(i) * CELL
			var z := float(j) * CELL
			var from_y := span.position.y + span.size.y + 60.0
			var cands: Array[float] = []
			while cands.size() < 8:
				ray.from = Vector3(x, from_y, z)
				ray.to = Vector3(x, span.position.y - 30.0, z)
				var hit := _sps.intersect_ray(ray)
				if hit.is_empty():
					break
				cands.append(hit.position.y)
				from_y = hit.position.y - 0.05
				if from_y < span.position.y - 29.0:
					break
			var c := Vector2i(i, j)
			for gy in cands:
				if gy > ymax:
					continue
				if not _hf.has(c):
					_hf[c] = gy
				# 膠囊底端離地 5cm（站著的姿勢），撞到東西就是站不下
				q.transform = Transform3D(Basis(), Vector3(x, gy + HEIGHT * 0.5 + 0.05, z))
				if _sps.intersect_shape(q, 1).is_empty():
					_hf[c] = gy
					_walk[c] = true
					break

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
