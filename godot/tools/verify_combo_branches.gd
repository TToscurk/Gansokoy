extends SceneTree
## 左右鍵互搭連段 ＋ 日之呼吸缺件四型：接線驗證。
##
## 執行：
##   godot --headless --path godot -s res://tools/verify_combo_branches.gd
##
## 驗的是「按鍵 → 狀態 → 動畫 → 演出」整條路，不是只看型表：
##   1. 四支自製 .res 載得進來、Hips 水平凍結、AnimationPlayer 註冊得到
##   2. LMB 段1 取消窗口內 RMB → 陸型 飛輪陽炎（不扣呼吸、起冷卻、前衝）
##   3. LMB 段2 → 伍型；段3 → 拾貳型（含第二刀 rehit 清單重置）
##   4. RMB 聚力單斬中 LMB → 拾壹型 幻日虹（起手後撤）
##   5. 疾跑中 RMB → 捌型 陽華突
##   6. 型的取消窗口後 LMB → 回連段段1；RMB → 聚力單斬
##   7. 冷卻中的分支被擋（不切、不留排隊殘留）
##   8. 起手火光／音效真的產生（root 底下多了粒子＋燈；audio events_played 增加）
##   9. 分支開關全設 0 → RMB 只是普通排隊，行為與舊版一致

const SunBreathing = preload("res://characters/yoriichi/sun_breathing.gd")
const RES := {
	5: "res://characters/yoriichi/animations/yoriichi_form05_turn.res",
	6: "res://characters/yoriichi/animations/yoriichi_form06_wheel.res",
	11: "res://characters/yoriichi/animations/yoriichi_form11_halo.res",
	12: "res://characters/yoriichi/animations/yoriichi_form12_dance.res",
}

var _pass := 0
var _fail := 0
var _player: CharacterBody3D


func check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [OK] ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", label, ("  " + detail) if detail != "" else "")


func _init() -> void:
	_run.call_deferred()


func _make_floor() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	body.add_child(col)
	root.add_child(body)


func _wait(n: int) -> void:
	for i in n:
		await physics_frame


## 等到攻擊進度 ≥ p（用角色自己的時鐘，不猜幀數）。
func _wait_progress(p: float, max_frames := 120) -> void:
	for i in max_frames:
		if _player.action_state != 1:
			return
		if _player._attack_progress() >= p:
			return
		await physics_frame


func _reset() -> void:
	if _player.action_state != 0:
		_player._finish_attack()
	_player._form_cooldowns.clear()
	_player.sun_breath_gauge = 0.0
	_player.velocity = Vector3.ZERO
	await _wait(3)


func _count_vfx() -> int:
	var n := 0
	for c in root.get_children():
		if c is GPUParticles3D or c is OmniLight3D:
			n += 1
	return n


func _run() -> void:
	print("=== 左右鍵互搭 ＋ 缺件四型 ===")
	_test_resources()
	_make_floor()
	var ps := load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene
	_player = ps.instantiate() as CharacterBody3D
	root.add_child(_player)
	await _wait(10)
	check("站在地板上", _player.is_on_floor())

	var ap: AnimationPlayer = _player.find_children("*", "AnimationPlayer", true, false)[0]
	for id in RES:
		var nm: String = SunBreathing.FORMS[id].anim
		check("AnimationPlayer 註冊 %s（型 %d）" % [nm, id], ap.has_animation(nm))
	check("型表：5/6/11/12 全 READY", [5, 6, 11, 12].all(func(i): return SunBreathing.FORMS[i].status == "READY"))
	check("missing_forms 為空", SunBreathing.missing_forms().is_empty(), str(SunBreathing.missing_forms()))

	_player.request_draw()
	await _wait(70)
	check("拔刀完成", _player.sword_state == 2)
	var audio: Node = _player.get_node("CharacterAudio")

	# --- 2. 段1 → RMB → 陸型 ---
	print("-- 段1 RMB → 陸型 飛輪陽炎 --")
	await _reset()
	_player.request_primary_attack()
	await physics_frame
	check("段1 進行中", _player.combo_stage == 1 and _player.action_state == 1)
	_player.request_heavy_cut()   # 窗口前：排隊
	check("窗口前 RMB 先排隊（_branch_queued=6）", _player._branch_queued == 6 and _player.active_form == 0)
	var vfx_before := _count_vfx()
	var snd_before: int = audio.events_played
	# 等到真的切型（不是等進度：切型後 _attack_progress 歸零，會多等一段）
	var p6 := Vector3.ZERO
	for i in 120:
		await physics_frame
		if _player.active_form == 6:
			p6 = _player.global_position
			break
	check("到取消窗口自動切到陸型", _player.active_form == 6, "active_form=%d" % _player.active_form)
	check("動畫是 Attack_Form06_Wheel（full 層）", _player._active_attack_name == "Attack_Form06_Wheel" and _player._attack_layer == "full")
	check("分支不扣呼吸（gauge 0 → 0）", is_zero_approx(_player.sun_breath_gauge))
	check("冷卻起算（2.0 s）", _player.form_cooldown_left(6) > 1.5, "%.2f" % _player.form_cooldown_left(6))
	await _wait(20)   # 0.33 s > form_impulse_time
	var d6 := Vector2(_player.global_position.x - p6.x, _player.global_position.z - p6.z).length()
	check("起手前衝 impulse 5 m/s × 0.22 s 衰減 ≈ 0.55 m", d6 > 0.35 and d6 < 1.0, "%.2f m" % d6)
	check("起手火光生成（root 粒子/燈 +）", _count_vfx() > vfx_before, "%d → %d" % [vfx_before, _count_vfx()])
	check("型音效有播", audio.events_played > snd_before, "%d → %d" % [snd_before, audio.events_played])
	var f6_life: float = float(load("res://characters/yoriichi/sun_breathing.gd").FORMS[6].trail.lifetime)
	check("刀光套用 FORMS[6].trail.lifetime", is_equal_approx(_player._sword_trail.lifetime, f6_life), "%.2f vs %.2f" % [_player._sword_trail.lifetime, f6_life])
	await _wait(80)
	check("型播完回 FREE", _player.action_state == 0)
	check("刀光還原", is_equal_approx(_player._sword_trail.lifetime, _player._trail_default_lifetime))

	# --- 3. 段2 → RMB → 伍型；段3 → RMB → 拾貳型 ---
	print("-- 段2 RMB → 伍型 / 段3 RMB → 拾貳型 --")
	await _reset()
	_player.request_primary_attack()
	await physics_frame
	_player.request_primary_attack()          # 排段2
	await _wait_progress(_player.combo_cancel_start)
	await _wait(2)
	check("進段2", _player.combo_stage == 2, "stage=%d" % _player.combo_stage)
	_player.request_heavy_cut()
	await _wait_progress(_player.combo_cancel_start)
	await physics_frame
	check("段2 RMB → 伍型 斜陽轉身", _player.active_form == 5, "active_form=%d" % _player.active_form)
	await _wait(80)
	await _reset()
	_player.request_primary_attack()
	await physics_frame
	_player.request_primary_attack()
	await _wait_progress(_player.combo_cancel_start)
	await _wait(2)
	_player.request_primary_attack()
	await _wait_progress(_player.combo_cancel_start)
	await _wait(2)
	check("進段3", _player.combo_stage == 3, "stage=%d" % _player.combo_stage)
	_player.request_heavy_cut()
	await _wait_progress(_player.combo_cancel_start)
	await physics_frame
	check("段3 RMB → 拾貳型 炎舞", _player.active_form == 12, "active_form=%d" % _player.active_form)
	_player._hit_targets_this_swing[_player] = true   # 假裝第一刀已命中
	await _wait_progress(0.56)
	await physics_frame
	check("炎舞 rehit 0.55：命中清單重置（第二刀可再判定）",
		_player.active_form == 12 and not _player._hit_targets_this_swing.has(_player))
	await _wait(80)

	# --- 4. 聚力單斬中 LMB → 拾壹型 ---
	print("-- RMB 聚力單斬中 LMB → 拾壹型 幻日虹 --")
	await _reset()
	_player.request_heavy_cut()
	await physics_frame
	check("聚力單斬進行中", _player._active_attack_name == "Heavy_Cut")
	_player.request_primary_attack()
	check("窗口前排隊 11", _player._branch_queued == 11)
	var p11 := Vector3.ZERO
	for i in 120:
		await physics_frame
		if _player.active_form == 11:
			p11 = _player.global_position
			break
	check("切到拾壹型", _player.active_form == 11, "active_form=%d" % _player.active_form)
	var fwd: Vector3 = _player._visual.global_transform.basis.z
	await _wait(20)
	var along: float = (_player.global_position - p11).dot(fwd.normalized())
	check("起手後撤 1.5 m/s（沿面朝反向 ≈ -0.17 m）", along < -0.08 and along > -0.5, "%.2f m" % along)
	await _wait(80)

	# --- 5. 疾跑中 RMB → 捌型 ---
	print("-- 疾跑 RMB → 捌型 陽華突 --")
	await _reset()
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _wait(20)
	var run_v := Vector2(_player.velocity.x, _player.velocity.z).length()
	check("正在疾跑", run_v > _player.speed + 0.5, "%.2f m/s" % run_v)
	_player.request_heavy_cut()
	await physics_frame
	check("疾跑 RMB → 捌型", _player.active_form == 8, "active_form=%d" % _player.active_form)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var p0 := _player.global_position
	await _wait(20)   # 0.33 s > form_impulse_time 0.22
	var dashed := Vector2(_player.global_position.x - p0.x, _player.global_position.z - p0.z).length()
	check("捌型起手衝刺真的位移（6 m/s × 0.22 s 線性衰減 ≈ 0.66 m）", dashed > 0.45 and dashed < 1.2, "%.2f m" % dashed)
	await _wait(70)

	# --- 6. 型中 LMB/RMB 後續 ---
	print("-- 型的取消窗口後續 --")
	await _reset()
	_player._branch_to_form(6)
	await physics_frame
	check("陸型進行中", _player.active_form == 6)
	_player.request_primary_attack()
	check("窗口前 LMB 排隊 light", _player._form_followup == "light")
	await _wait_progress(float(SunBreathing.FORMS[6].cancel.x))
	await _wait(2)
	check("進窗口 → 回連段段1", _player.active_form == 0 and _player.combo_stage == 1, "form=%d stage=%d" % [_player.active_form, _player.combo_stage])
	await _wait(60)
	await _reset()
	_player._branch_to_form(5)
	await physics_frame
	await _wait_progress(float(SunBreathing.FORMS[5].cancel.x))
	_player.request_heavy_cut()
	await _wait(2)
	check("窗口內 RMB → 聚力單斬", _player._active_attack_name == "Heavy_Cut", _player._active_attack_name)
	await _wait(60)

	# --- 7. 冷卻中的分支被擋 ---
	print("-- 冷卻 --")
	await _reset()
	_player._form_cooldowns[6] = 5.0
	_player.request_primary_attack()
	await physics_frame
	_player.request_heavy_cut()
	await _wait_progress(_player.combo_cancel_start)
	await _wait(2)
	check("陸型冷卻中：RMB 不切型", _player.active_form != 6)
	check("排隊已清空", _player._branch_queued == 0)
	await _wait(60)

	# --- 9. 分支關閉 = 舊行為 ---
	print("-- 分支關閉 --")
	await _reset()
	_player.branch_after_stage1 = 0
	_player.request_primary_attack()
	await physics_frame
	_player.request_heavy_cut()
	await _wait_progress(_player.combo_cancel_start)
	await _wait(2)
	check("branch_after_stage1=0：RMB 不接型", _player.active_form == 0)
	_player.branch_after_stage1 = 6
	await _wait(60)

	# --- execute_form 正常路徑仍要呼吸與熟練度 ---
	await _reset()
	_player.sun_mastery = 0
	check("正常 execute_form(5) 熟練度不足被擋", not _player.execute_form(5))
	_player.sun_mastery = 4
	_player.sun_breath_gauge = 100.0
	check("正常 execute_form(12) 成功", _player.execute_form(12))
	check("正常路徑扣呼吸 100 → 80", is_equal_approx(_player.sun_breath_gauge, 80.0), "%.1f" % _player.sun_breath_gauge)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _test_resources() -> void:
	print("-- .res 本體 --")
	for id in RES:
		var anim: Animation = load(RES[id])
		check("型 %d .res 載入" % id, anim != null)
		if anim == null:
			continue
		var rot := 0
		var pos: Array[String] = []
		var dx := 0.0
		var dy := 0.0
		for t in anim.get_track_count():
			var p := String(anim.track_get_path(t))
			if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				rot += 1
			elif anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				pos.append(p.get_slice(":", 1))
				var xs: Array[float] = []
				var ys: Array[float] = []
				for k in anim.track_get_key_count(t):
					var v: Vector3 = anim.track_get_key_value(t, k)
					xs.append(v.x); ys.append(v.y)
				dx = xs.max() - xs.min()
				dy = ys.max() - ys.min()
		check("型 %d 旋轉軌 22 骨、位置軌只有 Hips" % id, rot == 22 and pos == ["Hips"], "rot=%d pos=%s" % [rot, str(pos)])
		check("型 %d Hips 水平凍結" % id, is_zero_approx(dx) and is_zero_approx(dy), "dx=%.5f dy=%.5f" % [dx, dy])
		check("型 %d 長度 0.5~1.0 s" % id, anim.length > 0.5 and anim.length < 1.0, "%.3f s" % anim.length)
		# Hips 根骨方向：f0 必須 = Idle_Grounded f0（Blender GLB → FBX 骨架要乘 X+90°；
		# 漏掉會整個人躺平 —— 2026-09-16 實測所有反應 clip 都躺過）。
		var idle: Animation = load("res://characters/yoriichi/animations/yoriichi_idle_grounded.res")
		var q_idle := _hips_q(idle)
		var q_form := _hips_q(anim)
		var ang := rad_to_deg(q_idle.angle_to(q_form))
		check("型 %d Hips f0 方向 = Idle（根骨已校正）" % id, ang < 5.0, "差 %.1f°" % ang)


func _hips_q(a: Animation) -> Quaternion:
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D and String(a.track_get_path(t)).ends_with(":Hips"):
			return a.track_get_key_value(t, 0)
	return Quaternion.IDENTITY
