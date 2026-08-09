extends SceneTree

func _init() -> void:
	var packed := load("res://maps/asset_building_proof/asset_building_proof.tscn") as PackedScene
	if packed == null:
		push_error("asset proof scene failed to load")
		quit(1)
		return
	var root := packed.instantiate()
	get_root().add_child(root)
	await process_frame
	for child in root.get_children():
		print(child.name, " type=", child.get_class(), " children=", child.get_child_count(), " pos=", child.position if child is Node3D else "-")
		for nested in child.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := nested as MeshInstance3D
			print("  mesh=", mesh_node.name, " aabb=", mesh_node.get_aabb(), " global=", mesh_node.global_position)
	quit()
