extends RefCounted
## P13 W5C — upper shrine stair transition (s=89.85–99.50 m). Plan = the ORIGINAL r8 elements, verbatim
## (positions, depths, heights unchanged → ramp collision / walking contract unchanged); only the visible
## construction changes to the same W4B tread + W5A wall vocabulary as the approved lower stair.
## No re-planning (W5B proved plan_flight cannot re-plan the long treads / the exit-less last flight).
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")
const UP := preload("res://tools/p13/w5b_upper_plan.gd")
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const WALK_HALF := 1.2         # walking width + curb: |lat| below this must stay free of plants
const START := 1797           # s=89.85 m — W5B upper END (structural change r8 step -> long)
const END := 1990             # s=99.50 m — last original element end (shrine plaza begins)
const SEED := 133601          # tread-mesh rng (independent of W4 130401 / W5B 133401)

const EDGE_MIN := 0.20         # a tread is never narrower than this on either side of the walking line
const EDGE_MAX := 1.16         # W4.EDGE_HI
const MINOR := 0.85            # a cap at or above this is a few cm of grass at the very edge: left alone (natural), not a narrowing
const POKE_ALLOW := 0.08       # terrain may stand this far above a tread top (tilt 2.6 cm + grass lapping the edge) before the stone stops
const TAPER := 0.45            # |edge| may change by at most this between neighbouring treads → a taper, not a sawtooth

static func plan(st: Array, cl: PackedVector2Array = PackedVector2Array(), sampler: Callable = Callable()) -> Array:
	var out: Array = []
	for a: Dictionary in st:
		if int(a["k0"]) >= START and int(a["k1"]) <= END:
			if String(a["kind"]) == "landing":
				push_error("W5C: unexpected landing in %d..%d" % [START, END])
				return []
			out.append(a.duplicate(true))
	if sampler.is_valid() and cl.size() > 0 and OS.get_environment("W5C_NOCAP") != "1":
		_edge_caps(out, cl, sampler)
	return out

## Largest |u| per side where P1 terrain stays ≤ tread top + POKE_ALLOW (front / middle / back line of the tread), then a backward rate-limited
## taper (narrowing is anticipated over several treads, widening is immediate) so the stone edge follows the hill-side smoothly. Sets a["cap_l"], a["cap_r"] (read by W4.tread).
static func _edge_caps(plan: Array, cl: PackedVector2Array, sampler: Callable) -> void:
	var raw := [[], []]
	for a: Dictionary in plan:
		var y := float(a["y0"])
		for si in 2:
			var sd := -1.0 if si == 0 else 1.0
			var lim := EDGE_MAX
			for kk in [int(a["k0"]), (int(a["k0"]) + int(a["k1"])) / 2, int(a["k1"])]:
				var t := SA.tangent(cl, kk)
				var nr := Vector2(-t.y, t.x)
				var u := EDGE_MIN
				while u < lim:
					var ty: float = float(sampler.call(cl[kk] + nr * sd * u))
					if not is_nan(ty) and ty > y + POKE_ALLOW:
						lim = u
						break
					u += 0.05
			lim = maxf(lim, EDGE_MIN)
			(raw[si] as Array).append(lim if lim < MINOR else EDGE_MAX)
	for si in 2:
		var e: Array = raw[si]
		for i in range(e.size() - 2, -1, -1):
			e[i] = minf(float(e[i]), float(e[i + 1]) + TAPER)
	for i in plan.size():
		var a2: Dictionary = plan[i]
		if float((raw[0] as Array)[i]) < EDGE_MAX - 1e-6:
			a2["cap_l"] = float((raw[0] as Array)[i])
		if float((raw[1] as Array)[i]) < EDGE_MAX - 1e-6:
			a2["cap_r"] = float((raw[1] as Array)[i])

## Top of the last W5B upper tread (what the first W5C riser rises from). W5B's plan is deterministic.
static func initial_y(cl: PackedVector2Array, H: PackedFloat32Array, st: Array, rp: Array) -> float:
	var up := UP.plan(cl, H, st, rp)
	if up.is_empty():
		return NAN
	return float((up[up.size() - 1] as Dictionary)["y1"])

## W4 generator flags for the W5C group: own mesh seed, continue from the W5B top tread
static func flags(y_in: float) -> Dictionary:
	return {"mesh_seed": SEED, "initial_y": y_in}


## Sealed ForestP9 plants (Near LOD0/LOD1 nodes) whose body covers the walking width above the stone in s=89.85..99.50 m.
## Returns [{near, name, origin, far, far_index}] — `far` = the matching deep (LOD2) MultiMesh instance, found only when MultiMesh data is readable
## (rendering display). The sealed forest_p9.scn is never modified; the overlay script hides these at runtime (reversible).
static func intruders(v: Node3D, cl: PackedVector2Array, H: PackedFloat32Array) -> Array:
	var out: Array = []
	var fp := v.get_node_or_null("Vegetation/ForestP9")
	if fp == null:
		return out
	for n in fp.find_children("LOD0", "MeshInstance3D", true, false):
		var g := n as MeshInstance3D
		var plant := g.get_parent() as Node3D
		var wbx := g.global_transform * g.get_aabb()
		var c := wbx.get_center()
		var best := INF
		var bk := 0
		for k in range(START - 40, END + 40):
			var d := cl[k].distance_to(Vector2(c.x, c.z))
			if d < best:
				best = d
				bk = k
		if bk < START - 20 or bk > END + 20 or best > 6.0:
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
		if lo < WALK_HALF and hi > -WALK_HALF and wbx.end.y > H[bk] + 0.1:
			out.append({"near": String(v.get_path_to(plant)), "name": String(plant.name), "origin": plant.global_position, "far": "", "far_index": -1})
	var far := fp.get_node_or_null("Far")
	if far != null:
		for e: Dictionary in out:
			var species := String(e["name"]).substr(String(e["name"]).find("_") + 1)
			for mmi in far.find_children("*", "MultiMeshInstance3D", true, false):
				if not String(mmi.name).begins_with(species):
					continue
				var mm := (mmi as MultiMeshInstance3D).multimesh
				for i in mm.instance_count:
					if ((mmi as Node3D).global_transform * mm.get_instance_transform(i)).origin.distance_to(e["origin"]) < 0.05:
						e["far"] = String(v.get_path_to(mmi))
						e["far_index"] = i
	return out
