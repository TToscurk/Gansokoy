extends SceneTree
## 稗田邸室內漫遊：從落點走向房間各角落，找穿牆、卡角、掉出地板。
## 傳送區只證明「出得去」，這支證明「房間本身走得動」。

var failures := 0
var main: Node = null
var player: Node = null
var yaw: Node3D = null

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[ROAM] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _hold(a: String, down: bool) -> void:
	var e := InputEventAction.new()
	e.action = a
	e.pressed = down
	Input.parse_input_event(e)

## 房間的可走範圍：用地板 mesh 的 AABB 推，排除遠景與巨大網格。
func _room_bounds(mr: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in mr.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		if b.size.x > 90.0 or b.size.z > 90.0:
			continue
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box

## 朝某方向持續走 secs 秒，回傳走過的水平距離與是否掉出地板。
func _walk_dir(dir: Vector3, secs: float) -> Dictionary:
	var start: Vector3 = player.global_position
	var min_y: float = start.y
	yaw.rotation.y = atan2(-dir.x, -dir.z)
	_hold("move_forward", true)
	var t := 0.0
	while t < secs:
		await physics_frame
		await process_frame
		t += get_root().get_process_delta_time()
		min_y = minf(min_y, player.global_position.y)
	_hold("move_forward", false)
	await _wait(10)
	var moved: float = Vector2(player.global_position.x - start.x,
		player.global_position.z - start.z).length()
	return {"moved": moved, "min_y": min_y, "end": player.global_position}

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)

	for spec in [["hieda1f", "slice"], ["hieda2f", "hieda1f"], ["hieda3f", "hieda2f"]]:
		var id: String = spec[0]
		main.load_map(id, spec[1])
		await _wait(70)
		player = main.get_node_or_null("Player")
		player.visible = false
		if yaw == null:
			yaw = Node3D.new()
			main.add_child(yaw)
		player.input_yaw_node = yaw
		var home: Vector3 = player.global_position
		var bounds := _room_bounds(main.map_root)
		print("[ROAM] %s 房間範圍 pos=%s size=%s 落點=%s"
			% [id, str(bounds.position.round()), str(bounds.size.round()), str(home.round())])

		var floor_y: float = home.y
		var walked_any := false
		var escaped := false
		var fell := false

		# 八個方向各走 4 秒，看走不走得動、有沒有穿出房間或掉下去。
		for i in 8:
			var ang := TAU * float(i) / 8.0
			player.global_position = home
			player.velocity = Vector3.ZERO
			await _wait(15)
			if main.current_id != id:
				# 撞到傳送區就換圖了，重載繼續。
				main.load_map(id, spec[1])
				await _wait(70)
				player = main.get_node_or_null("Player")
				player.visible = false
				player.input_yaw_node = yaw
				continue
			var r: Dictionary = await _walk_dir(Vector3(sin(ang), 0.0, cos(ang)), 4.0)
			var moved: float = float(r.moved)
			var endp: Vector3 = r.end
			if moved > 1.5:
				walked_any = true
			# 掉出地板：比落點低超過 2 m。
			if float(r.min_y) < floor_y - 2.0:
				fell = true
				print("[ROAM] %s 方向 %d：掉下去了（最低 y=%.2f，地板 y=%.2f）"
					% [id, i, r.min_y, floor_y])
			# 穿出房間：跑到 AABB 之外 5 m 以上。
			var out_x: float = maxf(bounds.position.x - endp.x,
				endp.x - (bounds.position.x + bounds.size.x))
			var out_z: float = maxf(bounds.position.z - endp.z,
				endp.z - (bounds.position.z + bounds.size.z))
			if maxf(out_x, out_z) > 5.0 and main.current_id == id:
				escaped = true
				print("[ROAM] %s 方向 %d：走出房間外 %.1f m（%s）"
					% [id, i, maxf(out_x, out_z), str(endp.round())])
			print("[ROAM] %s 方向 %d：走了 %.1f m → %s（圖=%s）"
				% [id, i, moved, str(endp.round()), main.current_id])
			if main.current_id != id:
				main.load_map(id, spec[1])
				await _wait(70)
				player = main.get_node_or_null("Player")
				player.visible = false
				player.input_yaw_node = yaw

		check("%s 房間走得動（至少一個方向前進 > 1.5 m）" % id, walked_any)
		check("%s 不會穿牆走出房間" % id, not escaped)
		check("%s 不會掉出地板" % id, not fell)

	print("[ROAM] failures=%d" % failures)
	quit(failures)
