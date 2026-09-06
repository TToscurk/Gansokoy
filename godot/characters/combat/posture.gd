extends Node
class_name Posture
## 隻狼式雙軌戰鬥數值：血量（Health）決定生死，軀幹（Posture）決定破綻。
##
## 核心規則：
##   1. 血量歸零 = 死亡。
##   2. 軀幹滿 = 破綻（Vulnerable），此時可被忍殺，無視剩餘血量。
##   3. **血越少，軀幹回復越慢** —— 殘血時不能只靠格擋苟活，這是本系統的手感支柱。
##
## 玩家與敵人共用同一份實作；差異只在 @export 數值。

signal posture_broken
signal posture_recovered
signal health_changed(current: float, maximum: float)
signal posture_changed(current: float, maximum: float)
signal died

@export var max_health := 100.0
@export var max_posture := 100.0
## 軀幹每秒回復量（滿血時）。
@export var posture_regen := 25.0
## 受擊後多久才開始回復軀幹。
@export var posture_regen_delay := 0.8
## 破綻持續時間；期間可被忍殺，結束後軀幹清空。
@export var break_time := 2.0
## 殘血時的軀幹回復下限倍率：實際倍率 = floor + (1 - floor) * 血量比例。
@export_range(0.0, 1.0, 0.05) var wounded_regen_floor := 0.35

var health := 0.0
var posture := 0.0

var _regen_block := 0.0
var _break_left := 0.0
var _dead := false


func _ready() -> void:
	health = max_health
	posture = 0.0


func _process(delta: float) -> void:
	tick(delta)


func is_dead() -> bool:
	return _dead


func is_broken() -> bool:
	return _break_left > 0.0


## 受到一次攻擊：扣血並累積軀幹。兩者獨立，彈刀可以只灌軀幹不扣血。
func apply_damage(damage: float, posture_damage: float) -> void:
	if _dead:
		return

	if damage > 0.0:
		health = maxf(health - damage, 0.0)
		health_changed.emit(health, max_health)
		if health <= 0.0:
			_dead = true
			died.emit()
			return

	if posture_damage > 0.0:
		_regen_block = posture_regen_delay
		# 破綻中軀幹已滿，不再累積。
		if not is_broken():
			posture = minf(posture + posture_damage, max_posture)
			posture_changed.emit(posture, max_posture)
			if posture >= max_posture:
				_break_left = break_time
				posture_broken.emit()


## 手動推進一個時間步；_process 會自動呼叫，測試可直接驅動。
func tick(delta: float) -> void:
	if _dead:
		return

	if _break_left > 0.0:
		_break_left = maxf(_break_left - delta, 0.0)
		if _break_left <= 0.0:
			# 破綻結束：軀幹清空，重新開始累積。
			posture = 0.0
			posture_changed.emit(posture, max_posture)
			posture_recovered.emit()
		return

	if _regen_block > 0.0:
		var used := minf(_regen_block, delta)
		_regen_block -= used
		delta -= used
		if delta <= 0.0:
			return

	if posture > 0.0:
		posture = maxf(posture - posture_regen * regen_scale() * delta, 0.0)
		posture_changed.emit(posture, max_posture)


## 殘血懲罰倍率：滿血 1.0，瀕死趨近 wounded_regen_floor。
func regen_scale() -> float:
	var ratio := health / maxf(max_health, 0.001)
	return wounded_regen_floor + (1.0 - wounded_regen_floor) * ratio


func health_ratio() -> float:
	return clampf(health / maxf(max_health, 0.001), 0.0, 1.0)


func posture_ratio() -> float:
	return clampf(posture / maxf(max_posture, 0.001), 0.0, 1.0)


## 忍殺：無視剩餘血量直接處決，只在破綻中有效。
func deathblow() -> bool:
	if _dead or not is_broken():
		return false
	health = 0.0
	_dead = true
	health_changed.emit(health, max_health)
	died.emit()
	return true


func heal_full() -> void:
	_dead = false
	health = max_health
	posture = 0.0
	_break_left = 0.0
	_regen_block = 0.0
	health_changed.emit(health, max_health)
	posture_changed.emit(posture, max_posture)
