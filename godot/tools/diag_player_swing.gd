extends SceneTree
## 玩家的刀到底砍不砍得中敵人？站在旁邊發一記輕斬，看數值。

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
	for i in 20:
		await physics_frame
		await process_frame

	# 貼著敵人站，面向它
	enemy.global_position = player.global_position + Vector3(0, 0, -1.4)
	enemy.state = enemy.State.IDLE
	player.rotation.y = PI
	var hb: Area3D = null
	for a in player.find_children("*", "Area3D", true, false):
		if String(a.name) == "BladeHitbox":
			hb = a
	print("[SWING] hitbox=%s monitoring=%s layer=%d mask=%d" % [hb != null,
		str(hb.monitoring) if hb else "-", hb.collision_layer if hb else -1,
		hb.collision_mask if hb else -1])
	print("[SWING] enemy layer=%d mask=%d 敌人 Hurtbox mask=%d" % [enemy.collision_layer,
		enemy.collision_mask, enemy.get_node("Hurtbox").collision_mask])
	var h0: float = enemy.posture.health
	var p0: float = enemy.posture.posture
	player.request_primary_attack()
	print("[SWING] t=0 attack fired, action=%s" % str(player.action_state))
	for i in 120:
		await physics_frame
		await process_frame
		# 維持距離：物理可能推開雙方
		enemy.global_position = player.global_position + Vector3(0, 0, -1.4)
		if enemy.posture.health < h0:
			print("[SWING] 命中！t=%.2fs hp %.1f→%.1f posture %.1f→%.1f"
				% [i / 60.0, h0, enemy.posture.health, p0, enemy.posture.posture])
			break
	print("[SWING] 結果：hp %.1f→%.1f  posture %.1f→%.1f  action=%s" % [h0,
		enemy.posture.health, p0, enemy.posture.posture, str(player.action_state)])
	if enemy.posture.health == h0:
		# 沒打中——看 hitbox 掃描到什麼
		hb.monitoring = true
		await physics_frame
		print("[SWING] body overlaps=%s  areas=%s" % [
			str(hb.get_overlapping_bodies().map(func(b): return b.name)),
			str(hb.get_overlapping_areas().map(func(b): return b.name))])
		var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state
		var q := PhysicsShapeQueryParameters3D.new()
		q.collide_with_bodies = true
		q.collide_with_areas = true
		q.collision_mask = hb.collision_mask
		q.shape = hb.get_child(0).shape
		q.transform = hb.global_transform
		for hit in space.intersect_shape(q, 8):
			print("[SWING] query hit: %s" % str(hit.get("collider").name))
	quit(0)
