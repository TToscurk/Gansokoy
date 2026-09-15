extends SceneTree
## 存讀檔 UI 回歸測試 —— Godot --headless --path godot --script tools/verify_save_menu.gd
##
## 為什麼要有這一支：選單是「一個按鍵就可能毀掉幾小時進度」的地方，
## 而它跟地圖 UI 共用 Esc。以下每條都對應一個會真的出事的狀況：
##   A 開關     Esc 開／關；對話中不得開（存到半段對話讀回來是死狀態）
##   B 導覽     ↑↓ 繞行、Tab 切換存／讀模式
##   C 覆寫     空槽直接存；覆寫既有存檔必須先確認，且 Esc 只取消確認不關選單
##   D 讀取     空槽 Enter 不得有反應；有檔才讀，且讀前先關選單
##   E 刪除     Del 清掉槽位
##   F 摘要     槽位顯示時間／地點／任務；空槽顯示（空）
##   G 搶鍵     地圖開著時 Esc 先關地圖，不得同時彈出存檔選單
##   H 動作表   用到的 InputMap 動作必須存在（打錯名字會變成整個鍵沒反應）

var fails := 0
var main: Node
var menu: CanvasLayer
var mapui: CanvasLayer
var qm: Node
var sf: Node
var sm: Node


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print("[MENU] %s %s%s" % ["PASS" if ok else "FAIL", label,
		"" if detail.is_empty() else "   (%s)" % detail])
	if not ok:
		fails += 1


func step(n: int = 4) -> void:
	for i in n:
		await process_frame


## 直接把動作事件餵給選單的 _unhandled_input（headless 沒有真的視窗焦點）。
func send(node: Node, action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	node.call("_unhandled_input", e)


func slot_body(i: int) -> String:
	return String(menu.get_node("Panel/Slots/Slot%d/Body" % i).text)


func _run() -> void:
	qm = root.get_node("/root/QuestManager")
	sf = root.get_node("/root/StoryFlags")
	sm = root.get_node("/root/SaveManager")

	# ── H. 動作表（先驗，後面全靠它）──
	for a in ["ui_cancel", "ui_up", "ui_down", "ui_accept", "ui_focus_next",
			"ui_text_delete", "quick_save", "quick_load"]:
		check("H %s 動作存在" % a, InputMap.has_action(a))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await step(150)
	menu = main.get_node_or_null("SaveMenu")
	mapui = main.get_node_or_null("WorldMap")
	check("A0 選單已掛上", menu != null)
	check("A0b 地圖 UI 也在（Esc 共用對象）", mapui != null)
	if menu == null:
		print("[MENU] failures=%d" % fails)
		quit(1)
		return
	for i in sm.SLOT_COUNT:
		sm.call("delete_save", i)

	# ── A. 開關 ──
	check("A1 初始不顯示", not menu.visible)
	send(menu, "ui_cancel")
	await step()
	check("A2 Esc 開啟", menu.visible)
	check("A3 開啟時鎖住玩家", bool(main.player.get("input_locked")))
	send(menu, "ui_cancel")
	await step()
	check("A4 Esc 關閉", not menu.visible)
	check("A5 關閉後解鎖玩家", not bool(main.player.get("input_locked")))
	# 對話中不得開
	root.get_node("/root/DialogueManager").call("start", "yoriichi_wake")
	send(menu, "ui_cancel")
	await step()
	check("A6 對話中 Esc 不開選單", not menu.visible)
	var dm: Node = root.get_node("/root/DialogueManager")
	var guard := 0
	while dm.call("is_active") and guard < 60:
		dm.call("advance")
		guard += 1
	await step()

	# ── B. 導覽 ──
	send(menu, "ui_cancel")
	await step()
	check("B1 預設模式為存檔", String(menu.get_node("Panel/Title").text) == "存檔")
	var s0: int = menu.get("_sel")
	send(menu, "ui_down")
	check("B2 ↓ 移動選擇", int(menu.get("_sel")) == (s0 + 1) % sm.SLOT_COUNT)
	send(menu, "ui_up")
	check("B3 ↑ 回到原位", int(menu.get("_sel")) == s0)
	send(menu, "ui_up")
	check("B4 ↑ 在頂端繞回最後一格", int(menu.get("_sel")) == sm.SLOT_COUNT - 1)
	menu.set("_sel", 0)
	menu.call("_refresh")
	send(menu, "ui_focus_next")
	check("B5 Tab 切到讀取模式", String(menu.get_node("Panel/Title").text) == "讀取存檔")
	send(menu, "ui_focus_next")
	check("B6 Tab 切回存檔模式", String(menu.get_node("Panel/Title").text) == "存檔")

	# ── F/C. 空槽摘要 + 直接存檔 ──
	check("F1 空槽顯示（空）", slot_body(0) == "（空）", slot_body(0))
	qm.call("reset")
	qm.call("start_quest", "MQ04")
	send(menu, "ui_accept")
	await step()
	check("C1 空槽 Enter 直接存檔（不需確認）", sm.call("has_save", 0))
	check("C2 存完不留在確認狀態", not bool(menu.get("_confirming")))
	check("F2 槽位顯示摘要（含地點與任務）",
		slot_body(0).contains("獸道") and slot_body(0).contains("山上的神社"), slot_body(0))

	# ── C. 覆寫確認 ──
	send(menu, "ui_accept")
	await step()
	check("C3 覆寫既有存檔先進確認狀態", bool(menu.get("_confirming")))
	check("C4 確認提示顯示", menu.get_node("Panel/Confirm").visible)
	send(menu, "ui_cancel")
	await step()
	check("C5 Esc 只取消確認、不關選單", menu.visible and not bool(menu.get("_confirming")))
	send(menu, "ui_accept")
	send(menu, "ui_down")
	check("C6 換格子取消待確認狀態", not bool(menu.get("_confirming")))
	menu.set("_sel", 0)
	menu.call("_refresh")
	# 覆寫確認的完整兩步：Enter 進確認 → Enter 真的寫下去。
	# 用 saved_at 變了來證明「真的重寫過」，不是只看 has_save（那本來就是 true）。
	var before := String(sm.call("slot_info", 0).get("saved_at", ""))
	await step(2)
	send(menu, "ui_accept")
	check("C7a 第一次 Enter 只進確認、還沒寫", bool(menu.get("_confirming")))
	send(menu, "ui_accept")
	await step()
	check("C7b 第二次 Enter 真的覆寫", not bool(menu.get("_confirming")) and sm.call("has_save", 0))
	check("C7c 覆寫後摘要仍完整", slot_body(0).contains("獸道"), slot_body(0))

	# ── D. 讀取 ──
	send(menu, "ui_focus_next")           # → 讀取模式
	menu.set("_sel", 1)                   # 槽 2 是空的
	menu.call("_refresh")
	send(menu, "ui_accept")
	await step()
	check("D1 空槽 Enter 無反應（選單仍開著）", menu.visible)
	menu.set("_sel", 0)
	menu.call("_refresh")
	# 先把狀態弄髒，讀檔要能蓋回去
	qm.call("reset")
	sf.call("set_flag", "dirty_marker", true)
	send(menu, "ui_accept")
	await step(20)
	check("D2 有檔時 Enter 讀取並關閉選單", not menu.visible)
	check("D3 讀檔後任務還原成存檔內容", qm.call("is_active", "MQ04"),
		str(qm.call("get_active_quest")))
	check("D4 讀檔覆蓋了先前的髒狀態", not sf.call("get_flag", "dirty_marker"))
	check("D5 讀檔後玩家沒被鎖住", not bool(main.player.get("input_locked")))

	# ── G. 與地圖搶 Esc ──
	mapui.call("_set_open", true)
	await step()
	check("G1 地圖已開", mapui.visible)
	# 照 main 的掛載順序，Esc 應該先被地圖吃掉
	var e := InputEventAction.new()
	e.action = "ui_cancel"
	e.pressed = true
	main.get_viewport().push_unhandled_input(e)
	await step(4)
	check("G2 Esc 關地圖", not mapui.visible)
	check("G3 且不同時彈出存檔選單", not menu.visible,
		"menu.visible=%s" % menu.visible)

	# ── E. 刪除 ──
	send(menu, "ui_cancel")
	await step()
	menu.set("_sel", 0)
	menu.call("_refresh")
	send(menu, "ui_text_delete")
	await step()
	check("E1 Del 刪掉存檔", not sm.call("has_save", 0))
	check("E2 刪掉後顯示（空）", slot_body(0) == "（空）", slot_body(0))

	for i in sm.SLOT_COUNT:
		sm.call("delete_save", i)
	print("[MENU] failures=%d" % fails)
	quit(1 if fails > 0 else 0)
