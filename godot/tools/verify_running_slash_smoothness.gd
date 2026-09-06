extends SceneTree

func _init():
	_run.call_deferred()

func _run():
	print("--- 验证奔跑与走动挥砍速度平滑性 (Zero Stutter / Constant Speed) ---")
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	col.shape = box
	col.position = Vector3(0, -0.5, 0)
	floor_body.add_child(col)
	root.add_child(floor_body)

	var ps := load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene
	var player := ps.instantiate() as CharacterBody3D
	root.add_child(player)

	for i in 10: await physics_frame

	player.request_draw()
	for i in 60: await physics_frame

	var fails := 0

	# 1. 模拟疾跑按住攻击 (Sprint + LMB)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	Input.action_press("attack_light")

	player.request_primary_attack()
	await physics_frame

	var min_speed: float = 999.0
	var max_speed: float = 0.0

	for i in 100:
		await physics_frame
		var spd := Vector2(player.velocity.x, player.velocity.z).length()
		min_speed = minf(min_speed, spd)
		max_speed = maxf(max_speed, spd)

	print("  1. 疾跑挥砍 (Sprint + LMB):")
	print("     最低: %.2f m/s, 最高: %.2f m/s, 目标: %.2f m/s" % [min_speed, max_speed, player.run_speed])
	fails += _check("疾跑挥砍中速度恒定保持 7.0 m/s", min_speed >= 6.95 and max_speed <= 7.05)

	Input.action_release("sprint")
	# 2. 模拟普通移动按住攻击 (Walk + LMB)
	min_speed = 999.0
	max_speed = 0.0
	for i in 100:
		await physics_frame
		var spd := Vector2(player.velocity.x, player.velocity.z).length()
		min_speed = minf(min_speed, spd)
		max_speed = maxf(max_speed, spd)

	print("  2. 走动挥砍 (Walk + LMB):")
	print("     最低: %.2f m/s, 最高: %.2f m/s, 目标: %.2f m/s" % [min_speed, max_speed, player.speed])
	fails += _check("走动挥砍中速度恒定保持 4.0 m/s (不再被扣至 2.8 m/s)", min_speed >= 3.95 and max_speed <= 4.05)

	Input.action_release("move_forward")
	Input.action_release("attack_light")

	player.free()
	floor_body.free()
	print("--- 平滑性验证完成，失败项: %d ---" % fails)
	quit(fails)

func _check(label: String, ok: bool) -> int:
	print("  %s %s" % ["✓" if ok else "✗", label])
	return 0 if ok else 1
