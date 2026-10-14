extends SceneTree
## P13 Wave 6 TASK D 診断 3（唯読・headless）：AlbedoPilotP10 の対象 24 棟＋視線（神社高所／主動線）から各建物が見えるか。
##   godot --headless --path . --script res://tools/p13/w6/w6_inventory3.gd -- <out.json>
## 可視性＝建物 AABB 中心（＋屋根高 0.7）へ視点から射線を飛ばし、最初に当たる物体が当該建物の subtree か（Collision 物理射線は使わず、
## 建物の StaticBody 碰撞は B_P_* 直下の Shape で当たるので、射線が最初に当たった collider の親が当該建物かを見る）。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const ROUTE := "res://tools/walk_p10_final_route.json"


func _init() -> void:
	_run.call_deferred()


func _route_points(step: float) -> Array:
	var R: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROUTE))
	var polys := {}
	var order: Array = []
	var seg := ""
	for st: Array in R["route"]:
		match String(st[0]):
			"seg":
				seg = String(st[1])
				polys[seg] = []
				order.append(seg)
			"wp", "tp":
				(polys[seg] as Array).append(Vector2(float(st[1]), float(st[2])))
	var res: Array = []
	for sg: String in order:
		var pts: Array = polys[sg]
		var acc := 0.0
		var next_at := 0.0
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var ln := a.distance_to(b)
			if ln < 0.01:
				continue
			while next_at <= acc + ln:
				res.append(a.lerp(b, (next_at - acc) / ln))
				next_at += step
			acc += ln
	return res


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 12:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var out := {}
	# 1) R6a 24 棟
	var alb := v.get_node_or_null("AlbedoPilotP10")
	var tg: PackedStringArray = alb.get("targets") if alb else PackedStringArray()
	out["albedo_targets"] = Array(tg)
	# 2) 建物リスト
	var blds: Array = []
	for dn in ["Market", "MixedCommercial", "ResidentialWest", "ResidentialNE", "SouthGate"]:
		var b := v.get_node_or_null("Districts/%s/Buildings" % dn)
		if b == null:
			continue
		for bn in b.get_children():
			var p := (bn as Node3D).global_position
			blds.append({"name": String(bn.name), "district": dn, "pos": Vector3(p.x, p.y, p.z), "node": bn})
	# 3) 主動線
	var route := _route_points(10.0)
	out["route_points"] = route.size()
	# 4) 神社高所の視点（山頂社殿前の平地端）＋参道の数点
	var eyes := {
		"shrine_top": Vector3(258.0, 34.0 + 3.0, -215.0),
		"shrine_top_w": Vector3(247.0, 34.0 + 3.0, -218.0),
		"shrine_top_e": Vector3(270.0, 34.0 + 3.0, -218.0),
	}
	# 5) 各建物ごとの結果
	var rows: Array = []
	var space := sp
	for b in blds:
		var bp: Vector3 = b["pos"]
		var node: Node = b["node"]
		var dmin := INF
		for rp: Vector2 in route:
			dmin = minf(dmin, Vector2(bp.x, bp.z).distance_to(rp))
		# 神社高所から見えるか（建物中心 +2.5 m）
		var tgt := Vector3(bp.x, bp.y + 3.0, bp.z)
		var seen_top := 0
		for k in eyes.keys():
			var q := PhysicsRayQueryParameters3D.create(eyes[k], tgt)
			q.collide_with_areas = false
			var ex: Array[RID] = []
			var hit_b := false
			for u in 8:
				q.exclude = ex
				var h := space.intersect_ray(q)
				if h.is_empty():
					hit_b = true
					break
				var col := h.collider as Node
				var chain := col
				var inb := false
				while chain != null:
					if chain == node:
						inb = true
						break
					chain = chain.get_parent()
				if inb:
					hit_b = true
					break
				# 他の建物／地形／樹木等に当たったら遮蔽。ただし Collision は葉・小物の碰撞があるので薄いものは貫通して続行しない
				break
			if hit_b:
				seen_top += 1
		# 主動線の可視回数（路線点から目の高さ 1.7 m、25 m 以内のみ）
		var seen_route := 0
		var near_route := 0
		for rp: Vector2 in route:
			if Vector2(bp.x, bp.z).distance_to(rp) > 30.0:
				continue
			near_route += 1
			var gy := bp.y
			var eye := Vector3(rp.x, gy + 1.7, rp.y)
			var q2 := PhysicsRayQueryParameters3D.create(eye, tgt)
			var h2 := space.intersect_ray(q2)
			var ok := h2.is_empty()
			if not ok:
				var ch := h2.collider as Node
				while ch != null:
					if ch == node:
						ok = true
						break
					ch = ch.get_parent()
			if ok:
				seen_route += 1
		rows.append({"name": b["name"], "district": b["district"], "pos": [snappedf(bp.x, 0.1), snappedf(bp.z, 0.1)], "route_dist": snappedf(dmin, 0.1), "seen_from_shrine_top": seen_top, "route_near": near_route, "route_seen": seen_route})
	out["rows"] = rows
	var out_path := ""
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			out_path = a
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t") + "\n")
	f.close()
	print("[INV3] done rows=", rows.size(), " albedo_targets=", tg.size())
	quit(0)
