extends SceneTree

## Declared-vs-measured building dimension gate.
##
## Why this exists
## ---------------
## Phase 5A shipped three **invisible buildings with invisible colliders** and
## every static gate passed. The mechanism:
##
##   * `make_building_asset_proof.py` exported each building as dozens of loose
##     glTF nodes instead of one joined mesh;
##   * `gen_lib.semantic_mesh()` / `prop_mesh()` take the FIRST MeshInstance3D
##     in the imported scene and stop, so Godot only ever saw one sub-part
##     (a smoke vent, a lattice rail, a cedar ball);
##   * every downstream consumer — OBB overlap, collision boxes, spacing —
##     reads `w`/`d`/`h` from a **hand-written table**, never from the mesh.
##
## So the table said 11.30 × 9.60 × 6.45 and the engine drew 1.40 × 0.55 × 0.10,
## and nothing in the suite was in a position to notice. `art-review.md` already
## states the rule that was broken: *measure the artifact, not the parameter.*
##
## This gate closes that loop. It loads every module the village generator can
## instance, measures the mesh the engine will actually draw — via the same
## `semantic_mesh()` path the generator uses, so a reader bug shows up here too
## — and compares it against the declared frontage / depth / height.
##
## Tolerance
## ---------
## TOL_M = 0.05 m. The kit's own numbers are produced by measuring the exported
## bbox, so they agree to ~0.01 m; 0.05 m absorbs float and glTF quantisation
## without letting a real mismatch through. It is an absolute tolerance on
## purpose — a relative one would forgive metres on a large building, which is
## exactly the failure this gate exists to catch.
##
## Compared against `fw` / `fd` (frontage bbox **including roof overhang**), not
## `w` / `d`. For the machiya kit those differ by design: `w`/`d` are the core
## volume used for the collision box, `fw`/`fd` are the measured bbox. The mesh
## AABB is the bbox, so `fw`/`fd` are the honest comparison.
##
## Run: godot --headless --path godot --script tools/asset_dims_check.gd

const MODULES := "res://data/town_modules.json"
const TOL_M := 0.05

## Frontage/depth is checked for **every** module — that is the axis on which
## the "one arbitrary sub-part" defect shows up, whatever the module is.
##
## Height is checked for buildings only. `bridge` / `tower` / `landmark`
## deliberately declare a *functional* height rather than a bbox height
## (bridge_main h=2.89 is the deck-and-rail a walker meets; the mesh reaches
## 7.09 because the piers hang below y=0), so comparing those against the AABB
## would be comparing two different quantities and would train people to
## ignore this gate.
const BUILDING_KINDS := ["machiya"]

## Documented exemptions from the "a building must carry semantic surfaces"
## rule. These four are the legacy blockouts: single-surface, no albedo, kept
## on purpose and instanced in no map (PROJECT_STATE, Explicit Do-Not-Reopen).
## They are exempt from the surface rule, never from the dimension rule.
const LEGACY_ONE_SURFACE := ["machiya_e_a", "machiya_f_b", "machiya_b_a",
	"machiya_b_b"]

func _init() -> void:
	var lib = preload("res://tools/gen_lib.gd").new()
	var gen := load("res://tools/gen_town.gd")

	var f := FileAccess.open(MODULES, FileAccess.READ)
	if f == null:
		push_error("讀不到 %s —— 先跑 make_town.py" % MODULES)
		quit(1)
		return
	var mods: Dictionary = JSON.parse_string(f.get_as_text())["modules"]
	f.close()
	# The Phase 5A / 5A-V families live in the generator, not in the json the
	# Blender kit writes. Both populations must be gated, or the half that is
	# hand-declared stays exactly as unprotected as it was.
	for family in gen.PHASE5A_FAMILIES:
		mods[family] = gen.PHASE5A_FAMILIES[family]

	var names: Array = mods.keys()
	names.sort()
	var bad := 0
	var checked := 0
	print("\n──── 建物モジュールの宣言寸法 vs 実測 mesh（tol %.2fm）────" % TOL_M)
	for kind in names:
		var m: Dictionary = mods[kind]
		var glb := String(m.get("glb", ""))
		if glb == "":
			continue
		if not ResourceLoader.exists(glb):
			print("  ✗ %-30s glb が無い：%s" % [kind, glb])
			bad += 1
			continue
		var packed: PackedScene = load(glb) as PackedScene
		if packed == null:
			print("  ✗ %-30s glb が PackedScene として読めない：%s" % [kind, glb])
			bad += 1
			continue
		# Deliberately the same reader the generator uses: if semantic_mesh()
		# ever regresses to returning one sub-part again, this gate fails too.
		var probe: Array = lib.semantic_mesh(glb)
		var mesh: Mesh = probe[0] as Mesh
		if mesh == null:
			print("  ✗ %-30s glb に MeshInstance3D が無い：%s" % [kind, glb])
			bad += 1
			continue
		var size: Vector3 = mesh.get_aabb().size
		var is_building: bool = String(m.get("kind", "")) in BUILDING_KINDS \
			or gen.PHASE5A_FAMILIES.has(kind)
		var want := Vector3(float(m.get("fw", m.get("w", 0.0))),
			float(m.get("h", 0.0)),
			float(m.get("fd", m.get("d", 0.0))))
		var worst: float = maxf(absf(size.x - want.x), absf(size.z - want.z))
		if is_building:
			worst = maxf(worst, absf(size.y - want.y))
		checked += 1
		if worst > TOL_M:
			print("  ✗ %-30s 宣言 %.2f×%.2f×%.2f　実測 %.2f×%.2f×%.2f　差 %.2fm"
				% [kind, want.x, want.y, want.z, size.x, size.y, size.z, worst])
			bad += 1
		elif is_building and not (kind in LEGACY_ONE_SURFACE) \
				and mesh.get_surface_count() < 2:
			# A whole building collapsing to one surface is the same defect one
			# step earlier: it is what a "first sub-part only" read looks like
			# before the sizes drift far enough to trip the tolerance.
			print("  ⚠ %-30s 寸法は合うが surface が 1 枚（語意材質が死んでいる）"
				% kind)
			bad += 1
		else:
			print("  ✓ %-30s %.2f×%.2f×%.2f　%d surface（差 %.3fm%s）"
				% [kind, size.x, size.y, size.z, mesh.get_surface_count(), worst,
					"" if is_building else "・高さは機能値なので対象外"])

	if bad == 0:
		print("\n══ 資産寸法検査：%d モジュール、0 項不符 ✓ ══\n" % checked)
		quit(0)
	else:
		print("\n══ 資産寸法検査：%d モジュール中 %d 項が不符 ✗ ══" % [checked, bad])
		push_error("asset dimension mismatch: %d module(s)" % bad)
		quit(1)
