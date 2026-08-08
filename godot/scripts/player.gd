extends CharacterBody3D
## 第三人稱控制器 —— 對齊 web 版的操作：WASD/方向鍵移動、滑鼠轉視角、
## Shift 衝刺、Space 跳、F 飛行、Ctrl 下降、滾輪縮放。
## 這是遷移骨架：手感參數之後在編輯器 Inspector 直接調。

@export var walk_speed := 6.0
@export var sprint_speed := 11.0
@export var fly_speed := 18.0
@export var jump_velocity := 8.0
@export var gravity := 22.0
@export var mouse_sensitivity := 0.0028

@onready var pivot: Node3D = $Pivot
@onready var arm: SpringArm3D = $Pivot/SpringArm3D

var flying := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		pivot.rotation.x = clampf(pivot.rotation.x, -1.2, 0.7)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			arm.spring_length = clampf(arm.spring_length - 0.6, 1.6, 14.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			arm.spring_length = clampf(arm.spring_length + 0.6, 1.6, 14.0)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("fly_toggle"):
		flying = not flying
		velocity.y = 0.0

func _physics_process(delta: float) -> void:
	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input_2d.x, 0.0, input_2d.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed

	if flying:
		var v := dir * fly_speed
		if Input.is_action_pressed("jump"):
			v.y += fly_speed
		if Input.is_action_pressed("descend"):
			v.y -= fly_speed
		velocity = v
	else:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		if is_on_floor():
			if Input.is_action_just_pressed("jump"):
				velocity.y = jump_velocity
		else:
			velocity.y -= gravity * delta

	move_and_slide()
	if flying and is_on_floor():
		flying = false
