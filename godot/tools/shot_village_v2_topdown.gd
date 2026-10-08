extends SceneTree
## P10 R4 下調べ用の真上撮影（非 headless、Forward+、10:00）：x0,z0,x1,z1 の範囲を正射影で撮る。
## godot --path godot --script res://tools/shot_village_v2_topdown.gd -- x0,z0,x1,z1 <out.png> [px_per_m] [hide=Population,HumanUse]
func _initialize():
	go.call_deferred()

func go():
	var args := OS.get_cmdline_user_args()
	var r := args[0].split(",")
	var x0 := float(r[0]); var z0 := float(r[1]); var x1 := float(r[2]); var z1 := float(r[3])
	var out := args[1]
	var ppm := float(args[2]) if args.size() > 2 and not args[2].begins_with("hide=") else 8.0
	var hide := []
	for a in args:
		if a.begins_with("hide="): hide = Array(a.trim_prefix("hide=").split(","))
	var w := int((x1 - x0) * ppm); var h := int((z1 - z0) * ppm)
	root.size = Vector2i(w, h)
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"] + hide:
		if v.has_node(nm): v.get_node(nm).visible = false
	for n in v.get_node("Districts").find_children("*ParcelLines*", "", true, false): n.visible = false
	for c in root.get_children():
		if c.has_method("set_hour"): c.set_hour(10.0); c.set_process(false)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = z1 - z0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 1.0; cam.far = 400.0
	root.add_child(cam)
	cam.global_position = Vector3((x0 + x1) * 0.5, 150.0, (z0 + z1) * 0.5)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.make_current()
	for i in 40: await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("[TOP] ", out, " ", img.get_size())
	quit(0)
