extends Node3D
## Stage 4 完整羽織 SpringBone 測試：7 根 Haori 骨（左右袖各2 + 前擺L/R + 後擺）。
## 必測：Idle / Walk / Run / 快速轉身 / Draw_Sword / DRAWN 走路 / 突然停止。

const SHOT_DIR := "D:/神社/shrine-yoriichi/角色/haori_work/full_shots/"

var fbx: PackedScene = preload("res://yoriichi_haori_full.fbx")
var idle_src: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Idle_11_withSkin.fbx")
var walk_src: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Walking_withSkin.fbx")
var run_src: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Running_withSkin.fbx")
var draw_res: Animation = preload("res://yoriichi_draw_sword.res")
var sword: PackedScene = preload("res://yoriichi_sword.glb")

var _anim: AnimationPlayer
var _skel: Skeleton3D
var _char: Node3D
var _fps_log: Array = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_build_env()
	_char = fbx.instantiate()
	add_child(_char)
	_anim = _char.find_children("*", "AnimationPlayer", true, false)[0]
	_skel = _char.find_children("*", "Skeleton3D", true, false)[0]
	print("BONE_COUNT ", _skel.get_bone_count())
	_merge_from(idle_src)
	_merge_from(walk_src)
	_merge_from(run_src)
	if not _anim.has_animation("Draw_Sword"):
		_lib().add_animation("Draw_Sword", draw_res)
	_add_sockets()
	_add_spring()
	_run_sequence.call_deferred()

func _build_env() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.27, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.72)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	floor_mesh.mesh = pm
	add_child(floor_mesh)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.15, 1.9)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true

func _lib() -> AnimationLibrary:
	var lib_name: StringName = _anim.get_animation_library_list()[0] if _anim.get_animation_library_list().size() > 0 else &""
	if not _anim.has_animation_library(lib_name):
		_anim.add_animation_library(lib_name, AnimationLibrary.new())
	return _anim.get_animation_library(lib_name)

func _merge_from(source: PackedScene) -> void:
	if source == null:
		return
	var tmp := source.instantiate()
	var src_aps := tmp.find_children("*", "AnimationPlayer", true, false)
	if not src_aps.is_empty():
		var src: AnimationPlayer = src_aps[0]
		var lib := _lib()
		for n in src.get_animation_list():
			if not lib.has_animation(n):
				lib.add_animation(n, src.get_animation(n).duplicate())
	tmp.free()

func _add_sockets() -> void:
	var hs := BoneAttachment3D.new()
	hs.name = "HandSocket"
	_skel.add_child(hs)
	hs.bone_name = "RightHand"
	var sw_h := sword.instantiate() as Node3D
	hs.add_child(sw_h)
	sw_h.transform = Transform3D(Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)), Vector3(0, 0.07, 0))
	sw_h.visible = false
	var ss := BoneAttachment3D.new()
	ss.name = "SheathSocket"
	_skel.add_child(ss)
	ss.bone_name = "Hips"
	var sw_s := sword.instantiate() as Node3D
	ss.add_child(sw_s)
	sw_s.transform = Transform3D(
		Basis(Vector3(0.057647, -0.978981, -0.195633),
			Vector3(-0.065052, 0.191859, -0.979264),
			Vector3(0.996215, 0.069177, -0.052624)),
		Vector3(0.272761, -0.062122, 0.027695))
	print("SOCKET HandSocket bone_idx=", hs.bone_idx, " SheathSocket bone_idx=", ss.bone_idx)
	set_meta("sw_hand", sw_h)
	set_meta("sw_sheath", sw_s)

func _add_spring() -> void:
	var sim := SpringBoneSimulator3D.new()
	sim.name = "HaoriSpring"
	_skel.add_child(sim)
	# 5 條鏈：左袖 / 右袖 / 前擺L / 前擺R / 後擺，全部用左袖驗證過的 baseline 參數
	var chains := [
		["Haori_Sleeve_L_01", "Haori_Sleeve_L_02"],
		["Haori_Sleeve_R_01", "Haori_Sleeve_R_02"],
		["Haori_Front_L", "Haori_Front_L"],
		["Haori_Front_R", "Haori_Front_R"],
		["Haori_Back", "Haori_Back"],
	]
	sim.setting_count = chains.size()
	for i in chains.size():
		sim.set_root_bone_name(i, chains[i][0])
		sim.set_end_bone_name(i, chains[i][1])
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_length(i, 0.12)
		sim.set_stiffness(i, 1.2)
		sim.set_drag(i, 0.3)
		sim.set_gravity(i, 1.0)
		sim.set_gravity_direction(i, Vector3(0, -1, 0))
		sim.set_radius(i, 0.055)
		sim.set_enable_all_child_collisions(i, true)
	# 最低限度碰撞：torso / 雙臂 / hips / 雙腿
	_capsule(sim, "Spine", 0.13, 0.34)
	_capsule(sim, "LeftArm", 0.065, 0.26)
	_capsule(sim, "RightArm", 0.065, 0.26)
	_capsule(sim, "LeftForeArm", 0.055, 0.24)
	_capsule(sim, "RightForeArm", 0.055, 0.24)
	_capsule(sim, "Hips", 0.14, 0.2)
	_capsule(sim, "LeftUpLeg", 0.09, 0.4)
	_capsule(sim, "RightUpLeg", 0.09, 0.4)
	print("SPRING configured: ", sim.setting_count, " chains")

func _capsule(sim: SpringBoneSimulator3D, bone: String, radius: float, height: float) -> void:
	var c := SpringBoneCollisionCapsule3D.new()
	c.name = "Col_" + bone
	sim.add_child(c)
	c.bone_name = bone
	c.radius = radius
	c.height = height
	c.position_offset = Vector3(0, height * 0.5, 0)

func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + fname)
	_fps_log.append([fname, Engine.get_frames_per_second(),
		snapped(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01)])
	print("SHOT ", fname)

func _pick(needle: String) -> String:
	for n in _anim.get_animation_list():
		if String(n).findn(needle) != -1:
			return String(n)
	return ""

func _run_sequence() -> void:
	var idle_a := _pick("Idle")
	var walk_a := _pick("walking")
	var run_a := _pick("running")
	for n in [idle_a, walk_a, run_a]:
		if n != "" and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	var sw_h: Node3D = get_meta("sw_hand")
	var sw_s: Node3D = get_meta("sw_sheath")

	await get_tree().create_timer(0.6).timeout
	_anim.play(idle_a)
	for i in 3:
		await get_tree().create_timer(0.45).timeout
		await _shot("a_idle_%02d.png" % i)
	_anim.play(walk_a, 0.2)
	for i in 6:
		await get_tree().create_timer(0.32).timeout
		await _shot("b_walk_%02d.png" % i)
	_anim.play(run_a, 0.2)
	for i in 6:
		await get_tree().create_timer(0.26).timeout
		await _shot("c_run_%02d.png" % i)
	# 快速轉身（跑步中 0.6 秒 360°）
	var t := 0.0
	var shot_flags := [false, false]
	while t < 0.6:
		var dt := get_process_delta_time()
		await get_tree().process_frame
		t += dt
		_char.rotation.y += TAU * (dt / 0.6)
		if t > 0.2 and not shot_flags[0]:
			shot_flags[0] = true
			await _shot("d_turn_00.png")
		elif t > 0.45 and not shot_flags[1]:
			shot_flags[1] = true
			await _shot("d_turn_01.png")
	await _shot("d_turn_02.png")
	# 突然停止：跑步 → 0.1s blend 回 idle，觀察回擺
	_anim.play(run_a)
	await get_tree().create_timer(0.8).timeout
	_anim.play(idle_a, 0.1)
	for i in 5:
		await get_tree().create_timer(0.18).timeout
		await _shot("e_stop_%02d.png" % i)
	# 拔刀
	_anim.play("Draw_Sword", 0.2)
	var draw_len: float = _anim.get_animation("Draw_Sword").length
	for i in 4:
		await get_tree().create_timer(draw_len / 4.0).timeout
		if _anim.current_animation == "Draw_Sword" and _anim.current_animation_position / draw_len > 0.65:
			sw_s.visible = false
			sw_h.visible = true
		await _shot("f_draw_%02d.png" % i)
	# DRAWN 狀態走路（刀在手上）
	sw_s.visible = false
	sw_h.visible = true
	_anim.play(walk_a, 0.2)
	for i in 4:
		await get_tree().create_timer(0.32).timeout
		await _shot("g_drawnwalk_%02d.png" % i)
	print("FPSLOG ", JSON.stringify(_fps_log))
	print("SEQUENCE DONE")
	get_tree().quit()
