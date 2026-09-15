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
##  2. 沿主脊每隔一段，從路心往左右各做一次 shape cast（玩家膠囊尺寸），
##     要求在 play_half + 容差 之內就被擋住。
##  3. 南北兩端同樣往圖外推。
##  4. 傳送點必須**在牆以內**（玩家走得到），且腳下有地。

const TOL := 2.5           # 牆允許比 play_half 遠多少（盒子厚度 1 m + 餘裕）
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
func _cast(from: Vector3, dir: Vector3, dist: float) -> float:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = dir.normalized() * dist
	q.collision_mask = 0xFFFFFFFF
	var r := space.cast_motion(q)
	# cast_motion 回 [safe, unsafe]，1.0 = 全程沒撞到
	return INF if r[0] >= 0.999 else r[0] * dist


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

	# ── 1. 兩側圍堵 ──
	var worst_gap := 0.0
	var worst_t := 0.0
	var leaks := 0
	for i in SAMPLES:
		var t := float(i) / float(SAMPLES - 1)
		var f: float = t * float(spine.size() - 1)
		var i0 := int(floor(f))
		var i1: int = mini(i0 + 1, spine.size() - 1)
		var c: Vector2 = spine[i0].lerp(spine[i1], f - float(i0))
		var ph: float = lerpf(play[i0], play[i1], f - float(i0))
		var d: Vector2 = _dir_at(spine, i0)
		var perp := Vector2(-d.y, d.x)
		# 起點抬到路面上方 1 m（膠囊中心），沿地面往外掃
		var gy := _ground(c.x, c.y)
		for side in [-1.0, 1.0]:
			var from := Vector3(c.x, gy + 1.2, c.y)
			var dir := Vector3(perp.x * float(side), 0.0, perp.y * float(side))
			var hit := _cast(from, dir, ph + 40.0)
			if hit > ph + TOL:
				leaks += 1
				if hit == INF:
					hit = ph + 40.0
				if hit - ph > worst_gap:
					worst_gap = hit - ph
					worst_t = t
	check("兩側圍堵：%d/%d 次側掃在可動範圍內被擋住（最糟超出 %.1f m @ t=%.2f）"
		% [SAMPLES * 2 - leaks, SAMPLES * 2, worst_gap, worst_t], leaks == 0)

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

	# ── 3. 傳送點：在牆內、腳下有地、Area 存在 ──
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
		# 玩家走得到傳送點：往圖心方向 4 m 內不得有牆。
		# ⚠ 不要拉到 8 m。入口段路旁有界碑碰撞（規格要的景物），
		#   8 m 會掃到它然後誤報成「牆擋住傳送點」。4 m 足以確認
		#   傳送點不是被封在牆外的死角。
		if area != null:
			var to_center := Vector3(-px, 0.0, -pz).normalized()
			var hit := _cast(Vector3(px, gy + 1.2, pz), to_center, 4.0)
			check("傳送點 %s 往圖心 4 m 內無阻擋（實測 %s）"
				% [tgt, "無" if hit == INF else "%.1f m" % hit], hit == INF)

	# ── 4. 走廊內樹幹碰撞存在、牆外的樹沒有碰撞 ──
	var trunk_body: Node = null
	for c in trail.get_children():
		if str(c.name) == "樹幹碰撞":
			trunk_body = c
	check("樹幹碰撞節點存在（%d 根）" % (trunk_body.get_child_count() if trunk_body else 0),
		trunk_body != null and trunk_body.get_child_count() > 0)
	if trunk_body != null:
		# 每根碰撞都該落在可動範圍內
		var outside := 0
		for sh in trunk_body.get_children():
			var sp: Vector3 = (sh as Node3D).position
			var q := Vector2(sp.x, sp.z)
			var best := INF
			var bph := 20.0
			for k in spine.size() - 1:
				var a := spine[k]
				var b := spine[k + 1]
				var ab := b - a
				var u := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				var dd := q.distance_to(a + ab * u)
				if dd < best:
					best = dd
					bph = lerpf(play[k], play[k + 1], u)
			if best > bph + 2.0:
				outside += 1
		check("樹幹碰撞全在可動範圍內（牆外誤加 %d 根）" % outside, outside == 0)

	print("[WALL] failures=%d" % fails)
	quit(1 if fails > 0 else 0)


func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -40.0, z))
	q.collision_mask = 0xFFFFFFFF
	var hit := space.intersect_ray(q)
	return hit.position.y if hit.has("position") else -INF
