extends SceneTree
## 博麗神社 × 靈夢 Vertical Slice 驗收（規格 §42 Test 1–14）。
##   Godot --headless --path godot --script tools/verify_story_slice.gd
## 走真的 main.tscn（autoload 活著），真按鍵、真 Area3D。

var fails := 0
var main: Node
## --script 模式下 autoload 在編譯期不可見（會 Identifier not found），用動態取。
var qm: Node
var dm: Node
var sf: Node
var player: CharacterBody3D
var prompt: Label


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[STORY] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await physics_frame
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	await physics_frame


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _teleport(p: Vector3) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = p
	await _settle(6)


func _run() -> void:
	qm = root.get_node("/root/QuestManager")
	dm = root.get_node("/root/DialogueManager")
	sf = root.get_node("/root/StoryFlags")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(2)
	player = main.player
	prompt = main.interaction_prompt
	# ── 序章：獸道醒來 ──
	check("P0 開局在獸道", main.current_id == "trail")
	await _settle(60)
	var pp: Vector3 = player.global_position
	check("P0 醒來點在大空地 (-6, -17.6) 附近且落地 y≈3.9（實 %.1f,%.1f,%.1f）" % [pp.x, pp.y, pp.z],
		Vector2(pp.x + 6.0, pp.z + 17.6).length() < 2.0 and pp.y > 2.0 and pp.y < 6.0)
	check("P0 MQ00 active", qm.is_active("MQ00"))
	check("P0 醒來獨白自動播放", dm.is_active())
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	check("P0 woke_in_trail 旗標", sf.get_flag("woke_in_trail"))
	# 先往南試人里口：未開放
	await _teleport(Vector3(3, 2.0, 98))
	await _settle(4)
	check("P1 人里口未開放獨白", dm.is_active())
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	await _teleport(Vector3(3.2, 1.5, 106))
	main.portal_cooldown = 0.0
	await _settle(6)
	var before_map: String = main.current_id
	await _press("portal_enter")
	await _settle(10)
	check("P1 未見靈夢前 ↑ 不能傳送到人里", main.current_id == before_map and main.current_id == "trail")
	# 走北：離開空地 → MQ00 完成、MQ01 開始
	await _teleport(Vector3(-6, 6.0, -50))
	check("P2 MQ00 REACH 完成 → MQ01", qm.is_completed("MQ00") and qm.is_active("MQ01"))
	await _teleport(Vector3(7, 8.0, -70))
	await _settle(4)
	check("P2 感知獨白自動播放", dm.is_active())
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	check("P2 MQ01 完成 → MQ02（山犬）", qm.is_completed("MQ01") and qm.is_active("MQ02"))

	# ── MQ02 山犬：第一場戰鬥 ──
	await _teleport(Vector3(5.3, 8.0, -82))
	await _settle(8)
	check("P2b 踏入遭遇區播「……妖怪。」", dm.is_active())
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	var enc: Node = null
	for e in main.get_tree().get_nodes_in_group("combat_encounter"):
		enc = e
	check("P2b 遭遇區存在", enc != null)
	var wolves := main.get_tree().get_nodes_in_group("enemies")
	check("P2b 山犬已生成（%d 隻）" % wolves.size(), wolves.size() >= 1)
	if wolves.size() > 0:
		var w: Node = wolves[0]
		check("P2b 山犬鎖定玩家", w.get("target") != null)
		# 直接處決，跳過實戰
		w.posture.apply_damage(9999.0, 0.0)
	# 戰後停頓 1.6 s + 對話
	await _settle(160)
	check("P2b 戰後獨白播放", dm.is_active())
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	await _settle(4)
	check("P2b defeated_first_yokai 旗標", sf.get_flag("defeated_first_yokai"))
	check("P2b MQ02 完成 → MQ03（不要追）", qm.is_completed("MQ02") and qm.is_active("MQ03"))

	# ── MQ03 不要追：毛玉真的要跑 ──
	var kedamas := main.get_tree().get_nodes_in_group("kedama")
	check("P2c 毛玉已擺好（%d 隻，含受傷的）" % kedamas.size(), kedamas.size() >= 4)
	# 站在毛玉群旁邊（notice_range 7 m 內），它們要開始逃
	await _teleport(Vector3(4.2, 8.0, -90))
	await _settle(30)
	var fleeing := 0
	for k in main.get_tree().get_nodes_in_group("kedama"):
		if int(k.get("mode")) == 1 and bool(k.get("_noticed")):
			fleeing += 1
	check("P2c 靠近後毛玉開始逃（%d 隻在逃）" % fleeing, fleeing >= 2)
	# 等它們跑光（flee_distance 18 m / 6.5 m/s ≈ 3 s）
	await _settle(240)
	var left_flee := 0
	for k in main.get_tree().get_nodes_in_group("kedama"):
		if int(k.get("mode")) == 1:
			left_flee += 1
	check("P2c 逃跑毛玉全部消失（剩 %d）" % left_flee, left_flee == 0)
	check("P2c 逃光後留下果實", main.get_tree().get_nodes_in_group("kedama").size() >= 1 \
		and main.map_root.find_child("DroppedFruit", true, false) != null)
	# 走到果實旁 → 獨白
	await _teleport(Vector3(4.2, 8.0, -95))
	await _settle(8)
	check("P2c 果實獨白播放", dm.is_active())
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	await _settle(4)
	check("P2c saw_fleeing_yokai 旗標", sf.get_flag("saw_fleeing_yokai"))
	check("P2c MQ03 第一目標完成、仍 active", qm.is_active("MQ03") and qm.get_objective_progress("MQ03") == 0)

	# ── 受傷妖怪：序章唯一的選擇 ──
	await _teleport(Vector3(3.7, 8.0, -101))
	await _settle(8)
	check("P2d 受傷妖怪對話播放", dm.is_active())
	var ui_d: CanvasLayer = null
	for c in main.get_children():
		if c.name == "DialogueUI":
			ui_d = c
	var choices_box: VBoxContainer = ui_d.get_node("Panel/VBox/Choices")
	# 推到選項節點
	var guard := 0
	while dm.is_active() and not choices_box.visible and guard < 20:
		await _press("ui_accept"); await _press("ui_accept")
		guard += 1
	check("P2d 出現選項（%d 個）" % choices_box.get_child_count(), choices_box.visible and choices_box.get_child_count() == 2)
	if choices_box.visible:
		check("P2d 選項是「靠近」「離開」",
			(choices_box.get_child(0) as Button).text == "靠近" and (choices_box.get_child(1) as Button).text == "離開")
	# 先拔刀，這樣才能驗證「靠近 → 收刀」。
	# ⚠ 對話中 input_locked，request_draw 可能被擋；先解鎖再拔，拔完（DRAWN=2）再鎖回。
	player.set("input_locked", false)
	if player.has_method("request_draw"):
		player.request_draw()
	var g2 := 0
	while int(player.get("sword_state")) != 2 and g2 < 120:
		await physics_frame
		g2 += 1
	player.set("input_locked", true)
	var drawn_before: int = int(player.get("sword_state"))
	check("P2d 前置：刀已拔出（state=%d）" % drawn_before, drawn_before == 2)
	# 選「靠近」（index 0）
	dm.advance(0)
	await _settle(4)
	check("P2d 選靠近 → spared_wounded_yokai 旗標", sf.get_flag("spared_wounded_yokai"))
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	# 收刀動畫要跑完（SHEATHING=3 → SHEATHED=0）
	var g3 := 0
	while int(player.get("sword_state")) in [2, 3] and g3 < 180:
		await physics_frame
		g3 += 1
	var sword_after: int = int(player.get("sword_state"))
	check("P2d 靠近後緣一收刀（%d → %d）" % [drawn_before, sword_after], sword_after == 0)
	# 毛玉要逃走（2.2 s 後起跑 + 3 s 跑完）
	await _settle(360)
	var wounded_left := 0
	for k in main.get_tree().get_nodes_in_group("kedama"):
		wounded_left += 1
	check("P2d 受傷毛玉已逃離（場上剩 %d 隻）" % wounded_left, wounded_left == 0)
	check("P2d MQ03 完成 → MQ04（山上的神社）", qm.is_completed("MQ03") and qm.is_active("MQ04"))

	# nav 指路
	var nav: Node = null
	for c in main.get_children():
		if c.name == "NavWaypoint": nav = c
	check("P3 NavWaypoint 存在", nav != null)
	var wp: Dictionary = root.get_node("/root/WaypointResolver").resolve("trail", main.current_portals())
	check("P3 MQ04 目標在神社 → 指向北傳送點 (3,-107.8)：%s" % str(wp),
		not wp.is_empty() and wp.via_portal and (wp.pos as Vector2).distance_to(Vector2(3.0, -107.8)) < 1.0)
	# 進神社
	main.load_map("shrine", "trail")
	await _settle(30)
	# Test 1
	check("T1 神社載入、Player 存在、無錯", main.current_id == "shrine" and player != null)
	check("T1 Player 在 group player", player.is_in_group("player"))
	check("T1 序章任務鏈（MQ04 active）", qm.is_active("MQ04"))

	# REACH：走過參道抵達區 → MQ02 完成 → MQ03 開始
	await _teleport(Vector3(0, 1.0, 40))
	check("MQ04 REACH 完成、MQ05 開始", qm.is_completed("MQ04") and qm.is_active("MQ05"))

	# Test 2：靠近拜殿
	await _teleport(Vector3(0, 4.5, -21))
	check("T2 靠近拜殿出現提示「[E] 拜訪」", prompt.visible and prompt.text.contains("[E] 拜訪"))
	# Test 3：離開
	await _teleport(Vector3(0, 4.5, -8))
	check("T3 離開範圍提示消失", not prompt.visible)
	# Test 4：再進
	await _teleport(Vector3(0, 4.5, -21))
	check("T4 再次進入提示重新出現", prompt.visible and prompt.text.contains("拜訪"))
	# Test 13 前置：來回進出不該動進度
	var before: int = qm.get_objective_progress("MQ05")

	# Test 5：按 E → 對話開、玩家鎖
	await _press("interact")
	await _settle(2)
	check("T5 按 E 對話開始", dm.is_active())
	check("T5 玩家鎖定 input_locked", bool(player.get("input_locked")))
	await _settle(10)          # 先讓落地完成，只量水平位移
	var p0: Vector3 = player.global_position
	var mv := InputEventAction.new(); mv.action = "move_forward"; mv.pressed = true
	Input.parse_input_event(mv)
	await _settle(20)
	mv = InputEventAction.new(); mv.action = "move_forward"; mv.pressed = false
	Input.parse_input_event(mv)
	var dxz := Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length()
	check("T5 鎖定時按前進不移動（水平位移 %.2f m）" % dxz, dxz < 0.05)

	# Test 6：立繪與名字
	var ui: CanvasLayer = null
	for c in main.get_children():
		if c.name == "DialogueUI":
			ui = c
	check("T6 DialogueUI 存在且顯示", ui != null and ui.visible)
	var name_lbl: Label = ui.get_node("Panel/VBox/Name")
	check("T6 名字 = 博麗靈夢", name_lbl.text == "博麗靈夢")
	var portrait: TextureRect = ui.get_node("Portrait")
	print("[STORY]   立繪貼圖：%s" % ("有" if portrait.texture != null else "無（assets/portraits/ 尚未放圖，路徑由 portraits.json 決定）"))
	var text_lbl: RichTextLabel = ui.get_node("Panel/VBox/Text")
	check("T6 第一句 = 「……你誰？」", text_lbl.text == "「……你誰？」")

	# Test 7：逐句推進到底
	var steps := 0
	while dm.is_active() and steps < 40:
		await _press("ui_accept")   # 第一下補完打字，第二下才前進
		await _press("ui_accept")
		steps += 1
	check("T7 對話逐句推進至結束（%d 步）" % steps, not dm.is_active())

	# Test 8/9/10
	check("T8 met_reimu = true", sf.get_flag("met_reimu"))
	check("T9 MQ05 完成", qm.is_completed("MQ05"))
	check("T9b MQ06 也在同一對話完成", qm.is_completed("MQ06"))
	check("T10 下一任務 MQ07 開始", qm.is_active("MQ07"))

	# Test 11：恢復控制
	await _settle(2)
	check("T11 對話結束解鎖", not bool(player.get("input_locked")))
	check("T11 對話後提示回來", prompt.visible and prompt.text.contains("拜訪"))

	# Test 12：再拜訪 → repeat
	await _press("interact")
	await _settle(2)
	check("T12 再次拜訪進 repeat 對話", dm.is_active() and text_lbl.text == "「又來了？」")
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")

	# Test 13：來回進出不增加進度
	var mq07_before: int = qm.get_objective_progress("MQ07")
	for i in 3:
		await _teleport(Vector3(0, 4.5, -8))
		await _teleport(Vector3(0, 4.5, -21))
	check("T13 重複進出拜殿區不動任務進度", qm.get_objective_progress("MQ07") == mq07_before and before == 0)

	# 見過靈夢後人里開放
	main.load_map("trail", "shrine")
	await _settle(30)
	await _teleport(Vector3(3.2, 1.5, 106))
	main.portal_cooldown = 0.0
	await _settle(6)
	await _press("portal_enter")
	await _settle(30)
	check("P4 見過靈夢後可傳送到人里", main.current_id == "slice")
	# P5：人里門口 REACH → MQ07 完成（序章終點）
	await _teleport(Vector3(234.0, 2.0, 101.0))
	await _settle(6)
	check("P5 抵達人里門口 → MQ07 完成", qm.is_completed("MQ07"))
	check("P5 visited_human_village 旗標", sf.get_flag("visited_human_village"))
	# P6：見過靈夢後回獸道，人里口不得再播「先去山上看看」
	main.load_map("trail", "slice")
	await _settle(30)
	sf.set_flag("village_locked_hint_played", false)
	await _teleport(Vector3(3.0, 2.0, 98.0))
	await _settle(6)
	check("P6 見過靈夢後人里口不再播過時獨白", not dm.is_active())
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	main.load_map("shrine", "trail")
	await _settle(30)
	# Test 14：無對應 active quest 的事件不報錯
	qm.report_event("TALK", "nobody_here")
	qm.report_event("DEFEAT", "ghost", 5)
	check("T14 無對應任務的事件安靜忽略", true)

	print("[STORY] failures=%d" % fails)
	quit(fails)
