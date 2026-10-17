extends "res://tools/p13/w6/w6_base.gd"
## [scratch：丘腳社寺 E2 地面層高度勘查] 唯讀。對境內數個點，列出所有「蓋在地形上」的可見面層（Ground／Yards／Road／Drape／EdgeBlend…）的 y − 地形 y。
##   godot --path godot --script <this> -- <outdir/> LAYERS2 --map=village_v2
const PTS := [Vector2(228, -153.5), Vector2(228, -157), Vector2(228, -159), Vector2(225, -161), Vector2(231, -162), Vector2(228, -164.5),
	Vector2(221, -166), Vector2(235, -166), Vector2(221, -172), Vector2(235, -172), Vector2(228, -178), Vector2(238, -168), Vector2(217, -160), Vector2(240, -158), Vector2(228, -151.5), Vector2(228, -150)]

var _tms := {}


func _terr_rid() -> RID:
	return (vil.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()


func _th(x: float, z: float) -> float:
	var sp := player.get_world_3d().direct_space_state
	var tr := _terr_rid()
	var rq := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -30.0, z))
	var ex: Array[RID] = []
	for i in 12:
		rq.exclude = ex
		var r := sp.intersect_ray(rq)
		if r.is_empty():
			return NAN
		if (r["rid"] as RID) == tr:
			return float((r["position"] as Vector3).y)
		ex.append(r["rid"])
	return NAN


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	var L: PackedStringArray = []
	var cands: Array = []
	for n in vil.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var p := String(vil.get_path_to(mi))
		if p.begins_with("Districts/") and p.contains("/Buildings/"):
			continue
		var ab := mi.global_transform * mi.get_aabb()
		if ab.position.x > 245 or ab.end.x < 210 or ab.position.z > -145 or ab.end.z < -185:
			continue
		if ab.size.y > 6.0 and ab.size.x < 30.0:
			continue       # 樹・建物
		cands.append(mi)
	L.append("candidates=%d" % cands.size())
	for pt: Vector2 in PTS:
		var th := _th(pt.x, pt.y)
		var hits: Array = []
		for mi: MeshInstance3D in cands:
			var key := mi.get_instance_id()
			if not _tms.has(key):
				_tms[key] = mi.mesh.generate_triangle_mesh()
			var tm: TriangleMesh = _tms[key]
			if tm == null:
				continue
			var inv := mi.global_transform.affine_inverse()
			var o := inv * Vector3(pt.x, 80.0, pt.y)
			var d := (inv.basis * Vector3.DOWN)
			var r: Dictionary = tm.intersect_ray(o, d)
			if r.is_empty():
				continue
			var wp: Vector3 = mi.global_transform * (r["position"] as Vector3)
			hits.append([String(vil.get_path_to(mi)), wp.y - th])
		hits.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
		var row := PackedStringArray()
		for h: Array in hits:
			if absf(float(h[1])) < 3.0:
				row.append("%s %+0.3f" % [String(h[0]).get_slice("/", String(h[0]).get_slice_count("/") - 1) if String(h[0]).length() > 60 else h[0], h[1]])
		L.append("(%.1f,%.1f) terrain=%.3f | %s" % [pt.x, pt.y, th, " ; ".join(row)])
	var f := FileAccess.open(out.path_join("layers_above_terrain.txt"), FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	print("[LAYERS2] done")
	quit(0)
