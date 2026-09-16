extends Node
class_name HitFeedback
## 受擊回饋的鏡頭層 —— 受擊／彈刀／格擋時的鏡頭震動。
##
## 為什麼是獨立節點而不是寫進控制器：Camera3D 掛在 Pivot/SpringArm3D 底下，
## 而 Pivot 是玩家自己會手拖的節點。震動只能動 Camera3D 的 h_offset／v_offset
## （Camera3D 自己的欄位，不碰 transform），這樣使用者在編輯器拉的鏡位不會被
## 覆蓋，震動結束也一定回得到 0。
##
## 素材現況：緣一沒有受擊動作（animations/ 只有移動與攻擊）。使用者 2026-09-16
## 裁定「先用既有素材＋程式演出頂著」——這一層就是那件「程式演出」。

## 震動的取樣頻率（Hz）。太高像雜訊、太低像漂移。
@export var shake_hz := 34.0
## 每次震動的振幅上限（公尺）。安全上限：不要超過 0.4，
## 否則鏡頭會穿進角色身體或牆面。
@export var shake_max := 0.4

var _cam: Camera3D = null
var _strength := 0.0
var _left := 0.0
var _total := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_cam = _find_camera()


## 相機在 Player/Pivot/SpringArm3D/Camera3D —— 是 HitFeedback 的兄弟分支，
## 不是子節點（is_ancestor_of 會找不到）。從宿主（Player）往下找才對。
func _find_camera() -> Camera3D:
	var host := get_parent()
	if host == null:
		return null
	for n in host.find_children("*", "Camera3D", true, false):
		return n as Camera3D
	return null


## 目前是否正在震動（測試用）。
func is_shaking() -> bool:
	return _left > 0.0


## 目前的震動強度（測試用）。
func strength() -> float:
	return _strength


## 發動一次震動。強度 0 或時間 0 = 不做事（滑桿拉到 0 必須真的關掉）。
func shake(strength: float, duration: float) -> void:
	if strength <= 0.0 or duration <= 0.0:
		return
	if _cam == null:
		_cam = _find_camera()
	if _cam == null:
		return
	# 連續受擊取較強的一次，不疊加 —— 疊加會在連段時把鏡頭甩出去。
	_strength = minf(maxf(strength, _strength * (_left / maxf(_total, 0.001))), shake_max)
	_total = duration
	_left = duration
	_t = 0.0


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	if _cam == null:
		_left = 0.0
		return
	_left = maxf(_left - delta, 0.0)
	_t += delta
	# 線性衰減 × 正弦取樣：可預期、可量測，不需要額外曲線資源。
	var decay: float = _left / maxf(_total, 0.001)
	var amp: float = _strength * decay
	var phase := _t * shake_hz * TAU
	_cam.h_offset = sin(phase) * amp * _rng.randf_range(0.6, 1.0)
	_cam.v_offset = cos(phase * 1.37) * amp * _rng.randf_range(0.6, 1.0)
	if _left <= 0.0:
		_strength = 0.0
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0