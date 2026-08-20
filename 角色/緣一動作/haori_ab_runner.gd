extends Node3D
## Stage 3 A/B 測試 runner：左袖 = Haori cloth bones + SpringBoneSimulator3D，
## 右袖 = 原 Meshy 權重。走路 / 跑步 / 拔刀，各拍數張截圖後自動結束。
## 僅供 haori_work 驗證使用，不屬於正式角色資產。

const SHOT_DIR := "D:/神社/shrine-yoriichi/角色/haori_work/godot_shots/"

var fbx: PackedScene = preload("res://yoriichi_haori_test.fbx")
var idle_src: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Idle_11_withSkin.fbx")
var walk_src: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Walking_withSkin.fbx")
var run_src: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Running_withSkin.fbx")
var draw_res: Animation = preload("res://yoriichi_draw_sword.res")
var sword: PackedScene = preload("res://yoriichi_sword.glb")

var _anim: AnimationPlayer
var _skel: Skeleton3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_build_env()
	var ch := fbx.instantiate()
	add_child(ch)
	var aps := ch.find_children("*", "AnimationPlayer", true, false)
	var sks := ch.find_children("*", "Skeleton3D", true, false)
	if aps.is_empty() or sks.is_empty():
		push_error("runner: missing AnimationPlayer or Skeleton3D")
		get_tree().quit(1)
		return
	_anim = aps[0]
	_skel = sks[0]
	print("BONE_COUNT ", _skel.get_bone_count())
	for i in _skel.get_bone_count():
		print("BONE %d %s" % [i, _skel.get_bone_name(i)])
	_merge_from(idle_src)
	_merge_from(walk_src)
	_merge_from(run_src)
	var lib := _lib()
	if not _anim.has_animation("Draw_Sword"):
		lib.add_animation("Draw_Sword", draw_res)
	print("ANIMS ", _anim.get_animation_list())
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
	cam.position = Vector3(0, 1.2, 1.75)
	cam.look_at(Vector3(0, 1.05, 0))
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
	# bone_name only — 不依賴舊 bone_idx（新骨插入後 index 可能位移）
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
	sim.setting_count = 1
	sim.set_root_bone_name(0, "Haori_Sleeve_L_01")
	sim.set_end_bone_name(0, "Haori_Sleeve_L_02")
	sim.set_extend_end_bone(0, true)
	sim.set_end_bone_length(0, 0.12)
	sim.set_stiffness(0, 1.2)
	sim.set_drag(0, 0.3)
	sim.set_gravity(0, 1.0)
	sim.set_gravity_direction(0, Vector3(0, -1, 0))
	sim.set_radius(0, 0.055)
	sim.set_enable_all_child_collisions(0, true)
	_capsule(sim, "Spine", 0.13, 0.34)
	_capsule(sim, "LeftArm", 0.065, 0.26)
	_capsule(sim, "LeftForeArm", 0.055, 0.24)
	print("SPRING configured, root=Haori_Sleeve_L_01 end=Haori_Sleeve_L_02")

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
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT_DIR + fname)
	print("SHOT ", fname)

func _pick_anim(needle: String) -> String:
	for n in _anim.get_animation_list():
		if String(n).findn(needle) != -1:
			return String(n)
	return ""

func _run_sequence() -> void:
	var walk := _pick_anim("walking")
	if walk == "" and _anim.has_animation("Scene"):
		walk = "Scene"   # Blender 匯出的 take 名稱
	var run_a := _pick_anim("running")
	print("WALK=", walk, " RUN=", run_a)
	for n in [walk, run_a]:
		if n != "" and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	# 讓 spring 從 rest 穩定一下
	await get_tree().create_timer(0.5).timeout
	_anim.play(walk)
	for i in 6:
		await get_tree().create_timer(0.35).timeout
		await _shot("walk_%02d.png" % i)
	_anim.play(run_a, 0.2)
	for i in 6:
		await get_tree().create_timer(0.28).timeout
		await _shot("run_%02d.png" % i)
	# 拔刀
	var sw_h: Node3D = get_meta("sw_hand")
	var sw_s: Node3D = get_meta("sw_sheath")
	_anim.play("Draw_Sword", 0.2)
	for i in 5:
		await get_tree().create_timer(0.22).timeout
		if _anim.current_animation_position > 0.65:
			sw_s.visible = false
			sw_h.visible = true
		await _shot("draw_%02d.png" % i)
	print("SEQUENCE DONE")
	get_tree().quit()
