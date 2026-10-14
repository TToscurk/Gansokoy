extends SceneTree
## P13 W7 診断（唯読・headless）：町家の LOD1／LOD2 屋根部品（l_rh_*）が実際にどの材質で描かれているかを、群（Pilot／batch／主街／未校正）ごとに数える。
##   godot --headless --path . --script res://tools/p13/w7/w7_probe_roofs.gd
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await process_frame
	var reg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/kit_cal_p10/kit_material_variants.json"))
	var pilot := {}
	for p in reg["pilot_buildings"]:
		pilot[String(p)] = true
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p13w7_batch1.json"))
	var batch := {}
	for b: Dictionary in man["buildings"]:
		batch[String(b["path"])] = true
	var ms: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p13_mainstreet.json"))
	var main := {}
	for b: Dictionary in ms["buildings"]:
		main[String(b["id"])] = true
	var res := {}
	for b in v.get_node("Districts").find_children("B_*", "Node3D", true, false):
		var kit := b.get_node_or_null("Kit")
		if kit == null:
			continue
		var bp := String(v.get_path_to(b))
		var g := "pilot" if pilot.has(bp) else ("batch" if batch.has(bp) else ("main" if main.has(String(b.name)) else "rest"))
		for li in [1, 2]:
			var ln := kit.get_node_or_null("LOD%d" % li)
			if ln == null:
				continue
			for mi in ln.find_children("l_rh_*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				for si in m.mesh.get_surface_count():
					var base := m.mesh.surface_get_material(si)
					var ov := m.get_surface_override_material(si)
					var key := "%s LOD%d l_rh_*  base=%s  override=%s" % [g, li, base.resource_path.get_file() if base else "null", ov.resource_path.get_file() if ov else "なし"]
					res[key] = int(res.get(key, 0)) + 1
	var keys := res.keys()
	keys.sort()
	for k in keys:
		print("[W7R2] ", k, " ×", res[k])
	quit(0)
