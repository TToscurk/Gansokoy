class_name Floatable
extends Node3D
## Wind V2 浮物元件（可重用）。掛在要漂的 Node3D 上；水面／水流／風全部取自 Wind（同一個水面場、風場）。
##
## 模型（輕量物理近似，不做流體力學）：
##   垂直：浮力彈簧 k＝ρ_w·g·A_wl（水線面積），阻尼 2ζ√(k·m)；目標＝水面高 − 吃水 draft。
##   水平：F＝½ρ_w·Cd_w·A_w·|u_w−v|(u_w−v)（水流拖曳）＋½ρ_a·Cd_a·A_a·|u_a−v|(u_a−v)（風拖曳，風 m/s＝Wind.sample_wind）。
##   姿態：俯仰／橫搖朝水面法線（一階彈簧＋阻尼，上限 max_tilt_deg）；偏航＝流場剪切＋風力矩，帶慣性與阻尼。
##   繫留：tether_length > 0 → 離錨點超過長度時沿徑向軟拉回（彈簧＋徑向速度阻尼），不瞬移。
## 安全：dt 分步積分（≤ 1/60）、速度上限、離開水域（mask < 0.2）時減速並推回最近水域方向；
##   recycle＝true 的臨時漂流物：漂出範圍或離錨點 recycle_distance 後「縮小淡出→回上游重生」（只在離相機 > 25 m 時重生）。
## visual_node：設了就只動該子節點（例如小舟的 Hull），本節點與碰撞體不動——保留作者擺位與碰撞。

@export_enum("leaf", "heavy", "custom") var preset := 2:
	set(v):
		preset = v
		_apply_preset()
@export var mass_kg := 1.0
@export var waterline_area_m2 := 0.05      # 水線面積（浮力剛度）
@export var water_drag_area_m2 := 0.02     # 水下迎流面積
@export var air_drag_area_m2 := 0.01       # 水上受風面積
@export var draft_m := 0.01                # 吃水
@export_range(0.05, 2.0) var heave_damping := 0.6   # ζ
@export_range(0.0, 45.0) var max_tilt_deg := 18.0
@export_range(0.5, 20.0) var tilt_stiffness := 6.0  # 1/s，越大越快貼合水面法線
@export var yaw_inertia := 1.0
@export var yaw_damping := 1.5
@export var tether_length := 0.0            # 0＝不繫留
@export var tether_anchor := Vector3.INF    # INF＝用起始位置
@export var visual_node: NodePath
@export var recycle := false
@export var recycle_distance := 60.0
@export var max_speed := 3.0

const RHO_W := 1000.0
const RHO_A := 1.2
const CD_W := 1.0
const CD_A := 1.1

var velocity := Vector3.ZERO
var heave_v := 0.0
var yaw := 0.0
var yaw_rate := 0.0
var tilt := Vector2.ZERO        # (pitch, roll) rad
var _spawn := Transform3D()
var _anchor := Vector3.ZERO
var _vis: Node3D
var _vis_base := Transform3D()
var _pos := Vector3.ZERO        # 模擬位置（visual 模式時與節點位置分開）
var _fade := 1.0
var _fading := false
var _rng := RandomNumberGenerator.new()
var _ok := false
var _calibrated := false


func _apply_preset() -> void:
	match preset:
		0:   # 落葉／薄木片：輕、受風大、偏航快
			mass_kg = 0.004
			waterline_area_m2 = 0.004
			water_drag_area_m2 = 0.0004
			air_drag_area_m2 = 0.003
			draft_m = 0.001
			heave_damping = 0.35
			tilt_stiffness = 14.0
			max_tilt_deg = 25.0
			yaw_inertia = 0.02
			yaw_damping = 0.6
			max_speed = 2.5
		1:   # 重物（桶／原木）：慣性大、慢、穩
			mass_kg = 18.0
			waterline_area_m2 = 0.16
			water_drag_area_m2 = 0.10
			air_drag_area_m2 = 0.06
			draft_m = 0.12
			heave_damping = 0.8
			tilt_stiffness = 2.5
			max_tilt_deg = 8.0
			yaw_inertia = 4.0
			yaw_damping = 3.0
			max_speed = 1.5


func _ready() -> void:
	_rng.seed = hash(get_path())
	_spawn = global_transform
	_anchor = tether_anchor if tether_anchor != Vector3.INF else global_position
	_pos = global_position
	yaw = global_rotation.y
	if not visual_node.is_empty():
		_vis = get_node_or_null(visual_node) as Node3D
		if _vis:
			_vis_base = _vis.transform


func reset_to_spawn() -> void:
	global_transform = _spawn
	_pos = _spawn.origin
	velocity = Vector3.ZERO
	heave_v = 0.0
	yaw_rate = 0.0
	tilt = Vector2.ZERO
	yaw = _spawn.basis.get_euler().y
	_fade = 1.0
	_fading = false
	if _vis:
		_vis.transform = _vis_base


func _physics_process(delta: float) -> void:
	var w := get_node_or_null("/root/Wind")
	if w == null or not w.has_water():
		return
	var steps := maxi(1, int(ceil(delta / (1.0 / 60.0))))
	var dt := delta / float(steps)
	for i in steps:
		_step(w, dt)
	_apply_transform()


func _step(w: Node, dt: float) -> void:
	var wh: float = w.sample_water_height(_pos)
	var mask: float = w.sample_water_mask(_pos)
	_ok = not is_nan(wh)
	if not _ok:
		# 離開水域（岸上）：減速，不漂、不掉落
		velocity *= exp(-4.0 * dt)
		heave_v = 0.0
		return
	# visual 模式：第一次碰到水時以作者擺位反推吃水（靜止時視覺位移＝0）
	if _vis and not _calibrated:
		draft_m = wh - _spawn.origin.y
		_calibrated = true
	# ── 垂直浮力（隱式積分：落葉 ω≈100 rad/s，顯式 Euler 在 60 Hz 會發散）
	var k := RHO_W * 9.81 * waterline_area_m2
	var c := 2.0 * heave_damping * sqrt(k * mass_kg)
	var target := wh - draft_m
	heave_v = (heave_v + dt * (k / mass_kg) * (target - _pos.y)) / (1.0 + dt * c / mass_kg + dt * dt * k / mass_kg)
	_pos.y += heave_v * dt
	# ── 水平：水流＋風拖曳
	var uw: Vector3 = w.sample_water_flow(_pos)
	var ua: Vector3 = w.sample_wind(_pos + Vector3(0, 0.1, 0))
	ua.y = 0.0
	var rw := uw - Vector3(velocity.x, 0, velocity.z)
	var ra := ua - Vector3(velocity.x, 0, velocity.z)
	var f := 0.5 * RHO_W * CD_W * water_drag_area_m2 * rw.length() * rw \
		+ 0.5 * RHO_A * CD_A * air_drag_area_m2 * ra.length() * ra
	# 離岸邊推回：沿水域遮罩梯度（往水多的方向）
	if mask < 0.6:
		var g := Vector3(w.sample_water_mask(_pos + Vector3(0.5, 0, 0)) - w.sample_water_mask(_pos - Vector3(0.5, 0, 0)), 0,
			w.sample_water_mask(_pos + Vector3(0, 0, 0.5)) - w.sample_water_mask(_pos - Vector3(0, 0, 0.5)))
		f += g.normalized() * (0.6 - mask) * mass_kg * 2.0 if g.length() > 1e-4 else Vector3.ZERO
	var acc := f / mass_kg
	velocity += Vector3(acc.x, 0, acc.z) * dt
	# ── 繫留
	if tether_length > 0.0:
		var off := Vector3(_pos.x - _anchor.x, 0, _pos.z - _anchor.z)
		var dist := off.length()
		if dist > tether_length:
			var n := off / dist
			velocity -= n * maxf(velocity.dot(n), 0.0) * minf(1.0, 8.0 * dt)
			velocity -= n * (dist - tether_length) * 6.0 * dt
	var hv := Vector3(velocity.x, 0, velocity.z)
	if hv.length() > max_speed:
		hv = hv.normalized() * max_speed
	velocity = Vector3(hv.x, 0, hv.z)
	_pos.x += velocity.x * dt
	_pos.z += velocity.z * dt
	# ── 姿態：貼合水面法線（俯仰／橫搖）
	var nrm: Vector3 = w.sample_water_normal(_pos)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var right := Vector3(fwd.z, 0, -fwd.x)
	var lim := deg_to_rad(max_tilt_deg)
	var want := Vector2(clampf(-nrm.dot(fwd) * 6.0, -lim, lim), clampf(nrm.dot(right) * 6.0, -lim, lim))
	tilt = tilt.lerp(want, 1.0 - exp(-tilt_stiffness * dt))
	# ── 偏航：流場剪切（左右兩側流速差）＋風力矩（慢慢轉向順風／順流），帶慣性
	var side := right * 0.4
	var fl_r: Vector3 = w.sample_water_flow(_pos + side)
	var fl_l: Vector3 = w.sample_water_flow(_pos - side)
	var shear: float = (fl_r - fl_l).dot(fwd)
	var align := 0.0
	var drift := hv + ua * (air_drag_area_m2 / maxf(air_drag_area_m2 + water_drag_area_m2 * 30.0, 1e-5))
	if drift.length() > 0.02:
		align = wrapf(atan2(drift.x, drift.z) - yaw, -PI, PI) * 0.08
	var torque: float = shear * 0.6 + align - yaw_damping * yaw_rate
	yaw_rate += torque / maxf(yaw_inertia, 0.01) * dt
	yaw_rate = clampf(yaw_rate, -2.0, 2.0)
	yaw += yaw_rate * dt
	# ── 臨時漂流物：淡出回收
	if recycle:
		var gone := _pos.distance_to(_spawn.origin) > recycle_distance or mask < 0.1
		if gone and not _fading:
			_fading = true
		if _fading:
			_fade = maxf(0.0, _fade - dt / 1.2)
			if _fade <= 0.0 and _far_from_camera():
				_respawn()


## 重生點不在相機畫面內（或很遠）才重生——玩家看不到「突然冒出來」。
func _far_from_camera() -> bool:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return true
	return cam.global_position.distance_to(_spawn.origin) > 25.0 or not cam.is_position_in_frustum(_spawn.origin)


func _respawn() -> void:
	var j := Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
	_pos = _spawn.origin + j
	# 重生在「水面 − 吃水」（平衡位置），不是水面高度——否則重物會從 12 cm 高處落下再晃
	var w := get_node_or_null("/root/Wind")
	if w != null:
		var wh: float = w.sample_water_height(_pos)
		if not is_nan(wh):
			_pos.y = wh - draft_m
	velocity = Vector3.ZERO
	heave_v = 0.0
	_fading = false
	_fade = 0.0
	# 重生後淡入（縮放 0→1）
	create_tween().tween_property(self, "_fade", 1.0, 1.0)


func _apply_transform() -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt.x) * Basis(Vector3.FORWARD, tilt.y)
	var sc := maxf(_fade, 0.001)
	if _vis:
		# 只動視覺子節點：相對作者擺位的位移＋姿態；本體與碰撞不動
		var local_off := global_transform.affine_inverse() * _pos
		var rel := Basis(Vector3.UP, yaw - _spawn.basis.get_euler().y) * Basis(Vector3.RIGHT, tilt.x) * Basis(Vector3.FORWARD, tilt.y)
		_vis.transform = Transform3D(rel * _vis_base.basis, _vis_base.origin + local_off)
	else:
		global_transform = Transform3D(b.scaled(Vector3(sc, sc, sc)), _pos)


## 取證用狀態
func state() -> Dictionary:
	return {"pos": _pos, "vel": velocity, "heave_v": heave_v, "yaw": yaw, "yaw_rate": yaw_rate,
		"tilt": tilt, "in_water": _ok, "fade": _fade}
