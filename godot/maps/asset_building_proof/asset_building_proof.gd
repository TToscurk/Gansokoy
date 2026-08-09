extends Node3D

const ASSETS := [
	["SakeShop", "res://assets/models/asset_proof_sake_shop.glb", Vector3(-14, 0, 0)],
	["Hatago", "res://assets/models/asset_proof_hatago.glb", Vector3.ZERO],
	["Workshop", "res://assets/models/asset_proof_workshop.glb", Vector3(14, 0, 0)],
]

func _ready() -> void:
	for spec: Array in ASSETS:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_file(spec[1], state)
		if error != OK:
			push_error("GLB load failed: %s (%s)" % [spec[1], error])
			continue
		var building := document.generate_scene(state)
		building.name = spec[0]
		building.position = spec[2]
		add_child(building)
