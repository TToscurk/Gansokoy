extends CharacterBody3D
class_name EnemyWolf
## 獸道山犬 —— 序章 MQ02 的第一場戰鬥。
##
## 與 enemy_samurai 共用同一套戰鬥契約：軀幹（posture）、take_hit()、
## can_deathblow()、execute_deathblow()。玩家那邊一行都不用改。
##
## 2026-09-10 換模型：舊雙尾狼（wolf_twin_tail.glb，58 骨）換成新單尾狼
## （wolf_pounce.glb，46 骨）。兩隻骨架不相容，動畫不能互用，整套攻擊
## 鏈改成對應新模型自帶的 6 個動作：
##   Wolf_Idle / Wolf_Walk / Wolf_Run / Wolf_Attack_Claw / Wolf_Attack_Lunge
##   / Wolf_Attack_Pounce
## 舊的 Charge → Attack_Lunge（直線突進咬擊）、Slam → Attack_Claw（近身爪擊）、
## Gatsuga（舊旋轉突進特效）→ Attack_Pounce（新模型自帶旋風+滑行煞車，
## 不再需要 wolf_gatsuga_fx.gd 的鑽體遮蔽方案）。
## Dissolve 死亡動畫已完成：新模型的 Wolf_Death（96 幀 / 4.0 s）——中招 →
##   挺直抬頭 → 四腳離地 → 緩緩浮空 72 cm，全程不倒地。
##   wolf_dissolve_fx.gd／dissolve_fx.json 已接回，逐幀曲線重新由該動畫量測產生。
##
## 差別在三點：
## 1. **有真動畫**，前搖靠動畫本身讀，不是靠頭頂光環。光環仍保留成可選，預設關。
## 2. **原地動畫、無 root motion** —— 位移全部由本腳本驅動。
##    衝撞的推進必須自己算，否則狼會在原地跑步。
##    （Attack_Pounce 例外：旋風段的旋轉與滑行煞車已烘進動畫本身，
##    但推進量仍由本腳本的 velocity 驅動，動畫只負責姿態與视覺旋轉。）
## 3. 死亡流程見上方 ⚠ 備註，暫時簡化。
##
## 設計紅線同武士：**前搖必須看得見**。Lunge 前搖 1.2 s（蓄力後突進），
## Claw 前搖 1.0 s（收爪蓄力）—— 玩家輸掉必須是讀錯招，不是被偷。

const PostureComponent = preload("res://characters/combat/posture.gd")
const CombatVFX = preload("res://characters/yoriichi/vfx/combat_vfx.gd")
const VortexFX = preload("res://characters/combat/wolf_vortex_fx.gd")
const WindStreakFX = preload("res://characters/combat/wolf_windstreak_fx.gd")
const DissolveFX = preload("res://characters/combat/wolf_dissolve_fx.gd")

enum State { IDLE, APPROACH, WINDUP, STRIKE, RECOVER, BACKSTEP, BREAK, DEAD, DODGE }
enum Attack { LUNGE, CLAW, POUNCE }

signal attack_windup(perilous: bool)
signal attack_struck(damage: float)
signal state_changed(state: State)
signal posture_changed(current: float, maximum: float)
signal health_changed(current: float, maximum: float)
signal became_vulnerable
signal died

@export_group("Stats")
## 序章第一隻怪。設計目標：整場 20–40 秒。
## 2026-09-08 實測：55 血 + 只會挨打 ≈ 5 秒結束，太快。
## 血量拉到 90，並加上閃避（見 Dodge 群組）—— 拉長靠的是「打不中」而不是「打不動」，
## 純加血會變成砍木樁。
@export var max_health := 90.0
@export var max_posture := 85.0
@export var posture_regen := 16.0
@export var posture_regen_delay := 1.4
@export var break_time := 3.0

@export_group("Senses")
@export var detect_range := 16.0
## 四足獸的攻擊距離比人長。
@export var attack_range := 3.2
@export var move_speed := 4.2
## 突進咬擊（Lunge）時的推進速度。
@export var lunge_speed := 11.0
@export var turn_speed := 7.0
@export var gravity := 20.0

@export_group("Dodge")
## 看到玩家揮刀就側躍閃開。序章第一隻怪如果只會挨打，戰鬥 5 秒就結束了。
## GLB 沒有閃避動畫 —— 用 Run 加速 + 程序化側躍合成，四足獸的急停轉向本來就是這樣。
@export var dodge_enabled := true
## 玩家在這個距離內揮刀才閃（太遠沒必要閃，會顯得神經質）
@export var dodge_react_range := 4.5
@export var dodge_time := 0.42
@export var dodge_speed := 9.5
## 起跳高度：四足獸側躍會離地，純水平滑動看起來像溜冰
@export var dodge_hop := 3.2
## 兩次閃避之間的冷卻，避免玩家連揮時狼一直跳
@export var dodge_cooldown := 1.6
## 閃避成功率。1.0 = 每次揮刀都閃得掉，玩家會打不到而煩躁
@export_range(0.0, 1.0, 0.05) var dodge_chance := 0.55

@export_group("Animation")
## Run 的播放倍速。
@export_range(0.25, 3.0, 0.05) var run_anim_speed := 1.5
## 閃避時 Run 再加速，做出急竄感
@export_range(0.5, 4.0, 0.05) var dodge_anim_speed := 2.2

@export_group("Attack")
## 突進咬擊（Lunge）：蓄力前搖 → 直線突進咬擊。
@export_range(0.4, 2.0, 0.05) var lunge_windup := 1.2
@export var lunge_dash_time := 0.55
@export var lunge_damage := 16.0
@export var lunge_posture_damage := 13.0
## 近身爪擊（Claw）：收爪蓄力 → 揮爪。範圍小、出招快。
@export_range(0.4, 2.0, 0.05) var claw_windup := 1.0
@export var claw_strike_time := 0.18
@export var claw_damage := 24.0
@export var claw_posture_damage := 22.0
@export var recover_time := 0.7
## 出招間隔。太短玩家沒有反擊窗口，太長狼會發呆。
@export var attack_cooldown := 0.55
## 出招時選擇爪擊的機率，其餘為突進咬擊。
@export_range(0.0, 1.0, 0.05) var claw_chance := 0.3
## 撲擊（Pounce）：距離較遠時才用，是拉近距離＋大傷害的招。
## 動畫自帶旋風加速與落地滑行煞車（見 wolf_pounce.README），
## 前搖由動畫本身決定，不用額外參數。
@export_range(0.0, 1.0, 0.05) var pounce_chance := 0.25
## 超過這個距離才考慮撲擊（近身用突進咬擊／爪擊）。
## ⚠ 這個值必須大於 attack_range，且撲擊的擲骰在 APPROACH 獨立進行——
##   撲擊是「拉近距離」的招，發動帶在近身攻擊範圍之外。
@export var pounce_min_range := 4.5
## 撲擊發動距離帶的上限。超過這個距離就純追擊，不撲。
@export var pounce_max_range := 9.0
@export var pounce_damage := 20.0
@export var pounce_posture_damage := 18.0
## 撲擊蓄力後的突進速度（對應動畫 frame 30–52 的衝刺段）。
@export var pounce_speed := 9.0
## 撲擊衝刺段長度，對應 Blender 動畫 f30–52 = 0.92 s。
## 之後交給 RECOVER 的指數滑行煞車（動畫 f52–84 的滑停段）。
@export var pounce_dash_time := 0.92
## 撲擊收招後的滑行煞車：每幀（24fps 基準）速度衰減倍率，數值取自
## Blender Root 骨骼滑行曲線實測（0.88/frame 指數衰減，非等速煞車）。
## 越接近 1.0 滑得越遠、越接近 0.5 停得越快。
@export_range(0.5, 0.99, 0.01) var pounce_slide_decay := 0.88

@export_group("Visual")
## 頭頂前搖光環。狼的動畫本身就讀得出前搖，預設關；除錯時可開。
@export var show_tell_ring := false

var posture: Node = null
var target: Node3D = null
var state: State = State.IDLE

var _timer := 0.0
var _attack: Attack = Attack.LUNGE
var _hit_this_strike := false
var _visual: Node3D = null
var _tell: MeshInstance3D = null
var _anim: AnimationPlayer = null
var _charge_dir := Vector3.ZERO
## 閃避
var _dodge_dir := Vector3.ZERO
var _dodge_cd := 0.0
## 上一幀玩家是否在攻擊 —— 用來抓「揮刀的那一瞬間」而不是整段攻擊
var _player_was_attacking := false
## 狼的網格根節點
var _wolf_mesh: Node3D = null
## 撲擊旋風特效：靜態管狀網格 + shader trim（見 wolf_vortex_fx.gd 註解）
var _vortex_root: Node3D = null
var _vortex_mats: Array = []
## 撲擊動畫經過秒數，驅動旋風 trim 曲線。-1 = 未在撲擊中。
var _pounce_t := -1.0
## 跑步風線：靜態管狀網格 + shader trim，16 幀循環（見 wolf_windstreak_fx.gd）
var _streak_root: Node3D = null
var _streak_mats: Array = []
## 跑步風線的循環計時器（一直累加，由 shader 端取模循環）
var _streak_t := 0.0
## 死亡溶解：換上的 shader 材質、光點粒子、經過秒數
var _dissolve_mats: Array = []
var _motes: GPUParticles3D = null
var _dissolve_t := -1.0
## 溶解掃描的底線，死亡當下鎖定（身體會上浮，底線不能跟著跑）
var _sweep_floor := INF


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
		# glTF 匯出/匯入沒有把循環旗標帶進來，Idle/Walk/Run 這三個要循環播放的
		# 動作在此手動強制設成 LOOP_LINEAR，其餘攻擊動作維持 LOOP_NONE（播一次）。
		for loop_anim in ["Wolf_Idle", "Wolf_Walk", "Wolf_Run"]:
			if _anim.has_animation(loop_anim):
				_anim.get_animation(loop_anim).loop_mode = Animation.LOOP_LINEAR
		_play("Wolf_Idle")
	if _visual != null:
		for c in _visual.get_children():
			if c is Node3D and String(c.name).begins_with("wolf"):
				_wolf_mesh = c
				break
		# 撲擊旋風：掛在 Visual 底下、與狼網格共用同一個變換（見 wolf_vortex_fx.gd
		# 的註解 —— 縮放與朝向寫在 wolf_pounce 子節點上，不是 Visual 上）。
		# 必須在 _wolf_mesh 找到之後才建。
		var fx: Dictionary = VortexFX.make(_visual, _wolf_mesh)
		_vortex_root = fx.get("root")
		_vortex_mats = fx.get("mats", [])
		# 跑步／撲擊風線，同樣共用狼網格的變換
		var sfx: Dictionary = WindStreakFX.make(_visual, _wolf_mesh)
		_streak_root = sfx.get("root")
		_streak_mats = sfx.get("mats", [])

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
	# ⚠ 只用 speed_scale 控速，play() 的 custom_speed 一律給 1.0。
	#   兩個都給會相乘（實際倍速 = speed_scale × custom_speed = speed²）。
	if _anim.current_animation == anim and _anim.is_playing():
		# ⚠ 同一段動畫換速度時不能直接 return —— 閃避是「Run 再加速」，
		#   早退會讓 dodge_anim_speed 永遠不生效（看起來跟一般跑步一樣）。
		if not is_equal_approx(_anim.speed_scale, speed):
			_anim.speed_scale = speed
		return
	_anim.speed_scale = speed
	_anim.play(anim, 0.18, 1.0)


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	_timer = 0.0
	state_changed.emit(s)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		# 死亡動畫是上浮化光點，不受重力；上浮位移烘在動畫的 Root 曲線裡
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
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_check_dodge()
	_tick_streaks(delta)

	match state:
		State.IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			_play("Wolf_Idle")
			if _target_distance() <= detect_range:
				_set_state(State.APPROACH)
		State.APPROACH:
			_chase(delta)
			_play("Wolf_Run", run_anim_speed)
			var d := _target_distance()
			if d > detect_range * 1.4:
				_set_state(State.IDLE)
			elif d <= attack_range and _timer >= attack_cooldown:
				_begin_windup()
			elif d >= pounce_min_range and d <= pounce_max_range \
					and _timer >= attack_cooldown and randf() < pounce_chance * delta * 4.0:
				# ⚠ 撲擊是「拉近距離」的招，發動帶在近身攻擊範圍之外。
				#   舊版把它跟近身招放在同一個 _begin_windup() 裡擲骰，條件
				#   （d <= attack_range 才進來，卻要求 d >= pounce_min_range）
				#   永不同時成立，撲擊整段是死碼、一次都沒發動過。
				_begin_pounce()
		State.WINDUP:
			_face_target(delta)
			velocity.x = 0.0
			velocity.z = 0.0
			var wind: float = lunge_windup
			if _attack == Attack.CLAW:
				wind = claw_windup
			elif _attack == Attack.POUNCE:
				# 撲擊前搖由動畫決定：起跳在 f30 = 1.25 s（24 fps）
				wind = 30.0 / 24.0
				# ⚠ _pounce_t 必須跟著撲擊動畫的播放時間走，從 WINDUP 就開始累加。
				#   只在 STRIKE 累加會讓 trim 曲線落後一整個前搖（1.25 s），
				#   結果旋風活躍區間（f30–61）還沒到就收招、整段特效不顯示。
				_pounce_t += delta
				VortexFX.tick(_vortex_root, _vortex_mats, _pounce_t, _visual_scale())
			if _timer >= wind:
				_begin_strike()
		State.STRIKE:
			if _attack == Attack.POUNCE:
				# 撲擊：推進交給腳本，旋風 trim 由 shader 逐幀重現。
				_pounce_t += delta
				VortexFX.tick(_vortex_root, _vortex_mats, _pounce_t, _visual_scale())
				velocity.x = _charge_dir.x * pounce_speed
				velocity.z = _charge_dir.z * pounce_speed
				if not _hit_this_strike:
					_do_strike()
				# ⚠ 不能用 not _anim.is_playing() 判定結束：WINDUP 已經播了
				#   1.25 s，動畫可能在 STRIKE 期間就播完，會提早跳出衝刺段。
				#   改用明確的衝刺秒數（對應動畫 f30–52）。
				if _timer >= pounce_dash_time:
					_set_state(State.RECOVER)
			elif _attack == Attack.LUNGE:
				# 原地動畫沒有 root motion：推進要自己給，否則狼在原地跑步。
				velocity.x = _charge_dir.x * lunge_speed
				velocity.z = _charge_dir.z * lunge_speed
				if not _hit_this_strike:
					_do_strike()
				if _timer >= lunge_dash_time:
					_set_state(State.RECOVER)
			else:
				velocity.x = 0.0
				velocity.z = 0.0
				if not _hit_this_strike:
					_do_strike()
				if _timer >= claw_strike_time:
					_set_state(State.RECOVER)
		State.RECOVER:
			if _attack == Attack.POUNCE:
				# 撲擊收招是滑行煞車，不是硬停——速度逐幀乘衰減率，
				# 跟 Blender Root 骨骼滑行曲線（0.88/frame @ 24fps）對齊，
				# 而非 LUNGE/CLAW 那種等速 move_toward 急煞。
				var decay: float = pow(pounce_slide_decay, delta * 24.0)
				velocity.x *= decay
				velocity.z *= decay
				if velocity.length() < 0.05:
					velocity.x = 0.0
					velocity.z = 0.0
				# 旋風在滑行段淡出（trim 曲線 f52–61 尾段），播完自動關掉
				if _pounce_t >= 0.0:
					_pounce_t += delta
					VortexFX.tick(_vortex_root, _vortex_mats, _pounce_t, _visual_scale())
					if _pounce_t > VortexFX.active_window().y:
						_end_pounce()
			else:
				velocity.x = move_toward(velocity.x, 0.0, 22.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, 22.0 * delta)
			_play("Wolf_Idle")
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
			_play("Wolf_Walk")
			_face_target(delta)
			if _timer >= 0.55:
				_set_state(State.APPROACH)
		State.DODGE:
			# 側躍：水平推進 + 一個小跳。動畫沒有 root motion，位移全靠這裡。
			velocity.x = _dodge_dir.x * dodge_speed
			velocity.z = _dodge_dir.z * dodge_speed
			_play("Wolf_Run", dodge_anim_speed)
			# 面向玩家，讓閃避看起來是「繞著打」而不是逃跑
			_face_target(delta)
			if _timer >= dodge_time:
				_set_state(State.APPROACH)
		State.BREAK:
			velocity.x = 0.0
			velocity.z = 0.0

	move_and_slide()


## 玩家揮刀的那一瞬間，決定要不要側躍閃開。
##
## 只在「上一幀沒攻擊、這一幀開始攻擊」時判定 —— 用整段 ATTACKING 判定的話，
## 一次揮刀會觸發數十幀，狼會連跳到天邊。
func _check_dodge() -> void:
	if not dodge_enabled or not is_instance_valid(target):
		_player_was_attacking = false
		return
	# ⚠ 不能寫 int(target.get(...))：目標沒有這個屬性時 get() 回 null，
	#   int(null) 會噴「Nonexistent 'int' constructor」每幀洗版。
	var st: Variant = target.get("action_state")
	var attacking: bool = st != null and int(st) == 1   # ActionState.ATTACKING
	var just_started := attacking and not _player_was_attacking
	_player_was_attacking = attacking
	if not just_started or _dodge_cd > 0.0:
		return
	# 這些狀態不能中斷：出招中、破綻中、死亡
	if state in [State.STRIKE, State.BREAK, State.DEAD, State.DODGE]:
		return
	if _target_distance() > dodge_react_range:
		return
	if randf() > dodge_chance:
		return
	_begin_dodge()


func _begin_dodge() -> void:
	# 前搖被自己的閃避打斷時要收乾淨（旋風不能留在場上）
	_end_pounce()
	if _tell:
		_tell.visible = false
	var to := _target_position() - global_position
	to.y = 0.0
	if to.length() < 0.01:
		to = -global_transform.basis.z
	to = to.normalized()
	# 側向為主、略微後退：純側移會繞圈，純後退會拉開距離變成放風箏
	var side := Vector3(-to.z, 0.0, to.x) * (1.0 if randf() < 0.5 else -1.0)
	_dodge_dir = (side * 0.85 - to * 0.35).normalized()
	_dodge_cd = dodge_cooldown
	_set_state(State.DODGE)
	if is_on_floor():
		velocity.y = dodge_hop


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
	# 近身二選一：突進咬擊／爪擊。撲擊走 _begin_pounce()，不在這裡擲骰。
	var roll := randf()
	if roll < claw_chance:
		_attack = Attack.CLAW
	else:
		_attack = Attack.LUNGE
	_hit_this_strike = false
	_set_state(State.WINDUP)
	match _attack:
		Attack.CLAW:
			_play("Wolf_Attack_Claw")
		_:
			_play("Wolf_Attack_Lunge")
	if _tell and show_tell_ring:
		_tell.visible = true
		var mat := _tell.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(1.0, 0.15, 0.1) if _attack == Attack.CLAW else Color(1.0, 0.95, 0.8)
			mat.emission = mat.albedo_color
	# 撲擊命中面較大、傷害較高，算危攻擊
	attack_windup.emit(_attack == Attack.POUNCE)


func _begin_pounce() -> void:
	# 撲擊：中距離發動的拉近招。前搖是動畫 f0–30（1.25 s 蓄力），
	# 衝刺 f30–52，落地滑行煞車 f52–84 由 RECOVER 的指數衰減接手。
	# 旋風活躍區間 f30–61，由 _pounce_t 驅動 shader trim。
	_attack = Attack.POUNCE
	_hit_this_strike = false
	_pounce_t = 0.0
	_set_state(State.WINDUP)
	_play("Wolf_Attack_Pounce")
	if _tell and show_tell_ring:
		_tell.visible = true
		var mat := _tell.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(1.0, 0.15, 0.1)
			mat.emission = mat.albedo_color
	attack_windup.emit(true)


func _begin_strike() -> void:
	_set_state(State.STRIKE)
	if _tell:
		_tell.visible = false
	if _attack == Attack.LUNGE or _attack == Attack.POUNCE:
		# 衝撞方向在出招瞬間鎖定：鎖定後玩家閃得開，才是可讀的攻擊。
		var to := _target_position() - global_position
		to.y = 0.0
		_charge_dir = to.normalized() if to.length() > 0.01 else -global_transform.basis.z


## 狼的視覺縮放（特效曲線是模型空間的公尺，要乘上去）
func _visual_scale() -> float:
	if _wolf_mesh != null:
		return _wolf_mesh.scale.y
	return 1.0


## 收掉撲擊旋風。所有中斷路徑（被打斷前搖、自己閃避、破防、死亡）都必須呼叫，
## 否則旋風會留在場上。
func _end_pounce() -> void:
	_pounce_t = -1.0
	VortexFX.stop(_vortex_root, _vortex_mats)


## 速度風線：撲擊時播撲擊版，否則依實際水平速度決定跑步版強度。
##
## 強度接速度而不是接狀態，是因為「看起來跑多快」才是風線該表達的東西 ——
## 綁狀態的話，BACKSTEP 慢走與 APPROACH 全速衝會噴一樣多的速度線。
func _tick_streaks(delta: float) -> void:
	if _streak_root == null:
		return
	# 撲擊期間走專用曲線（更誇張、一次性）
	if _attack == Attack.POUNCE and _pounce_t >= 0.0:
		WindStreakFX.tick_pounce(_streak_root, _streak_mats, _pounce_t)
		return

	var speed := Vector2(velocity.x, velocity.z).length()
	# ⚠ 強度區間的下界要低於 move_speed，否則正常追擊（速度 = move_speed）
	#   只會落在區間開頭、風線幾乎看不見（實測 intensity 只有 0.23）。
	#   設計意圖：走路（BACKSTEP，0.9×move_speed）微微帶線，
	#   全速追擊已經相當明顯，衝刺／撲擊才拉到滿。
	var strength := clampf(
		inverse_lerp(move_speed * 0.5, lunge_speed * 0.6, speed), 0.0, 1.0)
	# 讓中段更飽和：純線性會讓「跑步」這個最常見的狀態一直偏淡
	strength = sqrt(strength)
	if strength <= 0.01:
		_streak_t = 0.0
		WindStreakFX.stop(_streak_root, _streak_mats)
		return
	_streak_t += delta
	WindStreakFX.tick_run(_streak_root, _streak_mats, _streak_t, strength)


func _do_strike() -> void:
	# ⚠ 距離不夠時不可以鎖 _hit_this_strike —— 衝撞／撲擊在 STRIKE 的第一幀
	#   還沒衝到玩家面前，此時判定必定超出 reach。舊寫法在函式開頭就把旗標
	#   設 true，等於「衝刺還沒開始就判定落空、整段攻擊再也不會命中」。
	#   改成命中判定成功（或目標失效）才鎖旗標，讓衝刺途中每幀都能重試。
	var reach: float = attack_range * 1.3
	if _attack == Attack.POUNCE:
		reach = attack_range * 1.5

	if not is_instance_valid(target) or not target.has_method("take_hit"):
		_hit_this_strike = true
		return
	if _target_distance() > reach:
		return

	_hit_this_strike = true
	var claw := _attack == Attack.CLAW
	var damage := lunge_damage
	var pdmg := lunge_posture_damage
	if claw:
		damage = claw_damage
		pdmg = claw_posture_damage
	elif _attack == Attack.POUNCE:
		damage = pounce_damage
		pdmg = pounce_posture_damage
	attack_struck.emit(damage)

	var hit_dir := (_target_position() - global_position).normalized()
	var result: Variant = target.take_hit({
		"damage": damage,
		"posture_damage": pdmg,
		"perilous": _attack == Attack.POUNCE,
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

	# 打斷前搖：蓄力被打斷，玩家搶到節奏
	if state == State.WINDUP:
		_set_state(State.RECOVER)
		_end_pounce()
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
	_play("Wolf_Idle", 0.35)
	_end_pounce()
	if _tell:
		_tell.visible = false
	became_vulnerable.emit()


func _on_posture_recovered() -> void:
	if state == State.BREAK:
		_set_state(State.APPROACH)


## 死亡：Wolf_Death 是「中招 → 挺直抬頭 → 四腳離地緩緩浮空 72 cm」，不倒地。
## 上浮位移烘進動畫的 Root 曲線（in-place 例外），本腳本只餵溶解曲線。
func _on_died() -> void:
	_set_state(State.DEAD)
	velocity = Vector3.ZERO
	_end_pounce()
	WindStreakFX.stop(_streak_root, _streak_mats)
	_play("Wolf_Death")
	set_collision_layer_value(2, false)
	var col := get_node_or_null("CollisionShape3D")
	if col:
		# ⚠ 必須 set_deferred：_on_died() 是從 take_hit() → posture.apply_damage()
		#   一路同步呼叫下來的，此時物理引擎正在 flush queries，直接改 disabled
		#   會噴「Can't change this state while flushing queries」（實機日誌實證）。
		(col as CollisionShape3D).set_deferred("disabled", true)
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
	# ⚠ 掃描底部鎖在死亡當下的腳高。zmin 會隨上浮抬高，若拿它當底，
	#   溶解線的 0 點會跟著身體往上跑，進度看起來比曲線快。
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
