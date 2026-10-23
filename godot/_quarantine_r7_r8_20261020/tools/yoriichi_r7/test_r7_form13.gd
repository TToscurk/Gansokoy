extends SceneTree
## R7 P4 十三型 focused 測試（headless、物理整合、不寫資源）。每個 scenario 用獨立行程跑：
##   godot --headless --fixed-fps 60 --path godot -s res://tools/yoriichi_r7/test_r7_form13.gd -- <scenario>
## 輸出 user://r7_form13/<scenario>.json ＋ stdout 一行 R7C_RESULT。InputMap 實體事件先清空，只用 action_press／InputEventAction。
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"
const REF_ORDER := ["REF01", "REF02", "REF03", "REF04", "REF05", "REF06", "REF07", "REF08", "REF09", "REF10", "REF11", "REF12"]
const TARGETS := "user://r7_form13/targets.json"
var _failures: Array = []
var _case := {}
var _world: Node3D
var _p: CharacterBody3D
var _scenario := ""
var _ticks: Array = []
var _hits: Array = []
var _wins: Array = []
var _hs: Array = []
var _samples := {}
var _frame := 0
var _flags := {}
var _hand: int = -1
var _sk: Skeleton3D

class Receiver extends Area3D:
	var label := ""
	var owner_p: Node = null
	var log: Array = []
	var hp := 1000.0
	func take_hit(data: Dictionary) -> Dictionary:
		hp -= float(data.damage)
		log.append({"label": label, "form": owner_p.get("active_form"), "anim": str(owner_p.get("_active_attack_name")),
			"grp": owner_p.get("r7_hit_group"), "lap": owner_p.get("r7c_lap"), "clock": snappedf(float(owner_p.get("_action_elapsed")), 0.001),
			"dmg": snappedf(float(data.damage), 0.1), "hp": hp})
		return {"result": "hit", "damage": data.damage, "attacker_posture": 0.0}

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	_case.checks.append({"ok": ok, "label": label})
	if not ok:
		_failures.append(label)
		push_error("FAIL %s: %s" % [_scenario, label])

func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	_world.add_child(body)
	return body

func _receiver(label: String, pos: Vector3, r: float) -> Receiver:
	var a := Receiver.new()
	a.label = label
	a.owner_p = _p
	a.collision_layer = 2
	a.collision_mask = 0
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = r
	cs.shape = s
	a.add_child(cs)
	a.position = pos
	_world.add_child(a)
	return a

func _ref() -> String:
	var f: int = _p.get("active_form")
	var forms: Dictionary = _p.get("R7_FORMS")
	return String(forms[f].ref) if forms.has(f) else ""

func _fr() -> float:
	return float(_p.get("_action_elapsed")) * 60.0

func _setup() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	_p = (load(PLAYER) as PackedScene).instantiate()
	_p.set("r7_vfx_enabled", false)
	_p.set("sun_mastery", 100)
	_p.set("sun_breath_gauge", 100.0)
	_p.set("form13_unlocked", true)
	_world.add_child(_p)
	_p.set_physics_process(false)
	await process_frame
	_p.set_process_unhandled_input(_scenario in ["lap2", "recover"])
	_p.set_physics_process(true)
	for i in 12:
		await physics_frame
	_p.call("request_draw")
	for i in 100:
		await physics_frame
	_sk = (_p.get("_visual") as Node).find_children("*", "Skeleton3D", true, false)[0]
	_hand = _sk.find_bone("mixamorig_RightHand")
	_check(_p.is_on_floor() and int(_p.get("sword_state")) == 2, "ready: drawn and grounded")

func _press_form13() -> void:
	Input.action_press("form13")
	var ev := InputEventAction.new()
	ev.action = "form13"
	ev.pressed = true
	_case.input_gate = {"input_locked": _p.get("input_locked"), "anims_ready": _p.get("_combat_anims_ready"), "uh": _p.is_processing_unhandled_input()}
	root.push_input(ev)   # 同步經 Viewport 分派到 _unhandled_input（父類 form13 分支）
	_case.input_route = "viewport.push_input"
	if not bool(_p.call("r7c_running")):
		# headless 下 Viewport 分派未到達 → 直接呼叫同一個 _unhandled_input 處理器（父類 form13 分支 → R7 start_form13）
		_p.call("_unhandled_input", ev)
		_case.input_route = "_unhandled_input(InputEventAction) direct"

func _release_form13() -> void:
	Input.action_release("form13")
	var ev := InputEventAction.new()
	ev.action = "form13"
	ev.pressed = false
	Input.parse_input_event(ev)

func _start(hold := true) -> bool:
	if hold:
		Input.action_press("form13")
	else:
		_p.set("r7c_hold_to_continue", false)
	return bool(_p.call("start_form13"))

func _hand_w() -> Vector3:
	return _sk.global_transform * _sk.get_bone_global_pose(_hand).origin

## 一個物理步的紀錄＋命中窗／hitstop 量測
var _prev_grp := 0
var _prev_hand := Vector3.ZERO
var _prev_pos := Vector3.ZERO
func _tick() -> void:
	_frame += 1
	var grp: int = _p.get("r7_hit_group")
	var ref := _ref()
	var row := {"f": _frame, "ref": ref, "anim": str(_p.get("_active_attack_name")), "af": snappedf(_fr(), 0.1), "grp": grp,
		"st": _p.get("action_state"), "air": _p.get("r7_air_phase"), "y": snappedf(_p.position.y, 0.001), "floor": _p.is_on_floor(),
		"run": _p.call("r7c_running"), "lap": _p.get("r7c_lap"), "os": _p.get("_tree").get("parameters/full/internal_active")}
	_ticks.append(row)
	if grp != _prev_grp:
		if _prev_grp > 0 and not _wins.is_empty():
			_wins[-1].close_af = row.af
			_wins[-1].close_f = _frame
		if grp > 0:
			_wins.append({"lap": row.lap, "ref": ref, "anim": row.anim, "grp": grp, "open_af": row.af, "open_f": _frame})
		_prev_grp = grp
	if grp > 0:
		var tr: Array = _p.get("r7_blade_trace")
		if not tr.is_empty():
			var key := "%d|%s|%d" % [row.lap, ref, grp]
			if not _samples.has(key):
				_samples[key] = []
			_samples[key].append(tr[-1][2][2])
	var hs := float(_p.get("_hitstop_time"))
	var hw := _hand_w()
	if hs > 0.0:
		_hs.append({"f": _frame, "ref": ref, "hitstop": snappedf(hs, 0.001), "af": row.af,
			"hand_move_mm": snappedf((hw - _prev_hand).length() * 1000.0, 0.1), "body_move_mm": snappedf((_p.position - _prev_pos).length() * 1000.0, 0.1)})
	_prev_hand = hw
	_prev_pos = _p.position

func _until(max_frames: int, stop: Callable, inject: Callable = Callable()) -> void:
	for i in max_frames:
		if inject.is_valid():
			inject.call()
		await physics_frame
		_tick()
		if stop.call():
			return

func _starts() -> Array:
	var out := []
	for e in _p.get("r7c_log"):
		if e.ev == "start":
			out.append(e.ref)
	return out

func _exit_reason() -> String:
	return String(_p.get("r7c_exit"))

func _not_running() -> bool:
	return not bool(_p.call("r7c_running"))

func _free_after() -> bool:
	return not bool(_p.call("r7c_running")) and int(_p.get("action_state")) == 0

## 循環中：action_state 不離開 ATTACKING、OneShot 不中斷（不回 locomotion）、交接格沒有命中組
func _check_continuity() -> void:
	var gap_state := 0
	var gap_os := 0
	for t in _ticks:
		if t.run:
			if t.st != 1:
				gap_state += 1
			if not t.os:
				gap_os += 1
	_case.continuity = {"non_attacking_ticks_while_running": gap_state, "oneshot_inactive_ticks_while_running": gap_os}
	_check(gap_state == 0, "cycle never drops to FREE between forms")
	_check(gap_os == 0, "full OneShot stays active across handoffs (no return to locomotion)")

func _check_hits_in_windows() -> void:
	var bad := 0
	for rc in _world.get_children():
		if rc is Receiver:
			for h in rc.log:
				_hits.append(h)
				if int(h.grp) <= 0:
					bad += 1
	_check(bad == 0, "every damage event inside an open hit group (no handoff damage)")

func _run() -> void:
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	var args := OS.get_cmdline_user_args()
	_scenario = args[0] if args.size() > 0 else "lap2"
	_case = {"scenario": _scenario, "checks": []}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://r7_form13/"))
	await _setup()
	await call("_sc_" + _scenario)
	_case.log = _p.get("r7c_log")
	_case.exit = _exit_reason()
	_case.starts = _starts()
	_case.windows = _wins
	_case.hits = _hits
	_case.hitstop = _hs
	var f := FileAccess.open("user://r7_form13/%s.json" % _scenario, FileAccess.WRITE)
	f.store_string(JSON.stringify(_case, "\t"))
	f.close()
	var ok := 0
	for c in _case.checks:
		ok += int(c.ok)
	print("R7C_RESULT scenario=", _scenario, " checks=", _case.checks.size(), " pass=", ok, " failures=", _failures.size(), " exit=", _case.exit, " starts=", _case.starts.size())
	for fl in _failures:
		print("  FAIL ", fl)
	Input.action_release("form13")
	quit(0 if _failures.is_empty() else 1)

# ---------------------------------------------------------------- scenarios
func _sc_lap2() -> void:
	# 公開輸入：InputEventAction(form13) → 父類 _unhandled_input → start_form13（R7 覆寫）；按住兩圈後鬆開
	_press_form13()
	await physics_frame
	_check(bool(_p.call("r7c_running")), "public form13 action starts the cycle")
	await _until(2400, func(): return _starts().size() >= 14)
	_release_form13()
	await _until(400, _free_after)
	var st := _starts()
	var want := REF_ORDER + REF_ORDER + ["REF01", "REF02"]
	_check(st.slice(0, 14) == want.slice(0, 14), "REF order REF01→REF12→REF01→… (two laps)")
	_check(st.size() == 14, "release stops after current form (no extra form)")
	_check(_exit_reason() == "stop", "exit reason stop")
	_check(int(_p.get("r7c_lap")) == 2, "second lap reached")
	var ids := []
	for e in _p.get("r7c_log"):
		if e.ev == "start":
			ids.append(e.id)
	_case.id_sequence = ids
	_check(ids.slice(0, 12) == [1, 2, 3, 11, 10, 4, 8, 6, 5, 7, 9, 12], "legacy ID sequence 1,2,3,11,10,4,8,6,5,7,9,12")
	_check_continuity()
	var lap1_end := -1
	for t in _ticks:
		if t.lap == 2:
			lap1_end = t.f
			break
	_case.lap1_seconds = snappedf(float(lap1_end) / 60.0, 0.01)
	_case.anim_by_ref = {}
	for e in _p.get("r7c_log"):
		if e.ev == "start":
			_case.anim_by_ref[e.ref] = e.anim
	# P4 接縫修補：循環中 REF09 播的是 MX 的派生 clip（R7C_Sun09_ShayouTenshinMX_from_Sun08），單招仍是原 MX
	var a09 := String(_case.anim_by_ref.get("REF09", ""))
	_check(a09 == "R7_Sun09_ShayouTenshinMX" or a09.begins_with("R7C_Sun09_ShayouTenshinMX_"), "REF09 plays MX resource")
	# 每型命中窗（authored 格）
	var wref := {}
	for w in _wins:
		if w.lap == 1:
			wref[w.ref] = int(wref.get(w.ref, 0)) + 1
	_case.windows_lap1 = wref
	for r in REF_ORDER:
		if r != "REF04":
			_check(int(wref.get(r, 0)) >= 1, "hit window opened in lap 1 for " + r)
	_check(not wref.has("REF04"), "REF04 (evade) opens no damage window")
	var free_move_ok: bool = int(_p.get("action_state")) == 0 and not bool(_p.get("input_locked"))
	_check(free_move_ok, "after stop: FREE, input not locked")

func _sc_trace() -> void:
	# 一圈、無目標；記錄每型每命中組刀身中段位置（世界）→ targets.json，給 hits 情境放木樁
	_start(false)
	await _until(1200, func(): return _starts().size() >= 12 and _ref() == "REF12" and _fr() > 40.0)
	_p.call("r7c_request_stop")
	await _until(300, _free_after)
	var tg := {}
	for key in _samples:
		var arr: Array = _samples[key]
		var mid: Vector3 = arr[arr.size() / 2]
		tg[key] = [mid.x, mid.y, mid.z]
	var f := FileAccess.open(TARGETS, FileAccess.WRITE)
	f.store_string(JSON.stringify(tg))
	f.close()
	_case.targets = tg
	_check(tg.size() >= 13, "sampled blade positions for every hit group (11 forms, 15 groups)")

func _sc_hits() -> void:
	# 依 trace 實際刀路放木樁（半徑 0.15 m，不放大判定）；每型一個標示木樁
	var tg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TARGETS))
	var placed := {}
	for key in tg:
		var parts: PackedStringArray = String(key).split("|")
		if parts[2] != "1":
			continue   # 每型只放第一組的位置；雙段／三段型的後續組靠同一木樁或其他組驗證
		var v: Array = tg[key]
		placed[parts[1]] = _receiver("dummy_" + parts[1], Vector3(v[0], v[1], v[2]), 0.15)
	_case.dummies = placed.keys()
	_start(false)
	await _until(1200, func(): return _starts().size() >= 12 and _ref() == "REF12" and _fr() > 70.0)
	_p.call("r7c_request_stop")
	await _until(300, _free_after)
	_check_hits_in_windows()
	var by := {}
	for h in _hits:
		var forms: Dictionary = _p.get("R7_FORMS")
		var r: String = forms[int(h.form)].ref
		if not by.has(r):
			by[r] = []
		by[r].append("%s g%d hp=%d" % [h.label, h.grp, int(h.hp)])
	_case.hits_by_ref = by
	var hitc := 0
	for r in REF_ORDER:
		if r != "REF04" and by.has(r):
			hitc += 1
	_case.forms_with_hits = hitc
	_check(hitc >= 9, "real blade sweep hits for >= 9 of 11 damaging forms (per-form receivers)")
	# 去重：同一刀同一組同一木樁至多一次
	var seen := {}
	var dup := 0
	for h in _hits:
		var k := "%s|%d|%d|%s" % [h.form, h.lap, h.grp, h.label]
		if seen.has(k):
			dup += 1
		seen[k] = true
	_check(dup == 0, "per-group dedupe: no repeated damage within one hit group")

func _sc_release_mid() -> void:
	_start(true)
	await _until(400, func(): return _ref() == "REF03" and _fr() > 10.0)
	Input.action_release("form13")
	await _until(300, _free_after)
	_check(_starts() == ["REF01", "REF02", "REF03"], "release during REF03 finishes REF03 only")
	_check(_exit_reason() == "stop", "exit stop")

func _sc_release_wait() -> void:
	_start(true)
	await _until(900, func(): return _ref() == "REF05" and int(_p.get("r7_air_phase")) >= 1 and not _p.is_on_floor() and _fr() > 50.0)
	var y0 := _p.position.y
	Input.action_release("form13")
	await physics_frame
	_tick()
	_check(not _p.is_on_floor() and bool(_p.call("r7c_running")), "stop request recorded while airborne, cycle not cut mid-air")
	await _until(300, _free_after)
	var min_y := 99.0
	for t in _ticks:
		min_y = minf(min_y, t.y)
	_check(_starts().back() == "REF05" and _exit_reason() == "stop", "after landing REF05 recovers then stops")
	_check(_p.is_on_floor() and min_y < y0, "gravity kept running (real landing)")

# ---- 固定輸入時刻（玩家真實輸入）：輸入時刻＝循環起手後第 N 個物理步，不看系統是否宣告合法。
# N 由無輸入時間軸（timeline 情境，決定性）換算 (REF, af) → tick；之後只在該 tick 送輸入。
const TIMELINE := "user://r7_form13/timeline_rows.json"
const BUF_TICKS := 24   # r7c_dodge_buffer_time 0.40 s × 60

func _tl() -> Array:
	if not FileAccess.file_exists(TIMELINE):
		return []
	return JSON.parse_string(FileAccess.get_file_as_string(TIMELINE))

func _tick_of(tl: Array, ref: String, af: float, lap := 1) -> int:
	for r in tl:
		if r.ref == ref and int(r.lap) == lap and float(r.af) >= af:
			return int(r.f)
	return -1

## 接縫 k：REF(k) → 下一型的第一個 tick（REF12 → 第二圈 REF01）
func _seam_tick(tl: Array, k: int) -> int:
	var nxt: String = REF_ORDER[(k + 1) % 12]
	var lap := 2 if k == 11 else 1
	for r in tl:
		if r.ref == nxt and int(r.lap) == lap:
			return int(r.f)
	return -1

## 從 tick t 起，第一個合法取消 tick（修後時間軸 safe 欄；修前控制器沒有此欄 → 用 cancel_ok）
func _next_safe(tl: Array, t: int) -> int:
	for r in tl:
		if int(r.f) >= t and bool(r.get("safe", r.cancel_ok)):
			return int(r.f)
	return -1

func _sc_timeline() -> void:
	# 無輸入時間軸：每 tick 的 (REF, authored af, lap, 合法點)。修前控制器沒有 _r7c_safe_point → 只記 cancel_ok。
	_start(true)
	var rows := []
	var has_safe := _p.has_method("_r7c_safe_point")
	var spd := float(_p.get("r7_sun_speed"))
	for i in 2400:
		await physics_frame
		_frame += 1
		var row := {"f": _frame, "ref": _ref(), "lap": int(_p.get("r7c_lap")), "af": snappedf(float(_p.get("_action_elapsed")) * spd * 30.0, 0.1),
			"floor": _p.is_on_floor(), "air": int(_p.get("r7_air_phase")), "cancel_ok": bool(_p.call("r7_form_cancel_ok"))}
		if has_safe:
			row.safe = bool(_p.call("_r7c_safe_point"))
		rows.append(row)
		if int(_p.get("r7c_lap")) >= 2 and _ref() == "REF02" or _not_running():
			break
	Input.action_release("form13")
	var f := FileAccess.open(TIMELINE, FileAccess.WRITE)
	f.store_string(JSON.stringify(rows))
	f.close()
	var nsafe := 0
	var ncan := 0
	for r in rows:
		if int(r.lap) == 1:
			nsafe += int(bool(r.get("safe", false)))
			ncan += int(bool(r.cancel_ok))
	_case.lap1_cancel_ok_ticks = ncan
	_case.lap1_safe_ticks = nsafe
	_check(rows.size() > 600, "timeline recorded through lap 2")

## 一個固定時刻案例（自行重建場景）。kind: dodge | move。
func _fixed_case(kind: String, label: String, t_in: int, tl: Array) -> Dictionary:
	await _teardown_setup()
	_start(true)
	var res := {"case": label, "kind": kind, "in_tick": t_in}
	var state := {"rolled": -1, "exit": -1}
	await _until(t_in + 420, func(): return state.exit >= 0 and (kind == "move" or state.rolled >= 0 or _frame > state.exit + 30), func():
		if _frame == t_in:
			res.in_ref = _ref()
			res.in_af = snappedf(_fr() * float(_p.get("r7_sun_speed")) * 0.5, 0.1)
			res.in_floor = _p.is_on_floor()
			if kind == "dodge":
				_p.call("request_dodge")
				if int(_p.get("action_state")) == 2 and state.rolled < 0:
					state.rolled = _frame
			else:
				Input.action_press("move_forward")
		if state.exit < 0 and _frame >= t_in and _not_running():
			state.exit = _frame
			res.exit_ref = String(_p.get("r7c_log").back().get("last", ""))
		if state.rolled < 0 and _frame >= t_in and int(_p.get("action_state")) == 2:
			state.rolled = _frame)
	Input.action_release("move_forward")
	Input.action_release("form13")
	res.exit_tick = state.exit
	res.exit_reason = _exit_reason() if state.exit >= 0 else "still_running"
	res.latency = (state.exit - t_in) if state.exit >= 0 else -1
	res.roll_tick = state.rolled
	res.next_safe = _next_safe(tl, t_in)
	res.starts = _starts().size()
	var ev := []
	for e in _p.get("r7c_log"):
		if String(e.ev).begins_with("dodge") or e.ev == "move_exit" or e.ev == "stop_request" or e.ev == "exit":
			ev.append(e)
	res.events = ev
	return res

func _teardown_setup() -> void:
	Input.action_release("move_forward")
	Input.action_release("form13")
	if _world != null:
		_world.queue_free()
		await process_frame
		await physics_frame
	_ticks.clear()
	_wins.clear()
	_frame = 0
	_prev_grp = 0
	await _setup()

## 判定：地面輸入 → 在第一個合法點（timeline next_safe）退出（容許 1 tick）；閃避若下一合法點超過緩衝 → 不翻滾、循環繼續。
## 空中輸入 → 不強制著地：記停止意圖，落地後本型收完（stop）或到合法點退出。
func _judge(r: Dictionary) -> void:
	var gap: int = int(r.next_safe) - int(r.in_tick)
	var air := not bool(r.get("in_floor", true))
	if r.kind == "move":
		if air:
			_check(r.exit_reason in ["move", "stop"] and r.exit_ref == r.in_ref, "%s: airborne move → stop intent, exits after landing of same form" % r.case)
		else:
			_check(r.exit_reason == "move" and int(r.latency) <= gap + 1, "%s: move exits at first safe point (lat %d, gap %d)" % [r.case, r.latency, gap])
	else:
		if air:
			_check(r.exit_reason in ["dodge", "stop"] and r.exit_ref == r.in_ref, "%s: airborne dodge → no forced landing, no next form" % r.case)
		elif gap <= BUF_TICKS:
			_check(r.exit_reason == "dodge" and int(r.roll_tick) >= 0 and int(r.latency) <= gap + 1, "%s: buffered dodge rolls at first safe point (lat %d, gap %d)" % [r.case, r.latency, gap])
		else:
			var expired := false
			for e in r.events:
				if e.ev == "dodge_expired":
					expired = true
			_check(expired and int(r.roll_tick) < 0, "%s: dodge older than buffer expires, no later roll" % r.case)

func _fixed_list(tl: Array, group: String) -> Array:
	var out := []
	if group in ["core", "all"]:
		out.append(["dodge", "dodge REF01 af13", _tick_of(tl, "REF01", 13)])
		out.append(["dodge", "dodge REF02 af20", _tick_of(tl, "REF02", 20)])
		out.append(["move", "move REF01 af13", _tick_of(tl, "REF01", 13)])
		out.append(["move", "move REF02 af20", _tick_of(tl, "REF02", 20)])
		out.append(["move", "move REF04 af5", _tick_of(tl, "REF04", 5)])
		out.append(["dodge", "dodge REF11 af20 (expire)", _tick_of(tl, "REF11", 20)])
	if group in ["seam_dodge", "all"]:
		for k in 12:
			var st := _seam_tick(tl, k)
			out.append(["dodge", "dodge seam %s→%s -3" % [REF_ORDER[k], REF_ORDER[(k + 1) % 12]], st - 3])
			out.append(["dodge", "dodge seam %s→%s +3" % [REF_ORDER[k], REF_ORDER[(k + 1) % 12]], st + 3])
	if group in ["seam_move", "all"]:
		for k in 12:
			var st := _seam_tick(tl, k)
			out.append(["move", "move seam %s→%s -3" % [REF_ORDER[k], REF_ORDER[(k + 1) % 12]], st - 3])
			out.append(["move", "move seam %s→%s +3" % [REF_ORDER[k], REF_ORDER[(k + 1) % 12]], st + 3])
	return out

func _sc_fixed() -> void:
	var args := OS.get_cmdline_user_args()
	var group: String = args[1] if args.size() > 1 else "core"
	var judge: bool = not (args.size() > 2 and args[2] == "nojudge")
	var tl := _tl()
	_check(not tl.is_empty(), "timeline.json present (run scenario timeline first)")
	var rows := []
	for c in _fixed_list(tl, group):
		var r: Dictionary = await _fixed_case(c[0], c[1], int(c[2]), tl)
		rows.append(r)
		print("R7C_FIXED ", JSON.stringify({"case": r.case, "in": "%s af%s t%d" % [r.get("in_ref", "?"), r.get("in_af", "?"), r.in_tick],
			"exit_t": r.exit_tick, "lat": r.latency, "why": r.exit_reason, "roll_t": r.roll_tick, "next_safe": r.next_safe, "exit_ref": r.get("exit_ref", "")}))
		if judge:
			_judge(r)
	_case.fixed = rows
	_case.group = group

func _sc_move_cancel() -> void:
	# 固定時刻：REF01 af13 開始按住移動（不等系統宣告合法）→ 應在 REF01 接出格附近退出
	var tl := _tl()
	var r: Dictionary = await _fixed_case("move", "move REF01 af13", _tick_of(tl, "REF01", 13), tl)
	_case.fixed = [r]
	_judge(r)
	_check(r.exit_ref == "REF01", "REF01 af13 move exits during REF01 (not dragged to REF03)")
	var p0 := _p.position
	Input.action_press("move_forward")
	for i in 25:
		await physics_frame
		_tick()
	Input.action_release("move_forward")
	_check((_p.position - p0).length() > 0.5, "movement resumes after cancel")

func _sc_dodge() -> void:
	# 固定時刻：REF01 af13 單次閃避（不等合法）→ 緩衝到 REF01 接出格翻滾
	var tl := _tl()
	var r: Dictionary = await _fixed_case("dodge", "dodge REF01 af13", _tick_of(tl, "REF01", 13), tl)
	_case.fixed = [r]
	_judge(r)
	_check(r.exit_reason == "dodge" and r.exit_ref == "REF01" and int(r.starts) == 1, "dodge exits from REF01, REF02 never starts")
	await _until(120, func(): return int(_p.get("action_state")) == 0)
	_check(int(_p.get("action_state")) == 0, "roll completes, FREE")

## 單招（非循環）閃避取消規則不變：取消點前的閃避被丟棄（無緩衝）、取消點後可翻滾
func _sc_single_dodge() -> void:
	var a: Animation = (_p.get("_anim") as AnimationPlayer).get_animation("R7_Sun01_Enbu")
	var cancel_t: float = 0.70 * a.length / float(_p.get("r7_sun_speed"))
	_check(bool(_p.call("execute_form", 1, true)), "single REF01 starts")
	for i in 13:
		await physics_frame
	_p.call("request_dodge")
	var early_state: int = _p.get("action_state")
	var rolled_later := false
	while float(_p.get("_action_elapsed")) < cancel_t - 0.02:
		await physics_frame
		if int(_p.get("action_state")) == 2:
			rolled_later = true
	_check(early_state == 1 and not rolled_later, "single form: early dodge dropped, no buffered roll")
	for i in 4:
		await physics_frame
	_p.call("request_dodge")
	_case.late_state = _p.get("action_state")
	_check(int(_p.get("action_state")) == 2, "single form: dodge after cancel point rolls")
	await _until(120, func(): return int(_p.get("action_state")) == 0)

func _sc_hit() -> void:
	_start(true)
	await _until(300, func(): return _ref() == "REF02" and _fr() > 20.0)
	var r: Dictionary = _p.call("take_hit", {"damage": 5.0, "posture_damage": 5.0, "hit_dir": Vector3(0, 0, -1)})
	_case.hit_result = r
	await _until(150, func(): return float(_p.get("_hitstun_left")) <= 0.0 and int(_p.get("action_state")) == 0)
	Input.action_release("form13")
	_check(_exit_reason() == "hit", "ground hit interrupts cycle (reason hit)")
	_check(_starts() == ["REF01", "REF02"], "no next form after hit")
	var p0 := _p.position
	Input.action_press("move_forward")
	for i in 25:
		await physics_frame
	Input.action_release("move_forward")
	_check((_p.position - p0).length() > 0.5, "movement recovers after hit")

func _sc_wait_hit() -> void:
	_start(true)
	await _until(900, func(): return _ref() == "REF05" and not _p.is_on_floor() and _fr() > 50.0)
	var phase: int = _p.get("r7_air_phase")
	_p.call("take_hit", {"damage": 5.0, "posture_damage": 5.0, "hit_dir": Vector3(0, 0, -1)})
	await _until(240, func(): return _p.is_on_floor() and int(_p.get("action_state")) == 0 and float(_p.get("_hitstun_left")) <= 0.0)
	Input.action_release("form13")
	_case.phase_at_hit = phase
	_check(_exit_reason() == "hit", "airborne hit interrupts cycle")
	_check(_p.is_on_floor() and _starts().back() == "REF05", "falls to real ground, no further form")

func _sc_death() -> void:
	_start(true)
	await _until(400, func(): return _ref() == "REF03" and _fr() > 14.0)
	_p.posture.health = 1.0
	var hp_before := 0
	for rc in _world.get_children():
		if rc is Receiver:
			hp_before += 1
	_p.call("take_hit", {"damage": 999.0, "posture_damage": 999.0, "hit_dir": Vector3(0, 0, -1)})
	await _until(60, func(): return false)
	Input.action_release("form13")
	_check(_exit_reason() == "death", "death exits cycle with reason death")
	_check(int(_p.get("action_state")) == 0 and int(_p.get("r7_hit_group")) == 0 and not bool(_p.get("_hitbox").monitoring), "dead: no attack state, no damage window")
	_check(_starts().back() == "REF03", "no next form after death")

func _sc_ceiling() -> void:
	_start(true)
	var placed := [false]
	await _until(900, _not_running, func():
		if not placed[0] and _ref() == "REF05" and not _p.is_on_floor() and _p.velocity.y > 0.0:
			placed[0] = true
			_box(_p.position + Vector3(0, 2.3, 0), Vector3(6, 0.2, 6)))
	await _until(240, func(): return _p.is_on_floor())
	Input.action_release("form13")
	_check(_exit_reason() == "ceiling", "ceiling during REF05 aborts cycle (ceiling)")
	_check(_p.is_on_floor() and int(_p.get("action_state")) == 0, "falls back to ground, FREE")

func _sc_early() -> void:
	_start(true)
	var placed := [false]
	await _until(900, _not_running, func():
		if not placed[0] and _ref() == "REF05" and not _p.is_on_floor() and _p.velocity.y < 0.0 and _p.position.y > 0.6:
			placed[0] = true
			_box(_p.position + Vector3(0, -0.45, 0), Vector3(3, 0.6, 3)))
	await _until(120, func(): return _p.is_on_floor())
	Input.action_release("form13")
	_check(_exit_reason() == "early_contact", "early landing aborts cycle (early_contact)")

func _sc_wall() -> void:
	var vis: Node3D = _p.get("_visual")
	var fwd := vis.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var w := _box(fwd * 1.2 + Vector3.UP * 2.0, Vector3(10, 4, 0.2))
	w.rotation.y = atan2(fwd.x, fwd.z)
	_start(false)
	var max_d := [-9.0]
	await _until(1200, func(): return _starts().size() >= 12 and _ref() == "REF12" and _fr() > 40.0, func(): max_d[0] = maxf(max_d[0], _p.position.dot(fwd)))
	_p.call("r7c_request_stop")
	await _until(300, _free_after)
	_case.max_forward_m = max_d[0]
	_check(max_d[0] < 1.2 - 0.25, "body never passes wall (capsule stays in front)")
	_check(_starts().size() == 12 or _exit_reason() in ["ceiling", "early_contact", "timeout"], "cycle completes or exits via existing abort")
	_check_continuity()

func _sc_breath() -> void:
	_p.set("form13_unlocked", false)
	_p.set("sun_breath_gauge", 100.0)
	_check(_start(true), "locked: full gauge starts cycle")
	_check(is_zero_approx(float(_p.get("sun_breath_gauge"))), "gauge consumed on start")
	await _until(1500, _free_after)
	Input.action_release("form13")
	_check(_exit_reason() == "breath", "insufficient gauge at lap end exits (breath)")
	_check(_starts().size() == 12 and _starts().back() == "REF12", "full lap played, no wrap without resources")
	_p.set("sun_breath_gauge", 50.0)
	Input.action_press("form13")
	_check(not bool(_p.call("start_form13")), "refuse start with 50/100 gauge")
	Input.action_release("form13")
	_check(is_equal_approx(float(_p.get("sun_breath_gauge")), 50.0) and int(_p.get("action_state")) == 0, "refusal costs nothing")

func _sc_missing() -> void:
	var anim: AnimationPlayer = _p.get("_anim")
	for ln in anim.get_animation_library_list():
		var lib := anim.get_animation_library(ln)
		if lib.has_animation("R7_Sun08_HirinKagerou"):
			lib.remove_animation("R7_Sun08_HirinKagerou")
	var g := float(_p.get("sun_breath_gauge"))
	_check(not bool(_p.call("start_form13")), "missing REF08 refuses start")
	var lg: Array = _p.get("r7c_log")
	_check(not lg.is_empty() and String(lg.back().get("reason", "")) == "missing:REF08", "reason missing:REF08")
	_check(is_equal_approx(float(_p.get("sun_breath_gauge")), g) and int(_p.get("action_state")) == 0, "no cost, no state change")

func _sc_dummy() -> void:
	# 與擷取相同：正式 training_dummy（enemies 群組）在正前 1.6 m，按住兩圈
	var d: Node3D = (load("res://characters/combat/training_dummy.tscn") as PackedScene).instantiate()
	_world.add_child(d)
	var vis: Node3D = _p.get("_visual")
	var fw := vis.global_basis.z
	fw.y = 0
	d.global_position = _p.global_position + fw.normalized() * 1.6
	d.add_to_group("enemies")
	_start(true)
	await _until(2400, func(): return _starts().size() >= 14 or _not_running())
	Input.action_release("form13")
	await _until(400, _free_after)
	_case.dummy_hp = d.get("health") if d.get("health") != null else (d.get("posture").health if d.get("posture") != null else null)
	_case.air_exit = String(_p.get("r7_air_exit"))
	_check(_starts().size() >= 14, "two laps with a real dummy in front")


func _sc_recover() -> void:
	_start(true)
	await _until(300, func(): return _ref() == "REF02")
	Input.action_release("form13")
	await _until(300, _free_after)
	_p.call("request_primary_attack")
	await physics_frame
	_check(int(_p.get("action_state")) == 1 and int(_p.get("combo_stage")) >= 1, "light attack works after cycle")
	await _until(120, func(): return int(_p.get("action_state")) == 0)
	_p.call("request_dodge")
	await physics_frame
	_check(int(_p.get("action_state")) == 2, "dodge works after cycle")
	await _until(120, func(): return int(_p.get("action_state")) == 0)
	_p.get("_form_cooldowns").clear()   # 只為立即再測一次入口；冷卻本身另有 lap2 覆蓋
	_press_form13()
	await physics_frame
	_check(bool(_p.call("r7c_running")), "form13 can start again")
	_release_form13()
	await _until(300, _free_after)


# ---------------------------------------------------------------- R7 P5 (A) 邊界
## REF09 MX 空中三段（離地上升／空中有效斬擊／下降）各送一次公開 request_dodge（每段重建場景；form13 全程按住）
func _air_dodge_case(phase: String) -> Dictionary:
	await _teardown_setup()
	_start(true)
	var res := {"phase": phase, "in_tick": -1, "land_tick": -1, "expire_tick": -1, "exit_tick": -1, "roll_tick": -1,
		"air_roll_ticks": 0, "land_recover_seen": false, "min_y_after": 99.0, "land_y": 99.0}
	var st := {"sent": false, "closed09": false}
	await _until(1500, func(): return st.sent and res.exit_tick >= 0 and _frame > res.exit_tick + 40, func():
		var ref := _ref()
		var air := not _p.is_on_floor()
		var grp: int = _p.get("r7_hit_group")
		if ref == "REF09" and air and grp == 0 and not _wins.is_empty() and _wins[-1].ref == "REF09" and _wins[-1].has("close_f"):
			st.closed09 = true
		if not st.sent and ref == "REF09" and air:
			var ok := false
			if phase == "rise":
				ok = _p.velocity.y > 0.5 and grp == 0
			elif phase == "active":
				ok = grp > 0
			else:
				ok = _p.velocity.y < -0.5 and grp == 0 and st.closed09
			if ok:
				st.sent = true
				res.in_tick = _frame + 1
				res.in_af = snappedf(_fr() * float(_p.get("r7_sun_speed")) * 0.5, 0.1)
				res.in_vy = snappedf(_p.velocity.y, 0.01)
				res.in_grp = grp
				res.in_air_phase = int(_p.get("r7_air_phase"))
				res.in_y = snappedf(_p.position.y, 0.001)
				_p.call("request_dodge")
				res.after_call_state = int(_p.get("action_state"))
				res.after_call_buffer = snappedf(float(_p.get("_r7c_dodge_left")), 0.001)
				res.after_call_stop = bool(_p.get("_r7c_stop_req"))
		if st.sent and _frame >= res.in_tick:
			res.min_y_after = minf(res.min_y_after, _p.position.y)
			if int(_p.get("action_state")) == 2 and (air or res.land_tick < 0):
				res.air_roll_ticks += 1
			if res.land_tick < 0 and not air:
				res.land_tick = _frame
				res.land_y = snappedf(_p.position.y, 0.001)
			if int(_p.get("r7_air_phase")) == 4:
				res.land_recover_seen = true
			if res.roll_tick < 0 and int(_p.get("action_state")) == 2:
				res.roll_tick = _frame
			if res.exit_tick < 0 and _not_running():
				res.exit_tick = _frame
			if res.expire_tick < 0:
				for e in _p.get("r7c_log"):
					if e.ev == "dodge_expired":
						res.expire_tick = _frame
						break)
	Input.action_release("form13")
	res.exit_reason = _exit_reason()
	res.starts = _starts()
	var ev := []
	for e in _p.get("r7c_log"):
		if String(e.ev).begins_with("dodge") or e.ev in ["stop_request", "exit"]:
			ev.append(e)
	res.events = ev
	return res

func _sc_air_dodge09() -> void:
	var rows := []
	for ph in ["rise", "active", "fall"]:
		var r: Dictionary = await _air_dodge_case(ph)
		rows.append(r)
		print("R7C_AIRDODGE ", JSON.stringify({"phase": ph, "in": r.in_tick, "in_af": r.get("in_af"), "vy": r.get("in_vy"), "grp": r.get("in_grp"),
			"land": r.land_tick, "expire": r.expire_tick, "roll": r.roll_tick, "exit": r.exit_tick, "why": r.exit_reason,
			"last": (r.starts.back() if not r.starts.is_empty() else "")}))
		var p := "REF09 %s: " % ph
		_check(r.in_tick >= 0, p + "input sent while airborne in phase")
		if r.in_tick < 0:
			continue
		_check(int(r.after_call_state) == 1 and float(r.after_call_buffer) > 0.0 and bool(r.after_call_stop), p + "dodge buffered + stop intent recorded, still ATTACKING")
		_check(int(r.air_roll_ticks) == 0, p + "never enters ground roll while airborne")
		_check(r.land_tick > r.in_tick and float(r.land_y) < 0.05 and r.land_recover_seen, p + "gravity -> real landing -> LAND_RECOVER (absorb)")
		_check(r.starts.back() == "REF09" and not r.starts.has("REF10"), p + "no auto next form (REF10 never starts)")
		_check(r.exit_reason in ["stop", "dodge"] and r.exit_tick > r.land_tick, p + "cycle stops after landing (stop/dodge)")
		if r.roll_tick >= 0:
			_check(r.roll_tick - r.in_tick <= BUF_TICKS + 1 and r.expire_tick < 0, p + "roll only inside 0.4 s buffer")
		else:
			_check(r.exit_reason == "stop", p + "buffer expired -> no late roll, stop intent kept (exit stop)")
	_case.air_dodge = rows

## 真實高落差：REF05 起跳且 hold 判定已完成後，地面整片下移 4 m（物理落下，不寫角色高度）→ 動畫到觸地格仍在空中 → WAIT_CONTACT；
## 先建立閃避暫存＋停止意圖，再受擊一次。
func _sc_wait_contact_hit() -> void:
	var floor_body: StaticBody3D = null
	for c in _world.get_children():
		if c is StaticBody3D:
			floor_body = c
			break
	_start(true)
	var st := {"dropped": false, "wc": false}
	await _until(1500, func(): return st.wc, func():
		if not st.dropped and _ref() == "REF05" and not _p.is_on_floor() and bool(_p.get("_r7_air_launched")) \
				and bool(_p.get("_r7_air_hold_done")) and int(_p.get("r7_air_phase")) == 1:
			st.dropped = true
			_case.drop_af = snappedf(_fr() * float(_p.get("r7_sun_speed")) * 0.5, 0.1)
			_case.drop_y = snappedf(_p.position.y, 0.001)
			floor_body.position.y -= 4.0
		if st.dropped and int(_p.get("r7_air_phase")) == 3 and not _p.is_on_floor():
			st.wc = true)
	_check(st.dropped and st.wc, "real drop reached WAIT_CONTACT airborne (REF05)")
	if not st.wc:
		return
	_case.wc_y = snappedf(_p.position.y, 0.001)
	_p.call("request_dodge")
	await physics_frame
	_tick()
	var pre := {"phase": int(_p.get("r7_air_phase")), "floor": _p.is_on_floor(), "running": _p.call("r7c_running"),
		"dodge_left": snappedf(float(_p.get("_r7c_dodge_left")), 0.001), "stop_req": _p.get("_r7c_stop_req")}
	_case.pre_hit = pre
	_check(pre.phase == 3 and not pre.floor and pre.running and float(pre.dodge_left) > 0.0 and bool(pre.stop_req), "pre-hit: WAIT_CONTACT, dodge buffered, stop intent set")
	var probe := _receiver("probe_after_hit", _p.global_position + Vector3(0, 0.9, 0), 1.2)
	var sweep0: int = (_p.get("r7_sweep_hits") as Array).size()
	var r: Dictionary = _p.call("take_hit", {"damage": 5.0, "posture_damage": 5.0, "hit_dir": Vector3(0, 0, -1)})
	var post := {"result": r.get("result"), "running": _p.call("r7c_running"), "queue": (_p.get("_form13_queue") as Array).size(),
		"handoff": _p.get("_r7c_handoff"), "dodge_left": float(_p.get("_r7c_dodge_left")), "stop_req": _p.get("_r7c_stop_req"),
		"grp": int(_p.get("r7_hit_group")), "hitbox": bool((_p.get("_hitbox") as Area3D).monitoring), "wins": (_p.get("_r7_wins") as Array).size(),
		"prev_in_win": _p.get("_r7_prev_in_win"), "state": int(_p.get("action_state")), "air_phase": int(_p.get("r7_air_phase")),
		"exit": _exit_reason(), "form_on": _p.get("_r7_form_on")}
	_case.post_hit = post
	_check(post.result == "hit" and not post.running and post.queue == 0 and not post.handoff, "hit clears _r7c_running / parent _form13_queue / pending handoff")
	_check(post.dodge_left == 0.0 and not post.stop_req, "hit clears dodge buffer and stop flag")
	_check(post.grp == 0 and not post.hitbox and post.wins == 0 and not post.prev_in_win and post.air_phase == 0 and not post.form_on, "hit clears damage window / hit group / sweep history")
	_check(post.exit == "hit", "exit reason hit")
	var bad := {"rolls": 0, "grp": 0}
	await _until(300, func(): return _p.is_on_floor() and int(_p.get("action_state")) == 0 and float(_p.get("_hitstun_left")) <= 0.0, func():
		if int(_p.get("action_state")) == 2:
			bad.rolls += 1
		if int(_p.get("r7_hit_group")) > 0:
			bad.grp += 1)
	_case.land_y = snappedf(_p.position.y, 0.001)
	_case.sweep_growth = (_p.get("r7_sweep_hits") as Array).size() - sweep0
	_case.probe_hits = probe.log.size()
	_check(_p.is_on_floor() and _p.position.y < -3.9, "falls the real 4 m to ground")
	_check(bad.rolls == 0 and bad.grp == 0 and probe.log.is_empty() and _case.sweep_growth == 0, "after hit: no roll, no hit group, no damage")
	_check(_starts().back() == "REF05" and not _starts().has("REF06"), "no further form after hit (form13 still held)")
	Input.action_release("form13")
	var p0 := _p.position
	Input.action_press("move_forward")
	for i in 25:
		await physics_frame
	Input.action_release("move_forward")
	_case.move_m = snappedf((_p.position - p0).length(), 0.01)
	_check(_case.move_m > 0.5, "movement works after landing")
	await _until(30, func(): return int(_p.get("action_state")) == 0)
	_p.call("request_primary_attack")
	await physics_frame
	_check(int(_p.get("action_state")) == 1 and int(_p.get("combo_stage")) >= 1, "light attack works after landing")
