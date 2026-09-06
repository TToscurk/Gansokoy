extends SceneTree
## What blocks the trail at z ≈ -230?

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

func _path_of(n: Node) -> String:
	var out := ""
	var cur := n
	while cur != null and cur != main:
		out = "/" + String(cur.name) + out
		cur = cur.get_parent()
	return out

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(2)
	main.load_map("trail", "shrine")
	await _wait(40)
	player = main.get_node_or_null("Player")

	var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state

	# Ground profile along the stuck stretch.
	print("[TRAIL] --- ground profile along x=7 ---")
	for z in [-245.0, -240.0, -235.0, -232.0, -230.0, -229.0, -228.0, -226.0, -224.0, -220.0, -210.0]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(7.0, 80.0, z), Vector3(7.0, -80.0, z))
		q.collide_with_areas = false
		var hit: Dictionary = space.intersect_ray(q)
		var nm: String = _path_of(hit.collider) if hit.has("collider") else "-"
		var y: float = hit.position.y if hit.has("position") else 999.0
		print("[TRAIL] z=%7.1f ground_y=%7.2f  %s" % [z, y, nm])

	# Forward cast at knee and chest height from the stuck spot.
	print("[TRAIL] --- forward casts from the stuck spot ---")
	for h in [0.25, 0.6, 1.2, 1.8]:
		var from := Vector3(7.0, 8.9 + h, -230.5)
		var to := Vector3(7.0, 8.9 + h, -215.0)
		var fq := PhysicsRayQueryParameters3D.create(from, to)
		fq.collide_with_areas = false
		var fh: Dictionary = space.intersect_ray(fq)
		if fh.has("collider"):
			print("[TRAIL] h=%.2f blocked %.2f m ahead by %s at %s"
				% [h, from.distance_to(fh.position), _path_of(fh.collider), _v(fh.position)])
		else:
			print("[TRAIL] h=%.2f clear for 15 m" % h)

	# Sweep sideways: is there a gap the walker just missed?
	print("[TRAIL] --- lateral scan at z=-228 (is there any opening?) ---")
	for x in [-20.0, -10.0, -4.0, 0.0, 4.0, 7.0, 12.0, 20.0, 30.0]:
		var from2 := Vector3(x, 20.0, -234.0)
		var to2 := Vector3(x, 20.0, -222.0)
		var q2 := PhysicsRayQueryParameters3D.create(from2, to2)
		q2.collide_with_areas = false
		var h2: Dictionary = space.intersect_ray(q2)
		var blocker: String = _path_of(h2.collider) if h2.has("collider") else "clear"
		print("[TRAIL] x=%6.1f at y=20 : %s" % [x, blocker])

	# What does the player physically collide with when pushed forward?
	print("[TRAIL] --- physical push test ---")
	player.global_position = Vector3(7.0, 9.4, -232.0)
	player.velocity = Vector3.ZERO
	await _wait(10)
	var start: Vector3 = player.global_position
	for i in 120:
		player.velocity.x = 0.0
		player.velocity.z = 7.0
		player.move_and_slide()
		await physics_frame
	print("[TRAIL] pushed from %s to %s" % [_v(start), _v(player.global_position)])
	for i in player.get_slide_collision_count():
		var c: KinematicCollision3D = player.get_slide_collision(i)
		var col: Object = c.get_collider()
		print("[TRAIL] colliding with %s normal=%s" % [_path_of(col) if col else "?", str(c.get_normal())])

	quit(0)
