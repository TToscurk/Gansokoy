extends SceneTree
## R3c.1 motion evidence: the review cameras of shot_p10_activity_population.gd, but with the residents
## animating normally (patrol walkers moving) for 6 s, captured at 4 fps. Runs once with the activity layer
## off (R3b) and once on (R3c.1). Never saves the world. Same camera solve / player placement as the stills.
## Usage: godot --path godot --script res://tools/shot_p10_r3c1_motion.gd -- <outdir/>
const VG = preload("res://tools/verify_village_v2_population.gd")
const VIEWS := ["1_market_tps", "2_market_west_tps", "3_main_street_tps"]
var cam: Camera3D

func _initialize():
	run.call_deferred()

func run():
	root.borderless = true
	root.position = Vector2i.ZERO
	root.size = Vector2i(1920, 1080)
	var outdir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm): v.get_node(nm).visible = false
	for n in v.get_node("Districts").find_children("*ParcelLines*", "", true, false): n.visible = false
	for i in 20: await process_frame
	for c in root.get_children():
		if c.has_method("set_hour"): c.set_hour(10.0); c.set_process(false)
	var sp := v.get_world_3d().direct_space_state
	var helper = VG.new()
	var player: Node3D = (load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene).instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	cam = Camera3D.new(); cam.fov = 75.0; cam.near = 0.05; cam.far = 900.0
	root.add_child(cam); cam.make_current()
	var overlay := v.get_node("Population/ActivityP10")
	for i in 4: await process_frame
	var views := {}
	for vw: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://tools/shot_village_v2_population_views.json")):
		views[vw.name] = vw
	var manifest := []
	for mode in ["R3b", "R3c1"]:
		overlay.set_enabled(mode == "R3c1")
		for vn in VIEWS:
			var vw: Dictionary = views[vn]
			var p := Vector2(vw.player[0], vw.player[1])
			player.global_position = Vector3(p.x, VG._ground(sp, p) + 0.03, p.y)
			var f := (Vector2(vw.target[0], vw.target[1]) - p).normalized()
			player.rotation.y = atan2(-f.x, -f.y)
			cam.global_transform = helper._tps(v, sp, vw.duplicate(true))
			for k in 24:
				for j in 15: await process_frame   # ~0.25 s at 60 fps
				await RenderingServer.frame_post_draw
				var im := root.get_texture().get_image()
				var name := "%s__%s__%02d.jpg" % [mode, vn, k]
				if im.get_size() != Vector2i(1920, 1080) or im.save_jpg(outdir + name, 0.9) != OK: quit(2); return
				manifest.append({"file": name, "mode": mode, "view": vn, "frame": k})
			print("[R31MOTION] ", mode, " ", vn)
	FileAccess.open(outdir + "capture.json", FileAccess.WRITE).store_string(JSON.stringify(manifest, "  "))
	helper.free()
	quit(0)
