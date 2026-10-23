extends "res://scripts/npc_population_actor.gd"
## 隨性散步的 NPC（魔理莎用）。沿用 npc_population_actor 的路線資料（path_xz／path_y，0.25 m 弧長）與
## _place／_sample／_turn／_anim／_blocked，行為改成：
##   WALK  沿整條長路線慢慢走（起點、方向隨機），每隔 stop_gap 公尺隨機停下
##   PAUSE 做一個小動作（發呆／低頭看東西／自言自語比手畫腳），結束後有機會折返
##   TURN  邊踏步邊轉向再繼續（不原地陀螺轉）
##   CHAT  玩家（group "player"）進入 react_radius：停步、轉向玩家、先打招呼（雙手比劃）再閒聊；
##         玩家離開 leave_radius、聊滿 chat_max 秒就結束，之後 chat_cooldown 秒內不再搭話
## 父類 _physics_process 在子類覆寫後不會執行（實測），所以狀態機整個在這裡。_ready 沿用父類。
## 需要 NPC 子節點是 marisa_visual.gd（有 browse／talk_* 動作）；缺動作時略過該動作，不報錯停擺。

@export var stop_gap_min := 8.0
@export var stop_gap_max := 24.0
@export_range(0.0, 1.0) var turn_back_chance := 0.3
@export var react_radius := 4.0
@export var leave_radius := 6.5
@export var chat_max := 30.0
@export var chat_cooldown := 25.0
## 閒聊時頭部看向玩家（LookAtModifier3D 掛在 GeneralSkeleton 的 Head）。influence 上限留一點給動作本身的點頭。
@export var head_look := true
@export_range(0.0, 1.0) var head_look_influence := 0.75
## 左右各 head_limit_deg/2（symmetry_limitation：primary_limit_angle 是整個可動範圍）。
@export_range(20.0, 180.0) var head_limit_deg := 120.0

## 停下時可做的動作：[動作名, 權重, 最短秒, 最長秒]
const ACTIVITIES := [
	[&"idle", 3.0, 4.0, 9.0],            # 站著（保留 keine_visual 的重心移動／思考變奏）
	[&"browse", 3.0, 4.8, 10.0],         # 低頭看東西
	[&"talk_funny", 1.5, 6.0, 12.0],     # 自言自語比手畫腳
]
const CHAT_LOOP := [&"talk_general", &"talk_funny", &"talk_twohands"]

enum { WALK, PAUSE, TURN, CHAT }
var _st := PAUSE
var _after := WALK
var _inited := false
var _stop_u := 0.0
var _pause_left := 0.0
var _cool := 0.0
var _chat_t := 0.0
var _chat_stage := 0      # 0 轉向 1 打招呼 2 閒聊
var _stage_left := 0.0
var _chat_clip: StringName = &""
var _look: LookAtModifier3D
var _look_target: Node3D


func _init_once() -> void:
	_inited = true
	if mode != "patrol" or _len <= 0.0:
		set_physics_process(false)
		return
	_u = _rng.randf() * _len
	_dir = 1 if _rng.randf() < 0.5 else -1
	_walking = false
	_place(true)
	_schedule_stop()
	_st = WALK
	_make_look()


func _physics_process(dt: float) -> void:
	if not _inited:
		_init_once()
		if not is_physics_processing():
			return
	_cool = maxf(_cool - dt, 0.0)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var pd := INF
	if pl != null:
		var d := pl.global_position - global_position
		d.y = 0.0
		pd = d.length()
	if _st != CHAT and _cool <= 0.0 and pd <= react_radius:
		_st = CHAT
		_chat_stage = 0
		_chat_t = 0.0
	match _st:
		WALK: _do_walk(dt)
		PAUSE: _do_pause(dt)
		TURN: _do_turn(dt)
		CHAT: _do_chat(dt, pl, pd)
	_update_look(dt, pl)


# ── 看向玩家 ─────────────────────────────────────────

func _make_look() -> void:
	if not head_look or _npc == null:
		return
	var sk := _npc.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if sk == null or sk.find_bone("Head") < 0:
		return
	_look_target = Node3D.new()
	_look_target.name = "HeadLookTarget"
	add_child(_look_target)
	_look = LookAtModifier3D.new()
	_look.name = "HeadLook"
	sk.add_child(_look)
	_look.bone_name = "Head"
	_look.forward_axis = 4                 # +Z（GeneralSkeleton 的 Head rest 與模型同向，實測 local Z＝正面）
	_look.primary_rotation_axis = 1        # 以 Y 軸轉（水平轉頭）
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = deg_to_rad(head_limit_deg)
	_look.secondary_limit_angle = deg_to_rad(70.0)
	_look.use_secondary_rotation = true
	_look.duration = 0.25
	_look.influence = 0.0
	_look.target_node = _look.get_path_to(_look_target)


func _update_look(dt: float, pl: Node3D) -> void:
	if _look == null:
		return
	var want := 0.0
	if _st == CHAT and _chat_stage >= 1 and pl != null:
		want = head_look_influence
		_look_target.global_position = pl.global_position + Vector3(0.0, 1.45, 0.0)
	_look.influence = move_toward(_look.influence, want, 3.0 * dt)


# ── 動作 ─────────────────────────────────────────────

func _has(c: StringName) -> bool:
	var ap = _npc.get("player") if _npc != null else null
	return ap != null and (ap as AnimationPlayer).has_animation(c)


func _clip_len(c: StringName) -> float:
	var ap = _npc.get("player")
	return (ap as AnimationPlayer).get_animation(c).length


## 從頭播（at＝0）；已經是這個動作就不重播。
func _play(c: StringName, at := -1.0) -> void:
	if _npc != null and _npc.get("animation") != c and _has(c):
		_npc.call("play_clip", c, at)


# ── 狀態 ─────────────────────────────────────────────

func _schedule_stop() -> void:
	_stop_u = clampf(_u + _dir * _rng.randf_range(stop_gap_min, stop_gap_max), 0.0, _len)


func _do_walk(dt: float) -> void:
	if _blocked():
		_anim(&"idle")
		return
	_anim(&"walk")
	var sp := walk_speed * float(_npc.get("speed_scale") if _npc != null else 1.0)
	var dy := absf(angle_difference(rotation.y, _yaw_goal))
	_u = clampf(_u + sp * dt * _dir * (0.0 if dy > 1.2 else 1.0), 0.0, _len)
	_place(false)
	rotation.y = _turn(rotation.y, _yaw_goal, 4.0 * dt)
	if (_dir > 0 and _u >= _len) or (_dir < 0 and _u <= 0.0):
		_dir = -_dir                      # 路線盡頭：短停後折返
		_begin_pause(&"idle", _rng.randf_range(2.0, 5.0))
		_schedule_stop()
	elif (_dir > 0 and _u >= _stop_u) or (_dir < 0 and _u <= _stop_u):
		_begin_activity()


func _begin_pause(clip: StringName, secs: float) -> void:
	_st = PAUSE
	_pause_left = secs
	_play(clip, -1.0 if clip == &"idle" else 0.0)


func _begin_activity() -> void:
	var total := 0.0
	for a in ACTIVITIES:
		if _has(a[0]):
			total += float(a[1])
	var r := _rng.randf() * total
	for a in ACTIVITIES:
		if not _has(a[0]):
			continue
		r -= float(a[1])
		if r <= 0.0:
			_begin_pause(a[0], _rng.randf_range(float(a[2]), float(a[3])))
			return
	_begin_pause(&"idle", 4.0)


func _do_pause(dt: float) -> void:
	_pause_left -= dt
	if _pause_left > 0.0:
		return
	if _rng.randf() < turn_back_chance:
		_dir = -_dir
	_place(false)                         # 依新的 _dir 重算朝向目標
	_schedule_stop()
	_st = TURN
	_after = WALK


func _do_turn(dt: float) -> void:
	if absf(angle_difference(rotation.y, _yaw_goal)) > 0.12:
		_anim(&"walk")
		rotation.y = _turn(rotation.y, _yaw_goal, TURN_RATE * dt)
	else:
		_st = _after


func _do_chat(dt: float, pl: Node3D, pd: float) -> void:
	if pl == null or pd > leave_radius or _chat_t > chat_max:
		_end_chat()
		return
	_chat_t += dt
	var to := pl.global_position - global_position
	var goal := atan2(to.x, to.z)
	if _chat_stage == 0:
		if absf(angle_difference(rotation.y, goal)) > 0.25:
			_anim(&"walk")                # 邊踏步邊轉向玩家
			rotation.y = _turn(rotation.y, goal, TURN_RATE * dt)
			return
		_chat_stage = 1
		var greet: StringName = &"talk_twohands" if _has(&"talk_twohands") else &"idle"
		_play(greet, 0.0)
		_stage_left = _clip_len(greet) if greet != &"idle" else 2.0
	rotation.y = _turn(rotation.y, goal, 1.5 * dt)    # 聊天時慢慢跟著玩家的方位
	_stage_left -= dt
	if _stage_left > 0.0:
		return
	_chat_stage = 2
	var pool: Array = []
	for c in CHAT_LOOP:
		if _has(c) and c != _chat_clip:
			pool.append(c)
	if pool.is_empty():
		_stage_left = 6.0
		return
	_chat_clip = pool[_rng.randi() % pool.size()]
	_play(_chat_clip, 0.0)
	_stage_left = _rng.randf_range(6.0, 12.0)


func _end_chat() -> void:
	_cool = chat_cooldown
	_chat_clip = &""
	_place(false)                         # 朝向目標回到路線方向
	_st = TURN
	_after = WALK
