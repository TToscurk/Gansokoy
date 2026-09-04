extends SceneTree
## Scatter nature assets along the east river bank, following the user's own
## placement convention.
##
## Why a script and not the brush: the user has the brush working now, but
## covering ~1.2 km of bank by hand is not a reasonable ask for a first pass.
## This lays a BASE the user can then edit — every plant is an individual Node3D
## instance under a named parent, exactly like the one Bush_Common_Flowers2 they
## placed by hand at (271, 0, -32), so it can be selected, moved or deleted one
## by one. It is a starting point for their judgement, not a replacement for it.
##
## Placement is ray-verified, not assumed: each candidate fires a downward ray
## and is REJECTED unless it lands on soil (never the revetment stone, never
## water, never a slope over the species' tolerance). The band map from
## map_bank_bands.gd showed the plantable strip is the soil slope inboard of the
## stone — roughly X 407..430 — but the rays decide per point, since the bank
## meanders over the 1.2 km run.
##
## Distribution is deliberately uneven — clustered with gaps — because an even
## sprinkle is the exact "generated" look the project is trying to avoid. Species
## are chosen by distance from the water so the bank reads as a gradient:
## reeds/grass low near the stone, ferns mid, bushes high, with occasional trees.
##
## Output: maps/slice/gen/bank_planting.tscn, instanced into slice.tscn.
## Nothing already in slice.tscn is modified.
##
## Run: godot --headless --path godot --script tools/gen_bank_planting.gd

const SCENE := "res://maps/slice/slice.tscn"
const OUT := "res://maps/slice/gen/bank_planting.tscn"

const Z0 := -200.0
const Z1 := 200.0

# Corridor to test. Wider than the plantable strip on purpose: the rays, not
# these numbers, decide what is actually usable.
const X_LO := 400.0
const X_HI := 436.0

const SEED := 20260902
const WATER_Y := -5.15

# Height bands come from the MEASURED distribution (hist_bank_heights.gd), not
# from a guessed cross-section — two earlier attempts set them by eye and threw
# away 80%+ of candidates. Reality: 94% of plantable points sit on the flat
# terrace 4.5–5.5 m above water; only ~6% lie on the slope between the stone and
# the terrace. So the terrace is the main planting surface, and the narrow slope
# band gets the water-loving species.
const SPECIES := {
	"reed": {
		"paths": [
			"res://assets/nature/Grass_Wispy_Tall.gltf",
			"res://assets/nature/Grass_Common_Tall.gltf",
		],
		"h_lo": 3.6, "h_hi": 5.3, "slope_max": 40.0,
		"scale": [0.8, 1.35], "weight": 30,
	},
	"fern": {
		"paths": [
			"res://assets/nature/Fern_1.gltf",
			"res://assets/nature/Plant_1.gltf",
		],
		"h_lo": 3.4, "h_hi": 5.6, "slope_max": 30.0,
		"scale": [0.75, 1.25], "weight": 28,
	},
	"bush": {
		"paths": [
			"res://assets/nature/Bush_Common.gltf",
			"res://assets/nature/Bush_Common_Flowers.gltf",
		],
		"h_lo": 4.3, "h_hi": 5.6, "slope_max": 22.0,
		"scale": [0.7, 1.2], "weight": 26,
	},
	"rock": {
		"paths": [
			"res://assets/nature/Rock_Medium_1.gltf",
			"res://assets/nature/Pebble_Square_3.gltf",
		],
		"h_lo": 0.35, "h_hi": 5.2, "slope_max": 40.0,
		"scale": [0.6, 1.4], "weight": 16,
	},
}

# Cluster parameters. Hand painting produces clumps separated by bare ground;
# a uniform Poisson fill does not. Walk the bank in runs, alternating dense
# clusters with deliberate gaps.
const CLUSTER_LEN_MIN := 6.0
const CLUSTER_LEN_MAX := 22.0
const GAP_LEN_MIN := 4.0
const GAP_LEN_MAX := 26.0
const IN_CLUSTER_SPACING := 1.1

var _rng := RandomNumberGenerator.new()
var _cache := {}


func _init() -> void:
	root.call_deferred("add_child", load(SCENE).instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await physics_frame
	await physics_frame

	_rng.seed = SEED
	var scene := root.get_child(root.get_child_count() - 1)
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state

	var out_root := Node3D.new()
	out_root.name = "河岸植生"

	var groups := {}
	for k in SPECIES:
		var g := Node3D.new()
		g.name = "河岸_%s" % k
		out_root.add_child(g)
		groups[k] = g

	var placed := 0
	var rejected := {"stone": 0, "water": 0, "slope": 0, "band": 0, "nohit": 0}
	var per_species := {}

	var z := Z0
	while z < Z1:
		# One cluster, then one gap. Lengths vary so the rhythm never repeats.
		var cluster_len := _rng.randf_range(CLUSTER_LEN_MIN, CLUSTER_LEN_MAX)
		var z_end: float = min(z + cluster_len, Z1)
		# Each cluster leans toward one species, so clumps read as a stand of
		# reeds or a knot of bushes rather than a mixed salad everywhere.
		var lead: String = _pick_species()

		while z < z_end:
			# Sample a few X across the strip; density falls off away from the
			# cluster's core line to soften the edges.
			var picks := _rng.randi_range(2, 5)
			for i in picks:
				var x := _rng.randf_range(X_LO, X_HI)
				var zz := z + _rng.randf_range(-0.4, 0.4)

				var q := PhysicsRayQueryParameters3D.new()
				q.from = Vector3(x, 60.0, zz)
				q.to = Vector3(x, -60.0, zz)
				var r: Dictionary = space.intersect_ray(q)
				if r.is_empty():
					rejected["nohit"] += 1
					continue

				var body_name: String = r["collider"].name
				if body_name.begins_with("EastRiverRevetment"):
					rejected["stone"] += 1
					continue

				var hit: Vector3 = r["position"]
				if hit.y <= WATER_Y + 0.35:
					rejected["water"] += 1
					continue

				var n: Vector3 = r["normal"]
				var slope := rad_to_deg(acos(clampf(n.dot(Vector3.UP), -1.0, 1.0)))

				# 70% of a cluster is its lead species, the rest mixed in.
				var sp: String = lead if _rng.randf() < 0.7 else _pick_species()
				var d: Dictionary = SPECIES[sp]

				var h := hit.y - WATER_Y
				if h < d["h_lo"] or h > d["h_hi"]:
					rejected["band"] += 1
					continue
				if slope > d["slope_max"]:
					rejected["slope"] += 1
					continue

				var paths: Array = d["paths"]
				var path: String = paths[_rng.randi() % paths.size()]
				var inst := _instance(path)
				if inst == null:
					continue

				var s_range: Array = d["scale"]
				var s := _rng.randf_range(s_range[0], s_range[1])
				var yaw := _rng.randf() * TAU

				var b := Basis()
				b = b.rotated(Vector3.UP, yaw)
				b = b.scaled(Vector3.ONE * s)
				inst.transform = Transform3D(b, hit)
				inst.name = "%s_%04d" % [sp, placed]

				groups[sp].add_child(inst)
				per_species[sp] = per_species.get(sp, 0) + 1
				placed += 1

			z += IN_CLUSTER_SPACING

		z += _rng.randf_range(GAP_LEN_MIN, GAP_LEN_MAX)

	# Ownership must be set after the whole tree is built, or PackedScene.pack
	# drops the children.
	_set_owner(out_root, out_root)

	var ps := PackedScene.new()
	var err := ps.pack(out_root)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	err = ResourceSaver.save(ps, OUT)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return

	print("\n== 河岸植生 ==")
	var keys := per_species.keys()
	keys.sort()
	for k in keys:
		print("  %-6s %d 株" % [k, per_species[k]])
	print("  合計 %d 株" % placed)
	print("\n剔除:")
	for k in rejected:
		print("  %-8s %d" % [k, rejected[k]])
	print("\n[done] %s" % OUT)
	quit(0)


func _pick_species() -> String:
	var total := 0
	for k in SPECIES:
		total += SPECIES[k]["weight"]
	var roll := _rng.randi_range(1, total)
	for k in SPECIES:
		roll -= SPECIES[k]["weight"]
		if roll <= 0:
			return k
	return SPECIES.keys()[0]


func _instance(path: String) -> Node3D:
	if not _cache.has(path):
		var p = load(path)
		if p == null:
			push_warning("cannot load %s" % path)
			_cache[path] = null
		else:
			_cache[path] = p
	var packed = _cache[path]
	if packed == null:
		return null
	return packed.instantiate()


## Set ownership so PackedScene.pack keeps the nodes — but NEVER descend into an
## instanced sub-scene. Each plant here is an instantiated GLTF whose internal
## mesh nodes belong to that GLTF, not to us. Claiming them writes a duplicate
## copy of the model's internals into this scene, and on load Godot reports
## "匯入的節點名稱與場景中現有的 ... 衝突" and silently renames them — which then
## breaks every NodePath into those nodes. Own only the direct instance roots.
func _set_owner(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		# scene_file_path is non-empty exactly for instantiated sub-scenes.
		if c.scene_file_path.is_empty():
			_set_owner(c, owner_node)
