extends "res://characters/npc/npc_visual.gd"
## 慧音專用的見た目ルート（共用 npc_visual.gd を継承、共用ファイルは変更しない）。
##  - 動作切替を 0.35 s のクロスフェードにする（共用版は即切替）。
##  - 立ち止まっている間（animation == idle）、主 idle（Female Idle）を基本に、時々「重心移動」「考える」を挟む。
##    animation プロパティは &"idle" のまま（npc_population_actor.gd の _anim 判定を変えない）。
## 選定：JEV 文字候補選別＋慧音骨格上の実測（hand_motion／pelvis_yaw）＋審圖。Thinking は常用せず時々のみ（顔まわりの髪と重なる）。

@export_file("*.res") var idle_shift_clip := ""
@export_file("*.res") var idle_think_clip := ""
@export var blend_time := 0.25
@export var walk_start := 0.5   # walk 起步相位（秒）
@export var variant_blend := 0.6
@export var main_hold_min := 3.0     # 主 idle を続ける秒数（下限〜上限でランダム）
@export var main_hold_max := 6.0
@export var shift_hold_min := 6.0
@export var shift_hold_max := 10.0
@export_range(0.0, 1.0) var think_chance := 0.3   # 変化を挟むときに「考える」を選ぶ確率（残りは重心移動）

var _rng := RandomNumberGenerator.new()
var _in_idle := false
var _cur_variant: StringName = &"idle"
var _left := 0.0
var _last_variant: StringName = &""


func _ready() -> void:
	super._ready()
	_rng.randomize()
	var lib := player.get_animation_library(&"")
	if idle_shift_clip != "":
		lib.add_animation(&"idle_shift", load(idle_shift_clip))
	if idle_think_clip != "":
		var a := (load(idle_think_clip) as Animation).duplicate() as Animation
		a.loop_mode = Animation.LOOP_NONE
		lib.add_animation(&"idle_think", a)


func play_clip(clip: StringName, at := -1.0) -> void:
	if player == null or not player.has_animation(clip):
		push_warning("[NPC] %s：clip %s が無い" % [name, clip])
		return
	var first := player.current_animation == ""
	animation = clip
	player.play(clip, -1.0 if first else blend_time)
	var length := player.current_animation_length
	# 起步：walk 從接觸期（0 s）開始；隨機相位會在 idle→walk 混合時讓抬起的腳往下掉（實測腳尖低 3.7 cm）
	if clip == &"walk" and at < 0.0:
		at = walk_start
	player.seek(_rng.randf() * length if at < 0.0 else fmod(at, length), true)
	player.speed_scale = 0.0 if frozen else speed_scale
	_in_idle = clip == &"idle"
	_cur_variant = &"idle"
	_left = _rng.randf_range(main_hold_min, main_hold_max)


func _process(dt: float) -> void:
	if not _in_idle or frozen or player == null:
		return
	_left -= dt
	if _left > 0.0:
		return
	if _cur_variant != &"idle":
		_switch(&"idle", _rng.randf_range(main_hold_min, main_hold_max))
		return
	var want: StringName = &"idle_think" if (_rng.randf() < think_chance and _last_variant != &"idle_think") else &"idle_shift"
	if not player.has_animation(want):
		_left = _rng.randf_range(main_hold_min, main_hold_max)
		return
	var hold := _rng.randf_range(shift_hold_min, shift_hold_max)
	if want == &"idle_think":
		hold = player.get_animation(want).length - variant_blend
	_switch(want, hold)


func _switch(v: StringName, hold: float) -> void:
	_cur_variant = v
	_last_variant = v if v != &"idle" else _last_variant
	player.play(v, variant_blend)
	if v != &"idle_think":
		player.seek(_rng.randf() * player.current_animation_length, true)
	_left = hold
