extends Node3D

## Standalone review stage for the three building proofs.
##
## ⚠ This scene deliberately builds through the **production** path —
## `gen_lib.semantic_mesh()`, the same reader `gen_town._emit_batches()` uses —
## and NOT through `GLTFDocument.generate_scene()`.
##
## It used to use the latter, which instantiates the entire glTF node tree. That
## is precisely why Phase 5A's own review evidence
## (`shots2/asset_building_proof/final/`) showed three complete buildings while
## the village drew a smoke vent, a lattice rail and a cedar ball: the reviewer
## and the player were looking at two different readings of the same file, and
## the reviewer's reading was the forgiving one.
##
## A proof stage that does not exercise the production path proves nothing. If
## `semantic_mesh()` ever regresses to "first MeshInstance3D wins" again, these
## renders break in the same frame the village does.
##
## `tools/asset_dims_check.gd` is the automated half of the same guarantee.

const ASSETS := [
	["SakeShop", "res://assets/models/asset_proof_sake_shop.glb", Vector3(-14, 0, 0)],
	["Hatago", "res://assets/models/asset_proof_hatago.glb", Vector3.ZERO],
	["Workshop", "res://assets/models/asset_proof_workshop.glb", Vector3(14, 0, 0)],
]

func _ready() -> void:
	var lib = preload("res://tools/gen_lib.gd").new()
	for spec: Array in ASSETS:
		var probe: Array = lib.semantic_mesh(String(spec[1]))
		var mesh: Mesh = probe[0] as Mesh
		if mesh == null:
			push_error("GLB carries no mesh: %s" % spec[1])
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = String(spec[0])
		mi.position = spec[2]
		add_child(mi)
		print("PROOF %-10s aabb=%s surfaces=%d mats=%s" % [
			spec[0], str(mesh.get_aabb().size), mesh.get_surface_count(),
			str(probe[1])])
