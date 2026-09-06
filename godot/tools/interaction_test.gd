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
	main.load_map("slice", "trail")
	# load_map + NPC 生成 + 首次物理刷新要幾幀才穩定；單 process_frame 會抓到
	# 舊狀態（raycast 還沒命中過，prompt 永遠不出來）。
	for i in 10:
		await process_frame
		await physics_frame

	var npc := main.map_root.get_node_or_null("VerticalSliceNPC") as Node3D
	var prompt := main.get_node_or_null("UI/InteractionPrompt") as Label
	var message := main.get_node_or_null("UI/InteractionMessage") as Label
	if npc == null:
		_fail("slice test NPC is missing")
	if prompt == null or message == null:
		_fail("interaction UI labels are missing")
	if npc == null or prompt == null or message == null:
		await _teardown(main)
		_finish()
		return

	var player: CharacterBody3D = main.player
	# Spawn is at the reserved marker (235,0,16); the NPC sits 3 m north of it.
	# Camera default yaw looks -z, so the player already faces the NPC.
	player.global_position = npc.global_position + Vector3(0.0, 0.0, 3.0)
	# 互動射線每個物理幀刷新一次；生成點落定＋首次命中至少要兩幀。
	for i in 4:
		await physics_frame
		await process_frame
	if not prompt.visible or prompt.text != "E：交談":
		_fail("facing the NPC did not show the expected prompt")

	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	# "interact" is handled by the camera adapter (it owns the ray), not the body.
	player.get_node("CameraAdapter")._unhandled_input(event)
	await process_frame
	if not message.visible or message.text != "村人：歡迎來到人間之里。":
		_fail("interacting did not show the fixed NPC response")

	# The interaction ray hangs off the camera Pivot; the body does not carry it.
	var adapter := player.get_node("CameraAdapter")
	# Point the camera away from the NPC (yaw +90° = looking +x, NPC is at -z).
	adapter._target_yaw = PI / 2.0
	adapter._current_yaw = PI / 2.0
	await physics_frame
	await physics_frame
	if prompt.visible:
		_fail("prompt remained visible while facing away")

	main.load_map("kourindou", "slice")
	await process_frame
	if main.current_id != "kourindou":
		_fail("player could not leave slice for kourindou after interacting")
	if main.map_root.get_node_or_null("VerticalSliceNPC") != null:
		_fail("slice test NPC leaked into kourindou")
	if prompt.visible or message.visible:
		_fail("interaction UI was not cleared on map transition")

	await _teardown(main)
	_finish()


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: slice NPC prompt, interaction response, and facing-away hide")
		quit(0)
	else:
		print("FAIL: %d interaction problem(s)" % _failures.size())
		quit(1)


func _teardown(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()
	await process_frame
