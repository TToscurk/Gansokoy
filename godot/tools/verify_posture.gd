extends SceneTree
## Regression: the posture (軀幹) system that decides Sekiro-style fights.

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[POSTURE] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _run() -> void:
	var Posture = load("res://characters/combat/posture.gd")

	var p = Posture.new()
	p.max_health = 100.0
	p.max_posture = 100.0
	root.add_child(p)
	await process_frame

	check("starts at full health", is_equal_approx(p.health, 100.0))
	check("starts with empty posture", is_equal_approx(p.posture, 0.0))
	check("is not broken at rest", not p.is_broken())

	# Damage reduces health; posture builds separately.
	p.apply_damage(30.0, 12.0)
	check("damage reduces health", is_equal_approx(p.health, 70.0))
	check("damage also builds posture", is_equal_approx(p.posture, 12.0))

	# Posture must not regenerate during the delay right after a hit.
	var before: float = p.posture
	p.tick(0.1)
	check("posture holds during the post-hit delay", is_equal_approx(p.posture, before))

	# After the delay it recovers.
	p.tick(p.posture_regen_delay + 0.2)
	check("posture recovers after the delay", p.posture < before)

	# The Sekiro rule: low health means far slower posture recovery.
	var healthy = Posture.new()
	root.add_child(healthy)
	var hurt = Posture.new()
	root.add_child(hurt)
	await process_frame
	healthy.apply_damage(0.0, 60.0)
	hurt.apply_damage(90.0, 60.0)
	healthy.tick(healthy.posture_regen_delay + 1.0)
	hurt.tick(hurt.posture_regen_delay + 1.0)
	var healthy_recovered: float = 60.0 - healthy.posture
	var hurt_recovered: float = 60.0 - hurt.posture
	print("[POSTURE] recovered healthy=%.2f hurt=%.2f" % [healthy_recovered, hurt_recovered])
	check("wounded fighters recover posture far slower", hurt_recovered < healthy_recovered * 0.6)

	# Filling posture opens the deathblow window.
	var b = Posture.new()
	root.add_child(b)
	await process_frame
	var broke := [false]
	b.posture_broken.connect(func(): broke[0] = true)
	b.apply_damage(0.0, 200.0)
	check("posture caps at maximum", is_equal_approx(b.posture, b.max_posture))
	check("full posture means broken", b.is_broken())
	check("breaking emits a signal", broke[0])
	check("a broken fighter cannot gain more posture", is_equal_approx(b.posture, b.max_posture))

	# The break must expire on its own, emptying the bar.
	b.tick(b.break_time + 0.1)
	check("break wears off", not b.is_broken())
	check("posture empties after a break", b.posture < 1.0)

	# Death is separate from a break and is final.
	var d = Posture.new()
	root.add_child(d)
	await process_frame
	var died := [0]
	d.died.connect(func(): died[0] += 1)
	d.apply_damage(500.0, 10.0)
	check("health floors at zero", is_equal_approx(d.health, 0.0))
	check("zero health is death", d.is_dead())
	check("death emits a signal", died[0] == 1)
	d.apply_damage(10.0, 10.0)
	check("the dead take no further damage", died[0] == 1)

	print("[POSTURE] failures=%d" % failures)
	quit(failures)
