extends SceneTree
## Regression: 翻滾無敵幀（yoriichi_character.in_dodge_invuln / take_hit）。
##
##   Godot --headless --path godot --script tools/verify_dodge_iframes.gd
##
## 量的是行為，不是實作：無敵幀期間送出的命中必須是 "dodge" 且血／軀幹零變化；
## 窗口外的命中必須正常生效；兩個滑桿端點（0 / 0）必須真的把無敵幀關掉。

var failures := 0
var _player: Node = null


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[DODGE] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


## 平坦地板：翻滾需要 is_on_floor()，跑在 root 底下的空場景必須自己鋪。
func _make_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	col.shape = box
	body.add_child(col)
	body.position = Vector3(0, -0.5, 0)
	root.add_child(body)


func _hit() -> Dictionary:
	return {"damage": 20.0, "posture_damage": 12.0,
		"hit_dir": Vector3(0, 0, -1), "hit_pos": Vector3(0, 1, 0)}


## 起翻並等待，直到某個條件成立或超時。回傳實際等待的物理幀數。
func _roll_until(cond: Callable, limit := 300) -> int:
	_player.request_dodge()
	var n := 0
	while n < limit and not cond.call():
		await physics_frame
		await process_frame
		n += 1
	return n


func _run() -> void:
	_make_floor()
	var scene: PackedScene = load("res://characters/yoriichi/player_yoriichi.tscn")
	_player = scene.instantiate()
	root.add_child(_player)
	_player.global_position = Vector3(0, 0.3, 0)
	await _frames(12)
	check("player stands on the floor", _player.is_on_floor())
	_player.sword_state = _player.SwordState.DRAWN
	await _frames(1)

	# --- 窗口內：命中無效 -------------------------------------------------
	check("no i-frames while free", not _player.in_dodge_invuln())
	await _roll_until(func() -> bool: return _player.action_state == _player.ActionState.DODGING, 30)
	check("roll entered DODGING", _player.action_state == _player.ActionState.DODGING)
	# 窗口預設從 5% 進度才開（起翻那幾毫秒不給無敵），所以等幾幀再問。
	print("[DODGE] INFO roll duration = %.3f s" % _player._roll_duration)
	await _frames(4)
	check("i-frames open inside the roll", _player.in_dodge_invuln())
	var res: Dictionary = _player.take_hit(_hit())
	check("a hit inside the window is dodged", String(res.get("result", "")) == "dodge")
	check("a dodge costs no health", is_equal_approx(_player.posture.health, 100.0))
	check("a dodge costs no posture", is_equal_approx(_player.posture.posture, 0.0))
	check("a dodge does not punish the attacker", is_equal_approx(float(res.get("attacker_posture", -1.0)), 0.0))

	# --- 翻滾結束 ---------------------------------------------------------
	await _roll_until(func() -> bool: return _player.action_state == _player.ActionState.FREE, 400)
	check("roll returns to FREE", _player.action_state == _player.ActionState.FREE)
	check("i-frames close after the roll", not _player.in_dodge_invuln())

	# --- 端點 0 / 0：無敵幀全關 -------------------------------------------
	_player.dodge_invuln_start = 0.0
	_player.dodge_invuln_end = 0.0
	await _roll_until(func() -> bool: return _player.action_state == _player.ActionState.DODGING, 30)
	check("endpoint 0/0 closes the window from the first frame", not _player.in_dodge_invuln())
	_player.posture.heal_full()
	var res2: Dictionary = _player.take_hit(_hit())
	check("endpoint 0/0 lets the hit through", String(res2.get("result", "")) == "hit")
	check("endpoint 0/0 deals damage", _player.posture.health < 100.0)
	await _roll_until(func() -> bool: return _player.action_state == _player.ActionState.FREE, 400)

	# --- 端點 0 / 1：全程無敵 ---------------------------------------------
	_player.dodge_invuln_start = 0.0
	_player.dodge_invuln_end = 1.0
	_player.posture.heal_full()
	await _roll_until(func() -> bool: return _player.action_state == _player.ActionState.DODGING, 30)
	check("endpoint 0/1 opens the window at t=0", _player.in_dodge_invuln())
	var last_res := "dodge"
	# 一路打到翻滾結束前：全程都必須是 dodge。
	while _player.action_state == _player.ActionState.DODGING:
		last_res = String(_player.take_hit(_hit()).get("result", ""))
		if last_res != "dodge":
			break
		await physics_frame
	check("endpoint 0/1 dodges for the whole roll", last_res == "dodge")
	check("endpoint 0/1 keeps full health", is_equal_approx(_player.posture.health, 100.0))

	print("[DODGE] failures=%d" % failures)
	_player.free()
	quit(failures)