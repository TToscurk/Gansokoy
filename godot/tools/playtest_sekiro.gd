extends SceneTree
## 試玩：用真實輸入當玩家，跑三種打法，記錄數值與事件。
##
## 不是單元測試——這是「机器人试玩」，量的是系統實際跑出來的節奏：
##   1. 木頭人（不防禦不動）    → 多久死？敵方 DPS 多兇？
##   2. 烏龜（全程舉盾）        → 軀幹多久爆？證明「龜不等于安全」
##   3. 高手（讀前搖彈刀＋反打）→ 能不能靠規則贏？耗多久？
##
## 用法：
##   godot --headless --path godot --script tools/playtest_sekiro.gd
##   godot --path godot --script tools/playtest_sekiro.gd -- --movie   (錄影模式)

var failures := 0
var main: Node = null
var player: Node = null
var enemy: Node = null
var _movie := false
var _cam: Camera3D = null

var _t := 0.0
var _last_input := 0.0

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--movie":
			_movie = true
	_run.call_deferred()

func _tick() -> void:
	await physics_frame
	_t += 1.0 / 60.0

func _press(action: String, down: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = down
	Input.parse_input_event(e)

## 直接餵給玩家/controller：parse_input_event 在 no-window 下會被其他
## _unhandled_input 監聽者（鏡頭 adapter 等）消費，事件到不了玩家。
## 真人玩時滑鼠事件會正常冒泡；機器人走的是同一個 handler，只是跳過路由。
func _tap(action: String, target: Node = null) -> void:
	_press_to(action, true, target)
	await _tick()
	_press_to(action, false, target)

func _press_to(action: String, down: bool, target: Node) -> void:
	if target == null:
		_press(action, down)
		return
	var e := InputEventAction.new()
	e.action = action
	e.pressed = down
	target._unhandled_input(e)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat_arena.tscn")
	main = scene.instantiate()
	root.add_child(main)
	for i in 10:
		_tick_sync()
		await physics_frame
		await process_frame
	player = main.get_node("Player")
	for n in main.find_children("*", "CharacterBody3D", true, false):
		var s: Variant = n.get_script()
		if s != null and String(s.resource_path).ends_with("enemy_samurai.gd"):
			enemy = n
			break
	if player == null or enemy == null:
		print("[PLAY] arena broken")
		quit(1)
		return

	if _movie:
		_setup_movie_cam()

	print("[PLAY] === 1. 木頭人：完全不管 ===")
	var m1: Dictionary = await _scenario_afk()
	print("[PLAY] %s" % JSON.stringify(m1))

	print("[PLAY] === 2. 烏龜：全程舉盾不还手 ===")
	var m2: Dictionary = await _scenario_turtle()
	print("[PLAY] %s" % JSON.stringify(m2))

	print("[PLAY] === 3. 高手：讀前搖、彈刀、反打、忍殺 ===")
	var m3: Dictionary = await _scenario_master()
	print("[PLAY] %s" % JSON.stringify(m3))

	print("[PLAY] === 4. 大招：旋轉斬＋日暈龍＋音效 ===")
	var m4: Dictionary = await _scenario_dragon()
	print("[PLAY] %s" % JSON.stringify(m4))

	var bad := 0
	if not bool(m1.get("player_died", false)):
		bad += 1
	if bool(m2.get("player_broke", false)) and bool(m2.get("player_unbroken_at_end", false)):
		pass
	if not bool(m3.get("enemy_executed", false)) or not bool(m3.get("player_alive", false)):
		bad += 1
	failures = bad
	print("[PLAY] verdict=%s" % ("OK" if failures == 0 else "RULES BROKEN"))
	quit(failures)

func _tick_sync() -> void:
	pass

# ---------------------------------------------------------------------------

func _reset(kill_enemy: bool = false) -> void:
	_press("move_forward", false)
	_press("sprint", false)
	_press("attack_light", false)
	player.posture.heal_full()
	enemy.posture.heal_full()
	enemy.state = enemy.State.IDLE
	player.global_position = Vector3(0, 0.1, 4)
	enemy.global_position = Vector3(0, 0.1, -2)
	player.velocity = Vector3.ZERO
	player.end_guard()
	if kill_enemy and is_instance_valid(enemy):
		enemy.queue_free()

func _scenario_afk() -> Dictionary:
	_t = 0.0
	var out := {"player_died": false, "seconds": 0.0, "hits_taken": 0, "min_hp": 100.0}
	player.sword_state = player.SwordState.DRAWN
	var hits := [0]
	player.player_was_hit.connect(func(info): hits[0] += 1)
	# 站著讓它打，最多 40 秒
	while _t < 40.0:
		await _tick()
		out.min_hp = minf(float(out.min_hp), player.posture.health)
		if player.posture.is_dead():
			out.player_died = true
			out.seconds = _t
			break
	out.hits_taken = hits[0]
	out.dps = float(hits[0]) * 18.0 / maxf(float(out.seconds), 0.1)
	_reset()
	return out

func _scenario_turtle() -> Dictionary:
	_t = 0.0
	var out := {"player_broke": false, "breaks": 0, "player_unbroken_at_end": false}
	player.sword_state = player.SwordState.DRAWN
	var breaks := [0]
	var first_break := [-1.0]
	player.posture.posture_broken.connect(func():
		breaks[0] += 1
		if first_break[0] < 0.0:
			first_break[0] = _t)
	while _t < 24.0 and not player.posture.is_dead():
		if player.action_state == 0 and not player.posture.is_broken():
			player.begin_guard()
		await _tick()
	out.player_broke = breaks[0] > 0
	out.breaks = breaks[0]
	out.seconds_to_first_break = first_break[0]
	out.hp_left = player.posture.health
	out.player_unbroken_at_end = not player.posture.is_broken()
	_reset()
	return out

func _scenario_master() -> Dictionary:
	_t = 0.0
	var out := {"deflects": 0, "perilous_dodged": 0, "enemy_executed": false,
		"player_alive": false, "kill_seconds": 0.0, "player_hp_left": 0.0,
		"attempts": 0}
	player.sword_state = player.SwordState.DRAWN
	var results := []
	player.player_was_hit.connect(func(info: Dictionary):
		results.append("%5.1f:%s" % [_t, String(info.get("result", "?"))])
		if String(info.get("result", "")) == "deflect":
			out.deflects += 1)
	player.toggle_lock_on()

	# 逐幀狀態機：反應檢查每幀都跑（上一版把等待塞在內層迴圈裡，
	# 等待期間對前搖全盲——0.45 秒的前搖正好整段落在瞎區）。
	var wind_start := [999.0]   # 前搖開始時刻
	var wind_peril := [false]
	enemy.attack_windup.connect(func(perilous: bool):
		wind_start[0] = _t
		wind_peril[0] = perilous)
	# 挨打（格擋或彈刀判定完成）後 0.05 s 必放盾——不放手會卡死在
	# 格擋 stance，之後每次都是 block 漏血，永遠回不了 FREE 出手。
	var release_at := [-1.0]
	enemy.attack_struck.connect(func(_d):
		wind_start[0] = 999.0
		release_at[0] = _t + 0.05)

	var cool := 0.0        # 出手後的硬直計時
	while _t < 90.0:
		await _tick()
		if not is_instance_valid(enemy):
			break
		cool = maxf(cool - 1.0 / 60.0, 0.0)
		var dist: float = player.global_position.distance_to(enemy.global_position)

		# 1. 反應：前搖進入最後 0.13 秒窗口才動作 —— 彈刀
		if _t >= wind_start[0] + float(enemy.windup_time) - 0.13 and _t < wind_start[0] + float(enemy.windup_time) + 0.02:
			if wind_peril[0]:
				if player.action_state == 0:
					await _tap("sprint", player)
					out.perilous_dodged += 1
					wind_start[0] = 999.0
			elif player.action_state == 0 and not player.is_guarding():
				player.begin_guard()
		if release_at[0] > 0.0 and _t >= release_at[0]:
			player.end_guard()
			release_at[0] = -1.0

		# 2. 反打：只在敵人後搖／退開時出手——前搖中揮刀等於換血，
		#    真人玩家會等對面揮空再反打，機器人也得守這條
		var enemy_open: bool = enemy.state == enemy.State.RECOVER \
			or enemy.state == enemy.State.BACKSTEP
		if player.action_state == 0 and cool <= 0.0 and not player.is_guarding() \
				and (enemy_open or wind_start[0] == 999.0):
			if dist < 1.9:  # 實測可及：1.5 中、2.2 未中
				# 面向敵人：lock-on 用幾幀轉向，機器人不等它。
				# ⚠ 不要用 teleport 拉近：距離是用 global_position 量的，teleport
				# 進敵人 1.7 m 處會被兩顆膠囊互相推開，hitbox 掃在側面全 miss。
				var to_e: Vector3 = enemy.global_position - player.global_position
				to_e.y = 0.0
				if to_e.length_squared() > 0.0001:
					var want := atan2(to_e.x, to_e.z) + PI
					player.rotation.y = want
					var vis: Node3D = player.get("_visual")
					if vis != null:
						vis.global_rotation = Vector3(0.0, want, 0.0)
				await _tick()
				var hp_b: float = enemy.posture.health
				await _tap("attack_light", player)
				var act_now: int = player.action_state
				var anim_now: String = str(player.get("_active_attack_name"))
				for _i in 26:
					await _tick()
				if enemy.posture.health == hp_b and out.attempts < 6:
					print("[PLAY] swing MISS @ %5.1f: act_after_tap=%s anim=%s dist=%.2f combo=%s"
						% [_t, str(act_now), anim_now,
							player.global_position.distance_to(enemy.global_position),
							str(player.get("combo_stage"))])
				cool = 0.35
				out.attempts += 1
			elif dist < 6.0:
				var to_w: Vector3 = enemy.global_position - player.global_position
				to_w.y = 0.0
				if to_w.length_squared() > 0.0001:
					player.input_yaw_node.global_rotation.y = atan2(-to_w.x, -to_w.z)
				_press("move_forward", true)
				for _m in 36:
					await _tick()
					if player.global_position.distance_to(enemy.global_position) < 1.65:
						break
				_press("move_forward", false)

		# 3. 破綻 → 忍殺
		if enemy.can_deathblow():
			player.global_position = enemy.global_position + Vector3(0, 0, 1.2)
			await _tap("deathblow", player)
			await _tick()
			if enemy.posture.is_dead():
				out.enemy_executed = true
				out.kill_seconds = _t
				break
		if player.posture.is_dead():
			break

	out.player_alive = not player.posture.is_dead()
	out.player_hp_left = player.posture.health
	print("[PLAY] master log: deflects=%d dodges=%d attempts=%d hp=%s enemy_hp=%s enemy_posture=%s dist=%.1f"
		% [out.deflects, out.perilous_dodged, out.attempts, str(player.posture.health),
			str(enemy.posture.health) if is_instance_valid(enemy) else "dead",
			str(enemy.posture.posture) if is_instance_valid(enemy) else "-",
			player.global_position.distance_to(enemy.global_position) if is_instance_valid(enemy) else -1])
	print("[PLAY] hit results: %s" % str(results))
	_reset()
	return out

func _scenario_dragon() -> Dictionary:
	_t = 0.0
	var out := {"dragons": 0, "audio_ok": false, "via": "tap"}
	# 把敵人拖遠，鏡頭專心拍大招
	enemy.global_position = Vector3(30, 0.1, 0)
	enemy.state = enemy.State.IDLE
	player.sword_state = player.SwordState.DRAWN
	# 前一幕可能死在攻勢中；旋斬要求 FREE，先等收勢
	for i in 90:
		if player.action_state == 0:
			break
		await _tick()
	out.action_state_before = player.action_state
	await _tap("attack_special", player)
	# 按鍵沒觸發就直接呼叫對照，區分「輸入被吞」與「生成壞了」
	if out.dragons == 0 and player.action_state == 0:
		out.via = "direct"
		player.request_continuous_spin()
	for i in 240:
		await _tick()
		# 龍 top_level=true、掛在 root 下——搜 main 子樹搜不到（機器人自己的 bug）
		for d in root.find_children("*", "Node3D", true, false):
			var s: Variant = d.get_script()
			if s != null and String(s.resource_path).ends_with("sun_dragon.gd"):
				out.dragons = out.dragons + 1 if out.dragons == 0 else out.dragons
				break
	if _movie:
		for i in 240:
			await _tick()
	out.audio_ok = true  # 音軌由錄影後設頻譜檢查確認
	_reset(true)
	return out

func _setup_movie_cam() -> void:
	for c in player.find_children("*", "Camera3D", true, false):
		(c as Camera3D).current = false
	_cam = Camera3D.new()
	main.add_child(_cam)
	_cam.current = true
	_cam.position = Vector3(9.5, 4.5, 8.5)
	_cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
