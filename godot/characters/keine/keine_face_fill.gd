extends OmniLight3D
## 慧音專屬臉部補光：跟著 Head 骨、放在臉前上方；只照慧音自己（render layer 11），不投影。
## 起因：太陽高（10:00 仰角 ≈ 68°）且她背對太陽時，臉只剩天空藍光 → 膚色發藍、眼窩一圈暗（實測臉頰 RGB 0.68/0.71/0.82）。
## 夜間（DayNight 非白天）降到 night_scale，避免臉在夜裡發光。

const LAYER_BIT := 1 << 10   # render layer 11

@export var forward := 0.5        # 臉前方距離（m）
@export var up := 0.12            # 高於 Head 骨（m）
@export var day_energy := 0.4
@export var night_scale := 0.3
## 依太陽方向調補光（預設關，慧音／阿求維持原行為）：臉正對太陽時補光降到 lit_floor 倍，背光時全開。
## 避免順光時臉被補到發白、側光時陰影被補平。
@export var sun_aware := false
@export_range(0.0, 1.0) var lit_floor := 0.0

var _sk: Skeleton3D
var _head := -1
var _root: Node3D


func _ready() -> void:
	_root = get_parent() as Node3D
	shadow_enabled = false
	light_cull_mask = LAYER_BIT
	for mi in _root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers |= LAYER_BIT
	_sk = _root.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if _sk != null:
		_head = _sk.find_bone("Head")
	top_level = true


func _process(_dt: float) -> void:
	if _sk == null or _head < 0:
		return
	var hp := _sk.global_transform * _sk.get_bone_global_pose(_head).origin
	var fwd := _root.global_transform.basis.z.normalized()   # 模型正面 +Z
	global_position = hp + fwd * forward + Vector3(0, up, 0)
	var dn: Node = get_node_or_null("/root/DayNight")
	var day := true
	if dn != null and "hour" in dn:
		var h: float = dn.get("hour")
		day = h >= 6.0 and h < 18.0
	# 白天依太陽強度（DayNight：0.35 晨昏〜1.35 正午）縮放，晨昏／陰暗時補光一起變弱；夜間固定 night_scale
	var k := night_scale
	if day:
		k = 1.0
		var sun := get_node_or_null("/root/Main/Sun") as DirectionalLight3D
		if sun != null:
			k = clampf(sun.light_energy / 1.35, 0.4, 1.0)
	if sun_aware and day:
		var s := _find_sun()
		if s != null:
			var to_sun := s.global_transform.basis.z.normalized()      # 方向光朝 -Z 照，+Z＝指向太陽
			var facing := Vector2(fwd.x, fwd.z).normalized().dot(Vector2(to_sun.x, to_sun.z).normalized())
			k *= lerpf(lit_floor, 1.0, clampf(0.5 - 0.5 * facing, 0.0, 1.0))   # 正對 1→lit_floor、側光一半、背光全開
	light_energy = day_energy * k


var _sun: DirectionalLight3D
func _find_sun() -> DirectionalLight3D:
	if is_instance_valid(_sun): return _sun
	_sun = get_node_or_null("/root/Main/Sun") as DirectionalLight3D
	if _sun == null:
		for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			if (n as DirectionalLight3D).visible: _sun = n; break
	return _sun
