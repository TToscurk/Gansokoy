class_name YoriichiV24Rig
extends Node3D
## 緣一 V2.4 衣髮骨架（149 骨：65 身體 + 袖 8 鏈／下擺 8 鏈／頭髮 5 鏈，各 3 節）。
## 掛在「含 yoriichi_v24.glb 的節點」上：載入後自動建立 SpringBoneSimulator3D 與身體碰撞膠囊、
## 設定 idle / walk 循環，並提供 play_motion()。不引用 Player / 相機 / 戰鬥。
##
## 袖子「盡量不穿進身體」：袖口外段（Cuff_* 8 條鏈）對身體碰撞膠囊做彈簧碰撞；軀幹膠囊加大 torso_collider_extra。
## 資產已烘成 1.7 m（場景縮放必須保持 1.0）。袖口鏈採高剛性＋低重力，且不與手臂膠囊碰撞，目的是「手臂始終在袖管內」。
## 實測（74 格走路、Arm-Space 0.78）：手臂頂點落在袖管外 左1%／右0%（最深 33 mm）；袖子穿進身體的頂點中位數 363 -> 193，
## 最深 76 mm 未改善。降低、不是消除。要更多袖子擺動就降低 sleeve_stiffness，但手臂會從袖管穿出。

const DIR := "res://characters/yoriichi/v24/"

@export var springs_enabled := true:
	set(v):
		springs_enabled = v
		for s in _sims:
			s.active = v
## 軀幹（Hips/Spine/Spine1/Spine2）碰撞膠囊半徑加量（公尺，模型 1.0 m 高時的尺度）。
@export var torso_collider_extra := 0.05
## 袖鏈關節碰撞半徑
@export var sleeve_joint_radius := 0.03
## 袖口鏈是否與前臂／手的碰撞膠囊碰撞。關閉才不會把袖口從手臂上推開（手臂穿出袖管）。
@export var sleeve_collide_arms := false
@export var sleeve_stiffness := 30.0
@export var sleeve_drag := 0.85
@export var sleeve_gravity := 0.05
@export var hem_stiffness := 1.8
@export var hem_drag := 0.8
@export var hem_gravity := 0.8
@export var hair_stiffness := 0.65
@export var hair_drag := 0.8
@export var hair_gravity := 0.45
@export var start_motion := "idle"
## 走路用哪支動作：walk_user = Mixamo「Walking.fbx」（使用者提供）；walk = 先前 Arm-Space 0.78 的 Mixamo 走路。
@export var walk_motion := "walk_user"

var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var _sims: Array[SpringBoneSimulator3D] = []
var _chains: Dictionary
var _colliders: Dictionary

func _ready() -> void:
	skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or anim_player == null:
		push_error("YoriichiV24Rig: 找不到 Skeleton3D / AnimationPlayer（請把 yoriichi_v24.glb 放在此節點下）")
		return
	_chains = JSON.parse_string(FileAccess.get_file_as_string(DIR + "chains.json"))
	_colliders = JSON.parse_string(FileAccess.get_file_as_string(DIR + "colliders.json"))
	_setup_animations()
	_setup_springs()
	play_motion(start_motion)

func play_motion(name_: String, blend := 0.2) -> void:
	if anim_player and anim_player.has_animation(name_):
		anim_player.play(name_, blend)

func _setup_animations() -> void:
	for n in anim_player.get_animation_list():
		var a := anim_player.get_animation(n)
		a.loop_mode = Animation.LOOP_LINEAR
		_trim_duplicate_last_frame(a)

## Mixamo 循環動作最後一格＝第一格，直接 loop 會停一拍；偵測到就截掉最後一格。
func _trim_duplicate_last_frame(a: Animation) -> void:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D: continue
		if not str(a.track_get_path(t)).ends_with("Hips"): continue
		var k := a.track_get_key_count(t)
		if k < 3: return
		var q0: Quaternion = a.track_get_key_value(t, 0)
		var q1: Quaternion = a.track_get_key_value(t, k - 1)
		if q0.angle_to(q1) < deg_to_rad(0.5):
			var last := a.track_get_key_time(t, k - 1)
			var prev := a.track_get_key_time(t, k - 2)
			a.length = last - (last - prev)
		return

func _make_collision(d: Dictionary, extra_torso: float) -> SpringBoneCollisionCapsule3D:
	var cap := SpringBoneCollisionCapsule3D.new()
	var extra := extra_torso if bool(d.get("torso", false)) else 0.0
	var r := float(d.radius_m)
	cap.radius = r + extra
	cap.mid_height = maxf(0.0, float(d.height_m) - 2.0 * r)
	cap.name = "COL_" + str(d.name)
	return cap

func _setup_springs() -> void:
	var bone_map: Dictionary = _chains.bone_map
	for kind in ["sleeve", "hem", "hair"]:
		var chosen: Array = []
		for c in _chains.chains:
			if c.kind == kind: chosen.append(c)
		if chosen.is_empty(): continue
		var sim := SpringBoneSimulator3D.new()
		sim.name = "Spring_" + kind
		skeleton.add_child(sim)
		sim.setting_count = chosen.size()
		sim.influence = 1.0
		var paths: Array[String] = []
		for d in _colliders.colliders:
			var nm := str(d.name)
			var is_leg := nm.contains("Leg")
			var is_arm := nm.contains("Arm") or nm.contains("Hand")
			var include := false
			if kind == "sleeve": include = not is_leg and (sleeve_collide_arms or not is_arm)
			elif kind == "hem": include = not is_arm and nm != "Head" and nm != "Neck"
			else: include = nm in ["Head", "Neck", "Spine2", "Spine1"]
			if not include: continue
			var cap := _make_collision(d, torso_collider_extra)
			sim.add_child(cap)
			cap.bone_name = bone_map[str(d.bone)]
			cap.position_offset = Vector3(float(d.offset_xz[0]), float(d.center_y), float(d.offset_xz[1]))
			paths.append(str(cap.name))
		for i in chosen.size():
			var c: Dictionary = chosen[i]
			sim.set_root_bone_name(i, c.bones_game[0])
			sim.set_end_bone_name(i, c.bones_game[2])
			sim.set_extend_end_bone(i, true)
			sim.set_end_bone_direction(i, SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
			sim.set_end_bone_length(i, float(c.end_length_m))
			match kind:
				"sleeve":
					sim.set_radius(i, sleeve_joint_radius)
					sim.set_stiffness(i, sleeve_stiffness); sim.set_drag(i, sleeve_drag); sim.set_gravity(i, sleeve_gravity)
				"hem":
					sim.set_radius(i, 0.004)
					sim.set_stiffness(i, hem_stiffness); sim.set_drag(i, hem_drag); sim.set_gravity(i, hem_gravity)
				_:
					sim.set_radius(i, 0.004)
					sim.set_stiffness(i, hair_stiffness); sim.set_drag(i, hair_drag); sim.set_gravity(i, hair_gravity)
			sim.set_enable_all_child_collisions(i, false)
			sim.set_collision_count(i, paths.size())
			for k in paths.size(): sim.set_collision_path(i, k, NodePath(paths[k]))
		sim.active = springs_enabled
		_sims.append(sim)
	for s in _sims: s.reset()

## 切換羽織顯示（除錯用）。
func set_haori_visible(v: bool) -> void:
	var m := find_child("羽織", true, false) as Node3D
	if m: m.visible = v
