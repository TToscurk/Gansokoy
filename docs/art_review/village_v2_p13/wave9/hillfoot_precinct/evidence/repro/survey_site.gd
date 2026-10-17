extends "res://tools/p13/w6/w6_base.gd"
## [scratch：丘腳社寺 E2 現況勘查] 唯讀・場景檔不寫。
##   godot --path godot --script <this> -- <outdir/> SURVEY --map=village_v2
## 印出：地形高度格、半徑內的節點（AABB・可見・碰撞層）、半徑內的 MultiMesh 實例數（依節點）。
const C := Vector2(228.0, -170.0)
const R := 46.0


func _aabb_world(vi: VisualInstance3D) -> AABB:
	return vi.global_transform * vi.get_aabb()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	var lines: PackedStringArray = []
	# ── A 地形高度格 ──
	lines.append("## HEIGHT GRID (x across, z down); '.'=no hit")
	var xs := range(196, 262, 4)
	lines.append("z\\x " + " ".join(PackedStringArray(xs.map(func(v): return str(v)))))
	for z in range(-206, -128, 4):
		var row := "%4d" % z
		for x in xs:
			var g := _ground(Vector2(x, z))
			row += " %5.2f" % g if not is_nan(g) else "   .  "
		lines.append(row)
	# ── B 節點 ──
	lines.append("## NODES near site (VisualInstance3D, AABB intersects circle R=%.0f)" % R)
	var cnt := 0
	for n in vil.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		var ab := _aabb_world(vi)
		if ab.size.x > 120.0 or ab.size.z > 120.0:
			continue
		var cx := clampf(C.x, ab.position.x, ab.end.x)
		var cz := clampf(C.y, ab.position.z, ab.end.z)
		if Vector2(cx, cz).distance_to(C) > R:
			continue
		var cls := vi.get_class()
		var extra := ""
		if vi is MultiMeshInstance3D:
			extra = " MM inst=%d" % (vi as MultiMeshInstance3D).multimesh.instance_count
		lines.append("%s | %s | vis=%s tree=%s | pos=(%.1f,%.1f,%.1f) | aabb pos=(%.1f,%.1f,%.1f) size=(%.1f,%.1f,%.1f)%s" % [
			String(vil.get_path_to(vi)), cls, vi.visible, vi.is_visible_in_tree(), vi.global_position.x, vi.global_position.y, vi.global_position.z,
			ab.position.x, ab.position.y, ab.position.z, ab.size.x, ab.size.y, ab.size.z, extra])
		cnt += 1
	lines.append("## total %d" % cnt)
	# ── C 碰撞體 ──
	lines.append("## COLLISION near site")
	for n in vil.find_children("*", "CollisionObject3D", true, false):
		var co := n as CollisionObject3D
		if Vector2(co.global_position.x, co.global_position.z).distance_to(C) > R + 30.0:
			continue
		var shp: PackedStringArray = []
		for ch in co.get_children():
			if ch is CollisionShape3D:
				var cs := ch as CollisionShape3D
				shp.append("%s%s" % [cs.shape.get_class() if cs.shape else "null", "(off)" if cs.disabled else ""])
		lines.append("%s | %s | layer=%d mask=%d | pos=(%.1f,%.1f,%.1f) | %s" % [String(vil.get_path_to(co)), co.get_class(), co.collision_layer, co.collision_mask,
			co.global_position.x, co.global_position.y, co.global_position.z, ",".join(shp)])
	# ── D MultiMesh 在半徑內的實例數 ──
	lines.append("## MULTIMESH instances within R of site (origin distance)")
	for n in vil.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null or mm.instance_count == 0:
			continue
		var ab := _aabb_world(mmi)
		var cx := clampf(C.x, ab.position.x, ab.end.x)
		var cz := clampf(C.y, ab.position.z, ab.end.z)
		if Vector2(cx, cz).distance_to(C) > R + 20.0:
			continue
		var inside := 0
		var inside15 := 0
		for i in mm.instance_count:
			var t := mmi.global_transform * mm.get_instance_transform(i)
			var d := Vector2(t.origin.x, t.origin.z).distance_to(C)
			if d <= R:
				inside += 1
			if d <= 15.0:
				inside15 += 1
		lines.append("%s | inst=%d | within46=%d within15=%d | mesh=%s" % [String(vil.get_path_to(mmi)), mm.instance_count, inside, inside15,
			mm.mesh.resource_path if mm.mesh else "null"])
	var f := FileAccess.open(out.path_join("survey_site.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("[SURVEY] done lines=%d" % lines.size())
	quit(0)
