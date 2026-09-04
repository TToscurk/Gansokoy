extends SceneTree
## Time-series: does FPS decay while the scene sits still? Sample every second
## for N seconds from one fixed camera, printing FPS, GPU ms, VRAM, and RAM.
## If FPS falls while nothing changes, it is memory pressure / paging, not
## triangle count.

const SECONDS := 40


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
	print("[decay]  秒   FPS  GPU ms  VRAM MB  貼圖 MB  RAM MB  物件")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < SECONDS * 1000:
		var f := []
		var g := 0.0
		var n := 0
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 1000:
			await process_frame
			f.append(Performance.get_monitor(Performance.TIME_FPS))
			g += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			n += 1
		f.sort()
		print("[decay] %3d  %5.1f  %6.1f  %7.0f  %7.0f  %6.0f  %d" % [
			(Time.get_ticks_msec() - t0) / 1000,
			f[f.size() / 2], g / maxi(n, 1),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
			OS.get_static_memory_usage() / 1048576.0,
			Performance.get_monitor(Performance.OBJECT_COUNT)])
	print("done")
	quit(0)
