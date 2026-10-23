extends SceneTree
## R7 第一階段展示擷取（複製自 tools/yoriichi_r62/capture_r62.gd；原檔不動；輸出 user://r7_moves/）。
## R6.2 擷取（複製自 tools/yoriichi_r61/capture_r61.gd；R6.1 原檔不動；輸出 user://r62_moves/）。需 rendering，不可 --headless。
## 與 R6.1 版差別：骨架 dump 改在 Skeleton3D.skeleton_updated 記錄（＝所有 SkeletonModifier3D（R6.2 握刀 IK、SpringBone）之後的最終
## 姿勢；Godot 4.3+ 在蒙皮後會把骨架還原成動畫姿勢，_process 讀到的是未修改的姿勢），並記錄 R6.2 IK 狀態。
## R6.1 驗收（複製自 tools/yoriichi_r6/capture_r6.gd；原檔不動；輸出 user://r61_moves/）。需 rendering，不可 --headless：
##   godot --path . --resolution 1280x720 --fixed-fps 30 -s tools/yoriichi_r6/capture_r6.gd -- 測項,逗號 [player.tscn] [輸出子資料夾]
## 鏡頭 dict 加："bone"（追骨頭近拍）、"dir"（角色本地方向，+Z=角色前方）、"dump"（逐格存全骨架 global pose → <測項>/poses.json）。
## 事件加：[t, "rig", 屬性, 值] 設 BodyVisual（YoriichiV24Rig）屬性，例如 springs_enabled。
## R5 測項逐格記錄 r5 狀態（clip 格、手上刀可見、刀身露出、hitbox monitoring）到 log.json。
## 測項 cam 參數 video=true 時每幀存圖（--fixed-fps 30 → 每張 = 1/30 s 遊戲時間）供合成 MP4。
## 原始說明：
##   godot --path . --resolution 1280x720 -s tools/v24_anim/capture_v24_moves.gd [-- 只跑的測項,逗號分隔]
## 自建測試場（地面、1.5 m 木箱、2.4 m 平台、6 m 高牆、5 m 高台），以 InputEventAction 模擬按鍵，
## 每個測項從固定位置開始，依時間點截圖（追身 3/4 鏡頭）並記錄狀態到 user://v24_moves/log.json。

var OUT := "user://r7_moves/"
var _player_path := "res://characters/yoriichi/player_yoriichi.tscn"
var _vframe := 0
var _p: CharacterBody3D
var _cam: Camera3D
var _log := {}
var _tests: Array = []
var _ti := -1
var _t := 0.0
var _events: Array = []
var _shots_pending: Array = []
var _shot_wait := 0
var _cam_side := 1.0
var _only: PackedStringArray = []
var _fix_anchor := Vector3.INF
var _fix_dir := Vector3.FORWARD

func _box(pos: Vector3, size: Vector3, col: Color) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	b.add_child(mi)
	b.position = pos + Vector3(0, size.y * 0.5, 0)
	root.add_child(b)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_only = args[0].split(",")
	if args.size() > 1 and args[1] != "":
		_player_path = args[1]
	if args.size() > 2:
		OUT = "user://r7_moves/" + args[2] + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.68, 0.74)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.82)
	e.ambient_light_energy = 0.8
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	_box(Vector3(0, -1, 0), Vector3(200, 1, 200), Color(0.45, 0.42, 0.36))
	_box(Vector3(0, 0, -13.5), Vector3(4, 1.5, 3), Color(0.55, 0.4, 0.25))      # 木箱 1.5 m（攀上）
	_box(Vector3(8, 0, -13.5), Vector3(4, 2.4, 3), Color(0.5, 0.5, 0.55))      # 平台 2.4 m（蹬牆跑）
	_box(Vector3(-9, 0, 0), Vector3(1, 6, 10), Color(0.6, 0.58, 0.5))          # 高牆 6 m（踩牆跳）
	_box(Vector3(16, 0, 10), Vector3(4, 5, 4), Color(0.5, 0.45, 0.4))          # 高台 5 m（落地翻滾）
	_p = (load(_player_path) as PackedScene).instantiate()
	if _p.get("r7_vfx_enabled") != null:
		_p.set("r7_vfx_enabled", false)      # R7 展示：關閉刀光與蓄力火焰
	if OS.get_environment("R62_NOIK") == "1" and _p.get("r62_grip_ik_enabled") != null:
		_p.set("r62_grip_ik_enabled", false)      # A/B：同一 R6.2 場景關掉握刀 IK
	root.add_child(_p)
	_cam = Camera3D.new()
	_cam.fov = 50
	root.add_child(_cam)
	_cam.make_current()
	_tests = [
		# R7 第一階段展示（刀光／蓄力火焰關閉）。[名稱, 起點, 面向yaw, 長度, 事件, 截圖, 鏡頭側, 鏡頭]
		["r7_combo", Vector3(0, 0, 0), PI, 4.6, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.6, "tap", "attack_light"],
			[2.85, "tap", "attack_light"]], [], 1, {"fixed": [1.0, 0.0, 0.35], "dist": 3.6, "h": 1.0, "video": true, "vstart": 2.2, "notrail": true}],
		["r7_combo_front", Vector3(0, 0, 20), PI, 4.6, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_light"], [2.6, "tap", "attack_light"],
			[2.85, "tap", "attack_light"]], [], 1, {"fixed": [0.45, 0.05, 1.0], "dist": 3.4, "h": 1.1, "video": true, "vstart": 2.2, "notrail": true}],
		["r7_heavy", Vector3(0, 0, 40), PI, 4.0, [[0.2, "call", "request_draw"], [2.4, "tap", "attack_heavy"]], [], 1,
			{"fixed": [1.0, 0.0, 0.35], "dist": 3.6, "h": 1.0, "video": true, "vstart": 2.2, "notrail": true}],
		["r7_charge", Vector3(0, 0, 60), PI, 6.6, [[0.2, "call", "request_draw"], [2.4, "press", "attack_heavy"], [4.9, "unpress", "attack_heavy"]], [], 1,
			{"bone": "mixamorig_Hips", "dir": [1.0, 0.05, 0.35], "dist": 3.8, "video": true, "vstart": 2.2, "notrail": true}],
		["r7_qd", Vector3(0, 0, 80), PI, 3.4, [[0.8, "tap", "attack_light"]], [], 1,
			{"fixed": [1.0, 0.0, 0.35], "dist": 3.4, "h": 1.0, "video": true, "vstart": 0.6, "notrail": true}],
		["r7_qd_front", Vector3(0, 0, 100), PI, 3.4, [[0.8, "tap", "attack_light"]], [], 1,
			{"fixed": [0.45, 0.05, 1.0], "dist": 3.2, "h": 1.1, "video": true, "vstart": 0.6, "notrail": true}],
	]
	if not _only.is_empty():
		_tests = _tests.filter(func(t): return t[0] in _only)

var _dump: Array = []
var _skf: Skeleton3D = null
var _want_dump := false
var _dump_frame := -1


## 最終姿勢（modifier 之後）在這裡記錄；每個 process frame 只記一次
func _on_skel() -> void:
	if not _want_dump or _ti < 0 or _ti >= _tests.size():
		return
	var pf := Engine.get_process_frames()
	if pf == _dump_frame:
		return
	_dump_frame = pf
	var fr := {"t": snappedf(_t, 0.001), "skel_xf": _xf12(_skf.global_transform), "st": _state()}
	var bones := {}
	for bi in _skf.get_bone_count():
		bones[_skf.get_bone_name(bi)] = _xf12(_skf.get_bone_global_pose(bi))
	fr["bones"] = bones
	var sh: Node3D = _p.get("_sword_hand")
	if sh:
		fr["sword_hand"] = _xf12(_skf.global_transform.affine_inverse() * sh.global_transform)
	var sb: Node3D = _p.find_child("Sheath", true, false) as Node3D
	if sb:
		fr["sheath"] = _xf12(_skf.global_transform.affine_inverse() * sb.global_transform)
	_dump.append(fr)


func _ik_state() -> Dictionary:
	var ik = _p.get("_r62_ik")
	if ik == null:
		return {}
	return {"w": snappedf(ik.right_weight, 0.001), "lw": snappedf(ik.last_left_weight, 0.001), "qd": ik.qd_on,
		"err": [snappedf(ik.last_err[0], 0.01), snappedf(ik.last_err[1], 0.01)],
		"wR": ik.last_wrist.get("Right", {}), "wL": ik.last_wrist.get("Left", {}),
		"aR": ik.last_wrist_anim.get("Right", {}), "aL": ik.last_wrist_anim.get("Left", {})}

func _xf12(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]

func _flush_dump() -> void:
	if _ti >= 0 and _ti < _tests.size() and not _dump.is_empty():
		var vd: String = OUT + _tests[_ti][0] + "/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(vd))
		var f := FileAccess.open(vd + "poses.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(_dump))
		f.close()
	_dump = []

func _next_test() -> void:
	_want_dump = false
	_flush_dump()
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "walk", "guard", "jump", "attack_light", "draw_sword"]:
		if InputMap.has_action(a):
			Input.action_release(a)
	_ti += 1
	if _ti >= _tests.size():
		var f := FileAccess.open(OUT + "log.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(_log, "  "))
		f.close()
		print("OUT ", ProjectSettings.globalize_path(OUT))
		quit()
		return
	var tt: Array = _tests[_ti]
	_p.velocity = Vector3.ZERO
	_fix_anchor = Vector3.INF
	# 每個測項從收刀、自由狀態開始（前一項可能停在拔刀）
	if int(_p.get("sword_state")) != 0:
		_p.set("sword_state", 0)
		_p.set("action_state", 0)
		_p.call("_apply_sword_visibility")
		_p._tree.set("parameters/grip/blend_amount", 0.0)
	var bvr := _p.get_node_or_null("BodyVisual")
	if bvr and bvr.get("springs_enabled") != null:
		bvr.set("springs_enabled", true)
	_p.global_position = tt[1]
	_p.snap_yaw(tt[2] - PI)
	_t = 0.0
	_events = (tt[4] as Array).duplicate(true)
	_shots_pending = (tt[5] as Array).duplicate(true)
	_cam_side = tt[6]
	_log[tt[0]] = []
	_vframe = 0

func _send(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)

## 左手（中指根）到刀鞘軸的距離（m）與沿軸位置：鞘 MeshInstance3D 的 AABB 最長軸當鞘軸
func _lh_saya() -> Array:
	var sh: Node3D = _p.find_child("Sheath", true, false) as Node3D
	if sh == null:
		return []
	var mis := sh.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		return []
	var mi: MeshInstance3D = mis[0]
	var ab := mi.get_aabb()
	var ax := 0
	for k in 3:
		if ab.size[k] > ab.size[ax]:
			ax = k
	var a := ab.get_center()
	var b := a
	a[ax] = ab.position[ax]
	b[ax] = ab.position[ax] + ab.size[ax]
	var A := mi.global_transform * a
	var B := mi.global_transform * b
	var sk: Skeleton3D = _p._visual.find_children("*", "Skeleton3D", true, false)[0]
	var out := []
	for bn in ["mixamorig_LeftHandMiddle1", "mixamorig_LeftHand"]:
		var P := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bn)).origin
		var ab3 := B - A
		var t := clampf((P - A).dot(ab3) / ab3.length_squared(), 0.0, 1.0)
		out.append([snappedf((P - (A + ab3 * t)).length(), 0.001), snappedf(t, 0.01)])
	return out

func _state() -> Dictionary:
	var pb: AnimationNodeStateMachinePlayback = _p._tree.get("parameters/loco/playback")
	return {"t": snappedf(_t, 0.01), "pos": str(_p.global_position.snapped(Vector3.ONE * 0.01)), "vel": str(_p.velocity.snapped(Vector3.ONE * 0.01)),
		"floor": _p.is_on_floor(), "loco": str(pb.get_current_node()), "full": str(_p._tree.get("parameters/full_sel/current_state")),
		"full_on": _p._tree.get("parameters/full/active"), "sword": _p.sword_state, "action": _p.action_state,
		"climb": snappedf(_p._climb_left, 0.01), "trick": snappedf(_p._trick_left, 0.01),
		"r5": _p.get("_r5_active"), "r5_tail": _p.get("_r5_tail"), "layer": _p._attack_layer,
		"r5_frame": snappedf(_p._action_elapsed * 30.0, 0.1) if _p.get("_r5_active") else -1.0,
		"hand_vis": _p._sword_hand.visible if _p._sword_hand else null, "sheathed_vis": _p._sword_sheathed.visible if _p._sword_sheathed else null,
		"hitbox": _p._hitbox.monitoring if _p._hitbox else null, "lower": _p._tree.get("parameters/lower/internal_active"),
		"upper": _p._tree.get("parameters/upper/internal_active"), "upper_sel": str(_p._tree.get("parameters/upper_sel/current_state")),
		"trail": _p._sword_trail.is_emitting if _p._sword_trail else null, "atk": str(_p._active_attack_name),
		"elapsed": snappedf(_p._action_elapsed, 0.001), "action_real": snappedf(_p._action_real, 0.001),
		"ik": _ik_state(), "lh_saya": _lh_saya() if (str(_tests[_ti][0]).begins_with("idle") or str(_tests[_ti][0]).begins_with("qd")) else []}

var _settle := 0
func _process(delta: float) -> bool:
	if _skf == null and _p.get("_visual") != null:
		_skf = _p._visual.find_children("*", "Skeleton3D", true, false)[0]
		_skf.skeleton_updated.connect(_on_skel)
	if _settle < 10:
		_settle += 1
		if _settle == 10:
			_next_test()
		return false
	if _ti >= _tests.size():
		return true
	# 截圖：Godot 視窗抓圖要等兩幀渲染
	if _shot_wait > 0:
		_shot_wait -= 1
		if _shot_wait == 0:
			var name: String = _tests[_ti][0] + "_" + _pending_name
			root.get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
			var st := _state()
			st["shot"] = name
			(_log[_tests[_ti][0]] as Array).append(st)
		return false
	_t += delta
	for ev in _events.duplicate():
		if _t >= ev[0]:
			match ev[1]:
				"hold":
					Input.action_press(ev[2])
				"release":
					Input.action_release(ev[2])
				"tap":
					_send(ev[2], true)
					_send(ev[2], false)
				"tap_sprint":
					_send(ev[2], true)
					_send(ev[2], false)
				"call":
					_p.call(ev[2])
				"callv":
					_p.callv(ev[2], ev[3])
				"rig":
					_p.get_node("BodyVisual").set(ev[2], ev[3])
				"press":
					_send(ev[2], true)
					Input.action_press(ev[2])
				"unpress":
					_send(ev[2], false)
					Input.action_release(ev[2])
			_events.erase(ev)
	# 追身鏡頭：角色右前 45°（cam_side=-1 為左前）
	var c := _p.global_position + Vector3(0, 1.0, 0)
	var fwd := Vector3(0, 0, -1)
	var side := Vector3(1, 0, 0) * _cam_side
	if _tests[_ti][0] == "walljump":
		fwd = Vector3(1, 0, 0)    # 鏡頭在牆外側（+x），看角色貼牆與蹬離
		side = Vector3(0, 0, 1.6)
	var cam: Dictionary = _tests[_ti][7] if (_tests[_ti] as Array).size() > 7 else {}
	var dist: float = cam.get("dist", 4.5)
	if cam.has("fixed"):
		# 固定世界鏡頭：以測項開始時的角色位置為錨（看得到真實踏步／位移），dir 為角色本地方向
		if _fix_anchor == Vector3.INF:
			_fix_anchor = _p.global_position + Vector3(0, float(cam.get("h", 1.0)), 0)
			var fv: Array = cam["fixed"]
			_fix_dir = ((_p._visual as Node3D).global_transform.basis.orthonormalized() * Vector3(float(fv[0]), float(fv[1]), float(fv[2]))).normalized()
		_cam.global_position = _fix_anchor + _fix_dir * dist
		_cam.look_at(_fix_anchor + Vector3(0, 0, 0), Vector3.UP)
	elif cam.has("bone"):
		var sk: Skeleton3D = _p._visual.find_children("*", "Skeleton3D", true, false)[0]
		var bi := sk.find_bone(str(cam["bone"]))
		var bp := sk.global_transform * sk.get_bone_global_pose(bi).origin
		var dv: Array = cam.get("dir", [1, 0, 1])
		var vb: Basis = (_p._visual as Node3D).global_transform.basis.orthonormalized()
		var dw: Vector3 = (vb * Vector3(float(dv[0]), float(dv[1]), float(dv[2]))).normalized()
		_cam.global_position = bp + dw * dist
		_cam.look_at(bp, Vector3.UP)
	elif cam.get("back", false):
		_cam.global_position = c - fwd * dist * 0.7 + side * dist * 0.7 + Vector3(0, cam.get("h", 0.6), 0)
	elif cam.get("side", false):
		_cam.global_position = c + side * dist + Vector3(0, cam.get("h", 0.6), 0)
	elif cam.get("front", false):
		_cam.global_position = c + fwd * dist + side * dist * 0.35 + Vector3(0, cam.get("h", 0.6), 0)
	else:
		_cam.global_position = c + (fwd + side).normalized() * dist + Vector3(0, cam.get("h", 0.6), 0)
	if not cam.has("bone") and not cam.has("fixed"):
		_cam.look_at(c, Vector3.UP)
	if cam.get("notrail", false) and _p._sword_trail != null:
		_p._sword_trail.visible = false
	_want_dump = cam.get("dump", false)
	if cam.get("video", false) and _t > float(cam.get("vstart", 1.5)):
		var vd: String = OUT + _tests[_ti][0] + "/"
		if _vframe == 0:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(vd))
		root.get_viewport().get_texture().get_image().save_png(vd + "f%04d.png" % _vframe)
		var vs := _state()
		vs["vframe"] = _vframe
		(_log[_tests[_ti][0]] as Array).append(vs)
		_vframe += 1
	if _t > 0.0 and int(_t * 10.0) != int((_t - delta) * 10.0):
		var st := _state()
		(_log[_tests[_ti][0]] as Array).append(st)
	for sh in _shots_pending.duplicate():
		if _t >= sh[0]:
			_pending_name = sh[1]
			_shots_pending.erase(sh)
			_shot_wait = 2
			return false
	if _t >= _tests[_ti][3]:
		_next_test()
	return false

var _pending_name := ""
