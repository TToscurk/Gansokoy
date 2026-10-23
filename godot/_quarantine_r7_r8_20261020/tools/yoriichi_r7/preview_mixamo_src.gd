extends SceneTree
## R7 REF09 實驗：把重定向後的 Mixamo 來源動作（未改造、原速 30 fps、保留起跳／落地與水平軌跡）直接播在 R7K 緣一候選上，
## 固定鏡頭逐格存圖。不寫任何資源／場景；AnimationTree 停用、控制器物理停用，只看來源人體動作。
##   godot --path godot --fixed-fps 60 -s res://tools/yoriichi_r7/preview_mixamo_src.gd -- <anim_res> <out_dir_name> [view]
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"
var _p: CharacterBody3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	var args := OS.get_cmdline_user_args()
	var res_path: String = args[0] if args.size() > 0 else "res://characters/yoriichi/v24/anims/twist_flip_src.res"
	var out := "user://r7_moves_v2/mx_src/" + (args[1] if args.size() > 1 else "twist_flip") + "/"
	var view: String = args[2] if args.size() > 2 else "f34"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.68, 0.74)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.42, 0.38)
	floor.material_override = fm
	root.add_child(floor)
	for i in range(-2, 11):   # 沿行進方向（-z）每 1 m 一條橫線，跟拍鏡頭下仍看得出真實位移
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(4.0, 0.005, 0.03)
		m.mesh = bm
		m.position = Vector3(0, 0.003, -float(i))
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.92, 0.92, 0.88)
		m.material_override = lm
		root.add_child(m)
	_p = (load(PLAYER) as PackedScene).instantiate()
	_p.set("r7_vfx_enabled", false)
	root.add_child(_p)
	await process_frame
	await process_frame
	_p.set_physics_process(false)
	_p.set_process_unhandled_input(false)
	var anim: AnimationPlayer = _p.get("_anim")
	var tree: AnimationTree = _p.get("_tree")
	tree.active = false
	var a := load(res_path) as Animation
	var lib := anim.get_animation_library(anim.get_animation_library_list()[0])
	lib.add_animation(&"MX_SRC", a)
	# 鏡頭：依 Hips 軌跡範圍取景（世界空間 = 玩家 visual 的朝向）
	var hp_t := -1
	for t in a.get_track_count():
		if str(a.track_get_path(t)).ends_with(":mixamorig_Hips") and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			hp_t = t
	var vis: Node3D = _p.get("_visual")
	var sk := _p.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for k in a.track_get_key_count(hp_t):
		var w := sk.global_transform * (a.track_get_key_value(hp_t, k) as Vector3)
		lo = lo.min(w)
		hi = hi.max(w)
	var mid := (lo + hi) * 0.5
	var span := maxf((hi - lo).length(), 1.5)
	var cam := Camera3D.new()
	cam.fov = 40.0
	var dir := Vector3(1.0, 0.0, 0.35) if view == "side" else (Vector3(0.75, 0.0, 1.0) if view == "f34" else Vector3(0.25, 0.0, -1.0))
	var fwd := vis.global_basis.z
	var right := vis.global_basis.x
	var d := (right * dir.x + fwd * dir.z).normalized()
	var look := Vector3(mid.x, 1.0, mid.z)
	var follow := args.size() > 3 and args[3] == "follow"
	cam.position = look + d * (span * 1.1 + 4.2) + Vector3.UP * 0.6
	root.add_child(cam)
	cam.look_at(look)
	cam.current = true
	print("MXPREV hips_lo=%s hips_hi=%s len=%.3f" % [lo, hi, a.length])
	anim.play(&"MX_SRC")
	anim.pause()
	var n := int(round(a.length * 30.0)) + 1
	for i in range(-8, n + 10):   # 前後各留短緩衝（定格首／末格）
		var t := clampf(float(i) / 30.0, 0.0, a.length)
		anim.seek(t, true)
		if follow:   # 只水平跟拍骨盆（距離 4.6 m、高度固定），垂直不跟，騰空高度照實可見
			var hw: Vector3 = sk.global_transform * _hips_at(a, hp_t, t)
			var tgt := Vector3(hw.x, 1.05, hw.z)
			cam.position = tgt + d * 4.6 + Vector3.UP * 0.35
			cam.look_at(tgt)
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		img.save_png(out + "f%04d.png" % (i + 8))
	print("MXPREV_DONE frames=%d out=%s" % [n + 18, ProjectSettings.globalize_path(out)])
	quit()


func _hips_at(a: Animation, track: int, t: float) -> Vector3:
	return a.position_track_interpolate(track, t)
