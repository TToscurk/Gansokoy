extends SceneTree
## 把動作 clip 變成「遊戲可接」的兩階段處理：
##   (1) 對齊 Idle：首／尾 head/tail 格逐骨 slerp 到 Idle 的 f0 姿 —— 滿足專案契約
##       （反應 clip 首尾 = Idle 姿、Hips f0 = Idle f0 < 5°，見 verify_react_anims.gd）。
##   (2) 地面夾制：逐骨 slerp 會讓過渡格的腳底陷地（關節角插值 ≠ 末端位置插值，實測 −4.9 cm），
##       所以再用引擎自己算 FK（Skeleton3D.get_bone_global_pose）逐格量腳底最低 Z，
##       把不足的量加回 Hips 位置軌的該格 Z。只抬不壓，來源中段的貼地值不動。
##
## 不覆寫來源：一律寫到 --out 目錄。
##
## 用法：
##   <godot_console> --path godot --headless --script res://tools/align_clip_to_idle.gd -- \
##     --dir=res://characters/yoriichi/animations/_mixamo_staging \
##     --out=res://characters/yoriichi/animations/_mixamo_aligned \
##     [--only=a,b] [--head=4] [--tail=5]
##
## 單支「切子段再對齊」模式（給從長動作裡只取一段用的，例如忍殺）：
##   ... --script res://tools/align_clip_to_idle.gd -- \
##     --slice=res://.../_mixamo_gap_staging/Stealth_Assassination.res \
##     --from=3.6 --to=4.7667 --name=yoriichi_deathblow \
##     --out=res://characters/yoriichi/animations
## from/to 會吸附到 1/30 格（否則切片後的 key 不在格線上，後面逐格夾制會差半格）。

const IDLE_PATH := "res://characters/yoriichi/animations/yoriichi_idle_grounded.res"
## 量測站在遊戲真正使用的那個 rig 上（與 tools/verify_mixamo_clips.gd 同一套），
## 否則兩支工具量同一支 clip 會有約 4 mm 的系統差。
const PLAYER_SCENE := "res://characters/yoriichi/player_yoriichi.tscn"
## 必須與 tools/verify_mixamo_clips.gd 同一組（含趾尖）：趾尖是最外側的點，
## 少算它會讓夾制留 4~5 mm 的陷地（實測兩支工具因此對不上）。
const FOOT_BONES := ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "LeftToe_End", "RightToe_End"]
const FPS := 30.0
## 小於此值的抬升不寫（避免為了量測雜訊動到原本貼地的格）。
const LIFT_EPS := 0.0005

var _dir := ""
var _out := ""
var _only := ""
var _head := 4
var _tail := 5
## 開頭這幾格直接等於 Idle 姿（不做漸層）。用途：full 層 OneShot 的 fadein 期間，
## 遊戲是把「clip 目前的姿」與 Idle 對半混合 —— 若 clip 第 1~3 格已經是半蹲，
## 混出來的「半彎膝＋半高髖」會把腳往下推（實測忍殺入場沉 29 mm，遊戲普攻只沉 4 mm）。
## 開頭壓平後，fadein 期間是 Idle↔Idle，不會混出壞姿。
var _head_hold := 0
var _slice := ""
var _from := -1.0
var _to := -1.0
var _name := ""
var _fail := 0
var _skel: Skeleton3D = null
var _ap: AnimationPlayer = null
var _lib: AnimationLibrary = null
var _base_lo := 0.0

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			_dir = a.split("=", 1)[1]
		elif a.begins_with("--out="):
			_out = a.split("=", 1)[1]
		elif a.begins_with("--only="):
			_only = a.split("=", 1)[1]
		elif a.begins_with("--head="):
			_head = int(a.split("=", 1)[1])
		elif a.begins_with("--head-hold="):
			_head_hold = int(a.split("=", 1)[1])
		elif a.begins_with("--tail="):
			_tail = int(a.split("=", 1)[1])
		elif a.begins_with("--slice="):
			_slice = a.split("=", 1)[1]
		elif a.begins_with("--from="):
			_from = float(a.split("=", 1)[1])
		elif a.begins_with("--to="):
			_to = float(a.split("=", 1)[1])
		elif a.begins_with("--name="):
			_name = a.split("=", 1)[1]
	_run.call_deferred()

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[ALIGN] PASS %s  %s" % [label, detail])
	else:
		_fail += 1
		print("[ALIGN] FAIL %s  %s" % [label, detail])

## 第 k 格（共 n 格）的對齊權重：頭 head 格由 1 漸到 0，尾 tail 格由 0 漸到 1。
## 前 _head_hold 格固定 1.0（直接等於 Idle 姿，見 _head_hold 的說明）。
func _weight(k: int, n: int) -> float:
	var w := 0.0
	if _head > 0:
		w = maxf(w, clampf(1.0 - float(maxi(k - _head_hold, 0)) / float(_head), 0.0, 1.0))
	if _head_hold > 0 and k < _head_hold:
		w = 1.0
	if _tail > 0:
		w = maxf(w, clampf(1.0 - float(n - 1 - k) / float(_tail), 0.0, 1.0))
	return w

func _hips_pos_track(a: Animation) -> int:
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_POSITION_3D and str(a.track_get_path(t)).ends_with(":Hips"):
			return t
	return -1

func _track_index(a: Animation, path: String) -> int:
	for t in a.get_track_count():
		if str(a.track_get_path(t)) == path:
			return t
	return -1


## 取 [from, to] 成一支新 clip（時間平移到 0）。from/to 已吸附到 1/30，且本專案的 clip
## 慣例是每骨每格一 key，所以窗內的格都是 key、邊界不需要補點。
func _slice_range(src: Animation, from: float, to: float) -> Animation:
	if to <= from or from < 0.0 or to > src.length + 0.001:
		return null
	var out := Animation.new()
	out.length = to - from
	out.step = src.step
	for t in src.get_track_count():
		var ty := src.track_get_type(t)
		var idx := out.add_track(ty)
		out.track_set_path(idx, src.track_get_path(t))
		out.track_set_interpolation_type(idx, src.track_get_interpolation_type(t))
		for k in src.track_get_key_count(t):
			var kt := src.track_get_key_time(t, k)
			if kt < from - 0.0001 or kt > to + 0.0001:
				continue
			out.track_insert_key(idx, kt - from, src.track_get_key_value(t, k))
	return out

func _n_frames(a: Animation) -> int:
	var t := _hips_pos_track(a)
	if t >= 0:
		return a.track_get_key_count(t)
	return maxi(1, int(round(a.length * FPS)))

## 逐格驅動骨架，量腳部骨最低 Z（骨架空間 Z = 高度）。回傳每格的最低值。
func _series(nm: String) -> Array:
	_ap.play(nm)
	var a: Animation = _lib.get_animation(nm)
	var n := _n_frames(a)
	var out: Array = []
	var feet: Array = []
	for b in FOOT_BONES:
		var i := _skel.find_bone(b)
		if i >= 0:
			feet.append(i)
	for k in n:
		_ap.seek(float(k) / FPS, true)
		await process_frame
		var lo := INF
		for i in feet:
			lo = minf(lo, _skel.get_bone_global_pose(i).origin.z)
		out.append(lo)
	return out

func _run() -> void:
	if _out == "" or (_dir == "" and _slice == ""):
		_check("參數", false, "需要 --out=，以及 --dir=（目錄模式）或 --slice=（切片模式）")
		quit(1)
		return
	var body: PackedScene = load(PLAYER_SCENE)
	if body == null:
		_check("載入玩家場景", false, PLAYER_SCENE)
		quit(1)
		return
	var node := body.instantiate()
	root.add_child(node)
	# 這張場景沒有地板：不先關掉物理，settle 的幀數會自由落體把世界座標基準拉走。
	node.set_physics_process(false)
	node.set_process(false)
	for i in 12:
		await process_frame
	var tree := node.get_node("Tree") as AnimationTree
	if tree != null:
		tree.active = false
	_skel = node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_ap = node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	if _skel == null or _ap == null:
		_check("取得骨架／AnimationPlayer", false, PLAYER_SCENE)
		quit(1)
		return
	_lib = _ap.get_animation_library("")
	# 對齊目標：Idle f0 的逐骨值
	var idle: Animation = load(IDLE_PATH)
	if idle == null:
		_check("載入 Idle", false, IDLE_PATH)
		quit(1)
		return
	var idle_rot := {}
	var idle_pos := {}
	for t in idle.get_track_count():
		var p := str(idle.track_get_path(t))
		match idle.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				idle_rot[p] = idle.track_get_key_value(t, 0) as Quaternion
			Animation.TYPE_POSITION_3D:
				idle_pos[p] = idle.track_get_key_value(t, 0) as Vector3
	_lib.add_animation("__idle", idle)
	var ilo: Array = await _series("__idle")
	_base_lo = float(ilo.min())
	print("[ALIGN] 目標 = Idle f0（%d 旋轉 / %d 位置軌）；貼地基準 = Idle %.4f（骨架 Z）" % [
		idle_rot.size(), idle_pos.size(), _base_lo])
	if _slice != "":
		# 單支「切子段再對齊」模式：切成 [from, to]（吸附 1/30 格）後走同一條對齊＋夾制。
		var src: Animation = load(_slice)
		if src == null:
			_check("載入來源 %s" % _slice, false, "")
			quit(1)
			return
		if _from < 0.0 or _to <= _from:
			_check("--from／--to 不合法", false, "%.3f~%.3f" % [_from, _to])
			quit(1)
			return
		var f0 := roundf(_from * FPS) / FPS
		var t1 := roundf(_to * FPS) / FPS
		var sl := _slice_range(src, f0, t1)
		if sl == null:
			_check("切子段", false, "%.4f~%.4f 不落在 0~%.4f s 內" % [f0, t1, src.length])
			quit(1)
			return
		print("[ALIGN] 切片 %.4f~%.4f → %d 格 / %.4f s（來源 %.4f s）" % [f0, t1, _n_frames(sl), sl.length, src.length])
		DirAccess.make_dir_recursive_absolute(_out)
		var nm2 := _name if _name != "" else _slice.get_file().get_basename()
		var ok2: bool = await _one(nm2, sl, idle_rot, idle_pos)
		print("[ALIGN] ===== 切片模式：%s、%d 項失敗 =====" % ["完成" if ok2 else "未完成", _fail])
		quit(1 if _fail > 0 else 0)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var d := DirAccess.open(_dir)
	if d == null:
		_check("來源目錄", false, _dir)
		quit(1)
		return
	var names: Array = []
	for f in d.get_files():
		if f.to_lower().ends_with(".res"):
			names.append(f)
	names.sort()
	var done := 0
	for f in names:
		var a: Animation = load("%s/%s" % [_dir, f])
		if a == null:
			_check("%s 可載入" % f, false, _dir)
			continue
		if await _one(str(f).get_basename(), a, idle_rot, idle_pos):
			done += 1
	print("[ALIGN] ===== %d/%d 支完成、%d 項失敗 =====" % [done, names.size(), _fail])
	quit(1 if _fail > 0 else 0)


func _one(nm: String, src: Animation, idle_rot: Dictionary, idle_pos: Dictionary) -> bool:
	if _only != "" and not _only.split(",").has(nm):
		return false
	var a: Animation = src.duplicate(true)
	# --- (1) 首尾對齊 Idle ---
	var rot := 0
	var pos := 0
	var miss := 0
	for t in a.get_track_count():
		var p := str(a.track_get_path(t))
		var ty := a.track_get_type(t)
		var n := a.track_get_key_count(t)
		if ty == Animation.TYPE_ROTATION_3D:
			if not idle_rot.has(p):
				miss += 1
				continue
			rot += 1
			var tq: Quaternion = idle_rot[p]
			for k in n:
				var w := _weight(k, n)
				if w <= 0.0:
					continue
				var q: Quaternion = a.track_get_key_value(t, k)
				a.track_set_key_value(t, k, q.slerp(tq, w))
		elif ty == Animation.TYPE_POSITION_3D:
			if not idle_pos.has(p):
				miss += 1
				continue
			pos += 1
			var tp: Vector3 = idle_pos[p]
			for k in n:
				var w2 := _weight(k, n)
				if w2 <= 0.0:
					continue
				var v: Vector3 = a.track_get_key_value(t, k)
				a.track_set_key_value(t, k, v.lerp(tp, w2))
	var hips_path := ""
	for t in a.get_track_count():
		if str(a.track_get_path(t)).ends_with(":Hips") and a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			hips_path = str(a.track_get_path(t))
			break
	var d_before := 999.0
	var d_after := 999.0
	if hips_path != "" and idle_rot.has(hips_path):
		var tq: Quaternion = idle_rot[hips_path]
		d_before = rad_to_deg(tq.angle_to(src.track_get_key_value(_track_index(src, hips_path), 0)))
		d_after = rad_to_deg(tq.angle_to(a.track_get_key_value(_track_index(a, hips_path), 0)))
	# --- (2) 地面夾制：量對齊後的逐格腳底，把不足的抬升寫回 Hips 位置軌 Z ---
	# 一輪量測 → 抬升會因關鍵格之間的線性插值留下殘量，故迭代到不再陷地（最多 3 輪）。
	var cn := "__c_" + nm
	_lib.add_animation(cn, a)
	var pt := _hips_pos_track(a)
	var lo: Array = []
	var lo_min := 0.0
	var lo_first := 0.0
	var lift_max := 0.0
	var lift_at := -1
	var lifted := 0
	var passes := 0
	for pi in 3:
		_ap.stop()
		lo = await _series(cn)
		lo_min = float(lo.min())
		if pi == 0:
			lo_first = lo_min
		if lo_min >= _base_lo - 0.001:
			break
		passes += 1
		if pt < 0:
			break
		for k in mini(lo.size(), a.track_get_key_count(pt)):
			var lift := _base_lo - float(lo[k])
			if lift > LIFT_EPS:
				var v: Vector3 = a.track_get_key_value(pt, k)
				a.track_set_key_value(pt, k, Vector3(v.x, v.y, v.z + lift))
				lifted += 1
				if lift > lift_max:
					lift_max = lift
					lift_at = k
		_lib.add_animation(cn, a)
	var n := _n_frames(a)
	var out_path := "%s/%s.res" % [_out, nm]
	var err := ResourceSaver.save(a, out_path)
	_check("%s 寫出" % nm, err == OK, out_path if err == OK else "err=%d" % err)
	print("[ALIGN] %-36s %d旋%d位 缺%d | Hips f0 %.1f°→%.1f° | 對齊後腳底 %+.4f 夾制%d輪 %d格(最大%.4f@f%d) → %+.4f | %d格" % [
		nm, rot, pos, miss, d_before, d_after, lo_first, passes, lifted, lift_max, lift_at, lo_min, n])
	if lo_min < -0.002:
		_check("%s 夾制後仍陷地" % nm, false, "%+.4f" % lo_min)
	return err == OK
