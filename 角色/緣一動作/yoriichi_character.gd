extends CharacterBody3D

@export var speed := 4.0
@export var run_speed := 7.0
@export var gravity := 20.0
@export var turn_speed := 12.0        # 視覺模型轉向速度（lerp 權重）
@export var blend_time := 0.2         # Idle ↔ Walking ↔ Running 交叉淡入秒數

@export var walk_anim := "Armature|Armature|walking_man|baselayer"
@export var idle_anim := "Armature|Armature|Idle_11|baselayer"
@export var run_anim := "Armature|Armature|running|baselayer"
@export var run_fast_anim := "RunFast"
## 含 Idle / Running 動畫的 FBX（同一角色、同一骨架）。啟動時只抽出它們的 Animation，
## 合併進現有 AnimationPlayer；不會實例化第二隻角色到場景裡。
@export var idle_source: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Idle_11_withSkin.fbx")
@export var run_source: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Running_withSkin.fbx")

@export_group("Gameplay Animations")
@export var run_fast_anim_resource: Animation = preload("res://animations/yoriichi_run_fast.res")
@export var roll_anim := "Roll_Dodge"
@export var roll_anim_resource: Animation = preload("res://animations/yoriichi_roll_dodge.res")
@export var attack_combo_anim := "Attack_Combo"
@export var attack_combo_resource: Animation = preload("res://animations/yoriichi_attack_combo.res")
@export var attack_spin_anim := "Attack_Spin"
@export var attack_spin_resource: Animation = preload("res://animations/yoriichi_attack_spin.res")
@export var attack_judgment_anim := "Attack_Judgment"
@export var attack_judgment_resource: Animation = preload("res://animations/yoriichi_attack_judgment.res")
@export var jump_anim := "Jump"
@export var jump_anim_resource: Animation = preload("res://animations/yoriichi_jump.res")
## 起跳速度。空中時間 2v/g 需與 Jump clip 的空中段（0.533~1.067 s，共 0.533 s）一致：
## v = gravity * 0.533 / 2。動畫垂直弧線頂點 +0.63 m，物理跳高 v²/2g ≈ 0.71 m。
@export var jump_velocity := 5.33
## Jump clip 的離地時間點（前 0.533 s 是蹲伏預備，角色仍在地面）。
@export var jump_takeoff_time := 0.533
## 空中攻擊結束後 blend 回 Jump clip 的這個時間點（下落姿勢）。
@export var jump_air_pose_time := 0.9
@export_group("Air Inertia")
## 空中不直接覆寫水平速度：有輸入時以 air_acceleration * air_control (m/s²)
## move_toward 目標速度；無輸入時只以 air_drag (m/s²) 衰減 → 保留起跳慣性。
@export var air_acceleration := 4.0
@export var air_control := 0.35
@export var air_drag := 0.2
@export_group("Actions")
@export var roll_distance := 6.4
@export var roll_animation_speed := 3.0
@export var action_blend_time := 0.12
@export var attack_speed_scale := 3.0
## 地面攻擊期間保留的移動量（locomotion 速度 × 此係數）。
@export var attack_move_factor := 0.65
## 攻擊結束 → Walk/Run/Idle 的 blend。
@export var attack_recovery_blend := 0.12
## Shift 按住 = 疾跑；按下後在此秒數內放開 = 翻滾。
@export var shift_tap_time := 0.25
@export_range(0.0, 1.0) var combo_cancel_start := 0.35
@export_range(0.0, 1.0) var combo_cancel_end := 0.65
@export var combo_input_buffer_time := 0.30
@export var combo_section_blend := 0.035
@export_range(0.0, 1.0) var attack_turn_control := 0.35

const COMBO_SECTION_RANGES: Array[Vector2] = [
	Vector2(0.00, 0.34),
	Vector2(0.30, 0.67),
	Vector2(0.63, 1.00),
]

# ---------------------------------------------------------------------------
# 刀：兩個 socket、兩個刀實例（同一 GLB），只切 visible、不 reparent。
#   SheathSocket (Hips)      Sword_Sheathed  左腰居合佩刀（平常 / Idle / Walk / Run）
#   HandSocket   (RightHand) Sword_Hand      右手持刀（拔刀後）
#
# 狀態：SHEATHED --Q--> DRAWING (draw anim) --> DRAWN（刀留在右手，不自動收回）
# DRAWING 期間依動畫進度 t（0~1）切 socket：
#   [0, t_unsheathe)  Sword_Sheathed 可見、Sword_Hand 隱藏
#   [t_unsheathe, 1]  Sword_Sheathed 隱藏、Sword_Hand 可見（刀離開刀鞘）
# 收刀流程尚未實作（DRAWN 再按 Q 目前不動作）。
# ---------------------------------------------------------------------------
enum SwordState { SHEATHED, DRAWING, DRAWN, SHEATHING }
enum ActionState { FREE, ATTACKING, DODGING, JUMPING }

@export_group("Sword Draw")
@export var draw_key := KEY_Q
## 右手從左腰拔刀的動畫名稱（留空 = 沒有 → 按 Q 只警告，不做假過場）。
@export var draw_anim := "Draw_Sword"
## 裁切好的拔刀 Animation 資源（由 build_draw_sword.gd 從 Meshy 拔刀 FBX 產生：
## 只保留「站姿 → 握柄 → 拔刀 → 完全拔出」0~1.0 s，收刀部分已裁掉，LOOP_NONE）。
@export var draw_anim_resource: Animation = preload("res://yoriichi_draw_sword.res")
## 或改用含拔刀動畫的同骨架 FBX（track 路徑需為 Armature/Skeleton3D:<bone>）；啟動時合併。
@export var draw_source: PackedScene
## 拔刀動畫進度（0~1）中「刀離開刀鞘」的時間點。Draw_Sword：刀鍔在 0.63~0.67 s 離鞘 → 0.65。
@export_range(0.0, 1.0) var t_unsheathe := 0.65
## DRAWN 狀態的站立動畫（Combat Idle）。留空 = 沿用 idle_anim。
@export var drawn_idle_anim := ""
@export var drawn_idle_source: PackedScene
## DRAWN 狀態是否允許 WASD 移動（移動時沿用 walk/run 動畫）。
@export var can_move_when_drawn := true

var sword_state: SwordState = SwordState.SHEATHED
var action_state: ActionState = ActionState.FREE
var _draw_t := 0.0
var _draw_len := 0.0
var _action_anim := ""
var _action_elapsed := 0.0
var _dodge_dir := Vector3.ZERO
var _roll_duration := 0.0
var _jump_launched := false
var _jump_anim_done := false
var pending_sheathe := false
var _shift_pressed_msec := -1
var _recovery_blend_pending := false
var combo_stage := 0
var combo_input_buffered := false
var _combo_queued_inputs := 0
var _combo_buffer_remaining := 0.0
var _combo_section_start := 0.0
var _combo_section_end := 0.0

var _anim: AnimationPlayer
var _visual: Node3D                   # FBX 視覺根節點（只旋轉這個，不動碰撞膠囊）
var _current := ""
var _sword_hand: Node3D
var _sword_sheathed: Node3D

func _ready():
	var aps := find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		push_warning("yoriichi_character: no AnimationPlayer found in FBX")
		return
	_anim = aps[0]
	_visual = _anim.get_parent()
	_merge_animations_from(idle_source)
	_merge_animations_from(run_source)
	_merge_animations_from(draw_source)
	_merge_animations_from(drawn_idle_source)
	_add_animation_resource(run_fast_anim, run_fast_anim_resource)
	_add_animation_resource(roll_anim, roll_anim_resource)
	_add_animation_resource(attack_combo_anim, attack_combo_resource)
	_add_animation_resource(attack_spin_anim, attack_spin_resource)
	_add_animation_resource(attack_judgment_anim, attack_judgment_resource)
	_add_animation_resource(jump_anim, jump_anim_resource)
	if draw_anim_resource and draw_anim != "" and not _anim.has_animation(draw_anim):
		_library().add_animation(draw_anim, draw_anim_resource)
	for n in [walk_anim, idle_anim, run_anim, run_fast_anim, drawn_idle_anim]:
		if n != "" and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in [draw_anim, roll_anim, attack_combo_anim, attack_spin_anim, attack_judgment_anim, jump_anim]:
		if n != "" and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_NONE
	_anim.animation_finished.connect(_on_animation_finished)
	_sword_hand = _find_first("Sword_Hand")
	_sword_sheathed = _find_first("Sword_Sheathed")
	sword_state = SwordState.SHEATHED
	_apply_sword_visibility()
	_play(idle_anim)

func _find_first(n: String) -> Node3D:
	var r := find_children(n, "", true, false)
	return r[0] if r.size() > 0 else null

func _library() -> AnimationLibrary:
	var lib_name: StringName = _anim.get_animation_library_list()[0] if _anim.get_animation_library_list().size() > 0 else &""
	if not _anim.has_animation_library(lib_name):
		_anim.add_animation_library(lib_name, AnimationLibrary.new())
	return _anim.get_animation_library(lib_name)

## 把另一個同骨架 FBX 的 AnimationPlayer 內的動畫複製到本角色的 AnimationPlayer。
## track 路徑同為 Armature/Skeleton3D:<bone>，可直接共用。
func _merge_animations_from(source: PackedScene):
	if source == null:
		return
	var tmp := source.instantiate()
	var src_aps := tmp.find_children("*", "AnimationPlayer", true, false)
	if not src_aps.is_empty():
		var src: AnimationPlayer = src_aps[0]
		var lib := _library()
		for n in src.get_animation_list():
			if not lib.has_animation(n):
				lib.add_animation(n, src.get_animation(n).duplicate())
	tmp.free()

func _add_animation_resource(animation_name: String, animation: Animation) -> void:
	if animation_name == "" or animation == null or _anim.has_animation(animation_name):
		return
	_library().add_animation(animation_name, animation)

func _play(name: String, blend := blend_time, custom_speed := 1.0):
	if _current == name or not _anim.has_animation(name):
		return
	_anim.play(name, blend, custom_speed)
	_current = name

func _idle_for_state() -> String:
	if sword_state == SwordState.DRAWN and drawn_idle_anim != "" and _anim.has_animation(drawn_idle_anim):
		return drawn_idle_anim
	return idle_anim

# ---------------------------------------------------------------------------
# 移動 / 基本動畫
# ---------------------------------------------------------------------------
func _physics_process(delta):
	var input_dir := _read_input_dir()
	var grounded := is_on_floor()
	var cur_speed := run_speed if Input.is_key_pressed(KEY_SHIFT) else speed
	var sword_busy := sword_state == SwordState.DRAWING or sword_state == SwordState.SHEATHING
	var movement_allowed := (action_state == ActionState.FREE or action_state == ActionState.JUMPING) \
		and not sword_busy and (sword_state != SwordState.DRAWN or can_move_when_drawn)
	if action_state == ActionState.DODGING:
		_update_roll_movement(delta)
	elif not grounded:
		# 空中一律走慣性模型（跳躍、下落、空中攻擊都相同），不直接覆寫水平速度。
		_apply_air_control(input_dir, cur_speed, delta)
	elif action_state == ActionState.ATTACKING:
		# 地面攻擊：保留玩家移動，但乘上 attack_move_factor。
		velocity.x = input_dir.x * cur_speed * attack_move_factor
		velocity.z = input_dir.z * cur_speed * attack_move_factor
	elif movement_allowed:
		velocity.x = input_dir.x * cur_speed
		velocity.z = input_dir.z * cur_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	if not grounded:
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# 起跳必須排在落地歸零之後，否則同一幀的 velocity.y 會被清掉。
	if action_state == ActionState.JUMPING:
		_update_jump(delta)

	move_and_slide()
	if action_state == ActionState.DODGING and _action_elapsed >= _roll_duration:
		_finish_action()
	elif action_state == ActionState.JUMPING and _jump_anim_done and is_on_floor():
		_finish_action()

	var moving := input_dir.length_squared() > 0.0
	if moving and movement_allowed and _visual:
		# 模型正面朝 +Z，所以朝 input_dir 的 yaw = atan2(x, z)
		var target_yaw := atan2(input_dir.x, input_dir.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))

	if _anim == null:
		return
	if action_state == ActionState.ATTACKING:
		_update_attack(delta, input_dir)
	elif sword_state == SwordState.DRAWING or sword_state == SwordState.SHEATHING:
		_update_drawing()
	elif action_state == ActionState.DODGING or action_state == ActionState.JUMPING:
		pass
	else:
		var running := moving and Input.is_key_pressed(KEY_SHIFT)
		var selected_run := run_fast_anim if run_fast_anim != "" and _anim.has_animation(run_fast_anim) else run_anim
		_play(selected_run if running else (walk_anim if moving else _idle_for_state()), _locomotion_blend())

func _apply_air_control(input_dir: Vector3, cur_speed: float, delta: float) -> void:
	var h := Vector2(velocity.x, velocity.z)
	if input_dir.is_zero_approx():
		h = h.move_toward(Vector2.ZERO, air_drag * delta)
	else:
		var desired := Vector2(input_dir.x, input_dir.z) * cur_speed
		h = h.move_toward(desired, air_acceleration * air_control * delta)
	velocity.x = h.x
	velocity.z = h.y

func _locomotion_blend() -> float:
	if _recovery_blend_pending:
		_recovery_blend_pending = false
		return attack_recovery_blend
	return blend_time

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

func _update_roll_movement(delta: float) -> void:
	var previous_t := clampf(_action_elapsed / _roll_duration, 0.0, 1.0) if _roll_duration > 0.0 else 1.0
	_action_elapsed = minf(_action_elapsed + delta, _roll_duration)
	var current_t := clampf(_action_elapsed / _roll_duration, 0.0, 1.0) if _roll_duration > 0.0 else 1.0
	# Ease-out displacement curve: p(t) = 1 - (1 - t)^2. The per-frame delta
	# moves CharacterBody3D itself, so its CollisionShape3D always follows.
	var previous_curve := 1.0 - pow(1.0 - previous_t, 2.0)
	var current_curve := 1.0 - pow(1.0 - current_t, 2.0)
	var frame_distance := roll_distance * (current_curve - previous_curve)
	var roll_velocity := _dodge_dir * (frame_distance / delta) if delta > 0.0 else Vector3.ZERO
	velocity.x = roll_velocity.x
	velocity.z = roll_velocity.z

# ---------------------------------------------------------------------------
# 拔刀狀態機
# ---------------------------------------------------------------------------
# 正式戰鬥輸入：左鍵 = 主 Combo、右鍵 = Spin 重攻擊。鍵盤攻擊鍵（J/K/L）已全部移除。
# Space = 跳躍；Shift 按住 = 疾跑、快按（<= shift_tap_time 放開）= 翻滾；Q = 拔刀/收刀 toggle。
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

## Q toggle：SHEATHED → DRAWING → DRAWN；DRAWN → SHEATHING → SHEATHED。
## ATTACKING 中按 Q 不打斷攻擊，改記 pending_sheathe，攻擊播完自動收刀。
func request_sword_toggle():
	match sword_state:
		SwordState.SHEATHED:
			request_draw()
		SwordState.DRAWN:
			if action_state == ActionState.ATTACKING:
				pending_sheathe = true
			elif action_state == ActionState.FREE:
				_start_sheathe()

func request_draw():
	if sword_state != SwordState.SHEATHED or action_state != ActionState.FREE:
		return
	if draw_anim == "" or not _anim.has_animation(draw_anim):
		push_warning("yoriichi_character: no draw animation assigned (draw_anim / draw_source); staying SHEATHED")
		return
	_draw_len = _anim.get_animation(draw_anim).length
	_draw_t = 0.0
	sword_state = SwordState.DRAWING
	_apply_sword_visibility()          # 起點：刀仍在左腰
	_play(draw_anim, blend_time)

## 收刀 = Draw_Sword 反向播放（不新增動畫資源）。visibility 依實際播放位置
## （_draw_t 對 t_unsheathe）判斷，反向跨過 0.65 時刀自動回鞘，無需另換算。
func _start_sheathe() -> void:
	if draw_anim == "" or not _anim.has_animation(draw_anim):
		sword_state = SwordState.SHEATHED
		_apply_sword_visibility()
		return
	_draw_len = _anim.get_animation(draw_anim).length
	_draw_t = 1.0
	sword_state = SwordState.SHEATHING
	_apply_sword_visibility()          # 起點：刀在右手
	_anim.play_backwards(draw_anim, blend_time)
	_current = draw_anim

func _update_drawing():
	if _anim.current_animation == _current and _draw_len > 0.0:
		_draw_t = clamp(_anim.current_animation_position / _draw_len, 0.0, 1.0)
	_apply_sword_visibility()

func _on_animation_finished(anim_name: StringName):
	if sword_state == SwordState.DRAWING and String(anim_name) == draw_anim:
		_draw_t = 1.0
		_finish_draw()
	elif sword_state == SwordState.SHEATHING and String(anim_name) == draw_anim:
		_draw_t = 0.0
		sword_state = SwordState.SHEATHED
		_apply_sword_visibility()
		_current = ""                  # 下一個 physics tick 依輸入回 Idle/Walk/Run
	elif action_state == ActionState.DODGING and String(anim_name) == roll_anim:
		return # CharacterBody3D completes the final roll displacement in physics.
	elif action_state == ActionState.JUMPING and String(anim_name) == jump_anim:
		_jump_anim_done = true # 落地判定在 physics（可能仍在空中，例如跳下平台）。
	elif action_state == ActionState.ATTACKING and String(anim_name) == _action_anim:
		if combo_stage > 0 and _combo_queued_inputs > 0 and combo_stage < COMBO_SECTION_RANGES.size():
			_advance_combo()
		else:
			_finish_action()

func _finish_draw():
	sword_state = SwordState.DRAWN
	_apply_sword_visibility()
	_current = ""                      # 強制重新 blend 到 (combat) idle
	_play(_idle_for_state())

func request_primary_attack() -> void:
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
	if attack_combo_anim == "" or not _anim.has_animation(attack_combo_anim):
		push_warning("yoriichi_character: primary attack animation is unavailable")
		return
	action_state = ActionState.ATTACKING
	_action_anim = attack_combo_anim
	_action_elapsed = 0.0
	combo_stage = 1
	_combo_queued_inputs = 0
	combo_input_buffered = false
	_combo_buffer_remaining = 0.0
	_play_combo_section(combo_stage)

func request_attack(animation_name: String) -> void:
	# Public compatibility entrypoint: Attack_Combo uses the buffered primary
	# chain; all other Attack animations use the shared 5x special-attack path.
	if animation_name == attack_combo_anim:
		request_primary_attack()
	else:
		request_special_attack(animation_name)

func request_special_attack(animation_name: String) -> void:
	if sword_state != SwordState.DRAWN:
		return
	if action_state != ActionState.FREE and action_state != ActionState.JUMPING:
		return
	if animation_name == "" or not _anim.has_animation(animation_name):
		push_warning("yoriichi_character: attack animation is unavailable: " + animation_name)
		return
	action_state = ActionState.ATTACKING
	_action_anim = animation_name
	_action_elapsed = 0.0
	combo_stage = 0
	_combo_queued_inputs = 0
	combo_input_buffered = false
	_play(animation_name, combo_section_blend, attack_speed_scale)

func _play_combo_section(stage: int) -> void:
	var animation := _anim.get_animation(attack_combo_anim)
	var range := COMBO_SECTION_RANGES[stage - 1]
	_combo_section_start = animation.length * range.x
	_combo_section_end = animation.length * range.y
	_anim.play_section(attack_combo_anim, _combo_section_start, _combo_section_end, combo_section_blend, attack_speed_scale)
	_current = attack_combo_anim

func _update_attack(delta: float, input_dir: Vector3) -> void:
	_action_elapsed += delta
	if not input_dir.is_zero_approx() and _visual:
		var target_yaw := atan2(input_dir.x, input_dir.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clampf(turn_speed * attack_turn_control * delta, 0.0, 1.0))
	if combo_stage <= 0:
		return
	if _combo_queued_inputs > 0:
		_combo_buffer_remaining = maxf(_combo_buffer_remaining - delta, 0.0)
		if _combo_buffer_remaining <= 0.0:
			_combo_queued_inputs = 0
			combo_input_buffered = false
	var section_length := _combo_section_end - _combo_section_start
	var progress := clampf((_anim.current_animation_position - _combo_section_start) / section_length, 0.0, 1.0) if section_length > 0.0 else 1.0
	if _combo_queued_inputs > 0 and progress >= combo_cancel_start and progress <= combo_cancel_end and combo_stage < COMBO_SECTION_RANGES.size():
		_advance_combo()
	elif progress >= 0.995:
		if _combo_queued_inputs > 0 and combo_stage < COMBO_SECTION_RANGES.size():
			_advance_combo()
		else:
			_finish_action()

func _advance_combo() -> void:
	_combo_queued_inputs = maxi(_combo_queued_inputs - 1, 0)
	combo_input_buffered = _combo_queued_inputs > 0
	_combo_buffer_remaining = combo_input_buffer_time if combo_input_buffered else 0.0
	combo_stage += 1
	_play_combo_section(combo_stage)

func request_dodge(direction_override: Vector3 = Vector3.ZERO) -> void:
	if sword_state == SwordState.DRAWING or sword_state == SwordState.SHEATHING:
		return
	if action_state != ActionState.FREE or not is_on_floor():
		return
	if roll_anim == "" or not _anim.has_animation(roll_anim):
		push_warning("yoriichi_character: dodge animation is unavailable")
		return
	var horizontal_override := Vector3(direction_override.x, 0.0, direction_override.z)
	_dodge_dir = horizontal_override.normalized() if not horizontal_override.is_zero_approx() else _read_input_dir()
	if _dodge_dir.is_zero_approx():
		var yaw := _visual.rotation.y if _visual else rotation.y
		_dodge_dir = Vector3(sin(yaw), 0.0, cos(yaw)).normalized()
	elif _visual:
		_visual.rotation.y = atan2(_dodge_dir.x, _dodge_dir.z)
	action_state = ActionState.DODGING
	_action_anim = roll_anim
	_action_elapsed = 0.0
	# 3x 播放：實際位移 duration 與動畫同步縮短，CharacterBody3D 曲線用同一個 _roll_duration。
	_roll_duration = _anim.get_animation(roll_anim).length / roll_animation_speed
	_play(roll_anim, action_blend_time, roll_animation_speed)

## Space：跳躍。前 0.533 s 是蹲伏預備（仍在地面），之後由物理起跳；
## 動畫垂直弧線已 clamp 到 rest 高度，上升完全由 CharacterBody3D 提供。
func request_jump() -> void:
	if sword_state == SwordState.DRAWING or sword_state == SwordState.SHEATHING:
		return
	if action_state != ActionState.FREE or not is_on_floor():
		return
	if jump_anim == "" or not _anim.has_animation(jump_anim):
		push_warning("yoriichi_character: jump animation is unavailable")
		return
	action_state = ActionState.JUMPING
	_action_anim = jump_anim
	_action_elapsed = 0.0
	_jump_launched = false
	_jump_anim_done = false
	_play(jump_anim, action_blend_time)

func _update_jump(delta: float) -> void:
	_action_elapsed += delta
	if not _jump_launched and _action_elapsed >= jump_takeoff_time:
		_jump_launched = true
		velocity.y = jump_velocity

func _finish_action() -> void:
	var was_attack := action_state == ActionState.ATTACKING
	action_state = ActionState.FREE
	_action_anim = ""
	_action_elapsed = 0.0
	_roll_duration = 0.0
	_jump_launched = false
	_jump_anim_done = false
	combo_stage = 0
	_combo_queued_inputs = 0
	combo_input_buffered = false
	_combo_buffer_remaining = 0.0
	_current = ""
	if pending_sheathe and sword_state == SwordState.DRAWN and is_on_floor():
		pending_sheathe = false
		_start_sheathe()
		return
	if not is_on_floor():
		_enter_airborne_recovery()
		return
	# 不強制回 Idle：下一個 physics tick 的 locomotion 分支依當前輸入
	# 接回 Idle / Walk / Run；攻擊後用較短的 recovery blend。
	_recovery_blend_pending = was_attack

## 空中攻擊結束後回到 airborne：blend 回 Jump clip 的下落姿勢，
## 慣性與 gravity 照常，落地時經由 JUMPING 的落地判定收尾。
func _enter_airborne_recovery() -> void:
	action_state = ActionState.JUMPING
	_action_anim = jump_anim
	_jump_launched = true
	_jump_anim_done = true
	if _anim.has_animation(jump_anim):
		_anim.play(jump_anim, 0.08)
		_anim.seek(jump_air_pose_time, true)
		_current = jump_anim

## 依狀態（與拔刀進度）決定哪一把刀可見。永遠恰好一把可見。
func _apply_sword_visibility():
	var in_hand := false
	match sword_state:
		SwordState.SHEATHED:
			in_hand = false
		SwordState.DRAWING:
			in_hand = _draw_t >= t_unsheathe
		SwordState.SHEATHING:
			# 反向播放共用同一個位置判斷：位置跌破 t_unsheathe 時刀回鞘。
			in_hand = _draw_t >= t_unsheathe
		SwordState.DRAWN:
			in_hand = true
	if _sword_sheathed:
		_sword_sheathed.visible = not in_hand
	if _sword_hand:
		_sword_hand.visible = in_hand
