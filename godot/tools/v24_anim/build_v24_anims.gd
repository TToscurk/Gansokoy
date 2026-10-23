extends SceneTree
## v2.4 緣一動畫建置：Mixamo FBX（角色 f2e0c040、Arm-Space 0.78、30 fps、無蒙皮）→ yoriichi_v24.glb 骨架的 Animation .res。
##
## 重定向用「世界旋轉差量」：D = S_world(t)·S_rest_world⁻¹，T_world = D·T_rest_world，再換回 local。
## 來源與目標是同一具 V2.4 綁定（同骨名、同 bind 形狀），只差 FBX/GLB 的骨頭本地座標系與單位。
## Hips 位置以 rest 髖高比例換算，再依每支 clip 的 root 規則處理（loop 去趨勢／freeze／air／clamp）。
##
## 用法（headless 可，只處理動畫數值，不涉 MultiMesh）：
##   godot --headless --path . -s tools/v24_anim/build_v24_anims.gd [-- key1,key2 | --validate]
## 輸出：res://characters/yoriichi/v24/anims/<key>.res、user://v24_anim_report.json

const SRC_DIR := "res://characters/yoriichi/v24/mixamo/"
const OUT_DIR := "res://characters/yoriichi/v24/anims/"
const GLB := "res://characters/yoriichi/v24/yoriichi_v24.glb"
const TRACK_PREFIX := "緣一_fbx/Armature/Skeleton3D:"
const FPS := 30.0

## root: loop=去除線性水平漂移（循環移動）、freeze=水平固定在 rest（位移由腳本驅動）
## y: keep=保留＋貼地、clamp=不高於站姿髖高（起跳蹲伏保留，騰空由物理給）、air=髖高固定站姿高度（空翻）
## trim=[起,迄] 秒（來源時間）；speed=播放倍率烘進 clip；loop=循環
## 串接：輕連段三段（L1 CrossSlash／L2 StableInward／L3 Downward，同 COMBAT_STATUS V2R2 候選）；
## 格擋 = 進架勢＋架勢循環。meta "sections" = 各段在 0..1 的起點。
const CONCAT := {
	# 格擋 = 雙手架刀進架勢＋架勢循環（Arm-Space 0）。
	"guard": ["gs_guard_in", "gs_guard_idle"],
	# 輕連段（第三輪）：單手三刀 L1 Cross Slash／L2 Stable Inward／L3 Downward，左手握鞘口、挺胸伸臂。
	"attack_combo": ["atk_cross", "atk_inward", "atk_downward"],
	# 拔刀 = Draw Sword 1（右手伸到左腰握柄）＋ Draw Sword 2（拔出）；之後由 AnimationTree 淡入持刀待機（雙手）。
	"draw": ["draw1", "draw2"],
	# 居合架勢 = 站→蹲（Great Sword Stand To Crouch）＋ 蹲姿持刀循環；iai_kamae_t = 第一段長度。
	"iai_stance": ["gs_to_crouch", "gs_crouch_idle"],
}

const SPEC := {
	"idle_breath": {"root": "loop", "y": "keep", "loop": true},
	"idle_look": {"root": "loop", "y": "keep", "loop": true},
	"run": {"root": "loop", "y": "keep", "loop": true},
	"sprint": {"root": "loop", "y": "keep", "loop": true},
	"run_turn180": {"root": "freeze", "y": "keep"},
	"jump_up": {"root": "freeze", "y": "clamp", "curve": true},
	"run_jump": {"root": "freeze", "y": "clamp", "curve": true},
	"fall": {"root": "freeze", "y": "air", "loop": true},
	"land": {"root": "freeze", "y": "keep", "trim": [0.25, 1.0667], "ground": "last"},
	"land_roll": {"root": "freeze", "y": "keep", "trim": [0.05, 1.8], "ground": "last"},
	"hard_land": {"root": "freeze", "y": "keep", "ground": "last", "speed": 1.4},
	"flip": {"root": "freeze", "y": "air", "trim": [0.5, 1.45]},
	"twist_flip": {"root": "freeze", "y": "air", "trim": [0.5, 1.35]},
	"roll": {"root": "freeze", "y": "keep", "trim": [0.25, 1.1667], "ground": "first"},
	"stand_roll": {"root": "freeze", "y": "keep", "ground": "first"},
	"wall_run": {"root": "freeze", "y": "air", "curve": true},
	"wall_run_up": {"root": "freeze", "y": "fixed_end", "ground": "last", "root_meta": true},
	"wall_jump": {"root": "freeze", "y": "air", "trim": [0.3, 1.0]},
	"mantle": {"root": "freeze", "y": "fixed_end", "ground": "last", "root_meta": true},
	"wall_climb": {"root": "freeze", "y": "fixed_end", "ground": "last", "root_meta": true},
	"draw1": {"root": "freeze", "y": "keep", "one_hand": true, "reach": 1.0, "grab_hilt": [6, 15, 15]},
	"draw2": {"root": "freeze", "y": "keep", "one_hand": true, "reach": 1.0, "grab_hilt": [0, 0, 5]},
	"sheath1": {"root": "freeze", "y": "keep"},
	"react_front": {"root": "freeze", "y": "keep"},
	"react_back": {"root": "freeze", "y": "keep"},
	"react_left": {"root": "freeze", "y": "keep"},
	"react_right": {"root": "freeze", "y": "keep"},
	"death": {"root": "freeze", "y": "keep", "ground": "first"},
	"get_up": {"root": "freeze", "y": "keep", "ground": "last"},
	"assassin": {"root": "freeze", "y": "keep", "trim": [3.6, 4.7667]},
	"sit_floor": {"root": "freeze", "y": "keep", "loop": true},
	# —— 雙手刀（Mixamo Great Sword 系列，2026-10-17 第二輪）——
	# gs_idle_ref = 未修正的 Great Sword Idle：握刀掛點與左手相對位姿的唯一參考（grip_fit.py／_grip_setup 讀它，不可加 two_hand）。
	"gs_idle_ref": {"src": "gs_idle", "root": "loop", "y": "keep", "loop": true},
	"gs_idle": {"root": "loop", "y": "keep", "loop": true, "two_hand": true},
	"gs_walk": {"root": "loop", "y": "keep", "loop": true, "two_hand": true},
	"gs_run": {"root": "loop", "y": "keep", "loop": true, "two_hand": true},
	"gs_walk_back": {"root": "loop", "y": "keep", "loop": true, "two_hand": true},
	"gs_run_back": {"root": "loop", "y": "keep", "loop": true, "two_hand": true},
	"gs_strafe_l": {"root": "loop", "y": "keep", "loop": true, "two_hand": true},
	"gs_strafe_r": {"root": "loop", "y": "keep", "loop": true, "two_hand": true},
	"gs_strafe_l_run": {"root": "loop", "y": "keep", "loop": true, "two_hand": true},
	"gs_strafe_r_run": {"root": "loop", "y": "keep", "loop": true, "two_hand": true},
	"gs_crouch_idle": {"root": "loop", "y": "keep", "loop": true, "two_hand": true},
	"gs_powerup": {"root": "loop", "y": "keep", "loop": true, "two_hand": true},
	"gs_turn_l": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_turn_r": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_run180": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_combo": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_low": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_power": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_down": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_crouch_slash": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_spin_run": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_jump_atk": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_slide": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_hilt": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_spin_kick": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_side_kick": {"root": "freeze", "y": "keep", "two_hand": true},
	"th_combo": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_guard_out": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_hit": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_head_hit": {"root": "freeze", "y": "keep", "two_hand": true},
	"withdraw": {"root": "freeze", "y": "keep"},
	"sheathing": {"root": "freeze", "y": "keep"},
	"gs_draw1": {"root": "freeze", "y": "keep"},
	"gs_draw2": {"root": "freeze", "y": "keep"},
	"gs_sheath1": {"root": "freeze", "y": "keep"},
	"gs_sheath2": {"root": "freeze", "y": "keep"},
	"sheath2": {"root": "freeze", "y": "keep"},
	"th_death_back": {"root": "freeze", "y": "keep"},
	"gs_jump": {"root": "freeze", "y": "clamp", "curve": true, "two_hand": true},
	"gs_run_jump": {"root": "freeze", "y": "clamp", "curve": true, "two_hand": true},
	"gs_guard_in": {"root": "freeze", "y": "keep", "two_hand": true},
	"gs_guard_idle": {"root": "freeze", "y": "keep", "loop": true, "two_hand": true},
	"gs_block_hit": {"root": "freeze", "y": "keep", "two_hand": true},
	"sword_run": {"root": "loop", "y": "keep", "loop": true},
	"gs_to_crouch": {"root": "freeze", "y": "keep", "two_hand": true},
	# 疾跑：Standard Sprint（前傾大、步幅大；Fast Run 跟慢跑看起來差不多）。
	"sprint_std": {"root": "loop", "y": "keep", "loop": true},
	# —— 單手刀（第三輪「超人類武士」：挺胸、伸臂、左手握鞘口；Arm-Space 0.78 素材）——
	"atk_cross": {"root": "freeze", "y": "keep", "trim": [0.0, 1.2], "one_hand": true, "reach": 1.15, "snap": [0.55, 2.2]},
	"atk_inward": {"root": "freeze", "y": "keep", "trim": [0.0, 1.6], "one_hand": true, "reach": 1.15, "snap": [0.55, 2.2]},
	"atk_outward": {"root": "freeze", "y": "keep", "trim": [0.0, 1.3333], "one_hand": true, "reach": 1.15, "snap": [0.55, 2.2]},
	"atk_downward": {"root": "freeze", "y": "keep", "trim": [0.0, 1.0], "one_hand": true, "reach": 1.15, "snap": [0.55, 2.2]},
	"atk_onehand": {"root": "freeze", "y": "keep", "one_hand": true, "reach": 1.15},
	"atk_high": {"root": "freeze", "y": "keep", "auto_strike": true, "pre": 14, "post": 16, "one_hand": true, "reach": 1.15, "snap": [0.55, 2.2]},
	"atk_low": {"root": "freeze", "y": "keep", "auto_strike": true, "pre": 14, "post": 16, "one_hand": true, "reach": 1.15, "snap": [0.55, 2.2]},
	"ua_idle_a": {"root": "loop", "y": "keep", "loop": true, "one_hand": true, "reach": 1.0},
	"ua_idle_b": {"root": "loop", "y": "keep", "loop": true, "one_hand": true, "reach": 1.0},
	"d_walk": {"src": "_ref_walk_user", "root": "loop", "y": "keep", "loop": true, "one_hand": true, "left_saya": 0.0, "posture": false},
	"_calib_walk": {"root": "loop", "y": "keep", "loop": true},
	"_ref_walk078": {"root": "loop", "y": "keep", "loop": true},
	"_ref_walk_user": {"root": "loop", "y": "keep", "loop": true},
}

var _tgt: Node3D
var _tsk: Skeleton3D
var _t_rest_g := {}         # bone idx -> Transform3D（目標骨架空間 global rest）
var _t_body: Array[int] = []  # 目標身體骨（mixamorig_*，依 index 排序 = 父先子後）
var _ground_toe := 0.0      # 目標 idle 首格腳趾骨最低高度（貼地基準）
var _stand_hips_y := 0.0    # 目標 idle 首格髖高
var _frame := 0
var _report := {}

func _initialize() -> void:
	_tgt = (load(GLB) as PackedScene).instantiate()
	root.add_child(_tgt)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_tsk = _tgt.find_child("Skeleton3D", true, false)
	for i in _tsk.get_bone_count():
		var p := _tsk.get_bone_parent(i)
		_t_rest_g[i] = (_t_rest_g[p] as Transform3D) * _tsk.get_bone_rest(i) if p >= 0 else _tsk.get_bone_rest(i)
		if _tsk.get_bone_name(i).begins_with("mixamorig_"):
			_t_body.append(i)
	_measure_target_idle()
	var args := OS.get_cmdline_user_args()
	var keys: Array = SPEC.keys()
	if args.size() > 0 and args[0] == "--validate":
		_validate()
		quit()
		return true
	if args.size() > 0:
		keys = Array(args[0].split(","))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for k in keys:
		if (k as String).begins_with("_"):
			continue
		var a := build_clip(k)
		if a == null:
			continue
		var err := ResourceSaver.save(a, OUT_DIR + k + ".res")
		print("BUILT ", k, " len=", snappedf(a.length, 0.001), " err=", err, " two_hand=", _report_two_hand.get(k, "-"))
	for cname in CONCAT:
		var parts: Array = CONCAT[cname]
		var touched := keys.size() == SPEC.keys().size()
		for pk in parts:
			touched = touched or pk in keys
		if touched:
			var ca := _concat(parts)
			print("CONCAT ", cname, " len=", ca.length, " sections=", ca.get_meta("sections"), " err=", ResourceSaver.save(ca, OUT_DIR + cname + ".res"))
	var f := FileAccess.open("user://v24_anim_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_report, "  "))
	f.close()
	quit()
	return true

# ---------------------------------------------------------------- 目標量測
func _measure_target_idle() -> void:
	var ap: AnimationPlayer = _tgt.find_child("AnimationPlayer", true, false)
	var a := ap.get_animation("idle")
	var loc := _sample_local(a, _tsk, 0.0, "緣一_fbx/Armature/Skeleton3D:")
	var g := _fk(_tsk, loc)
	_stand_hips_y = (g[_tsk.find_bone("mixamorig_Hips")] as Transform3D).origin.y
	_ground_toe = minf((g[_tsk.find_bone("mixamorig_LeftToeBase")] as Transform3D).origin.y, (g[_tsk.find_bone("mixamorig_RightToeBase")] as Transform3D).origin.y)
	print("TARGET idle hips_y=", _stand_hips_y, " toe_y=", _ground_toe)

## Animation 在時間 t 的各骨 local pose（無軌道 = rest）。prefix = 軌道路徑中骨架節點前綴。
func _sample_local(a: Animation, sk: Skeleton3D, t: float, prefix: String) -> Dictionary:
	var out := {}
	for i in sk.get_bone_count():
		out[i] = sk.get_bone_rest(i)
	for tr in a.get_track_count():
		var path := str(a.track_get_path(tr))
		var c := path.rfind(":")
		if c < 0:
			continue
		var bi := sk.find_bone(path.substr(c + 1))
		if bi < 0:
			continue
		var xf: Transform3D = out[bi]
		match a.track_get_type(tr):
			Animation.TYPE_ROTATION_3D:
				xf.basis = Basis(a.rotation_track_interpolate(tr, t)).scaled(xf.basis.get_scale())
			Animation.TYPE_POSITION_3D:
				xf.origin = a.position_track_interpolate(tr, t)
		out[bi] = xf
	return out

func _fk(sk: Skeleton3D, loc: Dictionary) -> Dictionary:
	var g := {}
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		g[i] = (g[p] as Transform3D) * (loc[i] as Transform3D) if p >= 0 else (loc[i] as Transform3D)
	return g

# ---------------------------------------------------------------- 建置
func _load_src(key: String) -> Array:
	var path := SRC_DIR + key + ".fbx"
	if not ResourceLoader.exists(path):
		push_error("缺來源 " + path)
		return []
	var src: Node3D = (load(path) as PackedScene).instantiate()
	root.add_child(src)
	var sk: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	var a := ap.get_animation(ap.get_animation_list()[0])
	# 骨架空間 → 世界（包含 Armature 的軸轉換與單位縮放）；動畫軌道路徑前綴相對 AnimationPlayer root。
	var ws := src.global_transform.affine_inverse() * sk.global_transform
	var prefix := str(src.get_path_to(sk)) + ":"
	return [src, sk, a, ws, prefix]

## 骨段方向校正（技能 mixamo-animation-batch-download「重定向」節）：來源 FBX 的 rest 與 GLB bind 在手臂差約 10°，
## 只用世界旋轉差量會把這個 rest 差帶進結果。對每根骨乘上 arc(目標rest骨段→來源rest骨段)，讓骨段世界方向對齊來源。
var _arc := {}
## 驗證（--validate）：不加骨段校正時與 GLB 既有 walk／walk_user（Blender 端產生）平均差 2.3°（不含手指）、
## 加了反而 3.7°。為與已驗收的袖子設定一致，預設關閉。
var MATCH_DIR := false
const PRIMARY_CHILD := {"mixamorig_Hips": "mixamorig_Spine", "mixamorig_Spine2": "mixamorig_Neck",
	"mixamorig_LeftHand": "mixamorig_LeftHandMiddle1", "mixamorig_RightHand": "mixamorig_RightHandMiddle1"}

func _build_arcs(sk: Skeleton3D, ws: Transform3D, s_rest_g: Dictionary) -> void:
	_arc.clear()
	for ti in _t_body:
		var n := _tsk.get_bone_name(ti)
		var child := -1
		if PRIMARY_CHILD.has(n):
			child = _tsk.find_bone(PRIMARY_CHILD[n])
		else:
			for c in _tsk.get_bone_children(ti):
				if _tsk.get_bone_name(c).begins_with("mixamorig_"):
					child = c
					break
		var si := sk.find_bone(n)
		var sc := sk.find_bone(_tsk.get_bone_name(child)) if child >= 0 else -1
		if child < 0 or si < 0 or sc < 0:
			_arc[ti] = Quaternion()
			continue
		var td := (_t_rest_g[child] as Transform3D).origin - (_t_rest_g[ti] as Transform3D).origin
		var sd := (ws * (s_rest_g[sc] as Transform3D).origin) - (ws * (s_rest_g[si] as Transform3D).origin)
		_arc[ti] = Quaternion(td.normalized(), sd.normalized()) if MATCH_DIR and td.length() > 1e-4 and sd.length() > 1e-4 else Quaternion()

## 回傳 {t: [world_rot_by_target_bone(Dictionary idx->Basis), hips_world_pos]}
func _retarget_frame(sk: Skeleton3D, a: Animation, ws: Transform3D, s_rest_g: Dictionary, t: float) -> Array:
	var loc := _sample_local(a, sk, t, "")
	var g := _fk(sk, loc)
	var wr := ws.basis.orthonormalized()
	var t_world := {}
	for ti in _t_body:
		var si := sk.find_bone(_tsk.get_bone_name(ti))
		if si < 0:
			t_world[ti] = (_t_rest_g[ti] as Transform3D).basis.orthonormalized()
			continue
		var s_now := wr * (g[si] as Transform3D).basis.orthonormalized()
		var s_rest := wr * (s_rest_g[si] as Transform3D).basis.orthonormalized()
		var d := s_now * s_rest.inverse()
		t_world[ti] = d * Basis(_arc.get(ti, Quaternion())) * (_t_rest_g[ti] as Transform3D).basis.orthonormalized()
	var hs := sk.find_bone("mixamorig_Hips")
	var hp: Vector3 = ws * (g[hs] as Transform3D).origin
	return [t_world, hp]

func build_clip(key: String) -> Animation:
	var spec: Dictionary = SPEC.get(key, {"root": "freeze", "y": "keep"})
	var L := _load_src(spec.get("src", key))
	if L.is_empty():
		return null
	var src: Node3D = L[0]
	var sk: Skeleton3D = L[1]
	var a: Animation = L[2]
	var ws: Transform3D = L[3]
	var s_rest_g := {}
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		s_rest_g[i] = (s_rest_g[p] as Transform3D) * sk.get_bone_rest(i) if p >= 0 else sk.get_bone_rest(i)
	_build_arcs(sk, ws, s_rest_g)
	var hs := sk.find_bone("mixamorig_Hips")
	var s_hips_rest: Vector3 = ws * (s_rest_g[hs] as Transform3D).origin
	var t_hips_i := _tsk.find_bone("mixamorig_Hips")
	var t_hips_rest: Vector3 = (_t_rest_g[t_hips_i] as Transform3D).origin
	var k := t_hips_rest.y / maxf(s_hips_rest.y, 0.001)
	var tr: Array = spec.get("trim", [0.0, a.length])
	var t0: float = tr[0]
	var t1: float = minf(tr[1], a.length)
	if spec.get("auto_strike", false):
		var w := _strike_window(sk, a, ws, spec.get("pre", 14), spec.get("post", 16))
		t0 = w[0]
		t1 = w[1]
	var speed: float = spec.get("speed", 1.0)
	# 取樣時間表：segments=[[來源格, 倍率], ...]（同 work/yoriichi_mixamo/v2mf_r2.py 的 time），否則等速。
	var times: Array[float] = []
	if spec.has("snap"):
		# 超人類武士的節奏：手速快的格（揮砍）時間走得更快、慢的格（架勢、收勢）停留更久。
		# rate(f) ∝ lo + (hi-lo)·(v/vmax)^1.5，正規化到平均 = speed（總長不變）。snap=[lo, hi]
		var sn: Array = spec.snap
		var srh := sk.find_bone("mixamorig_RightHand")
		var vs: Array[float] = []
		var prevp := Vector3.INF
		var f0 := int(round(t0 * FPS))
		var f1 := int(round(t1 * FPS))
		for fi in range(f0, f1 + 1):
			var g := _fk(sk, _sample_local(a, sk, fi / FPS, ""))
			var hp: Vector3 = ws * (g[srh] as Transform3D).origin
			vs.append(0.0 if prevp == Vector3.INF else hp.distance_to(prevp))
			prevp = hp
		var vmax := 0.0001
		for v in vs:
			vmax = maxf(vmax, v)
		var rates: Array[float] = []
		var acc := 0.0
		for v in vs:
			var r := lerpf(float(sn[0]), float(sn[1]), pow(v / vmax, 1.5))
			rates.append(r)
			acc += r
		var norm := speed * float(rates.size()) / maxf(acc, 0.0001)
		var tf := float(f0)
		while tf <= float(f1) + 1e-6:
			times.append(tf / FPS)
			var ri := clampi(int(tf) - f0, 0, rates.size() - 1)
			tf += rates[ri] * norm
		if times[times.size() - 1] < t1 - 1e-4:
			times.append(t1)
	elif spec.has("segments"):
		var segs: Array = spec.segments
		var tf: float = segs[0][0]
		var endf: float = t1 * FPS
		while tf <= endf + 1e-6:
			var sp := 1.0
			for sg in segs:
				if sg[0] <= tf + 1e-6:
					sp = sg[1]
			times.append(tf / FPS)
			tf += sp
		t0 = times[0]
	else:
		var nn := int(round((t1 - t0) * FPS / speed)) + 1
		for fi in nn:
			times.append(minf(t0 + fi / FPS * speed, t1))
	var hold_n := int(round(float(spec.get("hold", 0.0)) * FPS))
	for hi in hold_n:
		times.append(times[times.size() - 1])
	var n := times.size()
	var frames := []
	var raw_root := []
	for fi in n:
		var ts := times[fi]
		var r := _retarget_frame(sk, a, ws, s_rest_g, ts)
		raw_root.append(((r[1] as Vector3) - s_hips_rest) * k)
		var hp: Vector3 = t_hips_rest + ((r[1] as Vector3) - s_hips_rest) * k
		frames.append([r[0], hp])
	src.queue_free()
	if spec.get("two_hand", false):
		_report_two_hand[key] = _two_hand_fix(frames, spec)
	elif spec.get("one_hand", false):
		_report_two_hand[key] = _one_hand_fix(frames, spec)
	# --- root 規則（水平）
	var p0: Vector3 = frames[0][1]
	var pN: Vector3 = frames[n - 1][1]
	for fi in n:
		var hp: Vector3 = frames[fi][1]
		if spec.root == "loop":
			var lin := p0.lerp(pN, float(fi) / maxf(n - 1, 1))
			hp.x = hp.x - lin.x + t_hips_rest.x
			hp.z = hp.z - lin.z + t_hips_rest.z
		else:
			hp.x = t_hips_rest.x
			hp.z = t_hips_rest.z
		frames[fi][1] = hp
	# --- 轉 local（目標階層）並量腳趾高度
	var locs := []
	var toe_min := 99.0
	var toe_y := []
	for fi in n:
		var tw: Dictionary = frames[fi][0]
		var lr := {}
		for ti in _t_body:
			var p := _tsk.get_bone_parent(ti)
			var pw: Basis = tw[p] if tw.has(p) else Basis()
			lr[ti] = (pw.inverse() * (tw[ti] as Basis)).get_rotation_quaternion()
		locs.append(lr)
		var ty := _toe_y(lr, frames[fi][1])
		toe_y.append(ty)
		toe_min = minf(toe_min, ty)
	# --- 垂直規則
	# 貼地：ground=min（全片最低腳趾貼地，循環用）／first（首格站姿貼地）／last（末格貼地；翻滾起身、落地類）
	var gmode: String = spec.get("ground", "min" if spec.get("loop", false) else "first")
	var lift := 0.0
	match gmode:
		"min":
			lift = _ground_toe - toe_min
		"first":
			lift = _ground_toe - toe_y[0]
		"last":
			lift = _ground_toe - toe_y[n - 1]
	var root_path := PackedVector3Array()
	for fi in n:
		var hp: Vector3 = frames[fi][1]
		match spec.y:
			"keep":
				hp.y += lift
			"clamp":
				hp.y = minf(hp.y + (_ground_toe - toe_y[0]), _stand_hips_y)
			"air":
				hp.y = _stand_hips_y
			"fixed_end":
				# 攀爬類：髖固定在末格（貼地後）高度，身體位移改由 root_path 給腳本驅動。
				hp.y = (frames[n - 1][1] as Vector3).y + lift
		frames[fi][1] = hp
	# --- 寫 Animation：每根身體骨一條 rotation 軌、Hips 一條 position 軌，逐格 key。
	var out := Animation.new()
	out.length = (n - 1) / FPS if n > 1 else 1.0 / FPS
	out.loop_mode = Animation.LOOP_LINEAR if spec.get("loop", false) else Animation.LOOP_NONE
	var pt := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(pt, TRACK_PREFIX + "mixamorig_Hips")
	for fi in n:
		out.position_track_insert_key(pt, fi / FPS, frames[fi][1])
	for ti in _t_body:
		var rt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rt, TRACK_PREFIX + _tsk.get_bone_name(ti))
		for fi in n:
			out.rotation_track_insert_key(rt, fi / FPS, locs[fi][ti])
	# 循環 clip：Mixamo 末格＝首格，留著會停一拍 → 長度截到倒數第二格（key 仍在，播放器不會用到）。
	if out.loop_mode == Animation.LOOP_LINEAR and n > 2:
		out.length = (n - 2) / FPS
	var hy := []
	for fi in n:
		hy.append((frames[fi][1] as Vector3).y)
	if spec.get("root_meta", false):
		# root_path：每格髖的原始位移 − 末格位移（末格 = 0，模型空間 +Z 為正面）。
		for fi in n:
			root_path.append((raw_root[fi] as Vector3) - (raw_root[n - 1] as Vector3))
		out.set_meta("root_path", root_path)
	var disp: Vector3 = raw_root[n - 1] - raw_root[0]
	# 步速（m/s）：控制器用它把 locomotion 播放倍率對到實際移動速度，避免滑步。
	out.set_meta("root_speed", Vector2(disp.x, disp.z).length() / maxf(out.length, 0.001) if n > 1 else 0.0)
	_report[key] = {
		"root_speed_xz": Vector2(disp.x, disp.z).length() / maxf(out.length, 0.001) if n > 1 else 0.0,
		"root_disp": disp, "t0": t0, "t1": times[n - 1],
		"toe_curve": toe_y.map(func(v): return snappedf(v - _ground_toe, 0.01)) if spec.get("curve", false) else [],
		"hips_curve": raw_root.map(func(v): return snappedf(v.y, 0.01)) if spec.get("curve", false) else [],
		"frames": n, "len": out.length, "src_len": a.length, "hip_scale": k, "lift": lift,
		"toe_min_before": toe_min, "hips_y_min": hy.min(), "hips_y_max": hy.max(),
		"arm_clear_min": _arm_clearance(locs, frames),
	}
	return out

# ---------------------------------------------------------------- 雙手握刀修正
## Mixamo 雙手刀素材重定向後，左手會沿／離開握把漂移（實測 Great Sword 揮砍：左掌離握把軸最遠 12 cm、
## 沿軸位置 −2~+20 cm），看起來「手沒握刀」。修正（只改手臂，身體／腿／根照 Mixamo）：
##  1) 每格素材本身的雙手連線（右掌心→左掌心）＝它想表達的握把方向；右手腕以最短弧轉到該方向
##     （上限 max_wrist_deg，兩手距離 < 6 cm 時方向不可信，漸退回原方向）。
##  2) 刀跟右手（Sword_Hand 掛點，user://grip_socket.json）；左手目標 = 刀 × L_rel，
##     L_rel = Great Sword Idle 首格左手相對刀的位姿（Mixamo 自己的雙手握法）。
##  3) 左臂兩骨解析 IK，保留原手肘所在平面；左手腕直接設成目標朝向。
##  4) 素材兩手距離 > 24~32 cm 視為左手放開（踢、單手甩），權重漸退到 0。
var _report_two_hand := {}
var _grip_socket := Transform3D()
var _grip_l_rel := Transform3D()
var _grip_ready := false
const GRIP_FIST_Y := 0.02

func _desc(bi: int) -> Array[int]:
	var out: Array[int] = []
	for c in _tsk.get_bone_children(bi):
		if _tsk.get_bone_name(c).begins_with("mixamorig_"):
			out.append(c)
			out.append_array(_desc(c))
	return out

func _fk_pos(tw: Dictionary, hips: Vector3) -> Dictionary:
	var pos := {}
	for ti in _t_body:
		var p := _tsk.get_bone_parent(ti)
		if not tw.has(p):
			pos[ti] = hips
		else:
			pos[ti] = (pos[p] as Vector3) + (tw[p] as Basis) * _tsk.get_bone_rest(ti).origin
	return pos

func _grip_setup() -> bool:
	if _grip_ready:
		return true
	var js := FileAccess.get_file_as_string("user://grip_socket.json")
	if js == "":
		push_error("缺 user://grip_socket.json（先跑 clip_lab dump gs_idle + grip_fit.py）")
		return false
	var jd: Dictionary = JSON.parse_string(js)
	_grip_socket = str_to_var(jd["Sword_Hand"])
	var ls: Array = jd.get("left_shift", [0, 0, 0])
	var ref: Animation = load(OUT_DIR + "gs_idle_ref.res")
	var g := _fk(_tsk, _sample_local(ref, _tsk, 0.0, TRACK_PREFIX))
	var R: Transform3D = g[_tsk.find_bone("mixamorig_RightHand")]
	var L: Transform3D = g[_tsk.find_bone("mixamorig_LeftHand")]
	R.basis = R.basis.orthonormalized()
	L.basis = L.basis.orthonormalized()
	# 左拳心移到握把軸上（Mixamo 原姿左拳心離軸 5.7 cm＝左手浮在柄旁）：刀本地座標平移。
	_grip_l_rel = Transform3D(Basis(), Vector3(ls[0], ls[1], ls[2])) * (R * _grip_socket).affine_inverse() * L
	_grip_ready = true
	return true

func _swing_set(tw: Dictionary, bi: int, new_world: Basis) -> void:
	# 換掉 bi 的世界朝向，子孫一起帶（保持它們的 local）
	var d: Basis = new_world * (tw[bi] as Basis).inverse()
	tw[bi] = new_world.orthonormalized()
	for c in _desc(bi):
		tw[c] = (d * (tw[c] as Basis)).orthonormalized()

func _two_hand_fix(frames: Array, spec: Dictionary) -> Dictionary:
	if not _grip_setup():
		return {}
	var rh := _tsk.find_bone("mixamorig_RightHand")
	var rm := _tsk.find_bone("mixamorig_RightHandMiddle1")
	var lh := _tsk.find_bone("mixamorig_LeftHand")
	var lm := _tsk.find_bone("mixamorig_LeftHandMiddle1")
	var la := _tsk.find_bone("mixamorig_LeftArm")
	var lf := _tsk.find_bone("mixamorig_LeftForeArm")
	var max_wrist := deg_to_rad(float(spec.get("max_wrist_deg", 35.0)))
	var axis_local := (-(_grip_socket.basis.y)).normalized()     # 右手骨本地：往柄尾
	var stats := {"wrist_max_deg": 0.0, "left_move_max_cm": 0.0, "released_frames": 0}
	var wts: Array[float] = []
	var posture_on: bool = spec.get("posture", POSTURE_DEFAULT)
	wts.resize(frames.size())
	for fi in frames.size():
		wts[fi] = 0.0
		var tw: Dictionary = frames[fi][0]
		var pos := _fk_pos(tw, frames[fi][1])
		var pr: Vector3 = ((pos[rh] as Vector3) + (pos[rm] as Vector3)) * 0.5
		var pl: Vector3 = ((pos[lh] as Vector3) + (pos[lm] as Vector3)) * 0.5
		var v := pl - pr
		var dist := v.length()
		var w := 1.0 - smoothstep(0.24, 0.32, dist)
		if w <= 0.0:
			stats.released_frames += 1
			if posture_on:
				_posture(tw, frames[fi][1], spec)
			continue
		# 1) 右腕對齊素材的握把方向
		var a_now := ((tw[rh] as Basis) * axis_local).normalized()
		if fi == 0 and OS.get_environment("TH_DEBUG") != "":
			print("DBG pr=", pr, " pl=", pl, " dist=", dist, " a_now=", a_now, " v=", v / dist, " ang=", rad_to_deg(a_now.angle_to(v / dist)), " hips=", frames[fi][1])
		var wdir := smoothstep(0.06, 0.10, dist) * w
		if wdir > 0.0:
			var a_want := a_now.slerp(v / dist, wdir).normalized()
			var ang := a_now.angle_to(a_want)
			if ang > 1e-4:
				var ax := a_now.cross(a_want).normalized()
				var q := Quaternion(ax, minf(ang, max_wrist))
				_swing_set(tw, rh, Basis(q) * (tw[rh] as Basis))
				stats.wrist_max_deg = maxf(stats.wrist_max_deg, rad_to_deg(minf(ang, max_wrist)))
		# 1c) 姿勢（挺胸、伸臂）：在握把方向取完之後做，腕朝向保留 → 刀向不變
		if posture_on:
			_posture(tw, frames[fi][1], spec)
		wts[fi] = w
	# 1b) 刀身淨空：刀身穿頭（球心＝頭骨沿頸→頭上移 9 cm、半徑 13 cm）或穿軀幹（髖→頸線段、半徑 15 cm）時，
	#     右腕繞手腕最小角度轉開；修正量在時間上做三角窗擴散（±5 格），進出平滑不跳格。
	var need: Array[Vector3] = []
	need.resize(frames.size())
	for fi in frames.size():
		need[fi] = Vector3.ZERO
		if wts[fi] <= 0.0:
			continue
		need[fi] = _clearance_rotvec(frames[fi][0], frames[fi][1])
	var applied := 0
	for fi in frames.size():
		var best := Vector3.ZERO
		for j in range(maxi(fi - 5, 0), mini(fi + 6, frames.size())):
			var cand: Vector3 = need[j] * (1.0 - absf(j - fi) / 6.0)
			if cand.length() > best.length():
				best = cand
		if best.length() > 1e-4:
			applied += 1
			var tw: Dictionary = frames[fi][0]
			_swing_set(tw, rh, Basis(Quaternion(best.normalized(), best.length())) * (tw[rh] as Basis))
			stats["clear_max_deg"] = maxf(stats.get("clear_max_deg", 0.0), rad_to_deg(best.length()))
	stats["clear_frames"] = applied
	for fi in frames.size():
		var w: float = wts[fi]
		if w <= 0.0:
			continue
		var tw: Dictionary = frames[fi][0]
		# 2) 左手目標
		var pos := _fk_pos(tw, frames[fi][1])
		var R := Transform3D(tw[rh], pos[rh])
		var S := R * _grip_socket
		var A: Vector3 = pos[la]
		var E: Vector3 = pos[lf]
		var W: Vector3 = pos[lh]
		var l1 := A.distance_to(E)
		var l2 := E.distance_to(W)
		# 左手繞握把軸轉 φ／沿柄滑 s：手握圓柱本來就有這兩個自由度。挑「手臂搆得到」且偏離參考最少的那組
		# （參考握位把左拳心推到軸上後，常超出手臂長度 → IK 夾到極限，拳心又離軸）。
		var T := S * _grip_l_rel
		var best_c := INF
		for phi_deg in range(-70, 71, 10):
			for s_cm in [0.0, -2.0, 2.0, -4.0, 4.0]:
				var c := S * Transform3D(Basis(Vector3.UP, deg_to_rad(phi_deg)), Vector3(0, s_cm / 68.0, 0)) * _grip_l_rel
				var over := maxf(A.distance_to(c.origin) - (l1 + l2 - 0.01), 0.0)
				var cost := over * 1000.0 + absf(phi_deg) * 0.05 + absf(s_cm) * 0.3
				if cost < best_c:
					best_c = cost
					T = c
		var L0 := Transform3D(tw[lh], pos[lh])
		var tgt := L0.origin.lerp(T.origin, w)
		var tb := Basis((L0.basis.get_rotation_quaternion()).slerp(T.basis.orthonormalized().get_rotation_quaternion(), w))
		# 3) 兩骨 IK
		var to := tgt - A
		var dd := clampf(to.length(), absf(l1 - l2) + 0.005, l1 + l2 - 0.002)
		var u := to.normalized()
		var side := (E - A) - u * (E - A).dot(u)
		if side.length() < 1e-4:
			side = (tw[la] as Basis) * Vector3(0, 0, 1)
			side = side - u * side.dot(u)
		side = side.normalized()
		var cos_a := clampf((l1 * l1 + dd * dd - l2 * l2) / (2.0 * l1 * dd), -1.0, 1.0)
		var E2 := A + l1 * (cos_a * u + sqrt(1.0 - cos_a * cos_a) * side)
		var W2 := A + u * dd
		var r1 := Quaternion((E - A).normalized(), (E2 - A).normalized())
		_swing_set(tw, la, Basis(r1) * (tw[la] as Basis))
		pos = _fk_pos(tw, frames[fi][1])
		var cur_dir := ((pos[lh] as Vector3) - (pos[lf] as Vector3)).normalized()
		var r2 := Quaternion(cur_dir, (W2 - E2).normalized())
		_swing_set(tw, lf, Basis(r2) * (tw[lf] as Basis))
		_swing_set(tw, lh, tb)
		stats.left_move_max_cm = maxf(stats.left_move_max_cm, W.distance_to(W2) * 100.0)
	return stats

## ---------------------------------------------------------------- 單手刀（第三輪：「超人類武士」）
## 單手持刀：挺胸伸臂（_posture）＋ 左手握鞘口（居合的「鯉口」手勢，取代 Mixamo 劍盾素材舉在胸前的盾手）
## ＋ 刀身淨空。左手目標 = 鞘中刀框（Hips × Sword_Sheathed 掛點，讀 player_yoriichi.tscn）沿刀軸到鞘口後
## SAYA_GRIP_Y，握法沿用 Great Sword Idle 的左手握把姿勢（_grip_l_rel，拳心在軸上）；可繞鞘轉 ±70° 挑搆得到的。
## grab_hilt=[f0, f1, f2]（輸出格）：右手在 f1 準確握住鞘中刀柄（三角權重淡入淡出）——拔刀用。
const SAYA_GRIP_Y := 0.17
var _ss_local := Transform3D()
var _ss_ready := false
var _left_fist_locals := {}

func _saya_setup() -> bool:
	if _ss_ready:
		return true
	if not _grip_setup():
		return false
	var t := FileAccess.get_file_as_string("res://characters/yoriichi/player_yoriichi.tscn")
	var re := RegEx.new()
	re.compile("\\[node name=\"Sword_Sheathed\"[^\\n]*\\]\\ntransform = (Transform3D\\([^)]*\\))")
	var m := re.search(t.replace("\r\n", "\n"))
	if m == null:
		push_error("player_yoriichi.tscn 找不到 Sword_Sheathed transform")
		return false
	_ss_local = str_to_var(m.get_string(1))
	var ref: Animation = load(OUT_DIR + "gs_idle_ref.res")
	var loc := _sample_local(ref, _tsk, 0.0, TRACK_PREFIX)
	for i in _tsk.get_bone_count():
		var bn := _tsk.get_bone_name(i)
		if bn.begins_with("mixamorig_LeftHand") and bn != "mixamorig_LeftHand":
			_left_fist_locals[i] = (loc[i] as Transform3D).basis.get_rotation_quaternion()
	_ss_ready = true
	return true

func _one_hand_fix(frames: Array, spec: Dictionary) -> Dictionary:
	if not _saya_setup():
		return {}
	var hb := _tsk.find_bone("mixamorig_Hips")
	var rh := _tsk.find_bone("mixamorig_RightHand")
	var ra := _tsk.find_bone("mixamorig_RightArm")
	var rf := _tsk.find_bone("mixamorig_RightForeArm")
	var la := _tsk.find_bone("mixamorig_LeftArm")
	var lf := _tsk.find_bone("mixamorig_LeftForeArm")
	var lh := _tsk.find_bone("mixamorig_LeftHand")
	var saya_w: float = spec.get("left_saya", 1.0)
	var grab: Array = spec.get("grab_hilt", [])
	var stats := {"left_reach_miss_cm": 0.0, "grab_err_cm": -1.0}
	for fi in frames.size():
		var tw: Dictionary = frames[fi][0]
		var hips: Vector3 = frames[fi][1]
		if spec.get("posture", POSTURE_DEFAULT):
			_posture(tw, hips, spec)
		var pos := _fk_pos(tw, hips)
		var SS := Transform3D(tw[hb], pos[hb]) * _ss_local
		# 右手握鞘中刀柄（拔刀的抓柄瞬間）
		if grab.size() == 3:
			var g := 0.0
			if fi >= grab[0] and fi <= grab[2]:
				g = float(fi - grab[0]) / maxf(grab[1] - grab[0], 1) if fi <= grab[1] else 1.0 - float(fi - grab[1]) / maxf(grab[2] - grab[1], 1)
			if g > 0.0:
				var Rt := SS * _grip_socket.affine_inverse()
				var R0 := Transform3D(tw[rh], pos[rh])
				var hb0: Basis = tw[rh]
				_two_bone(tw, hips, ra, rf, rh, R0.origin.lerp(Rt.origin, g))
				_swing_set(tw, rh, Basis(hb0.get_rotation_quaternion().slerp(Rt.basis.orthonormalized().get_rotation_quaternion(), g)))
				if fi == grab[1]:
					stats.grab_err_cm = (_fk_pos(tw, hips)[rh] as Vector3).distance_to(Rt.origin) * 100.0
		# 左手握鞘口
		if saya_w > 0.0:
			pos = _fk_pos(tw, hips)
			var A: Vector3 = pos[la]
			var reach := A.distance_to(pos[lf]) + (pos[lf] as Vector3).distance_to(pos[lh])
			var base := SS * Transform3D(Basis(), Vector3(0, SAYA_GRIP_Y - (GRIP_FIST_Y - 0.164 / 0.68), 0))
			var T := base * _grip_l_rel
			var best := INF
			for phi in range(-70, 71, 10):
				var c := base * Transform3D(Basis(Vector3.UP, deg_to_rad(phi)), Vector3.ZERO) * _grip_l_rel
				var cost := maxf(A.distance_to(c.origin) - (reach - 0.01), 0.0) * 1000.0 + absf(phi) * 0.05
				if cost < best:
					best = cost
					T = c
			stats.left_reach_miss_cm = maxf(stats.left_reach_miss_cm, maxf(A.distance_to(T.origin) - reach, 0.0) * 100.0)
			var L0 := Transform3D(tw[lh], pos[lh])
			_two_bone(tw, hips, la, lf, lh, L0.origin.lerp(T.origin, saya_w))
			_swing_set(tw, lh, Basis(L0.basis.get_rotation_quaternion().slerp(T.basis.orthonormalized().get_rotation_quaternion(), saya_w)))
			# 左手指：握拳（世界朝向 = 手 × 參考 local）
			for fb in _left_fist_locals:
				var p := _tsk.get_bone_parent(fb)
				var want: Basis = (tw[p] as Basis) * Basis(_left_fist_locals[fb] as Quaternion)
				var cur: Basis = tw[fb]
				_swing_set(tw, fb, Basis(cur.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), saya_w)))
	# 刀身淨空（同雙手版，時間上三角窗擴散）
	var need: Array[Vector3] = []
	need.resize(frames.size())
	for fi in frames.size():
		need[fi] = _clearance_rotvec(frames[fi][0], frames[fi][1])
	var applied := 0
	for fi in frames.size():
		var best := Vector3.ZERO
		for j in range(maxi(fi - 5, 0), mini(fi + 6, frames.size())):
			var cand: Vector3 = need[j] * (1.0 - absf(j - fi) / 6.0)
			if cand.length() > best.length():
				best = cand
		if best.length() > 1e-4:
			applied += 1
			var tw: Dictionary = frames[fi][0]
			_swing_set(tw, rh, Basis(Quaternion(best.normalized(), best.length())) * (tw[rh] as Basis))
	stats["clear_frames"] = applied
	return stats

## ---------------------------------------------------------------- 姿勢修正（第三輪：「超人類武士」）
## 量測（clip_lab dump）：Great Sword 素材是西洋大劍的蜷縮持刀——持刀待機 髖→頸前傾 25.5°（空手待機 3.8°）、
## 右手離胸口水平只有 18 cm、手肘彎 ~110°。修正（每格，在握把修正之前）：
##  1) 挺胸：前傾超過 UPRIGHT_DEG 的部分只保留 UPRIGHT_KEEP（攻擊時的弓步前衝仍看得到，但不駝背）；
##     修正量分給 Spine／Spine1／Spine2（0.4／0.3／0.3），頸部反向補回，頭的朝向（視線）不變。
##  2) 伸臂：右手腕沿「右肩→右腕」方向外推到原距離 × REACH_SCALE（上限 = 臂長 96%），兩骨 IK、腕朝向不變；
##     左手之後由握把 IK 跟上。手肘從抱胸的 ~110° 打開。
const POSTURE_DEFAULT := true
const UPRIGHT_DEG := 6.0
const UPRIGHT_KEEP := 0.25
const REACH_SCALE := 1.2
const HEAD_TILT_MAX := 20.0

func _posture(tw: Dictionary, hips: Vector3, spec: Dictionary) -> void:
	var up_deg: float = spec.get("upright_deg", UPRIGHT_DEG)
	var keep: float = spec.get("upright_keep", UPRIGHT_KEEP)
	var reach: float = spec.get("reach", REACH_SCALE)
	var pos := _fk_pos(tw, hips)
	var hb := _tsk.find_bone("mixamorig_Hips")
	var nk := _tsk.find_bone("mixamorig_Neck")
	var v0: Vector3 = (pos[nk] as Vector3) - (pos[hb] as Vector3)
	var lean0 := rad_to_deg(v0.angle_to(Vector3.UP))
	var want := up_deg + (lean0 - up_deg) * keep
	# 脊椎樞紐在髖上方，轉一次只修到一部分 → 迭代到髖→頸前傾 ≈ want（最多 4 次）。
	for _it in 4:
		pos = _fk_pos(tw, hips)
		var v: Vector3 = (pos[nk] as Vector3) - (pos[hb] as Vector3)
		var lean := rad_to_deg(v.angle_to(Vector3.UP))
		if lean <= up_deg + 0.5 or lean <= want + 0.5:
			break
		var delta := deg_to_rad(lean - want)
		var ax := v.cross(Vector3.UP).normalized()
		for pair in [["mixamorig_Spine", 0.4], ["mixamorig_Spine1", 0.3], ["mixamorig_Spine2", 0.3]]:
			var bi := _tsk.find_bone(pair[0])
			_swing_set(tw, bi, Basis(Quaternion(ax, delta * float(pair[1]))) * (tw[bi] as Basis))
		_swing_set(tw, nk, Basis(Quaternion(ax, -delta)) * (tw[nk] as Basis))
	# 頸：量到攻擊素材 Neck→Head 前傾 34–42°（烏龜頸 = 「蜷縮」的主因）。壓到 HEAD_TILT_MAX，
	# Head 骨反向補回一半 → 視線仍略朝下看敵人，但頭疊在肩上。
	var ht_max: float = spec.get("head_tilt", HEAD_TILT_MAX)
	pos = _fk_pos(tw, hips)
	var hd := _tsk.find_bone("mixamorig_Head")
	var hv: Vector3 = (pos[hd] as Vector3) - (pos[nk] as Vector3)
	var tilt := rad_to_deg(hv.angle_to(Vector3.UP))
	if tilt > ht_max + 0.5:
		var hdelta := deg_to_rad(tilt - ht_max)
		var hax := hv.cross(Vector3.UP).normalized()
		_swing_set(tw, nk, Basis(Quaternion(hax, hdelta)) * (tw[nk] as Basis))
		_swing_set(tw, hd, Basis(Quaternion(hax, -hdelta * 0.5)) * (tw[hd] as Basis))
	if reach > 1.001:
		pos = _fk_pos(tw, hips)
		var ra := _tsk.find_bone("mixamorig_RightArm")
		var rf := _tsk.find_bone("mixamorig_RightForeArm")
		var rh := _tsk.find_bone("mixamorig_RightHand")
		var A: Vector3 = pos[ra]
		var E: Vector3 = pos[rf]
		var W: Vector3 = pos[rh]
		var l1 := A.distance_to(E)
		var l2 := E.distance_to(W)
		var d := A.distance_to(W)
		var nd := minf(d * reach, (l1 + l2) * 0.96)
		if nd > d + 0.002:
			var hand_basis: Basis = tw[rh]
			_two_bone(tw, hips, ra, rf, rh, A + (W - A).normalized() * nd)
			_swing_set(tw, rh, hand_basis)

## 兩骨解析 IK（保留原手肘平面）：只轉 root／mid 骨，末端骨朝向由呼叫端另設。
func _two_bone(tw: Dictionary, hips: Vector3, root_b: int, mid_b: int, end_b: int, target: Vector3) -> void:
	var pos := _fk_pos(tw, hips)
	var A: Vector3 = pos[root_b]
	var E: Vector3 = pos[mid_b]
	var W: Vector3 = pos[end_b]
	var l1 := A.distance_to(E)
	var l2 := E.distance_to(W)
	var to := target - A
	var dd := clampf(to.length(), absf(l1 - l2) + 0.005, l1 + l2 - 0.002)
	var u := to.normalized()
	var side := (E - A) - u * (E - A).dot(u)
	if side.length() < 1e-4:
		return
	side = side.normalized()
	var cos_a := clampf((l1 * l1 + dd * dd - l2 * l2) / (2.0 * l1 * dd), -1.0, 1.0)
	var E2 := A + l1 * (cos_a * u + sqrt(1.0 - cos_a * cos_a) * side)
	var W2 := A + u * dd
	_swing_set(tw, root_b, Basis(Quaternion((E - A).normalized(), (E2 - A).normalized())) * (tw[root_b] as Basis))
	pos = _fk_pos(tw, hips)
	var cur := ((pos[end_b] as Vector3) - (pos[mid_b] as Vector3)).normalized()
	_swing_set(tw, mid_b, Basis(Quaternion(cur, (W2 - E2).normalized())) * (tw[mid_b] as Basis))

## 刀身穿頭／穿身時，右手腕要轉的最小旋轉（世界座標旋轉向量 axis*angle；不穿 = ZERO）。
func _clearance_rotvec(tw: Dictionary, hips: Vector3) -> Vector3:
	var pos := _fk_pos(tw, hips)
	var rh := _tsk.find_bone("mixamorig_RightHand")
	var wr: Vector3 = pos[rh]
	var S := Transform3D(tw[rh], wr) * _grip_socket
	var pts: Array[Vector3] = []
	for i in 10:
		pts.append(S * Vector3(0, lerpf(0.16, 1.05, i / 9.0), 0))
	var hd: Vector3 = pos[_tsk.find_bone("mixamorig_Head")]
	var nk: Vector3 = pos[_tsk.find_bone("mixamorig_Neck")]
	var hc := hd + (hd - nk).normalized() * 0.09
	var h0: Vector3 = pos[_tsk.find_bone("mixamorig_Hips")]
	var cost := func(q: Quaternion) -> float:
		var c := 0.0
		for p in pts:
			var pp: Vector3 = wr + q * (p - wr)
			c += maxf(0.0, 0.13 - pp.distance_to(hc))
			c += maxf(0.0, 0.15 - pp.distance_to(Geometry3D.get_closest_point_to_segment(pp, h0, nk)))
		return c
	if cost.call(Quaternion()) <= 0.0:
		return Vector3.ZERO
	var axes: Array[Vector3] = []
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x != 0 or y != 0 or z != 0:
					axes.append(Vector3(x, y, z).normalized())
	var best := Vector3.ZERO
	var best_c := INF
	for deg in range(5, 55, 5):
		for ax in axes:
			var c: float = cost.call(Quaternion(ax, deg_to_rad(deg)))
			if c < best_c - 1e-6:
				best_c = c
				best = ax * deg_to_rad(deg)
		if best_c <= 0.0:
			break
	return best

## 右手（刀手）最快的一格附近取窗：[峰值-pre, 峰值+post] 格（來源時間，秒）。
func _strike_window(sk: Skeleton3D, a: Animation, ws: Transform3D, pre: int, post: int) -> Array:
	var rh := sk.find_bone("mixamorig_RightHand")
	var nf := int(a.length * FPS)
	var prev := Vector3.INF
	var best := 0.0
	var bf := 0
	for fi in nf + 1:
		var g := _fk(sk, _sample_local(a, sk, fi / FPS, ""))
		var hp: Vector3 = ws * (g[rh] as Transform3D).origin
		if prev != Vector3.INF and hp.distance_to(prev) > best:
			best = hp.distance_to(prev)
			bf = fi
		prev = hp
	return [maxf(0.0, (bf - pre) / FPS), minf(a.length, (bf + post) / FPS)]

func _toe_y(lr: Dictionary, hips_pos: Vector3) -> float:
	var loc := {}
	for i in _tsk.get_bone_count():
		loc[i] = _tsk.get_bone_rest(i)
	for ti in lr:
		var x: Transform3D = loc[ti]
		x.basis = Basis(lr[ti] as Quaternion)
		loc[ti] = x
	var hx: Transform3D = loc[_tsk.find_bone("mixamorig_Hips")]
	hx.origin = hips_pos
	loc[_tsk.find_bone("mixamorig_Hips")] = hx
	var g := _fk(_tsk, loc)
	return minf((g[_tsk.find_bone("mixamorig_LeftToeBase")] as Transform3D).origin.y, (g[_tsk.find_bone("mixamorig_RightToeBase")] as Transform3D).origin.y)

## 手肘／手腕到軀幹垂直軸（Hips→Spine2 連線）的最小水平距離（m）——袖子貼身程度的代理量測。
func _arm_clearance(locs: Array, frames: Array) -> float:
	var best := 99.0
	for fi in range(0, locs.size(), 2):
		var loc := {}
		for i in _tsk.get_bone_count():
			loc[i] = _tsk.get_bone_rest(i)
		for ti in locs[fi]:
			var x: Transform3D = loc[ti]
			x.basis = Basis(locs[fi][ti] as Quaternion)
			loc[ti] = x
		var hx: Transform3D = loc[_tsk.find_bone("mixamorig_Hips")]
		hx.origin = frames[fi][1]
		loc[_tsk.find_bone("mixamorig_Hips")] = hx
		var g := _fk(_tsk, loc)
		var a0: Vector3 = (g[_tsk.find_bone("mixamorig_Hips")] as Transform3D).origin
		var a1: Vector3 = (g[_tsk.find_bone("mixamorig_Spine2")] as Transform3D).origin
		for b in ["mixamorig_LeftForeArm", "mixamorig_RightForeArm", "mixamorig_LeftHand", "mixamorig_RightHand"]:
			var p: Vector3 = (g[_tsk.find_bone(b)] as Transform3D).origin
			if p.y < a0.y - 0.15 or p.y > a1.y:
				continue
			var q := Geometry3D.get_closest_point_to_segment(p, a0, a1)
			best = minf(best, Vector2(p.x - q.x, p.z - q.z).length())
	return best

func _concat(parts: Array) -> Animation:
	var out := Animation.new()
	var off := 0.0
	var secs := PackedFloat32Array()
	var tracks := {}
	for pk in parts:
		var a: Animation = load(OUT_DIR + pk + ".res")
		secs.append(off)
		for t in a.get_track_count():
			var path := a.track_get_path(t)
			var key := str(path) + "#" + str(a.track_get_type(t))
			if not tracks.has(key):
				var nt := out.add_track(a.track_get_type(t))
				out.track_set_path(nt, path)
				tracks[key] = nt
			var ti: int = tracks[key]
			for kk in a.track_get_key_count(t):
				var kt := a.track_get_key_time(t, kk)
				if kt > a.length + 0.001:
					continue
				if off > 0.0 and kk == 0:
					kt += 0.5 / FPS   # 段間半格，避免同時間兩個 key
				match a.track_get_type(t):
					Animation.TYPE_ROTATION_3D:
						out.rotation_track_insert_key(ti, off + kt, a.track_get_key_value(t, kk))
					Animation.TYPE_POSITION_3D:
						out.position_track_insert_key(ti, off + kt, a.track_get_key_value(t, kk))
		off += a.length + 1.0 / FPS
	out.length = off - 1.0 / FPS
	for i in secs.size():
		secs[i] = secs[i] / out.length
	out.set_meta("sections", secs)
	return out

# ---------------------------------------------------------------- 驗證
## 用同一份 Mixamo 走路比對：自己重定向的結果 vs GLB 內既有的 walk / walk_user（Blender 端產生）。
func _validate() -> void:
	var ap: AnimationPlayer = _tgt.find_child("AnimationPlayer", true, false)
	for pair in [["_ref_walk078", "walk", true], ["_ref_walk078", "walk", false], ["_ref_walk_user", "walk_user", true], ["_ref_walk_user", "walk_user", false]]:
		MATCH_DIR = pair[2]
		var mine := build_clip(pair[0])
		if mine == null:
			continue
		var ref := ap.get_animation(pair[1])
		var worst := 0.0
		var worst_b := ""
		var best_mean := 999.0
		var best_off := 0
		var nf := int(minf(mine.length, ref.length) * FPS) - 3
		for off in range(-3, 4):
			var sum := 0.0
			var cnt := 0
			var wv := 0.0
			var wb := ""
			for fi in range(3, nf):
				var g1 := _fk(_tsk, _sample_local(mine, _tsk, fi / FPS, TRACK_PREFIX))
				var g2 := _fk(_tsk, _sample_local(ref, _tsk, (fi + off) / FPS, TRACK_PREFIX))
				for ti in _t_body:
					var bn := _tsk.get_bone_name(ti)
					if bn.contains("Index") or bn.contains("Middle") or bn.contains("Ring") or bn.contains("Pinky") or bn.contains("Thumb"):
						continue
					var ang := (g1[ti] as Transform3D).basis.get_rotation_quaternion().angle_to((g2[ti] as Transform3D).basis.get_rotation_quaternion())
					sum += ang
					cnt += 1
					if ang > wv:
						wv = ang
						wb = bn + "@f" + str(fi)
			var mean := rad_to_deg(sum / maxf(cnt, 1))
			if mean < best_mean:
				best_mean = mean
				best_off = off
				worst = wv
				worst_b = wb
		var sum := deg_to_rad(best_mean)
		var cnt := 1
		print("VALIDATE ", pair, " frames=", nf, " mine_len=", mine.length, " ref_len=", ref.length, " off=", best_off, " mean_deg(no fingers)=", best_mean, " max_deg=", rad_to_deg(worst), " at ", worst_b)
