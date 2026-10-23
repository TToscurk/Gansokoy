extends SceneTree
func _init() -> void:
	var s: Node3D = (load("res://characters/reimu/reimu.glb") as PackedScene).instantiate()
	root.add_child(s)
	await process_frame
	var sk := s.find_child("GeneralSkeleton", true, false) as Skeleton3D
	print("SKEL bones ", sk.get_bone_count())
	var cj = JSON.parse_string(FileAccess.get_file_as_string("res://characters/reimu/reimu_skirt_chains.json"))
	var maxerr := 0.0; var miss := 0
	for ch in cj.chains:
		for i in ch.bones.size():
			var bi := sk.find_bone(ch.bones[i])
			if bi < 0: miss += 1; continue
			var g := (sk.global_transform * sk.get_bone_global_rest(bi)).origin
			var q = ch.joints_blender[i]; var exp := Vector3(q[0], q[2], -q[1])
			maxerr = maxf(maxerr, g.distance_to(exp))
	print("SKIRT bones missing ", miss, " head pos max err m ", maxerr)
	var b0 := sk.find_bone("Skirt_00_1")
	print("Skirt_00_1 parent ", sk.get_bone_name(sk.get_bone_parent(b0)), " rest y-axis ", (sk.get_bone_global_rest(b0).basis.y).normalized())
	quit(0)
