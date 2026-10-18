extends Node
## 慧音 袴骨鏈（24 根 Hakama_*：前／前左／左／後左／後／後右／右／前右 × 3 節）的引擎端彈簧。
## 放在 keine.tscn 裡、與 Model 同層；_ready 時在 GeneralSkeleton 底下建立 SpringBoneSimulator3D，
## 碰撞膠囊掛在 simulator 的子節點（不是子節點就無效）。前／後兩條根接 Hips，左右各三條接大腿骨。
## 碰撞：兩腰關節之間一條橫膠囊、大腿、小腿。大腿半徑刻意比身體網格大（坐下時前片才會蓋在大腿上，
## 不會從兩腿之間掉下去露出胯部）。半徑以公尺計，資產已烘成 1.70 m（場景縮放必須保持 1.0）。
## 身體網格實測（keine_springs.json，85 百分位）：大腿 0.080–0.082、小腿 0.062–0.066、骨盆 0.089。

const DATA := "res://characters/keine/keine_springs.json"

@export var springs_enabled := true:
	set(v):
		springs_enabled = v
		if _sim:
			_sim.active = v
## 參數掃描（sweep_keine_hakama_springs.gd，idle 4 秒／走路 2 秒，彈簧開 vs 關的末端位移）：
## 重力是站著下垂的主因（碰撞關掉結果相同）。剛性 2／重力 0.6 → 站著下垂到 15 cm；剛性 4／重力 0.15 → 站著 ≤3 cm、走路平均 10 cm（最大 26 cm）。
## 要更多擺動就降剛性，但站著會開始下垂；剛性 8／重力 0.2 → 走路平均 6 cm。
## 前、後兩條（接 Hips）
@export var center_stiffness := 4.0
@export var center_drag := 0.8
@export var center_gravity := 0.15
## 左右六條（接大腿）
@export var side_stiffness := 4.0
@export var side_drag := 0.8
@export var side_gravity := 0.15
## 袴骨關節碰撞半徑
@export var joint_radius := 0.025
## 碰撞膠囊半徑（公尺）
@export var hip_radius := 0.10
@export var thigh_radius := 0.105
@export var shin_radius := 0.075

## 坐姿 clip（加入 AnimationPlayer 為 "sit"，並疊上 Blender 的坐姿垂放 Hakama_SitDrape_90）
@export_file("*.res") var sit_clip := "res://animations/npc_activity_p10/setomono_f01/sitting_breathing_a030_grounded.res"
## 坐姿垂放強度：0＝袴骨維持靜止角度只靠彈簧，1＝Blender 手調垂放。彈簧以此為目標再加擺動。
@export_range(0.0, 1.0) var sit_drape := 1.0:
	set(v):
		sit_drape = v
		if skeleton:
			rebuild_sit()

var skeleton: Skeleton3D
var _sim: SpringBoneSimulator3D
var _data: Dictionary


func _ready() -> void:
	skeleton = get_parent().find_child("GeneralSkeleton", true, false) as Skeleton3D
	if skeleton == null:
		push_error("KeineHakamaSprings: 找不到 GeneralSkeleton")
		return
	_data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	_build()
	_sim.reset.call_deferred()
	rebuild_sit.call_deferred()   # npc_visual 的 _ready（父節點，較晚）會換掉動作庫，所以延後加


## 重建 "sit"：坐姿 clip 複本＋24 根袴骨的垂放旋轉（骨本地 delta；Blender 與 Godot 的袴骨本地軸實測差 0.04°）。
func rebuild_sit() -> void:
	var player := get_parent().find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null or sit_clip == "" or not player.has_animation_library(&""):
		return
	var a := (load(sit_clip) as Animation).duplicate(true) as Animation
	for c in _data.chains:
		for k in 3:
			var bn: String = c.bones[k]
			var q: Array = c.sit_drape_wxyz[k]
			var d := Quaternion.IDENTITY.slerp(Quaternion(q[1], q[2], q[3], q[0]).normalized(), sit_drape)
			var t := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(t, NodePath("%GeneralSkeleton:" + bn))
			var r := skeleton.get_bone_rest(skeleton.find_bone(bn)).basis.get_rotation_quaternion() * d
			a.rotation_track_insert_key(t, 0.0, r)
			a.rotation_track_insert_key(t, a.length, r)
	var lib := player.get_animation_library(&"")
	if lib.has_animation(&"sit"):
		lib.remove_animation(&"sit")
	lib.add_animation(&"sit", a)
	# RESET：讓沒有袴軌道的 clip（idle／walk）把袴骨放回靜止角度；否則坐完再走，垂放會一直留著（實測 173°）。
	if not lib.has_animation(&"RESET"):
		var rs := Animation.new()
		rs.length = 0.001
		for c in _data.chains:
			for bn in c.bones:
				var t := rs.add_track(Animation.TYPE_ROTATION_3D)
				rs.track_set_path(t, NodePath("%GeneralSkeleton:" + str(bn)))
				rs.rotation_track_insert_key(t, 0.0, skeleton.get_bone_rest(skeleton.find_bone(bn)).basis.get_rotation_quaternion())
		lib.add_animation(&"RESET", rs)
	player.deterministic = true
	if str(get_parent().get("animation")) == "sit":
		get_parent().call("play_clip", &"sit", 0.0)


## 膠囊：在骨 bone 的靜止空間裡，從 a 到 b（皆為骨架空間靜止座標）。
func _capsule(nm: String, bone: String, a: Vector3, b: Vector3, r: float) -> SpringBoneCollisionCapsule3D:
	var cap := SpringBoneCollisionCapsule3D.new()
	cap.name = "COL_" + nm
	var inv := skeleton.get_bone_global_rest(skeleton.find_bone(bone)).affine_inverse()
	var la := inv * a
	var lb := inv * b
	cap.radius = r
	cap.height = la.distance_to(lb) + 2.0 * r
	cap.position_offset = (la + lb) * 0.5
	cap.rotation_offset = Quaternion(Vector3.UP, (lb - la).normalized())
	_sim.add_child(cap)
	cap.bone_name = bone
	return cap


func _rest(bone: String) -> Vector3:
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin


func _build() -> void:
	_sim = SpringBoneSimulator3D.new()
	_sim.name = "Spring_Hakama"
	skeleton.add_child(_sim)
	var caps: Array[Node] = []
	caps.append(_capsule("Hips", "Hips", _rest("LeftUpperLeg"), _rest("RightUpperLeg"), hip_radius))
	for s in ["Left", "Right"]:
		caps.append(_capsule(s + "UpperLeg", s + "UpperLeg", _rest(s + "UpperLeg"), _rest(s + "LowerLeg"), thigh_radius))
		caps.append(_capsule(s + "LowerLeg", s + "LowerLeg", _rest(s + "LowerLeg"), _rest(s + "Foot"), shin_radius))
	var chains: Array = _data.chains
	_sim.setting_count = chains.size()
	for i in chains.size():
		var c: Dictionary = chains[i]
		var center := str(c.dir) in ["F", "B"]
		_sim.set_root_bone_name(i, c.bones[0])
		_sim.set_end_bone_name(i, c.bones[2])
		_sim.set_extend_end_bone(i, true)
		_sim.set_end_bone_direction(i, SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
		_sim.set_end_bone_length(i, float(c.lengths[2]))
		_sim.set_radius(i, joint_radius)
		_sim.set_stiffness(i, center_stiffness if center else side_stiffness)
		_sim.set_drag(i, center_drag if center else side_drag)
		_sim.set_gravity(i, center_gravity if center else side_gravity)
		_sim.set_enable_all_child_collisions(i, false)
		_sim.set_collision_count(i, caps.size())
		for k in caps.size():
			_sim.set_collision_path(i, k, NodePath(caps[k].name))
	_sim.active = springs_enabled
