extends SceneTree
## 診断：P8 EarthBanks の材質と地形材質（唯読）。
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _desc(m: Material) -> String:
	if m == null:
		return "null"
	var s := "%s path=%s" % [m.get_class(), m.resource_path.get_file() if m.resource_path != "" else "(embedded)"]
	if m is StandardMaterial3D:
		var sm := m as StandardMaterial3D
		s += " albedo=%s tex=%s vcol=%s rough=%.2f unshaded=%s" % [str(sm.albedo_color), str(sm.albedo_texture != null), str(sm.vertex_color_use_as_albedo), sm.roughness, str(sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)]
	elif m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		s += " shader=%s" % (sh.resource_path.get_file() if sh != null else "null")
		if sh != null:
			for u in sh.get_shader_uniform_list():
				var v = (m as ShaderMaterial).get_shader_parameter(u["name"])
				var vs := str(v)
				if vs.length() > 60:
					vs = vs.substr(0, 60) + "…"
				s += "\n      %s = %s" % [u["name"], vs]
	return s


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await process_frame
	var eb := v.get_node("Districts/FarmlandEast/FarmlandP8/EarthBanks")
	print("[BANKM] EarthBanks children=", eb.get_child_count())
	var seen := {}
	var shown := 0
	for c in eb.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var key := ""
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			key += (mat.resource_path if mat != null and mat.resource_path != "" else str(mat)) + "|"
		var kind := String(mi.name).get_slice("_", 2)
		var k2 := kind.rstrip("0123456789AB")
		if not seen.has(k2 + key):
			seen[k2 + key] = 0
			if shown < 8:
				shown += 1
				print("[BANKM] sample ", mi.name, " kind=", k2, " surf=", mi.mesh.get_surface_count(), " vcolor=", str(mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != null))
				for s in mi.mesh.get_surface_count():
					print("[BANKM]    surf", s, ": ", _desc(mi.get_active_material(s)))
		seen[k2 + key] += 1
	print("[BANKM] distinct (kind+mat) groups=", seen.size())
	var ft := v.get_node("Terrain/FarmlandTerrain") as MeshInstance3D
	print("[BANKM] FarmlandTerrain override: ", _desc(ft.material_override))
	for s in ft.mesh.get_surface_count():
		print("[BANKM] FarmlandTerrain surf", s, ": ", _desc(ft.get_active_material(s)))
	quit(0)
