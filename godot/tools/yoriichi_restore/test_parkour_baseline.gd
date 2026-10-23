extends SceneTree
## 跑酷基準測試（正式 player_yoriichi.tscn，只讀，不寫資源／場景）。清理前後各跑一次比對。
##   godot --headless --fixed-fps 60 --path godot -s res://tools/yoriichi_restore/test_parkour_baseline.gd -- <out_name>
## 測項：走／跑／衝刺、跑步急轉、一般跳＋落地、二段空翻、踩牆跳、空中攀上矮牆（Mantle）、地面蹬牆跑上高牆（Wall Run）、
##       高處落下（翻滾／重落地）、攀爬後與落地後恢復一般操作、拔刀後移動與跳躍。逐項記錄實際數值。
const PLAYER := "res://characters/yoriichi/player_yoriichi.tscn"
var _p: CharacterBody3D
var _rows := []
var _fail := 0

func _initialize() -> void:
	call_deferred("_run")

func _rec(name: String, ok: bool, data: Dictionary) -> void:
	data["case"] = name
	data["ok"] = ok
	_rows.append(data)
	if not ok:
		_fail += 1
	print(("PASS " if ok else "FAIL ") + name + " " + JSON.stringify(data))

func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	root.add_child(b)
	return b

func _steps(n: int) -> void:
	for i in n:
		await physics_frame

func _spawn(at: Vector3, yaw := 0.0) -> void:
	if _p != null:
		_p.queue_free()
		await _steps(2)
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump"]:
		Input.action_release(a)
	_p = (load(PLAYER) as PackedScene).instantiate()
	root.add_child(_p)
	_p.global_position = at
	var vis: Node3D = _p.get("_visual")
	await _steps(6)
	vis = _p.get("_visual")
	if vis != null:
		vis.global_rotation.y = yaw
	# 相機轉接器每格維持 Pivot 朝向 → move_forward 一律朝世界 -Z；障礙因此都放在 -Z 側。
	await _steps(4)

func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	await _steps(frames)
	Input.action_release(action)

func _anim_now() -> String:
	var t: AnimationTree = _p.get("_tree")
	var s := ""
	if t != null:
		var pb = t.get("parameters/loco/playback")
		if pb != null:
			s = str(pb.get_current_node())
		if t.get("parameters/full/active"):
			s += "+full:" + str(t.get("parameters/full_sel/current_state"))
	return s

func _run() -> void:
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	# 障礙：矮牆（1.2 m，Mantle）、高牆（2.6 m，Wall Run）、高台（4 m，落下）、側牆（踩牆跳）
	_box(Vector3(0, 0.6, -26), Vector3(6, 1.2, 2))
	_box(Vector3(20, 1.3, -26), Vector3(6, 2.6, 2))
	_box(Vector3(-20, 2.0, 0), Vector3(4, 4.0, 4))
	_box(Vector3(40, 3.0, -6), Vector3(12, 6.0, 0.6))

	# 1 走／跑／衝刺
	await _spawn(Vector3(0, 0.05, 0))
	var p0 := _p.global_position
	await _hold("move_forward", 60)
	var run_d := (_p.global_position - p0).length()
	var run_anim := _anim_now()
	await _steps(30)
	p0 = _p.global_position
	Input.action_press("sprint")
	await _hold("move_forward", 60)
	Input.action_release("sprint")
	var spr_d := (_p.global_position - p0).length()
	_rec("走跑", run_d > 2.0, {"run_1s_m": snappedf(run_d, 0.01), "anim": run_anim})
	_rec("衝刺", spr_d > run_d * 1.15, {"sprint_1s_m": snappedf(spr_d, 0.01)})

	# 2 跑步急轉
	await _steps(20)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _steps(45)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	var turned := false
	for i in 30:
		await physics_frame
		if float(_p.get("_run_turn_left")) > 0.0:
			turned = true
	Input.action_release("move_back")
	Input.action_release("sprint")
	_rec("跑步急轉", turned, {"run_turn_triggered": turned})

	# 3 一般跳＋落地
	await _spawn(Vector3(60, 0.05, 0))
	var y0 := _p.global_position.y
	_p.call("request_jump")
	var peak := y0
	var air_f := 0
	var landed := false
	for i in 120:
		await physics_frame
		peak = maxf(peak, _p.global_position.y)
		if not _p.is_on_floor():
			air_f += 1
		elif air_f > 5:
			landed = true
			break
	_rec("一般跳與落地", landed and peak - y0 > 0.8, {"apex_m": snappedf(peak - y0, 0.01), "air_frames": air_f})

	# 4 二段空翻
	await _steps(30)
	_p.call("request_jump")
	await _steps(18)
	var vy_before := _p.velocity.y
	_p.call("request_jump")
	await _steps(2)
	var dj := bool(_p.get("_double_jump_used"))
	_rec("二段空翻", dj and _p.velocity.y > vy_before, {"double_jump_used": dj, "vy_after": snappedf(_p.velocity.y, 0.1)})
	await _steps(90)

	# 5 空中攀上矮牆（Mantle）
	await _spawn(Vector3(0, 0.05, -22.5))
	Input.action_press("move_forward")
	await _steps(4)
	_p.call("request_jump")
	var mantled := false
	var top_y := 0.0
	for i in 120:
		await physics_frame
		if float(_p.get("_climb_left")) > 0.0:
			mantled = true
		if mantled and float(_p.get("_climb_left")) <= 0.0:
			break
	Input.action_release("move_forward")
	await _steps(20)
	top_y = _p.global_position.y
	_rec("攀上矮牆 Mantle", mantled and top_y > 1.1, {"climbed": mantled, "end_y": snappedf(top_y, 0.02), "wall_h": 1.2, "pos": str(_p.global_position.snapped(Vector3.ONE*0.01))})
	var pm := _p.global_position
	await _hold("move_forward", 30)
	_rec("攀爬結束後恢復移動", (_p.global_position - pm).length() > 0.5 and int(_p.get("action_state")) == 0,
		{"moved_m": snappedf((_p.global_position - pm).length(), 0.01)})

	# 6 地面蹬牆跑上高牆（Wall Run）
	await _spawn(Vector3(20, 0.05, -23.6))
	Input.action_press("move_forward")
	await _steps(3)
	_p.call("request_jump")
	var wr := false
	for i in 150:
		await physics_frame
		if float(_p.get("_climb_left")) > 0.0:
			wr = true
		if wr and float(_p.get("_climb_left")) <= 0.0:
			break
	Input.action_release("move_forward")
	await _steps(20)
	_rec("蹬牆跑上高牆 Wall Run", wr and _p.global_position.y > 2.4, {"climbed": wr, "end_y": snappedf(_p.global_position.y, 0.02), "wall_h": 2.6})

	# 7 踩牆跳：牆高 6 m（超出 Wall Run 3.4 m 上限，不會被當成蹬牆跑上去）。先跳起、朝牆前進，貼牆時再按跳。
	await _spawn(Vector3(40, 0.05, -4.3))      # 牆面 z=-5.7，騰空中約 0.3 s 抵達
	_p.call("request_jump")
	await _steps(6)
	Input.action_press("move_forward")
	var on_wall := false
	var wj_vy := 0.0
	var did := false
	for i in 60:
		await physics_frame
		if _p.is_on_wall() and not _p.is_on_floor() and not did:
			on_wall = true
			_p.call("request_jump")
			await _steps(2)
			wj_vy = _p.velocity.y
			did = true
			break
	Input.action_release("move_forward")
	_rec("踩牆跳", on_wall and wj_vy > 3.0, {"on_wall": on_wall, "vy_after": snappedf(wj_vy, 0.1)})
	await _steps(120)

	# 8 高台落下（翻滾或重落地）＋落地後恢復
	await _spawn(Vector3(-20, 4.1, 0))
	await _steps(10)
	Input.action_press("move_left")
	var tricks := []
	var land_t := false
	for i in 200:
		await physics_frame
		var a := _anim_now()
		if a.find("Trick_LandRoll") >= 0 or a.find("Trick_HardLand") >= 0 or a.find("land_roll") >= 0 or a.find("hard_land") >= 0:
			if not tricks.has(a):
				tricks.append(a)
		if _p.is_on_floor() and _p.global_position.y < 0.3:
			land_t = true
	Input.action_release("move_left")
	await _steps(40)
	var pl := _p.global_position
	await _hold("move_forward", 30)
	_rec("高台落下著地", land_t, {"landing_anims": tricks, "fall_h": 4.0})
	_rec("落地後恢復移動", (_p.global_position - pl).length() > 0.5, {"moved_m": snappedf((_p.global_position - pl).length(), 0.01)})

	# 9 拔刀後移動與跳躍
	await _spawn(Vector3(60, 0.05, 30))
	_p.call("request_draw")
	await _steps(120)
	var drawn := int(_p.get("sword_state")) == 2
	var pd := _p.global_position
	await _hold("move_forward", 40)
	_p.call("request_jump")
	var up := false
	for i in 40:
		await physics_frame
		if not _p.is_on_floor():
			up = true
	_rec("拔刀後移動與跳躍", drawn and up and (_p.global_position - pd).length() > 1.0,
		{"drawn": drawn, "moved_m": snappedf((_p.global_position - pd).length(), 0.01), "jumped": up})

	var args := OS.get_cmdline_user_args()
	var nm: String = args[0] if args.size() > 0 else "baseline"
	var f := FileAccess.open("user://parkour_%s.json" % nm, FileAccess.WRITE)
	f.store_string(JSON.stringify(_rows, " "))
	f.close()
	print("PARKOUR_RESULT cases=%d fail=%d json=%s" % [_rows.size(), _fail, ProjectSettings.globalize_path("user://parkour_%s.json" % nm)])
	quit()
