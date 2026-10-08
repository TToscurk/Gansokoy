extends Node3D
## P10 R5b Water Logic Pilot（overlay `WaterLifeP10`，由 tools/village_v2_water_life_lib.gd 產生）。
## _ready：把柄杓（LiftBuckets）掛到水車 2 的轉子（Hero/Wheel）下，隨輪轉；enabled=false → 取下柄杓、隱藏本 overlay 全部內容。
@export var rotor_path: NodePath
@export var buckets_path: NodePath
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _bk: Node3D
var _home: Node3D
var attached := false


func _ready() -> void:
	_bk = get_node_or_null(buckets_path) as Node3D
	if _bk:
		_home = _bk.get_parent() as Node3D
	if enabled:
		apply.call_deferred(true)


func apply(on: bool) -> void:
	for c in get_children():
		if c is Node3D:
			(c as Node3D).visible = on
		for b in c.find_children("*", "CollisionShape3D", true, false):
			(b as CollisionShape3D).disabled = not on
	if _bk == null:
		return
	var rotor := get_parent().get_node_or_null(rotor_path) as Node3D
	if on and rotor:
		if _bk.get_parent() != rotor:
			_bk.reparent(rotor, false)
		_bk.transform = Transform3D.IDENTITY
		_bk.visible = true
		attached = true
	else:
		if _home and _bk.get_parent() != _home:
			_bk.reparent(_home, false)
		_bk.transform = Transform3D(Basis(), Vector3(1.6, 2.65, 0.0))
		_bk.visible = false
		attached = false
