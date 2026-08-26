extends SceneTree
const WARMUP := 40
const SAMPLE := 90
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main = packed.instantiate()
	root.add_child(main)
	await process_frame
	for m in ["village", "trail", "kourindou"]:
		main.load_map(m, "")
		for i in WARMUP: await process_frame
		var t0 := Time.get_ticks_usec()
		var worst: float = 0.0
		for i in SAMPLE:
			var a := Time.get_ticks_usec()
			await process_frame
			worst = maxf(worst, (Time.get_ticks_usec() - a) / 1000.0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / SAMPLE
		print("%-11s 平均 %7.2f ms (%5.1f fps)  最悪 %7.2f ms  draw %5d" % [
			m, ms, 1000.0 / maxf(ms, 0.001), worst,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	quit(0)
