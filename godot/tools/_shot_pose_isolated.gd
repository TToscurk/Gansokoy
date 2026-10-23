extends SceneTree
## 單元驗證：把 yoriichi_meditate.res 直接套在身體 FBX 上（不經過遊戲流程），
## 量高度 + 從四個角度拍圖。這是最乾淨的「這支 clip 對不對」測試。
##   <godot_console.exe> --path godot --script res://tools/_shot_pose_isolated.gd
const OUT := "D:/神社/shrine/work/shots/pose_isolated/"
const BODY := "res://characters/yoriichi/yoriichi_body.fbx"
const CLIP := "res://characters/yoriichi/animations/yoriichi_meditate.res"


func _init() -> void:
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _settle(3)
	await RenderingServer.frame_post_draw
	await _settle(1)
	DirAccess.make_dir_recursive_absolute(OUT)
	root.get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("[ISO] 拍 " + name)


func _run() -> void:
	# 灰色底 + 亮光，看清楚人形
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.38, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.4
	root.add_child(sun)

	var body := (load(BODY) as PackedScene).instantiate()
	root.add_child(body)
	await _settle(4)
	var sk := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ap := body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	print("[ISO] 骨架父=%s 母旋轉=%s 骨數=%d" % [sk.get_parent().name,
		str((sk.get_parent() as Node3D).rotation_degrees.snappedf(1.0)), sk.get_bone_count()])

	var res: Animation = load(CLIP)
	print("[ISO] clip 長度=%.2f 軌道=%d 第一軌=%s" % [
		res.length, res.get_track_count(), str(res.track_get_path(0))])
	if not ap.has_animation_library(""):
		ap.add_animation_library("", AnimationLibrary.new())
	ap.get_animation_library("").add_animation("Meditate", res)
	ap.play("Meditate")
	ap.seek(res.length, true)
	ap.speed_scale = 0.0
	await _settle(4)
	print("[ISO] 播放中=%s 目前=%s" % [str(ap.is_playing()), ap.current_animation])

	print("[ISO] 世界高度（骨骼空間 z → 世界 y）：")
	# 先把骨頭姿勢與世界變換的關係攤開來看
	var hb := sk.find_bone("Hips")
	var restb := sk.get_bone_rest(hb)
	print("[ISO] 骨架節點 global basis=%s  origin=%s" % [
		str(sk.global_transform.basis.get_euler().snappedf(0.01)), str(sk.global_transform.origin.snappedf(0.001))])
	var anc := sk.get_parent()
	while anc is Node3D:
		print("[ISO]   祖先 %-14s 旋轉=%s 縮放=%s 位置=%s" % [(anc as Node3D).name,
			str((anc as Node3D).rotation_degrees.snappedf(1.0)), str((anc as Node3D).scale.snappedf(0.001)),
			str((anc as Node3D).position.snappedf(0.001))])
		anc = anc.get_parent()
	print("[ISO]   Hips rest=%s（origin=%s basis euler=%s）" % [str(restb.origin.snappedf(0.001)),
		str(restb.origin.snappedf(0.001)), str(restb.basis.get_euler().snappedf(0.01))])
	print("[ISO]   Hips 引擎 global=%s" % str(sk.get_bone_global_pose(hb).origin.snappedf(0.001)))
	var pt := -1
	for t in res.get_track_count():
		if res.track_get_type(t) == Animation.TYPE_POSITION_3D:
			pt = t
	if pt >= 0:
		print("[ISO]   位置軌 key=%s" % str(res.track_get_key_value(pt, 0)))
		print("[ISO]   理論 global = rest × key = %s" % str(
			(restb * Transform3D(Basis(), res.track_get_key_value(pt, 0))).origin.snappedf(0.001)))
	for b in ["Hips", "Spine02", "Spine", "neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot",
			"RightFoot", "LeftHand", "RightHand"]:
		var i := sk.find_bone(b)
		if i < 0:
			continue
		var w := sk.global_transform * sk.get_bone_global_pose(i)
		print("   %-11s 世界=%s" % [b, str(w.origin.snappedf(0.01))])

	# 相機：看角色正面（模型面朝 -Z）
	var cam := Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	cam.make_current()
	var views := {
		"i1_front": Vector3(0, 0.55, 1.7),
		"i2_quarter": Vector3(1.1, 0.75, 1.3),
		"i3_side": Vector3(1.7, 0.5, 0.0),
		"i4_low": Vector3(0.5, 0.22, 1.3),
		"i5_top": Vector3(0.01, 1.5, 0.6),
	}
	for name in views.keys():
		cam.global_position = views[name] as Vector3
		cam.look_at(Vector3(0, 0.35, 0), Vector3.UP)
		await _shot(name)
	quit(0)
