extends SceneTree
## Runtime contract: Machi visuals load near canal and release after leaving it.
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
	var canal := main.map_root.get_node_or_null("MachiCanal") as Node3D
	if player == null or canal == null:
		push_error("Missing Player or MachiCanal")
		quit(1)
		return
	player.global_position = Vector3(287.0, 1.0, 10.0)
	await _settle(8)
	if canal.get_node_or_null("Machi_Waterworks") == null or canal.get_node_or_null("Machi_BankDressing") == null:
		push_error("Machi chunks did not load near canal")
		quit(2)
		return
	player.global_position = Vector3(180.0, 1.0, 10.0)
	await _settle(8)
	if canal.get_node_or_null("Machi_Waterworks") != null or canal.get_node_or_null("Machi_BankDressing") != null:
		push_error("Machi chunks did not unload away from canal")
		quit(3)
		return
	print("[MACHI RUNTIME] near-load and far-unload passed")
	quit(0)
