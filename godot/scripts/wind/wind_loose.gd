extends Node3D
## Wind V1.1 類別 C／D：地面鬆動小物（落葉、紙屑、空籃、淺盤）。
##
## 不是 RigidBody3D：這一類只需要「靜摩擦門檻 → 慢慢加速 → 地面摩擦 → 邊界內停住」，
## 用積分＋射線接地就夠，而且可以精確控制天花板（max_radius），不會把道具推去擋路。
## 質量、迎風面積、摩擦、阻尼都是每個節點自己的參數 → 同一陣風下反應不同。
##
## 重要：根部（root）位置只會被速度推動；沒有「計時到就瞬移」的邏輯。
## 葉片的抖動畫在子節點上（tremble），所以還沒超過靜摩擦前，物件不會漂移。

enum Kind { LEAF, BASKET }

@export var kind: Kind = Kind.LEAF
@export var mass_kg := 0.004
@export var area_m2 := 0.006
## 靜摩擦係數：風壓/重量 超過這個值才開始動。
@export var mu_static := 0.22
@export var mu_kinetic := 0.14
## 空氣阻尼（1/s）。
@export var drag := 2.4
## 離原點的最大水平距離（m）。超過就貼在邊界上、把外向速度吃掉。
@export var max_radius := 1.4
@export var wind_gain := 1.0
@export var tumble := true
@export var ground_offset := 0.008
## 葉片被陣風抬起的最大高度（m）。籃子＝0。
@export var lift_max := 0.35

const G := 9.8
const RHO := 1.2

var _vel := Vector3.ZERO
var _origin := Vector3.ZERO
var _ground_y := 0.0
var _ray_t := 0.0
var _moving := false
var _phase := 0.0
var _spin := Vector3.ZERO
var _t := 0.0
var _visual: Node3D = null
var _tremble := 0.0


func _ready() -> void:
	_origin = global_position
	_ground_y = global_position.y - ground_offset
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	_phase = rng.randf() * TAU
	wind_gain *= 0.85 + 0.3 * rng.randf()
	mu_static *= 0.85 + 0.3 * rng.randf()
	for c in get_children():
		if c is Node3D:
			_visual = c as Node3D
			break
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	_t += delta
	var f: Dictionary = Wind.sample_field(global_position)
	var speed := float(f["speed"]) * wind_gain
	var ang := float(f["angle"])
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	# 風壓（N）→ 加速度（m/s²）
	var q := 0.5 * RHO * speed * speed * area_m2
	var drive := q / maxf(mass_kg, 0.001)
	var need := mu_static * G
	if not _moving and drive < need:
		# 靜止：只讓子節點抖一下（不移動 root）
		_tremble = clampf(drive / maxf(need, 0.001), 0.0, 1.0)
		if _visual != null:
			_visual.position = dir * 0.004 * _tremble * sin(_t * 37.0 + _phase)
		return
	_tremble = 0.0
	if _visual != null and _visual.position != Vector3.ZERO:
		_visual.position = Vector3.ZERO
	_moving = true
	_vel += dir * drive * delta
	# 動摩擦（地面）
	var sp := _vel.length()
	if sp > 0.0:
		var dec := mu_kinetic * G * delta
		_vel -= _vel / sp * minf(dec, sp)
	_vel *= exp(-drag * delta)
	# 停下門檻：速度 <1 cm/s 且風壓不足以再推動 → 真的停住（避免永遠漂 1 mm）
	if _vel.length() < 0.01 and drive < need:
		_vel = Vector3.ZERO
		_moving = false
	# 葉片：強陣風時短暫離地
	if kind == Kind.LEAF and lift_max > 0.0 and speed > 4.0 and _is_grounded():
		_vel.y = minf(1.0, (speed - 4.0) * 0.16)
	if not _is_grounded():
		_vel.y -= G * delta
	_vel.x = clampf(_vel.x, -5.0, 5.0)
	_vel.z = clampf(_vel.z, -5.0, 5.0)
	var np := global_position + _vel * delta
	# 接地
	_ray_t -= delta
	if _ray_t <= 0.0:
		_ray_t = 0.12
		var gy := _ray_ground(np)
		if gy > -INF:
			_ground_y = gy
	if np.y <= _ground_y + ground_offset:
		np.y = _ground_y + ground_offset
		_vel.y = 0.0
	# 邊界（不瞬移：貼在圈上、吃掉外向速度）
	var d := Vector2(np.x - _origin.x, np.z - _origin.z)
	if d.length() > max_radius:
		var n := d.normalized()
		np.x = _origin.x + n.x * max_radius
		np.z = _origin.z + n.y * max_radius
		var outward := _vel.x * n.x + _vel.z * n.y
		if outward > 0.0:
			_vel.x -= n.x * outward
			_vel.z -= n.y * outward
	global_position = np
	# 翻滾：速度越快轉越快；籃子只微微傾斜
	if tumble and _visual != null:
		var spin_rate := minf(_vel.length() * 2.0, 12.0)
		_spin = Vector3(sin(_phase + _t * 2.3), 0.7, cos(_phase + _t * 1.9)) * spin_rate * delta
		if kind == Kind.LEAF:
			_visual.rotate_object_local(Vector3.RIGHT, _spin.x)
			_visual.rotate_object_local(Vector3.FORWARD, _spin.z)
		else:
			_visual.rotation.x = clampf(_visual.rotation.x + _spin.x * 0.15, -0.12, 0.12)
			_visual.rotation.z = clampf(_visual.rotation.z + _spin.z * 0.15, -0.12, 0.12)


func _is_grounded() -> bool:
	return global_position.y <= _ground_y + ground_offset + 0.02


func _ray_ground(at: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.0, 0), at + Vector3(0, -3.0, 0))
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return -INF
	return float((hit["position"] as Vector3).y)


## 測試／除錯
func is_moving() -> bool:
	return _moving


func speed() -> float:
	return _vel.length()


func displacement() -> float:
	return Vector2(global_position.x - _origin.x, global_position.z - _origin.z).length()


func origin() -> Vector3:
	return _origin


func reset_to_origin() -> void:
	global_position = _origin
	_vel = Vector3.ZERO
	_moving = false
