extends Node3D
## P13 Wave 6 DrapeFixP13（overlay `DrapeFixP13`，由 tools/p13/w6/build_w6_drape_fix.gd 產生）。
##
## 根因：地面 overlay（Vegetation/*/Ground*）只在「頂點」取地形高度再 +1.6 cm 貼地；三角形內部會因為地形自己的
## 三角剖分不同而沈到地形面之下（實測最深 25.6 cm），於是下方的地形材質（坡面岩層的淡灰）從 overlay 的三角形內
## 戳出來，成為淡色三角形／碎片（P13 backlog #1「淡色の地面碎塊」）。
##
## 修正：把這些 overlay 網格的頂點「只往上」抬到剛好讓三角形內所有取樣點都不低於可見地形（拓樸／UV／色／法線不變，
## 只改 y）。原 .scn／.res 一字不改（封存雜湊不動）——這裡只在執行期把 MeshInstance3D.mesh 換成修正過的副本，
## enabled=false 即還原。與 RoadBaseP10 同一做法。
@export var paths: PackedStringArray = PackedStringArray()
@export var meshes: Array[Mesh] = []
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _orig := {}     # MeshInstance3D → 元の mesh
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
	for i in paths.size():
		var mi := par.get_node_or_null(NodePath(paths[i])) as MeshInstance3D
		if mi == null or i >= meshes.size() or meshes[i] == null:
			continue
		_orig[mi] = mi.mesh
		mi.mesh = meshes[i]
		applied += 1
