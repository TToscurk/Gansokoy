extends SceneTree
## 把 Mixamo／AccuRig 下載回來的動作（CC_Base 骨架，101 骨）**逐格**重定向到
## 遊戲的緣一骨架（Meshy 24 骨），輸出 characters/yoriichi/animations/<name>.res。
##
## 用法（可單檔或整個資料夾）：
##   <godot_console.exe> --path godot --headless --script res://tools/build_mixamo_clip.gd -- \
##       --dir=res://characters/yoriichi/anim_src/_mixamo_incoming \
##       --out=res://characters/yoriichi/animations/_mixamo_staging \
##       [--only=Quick_Roll_To_Run] [--freeze-xy=0] [--limit=0]
##
## 與 build_meditate_clip.gd 的關係（紅線 1：重用優先）：
##   骨架對應表 PAIRS、座標轉換 _frame、最短弧「方向對準」_retarget()、區域骨姿
##   _poses()／_emit() 與 FK 回報 _fk() 全部沿用同一套已驗證數學。差別只有兩點：
##     1. 這裡**逐格取樣**（冥想那支是定姿，只取 t=3.0 一格）。舊版拿去跑會動的
##        clip 只會得到「某一格的定格」。
##     2. Hips 水平位移可凍結（--freeze-xy，預設開）——本專案是「動畫零 root
##        motion、位移全程式驅動」，Mixamo 的翻滾/受擊帶 1.9~9.5 m 的 Hips 水平位移。
##
## 輸出慣例（實測 _audit_all_clips.gd 於既有 31 支）：每根對應骨頭一條 ROTATION_3D
## 軌道、逐格 LINEAR key；另加一條 Hips POSITION_3D 逐格 key（其它骨頭位置維持 rest）。
##
## ⚠ 來源軌道座標系與 rest 不一致（軌道像 Z-up、rest 是 Y-up），所以一律走引擎算好的
##   skeleton.get_bone_global_pose()，不要自己讀 Animation 軌道值。
## ⚠ 來源檔同時帶 0_T-Pose（1 格）與 mixamo.com|Layer0（真動作），這裡自動挑**最長**的。

const BODY_FBX := "res://characters/yoriichi/yoriichi_body.fbx"
const DEFAULT_SRC_DIR := "res://characters/yoriichi/anim_src/_mixamo_incoming"
const DEFAULT_OUT_DIR := "res://characters/yoriichi/animations/_mixamo_staging"

## 來源骨頭 → 遊戲骨頭（與 build_meditate_clip.gd 同一張表）
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

const SRC_FOOT_BONES := ["CC_Base_L_Foot", "CC_Base_R_Foot", "CC_Base_L_ToeBase",
	"CC_Base_R_ToeBase", "CC_Base_L_BigToe1", "CC_Base_R_BigToe1"]
const TGT_FOOT_BONES := ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]

## 目標骨架（遊戲緣一 24 骨）**站立貼地**時腳部骨 Z 的實測基準。用
## tools/_probe_clip_foot.gd 量 yoriichi_idle_grounded 得到 +0.0235~+0.0297；
## run_fast +0.0329、roll_dodge +0.0294、meditate 坐姿 +0.2508。
## --ground-fix=const 會把整支 clip 垂直平移，使全片腳底最低點落在這個值。
## （平移只動 Hips 全域位置 → 整尊骨架剛體位移 → 腳底 Z 同步位移，弧線不變。）
const TGT_GROUND := 0.0235

var _src_dir := DEFAULT_SRC_DIR
var _out_dir := DEFAULT_OUT_DIR
var _only := ""
var _freeze_xy := true
var _limit := 0
var _dry := false          # true = 只量測與列印，不寫檔（用來量來源，不會動到既有產出）
var _fps := 30.0
var _mode := "seg"          # seg（世界旋轉差量＋骨段方向對齊 rest；2026-09-23 修 S 形駝背）| world（Y 軸對齊 rest，脊椎差 9~18°）| shortest（舊：只對齊方向軸，會丟 twist→歪）| roll
var _k_basis := {}          # 目標骨頭索引 → K_i（delta 模式用：目標rest × 來源rest映射⁻¹）
var _twist_sum := 0.0
var _twist_max := 0.0
var _twist_n := 0
## 逐骨頭的「被丟棄 twist」統計（平均 / 平方和 / 格數）→ 用來判別它是座標系慣例差
## （跨格幾乎常數 → 舊算法丟掉才對）還是真的動作扭轉（跨格大幅變化 → 該補回來）。
var _dev_bone := {}
## POP 對照：同一支 clip 在「來源骨架」與「重定向後目標骨架」上，相鄰兩格的最大方向變化。
## 兩者相近 = POP 是 Mixamo 原動作就有的；目標遠大於來源 = 我重定向造成的。
var _src_pop := 0.0
var _src_pop_at := -1
var _src_pop_bone := ""
var _tgt_pop := 0.0
var _tgt_pop_at := -1
var _tgt_pop_bone := ""
var _prev_src := []
var _prev_tgt := []
## 「髖→頭」傾角（相對 rest）在來源與目標的最大值。兩者相近 = 軀幹折幅忠實；
## 目標遠大於來源 = 我重定向把身體折得更深（會讓穿長外套的角色視覺上糊成一團）。
var _lean_src_max := 0.0
var _lean_tgt_max := 0.0
var _ground_fix := "const"     # const | off

## 來源座標 → 目標座標：X→X、Y(上)→Z(上)、Z(前)→-Y(前)
var _frame := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

var _tgt: Node
var _tgt_skel: Skeleton3D
var _tgt_hips := -1
var _tgt_rest_h := Vector3.ZERO
var _scale := 1.0
var _map := {}          # 目標骨頭索引 → 來源骨頭索引


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			_src_dir = a.split("=", 1)[1]
		elif a.begins_with("--out="):
			_out_dir = a.split("=", 1)[1]
		elif a.begins_with("--only="):
			_only = a.split("=", 1)[1]
		elif a.begins_with("--freeze-xy="):
			_freeze_xy = a.split("=", 1)[1] != "0"
		elif a.begins_with("--limit="):
			_limit = int(a.split("=", 1)[1])
		elif a.begins_with("--dry="):
			_dry = a.split("=", 1)[1] != "0"
		elif a.begins_with("--fps="):
			_fps = float(a.split("=", 1)[1])
		elif a.begins_with("--ground-fix="):
			_ground_fix = a.split("=", 1)[1]
		elif a.begins_with("--mode="):
			_mode = a.split("=", 1)[1]
	_run.call_deferred()


func _run() -> void:
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	# 目標骨架只載一次，所有 clip 共用（重定向只讀它的 rest/global，不改它）
	_tgt = (load(BODY_FBX) as PackedScene).instantiate()
	root.add_child(_tgt)
	_tgt_skel = _tgt.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_tgt_hips = _tgt_skel.find_bone("Hips")
	_tgt_rest_h = _tgt_skel.get_bone_global_rest(_tgt_hips).origin

	var dir := DirAccess.open(_src_dir)
	if dir == null:
		push_error("[mixamo] 找不到來源資料夾 %s" % _src_dir)
		quit(1)
		return
	var files := []
	for f in dir.get_files():
		if f.to_lower().ends_with(".fbx"):
			files.append(f)
	files.sort()
	if _only != "":
		var want := _only.split(",")
		files = files.filter(func(f): return want.has(f.get_basename()))
	if _limit > 0:
		files = files.slice(0, _limit)
	print("[mixamo] 來源 %s：%d 支；目標骨 %d 根、髖 rest=%s" % [
		_src_dir, files.size(), _tgt_skel.get_bone_count(), str(_tgt_rest_h)])
	if files.is_empty():
		quit(1)
		return

	var ok := 0
	for f in files:
		if await _build_clip(f):
			ok += 1
	print("[mixamo] 完成 %d/%d" % [ok, files.size()])
	quit(0 if ok == files.size() else 1)


func _build_clip(file_name: String) -> bool:
	var src_path := "%s/%s" % [_src_dir, file_name]
	var out_path := "%s/%s.res" % [_out_dir, file_name.get_basename()]
	var src: Node = (load(src_path) as PackedScene).instantiate()
	root.add_child(src)
	var src_skel := src.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var src_ap := src.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	if src_skel == null or src_ap == null:
		push_error("[mixamo] %s：找不到 Skeleton3D / AnimationPlayer" % file_name)
		src.queue_free()
		return false
	_src_skel_ref = src_skel

	# 挑最長的動畫（0_T-Pose 只有 1 格，真動作在 mixamo.com|Layer0）
	var clip := ""
	var clip_len := -1.0
	for n in src_ap.get_animation_list():
		var a := src_ap.get_animation(n)
		if a != null and a.length > clip_len:
			clip = n
			clip_len = a.length
	if clip == "":
		push_error("[mixamo] %s：沒有動畫" % file_name)
		src.queue_free()
		return false

	# 骨頭對應
	_map.clear()
	_seg_cache.clear()
	_dev_bone.clear()
	_src_pop = 0.0
	_tgt_pop = 0.0
	_src_pop_at = -1
	_tgt_pop_at = -1
	_prev_src = []
	_prev_tgt = []
	# 「髖→頭」傾角用的索引與 rest 向量（用來判定軀幹前折是來源本來就有還是我造成的）
	var _lean_sh_s := -1
	var _lean_hd_s := -1
	var _lean_sh_t := -1
	var _lean_hd_t := -1
	for s in PAIRS.keys():
		var ti := _tgt_skel.find_bone(String(PAIRS[s]))
		var si := src_skel.find_bone(String(s))
		if ti < 0 or si < 0:
			push_error("[mixamo] %s：對應失敗 %s(%d) → %s(%d)" % [file_name, s, si, PAIRS[s], ti])
			continue
		_map[ti] = si
	# 身高比例（來源髖 rest Y 上 / 目標髖 rest Z 上）
	var src_hips := src_skel.find_bone("CC_Base_Hip")
	var src_rest_h: Vector3 = src_skel.get_bone_global_rest(src_hips).origin
	_scale = _tgt_rest_h.z / src_rest_h.y

	# 「髖→頭」傾角：取同一組（髖、頭）在來源與目標的 rest 方向，逐格量偏離量
	_lean_sh_s = _map[_tgt_hips]
	_lean_sh_t = _tgt_hips
	_lean_hd_t = _tgt_skel.find_bone("Head")
	var src_rest_lean := Vector3.ZERO
	var tgt_rest_lean := Vector3.ZERO
	if _map.has(_lean_hd_t):
		_lean_hd_s = _map[_lean_hd_t]
		src_rest_lean = ((_src_skel_ref.get_bone_global_rest(_lean_hd_s) as Transform3D).origin
			- (_src_skel_ref.get_bone_global_rest(_lean_sh_s) as Transform3D).origin).normalized()
		tgt_rest_lean = ((_tgt_skel.get_bone_global_rest(_lean_hd_t) as Transform3D).origin
			- (_tgt_skel.get_bone_global_rest(_lean_sh_t) as Transform3D).origin).normalized()
	_lean_src_max = 0.0
	_lean_tgt_max = 0.0

	var frames := int(round(clip_len * _fps))
	if frames < 1:
		frames = 1

	# 播放並逐格取樣
	src_ap.play(clip)
	var out := Animation.new()
	out.length = frames / _fps
	out.loop_mode = Animation.LOOP_NONE

	var tracks := {}        # 目標骨頭索引 → rotation track
	for ti in _map.keys():
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, "Armature/Skeleton3D:" + _tgt_skel.get_bone_name(ti))
		out.track_set_interpolation_type(tr, Animation.INTERPOLATION_LINEAR)
		tracks[ti] = tr
	var hips_pos_tr := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_pos_tr, "Armature/Skeleton3D:Hips")
	out.track_set_interpolation_type(hips_pos_tr, Animation.INTERPOLATION_LINEAR)

	# 第一遍：逐格取樣（來源 → 目標全域姿態 → 區域骨姿），存起來並量原始腳底高度。
	# 先量完才能決定垂直修正量（平移只動 Hips，整尊剛體位移）。
	var worst_err := 0.0
	var frame_poses := []
	var foot_lo := []
	var hips_zs := []
	for k in frames:
		var t := float(k) / _fps
		src_ap.seek(t, true)
		await process_frame
		await process_frame
		var src_glob := _read_pose(src_skel)
		var tg := _retarget(src_glob)
		var poses := _poses(tg)
		var g := _fk_tg(tg, poses)
		var lo := INF
		for b in TGT_FOOT_BONES:
			var i := _tgt_skel.find_bone(b)
			if i >= 0:
				lo = minf(lo, (g[i] as Transform3D).origin.z)
		frame_poses.append(poses)
		foot_lo.append(lo)
		hips_zs.append((g[_tgt_hips] as Transform3D).origin.z)
		worst_err = maxf(worst_err, _last_dir_err)

		# POP 對照（來源 vs 目標，同一格格距）
		if not _prev_src.is_empty():
			for si in _map.values():
				var d0: Vector3 = ((_prev_src[si] as Transform3D).basis * Vector3.UP).normalized()
				var d1: Vector3 = ((src_glob[si] as Transform3D).basis * Vector3.UP).normalized()
				var a2: float = rad_to_deg(d0.angle_to(d1))
				if a2 > _src_pop:
					_src_pop = a2
					_src_pop_at = k
					_src_pop_bone = _src_skel_ref.get_bone_name(si)
			for ti in _map.keys():
				var e0: Vector3 = ((_prev_tgt[ti] as Transform3D).basis * Vector3.UP).normalized()
				var e1: Vector3 = ((tg[ti] as Transform3D).basis * Vector3.UP).normalized()
				var a3: float = rad_to_deg(e0.angle_to(e1))
				if a3 > _tgt_pop:
					_tgt_pop = a3
					_tgt_pop_at = k
					_tgt_pop_bone = _tgt_skel.get_bone_name(ti)
		_prev_src = src_glob
		_prev_tgt = tg

		# 軀幹傾角對照（目標端必須用 FK 後的 g，不能用 tg——tg 的 origin 全是 rest 位置）
		if _lean_hd_s >= 0:
			var vs: Vector3 = ((src_glob[_lean_hd_s] as Transform3D).origin
				- (src_glob[_lean_sh_s] as Transform3D).origin).normalized()
			var vt: Vector3 = ((g[_lean_hd_t] as Transform3D).origin
				- (g[_lean_sh_t] as Transform3D).origin).normalized()
			_lean_src_max = maxf(_lean_src_max, rad_to_deg(src_rest_lean.angle_to(vs)))
			_lean_tgt_max = maxf(_lean_tgt_max, rad_to_deg(tgt_rest_lean.angle_to(vt)))

	# 地面修正：把整支 clip 抬（或壓）到「全片腳底最低點 = 目標貼地基準」
	var raw_min := INF
	for v in foot_lo:
		raw_min = minf(raw_min, v)
	var lift := 0.0
	if _ground_fix == "const" and raw_min < INF:
		lift = TGT_GROUND - raw_min
		for poses in frame_poses:
			var th: Transform3D = poses[_tgt_hips]
			poses[_tgt_hips] = Transform3D(th.basis, th.origin + Vector3(0, 0, lift))

	# 第二遍：寫 key（逐格 rotation + Hips position，與既有 31 支 .res 同慣例）
	for k in frames:
		var t := float(k) / _fps
		var poses: Array = frame_poses[k]
		for ti in tracks.keys():
			var q: Quaternion = (poses[ti] as Transform3D).basis.get_rotation_quaternion().normalized()
			out.track_insert_key(tracks[ti], t, q)
		out.track_insert_key(hips_pos_tr, t, (poses[_tgt_hips] as Transform3D).origin)

	var err := OK
	if not _dry:
		err = ResourceSaver.save(out, out_path)
	var lo_min := INF
	var lo_max := -INF
	for v in foot_lo:
		lo_min = minf(lo_min, v)
		lo_max = maxf(lo_max, v)
	print("[mixamo] %-38s %3d格 %.2fs 軌道%d key%d | 原始腳底Z %+.3f~%+.3f | 抬%+.4f → %+.3f~%+.3f | 髖Z %.3f~%.3f | %s 方向誤差%.1f° twist差平均%.1f°/最大%.1f° -> %d" % [
		(("(dry) " if _dry else "") + file_name.get_basename()), frames, out.length, out.get_track_count(),
		_count_keys(out), lo_min, lo_max, lift, lo_min + lift, lo_max + lift,
		hips_zs.min() + lift, hips_zs.max() + lift,
		_mode, worst_err, _twist_sum / maxf(1.0, float(_twist_n)), _twist_max, err])
	_print_dev_table()
	print("[mixamo]   POP 來源 %5.0f° @f%-3d(%-16s) vs 目標 %5.0f° @f%-3d(%-12s) → %s" % [
		_src_pop, _src_pop_at, _src_pop_bone, _tgt_pop, _tgt_pop_at, _tgt_pop_bone,
		"來源本來就有" if _tgt_pop <= maxf(5.0, _src_pop * 1.15) else "我造成的"])
	print("[mixamo]   軀幹傾角（髖→頭，相對 rest）來源最大 %.1f° vs 目標最大 %.1f° → %s" % [
		_lean_src_max, _lean_tgt_max,
		"忠實" if absf(_lean_tgt_max - _lean_src_max) <= maxf(3.0, _lean_src_max * 0.1) else "被放大/縮小"])
	src.queue_free()
	return err == OK


## 逐骨「被丟棄 twist」表：平均 ± 標準差（度）。變異小 = 座標系慣例差；變異大 = 真的動作扭轉。
func _print_dev_table() -> void:
	var rows := []
	for i in _dev_bone.keys():
		var dbi: Array = _dev_bone[i]
		var n: float = float(dbi[2])
		var mean: float = float(dbi[0]) / n
		var var_: float = maxf(0.0, float(dbi[1]) / n - mean * mean)
		rows.append({"name": _tgt_skel.get_bone_name(i), "mean": mean, "sd": sqrt(var_), "n": int(n)})
	rows.sort_custom(func(x, y): return float(x["mean"]) > float(y["mean"]))
	var parts := []
	for r in rows.slice(0, 8):
		parts.append("%s %.0f±%.0f" % [r["name"], r["mean"], r["sd"]])
	print("[mixamo]   丟棄 twist 前 8 名（平均±標準差）: %s" % (" | ".join(parts)))


func _count_keys(a: Animation) -> int:
	var n := 0
	for i in a.get_track_count():
		n += a.track_get_key_count(i)
	return n


func _read_pose(skel: Skeleton3D) -> Array:
	var out := []
	out.resize(skel.get_bone_count())
	for i in skel.get_bone_count():
		out[i] = skel.get_bone_global_pose(i)
	return out


var _last_dir_err := 0.0


## 重定向：每根骨頭只要求「方向對」——G.basis = 最短弧(目標 rest 方向 → 來源動畫方向) × 目標 rest basis。
## （照抄 build_meditate_clip.gd 的實證結論：兩邊 rest 骨頭方向不一致，套世界旋轉差會沿脊椎累加。）
func _retarget(src_glob: Array) -> Array:
	var out := []
	out.resize(_tgt_skel.get_bone_count())
	var worst := 0.0
	for i in _tgt_skel.get_bone_count():
		var rest_g := _tgt_skel.get_bone_global_rest(i)
		if not _map.has(i):
			out[i] = rest_g
			continue
		var si: int = _map[i]
		var dir_src: Vector3 = ((src_glob[si] as Transform3D).basis * Vector3.UP).normalized()
		var want: Vector3 = (_frame * dir_src).normalized()
		var rest_b := rest_g.basis
		var rest_dir: Vector3 = (rest_b * Vector3.UP).normalized()
		# 做法 A（shortest，原本的）：只保證方向軸對上，繞骨軸的 roll（twist）沿用目標 rest。
		var g_short := (Basis(Quaternion(rest_dir, want)) * rest_b).orthonormalized()
		# 做法 B（roll，修正版）：把來源相對 rest 的增量拆成「方向」＋「繞骨軸 roll」，
		# 方向照舊走最短弧（既有實證是對的），再把 roll 疊上去。
		#   r = A⁻¹·M（來源在本骨 rest 座標系裡的增量）
		#   r = perp · roll，其中 perp = 從 UP 到 r·UP 的最短弧 → roll 是純繞 UP 的轉角
		#   目標 G = 最短弧(rest_dir→want) · B · roll
		# 檢查：來源在 rest 時 r=I → roll=I → G=B（等於 rest，正確）。
		#       方向：G·UP = 最短弧·B·roll·UP = 最短弧·B·UP = want（方向完全不受影響）。
		var a_b: Basis = (_frame * (_src_skel_ref.get_bone_global_rest(si) as Transform3D).basis).orthonormalized()
		var r := a_b.inverse() * (_frame * (src_glob[si] as Transform3D).basis)
		var r_dir: Vector3 = (r * Vector3.UP).normalized()
		var roll_q := Quaternion.IDENTITY
		if r_dir.dot(Vector3.UP) > -0.9999:
			roll_q = Quaternion(Vector3.UP, r_dir).inverse() * r.get_rotation_quaternion()
		var g_roll := (Basis(Quaternion(rest_dir, want)) * rest_b * Basis(roll_q)).orthonormalized()
		# 兩者夾角 = 修正後多帶回來的 twist（＝現行法丟掉的擰轉量）
		var dev := rad_to_deg(g_short.get_rotation_quaternion()
			.angle_to(g_roll.get_rotation_quaternion()))
		_twist_sum += dev
		_twist_n += 1
		_twist_max = maxf(_twist_max, dev)
		if not _dev_bone.has(i):
			_dev_bone[i] = [0.0, 0.0, 0]
		var dbi: Array = _dev_bone[i]
		dbi[0] += dev
		dbi[1] += dev * dev
		dbi[2] += 1
		# 做法 C（world，2026-09-23 A/B 實證後的預設）：世界旋轉差量。
		#   D = (F·S_anim)·(F·S_rest)⁻¹ ＝來源這格相對自己 rest 的世界旋轉（含 twist、與骨軸慣例無關）
		#   C = 最短弧(目標 rest 方向 → 來源 rest 方向)：先把目標 rest 擺成來源 rest 的姿勢（A/T-pose 差）
		#   G = D·C·B → 來源 rest 時 G·UP = 來源 rest 方向；動畫時 G·UP = D·來源 rest 方向 = 動畫方向。
		#   與 shortest 的差別：twist（含 Hips 轉身 yaw、手腕翻轉）一起轉過去，而 shortest 會丟掉。
		var src_rest_dir: Vector3 = (a_b * Vector3.UP).normalized()
		var d_world: Basis = (_frame * (src_glob[si] as Transform3D).basis).orthonormalized() * a_b.inverse()
		var g_world := (d_world * Basis(Quaternion(rest_dir, src_rest_dir)) * rest_b).orthonormalized()
		# 做法 D（seg，預設）：同 world，但 rest 對齊改用「骨段方向」（本骨關節 → 下一根對應骨關節），
		#   不用 basis·UP。FBX 匯入的骨頭 local Y 不一定指向子骨（實測目標 Head 的 Y 與來源差 49°、
		#   Hips 23°、neck 24°），拿 Y 軸對齊 rest 會把直立脊椎硬掰成 S 形駝背。
		var g_seg := (d_world * Basis(_seg_align(i, si)) * rest_b).orthonormalized()
		var g: Basis = g_short
		if _mode == "roll":
			g = g_roll
		elif _mode == "world":
			g = g_world
		elif _mode == "seg":
			g = g_seg
		out[i] = Transform3D(g, rest_g.origin)
		worst = maxf(worst, rad_to_deg(((g * Vector3.UP).normalized()).angle_to(want)))
	_last_dir_err = worst
	# 髖的位置：來源相對 rest 的位移 → 換座標 → 乘身高比例 → 加回目標 rest
	var si_h: int = _map[_tgt_hips]
	var src_rest_h: Vector3 = _src_skel_ref.get_bone_global_rest(si_h).origin
	var src_now: Vector3 = (src_glob[si_h] as Transform3D).origin
	var goal: Vector3 = _tgt_rest_h + _frame * ((src_now - src_rest_h) * _scale)
	if _freeze_xy:
		# 本專案位移全程式驅動 → 水平釘回目標 rest（等同零 root motion）
		goal.x = _tgt_rest_h.x
		goal.y = _tgt_rest_h.y
	var th: Transform3D = out[_tgt_hips]
	out[_tgt_hips] = Transform3D(th.basis, goal)
	_hips_goal = goal
	return out


var _hips_goal := Vector3.ZERO
var _src_skel_ref: Skeleton3D

## 骨段鏈：目標骨 → 決定其「骨段方向」的下一根目標骨（末端骨 = ""，沿用父骨的對齊）
const SEG_CHILD := {
	"Hips": "Spine02", "Spine02": "Spine01", "Spine01": "Spine", "Spine": "neck", "neck": "Head", "Head": "",
	"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand", "LeftHand": "",
	"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand", "RightHand": "",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase", "LeftToeBase": "",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase", "RightToeBase": "",
}
var _seg_cache := {}   # 目標骨索引 → Quaternion（每支 clip 清空；來源 rest 每檔都一樣但保險起見）

## rest 對齊：把目標骨段方向轉到來源骨段方向的最短弧（兩邊都在同一座標系）。
func _seg_align(ti: int, si: int) -> Quaternion:
	if _seg_cache.has(ti):
		return _seg_cache[ti]
	var q := Quaternion.IDENTITY
	var tname := _tgt_skel.get_bone_name(ti)
	var child: String = SEG_CHILD.get(tname, "")
	if child == "":
		var p := _tgt_skel.get_bone_parent(ti)
		if p >= 0 and _map.has(p):
			q = _seg_align(p, _map[p])
	else:
		var tc := _tgt_skel.find_bone(child)
		if tc >= 0 and _map.has(tc):
			var sc: int = _map[tc]
			var td: Vector3 = _tgt_skel.get_bone_global_rest(tc).origin - _tgt_skel.get_bone_global_rest(ti).origin
			var sd: Vector3 = _frame * (_src_skel_ref.get_bone_global_rest(sc).origin - _src_skel_ref.get_bone_global_rest(si).origin)
			if td.length() > 1e-5 and sd.length() > 1e-5:
				q = Quaternion(td.normalized(), sd.normalized())
	_seg_cache[ti] = q
	return q


## 每根骨頭要寫進軌道的「相對父骨頭變換」（Godot：global[i] = global[parent] × pose[i]）
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


## FK：用真正的正向運動學算目標骨架全域位置
func _fk_tg(tgt_glob: Array, poses: Array) -> Array:
	var n := _tgt_skel.get_bone_count()
	var out := []
	out.resize(n)
	for i in n:
		var p := _tgt_skel.get_bone_parent(i)
		var gpar: Transform3D = Transform3D() if p < 0 else (out[p] as Transform3D)
		out[i] = gpar * (poses[i] as Transform3D)
	return out
