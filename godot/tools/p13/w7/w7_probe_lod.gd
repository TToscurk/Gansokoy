extends SceneTree
## P13 W7 診断（唯読・headless）：指定建物の LOD0／1／2 ごとに「基底材質 → 実効材質」の面数ヒストグラムを出す（overlay 適用後）。
##   godot --headless --path . --script res://tools/p13/w7/w7_probe_lod.gd -- <id1,id2,...>
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _nm(m: Material) -> String:
	if m == null:
		return "null"
	if m.resource_path != "" and not m.resource_path.contains("::"):
		return m.resource_path.get_file().get_basename()
	return m.resource_name if m.resource_name != "" else m.get_class()


func _run() -> void:
	var ids := String(OS.get_cmdline_user_args()[0]).split(",", false)
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await process_frame
	for id in ids:
		var b: Node = null
		for n in v.get_node("Districts").find_children(id, "", true, false):
			b = n
			break
		if b == null:
			print("[W7L] ", id, " not found")
			continue
		var kit := b.get_node("Kit")
		print("[W7L] == ", id)
		for lod in ["LOD0", "LOD1", "LOD2"]:
			var ln := kit.get_node_or_null(lod)
			if ln == null:
				print("[W7L]   ", lod, " 無し")
				continue
			var h := {}
			var tris := 0
			for mi in ln.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if m.mesh == null:
					continue
				for si in m.mesh.get_surface_count():
					var base := m.mesh.surface_get_material(si)
					var ov := m.get_surface_override_material(si)
					var mo := m.material_override
					var eff := mo if mo != null else (ov if ov != null else base)
					var k := "%s → %s" % [_nm(base), _nm(eff) if eff != base else "(同じ)"]
					h[k] = int(h.get(k, 0)) + 1
			var keys := h.keys()
			keys.sort()
			var line := ""
			for k in keys:
				line += "  [%s ×%d]" % [k, h[k]]
			print("[W7L]   ", lod, line)
	quit(0)
