extends SceneTree
## 阿求 正座（seiza）clip：Mixamo 沒有正座，以 Kneeling Idle（跪立：膝著地、小腿平貼地、大腿垂直）為底改成坐在腳跟上。
##   - 膝蓋、腳踝、腳掌世界位置保持原 clip（小腿仍平貼地）；Hips 往後下移，使大腿從膝蓋往後上方傾 thigh_deg 度 → 臀部落在腳跟上
##   - 大腿／小腿以「瞄準」改（只轉最短弧，保留骨頭扭轉）；腳掌保持原世界旋轉
##   - 雙手放到大腿上（兩骨 IK，手腕目標＝大腿 hand_t 處、往上 hand_up、往外 hand_out；手肘朝外後）
##   - 上身（Spine 以上）沿用原 clip 的局部旋轉＝原本的待機呼吸
## godot --headless --path . -s res://tools/akyuu/build_akyuu_seiza.gd -- [--src=res://….res] [--out=res://….res] [--thigh_deg=22]
const GLB := "res://characters/akyuu/akyuu.glb"
var sk: Skeleton3D

func _initialize() -> void: _go.call_deferred()

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="): return a.split("=", true, 1)[1]
	return d

func _g(n: String) -> Transform3D: return sk.get_bone_global_pose(sk.find_bone(n))

## 把骨 n 的全域方向（本骨→子骨）轉到 dir，只轉最短弧；寫回局部旋轉
func _aim(n: String, child: String, dir: Vector3) -> void:
	var b := sk.find_bone(n)
	var g := _g(n)
	var cur := (_g(child).origin - g.origin).normalized()
	var q := Quaternion(cur, dir.normalized())
	var ng := Basis(q) * g.basis
	_set_global_basis(b, ng)

func _set_global_basis(b: int, ng: Basis) -> void:
	var p := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(p).basis if p >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(b, (pg.inverse() * ng).get_rotation_quaternion())

func _go() -> void:
	var src := _arg("src", "res://characters/akyuu/anim/kneel_idle_a030_final.res")
	var out := _arg("out", "res://characters/akyuu/anim/seiza_idle_a030_final.res")
	var thigh_deg := float(_arg("thigh_deg", "20"))
	var hand_t := float(_arg("hand_t", "0.5"))
	var hand_up := float(_arg("hand_up", "0.13"))
	var hand_out := float(_arg("hand_out", "0.035"))
	var foot_down := float(_arg("foot_down", "0"))
	var drop := float(_arg("drop", "0.075"))          # 整體下移：膝蓋皮膚與腳背貼地（實測 0.075 → 身體／鞋最低 −0.5～+0.9 cm）
	var knee_in := float(_arg("knee_in", "0.3"))    # 膝蓋 x 往中線收（1＝不動）
	var ankle_in := float(_arg("ankle_in", "0.3"))  # 腳踝 x 往中線收：腳跟在坐骨下
	var upright := float(_arg("upright", "1.0"))     # 上身（Hips 旋轉、Spine～Head）往 rest 直立拉回的比例
	var m: Node3D = (load(GLB) as PackedScene).instantiate(); root.add_child(m)
	sk = m.find_child("GeneralSkeleton", true, false)
	var ap := AnimationPlayer.new(); m.add_child(ap); ap.root_node = NodePath("../Armature")
	var clip: Animation = load(src)
	var lib := AnimationLibrary.new(); lib.add_animation(&"c", clip); ap.add_animation_library(&"", lib); ap.play(&"c"); ap.speed_scale = 0.0
	var an := Animation.new(); an.length = clip.length; an.loop_mode = Animation.LOOP_LINEAR
	var bones := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "RightShoulder",
		"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
		"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]  # 這些骨的軌道由本腳本重寫
	# 手指沿用原 clip
	for i in clip.get_track_count():
		var pth := str(clip.track_get_path(i))
		var bn := pth.get_slice(":", 1)
		if clip.track_get_type(i) == Animation.TYPE_ROTATION_3D and not (bn in bones):
			var t := an.add_track(Animation.TYPE_ROTATION_3D); an.track_set_path(t, clip.track_get_path(i))
			for k in clip.track_get_key_count(i): an.rotation_track_insert_key(t, clip.track_get_key_time(i, k), clip.track_get_key_value(i, k))
	var rt := {}
	for bn in bones:
		var t := an.add_track(Animation.TYPE_ROTATION_3D); an.track_set_path(t, NodePath("%GeneralSkeleton:" + bn)); rt[bn] = t
	var pt := an.add_track(Animation.TYPE_POSITION_3D); an.track_set_path(pt, NodePath("%GeneralSkeleton:Hips"))
	var n := int(round(clip.length * 30.0))
	var rep := {}
	for f in n + 1:
		var tm := minf(clip.length, f / 30.0)
		ap.seek(tm, true)
		var K := {}; var A := {}; var Fq := {}
		var hx := _g("Hips").origin.x
		for s in ["Left", "Right"]:
			K[s] = _g(s + "LowerLeg").origin + Vector3.DOWN * drop; A[s] = _g(s + "Foot").origin + Vector3.DOWN * drop; Fq[s] = _g(s + "Foot").basis
			K[s].x = hx + (K[s].x - hx) * knee_in; A[s].x = hx + (A[s].x - hx) * ankle_in
		# 上身直立、頭平視：Hips 旋轉與脊椎～頭往 rest 拉回
		for bn in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"]:
			var bi := sk.find_bone(bn)
			sk.set_bone_pose_rotation(bi, sk.get_bone_pose_rotation(bi).slerp(sk.get_bone_rest(bi).basis.get_rotation_quaternion(), upright))
		# 大腿長、目標髖關節
		var d := Vector3.ZERO
		for s in ["Left", "Right"]:
			var hj := _g(s + "UpperLeg").origin
			var L := hj.distance_to(K[s])
			var back: Vector3 = (A[s] - K[s]); back.y = 0; back = back.normalized()
			var want: Vector3 = K[s] + (back * cos(deg_to_rad(thigh_deg)) + Vector3.UP * sin(deg_to_rad(thigh_deg))) * L
			d += (want - hj) * 0.5
		var hb := sk.find_bone("Hips")
		sk.set_bone_pose_position(hb, sk.get_bone_pose_position(hb) + d)   # Hips 無父骨：骨架空間
		for s in ["Left", "Right"]:
			_aim(s + "UpperLeg", s + "LowerLeg", K[s] - _g(s + "UpperLeg").origin)
			_aim(s + "LowerLeg", s + "Foot", A[s] - _g(s + "LowerLeg").origin)
			_set_global_basis(sk.find_bone(s + "Foot"), Fq[s])
			# 腳背平貼地：腳掌（腳踝→腳趾）朝正後方、略往下 foot_down 度
			var bk: Vector3 = (A[s] - K[s]); bk.y = 0; bk = bk.normalized()
			_aim(s + "Foot", s + "Toes", bk * cos(deg_to_rad(foot_down)) + Vector3.DOWN * sin(deg_to_rad(foot_down)))
		# 手放大腿上（兩骨 IK）
		for s in ["Left", "Right"]:
			var hj := _g(s + "UpperLeg").origin; var kn := _g(s + "LowerLeg").origin
			var side := 1.0 if s == "Left" else -1.0
			var tgt := hj.lerp(kn, hand_t) + Vector3.UP * hand_up + Vector3(side * hand_out, 0, 0)
			var sh := _g(s + "UpperArm").origin
			var la := sh.distance_to(_g(s + "LowerArm").origin); var lb := _g(s + "LowerArm").origin.distance_to(_g(s + "Hand").origin)
			var to := tgt - sh; var dl := clampf(to.length(), absf(la - lb) + 0.001, la + lb - 0.001)
			var dirn := to.normalized()
			var pole := (Vector3(side, 0, 0) * 0.8 + Vector3(0, 0, -0.6)).normalized()   # 手肘朝外後
			pole = (pole - dirn * pole.dot(dirn)).normalized()
			var ca := (la * la + dl * dl - lb * lb) / (2.0 * la * dl)
			var elbow := sh + dirn * (la * ca) + pole * (la * sqrt(maxf(0.0, 1.0 - ca * ca)))
			_aim(s + "UpperArm", s + "LowerArm", elbow - sh)
			_aim(s + "LowerArm", s + "Hand", tgt - _g(s + "LowerArm").origin)
			# 手掌朝下、手指沿大腿朝前（略往下貼腿）
			var hb2 := sk.find_bone(s + "Hand")
			sk.set_bone_pose_rotation(hb2, sk.get_bone_rest(hb2).basis.get_rotation_quaternion())   # 手腕打直（局部＝rest）
			if f == 0: rep[s + "_hand_err_m"] = snappedf(_g(s + "Hand").origin.distance_to(tgt), 0.001)
		for bn in bones:
			an.rotation_track_insert_key(rt[bn], tm, sk.get_bone_pose_rotation(sk.find_bone(bn)))
		an.position_track_insert_key(pt, tm, sk.get_bone_pose_position(hb) / sk.motion_scale)   # 軌道值是除以 motion_scale 的正規化值
		if f == 0:
			rep["hips_y"] = snappedf(_g("Hips").origin.y, 0.001); rep["hip_joint_y"] = snappedf(_g("LeftUpperLeg").origin.y, 0.001)
			rep["knee_y"] = snappedf(_g("LeftLowerLeg").origin.y, 0.001); rep["knee_err_m"] = snappedf(_g("LeftLowerLeg").origin.distance_to(K["Left"]), 0.001)
			rep["ankle_err_m"] = snappedf(_g("LeftFoot").origin.distance_to(A["Left"]), 0.001)
	an.resource_name = out.get_file().get_basename()
	var e := ResourceSaver.save(an, out)
	print("SEIZA ", JSON.stringify(rep), " keys ", n + 1, " save ", e, " → ", out)
	quit()
