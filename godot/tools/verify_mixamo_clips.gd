extends SceneTree
## 逐支動作驗收（引擎端獨立量測）。
##
##   <godot_console> --path godot --headless --script res://tools/verify_mixamo_clips.gd -- \
##       --dirs=res://characters/yoriichi/animations/_mixamo_staging,res://characters/yoriichi/animations/_mixamo_gap_staging \
##       [--control=1] [--out=<絕對路徑>.json]
##
## 判準來源（不是我自己訂的）：
##   - `tools/verify_react_anims.gd`：**每支自製 clip 的 Hips f0 = Idle_Grounded f0（<5°）**。
##     該行註解載明漏掉會「角色躺平（Stagger 腳趾離地 0.84 m）」，屬硬契約。
##   - 既有 .res 慣例：22 條骨骼 ROTATION_3D 逐格 key + 僅一條 Hips POSITION_3D = 23 軌。
##   - 專案是動畫零 root motion：Hips 水平必須凍結。
##   - 貼地基準自校準：以遊戲自己的 Idle_Grounded 腳底量到的值當 0，不比外來常數。
##
## 這裡量的是「磁碟上的 .res 經引擎播放後的實際結果」，不採用 build 工具的內部數字。

const IDLE := "Idle_Grounded"
const FPS := 30.0
const TOL_ROOT := 5.0        # Hips f0 與 Idle f0 的角度上限（專案契約）
const SINK_TOL := 0.005      # 容許腳底低於基準 5 mm
const GROUND_TOUCH := 0.020  # 全片腳底最高不得超過基準這麼多，否則視為空中動作
const XY_TOL := 0.002        # Hips 水平漂移上限
const POP_WARN := 25.0       # 相鄰格方向跳動警示值

var _dirs: Array = []
var _control := true
var _out := ""
var _fail := 0
var _warn := 0
var _n := 0
var _rows: Array = []
var _player: Node = null
var _tree: AnimationTree = null
var _skel: Skeleton3D = null
var _anim: AnimationPlayer = null
var _feet: Array = []
var _hips := -1
var _idle_foot := 0.0
var _idle_q := Quaternion.IDENTITY


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dirs="):
			_dirs = a.split("=", 1)[1].split(",")
		elif a.begins_with("--control="):
			_control = a.split("=", 1)[1] != "0"
		elif a.begins_with("--out="):
			_out = a.split("=", 1)[1]
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func check(label: String, ok: bool, detail := "", warn_only := false) -> void:
	if not ok:
		if warn_only:
			_warn += 1
			print("[CLIP] WARN %s%s" % [label, ("  (" + detail + ")") if detail != "" else ""])
		else:
			_fail += 1
			print("[CLIP] FAIL %s%s" % [label, ("  (" + detail + ")") if detail != "" else ""])
	else:
		if detail != "":
			print("[CLIP] PASS %s  (%s)" % [label, detail])


func _hips_q0(a: Animation) -> Quaternion:
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D and String(a.track_get_path(t)).ends_with(":Hips"):
			return a.track_get_key_value(t, 0)
	return Quaternion.IDENTITY


func _measure(nm: String) -> Dictionary:
	var a: Animation = _anim.get_animation(nm)
	var frames: int = maxi(1, int(round(a.length * FPS)))
	_anim.play(nm)
	var prev: Array = []
	var pop := 0.0
	var pop_f := -1
	var pop_bone := ""
	var fmin := INF
	var fmax := -INF
	var fmin_f := -1
	var hz_lo := INF
	var hz_hi := -INF
	var xy := 0.0
	var hips0 := Vector3.ZERO
	for k in frames:
		_anim.seek(float(k) / FPS, true)
		# 必須等一幀：seek() 之後骨架的 pose 要到下一次 process 才更新，
		# 不等就會量到「上一格」的姿態（實測與 tools/align_clip_to_idle.gd 差 4.3 mm）。
		await process_frame
		var dirs: Array = []
		for i in _skel.get_bone_count():
			dirs.append((_skel.get_bone_global_pose(i).basis * Vector3.UP).normalized())
		if not prev.is_empty():
			for i in dirs.size():
				var d: float = rad_to_deg((prev[i] as Vector3).angle_to(dirs[i] as Vector3))
				if d > pop:
					pop = d
					pop_f = k
					pop_bone = _skel.get_bone_name(i)
		prev = dirs
		var fy := INF
		for b in _feet:
			fy = minf(fy, (_skel.global_transform * _skel.get_bone_global_pose(b).origin).y)
		if fy < fmin:
			fmin = fy
			fmin_f = k
		fmax = maxf(fmax, fy)
		var hp: Vector3 = _skel.get_bone_global_pose(_hips).origin
		if k == 0:
			hips0 = hp
		xy = maxf(xy, Vector2(hp.x - hips0.x, hp.y - hips0.y).length())
		hz_lo = minf(hz_lo, hp.z)
		hz_hi = maxf(hz_hi, hp.z)
	# 末格
	_anim.seek(float(frames - 1) / FPS, true)
	var q_end: Quaternion = _skel.get_bone_global_pose(_hips).basis.get_rotation_quaternion()
	var hz_end: float = _skel.get_bone_global_pose(_hips).origin.z
	return {"frames": frames, "len": a.length, "keys": _count_keys(a), "tracks": a.get_track_count(),
		"fmin": fmin - _idle_foot, "fmax": fmax - _idle_foot, "fmin_f": fmin_f,
		"pop": pop, "pop_f": pop_f, "pop_bone": pop_bone,
		"xy": xy, "hz_lo": hz_lo, "hz_hi": hz_hi, "hz_end": hz_end, "q_end": q_end}


func _count_keys(a: Animation) -> int:
	var n := 0
	for t in a.get_track_count():
		n += a.track_get_key_count(t)
	return n


func _shape_ok(a: Animation, nm: String) -> bool:
	var rot := 0
	var pos_st := 0
	var bad: Array = []
	for t in a.get_track_count():
		var p := String(a.track_get_path(t))
		var bone := p.get_slice(":", 1)
		if _skel.find_bone(bone) < 0:
			bad.append(bone)
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot += 1
		elif a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			pos_st += 1
	check("%s Hips 位置軌恰好 1 條" % nm, pos_st == 1, "位置軌 %d 條" % pos_st)
	check("%s 旋轉軌 >= 22（慣例 22）" % nm, rot >= 22, "旋轉 %d、共 %d" % [rot, a.get_track_count()], true)
	check("%s 全部軌道路徑都解析得到骨頭" % nm, bad.is_empty(), "找不到: %s" % str(bad))
	return bad.is_empty()


func _test_one(nm: String, path: String, tag: String) -> void:
	var a: Animation = load(path) as Animation
	if a == null:
		check("%s 可載入" % nm, false, path)
		return
	check("%s 可載入" % nm, true, "%d 軌 / %d key" % [a.get_track_count(), _count_keys(a)])
	_shape_ok(a, nm)
	var lib := _anim.get_animation_library("")
	if lib == null:
		check("%s 取得預設 AnimationLibrary" % nm, false)
		return
	lib.add_animation(nm + "__v", a)
	var m: Dictionary = await _measure(nm + "__v")
	var q0 := _hips_q0(a)
	var d_root := rad_to_deg(_idle_q.angle_to(q0))
	var d_end := rad_to_deg(_idle_q.angle_to(m["q_end"] as Quaternion))
	var kpf := float(m["keys"]) / maxf(1.0, float(m["frames"]))
	# 角色分組：f0=Idle 契約只適用「反應組」（verify_react_anims.gd:87 的清單：架勢／格擋／
	# 彈刀／受擊／軀幹爆）；Dead、攻擊、翻滾、居合不適用——對照組實測 dead 偏 40.7°、
	# attack_combo 偏 61.9°、roll_dodge 偏 13.8°，把它們當失敗是判準錯不是素材錯。
	var role := "other"
	for kw in ["React", "Hit_React", "Stagger", "Guard", "Block", "Deflect"]:
		if nm.contains(kw):
			role = "react"
			break
	if name_is_death(nm):
		role = "death"
	# --- 硬性（違反 = 不可用）---
	check("%s Hips f0 = Idle f0（%s 組契約 <%.0f°）" % [nm, role, TOL_ROOT], d_root < TOL_ROOT,
		"%.1f°" % d_root, role != "react")
	check("%s 腳底不陷地（基準 0，容許 %.0f mm）" % [nm, SINK_TOL * 1000.0],
		float(m["fmin"]) >= -SINK_TOL, "最低 %+.4f @f%d" % [m["fmin"], m["fmin_f"]])
	# --- 報告型（可接受但要知道）---
	check("%s 逐格 key（>=22/格）" % nm, kpf >= 22.0, "%.1f key/格" % kpf, true)
	check("%s Hips 水平漂移（遊戲 Idle 自己 0.0139 m）" % nm, float(m["xy"]) <= 0.02, "%.4f m" % m["xy"], true)
	check("%s 全片有觸地（上層動畫可豁免）" % nm, float(m["fmin"]) <= GROUND_TOUCH,
		"最低 %+.4f、最高 %+.4f" % [m["fmin"], m["fmax"]], true)
	check("%s Hips 高度帶（離譜才警示）" % nm,
		float(m["hz_lo"]) >= 0.05 and float(m["hz_hi"]) <= 1.15, "%.3f~%.3f" % [m["hz_lo"], m["hz_hi"]], true)
	check("%s 末格 Hips 回 Idle f0（可淡回）" % nm, d_end < TOL_ROOT, "%.1f°" % d_end, true)
	check("%s 逐格無突跳（>%.0f°）" % [nm, POP_WARN], float(m["pop"]) <= POP_WARN,
		"%.0f° @f%d(%s)" % [m["pop"], m["pop_f"], m["pop_bone"]], true)
	_rows.append({"name": nm, "tag": tag, "role": role, "path": path, "frames": m["frames"],
		"sec": m["len"], "keys": m["keys"], "tracks": m["tracks"], "key_per_frame": kpf,
		"root_f0_deg": d_root, "root_end_deg": d_end, "foot_min": m["fmin"], "foot_max": m["fmax"],
		"hips_xy": m["xy"], "hips_lo": m["hz_lo"], "hips_hi": m["hz_hi"],
		"pop": m["pop"], "pop_bone": m["pop_bone"]})
	_n += 1


func name_is_death(nm: String) -> bool:
	return nm.contains("Dead") or nm.contains("Death") or nm.contains("Knockdown") \
		or nm.contains("Getting_Up") or nm.contains("Dying")


func _run() -> void:
	var scn: PackedScene = load("res://characters/yoriichi/player_yoriichi.tscn")
	_player = scn.instantiate()
	root.add_child(_player)
	# 這張場景沒有地板：不先關掉物理，12 幀的自由落體會把世界座標基準整個拉走
	# （實測校準會量到 −1.14 m，之後所有腳底數字都失去意義）。
	_player.set_physics_process(false)
	_player.set_process(false)
	await _frames(12)
	_tree = _player.get_node("Tree") as AnimationTree
	_anim = _player.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_skel = _player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	if _tree != null:
		_tree.active = false
	print("[CLIP] 骨架 %d 骨、AnimationPlayer=%s、已註冊 %d 支" % [
		_skel.get_bone_count(), str(_anim.get_path()), _anim.get_animation_list().size()])
	check("Idle_Grounded 已註冊（校準基準）", _anim.has_animation(IDLE))
	_hips = _skel.find_bone("Hips")
	check("Hips 骨存在", _hips >= 0)
	for bn in ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "LeftToe_End", "RightToe_End"]:
		var i := _skel.find_bone(bn)
		if i >= 0:
			_feet.append(i)
	check("腳部骨至少兩個", _feet.size() >= 2, str(_feet))

	# 校準：遊戲自己的 Idle 腳底當 0
	_idle_q = _hips_q0(_anim.get_animation(IDLE))
	_idle_foot = 0.0
	var mi: Dictionary = await _measure(IDLE)
	_idle_foot = float(mi["fmin"])
	print("[CLIP] 校準：Idle_Grounded 腳底 %.4f（此值當 0 基準）" % _idle_foot)

	if _control:
		var ctrl := ["yoriichi_idle_grounded", "yoriichi_hit_react", "yoriichi_stagger", "yoriichi_dead",
			"yoriichi_guard_hold", "yoriichi_block_impact", "yoriichi_deflect", "yoriichi_roll_dodge",
			"yoriichi_attack_combo", "yoriichi_iai_slash"]
		print("[CLIP] --- 對照組：遊戲自己的 clip（這些應該符合契約）---")
		for c in ctrl:
			var p := "res://characters/yoriichi/animations/%s.res" % c
			if ResourceLoader.exists(p):
				await _test_one(c, p, "control")

	for d in _dirs:
		var dir := DirAccess.open(d)
		if dir == null:
			check("目錄存在 %s" % d, false)
			continue
		var names: Array = []
		for f in dir.get_files():
			if f.ends_with(".res"):
				names.append(f)
		names.sort()
		print("[CLIP] --- 候選：%s（%d 支）---" % [d, names.size()])
		for f in names:
			await _test_one(String(f).get_basename(), "%s/%s" % [d, f], "candidate")

	print("[CLIP] ===== 共測 %d 支：%d 項 FAIL、%d 項 WARN =====" % [_n, _fail, _warn])
	for tag in ["control", "candidate"]:
		var title := "對照組（遊戲自己的 clip）" if tag == "control" else "候選（Mixamo 重定向）"
		print("[CLIP] --- %s ---" % title)
		print("[CLIP] %-38s %4s %5s %9s %9s %8s %7s %6s %6s %s" % [
			"clip", "軌", "格", "腳底低", "腳底高", "HipsXY", "f0偏", "POP", "key/格", "角色"])
		for r in _rows:
			if String(r["tag"]) != tag:
				continue
			print("[CLIP] %-38s %4d %5d %+9.4f %+9.4f %8.4f %6.1f° %5.0f° %6.1f %s" % [
				r["name"], r["tracks"], r["frames"], r["foot_min"], r["foot_max"], r["hips_xy"],
				r["root_f0_deg"], r["pop"], r["key_per_frame"], r["role"]])
	if _out != "":
		var fa := FileAccess.open(_out, FileAccess.WRITE)
		if fa != null:
			fa.store_string(JSON.stringify({"n": _n, "fail": _fail, "warn": _warn, "rows": _rows}, "  "))
			print("[CLIP] JSON -> %s" % _out)
	quit(1 if _fail > 0 else 0)
