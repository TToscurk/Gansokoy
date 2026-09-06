extends SceneTree
## Locate the landmarks the user named, in slice world coordinates:
##   * every 鳥居 (torii) — which one is the trail entrance, which faces 稗田邸
##   * 稗田邸 (the Hieda mansion) at the far end
##   * 龍神像 + 龍石像橋 (dragon statue and its bridge) for the 香霖堂 portal

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box

func _report(n: Node3D, tag: String) -> void:
	var box := _aabb(n)
	var c := box.get_center()
	print("[MARK] %-10s %-22s origin=(%.1f, %.1f, %.1f) centre=(%.1f, %.1f, %.1f) size=(%.1f, %.1f, %.1f)"
		% [tag, n.name, n.global_position.x, n.global_position.y, n.global_position.z,
			c.x, c.y, c.z, box.size.x, box.size.y, box.size.z])

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "")
	await _wait(80)
	var mr: Node3D = main.map_root

	# Torii gates can be nested anywhere; search by name fragment.
	print("[MARK] === 鳥居 ===")
	for n in mr.find_children("*鳥居*", "Node3D", true, false):
		_report(n, "torii")
	print("[MARK] === 稗田 ===")
	for n in mr.find_children("*稗田*", "Node3D", true, false):
		_report(n, "hieda")
	print("[MARK] === 龍 ===")
	for n in mr.find_children("*龍*", "Node3D", true, false):
		_report(n, "dragon")
	print("[MARK] === 橋 ===")
	for n in mr.find_children("*橋*", "Node3D", true, false):
		_report(n, "bridge")
	print("[MARK] === 石 (stones / paving) ===")
	var stones := 0
	for n in mr.find_children("*石*", "Node3D", true, false):
		if stones < 12:
			_report(n, "stone")
		stones += 1
	print("[MARK] 石-named nodes: %d" % stones)

	quit(0)
