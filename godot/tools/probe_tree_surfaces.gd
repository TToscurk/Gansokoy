extends SceneTree
## TwistedTree 的 surface 佈局：哪個 surface 是葉子？
##   Godot --headless --path godot --script tools/probe_tree_surfaces.gd

func _init() -> void:
	for n in ["TwistedTree_1", "TwistedTree_3", "CommonTree_1", "DeadTree_1", "Pine_1"]:
		var ps := load("res://assets/nature/%s.gltf" % n) as PackedScene
		var inst := ps.instantiate() as Node3D
		for m in _mesh_nodes(inst):
			var mi := m as MeshInstance3D
			print("[SURF] %-14s node=%-20s surfaces=%d" % [n, mi.name, mi.mesh.get_surface_count()])
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i)
				var tex := "?"
				if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
					tex = (mat as StandardMaterial3D).albedo_texture.resource_path.get_file()
				print("[SURF]    surface %d  mat=%s  tex=%s" % [i, mat.resource_name if mat else "null", tex])
		inst.free()
	quit(0)

func _mesh_nodes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null: o.append(n)
	for c in n.get_children(): o.append_array(_mesh_nodes(c))
	return o
