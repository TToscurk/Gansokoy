extends SceneTree
## 冥想模式實機截圖（ART_REVIEW 用）：選單、入定運鏡、夜間快轉、被打斷。
##   <godot_console.exe> --path godot --script res://tools/_shot_meditation.gd
##
## 走**真的按鍵**（root.push_input 送 T／方向鍵／Enter 進正常輸入管線），
## 不是直接呼叫控制器的方法 —— 要驗的就是「玩家按 T 會發生什麼」。
##
## ⚠ --script 模式下 autoload 在 _init 當下尚未就緒，必須 call_deferred。
## ⚠ 不開 --headless：要真的畫出畫面才有像素可讀。
## ⚠ 獸道夜晚冥想有 35% 機率被打斷，拍圖要可控：start 之後把 _interrupt_at
##   改成 -1（除非那張就是要拍被打斷）。
## ⚠ 鏡頭拉遠要 2.6 秒。拍「入定中」用預設真實秒數（5 秒起）才拍得到運鏡；
##   只有「被打斷」那張把秒數縮短，讓打斷早點發生。
const OUT := "D:/神社/shrine/work/shots/meditation/"

var _main: Node
var _med: Node
var _dm: Node
var _dn: Node
var _wtm: Node
var _last_dialogue := ""


func _init() -> void:
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _wait_idle(timeout_s: float = 30.0) -> void:
	var t0 := Time.get_ticks_msec()
	while bool(_med.call("is_meditating")) and float(Time.get_ticks_msec() - t0) / 1000.0 < timeout_s:
		await process_frame


func _shot(name: String) -> void:
	await _settle(4)
	await RenderingServer.frame_post_draw
	await process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	print("[SHOT] %s  %dx%d" % [name, img.get_width(), img.get_height()])


## 送一次真按鍵（走 Viewport 的輸入管線 → _unhandled_input 收得到）
func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	root.push_input(ev)
	await _settle(2)
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.keycode = code
	up.pressed = false
	root.push_input(up)
	await _settle(2)


func _report(tag: String) -> void:
	print("[MED] %s 冥想中=%s 流速=%.1f 現在=%s 目標=%s 風險=%.0f%% 黑邊=%.1f px player鎖=%s" % [
		tag, str(_med.call("is_meditating")), float(_wtm.get("time_scale")),
		_wtm.call("clock_text"), _med.call("clock_at", int(_med.get("_target_total"))),
		float(_med.call("interrupt_chance")) * 100.0, _bar_h(),
		str(_main.player.get("input_locked"))])


func _bar_h() -> float:
	for c in root.find_children("BarTop", "ColorRect", true, false):
		return (c as Control).offset_bottom
	return -1.0


func _menu_rect() -> String:
	for c in root.find_children("MeditationMenu", "CanvasLayer", true, false):
		var p := (c as Node).get_node_or_null("Panel") as Control
		if p != null:
			return "開啟=%s pos=%s size=%s（%.0f%% x %.0f%% 畫面）" % [
				str((c as CanvasLayer).visible), str(p.global_position), str(p.size),
				100.0 * p.size.x / root.get_viewport().get_visible_rect().size.x,
				100.0 * p.size.y / root.get_viewport().get_visible_rect().size.y]
	return "找不到 MeditationMenu"


## 收掉畫面上任何對話（開場獨白、地圖抵達獨白、屋台搭話…）。
## 這些都會讓 can_meditate() 說不 —— 拍冥想前一定要先清乾淨。
func _drain(on: bool = true) -> void:
	var guard := 0
	while bool(_dm.call("is_active")) and guard < 30:
		if on:
			_dm.call("advance", -1)
		await _settle(1)
		guard += 1


## 按 T 開冥想選單。被拒絕（對話中／過場中／玩家被鎖）就清乾淨再試一次。
func _open_menu() -> bool:
	for attempt in 3:
		await _drain()
		_main.player.set("input_locked", false)
		await _key(KEY_T)
		for c in root.find_children("MeditationMenu", "CanvasLayer", true, false):
			if (c as CanvasLayer).visible:
				return true
		print("[MED] 第 %d 次按 T 沒開起來（對話中=%s 玩家鎖=%s 時間暫停=%s）" % [
			attempt + 1, str(_dm.call("is_active")), str(_main.player.get("input_locked")),
			str(_wtm.call("is_time_paused"))])
		await _settle(30)
	return false


func _run() -> void:
	_dm = root.get_node("/root/DialogueManager")
	_dn = root.get_node("/root/DayNight")
	_wtm = root.get_node("/root/WorldTimeManager")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_dm.dialogue_started.connect(func(id: String) -> void: _last_dialogue = id)
	await _settle(8)

	# 序章演出會鎖時間／鎖輸入，先收乾淨 —— 這批要驗的是冥想不是開場
	var ui := root.find_child("DialogueUI", true, false)
	if ui != null:
		ui.set_process_unhandled_input(false)
		ui.set("typewriter_cps", 0.0)
	await _drain(false)
	# ⚠ 開場的 dialogue_started 會把 player.input_locked 設 true，而我們剛剛
	# 是硬把對話推完的，dialogue_ended 的解鎖不一定輪得到 —— 明著解除。
	_main.player.set("input_locked", false)

	_main.load_map("slice", "trail")
	await _settle(120)
	_med = _main.get("meditation")
	if _med == null:
		print("[MED] 失敗：main 沒有 meditation（掛載沒生效）")
		quit(1)
		return
	print("[MED] 控制器掛載 OK；選單 %s" % _menu_rect())
	print("[MED] 冥想鍵：T；選項數=%d；玩家位置=%s（地面 y）" % [
		(_med.get("OPTIONS") as Array).size(), str(_main.player.global_position)])
	_dn.set("day", 1)
	_dn.set("pause_reasons", [] as Array[String])
	_dn.set("flowing", true)
	await _settle(30)

	# ── 人里的天象系統（每圖一個，先確認節點在）
	var sky := (_main.get("map_root") as Node).find_child("天象系統", true, false)
	print("[MED] 人里天象系統=%s；安全圖風險=%.0f%%" % [str(sky != null), float(_med.call("interrupt_chance")) * 100.0])

	# ── ① 選單：15:20 打開
	_dn.call("set_hour", 15.0 + 20.0 / 60.0)
	await _settle(20)
	print("[MED] 按 T 開選單=%s" % str(await _open_menu()))
	print("[MED] 選單 %s" % _menu_rect())
	await _shot("m0_menu")
	for i in 3:
		await _key(KEY_DOWN)
	await _shot("m1_menu_dusk")
	for i in 3:
		await _key(KEY_UP)          # 回到「30 分鐘」

	# ── ② 入定（30 分鐘，預設運鏡秒數）：鏡頭拉遠＋上下黑邊
	await _key(KEY_ENTER)
	_med.set("_interrupt_at", -1)
	var start_clock: String = _wtm.call("clock_text")
	await _settle(140)              # 約 2.3 秒：鏡頭拉到定位、黑邊進場
	_report("入定中")
	await _shot("m2_meditating")
	await _wait_idle()
	await _settle(140)
	_report("收功後")
	await _shot("m3_after_meditation")
	print("[MED] 冥想結束：%s → %s" % [start_clock, _wtm.call("clock_text")])

	# ── ③ 直到夜晚：世界真的換了（天空／燈／屋台）
	_dn.call("set_hour", 18.0 + 20.0 / 60.0)
	await _settle(40)
	print("[MED] 按 T 開選單=%s" % str(await _open_menu()))
	if bool(_med.call("is_busy")):
		for i in 4:
			await _key(KEY_DOWN)
		await _shot("m4_menu_to_night")
		await _key(KEY_ENTER)
		_med.set("_interrupt_at", -1)
		var dusk_clock: String = _wtm.call("clock_text")
		await _settle(140)
		_report("冥想到夜晚中")
		await _shot("m5_to_night")
		await _wait_idle()
		await _settle(160)
		_report("夜晚")
		await _shot("m6_night_after")
		print("[MED] 冥想到夜晚結束：%s → %s" % [dusk_clock, _wtm.call("clock_text")])

	# ── ④ 被打斷：真的獸道、真的夜晚（風險表上唯一會被打斷的圖）
	_main.load_map("trail", "slice")
	await _settle(150)
	_dn.call("set_hour", 21.0)
	await _settle(40)
	var trail_sky := (_main.get("map_root") as Node).find_child("天象系統", true, false)
	print("[MED] 獸道 21:00 風險=%.0f%%（晴夜）" % (float(_med.call("interrupt_chance")) * 100.0))
	if trail_sky != null:
		trail_sky.set("天氣", 3)
		await _settle(2)
		print("[MED] 獸道 21:00 雨天風險=%.0f%%" % (float(_med.call("interrupt_chance")) * 100.0))
		trail_sky.set("天氣", 0)
		await _settle(2)
	_med.set("min_real_seconds", 1.2)
	_med.set("max_real_seconds", 2.0)
	print("[MED] 按 T 開選單=%s" % str(await _open_menu()))
	if bool(_med.call("is_busy")):
		for i in 2:
			await _key(KEY_DOWN)        # 3 小時
		await _key(KEY_ENTER)
		# 打斷是機率事件，驗收要可控：直接把它排在 6 分鐘後
		_med.set("_interrupt_at", int(_wtm.get("total_minutes")) + 6)
		await _wait_idle()
		await _settle(240)
		_report("被打斷後")
		await _settle(60)
		print("[MED] 打斷後畫面對話=%s（應為 yoriichi_meditation）" % str(_last_dialogue))
		await _shot("m7_interrupted")

	print("[MED] 全部拍完，輸出在 %s" % OUT)
	quit(0)
