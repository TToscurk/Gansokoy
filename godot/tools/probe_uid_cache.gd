extends SceneTree
func _init() -> void:
	for t in ["uid://dk1uqmfvufc8x", "uid://bhepfy5mcuoii", "uid://cxrl2unb0g4mh", "uid://di8l4d0vl7a2p", "uid://u6gnfq4esa13", "uid://bj3q8eds2a560"]:
		var id: int = ResourceUID.text_to_id(t)
		var p: String = ResourceUID.get_id_path(id)
		print("[CACHE] ", t, " id=", id, " -> '", p, "' valid=", ResourceUID.has_id(id))
	quit(0)
