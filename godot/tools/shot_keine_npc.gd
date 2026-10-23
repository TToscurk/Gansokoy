extends SceneTree
## 慧音 NPC 實機檢查（非 headless）：載入 village_v2，記錄 K1_keine 的位置／動作 14 秒，並從固定鏡位拍 4 張。
##   godot --path . --script res://tools/shot_keine_npc.gd -- <outdir/> [Population/MarisaNPC/M1_marisa]   ← 第 2 個參數＝要拍的 NPC 節點路徑（預設慧音）
const SIZE := Vector2i(1600, 900)


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	root.size = SIZE
	var outdir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	_add_sun(float(OS.get_environment("KEINE_HOUR")) if OS.get_environment("KEINE_HOUR") != "" else 10.0)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	for n in v.get_node("Districts").find_children("*ParcelLines*", "", true, false):
		n.visible = false
	var args := OS.get_cmdline_user_args()
	var k := v.get_node(args[1] if args.size() > 1 else "Population/KeineNPC/K1_keine") as Node3D
	var ap := k.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sk := k.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var cam := Camera3D.new()
	cam.fov = 40.0
	v.add_child(cam)
	cam.current = true
	var shots := {2.0: "a_side", 5.0: "b_front", 7.0: "e_wide", 9.0: "c_side", 12.0: "d_close"}
	var t := 0.0
	var last := -1
	var log := []
	var foot_min := INF
	var foot_at := ""
	var dips := 0
	while t < float(OS.get_environment("KEINE_SECS")) if OS.get_environment("KEINE_SECS") != "" else t < 14.0:
		await process_frame
		t += get_root().get_process_delta_time() if false else 1.0 / 60.0
		await physics_frame
		var p := k.global_position
		var hd := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin
		var lf := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftToes")).origin).y - p.y
		var rf := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightToes")).origin).y - p.y
		if minf(lf, rf) < foot_min:
			foot_min = minf(lf, rf)
			foot_at = "t=%.2f anim %s" % [t, ap.current_animation]
		if minf(lf, rf) < 0.095:
			dips += 1
		if int(t) != last:
			last = int(t)
			log.append("t=%2d pos (%.2f, %.3f, %.2f) yaw %.0f anim %s head_y %.2f fill %.2f" % [last, p.x, p.y, p.z, rad_to_deg(k.rotation.y), ap.current_animation, hd.y - p.y, (k.find_child("FaceFill", true, false) as Light3D).light_energy])
		for st: float in shots.keys():
			if absf(t - st) < 0.009:
				var name: String = shots[st]
				var off := Vector3(3.2, 1.0, 0.0) if name.ends_with("side") else (Vector3(0.0, 1.0, -3.4) if name == "b_front" else (Vector3(7.5, 2.0, 5.5) if name == "e_wide" else Vector3(1.4, 0.6, -1.4)))
				var tgt := p + (Vector3(-3.5, 1.5, 0) if name == "e_wide" else Vector3(0, 0.95 if name != "d_close" else 1.25, 0))
				cam.global_position = p + off + Vector3(0, 0.5, 0)
				cam.look_at(tgt, Vector3.UP)
				for i in 3:
					await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(outdir + name + ".png")
				log.append("  SHOT %s at t=%.1f anim %s" % [name, t, ap.current_animation])
	for l in log:
		print("[KSHOT] ", l)
	print("[KSHOT] min toe height above actor origin over run: %.3f m at %s; frames below 0.095: %d" % [foot_min, foot_at, dips])
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
