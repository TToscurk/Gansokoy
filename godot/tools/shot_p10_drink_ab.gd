extends SceneTree
## R3c W3 Drink A/B — rendered comparison in the real village (never saves world or frozen resources).
## Same cameras / same moments for every candidate:
##   close-up  front-3/4 1.7 m + left profile 1.7 m  × 5 moments (hold, approach, sip, widest arm, return)
##   TPS       4 / 6 / 8 m, camera 2.5 m up, fov 75 (player Camera3D default) × 2 moments (hold, sip)
## Usage: godot --path godot --script res://tools/shot_p10_drink_ab.gd -- <outdir/>
const CANDS := [
	# key, clip, cup grip (LeftHand axes, foot centre from LeftMiddleProximal), cup up-axis (LeftHand axes),
	# moments [hold, approach, sip (rim nearest the lips), widest (largest cup tilt), return]
	["A_current", "drinking_a030", Vector3(0.020, 0.0, 0.022), Vector3(-1, 0, 0), [1.0, 2.4, 3.07, 4.1, 6.0]],
	["B1_final", "drinking_im1_a030", Vector3(0.04, -0.02, 0.09), Vector3(-0.9624, 0.2634, -0.0662), [1.0, 3.0, 3.23, 4.13, 6.0]],
	["B2_rejected", "watercooler_a030", Vector3(0.04, -0.02, 0.09), Vector3(-0.9624, 0.2634, -0.0662), [5.0, 43.0, 43.5, 0.23, 20.0]],
]
const MOMENT := ["hold", "approach", "sip", "widest", "return"]
var cam: Camera3D

func _initialize():
	run.call_deferred()

func shot(path: String) -> bool:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var im := root.get_texture().get_image()
	if im.get_size() != Vector2i(1920, 1080): return false
	return im.save_jpg(path, 0.92) == OK

func run():
	root.borderless = true
	root.position = Vector2i.ZERO
	root.size = Vector2i(1920, 1080)
	var world: Node3D = load("res://maps/village_v2/village_v2.tscn").instantiate()
	root.add_child(world)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if world.has_node(nm): world.get_node(nm).visible = false
	for n in world.get_node("Districts").find_children("*ParcelLines*", "", true, false): n.visible = false
	for i in 20: await process_frame
	for n in root.get_children():
		if n.has_method("set_hour"): n.set_hour(10.0); n.set_process(false)
	var pop := world.get_node("Population/PopulationP10")
	var overlay := world.get_node("Population/ActivityP10")
	for i in 4: await process_frame
	for b in pop.find_children("*", "AnimatableBody3D", true, false):
		b.set_physics_process(false)
		b.get_node("NPC").player.speed_scale = 0.0
	cam = Camera3D.new(); cam.near = 0.04; cam.far = 900
	root.add_child(cam); cam.make_current()
	var outdir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	var actor: Node3D = pop.get_node("MarketWest/W3_chaya_f01")
	var ap: AnimationPlayer = actor.get_node("NPC").player
	var base := actor.global_position
	var manifest := []
	for c in CANDS:
		var an: Animation = load("res://animations/npc_activity_p10/chaya_f01/%s_grounded.res" % c[1])
		var lib := AnimationLibrary.new(); lib.add_animation(&"c", an)
		if ap.has_animation_library(&"dab"): ap.remove_animation_library(&"dab")
		ap.add_animation_library(&"dab", lib)
		ap.play(&"dab/c"); ap.speed_scale = 0.0
		overlay.cup_grip = c[2]
		overlay.cup_axis = c[3]
		var views := [
			["close_front34", deg_to_rad(35.0), 1.7, 1.55, 1.42, 35.0, [0, 1, 2, 3, 4]],
			["close_profileL", deg_to_rad(90.0), 1.7, 1.50, 1.38, 35.0, [0, 1, 2, 3, 4]],
			["tps_4m", deg_to_rad(30.0), 4.0, 2.5, 1.15, 75.0, [0, 2]],
			["tps_6m", deg_to_rad(30.0), 6.0, 2.5, 1.15, 75.0, [0, 2]],
			["tps_8m", deg_to_rad(30.0), 8.0, 2.5, 1.15, 75.0, [0, 2]],
		]
		for v in views:
			var off: Vector3 = actor.global_basis * Vector3(sin(v[1]) * v[2], 0.0, cos(v[1]) * v[2])
			cam.fov = v[5]
			cam.global_position = base + off + Vector3(0, v[3], 0)
			cam.look_at(base + Vector3(0, v[4], 0))
			for mi in v[6]:
				var t: float = c[4][mi]
				ap.seek(t, true)
				overlay.update_props()
				var name := "%s__%s__%d_%s.jpg" % [c[0], v[0], mi, MOMENT[mi]]
				if not await shot(outdir + name): quit(2); return
				manifest.append({"file": name, "candidate": c[0], "clip": c[1], "grip": [c[2].x, c[2].y, c[2].z], "axis": [c[3].x, c[3].y, c[3].z],
					"view": v[0], "moment": MOMENT[mi], "time": t, "camera": str(cam.global_transform), "fov": v[5]})
		print("[DRINKSHOT] ", c[0], " done")
	var f := FileAccess.open(outdir + "capture.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	print("[DRINKSHOT] ", manifest.size(), " images")
	quit(0)
