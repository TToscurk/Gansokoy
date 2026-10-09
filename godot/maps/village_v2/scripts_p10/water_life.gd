extends Node3D
## P10 R5b Water Logic Pilot（overlay `WaterLifeP10`，由 tools/village_v2_water_life_lib.gd 產生）。
## _ready：把柄杓（LiftBuckets）掛到水車 2 的轉子（Hero/Wheel）下，隨輪轉；enabled=false → 取下柄杓、隱藏本 overlay 全部內容。
## ROUND 2：P8 落とし樋（WaterSupply）の木部は頂点色なし＝水車の輪（頂点色 0.61）より 1.6 倍明るく「白い縦材」に見える
##   → 木部だけ material_override で輪と同じ明度へ（P8 のファイルは不変、enabled=false で元の override に戻す）。
@export var rotor_path: NodePath
@export var buckets_path: NodePath
@export var p8_supply_path: NodePath
@export var p8_tone := 0.62
@export var p8_near: PackedVector3Array   # 水車 2 の落とし樋の中心線（世界）：この近く（水平 p8_near_r 以内）の木部だけ
@export var p8_near_r := 1.2
@export var enabled := true:
	set(v):
		enabled = v
		if is_inside_tree():
			apply(v)

var _bk: Node3D
var _home: Node3D
var attached := false
var _p8_prev := {}     # MeshInstance3D → 元の material_override
var p8_toned := 0


func _ready() -> void:
	_bk = get_node_or_null(buckets_path) as Node3D
	if _bk:
		_home = _bk.get_parent() as Node3D
	# ROUND 2：enabled=false で読み込まれた時も apply(false)（架台・受け樋・水・舟を隠し碰撞を止める）。
	apply.call_deferred(enabled)


## P8 落とし樋の木部（水面 Water・落とし桝の石を除く）
func p8_wood_nodes() -> Array:
	var out := []
	var g := get_parent().get_node_or_null(p8_supply_path)
	if g == null:
		return out
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name == "Water" or String(m.get_parent().name) == "DropBox":
			continue
		if not _near_chute(m.global_position):
			continue
		var mat := m.get_active_material(0)
		if mat is StandardMaterial3D:
			out.append(m)
	return out


func _near_chute(p: Vector3) -> bool:
	for i in p8_near.size() - 1:
		var a := Vector2(p8_near[i].x, p8_near[i].z)
		var b := Vector2(p8_near[i + 1].x, p8_near[i + 1].z)
		var q := Vector2(p.x, p.z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		if q.distance_to(a + ab * t) <= p8_near_r:
			return true
	return false


func _tone_p8(on: bool) -> void:
	if on:
		if not _p8_prev.is_empty():
			return
		var cache := {}
		for m: MeshInstance3D in p8_wood_nodes():
			var src := m.get_active_material(0) as StandardMaterial3D
			if not cache.has(src):
				var d := src.duplicate() as StandardMaterial3D
				d.albedo_color = Color(src.albedo_color.r * p8_tone, src.albedo_color.g * p8_tone, src.albedo_color.b * p8_tone, src.albedo_color.a)
				d.resource_name = "P10_WLF_P8WoodTone"
				cache[src] = d
			_p8_prev[m] = m.material_override
			m.material_override = cache[src]
		p8_toned = _p8_prev.size()
	else:
		for m in _p8_prev.keys():
			if is_instance_valid(m):
				(m as MeshInstance3D).material_override = _p8_prev[m]
		_p8_prev.clear()
		p8_toned = 0


func apply(on: bool) -> void:
	_tone_p8(on)
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
