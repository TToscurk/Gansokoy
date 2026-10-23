extends SceneTree
## 把使用者提供的「盤腿坐」動作（CC_Base 骨架，101 骨）重定向到遊戲的緣一骨架
## （Meshy 24 骨），輸出 characters/yoriichi/animations/yoriichi_meditate.res。
##
##   <godot_console.exe> --path godot --headless --script res://tools/build_meditate_clip.gd
##   （可選：-- --hold=1.5 指定輸出長度秒數）
##
## 來源檔實測（2026-09-22）：
##   characters/yoriichi/anim_src/meditate.fbx ← C:\Users\B365\Downloads\
##   緣一模組半成品\rig\緣一動作新增\盤腿坐.fbx（原始 68.89 MB，抽掉網格/貼圖後 1.99 MB）
##   兩支 clip：0_T-Pose（1 格）與 mixamo.com|Layer0（173 格 24fps）。
##   ⚠ 173 格裡**骨頭完全不動** —— 這是「已完成的盤腿坐定姿」被整段保留，
##     不是循環動作。所以這裡只取一個時間點，輸出「定格用」的短 clip。
##     （Blender 端同一姿勢量到 髖 z=0.224、頭 0.772、腳 0.144，與 Godot 引擎
##       get_bone_global_pose 完全一致 → 兩邊都讀得到正確坐姿。）
##
## ⚠ 來源與遊戲是**不同骨架**，不能照抄軌道。這裡做真正的重定向：
##   1. 來源骨頭在骨骼空間的全域姿態 G_src（**用引擎的 get_bone_global_pose**）
##   2. Δ = G_src.basis × R_src_rest.basis⁻¹      ← 這根骨頭從 rest 轉到現在的
##      世界旋轉（在來源座標系）
##   3. Δ' = C × Δ × C⁻¹                          ← 換到目標座標系
##   4. G_tgt = Δ' × R_tgt_rest                   ← 目標該骨頭的全域姿態
##   5. 軌道寫的是**區域骨姿** pose = rest_local⁻¹ × G_parent⁻¹ × G_tgt
##      （Godot 定義：global = global[parent] × rest_local × pose；根骨 G_parent = I）
##
## ⚠ 為什麼不自己算來源全域姿態：這支 FBX 的動畫軌道與 rest 不是同一個座標系
##   （軌道值像 Z-up、rest 是 Y-up；hips 軌道 (0,0,1.229) vs rest (0,1.229,0)），
##   自己算會得到 2.2 m 的鬼髖高。引擎的 get_bone_global_pose 才是對的 → 直接用它。
##
## 座標系：來源 X 右 / Y 上 / Z 前；目標 X 右 / Z 上 / -Y 前。
## 兩邊 rest 都是 T-pose（來源手 x 0.197→0.772、目標 0.200→0.659），
## 「世界旋轉差」可以直接套 —— 這是重定向的標準前提。
##
## 髖部位置：取「相對 rest 的位移」→ 換座標 → 乘身高比例（來源髖高 1.229 m／
## 目標 0.990 m → 0.806）→ 加回目標 rest → 換成區域骨姿。

const SRC_FBX := "res://characters/yoriichi/anim_src/meditate.fbx"
const BODY_FBX := "res://characters/yoriichi/yoriichi_body.fbx"
const OUT_DEFAULT := "res://characters/yoriichi/animations/yoriichi_meditate.res"
const SRC_CLIP := "mixamo_com"
## 取樣時間：整支都是同一個定姿，取中段最保險
const SAMPLE_TIME := 3.0
## 來源坐姿的**網格**最低點（Blender 量到的世界 z，公尺）：盤腿＋羽織鋪開會比骨頭
## 低很多。來源髖 0.223 m、網格最低 -0.202 m → 網格比髖低 0.425 m。
## 直接照抄這個姿勢會讓緣一陷進地裡（實測：人里土面上只露出一團羽織），
## 所以要按身高比例把整個姿勢抬起來：lift = 0.202 × 0.805 ≈ 0.163 m。
const SRC_MESH_FLOOR := -0.202

## 來源骨頭 → 遊戲骨頭。
## 脊椎：來源 Waist→Spine01→Spine02（3 節）對目標 Spine02→Spine01→Spine（3 節；
## 目標命名是反的 —— 最靠近髖的才叫 Spine02）。頭頸：CC 的 NeckTwist01/02 就是脖子。
const PAIRS := {
	"CC_Base_Hip": "Hips",
	"CC_Base_Waist": "Spine02",
	"CC_Base_Spine01": "Spine01",
	"CC_Base_Spine02": "Spine",
	"CC_Base_NeckTwist01": "neck",
	"CC_Base_Head": "Head",
	"CC_Base_L_Clavicle": "LeftShoulder",
	"CC_Base_L_Upperarm": "LeftArm",
	"CC_Base_L_Forearm": "LeftForeArm",
	"CC_Base_L_Hand": "LeftHand",
	"CC_Base_L_Thigh": "LeftUpLeg",
	"CC_Base_L_Calf": "LeftLeg",
	"CC_Base_L_Foot": "LeftFoot",
	"CC_Base_L_ToeBase": "LeftToeBase",
	"CC_Base_R_Clavicle": "RightShoulder",
	"CC_Base_R_Upperarm": "RightArm",
	"CC_Base_R_Forearm": "RightForeArm",
	"CC_Base_R_Hand": "RightHand",
	"CC_Base_R_Thigh": "RightUpLeg",
	"CC_Base_R_Calf": "RightLeg",
	"CC_Base_R_Foot": "RightFoot",
	"CC_Base_R_ToeBase": "RightToeBase",
}

var _hold := 1.0
var _src: Node
var _tgt: Node
var _src_skel: Skeleton3D
var _tgt_skel: Skeleton3D
var _src_ap: AnimationPlayer
var _map := {}          # 目標骨頭索引 → 來源骨頭索引
var _scale := 1.0
var _tgt_hips := -1
var _hips_goal := Vector3.ZERO
## 來源座標 → 目標座標：X→X、Y(上)→Z(上)、Z(前)→-Y(前)
var _frame := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hold="):
			_hold = float(a.split("=", 1)[1])
	_run.call_deferred()


func _run() -> void:
	_src = (load(SRC_FBX) as PackedScene).instantiate()
	_tgt = (load(BODY_FBX) as PackedScene).instantiate()
	root.add_child(_src)
	root.add_child(_tgt)
	_src_skel = _src.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_tgt_skel = _tgt.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_src_ap = _src.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer

	for s in PAIRS.keys():
		var ti := _tgt_skel.find_bone(String(PAIRS[s]))
		var si := _src_skel.find_bone(String(s))
		if ti < 0 or si < 0:
			push_error("[冥想動作] 對應失敗：%s（來源 %d）→ %s（目標 %d）" % [s, si, PAIRS[s], ti])
			continue
		_map[ti] = si
	print("[冥想動作] 對應 %d 組骨頭；來源 %d 骨、目標 %d 骨" % [
		_map.size(), _src_skel.get_bone_count(), _tgt_skel.get_bone_count()])

	_tgt_hips = _tgt_skel.find_bone("Hips")
	var src_hips := _src_skel.find_bone("CC_Base_Hip")
	var src_rest_h := _src_skel.get_bone_global_rest(src_hips).origin
	var tgt_rest_h := _tgt_skel.get_bone_global_rest(_tgt_hips).origin
	_scale = tgt_rest_h.z / src_rest_h.y
	print("[冥想動作] 來源髖 rest=%s（Y 上）→ 目標髖 rest=%s（Z 上）；身高比例 %.4f" % [
		str(src_rest_h), str(tgt_rest_h), _scale])

	# 播來源 clip 並取樣（定姿，取一個時間點就好）
	_src_ap.play(SRC_CLIP)
	_src_ap.seek(SAMPLE_TIME, true)
	await process_frame
	await process_frame
	var src_pose := _read_source()
	var src_h: Vector3 = (src_pose[src_hips] as Transform3D).origin
	print("[冥想動作] 來源 t=%.1fs：髖=%s（rest 的 %.3f m 下方）；來源 clip 長 %.2fs" % [
		SAMPLE_TIME, str(src_h), src_rest_h.y - src_h.y, _src_ap.get_animation(SRC_CLIP).length])

	var tgt_glob := _retarget(src_pose)
	var out := _emit(tgt_glob)
	var err := ResourceSaver.save(out, OUT_DEFAULT)
	print("[冥想動作] %.2f s、%d 軌道 → %s（%d）" % [
		out.length, out.get_track_count(), OUT_DEFAULT.get_file(), err])
	_report(tgt_glob)
	_src.queue_free()
	_tgt.queue_free()
	quit(0 if err == OK else 1)


## 來源：引擎算好的骨骼空間全域姿態
func _read_source() -> Array:
	var out := []
	out.resize(_src_skel.get_bone_count())
	for i in _src_skel.get_bone_count():
		out[i] = _src_skel.get_bone_global_pose(i)
	return out


## 重定向成目標骨架的全域姿態（骨骼空間）——**對準骨頭方向**版
##
## ⚠ 為什麼不是「把來源的世界旋轉差 Δ 套到目標 rest」：
##   那條公式要求兩邊 rest 的骨頭方向一致。實測這兩個 rig 不一致
##   （髖差 27°、頭差 53°，因為 Meshy 的 Hips 骨朝上前方、CC 的朝正上），
##   誤差會沿脊椎累加 → 算出來頭部跑到 -0.77 m（整個人翻過去）。
##
## 改成：每根骨頭只要求「方向對」——
##   G_tgt.basis = 最短弧(目標 rest 方向 → 來源動畫方向) × 目標 rest basis
## 方向是絕對值，不會累加誤差；扭轉（roll）沿用目標自己的 rest，穩定可預期。
func _retarget(src_glob: Array) -> Array:
	var out := []
	out.resize(_tgt_skel.get_bone_count())
	var worst := 0.0
	var worst_bone := ""
	for i in _tgt_skel.get_bone_count():
		var rest_g := _tgt_skel.get_bone_global_rest(i)
		if not _map.has(i):
			out[i] = rest_g                     # 沒對應的骨頭 → 保持 rest
			continue
		var si: int = _map[i]
		var dir_src: Vector3 = ((src_glob[si] as Transform3D).basis * Vector3.UP).normalized()
		var want: Vector3 = (_frame * dir_src).normalized()
		var rest_b := rest_g.basis
		var rest_dir: Vector3 = (rest_b * Vector3.UP).normalized()
		var q := Quaternion(rest_dir, want)
		var g := (Basis(q) * rest_b).orthonormalized()
		out[i] = Transform3D(g, rest_g.origin)
		var err := rad_to_deg(((g * Vector3.UP).normalized()).angle_to(want))
		if err > worst:
			worst = err
			worst_bone = _tgt_skel.get_bone_name(i)
	print("[冥想動作] 方向對準：最大誤差 %.2f°（%s）" % [worst, worst_bone])
	# 髖的位置另外算
	var si_h: int = _map[_tgt_hips]
	var src_rest_h := _src_skel.get_bone_global_rest(si_h).origin
	var src_now: Vector3 = (src_glob[si_h] as Transform3D).origin
	var tgt_rest_h := _tgt_skel.get_bone_global_rest(_tgt_hips).origin
	var goal: Vector3 = tgt_rest_h + _frame * ((src_now - src_rest_h) * _scale)
	goal.z += -SRC_MESH_FLOOR * _scale      # 抬到「網格剛好踩地」（見 SRC_MESH_FLOOR 註解）
	var th: Transform3D = out[_tgt_hips]
	out[_tgt_hips] = Transform3D(th.basis, goal)
	_hips_goal = goal
	return out


## 產生 .res。⚠ Godot 骨頭模型（實測 tools/_probe_skel_semantics.gd）：
##     global[i] = global[parent] × pose[i]，pose[i] 的**預設值就是 rest**，
##     軌道寫進去的是「相對父骨頭」的完整變換，**沒有** rest × pose 這種事。
##   （我一開始多乘了 rest_local⁻¹，髖就整整低了 0.67 m → 人里土面上只露一團羽織。）
## 所以：
##   旋轉 = global[parent]⁻¹ × G_target
##   髖位置 = 骨骼空間的目標位置（根骨的 global 就是它的 pose）
## 每根對應骨頭都寫位置鍵（= rest 原點），讓這支 clip 自成完整姿勢，
## 不會殘留前一個動作（倒地、走路）的骨頭位移。
func _emit(tgt_glob: Array) -> Animation:
	var poses := _poses(tgt_glob)
	var out := Animation.new()
	out.length = _hold
	out.loop_mode = Animation.LOOP_NONE
	for ti in _map.keys():
		var pose: Transform3D = poses[ti]
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, "Armature/Skeleton3D:" + _tgt_skel.get_bone_name(ti))
		out.track_set_interpolation_type(tr, Animation.INTERPOLATION_LINEAR)
		var q := pose.basis.get_rotation_quaternion().normalized()
		out.track_insert_key(tr, 0.0, q)
		out.track_insert_key(tr, _hold, q)
		var tp := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(tp, "Armature/Skeleton3D:" + _tgt_skel.get_bone_name(ti))
		out.track_insert_key(tp, 0.0, pose.origin)
		out.track_insert_key(tp, _hold, pose.origin)
	return out


## 每根骨頭要寫進軌道的「相對父骨頭變換」（沒對應的維持 rest）
func _poses(tgt_glob: Array) -> Array:
	var out := []
	out.resize(_tgt_skel.get_bone_count())
	for i in _tgt_skel.get_bone_count():
		var rest := _tgt_skel.get_bone_rest(i)
		if not _map.has(i):
			out[i] = rest
			continue
		var p := _tgt_skel.get_bone_parent(i)
		var gpar: Basis = Basis() if p < 0 else (tgt_glob[p] as Transform3D).basis
		var basis := (gpar.inverse() * (tgt_glob[i] as Transform3D).basis).orthonormalized()
		out[i] = Transform3D(basis, rest.origin)
	if _tgt_hips >= 0:
		out[_tgt_hips] = Transform3D((out[_tgt_hips] as Transform3D).basis, _hips_goal)
	return out


## 回報：用真正的正向運動學算一次目標骨架的坐姿全域位置
## 模型（見 _emit 註解）：global[i] = global[parent] × pose[i]
func _fk(tgt_glob: Array) -> Array:
	var poses := _poses(tgt_glob)
	var n := _tgt_skel.get_bone_count()
	var out := []
	out.resize(n)
	for i in n:
		var p := _tgt_skel.get_bone_parent(i)
		var gpar: Transform3D = Transform3D() if p < 0 else (out[p] as Transform3D)
		out[i] = gpar * (poses[i] as Transform3D)
	return out


func _report(tgt_glob: Array) -> void:
	var g := _fk(tgt_glob)
	var watch := ["Hips", "Head", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase",
		"LeftHand", "RightHand"]
	var line := "[冥想動作] 重定向後高度（m）："
	var low := INF
	for w in watch:
		var i := _tgt_skel.find_bone(w)
		if i >= 0:
			line += " %s=%.3f" % [w, (g[i] as Transform3D).origin.z]
	for i in _tgt_skel.get_bone_count():
		low = minf(low, (g[i] as Transform3D).origin.z)
	print(line)
	print("[冥想動作] 最低骨頭=%.3f m；對照站立 Idle 髖=0.948" % low)
	for b in ["Hips", "Spine02", "Spine01", "Spine", "neck", "Head", "LeftUpLeg", "LeftLeg", "LeftFoot"]:
		var i := _tgt_skel.find_bone(b)
		if i < 0:
			continue
		print("  %-10s 全域=%s 區域rest偏移=%s 方向=%s" % [b,
			str((g[i] as Transform3D).origin.snappedf(0.001)),
			str(_tgt_skel.get_bone_rest(i).origin.snappedf(0.001)),
			str(((g[i] as Transform3D).basis * Vector3.UP).snappedf(0.01))])
