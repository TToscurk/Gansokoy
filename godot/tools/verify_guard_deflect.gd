extends SceneTree
## Regression: guarding and the Sekiro deflect (弾き) window on the player.

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[GUARD] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _make() -> Node:
	var scene: PackedScene = load("res://characters/yoriichi/player_yoriichi.tscn")
	var p = scene.instantiate()
	root.add_child(p)
	return p

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	var player = _make()
	await _frames(4)
	# Guarding needs a drawn blade; enter combat stance first.
	player.sword_state = player.SwordState.DRAWN
	await _frames(1)

	check("player carries a posture component", player.posture != null)
	check("player starts alive and unbroken", not player.posture.is_dead() and not player.posture.is_broken())
	check("player is not guarding by default", not player.is_guarding())

	# --- Taking a hit with no guard: full damage. -------------------------
	var hit := {"damage": 20.0, "posture_damage": 12.0, "hit_dir": Vector3(0, 0, -1), "hit_pos": player.global_position}
	var res: Dictionary = player.take_hit(hit)
	check("an unguarded hit deals full damage", is_equal_approx(player.posture.health, 80.0))
	check("an unguarded hit reports no block", res.get("result", "") == "hit")

	# --- Deflect: guard pressed within the window. -----------------------
	player.posture.heal_full()
	player.begin_guard()
	await _frames(1)
	check("guarding is reported while held", player.is_guarding())
	var deflect: Dictionary = player.take_hit(hit)
	check("a deflect negates all damage", is_equal_approx(player.posture.health, 100.0))
	check("a deflect is reported as a deflect", deflect.get("result", "") == "deflect")
	check("a deflect punishes the attacker's posture", float(deflect.get("attacker_posture", 0.0)) > 15.0)
	var posture_after_deflect: float = player.posture.posture
	check("a deflect costs the defender little posture", posture_after_deflect < 10.0)

	# --- Guard: still holding, but the window has passed. ----------------
	player.posture.heal_full()
	player.begin_guard()
	# Let the deflect window lapse.
	for i in 40:
		await physics_frame
		await process_frame
	var block: Dictionary = player.take_hit(hit)
	check("a late guard is a block, not a deflect", block.get("result", "") == "block")
	check("a block still leaks some damage", player.posture.health < 100.0 and player.posture.health > 90.0)
	check("a block costs far more posture than a deflect", player.posture.posture > posture_after_deflect * 2.0)

	# --- Releasing the guard drops protection. ---------------------------
	player.end_guard()
	await _frames(1)
	check("releasing stops the guard", not player.is_guarding())
	player.posture.heal_full()
	var open: Dictionary = player.take_hit(hit)
	check("a released guard takes full damage again", open.get("result", "") == "hit")

	# --- Perilous attacks cannot be guarded safely. ----------------------
	player.posture.heal_full()
	player.begin_guard()
	await _frames(1)
	var peril := hit.duplicate()
	peril["perilous"] = true
	var pr: Dictionary = player.take_hit(peril)
	check("a perilous attack is not deflected", pr.get("result", "") != "deflect")
	check("guarding a perilous attack floods posture", player.posture.posture > 30.0)
	player.end_guard()

	# --- Guarding must not be possible mid-attack. -----------------------
	player.posture.heal_full()
	player.action_state = 1
	player.begin_guard()
	await _frames(1)
	check("cannot raise a guard mid-attack", not player.is_guarding())
	player.action_state = 0

	# --- Death routes through the posture component. ---------------------
	player.posture.apply_damage(999.0, 0.0)
	await _frames(2)
	check("lethal damage kills the player", player.posture.is_dead())

	print("[GUARD] failures=%d" % failures)
	player.free()
	quit(failures)
