extends "res://tools/yoriichi_r7/test_r7_form13.gd"
## R7 P5 REF01 圓舞 右鍵分支 focused 測試（headless、物理整合、不寫資源）。每個情境獨立行程、固定輸入時刻（以 REF01 clip 實際
## 命中窗／取消點換算的物理格），輸入由程式呼叫（request_heavy_cut／request_dodge／take_hit／Input.action_press）。
##   godot --headless --fixed-fps 60 --path godot -s res://tools/yoriichi_r7/test_r7_ref01_rmb.gd -- <rmb_single|rmb_buffer|rmb_expire|rmb_cycle|rmb_hit|rmb_hit_pending|rmb_recover|rmb_dummy>
## 輸出 user://r7_form13/<scenario>.json ＋ R7C_RESULT 一行（與 test_r7_form13 同格式）。

const RMB_ID := 102

func _rmb_log() -> Array:
	return _p.get("r7_rmb_log")

func _rmb_ev(name: String) -> Array:
	var out := []
	for e in _rmb_log():
		if e.ev == name:
			out.append(e)
	return out

## REF01 單招合法窗（物理格，起手＝0）：max(取消進度, 最後命中窗結束＋1)
func _ref01_legal_tick() -> int:
	var forms: Dictionary = _p.get("R7_FORMS")
	var a: Animation = _p.get("_anim").get_animation(forms[1].anim)
	var spd := float(_p.get("r7_sun_speed"))
	var t_cancel := float(forms[1].cancel) * a.length / spd
	var wend := 0.0
	for w in a.get_meta("r7_hit_windows", [a.get_meta("r7_hit_window", [-1, -1])]):
		wend = maxf(wend, (float(w[1]) + 1.0) / (30.0 * spd))
	_case.ref01 = {"len_s": snappedf(a.length / spd, 0.001), "cancel_s": snappedf(t_cancel, 0.001), "hit_end_s": snappedf(wend, 0.001)}
	return int(ceil(maxf(t_cancel, wend) * 60.0))

func _forms_seen() -> Array:
	var seen := []
	for t in _ticks:
		var r: String = t.ref
		if r != "" and (seen.is_empty() or seen[-1] != r):
			seen.append(r)
	return seen

func _start_ref01() -> bool:
	var ok := bool(_p.call("execute_form", 1, true))
	_check(ok and int(_p.get("active_form")) == 1, "REF01 single started")
	return ok

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		_tick()

func _rmb() -> void:
	_case.inputs = _case.get("inputs", []) + [{"f": _frame, "call": "request_heavy_cut", "af": snappedf(_fr(), 0.1)}]
	_p.call("request_heavy_cut")

func _branch_done() -> bool:
	return int(_p.get("action_state")) == 0

func _common_branch_checks() -> void:
	var st := _rmb_ev("rmb_start")
	_check(st.size() == 1, "branch started exactly once")
	_check(_forms_seen().has("REF01_RMB"), "REF01_RMB actually played")
	var a := ""
	for t in _ticks:
		if t.ref == "REF01_RMB":
			a = t.anim
			break
	_check(a == "R7_Sun01_RmbSpinCut", "branch anim R7_Sun01_RmbSpinCut")
	_check(not _forms_seen().has("REF02"), "REF02 never starts")

# ---------------------------------------------------------------- 單招：合法窗內右鍵 → 立即分支
func _sc_rmb_single() -> void:
	var L := _ref01_legal_tick()
	_start_ref01()
	await _wait(L + 2)
	_rmb()
	_check(int(_p.get("active_form")) == RMB_ID, "same-tick switch to branch (active_form 102)")
	await _until(400, _branch_done)
	_common_branch_checks()
	_check(_rmb_ev("rmb_buffered").is_empty(), "legal press not buffered")
	_check(int(_p.get("action_state")) == 0 and not bool(_p.get("input_locked")), "branch ends FREE, input unlocked")
	_case.forms_seen = _forms_seen()

# ---------------------------------------------------------------- 窗前 0.2 s 右鍵 → 緩衝，到合法格才發
func _sc_rmb_buffer() -> void:
	var L := _ref01_legal_tick()
	_start_ref01()
	await _wait(L - 12)
	_rmb()
	_check(_rmb_ev("rmb_buffered").size() == 1 and int(_p.get("active_form")) == 1, "early press buffered, REF01 continues")
	var box := {"f": -1}   # GDScript lambda 以值捕捉區域變數 → 用 Dictionary 回傳
	await _until(60, func():
		if int(box.f) < 0 and int(_p.get("active_form")) == RMB_ID:
			box.f = _frame
		return int(box.f) >= 0)
	var fire_f: int = box.f
	_case.fire_tick = fire_f
	_case.legal_tick = L
	_check(fire_f >= L and fire_f <= L + 2, "buffered branch fires at the legal tick (%d vs legal %d)" % [fire_f, L])
	await _until(400, _branch_done)
	_common_branch_checks()

# ---------------------------------------------------------------- 窗前 0.6 s 右鍵 → 0.40 s 到期清除，之後不觸發
func _sc_rmb_expire() -> void:
	var L := _ref01_legal_tick()
	_start_ref01()
	var at := maxi(1, L - 36)
	await _wait(at)
	_rmb()
	await _until(400, _branch_done)
	_case.legal_tick = L
	_case.press_tick = at
	_check(_rmb_ev("rmb_buffered").size() == 1, "press buffered")
	_check(_rmb_ev("rmb_expired").size() == 1, "buffer expired")
	_check(_rmb_ev("rmb_start").is_empty(), "no branch after expiry (no surprise trigger)")
	_check(not _forms_seen().has("REF01_RMB"), "REF01 played to its natural end")
	_check(L - at > 24, "press was more than 0.40 s before the legal window")

# ---------------------------------------------------------------- 十三型中 REF01 → 右鍵分支
func _sc_rmb_cycle() -> void:
	_start(false)
	_check(bool(_p.call("r7c_running")), "cycle running")
	var hf := float(_p.call("_r7c_handoff_frame", 1))
	_case.handoff_af = hf
	await _until(200, func(): return _fr() >= hf - 16.0)
	_rmb()
	await _until(400, _branch_done)
	_common_branch_checks()
	_check(_exit_reason() == "rmb_branch", "cycle exit reason rmb_branch")
	_check(_starts() == ["REF01"], "cycle started only REF01 (no REF02)")
	_check(not bool(_p.call("r7c_running")), "cycle not running after branch")
	var after_start := 0
	var seen_branch := false
	for t in _ticks:
		if t.ref == "REF01_RMB":
			seen_branch = true
		elif seen_branch and t.ref != "" and t.ref != "REF01_RMB":
			after_start += 1
	_check(after_start == 0, "nothing pulls the cycle back after the branch")
	var fire: Array = _rmb_ev("rmb_fire")
	_check(fire.size() == 1 and bool(fire[0].cycle), "branch fired from inside the cycle")
	_case.fire_af = fire[0].af if fire.size() > 0 else -1
	_check(fire.size() == 1 and float(fire[0].af) >= hf - 0.01, "cycle branch fires at/after REF01 handoff frame (not inside hit window)")
	await _wait(30)
	_check(not bool(_p.call("r7c_running")) and int(_p.get("action_state")) == 0, "still FREE 0.5 s later (no restart)")

# ---------------------------------------------------------------- 分支中受擊 → 乾淨中斷、恢復操作
func _sc_rmb_hit() -> void:
	var L := _ref01_legal_tick()
	_start_ref01()
	await _wait(L + 2)
	_rmb()
	await _wait(20)
	_check(int(_p.get("active_form")) == RMB_ID, "in branch before hit")
	var r: Dictionary = _p.call("take_hit", {"damage": 5.0, "posture_damage": 5.0, "hit_dir": Vector3(0, 0, -1)})
	_case.hit_result = r
	_check(int(_p.get("active_form")) != RMB_ID and int(_p.get("action_state")) != 1, "hit interrupts branch")
	await _wait(1)   # _r7_form_end 在下一個物理步尾執行（action_state 已離開 ATTACKING）
	_check(not bool(_p.get("_r7_form_on")), "R7 form state cleared (next physics step)")
	_check(float(_p.get("_r7_rmb_left")) == 0.0, "no pending branch after hit")
	await _until(240, func(): return int(_p.get("action_state")) == 0 and float(_p.get("_hitstun_left")) <= 0.0 and float(_p.get("_stagger_left")) <= 0.0)
	var p0: Vector3 = _p.global_position
	Input.action_press("move_forward")
	await _wait(30)
	Input.action_release("move_forward")
	_case.move_after_hit_m = snappedf((_p.global_position - p0).length(), 0.001)
	_check(float(_case.move_after_hit_m) > 0.3, "movement restored after hit")

# ---------------------------------------------------------------- 緩衝中受擊 → 清除，之後不觸發
func _sc_rmb_hit_pending() -> void:
	var L := _ref01_legal_tick()
	_start_ref01()
	await _wait(L - 12)
	_rmb()
	_check(_rmb_ev("rmb_buffered").size() == 1, "press buffered")
	_p.call("take_hit", {"damage": 5.0, "posture_damage": 5.0, "hit_dir": Vector3(0, 0, -1)})
	await _wait(120)
	_check(_rmb_ev("rmb_cleared").size() >= 1, "pending cleared on hit")
	_check(_rmb_ev("rmb_start").is_empty(), "no branch after hit")
	_check(float(_p.get("_r7_rmb_left")) == 0.0, "pending timer zero")

# ---------------------------------------------------------------- 分支後：移動／閃避／普攻恢復
func _sc_rmb_recover() -> void:
	var L := _ref01_legal_tick()
	_start_ref01()
	await _wait(L + 2)
	_rmb()
	await _until(400, _branch_done)
	_common_branch_checks()
	var p0: Vector3 = _p.global_position
	Input.action_press("move_forward")
	await _wait(30)
	Input.action_release("move_forward")
	_case.move_m = snappedf((_p.global_position - p0).length(), 0.001)
	_check(float(_case.move_m) > 0.3, "move after branch")
	await _wait(20)
	_p.call("request_dodge")
	await _wait(2)
	_check(int(_p.get("action_state")) == 2, "dodge after branch")
	await _until(120, func(): return int(_p.get("action_state")) == 0)
	await _wait(10)
	_p.call("request_primary_attack")
	await _wait(2)
	_check(int(_p.get("action_state")) == 1 and int(_p.get("combo_stage")) >= 1, "light attack after branch")
	await _until(200, func(): return int(_p.get("action_state")) == 0)
	# 分支後 REF01 期間外的右鍵＝一般重斬（不被分支攔截）
	await _wait(10)
	_rmb()
	await _wait(2)
	_check(str(_p.get("_active_attack_name")) == "Heavy_Cut", "RMB outside REF01 = ordinary heavy cut")

# ---------------------------------------------------------------- 真實刀路木樁：只命中一次
func _sc_rmb_dummy() -> void:
	var L := _ref01_legal_tick()
	var p0: Vector3 = _p.global_position
	var vis: Node3D = _p.get("_visual")
	var y0 := vis.global_rotation.y
	# A：無木樁，記錄分支命中窗內刀身中段（世界）
	_start_ref01()
	await _wait(L + 2)
	_rmb()
	_samples.clear()
	await _until(400, _branch_done)
	var arr: Array = []
	for key in _samples:
		if String(key).contains("REF01_RMB"):
			arr = _samples[key]
	_check(arr.size() >= 2, "branch hit window sampled (%d steps)" % arr.size())
	if arr.is_empty():
		return
	var mid: Vector3 = arr[arr.size() / 2]
	_case.dummy_pos = [snappedf(mid.x, 0.001), snappedf(mid.y, 0.001), snappedf(mid.z, 0.001)]
	_case.dummy_rel = [snappedf(mid.x - p0.x, 0.001), snappedf(mid.y - p0.y, 0.001), snappedf(mid.z - p0.z, 0.001)]
	# B：回到同一起點／朝向，木樁（半徑 0.15 m，不放大判定）放在 A 的刀路上，同一輸入時刻重跑
	await _wait(20)
	_p.global_position = p0
	_p.velocity = Vector3.ZERO
	vis.global_rotation.y = y0
	await _wait(10)
	var rc := _receiver("dummy_rmb", mid, 0.15)
	_ticks.clear()
	_start_ref01()
	await _wait(L + 2)
	_rmb()
	await _until(400, _branch_done)
	var hits_b := []
	for h in rc.log:
		hits_b.append(h)
	_case.dummy_hits = hits_b
	var on_branch := 0
	for h in hits_b:
		if int(h.form) == RMB_ID:
			on_branch += 1
	_check(on_branch == 1, "branch hits the on-path dummy exactly once (got %d)" % on_branch)
	_check(hits_b.size() == on_branch, "REF01 itself does not hit the branch dummy")
	for h in hits_b:
		_check(int(h.grp) >= 1, "hit inside an open hit group")
