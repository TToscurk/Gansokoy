extends SceneTree
## P11 R2D 審圖（非 headless、只讀）：竜骨車 → 分水 → 原田區／N0／T0 の接続を 10:00 で撮る。
const VIEWS := [
	["t0_inlet_top", Vector3(330.2, 9.0, 72.0), Vector3(330.2, 0.3, 78.5)],
	["n0_inlet_top", Vector3(349.0, 9.0, -41.0), Vector3(352.4, 0.1, -45.5)],
	["t0_inlet_tps", Vector3(327.0, 2.0, 73.0), Vector3(330.4, 0.35, 78.2)],
]
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var outdir: String = OS.get_cmdline_user_args()[0]
	var only := OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(outdir)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	await process_frame
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.set_hour(10.0)
	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.near = 0.05
	root.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame
	for vw in VIEWS:
		cam.global_transform = Transform3D(Basis(), vw[1]).looking_at(vw[2], Vector3.UP)
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(outdir + String(vw[0]) + ".png")
	print("[BSHOT] done")
	quit(0)
