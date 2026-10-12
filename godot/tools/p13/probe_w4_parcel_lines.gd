extends SceneTree
## P13 Wave 4：Districts/LandmarkParcelLines（MeshInstance3D 1 個）の材質と、参道の頂付近にある部分の形（洋紅帯の正体）を調べる（唯讀、headless）。
##   godot --headless --path . --script res://tools/p13/probe_w4_parcel_lines.gd
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	var top := Vector2(259.0, -220.2)   # 参道の頂（s≈100）
	for pth in ["Districts/LandmarkParcelLines", "Districts/AuxParcelLines"]:
		var mi := v.get_node_or_null(pth) as MeshInstance3D
		if mi == null:
			print("[W4P] %s なし" % pth)
			continue
		var m := mi.material_override
		var minfo := "-"
		if m is StandardMaterial3D:
			var s := m as StandardMaterial3D
			minfo = "StandardMaterial3D albedo=%s unshaded=%s vertex_color_use_as_albedo=%s emission=%s cast_shadow=%d" % [str(s.albedo_color), str(s.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED), str(s.vertex_color_use_as_albedo), str(s.emission_enabled), mi.cast_shadow]
		print("[W4P] %s：visible=%s mesh=%s surfaces=%d  %s" % [pth, str(mi.visible), mi.mesh.resource_path, mi.mesh.get_surface_count(), minfo])
		var ab: AABB = mi.global_transform * mi.get_aabb()
		print("[W4P]   全体 AABB 中心(%.0f, %.0f, %.0f) サイズ(%.0f, %.0f, %.0f)" % [ab.get_center().x, ab.get_center().y, ab.get_center().z, ab.size.x, ab.size.y, ab.size.z])
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cols = arr[Mesh.ARRAY_COLOR]
			var lo := Vector3(INF, INF, INF)
			var hi := Vector3(-INF, -INF, -INF)
			var n := 0
			for i in vs.size():
				var w := mi.global_transform * vs[i]
				if Vector2(w.x, w.z).distance_to(top) < 28.0:
					n += 1
					lo = Vector3(minf(lo.x, w.x), minf(lo.y, w.y), minf(lo.z, w.z))
					hi = Vector3(maxf(hi.x, w.x), maxf(hi.y, w.y), maxf(hi.z, w.z))
			print("[W4P]   surface %d：頂点 %d、参道の頂から 28 m 以内の頂点 %d" % [s, vs.size(), n])
			if n > 0:
				print("[W4P]     その範囲 x %.1f–%.1f  y %.2f–%.2f  z %.1f–%.1f" % [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])
				if cols != null and (cols as PackedColorArray).size() > 0:
					print("[W4P]     頂点色の例：", str((cols as PackedColorArray)[0]))
	quit(0)
