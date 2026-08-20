extends CharacterBody3D

@export var speed := 4.0
@export var run_speed := 7.0
@export var gravity := 20.0
@export var turn_speed := 12.0        # 視覺模型轉向速度（lerp 權重）
@export var blend_time := 0.2         # Idle ↔ Walking ↔ Running 交叉淡入秒數

@export var walk_anim := "Armature|Armature|walking_man|baselayer"
@export var idle_anim := "Armature|Armature|Idle_11|baselayer"
@export var run_anim := "Armature|Armature|running|baselayer"
## 含 Idle / Running 動畫的 FBX（同一角色、同一骨架）。啟動時只抽出它們的 Animation，
## 合併進現有 AnimationPlayer；不會實例化第二隻角色到場景裡。
@export var idle_source: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Idle_11_withSkin.fbx")
@export var run_source: PackedScene = preload("res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Running_withSkin.fbx")

# ---------------------------------------------------------------------------
# 刀：兩個 socket、兩個刀實例（同一 GLB），只切 visible、不 reparent。
#   SheathSocket (Hips)      Sword_Sheathed  左腰居合佩刀（平常 / Idle / Walk / Run）
#   HandSocket   (RightHand) Sword_Hand      右手持刀（拔刀後）
#
# 狀態：SHEATHED --Q--> DRAWING (draw anim) --> DRAWN（刀留在右手，不自動收回）
# DRAWING 期間依動畫進度 t（0~1）切 socket：
#   [0, t_unsheathe)  Sword_Sheathed 可見、Sword_Hand 隱藏
#   [t_unsheathe, 1]  Sword_Sheathed 隱藏、Sword_Hand 可見（刀離開刀鞘）
# 收刀流程尚未實作（DRAWN 再按 Q 目前不動作）。
# ---------------------------------------------------------------------------
enum SwordState { SHEATHED, DRAWING, DRAWN }

@export_group("Sword Draw")
@export var draw_key := KEY_Q
## 右手從左腰拔刀的動畫名稱（留空 = 沒有 → 按 Q 只警告，不做假過場）。
@export var draw_anim := "Draw_Sword"
## 裁切好的拔刀 Animation 資源（由 build_draw_sword.gd 從 Meshy 拔刀 FBX 產生：
## 只保留「站姿 → 握柄 → 拔刀 → 完全拔出」0~1.0 s，收刀部分已裁掉，LOOP_NONE）。
@export var draw_anim_resource: Animation = preload("res://yoriichi_draw_sword.res")
## 或改用含拔刀動畫的同骨架 FBX（track 路徑需為 Armature/Skeleton3D:<bone>）；啟動時合併。
@export var draw_source: PackedScene
## 拔刀動畫進度（0~1）中「刀離開刀鞘」的時間點。Draw_Sword：刀鍔在 0.63~0.67 s 離鞘 → 0.65。
@export_range(0.0, 1.0) var t_unsheathe := 0.65
## DRAWN 狀態的站立動畫（Combat Idle）。留空 = 沿用 idle_anim。
@export var drawn_idle_anim := ""
@export var drawn_idle_source: PackedScene
## DRAWN 狀態是否允許 WASD 移動（移動時沿用 walk/run 動畫）。
@export var can_move_when_drawn := true

var sword_state: SwordState = SwordState.SHEATHED
var _draw_t := 0.0
var _draw_len := 0.0

var _anim: AnimationPlayer
var _visual: Node3D                   # FBX 視覺根節點（只旋轉這個，不動碰撞膠囊）
var _current := ""
var _sword_hand: Node3D
var _sword_sheathed: Node3D

func _ready():
	var aps := find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		push_warning("yoriichi_character: no AnimationPlayer found in FBX")
		return
	_anim = aps[0]
	_visual = _anim.get_parent()
	_merge_animations_from(idle_source)
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

## 把另一個同骨架 FBX 的 AnimationPlayer 內的動畫複製到本角色的 AnimationPlayer。
## track 路徑同為 Armature/Skeleton3D:<bone>，可直接共用。
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

# ---------------------------------------------------------------------------
# 移動 / 基本動畫
# ---------------------------------------------------------------------------
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
		# 模型正面朝 +Z，所以朝 input_dir 的 yaw = atan2(x, z)
		var target_yaw := atan2(input_dir.x, input_dir.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, clamp(turn_speed * delta, 0.0, 1.0))

	if _anim == null:
		return
	if sword_state == SwordState.DRAWING:
		_update_drawing()
	else:
		var running := moving and Input.is_key_pressed(KEY_SHIFT)
		_play(run_anim if running else (walk_anim if moving else _idle_for_state()))

# ---------------------------------------------------------------------------
# 拔刀狀態機
# ---------------------------------------------------------------------------
func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == draw_key:
		request_draw()

## Q：SHEATHED → DRAWING → DRAWN。DRAWING / DRAWN 時忽略（收刀尚未實作）。
func request_draw():
	if sword_state != SwordState.SHEATHED:
		return
	if draw_anim == "" or not _anim.has_animation(draw_anim):
		push_warning("yoriichi_character: no draw animation assigned (draw_anim / draw_source); staying SHEATHED")
		return
	_draw_len = _anim.get_animation(draw_anim).length
	_draw_t = 0.0
	sword_state = SwordState.DRAWING
	_apply_sword_visibility()          # 起點：刀仍在左腰
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
	_current = ""                      # 強制重新 blend 到 (combat) idle
	_play(_idle_for_state())

## 依狀態（與拔刀進度）決定哪一把刀可見。永遠恰好一把可見。
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
