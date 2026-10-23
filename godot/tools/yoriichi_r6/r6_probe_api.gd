extends SceneTree
## R6：唯讀查 SpringBoneSimulator3D 在本版引擎的屬性／方法（center 相關）。
func _initialize() -> void:
	var names := []
	for m in ClassDB.class_get_method_list("SpringBoneSimulator3D", true):
		var n: String = m.name
		if n.contains("center") or n.contains("external") or n.contains("gravity_dir") or n.contains("rotation_axis") or n.contains("individual"):
			names.append(n)
	print("SBS_METHODS ", names)
	var en := []
	for e in ClassDB.class_get_enum_list("SpringBoneSimulator3D", true):
		en.append([e, ClassDB.class_get_enum_constants("SpringBoneSimulator3D", e, true)])
	print("SBS_ENUMS ", en)
	quit()
