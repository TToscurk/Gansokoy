extends SceneTree
## 慧音走路／待機 clip 量測：在慧音骨架上取樣 Hips 高度、腳最低點，量「上下起伏」與「抖動」。
##   godot --headless --path . --script res://tools/measure_keine_clips.gd -- <res://a.res> <res://b.res> ...
## 起伏 amp＝Hips y 的 max−min；抖動 jerk＝每格二階差分 RMS（m/frame²×1e3）、max_step＝相鄰格 |Δy| 最大；
## 足接地：腳最低點 y 的範圍（理想 ≈ 0 的固定值）；腳速＝walk 接地足後退速度（同 population_lib）。

func _init() -> void:
	var w: Node3D = (load("res://characters/keine/keine.tscn") as PackedScene).instantiate()
	w.set("frozen", true)
	root.add_child(w)
	await process_frame
	var ap := w.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var lib := ap.get_animation_library(&"")
	var hips := sk.find_bone("Hips")
	var feet := [sk.find_bone("LeftToes"), sk.find_bone("RightToes"), sk.find_bone("LeftFoot"), sk.find_bone("RightFoot")]
	var idx := 0
	for p: String in OS.get_cmdline_user_args():
		var a := load(p) as Animation
		if a == null:
			print("[KCLIP] missing ", p)
			continue
		var nm := "m%d" % idx
		idx += 1
		lib.add_animation(nm, a)
		ap.play(nm)
		var L := a.length
		var N := int(round(L * 60.0))
		var yaws := PackedFloat32Array()
		var hand_min := INF
		var hand_lo := [Vector3.INF, Vector3.INF]
		var hand_range := 0.0
		var hand_first := []
		var hy := PackedFloat32Array()
		var fy := PackedFloat32Array()
		for k in N:
			ap.seek(L * k / N, true)
			hy.append((sk.global_transform * sk.get_bone_global_pose(hips).origin).y)
			var m := INF
			for f in feet:
				m = minf(m, (sk.global_transform * sk.get_bone_global_pose(f).origin).y)
			fy.append(m)
			var lu := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftUpperLeg")).origin
			var ru := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightUpperLeg")).origin
			var side := lu - ru
			yaws.append(rad_to_deg(atan2(side.z, side.x)))
			var hp := sk.global_transform * sk.get_bone_global_pose(hips).origin
			var hi := 0
			for hb in ["LeftHand", "RightHand"]:
				var h := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(hb)).origin
				hand_min = minf(hand_min, Vector2(h.x - hp.x, h.z - hp.z).length())
				if hand_first.size() < 2:
					hand_first.append(h)
				else:
					hand_range = maxf(hand_range, h.distance_to(hand_first[hi]))
				hi += 1
		var amp := _max(hy) - _min(hy)
		var j2 := 0.0
		var ms := 0.0
		for k in N:
			var d2 := hy[(k + 1) % N] - 2.0 * hy[k] + hy[(k - 1 + N) % N]
			j2 += d2 * d2
			ms = maxf(ms, absf(hy[(k + 1) % N] - hy[k]))
		var jerk := sqrt(j2 / N) * 1000.0
		print("[KCLIP] %-60s len %.2fs  hips_amp %.3f m  jerk %.3f  max_step %.4f m  foot_min %.3f..%.3f  pelvis_yaw %.1f..%.1f  hand_to_axis_min %.3f m  hand_motion %.3f m" % [p.get_file(), L, amp, jerk, ms, _min(fy), _max(fy), _min(yaws), _max(yaws), hand_min, hand_range])
	quit()


func _min(a: PackedFloat32Array) -> float:
	var m := INF
	for x in a:
		m = minf(m, x)
	return m


func _max(a: PackedFloat32Array) -> float:
	var m := -INF
	for x in a:
		m = maxf(m, x)
	return m
