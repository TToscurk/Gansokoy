extends SceneTree
## 走廊圍堵體檢：用**真的物理**確認玩家出不去、傳送點進得來。
##
##   Godot --headless --path godot --script tools/audit_trail_containment.gd
##
## 為什麼要有這支：牆是一段一段的盒子，彎道外側相鄰段之間可能留縫；
## 「我算過盒子夠長」不算證據，要真的從走廊內往外推一顆膠囊看它會不會穿出去。
##
## 做法：
##  1. 載入真的 main.tscn（有物理世界、有 trail 的碰撞）。
##  2. 沿主脊每隔一段，從路心往左右各掃三個方向（垂直 ±20°，理由見 §1），
##     最短的那條要在 play_half + TOL 內被擋住、最長的那條要能走過 play_half − EAT_TOL。
##  3. 南北兩端同樣往圖外推。
##  4. 傳送點必須**在牆以內**（玩家走得到），且腳下有地。
##  5. 碰撞只剩「可動範圍框」＋木橋橋面（2026-09-16 使用者裁定）。
##
## 2026-09-16 碰撞重排（使用者：「把獸道的碰撞重新排過一次，目前太亂了，就用正方形
## 把能夠移動的範圍框起來就好」）：舊版是 608 個零散形狀（406 根樹幹圓柱 + 129 段
## 牆 + 岩石／隘口岩體／地藏／燈籠／屋台），新版是沿可動範圍邊界鋪的一圈正方形。

const TOL := 2.5           # 牆允許比 play_half 遠多少（沒有真的破洞）
const EAT_TOL := 3.0       # 允許比 play_half 內縮多少（旋轉方塊的內面是平面，
                           # 曲率半徑 18 m 處弦矢高 1.0 m，留 3 m 當門）
const SAMPLES := 60

var fails := 0
var main: Node
var space: PhysicsDirectSpaceState3D


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("[WALL] %s %s" % ["PASS" if ok else "FAIL", label])


func _settle(n: int) -> void:
	for i in n:
		await physics_frame


## 從 from 往 dir 方向掃一顆玩家大小的膠囊，回傳撞到東西的距離（沒撞到 = INF）
## exclude_rids 是「這次不算數」的碰撞體（用來分辨是不是框擋的）。
func _cast(from: Vector3, dir: Vector3, dist: float, exclude_rids: Array = []) -> float:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = dir.normalized() * dist
	q.collision_mask = 0xFFFFFFFF
	if not exclude_rids.is_empty():
		q.exclude = exclude_rids
	var r := space.cast_motion(q)
	# cast_motion 回 [safe, unsafe]，1.0 = 全程沒撞到
	return INF if r[0] >= 0.999 else r[0] * dist


## 擋住玩家的到底是不是「可動範圍框」。
##   ⚠ 不要用細射線問名字：射線會從地形上方穿過去、打到後面那塊框，把地形擋住的
##     情況全誤判成「框內縮」（實測 74 次全錯）。改成把框排除再掃一次：
##     排除後還是一樣近 → 擋人的是地形／其他；排除後變遠 → 就是框擋的。
func _classify(from: Vector3, dir: Vector3, dist: float, hit: float, frame_rids: Array) -> Array:
	var nof := _cast(from, dir, dist, frame_rids)
	if nof <= hit + 0.15:
		return ["other", nof]
	return ["frame", hit]


## 主脊在 t 處的切線方向。
## ⚠ 不能用 spine[i0] → spine[i0+1]：t=1.0 時 i0 = i1 = 最後一點，
##   相減得到零向量，normalized() 回 (0,0)，掃描方向變成零 → 永遠不會撞到東西，
##   體檢就會把「牆好好的」誤報成「漏了 40 m」。端點要取前一段。
func _dir_at(spine: PackedVector2Array, i0: int) -> Vector2:
	var a: int = mini(i0, spine.size() - 2)
	return (spine[a + 1] - spine[a]).normalized()


func _run() -> void:
	var scn := load("res://scenes/main.tscn") as PackedScene
	main = scn.instantiate()
	root.add_child(main)
	await _settle(4)
	main.load_map("trail", "")
	await _settle(90)
	space = main.get_viewport().world_3d.direct_space_state

	var map_root: Node3D = main.map_root
	var trail: Node3D = null
	for c in map_root.get_children():
		if c is Node3D and c.has_meta("spine"):
			trail = c
	if trail == null and map_root.has_meta("spine"):
		trail = map_root
	if trail == null:
		print("[WALL] 找不到帶 meta(spine) 的節點——請重跑 gen_trail_v2.gd")
		quit(1)
		return
	var spine: PackedVector2Array = trail.get_meta("spine")
	var play: PackedFloat32Array = trail.get_meta("play_half")
	print("[WALL] 主脊 %d 點" % spine.size())

	# ─ 1. 兩側圍堵（扇形量測）──
	#  單一「垂直於主脊」的射線在大空地／獵食者袋那兩段會誤判：play_half 在
	#   10 m 內從 20 鼓到 27/30，邊界在那裡是**斜的**，垂直射線會沿著邊界跑，
	#   一下量成「超出 9.8 m 的破洞」、一下量成「內縮 7.6 m 的框」。改動前的
	#   舊牆也一樣（同一支腳本在改動前就是 117/120、最糟 9.8 m @ t=0.69）。
	#   所以改成每個取樣點掃三個方向（垂直 ±20°）：
	#     最短的那條要在 play_half + TOL 之內（沒有真的破洞）
	#     最長的那條要能走到 play_half − EAT_TOL（玩家的空間沒被吃掉）
	var worst_gap := 0.0
	var worst_t := 0.0
	var leaks := 0
	var worst_eat := 0.0
	var eat_t := 0.0
	var eats := 0
	var worst_other := 0.0
	var other_t := 0.0
	var others := 0
	var frame_rids: Array = []
	var frame_node := trail.get_node_or_null("走廊碰撞牆/可動範圍框")
	if frame_node is PhysicsBody3D:
		frame_rids.append((frame_node as PhysicsBody3D).get_rid())
	for i in SAMPLES:
		var t := float(i) / float(SAMPLES - 1)
		var f: float = t * float(spine.size() - 1)
		var i0 := int(floor(f))
		var i1: int = mini(i0 + 1, spine.size() - 1)
		var c: Vector2 = spine[i0].lerp(spine[i1], f - float(i0))
		var ph: float = lerpf(play[i0], play[i1], f - float(i0))
		var d: Vector2 = _dir_at(spine, i0)
		var perp := Vector2(-d.y, d.x)
		var gy := _ground(c.x, c.y)
		for side in [-1.0, 1.0]:
			var lo := INF
			var hi := -INF
			var lo_dir: Vector2 = perp * side
			for k in 3:
				var ang := (float(k) - 1.0) * 0.35
				var dir2: Vector2 = perp.rotated(ang) * side
				var hit := _cast(Vector3(c.x, gy + 1.2, c.y), Vector3(dir2.x, 0.0, dir2.y), ph + 40.0)
				if hit < lo:
					lo = hit
					lo_dir = dir2
				hi = maxf(hi, minf(hit, ph + 40.0))
			if lo > ph + TOL:
				leaks += 1
				if lo - ph > worst_gap:
					worst_gap = lo - ph
					worst_t = t
			elif hi < ph - EAT_TOL:
				var cls := _classify(Vector3(c.x, gy + 1.2, c.y), Vector3(lo_dir.x, 0.0, lo_dir.y),
					ph + 40.0, hi, frame_rids)
				if cls[0] == "frame":
					eats += 1
					if ph - hi > worst_eat:
						worst_eat = ph - hi
						eat_t = t
				else:
					others += 1
					if ph - hi > worst_other:
						worst_other = ph - hi
						other_t = t
	check("兩側圍堵：%d/%d 次側掃在可動範圍內被擋住（最糟超出 %.1f m @ t=%.2f）"
		% [SAMPLES * 2 - leaks, SAMPLES * 2, worst_gap, worst_t], leaks == 0)
	check("玩家空間沒被吃掉：%d/%d 次側掃走不到 play_half − %.0f m（最糟 %.1f m @ t=%.2f）"
		% [SAMPLES * 2 - eats, SAMPLES * 2, EAT_TOL, worst_eat, eat_t], eats == 0)
	print("[WALL] 地形擋住（僅記錄）：%d/%d 次，最淺處離路心 %.1f m @ t=%.2f"
		% [others, SAMPLES * 2, worst_other, other_t])

	# ── 2. 南北兩端 ──
	for e in [[0.0, "南"], [1.0, "北"]]:
		var t: float = e[0]
		var f: float = t * float(spine.size() - 1)
		var i0 := int(floor(f))
		var i1: int = mini(i0 + 1, spine.size() - 1)
		var c: Vector2 = spine[i0].lerp(spine[i1], f - float(i0))
		var d: Vector2 = _dir_at(spine, i0)
		var outward := -1.0 if t < 0.5 else 1.0
		var gy := _ground(c.x, c.y)
		var from := Vector3(c.x, gy + 1.2, c.y)
		var dir := Vector3(d.x * outward, 0.0, d.y * outward)
		var hit := _cast(from, dir, 30.0)
		check("%s端封口：距路端 %.1f m 處被擋住" % [e[1], hit], hit < 12.0)

	# ─ 3. 傳送點：在牆內、腳下有地、Area 存在 ──
	var portals: Array = main.current_portals()
	check("傳送點資料 2 個（shrine / slice）", portals.size() == 2)
	for p in portals:
		var px := float(p.x)
		var pz := float(p.z)
		var tgt := String(p.get("target", ""))
		# 玩家能不能站上去：從正上方 3 m 掉下來要落在地面附近
		var gy := _ground(px, pz)
		check("傳送點 %s (%.1f, %.1f) 腳下有地面 y=%.2f（meta y=%.2f，差 %.2f m）"
			% [tgt, px, pz, gy, float(p.y), absf(gy - float(p.y))],
			gy != -INF and absf(gy - float(p.y)) < 0.6)
		# Area3D 真的生成了
		var area: Node = main.map_root.get_node_or_null("Portal_%s" % tgt)
		check("傳送點 %s 的 Area3D 已生成" % tgt, area != null)
		# 從傳送點往路心方向沒有牆擋著（玩家走得到）
		#   不要拉到 8 m。入口段路旁有界碑碰撞（規格要的景物），
		#   8 m 會掃到它然後誤報成「牆擋住傳送點」。4 m 足以確認
		#   傳送點不是被封在牆外的死角。
		if area != null:
			var to_center := Vector3(-px, 0.0, -pz).normalized()
			var hit := _cast(Vector3(px, gy + 1.2, pz), to_center, 4.0)
			check("傳送點 %s 往圖心 4 m 內無阻擋（實測 %s）"
				% [tgt, "無" if hit == INF else "%.1f m" % hit], hit == INF)

	# ─ 4. 碰撞只剩「可動範圍框」＋木橋橋面 ──
	# 2026-09-16 使用者裁定「用正方形把能夠移動的範圍框起來就好」：樹幹／岩石／
	# 隘口岩體／地藏／燈籠／屋台一律不再給碰撞。這裡量框本身。
	var frame: Node = null
	for c in trail.get_children():
		if str(c.name) == "走廊碰撞牆":
			frame = c.get_node_or_null("可動範圍框")
	check("可動範圍框節點存在（%d 塊）" % (frame.get_child_count() if frame else 0),
		frame != null and frame.get_child_count() > 0)
	if frame != null:
		var non_box := 0
		var bad_size := 0
		var sizes := {}
		for sh in frame.get_children():
			var cs := sh as CollisionShape3D
			var bx := cs.shape as BoxShape3D
			if bx == null:
				non_box += 1
				continue
			# 足跡必須是正方形（x == z），高度另外算
			if absf(bx.size.x - bx.size.z) > 0.01:
				bad_size += 1
			var key := "%.0f" % bx.size.x
			sizes[key] = int(sizes.get(key, 0)) + 1
		check("框內全是 BoxShape3D（非方塊 %d 塊）" % non_box, non_box == 0)
		check("每個形狀的足跡都是正方形（x≠z 的 %d 塊）" % bad_size, bad_size == 0)
		check("框的尺寸分布：%s 公尺" % str(sizes), not sizes.is_empty())
	# 舊的零散碰撞體不該再存在
	var leftovers: Array = []
	for c in trail.get_children():
		if str(c.name) in ["樹幹碰撞", "岩石與倒木", "岩壁隘口", "獸道大空地", "夜雀屋台區"]:
			for sub in c.get_children():
				if sub is StaticBody3D:
					leftovers.append(str(sub.get_path()))
	check("沒有殘留的舊碰撞 body（%s）" % str(leftovers), leftovers.is_empty())

	print("[WALL] failures=%d" % fails)
	quit(1 if fails > 0 else 0)


func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -40.0, z))
	q.collision_mask = 0xFFFFFFFF
	var hit := space.intersect_ray(q)
	return hit.position.y if hit.has("position") else -INF