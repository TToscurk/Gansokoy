extends SceneTree
## P13 Wave 6 RoadEdgeBlendP13 builder：gen/road_edge_blend_p13.scn を書く。
##   godot --headless --path . --script res://tools/p13/w6/build_w6_road_edge.gd
## 道路リストとパラメータはここが唯一の正（approved pilot の語彙：edge_w／edge_irreg／edge_core／center_patch）。
const SCRIPT := "res://maps/village_v2/scripts_p13/road_edge_blend.gd"
const SHADER := "res://maps/village_v2/shaders_p10/ground_p10_pilot.gdshader"
const OUT_SCENE := "res://maps/village_v2/gen/road_edge_blend_p13.scn"

## [path, params]。FarmPath 系は FarmPath_1／4 と同じ、その他は CrossStreetSouth／RiversidePath の語彙。
const ROADS := [
	["Roads/SecondaryRoads/CrossStreetMid", {"edge_w": 0.55, "edge_irreg": 0.30, "edge_core": 0.35, "center_patch": 0.0}],
	["Roads/SecondaryRoads/HillFootStreet", {"edge_w": 0.55, "edge_irreg": 0.30, "edge_core": 0.35, "center_patch": 0.0}],
	["Roads/SecondaryRoads/RiverNorthPath", {"edge_w": 0.55, "edge_irreg": 0.30, "edge_core": 0.35, "center_patch": 0.0}],
	["Roads/MainStreet/EntranceRoad", {"edge_w": 0.55, "edge_irreg": 0.30, "edge_core": 0.35, "center_patch": 0.0}],
	["Roads/FarmPaths/FarmPath_2", {"edge_w": 0.40, "edge_irreg": 0.26, "edge_core": 0.35, "center_patch": 0.35}],
	["Roads/FarmPaths/FarmPath_3", {"edge_w": 0.40, "edge_irreg": 0.26, "edge_core": 0.35, "center_patch": 0.35}],
	["Roads/FarmPaths/FarmPath_5", {"edge_w": 0.40, "edge_irreg": 0.26, "edge_core": 0.35, "center_patch": 0.35}],
]


func _init() -> void:
	var node := Node3D.new()
	node.name = "RoadEdgeBlendP13"
	node.set_script(load(SCRIPT))
	node.set("pilot_shader", load(SHADER))
	var paths := PackedStringArray()
	var prm: Array[Dictionary] = []
	for r: Array in ROADS:
		paths.append(r[0])
		prm.append(r[1])
	node.set("road_paths", paths)
	node.set("road_params", prm)
	var ps := PackedScene.new()
	ps.pack(node)
	var err := ResourceSaver.save(ps, OUT_SCENE)
	print("[W6E] saved ", OUT_SCENE, " err=", err, " roads=", paths.size())
	quit(0)
