extends SceneTree
## P13 W7 診断（唯読・headless）：Terrain 直下の MeshInstance3D 一覧（world AABB・頂点数・材質 shader・窓内の頂点数）と、
## 窓内の頂点の COLOR.r を全 mesh 分 JSON に出す。
##   godot --headless --path . --script res://tools/p13/w7/w7_probe_terrain_all.gd -- <out.json> <cx> <cz> <half>
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out_path := String(a[0])
	var cx := float(a[1])
	var cz := float(a[2])
	var half := float(a[3])
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await process_frame
	var res := {}
	for mi in v.get_node("Terrain").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var aabb := m.global_transform * m.mesh.get_aabb()
		var nm := String(v.get_path_to(m))
		var sh := ""
		var mat := m.material_override if m.material_override != null else m.get_active_material(0)
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
			sh = (mat as ShaderMaterial).shader.resource_path.get_file()
		var rows := []
		var nwin := 0
		if m.mesh is ArrayMesh and m.mesh.get_surface_count() > 0:
			var arr := (m.mesh as ArrayMesh).surface_get_arrays(0)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cs = arr[Mesh.ARRAY_COLOR]
			var xf := m.global_transform
			for i in vs.size():
				var w := xf * vs[i]
				if absf(w.x - cx) <= half and absf(w.z - cz) <= half:
					nwin += 1
					if cs != null:
						var c: Color = (cs as PackedColorArray)[i]
						rows.append([snappedf(w.x, 0.001), snappedf(w.y, 0.001), snappedf(w.z, 0.001), snappedf(c.r, 0.0001), snappedf(c.g, 0.0001), snappedf(c.b, 0.0001), snappedf(c.a, 0.0001)])
		res[nm] = {"aabb": [aabb.position.x, aabb.position.z, aabb.end.x, aabb.end.z], "shader": sh, "verts_in_window": nwin, "rows": rows, "visible": m.is_visible_in_tree(), "layers": m.layers}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(res))
	f.close()
	for k in res:
		print("[W7T] ", k, " aabb=", res[k]["aabb"], " sh=", res[k]["shader"], " win=", res[k]["verts_in_window"], " vis=", res[k]["visible"])
	quit(0)
