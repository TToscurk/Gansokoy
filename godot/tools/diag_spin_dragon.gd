extends SceneTree
## 大招鏈路：輸入 → request_continuous_spin → _spawn_sun_dragon，逐段定位。

var main: Node = null
var player: Node = null

func _init() -> void:
	_run.call_deferred()

func _dragons() -> int:
	var c := 0
	for d in root.find_children("*", "Node3D", true, false):
		var s: Variant = d.get_script()
		if s != null and String(s.resource_path).ends_with("sun_dragon.gd"):
			c += 1
	return c

func _run() -> void:
	main = load("res://scenes/combat_arena.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await physics_frame
		await process_frame
	player = main.get_node("Player")
	print("[SPIN] sun_dragon_enabled=%s scale=%.2f" % [str(player.sun_dragon_enabled), player.sun_dragon_scale])

	# A) 直接呼叫生成函數：特效本體壞了會被這一段抓到
	player._spawn_sun_dragon()
	for i in 5:
		await process_frame
	print("[SPIN] A) _spawn_sun_dragon() 直呼 → dragons=%d" % _dragons())
	for d in root.find_children("*", "Node3D", true, false):
		var s: Variant = d.get_script()
		if s != null and String(s.resource_path).ends_with("sun_dragon.gd"):
			d.queue_free()
	for i in 10:
		await process_frame

	# B) request_continuous_spin()：招式閘門壞了會被這一段抓到
	player.sword_state = player.SwordState.DRAWN
	player.action_state = 0
	player._active_attack_name = ""
	print("[SPIN] B) before: action=%s sword=%s" % [str(player.action_state), str(player.sword_state)])
	player.request_continuous_spin()
	await process_frame
	await process_frame
	print("[SPIN] B) after request: action=%s anim=%s dragons=%d"
		% [str(player.action_state), str(player._active_attack_name), _dragons()])

	# C) 按鍵路徑
	for i in 240:
		await physics_frame
		await process_frame
	player.action_state = 0
	player._active_attack_name = ""
	var e := InputEventAction.new()
	e.action = "attack_special"
	e.pressed = true
	Input.parse_input_event(e)
	await physics_frame
	await process_frame
	e.pressed = false
	Input.parse_input_event(e)
	print("[SPIN] C) after tap: action=%s anim=%s" % [str(player.action_state), str(player._active_attack_name)])
	for i in 20:
		await physics_frame
		await process_frame
	print("[SPIN] C) 20 幀後 dragons=%d" % _dragons())
	quit(0)
