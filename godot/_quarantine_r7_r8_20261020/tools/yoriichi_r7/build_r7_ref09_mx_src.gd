extends "res://tools/v24_anim/build_v24_anims.gd"
## R7 REF09 Mixamo 來源預覽專用（不改共用 build_v24_anims.gd）：沿用其重定向（世界旋轉差量、rest 髖高比例、貼地），
## 只多做兩件事：(1) key 前綴 r09_ → 先找 R7 自有素材資料夾，再找共用 mixamo/；(2) 把來源 Hips 水平軌跡補回（只供離線看片）。
## 輸出只寫 res://characters/yoriichi/v24_r7/ref09_mx/<key>.res，不碰 v24/anims。
##   godot --headless --path godot -s res://tools/yoriichi_r7/build_r7_ref09_mx_src.gd -- r09_ss_jump_atk,r09_gs_jump_atk
const R7_SRC := "res://characters/yoriichi/v24_r7/ref09_mx/"
const R7_OUT := "res://characters/yoriichi/v24_r7/ref09_mx/"

func _src_path(key: String) -> String:
	var name := key.trim_prefix("r09_").trim_suffix("_diag")
	return R7_SRC + name + ".fbx" if ResourceLoader.exists(R7_SRC + name + ".fbx") else SRC_DIR + name + ".fbx"

func _load_src(key: String) -> Array:
	var path := _src_path(key)
	if not ResourceLoader.exists(path):
		push_error("缺來源 " + path)
		return []
	var src: Node3D = (load(path) as PackedScene).instantiate()
	root.add_child(src)
	var sk: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	var best := ""
	for n in ap.get_animation_list():   # 取最長的 take（避開 1 格的 T-Pose）
		if best == "" or ap.get_animation(n).length > ap.get_animation(best).length:
			best = n
	var ws := src.global_transform.affine_inverse() * sk.global_transform
	return [src, sk, ap.get_animation(best), ws, str(src.get_path_to(sk)) + ":"]

func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_tsk = _tgt.find_child("Skeleton3D", true, false)
	for i in _tsk.get_bone_count():
		var p := _tsk.get_bone_parent(i)
		_t_rest_g[i] = (_t_rest_g[p] as Transform3D) * _tsk.get_bone_rest(i) if p >= 0 else _tsk.get_bone_rest(i)
		if _tsk.get_bone_name(i).begins_with("mixamorig_"):
			_t_body.append(i)
	_measure_target_idle()
	var args := OS.get_cmdline_user_args()
	for k in Array(args[0].split(",")):
		var a := build_clip(k)
		if a == null:
			continue
		_add_horizontal(k, a)
		if (k as String).ends_with("_diag"):
			_reorient(a, 55.0)
		print("R09_BUILT ", k, " len=", snappedf(a.length, 0.001), " err=", ResourceSaver.save(a, R7_OUT + k + ".res"))
	quit()
	return true

## 來源 Hips 水平位移 × 髖高比例，加回 freeze 後固定在 rest 的 x/z（與 build_clip 同一換算）。
func _add_horizontal(key: String, out: Animation) -> void:
	var L := _load_src(key)
	var sk: Skeleton3D = L[1]
	var a: Animation = L[2]
	var ws: Transform3D = L[3]
	var hs := sk.find_bone("mixamorig_Hips")
	var rg := Transform3D.IDENTITY
	var chain: Array[int] = []
	var b := hs
	while b >= 0:
		chain.push_front(b)
		b = sk.get_bone_parent(b)
	for c in chain:
		rg = rg * sk.get_bone_rest(c)
	var s_rest: Vector3 = ws * rg.origin
	var t_rest: Vector3 = (_t_rest_g[_tsk.find_bone("mixamorig_Hips")] as Transform3D).origin
	var k := t_rest.y / maxf(s_rest.y, 0.001)
	var pt := -1
	for t in out.get_track_count():
		if out.track_get_type(t) == Animation.TYPE_POSITION_3D:
			pt = t
	var travel := 0.0
	for i in out.track_get_key_count(pt):
		var tt := out.track_get_key_time(pt, i)
		var g := _fk(sk, _sample_local(a, sk, minf(tt, a.length), L[4]))
		var hw: Vector3 = ws * (g[hs] as Transform3D).origin
		var v: Vector3 = out.track_get_key_value(pt, i)
		v.x = t_rest.x + (hw.x - s_rest.x) * k
		v.z = t_rest.z + (hw.z - s_rest.z) * k
		out.track_set_key_value(pt, i, v)
		travel = Vector2(v.x - t_rest.x, v.z - t_rest.z).length()
	print("R09_TRAVEL ", key, " end_xz=", snappedf(travel, 0.01), " m")
	(L[0] as Node).queue_free()


## REF09 改造實驗：只改「全身取向」一層（Hips 旋轉），子骨局部動作（腿、脊柱、手、落地壓縮）全部保留。
## θ = 身體上軸在「前進／上」平面內的前翻角（逐格展開、連續）。原本繞左右軸 k 轉 θ；改成繞斜軸 m(θ) 轉同樣的 θ：
##   m = normalize(k·cosα + up·sinα)，α(θ) = α_max·sin²(θ/2)（θ 夾在 0..360）。
## θ≈0（地面、起跳）與 θ≈360（觸地）時 α→0 → 與原素材完全相同；中段變成斜向翻轉＋轉體，不完整倒立。
## 時序／角速度沿用原素材 θ(t)，旋轉中心＝骨盆（接近重心），四元數合成，無 Euler 縮放。
func _reorient(out: Animation, a_max: float) -> void:
	var hb := _tsk.find_bone("mixamorig_Hips")
	var parent_g := Basis()
	if _tsk.get_bone_parent(hb) >= 0:
		parent_g = (_t_rest_g[_tsk.get_bone_parent(hb)] as Transform3D).basis.orthonormalized()
	var q0 := (_t_rest_g[hb] as Transform3D).basis.orthonormalized().get_rotation_quaternion()
	var u_rest := ((_t_rest_g[_tsk.find_bone("mixamorig_Spine1")] as Transform3D).origin - (_t_rest_g[hb] as Transform3D).origin).normalized()
	var rt := -1
	var pt := -1
	for t in out.get_track_count():
		if str(out.track_get_path(t)).ends_with(":mixamorig_Hips"):
			if out.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				rt = t
			elif out.track_get_type(t) == Animation.TYPE_POSITION_3D:
				pt = t
	var n := out.track_get_key_count(rt)
	var p0: Vector3 = out.track_get_key_value(pt, 0)
	var p1: Vector3 = out.track_get_key_value(pt, out.track_get_key_count(pt) - 1)
	var fwd := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
	var up := Vector3.UP
	var k := up.cross(fwd).normalized()
	var pq := parent_g.get_rotation_quaternion()
	var prev := 0.0
	var unwrap := 0.0
	var rows := []
	for i in n:
		var ql: Quaternion = out.track_get_key_value(rt, i)
		var qg := pq * ql
		var u := (qg * q0.inverse()) * u_rest
		var raw := atan2(u.dot(fwd), u.dot(up))
		if i > 0:
			var d := wrapf(raw - prev, -PI, PI)
			unwrap += d
		else:
			unwrap = raw
		prev = raw
		var th := unwrap
		var th_c := clampf(th, 0.0, TAU)
		var al := deg_to_rad(a_max) * pow(sin(th_c * 0.5), 2.0)
		var m := (k * cos(al) + up * sin(al)).normalized()
		var corr := Quaternion(m, th) * Quaternion(k, th).inverse()
		var qn := pq.inverse() * (corr * qg)
		out.track_set_key_value(rt, i, qn.normalized())
		if i % 5 == 0:
			var un := ((pq * qn) * q0.inverse()) * u_rest
			rows.append([i, snappedf(rad_to_deg(th), 1), snappedf(rad_to_deg(al), 1),
				snappedf(rad_to_deg(u.angle_to(up)), 1), snappedf(rad_to_deg(un.angle_to(up)), 1)])
	print("R09_REORIENT a_max=%s  [frame, flip_deg, axis_tilt_deg, body_tilt_src, body_tilt_new]" % a_max)
	print("  ", JSON.stringify(rows))
