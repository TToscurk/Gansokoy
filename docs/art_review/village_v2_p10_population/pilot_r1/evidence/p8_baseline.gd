extends "res://tools/walk_village_v2_farmland.gd"
# P10 R3b closure: reuse the frozen P8 benchmark, no saved-scene edits.
func _cost() -> void:
	var population: Node = main.map_root.get_node_or_null("Population")
	if population:
		main.map_root.remove_child(population)
		population.free()
		await process_frame
	print("[BASELINE] PRELIMINARY: GPU preflight range failed; NOT a formal regression verdict. P10 Population absent IN MEMORY; shared scene unchanged; frozen P8 benchmark reused")
	await super._cost()
