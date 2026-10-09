extends Node3D
## P10 R5a Road Base Pilot（overlay `RoadBaseP10`，由 tools/village_v2_road_base_lib.gd 產生）。
## _ready：road_paths の MeshInstance3D の mesh を road_meshes に差し替え（道 3 本＝材質は GroundPilotP10 の pilot shader のまま；
## ROUND 3：＋Terrain/FarmlandTerrain＝踩み固め重み COLOR.r だけ局部修正した同形の mesh）。
## enabled=false → 元の mesh に戻す。元の road_*.res／terrain_farmlandterrain.res は不変（runtime の差し替えだけ）。
@export var road_paths: PackedStringArray = PackedStringArray()
@export var road_meshes: Array[Mesh] = []
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _orig := {}   # MeshInstance3D → 元の mesh
var applied := 0


func _ready() -> void:
	if enabled:
		apply.call_deferred(true)


func apply(on: bool) -> void:
	for mi in _orig.keys():
		if is_instance_valid(mi):
			(mi as MeshInstance3D).mesh = _orig[mi]
	_orig.clear()
	applied = 0
	if not on:
		return
	var par := get_parent()
	for i in road_paths.size():
		var mi := par.get_node_or_null(NodePath(road_paths[i])) as MeshInstance3D
		if mi == null or i >= road_meshes.size() or road_meshes[i] == null:
			continue
		_orig[mi] = mi.mesh
		mi.mesh = road_meshes[i]
		applied += 1
