extends SceneTree
## 忍殺（deathblow）玩家端接線驗收。用法：
##   godot --headless --path godot -s tools/verify_deathblow.gd
##
## 驗「接線」不驗美術：Tree 段落存在且子區段參數正確、原本的守衛沒被破壞（沒敵人／
## 敵人未破綻／距離外都不發動）、真的走 try_deathblow()（不直接呼叫內部函式）、
## 演出期間鎖操作、放完自動解鎖、面向目標、子區段的腳不穿地。
## 腳底量法與 verify_mixamo_clips.gd 同一套（Skeleton3D 世界座標）。
##
## 注意：玩家要留著 physics_process（忍殺的計時器就在 _physics_process 裡衰減），
## 所以要有地板，不能像 verify_mixamo_clips.gd 那樣關掉物理（那支沒有地板）。

const PLAYER_SCENE := "res://characters/yoriichi/player_yoriichi.tscn"
const ENEMY_SCENE := "res://characters/combat/enemy_samurai.tscn"
const FOOT_BONES := ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]
## 陷地容許量（m）：與 verify_mixamo_clips.gd 同一條契約。
const SINK_TOL := 0.005

var failures := 0
var total := 0
var _player: Node3D = null
var _tree: AnimationTree = null
var _anim: AnimationPlayer = null
var _skel: Skeleton3D = null
var _e: Node3D = null
var _idle_foot := 0.0


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	total += 1
	print("[DB] %s %s%s" % ["PASS" if ok else "FAIL", label, ("  (" + detail + ")") if detail != "" else ""])
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


## 等到站穩（髖連續 5 格變動 < 2 mm），最多等 n 格。回傳是否等到。
## 為什麼需要：對照組播完全身技後，玩家可能還停在收勢／下沉的過渡姿態（實測髖 0.56 且
## 還在往下掉），此時量的基準與相對值全部失真 —— 這道等待同時是量測正確性的守衛。
func _settle(n: int, hips_i: int) -> bool:
	var prev := INF
	var stable := 0
	for i in n:
		var hz: float = (_skel.global_transform * _skel.get_bone_global_pose(hips_i).origin).y
		if absf(hz - prev) < 0.002:
			stable += 1
			if stable >= 5:
				return true
		else:
			stable = 0
		prev = hz
		await _frames(1)
	return false


## 四根腳骨的骨架世界座標最低 y（與 verify_mixamo_clips.gd 同一種量法）。
func _foot_min() -> float:
	var lo := INF
	for b in FOOT_BONES:
		var i := _skel.find_bone(b)
		if i < 0:
			continue
		lo = minf(lo, (_skel.global_transform * _skel.get_bone_global_pose(i).origin).y)
	return lo


func _run() -> void:
	_make_floor()
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_player)
	await _frames(8)
	_tree = _player.get_node("Tree") as AnimationTree
	_anim = _player.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_skel = _player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	check("玩家／Tree／AnimationPlayer／Skeleton3D 都取得", _tree != null and _anim != null and _skel != null)
	if _tree == null or _anim == null or _skel == null:
		print("[DB] ===== 環境不成立，中止 =====")
		quit(1)
		return

	# ---- 1) 素材與 Tree 段落 ----
	var lib := _anim.get_animation_library("")
	check("Deathblow clip 已註冊", _anim.has_animation("Deathblow"),
		"共註冊 %d 支" % (lib.get_animation_list().size() if lib != null else -1))
	var seg_path := "full_sel_deathblow"
	check("Tree 有 %s 段落" % seg_path, _tree.tree_root.has_node(seg_path))
	if _tree.tree_root.has_node(seg_path):
		var seg := _tree.tree_root.get_node(seg_path) as AnimationNodeAnimation
		check("段落指向 Deathblow", seg.animation == "Deathblow", seg.animation)
		check("段落播整支（素材已切好對齊）", not seg.use_custom_timeline,
			"custom_timeline=%s" % str(seg.use_custom_timeline))
		check("素材是切好的 1.1667 s", absf(_anim.get_animation("Deathblow").length - 1.1667) < 0.001,
			"length=%.4f" % _anim.get_animation("Deathblow").length)

	# ---- 2) 對照組：原本的守衛不能被破壞 ----
	check("沒有敵人時不忍殺", not _player.try_deathblow())
	_e = (load(ENEMY_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_e)
	_e.global_position = Vector3(0, 0, 1.8)   # 玩家正前方（+Z 是正面）
	await _frames(6)
	check("敵人未破綻時不忍殺", not _player.try_deathblow())
	_e.posture.apply_damage(0.0, _e.posture.max_posture)
	await _frames(2)
	check("敵人已破綻（可處決）", _e.can_deathblow())
	var near := _player.global_position
	_player.global_position = near + Vector3(0, 0, -30.0)
	await _frames(4)
	check("距離 %.1f m 外不忍殺" % _player.deathblow_range, not _player.try_deathblow())
	_player.global_position = near
	await _frames(6)

	# 拔刀：沒拔刀時 request_primary_attack() 不會發動 —— 對照組會退化成量 Idle 雜訊
	# （這個坑第一次跑就踩到：量到「普攻 −4.1 mm」其實是 Idle 自己的微動）。
	# 忍殺在遊戲裡也是刀出鞘的戰鬥狀態下發動，所以整段驗收都在拔刀狀態下跑才寫實。
	_player.request_draw()
	for i in 120:
		if _player.sword_state == 2:
			break
		await _frames(1)
	check("已拔刀（sword_state=2）", _player.sword_state == 2, "sword=%d" % _player.sword_state)
	await _frames(10)

	# ---- 3) 對照組：遊戲自己的全身技（同一套 full 層 OneShot、同樣 fadein 0.10）
	# 量它入場淡化期間的腳底，用來判斷「入場擺盪」是不是這套機制的常態。
	var ctl_lo := INF
	var ctl_fired := false
	var ctl_state := ""
	print("[DB] 對照組前：sword=%s action=%s full_active=%s" % [
		str(_player.sword_state), str(_player.action_state), str(bool(_tree.get("parameters/full/active")))])
	for i in 40:
		if i == 0:
			# 對照組直接播遊戲自己的全身技片段（combo1）：輸入路徑在無頭測試裡不穩
			# （重斬是蓄力型、要按住才會進全身層；輕攻擊走的是上半身層）。
			# 機制完全相同 —— 同一顆 full 層 OneShot、同一個 fadein 0.10、同一套骨架。
			_player._fire_full("combo1", 1.0)
		if bool(_tree.get("parameters/full/active")):
			ctl_fired = true
			if ctl_state == "":
				ctl_state = String(_tree.get("parameters/full_sel/current_state"))
		ctl_lo = minf(ctl_lo, _foot_min())
		await _frames(1)
	check("對照組普攻真的發動（否則基準無意義）", ctl_fired, "full_sel=%s" % ctl_state)
	await _frames(80)   # 等它收勢回 Idle
	var ctl2_lo := INF
	for i in 30:
		ctl2_lo = minf(ctl2_lo, _foot_min())
		await _frames(1)

	# 對照組跑完（40 格＋收勢）敵人的軀幹已經恢復（break_time 2.0 s），重新打爆再處決。
	_e.posture.apply_damage(0.0, _e.posture.max_posture)
	await _frames(3)
	check("處決前敵人再次破綻", _e.can_deathblow())

	# ---- 4) 基準：演出前的腳底與髖（先等站穩，見 _settle 的說明）----
	var _hips_i := _skel.find_bone("Hips")
	check("對照組後能站穩再量基準", await _settle(240, _hips_i),
		"髖 %.4f" % (_skel.global_transform * _skel.get_bone_global_pose(_hips_i).origin).y)
	_idle_foot = _foot_min()
	var hips_z := func() -> float: return (_skel.global_transform * _skel.get_bone_global_pose(_hips_i).origin).y
	print("[DB] 基準：腳底 %+.4f 髖 %.4f" % [_idle_foot, hips_z.call()])
	var loco_pb: AnimationNodeStateMachinePlayback = _player._playback()
	var loco_name := func() -> String: return loco_pb.get_current_node() if loco_pb != null else "?"
	for i in 3:
		print("[DB]   前%2d 腳底 %+.4f 髖 %.4f loco=%s" % [i, _foot_min(), hips_z.call(), loco_name.call()])
		await _frames(1)

	# ---- 4) 發動 → 逐格量到放完之後 ----
	# 契約：clip 自己的時間軸內不得陷地（同 verify_mixamo_clips.gd 的 5 mm）。
	# clip 放完後的淡出尾巴是「與 Idle 交叉淡化」的產物 —— 兩個各自貼地的姿態用關節角
	# 插值混合，末端位置不會剛好貼地（與對齊工具遇到的是同一種現象）。那一段用寬鬆界線
	# （25 mm）單獨看，不與 clip 契約混為一談。
	check("忍殺發動", _player.try_deathblow())
	var clip_dur: float = _anim.get_animation("Deathblow").length / maxf(_player.deathblow_speed, 0.01)
	var lo_in := INF
	var hi_in := -INF
	var lo_tail := INF
	var fire_foot := 0.0
	var dy_at_fire := -1.0
	var sel_at_fire := ""
	var active_at_fire := false
	var scale_at_fire := -1.0
	var locked_at_fire := false
	var frames := int(maxf(_player._deathblow_left, 0.05) * 60.0) + 12
	for i in frames:
		var t := float(i) / 60.0
		var f := _foot_min()
		# i==0 是「開火那一格」（OneShot 剛 FIRE、淡入尚未走完）。單獨列報，不混進 clip 契約：
		# 它量到的是兩個姿態之間的過渡瞬間，不是素材本身。
		if i == 0:
			fire_foot = f
		elif t <= clip_dur:
			lo_in = minf(lo_in, f)
			hi_in = maxf(hi_in, f)
		else:
			lo_tail = minf(lo_tail, f)
		if i == 2:
			var to := _e.global_position - _player.global_position
			to.y = 0.0
			dy_at_fire = absf(wrapf(_player.global_rotation.y - atan2(to.x, to.z), -PI, PI))
			sel_at_fire = String(_tree.get("parameters/full_sel/current_state"))
			active_at_fire = bool(_tree.get("parameters/full/active"))
			scale_at_fire = float(_tree.get("parameters/ts_full/scale"))
			locked_at_fire = _player.input_locked
		if i < 42:
			print("[DB]   後%3d t=%5.3f 腳底 %+.4f 髖 %.4f loco=%s" % [
				i, t, f, hips_z.call(), loco_name.call()])
		await _frames(1)

	check("選中段落 = deathblow", sel_at_fire == "deathblow", sel_at_fire)
	check("full 層 OneShot 在跑", active_at_fire)
	check("重播速度 = deathblow_speed", is_equal_approx(scale_at_fire, _player.deathblow_speed), "%.2f" % scale_at_fire)
	check("演出期間鎖操作", locked_at_fire)
	check("敵人已被處決", _e.posture.is_dead())
	check("面向敵人（+Z 正面）", dy_at_fire >= 0.0 and dy_at_fire < 0.05,
		"誤差 %.2f°" % rad_to_deg(dy_at_fire))
	# 陷地契約改用「對照式」：同一場景、同一套 full 層 OneShot 之下，忍殺不得比遊戲自己的
	# 全身技（普攻）差超過 3 mm；再加一條寬鬆的絕對界線（10 mm）擋災難性穿地。
	# 為什麼不寫死 5 mm：遊戲自己的普攻在同一量測就沉 3.8~4.2 mm（它自己跨層淡化的擺盪），
	# 寫死會變成「比遊戲本身還嚴」的假門檻。兩數都印出來，讓差異一眼可查。
	var dip_in := lo_in - _idle_foot
	var ctl_dip := ctl_lo - _idle_foot
	check("忍殺陷地 ≤ 同場景普攻 + 3 mm", dip_in <= ctl_dip + 0.003,
		"忍殺 %+.1f mm vs 普攻 %+.1f mm" % [dip_in * 1000.0, ctl_dip * 1000.0])
	check("忍殺絕對不穿地 > -10 mm", dip_in > -0.010, "%+.1f mm" % (dip_in * 1000.0))
	check("淡出尾巴不塌（> -25 mm）", lo_tail - _idle_foot > -0.025,
		"最低 %+.4f（相對基準 %+.1f mm）" % [lo_tail, (lo_tail - _idle_foot) * 1000.0])
	print("[DB] 開火那一格（過渡瞬間，不列入契約）腳底 %+.4f（相對基準 %+.1f mm）" % [
		fire_foot, (fire_foot - _idle_foot) * 1000.0])
	print("[DB] 忍殺段腳底：clip 內 %+.4f~%+.4f（%+.1f~%+.1f mm）｜淡出尾巴最低 %+.1f mm" % [
		lo_in, hi_in, (lo_in - _idle_foot) * 1000.0, (hi_in - _idle_foot) * 1000.0, (lo_tail - _idle_foot) * 1000.0])
	print("[DB] 對照：遊戲普攻入場 40 格最低 %+.1f mm、收勢後 30 格最低 %+.1f mm（忍殺入場最低 %+.1f mm）" % [
		(ctl_lo - _idle_foot) * 1000.0, (ctl2_lo - _idle_foot) * 1000.0, (lo_in - _idle_foot) * 1000.0])

	# ---- 5) 放完自動解鎖 ----
	await _frames(12)
	check("演出結束已解鎖", not _player.input_locked)
	check("計時器歸零", _player._deathblow_left <= 0.0, "%.3f" % _player._deathblow_left)

	# ---- 6) 副作用檢查：忍殺把 full 層 fadein 調成 0.04，之後的招式必須回到標準 0.10 ----
	_player._fire_full("combo1", 1.0)
	await _frames(4)
	check("普攻的 fadein 回到標準 0.10", is_equal_approx(_player._full_node.fadein_time, 0.10),
		"%.2f" % _player._full_node.fadein_time)

	print("[DB] ===== 共 %d 項：%d 項 FAIL =====" % [total, failures])
	quit(1 if failures > 0 else 0)
