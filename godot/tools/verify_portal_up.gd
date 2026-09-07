extends SceneTree
## 真實鍵盤事件驗證：進區不自動傳送、↑ 按一次才換圖。
var failures := 0
var main: Node

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[UP] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func key(pressed: bool, echo_event: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_UP
	event.pressed = pressed
	event.echo = echo_event
	Input.parse_input_event(event)

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(3)
	main.load_map("shrine", "")
	await frames(3)
	var player: CharacterBody3D = main.player
	player.set_physics_process(false)
	var area: Area3D = main.map_root.get_node("Portal_trail")
	player.global_position = area.global_position
	main.portal_cooldown = 0.0
	await frames(6)
	check("進區不自動換圖", main.current_id == "shrine")
	if main.current_id != "shrine":
		print("[UP] failures=%d" % failures)
		quit(failures)
		return
	check("物理 overlap 真正包含玩家", area.get_overlapping_bodies().has(player))
	check("光門存在", area.has_node("GlowGate"))
	check("上鍵提示存在", area.has_node("PortalPrompt"))
	main.portal_cooldown = 1.0
	key(true)
	await frames(2)
	key(false)
	check("冷卻中按上不傳送", main.current_id == "shrine")
	main.portal_cooldown = 0.0
	await frames(3)
	check("冷卻結束不補發自動傳送", main.current_id == "shrine")
	key(true, true)
	await frames(2)
	check("鍵盤 repeat 不傳送", main.current_id == "shrine")
	key(false)
	key(true)
	await frames(5)
	check("實際 ↑ 事件前往獸道", main.current_id == "trail")
	var back: Area3D = main.map_root.get_node("Portal_shrine")
	player.global_position = back.global_position
	main.portal_cooldown = 0.0
	await frames(4)
	key(true, true)
	await frames(3)
	check("長按不會到站後彈回", main.current_id == "trail")
	key(false)
	key(true)
	await frames(5)
	key(false)
	check("放開再按可回神社", main.current_id == "shrine")
	player.global_position += Vector3(20, 0, 0)
	main.portal_cooldown = 0.0
	await frames(4)
	key(true)
	await frames(3)
	key(false)
	check("區外按上不傳送", main.current_id == "shrine")
	print("[UP] failures=%d" % failures)
	quit(failures)
