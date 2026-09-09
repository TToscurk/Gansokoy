extends CharacterBody3D
class_name EnemyWolf
## 獸道山犬（雙尾狼）—— 序章 MQ02 的第一場戰鬥。
##
## 與 enemy_samurai 共用同一套戰鬥契約：軀幹（posture）、take_hit()、
## can_deathblow()、execute_deathblow()。玩家那邊一行都不用改。
##
## 差別在三點：
## 1. **有真動畫**（Idle/Walk/Run/Charge/Slam/Gatsuga/Dissolve），前搖靠動畫本身讀，
##    不是靠頭頂光環。光環仍保留成可選，預設關。
## 2. **原地動畫、無 root motion** —— 位移全部由本腳本驅動（README 明載）。
##    衝撞的推進必須自己算，否則狼會在原地跑步。
## 3. **死亡是 Dissolve 上浮化光點**，不是倒地。所以 _on_died 不做倒地 tween。
##
## 設計紅線同武士：**前搖必須看得見**。Charge 前搖 1.2 s（刨地），
## Slam 前搖 1.0 s（蹲身）—— 玩家輸掉必須是讀錯招，不是被偷。

const PostureComponent = preload("res://characters/combat/posture.gd")
const CombatVFX = preload("res://characters/yoriichi/vfx/combat_vfx.gd")
const DissolveFX = preload("res://characters/combat/wolf_dissolve_fx.gd")
const GatsugaFX = preload("res://characters/combat/wolf_gatsuga_fx.gd")

enum State { IDLE, APPROACH, WINDUP, STRIKE, RECOVER, BACKSTEP, BREAK, DEAD }
enum Attack { CHARGE, SLAM, GATSUGA }

signal attack_windup(perilous: bool)
signal attack_struck(damage: float)
signal state_changed(state: State)
signal posture_changed(current: float, maximum: float)
signal health_changed(current: float, maximum: float)
signal became_vulnerable
signal died

@export_group("Stats")
## 序章第一隻怪：比武士脆，玩家 3–4 刀能解決。
@export var max_health := 55.0
@export var max_posture := 70.0
@export var posture_regen := 14.0
@export var posture_regen_delay := 1.4
@export var break_time := 3.0

@export_group("Senses")
@export var detect_range := 16.0
## 四足獸的攻擊距離比人長。
@export var attack_range := 3.2
@export var move_speed := 4.2
## 衝撞時的推進速度。
@export var charge_speed := 11.0
@export var turn_speed := 7.0
@export var gravity := 20.0

@export_group("Attack")
## 衝撞：刨地前搖 → 撞。README 的 Charge 全長 3.67 s，這裡只取前段做前搖。
@export_range(0.4, 2.0, 0.05) var charge_windup := 1.2
@export var charge_dash_time := 0.55
@export var charge_damage := 16.0
@export var charge_posture_damage := 13.0
## 砸地：蹲身 → 跳 → 砸。範圍攻擊，不可安全格擋（危）。
@export_range(0.4, 2.0, 0.05) var slam_windup := 1.0
@export var slam_strike_time := 0.18
@export var slam_damage := 24.0
@export var slam_posture_damage := 22.0
## 砸地的半徑（範圍攻擊，比 attack_range 大）。
@export var slam_radius := 4.0
@export var recover_time := 0.7
@export var attack_cooldown := 0.45
## 出招時選擇砸地（危攻擊）的機率，其餘為衝撞。
@export_range(0.0, 1.0, 0.05) var slam_chance := 0.3
## 牙通牙（旋轉突進）：距離較遠時才用，是拉近距離的招。
## 前搖 = 動畫起旋前的 f0–30（1.25 s），旋轉段 f30–73。
@export_range(0.0, 1.0, 0.05) var gatsuga_chance := 0.25
## 超過這個距離才考慮牙通牙（近身用衝撞／砸地）。
@export var gatsuga_min_range := 4.5
@export var gatsuga_damage := 20.0
@export var gatsuga_posture_damage := 18.0
## 旋轉段的推進速度。
@export var gatsuga_speed := 9.0

@export_group("Visual")
## 頭頂前搖光環。狼的動畫本身就讀得出前搖，預設關；除錯時可開。
@export var show_tell_ring := false

var posture: Node = null
var target: Node3D = null
var state: State = State.IDLE

var _timer := 0.0
var _attack: Attack = Attack.CHARGE
var _hit_this_strike := false
var _visual: Node3D = null
var _tell: MeshInstance3D = null
var _anim: AnimationPlayer = null
var _charge_dir := Vector3.ZERO
## 死亡溶解：換上的 shader 材質、光點粒子、經過秒數
var _dissolve_mats: Array = []
var _motes: GPUParticles3D = null
var _dissolve_t := -1.0
## 溶解掃描的底線，死亡當下鎖定（身體會上浮，底線不能跟著跑）
var _sweep_floor := INF
## 牙通牙特效：旋轉段用不透明鑽體取代狼的網格（見 wolf_gatsuga_fx.gd 註解）
var _drill: MeshInstance3D = null
var _dust: GPUParticles3D = null
var _streaks: GPUParticles3D = null
var _gatsuga_t := -1.0
## 狼的網格根節點（旋轉段要整個藏起來）
var _wolf_mesh: Node3D = null


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
	# AnimationPlayer 在匯入的 GLB 子樹裡，名字由匯入器決定 —— 用型別找，不用路徑。
	_anim = _find_anim(self)
	if _anim == null:
		push_warning("[狼] 找不到 AnimationPlayer，動畫不會播")
	else:
		_play("Idle")
	# 牙通牙的鑽體與粒子，建好先關著
	if _visual != null:
		_drill = GatsugaFX.make_drill(_visual)
		_dust = GatsugaFX.make_dust(self)
		_streaks = GatsugaFX.make_streaks(self)
		# 狼的 GLB 實例是 Visual 的子節點（見 enemy_wolf.tscn）
		for c in _visual.get_children():
			if c is Node3D and String(c.name).begins_with("wolf"):
				_wolf_mesh = c
				break

	if target == null:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_anim(c)
		if f != null:
			return f
	return null


func _play(anim: String, speed: float = 1.0) -> void:
	if _anim == null or not _anim.has_animation(anim):
		return
	if _anim.current_animation == anim and _anim.is_playing():
		return
	_anim.play(anim, 0.18, speed)


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	_timer = 0.0
	state_changed.emit(s)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		# 死亡動畫是上浮化光點，不受重力
		if _dissolve_t >= 0.0:
			_dissolve_t += delta
			_tick_dissolve()
		move_and_slide()
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
			_play("Idle")
			if _target_distance() <= detect_range:
				_set_state(State.APPROACH)
		State.APPROACH:
			_chase(delta)
			_play("Run")
			var d := _target_distance()
			if d > detect_range * 1.4:
				_set_state(State.IDLE)
			elif d <= attack_range and _timer >= attack_cooldown:
				_begin_windup()
		State.WINDUP:
			_face_target(delta)
			velocity.x = 0.0
			velocity.z = 0.0
			var wind: float = charge_windup
			if _attack == Attack.SLAM:
				wind = slam_windup
			elif _attack == Attack.GATSUGA:
				# 牙通牙的前搖由動畫決定：起旋在 f30 = 1.25 s
				wind = GatsugaFX.spin_window().x
				# ⚠ _gatsuga_t 必須跟著 Gatsuga 動畫的播放時間走，從 WINDUP 就開始累加。
				#   只在 STRIKE 累加會讓曲線落後一整個前搖（1.25 s），
				#   結果旋轉段還沒到就出招、特效整段不顯示。
				_gatsuga_t += delta
				GatsugaFX.tick(_drill, _dust, _streaks, self, _wolf_mesh, _gatsuga_t,
					-global_transform.basis.z, _visual_scale())
			if _timer >= wind:
				_begin_strike()
		State.STRIKE:
			if _attack == Attack.GATSUGA:
				# 旋轉突進：推進 + 特效逐幀更新
				_gatsuga_t += delta
				velocity.x = _charge_dir.x * gatsuga_speed
				velocity.z = _charge_dir.z * gatsuga_speed
				GatsugaFX.tick(_drill, _dust, _streaks, self, _wolf_mesh, _gatsuga_t,
					_charge_dir, _visual_scale())
				if not _hit_this_strike:
					_do_strike()
				if _gatsuga_t >= GatsugaFX.spin_window().y:
					_end_gatsuga()
					_set_state(State.RECOVER)
			elif _attack == Attack.CHARGE:
				# 原地動畫沒有 root motion：推進要自己給，否則狼在原地跑步。
				velocity.x = _charge_dir.x * charge_speed
				velocity.z = _charge_dir.z * charge_speed
				if not _hit_this_strike:
					_do_strike()
				if _timer >= charge_dash_time:
					_set_state(State.RECOVER)
			else:
				velocity.x = 0.0
				velocity.z = 0.0
				if not _hit_this_strike:
					_do_strike()
				if _timer >= slam_strike_time:
					_set_state(State.RECOVER)
		State.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, 22.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 22.0 * delta)
			_play("Idle")
			if _timer >= recover_time:
				if randf() < 0.4:
					_set_state(State.BACKSTEP)
				else:
					_set_state(State.APPROACH)
		State.BACKSTEP:
			var away := (global_position - _target_position())
			away.y = 0.0
			if away.length() > 0.01:
				away = away.normalized() * move_speed * 0.9
				velocity.x = away.x
				velocity.z = away.z
			_play("Walk")
			_face_target(delta)
			if _timer >= 0.55:
				_set_state(State.APPROACH)
		State.BREAK:
			velocity.x = 0.0
			velocity.z = 0.0

	move_and_slide()


func _target_position() -> Vector3:
	return target.global_position if is_instance_valid(target) else global_position


func _target_distance() -> float:
	if not is_instance_valid(target):
		return INF
	return global_position.distance_to(target.global_position)


## 狼的模型正面朝 +z（實測 probe_glb），與專案委製資產慣例一致。
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
	# 遠距離才用牙通牙（它是拉近距離的招）；近身用衝撞／砸地。
	var d := _target_distance()
	var roll := randf()
	if d >= gatsuga_min_range and roll < gatsuga_chance:
		_attack = Attack.GATSUGA
	elif roll < slam_chance:
		_attack = Attack.SLAM
	else:
		_attack = Attack.CHARGE
	_hit_this_strike = false
	_set_state(State.WINDUP)
	match _attack:
		Attack.SLAM:
			_play("Slam")
		Attack.GATSUGA:
			_play("Gatsuga")
			_gatsuga_t = 0.0
		_:
			_play("Charge")
	if _tell and show_tell_ring:
		_tell.visible = true
		var mat := _tell.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(1.0, 0.15, 0.1) if _attack == Attack.SLAM else Color(1.0, 0.95, 0.8)
			mat.emission = mat.albedo_color
	# 砸地是危攻擊（不可安全格擋）
	attack_windup.emit(_attack == Attack.SLAM)


func _begin_strike() -> void:
	_set_state(State.STRIKE)
	if _tell:
		_tell.visible = false
	if _attack == Attack.CHARGE or _attack == Attack.GATSUGA:
		# 衝撞方向在出招瞬間鎖定：鎖定後玩家閃得開，才是可讀的攻擊。
		var to := _target_position() - global_position
		to.y = 0.0
		_charge_dir = to.normalized() if to.length() > 0.01 else -global_transform.basis.z


## 狼的視覺縮放（特效曲線是模型空間的公尺，要乘上去）
func _visual_scale() -> float:
	if _wolf_mesh != null:
		return _wolf_mesh.scale.y
	return 1.0


func _end_gatsuga() -> void:
	_gatsuga_t = -1.0
	GatsugaFX.stop(_drill, _dust, _streaks, _wolf_mesh)


func _do_strike() -> void:
	_hit_this_strike = true
	var slam := _attack == Attack.SLAM
	var damage := charge_damage
	var pdmg := charge_posture_damage
	if slam:
		damage = slam_damage
		pdmg = slam_posture_damage
	elif _attack == Attack.GATSUGA:
		damage = gatsuga_damage
		pdmg = gatsuga_posture_damage
	attack_struck.emit(damage)

	if not is_instance_valid(target) or not target.has_method("take_hit"):
		return
	# 砸地是範圍攻擊，衝撞是接觸判定
	var reach: float = slam_radius if slam else attack_range * 1.3
	if _attack == Attack.GATSUGA:
		reach = attack_range * 1.5
	if _target_distance() > reach:
		return

	var hit_dir := (_target_position() - global_position).normalized()
	var result: Variant = target.take_hit({
		"damage": damage,
		"posture_damage": pdmg,
		"perilous": slam,
		"hit_pos": _target_position() + Vector3(0, 1.0, 0),
		"hit_dir": hit_dir,
		"attacker": self,
	})

	if result is Dictionary:
		var back: float = float(result.get("attacker_posture", 0.0))
		if back > 0.0:
			posture.apply_damage(0.0, back)


func take_hit(hit_data: Dictionary) -> Dictionary:
	if posture == null or posture.is_dead():
		return {"result": "dead"}

	var damage: float = float(hit_data.get("damage", 10.0))
	var posture_damage: float = float(hit_data.get("posture_damage", damage * 0.8))
	var hit_pos: Vector3 = hit_data.get("hit_pos", global_position + Vector3(0, 0.9, 0))
	var hit_dir: Vector3 = hit_data.get("hit_dir", -global_transform.basis.z)
	var heavy: bool = bool(hit_data.get("heavy", false))

	posture.apply_damage(damage, posture_damage)
	CombatVFX.spawn_hit_spark(self, hit_pos, -hit_dir, heavy)

	# 打斷前搖：衝撞蓄力被打斷，玩家搶到節奏
	if state == State.WINDUP:
		_set_state(State.RECOVER)
		_end_gatsuga()
		if _tell:
			_tell.visible = false

	return {"result": "hit", "damage": damage}


func can_deathblow() -> bool:
	return posture != null and not posture.is_dead() and posture.is_broken()


func execute_deathblow() -> bool:
	if not can_deathblow():
		return false
	return posture.deathblow()


func _on_posture_broken() -> void:
	_set_state(State.BREAK)
	_play("Idle", 0.35)
	_end_gatsuga()
	if _tell:
		_tell.visible = false
	became_vulnerable.emit()


func _on_posture_recovered() -> void:
	if state == State.BREAK:
		_set_state(State.APPROACH)


## 死亡：Dissolve 是「仰頭上浮 40 cm 後化為光點」，不倒地。
## 動畫本身無 root motion，上浮位移在此驅動。
func _on_died() -> void:
	_set_state(State.DEAD)
	velocity = Vector3.ZERO
	_end_gatsuga()
	_play("Dissolve")
	# 碰撞立刻關掉：屍體不該擋路，且 4 秒的化光過程玩家會想走過去
	set_collision_layer_value(2, false)
	var col := get_node_or_null("CollisionShape3D")
	if col:
		(col as CollisionShape3D).disabled = true
	died.emit()
	# 化光：材質換成溶解 shader、生出光點粒子，逐幀由 dissolve_fx.json 驅動
	if _visual != null:
		_dissolve_mats = DissolveFX.install(_visual)
		_motes = DissolveFX.make_particles(self)
		_motes.emitting = true
	_dissolve_t = 0.0
	# 動畫 4 秒 + 粒子殘留 1.7 秒
	var t := create_tween()
	t.tween_interval(DissolveFX.duration() + 1.7)
	t.tween_callback(queue_free)


## 每幀把 dissolve_fx.json 的曲線餵給 shader 與粒子。
## 曲線值是**模型局部**的高度，要換成世界座標才對得上 shader 的 world_pos。
func _tick_dissolve() -> void:
	var s: Dictionary = DissolveFX.sample(_dissolve_t)
	var sc := _visual_scale()
	var base_y := global_position.y
	# ⚠ 掃描範圍要用「該幀的實際身體上下界」，但 zmin 會隨上浮抬高。
	#   直接用 zmin 當底，溶解線的 0 點會跟著身體一起往上跑，
	#   結果是溶解進度看起來比曲線快（實測 dissolve=0.73 時身體幾乎沒了）。
	#   底部鎖在腳的起始高度，只讓頂部跟著上浮，掃描才與 dissolve 對得上。
	if _sweep_floor == INF:
		_sweep_floor = base_y + float(s["ymin"]) * sc
	var ymin: float = _sweep_floor
	var ymax: float = base_y + float(s["ymax"]) * sc
	for m in _dissolve_mats:
		var sm := m as ShaderMaterial
		if sm == null:
			continue
		sm.set_shader_parameter("dissolve", s["dissolve"])
		sm.set_shader_parameter("sweep_min", ymin)
		sm.set_shader_parameter("sweep_max", ymax)
	if _motes != null and is_instance_valid(_motes):
		var c: Vector3 = s["centre"]
		_motes.global_position = global_position + Vector3(c.x * sc, c.y * sc, c.z * sc)
		# emit_rate 0–1 → 粒子量。收斂到 0 時停止發射，讓已生成的自然飄完。
		var rate: float = float(s["emit_rate"])
		_motes.emitting = rate > 0.02
		_motes.amount_ratio = clampf(rate, 0.0, 1.0)
