# Minimal Human Village interaction regression test.
#   Godot --headless --path godot --script tools/interaction_test.gd
extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	# SceneTree scripts start before project autoloads finish registering.
	await process_frame
	if not InputMap.has_action("interact"):
		_fail("InputMap is missing interact")
		_finish()
		return

	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	if packed == null:
		_fail("main.tscn failed to load")
		_finish()
		return
	var main := packed.instantiate()
	get_root().add_child(main)
	await process_frame
	main.load_map("village", "trail")
	await process_frame
	await physics_frame

	var npc := main.map_root.get_node_or_null("VerticalSliceNPC") as Node3D
	var prompt := main.get_node_or_null("UI/InteractionPrompt") as Label
	var message := main.get_node_or_null("UI/InteractionMessage") as Label
	if npc == null:
		_fail("village test NPC is missing")
	if prompt == null or message == null:
		_fail("interaction UI labels are missing")
	if npc == null or prompt == null or message == null:
		await _teardown(main)
		_finish()
		return

	var player: CharacterBody3D = main.player
	player.global_position = npc.global_position + Vector3(0.0, 0.0, 3.0)
	player.look_at(Vector3(npc.global_position.x, player.global_position.y, npc.global_position.z), Vector3.UP)
	await physics_frame
	await physics_frame
	if not prompt.visible or prompt.text != "E：交談":
		_fail("facing the NPC did not show the expected prompt")

	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	player._unhandled_input(event)
	await process_frame
	if not message.visible or message.text != "村人：歡迎來到人間之里。":
		_fail("interacting did not show the fixed NPC response")

	player.rotate_y(PI)
	await physics_frame
	player.interaction_ray.force_raycast_update()
	player._update_interaction_target()
	if prompt.visible:
		_fail("prompt remained visible while facing away")

	main.load_map("kourindou", "village")
	await process_frame
	if main.current_id != "kourindou":
		_fail("player could not leave village for kourindou after interacting")
	if main.map_root.get_node_or_null("VerticalSliceNPC") != null:
		_fail("village test NPC leaked into kourindou")
	if prompt.visible or message.visible:
		_fail("interaction UI was not cleared on map transition")

	await _teardown(main)
	_finish()


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: village NPC prompt, interaction response, and facing-away hide")
		quit(0)
	else:
		print("FAIL: %d interaction problem(s)" % _failures.size())
		quit(1)


func _teardown(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()
	await process_frame
