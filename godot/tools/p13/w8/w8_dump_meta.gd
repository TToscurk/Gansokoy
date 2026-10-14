extends SceneTree
## P13 W8 TASK D：全町家 Kit 建物の meta（type／road／roof／kit_asset／district／pos）を JSON に出す（唯読・headless）。
##   godot --headless --path . --script res://tools/p13/w8/w8_dump_meta.gd -- <out.json>
func _init() -> void:
	_r.call_deferred()


func _r() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await process_frame
	var rows := {}
	for n in v.get_node("Districts").find_children("B_*", "Node3D", true, false):
		if n.get_node_or_null("Kit") == null:
			continue
		var d := {"path": String(v.get_path_to(n)), "district": String(v.get_path_to(n)).split("/")[1], "pos": [snappedf(n.global_position.x, 0.1), snappedf(n.global_position.z, 0.1)]}
		for key in ["type", "type_label", "road", "roof", "kit_asset", "use", "width", "depth", "fin", "tone"]:
			if n.has_meta(key):
				var val = n.get_meta(key)
				d[key] = val if (val is String or val is int or val is float) else str(val)
		rows[String(n.name)] = d
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(rows, "\t") + "\n")
	f.close()
	print("[META] ", rows.size())
	quit(0)
