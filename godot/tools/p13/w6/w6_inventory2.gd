extends SceneTree
## P13 Wave 6 TASK D 診断 2（唯読・headless）：各 B_P_* 建物の子構成・Kit 材質・可視性・位置を JSON へ。
##   godot --headless --path . --script res://tools/p13/w6/w6_inventory2.gd -- <out.json>
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _mats_of(n: Node, acc: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m: Material = mi.material_override if mi.material_override != null else mi.mesh.surface_get_material(s)
				var key := "null"
				if m != null:
					key = m.resource_path if m.resource_path != "" else (m.resource_name if m.resource_name != "" else m.get_class())
				acc[key] = int(acc.get(key, 0)) + 1
	for c in n.get_children():
		_mats_of(c, acc)


func _tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var ix = arr[Mesh.ARRAY_INDEX]
				t += ((ix as PackedInt32Array).size() if ix != null and (ix as PackedInt32Array).size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	for c in n.get_children():
		t += _tris(c)
	return t


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await process_frame
	var out := {"buildings": []}
	for dn in ["Market", "MixedCommercial", "ResidentialWest", "ResidentialNE", "SouthGate"]:
		var b := v.get_node_or_null("Districts/%s/Buildings" % dn)
		if b == null:
			continue
		for bn in b.get_children():
			var rec := {"district": dn, "name": String(bn.name), "pos": [], "children": {}, "visible": (bn as Node3D).visible if bn is Node3D else true}
			var p := (bn as Node3D).global_position
			rec["pos"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
			rec["yaw"] = snappedf((bn as Node3D).global_rotation.y, 0.001)
			for ch in bn.get_children():
				var acc := {}
				_mats_of(ch, acc)
				rec["children"][String(ch.name)] = {"cls": ch.get_class(), "vis": (ch as Node3D).visible if ch is Node3D else true, "tris": _tris(ch), "n_child": ch.get_child_count(), "mats": acc}
			if bn.has_meta("kind"):
				rec["meta_kind"] = str(bn.get_meta("kind"))
			rec["meta"] = Array(bn.get_meta_list())
			(out["buildings"] as Array).append(rec)
	var out_path := ""
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			out_path = a
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t") + "\n")
	f.close()
	print("[INV2] buildings=", (out["buildings"] as Array).size())
	quit(0)
