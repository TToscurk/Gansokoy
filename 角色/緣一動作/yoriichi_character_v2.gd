extends CharacterBody3D
## Yoriichi Body v2（無羽織）角色基底。
## 與 v1 的差異：base FBX（yoriichi_body_v2.fbx）只含 mesh + skeleton（無動畫），
## Idle / Walk / Run 全部在啟動時從動畫 FBX 合併，因此多了 walk_source。
## 拔刀邏輯與 v1 相同：SHEATHED --Q--> DRAWING --> DRAWN，刀不自動收回。

@export var speed := 4.0
@export var run_speed := 7.0
@export var gravity := 20.0
@export var turn_speed := 12.0
@export var blend_time := 0.2

@export var walk_anim := "Armature|Armature|walking_man|baselayer"
@export var idle_anim := "Armature|Armature|Idle_11|baselayer"
@export var run_anim := "Armature|Armature|running|baselayer"

@export var idle_source: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Idle_11_withSkin.fbx")
@export var walk_source: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Walking_withSkin.fbx")
@export var run_source: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Running_withSkin.fbx")

enum SwordState { SHEATHED, DRAWING, DRAWN }

@export_group("Sword Draw")
@export var draw_key := KEY_Q
@export var draw_anim := "Draw_Sword"
@export var draw_anim_resource: Animation = preload("res://yoriichi_draw_sword.res")
@export var draw_source: PackedScene
@export_range(0.0, 1.0) var t_unsheathe := 0.65
@export var drawn_idle_anim := ""
@export var drawn_idle_source: PackedScene
@export var can_move_when_drawn := true

var sword_state: SwordState = SwordState.SHEATHED
var _draw_t := 0.0
var _draw_len := 0.0

var _anim: AnimationPlayer
var _visual: Node3D
var _current := ""
var _sword_hand: Node3D
var _sword_sheathed: Node3D

func _ready():
	var aps := find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		# v2 base FBX 可能沒有 AnimationPlayer：掛一個在 FBX 根節點上
		var visual_root := get_child(0) as Node3D
		_anim = AnimationPlayer.new()
		_anim.name = "AnimationPlayer"
		visual_root.add_child(_anim)
	else:
		_anim = aps[0]
	_visual = _anim.get_parent()
	_merge_animations_from(idle_source)
	_merge_animations_from(walk_source)
	_merge_animations_from(run_source)
	_merge_animations_from(draw_source)
	_merge_animations_from(drawn_idle_source)
	if draw_anim_resource and draw_anim != "" and not _anim.has_animation(draw_anim):
		_library().add_animation(draw_anim, draw_anim_resource)
	for n in [walk_anim, idle_anim, run_anim, drawn_idle_anim]:
		if n != "" and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if draw_anim != "" and _anim.has_animation(draw_anim):
		_anim.get_animation(draw_anim).loop_mode = Animation.LOOP_NONE
	_anim.animation_finished.connect(_on_animation_finished)
	_sword_hand = _find_first("Sword_Hand")
	_sword_sheathed = _find_first("Sword_Sheathed")
	sword_state = SwordState.SHEATHED
	_apply_sword_visibility()
	_play(idle_anim)

func _find_first(n: String) -> Node3D:
	var r := find_children(n, "", true, false)
	return r[0] if r.size() > 0 else null

func _library() -> AnimationLibrary:
	var lib_name: StringName = _anim.get_animation_library_list()[0] if _anim.get_animation_library_list().size() > 0 else &""
	if not _anim.has_animation_library(lib_name):
		_anim.add_animation_library(lib_name, AnimationLibrary.new())
	return _anim.get_animation_library(lib_name)

func _merge_animations_from(source: PackedScene):
	if source == null:
		return
	var tmp := source.instantiate()
	var src_aps := tmp.find_children("*", "AnimationPlayer", true, false)
	if not src_aps.is_empty():
		var src: AnimationPlayer = src_aps[0]
		var lib := _library()
		for n in src.get_animation_list():
			if not lib.has_animation(n):
				lib.add_animation(n, src.get_animation(n).duplicate())
	tmp.free()

func _play(name: String, blend := blend_time):
	if _current == name or not _anim.has_animation(name):
		return
	_anim.play(name, blend)
	_current = name

func _idle_for_state() -> String:
	if sword_state == SwordState.DRAWN and drawn_idle_anim != "" and _anim.has_animation(drawn_idle_anim):
		return drawn_idle_anim
	return idle_anim

func _physics_process(delta):
	var input_dir = Vector3.ZERO
	var movement_allowed := sword_state != SwordState.DRAWING and (sword_state != SwordState.DRAWN or can_move_when_drawn)
	if movement_allowed:
		if Input.is_key_pressed(KEY_W):
			input_dir.z -= 1
		if Input.is_key_pressed(KEY_S):
			input_dir.z += 1
		if Input.is_key_pressed(KEY_A):
			input_dir.x -= 1
		if Input.is_key_pressed(KEY_D):
			input_dir.x += 1

	input_dir = input_dir.normalized()

	var cur_speed := run_speed if Input.is_key_pressed(KEY_SHIFT) else speed
	velocity.x = input_dir.x * cur_speed
	velocity.z = input_dir.z * cur_speed

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	move_and_slide()

	var moving := input_dir.length_squared() > 0.0
	if moving and _visual:
		var target_yaw := atan2(input_dir.x, input_dir.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))

	if _anim == null:
		return
	if sword_state == SwordState.DRAWING:
		_update_drawing()
	else:
		var running := moving and Input.is_key_pressed(KEY_SHIFT)
		_play(run_anim if running else (walk_anim if moving else _idle_for_state()))

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == draw_key:
		request_draw()

func request_draw():
	if sword_state != SwordState.SHEATHED:
		return
	if draw_anim == "" or not _anim.has_animation(draw_anim):
		push_warning("yoriichi_character_v2: no draw animation assigned; staying SHEATHED")
		return
	_draw_len = _anim.get_animation(draw_anim).length
	_draw_t = 0.0
	sword_state = SwordState.DRAWING
	_apply_sword_visibility()
	_play(draw_anim, blend_time)

func _update_drawing():
	if _anim.current_animation == _current and _draw_len > 0.0:
		_draw_t = clamp(_anim.current_animation_position / _draw_len, 0.0, 1.0)
	_apply_sword_visibility()

func _on_animation_finished(anim_name: StringName):
	if sword_state == SwordState.DRAWING and String(anim_name) == draw_anim:
		_draw_t = 1.0
		_finish_draw()

func _finish_draw():
	sword_state = SwordState.DRAWN
	_apply_sword_visibility()
	_current = ""
	_play(_idle_for_state())

func _apply_sword_visibility():
	var in_hand := false
	match sword_state:
		SwordState.SHEATHED:
			in_hand = false
		SwordState.DRAWING:
			in_hand = _draw_t >= t_unsheathe
		SwordState.DRAWN:
			in_hand = true
	if _sword_sheathed:
		_sword_sheathed.visible = not in_hand
	if _sword_hand:
		_sword_hand.visible = in_hand
