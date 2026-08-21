extends SceneTree
# Headless runtime validation for the AnimationTree-layered controller:
# run-draw/sheathe without stopping, run turns, split jump (fast start/fall/land),
# air inertia, moving & air attacks, roll 3.2m@3x, quick-draw, Form13 framework.
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

	func loco() -> StringName:
		return chr._playback().get_current_node()

	func recenter(start_z := 0.0) -> void:
		for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT]:
			key(k, false)
		chr.velocity = Vector3.ZERO
		chr.global_position = Vector3(0, 0.5, start_z)
		await wait(0.4)

	func _ready() -> void:
		run()

	func run() -> void:
		await wait(0.6)
		check("tree_active", chr._tree != null and chr._tree.active and loco() == &"Idle",
			"AnimationTree active, loco=%s" % loco())

		# --- 3/4. Run 中拔刀 / 收刀不停下（upper layer） ---
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.6)
		await tap(KEY_Q)
		await wait(0.2)
		var draw_speed_mid := hspeed()
		var drawing_loco := loco()
		await wait(0.6)
		var drawn: bool = chr.sword_state == chr.SwordState.DRAWN
		check("run_draw_no_stop", drawn and draw_speed_mid > 6.5 and drawing_loco == &"Run",
			"DRAWING 中 speed=%.2f loco=%s -> DRAWN=%s" % [draw_speed_mid, drawing_loco, drawn])
		await tap(KEY_Q)
		await wait(0.2)
		var sheathe_speed_mid := hspeed()
		await wait(0.6)
		check("run_sheathe_no_stop", chr.sword_state == chr.SwordState.SHEATHED and sheathe_speed_mid > 6.5,
			"SHEATHING 中 speed=%.2f -> state=%d" % [sheathe_speed_mid, chr.sword_state])
		await recenter()

		# --- 12. quick-draw：SHEATHED + LMB → 自動拔刀接第一段 ---
		click(MOUSE_BUTTON_LEFT)
		await wait(0.3)
		var qd_drawing: bool = chr.sword_state != chr.SwordState.SHEATHED
		var reached_attack := false
		var t := 0.0
		while t < 2.0:
			if chr.action_state == chr.ActionState.ATTACKING:
				reached_attack = true
				break
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		await wait_free(2.0)
		check("quick_draw_slash", qd_drawing and reached_attack and chr.sword_state == chr.SwordState.DRAWN,
			"LMB from SHEATHED -> draw -> auto Attack_1 (attack=%s)" % reached_attack)

		# --- keyboard attacks dead ---
		for c in [KEY_J, KEY_K, KEY_L]:
			await tap(c)
			await wait(0.08)
		check("keyboard_attacks_dead", chr.action_state == chr.ActionState.FREE, "J/K/L no-op")
		await recenter(8.0)   # 2x 攻速下 run-combo 全程 ~13 m，需要完整跑道

		# --- 11/13. LMB combo 3x + buffer；8. Run attack momentum ---
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.5)
		var t0 := Time.get_ticks_msec()
		click(MOUSE_BUTTON_LEFT)
		await wait(0.1)
		var ts_upper: float = chr._tree.get("parameters/ts_upper/scale")
		var run_atk_v := hspeed()
		var run_atk_loco := loco()
		click(MOUSE_BUTTON_LEFT)
		await wait(0.1)
		click(MOUSE_BUTTON_LEFT)
		var max_stage := 0
		t = 0.0
		while chr.action_state == chr.ActionState.ATTACKING and t < 5.0:
			max_stage = maxi(max_stage, chr.combo_stage)
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		var combo_secs := (Time.get_ticks_msec() - t0) / 1000.0
		check("combo_buffer_3hits", max_stage >= 3 and combo_secs < 2.0,
			"stage max=%d, %.2f s total" % [max_stage, combo_secs])
		check("attack_speed_scale", absf(ts_upper - chr.attack_speed_scale) < 0.01,
			"ts_upper=%.2f (export %.1f)" % [ts_upper, chr.attack_speed_scale])
		var run_expect: float = chr.run_speed * chr.attack_move_factor_run
		check("run_attack_momentum", absf(run_atk_v - run_expect) < 0.4 and run_atk_loco == &"Run",
			"run attack v=%.2f (expect %.2f), legs=%s" % [run_atk_v, run_expect, run_atk_loco])
		await wait(0.3)
		check("resume_run_after_attack", hspeed() > chr.run_speed - 0.3 and loco() == &"Run",
			"v=%.2f loco=%s" % [hspeed(), loco()])
		await recenter()

		# --- walk attack momentum ---
		key(KEY_W, true)
		await wait(0.4)
		click(MOUSE_BUTTON_LEFT)
		await wait(0.15)
		var walk_atk_v := hspeed()
		var walk_expect: float = chr.speed * chr.attack_move_factor_walk
		await wait_free(2.0)
		check("walk_attack_momentum", absf(walk_atk_v - walk_expect) < 0.3,
			"walk attack v=%.2f (expect %.2f)" % [walk_atk_v, walk_expect])
		await recenter()

		# --- RMB heavy = full-body spin at 3x ---
		click(MOUSE_BUTTON_RIGHT)
		await wait(0.1)
		var ts_full: float = chr._tree.get("parameters/ts_full/scale")
		var full_cur: StringName = chr._tree.get("parameters/full_sel/current_state")
		var rmb_ok: bool = chr.action_state == chr.ActionState.ATTACKING and chr._attack_layer == "full"
		await wait_free(3.0)
		check("rmb_heavy_spin", rmb_ok and full_cur == &"spin" and absf(ts_full - chr.attack_speed_scale) < 0.01,
			"layer=full anim=%s ts=%.2f" % [full_cur, ts_full])

		# --- 5. Run Turn ---
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.6)
		key(KEY_W, false)
		key(KEY_A, true)          # 90° 方向改變 → 應觸發 Turn 狀態
		var saw_turn: StringName = &""
		t = 0.0
		while t < 0.5:
			var n := loco()
			if n == &"TurnL" or n == &"TurnR":
				saw_turn = n
				break
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		await wait(0.5)
		var back_to_run := loco() == &"Run"
		check("run_turn", saw_turn != &"" and back_to_run,
			"90° input change -> %s -> back to %s" % [saw_turn, loco()])
		await recenter()

		# --- 6/7. Roll：3.2 m、0.422 s、跑步中發動、結束回 Run ---
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.5)
		key(KEY_SHIFT, false)     # 結束長按（>0.25 s，不觸發 roll）
		await wait(0.05)
		key(KEY_SHIFT, true)      # quick tap：0.05 s 內放開 → roll
		await wait(0.05)
		key(KEY_SHIFT, false)
		key(KEY_SHIFT, true)      # 再按住：roll 結束後維持 Run 輸入
		t = 0.0
		while chr.action_state != chr.ActionState.DODGING and t < 0.5:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		var rolling: bool = chr.action_state == chr.ActionState.DODGING
		var p0: Vector3 = chr.global_position   # roll 起始幀才記起點，避免混入跑步位移
		var roll_dur: float = chr._roll_duration
		t = 0.0
		while chr.action_state == chr.ActionState.DODGING and t < 3.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		var p1: Vector3 = chr.global_position
		var roll_dist := Vector2(p1.x - p0.x, p1.z - p0.z).length()
		await wait(0.4)
		var snap := (chr.global_position - p1).length()
		var after_loco := loco()
		check("roll_from_run", rolling and absf(roll_dur - chr.roll_anim_resource.length / 3.0) < 0.01,
			"rolling=%s dur=%.3f s" % [rolling, roll_dur])
		check("roll_half_distance", absf(roll_dist - chr.roll_distance) < 0.5,
			"moved %.2f m (target %.1f)" % [roll_dist, chr.roll_distance])
		check("roll_to_run_no_snap", after_loco == &"Run" and snap > 1.0,
			"post-roll loco=%s, kept running %.2f m (no snap-back)" % [after_loco, snap])
		await recenter(8.0)

		# --- 1/2. Jump：快起跳、apex 切 Fall、慣性、落地 ---
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.6)
		var run_v := hspeed()
		var jt0 := Time.get_ticks_msec()
		key(KEY_SPACE, true)
		key(KEY_SPACE, false)
		t = 0.0
		while chr.is_on_floor() and t < 1.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		var takeoff_secs := (Time.get_ticks_msec() - jt0) / 1000.0
		key(KEY_W, false)
		key(KEY_SHIFT, false)
		await wait(0.12)
		var airborne := not chr.is_on_floor()
		var coast_v := hspeed()
		var saw_fall := false
		t = 0.0
		while not chr.is_on_floor() and t < 1.5:
			if loco() == &"Fall" and chr.velocity.y < 0.0:
				saw_fall = true
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		await wait_free(1.0)
		check("jump_fast_start", takeoff_secs < 0.45,
			"Space -> takeoff %.2f s (clip 0.533 / %.1fx = %.2f)" % [takeoff_secs, chr.jump_start_speed, 0.533 / chr.jump_start_speed])
		check("jump_momentum", airborne and coast_v > run_v * 0.85,
			"run %.2f -> coast %.2f (W released)" % [run_v, coast_v])
		check("jump_fall_state", saw_fall, "loco entered Fall while descending")
		check("jump_lands", chr.is_on_floor() and chr.action_state == chr.ActionState.FREE, "landed FREE, loco=%s" % loco())
		await recenter(8.0)

		# --- 9/10. Air attack（Jump + LMB / Fall + LMB） ---
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.5)
		key(KEY_SPACE, true)
		key(KEY_SPACE, false)
		t = 0.0
		while chr.is_on_floor() and t < 1.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		await wait(0.05)
		var air_v := hspeed()
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
		t = 0.0
		while not chr.is_on_floor() and t < 2.0:   # FREE 可能發生在空中，等實際落地再驗
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		check("air_attack", air_atk and falling and kept_v > air_v * 0.8,
			"airborne ATTACKING=%s, gravity on=%s, h %.2f->%.2f" % [air_atk, falling, air_v, kept_v])
		check("air_attack_lands", chr.is_on_floor() and chr.action_state == chr.ActionState.FREE, "grounded FREE")
		await recenter()

		# --- 收刀 queue（攻擊中 Q） ---
		click(MOUSE_BUTTON_LEFT)
		await wait(0.1)
		await tap(KEY_Q)
		await wait(0.02)
		var queued: bool = chr.pending_sheathe
		await wait(1.5)
		var hand_vis: bool = chr._sword_hand.visible
		var sheath_vis: bool = chr._sword_sheathed.visible
		check("pending_sheathe", queued and chr.sword_state == chr.SwordState.SHEATHED and not hand_vis and sheath_vis,
			"queued=%s final=%d hand=%s sheath=%s" % [queued, chr.sword_state, hand_vis, sheath_vis])

		# --- Form13 框架：可用型循環、缺動畫型誠實跳過 ---
		await tap(KEY_Q)
		await wait(0.8)
		chr.form13_unlocked = true
		chr.sun_mastery = 99      # 測試框架時解除熟練度門檻（正式預設 0 = 初期只開 1/3 型）
		var started: bool = chr.start_form13()
		var forms_seen: Array[int] = []
		t = 0.0
		while t < 15.0 and (chr.action_state == chr.ActionState.ATTACKING or not chr._form13_queue.is_empty()):
			if chr.active_form > 0 and (forms_seen.is_empty() or forms_seen[-1] != chr.active_form):
				forms_seen.append(chr.active_form)
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		var missing: Array[int] = preload("res://sun_breathing.gd").missing_forms()
		var skipped_ok := true
		for id in forms_seen:
			if id in missing:
				skipped_ok = false
		check("form13_sequence", started and forms_seen.size() >= 5 and skipped_ok,
			"chained forms %s in %.1f s (missing slots %s skipped)" % [forms_seen, t, missing])

		# --- 8 向速度一致（input normalized，禁止斜向 √2） ---
		await recenter()
		var dir_speeds := PackedFloat32Array()
		for combo in [[KEY_W], [KEY_W, KEY_A], [KEY_W, KEY_D], [KEY_A], [KEY_D], [KEY_S], [KEY_S, KEY_A], [KEY_S, KEY_D]]:
			for k in combo:
				key(k, true)
			await wait(0.4)
			dir_speeds.append(hspeed())
			for k in combo:
				key(k, false)
			await wait(0.15)
		var speeds_ok := true
		for v in dir_speeds:
			if absf(v - chr.speed) > 0.15:
				speeds_ok = false
		check("eight_dir_speed_equal", speeds_ok, "8-dir speeds %s (target %.1f)" % [dir_speeds, chr.speed])
		await recenter()

		# --- FL / FR 側身跑姿：轉向瞬間出現、min-hold 防抖、回 Run ---
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.6)
		key(KEY_A, true)
		var fl_seen := false
		var switches := 0
		var prev: StringName = loco()
		t = 0.0
		while t < 0.6:
			var n := loco()
			if n == &"RunFL":
				fl_seen = true
			if n != prev:
				switches += 1
				prev = n
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		key(KEY_A, false)
		await wait(0.4)
		var fl_back := loco() == &"Run"
		key(KEY_W, false)
		key(KEY_SHIFT, false)
		check("run_fl_sector", fl_seen and switches <= 3 and fl_back,
			"RunFL seen=%s, %d state switches in 0.6 s (no flicker), back to %s" % [fl_seen, switches, loco()])
		await recenter()
		key(KEY_W, true)
		key(KEY_SHIFT, true)
		await wait(0.6)
		key(KEY_D, true)
		var fr_seen := false
		t = 0.0
		while t < 0.6:
			if loco() == &"RunFR":
				fr_seen = true
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		key(KEY_D, false)
		key(KEY_W, false)
		key(KEY_SHIFT, false)
		check("run_fr_sector", fr_seen, "RunFR seen=%s" % fr_seen)
		await recenter()

		# --- BackPedal（Walking 反播）：反向輸入的過渡期出現 ---
		key(KEY_W, true)
		await wait(0.5)
		key(KEY_W, false)
		key(KEY_S, true)
		var bp_seen := false
		t = 0.0
		while t < 0.6:
			if loco() == &"BackPedal":
				bp_seen = true
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		key(KEY_S, false)
		check("backpedal_state", bp_seen, "BackPedal (reversed Walking) seen=%s during direction flip" % bp_seen)
		await recenter()

		# --- Quick Draw Slash：離鞘瞬間（0.65）就接攻擊，不等 draw 播完 ---
		if chr.sword_state == chr.SwordState.DRAWN:
			await tap(KEY_Q)          # 先收刀，確保從 SHEATHED 測居合
			await wait(0.8)
		var qt0 := Time.get_ticks_msec()
		click(MOUSE_BUTTON_LEFT)
		t = 0.0
		while chr.action_state != chr.ActionState.ATTACKING and t < 1.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		var iai_secs := (Time.get_ticks_msec() - qt0) / 1000.0
		var draw_full: float = chr.draw_anim_resource.length / chr.draw_speed_scale
		await wait_free(2.0)
		check("iai_cancel_timing", iai_secs < draw_full and chr.sword_state == chr.SwordState.DRAWN,
			"attack at %.2f s < full draw %.2f s (cancel at t_unsheathe)" % [iai_secs, draw_full])

		# --- Dodge Counter：DRAWN 翻滾中 LMB → roll 結束自動反擊 ---
		key(KEY_SHIFT, true)
		await wait(0.05)
		key(KEY_SHIFT, false)
		await wait(0.1)
		var dc_rolling: bool = chr.action_state == chr.ActionState.DODGING
		click(MOUSE_BUTTON_LEFT)
		t = 0.0
		while chr.action_state == chr.ActionState.DODGING and t < 1.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		await wait(0.05)
		var dc_counter: bool = chr.action_state == chr.ActionState.ATTACKING and chr.combo_stage == 1
		await wait_free(2.0)
		check("dodge_counter", dc_rolling and dc_counter,
			"LMB during roll -> counter slash on finish (rolling=%s counter=%s)" % [dc_rolling, dc_counter])

		# --- 姿勢校正批次 ---
		await recenter()
		# Idle 腳趾貼地（修正前懸空 0.153）
		var sk: Skeleton3D = chr.find_children("*", "Skeleton3D", true, false)[0]
		var toe_sum := 0.0
		var samples := 0
		t = 0.0
		while t < 0.8:
			var lp := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftToeBase"))).origin.y
			var rp := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightToeBase"))).origin.y
			toe_sum += minf(lp, rp)
			samples += 1
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		var idle_toe := toe_sum / samples
		check("idle_feet_grounded", idle_toe < 0.07, "idle toe min avg %.3f (was 0.153, walk contact 0.027)" % idle_toe)
		# Idle→Walk→Run→Idle 轉換不上下跳：Hips 全域 y 每幀變化量
		var max_dy := 0.0
		var spike_info := ""
		var prev_y := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips"))).origin.y
		key(KEY_W, true)
		var shift_sent := false
		var released_sent := false
		t = 0.0
		while t < 2.0:
			if t > 0.7 and not shift_sent:
				shift_sent = true
				key(KEY_SHIFT, true)     # 只送一次；每幀重送會被判成 tap-roll
			if t > 1.4 and not released_sent:
				released_sent = true
				key(KEY_SHIFT, false)
				key(KEY_W, false)
			var hy := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips"))).origin.y
			if absf(hy - prev_y) > max_dy:
				max_dy = absf(hy - prev_y)
				spike_info = "t=%.2f loco=%s" % [t, loco()]
			prev_y = hy
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		check("transition_no_pop", max_dy < 0.05, "max per-frame hips dy %.3f m (%s)" % [max_dy, spike_info])
		await recenter()
		# Walk Turn（剝離位移版）
		key(KEY_W, true)
		await wait(0.6)
		key(KEY_W, false)
		key(KEY_A, true)
		var wt_seen: StringName = &""
		t = 0.0
		while t < 0.5:
			var n := loco()
			if n == &"WalkTurnL" or n == &"WalkTurnR":
				wt_seen = n
				break
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		key(KEY_A, false)
		check("walk_turn", wt_seen != &"", "walk 90° input change -> %s" % wt_seen)
		await recenter()
		# Draw 減速：SHEATHED→DRAWN 時長 ≈ 1.0 / draw_speed_scale
		if chr.sword_state == chr.SwordState.DRAWN:
			await tap(KEY_Q)
			await wait(1.0)
		var dt0 := Time.get_ticks_msec()
		await tap(KEY_Q)
		t = 0.0
		while chr.sword_state != chr.SwordState.DRAWN and t < 2.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		var draw_secs := (Time.get_ticks_msec() - dt0) / 1000.0
		var expect_draw: float = chr.draw_anim_resource.length / chr.draw_speed_scale
		check("draw_slower", absf(draw_secs - expect_draw) < 0.15,
			"draw took %.2f s (expect %.2f at %.1fx)" % [draw_secs, expect_draw, chr.draw_speed_scale])

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
