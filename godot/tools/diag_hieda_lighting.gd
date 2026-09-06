extends SceneTree
## Measure what is actually lighting 稗田邸, per floor, before touching anything.

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

	for spec in [["hieda1f", "slice"], ["hieda2f", "hieda1f"], ["hieda3f", "hieda2f"]]:
		var id: String = spec[0]
		main.load_map(id, spec[1])
		await _wait(70)
		var mr: Node3D = main.map_root
		print("[LIGHT] ===== %s =====" % id)

		var lights := 0
		for n in mr.find_children("*", "Light3D", true, false):
			var l := n as Light3D
			lights += 1
			var kind := "Omni"
			if l is DirectionalLight3D:
				kind = "Directional"
			elif l is SpotLight3D:
				kind = "Spot"
			var rng := 0.0
			if l is OmniLight3D:
				rng = (l as OmniLight3D).omni_range
			elif l is SpotLight3D:
				rng = (l as SpotLight3D).spot_range
			print("[LIGHT] %-12s %-24s energy=%.2f range=%.1f pos=(%.1f,%.1f,%.1f) shadow=%s"
				% [kind, l.name, l.light_energy, rng,
					l.global_position.x, l.global_position.y, l.global_position.z,
					str(l.shadow_enabled)])
		print("[LIGHT] 光源總數：%d" % lights)

		var envs := 0
		for n in mr.find_children("*", "WorldEnvironment", true, false):
			var we := n as WorldEnvironment
			envs += 1
			var e := we.environment
			if e == null:
				print("[LIGHT] WorldEnvironment %s 但 environment 是 null" % we.name)
				continue
			print("[LIGHT] Env %s: bg_mode=%d ambient_source=%d ambient_energy=%.2f sky_contrib=%.2f ambient_color=%s"
				% [we.name, e.background_mode, e.ambient_light_source,
					e.ambient_light_energy, e.ambient_light_sky_contribution,
					str(e.ambient_light_color)])
			print("[LIGHT]     ssao=%s glow=%s tonemap=%d exposure=%.2f"
				% [str(e.ssao_enabled), str(e.glow_enabled), e.tonemap_mode, e.tonemap_exposure])
		print("[LIGHT] WorldEnvironment 數：%d" % envs)

		# Is the main scene's own environment/sun still active for this map?
		var main_env: Node = main.get_node_or_null("WorldEnvironment")
		var main_sun: Node = main.get_node_or_null("Sun")
		print("[LIGHT] main WorldEnvironment 啟用=%s / Sun 啟用=%s"
			% [str(main_env != null and main_env.environment != null),
				str(main_sun != null and (main_sun as Light3D).visible)])

	quit(0)
