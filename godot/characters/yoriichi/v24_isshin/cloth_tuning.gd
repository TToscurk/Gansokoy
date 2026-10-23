extends RefCounted
## 候選專用的衣物微調（只改這個角色實例的彈簧骨碰撞設定；不改 yoriichi_v24_rig.gd／chains.json／colliders.json／任何資產）。
## 1) 袖口：Cuff_*_Dn 兩條向下垂的袖鏈不與軀幹碰撞膠囊碰撞。實測它們會被擠進脊椎／髖膠囊最深 8.7 cm，
##    手臂離開時一幀彈開（單幀 18.6 cm、離靜止偏移 37 cm）；關掉後最大單幀 5.8 cm、偏移 8.5 cm。
## 2) 下襬：腿的碰撞膠囊半徑放大（大腿 8.0→12 cm、小腿 5.8→14 cm；袴實際表面半徑中位 11.7／15.1 cm）。
## 這是「現有碰撞代理的局部修正」，不是布料系統；殘餘穿插記為後續美術問題。
const HEM_THIGH_R := 0.12
const HEM_SHIN_R := 0.14

static func apply(rig) -> void:
	var sk: Skeleton3D = rig.skeleton
	var sleeve := sk.get_node_or_null("Spring_sleeve") as SpringBoneSimulator3D
	if sleeve:
		for i in sleeve.setting_count:
			if str(sleeve.get_root_bone_name(i)).contains("_Dn"):
				sleeve.set_collision_count(i, 0)
		sleeve.reset()
	var hem := sk.get_node_or_null("Spring_hem") as SpringBoneSimulator3D
	if hem:
		for nm in ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"]:
			var cap := hem.get_node_or_null("COL_" + nm) as SpringBoneCollisionCapsule3D
			if cap:
				cap.radius = HEM_SHIN_R if nm.ends_with("Leg") and not nm.contains("Up") else HEM_THIGH_R
		hem.reset()
