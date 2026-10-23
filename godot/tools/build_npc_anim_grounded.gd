extends SceneTree
## P10 R3a NPC：retarget 後の clip を NPC 骨格上で「接地」させた共通 clip を書き出す（再現可能）。
##   godot --headless --path . --script res://tools/build_npc_anim_grounded.gd -- [--dir=res://…] [--clips=a,b,…]
## 入力＝import が save_to_file した <dir>/<clip>.res（GeneralSkeleton＝SkeletonProfileHumanoid のトラック）。
## 各 Hips 位置キーで、最も低い足骨（足首・つま先）が rest の高さに来るよう Hips の高さだけ補正（位置トラックは motion_scale で正規化済み）。
## 出力＝<dir>/<clip>_grounded.res（npc_visual.gd が使う）。
## 2026-10-05：動作は Mixamo のみ（使用者指示）。Mixamo に NPC 本体（Tripo rig）を上傳して書き出した FBX＝同じ骨格。
## --leg_ik（2026-10-21，走路用）：逐 key 抬 Hips 會在蹬地那幾格跳 3–6 cm（走路「抖」）。改成 Hips 只加「平滑基準」
##   （去掉尖峰的中位數 → 高斯平滑），剩下的穿地由該腳的兩骨 IK 把腳踝抬起（膝蓋多彎一點，腳掌朝向不變）。

const NPC := "res://characters/npc/chonin_m01/chonin_m01.tscn"
const FEET := ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]
var leg_ik := false
const DEFAULT_DIR := "res://characters/npc/_shared/anim/mixamo"
const DEFAULT_CLIPS := ["idle_weightshift_a030", "idle_breathing_s0_a030", "idle_neutral_a030",
	"walk_standard_a030", "walk_malestandard_a030", "walk_hurried_a030"]


func _init() -> void:
	var dir := DEFAULT_DIR
	var clips: Array = DEFAULT_CLIPS
	var npc_path := NPC
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.trim_prefix("--dir=")
		elif a.begins_with("--clips="):
			clips = Array(a.trim_prefix("--clips=").split(","))
		elif a.begins_with("--npc="):   # P10 NPC Asset Library：各 NPC の glb（自分の骨格で接地を測る）
			npc_path = a.trim_prefix("--npc=")
		elif a == "--leg_ik":
			leg_ik = true
	var w: Node3D = (load(npc_path) as PackedScene).instantiate()
	w.set("frozen", true)
	root.add_child(w)
	await process_frame
	var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var ap := w.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:   # glb 単体（動作なし）：npc_visual.gd と同じ掛け方
		ap = AnimationPlayer.new()
		w.add_child(ap)
		ap.root_node = NodePath("../Armature")
	var rest := {}
	for b in FEET:
		rest[b] = sk.get_bone_global_rest(sk.find_bone(b)).origin.y
	var fails := 0
	var lib := AnimationLibrary.new()   # library は 1 回だけ追加し、clip ごとに別名で入れる
	ap.add_animation_library(&"tmp", lib)
	for c: String in clips:
		var src: Animation = load("%s/%s.res" % [dir, c])
		var an := src.duplicate(true) as Animation
		var tr := an.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
		if tr < 0:
			print("[NPCANIM] FAIL %s：Hips 位置トラックが無い" % c)
			fails += 1
			continue
		lib.add_animation(StringName(c), an)
		ap.play(StringName("tmp/" + c))
		ap.speed_scale = 0.0
		var before := [INF, -INF]
		var fix := {}
		for k in an.track_get_key_count(tr):
			ap.seek(an.track_get_key_time(tr, k), true)
			var lo := INF
			for b in FEET:
				lo = minf(lo, sk.get_bone_global_pose(sk.find_bone(b)).origin.y - float(rest[b]))
			before[0] = minf(before[0], lo)
			before[1] = maxf(before[1], lo)
			fix[k] = lo
		for k: int in fix:
			if leg_ik: break
			var v: Vector3 = an.track_get_key_value(tr, k)
			an.track_set_key_value(tr, k, v - Vector3(0, float(fix[k]) / sk.motion_scale, 0))
		if leg_ik:
			_ground_leg_ik(an, tr, sk, ap, StringName("tmp/" + c), fix, rest)
		var after := [INF, -INF]
		for k in an.track_get_key_count(tr):
			ap.seek(an.track_get_key_time(tr, k), true)
			var lo := INF
			for b in FEET:
				lo = minf(lo, sk.get_bone_global_pose(sk.find_bone(b)).origin.y - float(rest[b]))
			after[0] = minf(after[0], lo)
			after[1] = maxf(after[1], lo)
		an.resource_name = c
		an.loop_mode = Animation.LOOP_LINEAR
		var out := "%s/%s_grounded.res" % [dir, c]
		var err := ResourceSaver.save(an, out)
		var ok: bool = err == OK and absf(after[0]) < 0.005 and absf(after[1]) < (0.02 if leg_ik else 0.005)   # leg_ik：只保證不穿地，允許擺動腳短暫離地
		if not ok:
			fails += 1
		print("[NPCANIM] %s %s len %.2fs keys %d 接地誤差 before %.3f〜%.3f → after %.4f〜%.4f m → %s" % ["PASS" if ok else "FAIL", c, an.length, an.track_get_key_count(tr), before[0], before[1], after[0], after[1], out])
	quit(fails)


func _arc(a: Vector3, b: Vector3) -> Basis:
	a = a.normalized(); b = b.normalized()
	var ax := a.cross(b)
	if ax.length() < 1e-7:
		return Basis()
	return Basis(ax.normalized(), a.angle_to(b))


## Hips 加平滑基準；仍穿地的那隻腳用兩骨 IK 抬腳踝（腳掌朝向不變）
func _ground_leg_ik(an: Animation, tr: int, sk: Skeleton3D, ap: AnimationPlayer, anim: StringName, fix: Dictionary, rest: Dictionary) -> void:
	var n := an.track_get_key_count(tr)
	var need := []
	for k in n: need.append(-float(fix[k]))
	var med := []
	for k in n:   # 循環中位數（窗 9）去掉蹬地尖峰
		var win := []
		for j in range(-4, 5): win.append(need[(k + j + n) % n])
		win.sort(); med.append(win[4])
	var base := []
	for k in n:   # 循環高斯平滑 σ=1.5 key
		var acc := 0.0; var ws := 0.0
		for j in range(-5, 6):
			var w := exp(-0.5 * pow(j / 1.5, 2)); acc += w * med[(k + j + n) % n]; ws += w
		base.append(acc / ws)
	for k in n:
		var v: Vector3 = an.track_get_key_value(tr, k)
		an.track_set_key_value(tr, k, v + Vector3(0, float(base[k]) / sk.motion_scale, 0))
	var ik_keys := 0; var ik_max := 0.0
	for side in ["Left", "Right"]:
		var bu := sk.find_bone(side + "UpperLeg"); var bl := sk.find_bone(side + "LowerLeg"); var bf := sk.find_bone(side + "Foot"); var bt := sk.find_bone(side + "Toes")
		var tu := an.find_track(NodePath("%GeneralSkeleton:" + side + "UpperLeg"), Animation.TYPE_ROTATION_3D)
		var tl := an.find_track(NodePath("%GeneralSkeleton:" + side + "LowerLeg"), Animation.TYPE_ROTATION_3D)
		var tf := an.find_track(NodePath("%GeneralSkeleton:" + side + "Foot"), Animation.TYPE_ROTATION_3D)
		if tu < 0 or tl < 0 or tf < 0:
			continue
		for k in n:
			var t := an.track_get_key_time(tr, k)
			ap.seek(t, true)
			var lo := minf(sk.get_bone_global_pose(bf).origin.y - float(rest[side + "Foot"]), sk.get_bone_global_pose(bt).origin.y - float(rest[side + "Toes"]))
			if lo > -0.002:
				continue
			var gu := sk.get_bone_global_pose(bu); var gl := sk.get_bone_global_pose(bl); var gf := sk.get_bone_global_pose(bf)
			var H := gu.origin; var K := gl.origin; var A := gf.origin
			var l1 := H.distance_to(K); var l2 := K.distance_to(A)
			var A2 := A + Vector3(0, -lo, 0)
			var D := minf(H.distance_to(A2), l1 + l2 - 1e-4)
			var dir := (A2 - H).normalized()
			var nrm := (K - H).cross(A - H)
			if nrm.length() < 1e-6:
				continue
			var perp := nrm.normalized().cross(dir)
			if perp.dot(K - H) < 0.0: perp = -perp
			var ca := clampf((l1 * l1 + D * D - l2 * l2) / (2.0 * l1 * D), -1.0, 1.0)
			var K2 := H + l1 * (ca * dir + sqrt(1.0 - ca * ca) * perp)
			A2 = H + dir * D
			var R1 := _arc(K - H, K2 - H)
			var nu := R1 * gu.basis
			var R2 := _arc(R1 * (A - K), A2 - K2)
			var nl := R2 * R1 * gl.basis
			var pu := sk.get_bone_global_pose(sk.get_bone_parent(bu)).basis
			_set_rot(an, tu, t, (pu.inverse() * nu).get_rotation_quaternion())
			_set_rot(an, tl, t, (nu.inverse() * nl).get_rotation_quaternion())
			_set_rot(an, tf, t, (nl.inverse() * gf.basis).get_rotation_quaternion())
			ik_keys += 1; ik_max = maxf(ik_max, -lo)
	var bmin: float = base.min(); var bmax: float = base.max()
	print("[NPCANIM]   leg_ik：Hips 平滑基準 %.3f〜%.3f m；IK 抬腳 %d keys，最多 %.3f m" % [bmin, bmax, ik_keys, ik_max])


func _set_rot(an: Animation, trk: int, t: float, q: Quaternion) -> void:
	var i := an.track_find_key(trk, t, Animation.FIND_MODE_APPROX)
	if i >= 0:
		an.track_set_key_value(trk, i, q)
	else:
		an.rotation_track_insert_key(trk, t, q)
