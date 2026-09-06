extends SceneTree

func _init():
	_run.call_deferred()

func _run():
	print("--- 开始验证奔跑无CD连斩系统 ---")
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

	for i in 10:
		await physics_frame

	var fails := 0

	# 1. 拔刀
	player.request_draw()
	for i in 60: await physics_frame
	fails += _check("拔刀完成，持刀狀態 (DRAWN)", player.sword_state == 2)

	# 2. 測試奔跑按住左鍵無限連續連斬 (1 -> 2 -> 3 -> 1 -> 2 -> 3)
	print("測試奔跑按住左鍵無限連續連斬...")
	Input.action_press("sprint")
	Input.action_press("attack_light")

	player.request_primary_attack()
	await physics_frame
	fails += _check("開始攻擊，進入 ATTACKING 狀態", player.action_state == 1)

	var stages_seen: Array[int] = []
	var stayed_attacking := true

	# 模擬 180 物理幀（約 3 秒，足夠完成 1->2->3->1->2 循環）
	for i in 180:
		await physics_frame
		var cur_stage: int = player.combo_stage
		if stages_seen.is_empty() or stages_seen[-1] != cur_stage:
			stages_seen.append(cur_stage)
		if player.action_state != 1:
			stayed_attacking = false

	print("  連斬階段流轉歷程: ", stages_seen)
	fails += _check("連斬期間全程無中斷、無CD停頓 (stayed_attacking)", stayed_attacking)
	fails += _check("成功從第 3 斬循環回第 1 斬 (contains 1 -> 2 -> 3 -> 1)", 
		stages_seen.has(1) and stages_seen.has(2) and stages_seen.has(3) and stages_seen.size() >= 5)

	# 3. 放開按鍵，驗證自然收勢
	Input.action_release("attack_light")
	Input.action_release("sprint")
	for i in 60: await physics_frame
	fails += _check("放開按鍵後乾淨收勢回到 FREE 狀態", player.action_state == 0)

	# 4. 測試木人樁受擊反饋
	print("測試命中木人樁與受擊反饋...")
	var dummy_scene: PackedScene = load("res://characters/combat/training_dummy.tscn")
	var dummy: TrainingDummy = dummy_scene.instantiate()
	root.add_child(dummy)
	await physics_frame
	dummy.global_position = player.global_position + Vector3(0, 0, 1.0)
	
	var initial_health: float = dummy.health
	player.request_primary_attack()
	for i in 30: await physics_frame
	
	fails += _check("木人樁受到傷害 (health < initial_health)", dummy.health < initial_health)
	fails += _check("受擊時觸發 _hit_targets_this_swing 記錄", player._hit_targets_this_swing.has(dummy))

	for i in 50: await physics_frame

	print("--- 奔跑无CD连斩验证完成，失败项: %d ---" % fails)
	player.free()
	dummy.free()
	floor_body.free()
	quit(fails)

func _check(label: String, ok: bool) -> int:
	print("  %s %s" % ["✓" if ok else "✗", label])
	return 0 if ok else 1
