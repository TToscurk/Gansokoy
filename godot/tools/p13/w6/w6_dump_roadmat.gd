extends SceneTree
## P13 Wave 6 診断（唯読）：GroundPilotP10 / RoadBaseP10 の設定値と、全 Roads ノードの現在の material_override（実行時、_ready 後）を出す。
##   godot --headless --path . --script res://tools/p13/w6/w6_dump_roadmat.gd
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 12:
		await process_frame
	var gp := v.get_node_or_null("GroundPilotP10")
	if gp != null:
		print("[DUMP] GroundPilotP10.enabled=", gp.get("enabled"), " applied=", gp.get("applied"), " farm_soil=", gp.get("farm_soil"))
		var tp: PackedStringArray = gp.get("terrain_paths")
		print("[DUMP]  terrain_paths=", tp)
		var rp: PackedStringArray = gp.get("road_paths")
		var rpar: Array = gp.get("road_params")
		for i in rp.size():
			print("[DUMP]  road_path ", rp[i], " params=", rpar[i] if i < rpar.size() else {})
	for on in ["DrapeFixP13", "RoadEdgeBlendP13"]:
		var w6 := v.get_node_or_null(on)
		print("[DUMP] ", on, " present=", w6 != null, (" enabled=" + str(w6.get("enabled")) + " applied=" + str(w6.get("applied"))) if w6 != null else "")
	var rb := v.get_node_or_null("RoadBaseP10")
	if rb != null:
		print("[DUMP] RoadBaseP10.enabled=", rb.get("enabled"), " applied=", rb.get("applied"), " paths=", rb.get("road_paths"))
	for mi in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var path := String(v.get_path_to(m))
		if path.begins_with("Roads/Bridges"):
			continue
		var mat := m.material_override
		var desc := "null"
		if mat is ShaderMaterial:
			var sm := mat as ShaderMaterial
			desc = "Shader(%s)" % sm.shader.resource_path.get_file()
			var ps := ["mode", "edge_w", "edge_irreg", "edge_core", "shoulder_start", "edge_gravel", "center_grass", "wear_center", "rut_strength", "center_patch"]
			var kv := []
			for p: String in ps:
				var val = sm.get_shader_parameter(p)
				if val != null:
					kv.append("%s=%s" % [p, str(val)])
			desc += " " + " ".join(kv)
		elif mat != null:
			desc = mat.get_class()
		var ts := 0
		if m.mesh != null:
			for s in m.mesh.get_surface_count():
				ts += (m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		print("[DUMP] ", path, " verts=", ts, " ", desc)
	quit(0)
