extends Node3D
## SoftBody3D 羽織可行性實驗（獨立於正式角色）：
## 身體 = yoriichi_softbody_body.fbx（原骨架/權重，羽織面已移除）
## 羽織 = haori_softbody_proxy.glb（~7k tris）掛 SoftBody3D，
## 領口/肩/袖根 pin 到 Spine / LeftArm / RightArm 的 BoneAttachment3D。
## Idle / Walk / Run / Draw / 快速轉身，各拍截圖並記錄 FPS。

const SHOT_DIR := "D:/神社/shrine-yoriichi/角色/haori_work/softbody_shots/"

var body_scene: PackedScene = preload("res://yoriichi_softbody_body.fbx")
var proxy_scene: PackedScene = preload("res://haori_softbody_proxy.glb")
var idle_src: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Idle_11_withSkin.fbx")
var walk_src: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Walking_withSkin.fbx")
var run_src: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Running_withSkin.fbx")
var draw_res: Animation = preload("res://yoriichi_draw_sword.res")

var _anim: AnimationPlayer
var _skel: Skeleton3D
var _char: Node3D
var _soft: SoftBody3D
var _fps_log: Array = []

func _ready() -> void:
	Engine.physics_ticks_per_second = 120
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_build_env()
	_char = body_scene.instantiate()
	add_child(_char)
	var aps := _char.find_children("*", "AnimationPlayer", true, false)
	_skel = _char.find_children("*", "Skeleton3D", true, false)[0]
	if aps.is_empty():
		_anim = AnimationPlayer.new()
		_char.add_child(_anim)
	else:
		_anim = aps[0]
	_merge_from(idle_src)
	_merge_from(walk_src)
	_merge_from(run_src)
	if not _anim.has_animation("Draw_Sword"):
		_lib().add_animation("Draw_Sword", draw_res)
	print("ANIMS ", _anim.get_animation_list())
	_add_colliders()
	_add_softbody()
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
	cam.position = Vector3(0, 1.2, 1.85)
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

func _attach(bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.name = "Att_" + bone
	_skel.add_child(a)
	a.bone_name = bone
	return a

func _add_colliders() -> void:
	# 最低限度：torso / 左右上臂 / hips，AnimatableBody3D 跟著骨頭走
	for cfg in [
		{"bone": "Spine", "r": 0.14, "h": 0.36},
		{"bone": "LeftArm", "r": 0.07, "h": 0.27},
		{"bone": "RightArm", "r": 0.07, "h": 0.27},
		{"bone": "Hips", "r": 0.15, "h": 0.26},
	]:
		var att := _attach(cfg["bone"])
		var ab := AnimatableBody3D.new()
		ab.name = "Body_" + cfg["bone"]
		ab.collision_layer = 2
		ab.collision_mask = 0
		att.add_child(ab)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = cfg["r"]
		cap.height = cfg["h"]
		cs.shape = cap
		cs.position = Vector3(0, cfg["h"] * 0.5, 0)
		ab.add_child(cs)

func _add_softbody() -> void:
	var tmp := proxy_scene.instantiate()
	add_child(tmp)
	var mi: MeshInstance3D = tmp.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh := mi.mesh
	var xf := mi.global_transform
	tmp.queue_free()

	# mesh 必須在 add_child 之前設好，否則 GodotPhysics 不會建立模擬網格（實測）
	_soft = SoftBody3D.new()
	_soft.name = "HaoriSoft"
	_soft.mesh = mesh
	_soft.simulation_precision = 10
	_soft.total_mass = 0.6
	_soft.linear_stiffness = 0.9
	_soft.damping_coefficient = 0.05
	_soft.drag_coefficient = 0.05
	_soft.collision_layer = 0
	_soft.collision_mask = 2
	add_child(_soft)
	_soft.global_transform = xf

	var att_spine := _attach("Spine")
	var att_l := _attach("LeftArm")
	var att_r := _attach("RightArm")

	# 等物理跑起來、點的 global position 有效之後再 pin（否則 offset 會坍縮到 attachment 原點）
	await get_tree().physics_frame
	await get_tree().physics_frame

	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var pinned := 0
	var counts := {"spine": 0, "l": 0, "r": 0}
	for i in verts.size():
		var w := xf * verts[i]
		if w.y > 1.28 and abs(w.x) < 0.40:
			var target: BoneAttachment3D
			if w.x > 0.18:
				target = att_l
				counts["l"] += 1
			elif w.x < -0.18:
				target = att_r
				counts["r"] += 1
			else:
				target = att_spine
				counts["spine"] += 1
			_soft.set_point_pinned(i, true, _soft.get_path_to(target))
			pinned += 1
	print("SOFTBODY verts=", verts.size(), " pinned=", pinned, " ", counts)

func _shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + fname)
	var fps := Engine.get_frames_per_second()
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_fps_log.append([fname, fps, phys_ms])
	print("SHOT %s fps=%.0f phys=%.1fms" % [fname, fps, phys_ms])

func _pick(needle: String) -> String:
	for n in _anim.get_animation_list():
		if String(n).findn(needle) != -1:
			return String(n)
	return ""

func _run_sequence() -> void:
	var idle_a := _pick("Idle")
	var walk_a := _pick("walking")
	var run_a := _pick("running")
	print("IDLE=", idle_a, " WALK=", walk_a, " RUN=", run_a)
	for n in [idle_a, walk_a, run_a]:
		if n != "" and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	# 布料落定
	await get_tree().create_timer(1.2).timeout
	await _shot("settle.png")
	_anim.play(idle_a)
	for i in 3:
		await get_tree().create_timer(0.5).timeout
		await _shot("idle_%02d.png" % i)
	_anim.play(walk_a, 0.2)
	for i in 5:
		await get_tree().create_timer(0.35).timeout
		await _shot("walk_%02d.png" % i)
	_anim.play(run_a, 0.2)
	for i in 5:
		await get_tree().create_timer(0.28).timeout
		await _shot("run_%02d.png" % i)
	# 快速轉身：跑步中 0.6 秒轉 360°
	var t := 0.0
	while t < 0.6:
		var dt := get_process_delta_time()
		await get_tree().process_frame
		t += dt
		_char.rotation.y += TAU * (dt / 0.6)
		if t > 0.15 and t < 0.2:
			await _shot("turn_00.png")
		elif t > 0.35 and t < 0.4:
			await _shot("turn_01.png")
	await _shot("turn_02.png")
	await get_tree().create_timer(0.5).timeout
	await _shot("turn_settle.png")
	# 拔刀
	_anim.play("Draw_Sword", 0.2)
	for i in 4:
		await get_tree().create_timer(0.25).timeout
		await _shot("draw_%02d.png" % i)
	print("FPSLOG ", JSON.stringify(_fps_log))
	print("SEQUENCE DONE")
	get_tree().quit()
