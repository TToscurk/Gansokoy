extends SceneTree
## Regression: the dragon's head tracks the blade, and the finisher has fire + wind audio.

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[DRAGON_TRACK] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	var SunDragon = load("res://characters/yoriichi/vfx/sun_dragon.gd")
	var host := Node3D.new()
	root.add_child(host)
	var blade := Marker3D.new()
	host.add_child(blade)
	await process_frame

	var dragon = SunDragon.spawn(host, Transform3D(Basis(), Vector3.ZERO))
	dragon.track_node = blade
	# Keep it alive long enough to sample several bearings.
	dragon.reveal_time = 0.6
	dragon.hold_time = 3.0
	dragon.burn_time = 0.6
	await _frames(2)

	# The head sits at local +X, so yaw must follow the blade's bearing.
	blade.global_position = Vector3(0, 1, -4)
	await _frames(40)
	var head_dir: Vector3 = dragon.global_transform.basis.x
	var want: Vector3 = Vector3(0, 0, -1)
	print("[DRAGON_TRACK] head_dir=%s" % str(head_dir))
	check("head turns toward the blade", head_dir.dot(want) > 0.9)

	blade.global_position = Vector3(4, 1, 0)
	await _frames(40)
	var head_dir2: Vector3 = dragon.global_transform.basis.x
	print("[DRAGON_TRACK] head_dir2=%s" % str(head_dir2))
	check("head follows the blade as it sweeps", head_dir2.dot(Vector3(1, 0, 0)) > 0.9)
	check("head stays level while tracking", absf(head_dir2.y) < 0.05)

	# Turning must be gradual, not a snap: sample the intermediate bearing.
	blade.global_position = Vector3(-4, 1, 0)
	await _frames(3)
	var mid: Vector3 = dragon.global_transform.basis.x
	check("turn is smoothed, not instant", mid.dot(Vector3(-1, 0, 0)) < 0.95)

	# Fire + wind must actually be playing from the effect itself.
	var players: Array[AudioStreamPlayer3D] = []
	for p in dragon.find_children("*", "AudioStreamPlayer3D", true, false):
		players.append(p)
	check("dragon carries fire and wind players", players.size() >= 2)
	var playing := 0
	var streams := 0
	for p in players:
		if p.stream != null:
			streams += 1
		if p.playing:
			playing += 1
	check("both ambience streams are loaded", streams >= 2)
	check("ambience is audible during the strike", playing >= 2)

	# Audio must stop with the effect rather than outliving it.
	await _frames(220)
	check("effect and its audio are gone afterwards", not is_instance_valid(dragon) or not dragon.is_inside_tree())

	print("[DRAGON_TRACK] failures=%d" % failures)
	host.free()
	quit(failures)
