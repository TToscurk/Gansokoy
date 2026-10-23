class_name IsshinHipTwist
extends SkeletonModifier3D
## 斜向移動時「腿朝移動方向、上半身面向敵人」，以及待機時上半身先轉向敵人（腳不動）。
## 骨盆繞垂直軸轉 hip_yaw；脊椎三節反向補償，使胸口的淨偏航 = chest_yaw（相對 actor）。
## 偏航採 Godot 慣例：+ = 角色向左轉（繞 +Y）。必須排在 SpringBoneSimulator3D 之前（Skeleton3D 的第一個子節點）。
var hip_yaw := 0.0
var chest_yaw := 0.0
const SPINE := ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]
const SHARE := [0.34, 0.33, 0.33]
var _ix := {}

func _bone(n: String) -> int:
	if not _ix.has(n):
		_ix[n] = get_skeleton().find_bone(n)
	return _ix[n]

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or (absf(hip_yaw) < 1e-4 and absf(chest_yaw) < 1e-4):
		return
	var h := _bone("mixamorig_Hips")
	if absf(hip_yaw) > 1e-4:
		var hp := sk.get_bone_pose(h)
		hp.basis = Basis(Vector3.UP, hip_yaw) * hp.basis
		sk.set_bone_pose(h, hp)
	var net := chest_yaw - hip_yaw
	if absf(net) < 1e-4:
		return
	for i in SPINE.size():
		var b := _bone(SPINE[i])
		var par := sk.get_bone_parent(b)
		var pg := sk.get_bone_global_pose(par)
		var g := pg * sk.get_bone_pose(b)
		var ng := Transform3D(Basis(Vector3.UP, net * SHARE[i]) * g.basis, g.origin)
		var local := pg.affine_inverse() * ng
		sk.set_bone_pose_rotation(b, local.basis.get_rotation_quaternion())
