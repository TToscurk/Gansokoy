extends SceneTree
## Isolate why walking into the shrine→trail portal does not change maps.

var main: Node = null
var player: Node = null

func _init() -> void:
	_run.call_deferred()

func _v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _portal(nm: String) -> Area3D:
	for c in main.get_children():
		for g in c.get_children():
			if String(g.name) == nm:
				return g
	return null

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(2)
	main.load_map("shrine", "")
	await _wait(30)
	player = main.get_node_or_null("Player")
	print("[DIAG2] map=%s spawn=%s cooldown=%.2f"
		% [main.current_id, _v(player.global_position), main.portal_cooldown])

	# Let the arrival cooldown expire, watching whether the map changes by itself.
	var waited := 0.0
	while main.portal_cooldown > 0.0 and waited < 10.0:
		await physics_frame
		await process_frame
		waited += get_root().get_process_delta_time()
	print("[DIAG2] after cooldown: map=%s pos=%s (waited %.2f s)"
		% [main.current_id, _v(player.global_position), waited])

	# Does load_map to trail work at all when called directly?
	main.load_map("trail", "shrine")
	await _wait(40)
	print("[DIAG2] direct load_map('trail'): map=%s pos=%s"
		% [main.current_id, _v(player.global_position)])
	var tp := _portal("Portal_village")
	print("[DIAG2] trail has Portal_village: %s" % (_v(tp.global_position) if tp else "MISSING"))

	# Back to the shrine and step into the portal by hand.
	main.load_map("shrine", "")
	await _wait(40)
	var portal := _portal("Portal_trail")
	print("[DIAG2] back in %s, portal at %s, cooldown=%.2f"
		% [main.current_id, _v(portal.global_position) if portal else "?", main.portal_cooldown])
	var w2 := 0.0
	while main.portal_cooldown > 0.0 and w2 < 10.0:
		await physics_frame
		await process_frame
		w2 += get_root().get_process_delta_time()

	if portal == null or not is_instance_valid(portal):
		print("[DIAG2] portal vanished before the walk-in test")
		quit(1)
		return

	var z: float = 49.0
	var steps := 0
	while z < 55.0 and steps < 120:
		z += 0.15
		player.global_position = Vector3(0.0, player.global_position.y + 0.05, z)
		player.velocity = Vector3.ZERO
		await physics_frame
		await process_frame
		steps += 1
		if main.current_id != "shrine":
			print("[DIAG2] MAP CHANGED at z=%.2f → %s" % [z, main.current_id])
			break
		if is_instance_valid(portal):
			var inside: bool = portal.get_overlapping_bodies().has(player)
			if inside:
				print("[DIAG2] inside portal at z=%.2f y=%.2f map=%s cooldown=%.2f"
					% [z, player.global_position.y, main.current_id, main.portal_cooldown])
		else:
			print("[DIAG2] portal freed at z=%.2f (map=%s)" % [z, main.current_id])
			break
	print("[DIAG2] RESULT map=%s pos=%s" % [main.current_id, _v(player.global_position)])
	quit(0)
