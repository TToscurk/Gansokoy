extends SceneTree
## 立繪實機截圖（ART_REVIEW 用）：靈夢對話 + 緣一獨白，各一張。
## --script 模式下 autoload 在 _init 當下尚未就緒，必須 call_deferred。
const OUT := "D:/神社/shrine/work/shots/portraits/"


func _init() -> void:
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("[SHOT] ", name)


func _run() -> void:
	var dm: Node = root.get_node("/root/DialogueManager")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(4)
	var day := root.get_node("/root/DayNight")
	day.set("flowing", false)
	day.call("set_hour", 11.0)
	# 1) 開場獨白（緣一立繪）
	await _settle(60)
	if dm.is_active():
		await _shot("1_yoriichi_wake")
	while dm.is_active():
		dm.advance()
		await _settle(2)
	# 2) 神社靈夢對話（靈夢立繪）
	main.load_map("shrine", "trail")
	await _settle(40)
	var player: CharacterBody3D = main.player
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0.6, 4.5, -19.5)
	player.rotation.y = 0.0
	await _settle(40)
	var e := InputEventAction.new()
	e.action = "interact"
	e.pressed = true
	Input.parse_input_event(e)
	await _settle(60)
	print("[SHOT] dialogue_active=", dm.is_active())
	await _shot("2_reimu_first")
	# 推進到靈夢「認真」表情差分
	for i in 12:
		dm.advance()
		await _settle(4)
	await _shot("3_reimu_serious")
	quit(0)
