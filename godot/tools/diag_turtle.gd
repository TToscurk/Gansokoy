extends SceneTree
## Turtle diagnostics: enemy attack cadence vs posture economy, with timestamps.

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

	var t := 0.0
	var last_state := ""
	enemy.state_changed.connect(func(_st): pass)
	while t < 24.0:
		await physics_frame
		await process_frame
		t += 1.0 / 60.0
		if not player.is_guarding() and player.action_state == 0:
			player.begin_guard()
		var st: String = str(enemy.state)
		if st != last_state:
			print("[T2] t=%5.2f enemy state %s→%s dist=%.2f posture=%.1f"
				% [t, last_state, st, player.global_position.distance_to(enemy.global_position),
					player.posture.posture])
			last_state = st
		# 每 2 秒印一次軀幹與守勢狀態
		if int(t * 2) != int((t - 1.0 / 60.0) * 2):
			print("[T2] t=%5.2f hp=%s posture=%.1f guarding=%s act=%s broken=%s"
				% [t, str(player.posture.health), player.posture.posture,
					str(player.is_guarding()), str(player.action_state),
					str(player.posture.is_broken())])
	print("[T2] end: hp=%s posture=%s guarding=%s" % [str(player.posture.health),
		str(player.posture.posture), str(player.is_guarding())])
	quit(0)
