extends SceneTree
## Second-pass check for the two remaining collision failures: sweep a capsule
## horizontally toward each target and report whether anything stops it.
## A point probe can land on TOP of a wall and read as "no wall"; a sweep
## across the wall cannot.

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
	var space: PhysicsDirectSpaceState3D = _main.map_root.get_world_3d().direct_space_state
	var mask: int = _main.player.collision_mask

	# from -> to at walking height. Each should be STOPPED.
	# Coordinates MEASURED by probe_collision_targets.gd / probe_torii_legs.gd,
	# not guessed: the first pass probed the torii 10 m short and the stone
	# bank 290 m off (at the review-scene canal, x≈-8, not the live one at
	# x≈280); the second aimed 2 m outside the legs, which are 3 m wide at
	# x≈230–232 and 240–242 (probe_torii_legs 2026-09-03).
	var sweeps := [
		{"n": "走向大鳥居左柱", "a": Vector3(231, 1.3, 96), "b": Vector3(231, 1.3, 106)},
		{"n": "走向大鳥居右柱", "a": Vector3(241, 1.3, 96), "b": Vector3(241, 1.3, 106)},
		{"n": "穿過大鳥居中央（應通過）", "a": Vector3(236, 1.3, 96), "b": Vector3(236, 1.3, 106)},
		{"n": "從村側走向石砌護岸", "a": Vector3(276, -1.0, -22), "b": Vector3(284, -1.0, -22)},
		{"n": "從水路走向石砌護岸", "a": Vector3(284, -1.5, -22), "b": Vector3(276, -1.5, -22)},
		{"n": "對照：主街空地", "a": Vector3(233, 1.0, 10), "b": Vector3(237, 1.0, 10)},
	]

	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	for s in sweeps:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis.IDENTITY, s["a"])
		q.motion = s["b"] - s["a"]
		q.collision_mask = mask
		var r := space.cast_motion(q)
		# r[0] = safe fraction of the motion; 1.0 = travelled the full way.
		var blocked := r[0] < 0.999
		var where := ""
		if blocked:
			q.transform.origin = s["a"] + q.motion * r[1]
			q.motion = Vector3.ZERO
			var hits := space.intersect_shape(q, 1)
			if not hits.is_empty():
				var c: Node = hits[0]["collider"]
				where = "%s/%s" % [c.get_parent().name, c.name]
		print("%-24s 走了 %5.1f%%  %s %s" % [s["n"], r[0] * 100.0,
			"擋住" if blocked else "通過", where])
	print("done")
	quit(0)
