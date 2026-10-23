extends SceneTree
## 一次性探針：v24 Mixamo FBX 與 yoriichi_v24.glb 的骨架／rest／節點變換對照。

func _initialize() -> void:
	var tgt: Node = (load("res://characters/yoriichi/v24/yoriichi_v24.glb") as PackedScene).instantiate()
	root.add_child(tgt)
	var tsk: Skeleton3D = tgt.find_child("Skeleton3D", true, false)
	print("TGT skel global ", tsk.global_transform)
	for p in ["res://characters/yoriichi/v24/mixamo/_calib_walk.fbx", "res://characters/yoriichi/v24/mixamo/run.fbx"]:
		var src: Node = (load(p) as PackedScene).instantiate()
		root.add_child(src)
		var sk: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
		print(p.get_file(), " skelpath=", src.get_path_to(sk), " skel global=", sk.global_transform, " bones=", sk.get_bone_count(), " anims=", ap.get_animation_list())
		var a := ap.get_animation(ap.get_animation_list()[0])
		var types := {}
		for t in a.get_track_count():
			types[a.track_get_type(t)] = types.get(a.track_get_type(t), 0) + 1
		print("  len=", a.length, " tracks=", a.get_track_count(), " types=", types, " t0=", a.track_get_path(0), " keys0=", a.track_get_key_count(0))
		var miss := []
		var maxang := 0.0
		var worst := ""
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			var j := tsk.find_bone(n)
			if j < 0:
				miss.append(n)
				continue
			var ang := sk.get_bone_rest(i).basis.get_rotation_quaternion().angle_to(tsk.get_bone_rest(j).basis.get_rotation_quaternion())
			if ang > maxang:
				maxang = ang
				worst = n
		print("  missing in target: ", miss)
		print("  max local rest rot diff deg=", rad_to_deg(maxang), " at ", worst)
		print("  src hips rest ", sk.get_bone_rest(0).origin, " tgt hips rest ", tsk.get_bone_rest(tsk.find_bone("mixamorig_Hips")).origin)
		print("  src LeftArm rest ", sk.get_bone_rest(sk.find_bone("mixamorig_LeftArm")), " tgt ", tsk.get_bone_rest(tsk.find_bone("mixamorig_LeftArm")))
	quit()
