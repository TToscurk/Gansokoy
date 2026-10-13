extends RefCounted
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")
const START := 1284
const END := 1797  # Stop at structural change to shoulder long treads; no third stair kit.
const SEED := 133401

static func plan(cl: PackedVector2Array, H: PackedFloat32Array, st: Array, rp: Array) -> Array:
	var rd := W4.ramp_dense(rp, cl.size())
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = W4.SEED
	var i := 0
	while i < st.size() and int(st[i]["k0"]) < START:
		i += 1
	while i < st.size() and int(st[i]["k0"]) < END:
		var a: Dictionary = st[i]
		if String(a["kind"]) == "landing":
			out.append(a.duplicate(true))
			i += 1
			continue
		if String(a["kind"]) != "step":
			push_error("W5B upper incompatible kind before stop")
			return []
		var j := i
		while j + 1 < st.size() and String(st[j + 1]["kind"]) == "step" and int(st[j + 1]["k0"]) < END:
			j += 1
		var yin := float(st[i - 1]["y1"])
		var yout := float(st[j + 1]["y0"])
		var cells := W4.plan_flight(H, rd, int(a["k0"]), int(st[j]["k1"]), yin, yout, false, rng)
		if cells.is_empty():
			push_error("W5B upper planner failed; refuse fallback/rebuild")
			return []
		out.append_array(cells)
		i = j + 1
	return out

static func initial_y(st: Array) -> float:
	for a: Dictionary in st:
		if int(a["k1"]) == START:
			return float(a["y1"])
	return NAN
