extends SceneTree
## P13 W7 診断（唯読・headless）：第一批 50 棟で、実際に surface override が入っている面の数を直接数え、overlay の applied／skipped と突き合わせる。
##   godot --headless --path . --script res://tools/p13/w7/w7_probe_counts.gd
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
	var ab := v.get_node("AlbedoBatch1P13")
	var tot_ov := 0
	var tot_mi := 0
	var tot_surf := 0
	var by_base := {}
	var by_lod := {}
	for b: Dictionary in man["buildings"]:
		var n := v.get_node(NodePath(String(b["path"])))
		for mi in n.get_node("Kit").find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			tot_mi += 1
			var lod := "?"
			var p := m
			while p != null and p != n:
				if String(p.name).begins_with("LOD") and String(p.name).length() == 4:
					lod = String(p.name)
				p = p.get_parent() as MeshInstance3D if p.get_parent() is MeshInstance3D else null
				break
			for si in m.mesh.get_surface_count():
				tot_surf += 1
				var ov := m.get_surface_override_material(si)
				if ov != null:
					tot_ov += 1
					var base := m.mesh.surface_get_material(si)
					var key := (base.resource_path.get_file() if base != null else "(null)")
					by_base[key] = int(by_base.get(key, 0)) + 1
	print("[W7C] MeshInstance3D ", tot_mi, "・全面 ", tot_surf, "・override あり ", tot_ov)
	print("[W7C] override の基底材質別 ", by_base)
	print("[W7C] overlay applied_surfaces=", ab.get("applied_surfaces"), " skipped_surfaces=", ab.get("skipped_surfaces"))
	quit(0)
