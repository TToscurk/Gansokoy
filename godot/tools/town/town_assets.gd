extends RefCounted

## Module declarations that are not yet part of town_modules.json.
## Measured dimensions are guarded by tools/asset_dims_check.gd.
const PHASE5A_FAMILIES := {
	"family_standard_machiya_02": {"w": 9.56, "d": 11.60, "h": 5.42, "fw": 9.56, "fd": 11.60, "glb": "res://assets/models/family_standard_machiya_02.glb"},
	"family_standard_machiya_03": {"w": 7.96, "d": 12.61, "h": 5.72, "fw": 7.96, "fd": 12.61, "glb": "res://assets/models/family_standard_machiya_03.glb"},
	"family_small_merchant_01": {"w": 7.16, "d": 9.70, "h": 4.87, "fw": 7.16, "fd": 9.70, "glb": "res://assets/models/family_small_merchant_01.glb"},
	"family_small_merchant_03": {"w": 10.74, "d": 11.70, "h": 4.62, "fw": 10.74, "fd": 11.70, "glb": "res://assets/models/family_small_merchant_03.glb"},
	"family_kura_compact": {"w": 7.30, "d": 8.09, "h": 5.95, "fw": 7.30, "fd": 8.09, "glb": "res://assets/models/family_kura_compact.glb"},
	# These sizes are measured from the Godot AABB of each joined mesh. Never
	# edit them by hand: re-measure and update the asset dimension gate instead.
	"asset_proof_hatago": {"w": 9.90, "d": 13.20, "h": 7.30, "fw": 9.90, "fd": 13.20, "centered": true, "glb": "res://assets/models/asset_proof_hatago.glb"},
	"asset_proof_sake_shop": {"w": 13.20, "d": 9.36, "h": 5.30, "fw": 13.20, "fd": 9.36, "centered": true, "glb": "res://assets/models/asset_proof_sake_shop.glb"},
	"asset_proof_workshop": {"w": 11.11, "d": 9.88, "h": 6.49, "fw": 11.11, "fd": 9.88, "centered": true, "glb": "res://assets/models/asset_proof_workshop.glb"},
}
