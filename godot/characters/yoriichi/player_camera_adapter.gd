extends Node
## Main-game adapter for the Yoriichi controller: owns the third-person camera
## (mouse-look + SpringArm + scroll zoom) and the interaction ray, and relays
## the two signals main.gd subscribes to. yoriichi_character.gd knows nothing
## about this node; it only reads `input_yaw_node`, which player_yoriichi.tscn
## points at our Pivot so WASD is camera-relative.
##
## Split out from scenes/player.gd so the combat controller stays byte-for-byte
## the one validated in 角色/緣一動作 — no gameplay logic lives here.

signal interaction_prompt_changed(text: String)
signal interaction_message(text: String)

@export var mouse_sensitivity := 0.0028
@export var pitch_min := -1.2
@export var pitch_max := 0.7
@export var zoom_min := 1.6
@export var zoom_max := 14.0
@export var zoom_step := 0.6

@export var pivot: Node3D
@export var arm: SpringArm3D
@export var interaction_ray: RayCast3D

var _interaction_target: Node = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The character body must not block its own camera arm.
	var body := get_parent() as CollisionObject3D
	if body != null and arm != null:
		arm.add_excluded_object(body.get_rid())
	# Relay to the root so main.gd's `player.<signal>.connect` keeps working.
	if body != null and body.has_signal("interaction_prompt_changed"):
		interaction_prompt_changed.connect(func(t: String) -> void: body.emit_signal("interaction_prompt_changed", t))
		interaction_message.connect(func(t: String) -> void: body.emit_signal("interaction_message", t))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_interact()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		pivot.rotation.x = clampf(pivot.rotation.x - event.relative.y * mouse_sensitivity, pitch_min, pitch_max)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			arm.spring_length = clampf(arm.spring_length - zoom_step, zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			arm.spring_length = clampf(arm.spring_length + zoom_step, zoom_min, zoom_max)
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
