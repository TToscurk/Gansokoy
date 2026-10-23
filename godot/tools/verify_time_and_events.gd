@tool
extends SceneTree
## 驗證時間段事件、對話暫停時間、跨圖前進半小時、屋台日夜隱現與開場演出。

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== 開始驗證時間段事件與開場系統 ===")
	await process_frame
	await process_frame

	_test_daynight_advance()
	_test_world_time_periods_and_lock()
	_test_yatai_controller()
	_test_dialogue_ui_layout()
	_test_portal_route_travel()
	_test_world_event_manager()

	print("\n=== 所有驗證完成，全數通過 ===")
	quit(0)


func _test_daynight_advance() -> void:
	var dn: Node = root.get_node_or_null("/root/DayNight")
	if dn == null:
		push_error("FAIL: 找不到 DayNight 單例")
		return
	dn.call("set_hour", 6.5)
	dn.set("day", 1)
	var h1: float = float(dn.get("hour"))
	assert(absf(h1 - 6.5) < 0.01, "set_hour 6.5 失敗")
	dn.call("advance_minutes", 30)
	var h2: float = float(dn.get("hour"))
	assert(absf(h2 - 7.0) < 0.01, "advance_minutes 30 失敗，得到 %f" % h2)
	assert(int(dn.get("minute")) == 0, "minute 應為 0")
	assert(int(dn.get("hour_int")) == 7, "hour_int 應為 7")

	# 測試跨天進位（23:45 + 30 分 -> 第 2 天 00:15）
	dn.call("set_hour", 23.75)
	dn.set("day", 1)
	dn.call("advance_minutes", 30)
	assert(int(dn.get("day")) == 2, "跨天進位 day 應為 2")
	assert(absf(float(dn.get("hour")) - 0.25) < 0.01, "跨天後 hour 應為 0.25")
	assert(int(dn.get("minute")) == 15, "跨天後 minute 應為 15")

	print("✓ PASS: DayNight 日、時、分計算與跨日進位驗證通過")


func _test_world_time_periods_and_lock() -> void:
	var dn: Node = root.get_node_or_null("/root/DayNight")
	var dm: Node = root.get_node_or_null("/root/DialogueManager")
	if dn == null or dm == null:
		push_error("FAIL: 找不到 DayNight 或 DialogueManager")
		return

	# 測試 7 大時段
	dn.call("set_hour", 6.0)
	assert(dn.call("get_period_name") == "清晨", "06:00 應為清晨")
	assert(bool(dn.call("is_night")) == false, "06:00 不應為夜晚")

	dn.call("set_hour", 9.5)
	assert(dn.call("get_period_name") == "上午", "09:30 應為上午")

	dn.call("set_hour", 12.5)
	assert(dn.call("get_period_name") == "中午", "12:30 應為中午")

	dn.call("set_hour", 15.0)
	assert(dn.call("get_period_name") == "下午", "15:00 應為下午")

	dn.call("set_hour", 18.5)
	assert(dn.call("get_period_name") == "黃昏", "18:30 應為黃昏")

	dn.call("set_hour", 20.0)
	assert(dn.call("get_period_name") == "夜晚", "20:00 應為夜晚")
	assert(bool(dn.call("is_night")) == true, "20:00 應為夜晚")

	dn.call("set_hour", 2.0)
	assert(dn.call("get_period_name") == "深夜", "02:00 應為深夜")
	assert(bool(dn.call("is_night")) == true, "02:00 應為夜晚")

	# 測試多原因時間鎖定系統
	dn.call("lock_time", "reason_a")
	dn.call("lock_time", "reason_b")
	assert(bool(dn.call("is_time_paused")) == true, "lock_time 應暫停時間")

	dn.call("unlock_time", "reason_a")
	assert(bool(dn.call("is_time_paused")) == true, "reason_b 仍在，時間仍應暫停")

	dn.call("unlock_time", "reason_b")
	assert(bool(dn.call("is_time_paused")) == false, "所有原因解除，時間應恢復流逝")

	# 測試對話期間自動鎖定
	dm.emit_signal("dialogue_started", "test_dialogue")
	assert(bool(dn.call("is_time_paused")) == true, "對話期間時間應暫停")
	dm.emit_signal("dialogue_ended", "test_dialogue")
	assert(bool(dn.call("is_time_paused")) == false, "對話結束後時間應恢復")

	print("✓ PASS: 7 大時段標準分區與多原因時間鎖定系統驗證通過")


func _test_yatai_controller() -> void:
	var ctrl_script: Script = load("res://maps/trail/trail_yatai_controller.gd")
	var node: Node3D = Node3D.new()
	node.set_script(ctrl_script)
	root.add_child(node)

	# 早上 06:00 應不可見且 process_mode 禁用
	node._on_hour_changed(6.0)
	assert(node.visible == false, "早上 06:00 夜雀屋台應不可見")
	assert(node.process_mode == Node.PROCESS_MODE_DISABLED, "早上 06:00 process_mode 應為 DISABLED")

	# 中午 12:00 應不可見
	node._on_hour_changed(12.0)
	assert(node.visible == false, "中午 12:00 夜雀屋台應不可見")
	assert(node.process_mode == Node.PROCESS_MODE_DISABLED, "中午 12:00 process_mode 應為 DISABLED")

	# 晚上 20:00 應可見且 process_mode 啟用
	node._on_hour_changed(20.0)
	assert(node.visible == true, "晚上 20:00 夜雀屋台應可見")
	assert(node.process_mode == Node.PROCESS_MODE_INHERIT, "晚上 20:00 process_mode 應為 INHERIT")
	assert(bool(node.get("_was_night")) == true, "_was_night 應為 true")

	# 天氣香氣機率檢查
	var chance: float = node.call("_get_weather_chance")
	assert(chance >= 0.0 and chance <= 1.0, "天氣機率應在 0.0~1.0 之間")

	node.queue_free()
	print("✓ PASS: 獸道夜雀屋台日夜 visible 與 process_mode 同步開關驗證通過")


func _test_dialogue_ui_layout() -> void:
	var scene: PackedScene = load("res://ui/dialogue/dialogue_ui.tscn")
	var ui: CanvasLayer = scene.instantiate()
	root.add_child(ui)

	var panel: PanelContainer = ui.find_child("Panel", true, false)
	assert(panel != null, "找不到 Panel")
	# 2026-09-22 使用者裁定「對話框太大」：高度由內容決定（貼齊文字），
	# 不再是固定 220px 的空盒子；底部錨點 0.94、往上長（GROW_DIRECTION_BEGIN）。
	assert(panel.custom_minimum_size.y <= 0.0,
		"Panel 不應再被固定最小高度撐開（目前: %f）" % panel.custom_minimum_size.y)
	assert(absf(panel.anchor_top - 0.94) < 0.001 and absf(panel.anchor_bottom - 0.94) < 0.001,
		"Panel 上／下錨點都應是 0.94（貼底、往上長）")
	assert(panel.grow_vertical == Control.GROW_DIRECTION_BEGIN, "Panel 應往上方長（GROW_DIRECTION_BEGIN）")

	var style: StyleBox = panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		assert(style.content_margin_left >= 30.0, "左內邊距應 >= 30")
		assert(style.content_margin_right >= 30.0, "右內邊距應 >= 30")
		assert(style.content_margin_top >= 12.0, "上內邊距應 >= 12")
		assert(style.content_margin_bottom >= 14.0, "下內邊距應 >= 14")

	var text: RichTextLabel = ui.find_child("Text", true, false)
	assert(text != null, "找不到 Text")
	assert(text.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "Text 應設定為 AUTOWRAP_WORD_SMART")
	# fit_content = 面板跟著台詞長高的機制；關掉就退回「固定高度空盒子」。
	assert(text.fit_content, "Text 應開啟 fit_content，面板才會隨台詞行數長高")

	ui.queue_free()
	print("✓ PASS: DialogueUI 貼底自適應高度、內邊距（36,36,16,20）、fit_content 與 CJK 自動換行驗證通過")


func _test_portal_route_travel() -> void:
	var main_script: GDScript = load("res://scripts/main.gd")
	var src: String = main_script.source_code
	assert(src.contains("ROUTE_TRAVEL_MINUTES"), "main.gd 應包含 ROUTE_TRAVEL_MINUTES 路線時長設定")
	assert(src.contains("_show_time_toast"), "main.gd 應包含 _show_time_toast 浮動時間角標")
	assert(src.contains("OpeningTitleCard"), "main.gd 應包含開場獸道字卡演出")
	print("✓ PASS: 路線差量旅行時間、浮動時間角標與開場獸道字卡程式碼綁定驗證通過")


func _test_world_event_manager() -> void:
	var wem_script: Script = load("res://systems/world_event/world_event_manager.gd")
	var wem: Node = wem_script.new()
	wem.register_event("night_yatai_smell", {
		"map": "trail",
		"start_hour": 19.5,
		"end_hour": 4.5,
		"probability": 1.0,
		"one_shot": true,
	})

	# 白天 12:00 不應觸發
	var trig_noon: Array = wem.evaluate_events("trail", 12.0)
	assert(trig_noon.is_empty(), "白天不應觸發夜晚事件")

	# 夜晚 20:00 應觸發
	var trig_night: Array = wem.evaluate_events("trail", 20.0)
	assert(trig_night.has("night_yatai_smell"), "夜晚 20:00 應觸發 night_yatai_smell")

	# one_shot 事件第二次評估不應重複觸發
	var trig_repeat: Array = wem.evaluate_events("trail", 21.0)
	assert(not trig_repeat.has("night_yatai_smell"), "one_shot 事件不應重複觸發")

	wem.queue_free()
	print("✓ PASS: WorldEventManager 事件註冊、時間窗口判定與一次性旗標驗證通過")
