extends SceneTree
## P13 Wave 7 診断（唯読・headless）：町家 Kit 建物 187 棟の meta／位置／LOD 別の材質（基底 → 現在の override）を JSON に出す。
##   godot --headless --path . --script res://tools/p13/w7/w7_inventory.gd -- <out.json>
## 目的：batch1 の 50 棟が W2 主街 39／R6a Pilot 24 と重ならないこと、用途・区域・Kit、LOD0／1／2 の材質継承を確定する。
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _lod_of(mi: MeshInstance3D, kit: Node) -> int:
	var n: Node = mi
	while n != null and n.get_parent() != kit:
		n = n.get_parent()
	if n == null:
		return -1
	var nm := String(n.name)
	if nm.begins_with("LOD") and nm.length() >= 4:
		return int(nm.substr(3))
	return -1


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0]) if args.size() > 0 else "user://w7_inventory.json"
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await process_frame
	var rows: Array = []
	for n in v.get_node("Districts").find_children("B_*", "", true, false):
		if not (n is Node3D):
			continue
		var kit := (n as Node).get_node_or_null("Kit")
		if kit == null:
			continue
		var b := n as Node3D
		var row := {"name": String(b.name), "path": String(v.get_path_to(b)), "district": String(b.get_path()).split("/")[3] if String(b.get_path()).split("/").size() > 3 else ""}
		row["pos"] = [snappedf(b.global_position.x, 0.01), snappedf(b.global_position.y, 0.01), snappedf(b.global_position.z, 0.01)]
		row["yaw"] = snappedf(b.global_rotation.y, 0.001)
		var meta := {}
		for k in b.get_meta_list():
			var val = b.get_meta(k)
			meta[String(k)] = val if (val is int or val is float or val is String or val is bool) else str(val)
		row["meta"] = meta
		var lods := {}
		for mi in kit.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var li := _lod_of(m, kit)
			var key := "LOD%d" % li
			if not lods.has(key):
				lods[key] = {"n_mesh": 0, "tris": 0, "surf": {}, "vis_begin": m.visibility_range_begin, "vis_end": m.visibility_range_end}
			var L: Dictionary = lods[key]
			L["n_mesh"] += 1
			for si in m.mesh.get_surface_count():
				var arr_n := 0
				var ar := m.mesh.surface_get_arrays(si)
				var ix = ar[Mesh.ARRAY_INDEX]
				arr_n = (ix as PackedInt32Array).size() / 3 if ix != null else (ar[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				L["tris"] += arr_n
				var base := m.mesh.surface_get_material(si)
				var bp := base.resource_path.get_file() if base != null and base.resource_path != "" else (base.get_class() if base != null else "null")
				var ov := m.get_surface_override_material(si)
				var op := ""
				if ov != null:
					op = ov.resource_path.get_file() if ov.resource_path != "" else ov.get_class()
				var mo := m.material_override
				var key2 := "%s -> %s" % [bp, op if op != "" else ("MO:" + (mo.resource_path.get_file() if mo != null else "")) if mo != null else "(base)"]
				L["surf"][key2] = int(L["surf"].get(key2, 0)) + 1
		row["lods"] = lods
		# Frontage／Hisashi／Hero など Kit 以外の子
		var others := {}
		for c in b.get_children():
			if String(c.name) in ["Kit"]:
				continue
			var cnt := 0
			var tr := 0
			var ovs := 0
			for mi in c.find_children("*", "MeshInstance3D", true, false):
				cnt += 1
				var m2 := mi as MeshInstance3D
				if m2.mesh != null:
					for si in m2.mesh.get_surface_count():
						if m2.get_surface_override_material(si) != null:
							ovs += 1
			if c is MeshInstance3D:
				cnt += 1
			others[String(c.name)] = {"cls": c.get_class(), "n_mesh": cnt, "visible": (c as Node3D).visible if c is Node3D else true, "overrides": ovs}
		row["others"] = others
		rows.append(row)
	rows.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"buildings": rows}, " "))
	f.close()
	print("[W7INV] buildings=", rows.size(), " -> ", out_path)
	quit(0)
