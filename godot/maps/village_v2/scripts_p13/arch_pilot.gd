extends Node3D
## P13 W1 Architecture Pilot（overlay `ArchPilotP13`、tools/village_v2_arch_pilot_lib.gd が生成）。
## _ready：targets（village 根からの相対パス）の棟の元 Kit を隠し、子の Pilot Kit を見せる。enabled=false で元の状態へ完全に戻る。
## 碰撞（P4 BoxShape）・門前帶（Frontage）・棟ノードは一切変更しない。
@export var targets: PackedStringArray = PackedStringArray()
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)


func _ready() -> void:
	apply.call_deferred(enabled)


func apply(on: bool) -> void:
	var par := get_parent()
	for p in targets:
		var b := par.get_node_or_null(NodePath(p))
		if b == null:
			continue
		var k := b.get_node_or_null("Kit") as Node3D
		if k != null:
			k.visible = not on
	for c in get_children():
		(c as Node3D).visible = on
