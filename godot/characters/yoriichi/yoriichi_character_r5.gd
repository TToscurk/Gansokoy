extends "res://characters/yoriichi/yoriichi_character.gd"
## R5 候選控制器（只給 player_yoriichi_r5.tscn 用；正式 yoriichi_character.gd 一行不改）。
## Vergil 啟發、緣一原創「快速拔刀逆袈裟」：收刀狀態按 LMB → 完整一段
##   平靜備戰 → 右手握柄＋左手控鞘 → 節制預備 → 爆發拔刀 → 全身逆袈裟 → 隨揮 → 殘心 → 納刀 → 歸架。
## 架構：沿用現有 full 層（無 filter 的 OneShot）播全身 clip；腳紮地（移動倍率 0、不滑步），
## 殘心後若有移動輸入 → 剩餘的納刀改在 upper 層播、腿交回 locomotion（受控的攻擊專用混合）。
## 鞘的左手控制（鞘引き／鞘の回転）、刀身露出長度、手上刀／鞘中刀切換、命中窗口：讀 Animation metadata。
## 其餘輸入（拔刀鍵、已拔刀的 LMB 連段、RMB、型、閃避…）全部交回父類。

@export var r5_enabled := true
@export var r5_quickdraw_resource: Animation = preload("res://characters/yoriichi/v24/anims_r5/r5_quickdraw_kesa.res")
@export_range(0.5, 1.5, 0.01) var r5_speed := 1.0
## 拔斬～殘心期間的移動倍率（0 = 腳紮地；clip 自己有踏步）
@export_range(0.0, 1.0, 0.05) var r5_move_factor := 0.0
## 從這一格起，移動輸入可把剩餘的納刀交給 upper 層（腿回 locomotion）
@export var r5_cancel_frame := 40

const R5_ANIM := "R5_QuickDrawKesa"
const R5_TAIL_STEP := 6

var _r5_active := false
var _r5_tail := false
var _r5_fps := 30.0
var _r5_n := 0
var _r5_saya := PackedFloat32Array()
var _r5_clip := PackedFloat32Array()
var _r5_vis := PackedByteArray()
var _r5_hit := PackedInt32Array([27, 33])
var _r5_sheath: Node3D = null
var _r5_sheath_rest := Transform3D.IDENTITY
var _r5_ss_rest := Transform3D.IDENTITY
var _r5_sway_gain := 1.0
var _r5_saved_move := 0.5
var _r5_hand_sm: Array[ShaderMaterial] = []
var _r5_hand_mi: Array[MeshInstance3D] = []
var _r5_tails: Array[int] = []
var _r5_trail_on := false

const HILT_SHADER := preload("res://characters/yoriichi/sheath_v2/sword_hilt_only.gdshader")


func _ready():
	super._ready()
	_r5_install()


func _r5_install() -> void:
	if r5_quickdraw_resource == null or _tree == null:
		r5_enabled = false
		return
	var a := r5_quickdraw_resource
	_r5_fps = float(a.get_meta("r5_fps", 30.0))
	_r5_saya = a.get_meta("r5_saya_offset", PackedFloat32Array())
	_r5_clip = a.get_meta("r5_clip_y", PackedFloat32Array())
	_r5_vis = a.get_meta("r5_hand_visible", PackedByteArray())
	_r5_hit = a.get_meta("r5_hit_window", PackedInt32Array([27, 33]))
	_r5_n = _r5_clip.size()
	_add_animation_resource(R5_ANIM, a)
	var root := _tree.tree_root as AnimationNodeBlendTree
	# full 層：整段全身
	var fsel := root.get_node("full_sel") as AnimationNodeTransition
	var fi := fsel.input_count
	fsel.input_count = fi + 1
	fsel.set_input_name(fi, "r5_qd")
	fsel.set_input_reset(fi, true)
	root.add_node("full_sel_r5_qd", _anim_node(R5_ANIM))
	root.connect_node("full_sel", fi, "full_sel_r5_qd")
	# upper 層：殘心後被移動打斷時，從最近的段落接著播剩下的納刀（腿交回 locomotion）
	var usel := root.get_node("upper_sel") as AnimationNodeTransition
	_r5_tails.clear()
	var f := r5_cancel_frame
	while f < _r5_n - 4:
		var ui := usel.input_count
		usel.input_count = ui + 1
		var key := "r5_tail_%d" % f
		usel.set_input_name(ui, key)
		usel.set_input_reset(ui, true)
		root.add_node("upper_sel_" + key, _clip_node(R5_ANIM, float(f) / _r5_fps, a.length))
		root.connect_node("upper_sel", ui, "upper_sel_" + key)
		_r5_tails.append(f)
		f += R5_TAIL_STEP
	_r5_sheath = _find_first("Sheath") as Node3D
	if _r5_sheath:
		_r5_sheath_rest = _r5_sheath.transform
	if _sword_sheathed:
		_r5_ss_rest = _sword_sheathed.transform
	if _sword_hand:
		for mi in _sword_hand.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var src := m.get_active_material(0) as StandardMaterial3D
			var sm := ShaderMaterial.new()
			sm.shader = HILT_SHADER
			sm.set_shader_parameter("clip_y", 99.0)
			if src != null:
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("albedo_color", src.albedo_color)
				sm.set_shader_parameter("normal_tex", src.normal_texture)
				sm.set_shader_parameter("use_normal", src.normal_enabled and src.normal_texture != null)
				sm.set_shader_parameter("orm_tex", src.roughness_texture)
				sm.set_shader_parameter("roughness", src.roughness)
				sm.set_shader_parameter("metallic", src.metallic)
			_r5_hand_sm.append(sm)
			_r5_hand_mi.append(m)


## 收刀＋自由＋著地時的 LMB → R5 拔刀斬；其他情況照父類（拔刀中排隊、已拔刀連段…）。
func _queue_draw_attack(kind: String) -> bool:
	if r5_enabled and kind == "light" and sword_state == SwordState.SHEATHED \
			and action_state == ActionState.FREE and is_on_floor() and _r5_n > 0:
		_r5_start()
		return true
	return super._queue_draw_attack(kind)


func _r5_start() -> void:
	action_state = ActionState.ATTACKING
	_attack_layer = "full"
	_active_attack_name = R5_ANIM
	active_form = 0
	combo_stage = 0
	_combo_queued_inputs = 0
	combo_input_buffered = false
	_action_real = r5_quickdraw_resource.length / r5_speed
	_action_elapsed = 0.0
	_r5_active = true
	_r5_tail = false
	_r5_trail_on = false
	_r5_saved_move = attack_move_factor_heavy
	attack_move_factor_heavy = r5_move_factor
	if _r5_sheath:
		_r5_sway_gain = float(_r5_sheath.get("sway_gain"))
		_r5_sheath.set("sway_gain", 0.0)
	for i in _r5_hand_mi.size():
		_r5_hand_mi[i].material_override = _r5_hand_sm[i]
	_hit_targets_this_swing.clear()
	if _hitbox != null:
		_hitbox.monitoring = false
	_fire_full("r5_qd", r5_speed)
	_r5_apply(0.0)


func _physics_process(delta):
	super._physics_process(delta)
	if _r5_active:
		_r5_update()


func _r5_update() -> void:
	if action_state != ActionState.ATTACKING or _active_attack_name != R5_ANIM:
		_r5_end()
		return
	var fr := _action_elapsed * r5_speed * _r5_fps
	_r5_apply(fr)
	var fi := int(fr)
	# 命中窗口（clip 格數）
	var hit_on := fi >= _r5_hit[0] and fi <= _r5_hit[1]
	if _hitbox != null:
		_hitbox.monitoring = hit_on
	if hit_on and not _r5_trail_on and _sword_trail != null:
		_r5_trail_on = true
		_sword_trail.reset_form()
		_sword_trail.start_trail()
		_character_audio.play_heavy_swing()
	elif not hit_on and _r5_trail_on and fi > _r5_hit[1] + 6 and _sword_trail != null:
		_sword_trail.stop_trail()
	# 殘心後的移動輸入：剩下的納刀改走 upper 層、腿交回 locomotion
	if not _r5_tail and fi >= r5_cancel_frame and _attack_layer == "full" and _read_input_dir().length_squared() > 0.0:
		var pick := -1
		for t in _r5_tails:
			if t <= fi:
				pick = t
		if pick >= 0:
			_r5_tail = true
			_attack_layer = "upper"
			attack_move_factor_heavy = _r5_saved_move
			_action_elapsed = float(pick) / (_r5_fps * r5_speed)
			_upper_finish_fade = 0.16
			_fire_upper("r5_tail_%d" % pick, r5_speed)
			_fade_full()


## 依 clip 時間套用：手上刀／鞘中刀可見性、刀身露出長度、左手控鞘的鞘 offset。
func _r5_apply(fr: float) -> void:
	if _r5_n <= 0:
		return
	var f0 := clampi(int(floor(fr)), 0, _r5_n - 1)
	var f1 := mini(f0 + 1, _r5_n - 1)
	var u := clampf(fr - float(f0), 0.0, 1.0)
	var vis := _r5_vis[f0] == 1
	if _sword_hand:
		_sword_hand.visible = vis
	if _sword_sheathed:
		_sword_sheathed.visible = not vis
	if _tree != null:
		_tree.set("parameters/grip/blend_amount", 0.0)   # 手指由 R5 clip 自己握
	var clip := lerpf(_r5_clip[f0], _r5_clip[f1], u) if vis else 99.0
	for sm in _r5_hand_sm:
		sm.set_shader_parameter("clip_y", clip)
	var T := _r5_offset(f0).interpolate_with(_r5_offset(f1), u)
	if _r5_sheath:
		_r5_sheath.set("_rest", T * _r5_sheath_rest)
	if _sword_sheathed:
		_sword_sheathed.set_meta("sheath_rest", T * _r5_ss_rest)


func _r5_offset(f: int) -> Transform3D:
	var o := f * 12
	if o + 11 >= _r5_saya.size():
		return Transform3D.IDENTITY
	var s := _r5_saya
	return Transform3D(Basis(Vector3(s[o], s[o + 1], s[o + 2]), Vector3(s[o + 3], s[o + 4], s[o + 5]), Vector3(s[o + 6], s[o + 7], s[o + 8])),
		Vector3(s[o + 9], s[o + 10], s[o + 11]))


func _r5_end() -> void:
	_r5_active = false
	_r5_tail = false
	attack_move_factor_heavy = _r5_saved_move
	if _r5_sheath:
		_r5_sheath.set("_rest", _r5_sheath_rest)
		_r5_sheath.set("sway_gain", _r5_sway_gain)
	if _sword_sheathed:
		_sword_sheathed.set_meta("sheath_rest", _r5_ss_rest)
	for mi in _r5_hand_mi:
		mi.material_override = null
	if _hitbox != null:
		_hitbox.monitoring = false
	# clip 結束時刀已入鞘：狀態一直是 SHEATHED，交回父類的可見性規則
	_apply_sword_visibility()
