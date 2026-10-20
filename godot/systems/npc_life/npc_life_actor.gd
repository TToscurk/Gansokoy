extends "res://scripts/npc_population_actor.gd"
## NPC Living World 的 HERO 本體（docs/NPC自主生活系統.md）。
## 沿用 npc_population_actor.gd 的 SpringArm 排除、_turn、_anim；行為全部改由 NpcLifeDirector 排程：
##   plan（事件）＝ steps：say／goto／step_to／face／act／outcome／seek／converse／vanish
##   事件狀態回報 director：Reserved → Traveling → Interacting → Completed／Interrupted／Failed（→ Cooldown）
## 打斷優先序：劇情對話（附近凍結）＞ 戰鬥（敵人靠近：中止事件、面向威脅）＞ 玩家搭話（暫停事件、聊完續做）＞ 生活事件
## 遠距降頻：距玩家 > lod_near 每 3 幀、> lod_far 每 8 幀才更新一次（累積 dt，移動距離不變）。
## 走路高度用烘焙可走格的地面高（不做每幀射線）；緣側等落差用 step_to 直線＋晚段抬升。

@export var hero_id := ""
@export var react_radius := 3.2
@export var leave_radius := 5.5
@export var chat_max := 22.0
@export var chat_cooldown := 30.0
@export var lod_near := 45.0
@export var lod_far := 90.0

var _life: Node
var _def := {}
var _shared := {}
var _actions := {}
var _speed := 1.3
var _plan := {}
var _si := -1
var _step := {}
var _step_t := 0.0
var _step_rt := 0.0             # 本步驟實際經過秒數（不受生活時鐘倍率影響；逾時判定用）
var _step_started := false
var _decide_in := 2.0
var _path := PackedVector3Array()
var _pi := 0
var _goal := Vector3.INF
var _stuck_t := 0.0
var _stuck_ref := Vector3.INF
var _best_d := INF
var _repaths := 0
var _act := {}
var _pose := ""                 # "seiza"：正座中（離開前要先起身）
var _standing_up := 0.0
var _session := {}
var _hidden := false
var _vanish_left := 0.0
var _chat := {}
var _chat_cool := 0.0
var _alarm_clear := 0.0
var _frozen := false
var _bubble: Label3D
var _bubble_left := 0.0
var _look: LookAtModifier3D
var _look_target: Node3D
var _look_at: Node3D
var _lod_n := 0
var _lod_acc := 0.0
var _perceive_t := 0.0
var _player: Node3D
var _pd := INF
var _block_t := 0.0


func _ready() -> void:
	super._ready()
	add_to_group("npc_life_hero")
	set_physics_process(false)   # 等 director 的 life_setup


## director 註冊後呼叫
func life_setup(dir: Node, def: Dictionary, shared: Dictionary, first_delay: float) -> void:
	_life = dir
	_def = def
	_shared = shared
	_speed = float(def.get("walk_speed", walk_speed))
	_actions = (shared.get("actions", {}) as Dictionary).duplicate(true)
	for k in def.get("actions", {}):
		_actions[k] = def.actions[k]
	if String(def.get("skeleton", "")) == "general":
		_add_clips(shared.get("general_clips", {}))
	_add_clips(def.get("extra_clips", {}))
	_make_bubble()
	_make_voice()
	if bool(def.get("head_look", true)):
		_make_look()
	if String(def.get("start_pose", "")) == "seiza":
		_pose = "seiza"
	_decide_in = first_delay
	set_physics_process(true)


func _add_clips(m: Dictionary) -> void:
	if _npc == null:
		return
	var ap := _npc.get("player") as AnimationPlayer
	if ap == null:
		return
	var lib := ap.get_animation_library(&"")
	for k in m:
		if lib.has_animation(k):
			continue
		var spec: Variant = m[k]
		var path := String(spec[0]) if spec is Array else String(spec)
		var loop := bool(spec[1]) if spec is Array and spec.size() > 1 else false
		var a := load(path) as Animation
		if a == null:
			_life.call("_log", hero_id, "", "ANIM_MISSING", {"clip": k, "path": path})
			continue
		a = a.duplicate() as Animation
		a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		lib.add_animation(k, a)


# ─────────────────────────────── 對外介面（director 用） ───────────────────────────────

func life_state() -> String:
	if _hidden: return "hidden"
	if not _chat.is_empty(): return "player_chat"
	if not _session.is_empty(): return "session"
	if not _plan.is_empty(): return "plan:" + String(_plan.event.id)
	return "idle"


func current_event() -> String:
	return String(_plan.event.id) if not _plan.is_empty() else ""


func can_accept_social(_from: String) -> bool:
	if _hidden or not _chat.is_empty() or not _session.is_empty() or _alarm_clear > 0.0 or _frozen or _paused_for != "":
		return false
	if not _plan.is_empty():
		# 不可打斷：正在跪地／專心事件中途、或事件本身標記 focus
		if bool(_plan.event.get("focus", false)):
			return false
		if not _act.is_empty() and String(_act.get("phase", "")) in ["intro", "outro"]:
			return false
		if String(_plan.event.get("kind", "")) == "social":
			return false
	return true


## 被找：中止目前事件（可打斷者），原地等候
func hold_for_session(s: Dictionary) -> void:
	# 只預約：手上的事照做，等發起者走近（≤ hold_radius）或自己閒下來才停步等候
	_session = s
	_look_at = null


const HOLD_RADIUS := 12.0
const HELD_LOCAL_R := 30.0        # 被約、對方還遠時，可做的附近事件範圍
var _paused_for := ""            # "social"：手上事件因交談暫停（交談後續做）


func _pause_plan(why: String) -> void:
	if _plan.is_empty() or _paused_for != "":
		return
	_paused_for = why
	_stop_move()
	_act_outro_immediate()
	_life.call("_log", hero_id, current_event(), "PAUSED", {"why": why})


func _resume_plan() -> void:
	if _paused_for == "":
		return
	_paused_for = ""
	if not bool(_life.call("event_still_valid", hero_id, _plan.event)):
		_end_plan("Interrupted", {"why": "condition_lost"})
		return
	_life.call("_log", hero_id, current_event(), "RESUMED", {})
	_step_started = false
	_goal = Vector3.INF
	_best_d = INF
	_stuck_t = 0.0
	if String(_step.get("op", "")) == "act":
		_step_t = 0.0
		_step_rt = 0.0


## 測試／除錯：立刻改做指定事件（director.force_event 呼叫）
func force_plan(p: Dictionary) -> void:
	if not _chat.is_empty():
		_end_chat()
	if not _session.is_empty():
		_life.call("end_session", _session, "Interrupted", "forced")
	if not _plan.is_empty():
		_end_plan("Interrupted", {"why": "forced"})
	_start_plan(p)


## director 通知：學到新傳聞。依性格（plan_change）決定是否放下手上的事
## 交談中學到的（最常見：別人告訴我的）先記著，交談結束時再決定要不要改計畫
var _pending_learn: Array = []


func on_learn(f: String) -> void:
	var pc: Dictionary = _def.get("plan_change", {})
	if not pc.has(f):
		return
	if not _session.is_empty():
		_pending_learn.append(f)
		return
	_maybe_change_plan(f)


func _maybe_change_plan(f: String) -> bool:
	var pc: Dictionary = _def.get("plan_change", {})
	if _plan.is_empty():
		_decide_in = minf(_decide_in, 0.5)
		return false
	if bool(_plan.event.get("focus", false)) or int(_plan.event.get("priority", 0)) >= 5:
		return false
	if randf() < float(pc.get(f, 0.0)):
		_paused_for = ""
		_end_plan("Interrupted", {"why": "plan_change", "fact": f})
		_decide_in = 0.3
		return true
	return false


func session_speak(text: String, dur: float, listener: Node3D, clip: String, vclip := {}) -> void:
	_look_at = listener
	say(text, dur)
	if not vclip.is_empty():
		_speak_voice(vclip)
	if _pose == "":
		var c := clip if clip != "" else _pick_clip(_action("talk").get("loop", ["idle"]))
		_play(c, 0.0)


func session_listen(speaker: Node3D) -> void:
	_look_at = speaker
	if _pose == "" and _act.is_empty():
		_anim(&"idle")


func session_ended(s: Dictionary, state: String) -> void:
	if _session != s:
		return
	_stop_voice()
	_session = {}
	_look_at = null
	if _pose == "":
		_anim(&"idle")
	var quick := not _pending_learn.is_empty()   # 聊天裡學到會改變計畫的事 → 立刻重新挑事件
	# 發起者：converse 步驟依結果前進或失敗
	if not _plan.is_empty() and String(_step.get("op", "")) in ["seek", "converse"] and _paused_for == "":
		_pending_learn.clear()
		if state == "Completed":
			_next_step()
		else:
			_end_plan(state if state != "Completed" else "Interrupted", {"why": "session_" + state.to_lower()})
	elif _paused_for == "social":
		# 被找的一方：聊完繼續原本的事——除非聊天內容讓自己改變計畫（性格 plan_change）
		var changed := false
		for f in _pending_learn:
			if _maybe_change_plan(f):
				changed = true
				break
		_pending_learn.clear()
		if not changed:
			_resume_plan()
	else:
		_pending_learn.clear()
		_decide_in = 0.3 if quick else randf_range(2.0, 5.0)


func say(text: String, dur := -1.0) -> void:
	if text == "" or _bubble == null:
		return
	var nm := String(_def.get("name", hero_id))
	_bubble.text = "%s「%s」" % [nm, text]
	_bubble.visible = true
	_bubble_left = dur if dur > 0.0 else clampf(0.13 * text.length() + 1.4, 2.4, 6.5)
	if _life != null and _life.has_signal("hero_said"):
		_life.emit_signal("hero_said", hero_id, text, "")


# ─────────────────────────────── 主迴圈 ───────────────────────────────

func _physics_process(dt: float) -> void:
	if _life == null:
		return
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_pd = INF
	if _player != null:
		var d := _player.global_position - global_position
		d.y = 0.0
		_pd = d.length()
	# 遠距降頻
	var skip := 1 if _pd < lod_near else (3 if _pd < lod_far else 8)
	_lod_acc += dt
	_lod_n += 1
	if _lod_n < skip and _chat.is_empty() and _session.is_empty():
		return
	dt = _lod_acc
	_lod_acc = 0.0
	_lod_n = 0
	var ld := dt * float(_life.time_scale)
	_update_bubble(dt)
	_update_look(dt)
	_chat_cool = maxf(_chat_cool - ld, 0.0)
	if _hidden:
		_tick_hidden(ld)
		return
	_perceive_t -= dt
	if _perceive_t <= 0.0:
		_perceive_t = 1.0
		_life.call("perceive", hero_id, global_position)
	if _standing_up > 0.0:
		_standing_up -= dt
		return
	# 1) 劇情對話中：附近凍結
	var dm := get_node_or_null("/root/DialogueManager")
	_frozen = dm != null and bool(dm.call("is_active")) and _pd < 25.0
	if _frozen:
		if _act.is_empty() and _pose == "":
			_anim(&"idle")
		return
	# 2) 戰鬥：敵人靠近
	var threat := _threat()
	if threat != null:
		if _alarm_clear <= 0.0:
			_alarm(threat)
		_alarm_clear = 4.0
		_face_toward(threat.global_position, dt)
		return
	if _alarm_clear > 0.0:
		_alarm_clear -= dt
		if _alarm_clear <= 0.0:
			_life.call("_log", hero_id, "", "ALARM_CLEAR", {})
			_decide_in = 1.5
		return
	# 3) 玩家搭話
	if _tick_player_chat(dt, ld):
		return
	# 手上事件的目標物件失效（就算暫停中也要放掉預約）
	if not _plan.is_empty() and String(_plan.get("object", "")) != "" and not bool(_life.call("object_valid", String(_plan.object))):
		_fail("object_invalid")
		return
	# 4) 被找去聊天（session 的 b 方）：發起者走近或自己沒事做 → 暫停手上事件、原地等候
	if not _session.is_empty() and String(_session.b) == hero_id:
		var ini: Node3D = _life.heroes.get(_session.a)
		var near := ini != null and _xz(ini.global_position).distance_to(_xz(global_position)) < HOLD_RADIUS
		if _plan.is_empty() and not near and _session.state == "approach" and _paused_for == "":
			# 對方還遠：在附近找點事做（不離開 HELD_LOCAL_R），不要原地罰站
			_idle_pose()
			_decide_in -= ld
			if _decide_in <= 0.0:
				var lp: Dictionary = _life.call("request_plan", hero_id, HELD_LOCAL_R)
				if lp.is_empty():
					_decide_in = randf_range(4.0, 8.0)
				else:
					_start_plan(lp)
			return
		if _plan.is_empty() or near or _session.state != "approach" or _paused_for == "social":
			if not _plan.is_empty():
				_pause_plan("social")
			_tick_held(dt)
			return
	# 5) 生活事件
	if _plan.is_empty():
		_idle_pose()
		_decide_in -= ld
		if _decide_in <= 0.0:
			var p: Dictionary = _life.call("request_plan", hero_id)
			if p.is_empty():
				_decide_in = randf_range(3.0, 6.0)
			elif p.has("pending"):
				_decide_in = 0.15          # JEV 決策等待中（原地照常 idle）；逾時由 director 退回原本決策
			else:
				_start_plan(p)
		return
	_tick_step(dt, ld)


func _idle_pose() -> void:
	if _pose == "" and _act.is_empty():
		_anim(&"idle")


# ─────────────────────────────── plan／step ───────────────────────────────

func _start_plan(p: Dictionary) -> void:
	_plan = p
	_si = -1
	# 人在據點（緣側等可走格外的位置）：先直線走到銜接點
	var hd: Dictionary = _life.mapd.get("homes", {}).get(hero_id, {})
	if hd.has("link") and _xz(global_position).distance_to(Vector2(hd.at[0], hd.at[1])) < 0.6:
		var steps: Array = p.steps
		for k in steps.size():
			if String(steps[k].op) in ["goto", "seek"]:
				var lk := Vector2(hd.link[0], hd.link[1])
				steps.insert(k, {"op": "step_to", "to": Vector3(lk.x, _life.call("ground_y", lk, global_position.y), lk.y)})
				break
			if String(steps[k].op) == "step_to":
				break
	_life.call("report", hero_id, _plan, "Reserved", {"object": p.get("object", ""), "partner": p.get("partner", ""), "topic": String(p.get("topic", {}).get("id", ""))})
	_next_step()


func _next_step() -> void:
	_finish_act_now()
	_si += 1
	_step_t = 0.0
	_step_rt = 0.0
	_step_started = false
	_stop_move()
	_repaths = 0
	_stuck_t = 0.0
	_stuck_ref = Vector3.INF
	_best_d = INF
	var steps: Array = _plan.get("steps", [])
	if _si >= steps.size():
		_end_plan("Completed", {})
		return
	_step = steps[_si]
	# 事件前提已不成立（例：異狀已被別人解決）→ 中止，不做白工
	if String(_step.get("op", "")) in ["goto", "act", "seek"] and not bool(_life.call("event_still_valid", hero_id, _plan.event)):
		_end_plan("Interrupted", {"why": "condition_lost"})


func _end_plan(state: String, info: Dictionary) -> void:
	if _plan.is_empty():
		return
	var p := _plan
	_plan = {}
	_step = {}
	_si = -1
	_paused_for = ""
	_stop_move()
	if not _act.is_empty() and state != "Completed":
		_act_outro_immediate()
	_life.call("report", hero_id, p, state, info)
	var cool := randf_range(2.5, 6.0) if state == "Completed" else randf_range(3.0, 6.0)
	_life.call("_log", hero_id, String(p.event.id), "Cooldown", {"secs": snappedf(cool, 0.1)})
	_decide_in = cool


func _fail(reason: String) -> void:
	_end_plan("Failed", {"why": reason, "step": String(_step.get("op", ""))})


func _tick_step(dt: float, ld: float) -> void:
	_step_t += ld
	_step_rt += dt
	var op := String(_step.get("op", ""))
	# 正座中要移動：先起身
	if _pose == "seiza" and op in ["goto", "step_to", "seek", "face"]:
		_stand_from_seiza()
		return
	# 目標物件失效（被移除／停用）→ 失敗並釋放
	var oid := String(_plan.get("object", ""))
	if oid != "" and op in ["goto", "face", "act"] and not bool(_life.call("object_valid", oid)):
		_fail("object_invalid")
		return
	match op:
		"say":
			say(String(_step.get("text", "")))
			_next_step()
		"goto":
			if not _step_started:
				_step_started = true
				if _si <= 1 or _plan.get("_traveling_reported", false) == false:
					_plan["_traveling_reported"] = true
					_life.call("report", hero_id, _plan, "Traveling", {"to": String(_step.get("label", "")), "from": _xz(global_position), "goal": _xz(_step.to)})
			if _travel(_step.to, dt):
				_next_step()
		"step_to":
			if _step_straight(_step.to, dt):
				_next_step()
		"face":
			if _face_toward(_step.to, dt) or _step_rt > 6.0:
				_next_step()
		"act":
			if not _step_started:
				_step_started = true
				_life.call("report", hero_id, _plan, "Interacting", {"action": _step.action, "pos": _xz(global_position), "object": _plan.get("object", "")})
				say(String(_step.get("say", "")))
				_begin_act(String(_step.action), float(_step.dur))
			if _tick_act(dt, ld):
				_next_step()
			elif _step_rt > float(_step.dur) / maxf(float(_life.time_scale), 0.01) + 45.0:
				_fail("act_timeout")
		"outcome":
			_life.call("apply_outcome", hero_id, _plan)
			_next_step()
		"seek":
			_tick_seek(dt)
		"converse":
			# session 由 director 推進；這裡只顧轉向與逾時
			if _session.is_empty():
				_next_step()
			elif _step_rt > 150.0:
				_life.call("end_session", _session, "Failed", "converse_timeout")
			else:
				var other: Node3D = _life.heroes.get(_session.b)
				if other != null:
					_face_toward(other.global_position, dt, true)
		"vanish":
			if not _step_started:
				_step_started = true
				_vanish_left = float(_step.get("dur", 300))
				_set_hidden(true)
		_:
			_fail("bad_step:" + op)


# ─── 移動 ───

func _travel(to: Vector3, dt: float) -> bool:
	if _goal == Vector3.INF or _goal.distance_to(to) > 0.3:
		_goal = to
		_request_path(to)
	if _path_wait:
		if _anim_name() == "walk" and _pi >= _path.size():
			_anim(&"idle")
		return false
	if _path_failed:
		_path_failed = false
		if _xz(global_position).distance_to(_xz(to)) < 0.4:
			return true
		_fail("no_path")
		return false
	return _follow(dt)


## 背景尋路：送出請求；結果回來前原地等（通常 1–2 幀；長路線數十 ms，不卡主執行緒）
var _path_req := 0
var _path_wait := false
var _path_failed := false


func _request_path(to: Vector3) -> void:
	_path_req += 1
	var id := _path_req
	_path_wait = true
	_path_failed = false
	_life.call("request_path", global_position, to, func(p: PackedVector3Array) -> void:
		if id != _path_req:
			return
		_path_wait = false
		_path = p
		_pi = 0
		_path_failed = p.is_empty())


func _follow(dt: float) -> bool:
	if _pi >= _path.size():
		return true
	var tgt := _path[_pi]
	var d := tgt - global_position
	d.y = 0.0
	var L := d.length()
	if L < 0.12:
		_pi += 1
		return _pi >= _path.size()
	# 卡住監看：以「實際位移」判定（目標會動、會重算路徑，用剩餘距離會誤判）
	if _stuck_ref == Vector3.INF or _xz(global_position).distance_to(_xz(_stuck_ref)) > 0.5:
		_stuck_ref = global_position
		_stuck_t = 0.0
	elif _block_t <= 0.0:
		_stuck_t += dt
	if _stuck_t > 8.0:
		_stuck_t = 0.0
		_stuck_ref = Vector3.INF
		_repaths += 1
		if _repaths > 2:
			_fail("stuck")
			return false
		_goal = Vector3.INF
		return false
	if _blocked_ahead():
		_block_t += dt
		if _block_t < 3.0:
			_anim(&"idle")
			return false
	else:
		_block_t = 0.0
	var goal_yaw := atan2(d.x, d.z)
	var diff := absf(angle_difference(rotation.y, goal_yaw))
	_anim(&"walk")
	rotation.y = _turn(rotation.y, goal_yaw, (TURN_RATE if diff > 1.2 else 4.0) * dt)
	var adv := 0.0 if diff > 1.2 else minf(_speed * dt, L)
	var np := global_position + d / L * adv
	np.y = _life.call("ground_y", Vector2(np.x, np.z), global_position.y)
	global_position = np
	return false


## 直線走（緣側等可走格外的銜接段）：高度在離終點 0.9→0.35 m 之間抬升
func _step_straight(to: Vector3, dt: float) -> bool:
	if not _step_started:
		_step_started = true
		_step["from"] = global_position
	var from: Vector3 = _step.from
	var d := to - global_position
	d.y = 0.0
	var L := d.length()
	if L < 0.06:
		var at_home := false
		var hd0: Dictionary = _life.mapd.get("homes", {}).get(hero_id, {})
		if hd0.has("y") and Vector2(to.x, to.z).distance_to(Vector2(hd0.at[0], hd0.at[1])) < 0.1:
			at_home = true
		global_position = Vector3(to.x, float(hd0.y) if at_home else to.y, to.z)
		return true
	var goal_yaw := atan2(d.x, d.z)
	var diff := absf(angle_difference(rotation.y, goal_yaw))
	_anim(&"walk")
	rotation.y = _turn(rotation.y, goal_yaw, (TURN_RATE if diff > 1.2 else 4.0) * dt)
	var adv := 0.0 if diff > 1.2 else minf(_speed * 0.8 * dt, L)
	var np := global_position + d / L * adv
	var hd: Dictionary = _life.mapd.get("homes", {}).get(hero_id, {})
	if hd.has("edge"):
		# 緣側：以邊緣為界，界內＝緣側高、界外＝庭院地面；邊緣前後 0.2 m 平滑（上下都適用）
		var at := Vector2(hd.at[0], hd.at[1])
		var ed := at.distance_to(Vector2(hd.edge[0], hd.edge[1]))
		var sd := Vector2(np.x, np.z).distance_to(at)
		var w := 1.0 - smoothstep(ed - 0.2, ed + 0.2, sd)
		var lk := Vector2(hd.link[0], hd.link[1])
		np.y = lerpf(_life.call("ground_y", lk, from.y), float(hd.y), w)
	else:
		var tot := maxf(_xz(from).distance_to(_xz(to)), 0.01)
		np.y = lerpf(from.y, to.y, clampf(1.0 - _xz(np).distance_to(_xz(to)) / tot, 0.0, 1.0))
	global_position = np
	return false




func _blocked_ahead() -> bool:
	var fwd := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	if _player != null and _pd < 0.9:
		var d := (_player.global_position - global_position)
		d.y = 0.0
		if d.normalized().dot(fwd) > 0.3:
			return true
	for id in _life.heroes:
		if id == hero_id:
			continue
		var o: Node3D = _life.heroes[id]
		if not o.visible:
			continue
		var d2 := o.global_position - global_position
		d2.y = 0.0
		if d2.length() < 0.75 and d2.normalized().dot(fwd) > 0.5:
			return true
	return false


func _stop_move() -> void:
	_path = PackedVector3Array()
	_goal = Vector3.INF
	_path_req += 1          # 作廢還在背景算的路徑
	_path_wait = false
	_path_failed = false


func _face_toward(p: Vector3, dt: float, slow := false) -> bool:
	var d := p - global_position
	d.y = 0.0
	if d.length() < 0.05:
		return true
	var goal := atan2(d.x, d.z)
	var diff := absf(angle_difference(rotation.y, goal))
	if diff < 0.1:
		return true
	if _pose == "seiza" or (not _act.is_empty() and String(_act.get("phase", "")) != ""):
		return true   # 坐著／跪著不轉身體（頭部 look-at 補）
	if not slow and diff > 0.25:
		_anim(&"walk")
	rotation.y = _turn(rotation.y, goal, (1.6 if slow else TURN_RATE) * dt)
	if diff < 0.25 and not slow:
		_anim(&"idle")
	return false


# ─── 動作（intro／loop／outro） ───

func _action(name: String) -> Dictionary:
	var a: Variant = _actions.get(name)
	if a is Dictionary:
		return a
	return {"loop": [name]}


func _pick_clip(pool: Variant) -> String:
	var arr: Array = pool if pool is Array else [pool]
	var ok: Array = []
	for c in arr:
		if _has_clip(String(c)):
			ok.append(String(c))
	if ok.is_empty():
		return "idle"
	return ok[randi() % ok.size()]


func _has_clip(c: String) -> bool:
	if c == "" or _npc == null:
		return false
	var ap := _npc.get("player") as AnimationPlayer
	return ap != null and ap.has_animation(c)


func _clip_len(c: String) -> float:
	var ap := _npc.get("player") as AnimationPlayer
	return ap.get_animation(c).length if ap != null and ap.has_animation(c) else 1.0


func _play(c: String, at := -1.0) -> void:
	if _npc != null and _has_clip(c):
		_npc.call("play_clip", StringName(c), at)


func _begin_act(name: String, dur: float) -> void:
	if name == "seiza":
		_act = {"name": name, "phase": "", "left": dur, "special": "seiza"}
		var sz := _npc.get_node_or_null("Seiza") if _npc != null else null
		if sz != null and _pose != "seiza":
			sz.call("sit_down")
			_pose = "seiza"
		return
	var a := _action(name)
	var loop := _pick_clip(a.get("loop", ["idle"]))
	if loop == "idle" and not (a.get("loop", ["idle"]) as Array).has("idle"):
		_life.call("_log", hero_id, current_event(), "ANIM_FALLBACK", {"action": name, "wanted": a.get("loop", [])})
	_act = {"name": name, "intro": String(a.get("intro", "")), "loop": loop, "outro": String(a.get("outro", "")), "left": dur, "phase": "", "t": 0.0, "pool": a.get("loop", ["idle"]), "switch": float(a.get("switch", 0.0))}
	if _has_clip(_act.intro):
		_act.phase = "intro"
		_act.t = _clip_len(_act.intro) - 0.25
		_play(_act.intro, 0.0)
	else:
		_act.phase = "loop"
		_play(loop, -1.0 if loop == "idle" else 0.0)


## true ＝動作做完
func _tick_act(dt: float, ld: float) -> bool:
	if _act.is_empty():
		return true
	if String(_act.get("special", "")) == "seiza":
		_act.left -= ld
		if _act.left <= 0.0:
			_act = {}
			return true
		return false
	match String(_act.phase):
		"intro":
			_act.t -= dt
			if _act.t <= 0.0:
				_act.phase = "loop"
				_play(_act.loop, 0.0)
		"loop":
			_act.left -= ld
			if float(_act.switch) > 0.0:
				_act.t -= dt
				if _act.t <= 0.0:
					_act.t = float(_act.switch)
					_play(_pick_clip(_act.pool), 0.0)
			if _act.left <= 0.0:
				if _has_clip(_act.outro):
					_act.phase = "outro"
					_act.t = _clip_len(_act.outro) - 0.2
					_play(_act.outro, 0.0)
				else:
					_act = {}
					_anim(&"idle")
					return true
		"outro":
			_act.t -= dt
			if _act.t <= 0.0:
				_act = {}
				_anim(&"idle")
				return true
	return false


## 中途被打斷（玩家搭話／戰鬥）：跪地中 → 播起身再說
func _act_outro_immediate() -> void:
	if _act.is_empty():
		return
	if String(_act.get("special", "")) == "seiza":
		_act = {}
		return
	if String(_act.phase) in ["intro", "loop"] and _has_clip(String(_act.get("outro", ""))):
		_play(_act.outro, 0.0)
		_standing_up = _clip_len(_act.outro) - 0.2
	_act = {}


func _finish_act_now() -> void:
	if not _act.is_empty() and String(_act.get("special", "")) != "seiza":
		_act = {}


func _stand_from_seiza() -> void:
	var sz := _npc.get_node_or_null("Seiza") if _npc != null else null
	_pose = ""
	_act = {}
	if sz != null and bool(sz.call("is_seated")):
		sz.call("stand_up")
		_standing_up = 4.4
	_life.call("_log", hero_id, current_event(), "STAND_UP", {})


# ─── 社交 ───

func _tick_seek(dt: float) -> void:
	var partner := String(_plan.get("partner", ""))
	var other: Node3D = _life.heroes.get(partner)
	if other == null or not other.visible:
		_fail("partner_gone")
		return
	if not _step_started:
		_step_started = true
		var s: Dictionary = _life.call("open_session", hero_id, partner, _plan.topic)
		if s.is_empty():
			_fail("partner_busy")
			return
		_session = s
		_look_at = null
		_life.call("report", hero_id, _plan, "Traveling", {"to": partner, "from": _xz(global_position), "goal": _xz(other.global_position)})
	if _session.is_empty():
		_fail("session_lost")
		return
	var dist := _xz(global_position).distance_to(_xz(other.global_position))
	if dist <= 1.7:
		_stop_move()
		_look_at = other
		# 轉身逾時從「到位」起算（_step_rt 從出發就開始累計，遠途走來早就超過，會沒轉身就開講）
		_step["_face_t"] = float(_step.get("_face_t", 0.0)) + dt
		if _face_toward(other.global_position, dt) or float(_step._face_t) > 4.0:
			_life.call("session_arrived", _session)
			_next_step()   # converse
		return
	# 目標點：對方周圍可走、離我最近（對方移動 > 1 m 就重算）
	_step["_rp"] = float(_step.get("_rp", 0.0)) - dt
	var moved: float = _step.get("_tpos", Vector3.INF).distance_to(other.global_position)
	if _goal == Vector3.INF or moved > 2.5 or (moved > 0.6 and float(_step._rp) <= 0.0):
		_step["_rp"] = 3.0
		_step["_tpos"] = other.global_position
		var ap: Vector3 = _life.call("approach_point", other.global_position, global_position, 1.3)
		_goal = ap
		_request_path(ap)
	if _path_wait:
		return
	if _path_failed:
		_path_failed = false
		_life.call("end_session", _session, "Failed", "no_path_to_partner")
		return
	if _follow(dt):
		_goal = Vector3.INF
	if _step_rt > 300.0:
		_life.call("end_session", _session, "Failed", "seek_timeout")


## session 的 b 方：原地等候；對方 6 m 內轉身面向
func _tick_held(dt: float) -> void:
	var other: Node3D = _life.heroes.get(_session.a)
	if other == null:
		return
	if _pose == "" and _act.is_empty():
		if _xz(global_position).distance_to(_xz(other.global_position)) < 6.0:
			_look_at = other
			_face_toward(other.global_position, dt, _session.state == "talk")
		elif _anim_name() == "walk":
			_anim(&"idle")


# ─── 玩家 ───

func _tick_player_chat(dt: float, ld: float) -> bool:
	if _chat.is_empty():
		# 玩家走開了：解除自己對交談的暫停
		if not _session.is_empty() and float(_session.get("paused", 0.0)) > 0.0 and _session.get("_pl_said", false) and _pd > react_radius + 0.5:
			_life.call("session_player_pause", _session, false)
			_session["_pl_t"] = 0.0
			_session["_pl_said"] = false
			_look_at = _life.heroes.get(_session.b if _session.a == hero_id else _session.a)
		if _player == null or _chat_cool > 0.0 or _pd > react_radius or not bool(_def.get("player_chat", {}).size() > 0):
			return false
		# 雙人交談中：先暫停，玩家停留 6 s 才散場
		if not _session.is_empty():
			if _session.state == "talk":
				_life.call("session_player_pause", _session, true)
				_session["_pl_t"] = float(_session.get("_pl_t", 0.0)) + dt
				_look_at = _player
				if not _session.get("_pl_said", false):
					_session["_pl_said"] = true
					say(_line("busy_talk"))
				if float(_session._pl_t) < 6.0:
					return true
				var s := _session
				_life.call("end_session", s, "Interrupted", "player_joined")
			else:
				# 還在走向對方（或被約、對方還遠）：玩家優先，取消這次約談；兩人已在 HOLD_RADIUS 內就讓他們先聊
				var other: Node3D = _life.heroes.get(_session.b if _session.a == hero_id else _session.a)
				if other != null and _xz(other.global_position).distance_to(_xz(global_position)) < HOLD_RADIUS:
					return false
				var s2 := _session
				_life.call("end_session", s2, "Interrupted", "player_chat")
		_chat = {"t": 0.0, "stage": 0, "left": 0.0, "paused_event": current_event()}
		if not _plan.is_empty():
			_stop_move()
			_act_outro_immediate()
			_life.call("_log", hero_id, current_event(), "PAUSED", {"why": "player_chat", "pd": snappedf(_pd, 0.01)})
		else:
			_life.call("_log", hero_id, "", "PLAYER_CHAT", {"pd": snappedf(_pd, 0.01)})
		return true
	# 進行中
	if not _session.is_empty() and float(_session.get("paused", 0.0)) > 0.0 and _pd > leave_radius:
		_life.call("session_player_pause", _session, false)
	if _player == null or _pd > leave_radius or float(_chat.t) > chat_max:
		_end_chat()
		return false
	if _standing_up > 0.0:
		return true
	_chat.t += ld
	_look_at = _player
	if _chat.stage == 0:
		if not _face_toward(_player.global_position, dt):
			return true
		_chat.stage = 1
		var ctx := String(_chat.paused_event)
		say(_line(ctx) if ctx != "" and _def.player_chat.has(ctx) else _line("greet"))
		_play(_pick_clip(_action("greet").get("loop", ["idle"])), 0.0)
		_chat.left = 4.0
		return true
	_face_toward(_player.global_position, dt, true)
	_chat.left -= ld
	if _chat.left <= 0.0:
		_chat.left = randf_range(5.0, 8.0)
		say(_line("default"))
		_play(_pick_clip(_action("talk").get("loop", ["idle"])), 0.0)
	return true


func _end_chat() -> void:
	var ev := String(_chat.get("paused_event", ""))
	_chat = {}
	_chat_cool = chat_cooldown
	_look_at = null
	if not _session.is_empty():
		_life.call("session_player_pause", _session, false)
	if not _plan.is_empty():
		_life.call("_log", hero_id, ev, "RESUMED", {})
		# 重走目前步驟（goto 會重算路徑；act 從頭做）
		_step_started = false
		_goal = Vector3.INF
		if String(_step.get("op", "")) == "act":
			_step_t = 0.0
	else:
		_decide_in = 1.0
	_anim(&"idle")


func _line(key: String) -> String:
	var pc: Dictionary = _def.get("player_chat", {})
	var arr: Array = pc.get(key, pc.get("default", []))
	return String(arr[randi() % arr.size()]) if not arr.is_empty() else ""


# ─── 戰鬥 ───

func _threat() -> Node3D:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or not is_instance_valid(e):
			continue
		var p: Variant = e.get("posture")
		if p != null and p.has_method("is_dead") and p.is_dead():
			continue
		if global_position.distance_to((e as Node3D).global_position) < 20.0:
			return e
	return null


func _alarm(threat: Node3D) -> void:
	if not _session.is_empty():
		_life.call("end_session", _session, "Interrupted", "threat")
	if not _plan.is_empty():
		_end_plan("Interrupted", {"why": "threat"})
	if not _chat.is_empty():
		_chat = {}
	say(_line("alarm"))
	_life.call("_log", hero_id, "", "ALARM", {"threat": String(threat.name)})


# ─── 離開／回來（訪客） ───

func _set_hidden(h: bool) -> void:
	_hidden = h
	visible = not h
	var body := get_node_or_null("Body") as CollisionShape3D
	if body != null:
		body.set_deferred("disabled", h)
	_life.call("_log", hero_id, current_event(), "VANISH" if h else "APPEAR", {"pos": _xz(global_position)})


func _tick_hidden(ld: float) -> void:
	_vanish_left -= ld
	if _vanish_left > 0.0:
		return
	# 玩家看得到出入口就先不現身（避免憑空出現）
	if _pd < 30.0 and _in_view(global_position):
		return
	_set_hidden(false)
	_next_step()


func _in_view(p: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.is_position_in_frustum(p + Vector3(0, 1, 0))


# ─── 語音、嘴型 ───

var _vplayer: AudioStreamPlayer3D
var _mouth: Node
var _venv := PackedFloat32Array()
var _vt := -1.0


func _make_voice() -> void:
	_vplayer = AudioStreamPlayer3D.new()
	_vplayer.name = "LifeVoice"
	_vplayer.position = Vector3(0, float(_def.get("bubble_h", 2.0)) - 0.5, 0)
	_vplayer.unit_size = 4.0
	_vplayer.max_distance = 35.0
	_vplayer.bus = AudioBuses.ensure(&"Voice")
	add_child(_vplayer)
	var vc: Dictionary = {}
	if _life.get("voice") != null:
		vc = _life.voice.cfg.get("heroes", {}).get(hero_id, {})
	if vc.has("mouth_uv") and _npc != null and bool(_life.voice.cfg.get("mouth_enabled", true)):
		_mouth = load("res://systems/npc_life/npc_mouth.gd").attach(_npc, vc)


func _speak_voice(vclip: Dictionary) -> void:
	if _vplayer == null:
		return
	_vplayer.stream = vclip.stream
	_vplayer.play()
	_venv = vclip.get("env", PackedFloat32Array())
	_vt = 0.0


func _stop_voice() -> void:
	if _vplayer != null and _vplayer.playing:
		_vplayer.stop()
	_vt = -1.0
	if _mouth != null:
		_mouth.call("set_open", 0.0)


func is_speaking() -> bool:
	return _vplayer != null and _vplayer.playing


## 嘴型每個畫面都要更新（不受遠距降頻影響）
func _process(dt: float) -> void:
	if _vt < 0.0:
		return
	if _vplayer == null or not _vplayer.playing:
		_vt = -1.0
		if _mouth != null:
			_mouth.call("set_open", 0.0)
		return
	_vt = _vplayer.get_playback_position()
	var k := int(_vt * 30.0)
	var v := _venv[k] if k < _venv.size() else 0.0
	if _mouth != null:
		_mouth.call("set_open", clampf((v - 0.08) * 1.6, 0.0, 1.0))


# ─── 泡泡、看向 ───

func _make_bubble() -> void:
	_bubble = Label3D.new()
	_bubble.name = "LifeBubble"
	_bubble.position = Vector3(0, float(_def.get("bubble_h", 2.0)), 0)
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.font = load("res://assets/fonts/NotoSerifTC-VF.ttf")
	_bubble.font_size = 52
	_bubble.outline_size = 14
	_bubble.pixel_size = 0.0024
	_bubble.modulate = Color(1, 0.98, 0.92)
	_bubble.outline_modulate = Color(0.08, 0.06, 0.05, 0.9)
	_bubble.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_bubble.width = 620.0
	_bubble.visibility_range_end = 28.0
	_bubble.visible = false
	add_child(_bubble)


func _update_bubble(dt: float) -> void:
	if _bubble == null or not _bubble.visible:
		return
	_bubble_left -= dt
	if _bubble_left <= 0.0:
		_bubble.visible = false


func _make_look() -> void:
	if _npc == null:
		return
	var sk := _npc.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if sk == null or sk.find_bone("Head") < 0:
		return
	_look_target = Node3D.new()
	_look_target.name = "LifeLookTarget"
	add_child(_look_target)
	_look = LookAtModifier3D.new()
	_look.name = "LifeHeadLook"
	sk.add_child(_look)
	_look.bone_name = "Head"
	_look.forward_axis = 4
	_look.primary_rotation_axis = 1
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = deg_to_rad(120.0)
	_look.secondary_limit_angle = deg_to_rad(60.0)
	_look.use_secondary_rotation = true
	_look.duration = 0.25
	_look.influence = 0.0
	_look.target_node = _look.get_path_to(_look_target)


func _update_look(dt: float) -> void:
	if _look == null:
		return
	var want := 0.0
	if _look_at != null and is_instance_valid(_look_at):
		want = 0.7
		var h := 1.45 if _look_at != _player else 1.5
		_look_target.global_position = _look_at.global_position + Vector3(0.0, h, 0.0)
	_look.influence = move_toward(_look.influence, want, 3.0 * dt)


func _anim_name() -> String:
	return String(_npc.get("animation")) if _npc != null else ""


static func _xz(p: Vector3) -> Vector2:
	return Vector2(snappedf(p.x, 0.01), snappedf(p.z, 0.01))
