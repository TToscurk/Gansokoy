extends "res://tools/verify_walk_shrine_to_village.gd"
## 博麗神社 r3 實走測試：真的用角色控制器從獸道入口走到各區。
##   Godot --headless --path godot --script tools/verify_shrine_v2_walk.gd
## 沿用 verify_walk_shrine_to_village.gd 的轉向／繞行／卡住偵測，只換路線與檢查點。
## 路線：南端傳送點落點 → 參道 → 石階腳 → 石階（逐段）→ 鳥居 → 手水舍 → 賽錢箱前（拜訪區）→ 倉庫前 → 池畔 → 拜殿後 → 櫻花林 → 回石階頂 → 下石階 → 傳送區回獸道

const MAP_ID := "shrine_v2"

# [標籤, x, z, 預期地面 y（容差 ±1.2）, 說明]
const ROUTE := [
	["參道中段", 3.2, 52.0, -0.8],
	["石階腳", 0.0, 34.5, 0.0],
	["石階 z=31", 0.0, 31.0, -999.0],
	["石階 z=28", 0.0, 28.0, -999.0],
	["石階 z=25", 0.0, 25.0, -999.0],
	["石階 z=22", 0.0, 22.0, -999.0],
	["石階 z=19", 0.0, 19.0, -999.0],
	["石階 z=16", 0.0, 16.0, -999.0],
	["石階 z=13", 0.0, 13.0, -999.0],
	["石階 z=10", 0.0, 10.0, -999.0],
	["石階 z=7", 0.0, 7.0, -999.0],
	["石階頂", 0.0, 5.5, 8.32],
	["鳥居下", 0.0, 1.0, 8.32],
	["手水舍前", -8.6, -3.0, 8.32],
	["賽錢箱前（拜訪區）", 0.0, -21.0, 8.32],
	["倉庫前", 14.5, -19.0, 8.32],
	["拜殿東側", 8.0, -28.0, 8.32],
	["池畔西岸", 6.2, -35.0, 8.3],
	["拜殿後方", 0.0, -37.0, 8.32],
	["櫻花林西側", -10.0, -37.0, 8.32],
	["庭院西側", -10.0, -14.0, 8.32],
	["林徑 入口", -22.8, -11.2, -999.0],
	["林徑 西", -24.9, -14.5, -999.0],
	["林徑 西北", -25.3, -25.0, -999.0],
	["林徑 北西", -21.3, -39.6, -999.0],
	["林徑 北", -8.8, -47.5, -999.0],
	["林徑 北東端", 5.5, -52.0, -999.0],
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

	# 回程：走回石階頂 → 下石階 → 南端傳送區
	if failures == 0:
		var back := _portal_in_current_map("trail")
		check("有通往獸道的傳送區", back != Vector3.INF)
		# 回程沿林徑原路折返（也等於把林徑反向走一遍），再穿庭院西側回鳥居。基底轉向器只在胸口高度（0.9 m）射線，
		# 看不見膝蓋高的東西（賽錢箱 0.86 m、陰陽玉台石、木箱）；從北東端直線切向鳥居會頂進池畔台石／拜殿前的賽錢箱而卡住
		# （兩次實測），真玩家會繞，所以回程用林徑航點而不是一條直線。
		var legs := [
			["回林徑 北", Vector3(-8.8, 10.0, -47.5)],
			["回林徑 北西", Vector3(-21.3, 10.0, -39.6)],
			["回林徑 西北", Vector3(-25.3, 10.0, -25.0)],
			["回林徑 入口", Vector3(-22.8, 9.0, -11.2)],
			["回庭院西側", Vector3(-10.0, 8.32, -14.0)],
			["回鳥居前", Vector3(0.0, 8.32, -4.0)],
			["回石階頂", Vector3(0.0, 8.32, 4.5)],
			["石階腳", Vector3(0.0, 0.0, 34.5)],
		]
		for lg in legs:
			var res2: Dictionary = await _walk_to(lg[1], String(lg[0]), "")
			print("[WALK] %-8s %s (%.1f s, 路徑 %.1f m) 位置 %s" % [lg[0], res2.reason, res2.game_seconds, res2.path_len, _v(player.global_position)])
			check("到達 %s：%s" % [lg[0], res2.reason], res2.arrived)
		if back != Vector3.INF:
			var res3: Dictionary = await _walk_to(back, "傳送區", "trail")
			print("[WALK] 傳送區 %s (%.1f s, 路徑 %.1f m) 目前地圖 %s" % [res3.reason, res3.game_seconds, res3.path_len, main.current_id])
			check("走進傳送區換圖到獸道：%s" % res3.reason, res3.arrived and main.current_id == "trail")
	for line in _log:
		print("[WALK]" + line)
	print("[WALK] failures=%d" % failures)
	quit(failures)
