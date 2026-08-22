extends SceneTree
# Rebuild derived gameplay animations with the CORRECT axis convention.
# Skeleton space for this Meshy rig: Z = up (hips rest Z ~= 0.986), X/Y = horizontal.
# The previous build froze X/Z and left Y — leaving 6.47 units of horizontal root
# motion in Roll_Dodge (the snap-back bug). Here we freeze X and Y (horizontal)
# and keep Z (vertical bob), for roll + attacks.
# For Regular_Jump we additionally clamp Z to <= rest so the physics jump owns
# the rise while the crouch anticipation and the landing dip stay animated.
#
# Hips XY modes (option "xy"):
#   freeze_first  — 凍結在首 key（舊行為；首 key 本身帶偏移時會把偏移烤進去）
#   freeze_rest   — 凍結在骨架 rest 的 Hips XY（全身技：模型永遠留在膠囊中心）
#   recenter_rest — 保留循環內的自然擺動，但把首 key 對齊 rest（locomotion：
#                   八方向切換時原點一致，不飄移）
# z_shift 來源：_diag 腳本實測的腳底高度（腳骨原點距地面），以 Walk 的
# 邊界高度 0.0386 / 最低接觸 0.0277 為基準逐一補正（見 animations/README.md）。
#
# Run_Turn / Walk_Turn 已移出重建清單：實測這兩支的源 clip 整段懸空
# （腳底全程 0.12~0.25 m，且 Hips 水平錨在 -1.15 m 外），無法用偏移補正
# 修成落地轉身，正式狀態機不再引用（檔案保留，不刪除）。

const JOBS := [
	# Roll 不再用整段固定 z_shift（會顧此失彼）：改採 time-dependent 補正——
	# 起滾蹲伏段與收勢站立段把腳底釘回地面（target 0.038 = Walk 邊界高度），
	# 中段翻滾（真正騰空）完全不動。窗口參數為 clip 長度比例。
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Roll_Dodge_1_withSkin.fbx", "out": "res://animations/yoriichi_roll_dodge.res", "clamp_z": false, "xy": "freeze_rest",
		"ground_window": {"target": 0.038, "start_hold": 0.197, "start_fade_end": 0.331, "end_fade_start": 0.710, "end_hold": 0.829}},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Weapon_Combo_withSkin.fbx", "out": "res://animations/yoriichi_attack_combo.res", "clamp_z": false},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Axe_Spin_Attack_withSkin.fbx", "out": "res://animations/yoriichi_attack_spin.res", "clamp_z": false, "xy": "freeze_rest", "z_shift": -0.108},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Sword_Judgment_withSkin.fbx", "out": "res://animations/yoriichi_attack_judgment.res", "clamp_z": false, "xy": "freeze_rest", "z_shift": -0.090},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Regular_Jump_withSkin.fbx", "out": "res://animations/yoriichi_jump.res", "clamp_z": true, "xy": "freeze_rest", "z_shift": -0.028},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Weapon_Combo_1_withSkin.fbx", "out": "res://animations/yoriichi_attack_combo_1.res", "clamp_z": false, "xy": "freeze_rest", "z_shift": -0.090},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_360_Power_Spin_Jump_withSkin.fbx", "out": "res://animations/yoriichi_attack_spin_jump.res", "clamp_z": true, "xy": "freeze_rest", "z_shift": -0.048},
	# 疾跑／側身追擊跑：邊界腳底對齊 Walk（0.0386），水平錨回 rest 但保留步態擺動。
	# FL/FR 的 z_shift 受「最深幀腳底不低於 -0.01」限制（蹬地瞬間趾尖容許微陷）。
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_RunFast_withSkin.fbx", "out": "res://animations/yoriichi_run_fast.res", "clamp_z": false, "xy": "recenter_rest", "z_shift": -0.036},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_ForwardLeft_Run_Fight_withSkin.fbx", "out": "res://animations/yoriichi_run_fl.res", "clamp_z": false, "xy": "recenter_rest", "z_shift": -0.034},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_ForwardRight_Run_Fight_withSkin.fbx", "out": "res://animations/yoriichi_run_fr.res", "clamp_z": false, "xy": "recenter_rest", "z_shift": -0.037},
	# Idle 落地版：實測 Idle 腳趾懸空 0.123 m（vs Walk 接觸幀），Hips Z 下移補正。
	# 水平不凍結（Idle 原本就零漂移，凍結會殺掉呼吸晃動）。
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Idle_11_withSkin.fbx", "out": "res://animations/yoriichi_idle_grounded.res", "clamp_z": false, "keep_xy": true, "z_shift": -0.123},
]

# Jump 手臂抑制：雙手大幅上舉改為貼近跑姿。arm bones 的每個 rotation key
# 向 Running 首幀參考姿勢 slerp（保留 35% 原始擺動）。
const ARM_BONES := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand"]
const ARM_KEEP := 0.35
const ARM_REF_SRC := "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Running_withSkin.fbx"

func _anim_from_fbx(path: String) -> Animation:
	var ps: PackedScene = load(path)
	var tmp := ps.instantiate()
	var aps := tmp.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		push_error("no AnimationPlayer in " + path)
		tmp.free()
		return null
	var a: Animation = (aps[0] as AnimationPlayer).get_animation((aps[0] as AnimationPlayer).get_animation_list()[0]).duplicate()
	tmp.free()
	return a

func _rot_track(a: Animation, bone: String) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_ROTATION_3D and String(a.track_get_path(i)).ends_with(bone):
			return i
	return -1

func _damp_arms(a: Animation) -> void:
	var ref := _anim_from_fbx(ARM_REF_SRC)
	var worst_before := 0.0
	var worst_after := 0.0
	for b in ARM_BONES:
		var t := _rot_track(a, b)
		var rt := _rot_track(ref, b)
		if t < 0 or rt < 0:
			continue
		var ref_q: Quaternion = ref.track_get_key_value(rt, 0)
		for k in a.track_get_key_count(t):
			var q: Quaternion = a.track_get_key_value(t, k)
			worst_before = maxf(worst_before, rad_to_deg(ref_q.angle_to(q)))
			var nq := ref_q.slerp(q, ARM_KEEP)
			worst_after = maxf(worst_after, rad_to_deg(ref_q.angle_to(nq)))
			a.track_set_key_value(t, k, nq)
	print("  arm_damp: max deviation from run pose %.1f deg -> %.1f deg (keep %.2f)" % [worst_before, worst_after, ARM_KEEP])

func _hips_track(a: Animation) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_POSITION_3D and String(a.track_get_path(i)).ends_with("Hips"):
			return i
	return -1

func _rest_hips_xy() -> Vector2:
	var ps: PackedScene = load("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Walking_withSkin.fbx")
	var tmp := ps.instantiate()
	var out := Vector2.ZERO
	var skels := tmp.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var skel: Skeleton3D = skels[0]
		var h := skel.find_bone("Hips")
		if h >= 0:
			var r := skel.get_bone_rest(h).origin
			out = Vector2(r.x, r.y)
	tmp.free()
	return out

# --- ground_window：time-dependent 垂直補正（目前用於 Roll）---------------
# 在「起滾蹲伏」與「收勢站立」兩個窗口，依每個 key 的實際腳底高度把 Hips Z
# 下修到 target（腳底釘回地面）；窗口外（翻滾騰空中段）不動。
# 補正量 = -(measured_foot - target) * window_weight(t)，對剛性是線性的。
var _meas_skel: Skeleton3D = null
var _meas_player: AnimationPlayer = null
var _meas_foot_bones: Array = []

func _setup_measurer() -> void:
	if _meas_skel != null:
		return
	var ps: PackedScene = load("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Walking_withSkin.fbx")
	var inst: Node3D = ps.instantiate()
	root.add_child(inst)
	_meas_player = inst.find_children("*", "AnimationPlayer", true, false)[0]
	_meas_skel = inst.find_children("*", "Skeleton3D", true, false)[0]
	for i in _meas_skel.get_bone_count():
		if String(_meas_skel.get_bone_name(i)) in ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
			_meas_foot_bones.append(i)

func _meas_bone_global(bone_idx: int) -> Transform3D:
	var t := _meas_skel.get_bone_pose(bone_idx)
	var p := _meas_skel.get_bone_parent(bone_idx)
	while p >= 0:
		t = _meas_skel.get_bone_pose(p) * t
		p = _meas_skel.get_bone_parent(p)
	return t

func _measure_foot_at(anim: Animation, t: float) -> float:
	var lib_name: StringName = _meas_player.get_animation_library_list()[0] if _meas_player.get_animation_library_list().size() > 0 else &""
	if not _meas_player.has_animation_library(lib_name):
		_meas_player.add_animation_library(lib_name, AnimationLibrary.new())
	var lib := _meas_player.get_animation_library(lib_name)
	if lib.has_animation("__meas"):
		lib.remove_animation("__meas")
	lib.add_animation("__meas", anim)
	_meas_player.play("__meas", -1, 1.0, false)
	_meas_player.seek(t, true)
	var m := 1e9
	for i in _meas_foot_bones:
		m = minf(m, _meas_bone_global(i).origin.z)
	_meas_player.stop()
	lib.remove_animation("__meas")
	return m

func _window_weight(u: float, gw: Dictionary) -> float:
	var sh := float(gw.start_hold); var sfe := float(gw.start_fade_end)
	var efs := float(gw.end_fade_start); var eh := float(gw.end_hold)
	if u <= sh:
		return 1.0
	if u < sfe:
		return 0.5 * (1.0 + cos(PI * (u - sh) / (sfe - sh)))
	if u <= efs:
		return 0.0
	if u < eh:
		return 0.5 * (1.0 - cos(PI * (u - efs) / (eh - efs)))
	return 1.0

func _ground_window_pass(a: Animation, hips_track: int, gw: Dictionary) -> void:
	_setup_measurer()
	var n := a.track_get_key_count(hips_track)
	var target := float(gw.target)
	var worst := 0.0
	for k in n:
		var t := a.track_get_key_time(hips_track, k)
		var e := _window_weight(t / a.length, gw)
		if e <= 0.0:
			continue
		var foot := _measure_foot_at(a, t)
		var s := -(foot - target) * e
		worst = maxf(worst, absf(s))
		var v: Vector3 = a.track_get_key_value(hips_track, k)
		v.z += s
		a.track_set_key_value(hips_track, k, v)
	print("  ground_window: max_shift=%.4f (target foot=%.3f)" % [worst, target])

func _init():
	var rest_xy := _rest_hips_xy()
	for job in JOBS:
		var a := _anim_from_fbx(job.src)
		if a == null:
			continue
		var t := _hips_track(a)
		if t < 0:
			push_error("no hips position track in " + String(job.src))
			continue
		var n := a.track_get_key_count(t)
		var first: Vector3 = a.track_get_key_value(t, 0)
		var drift: Vector3 = a.track_get_key_value(t, n - 1) - first
		var z_min := 1e9
		var z_max := -1e9
		var takeoff := -1.0
		var land := -1.0
		var xy_mode: String = job.get("xy", "freeze_first")
		for k in n:
			var v: Vector3 = a.track_get_key_value(t, k)
			z_min = minf(z_min, v.z)
			z_max = maxf(z_max, v.z)
			var nv := Vector3(first.x, first.y, v.z)
			if job.get("keep_xy", false):
				nv.x = v.x
				nv.y = v.y
			elif xy_mode == "freeze_rest":
				nv.x = rest_xy.x
				nv.y = rest_xy.y
			elif xy_mode == "recenter_rest":
				nv.x = v.x - (first.x - rest_xy.x)
				nv.y = v.y - (first.y - rest_xy.y)
			if job.clamp_z:
				# Locate the animated air phase before clamping.
				var time := a.track_get_key_time(t, k)
				if v.z > first.z + 0.05:
					if takeoff < 0.0:
						takeoff = time
					land = time
				nv.z = minf(v.z, first.z)
			nv.z += job.get("z_shift", 0.0)
			a.track_set_key_value(t, k, nv)
		a.loop_mode = Animation.LOOP_NONE
		if String(job.out).contains("yoriichi_jump"):
			_damp_arms(a)
		if job.has("ground_window"):
			_ground_window_pass(a, t, job["ground_window"])
		var err := ResourceSaver.save(a, job.out)
		print("[%s] xy=%s len=%.4f keys=%d first_xy=(%.3f, %.3f)->anchor(%.3f, %.3f) drift_removed=(%.3f, %.3f) z_range=[%.3f, %.3f] z_shift=%.3f save=%d" % [
			String(job.out).get_file(), xy_mode, a.length, n, first.x, first.y,
			(rest_xy.x if xy_mode == "freeze_rest" else first.x - (first.x - rest_xy.x) if xy_mode == "recenter_rest" else first.x),
			(rest_xy.y if xy_mode == "freeze_rest" else first.y - (first.y - rest_xy.y) if xy_mode == "recenter_rest" else first.y),
			drift.x, drift.y, z_min, z_max, float(job.get("z_shift", 0.0)), err])
		if job.clamp_z:
			print("  air_phase: takeoff=%.3fs land=%.3fs duration=%.3fs (of %.2fs clip)" % [takeoff, land, land - takeoff, a.length])
	quit()
