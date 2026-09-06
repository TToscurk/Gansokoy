extends SceneTree
## Regression: lock-on plus the wiring that turns the parts into a fight.

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[ARENA] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat_arena.tscn")
	var arena = scene.instantiate()
	root.add_child(arena)
	await _frames(10)

	var player = arena.get_node_or_null("Player")
	var hud = arena.get_node_or_null("CombatHUD")
	check("the arena has a player", player != null)
	check("the arena has a combat hud", hud != null)
	var enemies: Array[Node] = []
	for n in arena.find_children("*", "CharacterBody3D", true, false):
		var s: Variant = n.get_script()
		if s != null and String(s.resource_path).ends_with("enemy_samurai.gd"):
			enemies.append(n)
	check("the arena has at least one enemy", enemies.size() >= 1)
	if player == null or hud == null or enemies.is_empty():
		print("[ARENA] failures=%d" % failures)
		quit(maxi(failures, 1))
		return

	var enemy = enemies[0]
	check("the enemy hunts the player", enemy.target == player)

	# --- Lock-on ---------------------------------------------------------
	enemy.global_position = player.global_position + Vector3(0, 0, -5.0)
	await _frames(3)
	check("nothing is locked at the start", player.lock_target == null)
	player.toggle_lock_on()
	await _frames(3)
	check("lock-on finds the nearby enemy", player.lock_target == enemy)
	check("locking on shows the enemy bar", hud.is_enemy_visible())

	# Locked, the player must keep facing the enemy.
	player.global_rotation.y = PI
	await _frames(40)
	var to_enemy: Vector3 = (enemy.global_position - player.global_position)
	to_enemy.y = 0.0
	var facing: Vector3 = -player.global_transform.basis.z
	print("[ARENA] facing dot = %.3f" % facing.dot(to_enemy.normalized()))
	check("a locked player turns to face the enemy", facing.dot(to_enemy.normalized()) > 0.85)

	# Out of range the lock must break on its own.
	enemy.global_position = player.global_position + Vector3(0, 0, -60.0)
	await _frames(6)
	check("lock breaks when the enemy runs far away", player.lock_target == null)
	check("the enemy bar hides when the lock breaks", not hud.is_enemy_visible())

	# --- The HUD must mirror live combat numbers -------------------------
	enemy.global_position = player.global_position + Vector3(0, 0, -4.0)
	await _frames(3)
	player.toggle_lock_on()
	await _frames(3)
	enemy.posture.apply_damage(20.0, 40.0)
	await _frames(4)
	check("hud shows the enemy's real health", is_equal_approx(hud.enemy_health_ratio, enemy.posture.health_ratio()))
	check("hud shows the enemy's real posture", is_equal_approx(hud.enemy_posture_ratio, enemy.posture.posture_ratio()))

	player.posture.apply_damage(35.0, 30.0)
	await _frames(4)
	check("hud shows the player's real health", is_equal_approx(hud.player_health_ratio, player.posture.health_ratio()))
	check("hud shows the player's real posture", is_equal_approx(hud.player_posture_ratio, player.posture.posture_ratio()))

	# --- Perilous warning is driven by the enemy, not by hand ------------
	hud.hide_perilous()
	enemy.attack_windup.emit(true)
	await _frames(2)
	check("a perilous windup raises the 危 warning", hud.is_perilous_visible())
	enemy.attack_struck.emit(10.0)
	await _frames(2)
	check("the warning clears once the blow lands", not hud.is_perilous_visible())

	# --- Breaking the enemy offers the deathblow -------------------------
	enemy.posture.apply_damage(0.0, enemy.posture.max_posture)
	await _frames(4)
	check("breaking the enemy shows the 忍殺 prompt", hud.is_deathblow_visible())

	# A deathblow must require closing in, not sniping from across the arena.
	check("a deathblow out of reach is refused", not player.try_deathblow())
	enemy.global_position = player.global_position + Vector3(0, 0, -1.6)
	await _frames(3)
	check("the player can execute a broken enemy up close", player.try_deathblow())
	await _frames(4)
	check("the deathblow kills the enemy", enemy.posture.is_dead())
	check("the prompt clears after the kill", not hud.is_deathblow_visible())
	check("the lock releases when the enemy dies", player.lock_target == null)

	print("[ARENA] failures=%d" % failures)
	quit(failures)
