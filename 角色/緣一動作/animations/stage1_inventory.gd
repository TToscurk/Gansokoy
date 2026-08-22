extends SceneTree
# STAGE 1: quantitative animation inventory. Reads actual keyframes of every
# playable animation (source FBX + derived .res) and prints one JSON line each:
# duration, tracks, hips drift/vertical, per-bone-group angular travel (deg/s),
# leg cadence (step extrema), start/end pose diff (reversibility/loopability),
# and start-pose distance to Idle (blend-in cost).

const FBX := [
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Idle_11_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Walking_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Running_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_RunFast_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_ForwardLeft_Run_Fight_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_ForwardRight_Run_Fight_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Run_Turn_Left_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Run_Turn_Right_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Walk_Turn_Left_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Walk_Turn_Right_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Regular_Jump_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Roll_Dodge_1_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Weapon_Combo_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Weapon_Combo_1_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Axe_Spin_Attack_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_360_Power_Spin_Jump_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Sword_Judgment_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Dead_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Double_Blade_Spin_withSkin.fbx",
	"Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_拔刀_withSkin.fbx",
]
const LEGS := ["LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot"]
const ARMS := ["LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftHand", "RightHand"]
const SPINE := ["Spine02", "Spine01", "Spine", "neck", "Head"]
const POSE_BONES := ["Hips", "Spine", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg",
	"LeftArm", "RightArm", "LeftForeArm", "RightForeArm"]

var _idle_pose := {}

func _anim_from_fbx(path: String) -> Animation:
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var tmp := ps.instantiate()
	var aps := tmp.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		tmp.free()
		return null
	var src: AnimationPlayer = aps[0]
	var a: Animation = src.get_animation(src.get_animation_list()[0]).duplicate()
	tmp.free()
	return a

func _bone_of(a: Animation, i: int) -> String:
	return String(a.track_get_path(i)).get_slice(":", 1)

func _rot_track(a: Animation, bone: String) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_ROTATION_3D and _bone_of(a, i) == bone:
			return i
	return -1

func _group_travel(a: Animation, bones: Array) -> float:
	# 每秒角度行程（deg/s），骨群加總。
	var total := 0.0
	for b in bones:
		var t := _rot_track(a, b)
		if t < 0:
			continue
		for k in range(1, a.track_get_key_count(t)):
			var q0: Quaternion = a.track_get_key_value(t, k - 1)
			var q1: Quaternion = a.track_get_key_value(t, k)
			total += rad_to_deg(q0.angle_to(q1))
	return total / maxf(a.length, 0.01)

func _cadence(a: Animation) -> int:
	# LeftUpLeg 相對首幀角度的局部極大值數 ≈ 步伐週期數。
	var t := _rot_track(a, "LeftUpLeg")
	if t < 0:
		return 0
	var q0: Quaternion = a.track_get_key_value(t, 0)
	var angles := PackedFloat32Array()
	for k in a.track_get_key_count(t):
		angles.append(rad_to_deg(q0.angle_to(a.track_get_key_value(t, k))))
	var peaks := 0
	for k in range(1, angles.size() - 1):
		if angles[k] > angles[k - 1] and angles[k] > angles[k + 1] and angles[k] > 10.0:
			peaks += 1
	return peaks

func _pose_at(a: Animation, at_end: bool) -> Dictionary:
	var sig := {}
	for b in POSE_BONES:
		var t := _rot_track(a, b)
		if t >= 0:
			sig[b] = a.track_get_key_value(t, a.track_get_key_count(t) - 1 if at_end else 0)
	return sig

func _pose_diff(pa: Dictionary, pb: Dictionary) -> float:
	var worst := 0.0
	for b in pa:
		if pb.has(b):
			worst = maxf(worst, rad_to_deg((pa[b] as Quaternion).angle_to(pb[b])))
	return worst

func _analyze(tag: String, a: Animation) -> void:
	if a == null:
		print('{"anim":"%s","error":"load failed"}' % tag)
		return
	var hips := -1
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_POSITION_3D and _bone_of(a, i) == "Hips":
			hips = i
			break
	var drift := Vector3.ZERO
	var zr := Vector2.ZERO
	if hips >= 0:
		var n := a.track_get_key_count(hips)
		var first: Vector3 = a.track_get_key_value(hips, 0)
		drift = (a.track_get_key_value(hips, n - 1) as Vector3) - first
		var zmin := 1e9
		var zmax := -1e9
		for k in n:
			var v: Vector3 = a.track_get_key_value(hips, k)
			zmin = minf(zmin, v.z)
			zmax = maxf(zmax, v.z)
		zr = Vector2(zmin, zmax)
	var ps := _pose_at(a, false)
	var pe := _pose_at(a, true)
	print(JSON.stringify({
		anim = tag, len = snappedf(a.length, 0.01), tracks = a.get_track_count(),
		hips_drift_xy = snappedf(Vector2(drift.x, drift.y).length(), 0.01),
		hips_z = [snappedf(zr.x, 0.01), snappedf(zr.y, 0.01)],
		legs_degps = int(_group_travel(a, LEGS)), arms_degps = int(_group_travel(a, ARMS)),
		spine_degps = int(_group_travel(a, SPINE)), steps = _cadence(a),
		start_end_diff = snappedf(_pose_diff(ps, pe), 0.1),
		start_vs_idle = snappedf(_pose_diff(ps, _idle_pose), 0.1),
		end_vs_idle = snappedf(_pose_diff(pe, _idle_pose), 0.1),
	}))

func _init():
	var idle := _anim_from_fbx("res://" + FBX[0])
	_idle_pose = _pose_at(idle, false)
	for f in FBX:
		var tag: String = f.replace("Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_", "").replace("_withSkin.fbx", "")
		_analyze(tag, _anim_from_fbx("res://" + f))
	for r in ["yoriichi_draw_sword.res"]:
		_analyze(r, load("res://" + r))
	quit()
