extends SceneTree
## Read-only W5B compatibility probe. No resource saves, generators, or disk state edits.
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	var overlay := v.get_node_or_null(W4.NODE_NAME)
	if overlay != null:
		overlay.set("enabled", false)
	root.add_child(v)
	await process_frame
	for n in 4:
		await physics_frame
	var cl := SA.centerline()
	var H := SA.ramp_profile(v, cl)
	var st := SA.steps(cl, H)
	var rp := SA.ramp_points(st, H)
	var rd := W4.ramp_dense(rp, cl.size())
	var shape := v.get_node("ShrineApproachP10/RampCollision/Ramp") as CollisionShape3D
	var body := shape.get_parent() as CollisionObject3D
	var sp := v.get_world_3d().direct_space_state
	var max_delta := 0.0
	var hits := 0
	for k in range(1284, mini(2000, cl.size() - 1) + 1):
		var p := cl[k]
		var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 80, p.y), Vector3(p.x, -20, p.y))
		var ex: Array[RID] = []
		for attempt in 20:
			query.exclude = ex
			var hit := sp.intersect_ray(query)
			if hit.is_empty():
				break
			if hit["rid"] == body.get_rid():
				hits += 1
				if not is_nan(rd[k]):
					max_delta = maxf(max_delta, absf(float(hit["position"].y) - rd[k]))
				break
			ex.append(hit["rid"])
	print("[UPPER] centerline_points=%d length=%.6f original_elements=%d ramp_hits=%d ramp_dense_vs_saved_max=%.9f" % [cl.size(), (cl.size() - 1) * 0.05, st.size(), hits, max_delta])
	var kinds := {}
	for i in st.size():
		var a: Dictionary = st[i]
		if int(a["k1"]) <= 1284 or int(a["k0"]) >= 2000:
			continue
		kinds[a["kind"]] = int(kinds.get(a["kind"], 0)) + 1
		print("[ELEMENT] idx=%d kind=%s k=%d..%d s=%.2f..%.2f y=%.9f..%.9f terrain=%.9f..%.9f" % [i, a["kind"], a["k0"], a["k1"], int(a["k0"]) * 0.05, int(a["k1"]) * 0.05, a["y0"], a["y1"], H[int(a["k0"])], H[int(a["k1"])]])
	print("[KINDS] ", JSON.stringify(kinds))
	print("[NONSTEP_DISPATCH] W4.build_meshes recognizes landing only; long/slab dispatch to tread. W4.replan processes step only and copies other kinds. Current upper slab count=", kinds.get("slab", 0))
	print("[EXTENSION_BOUNDARIES] complete_landing_bound=77.10 next_kind_change=89.85 long_end=97.25 original_element_end=99.50 requested_end=100.00")
	var saved_mesh := v.get_node("ShrineApproachP10/StoneSteps") as MeshInstance3D
	print("[ORIGINAL_STONE_MESH] surfaces=%d vertices=%d" % [saved_mesh.mesh.get_surface_count(), (saved_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()])
	for a: Dictionary in st:
		if a["kind"] == "landing":
			var ka := int(a["k0"])
			var kb := int(a["k1"])
			print("[LANDING] s=%.2f..%.2f start_xz=(%.9f,%.9f) end_xz=(%.9f,%.9f) top=%.9f" % [ka * 0.05, kb * 0.05, cl[ka].x, cl[ka].y, cl[kb].x, cl[kb].y, a["y0"]])
	var rng := RandomNumberGenerator.new()
	rng.seed = W4.SEED
	var i := 0
	var flight := 0
	while i < st.size():
		if st[i]["kind"] != "step":
			i += 1
			continue
		var j := i
		while j + 1 < st.size() and st[j + 1]["kind"] == "step":
			j += 1
		var ka := int(st[i]["k0"])
		var kb := int(st[j]["k1"])
		var yin := H[ka] if i == 0 else float(st[i - 1]["y1"])
		var yout := float(st[j + 1]["y0"]) if j + 1 < st.size() else H[kb] + 0.02
		var cells := W4.plan_flight(H, rd, ka, kb, yin, yout, i == 0, rng)
		var maxdev := 0.0
		var over := 0.0
		var minrise := INF
		var maxrise := -INF
		var prev := yin
		for c: Dictionary in cells:
			var rise := float(c["y0"]) - prev
			minrise = minf(minrise, rise)
			maxrise = maxf(maxrise, rise)
			for k in range(int(c["k0"]), int(c["k1"]) + 1):
				var d := absf(float(c["y0"]) - rd[k])
				maxdev = maxf(maxdev, d)
				over = maxf(over, d - W4.dev_limit(rise))
			prev = float(c["y1"])
		print("[FLIGHT] id=%d kind_after=%s original_count=%d s=%.2f..%.2f yin=%.9f yout=%.9f planned=%d maxdev=%.9f limit_over=%.9f minrise=%.9f maxrise=%.9f final_landing_rise=%.9f" % [flight, st[j + 1]["kind"] if j + 1 < st.size() else "END", j - i + 1, ka * 0.05, kb * 0.05, yin, yout, cells.size(), maxdev, over, minrise, maxrise, yout - prev])
		if ka >= 1284:
			var successes := 0
			for seed_offset in 10:
				var r2 := RandomNumberGenerator.new()
				r2.seed = W4.SEED + seed_offset
				if not W4.plan_flight(H, rd, ka, kb, yin, yout, false, r2).is_empty():
					successes += 1
			print("[SEED_ROBUSTNESS] s=%.2f..%.2f successful=%d/10" % [ka * 0.05, kb * 0.05, successes])
		flight += 1
		i = j + 1
	print("[READ_ONLY_AUDIT_COMPLETE] No files/scenes/resources/seals/index saved by probe.")
	v.queue_free()
	await process_frame
	quit(0)
