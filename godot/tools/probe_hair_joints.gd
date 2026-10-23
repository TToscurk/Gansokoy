extends SceneTree
# 檢查 HairSpring 是否真的建立 joints（等幾個 frame 後）
var n := 0
var sk: Skeleton3D
func _initialize() -> void:
	var s: Node = load("res://characters/yoriichi/v2/yoriichi_v2_test.tscn").instantiate()
	root.add_child(s)
	sk = s.find_child("GeneralSkeleton", true, false)
func _process(_d: float) -> bool:
	n += 1
	if n in [1, 5, 30]:
		for nm in ["HaoriSpring", "HairSpring"]:
			var sim: SpringBoneSimulator3D = sk.get_node(nm)
			print("JP f", n, " ", nm, " active ", sim.active, " joints ", range(sim.get_setting_count()).map(func(q): return sim.get_joint_count(q)),
				" root_idx ", range(sim.get_setting_count()).map(func(q): return sim.get_root_bone(q)), " end_idx ", range(sim.get_setting_count()).map(func(q): return sim.get_end_bone(q)))
		for bn in ["hair_ponytail_root", "hair_ponytail_01", "hair_ponytail_02", "hair_ponytail_03", "CC_Base_Head"]:
			var bi := sk.find_bone(bn)
			print("JP bone ", bn, " idx ", bi, " parent ", sk.get_bone_name(sk.get_bone_parent(bi)) if bi >= 0 else "-")
	return n > 31
