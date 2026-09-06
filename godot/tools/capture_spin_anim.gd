extends SceneTree

func _init():
	_run.call_deferred()

func _run():
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	
	# Light & Env
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.18, 0.20, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.75)
	env_node.environment = env
	vp.add_child(env_node)
	
	var sun := DirectionalLight3D.new()
	sun.position = Vector3(5, 10, 5)
	sun.rotation_degrees = Vector3(-40, 45, 0)
	vp.add_child(sun)
	
	# Floor
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.32, 0.35)
	floor_mesh.material_override = floor_mat
	vp.add_child(floor_mesh)
	
	# Floor collision
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	floor_body.add_child(col)
	vp.add_child(floor_body)
	
	# Camera: closer framing for clear visual review of character and sword
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.position = Vector3(0.5, 1.2, 2.3)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.current = true
	
	# Player
	var ps := load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene
	var player := ps.instantiate() as CharacterBody3D
	vp.add_child(player)
	
	if OS.get_cmdline_user_args().has("--sun-review"):
		cam.position = Vector3(2.8, 2.1, 3.6)
		cam.look_at(Vector3(0, 1.0, 0))
		cam.make_current()
		vp.audio_listener_enable_3d = true
		var display := TextureRect.new()
		display.texture = vp.get_texture()
		display.size = Vector2(1280, 720)
		root.add_child(display)
	# Let settle
	for i in 15:
		await physics_frame
		await process_frame
		
	# Draw sword and wait until fully drawn (approx 60 frames)
	player.request_draw()
	for i in 65:
		await physics_frame
		await process_frame
		
	print("Player sword_state before spin: %d (want 2=DRAWN)" % player.sword_state)
	if OS.get_cmdline_user_args().has("--sun-review"):
		await _capture_sun_review(player, vp, cam)
		player.free()
		vp.free()
		quit(0)
		return
	# Start spin
	player.request_continuous_spin()
	
	var capture_dir := "C:/Users/B365/.gemini/antigravity/brain/ff9e48e5-a2cb-40cd-b57e-612d13170c35"
	var capture_points := {
		20: "spin_slash_windup.png",
		55: "spin_slash_combo_mid.png",
		95: "spin_slash_climax.png",
		135: "spin_slash_recovery.png"
	}
	
	for frame in range(1, 145):
		await physics_frame
		await process_frame
		if capture_points.has(frame):
			var img: Image = vp.get_texture().get_image()
			var out_file: String = capture_dir + "/" + capture_points[frame]
			var err := img.save_png(out_file)
			print("Frame %d: saved %s (status %d)" % [frame, capture_points[frame], err])
			
	print("Capture complete.")
	player.free()
	vp.free()
	quit(0)


func _capture_sun_review(player: CharacterBody3D, vp: SubViewport, cam: Camera3D) -> void:
	var output := ProjectSettings.globalize_path("res://../_review/sun_breathing_review")
	DirAccess.make_dir_recursive_absolute(output)
	# Capture the project's real SFX. The earlier designed_* injection is gone:
	# the user rejected those layers and supplied his own slash recordings.
	var audio = player.get_node("CharacterAudio")
	var max_surfaces := 0
	var max_dragons := 0
	var frames := 0
	var stages := ["spin", "light", "heavy"]
	for stage in stages:
		match stage:
			"light": player.request_primary_attack()
			"heavy": player.request_heavy_cut()
			"spin": player.request_continuous_spin()
		for frame in 180:
			await physics_frame
			await process_frame
			await RenderingServer.frame_post_draw
			frames += 1
			cam.make_current()
			max_surfaces = maxi(max_surfaces, player._sword_trail.mesh.get_surface_count())
			var live := 0
			for c in root.get_children():
				if c.get_script() != null and c.get_script().resource_path.ends_with("sun_dragon.gd"):
					live += 1
			max_dragons = maxi(max_dragons, live)
			if frame in [6, 14, 22, 34, 48, 70, 96]:
				var path := output + "/%s_%03d.png" % [stage, frame]
				assert(vp.get_texture().get_image().save_png(path) == OK)
	var report := {"frames": frames, "max_trail_surfaces": max_surfaces, "audio_events": audio.events_played, "stages": stages, "max_dragons": max_dragons, "status": "ART_REVIEW"}
	var file := FileAccess.open(output + "/capture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "	"))
	print("[SUN_CAPTURE] " + JSON.stringify(report))
