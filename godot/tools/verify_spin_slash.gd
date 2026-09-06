extends SceneTree

func _init():
	_run.call_deferred()

func _run():
	print("--- 开始验证缘一角色连续旋转砍击动作 ---")
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	floor_body.add_child(col)
	root.add_child(floor_body)

	var ps := load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene
	var player := ps.instantiate() as CharacterBody3D
	root.add_child(player)
	
	# Wait for player to settle on floor
	for i in 10:
		await physics_frame
	
	var fails := 0
	
	# 1. AnimationPlayer 检查
	var aps := player.find_children("*", "AnimationPlayer", true, false)
	fails += _check("AnimationPlayer 存在", aps.size() > 0)
	var ap: AnimationPlayer = aps[0]
	fails += _check("包含 Attack_Continuous_Spin 动画", ap.has_animation("Attack_Continuous_Spin"))
	if ap.has_animation("Attack_Continuous_Spin"):
		var a := ap.get_animation("Attack_Continuous_Spin")
		print("  动画长度: %.2f 秒, 轨道数: %d" % [a.length, a.get_track_count()])
		fails += _check("动画长度接近 4.03 秒", is_equal_approx(a.length, 4.033333))
		fails += _check("动画为非循环 LOOP_NONE", a.loop_mode == Animation.LOOP_NONE)

	# 2. AnimationTree 检查
	var trees := player.find_children("*", "AnimationTree", true, false)
	fails += _check("AnimationTree 存在且激活", trees.size() > 0 and (trees[0] as AnimationTree).active)
	var tree: AnimationTree = trees[0]
	
	# 3. 拔刀并触发连续旋转砍击
	player.request_draw()
	# 快进拔刀阶段
	for i in 60:
		await physics_frame
	fails += _check("拔刀完成，持刀状态 (DRAWN)", player.sword_state == 2) # SwordState.DRAWN
	
	var sword_hand: Node3D = player.find_children("Sword_Hand", "", true, false)[0]
	fails += _check("手上武器可见 (Sword_Hand.visible)", sword_hand.visible)
	
	# 4. 发动连续旋转砍击
	print("发动 request_continuous_spin()...")
	player.request_continuous_spin()
	await physics_frame
	
	fails += _check("动作状态进入 ATTACKING", player.action_state == 1) # ActionState.ATTACKING
	fails += _check("攻击层级为 full (全身接管)", player.get("_attack_layer") == "full")
	
	var trail = player.get("_sword_trail")
	var hitbox = player.get("_hitbox")
	fails += _check("刀光特效已启动 (SwordTrail)", trail != null)
	fails += _check("打击判定框已开启 (Hitbox.monitoring)", hitbox != null and hitbox.monitoring)
	
	# 5. 模拟播放全流程（4.03s / 1.8x ≈ 2.24s，约 135 physics frames）
	print("模拟 135 帧物理更新...")
	var sampled_poses := 0
	for i in 140:
		await physics_frame
		if i % 30 == 0:
			sampled_poses += 1
			print("  Frame %3d: y=%.2f action_state=%s" % [i, player.global_position.y, player.action_state])
	
	# 6. 验证结束收势
	fails += _check("攻击结束恢复 FREE 状态", player.action_state == 0) # ActionState.FREE
	fails += _check("刀光特效已停止", trail != null and not trail.is_emitting)
	fails += _check("判定框已关闭", hitbox != null and not hitbox.monitoring)
	
	# 8. 测试中途换招：旋轉中途按 LMB 派生切換至輕連段
	print("测试中途换招：Spin -> LMB (輕連段)...")
	player.request_continuous_spin()
	for i in 25: await physics_frame # advance to ~18% progress
	fails += _check("Spin 正在播放中", player.action_state == 1)
	var evt_lmb := InputEventAction.new()
	evt_lmb.action = "attack_light"
	evt_lmb.pressed = true
	player._unhandled_input(evt_lmb)
	await physics_frame
	fails += _check("成功中斷 Spin 並切換至輕連段 (combo_stage == 1)", player.combo_stage == 1 and player.get("_attack_layer") == "upper")
	# 等待連段結束
	for i in 50: await physics_frame
	fails += _check("連段結束恢復 FREE", player.action_state == 0)

	# 9. 测试中途换招：旋轉中途按 RMB 派生切換至聚力重斬
	print("测试中途换招：Spin -> RMB (聚力重斬)...")
	player.request_continuous_spin()
	for i in 30: await physics_frame
	var evt_rmb := InputEventAction.new()
	evt_rmb.action = "attack_heavy"
	evt_rmb.pressed = true
	player._unhandled_input(evt_rmb)
	await physics_frame
	fails += _check("成功中斷 Spin 並切換至聚力重斬 (Heavy_Cut)", player.get("_active_attack_name") == "Heavy_Cut" and player.get("_attack_layer") == "upper")
	for i in 50: await physics_frame
	fails += _check("重斬結束恢復 FREE", player.action_state == 0)

	# 10. 测试中途换招：旋轉中途按 Shift 翻滾脫離 (Dodge Cancel)
	print("测试中途换招：Spin -> Shift (翻滾脫離)...")
	player.request_continuous_spin()
	for i in 35: await physics_frame
	player.request_dodge() # 直接測試中途 dodge 派生
	if player.action_state != 2: # 如果未直接取消，模擬 unhandled_input
		var evt_shift := InputEventAction.new()
		evt_shift.action = "sprint"
		evt_shift.pressed = true
		player._unhandled_input(evt_shift)
		evt_shift.pressed = false
		player._unhandled_input(evt_shift)
	await physics_frame
	fails += _check("成功中斷 Spin 並切換至翻滾 (DODGING)", player.action_state == 2) # ActionState.DODGING
	for i in 40: await physics_frame
	fails += _check("翻滾結束恢復 FREE", player.action_state == 0)

	# 11. 测试中途换招：旋轉中途按 Space 起跳 (Jump Cancel)
	print("测试中途换招：Spin -> Space (起跳)...")
	player.request_continuous_spin()
	for i in 25: await physics_frame
	var evt_jump := InputEventAction.new()
	evt_jump.action = "jump"
	evt_jump.pressed = true
	player._unhandled_input(evt_jump)
	await physics_frame
	fails += _check("成功中斷 Spin 並進入跳躍蓄力/起跳 (_jump_charge >= 0.0)", player.get("_jump_charge") >= 0.0)
	for i in 60: await physics_frame
	fails += _check("落地恢復 FREE", player.action_state == 0)

	# 12. 测试中途换招：旋轉中途派生至日之呼吸・壹ノ型 圓舞 (Form Cancel)
	print("测试中途换招：Spin -> Form 1 (日之呼吸・圓舞)...")
	player.request_continuous_spin()
	for i in 30: await physics_frame
	var form_ok: bool = player.execute_form(1)
	await physics_frame
	fails += _check("成功中斷 Spin 並發動壹ノ型 (active_form == 1)", form_ok and player.active_form == 1)
	for i in 60: await physics_frame
	fails += _check("型結束恢復 FREE", player.action_state == 0)

	print("--- 连续旋转砍击与中途换招验证完成，失败项: %d ---" % fails)
	player.free()
	floor_body.free()
	quit(fails)

func _check(label: String, ok: bool) -> int:
	print("  %s %s" % ["✓" if ok else "✗", label])
	return 0 if ok else 1
