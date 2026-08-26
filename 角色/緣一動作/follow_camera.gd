extends Camera3D
## 最簡第三人稱跟隨鏡頭：固定在目標後上方的世界偏移，始終看向目標胸口。
## 無滑鼠旋轉、無 SpringArm、無碰撞。

@export var target_path: NodePath
@export var offset := Vector3(0.0, 1.7, 3.5)      # 角色後上方（+Z 側），距離 3.5 m、高 1.7 m
@export var look_height := 1.3                     # 看向胸口
@export var follow_speed := 8.0                    # 位置平滑；0 = 立即

var _target: Node3D

func _ready():
	_target = get_node_or_null(target_path)
	if _target == null:
		push_warning("follow_camera: target_path not set")
		return
	global_position = _target.global_position + offset
	look_at(_target.global_position + Vector3(0, look_height, 0))

func _physics_process(delta):
	if _target == null:
		return
	var want := _target.global_position + offset
	if follow_speed > 0.0:
		global_position = global_position.lerp(want, clamp(follow_speed * delta, 0.0, 1.0))
	else:
		global_position = want
	look_at(_target.global_position + Vector3(0, look_height, 0))
