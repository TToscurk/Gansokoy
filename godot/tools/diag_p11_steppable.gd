extends SceneTree
## P11 R1 診斷（只讀、headless）：「歩いただけで乗り上がる」低い構件碰撞の棚卸し。
## 玩家（yoriichi_character.gd）の step_height＝0.6 m：足元の障害の上面が 0.6 m 以内なら自動で持ち上げる。
## 各 overlay の BoxShape3D／CylinderShape3D について、上面−地形（中心の地形射線）を測り、0.25–0.60 m（＝段差として乗り上がる帯）を列挙。
## 同時に最寄りの建物碰撞（Districts/**/B_*、Landmarks/*/Hero）までの水平距離も記録（店先・戸口前かどうか）。
##   godot --headless --path godot --script res://tools/diag_p11_steppable.gd -- [--out=<json>]

const STEP := 0.6
const LOW := 0.25
const SKIP_PREFIX := ["Collision/", "Terrain", "Water", "Districts/FarmlandEast", "Riverbank", "Roads", "ShrineApproachP10", "Debug", "Population", "Landmarks", "Districts/"]


func _init() -> void:
	_run.call_deferred()


func _terrain_y(sp: PhysicsDirectSpaceState3D, terr: RID, x: float, z: float) -> float:
	var ex: Array[RID] = []
	for i in 16:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60.0, z), Vector3(x, -30.0, z))
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if h["rid"] == terr:
			return float((h["position"] as Vector3).y)
		ex.append(h["rid"])
	return NAN


func _run() -> void:
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(v)
	for i in 6:
		await process_frame
	await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var terr := (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	# 建物の足元（2D）：B_* と Hero の碰撞形の AABB（xz）
	var bld: Array = []
	for co in v.find_children("*", "CollisionObject3D", true, false):
		var path := String(v.get_path_to(co))
		if not ((path.begins_with("Districts/") and String(co.name).begins_with("B_")) or (path.begins_with("Landmarks/") and path.ends_with("/Hero"))):
			continue
		for s in co.get_children():
			if s is CollisionShape3D and (s as CollisionShape3D).shape:
				var ab := _shape_aabb(s as CollisionShape3D)
				bld.append([Rect2(ab.position.x, ab.position.z, ab.size.x, ab.size.z), path.get_file()])
	var rows := []
	var by_group := {}
	for co in v.find_children("*", "CollisionObject3D", true, false):
		var path := String(v.get_path_to(co))
		var skip := false
		for pre: String in SKIP_PREFIX:
			if path.begins_with(pre):
				skip = true
		if skip or not (co is StaticBody3D):
			continue
		for s in co.get_children():
			if not (s is CollisionShape3D) or (s as CollisionShape3D).disabled or (s as CollisionShape3D).shape == null:
				continue
			var cs := s as CollisionShape3D
			if not (cs.shape is BoxShape3D or cs.shape is CylinderShape3D):
				continue
			var ab := _shape_aabb(cs)
			var c := ab.get_center()
			var g := _terrain_y(sp, terr, c.x, c.z)
			if is_nan(g):
				continue
			var top := ab.end.y - g
			if top <= LOW or top > STEP:
				continue
			var bot := ab.position.y - g
			var near := INF
			var near_b := ""
			var r2 := Rect2(ab.position.x, ab.position.z, ab.size.x, ab.size.z)
			for b: Array in bld:
				var br: Rect2 = b[0]
				var dx := maxf(0.0, maxf(br.position.x - r2.end.x, r2.position.x - br.end.x))
				var dz := maxf(0.0, maxf(br.position.y - r2.end.y, r2.position.y - br.end.y))
				var dd := Vector2(dx, dz).length()
				if dd < near:
					near = dd
					near_b = b[1]
			var grp := path.get_slice("/", 0) + "/" + path.get_slice("/", 1)
			var nm := String(cs.name)
			var item := nm.trim_suffix("_c").trim_suffix("_c0").trim_suffix("_c1")
			var row := {"overlay": grp, "body": path, "shape": nm, "center": [snappedf(c.x, 0.01), snappedf(c.z, 0.01)], "top_above_ground": snappedf(top, 0.01),
				"bottom_above_ground": snappedf(bot, 0.01), "size_xz": [snappedf(ab.size.x, 0.01), snappedf(ab.size.z, 0.01)], "nearest_building": near_b, "dist_building_m": snappedf(near, 0.01)}
			rows.append(row)
			by_group[grp] = int(by_group.get(grp, 0)) + 1
	rows.sort_custom(func(a, b): return float(a["dist_building_m"]) < float(b["dist_building_m"]))
	print("[STEP] 乗り上がり帯（上面−地形 %.2f–%.2f m）の構件碰撞：%d 件；overlay 別 %s" % [LOW, STEP, rows.size(), str(by_group)])
	var near_cnt := rows.filter(func(r): return float(r["dist_building_m"]) <= 1.2).size()
	print("[STEP]   そのうち建物の碰撞から 1.2 m 以内（店先・戸口前）：%d 件" % near_cnt)
	for r: Dictionary in rows.slice(0, 60):
		print("[STEP]   %s %s 上面 %.2f 下面 %.2f 平面 %s → %s %.2f m" % [r["body"], r["shape"], r["top_above_ground"], r["bottom_above_ground"], str(r["size_xz"]), r["nearest_building"], r["dist_building_m"]])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			var f := FileAccess.open(a.trim_prefix("--out="), FileAccess.WRITE)
			f.store_string(JSON.stringify({"step_height": STEP, "low": LOW, "count": rows.size(), "near_building_1_2m": near_cnt, "by_overlay": by_group, "rows": rows}, "\t") + "\n")
			f.close()
	quit(0)


func _shape_aabb(cs: CollisionShape3D) -> AABB:
	var xf := cs.global_transform
	var he := Vector3.ZERO
	if cs.shape is BoxShape3D:
		he = (cs.shape as BoxShape3D).size * 0.5
	else:
		var cy := cs.shape as CylinderShape3D
		he = Vector3(cy.radius, cy.height * 0.5, cy.radius)
	var ab := AABB(xf * Vector3(-he.x, -he.y, -he.z), Vector3.ZERO)
	for i in 8:
		ab = ab.expand(xf * Vector3(he.x * (1 if i & 1 else -1), he.y * (1 if i & 2 else -1), he.z * (1 if i & 4 else -1)))
	return ab
