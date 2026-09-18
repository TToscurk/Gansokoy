extends SceneTree
## RMB 長按蓄力拔刀斬：接線驗證（headless）。
##
## 執行：
##   godot --headless --path godot -s res://tools/verify_heavy_charge.gd
##
## 驗的是整條路：按下 → 舉刀凍住 → 蓄力特效 → 滿蓄放開才衝 → 衝刺煞停 → 落刀命中倍率 → 收乾淨。
##   1. 短按 = 原本聚力單斬（時長、判定、不留特效）
##   2. 按住 → 凍住（ts_upper 0、刀尖不動、判定關、特效開、進度單調遞增）
##   3. 未滿放開 → 解凍續播普通聚力單斬、傷害不加倍
##   4. 滿蓄（2 s）→ 仍按住 = 停在架勢不衝 → 放開 → 對武士衝刺、煞停在 stop_distance 前、武士真的掉 heavy×mult 的血、狀態回 FREE、材質／燈／粒子清空
##   5. 無敵人 → 沿面向衝 dash_no_target 公尺；木人樁擋在路上會被砍到（傷害倍率）
##   6. 蓄力中翻滾／input_locked／受擊／死亡 → 同幀清乾淨
##   7. 端點：heavy_charge_enabled=false → 按住也只是普通斬；dash_max=0 → 原地落刀
##   8. 真滑鼠事件（InputEventMouseButton button 2）經 Input.parse_input_event 也進蓄力

var fails := 0
var player: CharacterBody3D
var enemy: Node3D
var _released_target: Variant = null
var _progress_log: Array[float] = []
var _hit_count := 0


func _init() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		print("[HEAVY_CHARGE] FAIL watchdog timeout")
		quit(2))
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[HEAVY_CHARGE] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _seconds(s: float) -> void:
	await _frames(int(ceil(s * 60.0)))


func _flat_dist(a: Node3D, b: Node3D) -> float:
	var d := a.global_position - b.global_position
	d.y = 0.0
	return d.length()


func _place(pos: Vector3, yaw: float) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.global_rotation.y = 0.0          # 先歸零 root（鎖定會轉 root），再設 visual —— 反過來 visual 會被拖走
	player._visual.global_rotation.y = yaw


func _fx_clean() -> bool:
	var fx = player._charge_fx
	if fx == null:
		return false
	var mesh: MeshInstance3D = fx.sword_mesh
	var light: OmniLight3D = fx.get_node("ChargeLight")
	var sparks: GPUParticles3D = fx.get_node("PullSparks")
	return not fx.is_active() and not fx.visible and mesh.get_surface_override_material(0) == null \
		and is_zero_approx(light.light_energy) and not sparks.emitting


func _state_clean() -> bool:
	return player.action_state == 0 and not player._heavy_charging and not player._heavy_frozen \
		and player._iai_dash_remaining <= 0.0 and player._iai_unfreeze_in < 0.0 and not player._iai_charged \
		and not player._hitbox.monitoring \
		and is_equal_approx(float(player._tree.get("parameters/ts_upper/scale")), player.heavy_cut_speed)


func _wait_free(max_s: float) -> void:
	for i in int(max_s * 60.0):
		if player.action_state == 0:
			return
		await physics_frame


func _press() -> void:
	Input.action_press("attack_heavy")
	var ev := InputEventAction.new()
	ev.action = "attack_heavy"
	ev.pressed = true
	player._unhandled_input(ev)


func _release() -> void:
	Input.action_release("attack_heavy")


func _on_hitbox_body(b: Node) -> void:
	if b == enemy or b.get_parent() == enemy:
		_hit_count += 1


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	col.shape = box
	col.position.y = -0.5
	floor_body.add_child(col)
	root.add_child(floor_body)

	player = (load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene).instantiate()
	root.add_child(player)
	enemy = (load("res://characters/combat/enemy_samurai.tscn") as PackedScene).instantiate()
	root.add_child(enemy)
	await _frames(10)
	enemy.set_physics_process(false)   # 站樁：不走過來、不揮刀（script 保留，take_hit／posture 都在）
	enemy.posture.max_health = 1000.0
	enemy.posture.health = 1000.0
	player.sword_state = player.SwordState.DRAWN
	player._apply_sword_visibility()
	player.input_locked = false
	player.heavy_charge_changed.connect(func(t: float) -> void: _progress_log.append(t))
	player.heavy_charge_released.connect(func(t: Variant) -> void: _released_target = t)
	player._hitbox.body_entered.connect(_on_hitbox_body)
	await _frames(2)

	check("player grounded", player.is_on_floor())
	check("charge fx exists under sword", player._charge_fx != null and player._charge_fx.sword_mesh != null)
	var hand_scale: Vector3 = player._sword_hand.global_transform.basis.get_scale()
	check("Sword_Hand scale ≈ 1 (fx radius in metres) %s" % hand_scale, (hand_scale - Vector3.ONE).length() < 0.05)
	var section_len: float = player.attack_combo_resource.length * 0.34
	var heavy_real: float = section_len / player.heavy_cut_speed
	var heavy_dmg: float = player.heavy_attack_damage
	var charged_dmg: float = heavy_dmg * player.heavy_charge_damage_mult

	# --- 1. 短按 = 原本的聚力單斬 -------------------------------------------
	enemy.global_position = Vector3(40, 0.1, 40)
	_place(Vector3(0, 0.1, 30), PI)
	_press()
	check("tap: attack starts as Heavy_Cut", player.action_state == 1 and player._active_attack_name == "Heavy_Cut")
	check("tap: enters charging while held", player._heavy_charging)
	check("tap: hitbox off during raise", not player._hitbox.monitoring)
	await _frames(3)
	_release()
	await _frames(2)
	check("tap: released before freeze → charging off", not player._heavy_charging and not player._heavy_frozen)
	check("tap: hitbox back on", player._hitbox.monitoring)
	check("tap: action_real == heavy real (%.3f)" % player._action_real, is_equal_approx(player._action_real, heavy_real))
	check("tap: no fx started", _fx_clean())
	await _wait_free(2.0)
	check("tap: settles clean", _state_clean())

	# --- 2. 按住 → 切入居合架勢（full 層 iai_in → iai_hold）------------------
	var skel: Skeleton3D = player.find_children("*", "Skeleton3D", true, false)[0]
	var hips_idx := skel.find_bone("Hips")
	# 骨架空間是 Z-up（FBX 匯入慣例，Hips rest z≈0.99）——垂直在 .z 不是 .y。
	var hips_idle_y: float = skel.get_bone_global_pose(hips_idx).origin.z
	_progress_log.clear()
	_press()
	await _seconds(0.35)
	check("hold: stance entered by 0.35 s", player._heavy_frozen)
	check("hold: attack layer switched to full", player._attack_layer == "full")
	var full_state: String = String(player._tree.get("parameters/full_sel/current_state"))
	check("hold: full_sel in iai_in/iai_hold (%s)" % full_state, full_state == "iai_in" or full_state == "iai_hold")
	check("hold: full one-shot really playing (internal_active)", bool(player._tree.get("parameters/full/internal_active")))
	check("hold: charge fx active", player._charge_fx.is_active() and player._charge_fx.visible)
	check("hold: sword override material applied", player._charge_fx.sword_mesh.get_surface_override_material(0) != null)
	await _seconds(0.5)
	full_state = String(player._tree.get("parameters/full_sel/current_state"))
	check("hold: iai_in timed out into iai_hold loop (%s)" % full_state, full_state == "iai_hold")
	var hips_hold_y: float = skel.get_bone_global_pose(hips_idx).origin.z
	check("hold: crouched — hips %.3f below idle %.3f" % [hips_idle_y - hips_hold_y, hips_idle_y], hips_idle_y - hips_hold_y > 0.05)
	var tip0: Vector3 = player._blade_tip.global_position
	var pos0: Vector3 = player.global_position
	await _seconds(0.6)
	var tip_moved: float = (player._blade_tip.global_position - tip0).length()
	check("hold: blade tip steady in kamae over 0.6 s (moved %.3f m)" % tip_moved, tip_moved < 0.15)
	check("hold: body does not drift (%.3f m)" % (player.global_position - pos0).length(), (player.global_position - pos0).length() < 0.05)
	check("hold: hitbox off while holding stance", not player._hitbox.monitoring)
	var mono := true
	for i in range(1, _progress_log.size()):
		if _progress_log[i] < _progress_log[i - 1] - 0.0001:
			mono = false
	check("hold: progress monotonic (%d samples, last %.2f)" % [_progress_log.size(), _progress_log.back()], mono and _progress_log.back() > 0.5 and _progress_log.back() < 0.9)
	var light: OmniLight3D = player._charge_fx.get_node("ChargeLight")
	check("hold: light energy scales with progress (%.2f)" % light.light_energy, light.light_energy > 0.0 and light.light_energy < player._charge_fx.light_energy_max)
	var sparks: GPUParticles3D = player._charge_fx.get_node("PullSparks")
	var pm: ParticleProcessMaterial = sparks.process_material
	check("hold: sparks emitting and pulled inward (radial %.2f)" % pm.radial_velocity_max, sparks.emitting and pm.radial_velocity_max < 0.0)

	# --- 3. 未滿放開 → 淡掉架勢、重放普通聚力單斬 -----------------------------
	_release()
	await _frames(2)
	check("early release: stance exited", not player._heavy_frozen and not player._heavy_charging)
	check("early release: back on upper layer", player._attack_layer == "upper")
	check("early release: ts_upper back to heavy speed", is_equal_approx(float(player._tree.get("parameters/ts_upper/scale")), player.heavy_cut_speed))
	check("early release: not charged", not player._iai_charged)
	check("early release: hitbox on", player._hitbox.monitoring)
	check("early release: signal -1 emitted", _progress_log.back() < 0.0)
	await _seconds(0.3)
	check("early release: fx faded out", _fx_clean())
	await _wait_free(2.0)
	check("early release: settles clean", _state_clean())

	# --- 3b. 未滿放開貼著敵人：傷害是普通 heavy，不是倍率 ---------------------
	enemy.global_position = Vector3(0, 0.1, 28.6)
	_place(Vector3(0, 0.1, 30), PI)
	await _frames(2)
	var hp0: float = enemy.posture.health
	_press()
	await _seconds(0.6)
	_release()
	await _wait_free(2.0)
	var lost: float = hp0 - enemy.posture.health
	check("early release: enemy lost plain heavy damage (%.1f vs %.1f)" % [lost, heavy_dmg], is_equal_approx(lost, heavy_dmg))

	# --- 4. 滿蓄 → 放開才衝 → 煞停 → 落刀 ------------------------------------
	enemy.global_position = Vector3(0, 0.1, 24)
	enemy.posture.health = 1000.0
	_place(Vector3(0, 0.1, 30), PI)     # visual yaw PI = 面朝 -Z
	await _frames(2)
	var d0 := _flat_dist(player, enemy)
	check("full: setup distance 6 m (%.2f)" % d0, absf(d0 - 6.0) < 0.05)
	_released_target = null
	_hit_count = 0
	hp0 = enemy.posture.health
	_progress_log.clear()
	_press()
	await _seconds(2.3)
	check("full: charged by 2.3 s", player._heavy_charge_ready and player._heavy_charging)
	check("full: still held → no dash yet (auto_release off)", _released_target == null and not player._iai_charged and player._heavy_frozen)
	var pos_full := player.global_position
	await _seconds(0.4)
	check("full: holding past 2 s keeps the stance (drift %.3f m)" % (player.global_position - pos_full).length(), (player.global_position - pos_full).length() < 0.05)
	_release()
	await _frames(2)
	check("full: release fires the dash", player._iai_charged)
	await _seconds(0.6)
	var d1 := _flat_dist(player, enemy)
	check("full: stopped in front of enemy (%.2f m, stop %.2f)" % [d1, player.heavy_charge_stop_distance], absf(d1 - player.heavy_charge_stop_distance) < 0.35)
	check("full: heavy_charge_released emitted with samurai", _released_target == enemy)
	var fwd: Vector3 = player._visual.global_transform.basis.z
	var to: Vector3 = (enemy.global_position - player.global_position)
	to.y = 0.0
	check("full: facing enemy (dot %.2f)" % fwd.normalized().dot(to.normalized()), fwd.normalized().dot(to.normalized()) > 0.95)
	_release()
	await _wait_free(2.0)
	check("full: blade hitbox reached enemy body (%d)" % _hit_count, _hit_count >= 1)
	lost = hp0 - enemy.posture.health
	check("full: enemy lost heavy × mult (%.1f vs %.1f)" % [lost, charged_dmg], is_equal_approx(lost, charged_dmg))
	check("full: settles clean", _state_clean())
	check("full: ts_full restored to 1.0", is_equal_approx(float(player._tree.get("parameters/ts_full/scale")), 1.0))
	check("full: fx cleared", _fx_clean())
	var streaks := player.get_node_or_null("IaiDashStreaks")
	check("full: dash streaks stopped emitting", streaks == null or not (streaks as GPUParticles3D).emitting)
	await _seconds(0.6)
	check("full: dash streaks freed", player.get_node_or_null("IaiDashStreaks") == null)

	# --- 4b. 鎖定目標優先於最近敵人：面朝反方向也會轉身衝 --------------------
	enemy.global_position = Vector3(0, 0.1, 24)
	enemy.posture.health = 1000.0
	_place(Vector3(0, 0.1, 30), 0.0)    # 面朝 +Z（背對敵人）
	player.set_lock_target(enemy)
	await _frames(2)
	_press()
	await _seconds(3.8)
	_release()
	await _wait_free(2.0)
	d1 = _flat_dist(player, enemy)
	check("locked: turned around and closed in (%.2f m)" % d1, absf(d1 - player.heavy_charge_stop_distance) < 0.35)
	check("locked: enemy hit (%.1f)" % (1000.0 - enemy.posture.health), is_equal_approx(1000.0 - enemy.posture.health, charged_dmg))
	player.set_lock_target(null)
	check("locked: settles clean", _state_clean())

	# --- 5. 無敵人 → 沿面向衝 dash_no_target；木人樁在路上會被砍 ------------
	enemy.global_position = Vector3(60, 0.1, 60)   # 超出 lock_on_range 22 m
	var dummy := (load("res://characters/combat/training_dummy.tscn") as PackedScene).instantiate()
	root.add_child(dummy)
	dummy.global_position = Vector3(0.0, 0.0, 30.0 - player.heavy_charge_dash_no_target - 1.3)   # 正前方、衝刺終點前 1.3 m（木人樁 layer 3 會擋住玩家本體，不能放在路徑上）
	await _frames(2)
	_place(Vector3(0, 0.1, 30), PI)
	await _frames(2)
	var start := player.global_position
	var dummy_hp0: float = dummy.health
	_press()
	await _seconds(2.2)
	_release()
	await _seconds(0.6)   # 放開才衝：等衝刺（4 m ÷ 24 ≈ 0.17 s）與煞停結束
	var travelled := (player.global_position - start).length()
	check("no target: dashed ≈ %.1f m (%.2f)" % [player.heavy_charge_dash_no_target, travelled], absf(travelled - player.heavy_charge_dash_no_target) < 0.3)
	check("no target: went forward (-Z)", player.global_position.z < start.z - 3.0)
	await _wait_free(2.0)
	lost = dummy_hp0 - dummy.health
	check("no target: dummy in path took heavy × mult (%.1f vs %.1f)" % [lost, charged_dmg], is_equal_approx(lost, charged_dmg))
	check("no target: settles clean", _state_clean())
	dummy.queue_free()
	await _frames(2)

	# --- 6. 取消路徑 ----------------------------------------------------------
	# 6a 翻滾
	_place(Vector3(0, 0.1, 30), PI)
	_press()
	await _seconds(0.8)
	check("cancel/dodge: charging", player._heavy_frozen)
	player.request_dodge(Vector3.RIGHT)
	_release()
	check("cancel/dodge: became DODGING", player.action_state == 2)
	check("cancel/dodge: fx cleared same frame", _fx_clean())
	check("cancel/dodge: ts_upper restored", is_equal_approx(float(player._tree.get("parameters/ts_upper/scale")), player.heavy_cut_speed))
	await _wait_free(2.0)
	check("cancel/dodge: settles clean", _state_clean())
	# 6b input_locked
	_place(Vector3(0, 0.1, 30), PI)
	_press()
	await _seconds(0.8)
	player.input_locked = true
	_release()
	check("cancel/lock: attack finished", player.action_state == 0 and not player._heavy_charging)
	check("cancel/lock: fx cleared", _fx_clean())
	player.input_locked = false
	await _frames(5)
	check("cancel/lock: settles clean", _state_clean())
	# 6c 受擊
	_place(Vector3(0, 0.1, 30), PI)
	_press()
	await _seconds(0.8)
	var res: Dictionary = player.take_hit({"damage": 5.0, "posture_damage": 3.0, "hit_dir": Vector3(0, 0, -1), "hit_pos": player.global_position})
	_release()
	check("cancel/hit: result hit", res.get("result", "") == "hit")
	check("cancel/hit: charging cancelled", not player._heavy_charging and not player._heavy_frozen)
	check("cancel/hit: fx cleared", _fx_clean())
	await _seconds(1.0)
	check("cancel/hit: settles clean", _state_clean())
	# 6d 死亡中途
	_place(Vector3(0, 0.1, 30), PI)
	_press()
	await _seconds(0.8)
	player.posture.apply_damage(9999.0, 0.0)
	_release()
	check("cancel/death: charging cancelled", not player._heavy_charging and not player._heavy_frozen)
	check("cancel/death: fx cleared", _fx_clean())
	await _seconds(0.2)
	player.revive()
	player.sword_state = player.SwordState.DRAWN
	player._apply_sword_visibility()
	await _frames(5)
	check("cancel/death: revived clean", _state_clean())

	# 6e 蓄力中按格擋：不能架（會把凍住的舉刀換成凍住的架勢）
	_place(Vector3(0, 0.1, 30), PI)
	_press()
	await _seconds(0.8)
	player.begin_guard()
	check("cancel/guard: guard refused while charging", not player.is_guarding() and player._heavy_frozen)
	_release()
	await _wait_free(2.0)
	check("cancel/guard: settles clean", _state_clean())
	# 6f 敵人太遠（超過 dash_max）：不當目標，改沿面向衝 no_target
	enemy.global_position = Vector3(0, 0.1, 30.0 - 15.0)   # 15 m：在 lock 22 m 內、在 dash 8+1.3 m 外
	_place(Vector3(0, 0.1, 30), PI)
	start = player.global_position
	_released_target = null
	_press()
	await _seconds(2.2)
	_release()
	await _seconds(0.6)   # 放開才衝
	check("far enemy: not chosen as target", _released_target == null)
	check("far enemy: forward dash %.2f m" % (player.global_position - start).length(), absf((player.global_position - start).length() - player.heavy_charge_dash_no_target) < 0.3)
	await _wait_free(2.0)
	check("far enemy: settles clean", _state_clean())
	enemy.global_position = Vector3(60, 0.1, 60)

	# --- 7. 端點 ---------------------------------------------------------------
	player.heavy_charge_enabled = false
	_place(Vector3(0, 0.1, 30), PI)
	_press()
	await _seconds(0.6)
	check("disabled: hold is plain heavy cut", not player._heavy_charging and not player._heavy_frozen)
	_release()
	await _wait_free(2.0)
	check("disabled: settles clean", _state_clean())
	player.heavy_charge_enabled = true

	player.heavy_charge_dash_max = 0.0
	_place(Vector3(0, 0.1, 30), PI)
	start = player.global_position
	_press()
	await _seconds(2.2)
	_release()
	await _seconds(0.3)
	check("dash_max 0: no travel (%.2f m)" % (player.global_position - start).length(), (player.global_position - start).length() < 0.15)
	await _wait_free(2.0)
	check("dash_max 0: settles clean", _state_clean())
	player.heavy_charge_dash_max = 8.0

	# --- 8. 真滑鼠事件 --------------------------------------------------------
	# headless 下 Input.parse_input_event(InputEventMouseButton) 不會派到 _unhandled_input（實測），
	# 這裡只驗 InputMap：RMB 綁在 attack_heavy 上；派送路徑用 InputEventAction 走同一條 is_action_pressed 輪詢。
	var rmb_bound := false
	for e in InputMap.action_get_events("attack_heavy"):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT:
			rmb_bound = true
	check("mouse: attack_heavy bound to RMB in project.godot", rmb_bound)
	_place(Vector3(0, 0.1, 30), PI)
	var ia := InputEventAction.new()
	ia.action = "attack_heavy"
	ia.pressed = true
	Input.parse_input_event(ia)
	await _frames(3)
	check("mouse: parsed action press enters charge", player._heavy_charging)
	await _seconds(0.5)
	var ia_up := InputEventAction.new()
	ia_up.action = "attack_heavy"
	ia_up.pressed = false
	Input.parse_input_event(ia_up)
	await _frames(3)
	check("mouse: parsed action release resumes", not player._heavy_charging and not player._heavy_frozen)
	await _wait_free(2.0)
	check("mouse: settles clean", _state_clean())

	# --- 9. 收刀狀態按住 RMB：拔刀 → 直接進蓄力（真正的拔刀斬） -------------
	player.request_sword_toggle()
	await _wait_free(0.5)
	for i in 120:
		if player.sword_state == player.SwordState.SHEATHED:
			break
		await physics_frame
	check("sheathed: sword sheathed", player.sword_state == player.SwordState.SHEATHED)
	_place(Vector3(0, 0.1, 30), PI)
	_press()
	check("sheathed: RMB starts drawing", player.sword_state == player.SwordState.DRAWING)
	var entered := false
	for i in 90:
		await physics_frame
		if player._heavy_charging:
			entered = true
			break
	check("sheathed: draw flows into charge while held", entered and player.sword_state == player.SwordState.DRAWN)
	await _seconds(2.2)
	_release()
	await _wait_free(2.0)
	check("sheathed: settles clean", _state_clean())

	# --- 10. 端點：heavy_charge_auto_release=true → 滿蓄自己衝 ---------------
	enemy.global_position = Vector3(0, 0.1, 24)
	enemy.posture.health = 1000.0
	_place(Vector3(0, 0.1, 30), PI)
	await _frames(2)
	_released_target = null
	_hit_count = 0
	hp0 = enemy.posture.health
	player.heavy_charge_auto_release = true
	_press()
	await _seconds(2.4)
	check("auto: released without RMB release", _released_target == enemy or player._iai_charged)
	await _seconds(0.8)
	var d_auto := _flat_dist(player, enemy)
	check("auto: dashed to stop distance (%.2f m)" % d_auto, absf(d_auto - player.heavy_charge_stop_distance) < 0.35)
	_release()
	await _wait_free(2.0)
	check("auto: enemy took charged damage (%.1f vs %.1f)" % [hp0 - enemy.posture.health, charged_dmg], is_equal_approx(hp0 - enemy.posture.health, charged_dmg))
	check("auto: settles clean", _state_clean())
	player.heavy_charge_auto_release = false

	print("[HEAVY_CHARGE] %s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILED", fails])
	quit(0 if fails == 0 else 1)
