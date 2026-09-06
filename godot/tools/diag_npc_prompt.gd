extends SceneTree
## Why does the slice NPC prompt never fire?

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.load_map("slice", "trail")
	await process_frame
	await process_frame
	var player = main.player
	var npc = main.map_root.get_node_or_null("VerticalSliceNPC")
	print("[DBG] npc=%s" % npc)
	if npc == null:
		quit(1)
		return
	player.global_position = npc.global_position + Vector3(0, 0, 3)
	await physics_frame
	await physics_frame
	print("[DBG] no-look_at: prompt=%s text=%s" % [str(main.interaction_prompt.visible), main.interaction_prompt.text])
	player.get_node("Pivot").rotation.y = PI  # 面向 -z 的 NPC
	await physics_frame
	await physics_frame
	var ray2: RayCast3D = player.get_node("CameraAdapter").interaction_ray
	ray2.force_raycast_update()
	print("[DBG] after pivot turn: colliding=%s prompt=%s text=%s" % [str(ray2.is_colliding()),
		str(main.interaction_prompt.visible), main.interaction_prompt.text])
	var adapter = player.get_node("CameraAdapter")
	var ray: RayCast3D = adapter.interaction_ray
	print("[DBG] player=%s npc=%s body_rot=%s" % [str(player.global_position), str(npc.global_position), str(player.rotation)])
	print("[DBG] ray global=%s" % str(ray.global_position))
	print("[DBG] ray pivot rot=%s" % str(ray.global_rotation))
	ray.force_raycast_update()
	print("[DBG] colliding=%s collider=%s" % [str(ray.is_colliding()),
		str(ray.get_collider())])
	print("[DBG] ray enabled=%s mask=%d areas=%s target=%s" % [str(ray.enabled),
		ray.collision_mask, str(ray.collide_with_areas), str(ray.target_position)])
	print("[DBG] prompt label=%s text=%s" % [str(main.interaction_prompt.visible), main.interaction_prompt.text])
	# What layer does the NPC's area sit on, actually?
	for a in npc.find_children("*", "Area3D", true, false):
		print("[DBG] area %s layer=%d mask=%d global=%s" % [a.name, a.collision_layer, a.collision_mask, str((a as Node3D).global_position)])
	quit(0)
