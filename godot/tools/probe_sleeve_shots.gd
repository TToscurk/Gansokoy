extends SceneTree
# 上半身特寫（袖／肩）：用測試場景本身的 4 個 SubViewport，把相機改成跟 UpperChest 的近景
# 用法：-- <tag> <clip> <frames逗號>   例：-- base GS_ComboSlash_IP 48,66
# 輸出 work/yoriichi_mixamo/renders/sl_<tag>_<clip>_<frame>.png（2x2：Front / Left / Back / Right）
const OUT := "D:/神社/shrine/work/yoriichi_mixamo/renders/"
var S: Node
var sk: Skeleton3D
var ap: AnimationPlayer
var cams := []
var tag := "base"
var clip := "GS_ComboSlash_IP"
var shots := []
var f := 0
var nf := 0
var chest_i := -1

func _initialize() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0: tag = ua[0]
	if ua.size() > 1: clip = ua[1]
	if ua.size() > 2: shots = Array(ua[2].split(",")).map(func(x): return int(x))
	var ov := {}
	if ua.size() > 3: ov = JSON.parse_string(ua[3])
	S = (load("res://characters/yoriichi/v2/yoriichi_v2_test.tscn") as PackedScene).instantiate()
	S.set_script(null)
	root.add_child(S)
	var lbl: Node = S.get_node_or_null("ClipLabel")
	if lbl: lbl.queue_free()
	sk = S.find_child("GeneralSkeleton", true, false)
	ap = S.find_child("AnimationPlayer", true, false)
	for vn in ["Front", "Side (L)", "Back", "TPS"]:
		var c: Camera3D = S.get_node("Views/%s/VP/Cam" % vn)
		c.fov = 38.0
		cams.append(c)
		var l2: Label = S.get_node_or_null("Views/%s/Label" % vn)
		if l2: l2.text = ["Front", "Left", "Back", "Right"][cams.size() - 1]
	chest_i = sk.find_bone("UpperChest")
	# 袖參數覆寫：{"k":..,"d":..,"g":..,"r":..,"kc":[a,b],"torso":r}（torso = 在 clothcol_upperback 加胸廓膠囊、加進袖的 collision）
	var sim: SpringBoneSimulator3D = sk.get_node("HaoriSpring")
	var tcol: SpringBoneCollisionCapsule3D = null
	if ov.has("torso") and sim.get_node_or_null("Col_torso") == null:
		tcol = SpringBoneCollisionCapsule3D.new(); tcol.name = "Col_torso"; sim.add_child(tcol)
		tcol.bone_name = "clothcol_upperback"; tcol.radius = ov.torso; tcol.height = 0.40
	for si in sim.get_setting_count():
		if not String(sim.get_root_bone_name(si)).begins_with("haori_sleeve"):
			continue
		if ov.has("inner_k") and String(sim.get_root_bone_name(si)).begins_with("haori_sleevein"):
			sim.set_stiffness(si, ov.inner_k)
		if ov.has("k"): sim.set_stiffness(si, ov.k)
		if ov.has("d"): sim.set_drag(si, ov.d)
		if ov.has("g"): sim.set_gravity(si, ov.g)
		if ov.has("r"): sim.set_radius(si, ov.r)
		if ov.has("kc"):
			var c3 := Curve.new(); c3.add_point(Vector2(0, ov.kc[0])); c3.add_point(Vector2(1, ov.kc[1])); sim.set_stiffness_damping_curve(si, c3)
		if tcol:
			var n0 := sim.get_collision_count(si)
			sim.set_collision_count(si, n0 + 1)
			sim.set_collision_path(si, n0, sim.get_path_to(tcol))
	sim.reset()
	sim.modification_processed.connect(_on_mod)
	print("SL sleeve settings ", range(sim.get_setting_count()).filter(func(q): return String(sim.get_root_bone_name(q)).begins_with("haori_sleeve")).map(func(q): return [sim.get_root_bone_name(q), sim.get_stiffness(q), sim.get_drag(q), sim.get_gravity(q), sim.get_collision_count(q), sim.get_joint_count(q)]))
	ap.play(clip); ap.pause()
	nf = int(ap.current_animation_length * 30.0)
	var mx := 0
	for s_ in shots: mx = maxi(mx, s_)
	nf = mini(nf, mx + 1)

func _process(_d: float) -> bool:
	f += 1
	var t := minf((f - 1) / 30.0, ap.current_animation_length)
	ap.seek(t, true)
	var c := sk.global_transform * sk.get_bone_global_pose(chest_i).origin
	var tgt := c + Vector3(0, -0.12, 0)
	# 角色面向 +Z（Godot 匯入後），+X = 角色左
	var dirs := [Vector3(0, 0.15, 1), Vector3(1, 0.15, 0), Vector3(0, 0.15, -1), Vector3(-1, 0.15, 0)]
	for i in 4:
		var cam: Camera3D = cams[i]
		cam.look_at_from_position(tgt + dirs[i].normalized() * 1.9, tgt, Vector3.UP)
	if (f - 1) in shots:
		_shot.call_deferred(f - 1)
	return f >= nf + 3

var last := {}
func _on_mod() -> void:
	for bn in ["haori_sleeve_02.L", "haori_sleeve_02.R", "LeftLowerArm", "RightLowerArm"]:
		var i := sk.find_bone(bn)
		if i < 0: continue
		last[bn] = sk.get_bone_global_pose(i)

func _shot(fr: int) -> void:
	if last.has("haori_sleeve_02.L"):
		for s_ in ["L", "R"]:
			var sl: Transform3D = last["haori_sleeve_02." + s_]
			var fa: Transform3D = last[("Left" if s_ == "L" else "Right") + "LowerArm"]
			var down := rad_to_deg(sl.basis.y.normalized().angle_to(Vector3.DOWN))
			print("SL f", fr, " sleeve_02.", s_, " pos ", sl.origin.snapped(Vector3.ONE * 0.001), " bone-axis vs DOWN deg ", snappedf(down, 0.1), " rel-to-forearm ", (fa.affine_inverse() * sl).basis.get_euler().snapped(Vector3.ONE * 0.01))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "sl_%s_%s_%03d.png" % [tag, clip, fr])
	print("SL shot ", clip, " ", fr)
