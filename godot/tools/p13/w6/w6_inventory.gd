extends SceneTree
## P13 Wave 6 TASK D 診断（唯読・headless）：Districts / Landmarks の建物ノードを列挙し、材質・三角形数・位置・AABB・分類を JSON へ。
##   godot --headless --path . --script res://tools/p13/w6/w6_inventory.gd -- <out.json>
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _mat_desc(m: Material) -> Dictionary:
	if m == null:
		return {"cls": "null"}
	var d := {"cls": m.get_class(), "name": m.resource_name, "path": m.resource_path}
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		d["albedo"] = [snappedf(b.albedo_color.r, 0.001), snappedf(b.albedo_color.g, 0.001), snappedf(b.albedo_color.b, 0.001)]
		d["tex"] = b.albedo_texture != null
	elif m is ShaderMaterial:
		d["shader"] = (m as ShaderMaterial).shader.resource_path if (m as ShaderMaterial).shader else ""
	return d


func _collect(n: Node, out: Dictionary, root3: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var tris := 0
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var ix = arr[Mesh.ARRAY_INDEX]
				tris += ((ix as PackedInt32Array).size() if ix != null and (ix as PackedInt32Array).size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
				var m: Material = mi.material_override if mi.material_override != null else mi.mesh.surface_get_material(s)
				var key := (m.resource_path if m != null and m.resource_path != "" else (m.resource_name if m != null else "null")) + "|" + (m.get_class() if m != null else "null")
				if not out["mats"].has(key):
					out["mats"][key] = _mat_desc(m)
				out["mat_tris"][key] = int(out["mat_tris"].get(key, 0)) + ((ix as PackedInt32Array).size() if ix != null and (ix as PackedInt32Array).size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			out["tris"] += tris
			out["n_mesh"] += 1
			var ab := mi.global_transform * mi.get_aabb()
			if out["aabb"] == null:
				out["aabb"] = ab
			else:
				out["aabb"] = (out["aabb"] as AABB).merge(ab)
	for c in n.get_children():
		_collect(c, out, root3)


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await process_frame
	var result := {"districts": {}, "landmarks": {}, "other_roots": {}}
	var dist := v.get_node("Districts")
	for d in dist.get_children():
		var entry := {"children": []}
		for ch in d.get_children():
			var rec := {"mats": {}, "mat_tris": {}, "tris": 0, "n_mesh": 0, "aabb": null}
			_collect(ch, rec, v)
			var ab = rec["aabb"]
			var c3 := Vector3.ZERO
			var sz := Vector3.ZERO
			if ab != null:
				c3 = (ab as AABB).get_center()
				sz = (ab as AABB).size
			var gt := ch as Node3D
			(entry["children"] as Array).append({"name": String(ch.name), "cls": ch.get_class(), "pos": [snappedf(gt.global_position.x, 0.01), snappedf(gt.global_position.y, 0.01), snappedf(gt.global_position.z, 0.01)] if gt else [],
				"center": [snappedf(c3.x, 0.01), snappedf(c3.y, 0.01), snappedf(c3.z, 0.01)], "size": [snappedf(sz.x, 0.01), snappedf(sz.y, 0.01), snappedf(sz.z, 0.01)],
				"tris": rec["tris"], "n_mesh": rec["n_mesh"], "mats": rec["mats"], "mat_tris": rec["mat_tris"], "n_children": ch.get_child_count(),
				"child_names": Array(ch.get_children().map(func(x): return String(x.name))).slice(0, 14)})
		result["districts"][String(d.name)] = entry
	var lm := v.get_node("Landmarks")
	for ch in lm.get_children():
		var rec := {"mats": {}, "mat_tris": {}, "tris": 0, "n_mesh": 0, "aabb": null}
		_collect(ch, rec, v)
		var ab = rec["aabb"]
		var gt := ch as Node3D
		result["landmarks"][String(ch.name)] = {"cls": ch.get_class(), "pos": [snappedf(gt.global_position.x, 0.01), snappedf(gt.global_position.y, 0.01), snappedf(gt.global_position.z, 0.01)] if gt else [],
			"size": [snappedf((ab as AABB).size.x, 0.01), snappedf((ab as AABB).size.y, 0.01), snappedf((ab as AABB).size.z, 0.01)] if ab != null else [],
			"tris": rec["tris"], "n_mesh": rec["n_mesh"], "mats": rec["mats"], "mat_tris": rec["mat_tris"], "n_children": ch.get_child_count()}
	var out_path := ""
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			out_path = a
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(result, "\t") + "\n")
		f.close()
	var nb := 0
	for dn in result["districts"].keys():
		nb += (result["districts"][dn]["children"] as Array).size()
		print("[INV] ", dn, " children=", (result["districts"][dn]["children"] as Array).size())
	print("[INV] districts children total=", nb, " landmarks=", result["landmarks"].size())
	quit(0)
