extends SceneTree
## 玩家的刀能不能砍中 enemy_samurai——最小案例，無機器人干擾。
## （舊測試只有打木人樁與直呼 take_hit()，從沒驗證 blade→samurai 這條線。）

var main: Node = null
var player: Node = null
var enemy: Node = null

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	main = load("res://scenes/combat_arena.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await physics_frame
		await process_frame
	player = main.get_node("Player")
	for n in main.find_children("*", "CharacterBody3D", true, false):
		var s: Variant = n.get_script()
		if s != null and String(s.resource_path).ends_with("enemy_samurai.gd"):
			enemy = n
	player.sword_state = player.SwordState.DRAWN
	for i in 30:
		await physics_frame
		await process_frame

	# 玩家在原點面朝 -z；敵人放正前方 1.5 m，靜止。
	player.global_position = Vector3(0, 0.1, 0)
	player.rotation.y = 0.0
	enemy.global_position = Vector3(0, 0.1, -1.5)
	enemy.state = enemy.State.APPROACH  # 別让它 IDLE 不動；給它目標會面向玩家
	enemy.target = null  # 不追不打，只站著挨砍
	var hb0: float = enemy.posture.health
	print("[BLADE] before: enemy_hp=%.1f  player_rot=%.2f  dist=%.2f" % [hb0, player.rotation.y,
		player.global_position.distance_to(enemy.global_position)])

	var frames_with_monitoring := 0
	var hb: Area3D = null
	for a in player.find_children("*", "Area3D", true, false):
		if String(a.name) == "BladeHitbox":
			hb = a
	for attempt in 3:
		player.action_state = 0
		player.request_primary_attack()
		for i in 40:
			await physics_frame
			await process_frame
			enemy.global_position = Vector3(0, 0.1, -1.5)
			if hb != null and hb.monitoring:
				frames_with_monitoring += 1
		if enemy.posture.health < hb0:
			break
	print("[BLADE] after 3 swings: enemy_hp %.1f → %.1f  monitoring_frames=%d"
		% [hb0, enemy.posture.health, frames_with_monitoring])
	print("[BLADE] %s" % ("PASS 刀打得中武士" if enemy.posture.health < hb0
		else "FAIL 刀砍不到武士——實戰零命中是真 bug"))
	quit(0 if enemy.posture.health < hb0 else 1)
