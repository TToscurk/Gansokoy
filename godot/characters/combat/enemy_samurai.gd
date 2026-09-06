extends CharacterBody3D
class_name EnemySamurai
## 隻狼式敵人武士：有前搖、可被彈刀、軀幹會爆、破綻中可忍殺。
##
## 刻意用有限狀態機而不是行為樹 —— 敵人只需要「逼近／讀得出來的攻擊／退開」，
## 行為樹在這個規模是過度工程。
##
## 設計紅線：**前搖必須看得見**。玩家輸掉一場戰鬥，必須是自己讀錯招，
## 而不是被沒有預兆的攻擊偷掉。

const PostureComponent = preload("res://characters/combat/posture.gd")
const CombatVFX = preload("res://characters/yoriichi/vfx/combat_vfx.gd")

enum State { IDLE, APPROACH, WINDUP, STRIKE, RECOVER, BACKSTEP, BREAK, DEAD }

signal attack_windup(perilous: bool)
signal attack_struck(damage: float)
signal state_changed(state: State)
signal posture_changed(current: float, maximum: float)
signal health_changed(current: float, maximum: float)
signal became_vulnerable
signal died

@export_group("Stats")
@export var max_health := 80.0
@export var max_posture := 100.0
@export var posture_regen := 18.0
@export var posture_regen_delay := 1.2
@export var break_time := 3.0

@export_group("Senses")
## 進入此距離開始追擊。
@export var detect_range := 14.0
## 進入此距離開始出招。
@export var attack_range := 2.4
@export var move_speed := 3.4
@export var turn_speed := 6.0
@export var gravity := 20.0

@export_group("Attack")
## 前搖時間：武器抬起到判定之間。**低於 0.3 秒玩家讀不出來**。
@export_range(0.3, 1.5, 0.05) var windup_time := 0.45
## 判定持續時間。
@export var strike_time := 0.12
## 後搖：玩家的反擊窗口。
@export var recover_time := 0.55
@export var attack_damage := 18.0
@export var attack_posture_damage := 14.0
## 出招時是危攻擊（不可安全格擋）的機率。
@export_range(0.0, 1.0, 0.05) var perilous_chance := 0.25
@export var perilous_windup_time := 0.6
@export var perilous_damage := 26.0
@export var perilous_posture_damage := 24.0
## 攻擊之間的間隔，避免無縫連打。
@export var attack_cooldown := 0.35

var posture: Node = null
var target: Node3D = null
var state: State = State.IDLE

var _timer := 0.0
var _next_perilous := false
var _hit_this_strike := false
var _visual: Node3D = null
var _tell: MeshInstance3D = null


func _ready() -> void:
	add_to_group("hittable")
	add_to_group("enemies")

	posture = PostureComponent.new()
	posture.name = "Posture"
	posture.max_health = max_health
	posture.max_posture = max_posture
	posture.posture_regen = posture_regen
	posture.posture_regen_delay = posture_regen_delay
	posture.break_time = break_time
	add_child(posture)
	posture.posture_broken.connect(_on_posture_broken)
	posture.posture_recovered.connect(_on_posture_recovered)
	posture.died.connect(_on_died)
	posture.posture_changed.connect(func(c, m): posture_changed.emit(c, m))
	posture.health_changed.connect(func(c, m): health_changed.emit(c, m))

	_visual = get_node_or_null("Visual")
	_tell = get_node_or_null("Visual/Tell")
	if _tell:
		_tell.visible = false

	if target == null:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	_timer = 0.0
	state_changed.emit(s)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	_timer += delta

	match state:
		State.IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			if _target_distance() <= detect_range:
				_set_state(State.APPROACH)
		State.APPROACH:
			_chase(delta)
			var d := _target_distance()
			if d > detect_range * 1.4:
				_set_state(State.IDLE)
			elif d <= attack_range and _timer >= attack_cooldown:
				_begin_windup()
		State.WINDUP:
			_face_target(delta)
			velocity.x = 0.0
			velocity.z = 0.0
			var wind: float = perilous_windup_time if _next_perilous else windup_time
			if _timer >= wind:
				_begin_strike()
		State.STRIKE:
			velocity.x = 0.0
			velocity.z = 0.0
			if not _hit_this_strike:
				_do_strike()
			if _timer >= strike_time:
				_set_state(State.RECOVER)
		State.RECOVER:
			velocity.x = 0.0
			velocity.z = 0.0
			if _timer >= recover_time:
				# 退開或再壓上，讓節奏不是無腦連打。
				if randf() < 0.35:
					_set_state(State.BACKSTEP)
				else:
					_set_state(State.APPROACH)
		State.BACKSTEP:
			var away := (global_position - _target_position())
			away.y = 0.0
			if away.length() > 0.01:
				away = away.normalized() * move_speed * 0.8
				velocity.x = away.x
				velocity.z = away.z
			_face_target(delta)
			if _timer >= 0.5:
				_set_state(State.APPROACH)
		State.BREAK:
			# 破綻：完全不動，等著被忍殺。
			velocity.x = 0.0
			velocity.z = 0.0

	move_and_slide()


func _target_position() -> Vector3:
	return target.global_position if is_instance_valid(target) else global_position


func _target_distance() -> float:
	if not is_instance_valid(target):
		return INF
	return global_position.distance_to(target.global_position)


func _face_target(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var to := _target_position() - global_position
	to.y = 0.0
	if to.length_squared() < 0.0004:
		return
	var want := atan2(to.x, to.z)
	rotation.y = rotate_toward(rotation.y, want, turn_speed * delta)


func _chase(delta: float) -> void:
	if not is_instance_valid(target):
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var to := _target_position() - global_position
	to.y = 0.0
	if to.length() > attack_range * 0.9:
		var dir := to.normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	_face_target(delta)


func _begin_windup() -> void:
	_next_perilous = randf() < perilous_chance
	_hit_this_strike = false
	_set_state(State.WINDUP)
	if _tell:
		_tell.visible = true
		var mat := _tell.material_override as StandardMaterial3D
		if mat:
			# 危攻擊是紅色警示；一般攻擊是白色抬手。
			mat.albedo_color = Color(1.0, 0.15, 0.1) if _next_perilous else Color(1.0, 0.95, 0.8)
			mat.emission = mat.albedo_color
	attack_windup.emit(_next_perilous)


func _begin_strike() -> void:
	_set_state(State.STRIKE)
	if _tell:
		_tell.visible = false


## 判定：對前方扇形內的玩家送出 hit_data，由對方決定彈刀／格擋／中招。
func _do_strike() -> void:
	_hit_this_strike = true
	var damage: float = perilous_damage if _next_perilous else attack_damage
	var pdmg: float = perilous_posture_damage if _next_perilous else attack_posture_damage
	attack_struck.emit(damage)

	if not is_instance_valid(target) or not target.has_method("take_hit"):
		return
	if _target_distance() > attack_range * 1.35:
		return

	var hit_dir := (_target_position() - global_position).normalized()
	var result: Variant = target.take_hit({
		"damage": damage,
		"posture_damage": pdmg,
		"perilous": _next_perilous,
		"hit_pos": _target_position() + Vector3(0, 1.1, 0),
		"hit_dir": hit_dir,
		"attacker": self,
	})

	# 被彈刀的人自己吃軀幹傷害 —— 這是玩家反擊的主要手段。
	if result is Dictionary:
		var back: float = float(result.get("attacker_posture", 0.0))
		if back > 0.0:
			posture.apply_damage(0.0, back)


## 玩家的刀打中我。
func take_hit(hit_data: Dictionary) -> Dictionary:
	if posture == null or posture.is_dead():
		return {"result": "dead"}

	var damage: float = float(hit_data.get("damage", 10.0))
	var posture_damage: float = float(hit_data.get("posture_damage", damage * 0.8))
	var hit_pos: Vector3 = hit_data.get("hit_pos", global_position + Vector3(0, 1.1, 0))
	var hit_dir: Vector3 = hit_data.get("hit_dir", -global_transform.basis.z)
	var heavy: bool = bool(hit_data.get("heavy", false))

	# 破綻中挨打不再累積軀幹，但照樣掉血。
	posture.apply_damage(damage, posture_damage)
	CombatVFX.spawn_hit_spark(self, hit_pos, -hit_dir, heavy)

	# 被打斷前搖：攻擊取消，玩家搶到節奏。
	if state == State.WINDUP:
		_set_state(State.RECOVER)
		if _tell:
			_tell.visible = false

	return {"result": "hit", "damage": damage}


func can_deathblow() -> bool:
	return posture != null and not posture.is_dead() and posture.is_broken()


## 忍殺：無視剩餘血量處決。
func execute_deathblow() -> bool:
	if not can_deathblow():
		return false
	return posture.deathblow()


func _on_posture_broken() -> void:
	_set_state(State.BREAK)
	if _tell:
		_tell.visible = false
	became_vulnerable.emit()


func _on_posture_recovered() -> void:
	if state == State.BREAK:
		_set_state(State.APPROACH)


func _on_died() -> void:
	_set_state(State.DEAD)
	velocity = Vector3.ZERO
	if _visual:
		# 倒地：先給一個可讀的死亡姿態，正式動畫待美術。
		var t := create_tween()
		t.tween_property(_visual, "rotation:x", deg_to_rad(-85.0), 0.4).set_trans(Tween.TRANS_QUAD)
	died.emit()
