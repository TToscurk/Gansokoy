extends SceneTree
## 開場淡入實拍：黑幕、半淡、淡完三幀。
##   Godot --path godot --resolution 1280x720 --script tools/shot_opening.gd
const OUT := "D:/神社/shrine/work/shots/opening/"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	# t=0.5：黑幕停留中
	for i in 30:
		await physics_frame
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "1_black_t0.5.png")
	# t=2.5：淡入中段（1.4 停留 + 1.1 淡入）
	for i in 120:
		await physics_frame
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "2_mid_t2.5.png")
	# t=4.2：淡完、獨白起
	for i in 100:
		await physics_frame
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT + "3_done_t4.2.png")
	print("[OPEN] 3 shots")
	quit(0)
