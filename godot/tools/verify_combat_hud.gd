extends SceneTree
## Regression: the Sekiro-style combat HUD.

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[HUD] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	var scene: PackedScene = load("res://ui/combat_hud.tscn")
	var hud = scene.instantiate()
	root.add_child(hud)
	await _frames(3)

	# The drawing scripts must actually load; numeric checks alone hid a parse error.
	var pbars: Node = hud.get_node_or_null("Root/PlayerBars")
	var ebars: Node = hud.get_node_or_null("Root/EnemyPanel/Bars")
	check("player bar drawing script is attached", pbars != null and pbars.get_script() != null)
	check("enemy bar drawing script is attached", ebars != null and ebars.get_script() != null)
	check("player bars found the hud", pbars != null and pbars.get("_hud") == hud)
	check("enemy bars found the hud", ebars != null and ebars.get("_hud") == hud)

	check("hud reports full player health at rest", is_equal_approx(hud.player_health_ratio, 1.0))
	check("hud reports empty player posture at rest", is_equal_approx(hud.player_posture_ratio, 0.0))
	check("no enemy bar without a target", not hud.is_enemy_visible())
	check("no perilous warning at rest", not hud.is_perilous_visible())
	check("no deathblow prompt at rest", not hud.is_deathblow_visible())

	# --- Player bars follow the numbers ----------------------------------
	hud.set_player_health(40.0, 100.0)
	hud.set_player_posture(75.0, 100.0)
	await _frames(2)
	check("player health bar tracks health", is_equal_approx(hud.player_health_ratio, 0.4))
	check("player posture bar tracks posture", is_equal_approx(hud.player_posture_ratio, 0.75))

	# The posture bar must warn before it fills, or it is useless.
	var warn_col: Color = hud.posture_colour(0.75)
	var calm_col: Color = hud.posture_colour(0.2)
	check("posture turns hot as it fills", warn_col.r >= calm_col.r and warn_col != calm_col)
	var danger_col: Color = hud.posture_colour(0.95)
	check("near-full posture is the most alarming", danger_col != warn_col)

	# --- Enemy bar appears only with a live target -----------------------
	hud.show_enemy("侍", 60.0, 80.0, 30.0, 100.0)
	await _frames(2)
	check("enemy bar appears with a target", hud.is_enemy_visible())
	check("enemy health ratio is correct", is_equal_approx(hud.enemy_health_ratio, 0.75))
	check("enemy posture ratio is correct", is_equal_approx(hud.enemy_posture_ratio, 0.3))
	hud.hide_enemy()
	await _frames(2)
	check("enemy bar hides when the target is gone", not hud.is_enemy_visible())

	# --- Perilous warning -------------------------------------------------
	hud.show_perilous()
	await _frames(2)
	check("perilous warning appears on demand", hud.is_perilous_visible())
	check("the perilous glyph reads 危", hud.perilous_text() == "危")
	hud.hide_perilous()
	await _frames(2)
	check("perilous warning clears", not hud.is_perilous_visible())

	# --- Deathblow prompt -------------------------------------------------
	hud.show_deathblow()
	await _frames(2)
	check("deathblow prompt appears when an enemy breaks", hud.is_deathblow_visible())
	hud.hide_deathblow()
	await _frames(2)
	check("deathblow prompt clears", not hud.is_deathblow_visible())

	# --- Deflect flash is the player's only instant feedback -------------
	hud.flash_deflect()
	await _frames(1)
	check("a deflect flashes the posture bar", hud.deflect_flash > 0.5)
	await _frames(40)
	check("the deflect flash fades", hud.deflect_flash < 0.5)

	print("[HUD] failures=%d" % failures)
	quit(failures)
