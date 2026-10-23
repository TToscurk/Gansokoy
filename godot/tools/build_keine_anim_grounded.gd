extends SceneTree
## 慧音用「平滑接地」：同 build_npc_anim_grounded.gd 量每個 Hips key 的接地誤差（最低腳骨－其 rest 高），
## 但不逐 key 硬補（逐 key 補會在左右腳交替處折一下＝走路上下抖，實測 jerk 1.47→3.29），
## 而是對誤差曲線做循環高斯平滑（sigma 秒）後才補到 Hips 高度。
##   godot --headless --path . --script res://tools/build_keine_anim_grounded.gd -- --clip=res://….res --out=res://….res [--sigma=0.08]
##   [--npc=res://….tscn]：預設慧音；阿求等同 mixamo65 family 的角色傳自己的 tscn（量的是該角色自己的腳骨 rest）。
const NPC_DEFAULT := "res://characters/keine/keine.tscn"
const FEET := ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]


func _init() -> void:
	var clip := ""
	var out := ""
	var sigma := 0.08
	var NPC := NPC_DEFAULT
	var resmooth := 0.0   # >0：夾限後再做一次循環高斯平滑（秒）
	var tol := -1.0   # ≥0：平滑後仍陷地超過 tol 的 key 單邊補到 −tol（只補陷地，不補浮起）
	var fixed := NAN  # 指定時：不量腳骨，整支 Hips 固定抬高 fixed 公尺（跪姿：腳背平貼地，腳骨 rest 高度不能當基準；值由網格最低點量得）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.trim_prefix("--clip=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--resmooth="):
			resmooth = a.trim_prefix("--resmooth=").to_float()
		elif a.begins_with("--tol="):
			tol = a.trim_prefix("--tol=").to_float()
		elif a.begins_with("--fixed="):
			fixed = a.trim_prefix("--fixed=").to_float()
		elif a.begins_with("--npc="):
			NPC = a.trim_prefix("--npc=")
		elif a.begins_with("--sigma="):
			sigma = a.trim_prefix("--sigma=").to_float()
	var w: Node3D = (load(NPC) as PackedScene).instantiate()
	w.set("frozen", true)
	root.add_child(w)
	await process_frame
	var sk := w.find_child("GeneralSkeleton", true, false) as Skeleton3D
	var ap := w.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var rest := {}
	for b in FEET:
		rest[b] = sk.get_bone_global_rest(sk.find_bone(b)).origin.y
	var an := (load(clip) as Animation).duplicate(true) as Animation
	var tr := an.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
	var lib := AnimationLibrary.new()
	lib.add_animation(&"c", an)
	ap.add_animation_library(&"tmp", lib)
	ap.play(&"tmp/c")
	ap.speed_scale = 0.0
	var n := an.track_get_key_count(tr)
	var err := PackedFloat32Array()
	var times := PackedFloat32Array()
	for k in n:
		var t := an.track_get_key_time(tr, k)
		times.append(t)
		ap.seek(t, true)
		err.append(_lo(sk, rest))
	# 循環高斯平滑（loop clip：首尾相接）
	var L := an.length
	var sm := PackedFloat32Array()
	for k in n:
		if sigma <= 0.0:
			sm.append(err[k])
			continue
		var acc := 0.0
		var ws := 0.0
		for j in n:
			var d := absf(times[j] - times[k])
			d = minf(d, L - d)
			var wgt := exp(-0.5 * (d / sigma) * (d / sigma))
			acc += err[j] * wgt
			ws += wgt
		sm.append(acc / ws)
	if tol >= 0.0:
		for k in n:
			sm[k] = minf(sm[k], err[k] + tol)
		if resmooth > 0.0:
			sm = _smooth(sm, times, L, resmooth)
	if not is_nan(fixed):
		for k in n:
			sm[k] = -fixed
	for k in n:
		var v: Vector3 = an.track_get_key_value(tr, k)
		an.track_set_key_value(tr, k, v - Vector3(0, sm[k] / sk.motion_scale, 0))
	var after := PackedFloat32Array()
	for k in n:
		ap.seek(times[k], true)
		after.append(_lo(sk, rest))
	an.loop_mode = Animation.LOOP_LINEAR
	an.resource_name = out.get_file().get_basename()
	var e := ResourceSaver.save(an, out)
	print("[KGROUND] %s tol %.3f sigma %.3f keys %d 接地誤差 before %.3f..%.3f → after %.3f..%.3f m save %d → %s" % [clip.get_file(), tol, sigma, n, _mn(err), _mx(err), _mn(after), _mx(after), e, out])
	quit(0 if e == OK else 1)


func _smooth(v: PackedFloat32Array, times: PackedFloat32Array, L: float, sg: float) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	for k in v.size():
		var acc := 0.0
		var ws := 0.0
		for j in v.size():
			var d := absf(times[j] - times[k])
			d = minf(d, L - d)
			var wgt := exp(-0.5 * (d / sg) * (d / sg))
			acc += v[j] * wgt
			ws += wgt
		o.append(acc / ws)
	return o


func _lo(sk: Skeleton3D, rest: Dictionary) -> float:
	var lo := INF
	for b in FEET:
		lo = minf(lo, sk.get_bone_global_pose(sk.find_bone(b)).origin.y - float(rest[b]))
	return lo


func _mn(a: PackedFloat32Array) -> float:
	var m := INF
	for x in a:
		m = minf(m, x)
	return m


func _mx(a: PackedFloat32Array) -> float:
	var m := -INF
	for x in a:
		m = maxf(m, x)
	return m
