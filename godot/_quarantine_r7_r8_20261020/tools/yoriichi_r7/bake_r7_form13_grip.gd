extends SceneTree
## R7 P5 十三型派生 clip 的「刀—雙手閉鏈」烘焙（P1 握刀連續性）。
## 問題：build_r7_form13_seams.gd 對左右臂旋轉各自加衰減偏移 → 派生段左手離開刀柄（01→02 f0–5 執行期左手 IK 權重 0；
##       08→09 空中段執行期關 IK，左手停在離柄 0.45 m 的派生姿勢）。
## 作法（不另寫 IK：直接呼叫既有 r62_grip_ik.gd 的 _solve_arm 兩骨解算，關掉 swivel 搜尋、保留動畫彎曲平面）：
##   刀＝右手 × sock_old（authored 刀，派生後的單一刀具變換，右臂／軀幹／腳步／骨盆不動）。
##   左手在刀座標下的握位 rel(f)：第 0 格＝派生 clip 第 0 格（＝上一型出口）的關係，N 格內 smoothstep 過渡到原 clip 同格的關係
##   → 第 0 格與上一型出口相同、第 N 格起與原 clip 逐位元相同；出口單手（左手離柄）時 rel 從離柄過渡到原 clip 的握柄位置＝可見的接柄。
##   權重 g(f)：原 clip 該格是雙手握（左掌心離柄軸 ≤ d0）→1，離柄 ≥ d1 → 0（原動畫有意的單手隨揮不硬改成雙手）。
##   左手目標＝lerp(派生左手, 刀 × rel(f), g)，解左肩→肘→腕，寫回 LeftArm／LeftForeArm／LeftHand 旋轉鍵（只改 f < N 的鍵）。
##   godot --headless --path godot -s res://tools/yoriichi_r7/bake_r7_form13_grip.gd -- probe | bake
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"
const OUT_DIR := "res://characters/yoriichi/v24/anims_r7/form13/"
const SEAMS_SCRIPT := "res://tools/yoriichi_r7/build_r7_form13_seams.gd"
const D0 := 0.045
const D1 := 0.09
## 接柄過程格數（30 fps authored 格）；環境變數 R7P5_REGRASP 可覆寫
var REGRASP := 14
const ARM := ["mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand"]

var _anim: AnimationPlayer
var _sk: Skeleton3D
var _ik
var _ix := {}


func _initialize() -> void:
	call_deferred("_run")


func _b(n: String) -> int:
	if not _ix.has(n):
		_ix[n] = _sk.find_bone(n)
	return _ix[n]


func _seek(aname: String, t: float) -> void:
	_anim.play(aname)
	_anim.speed_scale = 0.0
	_anim.seek(t, true)
	await process_frame
	await process_frame


## 骨架空間：authored 刀、左手、左掌心離柄軸距離、左手在刀座標的關係、肘位置
func _state() -> Dictionary:
	var hr := _sk.get_bone_global_pose(_b("mixamorig_RightHand"))
	var sword: Transform3D = hr * _ik.sock_old
	var lg := _sk.get_bone_global_pose(_b("mixamorig_LeftHand"))
	var lm := _sk.get_bone_global_pose(_b("mixamorig_LeftHandMiddle1"))
	var palm := (lg.origin + lm.origin) * 0.5
	var a: Vector3 = sword * Vector3(0, -0.35, 0)
	var bb: Vector3 = sword * Vector3(0, -0.005, 0)
	var ab := bb - a
	var u := clampf((palm - a).dot(ab) / maxf(1e-9, ab.length_squared()), 0.0, 1.0)
	var d := (palm - (a + ab * u)).length()
	var std: Transform3D = sword * _ik.left_rel
	var qa := lg.basis.orthonormalized().get_rotation_quaternion()
	var qb := std.basis.orthonormalized().get_rotation_quaternion()
	return {"sword": sword, "lg": lg, "d": d, "rel": sword.affine_inverse() * lg,
		"std_mm": lg.origin.distance_to(std.origin) * 1000.0, "std_deg": rad_to_deg(qa.angle_to(qb)),
		"elbow_l": _sk.get_bone_global_pose(_b("mixamorig_LeftForeArm")).origin,
		"tip": sword * Vector3(0, 0.75, 0)}


static func _w(d: float) -> float:
	return 1.0 - smoothstep(D0, D1, d)


func _run() -> void:
	var mode := "probe"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	var seams: Array = load(SEAMS_SCRIPT).SEAMS
	if OS.get_environment("R7P5_REGRASP") != "":
		REGRASP = int(OS.get_environment("R7P5_REGRASP"))
	var w := Node3D.new()
	root.add_child(w)
	var p: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	p.set("r7_vfx_enabled", false)
	w.add_child(p)
	p.set_physics_process(false)
	await process_frame
	(p.get("_tree") as AnimationTree).active = false
	_anim = p.get("_anim")
	_sk = (p.get("_visual") as Node).find_children("*", "Skeleton3D", true, false)[0]
	_ik = p.get("_r62_ik")
	_ik.active = false
	for c in _sk.get_children():
		if c is SkeletonModifier3D:
			(c as SkeletonModifier3D).active = false
	var lib: AnimationLibrary = _anim.get_animation_library(_anim.get_animation_library_list()[0])
	var report := []
	for s in seams:
		var prev_name: String = s[0]
		var fa: int = s[1]
		var n: int = s[3]
		await _seek(prev_name, fa / 30.0)
		var ex := _state()
		for nm in s[2]:
			var on: String = load(SEAMS_SCRIPT).seam_out_name(prev_name, nm)
			var path := OUT_DIR + on.to_snake_case() + ".res"
			var der: Animation = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if der.has_meta("r7c_grip_baked") and mode == "bake":
				push_error("already baked: " + path + "（先跑 build_r7_form13_seams.gd -- save 重建）")
				quit(2)
				return
			if lib.has_animation(on):
				lib.remove_animation(on)
			lib.add_animation(on, der)
			var orig: Animation = _anim.get_animation(nm)
			# 原 clip 與派生 clip 逐格狀態（f = 0..n+3）
			var so := []
			var sd := []
			for f in n + 4:
				await _seek(nm, f / 30.0)
				so.append(_state())
				await _seek(on, f / 30.0)
				sd.append(_state())
			var rel0: Transform3D = sd[0].rel
			var rows := []
			for f in n + 4:
				rows.append({"f": f, "d_orig": snappedf(so[f].d, 0.001), "d_der": snappedf(sd[f].d, 0.001),
					"w_orig": snappedf(_w(so[f].d), 0.01)})
			var r := {"seam": "%s@%d -> %s" % [prev_name, fa, nm], "exit_d": snappedf(ex.d, 0.001), "exit_w": snappedf(_w(ex.d), 0.01), "n": n}
			if mode == "bake":
				# 左臂三骨的旋轉軌
				var tr := {}
				var skel_path := str(orig.track_get_path(0)).get_slice(":", 0)
				for bn in ARM:
					var ti := der.find_track(NodePath(skel_path + ":" + bn), Animation.TYPE_ROTATION_3D)
					if ti < 0:
						push_error("no track " + bn)
						quit(3)
						return
					tr[bn] = ti
				var times := []
				for k in der.track_get_key_count(tr[ARM[0]]):
					var t := der.track_get_key_time(tr[ARM[0]], k)
					if t * 30.0 < float(n) - 1e-4:
						times.append(t)
				var baked := []
				for tv in times:
					var t: float = tv
					var f := t * 30.0
					await _seek(nm, t)
					var o_st := _state()
					await _seek(on, t)
					var d_st := _state()
					var uu := clampf(f / float(mini(n, REGRASP)), 0.0, 1.0)
					var sm := uu * uu * (3.0 - 2.0 * uu)
					var rel: Transform3D = rel0.interpolate_with(o_st.rel, sm)
					var g := _w(o_st.d)
					if f < 0.5:
						g = 0.0   # 第 0 格＝上一型出口，原樣
					var lt: Transform3D = d_st.sword * rel
					var lg: Transform3D = d_st.lg
					var tgt := Transform3D(lg.basis.orthonormalized().slerp(lt.basis.orthonormalized(), g), lg.origin.lerp(lt.origin, g))
					if g > 0.001:
						_ik._solve_arm(_sk, "Left", tgt, 1.0, 1.0 / 30.0, false)
					var q := {}
					for bn in ARM:
						q[bn] = _sk.get_bone_pose_rotation(_b(bn))
					baked.append([t, q, g])
				for e in baked:
					if float(e[2]) <= 0.001:
						continue   # 原 clip 該格本來就單手（有意的單手隨揮）→ 鍵不動
					for bn in ARM:
						var ti: int = tr[bn]
						var k := der.track_find_key(ti, e[0], Animation.FIND_MODE_APPROX)
						if k >= 0:
							der.track_set_key_value(ti, k, e[1][bn])
				der.set_meta("r7c_grip_baked", true)
				der.set_meta("r7c_grip_rel_decay", n)
				der.resource_name = on
				# 回量烘焙後
				for f in n + 4:
					await _seek(on, f / 30.0)
					var st := _state()
					rows[f]["d_bake"] = snappedf(st.d, 0.001)
					rows[f]["g"] = snappedf(baked[f][2], 0.01) if f < baked.size() else 1.0
					var el: Vector3 = st.elbow_l
					rows[f]["el"] = [snappedf(el.x, 0.001), snappedf(el.y, 0.001), snappedf(el.z, 0.001)]
				var err := ResourceSaver.save(der, path)
				print("SAVE ", path, " err=", err)
			r["rows"] = rows
			print(JSON.stringify(r))
			report.append(r)
	var fo := FileAccess.open("user://r7p5_grip_bake_%s.json" % mode, FileAccess.WRITE)
	fo.store_string(JSON.stringify(report, " "))
	fo.close()
	quit(0)
