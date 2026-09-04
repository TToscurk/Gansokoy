extends SceneTree
## Direct per-script _process cost: wrap each candidate's _process via
## a proxy timer (call it ourselves with process disabled), so GPU wait time
## cannot leak into the number the way Performance.TIME_PROCESS does.

const SAMPLE := 60


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(235, 1.7, -10)
	cam.look_at(Vector3(235, 3, 60))
	for i in 60:
		await process_frame

	var nodes: Array[Node] = []
	_collect(scene, nodes)
	for a in ["/root/SimpleGrass", "/root/DayNight", "/root/Weather", "/root/CyclopsAutoload"]:
		var n := root.get_node_or_null(a)
		if n != null:
			nodes.append(n)

	var frame_total := 0.0
	var per := {}
	for n in nodes:
		n.set_process(false)
		per[n] = 0.0
	for f in SAMPLE:
		var t0 := Time.get_ticks_usec()
		for n in nodes:
			if not is_instance_valid(n) or not n.has_method("_process"):
				continue
			var a := Time.get_ticks_usec()
			n._process(1.0 / 60.0)
			per[n] += (Time.get_ticks_usec() - a) / 1000.0
		frame_total += (Time.get_ticks_usec() - t0) / 1000.0
		await process_frame
	var rows := []
	for n in per:
		rows.append([per[n] / SAMPLE, n])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("[proc2] 所有 _process 合計平均 %.2f ms/幀" % (frame_total / SAMPLE))
	for r in rows:
		var n: Node = r[1]
		var sp := String(n.get_script().resource_path).get_file() if n.get_script() else n.get_class()
		print("[proc2]  %7.2f ms  %-30s %s" % [r[0], sp, n.get_path()])
	print("done")
	quit(0)


func _collect(n: Node, out: Array[Node]) -> void:
	if n.get_script() != null and n.has_method("_process") and n.is_processing():
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
