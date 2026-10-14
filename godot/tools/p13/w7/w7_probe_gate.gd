extends "res://tools/p13/w6/w6_base.gd"
## P13 W7 診断（唯読）：正式経路（main→ReviewStart→village_v2）で南大門鳥居の状態を実機で読む。
##   godot --path . --script res://tools/p13/w7/w7_probe_gate.gd
## 鳥居の各 LOD の visible／visibility_range／transform／mesh AABB・面数と、f_001 の TPS 位置に置いた時のカメラ・距離を印刷する。


func _dump(n: Node, ind: String) -> void:
	var s := ind + n.name + " [" + n.get_class() + "]"
	if n is Node3D:
		s += " vis=" + str((n as Node3D).visible) + " intree=" + str((n as Node3D).is_visible_in_tree()) + " pos=" + str((n as Node3D).global_position.snapped(Vector3(0.01, 0.01, 0.01)))
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		s += " range=[" + str(g.visibility_range_begin) + "," + str(g.visibility_range_end) + "] fade=" + str(g.visibility_range_fade_mode)
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var mi := g as MeshInstance3D
			var tris := 0
			for si in mi.mesh.get_surface_count():
				var a := mi.mesh.surface_get_arrays(si)
				tris += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			s += " tris=" + str(tris) + " aabb=" + str(mi.get_aabb().size.snapped(Vector3(0.01, 0.01, 0.01)))
	print("[W7G2] ", s)
	for c in n.get_children():
		_dump(c, ind + "  ")


func _run() -> void:
	await _boot()
	var dn := root.get_node_or_null("/root/DayNight")
	if dn:
		dn.flowing = false
		dn.set_hour(10.0)
	var gate := vil.get_node("Landmarks/LANDMARK_SOUTH_GATE")
	print("[W7G2] ---- LANDMARK_SOUTH_GATE（正式経路・boot 直後）")
	_dump(gate, "")
	await _tpw(Vector2(226.414, 152.692), Vector2(0.124, -0.992))
	for i in 20:
		await process_frame
	var cam := root.get_viewport().get_camera_3d()
	print("[W7G2] camera pos=", cam.global_position.snapped(Vector3(0.01, 0.01, 0.01)), " fwd=", (-cam.global_transform.basis.z).snapped(Vector3(0.001, 0.001, 0.001)), " far=", cam.far, " near=", cam.near, " fov=", cam.fov, " cull_mask=", cam.cull_mask)
	var d := cam.global_position.distance_to(gate.global_position)
	print("[W7G2] camera→gate 距離 ", snappedf(d, 0.1), " m")
	print("[W7G2] ---- 同（TPS を f_001 に置いた後）")
	_dump(gate, "")
	quit(0)
