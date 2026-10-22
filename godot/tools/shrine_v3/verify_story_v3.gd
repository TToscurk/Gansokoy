extends SceneTree
## 博麗神社 v3 候選 × 靈夢初見（MQ04）整合驗收：真 main.tscn、真按鍵、真 Area3D、真對話與任務系統。
## 由 tools/verify_shrine_v3_story.gd 複製改寫（v2 檔不動）：id 改 shrine_v3；拜殿前站位改 (0,−15.8)（v3 拜殿中心在 z=−23，
## waypoints.json 的「拜殿」目標 (0,−21) 落在 v3 建物內，正式切換時要改成 (0,−15.5)；本測試只驗資料現況）。
##   godot --headless --path godot --script res://tools/shrine_v3/verify_story_v3.gd -- --map=shrine_v3
## 候選圖的 id 是 shrine_v3；waypoints.json 的目標仍指向舊 id "shrine"（正式切換才會改），
## 因此本測試在**記憶體內**把 WaypointResolver 的三個神社目標改指 shrine_v3——不動任何資料檔。
## 與 tools/verify_story_slice.gd（Test 1–14）同一套流程，只把傳送 y 改成「射線量到的地面高 + 1.0 m」。

var fails := 0
var main: Node
var qm: Node
var dm: Node
var sf: Node
var wr: Node
var player: CharacterBody3D
var prompt: Label


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[STORY3] %s %s" % ["PASS" if ok else "FAIL", label])
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


func _ground(x: float, z: float) -> float:
	var space := player.get_world_3d().direct_space_state
	# v3：從平台面上方 4 m 起射（拜殿向拜屋簷蓋在拜殿前站位上方，從 120 m 射會打到屋頂）
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 34.0, z), Vector3(x, -30.0, z))
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if hit.size() > 0 else NAN


func _teleport(x: float, z: float, dy: float = 1.0) -> void:
	var g := _ground(x, z)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(x, g + dy, z)
	await _settle(6)


func _dialogue_ui() -> CanvasLayer:
	for c in main.get_children():
		if c.name == "DialogueUI":
			return c
	return null


func _run() -> void:
	qm = root.get_node("/root/QuestManager")
	dm = root.get_node("/root/DialogueManager")
	sf = root.get_node("/root/StoryFlags")
	wr = root.get_node("/root/WaypointResolver")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(40)
	player = main.player
	prompt = main.interaction_prompt
	# 記憶體內改指：三個神社目標 → shrine_v3（不寫檔）
	var tg: Dictionary = wr._data.get("targets", {})
	for k in ["hakurei_shrine_approach", "reimu_hakurei_shrine", "reimu_gensokyo_intro"]:
		if tg.has(k):
			tg[k]["map"] = "shrine_v3"

	check("S1 載入候選圖 shrine_v3", main.current_id == "shrine_v3")
	check("S1 Player 存在且在 group player", player != null and player.is_in_group("player"))
	await _settle(30)
	check("S1 出生後站在地面（on_floor）", player.is_on_floor())
	var sp := player.global_position
	print("[STORY3]   出生點 (%.1f, %.1f, %.1f)" % [sp.x, sp.y, sp.z])
	check("S1 出生在南側入口（z>60）", sp.z > 60.0)
	# 開場鎖定（若有）先解除，這個測試不驗序章淡入
	player.set("input_locked", false)
	var fade: Node = main.get_node_or_null("OpeningFade")
	if fade != null:
		fade.queue_free()
	while dm.is_active():
		await _press("ui_accept")
		await _press("ui_accept")

	# ── 任務快轉：MQ00–MQ03 完成 → MQ04 ──
	qm.reset()
	sf.reset() if sf.has_method("reset") else null
	qm.start_quest("MQ00")
	for q in ["MQ00", "MQ01", "MQ02", "MQ03"]:
		qm.complete_quest(q)
	await _settle(4)
	check("S2 MQ04 啟動", qm.is_active("MQ04"))
	var obj = qm.get_current_objective("MQ04")
	check("S2 MQ04 第一格＝REACH hakurei_shrine_approach", obj != null and obj.target_id == "hakurei_shrine_approach")
	var wp: Dictionary = wr.resolve("shrine_v3", main.current_portals())
	check("S2 指路：指向參道 (0,40)「山上的建築」：%s" % str(wp), not wp.is_empty() and not wp.via_portal and (wp.pos as Vector2).distance_to(Vector2(0, 40)) < 1.0)

	# ── REACH：走到石階下參道 ──
	await _teleport(0.0, 40.0)
	obj = qm.get_current_objective("MQ04")
	check("S3 REACH 後 MQ04 仍 active、等待靈夢", qm.is_active("MQ04") and obj != null and obj.target_id == "reimu_gensokyo_intro")
	wp = wr.resolve("shrine_v3", main.current_portals())
	check("S3 指路改指拜殿 (0,-21)：%s" % str(wp), not wp.is_empty() and (wp.pos as Vector2).distance_to(Vector2(0, -21)) < 1.0)

	# ── 靠近拜殿：提示 ──
	await _teleport(0.0, -15.8)
	check("S4 靠近拜殿出現「[E] 拜訪」", prompt.visible and prompt.text.contains("[E] 拜訪"))
	await _teleport(0.0, -8.0)
	check("S4 離開範圍提示消失", not prompt.visible)
	await _teleport(0.0, -15.8)
	check("S4 再進提示重新出現", prompt.visible and prompt.text.contains("拜訪"))
	var before: int = qm.get_objective_progress("MQ04")

	# ── 按 E：對話 ──
	await _press("interact")
	await _settle(2)
	check("S5 按 E 對話開始", dm.is_active())
	check("S5 玩家鎖定 input_locked", bool(player.get("input_locked")))
	await _settle(10)
	var p0: Vector3 = player.global_position
	var mv := InputEventAction.new()
	mv.action = "move_forward"
	mv.pressed = true
	Input.parse_input_event(mv)
	await _settle(20)
	mv = InputEventAction.new()
	mv.action = "move_forward"
	mv.pressed = false
	Input.parse_input_event(mv)
	var dxz := Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length()
	check("S5 鎖定時按前進不移動（水平位移 %.2f m）" % dxz, dxz < 0.05)
	var ui := _dialogue_ui()
	check("S6 DialogueUI 存在且顯示", ui != null and ui.visible)
	if ui != null:
		var name_plate: Node = ui.get_node("Box/Nameplate")
		check("S6 名字＝博麗靈夢", String(name_plate.get("speaker")) == "博麗靈夢")
		var text_lbl: RichTextLabel = ui.get_node("Box/Panel/VBox/Text")
		check("S6 第一句＝「……你誰？」", text_lbl.text == "「……你誰？」")
	var steps := 0
	while dm.is_active() and steps < 40:
		await _press("ui_accept")
		await _press("ui_accept")
		steps += 1
	check("S7 對話逐句推進至結束（%d 步）" % steps, not dm.is_active())
	check("S8 met_reimu 旗標", sf.get_flag("met_reimu"))
	check("S8 一場初見完成 MQ04", qm.is_completed("MQ04"))
	check("S8 下一任務 MQ07 開始", qm.is_active("MQ07"))
	await _settle(2)
	check("S9 對話結束解鎖", not bool(player.get("input_locked")))
	check("S9 對話後提示回來", prompt.visible and prompt.text.contains("拜訪"))
	await _press("interact")
	await _settle(2)
	ui = _dialogue_ui()
	var again_ok := false
	if ui != null and dm.is_active():
		again_ok = (ui.get_node("Box/Panel/VBox/Text") as RichTextLabel).text == "「又來了？」"
	check("S10 再拜訪進 repeat 對話「又來了？」", again_ok)
	while dm.is_active():
		await _press("ui_accept")
		await _press("ui_accept")
	var mq07_before: int = qm.get_objective_progress("MQ07")
	for i in 3:
		await _teleport(0.0, -8.0)
		await _teleport(0.0, -15.8)
	check("S11 重複進出拜殿區不動任務進度", qm.get_objective_progress("MQ07") == mq07_before and before == 0)

	# ── 回獸道再回來（出生／傳送）──
	var portal_xz := Vector2.INF
	for p in main.current_portals():
		if String(p.get("target", "")) == "trail":
			portal_xz = Vector2(float(p.x), float(p.z))
	check("S12 候選圖有通往獸道的傳送點：%s" % str(portal_xz), portal_xz != Vector2.INF)
	main.load_map("trail", "shrine_v3")
	await _settle(30)
	check("S12 換圖到獸道", main.current_id == "trail")
	main.load_map("shrine_v3", "trail")
	await _settle(30)
	check("S12 從獸道回候選圖並站在地面", main.current_id == "shrine_v3" and player.is_on_floor() and player.global_position.z > 60.0)

	print("[STORY3] failures=%d" % fails)
	quit(fails)
