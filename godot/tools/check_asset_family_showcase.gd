extends SceneTree

const FAMILY_GLBS := [
	"res://assets/models/family_standard_machiya_01.glb",
	"res://assets/models/family_standard_machiya_02.glb",
	"res://assets/models/family_standard_machiya_03.glb",
	"res://assets/models/family_standard_machiya_04.glb",
	"res://assets/models/family_standard_machiya_05.glb",
	"res://assets/models/family_standard_machiya_06.glb",
	"res://assets/models/family_nagaya_03bay.glb",
	"res://assets/models/family_nagaya_04bay.glb",
	"res://assets/models/family_nagaya_05bay.glb",
	"res://assets/models/family_kura_compact.glb",
	"res://assets/models/family_kura_loading.glb",
	"res://assets/models/family_kura_deep.glb",
	"res://assets/models/family_small_merchant_01.glb",
	"res://assets/models/family_small_merchant_02.glb",
	"res://assets/models/family_small_merchant_03.glb",
	"res://assets/models/family_small_merchant_04.glb",
	"res://assets/models/family_small_merchant_05.glb",
]


func _init() -> void:
	var failures := 0
	for path: String in FAMILY_GLBS:
		var imported := load(path) as PackedScene
		if imported == null:
			push_error("family GLB import failed: %s" % path)
			failures += 1
			continue
		var instance := imported.instantiate()
		var meshes := instance.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty():
			push_error("family GLB has no imported mesh: %s" % path)
			failures += 1
		else:
			var mesh_instance := meshes[0] as MeshInstance3D
			if mesh_instance.mesh.get_surface_count() != 6:
				push_error("family GLB surface count is not six: %s" % path)
				failures += 1
		instance.free()

	var packed := load("res://maps/asset_family_showcase/asset_family_showcase.tscn") as PackedScene
	if packed == null:
		push_error("asset family showcase failed to load")
		quit(1)
		return
	var root := packed.instantiate()
	get_root().add_child(root)
	await process_frame
	for expected: String in ["StandardMachiya", "Nagaya", "Kura", "SmallMerchant"]:
		var family := root.get_node_or_null(expected)
		if family == null:
			push_error("missing showcase family: %s" % expected)
			failures += 1
			continue
		var meshes := family.find_children("*", "MeshInstance3D", true, false)
		if meshes.is_empty():
			push_error("showcase family has no mesh: %s" % expected)
			failures += 1
		else:
			print(expected, " meshes=", meshes.size())
	quit(1 if failures else 0)
