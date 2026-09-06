extends SceneTree
## Regression: the combat keys are bound and reach the controller.

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[INPUT] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	for a in ["guard", "lock_on", "deathblow"]:
		check("action '%s' exists" % a, InputMap.has_action(a))
		check("action '%s' has a binding" % a, InputMap.action_get_events(a).size() > 0)

	# Guard must not steal the existing heavy-attack right click.
	var heavy_buttons: Array = []
	for e in InputMap.action_get_events("attack_heavy"):
		if e is InputEventMouseButton:
			heavy_buttons.append(e.button_index)
	for e in InputMap.action_get_events("guard"):
		if e is InputEventMouseButton:
			check("guard does not hijack the heavy-attack button", not heavy_buttons.has(e.button_index))

	# Pressing the key must actually drive the controller.
	var scene: PackedScene = load("res://scenes/combat_arena.tscn")
	var arena = scene.instantiate()
	root.add_child(arena)
	await _frames(6)
	var player = arena.get_node_or_null("Player")
	player.sword_state = player.SwordState.DRAWN
	await _frames(2)

	var press := InputEventAction.new()
	press.action = "guard"
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(3)
	check("pressing guard raises the player's guard", player.is_guarding())

	var release := InputEventAction.new()
	release.action = "guard"
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(3)
	check("releasing guard lowers it", not player.is_guarding())

	var lock := InputEventAction.new()
	lock.action = "lock_on"
	lock.pressed = true
	Input.parse_input_event(lock)
	await _frames(3)
	check("pressing lock-on acquires a target", player.lock_target != null)

	print("[INPUT] failures=%d" % failures)
	quit(failures)
