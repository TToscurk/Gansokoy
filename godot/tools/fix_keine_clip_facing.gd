extends SceneTree
## Mixamo（Keine_Mixamo 上傳時未轉向）下載的 clip 整段差 90°：只轉 Hips（根骨）旋轉＋位置 key 繞 Y 軸 deg，
## 再把 Hips XZ 平均移回 rest（原地）。Y 不動（之後由 build_keine_anim_grounded.gd 接地）。
##   godot --headless --path . --script res://tools/fix_keine_clip_facing.gd -- --clip=… --out=… --deg=-90
const NPC := "res://characters/keine/keine.tscn"


func _init() -> void:
	var clip := ""
	var out := ""
	var deg := -90.0
	var auto := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.trim_prefix("--clip=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a == "--deg=auto":
			auto = true
		elif a.begins_with("--deg="):
			deg = a.trim_prefix("--deg=").to_float()
	var w: Node3D = (load(NPC) as PackedScene).instantiate()
	root.add_child(w)
	await process_frame
	var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var hips := sk.find_bone("Hips")
	var rest_pos := sk.get_bone_rest(hips).origin
	var an := (load(clip) as Animation).duplicate(true) as Animation
	if auto:
		# 量原 clip 的骨盆朝向（左右大腿根連線），四捨五入到 90° 倍數再轉回正面
		var ap := w.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var lib := AnimationLibrary.new()
		lib.add_animation(&"m", an)
		ap.add_animation_library(&"probe", lib)
		ap.play(&"probe/m")
		var acc := 0.0
		for k in 8:
			ap.seek(an.length * k / 8.0, true)
			var side := sk.get_bone_global_pose(sk.find_bone("LeftUpperLeg")).origin - sk.get_bone_global_pose(sk.find_bone("RightUpperLeg")).origin
			acc += rad_to_deg(atan2(side.z, side.x))
		var yaw := acc / 8.0
		deg = round(yaw / 90.0) * 90.0
		print("[KFACING] auto: pelvis yaw %.1f° → rotate %.0f°" % [yaw, deg])
		ap.stop()
		ap.remove_animation_library(&"probe")
	var q := Quaternion(Vector3.UP, deg_to_rad(deg))
	var tr := an.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_ROTATION_3D)
	var tp := an.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
	for k in an.track_get_key_count(tr):
		var r: Quaternion = an.track_get_key_value(tr, k)
		an.track_set_key_value(tr, k, (q * r).normalized())
	var mean := Vector3.ZERO
	var n := an.track_get_key_count(tp)
	for k in n:
		var p: Vector3 = an.track_get_key_value(tp, k)
		p = q * (p - Vector3(rest_pos.x, 0, rest_pos.z) / sk.motion_scale) + Vector3(rest_pos.x, 0, rest_pos.z) / sk.motion_scale
		an.track_set_key_value(tp, k, p)
		mean += p
	mean /= max(n, 1)
	var off := Vector3(mean.x - rest_pos.x / sk.motion_scale, 0, mean.z - rest_pos.z / sk.motion_scale)
	for k in n:
		an.track_set_key_value(tp, k, (an.track_get_key_value(tp, k) as Vector3) - off)
	an.resource_name = out.get_file().get_basename()
	var e := ResourceSaver.save(an, out)
	print("[KFACING] %s rot %d keys pos %d keys deg %.0f recentre xz %s save %d → %s" % [clip.get_file(), an.track_get_key_count(tr), n, deg, str(off * sk.motion_scale), e, out])
	quit(0 if e == OK else 1)
