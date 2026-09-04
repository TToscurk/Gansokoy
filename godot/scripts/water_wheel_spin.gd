@tool
extends Node3D
## Spins a water wheel about its axle, in-editor and at runtime.
##
## Axis is MEASURED, not assumed: probe_waterwheel.gd found 水車.glb spans
## 1.00 x 1.00 x 0.331 — the wheel face is XY and the axle is the thin Z axis,
## with the geometry centred on the node origin so the node itself can be the
## pivot. Rotating about the wrong axis makes the wheel tumble like a flipped
## coin, which is the usual failure here.
##
## @tool so the wheel turns in the editor viewport too — a water wheel that only
## moves at runtime cannot be judged during art review.
##
## Attach to the 水車 instance node (the one carrying the scene transform), not
## to its inner mesh_node: the outer node holds the scaling and placement, and
## spinning the inner node would fight that transform.

## Degrees per second. A village wheel of ~5.5 m diameter driven by a canal
## turns slowly — roughly 4-6 rpm, i.e. 24-36 deg/s. Higher reads as a fairground
## ride, not a working mill.
@export_range(0.0, 180.0, 0.5) var 每秒轉度: float = 28.0

## Local axis to spin around. Z is correct for 水車.glb / 水車(窄).glb; exposed
## so a differently-authored wheel can be corrected without editing code.
@export_enum("X", "Y", "Z") var 轉軸: int = 2

## Reverse for a wheel on the opposite bank, where the water hits the far side.
@export var 反向: bool = false

## Editor preview can be switched off while positioning the wheel — a moving
## gizmo is hard to align against.
@export var 編輯器中預覽: bool = true

var _axis_vec := Vector3.BACK


func _ready() -> void:
	_update_axis()
	set_process(true)


func _update_axis() -> void:
	match 轉軸:
		0:
			_axis_vec = Vector3.RIGHT
		1:
			_axis_vec = Vector3.UP
		_:
			_axis_vec = Vector3.BACK


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not 編輯器中預覽:
		return
	if is_zero_approx(每秒轉度):
		return
	_update_axis()
	var dir := -1.0 if 反向 else 1.0
	# rotate_object_local keeps the spin on the wheel's own axle regardless of
	# how the instance is yawed into place in the scene.
	rotate_object_local(_axis_vec, deg_to_rad(每秒轉度) * delta * dir)
