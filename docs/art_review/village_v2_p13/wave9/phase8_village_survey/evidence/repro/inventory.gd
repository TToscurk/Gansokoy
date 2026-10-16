extends SceneTree
## P13 W9 Phase 8 村落全域盤點（唯讀・headless）。不寫任何場景檔。
## 1) root 直下節點（overlay 掛載順序・節點數・可見 MeshInstance 數・MultiMesh 實例數）
## 2) 各 District 建築：數量／前綴／Kit 可見／P4 灰盒可見／被哪個建築 overlay 取代
## 3) Landmarks：每個地標的可見網格類型與三角面
## 4) 「灰盒／佔位」候選：可見的 PrimitiveMesh（Box/Cylinder/…）與名稱含 placeholder/greybox/proxy 的節點
## 5) 建築（含 overlay）中心座標 → JSON（地圖用）
const SCENE := "res://maps/village_v2/village_v2.tscn"
var out := {}


func _init() -> void:
	_run.call_deferred()


func _vis(n: Node) -> bool:
	var p := n
	while p != null:
		if p is Node3D and not (p as Node3D).visible:
			return false
		p = p.get_parent()
	return true


func _tri(m: Mesh) -> int:
	if m == null:
		return 0
	var t := 0
	if m is ArrayMesh:
		var am := m as ArrayMesh
		for s in am.get_surface_count():
			var ic := am.surface_get_array_index_len(s)
			t += (ic if ic > 0 else am.surface_get_array_len(s)) / 3
	return t


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await process_frame
	# 1) root children
	var rc := []
	var idx := 0
	for c in v.get_children():
		var n_all := 0
		var n_mi := 0
		var n_mm := 0
		var mm_inst := 0
		var tri := 0
		for d in c.find_children("*", "", true, false):
			n_all += 1
			if d is MeshInstance3D and _vis(d):
				n_mi += 1
				tri += _tri((d as MeshInstance3D).mesh)
			elif d is MultiMeshInstance3D and _vis(d) and (d as MultiMeshInstance3D).multimesh != null:
				n_mm += 1
				mm_inst += (d as MultiMeshInstance3D).multimesh.instance_count
		var en = c.get("enabled")
		rc.append({"i": idx, "name": c.name, "cls": c.get_class(), "scene": c.scene_file_path, "visible": (c as Node3D).visible if c is Node3D else null,
			"enabled": en, "nodes": n_all, "vis_mi": n_mi, "vis_tri": tri, "mm_nodes": n_mm, "mm_inst": mm_inst})
		idx += 1
	out["root"] = rc
	# 2) districts / buildings
	var arch_names := {}
	for ov in ["ArchW9R2P13", "ArchHeroP13", "HeroArchP13"]:
		var o := v.get_node_or_null(ov)
		if o:
			for b in o.get_children():
				arch_names[String(b.name)] = ov
	var dist := {}
	var blds := []
	var dn := v.get_node_or_null("Districts")
	if dn:
		for d in dn.get_children():
			var bn := d.get_node_or_null("Buildings")
			if bn == null:
				continue
			var stat := {"n": 0, "prefix": {}, "kit_vis": 0, "grey_vis": 0, "no_kit": 0, "overlay": {}}
			for b in bn.get_children():
				if not (b is Node3D):
					continue
				stat["n"] += 1
				var nm := String(b.name)
				var pre := nm.substr(0, nm.rfind("_"))
				stat["prefix"][pre] = int(stat["prefix"].get(pre, 0)) + 1
				var kit := b.get_node_or_null("Kit")
				var kit_vis := kit != null and _vis(kit)
				if kit == null:
					stat["no_kit"] += 1
				elif kit_vis:
					stat["kit_vis"] += 1
				var grey := false
				for gname in ["Building_Main", "Building", "Greybox", "Body"]:
					var g := b.get_node_or_null(gname)
					if g != null and g is Node3D and _vis(g):
						grey = true
				if grey:
					stat["grey_vis"] += 1
				var ov: String = arch_names.get(nm, "")
				if ov != "":
					stat["overlay"][ov] = int(stat["overlay"].get(ov, 0)) + 1
				var p := (b as Node3D).global_position
				blds.append({"name": nm, "district": String(d.name), "x": snappedf(p.x, 0.1), "y": snappedf(p.y, 0.01), "z": snappedf(p.z, 0.1),
					"yaw": snappedf((b as Node3D).global_rotation.y, 0.001), "w": b.get_meta("width", 0.0), "d": b.get_meta("depth", 0.0),
					"kit": kit != null, "kit_vis": kit_vis, "grey": grey, "overlay": ov, "role": b.get_meta("p13_role", ""), "type": b.get_meta("type", b.get_meta("btype", ""))})
			dist[String(d.name)] = stat
	out["districts"] = dist
	out["buildings"] = blds
	# 3) landmarks
	var lms := []
	var ln := v.get_node_or_null("Landmarks")
	if ln:
		for l in ln.get_children():
			var kinds := {}
			var tri := 0
			var nvis := 0
			for d in l.find_children("*", "MeshInstance3D", true, false):
				if _vis(d):
					nvis += 1
					var mm := (d as MeshInstance3D).mesh
					var k := mm.get_class() if mm else "null"
					kinds[k] = int(kinds.get(k, 0)) + 1
					tri += _tri(mm)
			var p2 := (l as Node3D).global_position if l is Node3D else Vector3.ZERO
			lms.append({"name": String(l.name), "pos": [snappedf(p2.x, 0.1), snappedf(p2.y, 0.1), snappedf(p2.z, 0.1)], "vis_mi": nvis, "kinds": kinds, "tri": tri,
				"label": l.get_meta("label", ""), "children": l.get_child_count()})
	out["landmarks"] = lms
	# 4) primitive / placeholder candidates
	var prim := {}
	var named := []
	for d in v.find_children("*", "", true, false):
		var path := String(v.get_path_to(d))
		if path.begins_with("Debug"):
			continue
		var low := String(d.name).to_lower()
		if ("placeholder" in low or "greybox" in low or "graybox" in low or "proxy" in low) and d is Node3D and _vis(d):
			var gp := (d as Node3D).global_position
			named.append({"path": path, "cls": d.get_class(), "pos": [snappedf(gp.x, 0.1), snappedf(gp.y, 0.1), snappedf(gp.z, 0.1)]})
		if d is MeshInstance3D and _vis(d):
			var m := (d as MeshInstance3D).mesh
			if m is PrimitiveMesh:
				var parts := path.split("/")
				var key := "/".join(parts.slice(0, min(3, parts.size() - 1)))
				var e: Dictionary = prim.get(key, {"n": 0, "cls": {}, "samples": []})
				e["n"] += 1
				e["cls"][m.get_class()] = int(e["cls"].get(m.get_class(), 0)) + 1
				if (e["samples"] as Array).size() < 4:
					var gp2 := (d as Node3D).global_position
					var ab := (d as MeshInstance3D).get_aabb()
					e["samples"].append({"path": path, "pos": [snappedf(gp2.x, 0.1), snappedf(gp2.y, 0.1), snappedf(gp2.z, 0.1)], "size": [snappedf(ab.size.x, 0.01), snappedf(ab.size.y, 0.01), snappedf(ab.size.z, 0.01)]})
				prim[key] = e
	out["primitive_meshes"] = prim
	out["named_placeholders"] = named
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("[INV] root=%d buildings=%d landmarks=%d prim_groups=%d named=%d" % [rc.size(), blds.size(), lms.size(), prim.size(), named.size()])
	quit(0)
