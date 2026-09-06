extends SceneTree
## Regression: 玖ノ型 spawns exactly one dragon, oriented to the actor, and honours its toggle.

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[SPIN_DRAGON] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _dragons() -> Array:
	# Match only the spawned effect roots, not the imported GLB scene node inside them.
	var out := []
	for c in root.get_children():
		if c.get_script() != null and c.get_script().resource_path.ends_with("sun_dragon.gd"):
			out.append(c)
	return out

func _run() -> void:
	var scene := load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene
	var player = scene.instantiate()
	root.add_child(player)
	await _frames(4)
	player.request_draw()
	await _frames(80)

	check("no dragon before the finisher", _dragons().is_empty())

	player.global_position = Vector3(5, 0, 7)
	player.request_continuous_spin()
	await _frames(2)
	var spawned := _dragons()
	print("[SPIN_DRAGON] action_state=%d sword_state=%d dragons=%d" % [player.action_state, player.sword_state, spawned.size()])
	print("[SPIN_DRAGON] names=%s" % str(_dragons().map(func(n): return n.name)))
	check("finisher spawns exactly one dragon", spawned.size() == 1)
	if spawned.size() == 1:
		var d: Node3D = spawned[0]
		print("[SPIN_DRAGON] dragon=%s player=%s" % [str(d.global_position), str(player.global_position)])
		check("dragon is centred on the actor", d.global_position.distance_to(player.global_position) < 0.05)
		check("dragon scale follows the export", absf(d.scale.x - player.sun_dragon_scale) < 0.01)
		check("dragon is upright", d.global_transform.basis.y.dot(Vector3.UP) > 0.95)

	# A blocked repeat input must not stack a second dragon.
	player.request_continuous_spin()
	await _frames(2)
	check("repeat input does not stack dragons", _dragons().size() == 1)

	# The toggle must actually disable the effect.
	for d in _dragons():
		d.free()
	await _frames(2)
	player.sun_dragon_enabled = false
	player.action_state = 0
	player.request_continuous_spin()
	await _frames(2)
	check("toggle off spawns no dragon", _dragons().is_empty())
	check("spin itself still runs with the toggle off", player.action_state != 0)

	# Head tracking is off by decision: the dragon must hold its spawn bearing.
	player.sun_dragon_enabled = true
	player.action_state = 0
	player.request_continuous_spin()
	await _frames(2)
	var live := _dragons()
	if live.size() == 1:
		check("head tracking is off by default", not player.sun_dragon_head_tracking)
		check("dragon does not chase the blade by default", live[0].track_node == null)

	# The toggle must still work for anyone who wants it back.
	player.sun_dragon_head_tracking = true
	player.action_state = 0
	for d in _dragons():
		d.queue_free()
	await _frames(2)
	player.request_continuous_spin()
	await _frames(2)
	var opted := _dragons()
	if opted.size() == 1:
		check("the toggle re-enables blade tracking", opted[0].track_node != null and opted[0].track_node.name == "BladeTip")
	player.sun_dragon_head_tracking = false

	print("[SPIN_DRAGON] failures=%d" % failures)
	player.free()
	quit(failures)
