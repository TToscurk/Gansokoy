extends SceneTree
## 阿求 正座轉場：坐下（seiza_sit）／起身（seiza_stand）。
## 來源：Mixamo「Kneeling In Prayer To Standing Up」（pray_to_stand_a030_mx.res）後段＝從跪立單膝前出再站起（日式從正座起身的順序）。
##   起身＝[正座 → 跪立（臀離開腳跟）blend_s 秒] ＋ [來源 t0 之後的起身段，放慢 stretch 倍]
##   坐下＝起身整支時間反轉（站 → 單膝 → 雙膝跪立 → 臀坐回腳跟）
## 水平對位：來源跪立時兩膝中點對齊正座的兩膝中點（膝蓋不在地上滑）；站起後 Hips 相對 idle 的水平差存進 meta "end_offset"，
##   由 akyuu_seiza.gd 在切換 idle 時把角色根節點移過去（坐下前反向移回），所以接 idle 不會滑步。
## 接地：每格 CPU 蒙皮身體（腰以下取樣）＋鞋，最低點貼地（高斯平滑）。
## 袴：SeizaDrape 權重依 Hips 高度（站＝0、正座＝1）寫成 blend shape 軌道。
## godot --headless --path . -s res://tools/akyuu/build_akyuu_seiza_transition.gd -- [--t0=3.9] [--blend_s=1.0] [--stretch=1.25] [--knots=Sit036:1.2,…,SeizaDrape:4.567]
## 注意：--knots 的時間是「坐下 clip」的時間；修正形狀由同一支坐下 clip 逐格布料模擬擷取（bake_akyuu_seiza_drape.py 序列模式），所以 clip 改了要整套重做
const GLB := "res://characters/akyuu/akyuu.glb"
const SRC := "res://characters/akyuu/anim/pray_to_stand_a030_mx.res"
const SEIZA := "res://characters/akyuu/anim/seiza_idle_a030_final.res"
const IDLE := "res://characters/akyuu/anim/idle_female_a030_final.res"
const OUT_STAND := "res://characters/akyuu/anim/seiza_stand_final.res"
const OUT_SIT := "res://characters/akyuu/anim/seiza_sit_final.res"
const FPS := 30.0

var sk: Skeleton3D
var ap: AnimationPlayer
var lib: AnimationLibrary

func _initialize() -> void: _go.call_deferred()

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="): return a.split("=", true, 1)[1]
	return d

func _pose(name: StringName, t: float) -> void:
	ap.play(name); ap.seek(t, true)

func _bp(n: String) -> Vector3: return sk.get_bone_global_pose(sk.find_bone(n)).origin

func _knees() -> Vector3:
	return (_bp("LeftLowerLeg") + _bp("RightLowerLeg")) * 0.5

func _go() -> void:
	var t0 := float(_arg("t0", "3.9")); var blend_s := float(_arg("blend_s", "1.0")); var stretch := float(_arg("stretch", "1.25"))
	var t_end := float(_arg("t_end", "6.75"))
	var m: Node3D = (load(GLB) as PackedScene).instantiate(); root.add_child(m)
	sk = m.find_child("GeneralSkeleton", true, false)
	ap = AnimationPlayer.new(); m.add_child(ap); ap.root_node = NodePath("../Armature")
	var P: Animation = load(SRC); var S: Animation = load(SEIZA); var I: Animation = load(IDLE)
	lib = AnimationLibrary.new(); lib.add_animation(&"P", P); lib.add_animation(&"S", S); lib.add_animation(&"I", I)
	ap.add_animation_library(&"", lib); ap.speed_scale = 0.0
	# 對位：膝中點（水平）
	_pose(&"S", 1.0); await process_frame
	var kS := _knees()
	_pose(&"P", t0); await process_frame
	var kP := _knees()
	var ms := sk.motion_scale   # Hips 位置軌是正規化值（×motion_scale＝公尺）
	var shift := Vector3(kS.x - kP.x, 0, kS.z - kP.z) / ms
	_pose(&"I", 0.0); await process_frame
	var hipI := _bp("Hips")
	# 軌道：取 P 的旋轉軌＋Hips 位置軌
	var rot_tracks := []   # [path, iP, iS]
	var hipP := -1; var hipS := -1
	for t in P.get_track_count():
		var path := P.track_get_path(t)
		if P.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot_tracks.append([path, t, S.find_track(path, Animation.TYPE_ROTATION_3D)])
		elif P.track_get_type(t) == Animation.TYPE_POSITION_3D and str(path).ends_with(":Hips"):
			hipP = t; hipS = S.find_track(path, Animation.TYPE_POSITION_3D)
	var rise_len := (t_end - t0) * stretch
	var L := blend_s + rise_len
	var nf := int(round(L * FPS)) + 1
	var A := Animation.new(); A.length = (nf - 1) / FPS; A.loop_mode = Animation.LOOP_NONE
	var at_rot := []
	for r in rot_tracks:
		var k := A.add_track(Animation.TYPE_ROTATION_3D); A.track_set_path(k, r[0]); at_rot.append(k)
	var at_hip := A.add_track(Animation.TYPE_POSITION_3D); A.track_set_path(at_hip, P.track_get_path(hipP))
	var hip_keys := PackedVector3Array()
	for f in nf:
		var tt := f / FPS
		var u := -1.0; var tp := t0
		if tt < blend_s:
			u = smoothstep(0.0, 1.0, tt / blend_s)
		else:
			tp = minf(t0 + (tt - blend_s) / stretch, t_end)
		for i in rot_tracks.size():
			var r = rot_tracks[i]
			var qP: Quaternion = P.rotation_track_interpolate(r[1], tp)
			var q := qP
			if u >= 0.0:
				var qS: Quaternion = S.rotation_track_interpolate(r[2], 1.0) if r[2] >= 0 else qP
				q = qS.slerp(qP, u)
			A.rotation_track_insert_key(at_rot[i], tt, q)
		var hP: Vector3 = P.position_track_interpolate(hipP, tp) + shift
		var h := hP
		if u >= 0.0:
			var hS: Vector3 = S.position_track_interpolate(hipS, 1.0) if hipS >= 0 else hP
			h = hS.lerp(hP, u)
		hip_keys.append(h)
	# 接地：CPU 蒙皮最低點（身體腰以下每 3 點取 1 + 鞋全取）
	var meshes := []
	for nm in ["身體", "鞋子右", "鞋子左"]:
		var mi := m.find_child(nm, true, false) as MeshInstance3D
		var arr := mi.mesh.surface_get_arrays(0)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]; var B: PackedInt32Array = arr[Mesh.ARRAY_BONES]; var W: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var nbw := B.size() / V.size()
		var idx := PackedInt32Array()
		for i in V.size():
			if nm != "身體" or (V[i].y < 0.7 and i % 3 == 0): idx.append(i)
		meshes.append([mi, V, B, W, nbw, idx])
	var tmp := A.duplicate(true) as Animation
	for f in nf: tmp.position_track_insert_key(at_hip, f / FPS, hip_keys[f])
	lib.add_animation(&"T", tmp)
	var low := PackedFloat32Array(); low.resize(nf)
	var hy := PackedFloat32Array(); hy.resize(nf)
	for f in nf:
		_pose(&"T", minf(f / FPS, tmp.length))
		await process_frame
		var mn := 1e9
		for mm in meshes:
			var mi: MeshInstance3D = mm[0]; var V: PackedVector3Array = mm[1]; var B: PackedInt32Array = mm[2]; var W: PackedFloat32Array = mm[3]; var nbw: int = mm[4]
			var Mb := []
			for j in mi.skin.get_bind_count():
				var bi := mi.skin.get_bind_bone(j)
				if bi < 0: bi = sk.find_bone(mi.skin.get_bind_name(j))
				Mb.append(sk.get_bone_global_pose(bi) * mi.skin.get_bind_pose(j))
			for i in mm[5]:
				var py := 0.0
				for q in nbw:
					var w := W[i * nbw + q]
					if w > 0.0: py += ((Mb[B[i * nbw + q]] as Transform3D) * V[i]).y * w
				mn = minf(mn, py)
		low[f] = mn
	# 平滑（σ 0.08 s）後抬高
	var sig := 0.08 * FPS
	var lift := PackedFloat32Array(); lift.resize(nf)
	for f in nf:
		var s := 0.0; var ws := 0.0
		for g in range(maxi(0, f - int(3 * sig)), mini(nf, f + int(3 * sig) + 1)):
			var w := exp(-0.5 * pow((g - f) / sig, 2)); s += -low[g] * w; ws += w
		lift[f] = s / ws
	var gmin := 1e9; var gmax := -1e9
	for f in nf:
		hip_keys[f].y += lift[f] / ms
		A.position_track_insert_key(at_hip, f / FPS, hip_keys[f])
		gmin = minf(gmin, low[f] + lift[f]); gmax = maxf(gmax, low[f] + lift[f])
	# 袴的姿勢修正權重：
	#  沒給 --knots：SeizaDrape 依 Hips 高度（站＝0、正座＝1）
	#  有給 --knots=名稱:坐下時間,…（坐下 clip 的時間；按時間排序；最後一個通常是 SeizaDrape:<全長>）：
	#    相鄰兩個姿勢之間線性交替（pose-space 修正），第一個之前從 knot0_t 由 0 淡入
	var hipS_y := hip_keys[0].y; var hipStand_y := hip_keys[nf - 1].y
	var mesh_path := str(ap.get_node(ap.root_node).get_path_to(m.find_child("衣身", true, false)))
	var wmid := 0.0
	var knots := []
	for kv in _arg("knots", "").split(",", false):
		var pr := kv.split(":"); knots.append([pr[0], float(pr[1])])
	if knots.is_empty():
		var bs := A.add_track(Animation.TYPE_BLEND_SHAPE); A.track_set_path(bs, NodePath(mesh_path + ":SeizaDrape"))
		for f in nf:
			var w := clampf((hipStand_y - hip_keys[f].y) / (hipStand_y - hipS_y), 0.0, 1.0)
			w = smoothstep(0.0, 1.0, w)
			A.blend_shape_track_insert_key(bs, f / FPS, w)
			if absf(f / FPS - blend_s) < 0.5 / FPS: wmid = w
	else:
		var fade0 := float(_arg("knot0_t", "0.9"))
		var names := []
		for kn in knots:
			if not names.has(kn[0]): names.append(kn[0])
		var tr := {}
		for nm in names:
			var k := A.add_track(Animation.TYPE_BLEND_SHAPE); A.track_set_path(k, NodePath(mesh_path + ":" + nm)); tr[nm] = k
		for f in nf:
			var ts := A.length - f / FPS   # 起身 clip 的第 f 格＝坐下 clip 的 ts 秒
			var w := {}
			for nm in names: w[nm] = 0.0
			if ts <= knots[0][1]:
				w[knots[0][0]] = smoothstep(fade0, knots[0][1], ts)
			elif ts >= knots[knots.size() - 1][1]:
				w[knots[knots.size() - 1][0]] = 1.0
			else:
				for j in knots.size() - 1:
					if ts >= knots[j][1] and ts <= knots[j + 1][1]:
						var u: float = (ts - knots[j][1]) / maxf(knots[j + 1][1] - knots[j][1], 1e-4)
						w[knots[j][0]] += 1.0 - u; w[knots[j + 1][0]] += u
						break
			for nm in names: A.blend_shape_track_insert_key(tr[nm], f / FPS, w[nm])
		wmid = -1.0
	var end_off := Vector3(hip_keys[nf - 1].x * ms - hipI.x, 0, hip_keys[nf - 1].z * ms - hipI.z)   # 公尺
	A.set_meta("end_offset", end_off)
	A.set_meta("src", "Mixamo Kneeling In Prayer To Standing Up 103130903（t0 %.2f–%.2f、放慢 %.2f）＋正座→跪立 %.2f s" % [t0, t_end, stretch, blend_s])
	var e1 := ResourceSaver.save(A, OUT_STAND)
	# 坐下＝時間反轉
	var R := Animation.new(); R.length = A.length; R.loop_mode = Animation.LOOP_NONE
	for t in A.get_track_count():
		var k := R.add_track(A.track_get_type(t)); R.track_set_path(k, A.track_get_path(t))
		for j in A.track_get_key_count(t):
			var tt := A.length - A.track_get_key_time(t, j)
			match A.track_get_type(t):
				Animation.TYPE_ROTATION_3D: R.rotation_track_insert_key(k, tt, A.track_get_key_value(t, j))
				Animation.TYPE_POSITION_3D: R.position_track_insert_key(k, tt, A.track_get_key_value(t, j))
				Animation.TYPE_BLEND_SHAPE: R.blend_shape_track_insert_key(k, tt, A.track_get_key_value(t, j))
	R.set_meta("start_offset", end_off)
	R.set_meta("src", "seiza_stand_final 時間反轉")
	var e2 := ResourceSaver.save(R, OUT_SIT)
	print("TRANS ", JSON.stringify({"len_s": snappedf(A.length, 0.01), "frames": nf, "knee_shift_m": [snappedf(shift.x * ms, 0.001), snappedf(shift.z * ms, 0.001)],
		"ground_after_m": [snappedf(gmin, 0.001), snappedf(gmax, 0.001)], "lift_range_m": [snappedf(Array(lift).min(), 0.001), snappedf(Array(lift).max(), 0.001)],
		"hips_y_seiza_m": snappedf(hipS_y * ms, 0.003), "hips_y_kneel_m": snappedf(hip_keys[int(blend_s * FPS)].y * ms, 0.003), "hips_y_stand_m": snappedf(hipStand_y * ms, 0.003),
		"drape_at_kneel": snappedf(wmid, 0.01), "end_offset_m": [snappedf(end_off.x, 0.001), snappedf(end_off.z, 0.001)], "mesh_track": mesh_path}), " save ", e1, e2)
	quit()
