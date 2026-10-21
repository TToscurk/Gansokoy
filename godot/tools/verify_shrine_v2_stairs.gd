extends "res://tools/verify_walk_shrine_to_village.gd"
## 博麗神社 r3 實走測試：真的用角色控制器從獸道入口走到各區。
##   Godot --headless --path godot --script tools/verify_shrine_v2_walk.gd
## 沿用 verify_walk_shrine_to_village.gd 的轉向／繞行／卡住偵測，只換路線與檢查點。
## 路線：南端傳送點落點 → 參道 → 石階腳 → 石階（逐段）→ 鳥居 → 手水舍 → 賽錢箱前（拜訪區）→ 倉庫前 → 池畔 → 拜殿後 → 櫻花林 → 回石階頂 → 下石階 → 傳送區回獸道

const MAP_ID := "shrine_v2"

# [標籤, x, z, 預期地面 y（容差 ±1.2）, 說明]
const ROUTE := [
	["石階腳", 0.0, 35.0, 0.0],
	["石階頂（一口氣）", 0.0, 3.0, 8.32],
]


func _settle(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _skip_dialogue() -> void:
	var dm: Node = root.get_node("/root/DialogueManager")
	var fade: Node = main.get_node_or_null("OpeningFade")
	var waited := 0
	while (fade != null and is_instance_valid(fade) and fade.is_inside_tree()) and waited < 600:
		await _settle(1)
		waited += 1
	while dm.is_active():
		var e := InputEventAction.new()
		e.action = "ui_accept"
		e.pressed = true
		Input.parse_input_event(e)
		await physics_frame
		e = InputEventAction.new()
		e.action = "ui_accept"
		e.pressed = false
		Input.parse_input_event(e)
		await physics_frame
	player.set("input_locked", false)
	await _settle(5)


func _area_inside(nm: String) -> bool:
	var n: Node = main.map_root.get_node_or_null("神社互動點/" + nm)
	if n == null:
		return false
	return bool(n.get("_player_inside"))


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.load_map(MAP_ID, "")
	await _settle(30)
	player = main.get_node_or_null("Player")
	check("the world loader booted", main != null and player != null)
	check("current map is " + MAP_ID, main.current_id == MAP_ID)
	if player == null or main.current_id != MAP_ID:
		print("[WALK] failures=%d" % failures)
		quit(maxi(failures, 1))
		return
	yaw = Node3D.new()
	main.add_child(yaw)
	player.input_yaw_node = yaw
	await _skip_dialogue()
	check("玩家未被鎖住", not bool(player.get("input_locked")))
	check("落點站在地面上", player.is_on_floor())
	print("[WALK] 落點 %s on_floor=%s" % [_v(player.global_position), str(player.is_on_floor())])

	var total := 0.0
	var t_game := 0.0
	for r in ROUTE:
		var tgt := Vector3(float(r[1]), float(r[3]), float(r[2]))
		var res: Dictionary = await _walk_to(tgt, String(r[0]), "")
		total += float(res.path_len)
		t_game += float(res.game_seconds)
		var py: float = player.global_position.y
		var ok_h: bool = float(r[3]) < -900.0 or absf(py - (float(r[3]) + 0.0)) < 1.6
		print("[WALK] %-10s %s (%.1f s, 路徑 %.1f m, 剩 %.1f m) 位置 %s on_floor=%s" % [
			r[0], res.reason, res.game_seconds, res.path_len, res.distance, _v(player.global_position), str(player.is_on_floor())])
		check("到達 %s：%s" % [r[0], res.reason], res.arrived)
		check("%s 高度合理（y=%.2f，預期 %.2f±1.6）" % [r[0], py, float(r[3])], ok_h)
		if String(r[0]).begins_with("賽錢箱前"):
			check("站在拜訪互動區內", _area_inside("拜殿拜訪"))
		if String(r[0]) == "參道中段":
			pass
		if not res.arrived:
			break
	print("[WALK] 去程總計 路徑 %.1f m，遊戲時間 %.1f s" % [total, t_game])

	for line in _log:
		print("[WALK]" + line)
	print("[WALK] failures=%d" % failures)
	quit(failures)
