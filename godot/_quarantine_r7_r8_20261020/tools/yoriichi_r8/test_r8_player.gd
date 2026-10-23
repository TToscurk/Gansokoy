extends SceneTree
## R8 候選角色煙霧測試：拔刀／收刀可用、移動與跳躍可用、所有攻擊入口被擋。只讀，不寫資源。
##   godot --headless --fixed-fps 60 --path godot -s res://tools/yoriichi_r8/test_r8_player.gd
const PLAYER := "res://characters/yoriichi/player_yoriichi_r8.tscn"
var _p: CharacterBody3D
var _fail := 0
var _ok := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(c: bool, label: String) -> void:
	if c:
		_ok += 1
	else:
		_fail += 1
		push_error("FAIL " + label)
	print(("PASS " if c else "FAIL ") + label)

func _box(pos: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	root.add_child(b)

func _steps(n: int) -> void:
	for i in n:
		await physics_frame

func _run() -> void:
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	_p = (load(PLAYER) as PackedScene).instantiate()
	_p.set("r7_vfx_enabled", false)
	_p.set("sun_mastery", 100)
	_p.set("sun_breath_gauge", 100.0)
	root.add_child(_p)
	await _steps(10)
	_check(_p.get_script().resource_path.ends_with("yoriichi_character_r8.gd"), "R8 控制器已掛上")
	_check(int(_p.get("sword_state")) == 0, "起始收刀")
	_p.call("request_draw")
	var drew := false
	for i in 240:
		await physics_frame
		if int(_p.get("sword_state")) == 2:
			drew = true
			break
	_check(drew, "拔刀完成（sword_state=DRAWN）")
	var sh: Node3D = _p.get("_sword_hand")
	_check(sh != null and sh.visible, "刀在手上可見")
	# 所有攻擊入口
	_p.call("request_primary_attack")
	await _steps(3)
	_check(int(_p.get("action_state")) == 0, "左鍵普攻被擋")
	_p.call("request_heavy_cut")
	await _steps(3)
	_check(int(_p.get("action_state")) == 0, "重斬被擋")
	_check(bool(_p.call("begin_heavy_charge")) and not bool(_p.get("_heavy_charging")), "蓄力被擋")
	_check(not bool(_p.call("execute_form", 1, true)), "日之呼吸型被擋")
	_check(not bool(_p.call("execute_form", 10, true)), "空中型（火車）被擋")
	_check(not bool(_p.call("start_form13")), "十三型被擋")
	_p.call("request_continuous_spin")
	await _steps(3)
	_check(int(_p.get("action_state")) == 0, "特殊攻擊被擋")
	var ev := InputEventAction.new()
	ev.action = "attack_light"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _steps(4)
	_check(int(_p.get("action_state")) == 0, "實際送出 attack_light 輸入也不出招")
	# 移動與跳躍
	var x0 := _p.global_position
	Input.action_press("move_forward")
	await _steps(40)
	Input.action_release("move_forward")
	_check((_p.global_position - x0).length() > 0.5, "可移動（%.2f m）" % (_p.global_position - x0).length())
	await _steps(20)
	_p.call("request_jump")
	var up := false
	for i in 60:
		await physics_frame
		if not _p.is_on_floor():
			up = true
	_check(up, "可跳躍")
	await _steps(80)
	# 收刀
	_p.call("request_sword_toggle")
	var sheathed := false
	for i in 240:
		await physics_frame
		if int(_p.get("sword_state")) == 0:
			sheathed = true
			break
	_check(sheathed, "收刀完成（sword_state=SHEATHED）")
	print("R8_PLAYER_RESULT pass=%d fail=%d" % [_ok, _fail])
	quit()
