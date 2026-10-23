extends SceneTree
## v2.4 換裝驗收：隔離場景放正式 player_yoriichi.tscn，模擬 待機→走→跑→跳，
## 每階段以「遊戲 TPS 相機」＋「正面 3/4」＋「側面」截圖，並量腳底高度、刀鞘位置。
## 需有 rendering（不可 --headless）：godot --path . -s tools/_v24_player_capture.gd
## 輸出：user://v24_player/*.png 與 log.json

const OUT := "user://v24_player/"
var _p: CharacterBody3D
var _cam_front: Camera3D
var _cam_side: Camera3D
var _t := 0.0
var _phase := 0
var _log := {}
var _foot_min := {}

var PHASES := [
	["idle", 1.5, []],
	["walk", 2.0, ["move_forward"]],
	["run", 2.0, ["move_forward", "sprint"]],
	["jump", 0.45, ["move_forward"]],
]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.68, 0.74)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.78)
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position.y = -0.5
	floor_body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	mi.position.y = -0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.42, 0.36)
	mi.material_override = mat
	floor_body.add_child(mi)
	root.add_child(floor_body)
	_p = (load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene).instantiate()
	root.add_child(_p)
	var args := OS.get_cmdline_user_args()
	if "closeup" in args:
		_closeup = true
		PHASES = [["idle", 1.5, []]]
		if "nohaori" in args:
			for m in _p.find_children("羽織", "MeshInstance3D", true, false):
				m.visible = false
			PHASES = [["idle_nohaori", 1.5, []]]
	_cam_front = Camera3D.new()
	_cam_front.fov = 40
	root.add_child(_cam_front)
	_cam_side = Camera3D.new()
	_cam_side.fov = 40
	root.add_child(_cam_side)

func _skel() -> Skeleton3D:
	return _p.find_children("*", "Skeleton3D", true, false)[0]

func _bone_y(sk: Skeleton3D, n: String) -> float:
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(n))).origin.y

var _closeup := false

func _place_cams() -> void:
	var c := _p.global_position + Vector3(0, 0.95, 0)
	if _closeup:
		# 腰部特寫：角色左側（-X）與俯視，對準刀鞘。
		var w := _p.global_position + Vector3(-0.12, 0.95, -0.2)
		_cam_front.global_position = w + Vector3(-1.5, 0.25, -0.9)
		_cam_front.look_at(w, Vector3.UP)
		_cam_side.global_position = w + Vector3(-0.2, 1.8, -0.05)
		_cam_side.look_at(w, Vector3.FORWARD)
		return
	# 角色面向 -Z（BodyVisual 轉 PI）。正面 3/4：在 -Z 前方偏右。
	_cam_front.global_position = c + Vector3(1.6, 0.25, -3.4)
	_cam_front.look_at(c, Vector3.UP)
	_cam_side.global_position = c + Vector3(3.6, 0.1, 0)
	_cam_side.look_at(c, Vector3.UP)

var _shots: Array = []   # [tag, cam] 待拍佇列
var _shot_wait := 0

func _queue_shots(tag: String) -> void:
	var game_cam: Camera3D = _p.get_node("Pivot/SpringArm3D/Camera3D")
	var pairs := [["tps", game_cam], ["front", _cam_front], ["side", _cam_side]]
	if _closeup:
		pairs = [["waist34", _cam_front], ["top", _cam_side]]
	for pair in pairs:
		_shots.append(["%s_%s" % [tag, pair[0]], pair[1]])

func _process(delta: float) -> bool:
	# 拍照中：每張切相機後等 3 幀再抓 viewport。
	if not _shots.is_empty():
		var cur: Array = _shots[0]
		if _shot_wait == 0:
			(cur[1] as Camera3D).make_current()
		_shot_wait += 1
		if _shot_wait >= 4:
			root.get_viewport().get_texture().get_image().save_png(OUT + cur[0] + ".png")
			_shots.pop_front()
			_shot_wait = 0
			if _shots.is_empty():
				(_p.get_node("Pivot/SpringArm3D/Camera3D") as Camera3D).make_current()
				_t = 0.0
				_phase += 1
		return false
	if _phase >= PHASES.size():
		for a in ["move_forward", "sprint"]:
			Input.action_release(a)
		var f := FileAccess.open(OUT + "log.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(_log, "  "))
		f.close()
		print("OUT ", ProjectSettings.globalize_path(OUT))
		quit()
		return true
	var ph: Array = PHASES[_phase]
	if _closeup:
		_cam_front.fov = 30
	if _t == 0.0:
		for a in ["move_forward", "sprint"]:
			Input.action_release(a)
		for a in ph[2]:
			Input.action_press(a)
		if ph[0] == "jump":
			_p.request_jump()
	_t += delta
	var sk := _skel()
	var fy := minf(_bone_y(sk, "mixamorig_LeftToeBase"), _bone_y(sk, "mixamorig_RightToeBase")) - _p.global_position.y
	var key: String = ph[0]
	_foot_min[key] = minf(_foot_min.get(key, 99.0), fy)
	if _t >= ph[1]:
		_place_cams()
		var sheath: Node3D = _p.find_child("Sheath", true, false)
		var tree: AnimationTree = _p.find_child("Tree", true, false)
		var pb: AnimationNodeStateMachinePlayback = tree.get("parameters/loco/playback")
		_log[key] = {
			"loco_state": str(pb.get_current_node()),
			"speed_xz": Vector2(_p.velocity.x, _p.velocity.z).length(),
			"on_floor": _p.is_on_floor(),
			"foot_min_y_rel": _foot_min[key],
			"hips_y_rel": _bone_y(sk, "mixamorig_Hips") - _p.global_position.y,
			"head_top_y_rel": _bone_y(sk, "mixamorig_HeadTop_End") - _p.global_position.y,
			"sheath_local": str(_p.global_transform.affine_inverse() * sheath.global_position),
			"sword_hand_visible": (_p.find_child("Sword_Hand", true, false) as Node3D).visible,
			"combat_ready": _p.get("_combat_anims_ready"),
		}
		print("PHASE ", key, " ", _log[key])
		_queue_shots(key)
	return false
