extends SceneTree
# 決定性 A/B：同一 world 放兩個角色（hair ON / OFF），同步 seek 同一 clip，逐幀比頭髮骨全域位置
# 用法：-- <clip> ['{"k":..,"d":..,"g":..}']
var A: Node3D
var B: Node3D
var skA: Skeleton3D
var skB: Skeleton3D
var apA: AnimationPlayer
var apB: AnimationPlayer
var clip := "TH_Combo_IP"
var f := 0
var nf := 0
var ov := {}
var cam: Camera3D
var shots := []
var view := "back"
const OUT := "D:/神社/shrine/work/yoriichi_mixamo/renders/"
var bones := ["hair_ponytail_root", "hair_ponytail_01", "hair_ponytail_02", "hair_ponytail_03", "hair_side_03.L", "hair_back_03.R", "hair_front_02.L", "haori_back_C_03"]
var mx := {}
var PA := {}
var PB := {}

func _initialize() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0: clip = ua[0]
	if ua.size() > 1: ov = JSON.parse_string(ua[1])
	if ua.size() > 2: shots = Array(ua[2].split(",")).map(func(x): return int(x))
	if ua.size() > 3: view = ua[3]
	var ps: PackedScene = load("res://characters/yoriichi/v2/yoriichi_v2_test.tscn")
	A = ps.instantiate(); B = ps.instantiate()
	A.set_script(null); B.set_script(null)
	root.add_child(A); root.add_child(B)
	B.position = Vector3(-1.5, 0, 0)     # B（無頭髮物理）放角色右手邊 1.5 m，同一鏡頭並排
	for n in [A, B]:
		for cn in ["Views", "ClipLabel", "Floor", "Sun", "Env"]:
			var x: Node = n.get_node_or_null(cn)
			if x and n == B and cn in ["Sun", "Env"]:
				x.queue_free()
			elif x and cn in ["Views", "ClipLabel"]:
				x.queue_free()
	cam = Camera3D.new(); root.add_child(cam); cam.fov = 40.0
	cam.current = true
	skA = A.find_child("GeneralSkeleton", true, false); skB = B.find_child("GeneralSkeleton", true, false)
	apA = A.find_child("AnimationPlayer", true, false); apB = B.find_child("AnimationPlayer", true, false)
	var hB: SpringBoneSimulator3D = skB.get_node("HairSpring"); hB.active = false
	var hA: SpringBoneSimulator3D = skA.get_node("HairSpring")
	for si in hA.get_setting_count():
		if ov.has("k"): hA.set_stiffness(si, ov.k)
		if ov.has("d"): hA.set_drag(si, ov.d)
		if ov.has("g"): hA.set_gravity(si, ov.g)
	print("ABH clip ", clip, " ov ", ov, " hairA joints ", range(hA.get_setting_count()).map(func(q): return hA.get_joint_count(q)), " hairA active ", hA.active, " influence ", hA.influence)
	hA.modification_processed.connect(_on_mod)
	(skB.get_node("HaoriSpring") as SpringBoneSimulator3D).modification_processed.connect(_on_mod_b)
	for ap in [apA, apB]:
		ap.play(clip); ap.pause()
	nf = int(apA.current_animation_length * 30.0)

func _process(_d: float) -> bool:
	f += 1
	var t := minf(f / 30.0, apA.current_animation_length)
	apA.seek(t, true); apB.seek(t, true)
	# 相機：跟 Hips 中點，back = 角色背後斜上，side = 角色左側
	var hips := skA.global_transform * skA.get_bone_global_pose(skA.find_bone("Hips")).origin
	var mid := Vector3(-0.75, hips.y + 0.45, hips.z)
	var eye := mid + (Vector3(0, 0.5, 4.2) if view == "back" else Vector3(4.2, 0.4, 0.0) if view == "side" else Vector3(-1.2, 0.9, -3.8))
	cam.look_at_from_position(eye, mid, Vector3.UP)
	if (f - 1) in shots:
		_shot.call_deferred(f - 1)
	return f >= nf + 2

func _shot(fr: int) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "hab_%s_%s_%03d.png" % [clip, view, fr])

var mq := {}

func _finalize() -> void:
	for fr in PA:
		if not PB.has(fr): continue
		for bn in bones:
			if not PA[fr].has(bn + "#q"): continue
			var qa: Quaternion = PA[fr][bn + "#q"]
			var ang := rad_to_deg(qa.angle_to(PB[fr][bn + "#q"]))
			if ang > mq.get(bn, 0.0): mq[bn] = ang
	print("ABH max_rot_diff_deg ", bones.map(func(b): return [b, snappedf(mq.get(b, 0.0), 0.1)]))
	for fr in PA:
		if not PB.has(fr): continue
		for bn in bones:
			if not PA[fr].has(bn): continue
			var dd: float = PA[fr][bn].distance_to(PB[fr][bn])
			if dd > mx.get(bn, [0.0, 0])[0]:
				mx[bn] = [dd, fr]
	print("ABH max_diff_cm ", bones.map(func(b): return [b, snappedf(mx.get(b, [0.0, 0])[0] * 100, 0.1), mx.get(b, [0.0, 0])[1]]))

func _grab(sk: Skeleton3D) -> Dictionary:
	var d := {}
	for bn in bones:
		var i := sk.find_bone(bn)
		if i >= 0:
			d[bn] = sk.get_bone_global_pose(i).origin
			d[bn + "#q"] = sk.get_bone_global_pose(i).basis.get_rotation_quaternion()
	return d

func _on_mod() -> void:
	if f > 2: PA[f] = _grab(skA)

func _on_mod_b() -> void:
	if f > 2: PB[f] = _grab(skB)
