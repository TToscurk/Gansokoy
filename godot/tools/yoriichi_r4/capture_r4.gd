extends SceneTree
## R4 候選實機驗收（複製自 tools/v24_anim/capture_v24_moves.gd；原檔不動）。需 rendering，不可 --headless：
##   godot --path . --resolution 1280x720 --fixed-fps 30 -s tools/yoriichi_r4/capture_r4.gd -- 測項,逗號 [player.tscn] [輸出子資料夾]
## 測項 cam 參數 video=true 時每幀存圖（--fixed-fps 30 → 每張 = 1/30 s 遊戲時間）供合成 MP4。
## 原始說明：
##   godot --path . --resolution 1280x720 -s tools/v24_anim/capture_v24_moves.gd [-- 只跑的測項,逗號分隔]
## 自建測試場（地面、1.5 m 木箱、2.4 m 平台、6 m 高牆、5 m 高台），以 InputEventAction 模擬按鍵，
## 每個測項從固定位置開始，依時間點截圖（追身 3/4 鏡頭）並記錄狀態到 user://v24_moves/log.json。

var OUT := "user://r4_moves/"
var _player_path := "res://characters/yoriichi/player_yoriichi_r4.tscn"
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
		OUT = "user://r4_moves/" + args[2] + "/"
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
		# [名稱, 起點, 面向yaw, 長度, 事件[[t, "hold"/"release"/"tap", action]], 截圖[[t, 名稱]], 鏡頭側(1右/-1左)]
		["idle", Vector3(0, 0, 10), PI, 1.6, [], [[1.5, "idle"]], 1],
		["walk", Vector3(0, 0, 10), PI, 1.6, [[0, "hold", "walk"], [0, "hold", "move_forward"]], [[1.4, "walk"]], 1],
		["jog", Vector3(0, 0, 10), PI, 1.6, [[0, "hold", "move_forward"]], [[1.4, "jog"]], 1],
		["sprint", Vector3(0, 0, 10), PI, 1.6, [[0, "hold", "move_forward"], [0, "hold", "sprint"]], [[1.4, "sprint"]], 1],
		["run_turn", Vector3(0, 0, 10), PI, 2.0, [[0, "hold", "move_forward"], [0, "hold", "sprint"], [1.0, "release", "move_forward"], [1.0, "hold", "move_back"]],
			[[1.15, "run_turn_mid"], [1.6, "run_turn_after"]], 1],
		["double_jump", Vector3(10, 0, 10), PI, 2.0, [[0, "hold", "move_forward"], [0.1, "tap", "jump"], [0.55, "tap", "jump"]],
			[[0.45, "jump_rise"], [0.75, "flip_mid"], [0.95, "flip_late"], [1.8, "after_land"]], 1],
		["mantle", Vector3(0, 0, -10.6), PI, 2.4, [[0, "hold", "move_forward"], [0.15, "tap", "jump"]],
			[[0.4, "mantle_0"], [0.55, "mantle_a"], [0.7, "mantle_a2"], [0.85, "mantle_b"], [1.25, "mantle_c"], [2.2, "mantle_end"]], 1, {"side": true, "dist": 4.5, "h": 0.3}],
		["wallrun", Vector3(8, 0, -11.4), PI, 2.8, [[0, "hold", "move_forward"], [0.1, "tap", "jump"]],
			[[0.3, "wallrun_0"], [0.5, "wallrun_a"], [0.7, "wallrun_a2"], [0.9, "wallrun_b"], [1.15, "wallrun_b2"], [1.4, "wallrun_c"], [2.6, "wallrun_end"]], 1, {"side": true, "dist": 5.0, "h": 0.5}],
		["walljump", Vector3(-7.3, 0, 0), -PI / 2, 2.2, [[0, "hold", "move_forward"], [0.05, "tap", "jump"], [0.42, "tap", "jump"]],
			[[0.38, "wall_touch"], [0.6, "walljump_flip"], [0.9, "walljump_late"]], -1],
		["high_drop", Vector3(16, 5.05, 9.0), PI, 2.6, [[0, "hold", "move_forward"]],
			[[0.9, "drop_land_a"], [1.25, "drop_land_b"], [2.4, "drop_after"]], 1],
		["combat", Vector3(0, 0, 25), PI, 7.2, [[0.2, "tap", "draw_sword"], [1.9, "tap", "attack_light"], [2.5, "tap", "attack_light"], [3.2, "tap", "attack_light"],
			[5.4, "press", "guard"], [6.2, "unpress", "guard"], [6.5, "tap_sprint", "sprint"]],
			[[0.55, "draw_grab"], [0.95, "draw_out"], [1.7, "drawn_idle"], [2.25, "atk1"], [2.95, "atk2"], [3.9, "atk3"], [6.0, "guard"], [6.75, "roll"]], 1,
			{"dist": 2.4, "h": 0.2, "notrail": true}],
		["heavy", Vector3(0, 0, 30), PI, 3.6, [[0.2, "call", "request_draw"], [1.9, "tap", "attack_heavy"]],
			[[2.45, "heavy_raise"], [2.62, "heavy_cut"], [2.78, "heavy_follow"], [3.4, "heavy_end"]], 1, {"dist": 2.6, "h": 0.3, "notrail": true}],
		["drawn_move", Vector3(0, 0, 35), PI, 5.0, [[0.2, "call", "request_draw"], [1.8, "hold", "walk"], [1.8, "hold", "move_forward"], [3.0, "release", "walk"], [4.0, "hold", "sprint"]],
			[[2.6, "walk"], [3.6, "run"], [4.7, "sprint"]], 1, {"dist": 3.2, "h": 0.3, "notrail": true}],
		["sleeve_drawn", Vector3(0, 0, 50), PI, 2.4, [[0.2, "call", "request_draw"]], [[1.9, "front"], [2.3, "front2"]], 1, {"dist": 2.0, "h": 0.15, "front": true, "notrail": true}],
		["sleeve_drawn_l", Vector3(0, 0, 50), PI, 0.6, [], [[0.4, "left"]], -1, {"dist": 2.0, "h": 0.15, "front": true, "notrail": true}],
		["sleeve_drawn_walk", Vector3(0, 0, 50), PI, 1.6, [[0.0, "hold", "walk"], [0.0, "hold", "move_forward"]], [[1.0, "front"], [1.35, "front2"]], 1, {"dist": 2.2, "h": 0.15, "front": true, "notrail": true}],
		["sleeve_atk", Vector3(0, 0, 55), PI, 3.6, [[0.1, "tap", "attack_light"], [0.7, "tap", "attack_light"], [1.4, "tap", "attack_light"]],
			[[0.45, "a1"], [1.1, "a2"], [2.0, "a3"]], 1, {"dist": 2.4, "h": 0.2, "front": true, "notrail": true}],
		["combo_seq", Vector3(0, 0, 60), PI, 4.6, [[0.1, "tap", "attack_light"], [0.8, "tap", "attack_light"], [1.6, "tap", "attack_light"]], [[0.30, "s00"], [0.55, "s01"], [0.80, "s02"], [1.05, "s03"], [1.30, "s04"], [1.55, "s05"], [1.80, "s06"], [2.05, "s07"], [2.30, "s08"], [2.55, "s09"], [2.80, "s10"], [3.05, "s11"], [3.30, "s12"], [3.55, "s13"], [3.80, "s14"], [4.05, "s15"]], 1, {"side": true, "dist": 3.2, "h": 0.3, "notrail": true}],
		["sheath_view", Vector3(0, 0, 45), PI, 1.2, [], [[0.8, "left"]], -1, {"side": true, "dist": 1.5, "h": -0.1}],
		["sheath_view_b", Vector3(0, 0, 45), PI, 1.2, [], [[0.8, "back34"]], -1, {"dist": 1.8, "h": 0.0, "back": true}],
		["lie_getup", Vector3(0, 0, 55), PI, 6.5, [[0.2, "call", "start_opening_lie_down"], [1.2, "call", "play_get_up"]],
			[[1.0, "lying"], [2.6, "getup_a"], [3.6, "getup_b"], [6.3, "getup_end"]], 1, {"dist": 3.2, "h": 0.4}],
		["meditate", Vector3(0, 0, 60), PI, 2.6, [[0.2, "call", "start_meditation_pose"], [2.3, "call", "end_meditation_pose"]],
			[[1.5, "sitting"], [2.55, "stood"]], 1, {"dist": 3.0, "h": 0.4}],
		# 袖子近拍：正面偏右 2.2 m，看手臂與袖子是否穿進身體／羽織
		["sleeve_idle", Vector3(0, 0, 40), PI, 1.6, [], [[1.0, "front"], [1.5, "front2"]], 1, {"dist": 2.2, "h": 0.1, "front": true}],
		["sleeve_walk", Vector3(0, 0, 40), PI, 1.6, [[0, "hold", "walk"], [0, "hold", "move_forward"]], [[1.0, "front"], [1.3, "front2"]], 1, {"dist": 2.2, "h": 0.1, "front": true}],
		["sleeve_jog", Vector3(0, 0, 40), PI, 1.6, [[0, "hold", "move_forward"]], [[1.0, "front"], [1.15, "front2"]], 1, {"dist": 2.4, "h": 0.1, "front": true}],
		["sleeve_sprint", Vector3(0, 0, 40), PI, 1.6, [[0, "hold", "move_forward"], [0, "hold", "sprint"]], [[1.0, "front"], [1.12, "front2"]], 1, {"dist": 2.6, "h": 0.1, "front": true}],
		# --- R4 additions: continuous video (every frame) from the gameplay rear camera and from the side
		["r4_combo_video", Vector3(0, 0, 70), PI, 4.2, [[0.2, "call", "request_draw"], [1.8, "tap", "attack_light"], [2.0, "tap", "attack_light"], [2.35, "tap", "attack_light"]],
			[[3.9, "end"]], 1, {"back": true, "dist": 3.0, "h": 0.55, "notrail": false, "video": true}],
		["r4_combo_side", Vector3(0, 0, 75), PI, 4.2, [[0.2, "call", "request_draw"], [1.8, "tap", "attack_light"], [2.0, "tap", "attack_light"], [2.35, "tap", "attack_light"]],
			[[3.9, "end"]], 1, {"side": true, "dist": 3.0, "h": 0.25, "notrail": true, "video": true}],
		["r4_combo_front", Vector3(0, 0, 80), PI, 4.2, [[0.2, "call", "request_draw"], [1.8, "tap", "attack_light"], [2.0, "tap", "attack_light"], [2.35, "tap", "attack_light"]],
			[[3.9, "end"]], 1, {"front": true, "dist": 3.0, "h": 0.25, "notrail": true, "video": true}],
		["r4_heavy_video", Vector3(0, 0, 85), PI, 4.0, [[0.2, "call", "request_draw"], [1.8, "tap", "attack_heavy"]],
			[[3.8, "end"]], 1, {"side": true, "dist": 3.0, "h": 0.3, "notrail": true, "video": true}],
		["r4_heavy_rear", Vector3(0, 0, 90), PI, 4.0, [[0.2, "call", "request_draw"], [1.8, "tap", "attack_heavy"]],
			[[3.8, "end"]], 1, {"back": true, "dist": 3.0, "h": 0.55, "notrail": false, "video": true}],
		["r4_move_video", Vector3(0, 0, 95), PI, 6.0, [[0.2, "call", "request_draw"], [1.8, "hold", "walk"], [1.8, "hold", "move_forward"], [2.8, "release", "move_forward"], [2.8, "hold", "move_left"], [3.6, "release", "move_left"], [3.6, "hold", "move_back"], [4.4, "release", "move_back"], [4.4, "release", "walk"], [5.0, "tap", "attack_light"]],
			[[5.9, "end"]], 1, {"dist": 3.4, "h": 0.4, "notrail": true, "video": true}],
		["r4_grip_close", Vector3(0, 0, 100), PI, 2.4, [[0.2, "call", "request_draw"]], [[2.0, "hand_front"]], 1, {"front": true, "dist": 0.9, "h": 0.05, "notrail": true}],
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
		"climb": snappedf(_p._climb_left, 0.01), "trick": snappedf(_p._trick_left, 0.01)}

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
