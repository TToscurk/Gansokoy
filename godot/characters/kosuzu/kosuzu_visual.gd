extends Node3D
## 小鈴的見た目ルート（與 npc_visual.gd 同介面：animation／play_clip／speed_scale／frozen），動作在 kosuzu.glb 內。
##   idle → idle_female、walk → walk_female（原地走）；站著時偶爾插一段 look_around／idle_happy／thinking。
## 袖子在子節點 Sleeves（kosuzu_sleeve_bones.gd：袖骨鏈＋SpringBoneSimulator3D；2026-10-21 起不再用 SoftBody，AnimationPlayer 照常自己推進）。

@export var animation: StringName = &"idle"
@export var speed_scale := 1.0
@export var start_time := -1.0
@export var frozen := false
@export var blend_time := 0.3
@export var variants: Array[StringName] = [&"look_around", &"idle_happy", &"thinking"]
@export var main_hold_min := 6.0
@export var main_hold_max := 12.0

const ALIAS := {&"idle": &"idle_female", &"walk": &"walk_female"}
const LOOP := [&"idle_female", &"idle_happy", &"walk_female", &"look_around", &"talk_funny", &"sit_chair_idle", &"thinking"]

var player: AnimationPlayer
var _rng := RandomNumberGenerator.new()
var _left := 0.0
var _variant := false


func _ready() -> void:
	_rng.randomize()
	player = $Model.find_children("*", "AnimationPlayer", true, false)[0]
	var lib := player.get_animation_library(&"")
	for n in lib.get_animation_list():
		lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR if n in LOOP else Animation.LOOP_NONE
	for a: StringName in ALIAS:
		if not lib.has_animation(a): lib.add_animation(a, lib.get_animation(ALIAS[a]))
	play_clip(animation, start_time)


func play_clip(clip: StringName, at := -1.0) -> void:
	if player == null or not player.has_animation(clip):
		push_warning("[Kosuzu] clip %s が無い" % clip); return
	var first := player.current_animation == ""
	animation = clip
	player.play(clip, -1.0 if first else blend_time)
	var length := player.current_animation_length
	player.seek(_rng.randf() * length if at < 0.0 else fmod(at, length), true)
	player.speed_scale = 0.0 if frozen else speed_scale
	_variant = false
	_left = _rng.randf_range(main_hold_min, main_hold_max)


func _process(dt: float) -> void:
	if animation != &"idle" or frozen or player == null or variants.is_empty(): return
	_left -= dt
	if _left > 0.0: return
	if _variant:
		player.play(&"idle", 0.6); _variant = false
		_left = _rng.randf_range(main_hold_min, main_hold_max)
		return
	var v: StringName = variants[_rng.randi() % variants.size()]
	if not player.has_animation(v): return
	player.play(v, 0.6); _variant = true
	_left = player.get_animation(v).length - 0.6
