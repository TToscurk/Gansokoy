extends SceneTree
## Runtime contract: each river vegetation band loads near its bank and all release away.
var main: Node

func _init() -> void:
	_run.call_deferred()

func _settle(frames: int) -> void:
	for i in frames:
		await process_frame
		await physics_frame

func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(8)
	main.load_map("slice", "")
	await _settle(30)
	var player := main.get_node_or_null("Player") as Node3D
	var river := main.map_root.get_node_or_null("RiverVegetation") as Node3D
	if player == null or river == null:
		push_error("Missing Player or RiverVegetation")
		quit(1)
		return
	var probes := {
		"RiverVegetationSouth": Vector3(430.0, 1.0, -450.0),
		"RiverVegetationLower": Vector3(430.0, 1.0, -150.0),
		"RiverVegetationUpper": Vector3(430.0, 1.0, 150.0),
		"RiverVegetationNorth": Vector3(430.0, 1.0, 480.0),
	}
	for name: String in probes:
		player.global_position = probes[name]
		await _settle(10)
		if river.get_node_or_null(name) == null:
			push_error("River chunk did not load: %s" % name)
			quit(2)
			return
	player.global_position = Vector3(0.0, 1.0, 0.0)
	await _settle(10)
	for name: String in probes:
		if river.get_node_or_null(name) != null:
			push_error("River chunk did not unload: %s" % name)
			quit(3)
			return
	print("[RIVER RUNTIME] each near-load and far-unload passed")
	quit(0)
