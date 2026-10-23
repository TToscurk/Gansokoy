extends SceneTree
## 量一支 .res 套到遊戲緣一骨架後的實際高度：逐格讀 Skeleton3D.get_bone_global_pose()，
## 回報腳部骨最低 Z（＝腳底離地）與髖 Z。用來建立「貼地基準」與驗收新產出的 clip。
##
##   <godot_console.exe> --path godot --headless --script res://tools/_probe_clip_foot.gd -- \
##       --anim=res://characters/yoriichi/animations/yoriichi_idle_grounded.res [--also=...]
##
## 這支是驗收用探針，刻意與 build_mixamo_clip.gd 分開（後者輸出、前者量測）。

const BODY_FBX := "res://characters/yoriichi/yoriichi_body.fbx"
const FOOT_BONES := ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]
const WATCH := ["Hips", "Head", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]

var _anims: Array[String] = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--anim="):
			_anims.append(a.split("=", 1)[1])
		elif a.begins_with("--also="):
			_anims.append(a.split("=", 1)[1])
	if _anims.is_empty():
		_anims = [
			"res://characters/yoriichi/animations/yoriichi_idle_grounded.res",
			"res://characters/yoriichi/animations/yoriichi_run_fast.res",
			"res://characters/yoriichi/animations/yoriichi_roll_dodge.res",
		]
	_run.call_deferred()


func _run() -> void:
	var body: Node = (load(BODY_FBX) as PackedScene).instantiate()
	root.add_child(body)
	var skel := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hips_i := skel.find_bone("Hips")
	print("[foot] 目標骨 %d 根；站立 rest 髖=%s" % [skel.get_bone_count(),
		str(skel.get_bone_global_rest(hips_i).origin.snappedf(0.001))])

	# rest（T-pose）狀態下的參考高度
	var rest_lo := INF
	for b in FOOT_BONES:
		var i := skel.find_bone(b)
		if i >= 0:
			rest_lo = minf(rest_lo, skel.get_bone_global_rest(i).origin.z)
	print("[foot] rest（T-pose）腳部骨最低 Z = %+.4f（純骨架參考，不是貼地值）" % rest_lo)

	var ap := AnimationPlayer.new()
	body.add_child(ap)
	var lib := AnimationLibrary.new()
	ap.add_animation_library("", lib)

	var idx := 0
	for path in _anims:
		var anim: Animation = load(path)
		if anim == null:
			print("[foot] 載入失敗 %s" % path)
			continue
		idx += 1
		var clip_name := "clip%d" % idx
		lib.add_animation(clip_name, anim)
		ap.play(clip_name)
		var frames := int(round(anim.length * 30.0))
		if frames < 1:
			frames = 1
		var lo_series := []
		var hi_bone := {}
		var hips_series := []
		var watch_series := {}
		for w in WATCH:
			watch_series[w] = []
		for k in frames:
			ap.seek(float(k) / 30.0, true)
			await process_frame
			var lo := INF
			for b in FOOT_BONES:
				var i := skel.find_bone(b)
				if i >= 0:
					lo = minf(lo, skel.get_bone_global_pose(i).origin.z)
			lo_series.append(lo)
			for w in WATCH:
				var i := skel.find_bone(w)
				if i >= 0:
					watch_series[w].append(skel.get_bone_global_pose(i).origin.z)
		var lo_min := INF
		var lo_max := -INF
		for v in lo_series:
			lo_min = minf(lo_min, v)
			lo_max = maxf(lo_max, v)
		var hz: Array = watch_series["Hips"]
		print("[foot] %-46s %3d格 %.2fs | 腳底Z %+.4f~%+.4f | 髖Z %.4f~%.4f | 頭Z %.3f" % [
			path.get_file().replace(".res", ""), frames, anim.length, lo_min, lo_max,
			hz.min(), hz.max(), (watch_series["Head"] as Array)[0]])
		ap.stop()
	quit(0)
