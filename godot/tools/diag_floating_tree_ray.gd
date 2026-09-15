extends SceneTree
## 查兩棵浮空樹 (189.9,-191.7) 與 (206.7,-210.6) 的射線到底撞到什麼。
## 逐層列出該 xz 上所有碰撞體，而不只是最上面那個。

const SPOTS := [
	Vector2(189.9, -191.7),   # 大衫 #7   y=54.92
	Vector2(206.7, -210.6),   # 普通樹 #5 y=54.92
	Vector2(212.7, 1.6),      # 盆樹 #4   y=4.13
	Vector2(213.8, 66.2),     # 盆樹 #10  y=3.27
	Vector2(150.0, -20.0),    # 對照組：正常的西側林緣
]

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
	var space: PhysicsDirectSpaceState3D = main.get_viewport().world_3d.direct_space_state

	for s in SPOTS:
		print("\n=== (%.1f, %.1f) 由上而下所有碰撞層 ===" % [s.x, s.y])
		var from_y := 400.0
		var exclude: Array[RID] = []
		for depth in 8:
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(s.x, from_y, s.y), Vector3(s.x, -400.0, s.y))
			q.exclude = exclude
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty():
				if depth == 0:
					print("  （完全沒有碰撞）")
				break
			var col: Object = hit.get("collider")
			var nm := "?"
			var cls := "?"
			var owner_path := "?"
			if col is Node:
				nm = String((col as Node).name)
				cls = (col as Node).get_class()
				owner_path = String((col as Node).get_path())
			print("  y=%8.2f  %-22s (%s)" % [(hit.position as Vector3).y, nm, cls])
			print("            %s" % owner_path)
			exclude.append(hit.get("rid"))
	quit(0)
