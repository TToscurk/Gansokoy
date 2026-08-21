extends CharacterBody3D
## Yoriichi 高速武士控制器 — AnimationTree 三層架構。
##
##   loco  (AnimationNodeStateMachine)：Idle / Walk / Run / TurnL / TurnR /
##          JumpStart / Fall / Land —— 下半身與一般 locomotion。
##   upper (AnimationNodeOneShot，上半身 bone filter)：Draw / Sheathe(反播) /
##          輕攻擊三段 —— 腿繼續 locomotion，邊跑邊做。
##   full  (AnimationNodeOneShot，無 filter)：Roll / Spin / Judgment /
##          Combo_1 / SpinJump —— 需要全身姿勢的技能暫時接管。
##
## CharacterBody3D 永遠是真實世界位置；所有衍生動畫資源水平 root motion 已清除，
## 位移（roll / lunge / jump）一律程式驅動。動畫時間全部由本腳本的計時器管理
## （AnimationTree 不提供 per-clip position），一個時鐘避免視覺與位移脫鉤。

# ---------------------------------------------------------------------------
# Locomotion
# ---------------------------------------------------------------------------
@export var speed := 4.0
@export var run_speed := 7.0
@export var gravity := 20.0
@export var turn_speed := 12.0        # 視覺模型轉向速度（lerp 權重）
@export var blend_time := 0.2         # locomotion 狀態間預設 xfade

@export var walk_anim := "Armature|Armature|walking_man|baselayer"
@export var idle_anim := "Armature|Armature|Idle_11|baselayer"
@export var run_anim := "Armature|Armature|running|baselayer"
@export var run_fast_anim := "RunFast"
@export var idle_source: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Idle_11_withSkin.fbx")
@export var run_source: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Running_withSkin.fbx")
## 剝離水平 root motion 的 Run_Turn 衍生資源（原始 clip 帶 2.8~3.5 u 水平位移，
## 直接播會把視覺拖離碰撞體 —— Stage 1 inventory 實測發現）。
@export var turn_left_resource: Animation = preload("res://animations/yoriichi_turn_left.res")
@export var turn_right_resource: Animation = preload("res://animations/yoriichi_turn_right.res")
## 左前 / 右前「武士側身追擊」跑姿（原地完美循環，手臂活動量僅 RunFast 1/3 的持刀跑）。
@export var fl_run_source: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_ForwardLeft_Run_Fight_withSkin.fbx")
@export var fr_run_source: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_ForwardRight_Run_Fight_withSkin.fbx")

@export_group("Run Turn / 8-Direction")
## 跑步中輸入方向與面朝方向夾角超過此值才播 Run_Turn 急轉；
## 22.5°~112.5° 的中等偏角由 FL/FR 側身跑姿處理。
@export var turn_angle_deg := 60.0
## Turn clip 播放這麼久之後 blend 回 Run（不強制播完整支）。
@export var turn_time := 0.35
## 8 向 sector 判定以角色 local 速度方向為準；換 sector 後最短持續時間（防抖）。
@export var sector_min_hold := 0.15

@export_group("Jump")
@export var jump_anim := "Jump"
@export var jump_anim_resource: Animation = preload("res://animations/yoriichi_jump.res")
## 起跳段（clip 0~0.62 s）播放倍率——修掉「懸空被拖著走」的飄浮感。
@export var jump_start_speed := 1.9
## 落地段（clip 1.067~1.9 s）播放倍率。
@export var jump_land_speed := 1.5
## 起跳速度（物理）。空中時間 2v/g = 0.533 s，跳高 v²/2g ≈ 0.71 m。
@export var jump_velocity := 5.33
## 落地後無輸入時 Land 動畫佔用 locomotion 的時間；有輸入直接接 Run/Walk。
@export var land_lock_time := 0.35
## FREE 狀態離地超過此秒數視為 Fall（走出平台邊緣）。
@export var coyote_time := 0.12

@export_group("Air Inertia")
## 空中不直接覆寫水平速度：有輸入時以 air_acceleration * air_control (m/s²)
## move_toward 目標速度；無輸入時只以 air_drag (m/s²) 衰減 → 保留起跳慣性。
@export var air_acceleration := 4.0
@export var air_control := 0.35
@export var air_drag := 0.2

@export_group("Roll")
@export var roll_anim := "Roll_Dodge"
@export var roll_anim_resource: Animation = preload("res://animations/yoriichi_roll_dodge.res")
## 3.2 m = 原 6.4 m 縮短 50%。位移仍由 CharacterBody3D ease-out 曲線驅動。
@export var roll_distance := 3.2
@export var roll_animation_speed := 3.0
@export var action_blend_time := 0.12
## Shift 按住 = 疾跑；按下後在此秒數內放開 = 翻滾。
@export var shift_tap_time := 0.25

@export_group("Attack")
@export var attack_combo_anim := "Attack_Combo"
@export var attack_combo_resource: Animation = preload("res://animations/yoriichi_attack_combo.res")
@export var attack_spin_anim := "Attack_Spin"
@export var attack_spin_resource: Animation = preload("res://animations/yoriichi_attack_spin.res")
@export var attack_judgment_anim := "Attack_Judgment"
@export var attack_judgment_resource: Animation = preload("res://animations/yoriichi_attack_judgment.res")
@export var attack_combo_1_anim := "Attack_Combo_1"
@export var attack_combo_1_resource: Animation = preload("res://animations/yoriichi_attack_combo_1.res")
@export var attack_spin_jump_anim := "Attack_Spin_Jump"
@export var attack_spin_jump_resource: Animation = preload("res://animations/yoriichi_attack_spin_jump.res")
@export var attack_speed_scale := 3.0
@export_range(0.0, 1.0) var combo_cancel_start := 0.35
@export_range(0.0, 1.0) var combo_cancel_end := 0.65
@export var combo_input_buffer_time := 0.30
@export var combo_section_blend := 0.035
@export_range(0.0, 1.0) var attack_turn_control := 0.35
## Run 攻擊保留 85% 前進動量、Walk 60%；全身技（heavy）30%。
@export var attack_move_factor_run := 0.85
@export var attack_move_factor_walk := 0.60
@export var attack_move_factor_heavy := 0.30

const SunBreathing = preload("res://sun_breathing.gd")
const COMBO_SECTION_RANGES: Array[Vector2] = [
	Vector2(0.00, 0.34),
	Vector2(0.30, 0.67),
	Vector2(0.63, 1.00),
]
const JUMP_TAKEOFF_CLIP := 0.533      # Jump clip 內離地時間點
const JUMP_START_END := 0.62          # JumpStart 段結尾
const JUMP_AIR_LOOP := Vector2(0.75, 1.05)
const JUMP_LAND_START := 1.067
## OneShot filter：上半身骨骼（Spine02 以上）。下半身（Hips＋腿）留給 loco。
const UPPER_BONES := ["Spine02", "Spine01", "Spine",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"neck", "Head", "head_end", "headfront"]

# ---------------------------------------------------------------------------
# 刀（socket 結構不變）：SheathSocket(Hips)=Sword_Sheathed、HandSocket(RightHand)=Sword_Hand
# ---------------------------------------------------------------------------
enum SwordState { SHEATHED, DRAWING, DRAWN, SHEATHING }
enum ActionState { FREE, ATTACKING, DODGING, JUMPING }

@export_group("Sword Draw")
@export var draw_key := KEY_Q
@export var draw_anim := "Draw_Sword"
@export var draw_anim_resource: Animation = preload("res://yoriichi_draw_sword.res")
## 拔刀斬節奏：Draw/Sheathe 播放倍率（低於攻擊的 3x）。
@export var draw_speed_scale := 2.2
## 拔刀動畫進度（0~1）中「刀離開刀鞘」的時間點。反播跨過同一點刀即回鞘。
@export_range(0.0, 1.0) var t_unsheathe := 0.65

@export_group("Sun Breathing")
## 呼吸量（之後由命中回饋累積；先提供 add_breath() API）。
@export var sun_breath_gauge := 0.0
@export var sun_breath_max := 100.0
## 型的解鎖熟練度（0=初期）。required_mastery 高於此值的型不可用。
@export var sun_mastery := 0
## 拾參ノ型解鎖開關與啟動所需呼吸量（data parameter，先不綁輸入）。
@export var form13_unlocked := false
@export var form13_gauge_cost := 100.0

var sword_state: SwordState = SwordState.SHEATHED
var action_state: ActionState = ActionState.FREE
var combo_stage := 0
var combo_input_buffered := false
var pending_sheathe := false
var active_form := 0                  # 執行中的日之呼吸型 id（0 = 一般攻擊）

var _anim: AnimationPlayer
var _tree: AnimationTree
var _visual: Node3D
var _sword_hand: Node3D
var _sword_sheathed: Node3D
var _turn_l_anim := ""
var _turn_r_anim := ""
var _fl_anim := ""
var _fr_anim := ""
var _sector_state := "Run"
var _sector_hold := 0.0
var _attack_after_roll := false

var _attack_layer := "upper"          # "upper" | "full"
var _action_elapsed := 0.0
var _action_real := 0.0               # 目前段/技的真實時長（已除以播放倍率）
var _roll_duration := 0.0
var _dodge_dir := Vector3.ZERO
var _combo_queued_inputs := 0
var _combo_buffer_remaining := 0.0
var _jump_launched := false
var _in_fall := false
var _air_t := 0.0
var _land_lock := 0.0
var _turn_lock := 0.0
var _draw_elapsed := 0.0
var _draw_real := 0.0
var _draw_t := 0.0
var _attack_after_draw := false
var _shift_pressed_msec := -1
var _form13_queue: Array[int] = []

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func _ready():
	var aps := find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		push_warning("yoriichi_character: no AnimationPlayer found in FBX")
		return
	_anim = aps[0]
	_visual = _anim.get_parent()
	_merge_animations_from(idle_source)
	_merge_animations_from(run_source)
	_fl_anim = _merge_animations_from(fl_run_source)
	_fr_anim = _merge_animations_from(fr_run_source)
	_turn_l_anim = "Turn_Left"
	_turn_r_anim = "Turn_Right"
	_add_animation_resource(_turn_l_anim, turn_left_resource)
	_add_animation_resource(_turn_r_anim, turn_right_resource)
	_add_animation_resource(roll_anim, roll_anim_resource)
	_add_animation_resource(jump_anim, jump_anim_resource)
	_add_animation_resource(attack_combo_anim, attack_combo_resource)
	_add_animation_resource(attack_spin_anim, attack_spin_resource)
	_add_animation_resource(attack_judgment_anim, attack_judgment_resource)
	_add_animation_resource(attack_combo_1_anim, attack_combo_1_resource)
	_add_animation_resource(attack_spin_jump_anim, attack_spin_jump_resource)
	_add_animation_resource(draw_anim, draw_anim_resource)
	_add_animation_resource(run_fast_anim, preload("res://animations/yoriichi_run_fast.res"))
	for n in [walk_anim, idle_anim, run_anim, run_fast_anim, _fl_anim, _fr_anim]:
		if n != "" and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in [draw_anim, roll_anim, jump_anim, attack_combo_anim, attack_spin_anim,
			attack_judgment_anim, attack_combo_1_anim, attack_spin_jump_anim,
			_turn_l_anim, _turn_r_anim]:
		if n != "" and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_NONE
	_sword_hand = _find_first("Sword_Hand")
	_sword_sheathed = _find_first("Sword_Sheathed")
	_apply_sword_visibility()
	_build_tree()

func _find_first(n: String) -> Node3D:
	var r := find_children(n, "", true, false)
	return r[0] if r.size() > 0 else null

func _library() -> AnimationLibrary:
	var lib_name: StringName = _anim.get_animation_library_list()[0] if _anim.get_animation_library_list().size() > 0 else &""
	if not _anim.has_animation_library(lib_name):
		_anim.add_animation_library(lib_name, AnimationLibrary.new())
	return _anim.get_animation_library(lib_name)

## 合併同骨架 FBX 的動畫進本角色 AnimationPlayer；回傳第一個新增的動畫名。
func _merge_animations_from(source: PackedScene) -> String:
	if source == null:
		return ""
	var first_new := ""
	var tmp := source.instantiate()
	var src_aps := tmp.find_children("*", "AnimationPlayer", true, false)
	if not src_aps.is_empty():
		var src: AnimationPlayer = src_aps[0]
		var lib := _library()
		for n in src.get_animation_list():
			if not lib.has_animation(n):
				lib.add_animation(n, src.get_animation(n).duplicate())
				if first_new == "":
					first_new = n
	tmp.free()
	return first_new

func _add_animation_resource(animation_name: String, animation: Animation) -> void:
	if animation_name == "" or animation == null or _anim.has_animation(animation_name):
		return
	_library().add_animation(animation_name, animation)

# --- AnimationTree ---------------------------------------------------------
func _anim_node(name: String, backward := false) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = name
	if backward:
		n.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
	return n

func _clip_node(name: String, from: float, to: float, loop := false) -> AnimationNodeAnimation:
	var n := _anim_node(name)
	n.use_custom_timeline = true
	n.start_offset = from
	n.timeline_length = to - from
	n.stretch_time_scale = false
	n.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return n

## 內含 TimeScale 的單動畫子樹（給需要獨立倍率的 SM 狀態）。
## scale 是 AnimationTree 的 runtime 參數，樹啟用後由 parameters/loco/<state>/ts/scale 設定。
func _scaled_state(clip: AnimationNodeAnimation) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("anim", clip)
	bt.add_node("ts", AnimationNodeTimeScale.new())
	bt.connect_node("ts", 0, "anim")
	bt.connect_node("output", 0, "ts")
	return bt

func _build_tree() -> void:
	var root := AnimationNodeBlendTree.new()

	# --- loco state machine ---
	var sm := AnimationNodeStateMachine.new()
	var states := {
		"Idle": _anim_node(idle_anim),
		"Walk": _anim_node(walk_anim),
		"Run": _anim_node(run_fast_anim if _anim.has_animation(run_fast_anim) else run_anim),
		"JumpStart": _scaled_state(_clip_node(jump_anim, 0.0, JUMP_START_END)),
		"Fall": _clip_node(jump_anim, JUMP_AIR_LOOP.x, JUMP_AIR_LOOP.y, true),
		"Land": _scaled_state(_clip_node(jump_anim, JUMP_LAND_START, jump_anim_resource.length)),
	}
	if _anim.has_animation(_turn_l_anim):
		states["TurnL"] = _anim_node(_turn_l_anim)
	if _anim.has_animation(_turn_r_anim):
		states["TurnR"] = _anim_node(_turn_r_anim)
	if _fl_anim != "":
		states["RunFL"] = _anim_node(_fl_anim)
	if _fr_anim != "":
		states["RunFR"] = _anim_node(_fr_anim)
	# 後退步：Walking 是零位移的完美循環（inventory 實測 start_end_diff 0.0°），
	# 反播即為合法 backpedal，不需新動畫。
	states["BackPedal"] = _anim_node(walk_anim, true)
	for s in states:
		sm.add_node(s, states[s])
	for a in states:
		for b in states:
			if a == b:
				continue
			var tr := AnimationNodeStateMachineTransition.new()
			tr.xfade_time = blend_time
			if b == "JumpStart" or b == "Land":
				tr.xfade_time = 0.08
			elif b == "Fall":
				tr.xfade_time = 0.15
			sm.add_transition(a, b, tr)
	root.add_node("loco", sm)

	# --- upper one-shot（bone filter：上半身） ---
	var upper_sel := AnimationNodeTransition.new()
	var combo_len := attack_combo_resource.length
	var upper_inputs := {
		"draw": _anim_node(draw_anim),
		"sheathe": _anim_node(draw_anim, true),
		"atk1": _clip_node(attack_combo_anim, combo_len * COMBO_SECTION_RANGES[0].x, combo_len * COMBO_SECTION_RANGES[0].y),
		"atk2": _clip_node(attack_combo_anim, combo_len * COMBO_SECTION_RANGES[1].x, combo_len * COMBO_SECTION_RANGES[1].y),
		"atk3": _clip_node(attack_combo_anim, combo_len * COMBO_SECTION_RANGES[2].x, combo_len * COMBO_SECTION_RANGES[2].y),
	}
	_setup_transition(root, upper_sel, "upper_sel", upper_inputs)
	var ts_upper := AnimationNodeTimeScale.new()
	root.add_node("ts_upper", ts_upper)
	root.connect_node("ts_upper", 0, "upper_sel")
	var upper := AnimationNodeOneShot.new()
	upper.fadein_time = 0.06
	upper.fadeout_time = 0.1
	upper.filter_enabled = true
	for b in UPPER_BONES:
		upper.set_filter_path("Armature/Skeleton3D:" + b, true)
	root.add_node("upper", upper)
	root.connect_node("upper", 0, "loco")
	root.connect_node("upper", 1, "ts_upper")

	# --- full-body one-shot ---
	var full_sel := AnimationNodeTransition.new()
	var full_inputs := {
		"roll": _anim_node(roll_anim),
		"spin": _anim_node(attack_spin_anim),
		"judgment": _anim_node(attack_judgment_anim),
		"combo1": _anim_node(attack_combo_1_anim),
		"spinjump": _anim_node(attack_spin_jump_anim),
	}
	_setup_transition(root, full_sel, "full_sel", full_inputs)
	var ts_full := AnimationNodeTimeScale.new()
	root.add_node("ts_full", ts_full)
	root.connect_node("ts_full", 0, "full_sel")
	var full := AnimationNodeOneShot.new()
	full.fadein_time = 0.05
	full.fadeout_time = 0.1
	root.add_node("full", full)
	root.connect_node("full", 0, "upper")
	root.connect_node("full", 1, "ts_full")
	root.connect_node("output", 0, "full")

	_tree = AnimationTree.new()
	_tree.name = "Tree"
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim)
	_tree.root_node = _tree.get_path_to(_visual)
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_tree.tree_root = root
	_tree.active = true
	_tree.set("parameters/loco/JumpStart/ts/scale", jump_start_speed)
	_tree.set("parameters/loco/Land/ts/scale", jump_land_speed)
	_playback().start("Idle")

func _setup_transition(root: AnimationNodeBlendTree, sel: AnimationNodeTransition, sel_name: String, inputs: Dictionary) -> void:
	sel.xfade_time = combo_section_blend
	sel.input_count = inputs.size()
	root.add_node(sel_name, sel)
	var i := 0
	for key: String in inputs:
		sel.set_input_name(i, key)
		sel.set_input_reset(i, true)
		var node_name: String = sel_name + "_" + key
		root.add_node(node_name, inputs[key])
		root.connect_node(sel_name, i, node_name)
		i += 1

func _playback() -> AnimationNodeStateMachinePlayback:
	return _tree.get("parameters/loco/playback")

func _fire_upper(input_name: String, time_scale: float) -> void:
	_tree.set("parameters/upper_sel/transition_request", input_name)
	_tree.set("parameters/ts_upper/scale", time_scale)
	_tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _fire_full(input_name: String, time_scale: float) -> void:
	_tree.set("parameters/full_sel/transition_request", input_name)
	_tree.set("parameters/ts_full/scale", time_scale)
	_tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _fade_upper() -> void:
	_tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)

func _fade_full() -> void:
	_tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)

# ---------------------------------------------------------------------------
# Physics
# ---------------------------------------------------------------------------
func _physics_process(delta):
	var input_dir := _read_input_dir()
	var grounded := is_on_floor()
	var running := Input.is_key_pressed(KEY_SHIFT)
	var cur_speed := run_speed if running else speed
	var moving := input_dir.length_squared() > 0.0

	# --- 水平速度 ---
	if action_state == ActionState.DODGING:
		_update_roll_movement(delta)
	elif not grounded:
		_apply_air_control(input_dir, cur_speed, delta)
	elif action_state == ActionState.ATTACKING:
		var f := attack_move_factor_heavy if _attack_layer == "full" \
			else (attack_move_factor_run if running else attack_move_factor_walk)
		velocity.x = input_dir.x * cur_speed * f
		velocity.z = input_dir.z * cur_speed * f
	else:
		velocity.x = input_dir.x * cur_speed
		velocity.z = input_dir.z * cur_speed

	if not grounded:
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	if action_state == ActionState.JUMPING:
		_update_jump(delta)

	move_and_slide()

	if action_state == ActionState.DODGING:
		if _action_elapsed >= _roll_duration:
			_finish_roll()
	elif action_state == ActionState.ATTACKING:
		_update_attack(delta, input_dir)
	elif action_state == ActionState.JUMPING:
		if _jump_launched and _air_t > 0.1 and is_on_floor():
			_finish_jump(moving)

	_update_sword(delta)
	_update_visual_yaw(delta, input_dir, moving)
	if _tree:
		_update_locomotion(delta, input_dir, is_on_floor(), moving, running)

func _read_input_dir() -> Vector3:
	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	return input_dir.normalized()

func _apply_air_control(input_dir: Vector3, cur_speed: float, delta: float) -> void:
	var h := Vector2(velocity.x, velocity.z)
	if input_dir.is_zero_approx():
		h = h.move_toward(Vector2.ZERO, air_drag * delta)
	else:
		var desired := Vector2(input_dir.x, input_dir.z) * cur_speed
		h = h.move_toward(desired, air_acceleration * air_control * delta)
	velocity.x = h.x
	velocity.z = h.y

func _update_visual_yaw(delta: float, input_dir: Vector3, moving: bool) -> void:
	if not moving or _visual == null or action_state == ActionState.DODGING:
		return
	var target_yaw := atan2(input_dir.x, input_dir.z)
	var w := turn_speed * delta
	if action_state == ActionState.ATTACKING:
		w *= attack_turn_control
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clampf(w, 0.0, 1.0))

# --- locomotion 狀態選擇 ----------------------------------------------------
func _update_locomotion(delta: float, input_dir: Vector3, grounded: bool, moving: bool, running: bool) -> void:
	if action_state == ActionState.DODGING or (action_state == ActionState.ATTACKING and _attack_layer == "full"):
		return   # 全身 override 顯示中
	var pb := _playback()
	if not grounded:
		_air_t += delta
		var falling := (action_state == ActionState.JUMPING and _jump_launched and velocity.y <= 0.0) \
			or (action_state != ActionState.JUMPING and _air_t > coyote_time)
		if falling and pb.get_current_node() != &"Fall":
			pb.travel("Fall")
		return
	_air_t = 0.0
	if action_state == ActionState.JUMPING:
		return   # 蹲伏預備：JumpStart 播放中
	if _land_lock > 0.0:
		if moving:
			_land_lock = 0.0   # 有輸入直接接 locomotion
		else:
			_land_lock -= delta
			return
	if _turn_lock > 0.0:
		_turn_lock -= delta
		return
	_sector_hold = maxf(_sector_hold - delta, 0.0)
	if not moving:
		pb.travel("Idle")
		return
	# 急轉（夾角 > turn_angle_deg）優先於 sector 側身跑姿。
	if running and _anim.has_animation(_turn_l_anim) and pb.get_current_node() == &"Run":
		var diff := wrapf(atan2(input_dir.x, input_dir.z) - _visual.rotation.y, -PI, PI)
		if absf(diff) > deg_to_rad(turn_angle_deg):
			pb.travel("TurnL" if diff > 0.0 else "TurnR")
			_turn_lock = turn_time
			return
	pb.travel(_locomotion_target(running))

## 8 向 locomotion：以角色 local 速度方向分 sector（不是世界座標、不是輸入鍵）。
## 0°=前、+90°=左、180°=後。Forward |a|<22.5 → Run/Walk；22.5~112.5 → RunFL
## （側向 67.5~112.5 目前無專用 strafe clip，代用 FL 側身跑，鏡像同理）；
## |a|>112.5 → BackPedal（Walking 反播）。sector_min_hold 防抖。
func _locomotion_target(running: bool) -> String:
	var lv := Vector2(velocity.x, velocity.z)
	var forward_state := "Run" if running else "Walk"
	if lv.length() < 0.5 or _visual == null:
		return forward_state
	var yaw: float = _visual.rotation.y
	var fwd := Vector2(sin(yaw), cos(yaw))
	var left := Vector2(cos(yaw), -sin(yaw))
	var nd := lv.normalized()
	var ang := rad_to_deg(atan2(nd.dot(left), nd.dot(fwd)))
	var target := forward_state
	if absf(ang) > 112.5:
		target = "BackPedal"
	elif running and _fl_anim != "" and ang > 22.5:
		target = "RunFL"
	elif running and _fr_anim != "" and ang < -22.5:
		target = "RunFR"
	if target != _sector_state:
		if _sector_hold > 0.0:
			return _sector_state   # 換 sector 後最短持續 0.15 s，防高速抖動
		_sector_state = target
		_sector_hold = sector_min_hold
	return _sector_state

# ---------------------------------------------------------------------------
# Input（正式戰鬥輸入只有滑鼠；J/K/L 已移除，無 debug fallback）
# Space = 跳躍；Shift 按住 = 疾跑、快按 = 翻滾；Q = 拔/收刀 toggle。
# ---------------------------------------------------------------------------
func _unhandled_input(event):
	if event is InputEventKey and not event.echo:
		if event.pressed:
			match event.keycode:
				draw_key:
					request_sword_toggle()
				KEY_SPACE:
					request_jump()
				KEY_SHIFT:
					_shift_pressed_msec = Time.get_ticks_msec()
		elif event.keycode == KEY_SHIFT and _shift_pressed_msec >= 0:
			if (Time.get_ticks_msec() - _shift_pressed_msec) / 1000.0 <= shift_tap_time:
				request_dodge()
			_shift_pressed_msec = -1
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			request_primary_attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			request_special_attack(attack_spin_anim)

# ---------------------------------------------------------------------------
# Jump
# ---------------------------------------------------------------------------
func request_jump() -> void:
	if sword_state == SwordState.DRAWING or sword_state == SwordState.SHEATHING:
		return
	if action_state != ActionState.FREE or not is_on_floor():
		return
	action_state = ActionState.JUMPING
	_action_elapsed = 0.0
	_jump_launched = false
	_air_t = 0.0
	_playback().travel("JumpStart")

func _update_jump(delta: float) -> void:
	_action_elapsed += delta
	if not _jump_launched and _action_elapsed >= JUMP_TAKEOFF_CLIP / jump_start_speed:
		_jump_launched = true
		velocity.y = jump_velocity
	if not is_on_floor():
		_air_t += delta

func _finish_jump(moving: bool) -> void:
	action_state = ActionState.FREE
	_jump_launched = false
	_action_elapsed = 0.0
	if moving:
		_land_lock = 0.0        # 有輸入：直接接 Run/Walk
	else:
		_land_lock = land_lock_time
		_playback().travel("Land")

# ---------------------------------------------------------------------------
# Roll
# ---------------------------------------------------------------------------
func request_dodge(direction_override: Vector3 = Vector3.ZERO) -> void:
	if sword_state == SwordState.DRAWING or sword_state == SwordState.SHEATHING:
		return
	if action_state != ActionState.FREE or not is_on_floor():
		return
	var horizontal_override := Vector3(direction_override.x, 0.0, direction_override.z)
	_dodge_dir = horizontal_override.normalized() if not horizontal_override.is_zero_approx() else _read_input_dir()
	if _dodge_dir.is_zero_approx():
		var yaw := _visual.rotation.y if _visual else rotation.y
		_dodge_dir = Vector3(sin(yaw), 0.0, cos(yaw)).normalized()
	elif _visual:
		_visual.rotation.y = atan2(_dodge_dir.x, _dodge_dir.z)
	action_state = ActionState.DODGING
	_action_elapsed = 0.0
	_attack_after_roll = false
	_roll_duration = roll_anim_resource.length / roll_animation_speed
	_fire_full("roll", roll_animation_speed)

func _update_roll_movement(delta: float) -> void:
	var previous_t := clampf(_action_elapsed / _roll_duration, 0.0, 1.0) if _roll_duration > 0.0 else 1.0
	_action_elapsed = minf(_action_elapsed + delta, _roll_duration)
	var current_t := clampf(_action_elapsed / _roll_duration, 0.0, 1.0) if _roll_duration > 0.0 else 1.0
	# ease-out p(t) = 1 - (1-t)^2；位移驅動 CharacterBody3D 本體，碰撞體永遠跟隨。
	var previous_curve := 1.0 - pow(1.0 - previous_t, 2.0)
	var current_curve := 1.0 - pow(1.0 - current_t, 2.0)
	var frame_distance := roll_distance * (current_curve - previous_curve)
	var roll_velocity := _dodge_dir * (frame_distance / delta) if delta > 0.0 else Vector3.ZERO
	velocity.x = roll_velocity.x
	velocity.z = roll_velocity.z

func _finish_roll() -> void:
	action_state = ActionState.FREE
	_action_elapsed = 0.0
	_roll_duration = 0.0
	_fade_full()
	if _attack_after_roll:
		_attack_after_roll = false
		if sword_state == SwordState.DRAWN:
			# dodge counter（斜陽轉身雛形）：沿翻滾方向小前衝＋立即反擊斬。
			velocity.x += _dodge_dir.x * 2.0
			velocity.z += _dodge_dir.z * 2.0
			_start_combo()
	# 否則不強制回 Idle：locomotion 分支依當前輸入接回 Run / Walk / Idle。

# ---------------------------------------------------------------------------
# Attack（LMB 輕連段 = upper layer 邊跑邊斬；RMB/型 heavy = full-body override）
# ---------------------------------------------------------------------------
func request_primary_attack() -> void:
	if sword_state == SwordState.SHEATHED and action_state == ActionState.FREE:
		# quick-draw：收刀狀態直接 LMB = 拔刀，刀離鞘（t=0.65）瞬間接第一段。
		_attack_after_draw = true
		request_draw()
		return
	if action_state == ActionState.DODGING and sword_state == SwordState.DRAWN:
		_attack_after_roll = true   # dodge counter：roll 結束自動接反擊斬
		return
	if sword_state != SwordState.DRAWN:
		return
	if action_state == ActionState.ATTACKING and combo_stage > 0:
		_combo_queued_inputs = mini(_combo_queued_inputs + 1, COMBO_SECTION_RANGES.size() - combo_stage)
		combo_input_buffered = _combo_queued_inputs > 0
		_combo_buffer_remaining = combo_input_buffer_time
		return
	if action_state != ActionState.FREE and action_state != ActionState.JUMPING:
		return
	_start_combo()

func _start_combo() -> void:
	action_state = ActionState.ATTACKING
	_attack_layer = "upper"
	active_form = 0
	combo_stage = 1
	_combo_queued_inputs = 0
	combo_input_buffered = false
	_combo_buffer_remaining = 0.0
	_start_light_section(combo_stage)

func _start_light_section(stage: int) -> void:
	var range := COMBO_SECTION_RANGES[stage - 1]
	var section_len := attack_combo_resource.length * (range.y - range.x)
	_action_real = section_len / attack_speed_scale
	_action_elapsed = 0.0
	_fire_upper("atk%d" % stage, attack_speed_scale)

func request_special_attack(animation_name: String) -> void:
	if sword_state != SwordState.DRAWN:
		return
	if action_state != ActionState.FREE and action_state != ActionState.JUMPING:
		return
	var key := _full_input_for(animation_name)
	if key == "":
		push_warning("yoriichi_character: attack animation is unavailable: " + animation_name)
		return
	action_state = ActionState.ATTACKING
	_attack_layer = "full"
	active_form = 0
	combo_stage = 0
	_combo_queued_inputs = 0
	combo_input_buffered = false
	_action_real = _full_anim_length(animation_name) / attack_speed_scale
	_action_elapsed = 0.0
	_fire_full(key, attack_speed_scale)

func _full_input_for(animation_name: String) -> String:
	match animation_name:
		attack_spin_anim: return "spin"
		attack_judgment_anim: return "judgment"
		attack_combo_1_anim: return "combo1"
		attack_spin_jump_anim: return "spinjump"
	return ""

func _full_anim_length(animation_name: String) -> float:
	return _anim.get_animation(animation_name).length if _anim.has_animation(animation_name) else 0.0

func _update_attack(delta: float, _input_dir: Vector3) -> void:
	_action_elapsed += delta
	if _combo_queued_inputs > 0:
		_combo_buffer_remaining = maxf(_combo_buffer_remaining - delta, 0.0)
		if _combo_buffer_remaining <= 0.0:
			_combo_queued_inputs = 0
			combo_input_buffered = false
	var progress := clampf(_action_elapsed / _action_real, 0.0, 1.0) if _action_real > 0.0 else 1.0
	if combo_stage > 0:
		if _combo_queued_inputs > 0 and progress >= combo_cancel_start and progress <= combo_cancel_end \
				and combo_stage < COMBO_SECTION_RANGES.size():
			_advance_combo()
		elif progress >= 1.0:
			if _combo_queued_inputs > 0 and combo_stage < COMBO_SECTION_RANGES.size():
				_advance_combo()
			else:
				_finish_attack()
	elif progress >= 1.0:
		_finish_attack()

func _advance_combo() -> void:
	_combo_queued_inputs = maxi(_combo_queued_inputs - 1, 0)
	combo_input_buffered = _combo_queued_inputs > 0
	_combo_buffer_remaining = combo_input_buffer_time if combo_input_buffered else 0.0
	combo_stage += 1
	_start_light_section(combo_stage)

func _finish_attack() -> void:
	var was_layer := _attack_layer
	action_state = ActionState.FREE
	combo_stage = 0
	active_form = 0
	_combo_queued_inputs = 0
	combo_input_buffered = false
	_action_elapsed = 0.0
	_action_real = 0.0
	if was_layer == "upper":
		_fade_upper()
	else:
		_fade_full()
	if not _form13_queue.is_empty():
		var next_id: int = _form13_queue.pop_front()
		if execute_form(next_id):
			return
		_form13_queue.clear()
	if pending_sheathe and sword_state == SwordState.DRAWN:
		pending_sheathe = false
		_start_sheathe()

# ---------------------------------------------------------------------------
# Draw / Sheathe（upper layer：腿繼續 locomotion，跑步中拔/收刀不停下）
# ---------------------------------------------------------------------------
func request_sword_toggle():
	match sword_state:
		SwordState.SHEATHED:
			request_draw()
		SwordState.DRAWN:
			if action_state == ActionState.ATTACKING:
				pending_sheathe = true
			elif action_state == ActionState.FREE or action_state == ActionState.JUMPING:
				_start_sheathe()

func request_draw():
	if sword_state != SwordState.SHEATHED:
		return
	if action_state == ActionState.DODGING or action_state == ActionState.ATTACKING:
		return
	sword_state = SwordState.DRAWING
	_draw_real = draw_anim_resource.length / draw_speed_scale
	_draw_elapsed = 0.0
	_draw_t = 0.0
	_apply_sword_visibility()
	_fire_upper("draw", draw_speed_scale)

func _start_sheathe() -> void:
	sword_state = SwordState.SHEATHING
	_draw_real = draw_anim_resource.length / draw_speed_scale
	_draw_elapsed = 0.0
	_draw_t = 1.0
	_apply_sword_visibility()
	_fire_upper("sheathe", draw_speed_scale)

func _update_sword(delta: float) -> void:
	if sword_state == SwordState.DRAWING:
		_draw_elapsed += delta
		_draw_t = clampf(_draw_elapsed / _draw_real, 0.0, 1.0) if _draw_real > 0.0 else 1.0
		_apply_sword_visibility()
		if _attack_after_draw and _draw_t >= t_unsheathe:
			# 拔刀斬（居合）：刀一離鞘立即取消剩餘 draw、接第一段斬擊。
			sword_state = SwordState.DRAWN
			_apply_sword_visibility()
			_attack_after_draw = false
			_start_combo()
			return
		if _draw_t >= 1.0:
			sword_state = SwordState.DRAWN
			_apply_sword_visibility()
			if _attack_after_draw:
				_attack_after_draw = false
				_start_combo()
	elif sword_state == SwordState.SHEATHING:
		_draw_elapsed += delta
		_draw_t = 1.0 - (clampf(_draw_elapsed / _draw_real, 0.0, 1.0) if _draw_real > 0.0 else 1.0)
		_apply_sword_visibility()
		if _draw_t <= 0.0:
			sword_state = SwordState.SHEATHED
			_apply_sword_visibility()

## 依狀態與拔刀進度決定哪一把刀可見；反向共用同一個 t_unsheathe 門檻。
func _apply_sword_visibility():
	var in_hand := false
	match sword_state:
		SwordState.SHEATHED:
			in_hand = false
		SwordState.DRAWING, SwordState.SHEATHING:
			in_hand = _draw_t >= t_unsheathe
		SwordState.DRAWN:
			in_hand = true
	if _sword_sheathed:
		_sword_sheathed.visible = not in_hand
	if _sword_hand:
		_sword_hand.visible = in_hand

# ---------------------------------------------------------------------------
# Sun Breathing（data-driven；定義見 sun_breathing.gd）
# ---------------------------------------------------------------------------
func add_breath(amount: float) -> void:
	sun_breath_gauge = clampf(sun_breath_gauge + amount, 0.0, sun_breath_max)

func can_use_form(id: int) -> bool:
	if not SunBreathing.FORMS.has(id):
		return false
	var def: Dictionary = SunBreathing.FORMS[id]
	if def.anim == "" or def.required_mastery > sun_mastery:
		return false
	if not def.allowed_airborne and not is_on_floor():
		return false
	return true

## 執行單一型。缺動畫的型誠實回傳 false，不播假內容。
func execute_form(id: int) -> bool:
	if sword_state != SwordState.DRAWN or not can_use_form(id):
		return false
	if action_state != ActionState.FREE and action_state != ActionState.JUMPING:
		return false
	var def: Dictionary = SunBreathing.FORMS[id]
	action_state = ActionState.ATTACKING
	active_form = id
	combo_stage = 0
	_combo_queued_inputs = 0
	combo_input_buffered = false
	if def.impulse > 0.0 and _visual:
		var yaw: float = _visual.rotation.y
		velocity.x += sin(yaw) * def.impulse
		velocity.z += cos(yaw) * def.impulse
	if def.layer == "upper":
		_attack_layer = "upper"
		var clip_len: float = _full_anim_length(def.anim) * (def.section.y - def.section.x)
		_action_real = clip_len / def.speed
		_action_elapsed = 0.0
		# 型 1/3 的 section 與 atk1/atk2 相同，直接重用 upper 段落節點。
		var section_input := "atk1" if def.section.is_equal_approx(COMBO_SECTION_RANGES[0]) else "atk2"
		_fire_upper(section_input, def.speed)
	else:
		_attack_layer = "full"
		var key := _full_input_for(def.anim)
		if key == "":
			action_state = ActionState.FREE
			active_form = 0
			return false
		_action_real = _full_anim_length(def.anim) / def.speed
		_action_elapsed = 0.0
		_fire_full(key, def.speed)
	return true

## 拾參ノ型：把可用的前十二型按 FORM13_SEQUENCE 高速循環（框架；
## 解鎖條件 = form13_unlocked 或 gauge 滿）。缺動畫的型跳過。
func start_form13() -> bool:
	if sword_state != SwordState.DRAWN or action_state != ActionState.FREE:
		return false
	if not form13_unlocked and sun_breath_gauge < form13_gauge_cost:
		return false
	_form13_queue.clear()
	for id in SunBreathing.FORM13_SEQUENCE:
		if can_use_form(id):
			_form13_queue.append(id)
	if _form13_queue.is_empty():
		return false
	sun_breath_gauge = 0.0
	var first: int = _form13_queue.pop_front()
	return execute_form(first)
