extends SceneTree
## R3c.1 readability probe (read-only): for each population review camera, where every actor lands on
## screen (feet/head pixels, pixel height) and how much of the body a physics ray from the camera
## reaches (5 points). Same camera solve as shot_p10_activity_population.gd. Headless OK.
## Usage: godot --headless --path godot --script res://tools/probe_p10_readability.gd -- <out.json>
const VG = preload("res://tools/verify_village_v2_population.gd")

func _initialize():
	run.call_deferred()

func run():
	var out: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1920, 1080)
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 20: await process_frame
	var sp := v.get_world_3d().direct_space_state
	var helper = VG.new()
	var cam := Camera3D.new(); cam.fov = 75.0; cam.near = 0.05; cam.far = 900.0
	root.add_child(cam); cam.make_current()
	var pop := v.get_node("Population/PopulationP10")
	var actors := pop.find_children("*", "AnimatableBody3D", true, false)
	var ex: Array[RID] = []
	for b in actors: ex.append(b.get_rid())
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/shot_village_v2_population_views.json"))
	var res := {}
	for vw: Dictionary in views:
		var p := Vector2(vw.player[0], vw.player[1])
		var d: Dictionary = vw.duplicate(true)
		cam.global_transform = helper._tps(v, sp, d)
		var rows := []
		for b: Node3D in actors:
			var feet := b.global_position
			var head := feet + Vector3(0, 1.62, 0)
			var vis := 0
			for h in [0.3, 0.7, 1.0, 1.3, 1.55]:
				var tp := feet + Vector3(0, h, 0)
				var q := PhysicsRayQueryParameters3D.create(cam.global_position, tp, 0xFFFFFFFF, ex)
				if sp.intersect_ray(q).is_empty(): vis += 1
			var behind := cam.is_position_behind(feet)
			var sf := cam.unproject_position(feet); var sh := cam.unproject_position(head)
			var on := not behind and sf.x > -50 and sf.x < 1970 and sh.y < 1080 and sf.y > 0
			rows.append({"actor": String(pop.get_path_to(b)), "dist_m": snappedf(cam.global_position.distance_to(feet + Vector3(0, 1, 0)), 0.1),
				"on_screen": on, "feet_px": [int(sf.x), int(sf.y)], "head_px": [int(sh.x), int(sh.y)], "height_px": int(sf.y - sh.y) if on else 0, "ray_visible_of5": vis})
		res[vw.name] = {"camera": str(cam.global_transform), "actors": rows}
		print("[READ] ", vw.name)
		for r in rows:
			if r.on_screen: print("   ", r.actor, " d=", r.dist_m, " h=", r.height_px, "px vis=", r.ray_visible_of5, "/5 feet=", r.feet_px)
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(res, "  "))
	helper.free()
	quit(0)
