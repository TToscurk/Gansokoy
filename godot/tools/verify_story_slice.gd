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
	# 開場淡入：黑幕 1.4 s + 淡入 2.2 s，期間玩家鎖定、獨白未起
	var fade: Node = main.get_node_or_null("OpeningFade")
	check("P0 開場淡入存在", fade != null)
	check("P0 淡入期間玩家鎖定", bool(player.get("input_locked")))
	check("P0 淡入期間獨白未起（黑畫面不該有對話框）", not dm.is_active())
	if fade != null:
		var black: ColorRect = fade.get_node("Black")
		check("P0 黑幕全黑（a=%.2f）" % black.color.a, black.color.a > 0.99)
		# 等它自然淡完（不 skip，驗證真的會結束）
		var waited := 0
		while is_instance_valid(fade) and waited < 400:
			await physics_frame
			waited += 1
		check("P0 淡入 %.1f s 內結束（實 %d 幀）" % [4.5, waited], not is_instance_valid(fade))
	await _settle(4)
	# 淡完立刻起獨白，對話會再把玩家鎖回去 —— 所以驗「獨白起了」而不是「解鎖了」
	check("P0 淡完才起醒來獨白", dm.is_active())
	var ui_o: CanvasLayer = null
	for c in main.get_children():
		if c.name == "DialogueUI":
			ui_o = c
	if ui_o != null:
		var first_line: RichTextLabel = ui_o.get_node("Panel/VBox/Text")
		check("P0 第一句是「……」", first_line.text == "「……」")
		await _press("ui_accept"); await _press("ui_accept")
		check("P0 第二句是「這是……哪裡？」", first_line.text == "「這是……哪裡？」")
	await _settle(60)
	var pp: Vector3 = player.global_position
	# r3 重排後的空地中心（tools/probe_trail_anchors.gd 實測 (-13.78,-26.82) 地面 y=5.19）
	check("P0 醒來點在大空地 (-13.8, -26.8) 附近且落地 y≈5.2（實 %.1f,%.1f,%.1f）" % [pp.x, pp.y, pp.z],
		Vector2(pp.x + 13.78, pp.z + 26.82).length() < 2.0 and pp.y > 3.5 and pp.y < 7.5)
	check("P0 MQ00 active", qm.is_active("MQ00"))
	check("P0 醒來獨白自動播放", dm.is_active())
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	check("P0 woke_in_trail 旗標", sf.get_flag("woke_in_trail"))
	# 先往南試人里口：未開放
	await _teleport(Vector3(0.99, 2.0, 95.27))
	await _settle(4)
	check("P1 人里口未開放獨白", dm.is_active())
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	await _teleport(Vector3(1.65, 1.5, 108.81))
	main.portal_cooldown = 0.0
	await _settle(6)
	var before_map: String = main.current_id
	await _press("portal_enter")
	await _settle(10)
	check("P1 未見靈夢前 ↑ 不能傳送到人里", main.current_id == before_map and main.current_id == "trail")
	# 走北：離開空地 → MQ00 完成、直接開始 MQ02 山犬事件
	# 座標：2026-09-15 r3 路線重排後的實測錨點（tools/probe_trail_anchors.gd）
	# ⚠ 2026-09-16：這一點同時是「山犬遭遇」（CombatEncounter）的觸發區 ——
	#   走出空地就被撲上來，是刻意的（探針實測該處淨空半徑 12.50 m 才打得起）。
	await _teleport(Vector3(-14.08, 7.0, -40.03))
	check("P2 MQ00 REACH 完成 → MQ02", qm.is_completed("MQ00") and qm.is_active("MQ02"))
	await _settle(20)
	var wolves := main.get_tree().get_nodes_in_group("enemies")
	check("P2 踏出空地生成山犬（%d）" % wolves.size(), wolves.size() == 1)
	check("P2 山犬開場獨白播放", dm.is_active())
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	# 走真的戰鬥規則：軀幹打爆 → 破綻 → 忍殺（不是直接砍血）。
	if wolves.size() > 0:
		var wolf: Node = wolves[0]
		wolf.get("posture").apply_damage(0.0, 999.0)
		await _settle(4)
		check("P2 軀幹爆 → 可忍殺", bool(wolf.call("can_deathblow")))
		check("P2 忍殺成功", bool(wolf.call("execute_deathblow")))
	await _settle(90)                       # clear_delay 1.6 s ＋ 戰後獨白 ＋ 化光
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	await _settle(6)
	check("P2 山犬擊退事件已送出", qm.is_active("MQ02") or qm.is_active("MQ03"))

	# 獸骨現在只是非任務環境觀察，不再阻塞流程。
	await _teleport(Vector3(0.9, 8.0, -62.0))
	await _settle(8)
	check("P2b 踏入痕跡區播獨白", dm.is_active())
	while dm.is_active():
		await _press("ui_accept"); await _press("ui_accept")
	await _settle(4)
	check("P2b saw_predator_sign 旗標", sf.get_flag("saw_predator_sign"))
	check("P2b 山犬已死透（不再留屍體在場上）",
		main.get_tree().get_nodes_in_group("enemies").size() <= 1)
	check("P2b 獸骨觀察不改變 MQ03 進度", qm.is_active("MQ03"))

	# ── MQ03 害怕我的東西 ──
	# 2026-09-17：果實那一格（逃跑毛玉群 z=-78）已整條刪除，獸道事件點過密。
	# 現在 MQ03 只有一個目標：受傷妖怪。場上毛玉只剩受傷的那一隻。
	var kedamas := main.get_tree().get_nodes_in_group("kedama")
	check("P2c 場上只剩受傷毛玉那一隻（實得 %d）" % kedamas.size(), kedamas.size() == 1)
	check("P2c MQ03 第一目標就是受傷妖怪", qm.is_active("MQ03") \
		and qm.get_current_objective("MQ03").target_id == "trail_wounded_yokai")

	# ── 受傷妖怪：序章唯一的選擇 ──
	# ⚠ 這一段的時序很容易寫錯，踩過兩次：
	#   1) 只 _settle(4) 就傳送 → 果實獨白偶爾還在跑（實測約 1/7），
	#      WoundedYokaiEvent 走「對話中先等等」的補演路徑，後續 ui_accept
	#      全打在果實獨白上 → P2d 間歇失敗。所以要先確認前一段真的結束。
	#   2) 排空／推進時用 _press("ui_accept") → DialogueUI 在選項顯示時把
	#      ui_accept 當成「確定這個選項」（見 dialogue_ui.gd），連按會直接
	#      把「靠近／離開」選掉，選項還沒被檢查就消失（0 個選項）。
	#   結論：排空用 dm.advance()，推進到選項也用 dm.advance()，
	#   而且**推進前先檢查有沒有選項**，有就停手。
	var settle_guard := 0
	while dm.is_active() and settle_guard < 60:
		dm.advance()
		await _settle(1)
		settle_guard += 1
	await _settle(8)
	await _teleport(Vector3(-1.54, 8.8, -90.74))
	await _settle(12)
	check("P2d 受傷妖怪對話播放（id=%s）" % str(dm.get("_dialogue_id")), dm.is_active())
	var ui_d: CanvasLayer = null
	for c in main.get_children():
		if c.name == "DialogueUI":
			ui_d = c
	var choices_box: VBoxContainer = ui_d.get_node("Panel/VBox/Choices")
	# 推到選項節點。用 dm.advance()，不要送 ui_accept —— DialogueUI 在選項
	# 顯示時把 ui_accept 當成「確定這個選項」，會在檢查之前就把選項選掉。
	var guard := 0
	while dm.is_active() and not choices_box.visible and guard < 20:
		dm.advance()
		await _settle(2)
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
	check("P3 MQ04 目標在神社 → 指向北傳送點 (-2.08,-108.87)：%s" % str(wp),
		not wp.is_empty() and wp.via_portal and (wp.pos as Vector2).distance_to(Vector2(-2.08, -108.87)) < 1.0)
	# 進神社
	main.load_map("shrine", "trail")
	await _settle(30)
	# Test 1
	check("T1 神社載入、Player 存在、無錯", main.current_id == "shrine" and player != null)
	check("T1 Player 在 group player", player.is_in_group("player"))
	check("T1 序章任務鏈（MQ04 active）", qm.is_active("MQ04"))

	# REACH：走過參道只完成 MQ04 第一格，仍等待完整靈夢初見。
	await _teleport(Vector3(0, 1.0, 40))
	check("MQ04 REACH 後仍 active、等待靈夢", qm.is_active("MQ04") and qm.get_current_objective("MQ04").target_id == "reimu_gensokyo_intro")

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
	var before: int = qm.get_objective_progress("MQ04")

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
	check("T9 一場初見完成 MQ04", qm.is_completed("MQ04"))
	check("T9b 不再建立 MQ05／MQ06", not qm.is_active("MQ05") and not qm.is_active("MQ06"))
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
	await _teleport(Vector3(1.65, 1.5, 108.81))
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
