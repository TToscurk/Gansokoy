extends Node3D
## P10 R5b Water Pilot（overlay `WaterLifeP10`，由 tools/village_v2_water_life_lib.gd 產生）。
## ROUND 3：水車 2＝純動力水車。揚水部材なし（ROUND 1／2 の柄杓の掛け替え・P8 木部の調暗は撤去）。
## P8 の「水車 2 から田へ渡す高架落とし樋」（封存 farmland_p8.scn）は水源のない高架渠道になるので、
##   runtime で可視ノード p8_hide_vis を隠し、碰撞形 p8_hide_col を止める（P8 ファイル不変）。
## enabled=false → 本 overlay を隠し碰撞を止め、P8 の隠したノード／碰撞形を元の状態へ戻す。
@export var p8_supply_path: NodePath
@export var p8_col_path: NodePath
@export var p8_hide_vis: PackedStringArray = PackedStringArray()
@export var p8_hide_col: PackedStringArray = PackedStringArray()
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _prev_vis := {}   # Node3D → 元の visible
var _prev_col := {}   # CollisionShape3D → 元の disabled
var p8_hidden := 0


func _ready() -> void:
	# enabled=false で読み込まれた時も apply(false)（ROUND 2 の修正を継承）
	apply.call_deferred(enabled)


func p8_hide_nodes() -> Array:
	var out := []
	var g := get_parent().get_node_or_null(p8_supply_path)
	if g:
		for nm in p8_hide_vis:
			var n := g.get_node_or_null(NodePath(nm))
			if n is Node3D:
				out.append(n)
	return out


func p8_hide_shapes() -> Array:
	var out := []
	var b := get_parent().get_node_or_null(p8_col_path)
	if b:
		for nm in p8_hide_col:
			var s := b.get_node_or_null(NodePath(nm))
			if s is CollisionShape3D:
				out.append(s)
	return out


func _p8(on: bool) -> void:
	if on:
		if not _prev_vis.is_empty() or not _prev_col.is_empty():
			return
		for n: Node3D in p8_hide_nodes():
			_prev_vis[n] = n.visible
			n.visible = false
		for s: CollisionShape3D in p8_hide_shapes():
			_prev_col[s] = s.disabled
			s.disabled = true
		p8_hidden = _prev_vis.size() + _prev_col.size()
	else:
		for n in _prev_vis.keys():
			if is_instance_valid(n):
				(n as Node3D).visible = _prev_vis[n]
		for s in _prev_col.keys():
			if is_instance_valid(s):
				(s as CollisionShape3D).disabled = _prev_col[s]
		_prev_vis.clear()
		_prev_col.clear()
		p8_hidden = 0


func apply(on: bool) -> void:
	_p8(on)
	for c in get_children():
		if c is Node3D:
			(c as Node3D).visible = on
		for b in c.find_children("*", "CollisionShape3D", true, false):
			(b as CollisionShape3D).disabled = not on
