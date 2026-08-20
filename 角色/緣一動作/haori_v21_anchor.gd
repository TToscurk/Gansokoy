extends SkeletonModifier3D
## Haori v2.1 anchor 跟隨：Body bone → Haori anchor（rest-space offset）。
## 必須是 Haori Skeleton3D 的第一個 modifier 子節點，
## SpringBoneSimulator3D 排在其後 → anchor 更新保證發生在 spring 之前。

const MAPPINGS := {
	"Haori_Root": "Spine",
	"Haori_Shoulder_L": "LeftShoulder",
	"Haori_Shoulder_R": "RightShoulder",
	"Haori_Waist": "Hips",
	"Haori_SleeveUpper_L": "LeftArm",
	"Haori_SleeveUpper_R": "RightArm",
	"Haori_Col_ForeArm_L": "LeftForeArm",
	"Haori_Col_ForeArm_R": "RightForeArm",
	"Haori_Col_Thigh_L": "LeftUpLeg",
	"Haori_Col_Thigh_R": "RightUpLeg",
}

var body_skel: Skeleton3D
var _pairs: Array = []

func setup(p_body: Skeleton3D) -> void:
	body_skel = p_body

func _ensure_pairs() -> void:
	if not _pairs.is_empty() or body_skel == null:
		return
	var hskel := get_skeleton()
	for hname in MAPPINGS:
		var hi := hskel.find_bone(hname)
		var bi := body_skel.find_bone(MAPPINGS[hname])
		if hi == -1 or bi == -1:
			push_error("haori_v21_anchor: missing %s/%s" % [hname, MAPPINGS[hname]])
			continue
		var t_b: Transform3D = body_skel.global_transform * body_skel.get_bone_global_rest(bi)
		var t_h: Transform3D = hskel.global_transform * hskel.get_bone_global_rest(hi)
		_pairs.append([hi, bi, t_b.affine_inverse() * t_h])
	_pairs.sort_custom(func(a, b): return a[0] < b[0])
	print("haori_v21_anchor: coupled ", _pairs.size(), " anchors")

func _process_modification() -> void:
	if body_skel == null:
		return
	_ensure_pairs()
	var hskel := get_skeleton()
	var inv_h: Transform3D = hskel.global_transform.affine_inverse()
	for p in _pairs:
		var hi: int = p[0]
		var bi: int = p[1]
		var off: Transform3D = p[2]
		var target: Transform3D = inv_h * (body_skel.global_transform * body_skel.get_bone_global_pose(bi) * off)
		var parent := hskel.get_bone_parent(hi)
		var local: Transform3D = target if parent < 0 else hskel.get_bone_global_pose(parent).affine_inverse() * target
		hskel.set_bone_pose_position(hi, local.origin)
		hskel.set_bone_pose_rotation(hi, local.basis.get_rotation_quaternion())
