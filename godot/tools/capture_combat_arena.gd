extends SceneTree
## Record a real fight in the combat arena so the HUD can be judged on screen.
##
## Not a test: it drives the arena with scripted input and lets --write-movie
## capture it. Verification lives in the verify_* scripts.

var _frames_seen := 0


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await process_frame
		_frames_seen += 1


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat_arena.tscn")
	var arena = scene.instantiate()
	root.add_child(arena)
	await _wait(10)

	var player = arena.get_node_or_null("Player")
	var hud = arena.get_node_or_null("CombatHUD")
	var enemy = null
	for n in arena.find_children("*", "CharacterBody3D", true, false):
		var s: Variant = n.get_script()
		if s != null and String(s.resource_path).ends_with("enemy_samurai.gd"):
			enemy = n
			break
	if player == null or enemy == null or hud == null:
		push_error("arena is missing pieces")
		quit(1)
		return

	# A camera that frames both fighters, since the player's own rig follows the
	# character and would hide the enemy bar during the duel.
	var cam := Camera3D.new()
	cam.position = Vector3(6.5, 4.2, 7.0)
	arena.add_child(cam)
	cam.look_at(Vector3(0, 1.1, 0), Vector3.UP)
	cam.current = true
	await _wait(4)

	player.sword_state = player.SwordState.DRAWN
	player.toggle_lock_on()
	await _wait(30)

	# 1. Player takes a clean hit — health drops, posture climbs.
	player.take_hit({"damage": 18.0, "posture_damage": 16.0, "hit_pos": player.global_position, "hit_dir": Vector3.FORWARD})
	await _wait(45)

	# 2. A deflect — the posture bar flashes white.
	player.begin_guard()
	await _wait(2)
	player.take_hit({"damage": 18.0, "posture_damage": 16.0, "hit_pos": player.global_position, "hit_dir": Vector3.FORWARD})
	await _wait(50)
	player.end_guard()
	await _wait(20)

	# 3. A perilous attack — the 危 glyph.
	enemy.attack_windup.emit(true)
	await _wait(60)
	enemy.attack_struck.emit(0.0)
	await _wait(20)

	# 4. Grind the enemy's posture up in stages so the colour ramp is visible.
	for i in 5:
		enemy.posture.apply_damage(6.0, 22.0)
		await _wait(28)

	# 5. Break — the 忍殺 prompt.
	await _wait(60)

	# 6. Deathblow.
	enemy.global_position = player.global_position + Vector3(0, 0, -1.6)
	await _wait(10)
	player.try_deathblow()
	await _wait(70)

	print("[ARENA_CAPTURE] %s" % JSON.stringify({
		"frames": _frames_seen,
		"enemy_dead": enemy.posture.is_dead(),
		"status": "ART_REVIEW",
	}))
	quit(0)
