extends SceneTree
## P13 W7 診断（唯読・headless）：LANDMARK_HILLFOOT_TEMPLE（丘腳社寺・P4 灰盒）の現況を数値で出す。
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await process_frame
	var lm := v.get_node("Landmarks/LANDMARK_HILLFOOT_TEMPLE")
	print("[W7T] pos=", lm.global_position, " children=", lm.get_child_count(), " meta=", lm.get_meta_list())
	for mi in lm.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var tris := 0
		var mats := []
		for si in m.mesh.get_surface_count():
			var a := m.mesh.surface_get_arrays(si)
			tris += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var mt := m.get_surface_override_material(si)
			if mt == null:
				mt = m.mesh.surface_get_material(si)
			mats.append(mt.resource_path.get_file() if mt != null and mt.resource_path != "" else (str(mt.get_class()) if mt != null else "null"))
		print("[W7T] mesh ", m.name, " size=", m.get_aabb().size.snapped(Vector3(0.01, 0.01, 0.01)), " tris=", tris, " surfaces=", m.mesh.get_surface_count(), " materials=", mats, " range=[", m.visibility_range_begin, ",", m.visibility_range_end, "] yaw=", snappedf(rad_to_deg(m.global_rotation.y), 0.1))
	quit(0)
