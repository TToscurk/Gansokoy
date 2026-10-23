extends SceneTree
func _init() -> void:
	for cls in ["SpringBoneSimulator3D", "SpringBoneCollisionCapsule3D", "SpringBoneCollision3D"]:
		var ms := ClassDB.class_get_method_list(cls, true).map(func(m): return m.name)
		ms.sort()
		print("API ", cls, " ", ms)
		print("SIG ", cls, " ", ClassDB.class_get_signal_list(cls, true).map(func(s): return s.name))
	quit()
