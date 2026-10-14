extends SceneTree
## P13 W9 短距離の通行検査（物理）：実際の物理空間で、玩家と同じ大きさのカプセル（半径 0.35・高 1.7）を経路に沿って 0.25 m ごとに置き、
## EnrichW9P13/Collision に触れるか数える。経路＝巷の中心線とその両端寄り、主街の中心線と両端寄り、農家の踏石道・庭先の帯、NPC の巡回路全部。
## 反向：W9 の碰撞箱を貫く経路は必ず検出される。
##   godot --headless --path godot --script res://tools/p13/w9/w9_walk_check.gd
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const FARM := preload("res://tools/village_v2_farmstead_lib.gd")

var hits_total := 0


func _init() -> void:
	_run.call_deferred()


func _poly_pts(pts: Array, step: float, off: float) -> Array:
	var out: Array = []
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var d := b - a
		var L := d.length()
		if L < 0.01:
			continue
		var n := Vector2(-d.y, d.x).normalized() * off
		var k := int(ceil(L / step))
		for j in k + 1:
			out.append(a + d * (float(j) / float(k)) + n)
	return out


func _sweep(space: PhysicsDirectSpaceState3D, caps: CapsuleShape3D, pts: Array, body_rid: RID) -> Array:
	var hits: Array = []
	for p: Vector2 in pts:
		var rp := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60.0, p.y), Vector3(p.x, -20.0, p.y))
		rp.exclude = [body_rid]      # W9 の碰撞箱の上面に乗らない（地面の高さを取る）
		var r := space.intersect_ray(rp)
		if r.is_empty():
			continue
		var y: float = (r["position"] as Vector3).y
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = caps
		q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, y + 0.85 + 0.12, p.y))   # 0.12 m は段差を乗り越える分（足元の石畳・縁石）
		q.collide_with_bodies = true
		var res := space.intersect_shape(q, 8)
		for h in res:
			if (h["rid"] as RID) == body_rid:
				hits.append(p)
				break
	return hits


## 歩ける格子（0.25 m）で a → b に行けるか：W9 の碰撞を含める／除く 2 通りで比べる。返り値＝経路長（行けなければ -1）
func _reach(space: PhysicsDirectSpaceState3D, caps: CapsuleShape3D, body_rid: RID, a: Vector2, b: Vector2, with_w9: bool, margin := 7.0) -> float:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(margin, margin)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(margin, margin)
	var st := 0.25
	var nx := int((hi.x - lo.x) / st) + 1
	var nz := int((hi.y - lo.y) / st) + 1
	var cache := {}
	var free_fn := func(ix: int, iz: int) -> bool:
		var key := ix * 100000 + iz
		if cache.has(key):
			return cache[key]
		var p := lo + Vector2(ix, iz) * st
		var rp := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60.0, p.y), Vector3(p.x, -20.0, p.y))
		rp.exclude = [body_rid]
		var r := space.intersect_ray(rp)
		var ok := false
		if not r.is_empty():
			var y: float = (r["position"] as Vector3).y
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = caps
			q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, y + 0.85 + 0.12, p.y))
			if not with_w9:
				q.exclude = [body_rid]
			ok = space.intersect_shape(q, 1).is_empty()
		cache[key] = ok
		return ok
	var sa := Vector2i(int(round((a.x - lo.x) / st)), int(round((a.y - lo.y) / st)))
	var sb := Vector2i(int(round((b.x - lo.x) / st)), int(round((b.y - lo.y) / st)))
	if not free_fn.call(sa.x, sa.y) or not free_fn.call(sb.x, sb.y):
		return -2.0
	var dist := {sa: 0.0}
	var open: Array = [sa]
	var head := 0
	while head < open.size():
		var cur: Vector2i = open[head]
		head += 1
		if cur == sb:
			return float(dist[cur])
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var nb: Vector2i = cur + d
			if nb.x < 0 or nb.y < 0 or nb.x >= nx or nb.y >= nz or dist.has(nb):
				continue
			if not free_fn.call(nb.x, nb.y):
				continue
			if absi(d.x) + absi(d.y) == 2 and (not free_fn.call(cur.x + d.x, cur.y) or not free_fn.call(cur.x, cur.y + d.y)):
				continue
			dist[nb] = float(dist[cur]) + (st * 1.4142 if absi(d.x) + absi(d.y) == 2 else st)
			open.append(nb)
	return -1.0


func _run() -> void:
	var v: Node3D = (load(W9.SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await physics_frame
	var own := v.get_node(W9.NODE_NAME) as Node3D
	var col := own.get_node("Collision") as StaticBody3D
	var space := root.get_world_3d().direct_space_state
	var caps := CapsuleShape3D.new()
	caps.radius = 0.35
	caps.height = 1.7
	var C := W9.context(v, PackedVector2Array())
	var routes := {}
	for rn: String in ["WestBankLane", "MainStreet"]:
		var rd: Dictionary = (C["roads"] as Dictionary).get(rn, {})
		if rd.is_empty():
			print("[W9W] 道なし ", rn)
			continue
		var pts: Array = rd["pts"]
		var hw := float(rd["hw"])
		for off in [0.0, hw - 0.7, -(hw - 0.7)]:
			routes["%s off %+.1f" % [rn, off]] = _poly_pts(pts, 0.25, off)
	var stones: Array = []
	for s in FARM.STONES:
		stones.append(s)
	routes["Farm 踏石道"] = _poly_pts(stones, 0.25, 0.0)
	routes["入口の辻の前"] = _poly_pts([Vector2(236.0, 108.0), Vector2(236.0, 94.0), Vector2(238.0, 60.0)], 0.25, 0.0)
	var k := 0
	for pts2: PackedVector2Array in C["npc_paths"]:
		k += 1
		routes["NPC 巡回 %03d" % k] = _poly_pts(Array(pts2), 0.25, 0.0)
	var bad := 0
	var n_pts := 0
	var near_w9 := 0
	for name: String in routes:
		var pts3: Array = routes[name]
		n_pts += pts3.size()
		var hits := _sweep(space, caps, pts3, col.get_rid())
		if hits.size() > 0:
			bad += 1
			print("[W9W] 接触 %s：%d 点（最初 (%.1f, %.1f)）" % [name, hits.size(), (hits[0] as Vector2).x, (hits[0] as Vector2).y])
		hits_total += hits.size()
	print("[W9W] 経路 %d 本・検査点 %d・W9 の碰撞に触れた経路 %d・触れた点 %d" % [routes.size(), n_pts, bad, hits_total])
	# 到達性：庭先の「歩ける道」が W9 の構件で塞がれたり大回りになったりしていない（直線で突っ切る検査ではなく、実際に歩ける格子で比べる）
	var legs := [
		["Farm 渡し板 → 主屋の戸口", Vector2(326.4, 70.9), Vector2(322.6, 84.2), 7.0],
		["Farm 渡し板 → 庭の南端", Vector2(326.4, 70.9), Vector2(325.6, 92.0), 7.0],
		["Farm 戸口 → 庭の南端", Vector2(322.6, 84.2), Vector2(325.6, 92.0), 6.0],
		["入口の辻：道の縁 → 祠の前", Vector2(239.8, 96.0), Vector2(244.8, 96.4), 6.0],
		["入口の辻：道の縁 → 縁台の前", Vector2(239.8, 101.8), Vector2(243.6, 101.8), 6.0],
	]
	var reach_bad := 0
	for lg: Array in legs:
		var w_ := _reach(space, caps, col.get_rid(), lg[1], lg[2], true, float(lg[3]))
		var wo := _reach(space, caps, col.get_rid(), lg[1], lg[2], false, float(lg[3]))
		var ratio := (w_ / wo) if (w_ > 0.0 and wo > 0.0) else -1.0
		var ok_leg := (w_ > 0.0 and wo > 0.0 and ratio <= 1.25) or (wo < 0.0 and w_ < 0.0)
		if not ok_leg:
			reach_bad += 1
		print("[W9W] 到達 %-26s W9 あり %.1f m・なし %.1f m・比 %.2f %s" % [lg[0], w_, wo, ratio, "OK" if ok_leg else "NG"])
	print("[W9W] 到達性：%d 区間中 NG %d" % [legs.size(), reach_bad])
	bad += reach_bad
	# 反向：W9 の碰撞箱の中心を通る経路は検出される
	var neg_ok := 0
	var shapes := col.get_children().filter(func(c: Node) -> bool: return c is CollisionShape3D)
	for i in mini(5, shapes.size()):
		var cs := shapes[i * (shapes.size() / 5)] as CollisionShape3D
		var c := cs.global_transform.origin
		var h := _sweep(space, caps, [Vector2(c.x, c.z)], col.get_rid())
		if h.size() > 0:
			neg_ok += 1
	print("[W9W] 反向：碰撞箱の中心を通る点は検出される（%d／5）" % neg_ok)
	var ok := bad == 0 and neg_ok == 5
	print("[W9W] 結果：%s" % ("0 項失敗" if ok else "失敗あり"))
	quit(0 if ok else 1)
