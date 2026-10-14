extends SceneTree
## P13 Wave 6 診断（唯読・headless）：P8 EarthBanks の各メッシュ — AABB、三角形数、垂直面比率、地形との高低差。
##   godot --headless --path . --script res://tools/p13/w6/w6_audit_banks.gd -- [out.json]
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var terr_rid := (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var rows := []
	var banks := v.get_node_or_null("Districts/FarmlandEast/FarmlandP8/EarthBanks")
	print("[BNK] banks node: ", banks != null, " children=", banks.get_child_count() if banks else 0)
	for mi in banks.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := m.global_transform
		var tris := 0
		var vert := 0
		var area_tot := 0.0
		var area_vert := 0.0
		var ymin := INF
		var ymax := -INF
		var below := 0
		var n_s := 0
		var worst_above := -INF
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix = arr[Mesh.ARRAY_INDEX]
			var tri: PackedInt32Array
			if ix != null and (ix as PackedInt32Array).size() > 0:
				tri = ix
			else:
				tri = PackedInt32Array()
				tri.resize(vs.size())
				for k in vs.size():
					tri[k] = k
			for t in range(0, tri.size(), 3):
				var a := xf * vs[tri[t]]
				var b := xf * vs[tri[t + 1]]
				var c := xf * vs[tri[t + 2]]
				var n := (b - a).cross(c - a)
				var ar := n.length() * 0.5
				tris += 1
				area_tot += ar
				if ar > 1e-9 and absf(n.normalized().y) < 0.35:
					vert += 1
					area_vert += ar
				for p in [a, b, c, (a + b + c) / 3.0]:
					ymin = minf(ymin, p.y)
					ymax = maxf(ymax, p.y)
					if n_s % 3 == 0:
						var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 6.0, p.z), Vector3(p.x, p.y - 20.0, p.z))
						var ex: Array[RID] = []
						for u in 6:
							q.exclude = ex
							var h := sp.intersect_ray(q)
							if h.is_empty():
								break
							if h.rid == terr_rid:
								var d: float = p.y - float(h.position.y)
								worst_above = maxf(worst_above, d)
								if d < -0.02:
									below += 1
								break
							ex.append(h.rid)
					n_s += 1
		var ab := xf * m.get_aabb()
		rows.append({"name": String(m.name), "tris": tris, "vert_tris": vert, "area": snappedf(area_tot, 0.01), "area_vert": snappedf(area_vert, 0.01), "aabb_pos": [snappedf(ab.position.x, 0.1), snappedf(ab.position.y, 0.1), snappedf(ab.position.z, 0.1)], "aabb_size": [snappedf(ab.size.x, 0.1), snappedf(ab.size.y, 0.1), snappedf(ab.size.z, 0.1)], "y": [snappedf(ymin, 0.01), snappedf(ymax, 0.01)], "above_terrain_max": snappedf(worst_above, 0.01) if worst_above > -INF else null, "below_terrain_samples": below})
	rows.sort_custom(func(a, b): return a["area"] > b["area"])
	for r in rows.slice(0, 14):
		print("[BNK] ", r)
	print("[BNK] total meshes ", rows.size())
	var out_path := ""
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			out_path = a
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(rows, "\t") + "\n")
		f.close()
	quit(0)
