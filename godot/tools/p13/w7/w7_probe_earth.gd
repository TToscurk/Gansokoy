extends SceneTree
## P13 W7 診断（唯読・headless）：P8 FarmlandEast の全 MeshInstance3D を材質インスタンス別に分類し、
## EarthBanks の材質 ko36i が他のどのノードと共有されているかを出す。
##   godot --headless --path . --script res://tools/p13/w7/w7_probe_earth.gd -- <out.json>
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _mat_key(m: Material) -> String:
	if m == null:
		return "null"
	var sh := ""
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		sh = (m as ShaderMaterial).shader.resource_path.get_file()
	return "%s#%d|%s|%s" % [m.get_class(), m.get_instance_id(), m.resource_path.get_file() if m.resource_path != "" else "(embedded)", sh]


func _run() -> void:
	var out_path := String(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else "user://w7_earth.json"
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await process_frame
	var fe := v.get_node("Districts/FarmlandEast")
	var groups := {}    # mat_key → {n, tris, kinds{}, sample[]}
	for mi in fe.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var p := String(v.get_path_to(m))
		var keys := []
		if m.material_override != null:
			keys.append("MO:" + _mat_key(m.material_override))
		for si in m.mesh.get_surface_count():
			var so := m.get_surface_override_material(si)
			var sm := m.mesh.surface_get_material(si)
			keys.append(("SO:" if so != null else "SM:") + _mat_key(so if so != null else sm))
		var seen := {}
		for k in keys:
			if seen.has(k):
				continue
			seen[k] = true
			if not groups.has(k):
				groups[k] = {"n": 0, "dirs": {}, "sample": []}
			var g: Dictionary = groups[k]
			g["n"] += 1
			var parts := p.split("/")
			var d := "/".join(parts.slice(0, mini(parts.size() - 1, 6)))
			g["dirs"][d] = int(g["dirs"].get(d, 0)) + 1
			if (g["sample"] as Array).size() < 4:
				(g["sample"] as Array).append(p)
	# EarthBanks の子の名前内訳
	var eb := v.get_node("Districts/FarmlandEast/FarmlandP8/EarthBanks")
	var kinds := {}
	for c in eb.get_children():
		var nm := String(c.name)
		var parts2 := nm.split("_")
		var zone := parts2[1] if parts2.size() > 1 else nm
		var kind := parts2[2].rstrip("0123456789AB") if parts2.size() > 2 else ""
		var key2 := "%s/%s" % [zone, kind]
		var tr := 0
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var ar := (c as MeshInstance3D).mesh.surface_get_arrays(0)
			var ix = ar[Mesh.ARRAY_INDEX]
			tr = (ix as PackedInt32Array).size() / 3 if ix != null else (ar[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		if not kinds.has(key2):
			kinds[key2] = {"n": 0, "tris": 0}
		kinds[key2]["n"] += 1
		kinds[key2]["tris"] += tr
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"groups": groups, "earthbank_kinds": kinds}, " "))
	f.close()
	print("[W7E] groups=", groups.size(), " earthbank_kinds=", kinds.size(), " -> ", out_path)
	quit(0)
