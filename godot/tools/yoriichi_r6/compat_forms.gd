extends SceneTree
## R6 相容性巡檢（headless、唯讀）：現有普通斬／重斬／型／居合／架勢 clip，在 R3 握刀掛點 vs R6 掛點下
##   * 刀尖位置差（cm）、刀身方向差（度）
##   * 左手與刀柄軸的距離（R3 / R6；判斷雙手段落的左手會不會脫柄）
## 骨架 global pose 由 local pose 自行累乘（headless 下 Skeleton3D 快取不重算）。
##   godot --headless --path . -s res://tools/yoriichi_r6/compat_forms.gd -- <out.json>
const GLB := "res://characters/yoriichi/v24/yoriichi_v24.glb"
const R3_SCENE := "res://characters/yoriichi/player_yoriichi.tscn"
const R6_SCENE := "res://characters/yoriichi/player_yoriichi_r6.tscn"
const A := "res://characters/yoriichi/v24/anims/"
const CLIPS := ["attack_combo", "atk_onehand", "atk_high", "atk_low", "gs_jump_atk", "gs_slide", "gs_power", "gs_crouch_slash",
	"atk_outward", "th_combo", "gs_spin_run", "iai_stance", "gs_down", "guard", "gs_block_hit", "draw", "d_walk", "ua_idle_b", "sword_run",
	"gs_walk_back", "gs_strafe_l", "gs_strafe_r", "assassin"]

func _glob(sk: Skeleton3D, bi: int, cache: Dictionary) -> Transform3D:
	if cache.has(bi):
		return cache[bi]
	var local := Transform3D(Basis(sk.get_bone_pose_rotation(bi)).scaled(sk.get_bone_pose_scale(bi)), sk.get_bone_pose_position(bi))
	var p := sk.get_bone_parent(bi)
	var g := local if p < 0 else _glob(sk, p, cache) * local
	cache[bi] = g
	return g

func _sock(scene_path: String) -> Transform3D:
	var inst: Node = (load(scene_path) as PackedScene).instantiate()
	var t: Transform3D = (inst.find_child("Sword_Hand", true, false) as Node3D).transform
	inst.free()
	return t

func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return (p - (a + ab * t)).length()

func _initialize() -> void:
	var out_path: String = OS.get_cmdline_user_args()[0]
	var s3 := _sock(R3_SCENE)
	var s6 := _sock(R6_SCENE)
	var inst: Node3D = (load(GLB) as PackedScene).instantiate()
	root.add_child(inst)
	var sk := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var rh := sk.find_bone("mixamorig_RightHand")
	var lh := sk.find_bone("mixamorig_LeftHand")
	var lm := sk.find_bone("mixamorig_LeftHandMiddle1")
	var res := {}
	for c in CLIPS:
		var path: String = A + c + ".res"
		if not ResourceLoader.exists(path):
			continue
		var a: Animation = load(path)
		var n := int(round(a.length * 30.0)) + 1
		var tip_d := 0.0
		var ang := 0.0
		var lnear3 := 0
		var lnear6 := 0
		var lworse := 0.0
		var two_frames: Array = []
		for i in n:
			var t := minf(float(i) / 30.0, a.length)
			for bi in sk.get_bone_count():
				sk.set_bone_pose_rotation(bi, sk.get_bone_rest(bi).basis.get_rotation_quaternion())
				sk.set_bone_pose_position(bi, sk.get_bone_rest(bi).origin)
			for ti in a.get_track_count():
				var bi := sk.find_bone(str(a.track_get_path(ti)).get_slice(":", 1))
				if bi < 0:
					continue
				var ty := a.track_get_type(ti)
				if ty == Animation.TYPE_ROTATION_3D:
					sk.set_bone_pose_rotation(bi, a.rotation_track_interpolate(ti, t))
				elif ty == Animation.TYPE_POSITION_3D:
					sk.set_bone_pose_position(bi, a.position_track_interpolate(ti, t))
			var cache := {}
			var H := _glob(sk, rh, cache)
			var w3 := H * s3
			var w6 := H * s6
			var tip3 := w3 * Vector3(0, 1.085, 0)
			var tip6 := w6 * Vector3(0, 1.085, 0)
			tip_d = maxf(tip_d, tip3.distance_to(tip6))
			ang = maxf(ang, rad_to_deg(w3.basis.y.normalized().angle_to(w6.basis.y.normalized())))
			var lp := _glob(sk, lm, cache).origin
			var d3 := _seg_dist(lp, w3 * Vector3(0, -0.38, 0), w3 * Vector3(0, -0.005, 0))
			var d6 := _seg_dist(lp, w6 * Vector3(0, -0.38, 0), w6 * Vector3(0, -0.005, 0))
			if d3 < 0.06:
				lnear3 += 1
				two_frames.append([i, snappedf(d3 * 100.0, 0.1), snappedf(d6 * 100.0, 0.1)])
				lworse = maxf(lworse, d6 - d3)
			if d6 < 0.06:
				lnear6 += 1
		res[c] = {"frames": n, "tip_shift_cm_max": snappedf(tip_d * 100.0, 0.1), "blade_dir_deg_max": snappedf(ang, 0.1),
			"left_on_hilt_frames_r3": lnear3, "left_on_hilt_frames_r6": lnear6, "left_hilt_dist_increase_cm_max": snappedf(lworse * 100.0, 0.1),
			"two_hand_samples": two_frames.slice(0, 6)}
		print("COMPAT ", c, " ", res[c])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()
	quit()
