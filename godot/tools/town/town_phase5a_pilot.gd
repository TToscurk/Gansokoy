extends RefCounted


const REPLACEMENTS := [
	{"lot": Vector2(-69.6973, 78.6869), "kind": "family_small_merchant_01"},
	{"lot": Vector2(-78.8831, 80.2153), "kind": "family_small_merchant_03"},
	{"lot": Vector2(-89.0626, 78.7573), "kind": "family_standard_machiya_02", "move": Vector2(-1.0, 0.0)},
	{"lot": Vector2(-83.2000, 89.7000), "kind": "family_standard_machiya_02"},
	{"lot": Vector2(-61.6623, 90.1261), "kind": "family_standard_machiya_03"},
	{"lot": Vector2(-75.6838, 104.7178), "kind": "family_kura_compact"},
	{"lot": Vector2(-6.1034, -150.3902), "kind": "asset_proof_hatago", "move": Vector2(0.0, 1.1)},
	{"lot": Vector2(6.7199, -150.0819), "kind": "asset_proof_sake_shop", "move": Vector2(0.0, -3.5)},
	{"lot": Vector2(-5.6500, -116.7000), "kind": "family_small_merchant_01"},
]


static func apply(
		mods: Dictionary,
		dump: Array,
		batch: Dictionary,
		phase5a_families: Dictionary,
		bank_h: Callable,
		add_market_quarter_lots: Callable,
		audit: Array[String]) -> void:
	var changed := 0
	for spec in REPLACEMENTS:
		var best := -1
		var best_d := 0.35
		for i in dump.size():
			if not String(dump[i][0]).begins_with("machiya"):
				continue
			var p := Vector2(float(dump[i][1]), float(dump[i][3]))
			var d: float = p.distance_to(spec["lot"])
			if d < best_d:
				best = i
				best_d = d
		if best < 0:
			push_error("PHASE 5A lot missing near %s" % str(spec["lot"]))
			continue
		var e: Array = dump[best]
		var new_kind: String = spec["kind"]
		var yaw: float = float(e[4])
		if bool(mods[new_kind].get("centered", false)):
			var fwd := Vector2(sin(yaw), cos(yaw))
			var shift: float = float(mods[new_kind]["d"]) * 0.5 - 0.85
			e[1] = float(e[1]) - fwd.x * shift
			e[3] = float(e[3]) - fwd.y * shift
			e[2] = bank_h.call(float(e[1]), float(e[3]))
		var move: Vector2 = spec.get("move", Vector2.ZERO)
		e[1] = float(e[1]) + move.x
		e[3] = float(e[3]) + move.y
		e[2] = bank_h.call(float(e[1]), float(e[3]))
		e[0] = new_kind
		changed += 1
	var added: int = add_market_quarter_lots.call()
	batch.clear()
	for e in dump:
		var kind := String(e[0])
		if not _is_house_kind(kind, phase5a_families):
			continue
		var xf := Transform3D(Basis(Vector3.UP, float(e[4])),
			Vector3(float(e[1]), float(e[2]), float(e[3])))
		if not batch.has(kind):
			batch[kind] = []
		batch[kind].append(xf)
	audit.append("PHASE 5A curated pilot: %d lots replaced" % changed)
	audit.append("PHASE 5A-V market quarter: %d permanent commercial lots added" % added)


static func _is_house_kind(kind: String, phase5a_families: Dictionary) -> bool:
	return kind.begins_with("machiya") or phase5a_families.has(kind)
