extends SceneTree
## Headless physics integration, no resource/scene writes. Same candidate as the capture harness.
## --headless --fixed-fps 60 --path godot -s res://tools/yoriichi_r7/test_r7_air.gd -- [scenario] [legacy_id]
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"
const IDS := [10, 4, 5, 7]
const SCENARIOS := ["ground", "air", "high_air", "hitinterrupt", "early", "late", "never", "wall", "ceiling", "repeat", "hitstop", "wait_hit", "gates", "inputs", "cancel", "regression", "takeoff_hitstop", "takeoff_hit", "lost_floor", "jump_lock", "hold_timeout", "buffer_expire", "followup", "dodge_cancel", "same_tick", "damage", "zero_stun_hit", "priority", "stagger", "death"]
var _failures: Array = []
var _results: Array = []
var _world: Node3D
var _p: CharacterBody3D
var _floor: StaticBody3D
var _scenario := ""
var _id := 0
var _case: Dictionary
var _wall_dir := Vector3.FORWARD

class Receiver extends Node3D:
	var hits := 0
	func take_hit(data: Dictionary) -> Dictionary:
		hits += 1
		return {"result": "hit", "damage": data.damage, "attacker_posture": 0.0}

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	_case.checks.append({"ok": ok, "label": label})
	if not ok:
		_failures.append("%s/%d: %s" % [_scenario, _id, label])
		push_error("FAIL %s/%d: %s" % [_scenario, _id, label])

func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	_world.add_child(body)
	return body

func _snapshot() -> Dictionary:
	return {"t": _p.get("_action_elapsed"), "phase": _p.get("r7_air_phase"), "y": _p.position.y,
		"x": _p.position.x, "z": _p.position.z, "vy": _p.velocity.y, "floor": _p.is_on_floor(),
		"hit": _p.get("r7_hit_group"), "form": _p.get("active_form"), "exit": _p.get("r7_air_exit"),
		"ts": _p.get("_tree").get("parameters/ts_full/scale"), "used": _p.get("_r7_air_used")}

func _setup() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_floor = _box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	_p = (load(PLAYER) as PackedScene).instantiate()
	_p.set("r7_vfx_enabled", false)
	_p.set("sun_mastery", 100)
	_p.set("sun_breath_gauge", 100.0)
	_world.add_child(_p)
	_p.set_physics_process(false)
	await process_frame
	_p.set_process_unhandled_input(false)
	_p.set_physics_process(true)
	for i in 12:
		await physics_frame
	_p.call("request_draw")
	for i in 100:
		await physics_frame
	_check(_p.is_on_floor() and int(_p.get("sword_state")) == 2, "candidate ready, drawn and grounded")
	var a: Animation = _p.get("_anim").get_animation(_p.get("R7_FORMS")[_id].anim)
	_check(a != null, "authored resource installed")
	if a != null:
		_case.metadata = {}
		for k in a.get_meta_list():
			if String(k).begins_with("r7_") and k not in [&"r7_root_fwd", &"r7_root_side"]:
				_case.metadata[k] = a.get_meta(k)
		_case.tracks = a.get_track_count()
	var count: int = (_p.get("_tree").tree_root.get_node("full_sel") as AnimationNodeTransition).input_count
	_p.call("r7_install_air_forms")
	_check(count == (_p.get("_tree").tree_root.get_node("full_sel") as AnimationNodeTransition).input_count, "idempotent install")

func _run_case() -> void:
	_case = {"scenario": _scenario, "id": _id, "checks": [], "trace": []}
	await _setup()
	if _scenario in ["air", "high_air", "inputs", "hold_timeout"]:
		_p.position.y = 200.0 if _scenario == "hold_timeout" else (8.0 if _scenario == "high_air" else 0.65)
		_p.velocity.y = -1.0
		await physics_frame
		await physics_frame
		_check(not _p.is_on_floor(), "air start has no ground contact")
	if _scenario == "ceiling":
		_box(Vector3(0, 2.25, 0), Vector3(20, 0.2, 20))
	if _scenario == "wall":
		# Put the wall across this form's actual path, including REF09's predominantly lateral travel.
		var clip: Animation = _p.get("_anim").get_animation(_p.get("R7_FORMS")[_id].anim)
		var fwd := PackedFloat32Array(clip.get_meta("r7_root_fwd"))
		var side := PackedFloat32Array(clip.get_meta("r7_root_side"))
		var visual: Node3D = _p.get("_visual")
		_wall_dir = visual.global_basis.z * fwd[-1]
		if not side.is_empty():
			_wall_dir -= visual.global_basis.x * side[-1]
		_wall_dir.y = 0.0
		_wall_dir = _wall_dir.normalized()
		var wall := _box(_wall_dir * 0.75 + Vector3.UP * 2.0, Vector3(10, 6, 0.2))
		wall.rotation.y = atan2(_wall_dir.x, _wall_dir.z)
		await physics_frame
		await physics_frame
	if _scenario == "gates":
		for field in ["_hitstun_left", "_stagger_left", "_deathblow_left", "_dead_left", "_trick_left", "_guard_held", "input_locked"]:
			var old = _p.get(field)
			_p.set(field, true if old is bool else 0.5)
			_check(not _p.call("execute_form", _id, true), "reject gate " + field)
			_p.set(field, old)
		_p.set("action_state", 2)
		_check(not _p.call("execute_form", _id, true), "reject dodging")
		_p.set("action_state", 0)
	elif _scenario == "regression":
		for fid in [1, 8, 12, 3, 6, 9, 2, 11, 101]:
			_check(_p.call("execute_form", fid, true), "existing form starts %d" % fid)
			for i in 160:
				await physics_frame
			_check(int(_p.get("active_form")) == 0, "existing form ends %d" % fid)
		_p.call("request_primary_attack")
		_check(int(_p.get("combo_stage")) == 1 and int(_p.get("active_form")) == 0, "ground light unchanged")
		for i in 60:
			await physics_frame
		_p.call("request_primary_attack")
		for i in 15:
			await physics_frame
		_p.call("request_primary_attack")
		for i in 20:
			await physics_frame
		_case.branch_stage = _p.get("combo_stage")
		if int(_p.get("combo_stage")) != 2:
			_p.call("_advance_combo")
		_check(int(_p.get("combo_stage")) == 2, "stage2 light branch setup")
		_p.call("request_heavy_cut")
		for i in 30:
			await physics_frame
		_check(int(_p.get("active_form")) == 5, "REF09 accessible through stage2 RMB")
		_p.call("_finish_attack")
		for i in 100:
			await physics_frame
		_p.get("_form_cooldowns").clear()
	if _scenario == "inputs":
		var action: String = {10: "attack_light", 4: "attack_heavy", 7: "attack_special", 5: ""}[_id]
		if action != "":
			var e := InputEventAction.new()
			e.action = action
			e.pressed = true
			_p.set_process_unhandled_input(true)
			# Headless Window 沒有 OS focus；直接推進相同 Viewport event 傳遞。
			root.push_input(e, true)
			_p.set_process_unhandled_input(false)
			_check(int(_p.get("active_form")) == _id, "air input routes to aerial form")
		else:
			_check(_p.call("execute_form", _id, true), "REF09 explicit route")
	else:
		_check(_p.call("execute_form", _id, true), "execute_form accepted")
	var receiver: Receiver = null
	if _scenario == "damage":
		receiver = Receiver.new()
		_world.add_child(receiver)
		var area := Area3D.new()
		area.collision_layer = _p.get("_hitbox").collision_mask
		area.collision_mask = 0
		receiver.add_child(area)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(12, 12, 12)
		cs.shape = shape
		area.add_child(cs)
	var ik = _p.get("_r62_ik")
	var sock: Transform3D = ik.sock_new
	_check(ik.right_weight == 0.0 and not ik.left_enabled, "authored arms, both grip IK disabled")
	if _scenario in ["air", "high_air", "inputs", "hold_timeout"]:
		var a: Animation = _p.get("_anim").get_animation(_p.get("R7_FORMS")[_id].anim)
		_check(is_equal_approx(float(_p.get("_action_elapsed")) * 60.0, float(a.get_meta("r7_air_start_frame"))), "air clock starts at metadata offset")
	var phases: Array = []
	var peak := _p.position.y
	var injected := false
	var held_t := -1.0
	var held_y := 0.0
	var wait_samples := 0
	var hit_groups: Array = []
	var start_y := _p.position.y
	var previous_phase := -1
	var saw_air := not _p.is_on_floor()
	var base_jump_v: float = _p.get("jump_velocity")
	var max_vy := 0.0
	var cancel_checked := false
	var floor_recovered := false
	for i in 260:
		await physics_frame
		var phase := int(_p.get("r7_air_phase"))
		var clock := float(_p.get("_action_elapsed"))
		max_vy = maxf(max_vy, _p.velocity.y)
		_check(is_equal_approx(float(_p.get("jump_velocity")), base_jump_v), "ordinary jump velocity unchanged")
		if phase == 4:
			floor_recovered = true
		if _scenario == "jump_lock" and phase != 0:
			var charge_before: float = _p.get("_jump_charge")
			_p.call("request_jump")
			_check(is_equal_approx(float(_p.get("_jump_charge")), charge_before), "jump input cannot change current form charge")
		if _scenario in ["takeoff_hitstop", "takeoff_hit"] and not injected and clock + 0.016667 >= float(_p.get("_r7_air_takeoff")):
			if _scenario == "takeoff_hitstop":
				_p.set("_hitstop_time", 0.12)
			else:
				_p.call("take_hit", {"damage": 1.0, "posture_damage": 0.0})
			injected = true
		if _scenario == "lost_floor" and not injected and clock > 0.02:
			_floor.position.y = -10000.0
			injected = true
		if _scenario == "zero_stun_hit" and not injected and _p.position.y > 0.3:
			_p.set("hit_stun_time", 0.0)
			_p.call("take_hit", {"damage": 1.0, "posture_damage": 0.0})
			_check(int(_p.get("r7_air_phase")) == 0, "zero-stun hit still interrupts aerial action")
			injected = true
		if _scenario in ["stagger", "death"] and not injected and _p.position.y > 0.3:
			_p.call("take_hit", {"damage": 10000.0 if _scenario == "death" else 0.0, "posture_damage": 10000.0})
			_check(int(_p.get("r7_air_phase")) == 0 and not _p.call("execute_form", _id, true), "posture/death priority synchronously clears action and blocks FREE activation")
			_check(float(_p.get("_dead_left")) > 0.0 if _scenario == "death" else float(_p.get("_stagger_left")) > 0.0, "parent reaction owns control")
			injected = true
		if _scenario == "priority" and not injected and _p.position.y > 0.3:
			_p.set("input_locked", true)
			injected = true
		if _scenario == "buffer_expire" and not injected and clock > 0.02:
			_p.call("request_primary_attack")
			injected = true
		if _scenario == "buffer_expire" and clock > 0.38 and int(_p.get("active_form")) == _id:
			_check(String(_p.get("_r7_followup")) == "", "0.3s followup expires before landing")
		if _scenario in ["followup", "dodge_cancel", "same_tick"] and phase == 4 and _p.call("r7_form_cancel_ok") and not injected:
			if _scenario == "followup":
				_p.call("request_primary_attack")
				_check(int(_p.get("combo_stage")) == 1 and int(_p.get("active_form")) == 0, "recovery light followup works")
			elif _scenario == "dodge_cancel":
				_p.call("request_dodge")
				_check(int(_p.get("action_state")) == 2 and int(_p.get("r7_air_phase")) == 0, "grounded recovery dodge works")
			else:
				_p.call("_finish_attack")
				_p.get("_form_cooldowns").clear()
				_check(_p.call("execute_form", _id, true), "same-tick fresh form accepted")
				_check(_p.get("_r7_root").size() > 0 and int(_p.get("r7_air_phase")) == 1 and is_zero_approx(float(_p.get("_action_elapsed"))), "same-tick new state is not cleared by old cleanup")
			injected = true
		peak = maxf(peak, _p.position.y)
		saw_air = saw_air or not _p.is_on_floor()
		if phase not in phases:
			phases.append(phase)
		if i % 6 == 0 or phase != previous_phase:
			_case.trace.append(_snapshot())
		previous_phase = phase
		if int(_p.get("r7_hit_group")) > 0 and int(_p.get("r7_hit_group")) not in hit_groups:
			hit_groups.append(int(_p.get("r7_hit_group")))
		if _scenario == "repeat" and not injected and saw_air:
			_p.call("_finish_attack")
			_check(not _p.call("execute_form", _id, true), "same airtime activation rejected after cancellation")
			injected = true
		elif _scenario == "hitinterrupt" and not injected and _p.position.y > 0.3:
			_p.call("take_hit", {"damage": 1.0, "posture_damage": 0.0})
			_check(int(_p.get("r7_air_phase")) == 0 and not _p.get("_r7_form_on"), "take_hit synchronously clears air state")
			_check(not _p.call("execute_form", _id, true), "FREE during stun cannot attack")
			injected = true
		elif _scenario == "early" and not injected and _p.velocity.y < 0.0 and _p.position.y > 0.45:
			_box(Vector3(0, 0.3, 0), Vector3(30, 0.6, 30))
			injected = true
		elif _scenario in ["late", "never", "wait_hit"] and not injected and _p.position.y > 0.3:
			_floor.position.y = -4.5 if _scenario == "late" else -10000.0
			injected = true
		elif _scenario == "hitstop" and not injected and _p.position.y > 0.3:
			_p.set("_hitstop_time", 0.20)
			_case.hitstop_before = _snapshot()
			injected = true
		if phase == 3:
			wait_samples += 1
			_check(int(_p.get("r7_hit_group")) == 0 and not _p.get("_hitbox").monitoring, "WAIT_CONTACT damage closed")
			_check(not _p.call("r7_form_cancel_ok"), "WAIT_CONTACT cannot cancel")
			_check(is_zero_approx(float(_p.get("_tree").get("parameters/ts_full/scale"))), "WAIT_CONTACT animation frozen")
			if held_t < 0.0:
				held_t = clock
				held_y = _p.position.y
			else:
				_check(is_equal_approx(clock, held_t), "WAIT_CONTACT action clock frozen")
			if _scenario == "wait_hit" and wait_samples == 4:
				_p.call("take_hit", {"damage": 1.0, "posture_damage": 0.0})
				_check(int(_p.get("r7_air_phase")) == 0 and is_equal_approx(float(_p.get("_tree").get("parameters/ts_full/scale")), float(_p.get("hit_react_speed"))), "wait hit restores clocks synchronously to hit reaction speed")
		if phase == 4:
			_check(int(_p.get("r7_hit_group")) == 0, "LAND_RECOVER cannot replay air damage")
			if _scenario == "damage":
				_check(receiver.hits == 1, "recovery cannot deliver another sweep hit")
		if phase in [1, 2, 3] and not cancel_checked and clock > 0.30:
			_check(not _p.call("r7_form_cancel_ok") and not _p.call("_in_form_cancel_window") and not _p.call("_can_dodge_cancel_attack"), "all cancel routes closed before landing recovery")
			cancel_checked = true
		if _scenario == "cancel" and phase == 4 and _p.call("r7_form_cancel_ok"):
			_p.call("begin_guard")
			_check(bool(_p.get("_guard_held")) and int(_p.get("r7_air_phase")) == 0, "recovery guard cancel accepted")
			injected = true
		if i == 12 and _scenario == "hitstop":
			_case.hitstop_after = _snapshot()
		if int(_p.get("active_form")) == 0 and i > 5:
			if _scenario == "repeat" and not _p.is_on_floor():
				continue
			break
	_case.max_vy = max_vy
	_case.peak = peak
	_case.phases = phases
	_case.hit_groups = hit_groups
	_case.final = _snapshot()
	if _scenario != "takeoff_hit":
		_check(saw_air, "real CharacterBody leaves floor")
	else:
		_check(not saw_air and peak < 0.05 and float(_p.get("_jump_charge")) < 0.0, "takeoff interruption cannot leak delayed normal jump")
	_check(int(_p.get("active_form")) == 0, "action terminates within bounded time")
	if _scenario == "followup":
		var light: Animation = _p.get("r7_light_01_resource")
		_check(_p.get("_r7_wins").size() == 1 and _p.get("_r7_wins")[0] == PackedInt32Array(light.get_meta("r7_hit_window")), "followup owns only its new light hit window")
	else:
		_check(_p.get("_r7_wins").is_empty(), "air hit windows cleaned")
	_check(_p.get("_r7_root").is_empty(), "root displacement cleaned")
	if _scenario in ["air", "high_air", "inputs"]:
		var key: String = _p.get("R7_FORMS")[_id].key
		var node: AnimationNodeAnimation = _p.get("_tree").tree_root.get_node("full_sel_" + key)
		_check(node.use_custom_timeline and node.start_offset > 0.0, "air timeline retained through fade, no replay of earlier air slash")
	_check(_p.get("_sword_hand").transform.is_equal_approx(sock), "sword socket restored")
	_check(ik.right_weight > 0.9 and ik.left_enabled, "ground grip policy restored")
	if _scenario in ["ground", "air", "high_air", "inputs", "wall", "hitstop", "gates"]:
		_check(String(_p.get("r7_air_exit")) == "complete", "normal recovery completes, not early abort")
		_check(4 in phases, "actual contact enters LAND_RECOVER")
		_check(hit_groups == [1], "one authored hit group")
	if _scenario == "damage":
		_case.damage_hits = receiver.hits
		_check(receiver.hits == 1, "real Area3D sweep receiver hit exactly once")
	if _scenario in ["takeoff_hitstop", "jump_lock"]:
		_check(max_vy <= float(_case.metadata.r7_takeoff_v) + 0.01 and String(_p.get("r7_air_exit")) == "complete", "one metadata takeoff, no 8.2m/s jump or double jump")
	if _scenario == "lost_floor":
		_check(String(_p.get("r7_air_exit")) == "lost_floor_before_takeoff" and max_vy <= 0.0, "lost windup support aborts without a second takeoff")
	if _scenario == "hold_timeout":
		_check(2 in phases and String(_p.get("r7_air_exit")) == "timeout", "high-air hold bounded by 2s")
	if _scenario in ["followup", "dodge_cancel", "same_tick"]:
		_check(injected and floor_recovered, "cancel route exercised only after actual landing")
	if _scenario == "buffer_expire":
		_check(String(_p.get("r7_air_exit")) == "complete", "expired buffer never auto-starts attack")
	if _scenario == "priority":
		_check(String(_p.get("r7_air_exit")) == "interrupted", "input lock interrupts with cleanup")
	if _scenario == "high_air":
		_check(2 in phases, "high start holds non-damaging pose")
	if _scenario in ["late", "never", "wait_hit"]:
		_check(wait_samples >= 2, "late contact barrier reached")
		_check(_p.position.y < held_y - 0.01, "gravity continues while action clock waits")
	if _scenario == "late":
		_check(4 in phases and String(_p.get("r7_air_exit")) == "complete", "late landing resumes recovery")
	if _scenario == "never":
		_check(String(_p.get("r7_air_exit")) == "timeout" and not _p.is_on_floor(), "2s timeout returns airborne Fall")
	if _scenario == "early":
		_check(String(_p.get("r7_air_exit")) == "early_contact", "high platform aborts remaining air slash")
	if _scenario == "ceiling":
		_check(String(_p.get("r7_air_exit")) == "ceiling", "ceiling interrupts to Fall")
	if _scenario == "wall":
		var travel := _p.position.dot(_wall_dir)
		_case.wall_travel_m = travel
		_check(travel > 0.15 and travel < 0.45, "body approaches but cannot pass wall across actual form path")
	if _scenario == "repeat":
		_check(_p.is_on_floor() and not bool(_p.get("_r7_air_used")), "actual landing rearms activation")
		_p.get("_form_cooldowns").clear()
		_check(_p.call("execute_form", _id, true), "next airtime can activate again")
		_p.call("_finish_attack")
	if _scenario == "cancel":
		_check(injected, "cancel only opens in grounded recovery")
	if _scenario == "hitinterrupt":
		for i in 120:
			await physics_frame
			if _p.is_on_floor() and float(_p.get("_hitstun_left")) <= 0.0:
				break
		_check(_p.is_on_floor() and not bool(_p.get("input_locked")), "post-hit physics lands without input lock leak")
		var from := _p.position
		Input.action_press("move_forward")
		for i in 25:
			await physics_frame
		Input.action_release("move_forward")
		var displacement := Vector2(_p.position.x - from.x, _p.position.z - from.z).length()
		_case.post_hit_move_m = displacement
		_check(displacement > 1.4, "post-hit real movement recovers, >1.4m in 25 physics frames")
	_case.start_y = start_y
	_results.append(_case)
	print("CASE ", _scenario, "/", _id, " exit=", _case.final.exit, " peak=", snappedf(peak, 0.001), " phases=", phases)
	_world.queue_free()
	await process_frame
	await physics_frame

func _run() -> void:
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	var args := OS.get_cmdline_user_args()
	var expected_cases := 0
	for scenario in SCENARIOS:
		if args.size() > 0 and args[0] != "all" and args[0] != scenario:
			continue
		for id in IDS:
			if args.size() > 1 and int(args[1]) != id:
				continue
			expected_cases += 1
			_scenario = scenario
			_id = id
			await _run_case()
	if _results.size() != expected_cases or expected_cases == 0:
		_failures.append("incomplete or empty selected case set")
	var path := "user://r7_air_tests.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"scene": PLAYER, "engine": Engine.get_version_info().string, "expected_cases": expected_cases, "cases": _results, "failures": _failures}, "	"))
	file.close()
	print("R7_AIR_RESULT cases=", _results.size(), " failures=", _failures.size(), " json=", ProjectSettings.globalize_path(path))
	quit(0 if _failures.is_empty() else 1)
