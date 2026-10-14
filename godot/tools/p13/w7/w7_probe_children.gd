extends SceneTree
## P13 W7 診断（唯読・headless）：第一批 1 棟の直下の子ごとに、MeshInstance3D 数・表面数・override 数を出す（Kit 以外の子に何があるかを確かめる）。
##   godot --headless --path . --script res://tools/p13/w7/w7_probe_children.gd -- B_P_MKT_032
const SCENE := "res://maps/village_v2/village_v2.tscn"
const MAN := "res://data/village_v2_p13w7_batch1.json"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await process_frame
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAN))
	var agg := {}
	for b: Dictionary in man["buildings"]:
		var n := v.get_node(NodePath(String(b["path"])))
		for c in n.get_children():
			var mis := c.find_children("*", "MeshInstance3D", true, false)
			if c is MeshInstance3D:
				mis.append(c)
			var surf := 0
			var ov := 0
			for mi in mis:
				var m := mi as MeshInstance3D
				if m.mesh == null:
					continue
				for si in m.mesh.get_surface_count():
					surf += 1
					if m.get_surface_override_material(si) != null:
						ov += 1
			var a: Array = agg.get(String(c.name), [0, 0, 0, 0])
			a[0] += 1
			a[1] += mis.size()
			a[2] += surf
			a[3] += ov
			agg[String(c.name)] = a
	for k in agg:
		print("[W7K] 子 ", k, " ×", agg[k][0], " 棟  MeshInstance3D ", agg[k][1], "  面 ", agg[k][2], "  override ", agg[k][3])
	# Kit 以外の子の代表例
	var n0 := v.get_node(NodePath(String(man["buildings"][0]["path"])))
	for c in n0.get_children():
		if String(c.name) == "Kit":
			continue
		var names := []
		for mi in c.find_children("*", "MeshInstance3D", true, false).slice(0, 6):
			names.append(String(mi.name))
		print("[W7K] ", n0.name, "/", c.name, "  例 ", names)
	quit(0)
