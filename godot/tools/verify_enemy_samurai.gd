extends SceneTree
## Regression: an enemy samurai that approaches, telegraphs, strikes and breaks.

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[ENEMY] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	var scene: PackedScene = load("res://characters/combat/enemy_samurai.tscn")

	# A floor, or everyone falls and "distance" just measures the drop.
	var floor_body := StaticBody3D.new()
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(60, 1, 60)
	fshape.shape = fbox
	fshape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fshape)
	root.add_child(floor_body)

	var e = scene.instantiate()
	root.add_child(e)

	# A stand-in target the enemy should hunt.
	var target := CharacterBody3D.new()
	target.name = "FakePlayer"
	root.add_child(target)
	await _frames(3)

	check("enemy has posture and health", e.posture != null and e.posture.health > 0.0)
	check("enemy is hittable by the player's blade", e.is_in_group("hittable"))
	check("enemy idles with no target in range", e.state == e.State.IDLE)

	# --- Detection and approach ------------------------------------------
	target.global_position = e.global_position + Vector3(0, 0, -6.0)
	e.target = target
	await _frames(10)
	check("enemy notices a nearby target", e.state != e.State.IDLE)
	var gap_before: float = e.global_position.distance_to(target.global_position)
	await _frames(60)
	var gap_after: float = e.global_position.distance_to(target.global_position)
	print("[ENEMY] gap %.2f -> %.2f" % [gap_before, gap_after])
	check("enemy closes the distance", gap_after < gap_before - 0.5)

	# --- Telegraphed attack ----------------------------------------------
	target.global_position = e.global_position + Vector3(0, 0, -1.5)
	var saw_windup := [false]
	var strikes := [0]
	e.attack_windup.connect(func(_perilous): saw_windup[0] = true)
	e.attack_struck.connect(func(_d): strikes[0] += 1)
	await _frames(120)
	check("enemy telegraphs before striking", saw_windup[0])
	check("enemy actually strikes", strikes[0] >= 1)
	check("the windup is long enough to read", e.windup_time >= 0.3)

	# --- Posture break opens the deathblow window ------------------------
	e.posture.apply_damage(0.0, e.posture.max_posture)
	await _frames(3)
	check("full posture breaks the enemy", e.state == e.State.BREAK)
	check("a broken enemy is marked executable", e.can_deathblow())
	var pre_strikes: int = strikes[0]
	await _frames(30)
	check("a broken enemy cannot attack", strikes[0] == pre_strikes)

	# --- Deathblow is lethal regardless of health ------------------------
	e.posture.health = 999.0
	var killed := [false]
	e.died.connect(func(): killed[0] = true)
	check("deathblow succeeds on a broken enemy", e.execute_deathblow())
	await _frames(3)
	check("deathblow kills outright", killed[0] and e.posture.is_dead())
	check("a dead enemy stops acting", e.state == e.State.DEAD)

	# --- A fresh enemy refuses a deathblow while unbroken ----------------
	var e2 = scene.instantiate()
	root.add_child(e2)
	await _frames(3)
	check("an unbroken enemy cannot be executed", not e2.can_deathblow() and not e2.execute_deathblow())

	# --- Blade hits route through take_hit -------------------------------
	var hp: float = e2.posture.health
	e2.take_hit({"damage": 25.0, "posture_damage": 15.0, "hit_pos": e2.global_position, "hit_dir": Vector3.FORWARD})
	check("sword hits damage the enemy", e2.posture.health < hp)
	check("sword hits build enemy posture", e2.posture.posture > 0.0)

	print("[ENEMY] failures=%d" % failures)
	quit(failures)
