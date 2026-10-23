extends SceneTree
## UI 檢視截圖（ART_REVIEW 用）：對話框尺寸、任務追蹤＋指路提示的實機畫面。
##   <godot_console.exe> --path godot --script res://tools/_shot_ui_review.gd
##
## ⚠ --script 模式下 autoload 在 _init 當下尚未就緒，必須 call_deferred。
## ⚠ 不開 --headless：要真的畫出畫面才有像素可讀。
## ⚠ 跑之前把 DialogueUI 的 _unhandled_input 關掉：桌面上任何一次點擊都會推進對話。
const OUT := "D:/神社/shrine/work/shots/ui_review/"

var _main: Node
var _dm: Node
var _qm: Node
var _sf: Node
var _last_len := 0


func _on_line(_speaker: String, _p: Texture2D, text: String, _c: PackedStringArray) -> void:
	_last_len = text.length()


func _init() -> void:
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _shot(name: String) -> void:
	# 打字機沒跑完就存圖會拍到半句；另外等真正的 present 才讀得到像素。
	await _settle(40)
	await RenderingServer.frame_post_draw
	await process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	print("[SHOT] %s  %dx%d" % [name, img.get_width(), img.get_height()])


func _report_geometry(tag: String) -> void:
	var ui := root.find_child("DialogueUI", true, false)
	if ui == null:
		print("[GEO] %s 找不到 DialogueUI" % tag)
		return
	var panel: Control = ui.find_child("Panel", true, false)
	var g := root.get_viewport().get_visible_rect().size
	print("[GEO] %s viewport=%s panel pos=%s size=%s (%.1f%% x %.1f%%) name_h=%d text_h=%d hint_h=%d" % [
		tag, str(g), str(panel.global_position), str(panel.size),
		100.0 * panel.size.x / g.x, 100.0 * panel.size.y / g.y,
		int((ui.find_child("Name", true, false) as Control).size.y),
		int((ui.find_child("Text", true, false) as Control).size.y),
		int((ui.find_child("NextHint", true, false) as Control).size.y)])
	var vbox := ui.find_child("VBox", true, false) as VBoxContainer
	for c in vbox.get_children():
		var cc := c as Control
		print("      [VBox] %s visible=%s pos=%s size=%s vflags=%d" % [
			cc.name, str(cc.visible), str(cc.position), str(cc.size), cc.size_flags_vertical])


func _run() -> void:
	_dm = root.get_node("/root/DialogueManager")
	_qm = root.get_node("/root/QuestManager")
	_sf = root.get_node("/root/StoryFlags")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(6)
	var ui := root.find_child("DialogueUI", true, false)
	if ui != null:
		ui.set_process_unhandled_input(false)
		# 打字機要在短時間內跑完才有整句可拍；直接關掉逐字（t=0 → 立即全顯示）
		ui.set("typewriter_cps", 0.0)
	var day := root.get_node_or_null("/root/DayNight")
	if day != null:
		day.set("flowing", false)
		day.call("set_hour", 11.0)

	_main.load_map("slice", "trail")
	await _settle(90)

	# A：純遊戲畫面 —— 任務追蹤（右上）＋指路浮標／邊緣箭頭
	_qm.call("reset")
	_sf.call("reset")
	_qm.call("start_quest", "MQ04")
	await _settle(400)      # 等「新的委託」橫幅淡完，拍常駐狀態
	print("[GEO] tracker Box=%s Objective=%s visible=%s" % [
		str((root.find_child("QuestTracker", true, false) as Node).get_node("Box").get_rect()),
		str((root.find_child("QuestTracker", true, false) as Node).get_node("Box/Objective").get_rect()),
		str((root.find_child("QuestTracker", true, false) as Node).get_node("Box").visible)])
	await _shot("a1_gameplay_hud")
	await _settle(60)
	# A2：換任務時的中央橫幅（3 秒內）
	_qm.call("start_quest", "MQ07")
	await _settle(20)
	await _shot("a2_quest_banner")
	await _settle(240)

	# B：最長台詞（小鈴 60 字）
	_dm.line_shown.connect(_on_line)
	var ok: Variant = _dm.call("start", "kosuzu_suzunaan")
	await _settle(20)
	await _drive_to()
	await _shot("b_dialogue_long")
	_report_geometry("b_dialogue_long")
	await _drain()

	# C：有選項（受傷妖怪）
	_dm.call("start", "yoriichi_wounded_yokai")
	await _settle(20)
	for i in 12:
		await _settle(4)
		var n: int = (root.find_child("DialogueUI", true, false)
			.find_child("Choices", true, false) as Control).get_child_count()
		if n > 0:
			break
		_dm.call("advance")
	await _shot("c_dialogue_choices")
	_report_geometry("c_dialogue_choices")
	await _drain()

	# D：塞一段 3 行長台詞，驗證面板會跟著長高（不是固定高度）
	_dm.call("start", "kosuzu_suzunaan")
	await _settle(20)
	var ui_d := root.find_child("DialogueUI", true, false)
	var txt := ui_d.find_child("Text", true, false) as RichTextLabel
	txt.text = "「這是一段刻意拉長到三行的測試台詞，用來確認對話框會隨文字長高，而不是固定一個很大的空白方框。這一段文字沒有經過對話管理員，只是把字串直接塞進節點，用來量測版面。」"
	await _settle(60)
	await _shot("d_dialogue_3lines")
	_report_geometry("d_dialogue_3lines")
	await _drain()
	await _settle(30)
	await _shot("e_after_dialogue")

	print("[SHOT] 完成（%s）" % str(ok))
	quit(0)


func _drive_to() -> void:
	# 停在「台詞夠長」的那一句，不再往下推（推到底會關掉對話框）
	for i in 40:
		if not _dm.call("is_active") or _last_len >= 45:
			break
		_dm.call("advance")
		await _settle(4)


func _drain() -> void:
	# ⚠ 選項節點不吃 advance(-1)：不帶索引會原地不動，對話永遠關不掉。
	for i in 80:
		if not _dm.call("is_active"):
			break
		var choices := root.find_child("DialogueUI", true, false).find_child("Choices", true, false) as Control
		var n := choices.get_child_count() if choices != null else 0
		_dm.call("advance", 0 if n > 0 else -1)
		await _settle(3)
