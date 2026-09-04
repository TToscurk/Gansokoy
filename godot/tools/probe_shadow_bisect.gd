extends SceneTree
## Bisect the shadow cost by GROUP: turn off cast_shadow on one top-level
## subtree at a time (everything else as the cull leaves it) and read FPS at
## the street view. Whichever group buys the most FPS is the real cost.

const WARM := 40
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
	cam.fov = 72.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(235, 1.7, -10)
	cam.look_at(Vector3(235, 3, 60))
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 90:
		await process_frame

	var base := await _measure(vp)
	print("[bisect] 基線 FPS %.1f GPU %.1f ms 陰影面 %d" % [base[0], base[1], base[2]])

	var groups := []
	for c in scene.get_children():
		if c is Node3D:
			groups.append(c)
	var rows := []
	for g in groups:
		var saved := {}
		_off(g, saved)
		if saved.is_empty():
			continue
		var m := await _measure(vp)
		for k in saved:
			(k as GeometryInstance3D).cast_shadow = saved[k]
		rows.append([m[0] - base[0], g.name, m[0], m[1], m[2], saved.size()])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows:
		print("[bisect] 關 %-24s 陰影 → FPS %5.1f (+%5.1f)  GPU %5.1f ms  陰影面 %9d  (%d 個投影體)" % [r[1], r[2], r[0], r[3], r[4], r[5]])
	print("done")
	quit(0)


func _off(n: Node, saved: Dictionary) -> void:
	if n is GeometryInstance3D and (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		saved[n] = (n as GeometryInstance3D).cast_shadow
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_off(c, saved)


func _measure(vp: RID) -> Array:
	for i in WARM:
		await process_frame
	var f := []
	var g := 0.0
	var sh := 0
	for i in SAMPLE:
		await process_frame
		f.append(Performance.get_monitor(Performance.TIME_FPS))
		g += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		sh = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	f.sort()
	return [f[f.size() / 2], g / SAMPLE, sh]
