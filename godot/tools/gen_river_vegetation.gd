extends SceneTree
## River-crest vegetation belt for maps/slice, driven by ProtonScatter.
##
## Why this exists: the approved B-scale revetment leaves two razor-straight
## seams down both banks — stone cap -> ochre maintenance path, and ochre path
## -> grass slope. The outer seam is the one that reads as a printed stripe in
## `shots2/vegbelt_before_20260828`. A reed/bush belt straddling it breaks the
## line without touching the approved ground, water, or revetment meshes.
##
## Placement is NOT random-on-a-collider: the crest curves are computed from the
## same centreline, width and height maths as `tools/gen_terrain_river.gd`, so
## every scatter point sits on the real terrain surface with no raycast and no
## floating. Keep the constants below in sync with that generator; they are
## copied deliberately rather than imported because the terrain generator is a
## SceneTree script and re-running it would regenerate the approved meshes.
##
## Assets are reused, not authored: bamboo clumps stand in as reed/susuki tufts
## (uniform down-scale keeps the thin-culm proportion) and the 稗田 bushes fill
## the grass side. Both are existing approved GLBs — per the 2026-08-26 ruling,
## no new procedurally authored visible assets.
##
## Output: maps/slice/gen/river_vegetation.tscn (instanced once from slice.tscn)
## Run: godot --headless --path godot --script tools/gen_river_vegetation.gd

const CELL := 6.0
const R_EXT := 1250.0
const SEED := 20260827
const VILLAGE_HALF := 300.0
const VILLAGE_BLEND_END := 440.0
const WATER_HALF := 22.0
const TOP_HALF := 34.0
const BED_Y := -5.15 - 0.95

# Belt extent: covers every camera in tools/shots/east_river_view.json plus a
# margin, instead of the full 2.5 km corridor that would be paid for but never seen.
const Z0 := -620.0
const Z1 := 660.0
const STEP := 4.0

# The Meshy bridge lands here; its approach must stay clear on both banks.
const BRIDGE_Z := -143.9
const BRIDGE_CLEAR := 32.0

const OUT_PATH := "res://maps/slice/gen/river_vegetation.tscn"
const SCATTER := "res://addons/proton_scatter/src/scatter.gd"
const SCATTER_ITEM := "res://addons/proton_scatter/src/scatter_item.gd"
const SCATTER_SHAPE := "res://addons/proton_scatter/src/scatter_shape.gd"
const PATH_SHAPE := "res://addons/proton_scatter/src/shapes/path_shape.gd"
const MOD_STACK := "res://addons/proton_scatter/src/stack/modifier_stack.gd"
const MOD_EDGE := "res://addons/proton_scatter/src/modifiers/create_along_edge_even.gd"
const MOD_RANDOM := "res://addons/proton_scatter/src/modifiers/randomize_transforms.gd"
const REED_A_MESH := "res://maps/slice/gen/reed_a.res"
const REED_B_MESH := "res://maps/slice/gen/reed_b.res"
# The canopy binding that gen_lib gives every tree samples the forest texture at
# 1.25 m world tiling; on a 10 cm reed leaf that averages out to straw gold. The
# river transition grass material is the existing double-sided, coarse-tiled
# (5.5 m) green already authored for this waterline, so reeds borrow it.
const REED_MAT := "res://assets/materials/river_transition_grass.tres"
# PolyHaven CC0 photoscans (1k), fetched 2026-08-28 — see imported_models/polyhaven/LICENSE.txt.
# These carry their own scanned PBR materials; no override, unlike the reeds.
const PH := "res://imported_models/polyhaven/"
const GEN := "res://maps/slice/gen/"
# name -> [source gltf, baked mesh, is_foliage]
const PH_BAKES := {
	"shrub": [PH + "shrub_01/shrub_01_1k.gltf", GEN + "ph_shrub.res", true],
	"nettle": [PH + "nettle_plant/nettle_plant_1k.gltf", GEN + "ph_nettle.res", true],
	"periwinkle": [PH + "periwinkle_plant/periwinkle_plant_1k.gltf", GEN + "ph_periwinkle.res", true],
	"fern": [PH + "fern_02/fern_02_1k.gltf", GEN + "ph_fern.res", true],
	"grass": [PH + "grass_medium_02/grass_medium_02_1k.gltf", GEN + "ph_grass.res", true],
	"rock": [PH + "rock_moss_set_01/rock_moss_set_01_1k.gltf", GEN + "ph_rock.res", false],
}
const PH_SHRUB_A := GEN + "ph_shrub.res"
const PH_SHRUB_B := GEN + "ph_nettle.res"
const PH_SHRUB_C := GEN + "ph_periwinkle.res"
const PH_FERN := GEN + "ph_fern.res"
const PH_GRASS := GEN + "ph_grass.res"
const PH_ROCK := GEN + "ph_rock.res"

# One row = one parallel curve at a fixed offset from the outer seam, so every
# row carries its own exact terrain height. Lateral jitter stays small for the
# same reason (the bank still falls away ~0.22 m per metre just inside the seam).
# offset is metres outward from the seam; negative = towards the water.
const ROWS := [
	{"offset": -2.6, "spacing": 1.9, "kind": "reed", "row_seed": 11},
	{"offset": -0.9, "spacing": 1.7, "kind": "reed", "row_seed": 23},
	{"offset": 0.8, "spacing": 2.6, "kind": "reed", "row_seed": 37},
	{"offset": 3.4, "spacing": 8.0, "kind": "bush", "row_seed": 53},
	{"offset": 7.2, "spacing": 13.0, "kind": "bush", "row_seed": 71},
	# Mossy photoscan boulders half-buried in the grass shoulder; very sparse
	# so they read as survivors, not decoration. y_sink buries the flat base.
	{"offset": 5.0, "spacing": 60.0, "kind": "rock", "row_seed": 89, "y_sink": 0.3},
]

var _n := FastNoiseLite.new()
var _wander := FastNoiseLite.new()


func _river_x(z: float) -> float:
	return 430.0 + 55.0 * sin(z * 0.006 + 1.3) + 30.0 * sin(z * 0.0023 - 0.7) \
		+ _n.get_noise_1d(z * 0.8) * 18.0


func _wvar(z: float) -> float:
	return 1.0 + 0.08 * sin(z * 0.0042 + 0.9) + 0.05 * sin(z * 0.0117 - 1.7) \
		+ _n.get_noise_1d(z * 0.35 + 400.0) * 0.06


func _widths(z: float) -> Vector2:
	var water_half: float = WATER_HALF * _wvar(z)
	return Vector2(water_half, water_half + (TOP_HALF - WATER_HALF))


## Terrain height, matching gen_terrain_river.gd inside the river corridor.
## Hills are omitted on purpose: their valley_clear factor is exactly 0 for every
## point this belt can reach, so including them would only add drift.
func _ground_y(x: float, z: float) -> float:
	var pl: float = maxf(absf(x), absf(z))
	var village_blend: float = smoothstep(VILLAGE_HALF - 24.0, VILLAGE_BLEND_END, pl)
	var natural_ground: float = -0.12 + _n.get_noise_2d(x * 1.6 + 88.0, z * 1.6) * 0.55
	var g: float = lerpf(0.0, natural_ground, village_blend)

	var widths: Vector2 = _widths(z)
	var d: float = absf(x - _river_x(z))
	if d < widths.y:
		var bank_top: float = g
		if d <= widths.x:
			g = BED_Y
		else:
			var bank_t: float = (d - widths.x) / (widths.y - widths.x)
			g = lerpf(BED_Y, bank_top, smoothstep(0.0, 1.0, bank_t))
	return g


func _build_curve(side: float, offset: float, row_seed: int,
		y_sink: float = 0.0) -> Curve3D:
	var curve := Curve3D.new()
	var z: float = Z0
	while z <= Z1:
		if absf(z - BRIDGE_Z) < BRIDGE_CLEAR:
			z += STEP
			continue
		# The belt must not read as a drawn line: the offset itself wanders.
		var wander: float = _wander.get_noise_2d(z * 0.9, float(row_seed) * 40.0) * 2.3
		var d: float = _widths(z).y + offset + wander
		var x: float = _river_x(z) + side * d
		curve.add_point(Vector3(x, _ground_y(x, z) - 0.12 - y_sink, z))
		z += STEP
	return curve


## The bamboo GLBs carry no colour of their own: their vertex "Col" channel
## exports as pure white and their embedded glTF materials are untextured, so
## instancing the scene raw renders white sticks. Lift the bare mesh out here and
## let the item's override_material (REED_MAT) supply the colour for every
## surface. gen_lib.tree_mesh() would also work, but it re-saves the shared
## bark/canopy .tres files as a side effect and strips their uids.
func _bake_reed(glb: String, out_path: String) -> void:
	var packed: PackedScene = load(glb)
	var node: Node = packed.instantiate()
	var mesh: Mesh = null
	for c in node.find_children("*", "MeshInstance3D", true, false):
		mesh = (c as MeshInstance3D).mesh
		break
	node.free()
	if mesh == null:
		push_error("no mesh in %s" % glb)
		return
	var err: int = ResourceSaver.save(mesh, out_path)
	if err != OK:
		push_error("reed mesh save failed (%d): %s" % [err, out_path])


## PolyHaven photoscans arrive as multi-MeshInstance scenes whose leaf materials
## use ALPHA_SCISSOR at the default 0.5 threshold. Under gl_compatibility that
## erodes the leaf cards to white speckles a few metres out (mip alpha shrinks,
## scissor bites, only bright card edges survive) — measured in
## shots2/vegbelt_ph2_20260828. Bake each scene to one ArrayMesh (transforms
## applied, materials kept per surface) and re-tune every foliage material:
## lower scissor threshold so mips keep their leaves, kill the specular sky
## glint, force double-sided. Rocks pass through with materials untouched.
func _bake_photoscan(glb: String, out_path: String, foliage: bool) -> void:
	var packed: PackedScene = load(glb)
	if packed == null:
		push_error("missing photoscan %s" % glb)
		return
	var node: Node = packed.instantiate()
	var out := ArrayMesh.new()
	var tuned := {}
	for c in node.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var xf: Transform3D = mi.transform
		for si in range(mi.mesh.get_surface_count()):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.append_from(mi.mesh, si, xf)
			var mat: Material = mi.mesh.surface_get_material(si)
			if foliage and mat is StandardMaterial3D:
				if not tuned.has(mat):
					var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					m.alpha_scissor_threshold = 0.22
					m.metallic_specular = 0.05
					m.cull_mode = BaseMaterial3D.CULL_DISABLED
					tuned[mat] = m
				mat = tuned[mat]
			st.set_material(mat)
			st.commit(out)
	node.free()
	if out.get_surface_count() == 0:
		push_error("no surfaces baked from %s" % glb)
		return
	var err: int = ResourceSaver.save(out, out_path)
	if err != OK:
		push_error("photoscan bake failed (%d): %s" % [err, out_path])


func _make_item(parent: Node, nm: String, res_path: String,
		proportion: int, scale_mult: float, mat_path: String = "",
		shadows: bool = false) -> void:
	var item: Node3D = load(SCATTER_ITEM).new()
	item.name = nm
	item.source = 1
	item.path = res_path
	item.proportion = proportion
	item.source_scale_multiplier = scale_mult
	# The tree/bamboo GLBs ship no materials: colour lives in the vertex "Col"
	# attribute and the Godot side normally binds it per surface. Instanced raw
	# they render pure white, so bind the shared double-sided vertex-colour
	# foliage material here instead of authoring a new one.
	if not mat_path.is_empty():
		item.override_material = load(mat_path)
	item.override_cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	item.visibility_range_end = 320.0
	item.visibility_range_end_margin = 40.0
	item.lod_generate = false
	parent.add_child(item)


func _make_row(root: Node3D, side: float, side_name: String, row: Dictionary,
		index: int) -> Dictionary:
	var scatter: Node3D = load(SCATTER).new()
	scatter.name = "%s_%s_%02d" % [side_name, row["kind"], index]
	scatter.global_seed = SEED + int(row["row_seed"]) + (0 if side < 0.0 else 500)
	scatter.render_mode = 0
	scatter.force_rebuild_on_load = true
	# Headless capture screenshots after a fixed number of frames; a threaded
	# build can miss that window entirely and render an empty belt.
	scatter.dbg_disable_thread = true
	root.add_child(scatter)

	var shape_node: Node3D = load(SCATTER_SHAPE).new()
	shape_node.name = "Crest"
	var path_shape = load(PATH_SHAPE).new()
	path_shape.closed = false
	path_shape.curve = _build_curve(side, float(row["offset"]), int(row["row_seed"]),
			float(row.get("y_sink", 0.0)))
	shape_node.shape = path_shape
	scatter.add_child(shape_node)

	match row["kind"]:
		"reed":
			# Bamboo culms down-scaled to 1.4-2.0 m read as reed / susuki tufts.
			# Photoscan grass tufts were tried here and rejected: their blades
			# are sub-pixel past ~15 m and gl_compatibility has no TAA or
			# alpha-to-coverage, so they render as white dust
			# (shots2/vegbelt_ph2/ph3_20260828).
			_make_item(scatter, "ReedA", REED_A_MESH, 60, 0.22, REED_MAT)
			_make_item(scatter, "ReedB", REED_B_MESH, 40, 0.19, REED_MAT)
		"bush":
			# Photoscans are real-world scale (0.4-1 m); scaled well past that
			# so the leaf cards stay pixel-sized at the shot distances instead
			# of eroding. Shadows on — a photoscan bush without a contact
			# shadow floats visually.
			_make_item(scatter, "ShrubA", PH_SHRUB_A, 35, 2.4, "", true)
			_make_item(scatter, "ShrubB", PH_SHRUB_B, 25, 3.0, "", true)
			_make_item(scatter, "ShrubC", PH_SHRUB_C, 20, 3.0, "", true)
			_make_item(scatter, "FernA", PH_FERN, 20, 2.4, "", true)
		"rock":
			_make_item(scatter, "MossRock", PH_ROCK, 100, 1.3, "", true)

	# Build through the global class names: assigning a plain `load(...).new()`
	# Resource to the typed `modifier_stack` setter silently leaves it null, and
	# the scene then saves with no stack and scatters nothing.
	var stack := ProtonScatterModifierStack.new()
	var edge: ScatterBaseModifier = load(MOD_EDGE).new()
	edge.spacing = float(row["spacing"])
	edge.align_to_path = false
	var jitter: ScatterBaseModifier = load(MOD_RANDOM).new()
	# X is lateral here, Z runs with the river: keep lateral small (height drift),
	# let the along-path spread do the work of killing the even spacing.
	jitter.position = Vector3(0.45, 0.05, 1.1)
	jitter.rotation = Vector3(4.0, 180.0, 4.0)
	jitter.scale = Vector3(0.28, 0.28, 0.28)
	var mods: Array[ScatterBaseModifier] = [edge, jitter]
	stack.stack = mods
	scatter.modifier_stack = stack
	if scatter.modifier_stack == null:
		push_error("modifier stack did not attach to %s" % scatter.name)

	return {"name": scatter.name, "points": path_shape.curve.point_count}


func _init() -> void:
	_n.seed = SEED
	_n.noise_type = FastNoiseLite.TYPE_VALUE
	_n.fractal_octaves = 4
	_n.frequency = 1.0 / 300.0

	_wander.seed = SEED + 9001
	_wander.noise_type = FastNoiseLite.TYPE_VALUE
	_wander.fractal_octaves = 2
	_wander.frequency = 1.0 / 90.0

	_bake_reed("res://assets/models/bamboo_a.glb", REED_A_MESH)
	_bake_reed("res://assets/models/bamboo_b.glb", REED_B_MESH)
	for k in PH_BAKES:
		var spec: Array = PH_BAKES[k]
		_bake_photoscan(spec[0], spec[1], spec[2])

	var root := Node3D.new()
	root.name = "RiverVegetation"

	var report: Array = []
	var i: int = 0
	for row in ROWS:
		report.append(_make_row(root, -1.0, "West", row, i))
		report.append(_make_row(root, 1.0, "East", row, i))
		i += 1

	for child in root.get_children():
		child.owner = root
		for grand in child.get_children():
			grand.owner = root

	var packed := PackedScene.new()
	var pack_err: int = packed.pack(root)
	if pack_err != OK:
		push_error("pack failed: %d" % pack_err)
		quit(1)
		return
	var err: int = ResourceSaver.save(packed, OUT_PATH)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return

	var total: int = 0
	for r in report:
		total += int(r["points"])
	print("river_vegetation: %d scatter rows, %d curve points -> %s"
			% [report.size(), total, OUT_PATH])
	# ProtonScatter nodes keep signal connections alive; without an explicit free
	# the headless process never returns from quit().
	root.free()
	quit()
