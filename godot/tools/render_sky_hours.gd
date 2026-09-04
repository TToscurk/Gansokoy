extends SceneTree
## Render the painted-cloud sky at several hours so the user can see the
## clouds relighting — the whole point of option A. A single afternoon shot
## would prove nothing; the failure mode is "still afternoon at midnight".

const HOURS := [6.5, 12.0, 17.8, 22.0]

var _out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)

	# Load only what the sky needs; the full slice scene takes ~30s and its
	# buildings would fill the frame.
	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
	var scene := packed.instantiate()
	scene.get_node("場景效能裁剪").set("使用減面建築", true)
	root.add_child(scene)
	var sky := scene.get_node("天象系統")
	sky.set("一日長度分鐘", 0.0)
	sky.set("天氣", 0)

	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.current = true
	# Street level, looking up the main street with sky filling the top 2/3.
	cam.global_position = Vector3(235.0, 1.7, -10.0)
	cam.look_at(Vector3(235.0, 40.0, 100.0), Vector3.UP)

	for i in 3:
		await process_frame

	for hr in HOURS:
		sky.set("時刻", hr)
		# Let weather smoothing and radiance settle.
		for i in 40:
			await process_frame
		var p := "%s/sky_%04.1f.png" % [_out, hr]
		root.get_texture().get_image().save_png(p)
		print("[SKY] %04.1f -> %s" % [hr, p])

	print("[SKY] done")
	quit(0)
