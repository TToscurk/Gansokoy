extends SceneTree
## Regression: 受擊回饋（位移＋硬直＋鏡頭震動）—— 緣一沒有受擊動作素材，
## 使用者 2026-09-16 裁定先用程式演出頂著，這個工具就是那件演出的量測。
##
##   Godot --headless --path godot --script tools/verify_hit_feedback.gd
##
## 量的是「玩家能不能分辨三種結果」：彈刀幾乎不退、格擋小退、被打到退得遠
## 且有一段不能動的時間；而且硬直**不得**動到 input_locked（那是對話／過場的介面）。

var failures := 0
var _player: Node = null
var _cam: Camera3D = null


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[HITFB] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


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


## 送出一次命中並量測：總位移、硬直長度、是否動到 input_locked。
func _measure(hit: Dictionary) -> Dictionary:
	_player.posture.heal_full()
	_player.velocity = Vector3.ZERO
	await _frames(2)
	var before: Vector3 = _player.global_position
	var res: Dictionary = _player.take_hit(hit)
	# 取「命中之後」的硬直 —— 取之前永遠是 0，會把測試寫成永真/永假。
	var stun_at_hit: float = _player._hitstun_left
	var locked: bool = _player.input_locked
	var shaking: bool = _player.get_node("HitFeedback").is_shaking()
	var n := 0
	while n < 300 and (_player._knockback_left > 0.0 or _player._hitstun_left > 0.0):
		await physics_frame
		await process_frame
		n += 1
	await _frames(2)
	var moved := Vector2(_player.global_position.x - before.x, _player.global_position.z - before.z).length()
	return {
		"result": String(res.get("result", "")),
		"moved": moved,
		"stun_before": stun_at_hit,
		"stun_after": _player._hitstun_left,
		"locked": locked,
		"shaking": shaking,
		"frames": n,
	}


func _report(tag: String, m: Dictionary) -> void:
	print("[HITFB] INFO %-8s result=%-7s moved=%.3f m stun_before=%.3f stun_after=%.3f frames=%d" % [
		tag, m["result"], m["moved"], m["stun_before"], m["stun_after"], m["frames"]])


func _run() -> void:
	_make_floor()
	var scene: PackedScene = load("res://characters/yoriichi/player_yoriichi.tscn")
	_player = scene.instantiate()
	root.add_child(_player)
	_player.global_position = Vector3(0, 0.3, 0)
	await _frames(12)
	check("player stands on the floor", _player.is_on_floor())
	_player.sword_state = _player.SwordState.DRAWN
	_cam = _player.get_node("Pivot/SpringArm3D/Camera3D")
	check("feedback node exists", _player.get_node_or_null("HitFeedback") != null)
	check("feedback found the camera", _cam != null and _player.get_node("HitFeedback")._cam == _cam)
	await _frames(1)

	# --- 未防禦：退得遠、有硬直、不鎖輸入 ---------------------------------
	var m_hit: Dictionary = await _measure(_hit())
	_report("unguard", m_hit)
	check("an unguarded hit reports hit", m_hit["result"] == "hit")
	check("an unguarded hit staggers", float(m_hit["stun_before"]) > 0.0)
	check("the stagger runs out", is_zero_approx(float(m_hit["stun_after"])))
	check("an unguarded hit pushes the body back", absf(float(m_hit["moved"]) - float(_player.hit_knockback)) < float(_player.hit_knockback) * 0.3)
	check("the hit does not lock input", m_hit["locked"] == false)
	check("the hit shakes the camera", m_hit["shaking"] == true)

	# 鏡頭一定要回得到 0，否則使用者在編輯器拉的鏡位會被永久偏移。
	await _frames(int(_player.hit_shake_time * 60.0) + 8)
	check("the camera offset returns to zero", is_zero_approx(_cam.h_offset) and is_zero_approx(_cam.v_offset))

	# --- 格擋：小退、無硬直 -----------------------------------------------
	_player.begin_guard()
	for i in 40:
		await physics_frame
		await process_frame
	var m_block: Dictionary = await _measure(_hit())
	_report("block", m_block)
	check("a late guard reports block", m_block["result"] == "block")
	check("a block does not stagger", is_zero_approx(float(m_block["stun_before"])))
	check("a block pushes back less than a hit", float(m_block["moved"]) < float(m_hit["moved"]))
	check("a block still moves the body", float(m_block["moved"]) > 0.1)
	_player.end_guard()

	# --- 彈刀：幾乎不退、鏡頭只輕震 ---------------------------------------
	_player.begin_guard()
	await _frames(1)
	var m_defl: Dictionary = await _measure(_hit())
	_report("deflect", m_defl)
	check("a fresh guard reports deflect", m_defl["result"] == "deflect")
	check("a deflect barely moves the body", float(m_defl["moved"]) < float(m_block["moved"]))
	_player.end_guard()

	# --- 端點：位移 0、硬直 0、震動 0 -------------------------------------
	_player.hit_knockback = 0.0
	_player.hit_stun_time = 0.0
	_player.hit_shake_strength = 0.0
	var m_zero: Dictionary = await _measure(_hit())
	_report("endpoint0", m_zero)
	check("knockback 0 means the body does not move", float(m_zero["moved"]) < 0.05)
	check("hitstun 0 means no stagger", is_zero_approx(float(m_zero["stun_before"])))
	check("shake 0 means the camera does not shake", m_zero["shaking"] == false)

	print("[HITFB] failures=%d" % failures)
	_player.free()
	quit(failures)