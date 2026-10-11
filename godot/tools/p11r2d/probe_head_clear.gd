extends SceneTree
## P11 R2D：T0 頭部（s 0–4 m）近くの柳 004_yanagi_b LOD0 頂点（高さ 1.2 m 以下）と支線中心線の最小距離、FarmPath_5 西端と T0 堤外縁の距離。
const ZL := preload("res://tools/village_v2_farmland_zone.gd")
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	var pts: Array = ZL.BRANCHES["T0"]["pts"]
	var pl := PackedVector2Array()
	for a in pts:
		pl.append(Vector2(a[0], a[1]))
	var mi := v.get_node("Vegetation/WatersideP9/Trees/004_yanagi_b/LOD0") as MeshInstance3D
	var best := INF
	var at := Vector3()
	for s in mi.mesh.get_surface_count():
		for q: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			var w := mi.global_transform * q
			if w.y > ZL.ground_h(Vector2(w.x, w.z)) + 1.2:
				continue
			for k in pl.size() - 1:
				var d := Geometry2D.get_closest_point_to_segment(Vector2(w.x, w.z), pl[k], pl[k + 1]).distance_to(Vector2(w.x, w.z))
				if d < best:
					best = d
					at = w
	print("[HEAD] 柳 004 幹（地面+1.2 m 以下）〜T0 中心線 最小 %.2f m @%s（木槽半幅 0.21＋側板）" % [best, at.snappedf(0.01)])
	var e := INF
	for k in pl.size() - 1:
		e = minf(e, Geometry2D.get_closest_point_to_segment(Vector2(330.0, 70.0), pl[k], pl[k + 1]).distance_to(Vector2(330.0, 70.0)))
	print("[HEAD] FarmPath_5 西端 (330,70) 〜T0 中心線 %.2f m（堤外縁 %.2f m）" % [e, ZL.BR_HALF])
	quit(0)
