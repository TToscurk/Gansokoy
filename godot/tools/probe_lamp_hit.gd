extends SceneTree
## 路燈碰撞為何在實走測試中沒被撞到？
##
##   Godot --headless --path godot --script tools/probe_lamp_hit.gd
##
## 已知：verify_lamp_collision.gd 的膠囊掃掠（r=0.45）確實擋在 路燈_03_碰撞，
## 但 walk_slice.gd 的真實控制器（r=0.30）從 z=78 走到 z=104 卻一路暢通。
## 兩者差在半徑與路徑，這支把燈柱周圍的實際可穿越間隙量出來。

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	for i in 8:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = main.map_root.get_world_3d().direct_space_state

	# 燈的實際碰撞體位置（直接從場景樹讀，不從檔案推）
	var lamps: Node = main.map_root.get_node_or_null("路燈碰撞")
	if lamps == null:
		print("[HIT] ✗ 場景裡沒有「路燈碰撞」節點")
		quit(1)
		return
	print("[HIT] 路燈碰撞節點下有 %d 個 body" % lamps.get_child_count())
	for b in lamps.get_children():
		if String(b.name).contains("03"):
			var body := b as StaticBody3D
			var cs := body.get_child(0) as CollisionShape3D
			var cyl := cs.shape as CylinderShape3D
			print("[HIT] %s：位置 %v，半徑 %.3f 高 %.3f，圖層 %d" % [
				body.name, body.transform.origin, cyl.radius, cyl.height,
				body.collision_layer])

	# 沿實走路徑逐點做球體重疊測試，找出哪裡真的碰得到
	print("[HIT] === 沿 x=241.09 的路徑掃描（實走用 r=0.30）===")
	print("[HIT] %8s %10s %s" % ["z", "命中", "碰撞體"])
	var z := 78.0
	while z <= 96.0:
		var hit := _overlap(space, Vector3(241.09, 1.0, z), 0.30)
		if hit != "":
			print("[HIT] %8.1f %10s %s" % [z, "擋", hit])
		z += 1.0
	print("[HIT] （沒列出的 z 表示該處無碰撞）")

	# 燈柱中心到底在哪個 y？實走的膠囊中心在 y=1.0，燈的圓柱可能不在那個高度
	print("[HIT] === 高度掃描：x=241.09 z=86.06 垂直方向 ===")
	var y := -1.0
	while y <= 6.0:
		var hit := _overlap(space, Vector3(241.09, y, 86.06), 0.30)
		print("[HIT]   y=%5.2f  %s" % [y, hit if hit != "" else "（無）"])
		y += 0.5

	print("[HIT] done")
	quit(0)


func _overlap(space: PhysicsDirectSpaceState3D, p: Vector3, r: float) -> String:
	var sph := SphereShape3D.new()
	sph.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, p)
	q.collision_mask = 1
	var hits := space.intersect_shape(q, 4)
	var names := PackedStringArray()
	for h in hits:
		names.append(String((h["collider"] as Node).name))
	return ", ".join(names)
