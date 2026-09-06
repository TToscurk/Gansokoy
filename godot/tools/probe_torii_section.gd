extends SceneTree
## Cross-section of the torii's left leg: for each height band, which X
## positions does a capsule touch? Tells us whether the leg is a pedestal that
## narrows upward (audit probe floating 0.7 m above ground misses it) or a
## genuine hole in the trimesh.

const RADIUS := 0.45
const HEIGHT := 1.7

var _main: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	_main.load_map("slice", "")
	for i in 6:
		await physics_frame
	var map: Node = _main.map_root
	var space: PhysicsDirectSpaceState3D = map.get_world_3d().direct_space_state
	var mask: int = _main.player.collision_mask
	var z := 102.1

	# ground under the leg
	for x in [229.0, 230.0, 231.0, 232.0, 233.0]:
		var from := Vector3(x, 1.0, z)
		var rq := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -5, 0), mask)
		rq.exclude = [_main.player.get_rid()]
		var rh := space.intersect_ray(rq)
		print("x=%.0f 從 y=1.0 往下射：%s" % [x, ("y=%.2f %s" % [rh["position"].y, (rh["collider"] as Node).name]) if not rh.is_empty() else "無"])

	print("膠囊底部高度 → 各 x 是否接觸（z=%.1f）" % z)
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	for base_y in [0.3, 0.6, 1.0, 1.5, 2.0, 3.0]:
		var line := "  底 y=%.1f: " % base_y
		for x in range(228, 235):
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.transform = Transform3D(Basis.IDENTITY, Vector3(x, base_y + HEIGHT * 0.5, z))
			q.collision_mask = mask
			q.exclude = [_main.player.get_rid()]
			var hits := space.intersect_shape(q, 4)
			var tag := "·"
			for h in hits:
				var nm := String((h["collider"] as Node).name)
				tag = "T" if nm.begins_with("大鳥居") else ("G" if nm.findn("Terrain") != -1 or nm.findn("Ground") != -1 else "?")
				if tag == "T":
					break
			line += "x%d=%s " % [x, tag]
		print(line)
	print("T=鳥居 G=地面 ·=無")

	# thin box probes: 0.3 m cube at 0.5 m intervals up the column at x=231
	print("x=231 細探（0.3 m 方塊）沿高度：")
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	var y := 0.2
	var line2 := "  "
	while y <= 6.0:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = box
		q.transform = Transform3D(Basis.IDENTITY, Vector3(231.0, y, z))
		q.collision_mask = mask
		q.exclude = [_main.player.get_rid()]
		var hits := space.intersect_shape(q, 2)
		var t := "·"
		for h in hits:
			if String((h["collider"] as Node).name).begins_with("大鳥居"):
				t = "T"
		line2 += "y%.1f=%s " % [y, t]
		y += 0.4
	print(line2)
	print("done")
	quit(0)
