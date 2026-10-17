extends SceneTree
## 一時：保存された場景の『意味』の比較（腳本は走らせない＝木に入れずに instantiate）。
##   godot --headless --path . --script <this> -- res://a.tscn res://b.tscn [res://c.tscn]
const PROPS := ["visible", "disabled", "collision_layer", "collision_mask", "transform", "mesh", "material_override", "shape", "script", "cast_shadow", "light_energy", "multimesh"]


func _init() -> void:
	var paths := OS.get_cmdline_user_args()
	var sigs: Array = []
	for p in paths:
		var ps := ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var r := ps.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
		var d := {}
		_walk(r, r, d)
		r.free()
		sigs.append(d)
		print("[W9SEM] %s ノード %d" % [p, d.size()])
	for k in range(1, sigs.size()):
		var a: Dictionary = sigs[0] if k == 1 else sigs[k - 1]
		var b: Dictionary = sigs[k]
		var cat := {}
		var ex := {}
		for path in a:
			if not b.has(path):
				cat["node_removed"] = int(cat.get("node_removed", 0)) + 1
				continue
			var pa: Dictionary = a[path]
			var pb: Dictionary = b[path]
			for prop in pa:
				if str(pa[prop]) != str(pb.get(prop)):
					cat[prop] = int(cat.get(prop, 0)) + 1
					if not ex.has(prop) or (ex[prop] as Array).size() < 4:
						if not ex.has(prop):
							ex[prop] = []
						(ex[prop] as Array).append([path, str(pa[prop]).left(120), str(pb.get(prop)).left(120)])
		for path in b:
			if not a.has(path):
				cat["node_added"] = int(cat.get("node_added", 0)) + 1
		print("[W9SEM] %s → %s：差 %s" % [paths[0] if k == 1 else paths[k - 1], paths[k], str(cat)])
		for prop in ex:
			for e in ex[prop]:
				print("[W9SEM]    %s %s：%s → %s" % [prop, e[0], e[1], e[2]])
	quit(0)


func _walk(n: Node, root: Node, d: Dictionary) -> void:
	var s := {"class": n.get_class()}
	for p in PROPS:
		if p in n:
			var v = n.get(p)
			if v is Resource:
				var rp := (v as Resource).resource_path
				if rp.contains("::"):
					rp = "::" + rp.get_slice("::", 1)    # 内蔵リソース：ファイル名を除いた id だけ比べる
				v = rp if rp != "" else ("%s:%s" % [(v as Resource).get_class(), _res_sig(v)])
				if v is String and (v as String).begins_with("::") and v is String:
					v = "%s%s" % [v, _res_sig(n.get(p))]
			elif v is Transform3D:
				var t: Transform3D = v
				v = "%s|%s|%s|%s" % [t.basis.x.snapped(Vector3.ONE * 1e-4), t.basis.y.snapped(Vector3.ONE * 1e-4), t.basis.z.snapped(Vector3.ONE * 1e-4), t.origin.snapped(Vector3.ONE * 1e-4)]
			s[p] = v
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var so: Array = []
		for i in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(i)
			so.append(m.resource_path if m and m.resource_path != "" else (str(m.get_class()) if m else ""))
		s["surface_override"] = so
	var mk := n.get_meta_list()
	mk.sort()
	s["meta_keys"] = mk
	d[String(root.get_path_to(n))] = s
	for c in n.get_children():
		_walk(c, root, d)


func _res_sig(r: Resource) -> String:
	if r is BoxShape3D:
		return str((r as BoxShape3D).size.snapped(Vector3.ONE * 1e-4))
	return ""
