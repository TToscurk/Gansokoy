extends SceneTree
## v2.4 動作實驗台（不依賴 yoriichi_character.gd，直接用 GLB＋SpringBone rig）。
##   dump  ：godot --headless --path . -s tools/v24_anim/clip_lab.gd -- dump  clip1,clip2
##           → user://v24_hands/<clip>.json（Player 空間骨頭位置＋雙手 basis）
##   strip ：godot --path . -s tools/v24_anim/clip_lab.gd -- strip clip1,clip2 [格數=8] [view=34|front|side|back]
##           → user://v24_strips/<clip>.png（等時距 N 格拼成一張；持刀用 user://grip_socket.json 的 Sword_Hand 掛點）
## 渲染模式要等 SpringBone 穩定：每支先播 0.3 s 暖機再取格（衣袖才是真實動態，不是 rest）。

const GLB := "res://characters/yoriichi/v24/yoriichi_v24.glb"
const RIG := "res://characters/yoriichi/v24/yoriichi_v24_rig.gd"
const SWORD := "res://characters/yoriichi/yoriichi_sword.glb"
const SHEATH := "res://characters/yoriichi/sheath_v2/yoriichi_sheath_v2.glb"
const BONES := ["mixamorig_Hips", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head",
	"mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
	"mixamorig_RightHandThumb1", "mixamorig_RightHandThumb2", "mixamorig_RightHandIndex1", "mixamorig_RightHandIndex2", "mixamorig_RightHandIndex3",
	"mixamorig_RightHandMiddle1", "mixamorig_RightHandMiddle2", "mixamorig_RightHandMiddle3", "mixamorig_RightHandRing1", "mixamorig_RightHandRing2",
	"mixamorig_RightHandRing3", "mixamorig_RightHandPinky1", "mixamorig_RightHandPinky2", "mixamorig_RightHandPinky3",
	"mixamorig_LeftHandThumb1", "mixamorig_LeftHandThumb2", "mixamorig_LeftHandIndex1", "mixamorig_LeftHandIndex2", "mixamorig_LeftHandIndex3",
	"mixamorig_LeftHandMiddle1", "mixamorig_LeftHandMiddle2", "mixamorig_LeftHandMiddle3", "mixamorig_LeftHandRing1", "mixamorig_LeftHandRing2",
	"mixamorig_LeftHandRing3", "mixamorig_LeftHandPinky1", "mixamorig_LeftHandPinky2", "mixamorig_LeftHandPinky3",
	"mixamorig_LeftUpLeg", "mixamorig_RightUpLeg", "mixamorig_LeftLeg", "mixamorig_RightLeg", "mixamorig_LeftFoot", "mixamorig_RightFoot"]

var _mode := "dump"
var _clips: PackedStringArray = []
var _nframes := 8
var _view := "34"
var _body: Node3D
var _sk: Skeleton3D
var _ap: AnimationPlayer
var _lib: AnimationLibrary
var _cam: Camera3D
var _sword: Node3D
var _n := 0
# strip 狀態
var _ci := -1
var _t := 0.0
var _shot := 0
var _wait := 0
var _imgs: Array = []

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_mode = a[0] if a.size() > 0 else "dump"
	_clips = (a[1] if a.size() > 1 else "gs_idle").split(",")
	if a.size() > 2:
		_nframes = int(a[2])
	if a.size() > 3:
		_view = a[3]
	_body = (load(GLB) as PackedScene).instantiate()
	if _mode == "strip":
		_body.set_script(load(RIG))
		_body.set("start_motion", "")
	root.add_child(_body)
	_sk = _body.find_children("*", "Skeleton3D", true, false)[0]
	_ap = _body.find_children("*", "AnimationPlayer", true, false)[0]
	_lib = AnimationLibrary.new()
	_ap.add_animation_library("lab", _lib)
	for k in _clips:
		_lib.add_animation(k, load("res://characters/yoriichi/v24/anims/%s.res" % k))
	if _mode == "strip":
		_setup_render()

func _setup_render() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.68, 0.74)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.88)
	e.ambient_light_energy = 0.75
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.42, 0.36)
	g.material_override = gm
	root.add_child(g)
	_cam = Camera3D.new()
	_cam.fov = 40
	root.add_child(_cam)
	_cam.make_current()
	var gs := FileAccess.get_file_as_string("user://grip_socket.json")
	if gs != "":
		var att := BoneAttachment3D.new()
		att.bone_name = "mixamorig_RightHand"
		_sk.add_child(att)
		_sword = (load(SWORD) as PackedScene).instantiate()
		att.add_child(_sword)
		_sword.transform = str_to_var(JSON.parse_string(gs)["Sword_Hand"])

func _pose_at(anim: String, t: float) -> Dictionary:
	_ap.play("lab/" + anim)
	_ap.seek(t, true)
	var g := {}
	for i in _sk.get_bone_count():
		var pi := _sk.get_bone_parent(i)
		var lp := _sk.get_bone_pose(i)
		g[i] = (g[pi] as Transform3D) * lp if pi >= 0 else lp
	return g

func _process(delta: float) -> bool:
	_n += 1
	if _n < 3:
		return false
	if _mode == "dump":
		_dump()
		return true
	return _strip_step(delta)

func _dump() -> void:
	var out_dir := "user://v24_hands/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var base := _sk.global_transform
	for k in _clips:
		var a: Animation = _lib.get_animation(k)
		var frames := []
		for fi in int(round(a.length * 30.0)) + 1:
			var g := _pose_at(k, minf(fi / 30.0, a.length))
			var row := {}
			for b in BONES:
				var t: Transform3D = base * (g[_sk.find_bone(b)] as Transform3D)
				row[b] = [t.origin.x, t.origin.y, t.origin.z]
				if b.ends_with("RightHand") or b.ends_with("LeftHand"):
					row[b + "_basis"] = [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z, t.basis.z.x, t.basis.z.y, t.basis.z.z]
			frames.append(row)
		var f := FileAccess.open(out_dir + k + ".json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"len": a.length, "frames": frames}))
		f.close()
		print("DUMPED ", k, " frames=", frames.size())

func _cam_place() -> void:
	var hips := _sk.global_transform * _sk.get_bone_global_pose(_sk.find_bone("mixamorig_Hips")).origin
	var c := Vector3(hips.x, 1.05, hips.z)
	var d := 4.6
	if _view.begins_with("hands"):
		# 握刀近拍：看右手骨與左手骨中點，距離 1.1 m；hands=右前、handsL=左前、handsT=上方
		var rh := _sk.global_transform * _sk.get_bone_global_pose(_sk.find_bone("mixamorig_RightHand")).origin
		var lh := _sk.global_transform * _sk.get_bone_global_pose(_sk.find_bone("mixamorig_LeftHand")).origin
		var m := (rh + lh) * 0.5
		var hd := Vector3(0.8, 0.25, 0.6)
		if _view == "handsL":
			hd = Vector3(-0.8, 0.25, 0.6)
		elif _view == "handsT":
			hd = Vector3(0.2, 1.0, 0.35)
		_cam.global_position = m + hd.normalized() * 1.1
		_cam.look_at(m, Vector3.UP)
		return
	var dir := Vector3(0.75, 0.0, 0.66).normalized()   # 角色前方 +Z，鏡頭在右前 3/4
	match _view:
		"front": dir = Vector3(0.15, 0, 1).normalized()
		"side": dir = Vector3(1, 0, 0.05).normalized()
		"back": dir = Vector3(-0.35, 0, -1).normalized()
	_cam.global_position = c + dir * d + Vector3(0, 0.35, 0)
	_cam.look_at(c, Vector3.UP)

func _strip_step(delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var img := root.get_viewport().get_texture().get_image()
			img.resize(400, 450 * img.get_height() / img.get_height(), Image.INTERPOLATE_BILINEAR)
			_imgs.append(img)
		return false
	if _ci < 0 or _shot >= _nframes:
		if _ci >= 0:
			_save_strip(_clips[_ci])
		_ci += 1
		if _ci >= _clips.size():
			quit()
			return true
		_shot = 0
		_t = -0.3
		_imgs = []
		_ap.play("lab/" + _clips[_ci])
		_ap.seek(0.0, true)
		_ap.pause()
		return false
	var a: Animation = _lib.get_animation(_clips[_ci])
	var target := a.length * float(_shot) / float(maxi(_nframes - 1, 1))
	_t += delta
	var tt := clampf(_t, 0.0, target)
	_ap.seek(tt, true)
	_cam_place()
	if _t >= target:
		_shot += 1
		_wait = 2
	return false

func _save_strip(k: String) -> void:
	var cols := mini(_imgs.size(), 4)
	var rows := int(ceil(_imgs.size() / float(cols)))
	var w: int = (_imgs[0] as Image).get_width()
	var h: int = (_imgs[0] as Image).get_height()
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in _imgs.size():
		var im: Image = _imgs[i]
		im.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://v24_strips/"))
	sheet.save_png("user://v24_strips/%s_%s.png" % [k, _view])
	print("STRIP ", k, " ", _imgs.size())
