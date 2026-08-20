extends SceneTree
# Headless runtime validation for the mouse-combat controller rev:
# keyboard attacks dead, LMB combo / RMB spin at 3x, Shift-tap roll at 3x,
# Space jump with air inertia, moving/air attacks, Q draw/sheathe toggle.
# Injects real events via Input.parse_input_event.

class Driver extends Node:
	var chr: CharacterBody3D
	var results := PackedStringArray()

	func check(label: String, ok: bool, detail: String) -> void:
		results.append("%s %s: %s" % ["PASS" if ok else "FAIL", label, detail])

	func key(code: Key, pressed: bool) -> void:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)

	func tap(code: Key) -> void:
		key(code, true)
		await wait(0.05)
		key(code, false)

	func click(btn: MouseButton) -> void:
		var ev := InputEventMouseButton.new()
		ev.button_index = btn
		ev.pressed = true
		Input.parse_input_event(ev)
		var up := InputEventMouseButton.new()
		up.button_index = btn
		up.pressed = false
		Input.parse_input_event(up)

	func wait(s: float) -> void:
		await get_tree().create_timer(s).timeout

	func wait_free(timeout: float) -> float:
		var t := 0.0
		while chr.action_state != chr.ActionState.FREE and t < timeout:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		return t

	func hspeed() -> float:
		return Vector2(chr.velocity.x, chr.velocity.z).length()

	## 各段測試間把角色移回測試地板中心，避免累積位移走出 20 m 地板邊緣。
	func recenter(start_z := 0.0) -> void:
		chr.velocity = Vector3.ZERO
		chr.global_position = Vector3(0, 0.5, start_z)
		await wait(0.3)

	func _ready() -> void:
		run()

	func run() -> void:
		await wait(0.6)

		# --- A. keyboard attacks dead (need DRAWN first so they would fire) ---
		await tap(KEY_Q)
		await wait(1.4)
		check("draw_toggle_Q", chr.sword_state == chr.SwordState.DRAWN, "Q -> DRAWN")
		for c in [KEY_J, KEY_K, KEY_L]:
			await tap(c)
			await wait(0.1)
		check("keyboard_attacks_dead", chr.action_state == chr.ActionState.FREE,
			"J/K/L pressed, state stayed FREE")

		# --- B/C. LMB combo at 3x with buffer ---
		var t0 := Time.get_ticks_msec()
		click(MOUSE_BUTTON_LEFT)
		await wait(0.1)
		var stage1: int = chr.combo_stage
		var spd: float = chr._anim.get_playing_speed()
		click(MOUSE_BUTTON_LEFT)
		await wait(0.12)
		click(MOUSE_BUTTON_LEFT)
		var max_stage := 0
		while chr.action_state == chr.ActionState.ATTACKING:
			max_stage = maxi(max_stage, chr.combo_stage)
			await get_tree().physics_frame
		var combo_secs := (Time.get_ticks_msec() - t0) / 1000.0
		check("lmb_combo", stage1 == 1 and max_stage >= 3, "stage1=%d max=%d" % [stage1, max_stage])
		check("attack_speed_3x", absf(spd - 3.0) < 0.01, "playing speed %.2f" % spd)
		check("combo_duration", combo_secs < 2.5, "3-hit combo %.2f s" % combo_secs)

		# --- B2. RMB spin ---
		await wait(0.3)
		click(MOUSE_BUTTON_RIGHT)
		await wait(0.1)
		var rmb_ok: bool = chr.action_state == chr.ActionState.ATTACKING and chr._action_anim == chr.attack_spin_anim
		var rmb_spd: float = chr._anim.get_playing_speed()
		check("rmb_spin", rmb_ok and absf(rmb_spd - 3.0) < 0.01,
			"anim=%s speed=%.2f" % [chr._action_anim, rmb_spd])
		await wait_free(4.0)

		# --- F. moving attack: hold W, LMB, keep velocity * factor, resume walk ---
		key(KEY_W, true)
		await wait(0.4)
		var walk_v := hspeed()
		click(MOUSE_BUTTON_LEFT)
		await wait(0.15)
		var atk_v := hspeed()
		var expect: float = chr.speed * chr.attack_move_factor
		check("moving_attack_velocity", absf(atk_v - expect) < 0.3,
			"walk %.2f -> attack %.2f (expect %.2f)" % [walk_v, atk_v, expect])
		await wait_free(3.0)
		await wait(0.3)
		check("resume_walk_after_attack", hspeed() > chr.speed - 0.3 and chr._current == chr.walk_anim,
			"v=%.2f anim=%s" % [hspeed(), chr._current])
		key(KEY_W, false)
		await wait(0.4)

		await recenter()

		# --- D. Shift-tap roll: 3x speed, displacement synced, no snap back ---
		var p0: Vector3 = chr.global_position
		key(KEY_W, true)
		await wait(0.1)
		key(KEY_W, false)
		key(KEY_SHIFT, true)
		await wait(0.06)
		key(KEY_SHIFT, false)
		await wait(0.1)
		var rolling: bool = chr.action_state == chr.ActionState.DODGING
		var roll_spd: float = chr._anim.get_playing_speed()
		var roll_dur: float = chr._roll_duration
		var rt := 0.0
		while chr.action_state == chr.ActionState.DODGING:
			await get_tree().physics_frame
			rt += get_physics_process_delta_time()
		var p1: Vector3 = chr.global_position
		await wait(0.3)
		var snap := (chr.global_position - p1).length()
		var dist := Vector2(p1.x - p0.x, p1.z - p0.z).length()
		check("shift_tap_rolls", rolling and absf(roll_spd - 3.0) < 0.01,
			"DODGING=%s speed=%.2f" % [rolling, roll_spd])
		check("roll_3x_sync", absf(roll_dur - 1.2667 / 3.0) < 0.01 and rt < roll_dur + 0.15,
			"duration %.3f s (target 0.422), state ended at %.3f s" % [roll_dur, rt])
		check("roll_distance_no_snap", absf(dist - chr.roll_distance) < 0.6 and snap < 0.05,
			"moved %.2f m, post drift %.3f m" % [dist, snap])

		await recenter(8.0)   # 疾跑起跳全程 ~12 m，往 -Z 需要完整跑道

		# --- E. jump inertia: run-jump, release W in air, then counter-steer A ---
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.6)
		var run_v := hspeed()
		key(KEY_SPACE, true)
		key(KEY_SPACE, false)
		# 對「實際離地」對時，避免固定秒數與起跳時刻的競態。
		var t_air := 0.0
		while chr.is_on_floor() and t_air < 1.5:
			await get_tree().physics_frame
			t_air += get_physics_process_delta_time()
		key(KEY_W, false)
		key(KEY_SHIFT, false)
		await wait(0.12)
		var airborne_at_coast := not chr.is_on_floor()
		var coast_v := hspeed()
		var vx0: float = chr.velocity.x
		key(KEY_A, true)
		var steer_t := 0.0
		while not chr.is_on_floor() and steer_t < 0.2:
			await get_tree().physics_frame
			steer_t += get_physics_process_delta_time()
		var steer_dx: float = absf(chr.velocity.x - vx0)
		key(KEY_A, false)
		check("jump_inertia_coast", airborne_at_coast and coast_v > run_v * 0.85,
			"run %.2f -> air (W released) %.2f, airborne=%s" % [run_v, coast_v, airborne_at_coast])
		check("air_steer_gradual", steer_dx > 0.02 and steer_dx < 1.0,
			"%.2f s of A gave dvx %.2f m/s (accel %.2f m/s²)" % [steer_t, steer_dx, chr.air_acceleration * chr.air_control])
		await wait_free(3.0)
		check("jump_lands", chr.is_on_floor() and chr.action_state == chr.ActionState.FREE, "landed, FREE")
		await wait(0.3)

		await recenter(8.0)

		# --- G. air attack: gravity on, inertia kept, no hover ---
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.6)
		key(KEY_SPACE, true)
		key(KEY_SPACE, false)
		await wait(chr.jump_takeoff_time + 0.12)
		var air_v := hspeed()
		var y_at_click: float = chr.global_position.y
		click(MOUSE_BUTTON_LEFT)
		await wait(0.1)
		var air_atk: bool = chr.action_state == chr.ActionState.ATTACKING and not chr.is_on_floor()
		var vy: float = chr.velocity.y
		await wait(0.15)
		var falling := chr.velocity.y < vy or chr.is_on_floor()
		var kept_v := hspeed()
		key(KEY_W, false)
		key(KEY_SHIFT, false)
		await wait_free(4.0)
		check("air_attack", air_atk, "ATTACKING while airborne at y=%.2f" % y_at_click)
		check("air_attack_gravity", falling, "vy kept integrating (%.2f -> %.2f)" % [vy, chr.velocity.y])
		check("air_attack_inertia", kept_v > air_v * 0.8, "h speed %.2f -> %.2f during air attack" % [air_v, kept_v])
		check("air_attack_lands", chr.is_on_floor() and chr.action_state == chr.ActionState.FREE, "grounded, FREE")
		await wait(0.3)

		await recenter()

		# --- H. sheathe: Q toggle + pending during attack ---
		await tap(KEY_Q)
		await wait(0.3)
		var sheathing: bool = chr.sword_state == chr.SwordState.SHEATHING
		await wait(1.2)
		var hand_vis: bool = chr._sword_hand.visible
		var sheath_vis: bool = chr._sword_sheathed.visible
		check("q_sheathe", sheathing and chr.sword_state == chr.SwordState.SHEATHED,
			"SHEATHING seen=%s final=%d" % [sheathing, chr.sword_state])
		check("sheathe_sockets", not hand_vis and sheath_vis, "hand=%s sheath=%s" % [hand_vis, sheath_vis])
		await tap(KEY_Q)
		await wait(1.4)
		click(MOUSE_BUTTON_LEFT)
		await wait(0.1)
		await tap(KEY_Q)
		await wait(0.05)
		var queued: bool = chr.pending_sheathe and chr.action_state == chr.ActionState.ATTACKING
		await wait(2.0)
		check("pending_sheathe", queued and chr.sword_state == chr.SwordState.SHEATHED,
			"queued during attack=%s, final state=%d" % [queued, chr.sword_state])

		print("=== VALIDATION RESULTS ===")
		for r in results:
			print(r)
		get_tree().quit()

func _initialize():
	var level = (load("res://yoriichi_test.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var d := Driver.new()
	d.chr = level.get_node("Yoriichi")
	root.add_child(d)
