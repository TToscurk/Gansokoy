extends SceneTree
## 慧音 clip 審圖總表（簡單棚拍、非 headless）：每個 clip 一列、N 個時間點；正面＋45°。
##   godot --path . --script res://tools/shot_keine_clip_sheet.gd -- <out.png> <res://clip.res>...
const CELL := Vector2i(300, 420)
const N := 4


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var clips := args.slice(1)
	root.size = CELL
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.environment.ambient_light_energy = 0.6
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.shadow_enabled = true
	w.add_child(sun)
	var k: Node3D = (load("res://characters/keine/keine.tscn") as PackedScene).instantiate()
	k.set("frozen", true)
	w.add_child(k)
	await process_frame
	var ap := k.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var lib := ap.get_animation_library(&"")
	var cam := Camera3D.new()
	cam.fov = 30.0
	w.add_child(cam)
	cam.current = true
	var sheet := Image.create(CELL.x * N * 2, CELL.y * clips.size(), false, Image.FORMAT_RGB8)
	for r in clips.size():
		var a := load(clips[r]) as Animation
		lib.add_animation("s%d" % r, a)
		ap.play("s%d" % r)
		ap.speed_scale = 0.0
		for c in N:
			for view in 2:
				var t := a.length * (c + 0.5) / N
				ap.seek(t, true)
				var dir := Vector3(0, 0, 1) if view == 0 else Vector3(0.7, 0, 0.7)
				cam.global_position = Vector3(0, 0.95, 0) + dir * 4.2
				cam.look_at(Vector3(0, 0.88, 0), Vector3.UP)
				for i in 3:
					await process_frame
				await RenderingServer.frame_post_draw
				var img := root.get_texture().get_image()
				img.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((c * 2 + view) * CELL.x, r * CELL.y))
		print("[KSHEET] row %d %s len %.2fs" % [r, clips[r].get_file(), a.length])
	sheet.save_png(out)
	print("[KSHEET] saved ", out)
	quit()
