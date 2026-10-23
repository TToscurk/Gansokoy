extends SceneTree
func _initialize():
	var p = (load("res://characters/yoriichi/player_yoriichi_r7.tscn") as PackedScene).instantiate()
	root.add_child(p)
	for m in p.find_children("*", "MeshInstance3D", true, false):
		var aabb: AABB = (m as MeshInstance3D).get_aabb()
		print("MESH ", p.get_path_to(m), " surf=", (m as MeshInstance3D).mesh.get_surface_count() if m.mesh else 0, " size=", aabb.size.snapped(Vector3.ONE*0.01))
	quit()
