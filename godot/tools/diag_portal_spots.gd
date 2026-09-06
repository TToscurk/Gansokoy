extends SceneTree
## Probe the three portal spots the user asked for:
##   A. trail entrance — the SOUTH torii (大鳥居, z≈+102), grass and stone rows
##   B. confirm 稗田邸 lies beyond the NORTH torii (大鳥居2, z≈-80)
##   C. 香霖堂 portal — beside 龍石像橋 (x≈423, z≈-144), near 龍神像

var main: Node = null
var player: Node = null

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _ground(space: PhysicsDirectSpaceState3D, x: float, z: float) -> Array:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200.0, z), Vector3(x, -80.0, z))
	q.collide_with_areas = false
	var h: Dictionary = space.intersect_ray(q)
	if not h.has("position"):
		return [999.0, "-"]
	var nm := String(h.collider.name)
	var par: Node = h.collider.get_parent()
	if par != null:
		nm = String(par.name) + "/" + nm
	return [h.position.y, nm]

func _stand(pos: Vector3, tag: String) -> void:
	player.global_position = pos + Vector3(0, 3.0, 0)
	player.velocity = Vector3.ZERO
	await _wait(60)
	print("[PROBE] %-18s try %s → settled (%.2f, %.3f, %.2f) on_floor=%s"
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

	print("[PROBE] === A. 南側大鳥居周邊（獸道入口候選）x≈236, z≈+102 ===")
	for z in [90.0, 96.0, 102.0, 108.0, 114.0, 120.0, 130.0]:
		var g := _ground(space, 236.0, z)
		print("[PROBE] x=236 z=%6.1f y=%7.3f  %s" % [z, g[0], g[1]])
	print("[PROBE] --- 橫斷面 z=110 ---")
	for x in [215.0, 225.0, 236.0, 245.0, 255.0]:
		var g2 := _ground(space, x, 110.0)
		print("[PROBE] x=%6.1f z=110 y=%7.3f  %s" % [x, g2[0], g2[1]])

	print("[PROBE] === B. 北側大鳥居 → 稗田邸 方向 x≈235 ===")
	for z in [-80.0, -95.0, -110.0, -125.0, -138.0]:
		var g3 := _ground(space, 235.0, z)
		print("[PROBE] x=235 z=%7.1f y=%7.3f  %s" % [z, g3[0], g3[1]])

	print("[PROBE] === C. 龍石像橋周邊（香霖堂候選）x≈423, z≈-144 ===")
	for x in [400.0, 410.0, 420.0, 430.0, 440.0, 450.0]:
		var g4 := _ground(space, x, -144.0)
		print("[PROBE] x=%6.1f z=-144 y=%7.3f  %s" % [x, g4[0], g4[1]])
	print("[PROBE] --- 沿橋軸 x=423 ---")
	for z in [-165.0, -155.0, -144.0, -135.0, -125.0]:
		var g5 := _ground(space, 423.0, z)
		print("[PROBE] x=423 z=%7.1f y=%7.3f  %s" % [z, g5[0], g5[1]])

	print("[PROBE] === 可站立測試 ===")
	await _stand(Vector3(236.0, 0.0, 110.0), "A 南鳥居外")
	await _stand(Vector3(236.0, 0.0, 96.0), "A 南鳥居內")
	await _stand(Vector3(423.0, 0.0, -135.0), "C 橋頭(村側)")
	await _stand(Vector3(423.0, 0.0, -155.0), "C 橋尾(外側)")
	await _stand(Vector3(410.0, 0.0, -144.0), "C 橋西")
	await _stand(Vector3(440.0, 0.0, -144.0), "C 橋東")
	quit(0)
