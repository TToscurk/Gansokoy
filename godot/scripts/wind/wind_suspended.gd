extends Node3D
## Wind V1.1 類別 B：吊掛剛體（燈籠／風鈴／吊牌）。
##
## 為什麼不是 RigidBody3D：村裡有 62 個燈籠節點，全部開物理會把靜態場景變成
## 幾百個持續活動的剛體（而且吊點是繩子／橫桿，不是關節）。這裡用「二軸擺錘＋阻尼」：
##   角加速度 = 風壓力矩／慣量 − (g/L)·θ − damping·ω
## 風壓 q = ½·ρ·v²·A，v 來自 Wind.sample_field（與植被同一個場），所以陣風掃過時
## 燈籠會比草晚一點開始、也晚一點停（慣性），不會和樹葉同步。
##
## 葉片會擺、吊點不會移動：節點旋轉只改 Basis，位置固定；max_angle 夾住避免打結。

@export var mass_kg := 0.6
## 迎風面積（m²）。燈籠本體約 0.3×0.4 m。
@export var area_m2 := 0.12
## 吊點到重心的距離（m）——擺長。
@export var length_m := 0.55
@export var wind_gain := 1.0
## 阻尼比（1/s）。越大越快停。
@export var damping := 1.1
@export var max_angle_deg := 30.0
## 慣量倍率：>1 更遲鈍、<1 更活潑（逐物件微調用）。
@export var inertia_scale := 1.0
## 距離超過這個值就降到 10 Hz（省 CPU；畫面上一樣）。
@export var lod_distance := 45.0

var _rest: Transform3D
var _pitch := 0.0   # 繞 X：風的 +Z 分量
var _roll := 0.0    # 繞 Z：風的 +X 分量
var _vp := 0.0
var _vr := 0.0
var _phase := 0.0
var _acc := 0.0
var _camera: Camera3D


func _ready() -> void:
	_rest = transform
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	_phase = rng.randf() * TAU
	inertia_scale *= 0.9 + 0.2 * rng.randf()
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	# LOD：遠處 10 Hz
	var cam := _get_camera()
	if cam != null and cam.global_position.distance_to(global_position) > lod_distance:
		_acc += delta
		if _acc < 0.1:
			return
		delta = _acc
		_acc = 0.0
	var f: Dictionary = Wind.sample_field(global_position + Vector3(0, length_m, 0))
	var v := float(f["speed"]) * wind_gain
	var ang := float(f["angle"])
	var q := 0.5 * 1.2 * v * v * area_m2
	var inv_i := 1.0 / maxf(mass_kg * length_m, 0.01) * inertia_scale
	var a_roll := q * cos(ang) * inv_i
	var a_pitch := q * sin(ang) * inv_i
	var g_over_l := 9.8 / maxf(length_m, 0.05)
	_vr += (a_roll - g_over_l * _roll - damping * _vr) * delta
	_vp += (a_pitch - g_over_l * _pitch - damping * _vp) * delta
	_roll += _vr * delta
	_pitch += _vp * delta
	var mx := deg_to_rad(max_angle_deg)
	if absf(_roll) > mx:
		_roll = clampf(_roll, -mx, mx)
		_vr *= 0.2
	if absf(_pitch) > mx:
		_pitch = clampf(_pitch, -mx, mx)
		_vp *= 0.2
	# 靜止門檻：殘擺 <0.5°、角速度極小就真的停住，不再永遠微微晃（截圖／效能都需要）。
	if absf(_pitch) < 0.008 and absf(_roll) < 0.008 and absf(_vp) < 0.02 and absf(_vr) < 0.02:
		_pitch = 0.0
		_roll = 0.0
		_vp = 0.0
		_vr = 0.0
	transform = _rest * Transform3D(Basis.from_euler(Vector3(_pitch, 0.0, _roll)), Vector3.ZERO)


## 目前擺角（度），測試／除錯用。
func swing_deg() -> float:
	return rad_to_deg(Vector2(_roll, _pitch).length())


func settle() -> void:
	_pitch = 0.0
	_roll = 0.0
	_vp = 0.0
	_vr = 0.0
	transform = _rest


func _get_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	_camera = get_viewport().get_camera_3d()
	return _camera
