extends "res://characters/yoriichi/yoriichi_character_r5.gd"
## R6 候選控制器「Yoriichi R6 Animation Integration」（只給 player_yoriichi_r6.tscn 用；正式 yoriichi_character.gd、
## R5 子類 yoriichi_character_r5.gd 一行不改）。
## 在 R5（拔刀斬機制）之上加：
##   1. 下半身戰鬥層（lower OneShot，filter = Hips＋雙腿）：原地普通斬／重斬時，腿與骨盆也播攻擊 clip 本身的步法與重心，
##      上半身仍走既有 upper 層；一有移動輸入或離地就 0.15 s 淡回 locomotion 的腿（移動反應不變）。
##   2. 重斬右／左手握持換成 R6 片段；握拳覆蓋（grip overlay）改用 R6 實際刀柄網格解出的右手指形。
## 其餘（待機、持刀待機、跳躍、R6 拔刀斬資源、關掉 NPC 待機小動作）都是 export 值，由 make_r6_candidate.gd 寫進場景。

## 原地攻擊時腿跟著攻擊 clip（false = 與 R3/R5 相同的純上半身層）
@export var r6_lower_combat_enabled := true
@export var r6_lower_fadein := 0.08
@export var r6_lower_fadeout := 0.15
## 攻擊自然結束（站著沒動）時下半身回待機步幅的淡出時間；移動／離地打斷仍用 r6_lower_fadeout（反應不變）
@export var r6_lower_endfade := 0.35
## 視為「原地」的水平速度上限（m/s）
@export var r6_lower_still_speed := 0.35

const R6_LOWER_INPUTS := ["atk1", "atk2", "atk3", "heavy"]

var _r6_lower: AnimationNodeOneShot = null
var _r6_lower_on := false


func _ready():
	super._ready()
	_r6_install_lower()


func _r6_lower_filter_paths() -> Array[String]:
	var out: Array[String] = []
	var sks := _visual.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return out
	var sk: Skeleton3D = sks[0]
	var prefix := str(_visual.get_path_to(sk)) + ":"
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		if bn == "mixamorig_Hips" or bn.begins_with("mixamorig_LeftUpLeg") or bn.begins_with("mixamorig_LeftLeg") \
				or bn.begins_with("mixamorig_LeftFoot") or bn.begins_with("mixamorig_LeftToe") \
				or bn.begins_with("mixamorig_RightUpLeg") or bn.begins_with("mixamorig_RightLeg") \
				or bn.begins_with("mixamorig_RightFoot") or bn.begins_with("mixamorig_RightToe"):
			out.append(prefix + bn)
	return out


func _r6_install_lower() -> void:
	if not r6_lower_combat_enabled or _tree == null:
		return
	var root := _tree.tree_root as AnimationNodeBlendTree
	if root == null or not root.has_node("upper"):
		return
	var combo_len := attack_combo_resource.length
	var sel := AnimationNodeTransition.new()
	var inputs := {
		"atk1": _clip_node(attack_combo_anim, combo_len * COMBO_SECTION_RANGES[0].x, combo_len * COMBO_SECTION_RANGES[0].y),
		"atk2": _clip_node(attack_combo_anim, combo_len * COMBO_SECTION_RANGES[1].x, combo_len * COMBO_SECTION_RANGES[1].y),
		"atk3": _clip_node(attack_combo_anim, combo_len * COMBO_SECTION_RANGES[2].x, combo_len * COMBO_SECTION_RANGES[2].y),
		"heavy": _anim_node("Heavy_Cut") if _anim.has_animation("Heavy_Cut") else _clip_node(attack_combo_anim, 0.0, combo_len * COMBO_SECTION_RANGES[0].y),
	}
	_setup_transition(root, sel, "lower_sel", inputs)
	var ts := AnimationNodeTimeScale.new()
	root.add_node("ts_lower", ts)
	root.connect_node("ts_lower", 0, "lower_sel")
	var lower := AnimationNodeOneShot.new()
	lower.fadein_time = r6_lower_fadein
	lower.fadeout_time = r6_lower_fadeout
	lower.filter_enabled = true
	for path in _r6_lower_filter_paths():
		lower.set_filter_path(path, true)
	root.add_node("lower", lower)
	# loco -> lower -> upper（原本 upper 的輸入 0 是 loco）
	root.disconnect_node("upper", 0)
	root.connect_node("lower", 0, "loco")
	root.connect_node("lower", 1, "ts_lower")
	root.connect_node("upper", 0, "lower")
	_r6_lower = lower


func _r6_still() -> bool:
	var hv := Vector2(velocity.x, velocity.z)
	return is_on_floor() and hv.length() <= r6_lower_still_speed and _read_input_dir().length_squared() == 0.0


func _fire_upper(input_name: String, time_scale: float) -> void:
	super._fire_upper(input_name, time_scale)
	if _r6_lower == null:
		return
	if input_name in R6_LOWER_INPUTS and _r6_still():
		_tree.set("parameters/lower_sel/transition_request", input_name)
		_tree.set("parameters/ts_lower/scale", time_scale)
		_r6_lower.fadeout_time = maxf(r6_lower_fadeout, _upper_finish_fade)
		if not _tree.get("parameters/lower/internal_active"):
			_tree.set("parameters/lower/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_r6_lower_on = true
	elif _r6_lower_on:
		_r6_lower_fade()


func _r6_lower_fade(fade := -1.0) -> void:
	_r6_lower_on = false
	if _tree.get("parameters/lower/internal_active"):
		_r6_lower.fadeout_time = r6_lower_fadeout if fade < 0.0 else fade
		_tree.set("parameters/lower/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func _physics_process(delta):
	super._physics_process(delta)
	_r6_heavy_window()
	if _r6_lower == null or not _r6_lower_on:
		return
	# 上半身節奏（含重斬蓄力凍結）同步給下半身
	_tree.set("parameters/ts_lower/scale", _tree.get("parameters/ts_upper/scale"))
	if not _r6_still():
		_r6_lower_fade()
	elif action_state != ActionState.ATTACKING or not _tree.get("parameters/upper/internal_active"):
		_r6_lower_fade(r6_lower_endfade)


## R6 重斬（雙手）：判定與刀光只開在 clip 自己的落刀窗（metadata r5_hit_window，R6 = f25–30），
## 舉刀與收勢不拖刀光（父類短按重斬是整段開判定＋刀光，R3 片段沒有收勢段所以看不出來）。
## 蓄力架勢／居合衝刺（full 層）不經這裡。
var _r6_hv_trail := false

func _r6_heavy_window() -> void:
	if action_state != ActionState.ATTACKING or _active_attack_name != "Heavy_Cut" or _attack_layer != "upper" \
			or _heavy_charging or _heavy_frozen or heavy_cut_resource == null:
		_r6_hv_trail = false
		return
	var win: PackedInt32Array = heavy_cut_resource.get_meta("r5_hit_window", PackedInt32Array())
	if win.size() < 2 or win[0] < 0:
		return
	var fr := _action_elapsed * heavy_cut_speed * 30.0
	var on := fr >= float(win[0]) - 1.0 and fr <= float(win[1]) + 1.0
	if _hitbox != null:
		_hitbox.monitoring = on
	if _sword_trail == null:
		return
	if on and not _r6_hv_trail:
		_r6_hv_trail = true
		_sword_trail.reset_form()
		_sword_trail.start_trail()
	elif not on:
		if fr < float(win[0]) - 1.0:
			# 舉刀段：關掉父類一開始就點亮的刀光
			_sword_trail.stop_trail()
		elif fr > float(win[1]) + 3.0 and _r6_hv_trail:
			_sword_trail.stop_trail()
			_r6_hv_trail = false


## R6 重斬：clip 尾段（f46 以後左手放柄回鞘、回持刀架）只是視覺收尾，不鎖操作。
## 控制權在 metadata r6_ctrl_end 幀交還（_finish_attack 的 upper 淡出 0.24 s 接回持刀待機），
## 讓整招鎖定時間與 R3 重斬同級（R3 ≈ 1.1 s；R6 = 46 幀 / 30 / heavy_cut_speed）。
func _heavy_len() -> float:
	if _anim != null and _anim.has_animation("Heavy_Cut"):
		var a := _anim.get_animation("Heavy_Cut")
		if a.has_meta("r6_ctrl_end"):
			return minf(a.length, float(a.get_meta("r6_ctrl_end")) / 30.0)
	return super._heavy_len()


## 正式 _add_animation_resource 遇到同名動畫就不加：v2.4 GLB 內建了一支「idle」，
## 所以 idle_grounded_resource（R6 收刀待機）原本被擋掉，實機播的仍是正式 idle（R6 執行期稽核 r6_probe_resources.gd 抓到）。
## 候選場景改為：收刀待機以 R6 資源覆蓋同名內建。先把 AnimationPlayer 的動畫庫換成本實例自己的淺拷貝，
## 不改動 GLB 快取裡共用的那份（正式場景不受影響）。
func _add_animation_resource(animation_name: String, animation: Animation) -> void:
	if animation_name == idle_anim and animation != null and _anim != null and _anim.has_animation(animation_name) \
			and _anim.get_animation(animation_name) != animation:
		var lname: StringName = _anim.get_animation_library_list()[0]
		var own: AnimationLibrary = _anim.get_animation_library(lname).duplicate()
		_anim.remove_animation_library(lname)
		_anim.add_animation_library(lname, own)
		own.remove_animation(animation_name)
		own.add_animation(animation_name, animation)
		return
	super._add_animation_resource(animation_name, animation)
