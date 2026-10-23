extends Node3D
## 驗證用（headless 可跑）：同一支走路，A=彈簧骨關閉、B=彈簧骨開啟；逐格記錄骨頭姿勢到 user://v24_springs_samples.json
## 用法：godot --headless --path godot res://characters/yoriichi/v24/verify_v24_springs.tscn
const MODEL := preload("res://characters/yoriichi/v24/yoriichi_v24.glb")
const DT := 1.0 / 60.0
const WARMUP := 180
var cases: Array[Dictionary] = []
var step_index := -1
var SAMPLES := 74
var walk_name := "walk"

func _ready() -> void:
	set_process(false)
	for spec in [["A_OFF", false, -0.6], ["B_ON", true, 0.6]]:
		var rig := YoriichiV24Rig.new()
		rig.springs_enabled = spec[1]
		rig.start_motion = OS.get_environment("VERIFY_WALK") if OS.get_environment("VERIFY_WALK") != "" else "walk"
		if OS.get_environment("RIG_ARMS") == "1": rig.sleeve_collide_arms = true
		if OS.get_environment("RIG_TX") != "": rig.torso_collider_extra = float(OS.get_environment("RIG_TX"))
		if OS.get_environment("RIG_SR") != "": rig.sleeve_joint_radius = float(OS.get_environment("RIG_SR"))
		if OS.get_environment("RIG_K") != "": rig.sleeve_stiffness = float(OS.get_environment("RIG_K"))
		if OS.get_environment("RIG_G") != "": rig.sleeve_gravity = float(OS.get_environment("RIG_G"))
		rig.add_child(MODEL.instantiate())
		rig.position.x = spec[2]
		if OS.get_environment("VERIFY_SCALE") != "": rig.scale = Vector3.ONE * float(OS.get_environment("VERIFY_SCALE"))
		add_child(rig)
		var sk := rig.skeleton
		var ap := rig.anim_player
		sk.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var c := {"tag": spec[0], "rig": rig, "sk": sk, "ap": ap, "snap": {}, "sig": -99}
		sk.skeleton_updated.connect(func():
			c.snap = _snapshot(sk)
			c.sig = step_index)
		cases.append(c)
	await get_tree().process_frame
	for c in cases:
		for s in c.rig._sims: s.reset()
	await _run()

func _snapshot(sk: Skeleton3D) -> Dictionary:
	var out := {}
	for i in sk.get_bone_count():
		var t := sk.get_bone_global_pose(i)
		var b := t.basis
		out[sk.get_bone_name(i)] = [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]
	return out

func _run() -> void:
	var rows := {"A_OFF": [], "B_ON": []}
	var rest := {}
	var sk0: Skeleton3D = cases[0].sk
	for i in sk0.get_bone_count():
		var t := sk0.get_bone_global_rest(i)
		var b := t.basis
		rest[sk0.get_bone_name(i)] = [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]
	walk_name = OS.get_environment("VERIFY_WALK") if OS.get_environment("VERIFY_WALK") != "" else "walk"
	var length: float = (cases[0].ap as AnimationPlayer).get_animation(walk_name).length
	SAMPLES = int(round(length / DT))
	for n in range(WARMUP + SAMPLES):
		step_index = n
		for c in cases:
			var ap: AnimationPlayer = c.ap
			ap.seek(fposmod(float(n) * DT, length), true)
			ap.advance(0.0)
			(c.sk as Skeleton3D).advance(DT)
		await get_tree().process_frame
		if n < WARMUP: continue
		for c in cases:
			assert(c.sig == n, "skeleton_updated 與手動步進不一致")
			rows[c.tag].append(c.snap.duplicate(true))
	var f := FileAccess.open("user://v24_springs_samples" + OS.get_environment("VERIFY_SCALE") + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"dt": DT, "warmup": WARMUP, "walk_length_s": length, "rest": rest, "frames": rows,
		"config": {"torso_extra": cases[1].rig.torso_collider_extra, "sleeve_r": cases[1].rig.sleeve_joint_radius, "sleeve_k": cases[1].rig.sleeve_stiffness, "sleeve_g": cases[1].rig.sleeve_gravity}}))
	print("V24_SPRING_SAMPLES ", ProjectSettings.globalize_path("user://v24_springs_samples.json"), " len=", length, " sims=", cases[1].rig._sims.size())
	get_tree().quit()
