extends SceneTree
## P13 W9 Round 2.1 収尾：庇柱・玄関柱の碰撞を『実際の物理空間』で検査する。
##   godot --headless --path godot --script res://tools/p13/w9/verify_w9r2_posts.gd
## 見るもの：
##   ① 各柱で、実プレイヤーと同じ capsule（main.tscn が使う characters/yoriichi/player_yoriichi.tscn：r 0.30・h 1.7。実行時に読む）が柱の見た目に 2 cm 食い込む位置に立てない（柱の 4 面）／柱の中心を通る直線は必ず止まる（通り抜けない）。
##   ② 柱から見た目の面 + 余白だけ離れれば止まらない（碰撞が過大でない）／柱のない位置では止まらない（検査が空振りでない）。
##   ③ enabled=false で柱の碰撞は消え（Before＝柱なし）、true で戻る。
##   ④ 柱が通行を塞がない：戸口へ真っすぐ入る線（街側 3 m → 戸口 0.4 m）に柱が当たらない／封存済み NPC（R3b・R3d・R3e の待機位置と巡回経路）から
##      NPC 半径 + 柱 + 余白 以上離れている。
const L := preload("res://tools/p13/w9/w9r2_lib.gd")
## 玩家 capsule は main.tscn が実際に使う player_yoriichi.tscn から読む（Phase 2 で、従来ここに書いていた scenes/player.tscn の r 0.45 は main.tscn の玩家ではないと判明＝実際は r 0.30）
const PLAYER_SCENE := "res://characters/yoriichi/player_yoriichi.tscn"
var PLAYER_R := 0.30
var PLAYER_H := 1.7
const NPC_R := 0.35
const VIS_HALF := 0.07           # 見た目の柱の半幅（w 0.14）
const SNAPS := ["res://data/village_v2_p10r3b_snapshot.json", "res://data/village_v2_p10r3d_snapshot.json", "res://data/village_v2_p10r3e_snapshot.json"]

var passed := 0
var failed := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("[W9R2P] PASS ", msg)
	else:
		failed += 1
		print("[W9R2P] FAIL ", msg)


func _init() -> void:
	_run.call_deferred()


## capsule を g（床からの高さ＝足元）に置いて、衝突した相手に名前 "Posts" の body が含まれるか。
func _hits_posts(space: PhysicsDirectSpaceState3D, caps: CapsuleShape3D, g: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = caps
	q.transform = Transform3D(Basis.IDENTITY, g + Vector3(0.0, PLAYER_H / 2.0 + 0.05, 0.0))
	q.collision_mask = 1
	for r: Dictionary in space.intersect_shape(q, 16):
		var c = r.get("collider")
		if c is Node and String((c as Node).name) == "Posts":
			return true
	return false


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 1.0e-9 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## スナップショット JSON から [待機位置(Vector2)…]、[巡回経路(Array of Vector2)…] を集める
static func _npc_points(snaps: Array) -> Array:
	var idle: Array = []
	var routes: Array = []
	var stack: Array = snaps.duplicate()
	while not stack.is_empty():
		var o = stack.pop_back()
		if o is Array:
			stack.append_array(o)
		elif o is Dictionary:
			var d: Dictionary = o
			if d.has("position") and d["position"] is Array and (d["position"] as Array).size() == 3:
				idle.append(Vector2(float(d["position"][0]), float(d["position"][2])))
			if d.has("patrol") and d["patrol"] is Dictionary and (d["patrol"] as Dictionary).has("path"):
				var path: Array = []
				for q in (d["patrol"] as Dictionary)["path"]:
					path.append(Vector2(float(q[0]), float(q[1])))
				routes.append(path)
			for k in d:
				if d[k] is Array or d[k] is Dictionary:
					stack.append(d[k])
	return [idle, routes]


func _run() -> void:
	var meta := JSON.parse_string(FileAccess.get_file_as_string(L.META)) as Dictionary
	var posts_meta: Dictionary = meta.get("posts", {})
	var pinst := (load(PLAYER_SCENE) as PackedScene).instantiate()
	var pcs := pinst.get_node("CollisionShape3D") as CollisionShape3D
	PLAYER_R = (pcs.shape as CapsuleShape3D).radius
	PLAYER_H = (pcs.shape as CapsuleShape3D).height
	pinst.free()
	print("[W9R2P] 玩家 capsule（%s）：r %.2f・h %.2f" % [PLAYER_SCENE, PLAYER_R, PLAYER_H])
	var snaps: Array = []
	for f: String in SNAPS:
		snaps.append(JSON.parse_string(FileAccess.get_file_as_string(f)))
	var np := _npc_points(snaps)
	var v := (load(L.SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(v)
	for i in 6:
		await process_frame
	for i in 3:
		await physics_frame
	var ov := v.get_node(L.NODE_NAME)
	var space := v.get_world_3d().direct_space_state
	var caps := CapsuleShape3D.new()
	caps.radius = PLAYER_R
	caps.height = PLAYER_H
	var gposts: Array = []          # [id, Vector3 global（足元）, Vector2 外向き（街側）の単位ベクトル, half]
	var n_posts := 0
	for id: String in posts_meta:
		var body := v.get_node(NodePath(L.SPECS[id]["path"])) as Node3D
		var sb := ov.get_node(id).get_node_or_null("Posts") as StaticBody3D
		_ok(sb != null, "%s：Posts 碰撞がある" % id)
		var out3 := body.global_transform.basis * Vector3(0.0, 0.0, 1.0)         # 局部 +z＝街側
		var out2 := Vector2(out3.x, out3.z).normalized()
		for pd: Dictionary in posts_meta[id]:
			var g := body.global_transform * Vector3(float(pd["x"]), 0.0, float(pd["z"]))
			var half := float(pd["w"]) / 2.0 + L.POST_PAD
			gposts.append([id, g, out2, maxf(half, 0.125)])
			n_posts += 1
	_ok(n_posts == 6 or n_posts > 0, "柱 %d 本（%d 棟）" % [n_posts, posts_meta.size()])
	# ① 食い込む位置に立てない／直線で通り抜けられない  ② 離れれば止まらない・空振りでない
	var blocked_all := true
	var through_ok := true
	var clear_ok := true
	var empty_ok := true
	for gi in gposts.size():
		var gp: Array = gposts[gi]
		var g: Vector3 = gp[1]
		var o2: Vector2 = gp[2]
		var t2 := Vector2(-o2.y, o2.x)
		var bad: PackedStringArray = []
		# 食い込み（見た目の面から 2 cm 内側）の 4 方向：全部止まる
		for dv: Vector2 in [o2, -o2, t2, -t2]:
			var d := PLAYER_R + VIS_HALF - 0.02
			if not _hits_posts(space, caps, g + Vector3(dv.x * d, 0.0, dv.y * d)):
				blocked_all = false
				bad.append("食い込み %s" % str(dv))
		# 柱の中心を通る直線（街側／横）：0.05 m 刻みのどこかで必ず止まる
		for dv: Vector2 in [o2, t2]:
			var hit := false
			for k in range(-40, 41):
				var s := 0.05 * k
				if _hits_posts(space, caps, g + Vector3(dv.x * s, 0.0, dv.y * s)):
					hit = true
					break
			if not hit:
				through_ok = false
				bad.append("通り抜け %s" % str(dv))
		# 碰撞の外 +6 cm（街側）は止まらない。ただし同じ建物の別の碰撞箱（薪・桶・荷受け台など近接して並ぶ小物）が probe の円に触れる位置なら、
		# その probe は『別の箱』の領分なので判定から外す（箱ごとの局部座標で、円と他の箱の距離が capsule 半径 + 4 cm 未満のとき）。
		var pr := Vector2(0.0, PLAYER_R + float(gp[3]) + 0.06)         # この箱の局部（t2, o2）での probe 位置
		var near_other := false
		for gj in gposts.size():
			if gj == gi:
				continue
			var gq: Array = gposts[gj]
			if String(gq[0]) != String(gp[0]):
				continue
			var dq := Vector2((gq[1] as Vector3).x - g.x, (gq[1] as Vector3).z - g.z)
			var cq := Vector2(dq.dot(t2), dq.dot(o2))                  # 他の箱の中心（この箱の局部座標）
			var hq := float(gq[3])
			var ex := maxf(absf(pr.x - cq.x) - hq, 0.0)
			var ez := maxf(absf(pr.y - cq.y) - hq, 0.0)
			if Vector2(ex, ez).length() < PLAYER_R + 0.04:
				near_other = true
				break
		if not near_other and _hits_posts(space, caps, g + Vector3(o2.x * pr.y, 0.0, o2.y * pr.y)):
			clear_ok = false
			bad.append("碰撞が過大")
		# 柱のない位置（街側へ 4 m）では止まらない
		if _hits_posts(space, caps, g + Vector3(o2.x * 4.0, 0.0, o2.y * 4.0)):
			empty_ok = false
			bad.append("空振り")
		if not bad.is_empty():
			print("[W9R2P]   %s (%.2f, %.2f)：%s" % [gp[0], g.x, g.z, ", ".join(bad)])
	_ok(blocked_all, "全 %d 本：プレイヤー capsule（r %.2f・h %.1f）は柱の見た目に食い込む位置に立てない（4 方向）" % [gposts.size(), PLAYER_R, PLAYER_H])
	_ok(through_ok, "全 %d 本：柱の中心を通る直線（街側・横）は必ず止まる（通り抜けない）" % gposts.size())
	_ok(clear_ok, "全 %d 本：碰撞の外 6 cm では止まらない（過大な碰撞でない）" % gposts.size())
	_ok(empty_ok, "全 %d 本：柱のない位置（街側 4 m）では止まらない（検査が空振りでない）" % gposts.size())
	# ④ 戸口へ真っすぐ入る線に柱が当たらない
	var door_ok := true
	for id: String in posts_meta:
		var body := v.get_node(NodePath(L.SPECS[id]["path"])) as Node3D
		var kit := body.get_node("Kit")
		var dcx := float(kit.get_meta("door_cx", 0.0))
		var shp := body.get_node("Shape") as CollisionShape3D
		var zf := (shp.shape as BoxShape3D).size.z / 2.0
		var worst := 0
		for k in range(0, 27):
			var zz := zf + 3.0 - 0.1 * k
			if _hits_posts(space, caps, body.global_transform * Vector3(dcx, 0.0, zz)):
				worst += 1
		if worst > 0:
			door_ok = false
		print("[W9R2P]   %s 戸口 x=%.2f へ（街側 3 m → 0.4 m）：柱に当たる刻み %d／27" % [id, dcx, worst])
	_ok(door_ok, "戸口へ真っすぐ入る線（街側 3 m → 0.4 m）に柱が当たらない")
	# NPC：待機位置と巡回経路から NPC 半径 + 柱 + 余白（0.15）以上
	var idle: Array = np[0]
	var routes: Array = np[1]
	var min_idle := 1.0e9
	var min_route := 1.0e9
	for gp: Array in gposts:
		var p2 := Vector2((gp[1] as Vector3).x, (gp[1] as Vector3).z)
		var hh: float = float(gp[3])      # 碰撞箱の半幅（柱 0.125〜／荷受け台・薪・桶などの小物 0.18〜0.28）を引いた『縁までの距離』で見る
		for q: Vector2 in idle:
			min_idle = minf(min_idle, p2.distance_to(q) - hh)
		for path: Array in routes:
			for i in range(path.size() - 1):
				min_route = minf(min_route, _seg_dist(p2, path[i], path[i + 1]) - hh)
	var need := NPC_R + 0.15
	_ok(min_idle >= need, "封存済み NPC の待機位置 %d 点：碰撞箱の縁との最短 %.2f m ≥ %.2f m" % [idle.size(), min_idle, need])
	_ok(min_route >= need, "封存済み NPC の巡回経路 %d 本：碰撞箱の縁との最短 %.2f m ≥ %.2f m" % [routes.size(), min_route, need])
	# ③ enabled の往復
	var g0: Array = gposts[0]
	var probe: Vector3 = g0[1]
	_ok(_hits_posts(space, caps, probe), "enabled=true：柱の位置に立てない（基準）")
	ov.set("enabled", false)
	await process_frame
	await process_frame
	await physics_frame
	await physics_frame
	var off_hits := 0
	for gp: Array in gposts:
		if _hits_posts(space, caps, gp[1]):
			off_hits += 1
	_ok(off_hits == 0, "enabled=false（Before）：柱の碰撞は全て消える（残り %d／%d）" % [off_hits, gposts.size()])
	ov.set("enabled", true)
	await process_frame
	await process_frame
	await physics_frame
	await physics_frame
	var on_hits := 0
	for gp: Array in gposts:
		if _hits_posts(space, caps, gp[1]):
			on_hits += 1
	_ok(on_hits == gposts.size(), "enabled=true に戻すと柱の碰撞が全て復活（%d／%d）" % [on_hits, gposts.size()])
	print("[W9R2P] 結果：%d 通過・%d 失敗" % [passed, failed])
	quit(0 if failed == 0 else 1)
