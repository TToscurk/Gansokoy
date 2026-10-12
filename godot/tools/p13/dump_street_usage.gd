extends SceneTree
## P13 W2（只讀・headless）：StreetP10 烘焙物件の building→用途タグ（st_tag）一覧を JSON へ。
##   godot --headless --path . --script res://tools/p13/dump_street_usage.gd -- <out.json>
func _init() -> void:
	var s := (load("res://maps/village_v2/gen/street_p10.scn") as PackedScene).instantiate()
	var by := {}
	for n in s.find_children("*", "Node3D", true, false):
		if n.has_meta("building"):
			var b := String(n.get_meta("building"))
			if not by.has(b):
				by[b] = []
			(by[b] as Array).append({"node": String(s.get_path_to(n)), "id": String(n.get_meta("st_id")), "tag": String(n.get_meta("st_tag")),
				"p": [snappedf((n as Node3D).position.x, 0.001), snappedf((n as Node3D).position.y, 0.001), snappedf((n as Node3D).position.z, 0.001)]})
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(by, " "))
	f.close()
	print("[USAGE] buildings ", by.size())
	s.free()
	quit(0)
