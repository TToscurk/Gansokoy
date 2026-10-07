extends Node3D
## 人間之里 NPC の見た目ルート（P10 R3a Prototype）。
## 子に部位メッシュ入りの glb を 1 つ持つ（骨格は SkeletonProfileHumanoid へ retarget 済み＝GeneralSkeleton）。
## 動作は共通 AnimationLibrary（同じ GeneralSkeleton なら別の NPC でも同じ clip を再生できる）。
## 挙動（schedule・會話・群衆）はここに入れない。

const LIB := {
	&"idle": "res://characters/npc/_shared/anim/mixamo/idle_neutral_a030_grounded.res",   # Mixamo Neutral Idle（arm-space 0.30）
	&"walk": "res://characters/npc/_shared/anim/mixamo/walk_standard_a030_grounded.res",   # Mixamo Standard Walk（in place、arm-space 0.30）
}

@export var animation: StringName = &"idle"
## 角色ごとの clip（空なら LIB の既定＝chonin_m01 用）。P10 NPC Asset Library の各 NPC は自分の体形・服で選んだ arm-space の clip を指す。
@export_file("*.res") var idle_clip := ""
@export_file("*.res") var walk_clip := ""
@export var speed_scale := 1.0
## 開始位置（秒）。負なら clip 内のランダム位相（並んだ NPC が同期しないように）。
@export var start_time := -1.0
## true＝その位置で止める（審圖・静止画用）。
@export var frozen := false

var player: AnimationPlayer


func _ready() -> void:
	var model := get_child(0) as Node3D
	player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		player = AnimationPlayer.new()
		player.name = "AnimationPlayer"
		model.add_child(player)
		# %GeneralSkeleton は glb 内の owner（Model）から引く：root は Model 所有のノード（Armature）にする
		player.root_node = NodePath("../Armature")
	var lib := AnimationLibrary.new()
	var paths := {&"idle": idle_clip if idle_clip != "" else LIB[&"idle"], &"walk": walk_clip if walk_clip != "" else LIB[&"walk"]}
	for k: StringName in paths:
		lib.add_animation(k, load(paths[k]))
	if player.has_animation_library(&""):
		player.remove_animation_library(&"")
	player.add_animation_library(&"", lib)
	play_clip(animation, start_time)


func play_clip(clip: StringName, at := -1.0) -> void:
	if player == null or not player.has_animation(clip):
		push_warning("[NPC] %s：clip %s が無い" % [name, clip])
		return
	animation = clip
	player.play(clip)
	var length := player.current_animation_length
	player.seek(randf() * length if at < 0.0 else fmod(at, length), true)
	player.speed_scale = 0.0 if frozen else speed_scale
