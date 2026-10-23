extends SceneTree
## 逐格關節稽核：每一格量骨骼方向，抓「相鄰兩格之間的方向突跳（POP）」與髖位置跳動。
## 支援兩種來源，用來判定 POP 是**來源動作本來就有**還是**重定向造成的**：
##   --rig=tgt（預設）：讀 .res，套在遊戲緣一骨架上（24 骨）
##   --rig=src        ：讀 Mixamo/AccuRig 原始 .fbx（CC_Base 約 101 骨），取最長 take
##
##   <godot_console.exe> --path godot --headless --script res://tools/_audit_clip_joints.gd -- \
##       [--dir=res://...] [--rig=tgt|src] [--pop=25] [--hips=0.15] [--only=名字]
##
## ⚠ 膝／肘「反折」判定已**移除**：原本用 cross(上段,下段)·上段側軸 的正負號，
##   但腿打直時 cross 趨近零、正負號變雜訊 → 22 支裡 15 支誤報。改為只輸出彎折角度範圍
##   （供人判斷有無異常），不自動下反折結論。

const BODY := "res://characters/yoriichi/yoriichi_body.fbx"
const DEFAULT_DIR := "res://characters/yoriichi/animations/_mixamo_staging"
const DEFAULT_SRC_DIR := "res://characters/yoriichi/anim_src/_mixamo_incoming"
const FPS := 30.0

const LIMBS_TGT := [
	["LeftUpLeg", "LeftLeg", "左膝"], ["RightUpLeg", "RightLeg", "右膝"],
	["LeftArm", "LeftForeArm", "左肘"], ["RightArm", "RightForeArm", "右肘"],
]
const LIMBS_SRC := [
	["CC_Base_L_Thigh", "CC_Base_L_Calf", "左膝"], ["CC_Base_R_Thigh", "CC_Base_R_Calf", "右膝"],
	["CC_Base_L_Upperarm", "CC_Base_L_Forearm", "左肘"], ["CC_Base_R_Upperarm", "CC_Base_R_Forearm", "右肘"],
]

var _dir := DEFAULT_DIR
var _rig := "tgt"
var _pop := 25.0
var _hips_jump := 0.15
var _only := ""


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			_dir = a.split("=", 1)[1]
		elif a.begins_with("--rig="):
			_rig = a.split("=", 1)[1]
		elif a.begins_with("--pop="):
			_pop = float(a.split("=", 1)[1])
		elif a.begins_with("--hips="):
			_hips_jump = float(a.split("=", 1)[1])
		elif a.begins_with("--only="):
			_only = a.split("=", 1)[1]
	if _rig == "src" and _dir == DEFAULT_DIR:
		_dir = DEFAULT_SRC_DIR
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var names := []
	if _only != "":
		names.append(_only)
	else:
		var d := DirAccess.open(_dir)
		var ext := ".fbx" if _rig == "src" else ".res"
		for f in d.get_files():
			if f.to_lower().ends_with(ext):
				names.append(f.replace(ext, ""))
	names.sort()
	var limbs: Array = LIMBS_SRC if _rig == "src" else LIMBS_TGT
	print("[joint] rig=%s 來源 %s（%d 支）；POP 門檻 %.0f°/格、髖跳動 %.2f m" % [
		_rig, _dir, names.size(), _pop, _hips_jump])

	if _rig == "src":
		# 來源模式：每支各自實例化（每支 FBX 一個骨架）
		for nm in names:
			var node: Node = (load("%s/%s.fbx" % [_dir, nm]) as PackedScene).instantiate()
			root.add_child(node)
			await _settle(4)
			var sk := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var ap := node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
			await _audit(sk, ap, nm, limbs)
			node.queue_free()
			await _settle(2)
	else:
		var body: Node = (load(BODY) as PackedScene).instantiate()
		root.add_child(body)
		var sk := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var ap := AnimationPlayer.new()
		body.add_child(ap)
		ap.add_animation_library("", AnimationLibrary.new())
		var lib := ap.get_animation_library("")
		var i := 0
		for nm in names:
			var anim: Animation = load("%s/%s.res" % [_dir, nm])
			if anim == null:
				print("[joint] 載入失敗 %s" % nm)
				continue
			i += 1
			var cn := "c%d" % i
			lib.add_animation(cn, anim)
			ap.play(cn)
			await _audit(sk, ap, nm, limbs)
	quit(0)


func _audit(sk: Skeleton3D, ap: AnimationPlayer, label: String, limbs: Array) -> void:
	# 取最長 take（來源檔同時帶 0_T-Pose 一格）
	if ap.get_animation_list().size() > 1:
		var best := ""
		var bl := -1.0
		for a in ap.get_animation_list():
			var an := ap.get_animation(a)
			if an != null and an.length > bl:
				bl = an.length
				best = a
		if best != "":
			ap.play(best)
	var len_s := 0.0
	for a in ap.get_animation_list():
		if ap.current_animation == a:
			len_s = ap.get_animation(a).length
	if len_s <= 0.0 and ap.get_animation_list().size() > 0:
		len_s = ap.get_animation(ap.get_animation_list()[0]).length
	var frames := maxi(1, int(round(len_s * FPS)))

	var n := sk.get_bone_count()
	var prev_dir := []
	var prev_hips := Vector3.ZERO
	var has_prev := false
	var pop_worst := 0.0
	var pop_at := -1
	var pop_bone := ""
	var pop_count := 0
	var over_list := {}
	var hips_worst := 0.0
	var hips_at := -1
	var limb_range := {}
	for k in frames:
		ap.seek(float(k) / FPS, true)
		await _settle(2)
		var dirs := []
		dirs.resize(n)
		for i in n:
			dirs[i] = (sk.get_bone_global_pose(i).basis * Vector3.UP).normalized()
		var hz: Vector3 = sk.get_bone_global_pose(0).origin
		if has_prev:
			for i in n:
				var a: float = rad_to_deg((prev_dir[i] as Vector3).angle_to(dirs[i]))
				if a > pop_worst:
					pop_worst = a
					pop_at = k
					pop_bone = sk.get_bone_name(i)
				if a > _pop:
					pop_count += 1
					over_list[sk.get_bone_name(i)] = int(over_list.get(sk.get_bone_name(i), 0)) + 1
			var dh: float = (hz - prev_hips).length()
			if dh > hips_worst:
				hips_worst = dh
				hips_at = k
		for L in limbs:
			var pi := sk.find_bone(String(L[0]))
			var ci := sk.find_bone(String(L[1]))
			if pi < 0 or ci < 0:
				continue
			var bend: float = rad_to_deg((dirs[pi] as Vector3).angle_to(dirs[ci] as Vector3))
			var key: String = L[2]
			if not limb_range.has(key):
				limb_range[key] = [bend, bend]
			else:
				limb_range[key][0] = minf(limb_range[key][0], bend)
				limb_range[key][1] = maxf(limb_range[key][1], bend)
		prev_dir = dirs
		prev_hips = hz
		has_prev = true

	var limb_txt := []
	for L in limbs:
		var key: String = L[2]
		if limb_range.has(key):
			limb_txt.append("%s %.0f~%.0f°" % [key, limb_range[key][0], limb_range[key][1]])
	var top := []
	var ks := over_list.keys()
	ks.sort_custom(func(x, y): return int(over_list[x]) > int(over_list[y]))
	for b in ks.slice(0, 3):
		top.append("%s×%d" % [b, over_list[b]])
	print("[joint] %-38s %3d格 | POP 最大 %5.0f° @f%-3d(%-12s) 超標%3d次 %s | 髖跳動 %.3fm | %s" % [
		label, frames, pop_worst, pop_at, pop_bone, pop_count,
		("[" + " ".join(top) + "]") if top.size() > 0 else "", hips_worst, " ".join(limb_txt)])
