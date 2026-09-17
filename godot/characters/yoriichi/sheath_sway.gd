extends Node3D
## 刀鞘擺動：鞘不是焊死在腰上的棍子，而是掛在帶上的重物。
##
## 做法：記住掛點（SheathSocket）上一幀的世界位置／朝向，算出這一幀的
## 線加速度與轉速，轉成鞘在「掛點空間」的兩軸傾角，再用彈簧－阻尼逼近。
## 完全不用物理引擎，不會有 tunneling，也不影響拔刀時的 socket 對齊
## （Sword_Sheathed 收在鞘裡，所以它套用同一組偏移）。

## 鞘尾甩動幅度。0 = 完全剛性（回到焊死的樣子）。
@export_range(0.0, 3.0) var sway_gain := 1.0
## 彈簧剛性：越大越快回正、擺動越快。
@export_range(1.0, 60.0) var stiffness := 22.0
## 阻尼比。1.0 = 臨界阻尼不回彈；0.5 左右會有一兩下餘擺。
@export_range(0.05, 1.5) var damping_ratio := 0.55
## 單軸最大傾角（度），避免衝刺急停時鞘甩到穿過身體。
@export_range(1.0, 30.0) var max_angle_deg := 11.0
## 走路時的被動微擺幅度（度），站定時自然衰減到 0。
@export_range(0.0, 6.0) var stride_wobble_deg := 1.6
## 跟著鞘一起擺的節點（收在鞘裡的刀）。
@export var followers: Array[NodePath] = []

var _rest: Transform3D
var _prev_pos: Vector3
var _prev_basis: Basis
var _prev_vel: Vector3
var _has_prev := false
# 兩個自由度：繞掛點的前後擺與左右擺（弧度）
var _ang := Vector2.ZERO
var _vel := Vector2.ZERO
var _phase := 0.0
var _follow: Array[Node3D] = []


func _ready() -> void:
	_rest = transform
	for np in followers:
		var n := get_node_or_null(np)
		if n is Node3D:
			_follow.append(n)
			(n as Node3D).set_meta("sheath_rest", (n as Node3D).transform)
	set_process(true)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var parent := get_parent_node_3d()
	if parent == null:
		return

	var gx := parent.global_transform
	var pos := gx.origin
	var bas := gx.basis.orthonormalized()

	if not _has_prev:
		_prev_pos = pos
		_prev_basis = bas
		_prev_vel = Vector3.ZERO
		_has_prev = true
		return

	var vel := (pos - _prev_pos) / delta
	var acc := (vel - _prev_vel) / delta
	_prev_pos = pos
	_prev_vel = vel

	# 掛點自轉速度（繞世界 Y），轉身時鞘會落後
	var f_now := bas * Vector3.FORWARD
	var f_old := _prev_basis * Vector3.FORWARD
	var yaw_rate := atan2(
		Vector3.UP.dot(f_old.cross(f_now)),
		f_old.dot(f_now)) / delta
	_prev_basis = bas

	# 加速度在掛點空間分解 → 慣性讓鞘往反方向甩
	var local_acc := bas.inverse() * acc
	var drive := Vector2(
		clampf(-local_acc.z * 0.010, -0.5, 0.5),
		clampf(local_acc.x * 0.010, -0.5, 0.5))
	drive.y += clampf(-yaw_rate * 0.055, -0.4, 0.4)

	# 走動時的被動小擺：用水平速度推相位，停下就衰減
	var speed := Vector2(vel.x, vel.z).length()
	_phase += delta * (4.0 + speed * 2.2)
	var wob := deg_to_rad(stride_wobble_deg) * minf(speed / 3.0, 1.0)
	drive.x += sin(_phase) * wob
	drive.y += cos(_phase * 0.5) * wob * 0.5

	# 彈簧－阻尼往 drive 收斂
	var k := stiffness * stiffness
	var c := 2.0 * damping_ratio * stiffness
	var target := drive * sway_gain
	_vel += (target - _ang) * k * delta - _vel * c * delta
	_ang += _vel * delta
	var lim := deg_to_rad(max_angle_deg)
	_ang.x = clampf(_ang.x, -lim, lim)
	_ang.y = clampf(_ang.y, -lim, lim)

	# 繞鞘口（local 原點）旋轉，所以鞘口貼著腰不動，只有鞘尾甩
	var off := Basis(Vector3.RIGHT, _ang.x) * Basis(Vector3.FORWARD, _ang.y)
	var local_off := _rest.basis.inverse() * off * _rest.basis
	transform = Transform3D(_rest.basis * local_off, _rest.origin)
	for n in _follow:
		var r: Transform3D = n.get_meta("sheath_rest")
		n.transform = Transform3D(r.basis * (r.basis.inverse() * local_off * r.basis), r.origin)
