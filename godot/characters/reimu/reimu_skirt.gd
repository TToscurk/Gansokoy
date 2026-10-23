extends Node3D
## 靈夢的袴：骨鏈（SpringBoneSimulator3D）。16 條裙擺鏈 Skirt_00 … Skirt_15，每條 3 節（Skirt_xx_1 → _3，父骨 Hips），
## 袴網格是 Blender 刷好的蒙皮。2026-10-20 使用者裁定：放棄 Jolt SoftBody 布料，改用骨鏈。
## 做法同緣一 V2.4（characters/yoriichi/v24/yoriichi_v24_rig.gd）：彈簧骨鏈＋身體碰撞膠囊。
## - 鏈：reimu_skirt_chains.json（各關節靜止位置；最後一點＝末節尾端，用來算 end_bone_length）。
## - 碰撞：大腿／小腿膠囊（reimu_colliders.json 半徑＋leg_margin）＋骨盆橫向膠囊（擋裙擺往內塌）。
## - 動作照常由 AnimationPlayer（keine_visual.gd）播；裙擺骨沒有動畫軌，彈簧回到靜止姿勢。

const HUMANOID := {"UpLeg": "UpperLeg", "Leg": "LowerLeg", "Spine1": "Chest", "Spine2": "UpperChest"}

@export var data_prefix := "res://characters/reimu/reimu"
@export var springs_enabled := true:
	set(v):
		springs_enabled = v
		if _sim: _sim.active = v
## 回彈力（越大越硬、越貼靜止形）。
@export_range(0.0, 20.0) var stiffness := 2.0
## 阻尼（0～1，越大越不晃）。
@export_range(0.0, 1.0) var drag := 0.6
## 重力（越大下襬越往下垂）。
@export_range(0.0, 5.0) var gravity := 0.3
## 末節（下襬）比根部軟多少：stiffness 沿鏈線性降到 stiffness × tip_softness。
@export_range(0.1, 1.0) var tip_softness := 0.6
## 關節碰撞半徑（公尺）。
@export_range(0.0, 0.1) var joint_radius := 0.03
## 腿膠囊額外加厚（公尺）：關節之間的布不參與碰撞，加厚讓腿在碰到中段布之前就把關節推開。
@export_range(0.0, 0.15) var leg_margin := 0.05
## 骨盆膠囊（橫向，跟 Hips）：半徑、左右長度（公尺）。0＝不用。
@export_range(0.0, 0.2) var hip_radius := 0.09
@export_range(0.0, 0.4) var hip_width := 0.16
@export var skirt_mesh_name := "袴"
@export var model_path := NodePath("../Model")

var skel: Skeleton3D
var _sim: SpringBoneSimulator3D
var _caps := []            # [SpringBoneCollisionCapsule3D, bone_a, bone_b, 原始半徑]（量測工具用）
var _chains := []          # [{bones:[idx...]}]


func _ready() -> void:
	var model := get_node_or_null(model_path)
	if model == null:
		push_error("ReimuSkirt：找不到 Model"); return
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	_build()


func _bone(n: String) -> int:
	for c in [n, n.replace(":", "_"), n.split(":")[-1]]:
		var i := skel.find_bone(c)
		if i >= 0: return i
	var b: String = n.split(":")[-1]
	for side in ["Left", "Right"]:
		if b.begins_with(side) and HUMANOID.has(b.trim_prefix(side)):
			b = side + HUMANOID[b.trim_prefix(side)]
	if HUMANOID.has(b): b = HUMANOID[b]
	var j := skel.find_bone(b)
	if j >= 0: return j
	push_error("ReimuSkirt：找不到骨頭 " + n); return -1


func _build() -> void:
	var sc := skel.global_transform.basis.get_scale().x
	_sim = SpringBoneSimulator3D.new(); _sim.name = "Spring_Skirt"
	skel.add_child(_sim)
	var paths: Array[NodePath] = []
	# 腿膠囊：膠囊沿骨頭 +Y（大腿骨 → 膝、小腿骨 → 踝）
	var cj = JSON.parse_string(FileAccess.get_file_as_string(data_prefix + "_colliders.json"))
	for c in cj.capsules:
		var a := _bone(c.a); var b := _bone(c.b)
		var L := skel.get_bone_global_rest(a).origin.distance_to(skel.get_bone_global_rest(b).origin)
		var cap := SpringBoneCollisionCapsule3D.new(); cap.name = "COL_" + str(c.name)
		cap.radius = float(c.r) * sc + leg_margin
		cap.mid_height = L
		_sim.add_child(cap)
		cap.bone = a
		cap.position_offset = Vector3(0, L * 0.5, 0)
		paths.append(NodePath(cap.name))
		_caps.append([cap, a, b, float(c.r) * sc])
	# 骨盆：橫向膠囊，中心取骨盆切片的平均中心
	if hip_radius > 0.0:
		var hips := _bone("mixamorig:Hips")
		var cen := Vector3.ZERO; var n := 0
		for sd in cj.slabs:
			for q in sd.pts_blender: cen += Vector3(q[0], q[2], -q[1]); n += 1
		cen /= maxf(n, 1)
		var hg := skel.get_bone_global_rest(hips)
		var cap := SpringBoneCollisionCapsule3D.new(); cap.name = "COL_Hips"
		cap.radius = hip_radius; cap.mid_height = hip_width
		_sim.add_child(cap)
		cap.bone = hips
		cap.position_offset = hg.affine_inverse() * cen
		cap.rotation_offset = (hg.basis.orthonormalized().inverse() * Basis(Vector3.BACK, PI * 0.5)).get_rotation_quaternion()   # 軸轉成左右向
		paths.append(NodePath(cap.name))
	# 鏈
	var sj = JSON.parse_string(FileAccess.get_file_as_string(data_prefix + "_skirt_chains.json"))
	_sim.setting_count = sj.chains.size()
	for i in sj.chains.size():
		var ch: Dictionary = sj.chains[i]
		var bones: Array = ch.bones
		var j: Array = ch.joints_blender
		var tail_a := Vector3(j[-2][0], j[-2][2], -j[-2][1]); var tail_b := Vector3(j[-1][0], j[-1][2], -j[-1][1])
		var ids := []
		for bn in bones: ids.append(_bone(bn))
		_chains.append({"bones": ids})
		_sim.set_root_bone(i, ids[0])
		_sim.set_end_bone(i, ids[-1])
		_sim.set_extend_end_bone(i, true)
		_sim.set_end_bone_direction(i, SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
		_sim.set_end_bone_length(i, tail_a.distance_to(tail_b) * sc)
		_sim.set_radius(i, joint_radius)
		_sim.set_stiffness(i, stiffness)
		_sim.set_drag(i, drag)
		_sim.set_gravity(i, gravity)
		var curve := Curve.new()
		curve.add_point(Vector2(0, 1)); curve.add_point(Vector2(1, tip_softness))
		_sim.set_stiffness_damping_curve(i, curve)
		_sim.set_enable_all_child_collisions(i, false)
		_sim.set_collision_count(i, paths.size())
		for k in paths.size(): _sim.set_collision_path(i, k, paths[k])
	_sim.active = springs_enabled
	_sim.reset()


## 角色被瞬移（傳送、讀檔）後呼叫：彈簧歸位，避免裙擺被甩一大下。
func reset_skirt() -> void:
	if _sim: _sim.reset()


func get_simulator() -> SpringBoneSimulator3D:
	return _sim
