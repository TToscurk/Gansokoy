extends SceneTree
## R5 候選實機驗收（複製自 tools/yoriichi_r4/capture_r4.gd；原檔不動）。需 rendering，不可 --headless：
##   godot --path . --resolution 1280x720 --fixed-fps 30 -s tools/yoriichi_r5/capture_r5.gd -- 測項,逗號 [player.tscn] [輸出子資料夾]
## R5 測項逐格記錄 r5 狀態（clip 格、手上刀可見、刀身露出、hitbox monitoring）到 log.json。
## 測項 cam 參數 video=true 時每幀存圖（--fixed-fps 30 → 每張 = 1/30 s 遊戲時間）供合成 MP4。
## 原始說明：
##   godot --path . --resolution 1280x720 -s tools/v24_anim/capture_v24_moves.gd [-- 只跑的測項,逗號分隔]
## 自建測試場（地面、1.5 m 木箱、2.4 m 平台、6 m 高牆、5 m 高台），以 InputEventAction 模擬按鍵，
## 每個測項從固定位置開始，依時間點截圖（追身 3/4 鏡頭）並記錄狀態到 user://v24_moves/log.json。

var OUT := "user://r5_moves/"
var _player_path := "res://characters/yoriichi/player_yoriichi_r5.tscn"
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
		OUT = "user://r5_moves/" + args[2] + "/"
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
	root.add_child(_p)
	_cam = Camera3D.new()
	_cam.fov = 50
	root.add_child(_cam)
	_cam.make_current()
	_tests = [
		# [名稱, 起點, 面向yaw, 長度, 事件[[t, "hold"/"release"/"tap", action]], 截圖[[t, 名稱]], 鏡頭側(1右/-1左), 鏡頭]
		# R5：收刀狀態下 t=1.6 s 按一下 LMB → 完整拔刀斬（3.5 s clip）。影片自 t=1.5 s 起每格存圖。
		["r5_qd_rear", Vector3(0, 0, 70), PI, 5.6, [[1.6, "tap", "attack_light"]], [[5.4, "end"]], 1,
			{"back": true, "dist": 3.0, "h": 0.55, "notrail": false, "video": true}],
		["r5_qd_side", Vector3(0, 0, 75), PI, 5.6, [[1.6, "tap", "attack_light"]], [[5.4, "end"]], 1,
			{"side": true, "dist": 3.0, "h": 0.25, "notrail": true, "video": true}],
		["r5_qd_front", Vector3(0, 0, 80), PI, 5.6, [[1.6, "tap", "attack_light"]], [[5.4, "end"]], -1,
			{"front": true, "dist": 3.0, "h": 0.25, "notrail": true, "video": true}],
		# 殘心後（clip f40 = t 2.93 s）按住前進 → 剩下的納刀改走 upper 層、腿交回 locomotion
		["r5_qd_cancel", Vector3(0, 0, 85), PI, 5.0, [[1.6, "tap", "attack_light"], [3.1, "hold", "move_forward"], [4.3, "release", "move_forward"]], [[4.8, "end"]], 1,
			{"back": true, "dist": 3.2, "h": 0.55, "notrail": false, "video": true}],
		# 握刀近拍（左前方看左腰鞘口與右手）
		["r5_grip_close", Vector3(0, 0, 90), PI, 5.4, [[1.6, "tap", "attack_light"]],
			[[2.21, "f18_grasp"], [2.36, "f22_koiguchi"], [2.48, "f26_draw"], [2.52, "f27_sayabanare"], [2.63, "f30_cut"], [2.93, "f40_zanshin"], [3.6, "f60_low"], [3.93, "f70_noto"], [4.2, "f78_sheathed"]], -1,
			{"front": true, "dist": 1.35, "h": 0.05, "notrail": true}],
		# 收刀待機（未觸發）基準
		["idle", Vector3(0, 0, 10), PI, 1.6, [], [[1.5, "idle"]], 1],
	]
	if not _only.is_empty():
		_tests = _tests.filter(func(t): return t[0] in _only)

func _next_test() -> void:
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

func _state() -> Dictionary:
	var pb: AnimationNodeStateMachinePlayback = _p._tree.get("parameters/loco/playback")
	return {"t": snappedf(_t, 0.01), "pos": str(_p.global_position.snapped(Vector3.ONE * 0.01)), "vel": str(_p.velocity.snapped(Vector3.ONE * 0.01)),
		"floor": _p.is_on_floor(), "loco": str(pb.get_current_node()), "full": str(_p._tree.get("parameters/full_sel/current_state")),
		"full_on": _p._tree.get("parameters/full/active"), "sword": _p.sword_state, "action": _p.action_state,
		"climb": snappedf(_p._climb_left, 0.01), "trick": snappedf(_p._trick_left, 0.01),
		"r5": _p.get("_r5_active"), "r5_tail": _p.get("_r5_tail"), "layer": _p._attack_layer,
		"r5_frame": snappedf(_p._action_elapsed * 30.0, 0.1) if _p.get("_r5_active") else -1.0,
		"hand_vis": _p._sword_hand.visible if _p._sword_hand else null, "sheathed_vis": _p._sword_sheathed.visible if _p._sword_sheathed else null,
		"hitbox": _p._hitbox.monitoring if _p._hitbox else null}

var _settle := 0
func _process(delta: float) -> bool:
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
	if cam.get("back", false):
		_cam.global_position = c - fwd * dist * 0.7 + side * dist * 0.7 + Vector3(0, cam.get("h", 0.6), 0)
	elif cam.get("side", false):
		_cam.global_position = c + side * dist + Vector3(0, cam.get("h", 0.6), 0)
	elif cam.get("front", false):
		_cam.global_position = c + fwd * dist + side * dist * 0.35 + Vector3(0, cam.get("h", 0.6), 0)
	else:
		_cam.global_position = c + (fwd + side).normalized() * dist + Vector3(0, cam.get("h", 0.6), 0)
	_cam.look_at(c, Vector3.UP)
	if cam.get("notrail", false) and _p._sword_trail != null:
		_p._sword_trail.visible = false
	if cam.get("video", false) and _t > 1.5:
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
