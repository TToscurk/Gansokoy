extends "res://tools/p13/w6/w6_base.gd"
## [scratch：丘腳社寺 E2 抑制對象勘查] 唯讀。需要有顯示（MultiMesh 實例矩陣 headless 全是 0）。
##   godot --path godot --script <this> -- <outdir/> SUPP --map=village_v2
## 輸出 suppress_survey.txt：E082 子樹結構・碰撞、境內候選多邊形內各 MultiMesh 的實例數・各層個別節點。
const COURT := [Vector2(219.0, -178.0), Vector2(219.0, -160.5), Vector2(222.5, -158.2), Vector2(228.0, -157.6), Vector2(233.5, -158.2), Vector2(237.5, -160.5), Vector2(237.5, -178.0)]
const APPROACH := [Vector2(224.5, -152.0), Vector2(231.5, -152.0), Vector2(231.5, -158.5), Vector2(224.5, -158.5)]


func _in(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, PackedVector2Array(COURT)) or Geometry2D.is_point_in_polygon(p, PackedVector2Array(APPROACH))


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	var L: PackedStringArray = []
	var e82 := vil.get_node("Props/EnvironmentP9/edge/E082_fence_frag") as Node3D
	L.append("## E082_fence_frag children")
	for ch in e82.get_children():
		var n3 := ch as Node3D
		var cs: PackedStringArray = []
		for gc in ch.get_children():
			cs.append("%s:%s" % [gc.name, gc.get_class()])
		L.append("%s | %s | pos=(%.2f,%.2f,%.2f) | meta=%s | children=%s" % [ch.name, ch.get_class(), n3.global_position.x, n3.global_position.y, n3.global_position.z, str(ch.get_meta_list()), ",".join(cs)])
	L.append("## EnvironmentP9 top-level children")
	var env := vil.get_node("Props/EnvironmentP9")
	for ch in env.get_children():
		L.append("%s | %s | n=%d" % [ch.name, ch.get_class(), ch.get_child_count()])
	var col := env.get_node_or_null("Collision")
	if col != null:
		L.append("## EnvironmentP9/Collision shapes near E082 (within 14 m of (224,-162))")
		for sh in col.get_children():
			var s3 := sh as Node3D
			if s3 != null and Vector2(s3.global_position.x, s3.global_position.z).distance_to(Vector2(224, -162)) < 14.0:
				var cs2 := sh as CollisionShape3D
				L.append("%s | pos=(%.2f,%.2f,%.2f) | %s | disabled=%s" % [sh.name, s3.global_position.x, s3.global_position.y, s3.global_position.z, cs2.shape.get_class() if cs2 and cs2.shape else "?", cs2.disabled if cs2 else "?"])
	else:
		L.append("(no EnvironmentP9/Collision; searching CollisionObject3D under EnvironmentP9)")
		for co in env.find_children("*", "CollisionObject3D", true, false):
			L.append("  %s" % vil.get_path_to(co))
	L.append("## MultiMesh instances inside COURT∪APPROACH (origin xz)")
	var tot := 0
	for mmi in vil.find_children("*", "MultiMeshInstance3D", true, false):
		var m := mmi as MultiMeshInstance3D
		var mm := m.multimesh
		if mm == null or mm.instance_count == 0:
			continue
		var ab := m.global_transform * m.get_aabb()
		if ab.position.x > 240 or ab.end.x < 216 or ab.position.z > -150 or ab.end.z < -180:
			continue
		var n_in := 0
		var n_near := 0
		for i in mm.instance_count:
			var t := m.global_transform * mm.get_instance_transform(i)
			var p := Vector2(t.origin.x, t.origin.z)
			if _in(p):
				n_in += 1
			if p.x > 216 and p.x < 240 and p.y > -180 and p.y < -150:
				n_near += 1
		if n_near > 0:
			L.append("%s | total=%d | in_polys=%d | in_box(216..240,-180..-150)=%d | stride_floats=%d | mesh=%s" % [vil.get_path_to(m), mm.instance_count, n_in, n_near,
				mm.buffer.size() / mm.instance_count if mm.instance_count > 0 else 0, mm.mesh.resource_path.get_file() if mm.mesh else "null"])
			tot += n_in
	L.append("## total MultiMesh instances inside polys = %d" % tot)
	L.append("## individual MeshInstance nodes (LOD0, origin inside polys) not under EnvironmentP9")
	for mi in vil.find_children("LOD0", "MeshInstance3D", true, false):
		var p3 := (mi.get_parent() as Node3D).global_position
		if _in(Vector2(p3.x, p3.z)):
			L.append("%s | pos=(%.2f,%.2f,%.2f)" % [vil.get_path_to(mi.get_parent()), p3.x, p3.y, p3.z])
	var f := FileAccess.open(out.path_join("suppress_survey.txt"), FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	print("[SUPP] done")
	quit(0)
