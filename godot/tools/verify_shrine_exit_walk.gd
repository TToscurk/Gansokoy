extends "res://tools/verify_walk_shrine_to_village.gd"
## 神社南出口走測：真的用角色控制器走一遍。
##   下行：境內主鳥居前（z=40）→ 二之鳥居 → 20 階石階 → 下平台傳送區 → 換圖到獸道
##   上行：從獸道傳回神社（落在下平台）→ 走上石階回到 z=40
##
##   Godot --headless --path godot --script tools/verify_shrine_exit_walk.gd
##
## 沿用 verify_walk_shrine_to_village.gd 的轉向／卡住偵測，只換路線。

const AXIS_X := 0.0
const Z_COURT := 40.0         # 主鳥居北側，境內
const Y_COURT := -1.1


func _settle(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.load_map("shrine", "")
	await _settle(30)

	player = main.get_node_or_null("Player")
	check("the world loader booted", main != null and player != null)
	check("we start in 博麗神社", main.current_id == "shrine")
	if player == null or main.current_id != "shrine":
		print("[WALK] failures=%d" % failures)
		quit(maxi(failures, 1))
		return
	yaw = Node3D.new()
	main.add_child(yaw)
	player.input_yaw_node = yaw
	# 開場淡入 + 醒來獨白會鎖玩家（input_locked）——先跳完對話再解鎖
	var dm: Node = root.get_node("/root/DialogueManager")
	var fade: Node = main.get_node_or_null("OpeningFade")
	var waited := 0
	while (fade != null and is_instance_valid(fade) and fade.is_inside_tree()) and waited < 600:
		await _settle(1)
		waited += 1
	while dm.is_active():
		var e := InputEventAction.new()
		e.action = "ui_accept"; e.pressed = true
		Input.parse_input_event(e)
		await physics_frame
		e = InputEventAction.new()
		e.action = "ui_accept"; e.pressed = false
		Input.parse_input_event(e)
		await physics_frame
	player.set("input_locked", false)
	await _settle(5)
	check("玩家未被鎖住", not bool(player.get("input_locked")))

	# ── 下行 ──
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(AXIS_X, Y_COURT + 0.4, Z_COURT)
	await _settle(20)
	check("境內起點站得住", player.is_on_floor())
	print("[WALK] 下行起點 %s on_floor=%s" % [_v(player.global_position), str(player.is_on_floor())])
	var p1 := _portal_in_current_map("trail")
	check("神社有通往獸道的傳送區", p1 != Vector3.INF)
	var r1: Dictionary = await _walk_to(p1, "shrine↓", "trail")
	print("[WALK] 下行 %s (遊戲時間 %.1f s, 路徑 %.1f m, 剩 %.1f m)" % [r1.reason, r1.game_seconds, r1.path_len, r1.distance])
	check("能從境內走下石階進入獸道傳送區：%s" % r1.reason, r1.arrived)
	await _settle(30)
	check("換圖後真的在獸道", main.current_id == "trail")
	if main.current_id != "trail":
		for line in _log:
			print("[WALK]" + line)
		print("[WALK] failures=%d" % failures)
		quit(maxi(failures, 1))
		return

	# ── 上行：從獸道傳回神社 ──
	var back := _portal_in_current_map("shrine")
	check("獸道有回神社的傳送區", back != Vector3.INF)
	player.velocity = Vector3.ZERO
	player.global_position = back + Vector3(0.0, 1.2, 0.0)
	await _settle(20)
	main.portal_cooldown = 0.0
	await _press_up()
	await _settle(40)
	check("按 ↑ 回到神社", main.current_id == "shrine")
	if main.current_id != "shrine":
		print("[WALK] failures=%d" % failures)
		quit(maxi(failures, 1))
		return
	print("[WALK] 上行起點（獸道→神社落點）%s on_floor=%s locked=%s dialogue=%s" % [_v(player.global_position), str(player.is_on_floor()), str(player.get("input_locked")), str(dm.is_active())])
	# 換圖後若有對話／鎖定（序章劇情），同樣先跳過再走
	while dm.is_active():
		var e := InputEventAction.new()
		e.action = "ui_accept"; e.pressed = true
		Input.parse_input_event(e)
		await physics_frame
		e = InputEventAction.new()
		e.action = "ui_accept"; e.pressed = false
		Input.parse_input_event(e)
		await physics_frame
	player.set("input_locked", false)
	await _settle(5)
	check("回神社落在下平台（z 68–76）", player.global_position.z > 68.0 and player.global_position.z < 76.0)
	check("回神社落地高度合理（y −5.5～−2.5）", player.global_position.y > -5.5 and player.global_position.y < -2.5)
	var r2: Dictionary = await _walk_to(Vector3(AXIS_X, Y_COURT, Z_COURT), "shrine↑", "")
	print("[WALK] 上行 %s (遊戲時間 %.1f s, 路徑 %.1f m, 剩 %.1f m) 終點 %s" % [r2.reason, r2.game_seconds, r2.path_len, r2.distance, _v(player.global_position)])
	check("能從下平台走上石階回到境內：%s" % r2.reason, r2.arrived)
	check("上行終點高度 ≈ 境內（y > −1.6）", player.global_position.y > -1.6)

	for line in _log:
		print("[WALK]" + line)
	print("[WALK] failures=%d" % failures)
	quit(failures)
