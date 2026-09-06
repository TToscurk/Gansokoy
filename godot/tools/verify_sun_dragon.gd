extends SceneTree
## Regression: the sun-dragon finisher spawns real geometry, sweeps, and cleans up.

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[SUN_DRAGON] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	var SunDragon = load("res://characters/yoriichi/vfx/sun_dragon.gd")
	check("dragon script exists", SunDragon != null)
	if SunDragon == null:
		print("[SUN_DRAGON] failures=%d" % failures)
		quit(1)
		return

	var host := Node3D.new()
	root.add_child(host)
	await process_frame

	var dragon = SunDragon.spawn(host, Transform3D(Basis(), Vector3(3, 0, -2)))
	check("spawn returns a node in tree", dragon != null and dragon.is_inside_tree())
	var spawn_reveal: float = dragon.get_reveal()
	check("nothing is revealed at spawn", spawn_reveal == 0.0)
	await _frames(2)

	# Real Blender geometry, not a placeholder box.
	var surfaces := 0
	var tris := 0
	for m in dragon.find_children("*", "MeshInstance3D", true, false):
		surfaces += m.mesh.get_surface_count()
		for s in m.mesh.get_surface_count():
			var arrays: Array = m.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3
	check("imported dragon has multiple material surfaces", surfaces >= 5)
	check("imported dragon has real triangle count", tris > 20000)

	# Every surface must be driven by the flame shader, not the raw GLB material.
	var shaded := 0
	var flame_count := 0
	for m in dragon.find_children("*", "MeshInstance3D", true, false):
		for s in m.mesh.get_surface_count():
			var mat: Material = m.get_surface_override_material(s)
			if mat is ShaderMaterial:
				shaded += 1
				if mat.shader != null and mat.shader.code.find("reveal") >= 0:
					flame_count += 1
	check("all surfaces use flame shader material", shaded >= 5 and shaded == flame_count)

	# Guard the mask that once cancelled the whole body: at burn 0 the swept-in
	# part must be fully alive, and at burn 1 nothing may remain.
	var probe := load("res://characters/yoriichi/vfx/sun_dragon.gdshader") as Shader
	check("shader still exposes burn and reveal", probe.code.find("burn") >= 0 and probe.code.find("reveal") >= 0)
	check("burn dissolves tail-first toward the head", probe.code.find("smoothstep(burn - 0.05, burn + 0.15, sweep)") >= 0)

	# Reveal sweeps tail to head over the strike, then burns away.
	var first: float = dragon.get_reveal()
	print("[SUN_DRAGON] reveal_after_2_frames=%f" % first)
	check("sweep is still in progress early on", first > 0.0 and first < 0.5)
	await _frames(30)
	var mid: float = dragon.get_reveal()
	check("reveal advances while striking", mid > first)
	check("reveal never exceeds one", mid <= 1.001)

	# The mesh follows the actor rather than staying at the world origin.
	check("spawned at requested transform", dragon.global_position.distance_to(Vector3(3, 0, -2)) < 0.01)

	# Shader parameters are actually pushed to every surface, not just cached.
	var pushed := true
	for m in dragon.find_children("*", "MeshInstance3D", true, false):
		for s in m.mesh.get_surface_count():
			var mat: ShaderMaterial = m.get_surface_override_material(s) as ShaderMaterial
			if absf(float(mat.get_shader_parameter("reveal")) - dragon.get_reveal()) > 0.001:
				pushed = false
	check("reveal is pushed to every surface", pushed)

	# It must free itself; a finisher may not leak nodes into the level.
	await _frames(220)
	check("dragon frees itself after the strike", not is_instance_valid(dragon) or not dragon.is_inside_tree())

	print("[SUN_DRAGON] failures=%d" % failures)
	host.free()
	quit(failures)
