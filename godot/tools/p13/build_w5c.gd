extends SceneTree
## P13 W5C — add the upper-transition group `W5C` (s=89.85–99.50 m) to the existing SandoPilotW4P13 overlay.
## The committed lower stair (W4Steps) and W5Upper (s=64.2–89.85) are loaded verbatim from the saved overlay and NOT rebuilt.
##   godot --path . --script res://tools/p13/build_w5c.gd -- --build      (rendering display required; writes W4.OUTPUT)
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")
const W5 := preload("res://tools/village_v2_sando_w5a_lib.gd")
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const TR := preload("res://tools/p13/w5c_upper_plan.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	if not "--build" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		push_error("W5C requires explicit --build and a rendering display; no write performed")
		quit(2)
		return
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	var old := v.get_node_or_null(W4.NODE_NAME)
	if old:
		v.remove_child(old)
		old.free()
	root.add_child(v)
	for i in 5:
		await physics_frame
	var cl := SA.centerline()
	var H := SA.ramp_profile(v, cl)
	var st := SA.steps(cl, H)
	var rp := SA.ramp_points(st, H)
	var plan0 := TR.plan(st)
	var y_in := TR.initial_y(cl, H, st, rp)
	if plan0.is_empty() or is_nan(y_in):
		push_error("W5C plan/initial_y failed")
		quit(2)
		return
	var sp := v.get_world_3d().direct_space_state
	var lamps: Array = []
	for e in SA.lantern_specs(cl, H, st, sp):
		if not lamps.has(float(e["s"])):
			lamps.append(float(e["s"]))
	var rest := W4.r8_without_range((v.get_node("ShrineApproachP10/StoneSteps") as MeshInstance3D).mesh as ArrayMesh, cl, Vector2i(744, TR.END))
	print("[W5C] original triangles %d removed %d remaining %d" % [int(rest.get_meta("total")), int(rest.get_meta("removed")), int(rest.get_meta("total")) - int(rest.get_meta("removed"))])
	var kr := Vector2i(TR.START, TR.END)
	W5.integrated = true
	W5.scope_lo = kr.x
	W5.scope_hi = kr.y
	W5.setup(v, sp, cl)
	var plan := TR.plan(st, cl, W5.sampler)
	W4.flags = TR.flags(y_in)
	for a: Dictionary in plan:
		print("[W5C-PLAN] s=%.2f..%.2f %s y=%.3f cap_l=%s cap_r=%s" % [int(a["k0"]) * 0.05, int(a["k1"]) * 0.05, a["kind"], float(a["y0"]), str(a.get("cap_l", "-")), str(a.get("cap_r", "-"))])
	var top := W4.build(cl, H, plan, [W4.outer_profile(sp, cl, kr, -1.0), W4.outer_profile(sp, cl, kr, 1.0)],
		[W4.outer_profile(sp, cl, kr, -1.0, W4.U_FAR), W4.outer_profile(sp, cl, kr, 1.0, W4.U_FAR)], lamps, null)
	top.set_script(null)
	top.name = "W5C"
	for sd in W5.runs:
		for r: Dictionary in W5.runs[sd]:
			print("[W5C-RUN] sd=%s k=%d..%d (s=%.2f..%.2f) edge=%.2f ta=%.3f tb=%.3f" % [str(sd), int(r["ka"]), int(r["kb"]), int(r["ka"]) * 0.05, int(r["kb"]) * 0.05, float(r["edge"]), float(r["ta"]), float(r["tb"])])
	print("[W5C] %d elements; s=%.2f..%.2f; stats %s" % [plan.size(), TR.START * 0.05, TR.END * 0.05, str(W5.stats)])
	W4.flags = {}
	W5.scope_lo = 744
	W5.scope_hi = 1284
	# committed overlay (lower + W5Upper) is loaded untouched; W5C is appended
	var ov := (ResourceLoader.load(W4.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var prev := ov.get_node_or_null("W5C")
	if prev:
		ov.remove_child(prev)
		prev.free()
	ov.add_child(top)
	top.owner = ov
	for n in top.find_children("*", "", true, false):
		if n.owner == top:
			n.owner = ov
	(top.get_node("W4Soil") as MeshInstance3D).material_override = (v.get_node("Terrain/MainTerrain") as MeshInstance3D).material_override
	ov.set("rest_mesh", rest)
	var intr := TR.intruders(v, cl, H)
	ov.set("suppress_plants", intr)
	for e: Dictionary in intr:
		print("[W5C] suppress forest plant %s origin=%s far=%s[%d]" % [e["name"], str(e["origin"]), e["far"], int(e["far_index"])])
	ov.set_meta("integrated_range", Vector2(37.2, TR.END * 0.05))
	ov.set_meta("art_revision", "P13 W4B r13 + W5B integration r1 + W5C upper transition r1")
	var wind := SA.winding_bad(ov)
	var ok: bool = int(wind[0]) == 0 and ov.find_children("*", "CollisionObject3D", true, false).is_empty()
	var ps := PackedScene.new()
	if ok:
		ok = ps.pack(ov) == OK and ResourceSaver.save(ps, W4.OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK
	if ok:
		var saved := (ResourceLoader.load(W4.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		ok = saved.get_node_or_null("W5C/W4Steps") != null and saved.get_node_or_null("W5Upper/W4Steps") != null
		saved.free()
	print("[W5C] save+readback %s winding %s collision bodies %d" % [str(ok), str(wind), ov.find_children("*", "CollisionObject3D", true, false).size()])
	ov.free()
	quit(0 if ok else 1)
