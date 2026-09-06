extends SceneTree

func _init():
	_run.call_deferred()

func _run():
	print("--- TESTING COMBAT & CAMERA SYSTEM ---")

	# 1. Test Player instantiation
	var player_scene: PackedScene = load("res://characters/yoriichi/player_yoriichi.tscn")
	assert(player_scene != null, "player_yoriichi.tscn failed to load")
	var player = player_scene.instantiate()
	root.add_child(player)
	await process_frame
	print("[PASS] Player instantiated successfully")

	# 2. Check jump parameters
	print("Jump velocity: ", player.jump_velocity, " (expected: 8.2)")
	assert(is_equal_approx(player.jump_velocity, 8.2), "jump_velocity != 8.2")
	var jump_height = (player.jump_velocity * player.jump_velocity) / (2.0 * player.gravity)
	print("Calculated jump height: ", jump_height, " m (expected ~1.68 m)")
	print("[PASS] Jump parameters verified")

	# 3. Verify Audio is REMOVED
	var audio = player.get_node_or_null("CharacterAudio")
	assert(audio == null, "CharacterAudio should be removed from player")
	print("[PASS] Character audio successfully removed")

	# 4. Check sword trail & hitbox
	var trail = player.get_node_or_null("SwordTrail")
	assert(trail != null, "SwordTrail node not found on player")
	print("[PASS] SwordTrail node exists")

	var hitbox = player.find_child("BladeHitbox", true, false)
	assert(hitbox != null, "BladeHitbox not found")
	print("[PASS] BladeHitbox exists")

	# 5. Check Camera adapter improvements
	var adapter = player.get_node_or_null("CameraAdapter")
	assert(adapter != null, "CameraAdapter not found")
	assert(adapter.default_distance >= 8.0, "default_distance should be >= 8.0")
	var pivot = player.get_node_or_null("Pivot")
	assert(pivot != null and pivot.top_level == true, "Pivot must be top_level for smooth follow")
	print("[PASS] Camera smooth follow and distance verified (dist=", adapter.default_distance, ")")

	# 6. Test TrainingDummy & Hit interaction
	var dummy_scene: PackedScene = load("res://characters/combat/training_dummy.tscn")
	assert(dummy_scene != null, "training_dummy.tscn failed to load")
	var dummy = dummy_scene.instantiate()
	root.add_child(dummy)
	await process_frame
	dummy.global_position = Vector3(0, 0, 2)
	dummy.take_hit({
		"damage": 25.0,
		"hit_pos": Vector3(0, 1.2, 2),
		"hit_dir": Vector3(0, 0, 1),
		"heavy": true
	})
	assert(dummy.health < 1000.0, "Dummy did not take damage")
	print("[PASS] Dummy hit interaction verified (health remaining: ", dummy.health, ")")

	# 7. Clean up
	player.queue_free()
	dummy.queue_free()

	print("--- ALL COMBAT & CAMERA SYSTEM TESTS PASSED ---")
	quit(0)
