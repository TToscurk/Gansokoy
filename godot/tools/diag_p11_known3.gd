extends SceneTree
## P11 R1 診斷（只讀、headless）：既知 3 件の真因を量る。場景・封存には書き込まない。
##   godot --headless --path godot --script res://tools/diag_p11_known3.gd -- [--out=<json>]
## A 神社 P9 R4-2：封存 gate の「參道＋前庭膠囊」と同じ標本点で、地形 S.h と実際の歩行面（下向き射線の最初の地形／RampCollision）の差、
##   膠囊を「歩行面基準」に置いても当たるか（＝本当の障害か、歩行面が地形より高いだけか）。
## B 寺子屋 P9 R4-3：C20 巡回の経路・停止点と、封存 gate の入口ルートの距離；NPC 本体を除いた場合の当たり。
## C B_P_MKT_003：Kit gate 実走と同じ線（局部 x 0.9、正面 3 m → 壁）で、下向き射線の当たり（物体名・高さ）と地形。

const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

var out := {}


func _init() -> void:
	_run.call_deferred()


func _down(sp: PhysicsDirectSpaceState3D, x: float, z: float, from_y := 40.0, exclude: Array[RID] = []) -> Array:
	## 上から下へ、全部の当たりを列挙 [[y, path]]
	var hits := []
	var ex: Array[RID] = exclude.duplicate()
	for i in 12:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -20.0, z))
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			break
		hits.append([snappedf((h["position"] as Vector3).y, 0.001), String(root.get_node("V").get_path_to(h["collider"] as Node))])
		ex.append(h["rid"])
	return hits


func _run() -> void:
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate() as Node3D
	v.name = "V"
	root.add_child(v)
	for i in 6:
		await process_frame
	await physics_frame
	await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var terrain := v.get_node("Collision/TerrainCollision") as CollisionObject3D
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
	var S := RLib.terrain_sampler(v)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	# ── A 神社
	var road: Array = SG.road_pts(L)
	var routes: Array = [road.slice(1), [Vector2(266.0, -208.0), Vector2(258.0, -214.0), Vector2(258.0, -221.5)],
		[Vector2(250.5, -216.0), Vector2(266.0, -216.0)]]
	var A := []
	var n_blk := 0
	var n_blk_surface := 0
	var max_rise := 0.0
	var steps_over := 0
	var prev_surf := NAN
	for route: Array in routes:
		prev_surf = NAN
		for e: Array in GL.resample(route, 0.5):
			var p: Vector2 = e[0]
			if SG.TORII_BOX.grow(0.2).has_point(p) and absf((p - SG.TORII).dot(Vector2(0.927, 0.375))) > 1.6:
				continue
			var h: float = S.h(p.x, p.y)
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cap
			qp.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, h + 0.3 + 0.85 + 0.25, p.y))
			qp.exclude = [terrain.get_rid()]
			var r := sp.intersect_shape(qp, 1)
			# 歩行面：上から最初の当たりが地形か RampCollision ならそれ
			var hits := _down(sp, p.x, p.y, h + 3.0)
			var surf := NAN
			var surf_by := ""
			for hh: Array in hits:
				if String(hh[1]).contains("TerrainCollision") or String(hh[1]).contains("RampCollision"):
					surf = float(hh[0])
					surf_by = String(hh[1]).get_file()
					break
			var r2 := []
			if not is_nan(surf):
				var qp2 := PhysicsShapeQueryParameters3D.new()
				qp2.shape = cap
				qp2.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, surf + 0.3 + 0.85 + 0.25, p.y))
				qp2.exclude = [terrain.get_rid()]
				r2 = sp.intersect_shape(qp2, 1)
			if not is_nan(surf) and not is_nan(prev_surf):
				var st := absf(surf - prev_surf)
				if st > 0.6:
					steps_over += 1
			prev_surf = surf
			if not r.is_empty():
				n_blk += 1
				max_rise = maxf(max_rise, surf - h)
				A.append({"p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01)], "terrain": snappedf(h, 0.001), "surface": snappedf(surf, 0.001), "surface_by": surf_by,
					"rise": snappedf(surf - h, 0.001), "hit": (r[0]["collider"] as Node).name, "blocked_on_surface": not r2.is_empty(),
					"hit_on_surface": (r2[0]["collider"] as Node).name if not r2.is_empty() else ""})
				if not r2.is_empty():
					n_blk_surface += 1
	out["shrine"] = {"blocked_terrain_based": n_blk, "blocked_surface_based": n_blk_surface, "max_surface_rise_m": snappedf(max_rise, 0.001),
		"surface_steps_over_0_6": steps_over, "points": A}
	print("[DIAG] A 神社：地形基準で被擋 %d、歩行面基準で被擋 %d、被擋点の歩行面−地形 最大 %.3f m、隣接標本の歩行面段差 > 0.6 m %d" % [n_blk, n_blk_surface, max_rise, steps_over])
	for a: Dictionary in A.slice(0, 40):
		print("[DIAG]   (%.1f,%.1f) 地形 %.2f 歩行面 %.2f（%s）差 %+.2f 当たり %s／歩行面基準 %s" % [a["p"][0], a["p"][1], a["terrain"], a["surface"], a["surface_by"], a["rise"], a["hit"], a["hit_on_surface"] if a["blocked_on_surface"] else "なし"])
	# ── B 寺子屋
	var school_routes: Array = [[Vector2(208.4, 24.3), Vector2(196.0, 24.0)], [Vector2(197.0, 18.0), Vector2(202.0, 24.0), Vector2(197.6, 31.0)],
		[Vector2(197.2, 33.2), Vector2(195.6, 35.0), Vector2(192.6, 37.6), Vector2(186.0, 38.0), Vector2(180.0, 36.4), Vector2(179.0, 30.0)],
		[Vector2(197.0, 12.5), Vector2(188.0, 11.2), Vector2(180.0, 12.0)]]
	var npc_rids: Array[RID] = [terrain.get_rid()]
	var npc_list := []
	for n in v.find_children("*", "AnimatableBody3D", true, false):
		if String(v.get_path_to(n)).begins_with("Population/"):
			npc_rids.append((n as CollisionObject3D).get_rid())
			npc_list.append(n)
	var b_blk := []
	var b_blk_static := []
	for route: Array in school_routes:
		for e: Array in GL.resample(route, 0.5):
			var p: Vector2 = e[0]
			var qp := PhysicsShapeQueryParameters3D.new()
			qp.shape = cap
			qp.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, S.h(p.x, p.y) + 0.3 + 0.85 + 0.12, p.y))
			qp.exclude = [terrain.get_rid()]
			var r := sp.intersect_shape(qp, 1)
			if not r.is_empty():
				b_blk.append("(%.1f,%.1f) %s" % [p.x, p.y, String(v.get_path_to(r[0]["collider"] as Node))])
			qp.exclude = npc_rids
			var r2 := sp.intersect_shape(qp, 1)
			if not r2.is_empty():
				b_blk_static.append("(%.1f,%.1f) %s" % [p.x, p.y, String(v.get_path_to(r2[0]["collider"] as Node))])
	# C20 の巡回経路：snapshot と最短距離（ルート線分）
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p10r3d_snapshot.json"))
	var c20 := {}
	for k in ["r3d_added", "r3b_baseline"]:
		if snap.has(k):
			for a in (snap[k] as Array):
				if a is Dictionary and String(a.get("id", "")) == "C20":
					c20 = a
	var pathp: Array = (c20.get("patrol", {}) as Dictionary).get("path", [])
	var min_end := INF
	var cross := []
	for route: Array in school_routes:
		for i in route.size() - 1:
			var a0: Vector2 = route[i]
			var a1: Vector2 = route[i + 1]
			for ep in [pathp[0], pathp[pathp.size() - 1]] if pathp.size() > 1 else []:
				var q := Vector2(float(ep[0]), float(ep[1]))
				min_end = minf(min_end, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a0, a1)))
			for j in pathp.size() - 1:
				var b0 := Vector2(float(pathp[j][0]), float(pathp[j][1]))
				var b1 := Vector2(float(pathp[j + 1][0]), float(pathp[j + 1][1]))
				var xp: Variant = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
				if xp != null:
					cross.append([snappedf((xp as Vector2).x, 0.01), snappedf((xp as Vector2).y, 0.01)])
	out["school"] = {"blocked_all": b_blk, "blocked_excluding_npc": b_blk_static, "c20": c20, "c20_endpoint_min_dist_to_route_m": snappedf(min_end, 0.01), "c20_crossings": cross}
	print("[DIAG] B 寺子屋：全体で被擋 %d %s；NPC を除くと %d %s；C20 停止点（巡回両端）→ ルート最短 %.2f m；巡回とルートの交差 %s" % [b_blk.size(), str(b_blk.slice(0, 3)), b_blk_static.size(), str(b_blk_static.slice(0, 3)), min_end, str(cross)])
	# ── C B_P_MKT_003
	var bp := v.find_child("B_P_MKT_003", true, false) as Node3D
	var C := {}
	if bp:
		var xf := bp.global_transform
		var d := float(bp.get_meta("depth_m", 0.0))
		var w := float(bp.get_meta("width_m", 0.0))
		C["xf_origin"] = [snappedf(xf.origin.x, 0.01), snappedf(xf.origin.y, 0.01), snappedf(xf.origin.z, 0.01)]
		C["depth_width_meta"] = [d, w]
		var rows := []
		for k in range(0, 41):
			var lz := d * 0.5 + 3.0 - k * 0.1
			var wp := xf * Vector3(0.9, 0, lz)
			var hits := _down(sp, wp.x, wp.z, xf.origin.y + 6.0)
			var tg := NAN
			for hh: Array in hits:
				if String(hh[1]).contains("TerrainCollision"):
					tg = float(hh[0])
			rows.append({"local_z": snappedf(lz, 0.01), "world": [snappedf(wp.x, 0.01), snappedf(wp.z, 0.01)], "terrain": tg, "hits": hits.slice(0, 4)})
		C["walk_line"] = rows
		print("[DIAG] C B_P_MKT_003 origin %s meta depth %.2f width %.2f" % [str(C["xf_origin"]), d, w])
		for row: Dictionary in rows:
			if (row["hits"] as Array).size() > 0 and not String((row["hits"] as Array)[0][1]).contains("TerrainCollision"):
				print("[DIAG]   局部 z %.2f %s 地形 %.3f 最上 %s" % [row["local_z"], str(row["world"]), row["terrain"], str((row["hits"] as Array).slice(0, 2))])
	else:
		print("[DIAG] C B_P_MKT_003 が見つからない")
	out["mkt003"] = C
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			var f := FileAccess.open(a.trim_prefix("--out="), FileAccess.WRITE)
			f.store_string(JSON.stringify(out, "\t") + "\n")
			f.close()
	quit(0)
