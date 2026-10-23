extends SceneTree
## 反應動畫組接線驗證：架勢／格擋／彈刀／受擊／軀幹爆／死亡。
##
##   godot --headless --path godot -s tools/verify_react_anims.gd
##
## 量的是「動畫真的在對的層、對的時間播」：AnimationTree 的 upper/full OneShot
## 有沒有 active、Transition 目前是哪個輸入、持續架勢有沒有掉回 loco、
## 死亡後 Tree 有沒有關掉並凍在 Dead 末幀。素材本身的腳底／漂移在 Blender 端量過。

var failures := 0
var _player: Node = null
var _tree: AnimationTree = null
var _anim: AnimationPlayer = null


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print("[REACT] %s %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])
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


func _hit(dmg := 20.0, pdmg := 12.0) -> Dictionary:
	return {"damage": dmg, "posture_damage": pdmg, "hit_dir": Vector3(0, 0, -1), "hit_pos": Vector3(0, 1, 0)}


func _upper_active() -> bool:
	return bool(_tree.get("parameters/upper/active"))


func _full_active() -> bool:
	return bool(_tree.get("parameters/full/active"))


func _upper_sel() -> String:
	return String(_tree.get("parameters/upper_sel/current_state"))


func _full_sel() -> String:
	return String(_tree.get("parameters/full_sel/current_state"))


func _run() -> void:
	_make_floor()
	var scene: PackedScene = load("res://characters/yoriichi/player_yoriichi.tscn")
	_player = scene.instantiate()
	root.add_child(_player)
	_player.global_position = Vector3(0, 0.3, 0)
	await _frames(12)
	check("player stands on the floor", _player.is_on_floor())
	_tree = _player.get_node("Tree")
	_anim = _player.find_children("*", "AnimationPlayer", true, false)[0]
	_player.sword_state = _player.SwordState.DRAWN

	# --- 資源註冊 ---------------------------------------------------------
	for n in ["Guard_Hold", "Block_Impact", "Deflect", "Hit_React", "Stagger", "Dead"]:
		check("AnimationPlayer has " + n, _anim.has_animation(n))
	var lens := {"Guard_Hold": 0.5, "Block_Impact": 0.3333, "Deflect": 0.4167, "Hit_React": 0.4167, "Stagger": 2.0, "Dead": 2.9667}
	for n in lens:
		if _anim.has_animation(n):
			check("%s length %.3f" % [n, lens[n]], absf(_anim.get_animation(n).length - lens[n]) < 0.01, "%.4f" % _anim.get_animation(n).length)
	check("Dead does not loop", _anim.get_animation("Dead").loop_mode == Animation.LOOP_NONE)
	# Hips 根骨方向：每支自製 clip 的 f0 = Idle_Grounded f0。GLB→FBX 要乘 X+90°；
	# 2026-09-16 前所有 clip 都漏了 → 角色躺平（Stagger 腳趾離地 0.84 m）。
	var q_idle := _hips_q0(_anim.get_animation("Idle_Grounded"))
	for n in ["Guard_Hold", "Block_Impact", "Deflect", "Hit_React", "Stagger"]:
		if _anim.has_animation(n):
			var ang := rad_to_deg(q_idle.angle_to(_hips_q0(_anim.get_animation(n))))
			check("%s Hips f0 = Idle (root bone corrected)" % n, ang < 5.0, "%.1f deg" % ang)

	# --- 架勢：進場 → 循環持續，不掉回 loco ---------------------------------
	_player.begin_guard()
	await _frames(2)
	check("guard fires the upper one-shot", _upper_active())
	check("guard enter clip selected", _upper_sel() == "guard", _upper_sel())
	await _frames(60)   # 1 s：進場 0.31 s 早就播完
	check("guard still held after 1 s (hold loop)", _upper_active())
	check("guard hold loop selected", _upper_sel() == "guard_hold", _upper_sel())

	# --- 格擋（晚舉盾）：block clip → 回 hold ------------------------------
	var r_block: Dictionary = _player.take_hit(_hit())
	check("late guard reports block", String(r_block.result) == "block")
	await _frames(1)
	check("block clip selected", _upper_sel() == "block", _upper_sel())
	check("block stays on upper layer (no full override)", not _full_active())
	await _frames(40)
	check("after block returns to guard hold", _upper_active() and _upper_sel() == "guard_hold", _upper_sel())
	_player.end_guard()
	await _frames(20)
	check("release guard fades upper out", not _upper_active())

	# --- 彈刀（剛舉盾）：deflect clip ------------------------------------
	_player.posture.heal_full()
	_player.begin_guard()
	await _frames(1)
	var r_defl: Dictionary = _player.take_hit(_hit())
	check("fresh guard reports deflect", String(r_defl.result) == "deflect")
	await _frames(1)
	check("deflect clip selected", _upper_sel() == "deflect", _upper_sel())
	await _frames(40)
	check("after deflect returns to guard hold", _upper_active() and _upper_sel() == "guard_hold", _upper_sel())
	_player.end_guard()
	await _frames(20)

	# --- 受擊：full 層 hit，然後淡回 ------------------------------------------
	_player.posture.heal_full()
	var r_hit: Dictionary = _player.take_hit(_hit())
	check("unguarded reports hit", String(r_hit.result) == "hit")
	await _frames(1)
	check("hit fires full one-shot", _full_active())
	check("hit clip selected", _full_sel() == "hit", _full_sel())
	await _frames(50)
	check("hit one-shot ends", not _full_active())

	# --- 軀幹爆：stagger 長度 = break_time ----------------------------------
	_player.posture.heal_full()
	var bt: float = _player.posture.break_time
	while not _player.posture.is_broken() and _player.posture.health > 5.0:
		_player.take_hit(_hit(1.0, 40.0))
		await _frames(1)
	check("posture breaks", _player.posture.is_broken())
	# 注意兩件事：(1) transition_request 是唯寫屬性，讀回來是空字串，只能驗 current_state；
	# (2) current_state 要等 xfade（combo_section_blend 0.035 s）走完才切過去。
	await _frames(5)
	var req: String = _full_sel()
	# 2026-09-23：軀幹爆改成方向性（stagger → Stagger_Front/Back/Left/Right，接線驗收在
	# tools/verify_stagger_directional.gd）。契約不變的部分照驗：一定是 full 層 one-shot，
	# 而且「被選中那一支的長度 ÷ 播放倍率」必須等於 break_time（不再寫死 2.0 s clip）。
	var stagger_keys := {
		"stagger": "Stagger", "stagger_front": "Stagger_Front", "stagger_back": "Stagger_Back",
		"stagger_left": "Stagger_Left", "stagger_right": "Stagger_Right",
	}
	check("stagger fires full one-shot", _full_active() and stagger_keys.has(req), req)
	var ts: float = float(_tree.get("parameters/ts_full/scale"))
	var clip_name: String = stagger_keys.get(req, "Stagger")
	var clip_len: float = _anim.get_animation(clip_name).length
	check("stagger scaled to break_time", absf(clip_len / ts - bt) < 0.05,
		"scale %.3f clip %.2f(%s) break %.2f" % [ts, clip_len, clip_name, bt])
	await _frames(int(bt * 60.0) + 30)
	check("stagger ends with break", not _full_active())

	# --- 死亡：Dead 播完、Tree 關、停在末幀 ---------------------------------
	_player.posture.heal_full()
	await _frames(5)
	_player.take_hit(_hit(10000.0, 0.0))
	await _frames(2)
	check("death reported", _player.posture.is_dead())
	check("death fires Dead on full layer", _full_active() and _full_sel() == "dead", _full_sel())
	check("death locks input", _player.input_locked)
	await _frames(int(2.9667 * 60.0) + 20)
	check("after Dead the tree is disabled", not _tree.active)
	# seek 到 length 之後 player 視為播完，current_animation 清空；定格證據是
	# assigned_animation + 位置停在末幀（下一項）＋ speed_scale 0。
	check("AnimationPlayer frozen on Dead", _anim.assigned_animation.ends_with("Dead") and is_zero_approx(_anim.speed_scale), "assigned='%s' speed=%.1f" % [_anim.assigned_animation, _anim.speed_scale])
	check("frozen at the last frame", absf(_anim.current_animation_position - 2.9667) < 0.02, "%.3f" % _anim.current_animation_position)

	print("[REACT] %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _hips_q0(a: Animation) -> Quaternion:
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D and String(a.track_get_path(t)).ends_with(":Hips"):
			return a.track_get_key_value(t, 0)
	return Quaternion.IDENTITY
