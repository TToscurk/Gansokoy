extends SceneTree
## Where are the torii's legs, really? Scan a row of downward rays across the
## torii's X span at z = its centre, and a row of capsule probes at walking
## height, and print what each one hits. Also dump the trimesh's vertex count
## and Y range so we know whether the collision even reaches the ground.

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

	for body_name in ["大鳥居_mesh_node", "大鳥居2_mesh_node"]:
		var body := map.get_node_or_null("建物碰撞/" + body_name)
		if body == null:
			print("%s 不存在" % body_name)
			continue
		var cs: CollisionShape3D = body.get_child(0)
		var shape := cs.shape
		var hb: AABB = cs.global_transform * shape.get_debug_mesh().get_aabb()
		print("── %s  %s ──" % [body_name, shape.get_class()])
		print("  碰撞 AABB pos(%.1f, %.2f, %.1f) size(%.1f, %.2f, %.1f)" % [
			hb.position.x, hb.position.y, hb.position.z, hb.size.x, hb.size.y, hb.size.z])
		if shape is ConcavePolygonShape3D:
			var faces: PackedVector3Array = (shape as ConcavePolygonShape3D).get_faces()
			var lo := 1e9
			var hi := -1e9
			var below_1m := 0
			for v in faces:
				var wv: Vector3 = cs.global_transform * v
				lo = minf(lo, wv.y)
				hi = maxf(hi, wv.y)
				if wv.y < 1.0:
					below_1m += 1
			print("  trimesh %d 頂點，Y %.2f→%.2f，1 m 以下 %d 個頂點" % [faces.size(), lo, hi, below_1m])
		var cz := hb.get_center().z
		var ground_z := cz
		print("  沿 x 掃描 z=%.1f（膠囊中心 y=ground+0.9）" % ground_z)
		var x := hb.position.x - 1.0
		while x <= hb.position.x + hb.size.x + 1.0:
			var from := Vector3(x, 30.0, ground_z)
			var rq := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -60, 0), mask)
			rq.exclude = [_main.player.get_rid()]
			var rh := space.intersect_ray(rq)
			var gy := -99.0
			var gname := "無"
			if not rh.is_empty():
				gy = rh["position"].y
				gname = String((rh["collider"] as Node).name)
			# capsule at street level regardless of what the ray found on top
			var walk_y := 0.5
			var q := PhysicsShapeQueryParameters3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = RADIUS
			cap.height = HEIGHT
			q.shape = cap
			q.transform = Transform3D(Basis.IDENTITY, Vector3(x, walk_y + HEIGHT * 0.5, ground_z))
			q.collision_mask = mask
			q.exclude = [_main.player.get_rid()]
			var hits := space.intersect_shape(q, 4)
			var names := []
			for h in hits:
				names.append(String((h["collider"] as Node).name))
			print("    x=%6.1f  射線頂 y=%6.2f (%s)  膠囊: %s" % [
				x, gy, gname, "通" if hits.is_empty() else str(names)])
			x += 1.0
	print("done")
	quit(0)
