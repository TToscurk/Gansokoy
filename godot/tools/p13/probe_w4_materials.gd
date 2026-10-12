extends SceneTree
## P13 Wave 4：材質と掛載順の唯讀調査（headless）。
##   godot --headless --path . --script res://tools/p13/probe_w4_materials.gd
func _init() -> void:
	_run.call_deferred()


func _mat_info(m: Material) -> String:
	if m == null:
		return "(null)"
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		var out := "ShaderMaterial shader=%s" % sm.shader.resource_path
		for p in sm.shader.get_shader_uniform_list():
			var nm := String(p["name"])
			var v: Variant = sm.get_shader_parameter(nm)
			if v is Texture:
				out += "\n      %s = %s" % [nm, (v as Resource).resource_path if (v as Resource).resource_path != "" else str(v)]
			elif v != null:
				out += "\n      %s = %s" % [nm, str(v)]
		return out
	if m is StandardMaterial3D:
		var s := m as StandardMaterial3D
		return "StandardMaterial3D albedo_color=%s vertex_color_use_as_albedo=%s albedo_tex=%s rough=%s metallic=%s uv1_scale=%s tri=%s" % [str(s.albedo_color), str(s.vertex_color_use_as_albedo), s.albedo_texture.resource_path if s.albedo_texture else "-", str(s.roughness), str(s.metallic), str(s.uv1_scale), str(s.uv1_triplanar)]
	return str(m)


func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	print("[W4M] village_v2 の直下の子（掛載順）：")
	var i := 0
	for c in v.get_children():
		print("[W4M]   %02d %s (%s)" % [i, c.name, c.get_class()])
		i += 1
	var mt := v.get_node_or_null("Terrain/MainTerrain") as MeshInstance3D
	if mt:
		print("[W4M] Terrain/MainTerrain material_override: ", _mat_info(mt.material_override))
		if mt.mesh:
			for s in mt.mesh.get_surface_count():
				print("[W4M]   surface %d material: %s" % [s, _mat_info(mt.mesh.surface_get_material(s))])
	var rb := v.get_node_or_null("Roads/SecondaryRoads/HillApproach") as MeshInstance3D
	if rb:
		print("[W4M] HillApproach material_override: ", _mat_info(rb.material_override))
	var ss := v.get_node_or_null("ShrineApproachP10/StoneSteps") as MeshInstance3D
	if ss:
		print("[W4M] StoneSteps material_override: ", _mat_info(ss.material_override))
	quit(0)
