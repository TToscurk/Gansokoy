extends SceneTree
## P11 R2B 審圖（非 headless、只讀）：參道の石燈籠（土面に直接）と茶屋の W3（Idle が既定）を玩家高さで撮る。
##   godot --path . --script res://tools/p11r2b/shot_wave3.gd -- <outdir/>
var v: Node3D
var cam: Camera3D

func _init() -> void:
	_run.call_deferred()

func _shot(outdir: String, nm: String, eye: Vector3, at: Vector3) -> void:
	cam.global_transform = Transform3D(Basis(), eye).looking_at(at, Vector3.UP)
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(outdir + nm + ".png")

func _run() -> void:
	var outdir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	v = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	await process_frame
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.set_hour(10.0)
	cam = Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame
	var lg := v.get_node("ShrineApproachP10/Lanterns")
	var n := 0
	for t in lg.get_children():
		if not String(t.name).begins_with("Toro_") or n >= 3:
			continue
		var p := (t as Node3D).global_position
		var fw := (t as Node3D).global_basis.z
		var side := (t as Node3D).global_basis.x
		await _shot(outdir, "lantern_%s_side_low" % t.name, p + side * 2.2 + Vector3.UP * 0.35, p + Vector3.UP * 0.25)
		await _shot(outdir, "lantern_%s_tps" % t.name, p + fw * 3.5 + side * 1.5 + Vector3.UP * 2.0, p + Vector3.UP * 0.8)
		n += 1
	var w3 := v.get_node("Population/PopulationP10").find_child("W3_chaya_f01", true, false) as Node3D
	if w3:
		var p := w3.global_position
		var f := w3.global_basis.z
		for k in 4:
			await _shot(outdir, "w3_t%02d" % (k * 5), p + f * 3.0 + Vector3.UP * 1.6, p + Vector3.UP * 1.1)
			for i in 300:
				await process_frame
	print("[W3SHOT] done")
	quit(0)
