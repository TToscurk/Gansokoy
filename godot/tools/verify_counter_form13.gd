extends SceneTree
## 見切反擊 ＋ 閃避回報 ＋ 拾參ノ型（C）：接線驗證。
##   godot --headless --path godot -s res://tools/verify_counter_form13.gd

const SunBreathing = preload("res://characters/yoriichi/sun_breathing.gd")
var _pass := 0
var _fail := 0
var _p: CharacterBody3D


func check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [OK] ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", label, ("  " + detail) if detail != "" else "")


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame


func _reset() -> void:
	if _p.action_state != 0:
		_p._finish_attack()
	_p.end_guard()
	_p._form_cooldowns.clear()
	_p._form13_queue.clear()
	_p._form13_running = false
	_p.sun_breath_gauge = 0.0
	_p.posture.heal_full()
	_p._hitstun_left = 0.0
	_p._knockback_left = 0.0
	Engine.time_scale = 1.0
	_p._slowmo_left = 0.0
	_p._counter_until_msec = -1
	await _wait(3)


func _run() -> void:
	print("=== 見切反擊 / 閃避回報 / 拾參ノ型 ===")
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	body.add_child(col)
	root.add_child(body)
	_p = (load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene).instantiate()
	root.add_child(_p)
	await _wait(10)
	check("form13 action 已註冊（C）", InputMap.has_action("form13"))
	var keys: Array[int] = []
	for e in InputMap.action_get_events("form13"):
		if e is InputEventKey:
			keys.append(e.physical_keycode)
	check("form13 = C", keys.has(KEY_C), str(keys))
	# 不得與其他動作撞鍵
	var clash := ""
	for a in InputMap.get_actions():
		if String(a).begins_with("ui_") or a == &"form13":
			continue
		for e in InputMap.action_get_events(a):
			if e is InputEventKey and e.physical_keycode == KEY_C:
				clash = String(a)
	check("C 沒有撞到其他動作", clash == "", clash)

	_p.request_draw()
	await _wait(70)
	check("拔刀完成", _p.sword_state == 2)

	# --- 1. 見切反擊 ---
	print("-- 見切反擊（彈刀 → LMB → 拾壹型）--")
	await _reset()
	_p.begin_guard()
	await _wait(1)
	var r: Dictionary = _p.take_hit({"damage": 20.0, "posture_damage": 10.0, "hit_dir": Vector3.FORWARD})
	check("彈刀成功", r.result == "deflect", str(r.result))
	check("反擊窗口已開", _p._counter_until_msec > 0)
	var got := [0]
	_p.counter_triggered.connect(func(id: int) -> void: got[0] = id)
	_p.request_primary_attack()
	await _wait(1)
	check("LMB → 拾壹型 幻日虹", _p.active_form == 11, "active_form=%d" % _p.active_form)
	check("counter_triggered 訊號", got[0] == 11)
	check("反擊不扣呼吸（彈刀 +%.0f 後仍是 %.0f）" % [_p.breath_gain_on_deflect, _p.breath_gain_on_deflect],
		is_equal_approx(_p.sun_breath_gauge, _p.breath_gain_on_deflect), "%.1f" % _p.sun_breath_gauge)
	check("反擊後格擋已放下", not _p.is_guarding())
	check("窗口用掉即關", _p._counter_until_msec < 0)
	await _wait(80)
	# 窗口過期
	await _reset()
	_p.begin_guard()
	await _wait(1)
	_p.take_hit({"damage": 20.0, "posture_damage": 10.0, "hit_dir": Vector3.FORWARD})
	_p.end_guard()
	await _wait(int(_p.counter_window * 60.0) + 8)
	_p.request_primary_attack()
	await _wait(1)
	check("窗口過期後 LMB 只是普通連段", _p.active_form == 0 and _p.combo_stage == 1, "form=%d stage=%d" % [_p.active_form, _p.combo_stage])
	await _wait(60)
	# 關閉
	await _reset()
	_p.counter_form = 0
	_p.begin_guard()
	await _wait(1)
	_p.take_hit({"damage": 20.0, "posture_damage": 10.0, "hit_dir": Vector3.FORWARD})
	check("counter_form=0：不開窗口", _p._counter_until_msec < 0)
	_p.counter_form = 11
	_p.end_guard()

	# --- 2. 閃避成功回報 ---
	print("-- 翻滾閃過 → 呼吸 +、時間減速 --")
	await _reset()
	_p.request_dodge(Vector3.FORWARD)
	await _wait(6)
	check("翻滾中無敵幀開著", _p.in_dodge_invuln())
	r = _p.take_hit({"damage": 20.0, "posture_damage": 10.0})
	check("判定 dodge", r.result == "dodge")
	check("呼吸 +%.0f" % _p.dodge_success_breath, is_equal_approx(_p.sun_breath_gauge, _p.dodge_success_breath), "%.1f" % _p.sun_breath_gauge)
	check("時間減速到 %.2f" % _p.dodge_slowmo_scale, is_equal_approx(Engine.time_scale, _p.dodge_slowmo_scale), "%.2f" % Engine.time_scale)
	var t0 := Time.get_ticks_msec()
	while Engine.time_scale < 1.0 and Time.get_ticks_msec() - t0 < 3000:
		await physics_frame
	var real := (Time.get_ticks_msec() - t0) / 1000.0
	check("減速以真實時間 %.2f s 結束（實 %.2f）" % [_p.dodge_slowmo_time, real], is_equal_approx(Engine.time_scale, 1.0) and real < _p.dodge_slowmo_time + 0.15)
	await _wait(40)
	# 端點：slowmo_time 0 → 不減速
	await _reset()
	_p.dodge_slowmo_time = 0.0
	_p.request_dodge(Vector3.FORWARD)
	await _wait(6)
	_p.take_hit({"damage": 20.0, "posture_damage": 10.0})
	check("dodge_slowmo_time=0：不減速", is_equal_approx(Engine.time_scale, 1.0))
	_p.dodge_slowmo_time = 0.25
	await _wait(40)

	# --- 3. 拾參ノ型 ---
	print("-- 拾參ノ型（C）--")
	await _reset()
	_p.sun_breath_gauge = 50.0
	check("呼吸不滿：發不出", not _p.start_form13())
	_p.sun_breath_gauge = _p.sun_breath_max
	_p.sun_mastery = 0
	var started := [false]
	var finished := [false]
	_p.form13_started.connect(func() -> void: started[0] = true)
	_p.form13_finished.connect(func() -> void: finished[0] = true)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_C
	ev.pressed = true
	_p._unhandled_input(ev)
	await _wait(1)
	check("按 C 啟動", started[0] and _p._form13_running)
	check("呼吸歸零", is_zero_approx(_p.sun_breath_gauge))
	check("熟練度 0 也照放（第一型 = 壹）", _p.active_form == 1, "form=%d" % _p.active_form)
	var seen: Array[int] = []
	var t1 := Time.get_ticks_msec()
	while not finished[0] and Time.get_ticks_msec() - t1 < 15000:
		if _p.active_form != 0 and (seen.is_empty() or seen.back() != _p.active_form):
			seen.append(_p.active_form)
		await physics_frame
	check("連放結束（form13_finished）", finished[0], "%.1f s" % ((Time.get_ticks_msec() - t1) / 1000.0))
	check("十二型全部依序播過", seen == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], str(seen))
	check("結束後 FREE", _p.action_state == 0)
	# 不在玩家死亡／空中觸發
	await _reset()
	_p.form13_key_enabled = false
	_p.sun_breath_gauge = _p.sun_breath_max
	_p._unhandled_input(ev)
	await _wait(1)
	check("form13_key_enabled=false：C 無效", _p.active_form == 0)
	_p.form13_key_enabled = true

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
