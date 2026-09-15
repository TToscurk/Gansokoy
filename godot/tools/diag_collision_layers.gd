extends SceneTree
## 列出地面／建物／邊界牆各自的 collision_layer，決定射線該用哪個 mask。

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "trail")
	await _wait(90)
	var slice: Node = main.get_node_or_null("slice")
	if slice == null:
		print("找不到 slice")
		quit(1)
		return
	for group in ["地面碰撞_刷筆用", "建物碰撞", "手動碰撞"]:
		var g: Node = slice.get_node_or_null(group)
		if g == null:
			print("\n--- %s：不存在" % group)
			continue
		print("\n--- %s（%d 個子節點）---" % [group, g.get_child_count()])
		var shown := 0
		for c in g.get_children():
			if c is CollisionObject3D and shown < 6:
				var co: CollisionObject3D = c
				print("  %-26s layer=%d mask=%d"
					% [String(co.name), co.collision_layer, co.collision_mask])
				shown += 1
	quit(0)
