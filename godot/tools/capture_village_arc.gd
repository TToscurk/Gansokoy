extends SceneTree
## 批次 A（MQ08／MQ09）實機取證 —— 提示字與對話框的畫面。
##   Godot --path godot --script tools/capture_village_arc.gd
##
## 這裡**不擺自製相機**（寺子屋那一組例外，見下）：用遊戲自己的視角
## （玩家相機＋Main 的 UI），拍到的就是玩家真正會看到的東西。
##
## 覆核對象（依 .hermes.md 視覺專權，這裡只到 ART_REVIEW）：
##   - 村門守衛在 MQ08 之前完全沉默，進任務後才亮提示
##   - 慧音的對話框名字與「半人半獸」那句所在的段落
##   - 互動區站位（寺子屋南牆外）走起來是否合理
##
##  兩個踩過的坑，寫在這裡免得下次重踩：
##   1. 開場獨白（OpeningFade → yoriichi_wake）會自己演 3.6 秒後起對話。
##      不先把它讀完，後面每一次 advance 都在推**那一段**，守衛的 TALK 節點
##      永遠走不到 —— 看起來就像「互動區壞了」。
##   2. 對話 UI 吃 unhandled input（滑鼠左鍵＝推進）。取證期間把它關掉，
##      免得使用者剛好在桌面上點一下就把對話跳掉，整輪取證作廢。

const OUT := "D:/神社/shrine/shots2/village_arc_batchA_20260916/"

var _main: Node
var _dm: Node
var _qm: Node
var _t0 := 0


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _shoot(tag: String) -> void:
	# 打字機效果約 40 字/秒；先等它把這一句打完再拍，否則截圖會停在半句話。
	await _wait(24)
	var img := _main.get_viewport().get_texture().get_image()
	var path := OUT + tag + ".png"
	img.save_png(path)
	print("[SHOT] %s  ← %s" % [path, _line()])


## 目前對話框顯示的那一句（沒對話時回空）
func _line() -> String:
	if not _dm.call("is_active"):
		return "（沒有對話）"
	var nodes: Dictionary = _dm.get("_nodes")
	var cur: String = String(_dm.get("_current"))
	if not nodes.has(cur):
		return ""
	var n: Dictionary = nodes[cur]
	return "%s：%s" % [String(n.get("speaker", "")), String(n.get("text", ""))]


## 把目前對話推掉（含選項一律選第一項）
func _drain_dialogue(guard: int = 200) -> void:
	var n := 0
	while _dm.call("is_active") and n < guard:
		_dm.call("advance", 0)
		n += 1
		await _wait(2)


## 推進到某一句出現為止；回傳最後看到的那一句
func _advance_until(needle: String, max_steps: int = 25) -> String:
	var last := ""
	for i in max_steps:
		if not _dm.call("is_active"):
			break
		_dm.call("advance", 0)
		await _wait(4)
		last = _line()
		if last.contains(needle):
			return last
	return last


func _obj(qid: String) -> String:
	return str(_qm.get("_progress").get(qid, "（無）"))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _wait(4)
	_qm = root.get_node("/root/QuestManager")
	_dm = root.get_node("/root/DialogueManager")
	_t0 = Time.get_ticks_msec()
	_dm.connect("line_shown", func(s: String, _p: Texture2D, txt: String, ch: PackedStringArray) -> void:
		print("[LINE] +%6d ms  %s｜%s%s" % [Time.get_ticks_msec() - _t0, s, txt,
			"  選項=%s" % str(ch) if ch.size() > 0 else ""]))
	_dm.connect("dialogue_ended", func(id: String) -> void:
		print("[LINE] +%6d ms  ── 對話結束 %s" % [Time.get_ticks_msec() - _t0, id]))
	# 對話 UI 不得吃取證期間的雜訊輸入
	for n in _main.find_children("*", "CanvasLayer", true, false):
		var sc = n.get_script()
		if sc != null and String(sc.resource_path).ends_with("dialogue_ui.gd"):
			n.set_process_unhandled_input(false)
			print("[SHOT] 已停用 DialogueUI 的 unhandled input（取證用）")

	_main.load_map("slice", "trail")
	await _wait(120)
	var player = _main.get_node_or_null("Player")
	if player == null:
		print("[SHOT] 找不到 Player")
		quit(1)
		return
	print("[SHOT] 抵達人里 %s on_floor=%s" % [str(player.global_position), str(player.is_on_floor())])

	# 開場獨白：遊戲自己演的（OpeningFade 淡入完 → main 起 yoriichi_wake）。
	#  實測它要 **12.7 秒**才出生：load_map 本身擋掉約 9 秒，淡入才開始跑。
	#   前兩輪取證就是在這裡失敗的 —— 等太短，獨白在我按 E 的同一瞬間出生，
	#   start("village_gatekeeper") 因為「已有對話」被拒，之後每一次 advance
	#   都在推獨白，守衛的 TALK 節點永遠走不到，看起來像互動區壞掉。
	var waited := 0
	while not _dm.call("is_active") and waited < 1800:
		await _wait(10)
		waited += 10
	if _dm.call("is_active"):
		print("[SHOT] 等到開場獨白（約 %.1f s）：%s" % [float(waited) / 60.0, _line()])
	else:
		print("[SHOT] 等了 %.0f 幀沒有開場獨白（可能被跳過）" % waited)
	await _drain_dialogue()
	print("[SHOT] 獨白結束，woke_in_trail=%s" % str(root.get_node("/root/StoryFlags").call("get_flag", "woke_in_trail")))

	var guard = _main.find_child("村門守衛", true, false)
	var keine = _main.find_child("寺子屋慧音", true, false)
	var arrive = _main.find_child("寺子屋抵達", true, false)
	print("[SHOT] 互動區 guard=%s keine=%s arrive=%s" % [guard != null, keine != null, arrive != null])

	# ─ 1. MQ08 之前：守衛必須沉默 ──
	player.global_position = Vector3(240, 2.2, 92)
	await _wait(45)
	print("[SHOT] MQ08 之前守衛 prompt=「%s」" % String(guard.call("prompt_text")))
	await _shoot("01_gate_before_mq08")

	# ── 2. 走進村門 → MQ07 完成、MQ08 接手 → 提示亮起 ──
	_qm.call("start_quest", "MQ07")
	_qm.call("report_event", "REACH", "human_village_gate")
	await _wait(20)
	print("[SHOT] MQ08 之中守衛 prompt=「%s」" % String(guard.call("prompt_text")))
	await _shoot("02_gate_prompt_mq08")

	# ── 3. 按 E：守衛對話 ─
	guard.call("interact")
	await _wait(40)
	print("[SHOT] 守衛對話開場：%s" % _line())
	await _shoot("03_gate_dialogue_opening")
	# 推到「那就在這等著。」—— TALK 事件就在這一句的節點上
	var talk_line := await _advance_until("等著")
	print("[SHOT] 守衛對話 TALK 節點：%s" % talk_line)
	await _shoot("04_gate_dialogue_talk_event")
	await _drain_dialogue()
	print("[SHOT] 守衛對話結束，MQ08=%s" % _obj("MQ08"))

	# ─ 4. 寺子屋南側：抵達區站位與慧音的位置 ──
	#  這一組用自製相機取景：玩家相機跟在角色背後，看不到「站在哪裡」。
	#  相機只換視角，UI（提示字／對話框）照樣是遊戲自己的。
	var cam := Camera3D.new()
	_main.add_child(cam)
	cam.global_position = Vector3(315, 5.0, 66)
	cam.look_at(Vector3(315, 2.5, 40), Vector3.UP)
	cam.current = true
	player.global_position = Vector3(315, 2.2, 50)
	for i in 4:
		await _wait(20)
		print("[SHOT]   寺子屋落點 %s on_floor=%s" % [str(player.global_position), str(player.is_on_floor())])
	print("[SHOT] 寺子屋 MQ08完成=%s 慧音 prompt=「%s」" % [
		str(_qm.call("is_completed", "MQ08")), String(keine.call("prompt_text"))])
	await _shoot("05_school_arrive_prompt")

	# ── 5. 慧音對話（spared 分支）──
	root.get_node("/root/StoryFlags").call("set_flag", "spared_wounded_yokai", true)
	keine.call("interact")
	await _wait(40)
	print("[SHOT] 慧音對話開場：%s" % _line())
	await _shoot("06_keine_opening")
	var key_line := await _advance_until("半人半獸")
	print("[SHOT] 慧音自白：%s" % key_line)
	await _shoot("07_keine_half_yokai")
	await _drain_dialogue()
	print("[SHOT] 慧音對話結束 MQ09完成=%s met_keine=%s" % [
		str(_qm.call("is_completed", "MQ09")),
		str(root.get_node("/root/StoryFlags").call("get_flag", "met_keine"))])
	await _shoot("08_after_keine")

	quit(0)