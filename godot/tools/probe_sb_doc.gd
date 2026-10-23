extends SceneTree
func _init() -> void:
	for p in ClassDB.class_get_property_list("SpringBoneSimulator3D", true):
		if str(p.name).contains("curve") or str(p.name).contains("individual"):
			print("PROP ", p.name, " ", p.hint_string)
	quit()
