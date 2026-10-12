extends Node3D
## P13 W1／W1B Architecture Pilot（overlay `ArchPilotP13`、tools/village_v2_arch_pilot_lib.gd が生成）。
## ON：targets の元 Kit と hide_nodes（MKT_010 の店前踏段など）を隠し、子の Pilot Kit と農家預覽を見せる。
## OFF：最初に記録した元の visible に戻す（何度切替えても元状態は 1 回だけ記録）。碰撞・棟ノードは変更しない。
@export var targets: PackedStringArray = PackedStringArray()
@export var hide_nodes: PackedStringArray = PackedStringArray()
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _orig := {}   # 絶対パス → 元 visible


func _ready() -> void:
	apply.call_deferred(enabled)


func _nodes() -> Array:
	var par := get_parent()
	var out: Array = []
	for p in targets:
		var b := par.get_node_or_null(NodePath(p))
		if b != null and b.get_node_or_null("Kit") is Node3D:
			out.append(b.get_node("Kit"))
	for p in hide_nodes:
		var n := par.get_node_or_null(NodePath(p))
		if n is Node3D:
			out.append(n)
	return out


func apply(on: bool) -> void:
	for n: Node3D in _nodes():
		var k := String(n.get_path())
		if not _orig.has(k):
			_orig[k] = n.visible
		n.visible = false if on else bool(_orig[k])
	for c in get_children():
		(c as Node3D).visible = on


func _exit_tree() -> void:
	if not _orig.is_empty():
		apply(false)
