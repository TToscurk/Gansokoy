extends SceneTree
## P10 R3d 下調べ（読み取り専用）：封存 overlay の NPC activity anchors・Hero の位置・R3b の住人を一覧する。
## godot --headless --path godot --script res://tools/survey_village_v2_population_core.gd -- [--out=<json>]
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

func _initialize():
	go.call_deferred()

func go():
	var outp := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): outp = a.trim_prefix("--out=")
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	var out := {"anchors": {}, "heroes": {}, "population": [], "population_children": []}
	for top in ["Props", "Vegetation"]:
		var g := v.get_node_or_null(top)
		if g == null: continue
		for ov in g.get_children():
			var n := 0
			for mk in ov.find_children("*", "Marker3D", true, false):
				var xf := RLib.rel_xf(mk as Node3D, v)
				out.anchors[String(ov.name) + "/" + String(mk.name)] = [snappedf(xf.origin.x, 0.01), snappedf(xf.origin.y, 0.01), snappedf(xf.origin.z, 0.01),
					snappedf(rad_to_deg(xf.basis.get_euler().y), 0.1), String(mk.get_meta("activity", "")), String(mk.get_meta("ref", ""))]
				n += 1
			print("[SURVEY] overlay %s/%s markers %d" % [top, ov.name, n])
	for n in v.find_children("*", "", true, false):
		var sp := String(n.scene_file_path)
		if sp.begins_with("res://assets/village_v2/") and sp.ends_with(".scn") and n is Node3D:
			var p := RLib.rel_xf(n as Node3D, v).origin
			out.heroes[sp.get_file().get_basename() + ":" + String(n.name)] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)]
	var pop := v.get_node_or_null("Population")
	if pop:
		for c in pop.get_children(): out.population_children.append(String(c.name))
		for b in pop.find_children("*", "AnimatableBody3D", true, false):
			var p := RLib.rel_xf(b as Node3D, v).origin
			out.population.append([String(b.name), String(b.get_meta("zone", "")), snappedf(p.x, 0.1), snappedf(p.z, 0.1), String(b.get("mode"))])
	print("[SURVEY] anchors %d heroes %d population %d children %s" % [out.anchors.size(), out.heroes.size(), out.population.size(), str(out.population_children)])
	if outp != "": FileAccess.open(outp, FileAccess.WRITE).store_string(JSON.stringify(out, " "))
	quit(0)
