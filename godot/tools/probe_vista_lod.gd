extends SceneTree
## 量 vista_lod/*_far.glb 的面數與貼圖，確認能不能當 700 棵遠景樹的 MultiMesh 來源。
##   Godot --headless --path godot --script tools/probe_vista_lod.gd

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for p in ["res://assets/models/tree_round_far.glb",
			"res://assets/vista_lod/針葉樹1_far.glb",
			"res://assets/vista_lod/針葉林樹3_far.glb",
			"res://assets/vista_lod/針葉林樹4_far.glb",
			"res://assets/vista_lod/普通樹_far.glb"]:
		var ps: PackedScene = load(p)
		if ps == null:
			print("LOAD_FAIL %s" % p)
			continue
		var inst: Node3D = ps.instantiate()
		root.add_child(inst)
		await process_frame
		var faces := 0
		var surfs := 0
		var acc := AABB()
		var has := false
		var mats: Array = []
		var st: Array = [inst]
		while not st.is_empty():
			var n: Node = st.pop_back()
			st.append_array(n.get_children())
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var m: Mesh = (n as MeshInstance3D).mesh
				faces += m.get_faces().size() / 3
				surfs += m.get_surface_count()
				var b: AABB = (n as MeshInstance3D).global_transform * m.get_aabb()
				acc = acc.merge(b) if has else b
				has = true
				for si in m.get_surface_count():
					var mat: Material = m.surface_get_material(si)
					if mat is BaseMaterial3D:
						var t: Texture2D = (mat as BaseMaterial3D).albedo_texture
						mats.append("%dx%d" % [t.get_width(), t.get_height()] if t else "notex")
		print("VLOD %-40s faces=%6d surfaces=%d size=(%.2f,%.2f,%.2f) min_y=%.3f tex=%s" % [
			p.get_file(), faces, surfs, acc.size.x, acc.size.y, acc.size.z, acc.position.y, mats])
		inst.queue_free()
		await process_frame
	quit(0)
