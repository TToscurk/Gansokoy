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
		pivot.rotation = Vector3(_current_pitch, _current_yaw, 0.0)

	# 3. Smooth zoom
	if arm != null:
		_current_distance = lerpf(_current_distance, _target_distance, 1.0 - exp(-zoom_smoothing * delta))
		arm.spring_length = _current_distance


func _unhandled_input(event: InputEvent) -> void:
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
