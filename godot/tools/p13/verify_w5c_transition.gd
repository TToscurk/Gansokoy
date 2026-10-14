extends "res://tools/p13/verify_w5b_integration.gd"
## P13 W5C local gate (upper shrine stair transition, s=89.85–99.50 m). Rendering display NOT required (no MultiMesh read).
##   godot --headless --path . --script res://tools/p13/verify_w5c_transition.gd -- [--approved <W5B-committed sando_pilot_w4_p13.scn path>]
## Checks: scope / unchanged approved W5B geometry / plan fidelity (collision contract) / saved = generator / walk-surface vs ramp /
## joins / no double r8 stones / under-cap holes / terrain-through-tread / vegetation on the stair / negatives.
const TR := preload("res://tools/p13/w5c_upper_plan.gd")
const LAT_WALK := 0.85          # the walking corridor the contract protects (SWALK measures 0, ±0.5, ±0.85)
const POKE_MAX := 0.05          # terrain may rise at most 5 cm above a tread top inside |lat| <= LAT_WALK (riser feet / rear lips excluded); r8 before: 11.6 cm

## Visible walking surface = highest of the stair meshes and the P1 terrain (terrain is what the eye sees where it covers stone / where no stone is drawn).
class VisGrid extends WS.TopGrid:
	var terr: Callable
	func top_at(x: float, z: float) -> float:
		var y := super.top_at(x, z)
		var t: float = float(terr.call(Vector2(x, z)))
		if is_nan(y):
			return t
		if is_nan(t):
			return y
		return maxf(y, t)

func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await physics_frame
	cl = SA.centerline()
	sp = v.get_world_3d().direct_space_state
	var H := SA.ramp_profile(v, cl)
	var st := SA.steps(cl, H)
	var rp := SA.ramp_points(st, H)
	var ov := v.get_node(W4.NODE_NAME)
	var grp := ov.get_node_or_null("W5C")
	_ok(grp != null, "W5C group exists in overlay")
	if grp == null:
		quit(1)
		return
	# ── scope: nothing outside 89.85..99.50 (+ short tapers)
	var plan := TR.plan(st)
	_ok(plan.size() == 20 and int(plan[0]["k0"]) == TR.START and int(plan[plan.size() - 1]["k1"]) == TR.END, "plan = the 20 original r8 elements, s=89.85..99.50")
	var fid := 0
	var prev_k := TR.START
	for a: Dictionary in plan:
		var orig: Array = st.filter(func(x: Dictionary) -> bool: return int(x["k0"]) == int(a["k0"]) and int(x["k1"]) == int(a["k1"]))
		if orig.size() != 1 or absf(float(orig[0]["y0"]) - float(a["y0"])) > 1e-6 or absf(float(orig[0]["y1"]) - float(a["y1"])) > 1e-6 or int(a["k0"]) != prev_k:
			fid += 1
		prev_k = int(a["k1"])
	_ok(fid == 0, "every tread keeps the original k-range and height; contiguous; violations %d (collision contract)" % fid)
	# ── approved W5B geometry unchanged (W4Steps/W4Soil/W5Upper/W5Plants vs committed file)
	var args := OS.get_cmdline_user_args()
	if "--approved" in args:
		var ap := (ResourceLoader.load(args[args.find("--approved") + 1], "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		var same := true
		for path in ["W4Steps", "W4Soil", "W5Upper/W4Steps", "W5Upper/W4Soil"]:
			var a: PackedVector3Array = (ap.get_node(path) as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var b: PackedVector3Array = (ov.get_node(path) as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var eq := a.size() == b.size()
			if eq:
				for j in a.size():
					if a[j] != b[j]:
						eq = false
						break
			print("[W5C] approved %s vertices %d / %d identical=%s" % [path, a.size(), b.size(), str(eq)])
			same = same and eq
		_ok(same, "approved s=37.2..89.85 stair/wall/soil meshes bit-identical to committed W5B")
		ap.free()
	# ── generator reproducibility
	var lamps: Array = []
	for e in SA.lantern_specs(cl, H, st, sp):
		if not lamps.has(float(e["s"])):
			lamps.append(float(e["s"]))
	var kr := Vector2i(TR.START, TR.END)
	var y_in := TR.initial_y(cl, H, st, rp)
	W5.scope_lo = kr.x
	W5.scope_hi = kr.y
	W5.setup(v, sp, cl)
	W4.flags = TR.flags(y_in)
	var touts := [W4.outer_profile(sp, cl, kr, -1.0), W4.outer_profile(sp, cl, kr, 1.0)]
	var tfars := [W4.outer_profile(sp, cl, kr, -1.0, W4.U_FAR), W4.outer_profile(sp, cl, kr, 1.0, W4.U_FAR)]
	var ms := W4.build_meshes(cl, H, TR.plan(st, cl, W5.sampler), touts, tfars, lamps)
	var same2 := true
	for nm in ["W4Steps", "W4Soil"]:
		var a2: PackedVector3Array = (grp.get_node(nm) as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var b2: PackedVector3Array = (ms["steps" if nm == "W4Steps" else "soil"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if a2.size() != b2.size():
			same2 = false
		else:
			for j in a2.size():
				if a2[j].distance_to(b2[j]) > 1e-4:
					same2 = false
					break
	_ok(same2, "W5C saved meshes = recomputed same-seed generator")
	var pn := grp.get_node_or_null("W5Plants")
	_ok((pn.get_child_count() if pn != null else 0) == W5.plants.size(), "W5C plant count = generator (%d)" % W5.plants.size())
	# ── grounding / lantern feet / soil on P1 (same definitions as the W5B upper gate)
	var nb := 0
	var fl := 0
	var worst := INF
	for d: Dictionary in W4.diag:
		if not bool(d.get("base", false)):
			continue
		var by := _terr(d["p"])
		if is_nan(by):
			fl += 1
			continue
		nb += 1
		worst = minf(worst, by - float(d["ybot"]))
		if by - float(d["ybot"]) < 0.08:
			fl += 1
	_ok(nb > 20 and fl == 0, "W5C base stones grounded %d; violations %d; minimum embed %.3f m" % [nb, fl, worst])
	var soil_far := {}
	var soil_all := _tris(ms["soil"])
	for key in soil_all:
		var tt: Array = soil_all[key]
		var cc: Vector3 = ((tt[0] as Vector3) + (tt[1] as Vector3) + (tt[2] as Vector3)) / 3.0
		if _s_lat(cc).y > 1.38:
			soil_far[key] = tt
	_ok(_ground_bad(soil_far, -0.06, 0.62) == 0, "W5C soil outside the stair grounded on frozen P1 (no sunk / floating patch)")
	var all_new := _tris(ms["steps"])
	all_new.merge(soil_all)
	_ok(_lantern_bad(all_new, lamps, 1.62) == 0, "W5C stones keep clear of lantern feet")
	var scope_bad := 0
	for key in all_new:
		var tc: Array = all_new[key]
		var c3: Vector3 = ((tc[0] as Vector3) + (tc[1] as Vector3) + (tc[2] as Vector3)) / 3.0
		var sl := _s_lat(c3)
		if sl.x < TR.START * 0.05 - 1.2 or sl.x > TR.END * 0.05 + 1.2 or sl.y > 4.5:
			scope_bad += 1
	_ok(scope_bad == 0, "every W5C triangle lies within s=88.65..100.70 m (taper allowance) and 4.5 m of the axis; outside %d" % scope_bad)
	# ── structure
	_ok(ov.find_children("*", "CollisionObject3D", true, false).is_empty(), "no added collision bodies")
	var wb := SA.winding_bad(ov)
	_ok(int(wb[0]) == 0, "winding wrong %d / %d" % [int(wb[0]), int(wb[1])])
	# ── r8 removal: exactly once, up to 99.50 m
	var baseline := (load("res://maps/village_v2/gen/shrine_approach_p10.scn") as PackedScene).instantiate()
	var expected := W4.r8_without_range((baseline.get_node("StoneSteps") as MeshInstance3D).mesh as ArrayMesh, cl, Vector2i(744, TR.END))
	var actual := (v.get_node("ShrineApproachP10/StoneSteps") as MeshInstance3D).mesh
	_ok(expected.surface_get_arrays(0)[Mesh.ARRAY_INDEX] == actual.surface_get_arrays(0)[Mesh.ARRAY_INDEX], "old r8 treads/curbs removed exactly once through s=99.50 (no double visible stair); remaining r8 tris %d" % (int(expected.get_meta("total")) - int(expected.get_meta("removed"))))
	# ── walk surface vs actual ramp collision, before(r8)/after(W5C), at the contract lateral positions
	var g0 := VisGrid.new()
	g0.terr = _terr
	g0.add_mesh((baseline.get_node("StoneSteps") as MeshInstance3D).mesh)
	var g1 := VisGrid.new()
	g1.terr = _terr
	g1.add_mesh(actual)
	for n in ov.find_children("*", "MeshInstance3D", true, false):
		if String(n.name) in ["W4Steps", "W4Soil"]:
			g1.add_mesh((n as MeshInstance3D).mesh)
	var lats := [0.0, 0.5, -0.5, 0.85, -0.85]
	var measured := WS.measure(sp, cl, TR.START, TR.END, lats, [g0, g1])
	if "--surf-list" in args:
		for k in range(TR.START, TR.END):
			var tq := cl[mini(k + 6, cl.size() - 1)] - cl[maxi(k - 6, 0)]
			tq = tq.normalized()
			var pq := cl[k] + Vector2(-tq.y, tq.x) * 0.85
			var ryq := WS.ramp_y(sp, pq)
			var d1 := g1.top_at(pq.x, pq.y) - ryq
			var d0 := g0.top_at(pq.x, pq.y) - ryq
			if absf(d1) > 0.10:
				print("[SURF] s=%.2f u=0.85 after=%+.3f before=%+.3f terr-ramp=%+.3f" % [k * 0.05, d1, d0, _terr(pq) - ryq])
	var vok := true
	for u in lats:
		var before := WS.summarize(measured[0][u])
		var after := WS.summarize(measured[1][u])
		print("[W5C-SURFACE] u=%s %s | %s" % [str(u), WS.fmt("before", before), WS.fmt("after", after)])
		if int(after["n"]) < TR.END - TR.START - 2 or not WS.gate_ok(after, before):
			vok = false
	_ok(vok, "visible stone vs actual ramp collision: no missing walk surface, no deterioration vs r8")
	# ── joins: 89.85 (new/old W5B), 99.50 (end)
	var join_bad := 0
	for kk in [TR.START, 1830, 1900, 1945, TR.END - 5]:
		for u: float in lats:
			for k in range(kk - 3, mini(kk + 4, TR.END - 1)):
				var t := SA.tangent(cl, k)
				var p := cl[k] + Vector2(-t.y, t.x) * u
				var y := g1.top_at(p.x, p.y)
				var ry := WS.ramp_y(sp, p)
				if is_nan(ry):
					continue
				var y0 := g0.top_at(p.x, p.y)
				var bad0 := is_nan(y0) or absf(y0 - ry) > 0.15           # r8 itself: terrain on the hill-side covers the stair up to ~20 cm at the very top
				if (is_nan(y) or absf(y - ry) > 0.15) and not bad0:
					join_bad += 1
					print("[JOIN-BAD] k=%d s=%.2f u=%.2f stairTop=%.3f ramp=%.3f terr=%.3f" % [k, k * 0.05, u, y, WS.ramp_y(sp, p), _terr(p)])
	_ok(join_bad == 0, "joins s=89.85 / interior / 99.50: no walk hole or >15 cm surface mismatch beyond what r8 already had; new bad %d" % join_bad)
	# ── under-cap holes (same ray test as W5B)
	await _cap_holes(v, grp, cl, W5.runs, touts, tfars, lamps)
	# ── terrain through the tread (visible 'bare earth / grass inside the stair')
	var r0 := WS.TopGrid.new()
	r0.add_mesh((baseline.get_node("StoneSteps") as MeshInstance3D).mesh)
	var r1 := WS.TopGrid.new()
	r1.add_mesh(actual)
	for n2 in ov.find_children("*", "MeshInstance3D", true, false):
		if String(n2.name) in ["W4Steps", "W4Soil"]:
			r1.add_mesh((n2 as MeshInstance3D).mesh)
	var poke := _poke(r1, TR.START, TR.END, LAT_WALK)
	var poke0 := _poke(r0, TR.START, TR.END, LAT_WALK)
	print("[W5C-POKE] inside |lat|<=%.2f: before max %.3f m (%d cells) | after max %.3f m (%d cells)" % [LAT_WALK, poke0[0], poke0[1], poke[0], poke[1]])
	_ok(float(poke[0]) <= POKE_MAX, "terrain above tread top inside |lat|<=0.85 (riser feet excluded) <= %.0f cm (r8 before %.1f cm)" % [POKE_MAX * 100.0, float(poke0[0]) * 100.0])
	# ── vegetation on the stair (effective, with the overlay script applied)
	var sup: Array = ov.get("suppress_plants")
	var gen_intr := TR.intruders(v, cl, H)
	var names_saved: Array = sup.map(func(e: Dictionary) -> String: return String(e["name"]))
	var names_gen: Array = gen_intr.map(func(e: Dictionary) -> String: return String(e["name"]))
	names_saved.sort()
	names_gen.sort()
	_ok(names_saved == names_gen and not names_gen.is_empty(), "saved suppress list = generator's intruder list %s (sealed forest_p9.scn untouched)" % str(names_gen))
	var veg_bad := _veg_on_stair(v, H)
	_ok(veg_bad.is_empty(), "no visible plant sits on the walking width of s=89.85..99.50 (%s)" % str(veg_bad))
	if DisplayServer.get_name() != "headless":
		var far_ok := true
		for e: Dictionary in sup:
			var mmi := v.get_node_or_null(NodePath(String(e["far"]))) as MultiMeshInstance3D
			if mmi == null:
				far_ok = false
				continue
			var sc := mmi.multimesh.get_instance_transform(int(e["far_index"])).basis.get_scale().length()
			far_ok = far_ok and sc < 1e-4
		_ok(far_ok, "far (LOD2 deep MultiMesh) instances of the same plants are hidden too")
	else:
		print("[W5C] far-instance check skipped in headless (MultiMesh data unreadable); run without --headless for it")
	# the same check, overlay off → the plants are back and the check sees them (real data negative)
	ov.set("enabled", false)
	await process_frame
	var veg_off := _veg_on_stair(v, H)
	_ok(veg_off.size() == names_gen.size(), "negative: with the overlay disabled the plants are visible again and the check catches them %s" % str(veg_off))
	ov.set("enabled", true)
	await process_frame
	_ok(_veg_on_stair(v, H).is_empty(), "re-enabled overlay hides them again")
	# ── negatives: same checks with deliberately broken data
	var broken := plan.duplicate(true)
	(broken[3] as Dictionary)["y0"] = float((broken[3] as Dictionary)["y0"]) + 0.2
	var nf := 0
	for a: Dictionary in broken:
		var orig2: Array = st.filter(func(x: Dictionary) -> bool: return int(x["k0"]) == int(a["k0"]))
		if absf(float(orig2[0]["y0"]) - float(a["y0"])) > 1e-6:
			nf += 1
	_ok(nf > 0, "negative: a raised tread is caught by the plan-fidelity check")
	_ok(float(poke0[0]) > POKE_MAX, "negative: the r8 baseline (known terrain-through-tread) is flagged by the same poke metric (%.1f cm)" % (float(poke0[0]) * 100.0))
	# negative: a synthetic plant dropped on the stair is caught by the vegetation check
	var fp := v.get_node("Vegetation/ForestP9")
	var dummy := Node3D.new()
	dummy.name = "W5C_NEG_PLANT"
	var dm := MeshInstance3D.new()
	dm.name = "LOD0"
	dm.mesh = BoxMesh.new()
	dummy.add_child(dm)
	fp.add_child(dummy)
	var kmid := (TR.START + TR.END) / 2
	dummy.global_position = Vector3(cl[kmid].x, H[kmid] + 0.5, cl[kmid].y)
	_ok(_veg_on_stair(v, H).has("W5C_NEG_PLANT"), "negative: a plant placed on the stair is caught by the vegetation check")
	fp.remove_child(dummy)
	dummy.free()
	baseline.free()
	W4.flags = {}
	W5.scope_lo = 744
	W5.scope_hi = 1284
	print("[W5C] result failures %d" % fails)
	quit(1 if fails else 0)

## terrain-above-stone inside the walking width: [max poke m, cell count > 5 mm]
func _poke(g: WS.TopGrid, k0: int, k1: int, lat_max: float) -> Array:
	var mx := 0.0
	var n := 0
	for k in range(k0, k1, 2):
		var t := SA.tangent(cl, k)
		var nr := Vector2(-t.y, t.x)
		var lat := -lat_max
		while lat <= lat_max + 1e-6:
			var p := cl[k] + nr * lat
			var sy := g.top_at(p.x, p.y)
			var ty := _terr(p)
			var pa := cl[mini(k + 3, cl.size() - 1)] + nr * lat
			var ahead := g.top_at(pa.x, pa.y)
			# the 15 cm in front of a riser / of the tread's rear lip (stone ends ahead): earth laps the foot or buries the lip, it does not cut through the tread
			var riser_foot: bool = not is_nan(sy) and (is_nan(ahead) or ahead > sy + 0.08)
			if not is_nan(sy) and not is_nan(ty) and ty > sy + 0.005 and not riser_foot:
				n += 1
				mx = maxf(mx, ty - sy)
				if "--poke-list" in OS.get_cmdline_user_args() and ty > sy + 0.03:
					print("[POKE] s=%.2f lat=%.2f stone=%.3f terr=%.3f poke=%.3f ahead=%.3f" % [k * 0.05, lat, sy, ty, ty - sy, ahead])
			lat += 0.1
	return [mx, n]

## ForestP9 plants whose body overlaps the walking width above the stone, s=89.85..99.50 (names)
func _veg_on_stair(v: Node3D, H: PackedFloat32Array) -> Array:
	var bad: Array = []
	var fp := v.get_node_or_null("Vegetation/ForestP9")
	if fp == null:
		return bad
	for n in fp.find_children("*", "MeshInstance3D", true, false):
		var g := n as MeshInstance3D
		if String(g.name) != "LOD0" or not g.is_visible_in_tree():
			continue
		var wbx := g.global_transform * g.get_aabb()
		var c := wbx.get_center()
		var best := INF
		var bk := 0
		for k in range(TR.START - 40, TR.END + 40):
			var d := cl[k].distance_to(Vector2(c.x, c.z))
			if d < best:
				best = d
				bk = k
		if bk < TR.START - 20 or bk > TR.END + 20 or best > 6.0:
			continue
		var t := SA.tangent(cl, bk)
		var nr := Vector2(-t.y, t.x)
		var lo := INF
		var hi := -INF
		for ix in 2:
			for iz in 2:
				var l2 := (Vector2(wbx.position.x + wbx.size.x * ix, wbx.position.z + wbx.size.z * iz) - cl[bk]).dot(nr)
				lo = minf(lo, l2)
				hi = maxf(hi, l2)
		if lo < 1.2 and hi > -1.2 and wbx.end.y > H[bk] + 0.1:
			bad.append(String(g.get_parent().name))
	return bad
