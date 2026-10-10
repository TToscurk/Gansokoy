extends SceneTree
## P11 R1 診斷（只讀、headless）：51 名 NPC の站位・巡回と靜的碰撞／玩家通行の関係。場景・封存には書き込まない。
##   godot --headless --path godot --script res://tools/diag_p11_npc.gd -- [--out=<json>]
## ① 待機（idle）NPC の碰撞膠囊が靜的碰撞（地形・他の NPC 以外）にめり込むか（深さ＝collide_shape の接点距離）
## ② 巡回 NPC：経路を 0.1 m 毎に、NPC の碰撞膠囊を path_y の高さで置き、靜的碰撞へのめり込み（NPC が物を通り抜ける）
## ③ 玩家ルート（tools/walk_p11_route.json の wp 折れ線、tp 区間の切れ目は繋がない）から 1.2 m 以内の NPC：
##    NPC の位置でルート法線方向の靜的通行幅（NPC 除外、玩家膠囊 r 0.3）と、NPC が占める分を引いた残り幅（< 0.9 m ＝すれ違い不可）

const PL := preload("res://tools/village_v2_population_lib.gd")

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(v)
	for i in 6:
		await process_frame
	await physics_frame
	await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var terr := v.get_node("Collision/TerrainCollision") as CollisionObject3D
	var actors: Array = []
	for n in v.get_node("Population").find_children("*", "AnimatableBody3D", true, false):
		if n.get("mode") != null:
			actors.append(n)
	var ex: Array[RID] = [terr.get_rid()]
	for a in actors:
		ex.append((a as CollisionObject3D).get_rid())
	var rows := []
	var pen_idle := 0
	var pen_patrol := 0
	for a in actors:
		var n := a as Node3D
		var cs: CollisionShape3D = null
		for c in n.get_children():
			if c is CollisionShape3D:
				cs = c
		if cs == null:
			continue
		var local := cs.transform
		var row := {"npc": String(v.get_path_to(n)), "mode": String(n.get("mode")), "pos": [snappedf(n.global_position.x, 0.01), snappedf(n.global_position.z, 0.01)]}
		var samples: Array = []
		if String(n.get("mode")) == "patrol":
			var px: PackedVector2Array = n.get("path_xz")
			var py: PackedFloat32Array = n.get("path_y")
			var L := 0.0
			for i in px.size() - 1:
				L += px[i].distance_to(px[i + 1])
			var k := 0
			while k * 0.1 <= L:
				var u := k * 0.1
				var p2 := _path_at(px, u)
				var fy := u / 0.25
				var j := clampi(floori(fy), 0, py.size() - 2)
				var y := lerpf(py[j], py[j + 1], clampf(fy - j, 0.0, 1.0))
				samples.append(Transform3D(n.global_transform.basis, Vector3(p2.x, y, p2.y)) * local)
				k += 1
			row["path_len"] = snappedf(L, 0.01)
		else:
			samples.append(n.global_transform * local)
		var worst := 0.0
		var worst_with := ""
		var hit_n := 0
		for xf: Transform3D in samples:
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cs.shape
			q.transform = xf
			q.exclude = ex
			var res := sp.collide_shape(q, 8)
			var r2 := sp.intersect_shape(q, 4)
			if res.is_empty():
				continue
			hit_n += 1
			for i in range(0, res.size(), 2):
				var d := (res[i] as Vector3).distance_to(res[i + 1])
				if d > worst:
					worst = d
					worst_with = String(v.get_path_to(r2[0]["collider"] as Node)) if not r2.is_empty() else "?"
		row["penetration_samples"] = hit_n
		row["samples"] = samples.size()
		row["max_depth_m"] = snappedf(worst, 0.001)
		row["with"] = worst_with
		if worst > 0.05:
			if String(n.get("mode")) == "patrol":
				pen_patrol += 1
			else:
				pen_idle += 1
		rows.append(row)
	# ③ ルート近傍
	var R: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/walk_p11_route.json"))
	var lines: Array = []
	var cur: Array = []
	for st: Array in R["route"]:
		if String(st[0]) == "tp":
			if cur.size() >= 2:
				lines.append(cur)
			cur = [Vector2(float(st[1]), float(st[2]))]
		elif String(st[0]) == "wp":
			cur.append(Vector2(float(st[1]), float(st[2])))
	if cur.size() >= 2:
		lines.append(cur)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var near := []
	for a in actors:
		var n := a as Node3D
		var q := Vector2(n.global_position.x, n.global_position.z)
		var best := INF
		var dir := Vector2.RIGHT
		for ln: Array in lines:
			for i in ln.size() - 1:
				var cp := Geometry2D.get_closest_point_to_segment(q, ln[i], ln[i + 1])
				if cp.distance_to(q) < best:
					best = cp.distance_to(q)
					dir = ((ln[i + 1] as Vector2) - (ln[i] as Vector2)).normalized()
		if best > 1.2:
			continue
		var nrm := Vector2(-dir.y, dir.x)
		var free := [0.0, 0.0]
		for si in 2:
			var sgn := -1.0 if si == 0 else 1.0
			var t := 0.0
			while t < 4.0:
				var pp: Vector2 = q + nrm * (t + 0.05) * sgn
				var qp := PhysicsShapeQueryParameters3D.new()
				qp.shape = cap
				qp.transform = Transform3D(Basis.IDENTITY, Vector3(pp.x, n.global_position.y + 0.3 + 0.85 + 0.15, pp.y))
				qp.exclude = ex
				if not sp.intersect_shape(qp, 1).is_empty():
					break
				t += 0.05
			free[si] = t
		var width := float(free[0]) + float(free[1]) + 0.6
		var pass_side := maxf(float(free[0]), float(free[1])) - PL.CAP_R - 0.3
		near.append({"npc": String(v.get_path_to(n)), "mode": String(n.get("mode")), "dist_route_m": snappedf(best, 0.01), "static_width_m": snappedf(width, 0.01),
			"widest_side_after_npc_m": snappedf(pass_side + 0.6, 0.01), "pos": [snappedf(q.x, 0.01), snappedf(q.y, 0.01)]})
	var tight := near.filter(func(r): return float(r["widest_side_after_npc_m"]) < 0.9)
	print("[NPC] NPC %d（patrol %d）；靜的碰撞へのめり込み > 0.05 m：待機 %d・巡回 %d；ルート 1.2 m 以内 %d 体、NPC の横を抜ける幅 < 0.9 m %d 体" % [actors.size(),
		actors.filter(func(a): return String(a.get("mode")) == "patrol").size(), pen_idle, pen_patrol, near.size(), tight.size()])
	for r: Dictionary in rows:
		if float(r["max_depth_m"]) > 0.02:
			print("[NPC]   めり込み %s %s %.3f m（%d/%d 標本）← %s" % [r["npc"], r["mode"], r["max_depth_m"], r["penetration_samples"], r["samples"], r["with"]])
	for r: Dictionary in near:
		print("[NPC]   ルート近傍 %s %s 距離 %.2f 靜的幅 %.2f 横を抜ける幅 %.2f" % [r["npc"], r["mode"], r["dist_route_m"], r["static_width_m"], r["widest_side_after_npc_m"]])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			var f := FileAccess.open(a.trim_prefix("--out="), FileAccess.WRITE)
			f.store_string(JSON.stringify({"actors": rows, "near_route": near}, "\t") + "\n")
			f.close()
	quit(0)


func _path_at(path: PackedVector2Array, u: float) -> Vector2:
	var acc := 0.0
	for i in path.size() - 1:
		var l := path[i].distance_to(path[i + 1])
		if acc + l >= u:
			return path[i].lerp(path[i + 1], clampf((u - acc) / maxf(l, 1e-6), 0.0, 1.0))
		acc += l
	return path[path.size() - 1]
