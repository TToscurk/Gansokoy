extends Node
## Third-person camera controller with smooth position tracking, rotation damping,
## natural over-the-shoulder framing, and smooth zoom.

signal interaction_prompt_changed(text: String)
signal interaction_message(text: String)

@export_group("Distance & Zoom")
@export var default_distance := 8.5
@export var zoom_min := 3.0
@export var zoom_max := 16.0
@export var zoom_step := 0.75
@export var zoom_smoothing := 14.0

@export_group("Control & Feel")
@export var mouse_sensitivity := 0.0028
@export var pitch_min := -1.1       # ~63° looking down
@export var pitch_max := 0.55       # ~31° looking up (prevents floor clipping)
@export var rotation_smoothing := 26.0
@export var follow_speed := 20.0
@export var pivot_height := 1.70
@export var camera_shoulder_offset := Vector3(0.40, 0.10, 0.0)

@export_group("Nodes")
@export var pivot: Node3D
@export var arm: SpringArm3D
@export var interaction_ray: RayCast3D

var _body: CollisionObject3D = null
var _camera: Camera3D = null
var _interaction_target: Node = null

var _target_distance := 8.5
var _current_distance := 8.5
var _target_yaw := 0.0
var _target_pitch := -0.18          # Start with gentle 10° downward angle
var _current_yaw := 0.0
var _current_pitch := -0.18

## P11 R2：下り坂の俯仰バイアスと腕の伸び戻り（_process 2・3 参照）。
## 足元中心の真下の面の傾き α ≥ SLOPE_MIN_DEG の下り坂を SLOPE_MIN_TIME 秒以上移動中は、実効 pitch を −atan(tan α − SLOPE_LINE_K)
## （30° の參道で ≈ −0.43、下限 SLOPE_PITCH_MAX）まで「加算の偏り」で下げる＝頭→相機の線が背後の斜面より上を通る俯角。
## 坂を降りきっても移動中は SLOPE_HOLD 秒保持し、その後・停止・上り坂では SLOPE_EASE で 0 へ戻る。使用者の _target_pitch（マウス）は変えない。
## 腕：縮む（壁・屋根・坂に当たる）時は SpringArm3D のまま即時（相機碰撞は止めない）、伸び戻る時だけ ARM_EXTEND m/s。
const SLOPE_MIN_DEG := 18.0
const SLOPE_LINE_K := 0.12       # tan β = tan α − K（K ≈ 頭の高さ／腕の長さ − 余裕）
const SLOPE_PITCH_MAX := -0.6    # rad
const SLOPE_HOLD := 1.0          # s
const SLOPE_MIN_TIME := 0.3      # s（この時間続いた下り坂だけ）
const SLOPE_EASE := 0.9          # rad/s
const ARM_EXTEND := 6.0          # m/s

var _slope_bias := 0.0
var _slope_pitch := 0.0          # 直近の下り坂で要った実効 pitch（0＝なし）
var _slope_hold := 0.0
var _slope_time := 0.0
var _arm_eff := -1.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_body = get_parent() as CollisionObject3D

	if arm != null:
		arm.margin = 0.2
		arm.spring_length = default_distance
		_target_distance = default_distance
		_current_distance = default_distance
		for c in arm.get_children():
			if c is Camera3D:
				_camera = c
				_camera.position = camera_shoulder_offset
				break

	if pivot != null:
		pivot.top_level = true
		if _body != null:
			pivot.global_position = _body.global_position + Vector3(0.0, pivot_height, 0.0)
		_target_yaw = pivot.rotation.y
		_current_yaw = _target_yaw
		_current_pitch = _target_pitch
		pivot.rotation = Vector3(_current_pitch, _current_yaw, 0.0)

	# Exclude character body from camera collision
	if _body != null and arm != null:
		arm.add_excluded_object(_body.get_rid())

	# Relay interaction signals
	if _body != null and _body.has_signal("interaction_prompt_changed"):
		interaction_prompt_changed.connect(func(t: String) -> void: _body.emit_signal("interaction_prompt_changed", t))
		interaction_message.connect(func(t: String) -> void: _body.emit_signal("interaction_message", t))


## Snap camera yaw (e.g. on map spawn or portal arrival)
func snap_yaw(yaw: float) -> void:
	_target_yaw = yaw
	_current_yaw = yaw
	if pivot != null:
		pivot.rotation = Vector3(_current_pitch, _current_yaw, 0.0)


## Kept for signal/interface compatibility (no-op; screen shake removed per user request)
func add_trauma(_amount: float) -> void:
	pass


func _process(delta: float) -> void:
	# 1. Smooth position tracking (absorbs physics bumps, step-ups, and jump vertical spikes)
	if pivot != null and _body != null:
		var target_pos: Vector3 = _body.global_position + Vector3(0.0, pivot_height, 0.0)
		if pivot.global_position.distance_squared_to(target_pos) > 64.0:
			pivot.global_position = target_pos # Instant snap on teleport / map spawn
		else:
			pivot.global_position = pivot.global_position.lerp(target_pos, 1.0 - exp(-follow_speed * delta))

	# 2. Smooth rotation (damped mouse look, zero micro-stutter)
	if pivot != null:
		var rot_factor := 1.0 - exp(-rotation_smoothing * delta)
		_current_yaw = lerp_angle(_current_yaw, _target_yaw, rot_factor)
		_current_pitch = lerpf(_current_pitch, _target_pitch, rot_factor)
		_slope_bias = move_toward(_slope_bias, _slope_bias_target(delta), SLOPE_EASE * delta)
		pivot.rotation = Vector3(clampf(_current_pitch + _slope_bias, pitch_min, pitch_max), _current_yaw, 0.0)

	# 3. Smooth zoom
	if arm != null:
		_current_distance = lerpf(_current_distance, _target_distance, 1.0 - exp(-zoom_smoothing * delta))
		# 縮むのは即時、伸びるのはなめらかに（窄巷で建物を抜けた瞬間に 4–6 m 跳ね返らない）
		var hit := arm.get_hit_length()
		if _arm_eff < 0.0:
			_arm_eff = _current_distance
		if hit < _arm_eff - 0.01:
			_arm_eff = hit
		else:
			_arm_eff = move_toward(_arm_eff, _current_distance, ARM_EXTEND * delta)
		arm.spring_length = minf(_current_distance, _arm_eff + 0.05)


## P11 R2：下り坂バイアスの目標（0 か負）。
func _slope_bias_target(delta: float) -> float:
	var b := _body as CharacterBody3D
	if b == null:
		return 0.0
	var hv := Vector2(b.velocity.x, b.velocity.z)
	var moving := hv.length() > 0.5
	var want := 0.0
	if b.is_on_floor() and moving:
		# 坂の判定は足元中心の真下の面の法線（縁・壁際の接触法線では反応しない）
		var o := b.global_position
		var rq := PhysicsRayQueryParameters3D.create(o + Vector3(0, 0.3, 0), o - Vector3(0, 0.6, 0), b.collision_mask)
		rq.exclude = [b.get_rid()]
		var h := b.get_world_3d().direct_space_state.intersect_ray(rq)
		if not h.is_empty():
			var n: Vector3 = h["normal"]
			var a := n.angle_to(Vector3.UP)
			var down := Vector2(n.x, n.z)
			if rad_to_deg(a) >= SLOPE_MIN_DEG and down.length() > 0.01 and hv.normalized().dot(down.normalized()) > 0.5:
				want = maxf(-atan(maxf(0.0, tan(a) - SLOPE_LINE_K)), SLOPE_PITCH_MAX)
	# 一瞬の傾き（段の縁・踏石）では反応しない：SLOPE_MIN_TIME 秒続いた下り坂だけ
	_slope_time = _slope_time + delta if want < 0.0 else 0.0
	if want < 0.0 and _slope_time >= SLOPE_MIN_TIME:
		_slope_pitch = want
		_slope_hold = SLOPE_HOLD
	elif moving and _slope_hold > 0.0:
		_slope_hold -= delta
	else:
		_slope_hold = 0.0
		_slope_pitch = 0.0
	if _slope_pitch >= 0.0:
		return 0.0
	return minf(0.0, _slope_pitch - _current_pitch)


## P11 R2E：診断ツール（walk_p10_final.gd）が読む現在の下り坂バイアス（唯讀）
func slope_bias() -> float:
	return _slope_bias


func _unhandled_input(event: InputEvent) -> void:
	# 對話中：不轉視角、不互動（Esc 仍可放滑鼠）
	if _body != null and bool(_body.get("input_locked")) and not event.is_action_pressed("ui_cancel"):
		return
	if event.is_action_pressed("interact"):
		_interact()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_target_yaw -= event.relative.x * mouse_sensitivity
		_target_pitch = clampf(_target_pitch - event.relative.y * mouse_sensitivity, pitch_min, pitch_max)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = clampf(_target_distance - zoom_step, zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = clampf(_target_distance + zoom_step, zoom_min, zoom_max)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(_delta: float) -> void:
	_update_interaction_target()


func _update_interaction_target() -> void:
	var next_target: Node = null
	if interaction_ray != null and interaction_ray.is_colliding():
		next_target = _find_interactable(interaction_ray.get_collider() as Node)
	if next_target == _interaction_target:
		return
	_interaction_target = next_target
	var prompt := ""
	if _interaction_target != null:
		prompt = String(_interaction_target.get_interaction_prompt())
	interaction_prompt_changed.emit(prompt)


func _find_interactable(node: Node) -> Node:
	var candidate := node
	var body := get_parent()
	while candidate != null and candidate != body:
		if candidate.has_method("get_interaction_prompt") and candidate.has_method("interact"):
			return candidate
		candidate = candidate.get_parent()
	return null


func _interact() -> void:
	if _interaction_target == null or not is_instance_valid(_interaction_target):
		return
	var response: Variant = _interaction_target.interact()
	if response != null and not String(response).is_empty():
		interaction_message.emit(String(response))
