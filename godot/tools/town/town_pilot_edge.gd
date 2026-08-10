extends RefCounted


static func build(
		lib,
		root: Node3D,
		out_dir: String,
		seed_value: int,
		mods: Dictionary,
		dump: Array,
		is_pilot: Callable,
		pt_on_road_core: Callable,
		height_at: Callable,
		audit: Array[String]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 4101
	var kerbs: Array[Transform3D] = []
	var steps: Array[Transform3D] = []
	var t := -166.0
	while t < -80.0:
		for side in [-1.0, 1.0]:
			var px: float = side * 5.1
			kerbs.append(Transform3D(Basis(),
				Vector3(px, float(height_at.call(px, t)) + 0.02, t)))
		t += 1.0
	for e in dump:
		if not bool(is_pilot.call(e)):
			continue
		var m: Dictionary = mods[String(e[0])]
		var fac: Dictionary = m.get("facade", {})
		if fac.is_empty():
			continue
		var pos := Vector2(float(e[1]), float(e[3]))
		var yaw: float = float(e[4])
		var fwd := Vector2(sin(yaw), cos(yaw))
		var ax := Vector2(cos(yaw), -sin(yaw))
		var dx: float = float(fac["door_x"])
		for k in 3:
			var q: Vector2 = pos + ax * (dx - 0.9 + float(k) * 0.9) \
				+ fwd * (0.55 + float(k % 2) * 0.22)
			if bool(pt_on_road_core.call(q, 1.0)):
				continue
			steps.append(Transform3D(
				Basis(Vector3.UP, yaw + rng.randf_range(-0.08, 0.08)),
				Vector3(q.x, float(height_at.call(q.x, q.y)) + 0.03, q.y)))
	if kerbs.is_empty() and steps.is_empty():
		return
	var g: Node3D = lib.add(root, Node3D.new(), "回廊路縁")
	var kmat: Material = lib.pbr("回廊縁石", "stone_wall", 0.42, Color(0.58, 0.58, 0.56))
	var smat: Material = lib.pbr("回廊踏石", "stone_flag", 0.30, Color(0.62, 0.61, 0.57))
	for spec in [{"size": Vector3(1.0, 0.22, 0.16), "list": kerbs,
			"mat": kmat, "n": "路邊石"},
			{"size": Vector3(0.72, 0.11, 0.62), "list": steps,
			"mat": smat, "n": "踏石"}]:
		if (spec["list"] as Array).is_empty():
			continue
		var bm := BoxMesh.new()
		bm.size = spec["size"]
		bm.material = spec["mat"]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(bm, spec["list"], [],
			out_dir + "gen/pedge_%s.res" % String(spec["n"]))
		lib.add(g, mmi, "MM_%s" % String(spec["n"]))
	audit.append("PHASE 3.1A：回廊の縁石 %d・踏石 %d" % [kerbs.size(), steps.size()])
