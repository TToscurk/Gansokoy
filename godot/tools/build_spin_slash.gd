extends SceneTree

func _init():
	var glb_path := "res://characters/yoriichi/Meshy_AI_Animation_連續旋轉砍擊_withSkin.glb"
	var out_path := "res://characters/yoriichi/animations/yoriichi_attack_continuous_spin.res"
	
	var ps_glb := load(glb_path) as PackedScene
	if ps_glb == null:
		print("ERROR: could not load GLB")
		quit(1)
		return
	var inst_glb := ps_glb.instantiate()
	var aps := inst_glb.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		print("ERROR: no AnimationPlayer in GLB")
		quit(1)
		return
	var ap: AnimationPlayer = aps[0]
	var src_anim := ap.get_animation("rigify_clip")
	if src_anim == null:
		print("ERROR: no rigify_clip animation")
		quit(1)
		return
		
	var ps_fbx := load("res://characters/yoriichi/yoriichi_body.fbx") as PackedScene
	var inst_fbx := ps_fbx.instantiate()
	var skel_fbx: Skeleton3D = inst_fbx.find_children("*", "Skeleton3D", true, false)[0]
	var hips_bone_idx := skel_fbx.find_bone("Hips")
	var fbx_hips_rest := skel_fbx.get_bone_rest(hips_bone_idx)
	
	var skel_glb: Skeleton3D = inst_glb.find_children("*", "Skeleton3D", true, false)[0]
	var glb_hips_rest := skel_glb.get_bone_rest(skel_glb.find_bone("Hips"))
	
	var new_anim := Animation.new()
	new_anim.length = src_anim.length
	new_anim.loop_mode = Animation.LOOP_NONE
	
	var rot_x90 := Quaternion(Vector3(1, 0, 0), PI / 2.0)
	
	for t in src_anim.get_track_count():
		var old_path := String(src_anim.track_get_path(t))
		var track_type := src_anim.track_get_type(t)
		var bone_name := old_path.get_slice(":", 1) if old_path.contains(":") else old_path.get_file()
		var new_track_path := "Armature/Skeleton3D:" + bone_name
		
		if track_type == Animation.TYPE_POSITION_3D and bone_name == "Hips":
			var new_t := new_anim.add_track(Animation.TYPE_POSITION_3D)
			new_anim.track_set_path(new_t, new_track_path)
			new_anim.track_set_interpolation_type(new_t, src_anim.track_get_interpolation_type(t))
			var key_count := src_anim.track_get_key_count(t)
			for k in key_count:
				var time := src_anim.track_get_key_time(t, k)
				var v: Vector3 = src_anim.track_get_key_value(t, k)
				# Horizontal: freeze to FBX skeleton rest X and Y
				# Vertical: scale Y from cm to m, relative to rest + fbx rest Z
				var y_m := v.y / 100.0
				var glb_rest_y_m := glb_hips_rest.origin.y / 100.0
				var z_bob := y_m - glb_rest_y_m
				var z_shift := 0.0502
				var final_z := fbx_hips_rest.origin.z + z_bob + z_shift
				var new_v := Vector3(fbx_hips_rest.origin.x, fbx_hips_rest.origin.y, final_z)
				new_anim.track_insert_key(new_t, time, new_v)
			print("Created Hips position track with %d keys" % key_count)
			
		elif track_type == Animation.TYPE_ROTATION_3D:
			var new_t := new_anim.add_track(Animation.TYPE_ROTATION_3D)
			new_anim.track_set_path(new_t, new_track_path)
			new_anim.track_set_interpolation_type(new_t, src_anim.track_get_interpolation_type(t))
			var key_count := src_anim.track_get_key_count(t)
			for k in key_count:
				var time := src_anim.track_get_key_time(t, k)
				var q: Quaternion = src_anim.track_get_key_value(t, k)
				if bone_name == "Hips":
					q = rot_x90 * q
				elif bone_name == "RightForeArm":
					# Unbend elbow outward along flexion axis to extend reach
					q = q * Quaternion(Vector3(0, 0, 1), deg_to_rad(38.0))
				elif bone_name == "RightArm":
					# Abduct upper arm outward away from torso and slightly forward
					q = q * Quaternion(Vector3(0, 0, -1), deg_to_rad(18.0)) * Quaternion(Vector3(0, 1, 0), deg_to_rad(8.0))
				elif bone_name == "RightShoulder":
					# Open chest and spread shoulder outward
					q = q * Quaternion(Vector3(0, 1, 0), deg_to_rad(10.0))
				elif bone_name == "RightHand":
					# Angle blade outward into the cutting arc
					q = q * Quaternion(Vector3(1, 0, 0), deg_to_rad(15.0))
				new_anim.track_insert_key(new_t, time, q)
			print("Created rotation track for %s with %d keys" % [bone_name, key_count])
	
	# Also ensure RightHand and LeftHand tracks exist
	var hand_list: Array[String] = ["RightHand", "LeftHand"]
	for hand in hand_list:
		var hand_path: String = "Armature/Skeleton3D:" + hand
		var found := false
		for nt in new_anim.get_track_count():
			if String(new_anim.track_get_path(nt)) == hand_path:
				found = true
				break
		if not found:
			var b_idx := skel_fbx.find_bone(hand)
			if b_idx >= 0:
				var rest_q := skel_fbx.get_bone_rest(b_idx).basis.get_rotation_quaternion()
				if hand == "RightHand":
					rest_q = rest_q * Quaternion(Vector3(1, 0, 0), deg_to_rad(15.0))
				var new_t := new_anim.add_track(Animation.TYPE_ROTATION_3D)
				new_anim.track_set_path(new_t, hand_path)
				new_anim.track_insert_key(new_t, 0.0, rest_q)
				new_anim.track_insert_key(new_t, new_anim.length, rest_q)
				print("Added missing rest rotation track for %s" % hand)
				
	var err := ResourceSaver.save(new_anim, out_path)
	print("Saved to %s with status %d (tracks=%d, len=%.2f)" % [out_path, err, new_anim.get_track_count(), new_anim.length])
	
	inst_glb.free()
	inst_fbx.free()
	quit(0)
