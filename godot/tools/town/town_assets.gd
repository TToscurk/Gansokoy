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

const MAT_TONES := {
	# 真壁填充要亮，木框才會跳出來；瓦片則維持乾淨的藍灰。
	"plaster": [Color(1.30, 1.28, 1.22), Color(1.16, 1.13, 1.06),
		Color(1.05, 1.04, 1.00), Color(1.22, 1.17, 1.09)],
	"kawara": [Color(0.86, 0.94, 1.10), Color(0.72, 0.80, 0.96),
		Color(0.80, 0.86, 1.00), Color(0.64, 0.72, 0.88)],
	"thatch": [Color(0.66, 0.54, 0.36), Color(0.58, 0.47, 0.31),
		Color(0.72, 0.60, 0.40), Color(0.50, 0.42, 0.30)],
	"mud": [Color(0.80, 0.72, 0.58), Color(0.70, 0.62, 0.48),
		Color(0.86, 0.78, 0.64), Color(0.64, 0.58, 0.46)],
	# dark_wood 貼圖本身偏紅，木部色調要壓紅並轉成曬灰的褐色。
	"dark": [Color(0.44, 0.47, 0.45), Color(0.37, 0.40, 0.39),
		Color(0.52, 0.53, 0.50), Color(0.32, 0.35, 0.35)],
	"wood": [Color(0.72, 0.66, 0.58), Color(0.62, 0.56, 0.48),
		Color(0.80, 0.72, 0.62), Color(0.56, 0.51, 0.45)],
	"stone": [Color(1.00, 1.00, 1.00), Color(0.90, 0.90, 0.88),
		Color(0.82, 0.84, 0.82), Color(0.95, 0.93, 0.88)],
	"namako": [Color(1.00, 1.00, 1.00), Color(0.88, 0.90, 0.92),
		Color(0.94, 0.93, 0.90), Color(0.80, 0.83, 0.86)],
	"lattice": [Color(1.00, 0.98, 0.95), Color(0.88, 0.86, 0.84),
		Color(0.78, 0.76, 0.74), Color(0.94, 0.90, 0.86)],
	"gravel": [Color(1.00, 1.00, 1.00), Color(0.92, 0.94, 0.96),
		Color(0.88, 0.86, 0.82), Color(0.80, 0.83, 0.85)],
	# 河石是中灰，不是白色；四個色調避免一堆石頭像同一塊。
	"cobble": [Color(0.60, 0.61, 0.60), Color(0.50, 0.48, 0.45),
		Color(0.66, 0.63, 0.57), Color(0.42, 0.45, 0.48)],
	"foliage": [Color(1.00, 1.00, 1.00), Color(0.86, 0.94, 0.82),
		Color(0.74, 0.84, 0.70), Color(0.94, 0.90, 0.72)],
	"flag": [Color(1.00, 1.00, 1.00), Color(0.90, 0.90, 0.88),
		Color(0.82, 0.84, 0.86), Color(0.94, 0.91, 0.86)],
	"shoji": [Color(1.00, 1.00, 1.00), Color(0.96, 0.94, 0.90),
		Color(1.00, 0.98, 0.92), Color(0.92, 0.90, 0.86)],
	"tatami": [Color(1.00, 1.00, 1.00), Color(0.92, 0.94, 0.86),
		Color(0.86, 0.88, 0.80), Color(0.96, 0.92, 0.82)],
	"shitami": [Color(1.00, 0.98, 0.95), Color(0.86, 0.84, 0.80),
		Color(0.74, 0.72, 0.68), Color(0.92, 0.88, 0.82)],
	"yakisugi": [Color(1.00, 1.00, 1.00), Color(0.86, 0.86, 0.88),
		Color(1.12, 1.08, 1.04), Color(0.78, 0.79, 0.80)],
	"ishizumi": [Color(1.00, 1.00, 1.00), Color(0.90, 0.91, 0.90),
		Color(0.82, 0.84, 0.82), Color(0.95, 0.92, 0.86)],
}

const MAT_SET := {
	"kawara": ["roof_kawara", 0.22],
	# 茅葺使用真正的 roof_thatch，不再借用地形草貼圖。
	"thatch": ["roof_thatch", 0.55],
	"plaster": ["plaster", 0.4], "mud": ["arakabe", 0.42],
	"dark": ["dark_wood", 0.45], "wood": ["planks", 0.5], "stone": ["stone_wall", 0.30],
	"namako": ["namako", 0.30],
	"lattice": ["wood_lattice", 0.28],
	# gravel 是整片小石子地；cobble 是單顆玉石，不能共用貼圖比例。
	"gravel": ["pebble", 0.5],
	"cobble": ["stone_wall", 0.85],
	"foliage": ["foliage", 0.42], "flag": ["stone_flag", 0.30],
	"shoji": ["shoji", 0.30], "tatami": ["tatami", 0.42],
	"shitami": ["shitami", 0.34], "yakisugi": ["yakisugi", 0.36],
	"ishizumi": ["ishizumi", 0.30],
}


static func material(lib, rng: RandomNumberGenerator, key: String,
		v := -1) -> StandardMaterial3D:
	if not MAT_SET.has(key):
		key = "plaster"
	var tones: Array = MAT_TONES[key]
	if v < 0:
		v = int(rng.randf() * float(tones.size()))
	v = v % tones.size()
	var spec: Array = MAT_SET[key]
	return lib.pbr("%s_%d" % [key, v], String(spec[0]), float(spec[1]), tones[v])


static func sakura_mesh(lib, glb: String) -> Mesh:
	var packed: PackedScene = load(glb)
	var node: Node = packed.instantiate()
	var mesh: Mesh = null
	var stack: Array[Node] = [node]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for child in n.get_children():
			stack.push_back(child)
		if n is MeshInstance3D:
			mesh = n.mesh
			break
	node.free()
	var petal = lib.foliage_vc_mat()
	if mesh.get_surface_count() >= 2:
		mesh.surface_set_material(0, lib.pbr("bark", "bark_cedar", 0.7))
		for surface in range(1, mesh.get_surface_count()):
			mesh.surface_set_material(surface, petal)
	else:
		mesh.surface_set_material(0, petal)
	return mesh


static func village_tree_mesh(lib, glb_path: String,
		canopy: StandardMaterial3D) -> Mesh:
	var mesh: Mesh = lib.tree_mesh(glb_path).duplicate(true) as Mesh
	if mesh.get_surface_count() >= 2:
		for surface in range(1, mesh.get_surface_count()):
			mesh.surface_set_material(surface, canopy)
	return mesh
