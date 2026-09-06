extends SceneTree
## Find the ends of 龍石像橋 (the bridge spans x≈400-450 at z≈-144, over a
## channel whose bed sits at y=-6.10) and pick a standable spot beside it.

var main: Node = null
var player: Node = null

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _g(space: PhysicsDirectSpaceState3D, x: float, z: float) -> Array:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200.0, z), Vector3(x, -80.0, z))
	q.collide_with_areas = false
	var h: Dictionary = space.intersect_ray(q)
	if not h.has("position"):
		return [999.0, "-"]
	return [h.position.y, String(h.collider.name)]

func _stand(pos: Vector3, tag: String) -> void:
	player.global_position = pos + Vector3(0, 3.0, 0)
	player.velocity = Vector3.ZERO
	await _wait(60)
	print("[BR] %-16s try %s → (%.2f, %.3f, %.2f) on_floor=%s"
		% [tag, str(pos), player.global_position.x, player.global_position.y,
			player.global_position.z, str(player.is_on_floor())])

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "")
	await _wait(80)
	player = main.get_node_or_null("Player")
	var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state

	print("[BR] === 沿橋軸 z=-144，找兩端接地點 ===")
	for x in [370.0, 380.0, 390.0, 395.0, 398.0, 452.0, 455.0, 460.0, 470.0, 480.0]:
		var g := _g(space, x, -144.0)
		print("[BR] x=%6.1f y=%7.3f  %s" % [x, g[0], g[1]])

	print("[BR] === 龍神像周邊 x≈362, z≈-163 ===")
	for z in [-180.0, -170.0, -163.0, -155.0, -145.0]:
		var g2 := _g(space, 362.0, z)
		print("[BR] x=362 z=%7.1f y=%7.3f  %s" % [z, g2[0], g2[1]])
	for x in [340.0, 350.0, 362.0, 375.0, 390.0]:
		var g3 := _g(space, x, -163.0)
		print("[BR] x=%6.1f z=-163 y=%7.3f  %s" % [x, g3[0], g3[1]])

	print("[BR] === 可站立測試（橋頭候選）===")
	await _stand(Vector3(395.0, 0.0, -144.0), "橋西端")
	await _stand(Vector3(390.0, 0.0, -144.0), "橋西外")
	await _stand(Vector3(455.0, 0.0, -144.0), "橋東端")
	await _stand(Vector3(423.0, 3.0, -144.0), "橋中央")
	await _stand(Vector3(380.0, 0.0, -150.0), "龍像與橋之間")
	quit(0)
