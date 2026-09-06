extends SceneTree
## Where does the player actually end up on the east river band? Drop the real
## capsule and let physics settle — this is what a player would experience.

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "")
	await _wait(80)
	var player = main.get_node_or_null("Player")

	# The river bed the remote branch drew is at y=-6.10 (from the visual mesh).
	# If the player floats ~6 m above it, he is standing on air.
	for pt in [Vector3(445, 0, -60), Vector3(460, 0, -20), Vector3(430, 0, -100),
			Vector3(445, 0, -120), Vector3(445, 0, -160)]:
		player.global_position = pt + Vector3(0, 3, 0)
		player.velocity = Vector3.ZERO
		await _wait(60)
		var y: float = player.global_position.y
		var verdict := "站在 %.2f — 河床在 -6.10，%s" % [y,
			"懸空 %.1f m" % (y + 6.10) if y > -5.0 else "落到河床"]
		print("[DROP] (%4.0f, %5.0f) → %s  on_floor=%s" % [pt.x, pt.z, verdict, str(player.is_on_floor())])
	quit(0)
