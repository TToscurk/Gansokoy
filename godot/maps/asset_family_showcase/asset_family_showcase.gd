extends Node3D

const ASSETS := [
	["StandardMachiya", "res://assets/models/family_standard_machiya_04.glb", Vector3(-60, 0, 35)],
	["Nagaya", "res://assets/models/family_nagaya_04bay.glb", Vector3(-20, 0, 35)],
	["Kura", "res://assets/models/family_kura_loading.glb", Vector3(20, 0, 35)],
	["SmallMerchant", "res://assets/models/family_small_merchant_03.glb", Vector3(60, 0, 35)],
]

const LINEUP_ASSETS := [
	["LineupStandard", "res://assets/models/family_standard_machiya_04.glb", Vector3(-31, 0, -24)],
	["LineupNagaya", "res://assets/models/family_nagaya_04bay.glb", Vector3(-14, 0, -24)],
	["LineupKura", "res://assets/models/family_kura_loading.glb", Vector3(4, 0, -24)],
	["LineupMerchant", "res://assets/models/family_small_merchant_03.glb", Vector3(18, 0, -24)],
]


func _ready() -> void:
	for spec: Array in ASSETS:
		_add_asset(spec)
	for spec: Array in LINEUP_ASSETS:
		_add_asset(spec)


func _add_asset(spec: Array) -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(spec[1], state)
	if error != OK:
		push_error("family GLB load failed: %s (%s)" % [spec[1], error])
		return
	var building := document.generate_scene(state)
	building.name = spec[0]
	building.position = spec[2]
	add_child(building)
