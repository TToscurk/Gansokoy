extends SceneTree
## Regression: sheathed attack intent survives drawing, without double input.

var fails := 0
var player: CharacterBody3D

func _init() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	print("[ACTION_LINKS] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func _run() -> void:
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	col.shape = box
	col.position.y = -0.5
	floor_body.add_child(col)
	root.add_child(floor_body)
	var packed := load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene
	player = packed.instantiate() as CharacterBody3D
	root.add_child(player)
	await _frames(10)
	_check("player grounded", player.is_on_floor())
	for action in ["attack_heavy", "attack_special", "attack_light"]:
		var evt := InputEventAction.new()
		evt.action = action
		evt.pressed = true
		player._unhandled_input(evt)
		_check(action + " begins draw", player.sword_state == 1)
		var started := false
		for i in 90:
			await physics_frame
			if player.action_state == 1:
				started = true
				break
		var expected := "Heavy_Cut" if action == "attack_heavy" else ("Attack_Continuous_Spin" if action == "attack_special" else "Attack_Combo")
		_check(action + " executes requested attack", started and player._active_attack_name == expected)
		_check(action + " sword visible at attack", started and player._sword_hand.visible and not player._sword_sheathed.visible)
		await _frames(180)
		_check(action + " settles cleanly", player.action_state == 0 and not player._hitbox.monitoring)
		if player.sword_state == 2:
			player.request_sword_toggle()
			await _frames(90)
		_check(action + " returns to sheath", player.sword_state == 0)
	player.request_draw()
	await _frames(90)
	for heavy in [false, true]:
		if heavy:
			player.request_heavy_cut()
		else:
			player.request_primary_attack()
		player.request_dodge(Vector3.RIGHT)
		_check("opening cannot dodge-cancel heavy=%s" % heavy, player.action_state == 1)
		# Sample the actual attack clock, not an assumed number of frames.
		for i in 90:
			if player._action_elapsed >= player._action_real * 0.60:
				break
			await physics_frame
		player.request_dodge(Vector3.RIGHT)
		_check("recovery dodge-cancel heavy=%s" % heavy, player.action_state == 2)
		_check("cancel disables attack hitbox heavy=%s" % heavy, not player._hitbox.monitoring)
		_check("cancel stops sword trail heavy=%s" % heavy, not player._sword_trail.is_emitting)
		if player.action_state == 2:
			player.request_primary_attack()
			var counter_started := false
			for i in 90:
				await physics_frame
				if player.action_state == 1:
					counter_started = true
					break
			_check("dodge links to counter heavy=%s" % heavy, counter_started and player.combo_stage == 1)
		await _frames(120)
	# Export endpoints: zero cancels immediately; one waits for the full attack.
	for threshold in [0.0, 0.45, 1.0]:
		player.attack_dodge_cancel_start = threshold
		player.request_heavy_cut()
		player._action_elapsed = player._action_real * maxf(threshold - 0.01, 0.0)
		if threshold > 0.0:
			player.request_dodge()
			_check("threshold %.2f rejects earlier input" % threshold, player.action_state == 1)
		player._action_elapsed = player._action_real * threshold
		var shift := InputEventAction.new()
		shift.action = "sprint"
		shift.pressed = true
		player._unhandled_input(shift)
		shift.pressed = false
		player._unhandled_input(shift)
		_check("threshold %.2f accepts Shift tap at boundary" % threshold, player.action_state == 2)
		await _frames(120)
	player.attack_dodge_cancel_start = 0.45
	player.attack_dodge_cancel_enabled = false
	player.request_heavy_cut()
	player._action_elapsed = player._action_real * 0.8
	player.request_dodge()
	_check("disabled toggle retains attack", player.action_state == 1)
	await _frames(120)
	player.attack_dodge_cancel_enabled = true
	player.request_heavy_cut()
	player._action_elapsed = player._action_real * 0.6
	player.request_sword_toggle()
	player.request_dodge()
	_check("dodge supersedes pending sheath", player.action_state == 2 and not player.pending_sheathe and player.sword_state == 2)
	await _frames(120)
	player.request_jump()
	await _frames(15)
	_check("airborne setup", not player.is_on_floor())
	player.request_heavy_cut()
	player._action_elapsed = player._action_real * 0.6
	player.request_dodge()
	_check("air dodge does not cancel attack", player.action_state == 1 and player._hitbox.monitoring)
	await _frames(120)
	player.request_sword_toggle()
	await _frames(90)
	player.request_draw()
	player.request_continuous_spin()
	player.request_heavy_cut()
	var replacement_started := false
	for i in 90:
		await physics_frame
		if player.action_state == 1:
			replacement_started = true
			break
	_check("latest input during draw wins", replacement_started and player._active_attack_name == "Heavy_Cut")
	await _frames(180)
	_check("replaced draw input never fires later", player.action_state == 0 and not player._attack_after_draw)
	print("[ACTION_LINKS] failures=%d" % fails)
	player.free()
	floor_body.free()
	quit(fails)
