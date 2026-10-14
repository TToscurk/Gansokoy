extends Node3D
## P13 Wave 7 TASK 2（使用者 2026-10-14 承認）：FarmlandTerrain の「V 形直邊」の局部材質補正 overlay（COLOR.r＋street 重み UV2.y のみ）。
## 根因（W7 実測）：CrossStreetMid の ribbon は道の高さ＋0.10 m の平らな帯で、FarmPath_1 の入口（x≈368–372、z≈−34…−32）では P1 地形の
##   平坦な台座（66 cm）が ribbon の面と 0–2 cm まで寄る → 地形の三角形が ribbon の南縁から 3 m × 1.3 m の楔として顔を出し、
##   踩み固め土（暗い赤褐・碎石粒）が街の路面（淺い米黃・平滑）に突き刺さる＝2 本の直線（面の交線）で囲まれた V。
##   幾何（P1 地形・道路 ribbon・碰撞）は一切触れず、その楔の頂点だけ地形の「街の路面」重み（UV2.y）を足して、顔を出した面が ribbon と同じ路面に見えるようにする。
## 方法：RoadBaseP10 が差し替えた後の FarmlandTerrain.mesh（頂点位置・法線・UV 不変）から、指定頂点の COLOR.r と UV2.y だけを変えた複製 mesh を作って差し替える。
##   enabled=false で差し替え前の mesh に戻る。元の terrain_farmlandterrain.res／road_base_p10.scn は不変。
@export var terrain_path := "Terrain/FarmlandTerrain"
@export var vidx: PackedInt32Array = PackedInt32Array()
@export var vx: PackedFloat32Array = PackedFloat32Array()
@export var vz: PackedFloat32Array = PackedFloat32Array()
@export var new_r: PackedFloat32Array = PackedFloat32Array()
@export var new_street: PackedFloat32Array = PackedFloat32Array()
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _orig_mesh: Mesh = null
var _mi: MeshInstance3D = null
var applied := 0


func _ready() -> void:
	if enabled:
		apply.call_deferred(true)


func apply(on: bool) -> void:
	if _mi != null and is_instance_valid(_mi) and _orig_mesh != null:
		_mi.mesh = _orig_mesh
	_orig_mesh = null
	_mi = null
	applied = 0
	if not on:
		return
	var par := get_parent()
	var mi := par.get_node_or_null(NodePath(terrain_path)) as MeshInstance3D if par != null else null
	if mi == null or not (mi.mesh is ArrayMesh) or vidx.is_empty():
		return
	var src := mi.mesh as ArrayMesh
	var arr := src.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var u2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var xf := mi.global_transform
	# 頂点の位置が記録と違えば（元の mesh が変わった）何もしない
	for k in vidx.size():
		var i := vidx[k]
		if i < 0 or i >= vs.size():
			push_warning("FarmJunctionFixP13: 頂点番号 %d が範囲外" % i)
			return
		var w := xf * vs[i]
		if absf(w.x - vx[k]) > 0.02 or absf(w.z - vz[k]) > 0.02:
			push_warning("FarmJunctionFixP13: 頂点 %d の位置が記録と違う" % i)
			return
	for k in vidx.size():
		var i := vidx[k]
		var c := cs[i]
		cs[i] = Color(new_r[k], c.g, c.b, c.a)
		u2[i] = Vector2(u2[i].x, new_street[k])
	arr[Mesh.ARRAY_COLOR] = cs
	arr[Mesh.ARRAY_TEX_UV2] = u2
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, src.surface_get_format(0))
	m.resource_name = "FarmJunctionFix_FarmlandTerrain"
	m.custom_aabb = src.custom_aabb
	_orig_mesh = mi.mesh
	_mi = mi
	mi.mesh = m
	applied = vidx.size()
