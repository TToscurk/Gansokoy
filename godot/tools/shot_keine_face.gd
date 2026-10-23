extends SceneTree
## 慧音正臉診斷：同鏡位比較 village_v2 原環境 / 關 SSAO / 關 SSIL / 全關 / 臉材質 unshaded。
##   godot --path . --script res://tools/shot_keine_face.gd -- <outdir/>
const SIZE := Vector2i(1200, 900)


func _initialize() -> void:
	run.call_deferred()


func _env(v: Node) -> Environment:
	for we in v.find_children("*", "WorldEnvironment", true, false):
		return (we as WorldEnvironment).environment
	return null


func run() -> void:
	root.size = SIZE
	var outdir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	_add_sun(float(OS.get_environment("KEINE_HOUR")) if OS.get_environment("KEINE_HOUR") != "" else 10.0)
	var k := v.get_node("Population/KeineNPC/K1_keine") as Node3D
	k.set_physics_process(false)
	var npc := k.get_node("NPC")
	npc.set("frozen", true)
	var ap := k.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for i in 10:
		await process_frame
	ap.play(&"idle")
	ap.seek(1.0, true)
	ap.speed_scale = 0.0
	var sk := k.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
	var fwd := k.global_transform.basis.z.normalized()   # 模型正面 +Z
	var cam := Camera3D.new()
	cam.fov = 30.0
	v.add_child(cam)
	cam.current = true
	var face := head + Vector3(0, 0.08, 0)
	cam.global_position = face + fwd * 0.75 + Vector3(0, 0.02, 0)
	cam.look_at(face, Vector3.UP)
	var env := _env(v)
	if env == null:
		env = cam.get_world_3d().environment
	print("[KFACE] env ssao %s ssil %s sdfgi %s glow %s tonemap %d" % [env.ssao_enabled, env.ssil_enabled, env.sdfgi_enabled, env.glow_enabled, env.tonemap_mode])
	var body := k.find_child("身體", true, false) as MeshInstance3D
	var mat := body.get_active_material(0) as BaseMaterial3D
	print("[KFACE] body mat %s metallic %.2f rough %.2f normal %s ao %s spec %.2f" % [mat.resource_name, mat.metallic, mat.roughness, mat.normal_enabled, mat.ao_enabled, mat.metallic_specular])
	var fill := k.find_child("FaceFill", true, false)
	var cases := [["H3_e03_warmer", 0.3, Color(1, 0.8, 0.66)], ["J1_e035", 0.35, Color(1, 0.75, 0.58)], ["J2_e04", 0.4, Color(1, 0.72, 0.55)], ["J3_e045", 0.45, Color(1, 0.7, 0.52)]]
	for c in cases:
		if fill != null:
			fill.set("day_energy", c[1])
			(fill as Light3D).light_color = c[2]
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(outdir + "face_" + c[0] + ".png")
		print("[KFACE] shot ", c[0])
	var sun := root.get_node_or_null("Main/Sun") as DirectionalLight3D
	if sun != null:
		print("[KFACE] sun dir (light travels) ", -sun.global_transform.basis.z, " keine facing ", k.global_transform.basis.z)
	quit()


## 遊戲的太陽在 Main/Sun（DayNight 控制）；單獨載 village_v2 時沒有太陽，只剩天光（臉會發藍發暗）。
func _add_sun(hour: float) -> void:
	var main := Node3D.new()
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nvar map_root: Node = null\n"
	gs.reload()
	main.set_script(gs)
	main.name = "Main"
	root.add_child(main)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
	main.add_child(sun)
	var dn: Node = root.get_node_or_null("DayNight")
	if dn != null:
		dn.set("flowing", false)
		dn.call("set_hour", hour)
