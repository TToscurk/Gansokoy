extends SceneTree
## 原始（正式）緣一戰鬥操作測試：player_yoriichi.tscn。只讀，不寫資源／場景。
##   godot --headless --fixed-fps 60 --path godot -s res://tools/yoriichi_restore/test_original_combat.gd
const PLAYER := "res://characters/yoriichi/player_yoriichi.tscn"
var _p: CharacterBody3D
var _fail := 0
var _n := 0

class Dummy extends StaticBody3D:
	var hits := 0
	func take_hit(data: Dictionary) -> Dictionary:
		hits += 1
		return {"result": "hit", "damage": data.get("damage", 0), "attacker_posture": 0.0}

func _initialize() -> void:
	call_deferred("_run")

func _ck(ok: bool, name: String, info := "") -> void:
	_n += 1
	if not ok:
		_fail += 1
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))

func _steps(k: int) -> void:
	for i in k:
		await physics_frame

func _wait_free(maxf_: int) -> bool:
	for i in maxf_:
		await physics_frame
		if int(_p.get("action_state")) == 0:
			return true
	return false

func _run() -> void:
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	var fl := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(80, 1, 80)
	cs.shape = sh
	fl.add_child(cs)
	fl.position = Vector3(0, -0.5, 0)
	root.add_child(fl)
	_p = (load(PLAYER) as PackedScene).instantiate()
	root.add_child(_p)
	await _steps(10)
	_ck(_p.get_script().resource_path.ends_with("characters/yoriichi/yoriichi_character.gd"), "正式控制器 yoriichi_character.gd", _p.get_script().resource_path)
	var dm := Dummy.new()
	var dcs := CollisionShape3D.new()
	var dsh := CapsuleShape3D.new()
	dsh.radius = 0.35
	dsh.height = 1.8
	dcs.shape = dsh
	dcs.position = Vector3(0, 0.9, 0)
	dm.add_child(dcs)
	var vis: Node3D = _p.get("_visual")
	dm.position = _p.global_position + vis.global_basis.z * 1.3
	dm.collision_layer = 0xFFFFFFFF
	root.add_child(dm)
	await _steps(4)
	# 拔刀
	_p.call("request_draw")
	var drawn := false
	for i in 240:
		await physics_frame
		if int(_p.get("sword_state")) == 2:
			drawn = true
			break
	_ck(drawn, "拔刀")
	# 普通攻擊三段
	var names := []
	for k in 3:
		_p.call("request_primary_attack")
		for i in 8:
			await physics_frame
			var nm := str(_p.get("_active_attack_name"))
			if nm != "" and not names.has(nm):
				names.append(nm)
	await _steps(30)
	_ck(names.size() >= 1, "普通攻擊（左鍵）出招", JSON.stringify(names))
	await _wait_free(240)
	_ck(dm.hits >= 1, "普通攻擊命中木樁", "hits=%d" % dm.hits)
	# 重斬（右鍵點按）
	var h0 := dm.hits
	_p.call("request_heavy_cut")
	await _steps(6)
	var heavy_name := str(_p.get("_active_attack_name"))
	await _wait_free(300)
	_ck(heavy_name != "", "重斬（右鍵）出招", heavy_name)
	# 閃避
	var p0 := _p.global_position
	_p.call("request_dodge")
	await _steps(4)
	var dodging := int(_p.get("action_state")) == 2
	await _wait_free(200)
	_ck(dodging, "閃避（Shift 短按）", "moved=%.2f m" % (_p.global_position - p0).length())
	# 格擋
	_p.call("begin_guard")
	await _steps(10)
	var guard := bool(_p.get("_guard_held"))
	_p.call("end_guard")
	await _steps(20)
	_ck(guard, "格擋（F）")
	# 日之呼吸壹之型（正式型表）
	_p.set("sun_mastery", 100)
	_p.set("sun_breath_gauge", 100.0)
	var form_ok := bool(_p.call("execute_form", 1, true))
	await _steps(6)
	var form_name := str(_p.get("_active_attack_name"))
	await _wait_free(400)
	_ck(form_ok, "日之呼吸壹之型（正式型表）", form_name)
	# 收刀
	_p.call("request_sword_toggle")
	var sheathed := false
	for i in 300:
		await physics_frame
		if int(_p.get("sword_state")) == 0:
			sheathed = true
			break
	_ck(sheathed, "收刀")
	# 沒有任何 R7／R8 動畫被載入
	var anim: AnimationPlayer = _p.get("_anim")
	var bad := []
	for lib in anim.get_animation_library_list():
		for a in anim.get_animation_library(lib).get_animation_list():
			var res := anim.get_animation(a)
			if res != null and (res.resource_path.find("anims_r7") >= 0 or res.resource_path.find("v24_r7") >= 0 or res.resource_path.find("v24_r8") >= 0):
				bad.append(res.resource_path)
	_ck(bad.is_empty(), "正式角色未載入任何 R7／R8 動畫", JSON.stringify(bad))
	print("ORIG_COMBAT_RESULT cases=%d fail=%d" % [_n, _fail])
	quit()
