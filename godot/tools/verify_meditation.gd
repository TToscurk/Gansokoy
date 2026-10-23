extends SceneTree
## 冥想模式驗收：時間流速、跨日換算、選項、風險表、被打斷、出定還原。
##   <godot_console.exe> --path godot --headless --script res://tools/verify_meditation.gd
##
## 刻意**不**只驗算術：
##   · 流速跑真的 DayNight 時鐘（量「現實 1 秒實際走幾分」對不對）
##   · 選項跑真的 WorldTimeManager（total_minutes）
##   · 被打斷跑真的 DialogueManager（真的開得起來那句獨白）
##   · 擺姿跑真的緣一（player_yoriichi.tscn 的 start/end_meditation_pose）
##
## ⚠ 含 await 的測試一定要 `await` 著跑。前一版漏了 await：兩條測試同時進行、
##   互相把時鐘 reset 掉，量到的數字全是垃圾（看起來像「冥想暴走 15 小時」）。
## ⚠ 不量「幀數比」：headless 每幀長度浮動極大（實測到 1.5 秒／幀），
##   要量速率就用 Time.get_ticks_msec() 量真實秒數。
## ⚠ 不載 main.tscn（獸道要載 20~30 秒，而且開場演出會鎖住時間／對話，讓
##   「能不能冥想」的斷言變成在測開場）。main.gd 的掛載與按鍵走 _shot_meditation.gd。

const PLAYER_SCENE := preload("res://characters/yoriichi/player_yoriichi.tscn")
const CONTROLLER := preload("res://systems/time/meditation_controller.gd")
const STUB_MAIN := preload("res://tools/_meditation_stub_main.gd")

var _main: Node3D
var _player: Node
var _med: Node
var _wtm: Node
var _dn: Node
var _dm: Node
var _fails := 0
var _started_ids: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== 冥想模式驗收 ===")
	_wtm = root.get_node("/root/WorldTimeManager")
	_dn = root.get_node("/root/DayNight")
	_dm = root.get_node("/root/DialogueManager")
	_dm.dialogue_started.connect(func(id: String) -> void: _started_ids.append(id))
	_build()

	await _test_time_scale()
	_test_total_minutes_crossday()
	_test_options()
	_test_risk_table()
	_test_can_meditate_guard()
	_test_pose()
	await _test_full_run()
	await _test_interrupt()
	_test_input_action()

	print("=== 完成：%s ===" % ("全數通過" if _fails == 0 else "%d 項失敗" % _fails))
	quit(1 if _fails > 0 else 0)


func _build() -> void:
	_main = STUB_MAIN.new()
	# 名字取作 Main：weather.gd 會 get_node("Main") 掛雨粒子，改名會噴錯。
	_main.name = "Main"
	root.add_child(_main)
	_player = PLAYER_SCENE.instantiate()
	_main.add_child(_player)
	_main.set("player", _player)
	_main.set("current_id", "trail")
	_med = CONTROLLER.new()
	_med.name = "Meditation"
	_main.add_child(_med)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("✓ PASS: ", msg)
	else:
		_fails += 1
		printerr("✗ FAIL: ", msg)


func _reset_clock(day: int, hour_f: float) -> void:
	_dn.set("pause_reasons", [] as Array[String])
	_dn.set("flowing", true)
	_dn.set("time_scale", 1.0)
	_dn.set("day", day)
	_dn.call("set_hour", hour_f)


## 等到條件成立或逾時（真實秒）。回傳是否成立。
func _wait_until(cond: Callable, deadline_s: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < deadline_s:
		if bool(cond.call()):
			return true
		await process_frame
	return false


## ── ① 流速倍率真的放大時鐘（不是只有那個數字變大）────────────────────
## 用「日×24 + 時」的浮點絕對時間量位移：total_minutes 是整數分鐘，在 4 ms
## 一幀的環境裡取樣 6 幀只走 0.05 分，量化誤差比訊號大（前一版量到 0.0）。
func _test_time_scale() -> void:
	_dn.set("day_seconds", 600.0)
	var deltas: Array[float] = []
	var scales: Array[float] = [1.0, 30.0]
	for scale in scales:
		_reset_clock(1, 6.0)
		_dn.set("time_scale", scale)
		var h0 := _abs_hours()
		for i in 60:
			await process_frame
		deltas.append(_abs_hours() - h0)
	_dn.set("time_scale", 1.0)
	_dn.set("day_seconds", 3600.0)
	var ratio: float = deltas[1] / maxf(deltas[0], 0.000001)
	_check(deltas[0] > 0.0, "流速 1.0 時時鐘有在前進（60 幀 %.4f h）" % deltas[0])
	_check(ratio > 20.0 and ratio < 45.0, "流速 30.0 的時鐘位移約為 1.0 的 30 倍（實測 ×%.1f）" % ratio)


func _abs_hours() -> float:
	return float(_dn.get("day")) * 24.0 + float(_dn.get("hour"))


## ── ② 跨日：total_minutes 與 minutes_until_hour ────────────────────────
func _test_total_minutes_crossday() -> void:
	_reset_clock(3, 23.0)
	_check(int(_wtm.get("total_minutes")) == 2 * 1440 + 1380,
		"第 3 日 23:00 → total_minutes = %d" % int(_wtm.get("total_minutes")))
	_check(int(_dn.call("minutes_until_hour", 5.0)) == 360, "23:00 → 清晨 05:00 還差 360 分（跨日）")
	_check(int(_dn.call("minutes_until_hour", 23.0)) == 1440, "已經 23:00 再問 23:00 → 1440 分（下一天）")


## ── ③ 六個選項換算 ─────────────────────────────────────────────────────
func _test_options() -> void:
	_reset_clock(1, 15.0 + 20.0 / 60.0)     # 15:20
	var r0: Dictionary = _med.call("resolve_option", 0)
	_check(String(r0["clock"]) == "15:50" and int(r0["minutes"]) == 30, "30 分鐘：15:20 → %s" % r0["clock"])
	var r1: Dictionary = _med.call("resolve_option", 1)
	_check(String(r1["clock"]) == "16:20", "1 小時：15:20 → %s" % r1["clock"])
	var r2: Dictionary = _med.call("resolve_option", 2)
	_check(String(r2["clock"]) == "18:20", "3 小時：15:20 → %s" % r2["clock"])
	var r3: Dictionary = _med.call("resolve_option", 3)
	_check(String(r3["clock"]) == "18:00" and int(r3["minutes"]) == 160,
		"直到黃昏：15:20 → %s（%d 分）" % [r3["clock"], int(r3["minutes"])])
	var r4: Dictionary = _med.call("resolve_option", 4)
	_check(String(r4["clock"]) == "19:30" and int(r4["minutes"]) == 250,
		"直到夜晚：15:20 → %s（%d 分）" % [r4["clock"], int(r4["minutes"])])
	var r5: Dictionary = _med.call("resolve_option", 5)
	_check(String(r5["clock"]) == "05:00" and int(r5["minutes"]) == 820 and bool(r5["crossed_day"]),
		"直到清晨：15:20 → 翌日 %s（%d 分，跨日=%s）" % [r5["clock"], int(r5["minutes"]), r5["crossed_day"]])
	# 已經 04:00 選「直到清晨」只等 1 小時，不該順延一天
	_reset_clock(1, 4.0)
	var r5b: Dictionary = _med.call("resolve_option", 5)
	_check(String(r5b["clock"]) == "05:00" and int(r5b["minutes"]) == 60 and not bool(r5b["crossed_day"]),
		"04:00 選直到清晨 → 當日 %s（%d 分）" % [r5b["clock"], int(r5b["minutes"])])
	# 已經 20:00 選「直到黃昏」要跨到隔天，不是負數
	_reset_clock(1, 20.0)
	var r3b: Dictionary = _med.call("resolve_option", 3)
	_check(int(r3b["minutes"]) == 1320 and bool(r3b["crossed_day"]),
		"20:00 選直到黃昏 → 翌日 %s（%d 分）" % [r3b["clock"], int(r3b["minutes"])])


## ── ④ 風險表 ───────────────────────────────────────────────────────────
func _test_risk_table() -> void:
	_main.set("current_id", "trail")
	_reset_clock(1, 12.0)
	_check(absf(float(_med.call("interrupt_chance")) - 0.05) < 0.0001,
		"獸道白天 5%%（實測 %.0f%%）" % (float(_med.call("interrupt_chance")) * 100.0))
	_reset_clock(1, 18.5)
	_check(absf(float(_med.call("interrupt_chance")) - 0.15) < 0.0001, "獸道黃昏 15%")
	_reset_clock(1, 21.0)
	_check(absf(float(_med.call("interrupt_chance")) - 0.35) < 0.0001, "獸道夜晚 35%")
	# 壞天氣的夜：假 main 沒有每圖的天象系統，走的是**全域 Weather 單例**這條退路。
	# （真圖天象系統那條分支在 tools/_shot_meditation.gd 用真的獸道圖驗。）
	var w := root.get_node_or_null("/root/Weather")
	if w != null:
		w.call("set_weather", "rain")
		_reset_clock(1, 21.0)
		_check(absf(float(_med.call("interrupt_chance")) - 0.50) < 0.0001, "獸道雨天夜晚 50%")
		w.call("set_weather", "clear")
		_reset_clock(1, 21.0)
		_check(absf(float(_med.call("interrupt_chance")) - 0.35) < 0.0001, "轉晴後回到 35%")
	else:
		print("· SKIP: 找不到 Weather 單例")
	# 表上沒有的圖 = 安全（神社／人里／室內都是）
	_main.set("current_id", "slice")
	_reset_clock(1, 21.0)
	_check(float(_med.call("interrupt_chance")) == 0.0, "人間之里夜晚 0%（安全休息點）")
	_main.set("current_id", "shrine")
	_check(float(_med.call("interrupt_chance")) == 0.0, "博麗神社夜晚 0%（安全休息點）")
	_main.set("current_id", "trail")


## ── ⑤ 時間被鎖住時不准起冥想（不然永遠到不了點）──────────────────────
func _test_can_meditate_guard() -> void:
	_main.set("current_id", "slice")
	_reset_clock(1, 12.0)
	_player.set("input_locked", false)
	_check(bool(_med.call("can_meditate")), "平常可以冥想")
	_dn.call("lock_time", "verify_test")
	_check(not bool(_med.call("can_meditate")), "時間被鎖住（過場中）不能冥想")
	_dn.call("unlock_time", "verify_test")
	_check(bool(_med.call("can_meditate")), "解鎖後恢復可以冥想")
	# 對話中也不能（時間被鎖，而且會跟對話搶輸入）
	_dm.call("start", "yoriichi_wake")
	if bool(_dm.call("is_active")):
		_check(not bool(_med.call("can_meditate")), "對話進行中不能冥想")
		var guard := 0
		while bool(_dm.call("is_active")) and guard < 20:
			_dm.call("advance", -1)
			guard += 1
		_dn.set("pause_reasons", [] as Array[String])


## ── ⑥ 擺姿（真的緣一）────────────────────────────────────────────────
func _test_pose() -> void:
	_check(_player.has_method("start_meditation_pose"), "緣一有 start_meditation_pose")
	_player.call("start_meditation_pose")
	_check(bool(_player.get("input_locked")), "擺姿時鎖住輸入")
	_player.call("end_meditation_pose")
	_check(not bool(_player.get("input_locked")), "出定後解鎖")


## ── ⑦ 真的跑一次：30 分鐘 ──────────────────────────────────────────────
func _test_full_run() -> void:
	_main.set("current_id", "slice")
	_reset_clock(1, 15.0)
	_dn.set("day_seconds", 1200.0)          # 人里的「一日長度分鐘」= 20
	_med.set("min_real_seconds", 0.4)       # 驗收不要真的坐 5 秒
	_med.set("max_real_seconds", 0.5)
	var before: int = int(_wtm.get("total_minutes"))
	_med.call("start", 0)                   # 30 分鐘
	_check(bool(_med.call("is_meditating")), "開始冥想")
	_check(float(_wtm.get("time_scale")) > 1.0, "流速被拉高（×%.1f）" % float(_wtm.get("time_scale")))
	_check(bool(_player.get("input_locked")), "冥想中玩家被鎖住")
	_check(_bars().size() == 2, "上下黑邊有兩條")
	_check(await _wait_until(func() -> bool:
		var b := _bars()
		return b.size() == 2 and (b[0] as Control).offset_bottom > 1.0, 6.0),
		"入定時黑邊拉開（%.1f px）" % (_bars()[0] as Control).offset_bottom)
	_check(await _wait_until(func() -> bool: return not bool(_med.call("is_meditating")), 10.0), "到點自動收功")
	_check(absf(float(_wtm.get("time_scale")) - 1.0) < 0.0001, "流速還原 1.0")
	var after: int = int(_wtm.get("total_minutes"))
	_check(after >= before + 30, "時鐘走到目標（15:00 → %s）" % CONTROLLER.clock_at(after))
	_check(after <= before + 45, "沒有暴衝過頭（實走 %d 分，目標 30）" % (after - before))
	_check(await _wait_until(func() -> bool: return not bool(_player.get("input_locked")), 8.0), "收功後解鎖")
	_check(await _wait_until(func() -> bool:
		var b := _bars()
		return b.size() == 2 and absf((b[0] as Control).offset_bottom) < 1.0, 8.0),
		"黑邊收乾淨（%.1f px）" % (_bars()[0] as Control).offset_bottom)
	_check(_main.get_node_or_null("MeditationCamera") == null, "冥想專用鏡頭已釋放")
	_dn.set("day_seconds", 3600.0)


## ── ⑧ 被打斷：夜裡的獸道 ───────────────────────────────────────────────
func _test_interrupt() -> void:
	_main.set("current_id", "trail")
	_reset_clock(1, 21.0)
	_med.set("min_real_seconds", 1.2)
	_med.set("max_real_seconds", 1.5)
	_started_ids.clear()
	var before: int = int(_wtm.get("total_minutes"))
	_med.call("start", 2)                   # 3 小時
	# 機率是隨機的，驗收要可控：直接把打斷點塞到 10 分鐘後
	_med.set("_interrupt_at", before + 10)
	_check(await _wait_until(func() -> bool: return not bool(_med.call("is_meditating")), 10.0),
		"被打斷 → 冥想結束")
	_check(absf(float(_wtm.get("time_scale")) - 1.0) < 0.0001, "被打斷 → 流速還原")
	var after: int = int(_wtm.get("total_minutes"))
	_check(after < before + 180, "沒有坐滿 3 小時就醒了（實走 %d 分）" % (after - before))
	_check(await _wait_until(func() -> bool: return bool(_dm.call("is_active")), 6.0), "被打斷 → 獨白開始")
	_check(_started_ids.has("yoriichi_meditation"), "獨白是 yoriichi_meditation（實際：%s）" % str(_started_ids))
	# 收尾，別把對話留著
	var guard := 0
	while bool(_dm.call("is_active")) and guard < 20:
		_dm.call("advance", -1)
		guard += 1
	_check(not bool(_dm.call("is_active")), "獨白可以正常推完（%d 步）" % guard)


## ── ⑨ 按鍵存在（不然 _unhandled_input 整條掛掉）──────────────────────
func _test_input_action() -> void:
	_check(InputMap.has_action("meditate"), "InputMap 有 meditate 動作")
	var keys := InputMap.action_get_events("meditate")
	_check(keys.size() > 0, "meditate 綁了按鍵")
	if keys.size() > 0:
		var k := keys[0] as InputEventKey
		_check(k != null and OS.get_keycode_string(k.physical_keycode) == "T",
			"meditate 綁在 T（實際 %s）" % (OS.get_keycode_string(k.physical_keycode) if k != null else "?"))
	_check(InputMap.has_action("interact") and InputMap.has_action("ui_cancel"), "選單用到的動作都在（interact／ui_cancel）")


func _bars() -> Array:
	var out := []
	var d := _main.get_node_or_null("MeditationOverlay")
	if d == null:
		return out
	for c in (d as Node).get_children():
		out.append(c)
	return out
