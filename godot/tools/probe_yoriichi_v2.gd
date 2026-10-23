extends SceneTree
# 驗證 yoriichi_v2_combat.glb 匯入結果：骨名（Humanoid 重命名）、haori 骨保留、動畫、Root motion 軌
func _init() -> void:
	var ps: PackedScene = load("res://characters/yoriichi/v2/yoriichi_v2_combat.glb")
	if ps == null:
		print("PROBE load failed"); quit(); return
	var root: Node = ps.instantiate()
	get_root().add_child(root)
	await process_frame
	var skel: Skeleton3D = root.find_child("GeneralSkeleton", true, false)
	if skel == null:
		var sk = root.find_children("*", "Skeleton3D", true, false)
		print("PROBE no GeneralSkeleton; skeletons ", sk, " tree:")
		root.print_tree_pretty()
		quit(); return
	print("PROBE skeleton ", skel.name, " bones ", skel.get_bone_count(), " path ", root.get_path_to(skel))
	var names := []
	for i in skel.get_bone_count():
		names.append(skel.get_bone_name(i))
	print("PROBE humanoid sample ", ["Root", "Hips", "LeftHand", "RightHand", "Head"].map(func(n): return skel.find_bone(n)))
	print("PROBE extra ", names.filter(func(n): return n.begins_with("haori") or n in ["Weapon_R", "Grip_R", "Grip_L"]))
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	for an in ap.get_animation_list():
		var a: Animation = ap.get_animation(an)
		var haori_tracks := 0
		var root_track := -1
		for t in a.get_track_count():
			var p := str(a.track_get_path(t))
			if p.contains("haori") or p.contains("Weapon_R") or p.contains("Grip_"):
				haori_tracks += 1
				if an == "GS_Idle_RM":
					print("PROBE cloth/weapon track ", p)
			if p.ends_with(":Root") and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
				root_track = t
		var disp := Vector3.ZERO
		if root_track >= 0:
			disp = a.position_track_interpolate(root_track, a.length) - a.position_track_interpolate(root_track, 0.0)
		print("PROBE anim ", an, " len ", snappedf(a.length, 0.01), " tracks ", a.get_track_count(), " cloth/weapon tracks ", haori_tracks, " root disp ", disp, " loop ", a.loop_mode)
	var meshes = root.find_children("*", "MeshInstance3D", true, false)
	print("PROBE meshes ", meshes.map(func(m): return m.name))
	var ba = root.find_children("*", "BoneAttachment3D", true, false)
	print("PROBE attachments ", ba.map(func(b): return [b.name, b.bone_name]))
	quit()
