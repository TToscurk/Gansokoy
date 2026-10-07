extends SceneTree
## R3c.1 Readability candidates — render each Sit / Carry / Talk candidate on its actor from the review
## cameras that actually see that actor (same camera solve as shot_p10_activity_population.gd), plus a
## 6 m TPS-height camera. Never saves the world or any frozen resource.
## Usage: godot --path godot --script res://tools/shot_p10_r3c1_candidates.gd -- <outdir/>
const VG = preload("res://tools/verify_village_v2_population.gd")
const ACT_DIR := "res://animations/npc_activity_p10/"
## actor path, cid, review views, candidate clips ("" = R3b baseline clip)
const SETS := [
	["MarketWest/W4_yakusou_f01", "yakusou_f01", ["2_market_west_tps"], ["", "sit_talk_a_a030", "sit_talk_b_a030"]],
	["MainStreet/S3_yakusou_f01", "yakusou_f01", ["3_main_street_tps"], ["", "talk_twohands_a030", "argue_a030", "talk_funny_a030"]],
	["Market/M2_shufu_f01", "shufu_f01", ["1_market_tps", "4_market_high"], ["", "talk_general_a030", "talk_twohands_a030"]],
	["MainStreet/S4_sakanaya_m01", "sakanaya_m01", ["3_main_street_tps"], ["", "holding_walk_a038"]],
]
var cam: Camera3D

func _initialize():
	run.call_deferred()

func snap(path: String) -> bool:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var im := root.get_texture().get_image()
	if im.get_size() != Vector2i(1920, 1080): return false
	return im.save_jpg(path, 0.92) == OK

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
	cam = Camera3D.new(); cam.fov = 75.0; cam.near = 0.05; cam.far = 900.0
	root.add_child(cam); cam.make_current()
	var pop := v.get_node("Population/PopulationP10")
	var overlay := v.get_node("Population/ActivityP10")
	for i in 4: await process_frame
	for b in pop.find_children("*", "AnimatableBody3D", true, false):
		b.set_physics_process(false)
		b.get_node("NPC").player.speed_scale = 0.0
	var views := {}
	for vw: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://tools/shot_village_v2_population_views.json")):
		views[vw.name] = vw
	var manifest := []
	for s in SETS:
		var actor: Node3D = pop.get_node(s[0])
		var npc = actor.get_node("NPC")
		var ap: AnimationPlayer = npc.player
		var entry = null
		for e in overlay.entries:
			if e.path == s[0]: entry = e
		for clip_name: String in s[3]:
			var an: Animation
			if clip_name == "":
				an = entry.baseline if entry != null else ap.get_animation(&"idle")
			else:
				an = load(ACT_DIR + s[1] + "/" + clip_name + "_grounded.res")
				if entry != null and entry.opt.has("foot_speed") and entry.slot == "walk":
					an = overlay.retimed(an, float(actor.get("walk_speed")) / float(entry.opt.foot_speed))
			var lib := AnimationLibrary.new(); lib.add_animation(&"c", an)
			if ap.has_animation_library(&"r31"): ap.remove_animation_library(&"r31")
			ap.add_animation_library(&"r31", lib)
			ap.play(&"r31/c"); ap.speed_scale = 0.0
			if entry != null and entry.prop != null:
				entry.prop.visible = clip_name != ""
				if entry.has("body"): entry.body.collision_layer = 0
				if entry.has("seat"): entry.erase("seat")
			var cams := []
			for vn in s[2]:
				cams.append([vn, helper._tps(v, sp, views[vn].duplicate(true))])
			var off: Vector3 = actor.global_basis * Vector3(sin(deg_to_rad(30.0)) * 6.0, 0, cos(deg_to_rad(30.0)) * 6.0)
			var t6 := Transform3D(Basis(), actor.global_position + off + Vector3(0, 2.3, 0)).looking_at(actor.global_position + Vector3(0, 1.0, 0))
			cams.append(["tps6m", t6])
			var key := "%s__%s" % [String(actor.name), clip_name if clip_name != "" else "R3b"]
			for phase in 6:
				var t := an.length * phase / 6.0
				ap.seek(t, true)
				if entry != null and entry.prop != null and clip_name != "":
					if phase == 0 and entry.has("seat"): entry.erase("seat")
					overlay.update_props()
				for c in cams:
					cam.global_transform = c[1]
					var fname := "%s__%s__p%d.jpg" % [key, c[0], phase]
					if not await snap(outdir + fname): quit(2); return
					manifest.append({"file": fname, "actor": s[0], "clip": clip_name, "view": c[0], "phase": phase, "time": t, "camera": str(c[1])})
			print("[R31SHOT] ", key)
	FileAccess.open(outdir + "capture.json", FileAccess.WRITE).store_string(JSON.stringify(manifest, "  "))
	helper.free()
	quit(0)
