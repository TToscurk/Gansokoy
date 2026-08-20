extends Node
## Body bone → Haori anchor 跟隨（不複製人體骨架、不做物理）。
## anchor 對應：Haori_Root←Spine、Haori_Waist←Hips、
## Haori_Sleeve_L_01←LeftArm、Haori_Sleeve_R_01←RightArm。
## 其餘羽織骨保持 rest local，剛性跟著父骨走。
## offset 在 rest pose 下取樣，之後每幀 body skeleton 更新後套用。

const MAPPINGS := {
	"Haori_Root": "Spine",
	"Haori_Waist": "Hips",
	"Haori_Sleeve_L_01": "LeftArm",
	"Haori_Sleeve_R_01": "RightArm",
}

var _bskel: Skeleton3D
var _hskel: Skeleton3D
var _pairs: Array = []   # [haori_idx, body_idx, Transform3D offset]，依 haori 骨階層排序

func _ready() -> void:
	var chr := get_parent()
	for s in chr.find_children("*", "Skeleton3D", true, false):
		var sk := s as Skeleton3D
		if sk.find_bone("Haori_Root") != -1:
			_hskel = sk
		elif sk.find_bone("Hips") != -1:
			_bskel = sk
	if _bskel == null or _hskel == null:
		push_error("haori_follow: skeletons not found")
		return
	for hname in MAPPINGS:
		var hi := _hskel.find_bone(hname)
		var bi := _bskel.find_bone(MAPPINGS[hname])
		if hi == -1 or bi == -1:
			push_error("haori_follow: missing bone %s / %s" % [hname, MAPPINGS[hname]])
			continue
		var t_b: Transform3D = _bskel.global_transform * _bskel.get_bone_global_rest(bi)
		var t_h: Transform3D = _hskel.global_transform * _hskel.get_bone_global_rest(hi)
		_pairs.append([hi, bi, t_b.affine_inverse() * t_h])
	_pairs.sort_custom(func(a, b): return a[0] < b[0])
	_bskel.skeleton_updated.connect(_on_body_updated)
	print("haori_follow: coupled ", _pairs.size(), " anchors")

func _on_body_updated() -> void:
	for p in _pairs:
		var hi: int = p[0]
		var bi: int = p[1]
		var off: Transform3D = p[2]
		var target_world: Transform3D = _bskel.global_transform * _bskel.get_bone_global_pose(bi) * off
		var hg: Transform3D = _hskel.global_transform.affine_inverse() * target_world
		var parent := _hskel.get_bone_parent(hi)
		var local: Transform3D = hg if parent < 0 else _hskel.get_bone_global_pose(parent).affine_inverse() * hg
		_hskel.set_bone_pose_position(hi, local.origin)
		_hskel.set_bone_pose_rotation(hi, local.basis.get_rotation_quaternion())
