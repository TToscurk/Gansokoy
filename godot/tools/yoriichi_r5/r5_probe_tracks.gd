extends SceneTree
## R5：唯讀列出動畫資源的骨軌（檢查手指軌是否在內）。
##   godot --headless --path . -s res://tools/yoriichi_r5/r5_probe_tracks.gd -- res://path.res
func _initialize() -> void:
	var p := OS.get_cmdline_user_args()[0]
	var a: Animation = load(p)
	var names := []
	for i in a.get_track_count():
		names.append(str(a.track_get_path(i)).get_slice(":", 1))
	var hand := names.filter(func(n): return n.contains("Hand"))
	print("TRACKS ", names.size(), " hand=", hand)
	quit()
