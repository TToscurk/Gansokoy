extends "res://tools/p13/w6/w6_base.gd"
## [scratch：丘腳社寺 E2 地形細測] 唯讀。Terrain-only ray（Collision/TerrainCollision 的 RID 才算）。
##   godot --headless --path godot --script <this> -- <outdir/> TERR --map=village_v2   （需要 w6_base 的 _boot＝有顯示；地形高度表本身 headless 也可，但沿用 _boot）
const X0 := 196
const X1 := 262
const Z0 := -196
const Z1 := -138


func _terr_rid() -> RID:
	var tc := vil.get_node("Collision/TerrainCollision") as CollisionObject3D
	return tc.get_rid()


func _th(x: float, z: float) -> float:
	var sp := player.get_world_3d().direct_space_state
	var tr := _terr_rid()
	var rq := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -30.0, z))
	rq.collide_with_areas = false
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
	var lines: PackedStringArray = []
	lines.append("x0=%d x1=%d z0=%d z1=%d step=1 (rows z ascending, cols x ascending)" % [X0, X1, Z0, Z1])
	for z in range(Z0, Z1 + 1):
		var row := PackedStringArray()
		for x in range(X0, X1 + 1):
			var h := _th(float(x), float(z))
			row.append("%.2f" % h if not is_nan(h) else "nan")
		lines.append(",".join(row))
	var f := FileAccess.open(out.path_join("terrain_1m.csv"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	# 0.5 m 剖面：x=228 由 z=-152 到 -168
	var prof := PackedStringArray()
	for xx in [214.0, 221.0, 228.0, 235.0, 242.0]:
		var row2 := PackedStringArray()
		var z := -140.0
		while z >= -184.0:
			row2.append("%.2f" % _th(xx, z))
			z -= 0.5
		prof.append("x=%.0f z=-140..-184 step0.5: %s" % [xx, " ".join(row2)])
	var f2 := FileAccess.open(out.path_join("terrain_profiles.txt"), FileAccess.WRITE)
	f2.store_string("\n".join(prof) + "\n")
	f2.close()
	print("[TERR] done")
	quit(0)
